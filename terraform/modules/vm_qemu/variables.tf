variable "node_name" {
  description = "VM'in konuşlanacağı Proxmox node ismi"
  type        = string
}

variable "vm_id" {
  description = "VM ID'si (Örn: 200). Null bırakılırsa otomatik atanır."
  type        = number
  default     = null
}

variable "vm_name" {
  description = "Sanal makine adı"
  type        = string
}

variable "description" {
  description = "Sanal makine açıklaması"
  type        = string
  default     = "Managed by Terraform"
}

variable "tags" {
  description = "VM etiketleri"
  type        = list(string)
  default     = ["terraform", "ubuntu"]
}

variable "on_boot" {
  description = "Proxmox açılışında otomatik başlasın mı?"
  type        = bool
  default     = true
}

variable "started" {
  description = "VM başlatılsın mı?"
  type        = bool
  default     = true
}

variable "cpu_cores" {
  description = "CPU çekirdek sayısı"
  type        = number
  default     = 2
}

variable "cpu_type" {
  description = "QEMU CPU tipi. 'host' en hızlısıdır ama VM'i bu fiziksel CPU'ya bağlar; farklı işlemcili bir node'a canlı migrate edilecekse 'x86-64-v2-AES' gibi jenerik bir tip seçin."
  type        = string
  default     = "host"
}

variable "memory_mb" {
  description = "RAM miktarı (MB cinsinden)"
  type        = number
  default     = 2048
}

variable "disk_size_gb" {
  description = "Disk boyutu (GB)"
  type        = number
  default     = 20
}

variable "datastore_id" {
  description = "Diskin tutulacağı Proxmox Datastore ID (Örn: local-lvm)"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Ağ köprüsü (Örn: vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "template_vm_id" {
  description = "Klonlanacak Proxmox VM template ID'si (Örn: 100). Tanımlanırsa ISO yerine template klonlanır."
  type        = number
  default     = null
}

variable "agent_enabled" {
  description = "QEMU Guest Agent aktif edilsin mi?"
  type        = bool
  default     = true
}

variable "keyboard_layout" {
  description = "Klavye düzeni (tr, en-us vb.)"
  type        = string
  default     = "tr"
}

variable "cloud_init" {
  description = "Cloud-Init yapılandırması. user_data_file_id verilirse username/password/ssh_public_keys yok sayılır (kullanıcılar snippet içinde tanımlanmalı)."
  type = object({
    username          = optional(string, "ubuntu")
    password          = optional(string, null)
    ssh_public_keys   = optional(list(string), [])
    ip_address        = optional(string, "dhcp")
    gateway           = optional(string, null)
    dns_servers       = optional(list(string), [])
    user_data_file_id = optional(string, null)
  })
  default = null
}
