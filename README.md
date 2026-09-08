# homelab-provisioning

Proxmox VE üzerinde **1 master + 2 worker RKE2 cluster'ı**. Terraform altyapıyı, Ansible konfigürasyonu yönetir; iki katman ayrı dizinlerde durur.

> 📝 **Makale:** [Proxmox'ta RKE2: Terraform + Ansible](https://medium.com/@ozanbozkurt/TODO-slug) — bu repo yazının çalışan hali.

**Katman ayrımı:**

| Katman | Araç | Sorumluluk |
| --- | --- | --- |
| Altyapı | Terraform | VM'in var olması, boyutu, IP'si, diski, `destroy`. `plan` ile önizleme. |
| Bootstrap | cloud-init | Sadece Ansible'ın SSH ile girebilmesi kadarı: kullanıcı, SSH key, `qemu-guest-agent`. |
| Konfigürasyon | Ansible | RKE2 (+ opsiyonel Cilium) kurulum/join/upgrade. |
| Bağlantı | Terraform → Ansible | Terraform inventory ve secret'ları üretir; tek doğruluk kaynağı topolojidir. |
| Cluster içi | GitOps | Ayrı repo — faz 2. Bu repo cluster'ın kendisini kurar, orada durur. |

Konfigürasyon cloud-init'te değil Ansible'da olduğu için **gün-2 değişiklikleri VM'i yeniden yaratmadan** uygulanır.

---

## Hızlı başlangıç

Ön koşulları karşıladığını varsayarak, sıfırdan çalışan cluster'a:

```bash
export TF_VAR_proxmox_api_token='USER@REALM!TOKENID=UUID'

cd terraform/environments/ozan-local
cp terraform.tfvars.example terraform.tfvars   # ssh_public_keys zorunlu
umask 077 && terraform init && terraform apply

cd ../../../ansible
ansible-galaxy collection install -r collections/requirements.yml -p .galaxy
ansible-galaxy role install -r roles/requirements.yml -p .galaxy/roles
ansible-playbook playbooks/site.yml

kubectl --kubeconfig ~/.kube/rke2-ozan-local.yaml get nodes
```

Adımların gerekçesi ve seçenekleri [Kullanım](#kullanım) bölümünde.

---

## Hedef Ortam

| | |
| --- | --- |
| Proxmox | `192.168.1.99`, node `ozan`, PVE 9.2.6 |
| Node kaynakları | 8 vCPU · ~15.5 GB RAM · 338 GB boş |
| Template | VM `100` (Ubuntu cloud-init, `base-100-disk-0`) |
| RKE2 | `v1.31.7+rke2r1` (`rke2_channel: stable`) |
| Storage | `local` → ISO + cloud-init snippet'leri · `ssd` → VM diskleri |

## Oluşturulan Altyapı

| VM | ID | IP | vCPU | RAM | Disk | Rol |
| --- | --- | --- | --- | --- | --- | --- |
| `rke2-master` | 210 | 192.168.1.210 | 2 | 4096 MB | 40 GB | RKE2 server (control plane) |
| `rke2-worker-1` | 211 | 192.168.1.211 | 2 | 4096 MB | 60 GB | RKE2 agent |
| `rke2-worker-2` | 212 | 192.168.1.212 | 2 | 4096 MB | 60 GB | RKE2 agent |

**Toplam:** 6 vCPU · 12288 MB RAM (2048 MB PVE'ye ayrıldı, 13808 MB bütçe) · 160 GB thin disk.

Worker'lar master'la aynı RAM'i alıyor çünkü iş yüklerinin tamamı **worker'larda** koşuyor: control plane `CriticalAddonsOnly=true:NoExecute` ile iş yüklerine kapalı. Disk de aynı sebeple 60 GB — kalıcı volume'lar `local-path` ile worker diskinde duruyor.

**Diski Terraform büyütür.** Boyutu `master_disk_gb` / `worker_disk_gb` belirler, kullanılabilir hale getirmeyi de Terraform'un ürettiği cloud-init yapar. Şablon VM'de `/` LVM üzerinde ve root LV diskin tamamını kullanmaz (`sda3` 18 GB, root LV 10 GB); bu haliyle 40/60 GB disk verilse bile `/` 10 GB kalır, kubelet `node.kubernetes.io/disk-pressure` taint'i basar ve paketli chart'ların helm job'ları schedule edilemez. cloud-init dört adımda diski sonuna kadar açar:

| Adım | Ne yapar |
| --- | --- |
| `growpart` modülü | `root_partition`'ı (`/dev/sda3`) diskin sonuna kadar büyütür |
| `pvresize` | LVM physical volume'ü yeni partition boyutuna genişletir |
| `lvextend -l +100%FREE` | root LV'yi volume group'taki tüm boş alanı alacak şekilde büyütür |
| `resize2fs` | ext4 dosya sistemini LV'ye yayar, mount'lu haldeyken |

Düzen `root_partition` / `root_vg` / `root_lv` değişkenleriyle değişir. `runcmd` yalnızca ilk boot'ta çalıştığı için zaten açık bir VM'e uygulamak VM'i yeniden yaratmayı gerektirir:

```bash
terraform apply -replace='module.rke2_master.proxmox_virtual_environment_vm.vm'
```

`terraform_data.resource_budget` precondition'ı, talep edilen RAM node bütçesini aşarsa `plan` aşamasında hata verir. Boyutları değiştirirken `node_total_memory_mb` / `node_reserved_memory_mb` değerlerini de gözden geçirin.

---

## Ön Koşullar

1. **Snippets içerik tipi açık olmalı** (cloud-init user-data yüklemesi için):

   ```bash
   ssh root@192.168.1.99 'pvesm set local --content iso,vztmpl,backup,import,snippets'
   ```

2. **SSH agent** yüklü bir key ile `root@192.168.1.99`'a erişebilmeli — bpg provider snippet'leri SSH ile yükler.
3. `ssh_public_keys` **zorunlu** — cloud-init'te password ile SSH kapalı, Ansible key ile bağlanır.
4. Template VM `100` cloud-init içermeli.

---

## Kullanım

### 1. Altyapı

```bash
cd terraform/environments/ozan-local
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars                       # token'ı buraya değil env'e koy
chmod 600 terraform.tfvars

export TF_VAR_proxmox_api_token='USER@REALM!TOKENID=UUID'

umask 077                                      # state 0600 doğsun
terraform init
terraform plan
terraform apply
```

Apply, `ansible/inventory/ozan-local/` altına `hosts.yml` ve `group_vars/all/secrets.yml` (rke2 token) dosyalarını yazar.

### 2. Konfigürasyon

```bash
cd ../../../ansible
ansible-galaxy collection install -r collections/requirements.yml -p .galaxy
ansible-galaxy role install -r roles/requirements.yml -p .galaxy/roles

ansible all -m ping
ansible-playbook playbooks/site.yml
```

### 3. Sonuç

```bash
kubectl --kubeconfig ~/.kube/rke2-ozan-local.yaml get nodes
```

kubeconfig'i `lablabs.rke2` rolü `rke2_download_kubeconf: true` ile otomatik indirir.

### 4. Faz 2 — GitOps

Cluster ayağa kalktıktan sonra cluster içine kurulacak her şey GitOps ile gelir; o katman ayrı bir repoda yaşar.

### Temizlik / yeniden kurulum

Cluster'ı VM'lere dokunmadan sıfırla (demoyu baştan çalıştırmak için):

```bash
ansible-playbook playbooks/k8s/rke2-reset.yml -e reset_confirmation=yes
ansible-playbook playbooks/site.yml
```

VM'leri de sil:

```bash
cd terraform/environments/ozan-local
terraform destroy
```

`destroy`, Terraform'un ürettiği `hosts.yml` ve `secrets.yml` dosyalarını da kaldırır.

### Ölçek değiştirme

```hcl
worker_count     = 3
worker_memory_mb = 3072
```

`terraform apply` sonrası `ansible-playbook playbooks/site.yml` yeni node'u cluster'a katar.

---

## CNI seçimi — cilium (varsayılan) / canal

Tek değişken belirliyor: `ansible/inventory/ozan-local/group_vars/all/main.yml`

```yaml
cluster_cni: cilium   # cilium | canal
```

Bu değer hem `rke2_cni`'yi hem `disable_kube_proxy`'yi sürüyor. `canal`'a alınırsa `rke2_cilium` rolünün **bütün** task'ları atlanır (`ok=0 changed=0`), CA üretilmez ve kube-proxy açık kalır.

### Cilium ne yapıyor

`rke2_cilium` rolü, RKE2'nin paketlediği Cilium chart'ının değerlerini bir `HelmChartConfig` ile geçersiz kılar. **Manifest, `rke2-server` ilk kez başlamadan `server/manifests/` altına konmalı** — bu yüzden rol `lablabs.rke2`'den önce çalışır. Yanlış sırada olursa Cilium varsayılanlarla kurulur ve `kubeProxyReplacement` hiç devreye girmez.

| Ayar | Değer | Neden |
|---|---|---|
| `kubeProxyReplacement` | `true` | kube-proxy tamamen kaldırılır (`disable_kube_proxy: true`); yönlendirme eBPF'te |
| `k8sServiceHost/Port` | `192.168.1.210:6443` | kube-proxy yokken Cilium API'ye Service VIP'i üzerinden ulaşamaz |
| `routingMode` | `native` + `autoDirectNodeRoutes` | Tüm node'lar aynı L2'de → tünel (VXLAN/Geneve) yükü yok |
| `ipv4NativeRoutingCIDR` | `10.42.0.0/15` | cluster (`10.42/16`) + service (`10.43/16`) aralığını birlikte kapsar |
| `l2announcements` | `true` | `CiliumLoadBalancerIPPool` ile LAN'da gerçek LoadBalancer IP'si — MetalLB gerekmez |
| Hubble | relay açık, UI kapalı | Akışlar `hubble observe` ile; metrikler `:9965`. UI RAM'e mal oluyor |
| `gatewayAPI` | `true` | Yönlendirme Gateway API ile; `rke2-ingress-nginx` kapatıldı |
| `localRedirectPolicy` | `true` | node-local DNS cache'in `CiliumLocalRedirectPolicy`'si buna bağlı |
| clustermesh | **kapalı** | Tek cluster var; `cilium_clustermesh_enabled: true` ile açılır |

`operator.tolerations` yazmak chart'ın varsayılanını (`- operator: Exists`) geçersiz kılar. Sadece `CriticalAddonsOnly` tolere edilirse `node.kubernetes.io/not-ready` dışarıda kalır ve kurulum tamamlanamaz: node NotReady olduğu için operator schedule edilemez, CRD'ler oluşmaz, agent `Waiting for CRDs` ile bekler, node NotReady kalır. Template'te bu yüzden `- operator: Exists` duruyor.

Doğrulama playbook'un sonunda otomatik: `cilium status --wait` ve `kube-proxy` DaemonSet'inin gerçekten yok olduğunu kontrol eden bir assert.

```bash
ssh ubuntu@192.168.1.210 sudo cilium status
kubectl -n kube-system get pods -l k8s-app=cilium
```

> **Dikkat:** `cilium_lb_ipam_range` varsayılanı `192.168.1.240-192.168.1.250`. Router'ının DHCP havuzuyla çakışmadığını doğrula, yoksa IP çakışması yaşarsın.

> **RAM:** Cilium agent + envoy + Hubble relay + clustermesh-apiserver, canal'a göre kayda değer ek yük getirir. 4 GB'lık worker'larda iş yükleriyle birlikte sıkışırsa önce `cilium_clustermesh_replicas: 0`.

### Clustermesh ve paylaşılan CA

Mesh'teki tüm cluster'lar **aynı CA'yı** kullanmak zorunda, yoksa apiserver'lar arası mTLS kurulmaz. CA, Ansible controller'ında bir kez üretilip `ansible/cilium-ca/ozan-local/` altında saklanır ve `tls.ca` ile Cilium'a verilir. `ca.key` private key'dir, `.gitignore` ile dışlanmıştır — **CA'yı repoya commit etme**.

> CA inventory dizininin dışında tutulur: Ansible, inventory dizinindeki her dosyayı inventory kaynağı sanıp parse etmeye çalışır ve PEM dosyalarında hata verir.

İkinci cluster'ı bağlarken:

- `cilium_cluster_id` her cluster'da **benzersiz** olmalı (bu cluster: `1`).
- Yeni cluster aynı `ansible/cilium-ca/` içeriğini kullanmalı.
- Her iki tarafın `cilium_clustermesh_clusters` listesine karşı cluster'ı ekle:
  ```yaml
  cilium_clustermesh_clusters:
    - name: other-cluster
      ips: ["10.0.0.10"]
      port: 32379
  ```
  Liste boş kaldığı sürece `config.enabled: false` olur.
- `tls.auto.method: cronJob` seçildi; `helm` sertifikaları yenilemez ve süre dolduğunda mesh sessizce kopar.

### Kapatılan RKE2 bileşenleri

`group_vars/rke2-cluster.yml` → `rke2_disable`:

| Bileşen | Neden kapalı |
| --- | --- |
| `rke2-ingress-nginx` | Yönlendirme Cilium Gateway API + Envoy ile. İki controller pod'u + admission webhook + certgen job'ları gider. |
| `rke2-snapshot-controller` + `-crd` | Volume snapshot yalnızca destekleyen bir CSI ile işe yarar; `local-path` desteklemiyor. |

Kasıtlı olarak **açık** bırakılanlar: `rke2-coredns` (cluster DNS), `rke2-metrics-server` (`kubectl top`, HPA — Cilium ikamesi yok), `cloud-controller-manager` (node lifecycle buna bağlı), `rke2-runtimeclasses` (tek seferlik job, runtime maliyeti sıfır), `cilium-envoy` (Gateway API ve L7 policy için zorunlu).

### node-local DNS cache

Her node'da bir CoreDNS instance'ı (`node_local_dns` rolü) — pod'lar DNS için node'dan çıkmaz, cache miss olmadıkça cluster CoreDNS'e gitmez.

kube-proxy kaldırıldığı için upstream `nodelocaldns`'in dayandığı iptables NOTRACK kuralları ve link-local IP kurulumu burada işlemez. Onun yerine Cilium'un `CiliumLocalRedirectPolicy`'si kullanılıyor: pod'lar CoreDNS ClusterIP'sine (`10.43.0.10`) sormaya devam eder, Cilium bu trafiği aynı node'daki cache pod'una çevirir.

Döngü tehlikesi ve çözümü: cache pod'u upstream'e sorarken aynı ClusterIP'yi kullanırsa trafik kendine döner. Bu yüzden `kube-dns-upstream` adında ikinci bir Service var (sabit ClusterIP `10.43.0.11`, aynı CoreDNS pod'larını seçer) — LocalRedirectPolicy onu yakalamıyor. Ek güvence: `skipRedirectFromBackend: true`.

```bash
kubectl -n kube-system get ds node-local-dns
kubectl -n kube-system get ciliumlocalredirectpolicy node-local-dns
# cache çalışıyor mu: aynı sorguyu iki kez sor, ikincisi node'dan çıkmamalı
kubectl run -it --rm dnstest --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default
```

Cache node'da yoksa (pod down) Cilium trafiği normal servise gönderir — DNS kesilmez.

---

## Secret'lar ve state

| Nerede | Ne var | Nasıl korunuyor |
| --- | --- | --- |
| `terraform.tfvars` | Proxmox API token (yazılırsa) | gitignored + `chmod 600`. **Tercih edilen: hiç yazma**, `export TF_VAR_proxmox_api_token=...` |
| `terraform.tfstate` | `rke2_token`, API token — **düz metin** | gitignored + `chmod 600`. Terraform state'i şifrelemez |
| Proxmox snippet datastore'u | cloud-init user-data | Password düz metin değil **SHA-512 hash** olarak yazılır (`vm_password_hash`) |
| `group_vars/all/secrets.yml` | `rke2_token` | Terraform `0600` ile yazar, gitignored |

- `vm_password_hash` verilmezse hesap kilitlenir; giriş yalnızca SSH key ile olur. Konsoldan da girmek istiyorsan: `mkpasswd -m sha-512`.
- Terraform state'i her yazışında dosya iznini umask'tan alır. `0600` kalsın istiyorsan komutları `umask 077` ile çalıştır, yoksa apply sonrası tekrar `chmod 600 terraform.tfstate*`.
- **Uzak backend yok, bilinçli:** bu katman cluster'ı kuran katman, cluster'ın içindeki bir store'a (MinIO vb.) state yazamaz — tavuk-yumurta. Cluster dışı bir S3 uyumlu store çıkarsa `providers.tf` içine bir `backend "s3"` bloğu ekle. O zamana kadar state dosyasını yedekle: kaybı = elle temizlenecek 3 orphan VM.

---

## Dosya Yapısı

```text
.
├── .gitignore                         # state, tfvars, secret, CA, üretilen dosyalar
├── .pre-commit-config.yaml            # fmt + validate + ansible-lint + secret taraması
├── .ansible-lint                      # .galaxy hariç, production profili
├── terraform/
│   ├── environments/ozan-local/      # terraform apply bu dizinde çalışır
│   │   ├── main.tf                   # VM'ler, cloud-init snippet'leri, inventory/secret üretimi
│   │   ├── variables.tf              # Auth, ağ, boyutlar, kaynak bütçesi
│   │   ├── providers.tf              # bpg/proxmox + random + local
│   │   ├── outputs.tf                # IP'ler, sonraki adım komutu
│   │   ├── terraform.tfvars          # gitignored
│   │   ├── terraform.tfvars.example
│   │   ├── cloud-init/
│   │   │   ├── base.yaml.tftpl       # minimal bootstrap
│   │   │   └── validate.sh           # template'leri render edip YAML doğrular
│   │   └── templates/
│   │       └── ansible-inventory.yml.tftpl
│   └── modules/vm_qemu/              # tek VM modülü, 3 VM de bunu çağırır
└── ansible/
    ├── ansible.cfg
    ├── collections/requirements.yml  # community.general, community.crypto
    ├── roles/
    │   ├── requirements.yml          # lablabs.rke2
    │   ├── rke2_cilium/              # Cilium HelmChartConfig + LB-IPAM + Gateway API CRD + verify
    │   └── node_local_dns/           # node-local DNS cache + CiliumLocalRedirectPolicy
    ├── inventory/ozan-local/
    │   ├── hosts.yml                 # Terraform üretir, gitignored
    │   └── group_vars/
    │       ├── all/main.yml          # cluster_cni
    │       ├── all/secrets.yml       # Terraform üretir (rke2_token), gitignored
    │       └── rke2-cluster.yml
    └── playbooks/
        ├── site.yml
        └── k8s/
            ├── rke2-deploy.yml
            └── rke2-reset.yml         # cluster'ı kaldırır, VM'ler kalır
```

---

## Commit öncesi kontrol

```bash
brew install pre-commit
pre-commit install
pre-commit run --all-files
```

`terraform fmt` + `terraform validate` + `ansible-lint` + private key/large file taraması. `terraform validate`, silinmiş bir kaynağa bakan kırık `output` gibi hataları commit'ten önce yakalar.

`ansible-lint` playbook'ları syntax-check ettiği için `lablabs.rke2` rolünün kurulu olmasını bekler — galaxy bağımlılıklarını ([Kullanım → 2. Konfigürasyon](#2-konfigürasyon)) en az bir kez kurmadan hook kırmızı yanar.

Proxmox'a hiç bağlanmadan template'leri doğrulamak için:

```bash
terraform/environments/ozan-local/cloud-init/validate.sh
```

cloud-init ve inventory template'lerini render edip YAML olarak assert eder; pyyaml gerekir, sistem python'unda yoksa script `uv` ile geçici ortam kurar.
