"""RuO projekt: backend troslojne aplikacije (Tetris koji igra LLM).

Slojevi: frontend (nginx) -> backend (ovaj servis) -> baza (PostgreSQL).
Backend ne komunicira sa frontendom; prima /api zahtjeve koje je frontend proksirao,
pita LLM za potez i upisuje rezultate u bazu. Sve adrese su DNS imena (AO-7).
"""

import json
import os
import re
import socket
from typing import Union

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
    # ploca moze imati 0/1 ili slova figura (frontend salje 0/1; primamo i slova)
    ploca: list[list[Union[int, str]]]
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


Obl = {
    "I": [[1, 1, 1, 1]],
    "O": [[1, 1], [1, 1]],
    "T": [[0, 1, 0], [1, 1, 1]],
    "S": [[0, 1, 1], [1, 1, 0]],
    "Z": [[1, 1, 0], [0, 1, 1]],
    "J": [[1, 0, 0], [1, 1, 1]],
    "L": [[0, 0, 1], [1, 1, 1]],
}


def _rot(o):
    return [list(r) for r in zip(*o[::-1])]


def _oblik(komad, rotacija):
    o = Obl.get(komad.upper(), Obl["T"])
    for _ in range(rotacija % 4):
        o = _rot(o)
    return o


def _slobodno(ploca, o, px, py):
    for r, red in enumerate(o):
        for c, v in enumerate(red):
            if not v:
                continue
            nx, ny = px + c, py + r
            if nx < 0 or nx >= 10 or ny >= 20:
                return False
            if ny >= 0 and ploca[ny][nx]:
                return False
    return True


def _spusti(ploca, komad, rotacija, kolona):
    """Vrati (nova_ploca, ocisceno_redova) ako je postavljanje legalno, inace None."""
    o = _oblik(komad, rotacija)
    if not _slobodno(ploca, o, kolona, 0):
        return None
    y = 0
    while _slobodno(ploca, o, kolona, y + 1):
        y += 1
    nova = [list(r) for r in ploca]
    for r, red in enumerate(o):
        for c, v in enumerate(red):
            if v:
                nova[y + r][kolona + c] = 1
    ocisceno = sum(1 for red in nova if all(red))
    if ocisceno:
        nova = [red for red in nova if not all(red)]
        while len(nova) < 20:
            nova.insert(0, [0] * 10)
    return nova, ocisceno


def _ocjena(nova, ocisceno):
    """Klasicna heuristika: kazni visinu, rupe i neravninu; nagradi linije."""
    visine = []
    rupe = 0
    for c in range(10):
        h = 0
        for r in range(20):
            if nova[r][c]:
                h = 20 - r
                break
        visine.append(h)
        stupac = [nova[r][c] for r in range(20)]
        prvi = next((i for i, v in enumerate(stupac) if v), 20)
        rupe += sum(1 for v in stupac[prvi:] if not v)
    neravnina = sum(abs(visine[i] - visine[i + 1]) for i in range(9))
    return -0.51 * sum(visine) - 0.36 * rupe + 0.76 * ocisceno - 0.18 * neravnina


def _kandidati(ploca, komad, limit=3):
    """Najbolja (rotacija, kolona) rjesenja po heuristici."""
    ploca01 = [[1 if v else 0 for v in red] for red in ploca]
    vidjeno = set()
    opcije = []
    for rotacija in range(4):
        o = tuple(tuple(r) for r in _oblik(komad, rotacija))
        if o in vidjeno:
            continue
        vidjeno.add(o)
        for kolona in range(10):
            rez = _spusti(ploca01, komad, rotacija, kolona)
            if rez is None:
                continue
            opcije.append((_ocjena(*rez), rotacija, kolona))
    opcije.sort(reverse=True)
    return opcije[:limit]


def _sljedeci_potez(komad, x, rotacija, rotacija_cilj, kolona_cilj):
    """Jedan potez prema ciljnoj rotaciji i koloni."""
    if rotacija != rotacija_cilj:
        return "rotiraj"
    if x < kolona_cilj:
        return "desno"
    if x > kolona_cilj:
        return "lijevo"
    return "pad"


