terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

locals {
  node_count = var.server_count + var.agent_count

  nodes = [for i in range(local.node_count) : {
    name = "${var.vm_name_prefix}-${i + 1}"
    ip   = cidrhost(var.network_cidr, var.node_ip_start + i)
    mac  = format("52:54:00:aa:bb:%02x", i + 1)
    role = i < var.server_count ? "server" : "agent"
  }]

  servers = [for n in local.nodes : n if n.role == "server"]
  agents  = [for n in local.nodes : n if n.role == "agent"]
}

# Ubuntu cloud image
resource "libvirt_volume" "ubuntu_base" {
  name = "ubuntu-24.04-base.qcow2"

  source = var.ubuntu_image_url
  format = "qcow2"
}

# Disk untuk masing-masing VM
resource "libvirt_volume" "vm_disk" {
  count = local.node_count

  name           = "${var.vm_name_prefix}-${count.index + 1}.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = var.disk_size
}

# Network
resource "libvirt_network" "k3s" {
  name      = var.network_name
  mode      = "nat"
  domain    = var.domain
  addresses = [var.network_cidr]

  dhcp {
    enabled = true
  }

  dns {
    enabled = true
  }
}

# Cloud-init
resource "libvirt_cloudinit_disk" "cloudinit" {
  count = local.node_count

  name = "${var.vm_name_prefix}-${count.index + 1}-cloudinit.iso"

  user_data = templatefile("${path.module}/cloud-init/user-data.yaml", {
    hostname = "${var.vm_name_prefix}-${count.index + 1}"
    username = var.ssh_username
    ssh_key  = var.ssh_public_key
  })
}

# VM
resource "libvirt_domain" "vm" {
  count = local.node_count

  name   = local.nodes[count.index].name
  memory = var.memory
  vcpu   = var.vcpu

  cpu {
    mode = "host-passthrough"
  }

  qemu_agent = true

  disk {
    volume_id = libvirt_volume.vm_disk[count.index].id
  }

  cloudinit = libvirt_cloudinit_disk.cloudinit[count.index].id

  network_interface {
    network_name = libvirt_network.k3s.name
    mac          = local.nodes[count.index].mac
    addresses    = [local.nodes[count.index].ip]
    hostname     = local.nodes[count.index].name
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "none"
  }
}

# Generate Ansible inventory from deterministic node IPs
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"

  content = templatefile("${path.module}/templates/inventory.ini.tpl", {
    servers = local.servers
    agents  = local.agents
  })
}