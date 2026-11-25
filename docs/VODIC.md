# Vodic kroz projekt: troslojna aplikacija kao kod

Ovaj dokument objasnjava sta je uradjeno, gdje se sta nalazi i kako se brani.
Redoslijed: zadatak -> arhitektura -> mapa koda -> AO provjere -> DO odluke ->
pokretanje -> odbrana -> dokazi -> ogranicenja.

## 1. Zadatak (iz PDF-a "RuO - Projektni zadatak", sedmice 2-5, 20 bodova)

Troslojna aplikacija (frontend, backend, baza), svaki sloj u svom kontejneru,
na infrastrukturi opisanoj isključivo kodom. 10 obaveznih odluka (AO-1..AO-10)
i 9 dizajnerskih odluka studenta (DO-1..DO-9), svaka s ADR-om. Predaja: PDF
(DO tabela + ADR-ovi) + Git repo s README.

## 2. Arhitektura (stvarni raspored)

```
korisnik ---------> :80  web VM 192.168.111.21 (frontend: nginx kontejner)
                          |
                          | backend.projekt.lab:8000  (segment 192.168.20.0/24)
                          v
                      app VM 192.168.20.11 (backend: FastAPI kontejner)
                          |                 \
                          |                  \ llm.projekt.lab:8000
                          |                   v
                          |             llm VM 192.168.111.23 (vLLM, NAT ravan)
                          | baza.projekt.lab:5432  (segment 192.168.30.0/24)
                          v
                      db VM 192.168.30.11 (PostgreSQL kontejner + volume)

admin ravan (NAT) 192.168.111.0/24: SSH sa hosta, DNS ka BIND-u (dns VM .11)
```

- web segment 192.168.10.0/24, app 192.168.20.0/24, db 192.168.30.0/24.
- Host (.1 u svakom segmentu) je ruter; propusta samo web->app:8000 i app->db:5432.
- Frontend je jedini javni ulaz; frontend nema put do baze (test to dokazuje).
- Komponente se zovu samo DNS imenima: frontend/backend/baza.projekt.lab.

## 3. Mapa repozitorija (sta je gdje)

### Ulaz i upravljanje
| Fajl | Sta radi |
|---|---|
| `Makefile` | ciljevi: check, infra, config, dns, deploy, deploy-llama, test, all, destroy |
| `README.md` | opis arhitekture, plan adresiranja, upute od nule, drift, idempotentnost, testovi |
| `.gitignore` | state, tajne, .env, inventory, diskovi (AO-9, AO-3) |
| `scripts/generate_keys.sh` | pravi SSH kljuc, TSIG kljuc ruo-tf, vault (lozinka baze) |
| `scripts/sudoers-zahtjev.txt` | jednokratna priprema hosta (sudo za nft/sysctl) |

### Terraform: VM-ovi i mreze (AO-3)
| Fajl | Sta radi |
|---|---|
| `terraform/vm/main.tf` | 4 mreze (ruo-nat, ruo-web, ruo-app, ruo-db), varijabla `vm` (5 VM-ova), cloud-init ISO, domeni, generisanje inventoryja |
| `terraform/vm/outputs.tf` | adrese svih VM-ova (output) |
| `cloud-init/user-data.tftpl` | korisnik student + SSH kljuc, lozinka zabranjena (AO-4) |
| `cloud-init/network-config.tftpl` | staticke adrese po MAC-u, default ruta, rute do drugih segmenata |

### Terraform: DNS zapisi (AO-8)
| Fajl | Sta radi |
|---|---|
| `terraform/dns/main.tf` | provider hashicorp/dns, RFC 2136 UPDATE s TSIG kljucem ruo-tf; A zapisi frontend/backend/baza/llm |

