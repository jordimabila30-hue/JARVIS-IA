"""Banc de bout en bout Gmail (phase 3) : vraie route de chat, ODO et VRAIS
appels d'outils du fournisseur, sur une boîte FICTIVE (`scenarios_resumes`).

Rien de réel côté utilisateur : faux Google (requêtes réellement évaluées),
faux Supabase, Redis simulé, jeton de test. Seul le fournisseur IA est réel
(GroqCloud par défaut ; jamais Claude sans accord). Mesures relevées dans le
journal `ODO fin` (tours, appels, tokens d'entrée / sortie, requêtes Gmail,
durée) ; réponse notée avec les critères du scénario.

  python tests/banc_gmail.py --etiquette avant --sortie /sortie/avant.jsonl
  python tests/banc_gmail.py --renoter /sortie/avant.jsonl

Débit borné (≈ 6 000 tokens / min) pour la limite de GroqCloud.
"""

from __future__ import annotations

import os

# Configuration de TEST (jamais la base ni les comptes réels) ; seule la clé
# du fournisseur IA vient de l'environnement.
os.environ.update({"SUPABASE_URL": "https://test-project.supabase.co", "SUPABASE_SERVICE_ROLE_KEY": "service-role-test",
                   "SUPABASE_JWT_SECRET": "test-secret-with-at-least-32-characters!!", "ABONNEMENTS_ROUTAGE": "false",
                   "ODO_ACTIF": "true", "ENVIRONNEMENT": "development", "GOOGLE_CLIENT_ID": "", "GOOGLE_CLIENT_SECRET": "",
                   "GOOGLE_REDIRECT_URI": ""})

import argparse  # noqa: E402
import asyncio  # noqa: E402
import json  # noqa: E402
import logging  # noqa: E402
import re  # noqa: E402
import time  # noqa: E402
import uuid  # noqa: E402

import fakeredis  # noqa: E402
import httpx  # noqa: E402
import jwt  # noqa: E402
from fastapi import FastAPI  # noqa: E402

from app.api.v1 import chat  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.integrations.google import PORTEE_GMAIL, get_google  # noqa: E402
from app.llm.selection import creer  # noqa: E402
from app.odo.service import ServiceODO, get_odo  # noqa: E402
from app.quota import QuotaService, get_quota_service  # noqa: E402
from app.redis_client import get_redis  # noqa: E402
from app.supabase_client import UserLimits, get_supabase  # noqa: E402
from faux_google import FauxConnexions, FauxGoogle, message, service_google  # noqa: E402
from scenarios_resumes import BOITE, DEMANDES, ETIQUETTES  # noqa: E402
from test_chat import FakeSupabase  # noqa: E402

USER = "11111111-1111-1111-1111-111111111111"
DEBIT = 6000


class SupabaseBanc(FakeSupabase):
    """Une conversation neuve par demande (identifiants distincts)."""

    def __init__(self):
        super().__init__(limits=UserLimits("free", 10_000, 50_000_000))
        self.conversations: dict[str, dict] = {}

    async def get_conversation(self, conversation_id, user_id):
        return self.conversations.get(conversation_id) if user_id == USER else None

    async def create_conversation(self, user_id, title):
        c = {"id": str(uuid.uuid4()), "title": title, "persona": None}
        self.conversations[c["id"]] = c
        return c

    async def get_recent_messages(self, conversation_id, limit):
        return []

    async def increment_llm_usage(self, *args, **kwargs):
        return None


class Journal(logging.Handler):
    def __init__(self):
        super().__init__(logging.INFO)
        self.lignes: list[str] = []

    def emit(self, record):
        self.lignes.append(record.getMessage())


def jeton(settings) -> dict:
    t = jwt.encode({"sub": USER, "role": "authenticated", "aud": "authenticated", "iss": settings.supabase_issuer,
                    "exp": int(time.time()) + 3600}, settings.supabase_jwt_secret, algorithm="HS256")
    return {"Authorization": f"Bearer {t}"}


def mesures(lignes: list[str]) -> dict:
    fin = next((l for l in reversed(lignes) if l.startswith("ODO fin")), "")
    valeurs = dict(re.findall(r"(\w+)=(\S+)", fin))
    entiers = {k: int(v) for k, v in valeurs.items() if v.isdigit()}
    return {"tours": entiers.get("tours", 0), "appels": entiers.get("appels", 0),
            "entree": entiers.get("entree", 0), "sortie": entiers.get("sortie", 0),
            "requetes_gmail": entiers.get("requetes_gmail", 0), "duree_ms": entiers.get("duree_ms", 0),
            "premier_outil_ms": entiers.get("premier_outil_ms", 0),
            "outils": [re.search(r"outil=(\S+)", l).group(1) for l in lignes if l.startswith("ODO execution")]}


def noter(d, texte: str) -> list[str]:
    texte = texte.replace(" ", " ").replace(" ", " ").replace("’", "'")
    raisons = [f"manque /{m}/" for m in d.doit if not re.search(m, texte, re.I | re.S)]
    raisons += [f"interdit /{m}/" for m in d.interdit if re.search(m, texte, re.I | re.S)]
    if re.search(ETIQUETTES, texte, re.I | re.M):
        raisons.append("format : rubriques « Faits / Interprétation »")
    mots = len(texte.split())
    if d.mots_max and mots > d.mots_max:
        raisons.append(f"trop long : {mots} mots > {d.mots_max}")
    if not texte.strip():
        raisons.append("réponse vide")
    return raisons


