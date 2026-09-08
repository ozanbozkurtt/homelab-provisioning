output "vm_id" {
  description = "Oluşturulan VM'in ID'si"
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "vm_name" {
  description = "Oluşturulan VM'in adı"
  value       = proxmox_virtual_environment_vm.vm.name
}
