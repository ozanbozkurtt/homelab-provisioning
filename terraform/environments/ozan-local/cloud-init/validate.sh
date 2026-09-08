#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

py=(python3)
if ! python3 -c 'import yaml' 2>/dev/null; then
  if command -v uv >/dev/null 2>&1; then
    py=(uv run --quiet --with pyyaml python3)
  else
    echo "pyyaml gerekli: 'pip install pyyaml' ya da 'brew install uv'" >&2
    exit 1
  fi
fi

render() {
  terraform console <<<"$2" | sed -n '/^<<EOT$/,/^EOT$/p' | sed '1d;$d' > "$tmp/$1.yaml"
  [[ -s "$tmp/$1.yaml" ]] || { echo "render '$1' boş döndü — terraform console hatası:" >&2; terraform console <<<"$2" >&2; exit 1; }
}

render cloud-init 'templatefile("cloud-init/base.yaml.tftpl", {hostname="rke2-master", username="ubuntu", password_hash="$6$salt$hash", ssh_public_keys=jsonencode(["ssh-ed25519 AAAA t"]), root_partition="/dev/sda3", root_vg="ubuntu-vg", root_lv="ubuntu-lv"})'
render cloud-init-nopw 'templatefile("cloud-init/base.yaml.tftpl", {hostname="rke2-master", username="ubuntu", password_hash=null, ssh_public_keys=jsonencode(["ssh-ed25519 AAAA t"]), root_partition="/dev/sda3", root_vg="ubuntu-vg", root_lv="ubuntu-lv"})'

render inventory 'templatefile("templates/ansible-inventory.yml.tftpl", {username="ubuntu", master_name="rke2-master", master_ip="192.168.1.210", workers={"rke2-worker-1"="192.168.1.211","rke2-worker-2"="192.168.1.212"}})'

"${py[@]}" - "$tmp" <<'PY'
import pathlib, sys, yaml

tmp = pathlib.Path(sys.argv[1])

ci = (tmp / "cloud-init.yaml").read_text()
assert ci.startswith("#cloud-config"), "cloud-init: #cloud-config başlığı yok"
top = yaml.safe_load(ci)
assert top["users"][0]["ssh_authorized_keys"], "cloud-init: ssh_authorized_keys boş"
assert "qemu-guest-agent" in top["packages"], "cloud-init: qemu-guest-agent eksik"
assert top["ssh_pwauth"] is False, "cloud-init: SSH parola girişi açık kalmış"
assert top["chpasswd"]["users"][0]["type"] == "hash", "cloud-init: parola düz metin yazılıyor"
assert top["users"][0]["lock_passwd"] is False, "cloud-init: hash verildiği halde hesap kilitli"
assert top["growpart"]["devices"] == ["/dev/sda3"], "cloud-init: growpart partition'i yanlis"
cmds = [" ".join(c) if isinstance(c, list) else c for c in top["runcmd"]]
for expected in ("pvresize /dev/sda3", "lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv", "resize2fs /dev/ubuntu-vg/ubuntu-lv"):
    assert any(expected == c for c in cmds), f"cloud-init: runcmd'de eksik: {expected}"
print(f"cloud-init: OK ({len(top.get('packages', []))} paket, {len(top.get('runcmd', []))} runcmd, disk buyutme var)")

nopw = yaml.safe_load((tmp / "cloud-init-nopw.yaml").read_text())
assert "chpasswd" not in nopw, "cloud-init: hash yokken chpasswd bloğu üretiliyor"
assert nopw["users"][0]["lock_passwd"] is True, "cloud-init: parolasız kurulumda hesap kilitli değil"
print("cloud-init (parolasız): OK (hesap kilitli, yalnızca SSH key)")

inv = yaml.safe_load((tmp / "inventory.yaml").read_text())
hosts = inv["all"]["hosts"]
groups = {"masters", "workers"}
assert groups <= set(inv), f"inventory: eksik grup {groups - set(inv)}"
assert not (groups & set(hosts)), "inventory: grup adı ile host adı çakışıyor"
assert set(inv["rke2-cluster"]["children"]) == {"masters", "workers"}
member_count = len(inv["masters"]["hosts"]) + len(inv["workers"]["hosts"])
assert member_count == len(hosts), "inventory: gruplara atanmayan host var"
print(f"inventory: OK ({len(hosts)} host, {len(inv['workers']['hosts'])} worker)")
PY
