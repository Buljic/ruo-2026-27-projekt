#!/usr/bin/env bash
# Generise sve tajne projekta u .tajne/ (NIJE u Gitu). Idempotentno: postojece ne dira.
# Pokrece se automatski iz "make all", a i samostalno: bash scripts/generate_keys.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ANSIBLE_VAULT="${HOME}/Tools/ruo-ansible-venv/bin/ansible-vault"
TAJNE=".tajne"
KLJUC_VAULT="ansible/.vault_pass"

mkdir -p "$TAJNE" ansible/generated

# --- 1. SSH kljuc administratora (pristup svim VM-ovima) ---
if [ ! -f "${HOME}/.ssh/id_ed25519.pub" ]; then
  ssh-keygen -q -t ed25519 -N "" -f "${HOME}/.ssh/id_ed25519" -C "ruo-projekt"
fi

# --- 2. TSIG kljuc za zonu projekt.lab (RFC 2136, AO-8) ---
tsig() { # ime
  if command -v tsig-keygen >/dev/null 2>&1; then
    tsig-keygen "$1"
  else
    printf 'key "%s" {\n\talgorithm hmac-sha256;\n\tsecret "%s";\n};\n' "$1" "$(openssl rand -base64 32)"
  fi
}
[ -f "$TAJNE/tsig-tf.key" ] || tsig ruo-tf > "$TAJNE/tsig-tf.key"
chmod 600 "$TAJNE/tsig-tf.key"

# tajna u obliku koji terraform cita (make dns)
cat > "$TAJNE/tsig.env" <<EOF
# generisano: scripts/generate_keys.sh (nije u Gitu)
TF_TSIG_SECRET="$(grep secret "$TAJNE/tsig-tf.key" | sed 's/.*secret "\(.*\)".*/\1/')"
EOF
chmod 600 "$TAJNE/tsig.env"

# --- 3. Ansible Vault: lozinka baze i TSIG tajna ---
gen_pw() { openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24; }
[ -f "$KLJUC_VAULT" ] || openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32 > "$KLJUC_VAULT"
chmod 600 "$KLJUC_VAULT"

if [ ! -f ansible/group_vars/all/vault.yml ]; then
  TSIG_TF="$(grep secret "$TAJNE/tsig-tf.key" | sed 's/.*secret "\(.*\)".*/\1/')"
  cat > ansible/group_vars/all/vault.yml <<EOF
# Generisano. Sadrzaj je sifrovan (ansible-vault); kljuc je ansible/.vault_pass (nije u Gitu).
db_lozinka: "$(gen_pw)"
tsig_tajne:
  ruo_tf: "$TSIG_TF"
EOF
  "$ANSIBLE_VAULT" encrypt --vault-password-file "$KLJUC_VAULT" ansible/group_vars/all/vault.yml
  echo "vault.yml je kreiran i sifrovan."
fi

echo "Tajne spremne u .tajne/ (nije u Gitu)."
