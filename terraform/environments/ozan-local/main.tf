locals {
  master_name = "rke2-master"

  worker_names = [for i in range(var.worker_count) : format("rke2-worker-%d", i + 1)]
  worker_ids   = { for i, name in local.worker_names : name => var.worker_vm_id_start + i }
  worker_ips   = { for i, name in local.worker_names : name => cidrhost(var.network_cidr, var.worker_host_octet_start + i) }

  master_ip = cidrhost(var.network_cidr, var.master_host_octet)
  netmask   = split("/", var.network_cidr)[1]

  all_nodes = merge(
    { (local.master_name) = local.master_ip },
    local.worker_ips,
  )

  requested_memory_mb = var.master_memory_mb + (var.worker_count * var.worker_memory_mb)
  requested_disk_gb   = var.master_disk_gb + (var.worker_count * var.worker_disk_gb)
  available_memory_mb = var.node_total_memory_mb - var.node_reserved_memory_mb

  worker_octets  = [for i in range(var.worker_count) : var.worker_host_octet_start + i]
  worker_id_list = values(local.worker_ids)
}

resource "terraform_data" "resource_budget" {
  input = {
    memory_mb = local.requested_memory_mb
    disk_gb   = local.requested_disk_gb
  }

  lifecycle {
    precondition {
      condition     = local.requested_memory_mb <= local.available_memory_mb
      error_message = "Talep edilen RAM (${local.requested_memory_mb} MB) node bütçesini aşıyor (${local.available_memory_mb} MB). worker_count veya *_memory_mb değerlerini düşürün."
    }

    precondition {
      condition     = !contains(local.worker_octets, var.master_host_octet)
      error_message = "Master IP host numarası (${var.master_host_octet}) worker aralığıyla çakışıyor (${var.worker_host_octet_start}-${var.worker_host_octet_start + var.worker_count - 1}). master_host_octet veya worker_host_octet_start değerini değiştirin."
    }

    precondition {
      condition     = !contains(local.worker_id_list, var.master_vm_id)
      error_message = "Master VM ID'si (${var.master_vm_id}) worker aralığıyla çakışıyor (${var.worker_vm_id_start}-${var.worker_vm_id_start + var.worker_count - 1}). master_vm_id veya worker_vm_id_start değerini değiştirin."
    }

    precondition {
      condition     = alltrue([for o in concat(local.worker_octets, [var.master_host_octet]) : o > 0 && o < 255])
      error_message = "Host numaraları 1-254 aralığında olmalı; worker_count bu aralığı taşırıyor."
    }
  }
}

resource "random_password" "rke2_token" {
  length  = 48
  special = false
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  for_each = local.all_nodes

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.target_node

  source_raw {
    file_name = "${each.key}.cloud-config.yaml"
    data = templatefile("${path.module}/cloud-init/base.yaml.tftpl", {
      hostname        = each.key
      username        = var.vm_username
      password_hash   = var.vm_password_hash
      ssh_public_keys = jsonencode(var.ssh_public_keys)
      root_partition  = var.root_partition
      root_vg         = var.root_vg
      root_lv         = var.root_lv
    })
  }
}

module "rke2_master" {
  source = "../../modules/vm_qemu"

  node_name      = var.target_node
  vm_id          = var.master_vm_id
  vm_name        = local.master_name
  description    = "RKE2 control plane - Terraform ile oluşturuldu, Ansible ile yapılandırılır"
  template_vm_id = var.template_vm_id

  cpu_cores    = var.master_cpu_cores
  memory_mb    = var.master_memory_mb
  disk_size_gb = var.master_disk_gb
  datastore_id = var.vm_datastore_id

  cloud_init = {
    ip_address        = "${local.master_ip}/${local.netmask}"
    gateway           = var.network_gateway
    dns_servers       = var.dns_servers
    user_data_file_id = proxmox_virtual_environment_file.cloud_init[local.master_name].id
  }

  tags = ["terraform", "rke2", "master"]
}

module "rke2_worker" {
  source   = "../../modules/vm_qemu"
  for_each = toset(local.worker_names)

  node_name      = var.target_node
  vm_id          = local.worker_ids[each.key]
  vm_name        = each.key
  description    = "RKE2 worker - Terraform ile oluşturuldu, Ansible ile yapılandırılır"
  template_vm_id = var.template_vm_id

  cpu_cores    = var.worker_cpu_cores
  memory_mb    = var.worker_memory_mb
  disk_size_gb = var.worker_disk_gb
  datastore_id = var.vm_datastore_id

  cloud_init = {
    ip_address        = "${local.worker_ips[each.key]}/${local.netmask}"
    gateway           = var.network_gateway
    dns_servers       = var.dns_servers
    user_data_file_id = proxmox_virtual_environment_file.cloud_init[each.key].id
  }

  tags = ["terraform", "rke2", "worker"]
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/${var.ansible_root}/inventory/${var.environment}/hosts.yml"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/ansible-inventory.yml.tftpl", {
    username    = var.vm_username
    master_name = local.master_name
    master_ip   = local.master_ip
    workers     = local.worker_ips
  })
}

resource "local_sensitive_file" "ansible_secrets" {
  filename        = "${path.module}/${var.ansible_root}/inventory/${var.environment}/group_vars/all/secrets.yml"
  file_permission = "0600"

  content = yamlencode({
    rke2_token = random_password.rke2_token.result
  })
}
