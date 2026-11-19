# RuO 2026/27 - Projektni zadatak: troslojna aplikacija kao kod (DO-2: opcija B).
# Tri segmenta (web/app/db) su libvirt route mreze; host je ruter izmedju njih i
# propusta samo dozvoljeni saobracaj (nftables na hostu, ansible/host-tijelo).
# NAT mreza ruo-nat je admin/internet ravan: SSH, DNS ka BIND-u, izlaz na internet.

terraform {
  required_version = ">= 1.5"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# --- admin/internet ravan (NAT): SSH sa hosta, DNS ka BIND VM, izlaz na internet ---
resource "libvirt_network" "nat" {
  name      = "ruo-nat"
  bridge    = "br-nat"
  mode      = "nat"
  domain    = "projekt.lab"
  addresses = ["192.168.111.0/24"]
  autostart = true
  dns { enabled = true }
  dhcp { enabled = false }
}

# --- tri izolovana segmenta (route mod): host je ruter izmedju njih ---
resource "libvirt_network" "web" {
  name      = "ruo-web"
  bridge    = "br-web"
  mode      = "route"
  domain    = "web.projekt.lab"
  addresses = ["192.168.10.0/24"]
  autostart = true
  dns { enabled = false }
  dhcp { enabled = false }
}
resource "libvirt_network" "app" {
  name      = "ruo-app"
  bridge    = "br-app"
  mode      = "route"
  domain    = "app.projekt.lab"
  addresses = ["192.168.20.0/24"]
  autostart = true
  dns { enabled = false }
  dhcp { enabled = false }
}
resource "libvirt_network" "db" {
  name      = "ruo-db"
  bridge    = "br-db"
  mode      = "route"
  domain    = "db.projekt.lab"
  addresses = ["192.168.30.0/24"]
  autostart = true
  dns { enabled = false }
  dhcp { enabled = false }
}

# --- VM-ovi: jedan sloj = jedna masina; dns i llm su zasebne (vLLM build ostaje) ---
# eth0 = NAT (admin/internet), eth1 = segment (data ravan).
variable "vm" {
  description = "Parametri VM-ova (adrese, resursi, MAC adrese, rute segmenata)"
  type = map(object({
    nat     = string, seg = string, mem = number, cpu = number, disk = number,
    mac_nat = string, mac_seg = string, seg_gw = string, seg_rute = list(string)
  }))
  default = {
    web = { nat = "192.168.111.21", seg = "192.168.10.11", mem = 1024, cpu = 1, disk = 10, mac_nat = "52:54:00:aa:01:01", mac_seg = "52:54:00:ab:01:01", seg_gw = "192.168.10.1", seg_rute = ["192.168.20.0/24", "192.168.30.0/24"] }
    app = { nat = "192.168.111.22", seg = "192.168.20.11", mem = 2048, cpu = 2, disk = 10, mac_nat = "52:54:00:aa:02:01", mac_seg = "52:54:00:ab:02:01", seg_gw = "192.168.20.1", seg_rute = ["192.168.10.0/24", "192.168.30.0/24"] }
    db  = { nat = "192.168.111.14", seg = "192.168.30.11", mem = 1024, cpu = 1, disk = 10, mac_nat = "52:54:00:aa:03:01", mac_seg = "52:54:00:ab:03:01", seg_gw = "192.168.30.1", seg_rute = ["192.168.10.0/24", "192.168.20.0/24"] }
    dns = { nat = "192.168.111.11", seg = "", mem = 512, cpu = 1, disk = 10, mac_nat = "52:54:00:aa:04:01", mac_seg = "", seg_gw = "", seg_rute = [] }
    llm = { nat = "192.168.111.23", seg = "", mem = 10240, cpu = 4, disk = 30, mac_nat = "52:54:00:aa:05:01", mac_seg = "", seg_gw = "", seg_rute = [] }
  }
}

variable "ssh_pubkey_path" {
  description = "Javni SSH kljuc upravljackog korisnika"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "image_url" {
  description = "Bazna cloud slika (DO-4)"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

locals {
  segnet = { web = "web", app = "app", db = "db" }
  # mapa segmenata za dynamic blok (resource se ne moze indeksirati imenom direktno)
  mreze = { web = libvirt_network.web, app = libvirt_network.app, db = libvirt_network.db }
}

resource "libvirt_volume" "base" {
  name   = "ubuntu-noble-base.qcow2"
  pool   = "default"
  format = "qcow2"
  source = var.image_url
}

resource "libvirt_volume" "disk" {
  for_each       = var.vm
  name           = "ruo-${each.key}.qcow2"
  pool           = "default"
  base_volume_id = libvirt_volume.base.id
  size           = each.value.disk * 1024 * 1024 * 1024
}

resource "libvirt_cloudinit_disk" "init" {
  for_each = var.vm
  name     = "ruo-${each.key}-init.iso"
  pool     = "default"

  user_data = templatefile("${path.module}/../../cloud-init/user-data.tftpl", {
    hostname = each.key
    domena   = "projekt.lab"
    ssh_key  = trimspace(file(pathexpand(var.ssh_pubkey_path)))
  })

  network_config = templatefile("${path.module}/../../cloud-init/network-config.tftpl", {
    nat_ip     = each.value.nat
    seg_ip     = each.value.seg
    seg_gw     = lookup(each.value, "seg_gw", "")
    seg_routes = lookup(each.value, "seg_rute", [])
    mac_nat    = each.value.mac_nat
    mac_seg    = each.value.mac_seg
    gateway    = "192.168.111.1"
    dns        = each.key == "dns" ? "192.168.111.1" : "192.168.111.11" # dns VM prije BIND-a koristi libvirt resolver
  })
}

resource "libvirt_domain" "vm" {
  for_each  = var.vm
  name      = "ruo-${each.key}"
  memory    = each.value.mem
  vcpu      = each.value.cpu
  autostart = false
  cloudinit = libvirt_cloudinit_disk.init[each.key].id

  disk {
    volume_id = libvirt_volume.disk[each.key].id
  }

  network_interface {
    network_name = libvirt_network.nat.name
    mac          = each.value.mac_nat
  }

  dynamic "network_interface" {
    for_each = each.value.seg != "" ? [local.segnet[each.key]] : []
    content {
      network_name = local.mreze[local.segnet[each.key]].name
      mac          = each.value.mac_seg
    }
  }

  # llm VM: host-passthrough CPU (torch/vLLM CPU kerneli traze AVX; qemu64 ih nema)
  dynamic "cpu" {
    for_each = each.key == "llm" ? [1] : []
    content {
      mode = "host-passthrough"
    }
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "none"
  }
}

resource "local_file" "inventory" {
  filename = "${path.module}/../../ansible/inventory.ini"
  content  = <<-EOT
    # generise Terraform (terraform/vm/main.tf) - ne mijenjati rucno
    [all:vars]
    ansible_user=student
    ansible_ssh_private_key_file=~/.ssh/id_ed25519
    ansible_python_interpreter=/usr/bin/python3

    [web]
    web ansible_host=${var.vm.web.nat}

    [app]
    app ansible_host=${var.vm.app.nat}

    [db]
    db ansible_host=${var.vm.db.nat}

    [dns]
    dns ansible_host=${var.vm.dns.nat}

    [llm]
    llm ansible_host=${var.vm.llm.nat}
  EOT
}
