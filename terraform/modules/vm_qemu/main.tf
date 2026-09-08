terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.68.0"
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name            = var.vm_name
  description     = var.description
  node_name       = var.node_name
  vm_id           = var.vm_id
  tags            = var.tags
  started         = var.started
  on_boot         = var.on_boot
  stop_on_destroy = true
  keyboard_layout = var.keyboard_layout

  dynamic "clone" {
    for_each = var.template_vm_id != null ? [1] : []
    content {
      vm_id = var.template_vm_id
      full  = true
    }
  }

  agent {
    enabled = var.agent_enabled
  }

  cpu {
    cores = var.cpu_cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory_mb
  }

  vga {
    type = "std"
  }

  dynamic "initialization" {
    for_each = var.cloud_init != null ? [var.cloud_init] : []
    content {
      datastore_id = var.datastore_id

      ip_config {
        ipv4 {
          address = initialization.value.ip_address
          gateway = initialization.value.gateway
        }
      }

      dynamic "dns" {
        for_each = length(initialization.value.dns_servers) > 0 ? [1] : []
        content {
          servers = initialization.value.dns_servers
        }
      }

      dynamic "user_account" {
        for_each = initialization.value.user_data_file_id == null ? [1] : []
        content {
          username = initialization.value.username
          password = initialization.value.password
          keys     = initialization.value.ssh_public_keys
        }
      }

      user_data_file_id = initialization.value.user_data_file_id
    }
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size_gb
    file_format  = "raw"
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }
}
