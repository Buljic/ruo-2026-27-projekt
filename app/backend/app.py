"""RuO projekt: backend troslojne aplikacije (Tetris koji igra LLM).

Slojevi: frontend (nginx) -> backend (ovaj servis) -> baza (PostgreSQL).
Backend ne komunicira sa frontendom; prima /api zahtjeve koje je frontend proksirao,
pita LLM za potez i upisuje rezultate u bazu. Sve adrese su DNS imena (AO-7).
"""

import json
import os
import re
import socket

import httpx
import psycopg
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel

LLM_URL = os.environ.get("LLM_URL", "http://llm.projekt.lab:8000")
DB = dict(
    host=os.environ.get("DB_HOST", "baza.projekt.lab"),
    dbname=os.environ.get("DB_NAME", "igra"),
    user=os.environ.get("DB_USER", "app"),
    password=os.environ.get("DB_PASSWORD", ""),
    connect_timeout=3,
)
IME = socket.gethostname()
DOZVOLJENI = {"lijevo", "desno", "rotiraj", "pad", "ostani"}

app = FastAPI(title="RuO Tetris backend")

PROMPT = """Igras Tetris. Ploca ima 10 kolona i 20 redova (prikazano od vrha prema dnu, # = popunjeno):
{ploca}

Sljedeci komad: {komad}. Pozicija: x={x}, rotacija {rotacija}.
Izaberi JEDAN potez: lijevo, desno, rotiraj, pad, ostani.
Odgovori SAMO u JSON obliku: {{"potez": "..."}}"""


class PotezZahtjev(BaseModel):
    ploca: list[list[int]]
    komad: str = "T"
    x: int = 4
    rotacija: int = 0


class RezultatZahtjev(BaseModel):
    bodovi: int
    ime: str = "anon"


def llm_potez(ploca, komad, x, rotacija):
    """Pita LLM za potez; vraca (potez, sirovi_odgovor). Nikad ne baca iznimku."""
    redovi = [" ".join("#" if c else "." for c in red) for red in ploca]
    prompt = PROMPT.format(ploca="\n".join(redovi), komad=komad, x=x, rotacija=rotacija)
    try:
        resp = httpx.post(
            f"{LLM_URL}/v1/chat/completions",
            json={
                "model": "tetris",
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.0,
                "max_tokens": 40,
            },
            timeout=25.0,
        )
        sadrzaj = resp.json()["choices"][0]["message"]["content"]
    except Exception as e:
        return "ostani", f"LLM nedostupan: {e}"
    m = re.search(r"\{[^{}]*\}", sadrzaj, re.S)
    if m:
        try:
            potez = str(json.loads(m.group(0)).get("potez", "")).strip().lower()
            if potez in DOZVOLJENI:
                return potez, sadrzaj.strip()
        except Exception:
            pass
    return "ostani", sadrzaj.strip()[:200]


@app.post("/api/potez")
def api_potez(z: PotezZahtjev):
    potez, sirovi = llm_potez(z.ploca, z.komad, z.x, z.rotacija)
    return {"potez": potez, "llm": sirovi, "backend": IME}


@app.post("/api/kraj")
def api_kraj(z: RezultatZahtjev):
    bodovi = max(0, min(int(z.bodovi), 10_000_000))
    ime = z.ime[:40]
    try:
        with psycopg.connect(**DB) as pg:
            pg.execute("INSERT INTO rezultati (ime, bodovi) VALUES (%s, %s)", (ime, bodovi))
        return {"ok": True, "backend": IME}
    except Exception as e:
        return JSONResponse({"greska": f"baza: {e}"}, status_code=503)


@app.get("/api/top")
def api_top():
    try:
        with psycopg.connect(**DB) as pg:
            top = pg.execute(
                "SELECT ime, bodovi FROM rezultati ORDER BY bodovi DESC, id ASC LIMIT 5"
            ).fetchall()
            ukupno = pg.execute("SELECT count(*) FROM rezultati").fetchone()[0]
        return {"igara": ukupno, "top": [{"ime": i, "bodovi": int(b)} for i, b in top], "backend": IME}
    except Exception:
        return JSONResponse({"greska": "baza nedostupna"}, status_code=503)


@app.get("/health")
def health():
    return {"ok": True, "backend": IME}


@app.get("/ready")
def ready():
    # Spremnost = baza + LLM. Pad bilo kojeg = 503 (zajednicke zavisnosti backenda).
    try:
        with psycopg.connect(**DB) as pg:
            pg.execute("SELECT 1")
    except Exception:
        return JSONResponse({"spreman": False, "zasto": "baza"}, status_code=503)
    try:
        httpx.get(f"{LLM_URL}/health", timeout=2.0).raise_for_status()
    except Exception:
        return JSONResponse({"spreman": False, "zasto": "llm"}, status_code=503)
    return {"spreman": True, "backend": IME}
