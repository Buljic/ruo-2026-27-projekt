output "adrese" {
  description = "Adrese svih VM-ova i segmenata (administracija i provjere)"
  value = {
    web = { nat = var.vm.web.nat, segment = var.vm.web.seg }
    app = { nat = var.vm.app.nat, segment = var.vm.app.seg }
    db  = { nat = var.vm.db.nat, segment = var.vm.db.seg }
    dns = { nat = var.vm.dns.nat }
    llm = { nat = var.vm.llm.nat, segment = var.vm.llm.seg }
  }
}
