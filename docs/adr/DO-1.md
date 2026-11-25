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
- backend: FastAPI; heuristika predlaze tri najbolja poteza, LLM bira medju njima
  (ako ne odgovori, uzima se najbolji po heuristici), rezultati idu u bazu,
- baza: PostgreSQL u kontejneru sa volume-om (rezultati igre).

## Obrazlozenje i posljedice
Vlastita aplikacija daje tri stvarna toka kroz slojeve (UI -> API -> INSERT/SELECT),
pa se svaka AO provjerava na stvarnom saobracaju. LLM je interna zavisnost backenda
(vLLM na zasebnoj VM), pa backend ima i vanjski poziv, sto je realniji scenario od
cistog CRUD-a. Posljedica: vise komponenti za odrzavanje i sporiji odgovor poteza
(CPU inference), sto je prihvatljivo za lab.
