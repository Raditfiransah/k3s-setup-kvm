output "vm_names" {
  value = [for n in local.nodes : n.name]
}

output "vm_ips" {
  value = [for n in local.nodes : n.ip]
}

output "ssh_commands" {
  value = [for n in local.nodes : "ssh ${var.ssh_username}@${n.ip}"]
}
