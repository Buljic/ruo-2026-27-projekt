# tests/lib.sh: zajednicke funkcije za testove (korak/tvrdi/sadrzi/zakljucak).
korak() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
info() { echo "  $*"; }
tvrdi() { local o="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  ok: $o"; else echo "  NIJE OK: $o"; GRESKE=$((GRESKE + 1)); fi; }
sadrzi() { grep -q -- "$2" <<< "$1"; }
zakljucak() {
  echo
  if [ "$GRESKE" -eq 0 ]; then printf '\033[1;32mSVE PROVEDENO (0 gresaka)\033[0m\n'; else printf '\033[1;31m%d GRESAKA\033[0m\n' "$GRESKE"; fi
  return "$GRESKE"
}
GRESKE=0