### Ansible: konfiguracija (AO-5, AO-7)
| Fajl | Sta radi |
|---|---|
| `ansible/config.yml` | redoslijed: host ruter -> dns (BIND) -> common -> firewall -> docker |
| `ansible/host.yml` | host ruter: ip_forward + nftables pravila izmedju segmenata (sudo -n nft/sysctl) |
| `ansible/host/ruter.nft.j2` | dozvoljeni tokovi web->app:8000, app->db:5432; sve ostalo drop |
| `ansible/deploy.yml` | isporuka kontejnera: llm -> db -> backend -> frontend |
| `ansible/deploy-llama.yml` | alternativa: llama.cpp umjesto vLLM |
| `ansible/ansible.cfg` | inventory, vault lozinka, ssh opcije |
| `ansible/group_vars/all/vars.yml` | domena, plan adresiranja, imena servisa |
| `ansible/group_vars/<grupa>/vars.yml` | vatrozid pravila po VM-u (fw_ulazi) + rute segmenata |
| `ansible/roles/common/` | apt paketi, rute do segmenata (idempotentno) |
| `ansible/roles/dns/` | BIND: named.conf, zona SOA/NS, TSIG kljuc, update-policy (samo zona projekt.lab) |
| `ansible/roles/firewall/` | nftables iz group_vars; politika drop; ssh samo s admina; ICMP samo admin+gatewayi |
| `ansible/roles/docker/` | docker engine + compose plugin |
| `ansible/roles/frontend/` | kopira app/frontend, docker compose up (nginx) |
| `ansible/roles/backend/` | kopira app/backend, .env s lozinkom baze iz vaulta, compose up |
| `ansible/roles/db/` | kopira app/db, .env, compose up (postgres + volume) |
| `ansible/roles/llm/` | vLLM CPU build iz izvora, model, systemd, health wait |
| `ansible/roles/llm_llama/` | alternativa: llama.cpp build (~3 min), isti API |

### Aplikacija (AO-1)
| Fajl | Sta radi |
|---|---|
| `app/frontend/nginx.conf` | servira Tetris UI, proksira /api na backend.projekt.lab:8000 |
| `app/frontend/tetris.html` | igra u browseru (pravila u JS-u) |
| `app/backend/app.py` | FastAPI: /api/potez (LLM), /api/kraj i /api/top (baza), /health, /ready |
| `app/db/init.sh` | pravi tabelu rezultati + ulogu app (najmanja prava) |
| `app/*/Dockerfile`, `app/*/compose.yaml` | slike i pokretanje kontejnera |

### Testovi i dokumentacija
| Fajl | Sta dokazuje |
|---|---|
| `tests/test_izolacija.sh` | AO-6: frontend->baza pada (TCP i ping), dozvoljeni tokovi rade |
| `tests/test_dns.sh` | AO-7: imena na adrese segmenata, SOA/NS, rekurzija, NXDOMAIN |
| `tests/test_app.sh` | AO-1, AO-10: UI radi, LLM potez, upis u bazu, podaci prezive restart kontejnera, /ready |
| `docs/adr/DO-1..DO-9.md` | dizajnerske odluke po obrascu (kontekst, opcije, odluka, posljedice) |
| `docs/predaja.pdf` | predajni dokument (ime, link, opis, DO tabela, ADR-ovi) |

## 4. Kako se svaki AO ispunjava (i gdje se provjerava)

| AO | Gdjе u kodu | Provjera |
|---|---|---|
| AO-1 troslojna app, tri kontejnera | `app/*/compose.yaml`, `app/backend/app.py` | `make test` (test_app) |
| AO-2 sve kao kod, od nule | `Makefile`, `README.md` | `make destroy && make all && make test` |
| AO-3 VM-ovi kroz Terraform, varijable, outputi | `terraform/vm/main.tf` (`variable "vm"`), `outputs.tf` | `terraform plan` |
| AO-4 cloud-init | `cloud-init/user-data.tftpl` | SSH prijava kljucem; lozinka odbijena |
| AO-5 Ansible role, idempotentno | `ansible/config.yml`, `ansible/deploy.yml`, `ansible/roles/*` | drugi `make config`/`make deploy` = 0 changed |
| AO-6 izolovani segmenti | `terraform/vm/main.tf` (mreze), `ansible/host/ruter.nft.j2`, `ansible/roles/firewall/`, `app/db/compose.yaml` (listen_addresses) | `make test` (test_izolacija) |
| AO-7 BIND zona, samo DNS imena | `ansible/roles/dns/`, `app/frontend/nginx.conf`, `app/backend/app.py` (LLM_URL, DB_HOST) | `make test` (test_dns) + pregled koda |
| AO-8 DNS zapisi kao TF resursi | `terraform/dns/main.tf` | `terraform plan` u `terraform/dns` |
| AO-9 tajne van Gita | `scripts/generate_keys.sh`, `vault.yml.example`, `.gitignore` | `git log --all --stat` (nema tajni) |
| AO-10 podaci prezive kontejner | `app/db/compose.yaml` (volume pgdata) | `make test` (test_app, korak 4) |

## 5. Dizajnerske odluke (DO) - kratki rezime (detalji u docs/adr/)

