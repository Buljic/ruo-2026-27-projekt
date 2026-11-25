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
