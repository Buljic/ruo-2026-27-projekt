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
