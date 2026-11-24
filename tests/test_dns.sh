#!/usr/bin/env bash
# tests/test_dns.sh: dokaz AO-7. Servisna imena razrjesava nas BIND, na adrese segmenata.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib.sh

DNS=192.168.111.11

korak "1. Autoritativni odgovor za projekt.lab"
r="$(dig +short @$DNS projekt.lab SOA)"
echo "  $r"
tvrdi "SOA vraca ns1.projekt.lab" sadrzi "$r" "ns1.projekt.lab"

korak "2. Servisna imena (Terraform zapisi) na adrese segmenata"
for par in "frontend 192.168.10.11" "backend 192.168.20.11" "baza 192.168.30.11" "llm 192.168.111.23"; do
  set -- $par
  r="$(dig +short @$DNS "$1.projekt.lab" A)"
  tvrdi "$1.projekt.lab -> $2" test "$r" = "$2"
done

korak "3. NS zapis"
r="$(dig +short @$DNS projekt.lab NS | head -1)"
tvrdi "NS je ns1.projekt.lab" test "$r" = "ns1.projekt.lab."

korak "4. Rekurzija za lab mrezu (vanjska imena)"
r="$(dig +short @$DNS example.com A | head -1)"
tvrdi "example.com se razrjesava" test -n "$r"

korak "5. Negativno: nepostojece ime"
r="$(dig @$DNS nepostoji.projekt.lab 2>&1 | grep -c NXDOMAIN)"
tvrdi "NXDOMAIN za nepoznato ime" test "$r" -ge 1

zakljucak
