variable "environment" {
  description = "Ortam adı"
  type        = string
  default     = "ozan-local"
}

variable "proxmox_api_url" {
  description = "Proxmox VE API Endpoint URL"
  type        = string
  default     = "https://192.168.1.99:8006/"
}

variable "proxmox_api_token" {
  description = "Proxmox API Token (USER@REALM!TOKENID=UUID)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Self-signed SSL sertifika doğrulamasını atla"
  type        = bool
  default     = true
}

variable "target_node" {
  description = "Proxmox Node adı"
  type        = string
  default     = "ozan"
}

variable "template_vm_id" {
  description = "Klonlanacak Ubuntu cloud-init template ID'si"
  type        = number
  default     = 100
}

variable "vm_datastore_id" {
  description = "VM'lerin bulunacağı datastore"
  type        = string
  default     = "ssd"
}

variable "snippet_datastore_id" {
  description = "Cloud-init snippet dosyalarının yükleneceği datastore (snippets content type açık olmalı)"
  type        = string
  default     = "local"
}

variable "node_total_memory_mb" {
  description = "Proxmox node'unun toplam RAM'i (MB). Kaynak bütçesi kontrolü için."
  type        = number
  default     = 15856
}

variable "node_reserved_memory_mb" {
  description = "PVE hypervisor'a ayrılan ve VM'lere dağıtılmayacak RAM (MB)"
  type        = number
  default     = 2048
}

variable "network_cidr" {
  description = "VM'lerin bulunacağı LAN CIDR'ı"
  type        = string
  default     = "192.168.1.0/24"
}

variable "network_gateway" {
  description = "Ağ geçidi"
  type        = string
  default     = "192.168.1.1"
}

variable "dns_servers" {
  description = "Cloud-init ile atanacak DNS sunucuları. Statik IP kullanıldığı için boş bırakılmamalı."
  type        = list(string)
  default     = ["192.168.1.1", "1.1.1.1"]

  validation {
    condition     = length(var.dns_servers) > 0
    error_message = "Statik IP yapılandırmasında en az bir DNS sunucusu gerekir, aksi halde cloud-init paket indiremez."
  }
}

variable "root_partition" {
  description = "Root LVM PV'sinin partition'i. growpart ve pvresize bunu büyütür."
  type        = string
  default     = "/dev/sda3"
}

variable "root_vg" {
  description = "Root logical volume'un volume group'u"
  type        = string
  default     = "ubuntu-vg"
}

variable "root_lv" {
  description = "Root logical volume adı"
  type        = string
  default     = "ubuntu-lv"
}

variable "vm_username" {
  description = "VM'lerde oluşturulacak sudo yetkili kullanıcı"
  type        = string
  default     = "ubuntu"
}

variable "vm_password_hash" {
  description = "vm_username için SHA-512 parola hash'i ($6$...). null ise parola girişi kapalı."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.vm_password_hash == null || can(regex("^\\$[0-9a-z]+\\$", var.vm_password_hash))
    error_message = "vm_password_hash bir crypt hash'i olmalı ($6$... gibi), düz metin parola değil. Üret: mkpasswd -m sha-512"
  }
}

variable "ssh_public_keys" {
  description = "VM'lere eklenecek SSH public key'leri. Ansible katmanı SSH key ile bağlandığı için zorunlu."
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "En az bir SSH public key gerekir; Ansible playbook'ları key tabanlı SSH ile bağlanır (cloud-init'te ssh_pwauth kapalı)."
  }
}

variable "ansible_root" {
  description = "Terraform'un inventory ve secret dosyalarını yazacağı ansible dizininin bu modüle göre yolu (repo kökü: ../../..)"
  type        = string
  default     = "../../../ansible"
}

variable "master_vm_id" {
  description = "RKE2 master VM ID"
  type        = number
  default     = 210
}

variable "master_host_octet" {
  description = "Master'ın network_cidr içindeki host numarası"
  type        = number
  default     = 210
}

variable "master_cpu_cores" {
  description = "Control plane vCPU sayısı"
  type        = number
  default     = 2
}

variable "master_memory_mb" {
  description = "Control plane RAM (MB). resource_budget precondition'ına dahildir."
  type        = number
  default     = 4096
}

variable "master_disk_gb" {
  description = "Control plane disk boyutu (GB). Taint'li olduğu için iş yükü almaz, worker'lardan küçük."
  type        = number
  default     = 40
}

variable "worker_count" {
  description = "RKE2 worker sayısı"
  type        = number
  default     = 2
}

variable "worker_vm_id_start" {
  description = "İlk worker'ın VM ID'si, sonrakiler artarak devam eder"
  type        = number
  default     = 211
}

variable "worker_host_octet_start" {
  description = "İlk worker'ın host numarası, sonrakiler artarak devam eder"
  type        = number
  default     = 211
}

variable "worker_cpu_cores" {
  description = "Worker başına vCPU sayısı"
  type        = number
  default     = 2
}

variable "worker_memory_mb" {
  description = "Worker başına RAM (MB). Prometheus/Grafana cluster içinde ve worker'larda koştuğu için master ile aynı: 4096 + 2*4096 = 12288 MB, bütçe 13808 MB."
  type        = number
  default     = 4096
}

variable "worker_disk_gb" {
  description = "Worker disk boyutu. Prometheus TSDB'si local-path ile bu diskte durur."
  type        = number
  default     = 60
}
