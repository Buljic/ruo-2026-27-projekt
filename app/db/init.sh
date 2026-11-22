#!/bin/sh
# Inicijalizacija baze igra (jednom, na praznom volume-u).
# Superuser je postgres; aplikacija dobija vlastitu ulogu app (najmanja prava).
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -c "CREATE ROLE app LOGIN PASSWORD '$APP_PASSWORD';" \
  -c "CREATE TABLE rezultati (
        id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        ime     text NOT NULL,
        bodovi  integer NOT NULL CHECK (bodovi >= 0),
        vrijeme timestamptz NOT NULL DEFAULT now()
      );" \
  -c "GRANT SELECT, INSERT ON rezultati TO app;" \
  -c "GRANT USAGE ON SEQUENCE rezultati_id_seq TO app;"
