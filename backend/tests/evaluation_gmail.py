"""Évaluation RÉELLE de la compréhension Gmail (phase 2), corpus FICTIF.

Pour chaque scénario de `scenarios_gmail.py` : l'outil ODO réel lit les
e-mails du faux Google (aucun vrai e-mail), puis le VRAI fournisseur (MIA)
reçoit le message système de JARVIS, les consignes d'ODO / Gmail, le
dossier enveloppé et la question. La réponse est notée avec les critères
explicites du scénario (`doit` / `interdit`). Coûteux : à lancer à la main.

  python tests/evaluation_gmail.py --fournisseur groq --etiquette apres --sortie /tmp/eval.jsonl

Débit borné (≈ 6 000 tokens / min) pour respecter la limite de GroqCloud.
Le même script tourne sur l'ancien code (comparaison avant / après).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import re
import time
from datetime import datetime, timezone

import fakeredis

from app.api.v1.chat import Ton, build_system_prompt
from app.config import get_settings
from app.integrations.gmail import ClientGmail
from app.llm import Fin, Texte
from app.llm.selection import creer
from app.odo.contrat import ContexteOutil
from app.odo.outils_gmail import CONSIGNE_GMAIL, GmailLireFil, GmailLireMessage, GmailPreparerResume
from app.odo.securite import CONSIGNE_OUTILS, envelopper
from faux_google import FauxConnexions, FauxGoogle, message, service_google
from scenarios_gmail import SCENARIOS

USER = "11111111-1111-1111-1111-111111111111"
MAINTENANT = datetime(2026, 10, 19, 9, 0, tzinfo=timezone.utc)
OUTILS = {"gmail_lire_message": GmailLireMessage, "gmail_lire_fil": GmailLireFil,
          "gmail_preparer_resume": GmailPreparerResume}
DEBIT = 6000          # tokens par minute visés


def noter(s, texte: str) -> list[str]:
    # Espaces insécables (fines) et apostrophes typographiques des modèles.
    texte = texte.replace(" ", " ").replace(" ", " ").replace("’", "'")
    raisons = [f"manque /{m}/" for m in s.doit if not re.search(m, texte, re.I | re.S)]
    raisons += [f"interdit /{m}/" for m in s.interdit if re.search(m, texte, re.I | re.S)]
    # Règle commune : réponse naturelle, jamais d'étiquettes techniques.
    if re.search(r"^\W*(?:faits?|interprétations?|déductions?|inconnu)\s*:", texte, re.I | re.M):
        raisons.append("format : étiquettes « Faits / Interprétation »")
    return raisons


async def evaluer(fournisseur: str, etiquette: str, sortie: str, seuls: list[str]) -> None:
    settings = get_settings()
    llm = creer(fournisseur, settings)
    redis = fakeredis.FakeAsyncRedis(decode_responses=True)
    faux, connexions = FauxGoogle(), FauxConnexions()
    google = service_google(settings, redis, connexions, faux)
    await connexions.enregistrer_connexion(USER, "gmail", "pepper@gmail.com",
                                           "https://www.googleapis.com/auth/gmail.readonly", "rt-google-1")
    ctx = ContexteOutil(user_id=USER, demande_id="eval", plan="free", connexions=frozenset({"gmail"}),
                        decalage_minutes=60)
    systeme = "\n\n".join([build_system_prompt(Ton.naturel, None, MAINTENANT, decalage_minutes=60),
                           CONSIGNE_OUTILS, CONSIGNE_GMAIL])
    total, reussis = 0, 0
    with open(sortie, "a", encoding="utf-8") as f:
        for s in SCENARIOS:
            if not s.llm or (seuls and s.nom not in seuls):
                continue
            faux.messages = {i: message(i, de=m["de"], objet=m["objet"], date=m["date"], texte=m["texte"],
                                        fil=m["fil"], pieces=m["pieces"], important=m["important"])
                             for i, m in s.emails.items()}
            r = await OUTILS[s.outil](ClientGmail(google)).executer(s.arguments, ctx)
            messages = [{"role": "system", "content": systeme}, *s.historique,
                        {"role": "user", "content": f"{s.question}\n\n"
                                                    f"{envelopper(s.outil, r.contenu, settings.odo_resultat_max_caracteres)}"}]
            for essai in range(3):
                debut, texte, fin = time.perf_counter(), "", None
                try:
                    async for ev in llm.flux(messages, max_sortie=900):
                        if isinstance(ev, Texte):
                            texte += ev.texte
                        elif isinstance(ev, Fin):
                            fin = ev
                    break
                except Exception as exc:                 # noqa: BLE001 : limite de débit → on attend
                    print(f"  {s.nom} : {type(exc).__name__} {getattr(exc, 'code', '')}, nouvel essai dans 60 s")
                    await asyncio.sleep(60)
            ms = int((time.perf_counter() - debut) * 1000)
            tokens = fin.usage.total if fin else 0
            raisons = noter(s, texte)
            total += 1
            reussis += not raisons
            ligne = {"etiquette": etiquette, "fournisseur": fournisseur, "scenario": s.nom, "ok": not raisons,
                     "raisons": raisons, "ms": ms, "tokens": tokens, "entree": fin.usage.entree_totale if fin else 0,
                     "dossier_caracteres": len(r.contenu), "reponse": texte}
            f.write(json.dumps(ligne, ensure_ascii=False) + "\n")
            f.flush()
            print(f"{'OK ' if not raisons else 'KO '} {s.nom:32} {ms:6d} ms {tokens:6d} tok  {'; '.join(raisons)}")
            await asyncio.sleep(max(2.0, tokens / DEBIT * 60 - ms / 1000))
    print(f"\n{etiquette} / {fournisseur} : {reussis}/{total} réussis")


def renoter(fichier: str) -> None:
    """Note de nouveau des réponses enregistrées avec les critères actuels
    (aucun appel au fournisseur)."""
    par_nom = {s.nom: s for s in SCENARIOS}
    lignes = [json.loads(l) for l in open(fichier, encoding="utf-8")]
    ok = 0
    for d in lignes:
        raisons = noter(par_nom[d["scenario"]], d["reponse"])
        ok += not raisons
        print(f"{'OK ' if not raisons else 'KO '} {d['scenario']:32} {'; '.join(raisons)}")
    print(f"{lignes[0]['etiquette']} (renoté) : {ok}/{len(lignes)} réussis")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--fournisseur", default="groq")
    p.add_argument("--etiquette", default="apres")
    p.add_argument("--sortie", default="/tmp/evaluation_gmail.jsonl")
    p.add_argument("--seuls", nargs="*", default=[])
    p.add_argument("--renoter", help="fichier .jsonl déjà produit : nouvelle notation, sans appel")
    a = p.parse_args()
    if a.renoter:
        renoter(a.renoter)
    else:
        asyncio.run(evaluer(a.fournisseur, a.etiquette, a.sortie, a.seuls))
