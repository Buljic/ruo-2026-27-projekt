# DO-3: Plan adresiranja

Status: prihvaceno

## Kontekst
AO-6 trazi vlastitu podmrezu po segmentu; AO-7 trazi da se komponente zovu DNS
imenima. Adrese moraju biti deterministicke da bi ih Terraform, DNS i vatrozid
dijelili bez rucnog uskladjivanja.

## Razmotrene opcije
1. Dinamicke adrese (DHCP) po segmentima.
2. Staticke adrese (cloud-init), jedan plan u Terraformu.

## Odluka
Staticke adrese:
- web segment 192.168.10.0/24, app 192.168.20.0/24, db 192.168.30.0/24;
- NAT/admin ravan 192.168.111.0/24 (SSH, DNS, internet);
- svaki sloj .11 u svom segmentu; host .1 na svakom segmentu je gateway;
- DNS 192.168.111.11, LLM 192.168.111.23 (admin ravan).

## Obrazlozenje i posljedice
Sa statickim adresama ista mapa u Terraformu generise inventory i DNS zapise, a
vatrozid pravila po podmrezima su stabilna. DHCP bi uveo treci izvor istine i
mogucnost da se adresa promijeni izmedju pokretanja. Posljedica: adrese se ne
smiju rucno mijenjati; sve ide kroz Terraform.
