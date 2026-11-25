# DO-4: Porijeklo bazne slike VM-a

Status: prihvaceno

## Kontekst
AO-4 trazi da pocetnu konfiguraciju radi cloud-init (korisnik sa SSH kljucem,
lozinka zabranjena). Slika mora biti reproducibilna bez rucnih koraka.

## Razmotrene opcije
1. Javna Ubuntu 24.04 cloud slika + cloud-init (kao s2/p3).
2. Vlastita slika izgradjena Packerom (kao s2/p4).

## Odluka
Javna cloud slika (noble-server-cloudimg-amd64) + cloud-init user-data i
network-config po VM-u.

## Obrazlozenje i posljedice
Packer dodaje korak izgradnje i novi artefakt za odrzavanje, a nista ne dobija
jer se sve konfiguracije ionako rade Ansibleom (AO-5). Cloud-init pokriva tacno
ono sto AO-4 trazi: korisnik, kljuc, zabranu lozinke, staticke adrese i rute.
Posljedica: prvi boot traje malo duze (cloud-init), sto je prihvatljivo.
