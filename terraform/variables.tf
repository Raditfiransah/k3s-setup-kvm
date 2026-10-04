variable "libvirt_uri" {
  description = "Libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "ubuntu_image_url" {
  description = "Ubuntu 24.04 cloud image"
  type        = string

  default = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "vm_name_prefix" {
  type    = string
  default = "k3s-node"
}

variable "network_name" {
  type    = string
  default = "k3s-network"
}

variable "domain" {
  type    = string
  default = "k3s.local"
}

variable "network_cidr" {
  type    = string
  default = "192.168.100.0/24"
}

variable "server_count" {
  description = "Jumlah node server (master)"
  type        = number
  default     = 1
}

variable "agent_count" {
  description = "Jumlah node agent (worker)"
  type        = number
  default     = 1
}

variable "node_ip_start" {
  description = "Oktet terakhir IP node pertama (IP statis berurutan)"
  type        = number
  default     = 10
}

variable "memory" {
  description = "RAM per VM in MB"
  type        = number
  default     = 4096
}

variable "vcpu" {
  description = "vCPU per VM"
  type        = number
  default     = 2
}

variable "disk_size" {
  description = "Disk size in bytes"
  type        = number
  default     = 21474836480
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}