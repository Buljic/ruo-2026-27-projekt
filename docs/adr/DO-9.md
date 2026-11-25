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
