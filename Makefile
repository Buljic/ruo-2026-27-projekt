# RuO 2026/27 - Projektni zadatak: troslojna aplikacija kao kod.
# Tok: make all (infra -> config -> dns -> deploy), pa make test.
# Prefiks naredbi je ">" (ne tabulator): GNU make 3.82+.

.RECIPEPREFIX := >
SHELL := /bin/bash
ANSIBLE_PLAYBOOK := $(HOME)/Tools/ruo-ansible-venv/bin/ansible-playbook
TF := terraform

.DEFAULT_GOAL := help
.PHONY: help check keys infra config dns deploy deploy-llama test all destroy

help: ## prikazuje ciljeve
> @grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-10s %s\n", $$1, $$2}'

check: ## provjera alata (terraform, ansible, ssh, dig, curl, docker)
> @for t in $(TF) ssh dig curl python3; do command -v $$t >/dev/null 2>&1 && echo "$$t: ok" || echo "$$t: NEDOSTAJE"; done; \
> $(ANSIBLE_PLAYBOOK) --version >/dev/null 2>&1 && echo "ansible: ok" || echo "ansible: NEDOSTAJE"

keys: ## generise SSH kljuc, TSIG kljuc i vault (sve u .tajne, nije u Gitu)
> bash scripts/generate_keys.sh

infra: keys ## Terraform: kreira VM-ove i mreze (AO-3)
> cd terraform/vm && $(TF) init -input=false && $(TF) apply -auto-approve

config: ## Ansible: host ruter, osnovna konfiguracija, BIND, vatrozid, Docker (AO-5)
> cd ansible && $(ANSIBLE_PLAYBOOK) -i localhost, -c local host.yml
> cd ansible && $(ANSIBLE_PLAYBOOK) -i inventory.ini config.yml

dns: ## Terraform: DNS zapisi servisa kroz RFC 2136 (AO-8)
> @set -a; source .tajne/tsig.env; set +a; \
> cd terraform/dns && $(TF) init -input=false >/dev/null && \
> TF_VAR_tsig_secret="$$TF_TSIG_SECRET" $(TF) apply -auto-approve

deploy: ## Ansible: isporuka i pokretanje kontejnera (AO-1)
> cd ansible && $(ANSIBLE_PLAYBOOK) -i inventory.ini deploy.yml

deploy-llama: ## alternativa za slab laptop: llama.cpp umjesto vLLM (CPU, ~3 min)
> cd ansible && $(ANSIBLE_PLAYBOOK) -i inventory.ini deploy-llama.yml

test: ## izolacija (AO-6), dig upiti (AO-7), aplikacija (AO-1, AO-10)
> bash tests/test_izolacija.sh
> bash tests/test_dns.sh
> bash tests/test_app.sh

all: infra config dns deploy ## svi koraci redom, od praznog sistema do aplikacije

destroy: ## uklanjanje svega sto je projekat kreirao (AO-2)
> cd terraform/vm && $(TF) destroy -auto-approve
> rm -rf terraform/dns/.terraform terraform/dns/terraform.tfstate*
> @for ip in 11 14 21 22 23; do ssh-keygen -R 192.168.111.$$ip >/dev/null 2>&1 || true; done
