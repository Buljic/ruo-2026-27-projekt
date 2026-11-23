# DNS zapisi servisa kao Terraform resursi (AO-8).
# Provider hashicorp/dns mijenja zonu projekt.lab kroz RFC 2136 UPDATE, potpisan
# TSIG kljucem ruo-tf. Kljuc smije mijenjati samo ovu zonu (AO-8).

terraform {
  required_version = ">= 1.5"
  required_providers {
    dns = { source = "hashicorp/dns", version = "~> 3.4" }
  }
}

variable "tsig_secret" {
  description = "TSIG tajna kljuca ruo-tf (dozvoljava UPDATE samo u zoni projekt.lab)"
  type        = string
  sensitive   = true
}

provider "dns" {
  update {
    server        = "192.168.111.11"
    key_name      = "ruo-tf."
    key_algorithm = "hmac-sha256"
    key_secret    = var.tsig_secret
  }
}

# ime -> adresa segmenta; komponente se zovu ovim imenima (AO-7)
locals {
  zapisi = {
    frontend = "192.168.10.11"
    backend  = "192.168.20.11"
    baza     = "192.168.30.11"
    llm      = "192.168.111.23"
  }
}

resource "dns_a_record_set" "servis" {
  for_each  = local.zapisi
  zone      = "projekt.lab."
  name      = each.key
  addresses = [each.value]
  ttl       = 300
}
