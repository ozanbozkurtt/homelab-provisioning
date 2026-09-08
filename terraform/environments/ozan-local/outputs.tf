output "rke2_master" {
  description = "RKE2 control plane node"
  value = {
    vm_id = module.rke2_master.vm_id
    name  = module.rke2_master.vm_name
    ip    = local.master_ip
  }
}

output "rke2_workers" {
  description = "RKE2 worker node'ları"
  value = {
    for name, mod in module.rke2_worker : name => {
      vm_id = mod.vm_id
      ip    = local.worker_ips[name]
    }
  }
}

output "ansible_inventory_path" {
  description = "Terraform'un ürettiği Ansible inventory'si"
  value       = local_file.ansible_inventory.filename
}

output "next_step" {
  description = "Apply sonrası çalıştırılacak komut"
  value       = "cd ansible && ansible-playbook -i inventory/${var.environment}/ playbooks/site.yml"
}

output "kubeconfig_command" {
  description = "Master'dan kubeconfig alma komutu (Ansible rke2_download_kubeconf da indirir)"
  value       = "ssh ${var.vm_username}@${local.master_ip} sudo cat /etc/rancher/rke2/rke2.yaml | sed 's/127.0.0.1/${local.master_ip}/' > ~/.kube/rke2-ozan.yaml"
}

output "resource_budget" {
  description = "Node kaynak kullanım özeti"
  value = {
    requested_memory_mb = local.requested_memory_mb
    available_memory_mb = local.available_memory_mb
    requested_disk_gb   = local.requested_disk_gb
    requested_vcpu      = var.master_cpu_cores + (var.worker_count * var.worker_cpu_cores)
  }
}