def lire_sse(brut: str) -> tuple[str, str | None, str | None]:
    texte, conversation, erreur = "", None, None
    for bloc in brut.split("\n\n"):
        ev = re.search(r"^event: (\w+)", bloc, re.M)
        data = re.search(r"^data: (.*)$", bloc, re.M)
        if not ev or not data:
            continue
        d = json.loads(data.group(1))
        if ev.group(1) == "delta":
            texte += d.get("text", "")
        elif ev.group(1) == "meta":
            conversation = d.get("conversation_id")
        elif ev.group(1) == "error":
            erreur = d.get("code") or str(d)[:120]
    return texte, conversation, erreur


async def banc(fournisseur: str, etiquette: str, sortie: str, seuls: list[str]) -> None:
    settings = get_settings()
    journal = Journal()
    logging.getLogger("app.odo").addHandler(journal)
    logging.getLogger("app.odo").setLevel(logging.INFO)
    redis = fakeredis.FakeAsyncRedis(decode_responses=True)
    faux, connexions = FauxGoogle(), FauxConnexions()
    faux.filtrer = True
    faux.messages = {i: message(i, de=x["de"], objet=x["objet"], date=x["date"], texte=x["texte"], fil=x["fil"],
                                pieces=x["pieces"], important=x["important"]) for i, x in BOITE.items()}
    await connexions.enregistrer_connexion(USER, "gmail", "pepper@gmail.com", PORTEE_GMAIL, "rt-google-1")
    google = service_google(settings, redis, connexions, faux)
    supa = SupabaseBanc()
    llm = creer(fournisseur, settings)
    app = FastAPI()
    app.include_router(chat.router, prefix="/api/v1")
    app.dependency_overrides.update({
        get_google: lambda: google, get_quota_service: lambda: QuotaService(redis, supa),
        get_supabase: lambda: supa, get_redis: lambda: redis, chat.get_fournisseur: lambda: llm,
        get_odo: lambda: ServiceODO(settings, redis, google=google)})
    client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test", timeout=180)
    conversations: dict[str, str] = {}
    ok = total = 0
    with open(sortie, "a", encoding="utf-8") as f:
        for d in DEMANDES:
            if seuls and d.nom not in seuls:
                continue
            corps = {"message": d.texte, "fuseau_minutes": 60}
            if d.suite_de and d.suite_de in conversations:
                corps["conversation_id"] = conversations[d.suite_de]
            for essai in range(3):
                journal.lignes.clear()
                gmail_avant = len(faux.gmail)
                debut = time.perf_counter()
                r = await client.post("/api/v1/chat/stream", json=corps, headers=jeton(settings))
                await chat.wait_background_tasks()
                texte, conversation, erreur = lire_sse(r.text)
                if erreur not in ("llm_rate_limit", "llm_unavailable"):
                    break
                print(f"  {d.nom} : {erreur}, nouvel essai dans 60 s")
                await asyncio.sleep(60)
            total_ms = int((time.perf_counter() - debut) * 1000)
            conversations[d.nom] = conversation
            m = mesures(journal.lignes)
            m["requetes_gmail_http"] = len(faux.gmail) - gmail_avant
            raisons = noter(d, texte) + ([f"erreur {erreur}"] if erreur else [])
            total += 1
            ok += not raisons
            ligne = {"etiquette": etiquette, "fournisseur": fournisseur, "demande": d.nom, "ok": not raisons,
                     "raisons": raisons, "total_ms": total_ms, "mots": len(texte.split()), **m, "reponse": texte}
            f.write(json.dumps(ligne, ensure_ascii=False) + "\n")
            f.flush()
            jetons = m["entree"] + m["sortie"]
            print(f"{'OK ' if not raisons else 'KO '} {d.nom:26} {total_ms:6d} ms {jetons:6d} tok "
                  f"tours={m['tours']} gmail={m['requetes_gmail_http']} mots={len(texte.split())}  {'; '.join(raisons)}")
            await asyncio.sleep(max(3.0, jetons / DEBIT * 60 - total_ms / 1000))
    await client.aclose()
    print(f"\n{etiquette} / {fournisseur} : {ok}/{total} réussis")


def renoter(fichier: str) -> None:
    par_nom = {d.nom: d for d in DEMANDES}
    lignes = [json.loads(l) for l in open(fichier, encoding="utf-8")]
    ok = 0
    for x in lignes:
        raisons = noter(par_nom[x["demande"]], x["reponse"]) + [r for r in x["raisons"] if r.startswith("erreur")]
        ok += not raisons
        print(f"{'OK ' if not raisons else 'KO '} {x['demande']:26} {'; '.join(raisons)}")
    print(f"{lignes[0]['etiquette']} (renoté) : {ok}/{len(lignes)} réussis")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--fournisseur", default="groq")
    p.add_argument("--etiquette", default="essai")
    p.add_argument("--sortie", default="/tmp/banc_gmail.jsonl")
    p.add_argument("--seuls", nargs="*", default=[])
    p.add_argument("--renoter")
    a = p.parse_args()
    if a.renoter:
        renoter(a.renoter)
    else:
        asyncio.run(banc(a.fournisseur, a.etiquette, a.sortie, a.seuls))
