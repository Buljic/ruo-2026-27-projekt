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
