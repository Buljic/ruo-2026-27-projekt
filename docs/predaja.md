---
title: "Projektni zadatak: Troslojna aplikacija kao kod"
subtitle: "Racunarstvo u oblaku 2026/27"
author: "Imad Buljić"
date: "25.11.2026."
geometry: margin=2.5cm
fontsize: 11pt
---

## Podaci o predaji

- Student: **Imad Buljić**
- Predmet: Racunarstvo u oblaku, II ciklus, III semestar, 2026/27
- Git repozitorij: `https://github.com/Buljic/ruo-2026-27-projekt`
- Aplikacija: Tetris koji igra LLM (vLLM + Qwen2.5-0.5B na CPU); frontend nginx,
  backend FastAPI, baza PostgreSQL 16, svaki sloj u svom kontejneru.

## Kratak opis arhitekture

Tri mrezno izolovana segmenta: web (192.168.10.0/24), app (192.168.20.0/24),
db (192.168.30.0/24). Svaki sloj je jedna virtuelna masina koju kreira Terraform
(libvirt route mreze), a host je ruter koji propusta samo frontend->backend:8000
i backend->baza:5432. Frontend je jedini javni ulaz (port 80 na NAT ravni) i nema
mrezni put do baze; baza nema objavljen port izvan svog segmenta. Pocetnu
konfiguraciju VM-ova radi cloud-init (korisnik + SSH kljuc, lozinka zabranjena),
konfiguraciju servisa Ansible role. Autoritativna BIND zona `projekt.lab` drzi
servisna imena; zapisi frontend, backend, baza i llm su Terraform resursi
(provider hashicorp/dns, RFC 2136, TSIG kljuc `ruo-tf`). Podaci baze su u Docker
volume-u i prezivljavaju ponovno kreiranje kontejnera.

## Pregled dizajnerskih odluka (DO-1 do DO-9)

| DO | Pitanje | Izabrana opcija |
|---|---|---|
| DO-1 | Aplikacija i tehnologije po slojevima | Vlastita aplikacija: nginx + FastAPI + PostgreSQL, LLM (vLLM) kao zavisnost backenda |
| DO-2 | Broj VM-ova i raspored komponenti | Opcija B: po jedna VM za svaki segment, libvirt route mreze, host rutira; DNS zasebna VM |
| DO-3 | Plan adresiranja | Tri /24 segmenta + NAT admin ravan; staticke adrese; .11 po sloju, .1 gateway |
| DO-4 | Porijeklo bazne slike | Ubuntu 24.04 cloud slika + cloud-init (bez Packera) |
| DO-5 | Gradnja i distribucija slika | Build na ciljnoj VM preko docker compose (bez registryja) |
| DO-6 | Inventory za Ansible | Generisan iz Terraform outputa (local_file) |
| DO-7 | Organizacija rola i varijabli | Rola po komponenti; defaults za rolu, group_vars za okolis |
| DO-8 | DNS zona | Jedna zona projekt.lab, TTL 300, servisni A zapisi kroz Terraform RFC 2136 |
| DO-9 | Upravljanje tajnama | ansible-vault + generisanje pri prvom pokretanju; .env van Gita |


# DO-1: Aplikacija i tehnologije po slojevima

Status: prihvaceno

## Kontekst
AO-1 trazi troslojnu aplikaciju: frontend, backend i baza, svaki u svom kontejneru,
tok isključivo frontend -> backend -> baza. Aplikacija nije predmet ocjenjivanja,
ali mora dokazati tok kroz sva tri sloja.

## Razmotrene opcije
1. Gotova open-source aplikacija (npr. bbbm) bez izmjena.
2. Vlastita aplikacija: Tetris koji igra LLM (vLLM servira mali model koji bira poteze).

## Odluka
Vlastita aplikacija:
- frontend: nginx koji servira Tetris UI i proksira /api na backend,
- backend: FastAPI koji pita LLM za potez i upisuje rezultate,
- baza: PostgreSQL u kontejneru sa volume-om (rezultati igre).

## Obrazlozenje i posljedice
Vlastita aplikacija daje tri stvarna toka kroz slojeve (UI -> API -> INSERT/SELECT),
pa se svaka AO provjerava na stvarnom saobracaju. LLM je interna zavisnost backenda
(vLLM na zasebnoj VM), pa backend ima i vanjski poziv, sto je realniji scenario od
cistog CRUD-a. Posljedica: vise komponenti za odrzavanje i sporiji odgovor poteza
(CPU inference), sto je prihvatljivo za lab.
# DO-2: Broj VM-ova i raspored komponenti

Status: prihvaceno

## Kontekst
AO-6 trazi tri mrezno izolovana segmenta (web, app, db) s vlastitim podmrezama.
Nacin izvedbe je slobodan (DO-2), a DNS moze biti na zasebnoj ili zajednickoj VM.

## Razmotrene opcije
1. Opcija A: jedna VM, segmenti kao Docker mreze s fiksnim podmrezama (prosirenje s3/p4).
2. Opcija B: po jedna VM za svaki segment na libvirt route mrezama; host usmjerava
   izmedju njih; DNS na zasebnoj VM.

