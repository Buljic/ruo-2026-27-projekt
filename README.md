# RuO 2026/27 - Troslojna aplikacija kao kod

Projektni zadatak iz Racunarstva u oblaku: kompletna infrastruktura za troslojnu
web aplikaciju, opisana isključivo kodom. Aplikacija je Tetris koji igra LLM
(vLLM servira mali model koji bira poteze); pravila igre su u kodu, a rezultati
idu u bazu.

Univerzitet u Zenici, Politehnicki fakultet, II ciklus, III semestar.
Student: Imad Buljić. Repozitorij: `https://github.com/Buljic/ruo-2026-27-projekt`.

## 1. Aplikacija i arhitektura

Tok zahtjeva: **frontend -> backend -> baza** (AO-1). Frontend je jedini javni
ulaz; frontend nema mrežni put do baze (AO-6).

```
            korisnik (internet/lab)
                    |
                    v  :80
   +--------------------------------------------+
   | web segment 192.168.10.0/24                |
   |  web VM .11  [frontend: nginx kontejner]   |
   +-------------------+------------------------+
                       | :8000 (DNS: backend.projekt.lab)
   +-------------------v------------------------+
   | app segment 192.168.20.0/24                |
   |  app VM .11  [backend: FastAPI kontejner]  |
   |        \                                   |
   |         \ :8000 (DNS: llm.projekt.lab)     |
   |          v                                 |
   |   llm VM .23 (van segmenata, admin ravan)  |
   |      [vLLM, Qwen2.5-0.5B, CPU]             |
   +-------------------+------------------------+
                       | :5432 (DNS: baza.projekt.lab)
   +-------------------v------------------------+
   | db segment 192.168.30.0/24                 |
   |  db VM .11  [baza: PostgreSQL kontejner]   |
   |             [volume: podaci prezivljavaju] |
   +--------------------------------------------+

   admin ravan (NAT) 192.168.111.0/24: SSH, DNS (BIND na dns VM .11),
   izlaz na internet. Tu su i VM dns i VM llm.
```

Aplikacija po slojevima:
- frontend: nginx koji servira Tetris UI i proksira /api na backend,
- backend: FastAPI; pita LLM za potez, upisuje rezultat u bazu, izlaze /health i /ready,
- baza: PostgreSQL 16 u kontejneru; tabela `rezultati`; podaci u Docker volume-u.

## 2. Plan adresiranja i izolacija

| Segment | Podmreza | VM | Adresa | Gateway |
|---|---|---|---|---|
| web | 192.168.10.0/24 | web | 192.168.10.11 | 192.168.10.1 (host) |
| app | 192.168.20.0/24 | app | 192.168.20.11 | 192.168.20.1 (host) |
| db | 192.168.30.0/24 | db | 192.168.30.11 | 192.168.30.1 (host) |
| admin/NAT | 192.168.111.0/24 | dns, llm | .11, .23 | 192.168.111.1 |

Izolacija (AO-6) se sprovodi na tri mjesta:
1. **host ruter** (ansible/host/ruter.nft.j2): propusta samo web->app:8000 i
   app->db:5432; sve ostalo izmedju segmenata odbija (frontend->baza posebno);
2. **vatrozid svake VM** (ansible/roles/firewall): politika drop; baza prima 5432
   samo iz app podmreze, backend 8000 samo iz web podmreze, frontend 80 javno;
   ICMP samo s admina i gatewaya segmenata (admin/NAT ravan nije medjuslojevski put);
3. **kontejneri**: host mreza bez Docker DNAT-a; baza slusa samo na segment adresi
   (`listen_addresses`), pa nema porta na NAT ravni.

Sve adrese su staticke (cloud-init). Komponente se medjusobno zovu **samo DNS imenima** (frontend.projekt.lab,
backend.projekt.lab, baza.projekt.lab, llm.projekt.lab). IP adrese se u kodu
pojavljuju samo u planu adresiranja (Terraform varijabla `vm`, group_vars) i u
testovima. Napomena: VM-ovi dijele i admin/NAT ravan; nju vatrozid zatvara na
admina (SSH, DNS), pa ni preko nje nema puta izmedju slojeva (test pingom).

## 3. Pokretanje od praznog racunara

Preduslovi: Linux s KVM/libvirt (~5 VM-ova, ~15 GB RAM-a), Terraform, Ansible,
ssh, dig, curl. Terraform i Ansible su na ovoj masini instalirani bez root-a
(vidi `make check`).

Na Windowsu projekt radi kroz **WSL2 (Ubuntu)**, ne na golorom Windowsu (libvirt,
nftables i systemd su Linux): u `%UserProfile%\.wslconfig` postaviti
`nestedVirtualization=true`, u `/etc/wsl.conf` postaviti `[boot] systemd=true`,
pa u WSL2 instalirati `qemu-kvm libvirt-daemon-system` i Terraform/Ansible.
Provjera: `ls /dev/kvm` postoji i `systemctl --user status` radi; bez toga se
VM-ovi ne mogu dizati.

Jednokratna priprema hosta (samo prvi put; trazi lozinku jednom): dozvoliti
`sudo` bez lozinke za dvije naredbe host rutera (`scripts/sudoers-zahtjev.txt`):

```bash
echo 'imadbuljic ALL=(root) NOPASSWD: /usr/bin/nft, /usr/bin/sysctl' | sudo tee /etc/sudoers.d/ruo-projekt
sudo chmod 440 /etc/sudoers.d/ruo-projekt
```

Zatim, od nule:

```bash
git clone <repo> && cd ruo-2026-27-projekt
make all        # infra -> config -> dns -> deploy
make test       # izolacija, dig upiti, aplikacija
make all        # drugo izvrsavanje: bez promjena (idempotentnost)
```

Uklanjanje svega: `make destroy`.

Ciljevi: `check` (alati), `infra` (Terraform: mreze i VM-ovi), `config` (Ansible:
host ruter, BIND, vatrozid, Docker), `dns` (Terraform: servisni zapisi kroz RFC
2136), `deploy` (Ansible: kontejneri po slojevima), `test`, `all`, `destroy`.

## 4. Struktura repozitorija

```
app/frontend/     Dockerfile, nginx.conf, tetris.html, compose.yaml
app/backend/      Dockerfile, app.py, requirements.txt, compose.yaml
app/db/           init.sh, compose.yaml
terraform/vm/     VM-ovi i mreze (AO-3)
terraform/dns/    DNS zapisi kao Terraform resursi (AO-8)
cloud-init/       user-data i network-config (AO-4)
ansible/          config.yml, deploy.yml, role (AO-5, AO-7)
tests/            izolacija, DNS, aplikacija
docs/adr/         DO-1 do DO-9 (arhitektonske odluke)
Makefile
README.md
```

## 5. Drift i ispravka

Rucna izmjena DNS zapisa (mimo koda) i povratak na stanje iz koda:

```
$ nsupdate ... update add backend.projekt.lab 300 A 192.168.20.99
$ dig +short @192.168.111.11 backend.projekt.lab A
192.168.20.99
$ cd terraform/dns && terraform plan
  ~ dns_a_record_set.servis["backend"]
      ~ addresses = [ "192.168.20.99" -> "192.168.20.11" ]
$ terraform apply
  dns_a_record_set.servis["backend"]: Modifications complete
  Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
$ dig +short @192.168.111.11 backend.projekt.lab A
192.168.20.11
```

Isto vazi za VM-ove: parametri su u varijabli `vm` (`terraform/vm/main.tf`);
`terraform plan` pokaze drift, `terraform apply` ga ispravi.

## 6. Idempotentnost (drugo izvrsavanje)

```
$ make config
app : ok=14 changed=0   db : ok=14 changed=0   dns : ok=21 changed=0
llm : ok=13 changed=0   web : ok=14 changed=0

$ make deploy
app : ok=4 changed=0    db : ok=4 changed=0    llm : ok=12 changed=0
web : ok=3 changed=0

(Napomena: `make config` prvo pokrene host play; `nft -f` se primjenjuje svaki put,
pa host prijavi changed. VM-ovi su 0 changed. `make dns` drugi put: 0 added.)
```

## 7. Testovi

```
$ make test
== 1. Izolacija: frontend NE vidi bazu (AO-6)
  ok: frontend -> baza.projekt.lab:5432 (segment) (CLOSED)
  ok: frontend -> db NAT adresa:5432 (CLOSED)
== 2. Dozvoljeni tok: frontend -> backend
  ok: frontend -> backend.projekt.lab:8000 (OPEN)
== 3. Dozvoljeni tok: backend -> baza
  ok: backend -> baza.projekt.lab:5432 (OPEN)
== 4. Baza ne prima iz web segmenta ni s NAT ravni
  ok: frontend -> baza (ponovno, drugi put) (CLOSED)
  ok: backend -> db NAT adresa:5432 (nema porta izvana) (CLOSED)
== 5. Backend nije javno dostupan
  ok: frontend -> app NAT adresa:8000 (samo segment) (CLOSED)
SVE PROVEDENO (0 gresaka)

== DNS: SOA ns1, frontend/backend/baza/llm na adrese segmenata, NS, rekurzija, NXDOMAIN
SVE PROVEDENO (0 gresaka)

== Aplikacija: GET / 200 + Tetris, /api/potez vraca potez, /api/kraj upisuje,
   /api/top cita, AO-10 restart baze cuva podatke, /ready 200
SVE PROVEDENO (0 gresaka)
```

## 8. Tajne

`scripts/generate_keys.sh` pri prvom pokretanju pravi SSH kljuc, TSIG kljuc
`ruo-tf`, vault lozinku i sifrovani `vault.yml` (lozinka baze). U Git idu samo
`vault.yml.example` i `scripts/sudoers-zahtjev.txt`; `.tajne/`, `ansible/.vault_pass`,
`.env` i `*.tfstate` su gitignored (AO-9).

## 9. Ogranicenja

- LLM je na admin/NAT ravni, ne u app segmentu: interna je zavisnost backenda;
  u produkciji bi bio u app segmentu (ili iza vlastitog balansera).
- vLLM se na CPU gradi iz izvora (~25 min pri prvom `make deploy`, MAX_JOBS=4); model je
  Qwen2.5-0.5B. U produkciji GPU i veci model, isti API.
- Jedan DNS server (nema sekundarnog); jedan LLM (nema replike).
- TLS nije uveden (lab mreza); u produkciji balanser s certifikatom.

## 10. Opcija za slab laptop (llama.cpp umjesto vLLM)

vLLM se na CPU kompajlira ~25 min i trazi 10 GB RAM-a. Ako se projekt podize na
slabijem laptopu bez GPU-a, LLM sloj se moze zamijeniti bez izmjena u aplikaciji:

```bash
make deploy-llama   # llama.cpp server, isti model (GGUF Q4_K_M), isti API
```

llama.cpp se kompajlira ~3 min i servira isti OpenAI-kompatibilan endpoint, pa
backend i DNS imena ostaju isti. Vracanje na vLLM: `make deploy`. Ovo je opcija,
ne default; vLLM ostaje primarni izbor.