- **DO-1** Aplikacija: vlastiti Tetris + LLM (nginx / FastAPI / PostgreSQL; vLLM Qwen2.5-0.5B).
- **DO-2** Topologija: opcija B - po jedna VM za segment, libvirt route mreze, host rutira; dns i llm zasebne VM.
- **DO-3** Adresiranje: tri /24 segmenta + NAT admin ravan; staticke adrese po MAC-u; .11 po sloju, .1 gateway.
- **DO-4** Bazna slika: Ubuntu 24.04 cloud image + cloud-init (bez Packera).
- **DO-5** Kontejneri: build na ciljnoj VM (docker compose), bez registryja.
- **DO-6** Inventory: generisan iz Terraform outputa (`local_file`).
- **DO-7** Role: po komponenti; defaults za rolu, group_vars za okolis.
- **DO-8** DNS zona: jedna `projekt.lab`, TTL 300, servisni A zapisi kroz Terraform RFC 2136, TSIG samo ta zona.
- **DO-9** Tajne: ansible-vault + generisanje pri prvom pokretanju; .env na VM-u (0600), van Gita.

## 6. Pokretanje

```bash
make check     # alati
make infra     # Terraform: mreze + VM-ovi
make config    # host ruter + BIND + vatrozid + Docker
make dns       # Terraform: DNS zapisi (RFC 2136)
make deploy    # kontejneri (vLLM build ~25 min prvi put)
make test      # izolacija, DNS, aplikacija
make all       # sve redom od nule
make destroy   # uklanjanje svega
```

Jednokratno (host): `scripts/sudoers-zahtjev.txt` (sudo bez lozinke za nft, sysctl
i restart libvirt daemona). Windows: WSL2 s KVM-om i systemd-om (detalji u README).

## 7. Scenario odbrane (po PDF-u)

1. `make destroy` - prazan sistem (pokazati da nema VM-ova i zapisa).
2. `make all` - infra -> config -> dns -> deploy; objasnjavati dok radi.
3. `make test` - izolacija (frontend->baza PADA), dig upiti, aplikacija.
4. `make all` ponovo - bez promjena (idempotentnost).
5. Izmjena kroz kod, npr. novi DNS zapis: dodati u `terraform/dns/main.tf`
   (npr. `igra = "192.168.20.11"`), `make dns`, `dig igra.projekt.lab`.
6. Izmjena parametra VM-a: `terraform/vm/main.tf` (`variable "vm"`), `make infra`.

Drift demo: rucno promijeniti DNS zapis (`nsupdate`) -> `terraform plan` pokaze
razliku -> `terraform apply` vrati stanje iz koda.

## 8. Dokazi (stvarni izlazi)

- From-zero: `make destroy && make all && make test` -> `EXIT=0`, 3x "SVE PROVEDENO".
- Idempotentnost: drugo izvrsavanje `make config` i `make deploy` -> `changed=0` na svim VM-ovima.
- Drift: `terraform plan` pokazao `192.168.20.99 -> 192.168.20.11`, apply ispravio.
- LLM: vratio `{"potez":"rotiraj"}`; baza sacuvala podatke kroz restart kontejnera; `/ready` 200.

## 9. Ogranicenja (svjesno) i produkcija

- LLM je na admin/NAT ravni (interna zavisnost backenda); u produkciji u app segment.
- vLLM build iz izvora ~25 min na CPU; alternativa `make deploy-llama` (~3 min).
- Jedan DNS, jedan LLM (nema replike/sekundara); TLS nije uveden (lab).
- Host play uvijek prijavi changed (`nft -f` se primjenjuje); VM-ovi su 0 changed.

## 10. Najcesca pitanja i odgovori

- **Zasto opcija B, a ne jedna VM s Docker mrezama?** Svaki sloj dobija vlastitu
  adresu u vlastitoj podmrezi, pa AO-7 (imena po sloju) ima smisla, a izolacija se
  dokazuje na stvarnom ruteru (DO-2).
- **Zasto frontend ne vidi bazu?** Host ne propusta web->db, a vatrozid baze prima
  5432 samo iz app podmreze; baza slusa samo na segment adresi (test pingom i TCP-om).
- **Sta ako LLM padne?** `/ready` vrati 503 s razlogom "llm"; aplikacija i dalje
  radi (potez "ostani"), a balansiranje nije dio ovog zadatka (nema balansera).
- **Kako se dodaje novi sloj/servis?** Terraform (VM + mreza) -> Ansible rola ->
  DNS zapis u `terraform/dns` -> test.