@app.post("/api/plan")
def api_plan(z: PotezZahtjev):
    # Cilj za JEDNU figuru: (rotacija, kolona). Frontend izvrsava plan korak po
    # korak, pa nema zahtjeva u letu i nema pogresne figure.
    kandidati = _kandidati(z.ploca, z.komad)
    if not kandidati:
        return {"cilj_rotacija": z.rotacija % 4, "cilj_kolona": z.x,
                "izvor": "nema legalnog poteza", "llm": "nema", "kandidati": 0, "backend": IME}
    opis = "; ".join(f"{chr(65 + i)}: rotacija {r}, kolona {k}" for i, (_, r, k) in enumerate(kandidati))
    _, r0, k0 = kandidati[0]
    sirovi = "(LLM nije upitan)"
    izvor = "heuristika"
    try:
        resp = httpx.post(
            f"{LLM_URL}/v1/chat/completions",
            json={
                "model": "tetris",
                "messages": [{"role": "user", "content": (
                    "Igraceva ploca u Tetrisu, bira se najbolji potez. "
                    f"Kandidati: {opis}. Izaberi JEDAN i odgovori SAMO JSON: "
                    '{"izbor": "A"}')}],
                "temperature": 0.0,
                "max_tokens": 20,
            },
            timeout=8.0,
        )
        sirovi = resp.json()["choices"][0]["message"]["content"].strip()[:120]
        m = re.search(r'"izbor"\s*:\s*"([ABCabc])"', sirovi)
        if m:
            idx = "ABC".index(m.group(1).upper())
            if idx < len(kandidati):
                _, r0, k0 = kandidati[idx]
                izvor = "llm"
    except Exception:
        pass
    return {"cilj_rotacija": r0, "cilj_kolona": k0, "izvor": izvor,
            "llm": sirovi, "kandidati": len(kandidati), "backend": IME}


@app.post("/api/potez")
def api_potez(z: PotezZahtjev):
    # Heuristika predlaze 3 najbolja poteza; LLM bira medju njima (ako pogrijesi
    # ili je nedostupan, uzima se najbolji po heuristici). Pravila ostaju u kodu.
    kandidati = _kandidati(z.ploca, z.komad)
    if not kandidati:
        return {"potez": "pad", "llm": "nema legalnog poteza", "izvor": "heuristika",
                "kandidati": 0, "backend": IME}
    opis = "; ".join(
        f"{chr(65 + i)}: rotacija {r}, kolona {k}" for i, (_, r, k) in enumerate(kandidati)
    )
    _, r0, k0 = kandidati[0]
    sirovi = "(LLM nije upitan)"
    izvor = "heuristika"
    try:
        resp = httpx.post(
            f"{LLM_URL}/v1/chat/completions",
            json={
                "model": "tetris",
                "messages": [{
                    "role": "user",
                    "content": (
                        "Igraceva ploca u Tetrisu, bira se najbolji potez. "
                        f"Kandidati: {opis}. Izaberi JEDAN i odgovori SAMO JSON: "
                        '{"izbor": "A"}'
                    ),
                }],
                "temperature": 0.0,
                "max_tokens": 20,
            },
            timeout=8.0,
        )
        sirovi = resp.json()["choices"][0]["message"]["content"].strip()[:120]
        m = re.search(r'"izbor"\s*:\s*"([ABCabc])"', sirovi)
        if m:
            idx = "ABC".index(m.group(1).upper())
            if idx < len(kandidati):
                _, r0, k0 = kandidati[idx]
                izvor = "llm"
    except Exception:
        pass
    potez = _sljedeci_potez(z.komad, z.x, z.rotacija, r0, k0)
    return {"potez": potez, "llm": sirovi, "izvor": izvor,
            "kandidati": len(kandidati), "backend": IME}


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
