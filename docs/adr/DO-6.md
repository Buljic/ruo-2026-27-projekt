# DO-6: Kako Ansible dobija adrese VM-ova

Status: prihvaceno

## Kontekst
Terraform kreira VM-ove (AO-3), Ansible ih konfigurise (AO-5). Adrese se ne smiju
prepisivati rucno.

## Razmotrene opcije
1. Rucni inventory.
2. Inventory generisan iz Terraform outputa (local_file).
3. Dinamicki inventory plugin.

## Odluka
Terraform resource `local_file` generise `ansible/inventory.ini` iz mape `local.vm`
(ista mapa puni cloud-init i DNS zapise).

## Obrazlozenje i posljedica
Rucni inventory bi bio treci izvor istine i prva stvar koja se zaboravi azurirati.
Dinamicki plugin je jaci, ali za pet statickih VM-ova nema prednost. Generisani
inventory je gitignored (nastaje pri `make infra`), pa se ne moze razici sa stanjem.