## Odluka
Opcija B: VM web, VM app, VM db (svaka na svojoj route mrezi) + VM dns + VM llm.
Host je ruter izmedju segmenata; saobracaj koji smije prelaziti segmente propisuje
nftables na hostu i vatrozidi na VM-ovima.

## Obrazlozenje i posljedice
Opcija A bi kontejnere ostavila na Docker mrezama, pa bi DNS imena slojeva pokazivala
na istu VM adresu, a razlikovala bi se samo po portu; AO-7 (adresiranje iskljucivo
imena, po sloju) time slabi. Opcija B daje svakom sloju vlastitu adresu u vlastitoj
podmrezi, pa BIND zona ima smisla po sloju, a izolacija se dokazuje na stvarnom
ruteru. Cijena: vise VM-ova i host konfiguracija (ip_forward + nftables), sto je
dokumentovano i automatizovano.
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
# DO-5: Gradnja i distribucija slika kontejnera

Status: prihvaceno

## Kontekst
AO-1 trazi tri kontejnera. Treba odluciti gdje se slike grade i kako stizu na VM.

## Razmotrene opcije
1. Build na ciljnoj VM (docker compose build).
2. Build lokalno + privatni registry.

## Odluka
Build na ciljnoj VM: `docker compose up -d --build` unutar Ansible role za svaki sloj.

## Obrazlozenje i posljedice
Registry bi dodao cetvrti servis (i njegovo odrzavanje, autentikaciju i backup) za
dvije male slike. Build na ciljnoj VM je jedan korak manje, a reproducibilnost je
osigurana jer Dockerfile i kod dolaze iz Gita kroz Ansible. Posljedica: prvi deploy
traje duze (pip/nginx slojevi), a build trazi internet na VM-u; oba su prihvatljiva
u labu.
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
# DO-7: Organizacija Ansible rola i varijabli

Status: prihvaceno

## Kontekst
AO-5 trazi Ansible organizovan u role i idempotentan playbook.

## Razmotrene opcije
1. Role po komponenti (common, firewall, dns, docker, frontend, backend, db, llm).
2. Role po funkciji (npr. "mreza", "aplikacija") sa vise komponenti unutra.

## Odluka
Rola po komponenti. U `defaults/` idu vrijednosti koje rola moze promijeniti
(npr. model LLM-a), a u `group_vars/` okolisne cinjenice (adrese segmenata,
vatrozid pravila, tajne kroz vault).

## Obrazlozenje i posljedice
Rola po komponenti prati granice segmenata i laksa je za objasniti na odbrani:
jedna rola = jedan sloj. Posljedica: `config.yml` i `deploy.yml` moraju voditi racuna o redoslijedu
(DNS prije svega, host ruter prije deploya).
# DO-8: Projektovanje DNS zone

Status: prihvaceno

## Kontekst
AO-7 trazi vlastitu autoritativnu zonu (BIND) i adresiranje iskljucivo imenima;
AO-8 trazi da servisni zapisi budu Terraform resursi (RFC 2136, TSIG).

## Razmotrene opcije
1. Jedna zona `projekt.lab`, TTL 300, servisni A zapisi kroz Terraform; SOA/NS staticki.
2. Vise zona po sloju (web/app/db.projekt.lab) sa delegacijama.

## Odluka
Jedna zona `projekt.lab`, TTL 300. SOA i NS (`ns1`) su staticki u zoni; A zapisi
frontend, backend, baza i llm su `dns_a_record_set` resursi (terraform/dns), koje
BIND prihvata kroz RFC 2136 UPDATE potpisan TSIG kljucem `ruo-tf`. Zona zivi u
/var/lib/bind (journal). Sekundarni server, PTR i round-robin nisu uvedeni.

## Obrazlozenje i posljedice
Jedna zona je dovoljna za cetiri imena i drzi sve zapise na jednom mjestu; TSIG
kljuc smije mijenjati samo ovu zonu (AO-8). Sekundarni i round-robin bi dodali
komponente bez potrebe (po jedan sloj = jedna instanca). Posljedica: pad DNS VM-a
obara razrjesavanje; u produkciji bi isao sekundarni server na drugom segmentu.
# DO-9: Upravljanje tajnama

Status: prihvaceno

## Kontekst
AO-9: tajne (lozinke, TSIG, privatni kljucevi) nikad u Gitu u cistom obliku.

## Razmotrene opcije
1. ansible-vault + generisanje pri prvom pokretanju (kao s3/p2).
2. Eksterni secret manager (Vault server, SOPS).

## Odluka
`scripts/generate_keys.sh` pri prvom pokretanju pravi: SSH kljuc admina, TSIG kljuc
`ruo-tf`, vault lozinku i `ansible/group_vars/all/vault.yml` (lozinka baze, TSIG),
pa vault sifrira ansible-vaultom. Lozinke baze idu u `.env` na VM-u (0600, van Gita).
U Gitu je samo `vault.yml.example`.

## Obrazlozenje i posljedice
Vault server bi bio jos jedan servis za cuvanje dvije tajne; ansible-vault je
ugradjen i pokriva AO-9. Generisanje pri pokretanju znaci da tajne nikad ne postoje
u historiji repozitorija. Posljedica: tajne su vezane za lokalni `.tajne/` i
`ansible/.vault_pass`; gubitak tih fajlova znaci rotaciju (sto je i sigurnosno
ispravno).
