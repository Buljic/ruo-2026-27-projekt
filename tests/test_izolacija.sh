#!/usr/bin/env bash
# tests/test_izolacija.sh: dokaz AO-6. Frontend (web segment) NE smije doci do baze;
# backend smije; baza nema porta na NAT ravni.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib.sh

SSH="ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
WEB=192.168.111.21
APP=192.168.111.22
DB=192.168.111.14

provjeri() { # izvor opis host port ocekivano
  local src="$1" opis="$2" host="$3" port="$4" ocek="$5" r
  r="$($SSH student@"$src" "timeout 5 bash -c '</dev/tcp/$host/$port' 2>/dev/null && echo OPEN || echo CLOSED")"
  if [ "$r" = "$ocek" ]; then echo "  ok: $opis ($r)"; else echo "  NIJE OK: $opis ($r, ocekivano $ocek)"; GRESKE=$((GRESKE + 1)); fi
}

korak "1. Izolacija: frontend NE vidi bazu (AO-6)"
provjeri $WEB "frontend -> baza.projekt.lab:5432 (segment)" 192.168.30.11 5432 CLOSED
provjeri $WEB "frontend -> db NAT adresa:5432" $DB 5432 CLOSED

korak "2. Dozvoljeni tok: frontend -> backend"
provjeri $WEB "frontend -> backend.projekt.lab:8000" 192.168.20.11 8000 OPEN

korak "3. Dozvoljeni tok: backend -> baza"
provjeri $APP "backend -> baza.projekt.lab:5432" 192.168.30.11 5432 OPEN

korak "4. Admin/NAT ravan je zaštićena: web ne može ni pingom do db"
r="$($SSH student@$WEB "ping -c1 -W2 $DB >/dev/null 2>&1 && echo PROLAZI || echo PADA")"
tvrdi "web -> db NAT ping odbijen" test "$r" = "PADA"

korak "4b. Baza ne prima iz web segmenta ni s NAT ravni"
provjeri $WEB "frontend -> baza (ponovno, drugi put)" 192.168.30.11 5432 CLOSED
provjeri $APP "backend -> db NAT adresa:5432 (nema porta izvana)" $DB 5432 CLOSED

korak "5. Backend nije javno dostupan"
provjeri $WEB "frontend -> app NAT adresa:8000 (samo segment)" $APP 8000 CLOSED

zakljucak
