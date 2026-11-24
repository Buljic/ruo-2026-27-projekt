#!/usr/bin/env bash
# tests/test_app.sh: aplikacija radi kroz slojeve; baza cuva podatke (AO-1, AO-10).
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib.sh

FRONT=192.168.111.21
APP=192.168.111.22
DB=192.168.111.14
SSH="ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
PL='{"ploca":[[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[1,1,1,0,0,0,0,1,1,1]],"komad":"T","x":4,"rotacija":0}'

korak "1. Frontend servira Tetris (javni ulaz)"
r="$(curl -s -o /dev/null -w '%{http_code}' "http://$FRONT/")"
tvrdi "GET / = 200" test "$r" = 200
tvrdi "sadrzi Tetris" bash -c "curl -s http://$FRONT/ | grep -qi tetris"

korak "2. Tok frontend -> backend -> LLM (potez)"
r="$(curl -s -m 60 -X POST "http://$FRONT/api/potez" -H 'Content-Type: application/json' -d "$PL")"
echo "  $r"
tvrdi "odgovor sadrzi potez" sadrzi "$r" '"potez"'
tvrdi "potez je iz dozvoljenog skupa" bash -c "echo '$r' | grep -qE '\"potez\": ?\"(lijevo|desno|rotiraj|pad|ostani)\"'"

korak "3. Tok frontend -> backend -> baza (rezultat se upisuje)"
r="$(curl -s -X POST "http://$FRONT/api/kraj" -H 'Content-Type: application/json' -d '{"bodovi":321,"ime":"test"}')"
echo "  $r"
tvrdi "upis u bazu prosao" sadrzi "$r" '"ok":true'
r="$(curl -s "http://$FRONT/api/top")"
echo "  $r"
tvrdi "top lista sadrzi test" sadrzi "$r" "test"

korak "4. AO-10: podaci prezive ponovno kreiranje kontejnera baze"
r="$($SSH student@$DB "cd /opt/ruo/db && sudo docker compose down >/dev/null 2>&1 && sudo docker compose up -d >/dev/null 2>&1 && sleep 4 && sudo docker exec \$(sudo docker ps -q --filter name=db) psql -U postgres -d igra -tAc 'SELECT count(*) FROM rezultati'")"
echo "  redova poslije restarta: $r"
tvrdi "podaci su ostali u volume-u" bash -c "[ '${r:-0}' -ge 1 ]"

korak "5. Backend /ready (baza + LLM)"
r="$($SSH student@$APP "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/ready")"
tvrdi "backend spreman (200)" test "$r" = 200

zakljucak
