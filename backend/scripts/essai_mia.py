"""Essais RÉELS de MIA universel (phase 2) contre une instance de TEST.

FACTURABLE (Claude) : à lancer à la main, après accord. Jamais contre la
production. Le mot de passe est demandé au clavier (jamais stocké) ; aucune
clé n'est lue, affichée ni écrite par ce script (le serveur lit la sienne
dans .env). Données WhatsApp : conversation FICTIVE de tests_whatsapp/.

Depuis le conteneur de test (dépôt monté sur /repo) :
  docker exec -it jarvis-api-mia python /repo/backend/scripts/essai_mia.py

Scénarios : 1 conversation, 2 streaming, 3 WhatsApp + JSON, 4 Reprendre,
5 erreurs, 6 modèle enregistré, 7 comparaison GroqCloud (si autorisée).
"""

import argparse
import asyncio
import getpass
import json
import re
import sys
import time
import zipfile
from datetime import datetime
from pathlib import Path
from uuid import uuid4

import httpx

sys.path.insert(0, "/app")

from app.config import get_settings  # noqa: E402
from app.supabase_client import SupabaseAdmin  # noqa: E402
from scripts.smoke_test import sign_in  # noqa: E402

ZIP = Path("/repo/tests_whatsapp/JARVIS_TEST_SENTIMENTAL.zip")
_LIGNE = re.compile(r"^(\d{2}/\d{2}/\d{4} \d{2}:\d{2}) - (?:([^:]+): )?(.*)$")
resultats: list[tuple[str, bool, str]] = []


def noter(nom: str, ok: bool, detail: str = "") -> None:
    resultats.append((nom, ok, detail))
    print(f"   {'OK ' if ok else 'ÉCHEC'} {nom}{' — ' + detail if detail else ''}")


async def flux(client: httpx.AsyncClient, corps: dict, entetes: dict | None = None) -> dict:
    """Un échange SSE : événements, texte, délais, en-têtes."""
    debut = time.perf_counter()
    out = {"evenements": [], "texte": "", "premier": None, "statut": None, "entetes": {}, "corps": None}
    async with client.stream("POST", "/api/v1/chat/stream", json=corps, headers=entetes or {}) as r:
        out["statut"], out["entetes"] = r.status_code, dict(r.headers)
        if r.status_code != 200:
            out["corps"] = json.loads(await r.aread() or b"{}")
            return out
        evenement = None
        async for ligne in r.aiter_lines():
            if ligne.startswith("event:"):
                evenement = ligne[6:].strip()
            elif ligne.startswith("data:") and evenement:
                donnees = json.loads(ligne[5:])
                out["evenements"].append((evenement, donnees))
                if evenement == "delta":
                    out["premier"] = out["premier"] or time.perf_counter() - debut
                    out["texte"] += donnees["text"]
    out["duree"] = time.perf_counter() - debut
    return out


def noms(r: dict) -> list[str]:
    return [e for e, _ in r["evenements"]]


def donnees(r: dict, nom: str) -> dict | None:
    return next((d for e, d in r["evenements"] if e == nom), None)


def messages_zip() -> list[dict]:
    with zipfile.ZipFile(ZIP) as z:
        texte = z.read(z.namelist()[0]).decode("utf-8")
    out = []
    for i, ligne in enumerate(texte.splitlines()):
        m = _LIGNE.match(ligne)
        if not m:
            continue
        auteur = m.group(2)
        out.append({"message_order": len(out), "source_order": i, "author": auteur, "content": m.group(3),
                    "kind": "text" if auteur else "system",
                    "sent_at": datetime.strptime(m.group(1), "%d/%m/%Y %H:%M").isoformat(),
                    "sent_at_raw": m.group(1)})
    return out


async def reprendre(client: httpx.AsyncClient, conversation: str, message: str) -> None:
    """Scénario 4. La réponse est enregistrée en tâche de fond, juste APRÈS
    `done` : dans l'appli, l'appui sur « Reprendre » vient bien plus tard ;
    ici on attend qu'elle existe (404 → nouvel essai)."""
    print("\n=== 4. Reprendre")
    url = f"/api/v1/conversations/{conversation}/messages/{message}/propositions/completer"
    for _ in range(5):
        await asyncio.sleep(2)
        debut = time.perf_counter()
        rep = await client.post(url)
        if rep.status_code != 404:
            break
    p4 = rep.json().get("propositions", {}) if rep.status_code == 200 else {}
    noter("Reprendre", rep.status_code == 200 and p4.get("statut") == "complet",
          f"HTTP {rep.status_code}, statut={p4.get('statut')}, {time.perf_counter() - debut:.1f} s, "
          f"tons={[t['nom'] for t in p4.get('tons', [])]}")
    if p4.get("tons"):
        t = p4["tons"][0]
        for x in t["propositions"][:3]:
            print(f"   [{t['nom']} · {x['longueur']}] {x['texte']}")


async def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--api", default="http://localhost:8000")
    p.add_argument("--email", help="demandé au clavier si absent")
    p.add_argument("--sans-groq", action="store_true", help="ne pas faire la comparaison GroqCloud")
    p.add_argument("--reprise", nargs=2, metavar=("CONVERSATION", "MESSAGE"),
                   help="seulement « Reprendre » sur un ensemble existant, puis la comparaison")
    args = p.parse_args()
    settings = get_settings()
    supa = SupabaseAdmin(settings.supabase_url, settings.supabase_service_role_key)
    email = args.email or input("E-mail de votre compte JARVIS : ").strip()
    jeton = await sign_in(settings, settings.supabase_publishable_key, email,
                          getpass.getpass("Mot de passe : "))
    client = httpx.AsyncClient(base_url=args.api, timeout=180, headers={"Authorization": f"Bearer {jeton}"})
    try:
        compte = (await client.get("/me")).json()["id"]
        if args.reprise:
            await reprendre(client, *args.reprise)
        else:
            await scenarios_1_a_6(client, supa, compte)
        if not args.sans_groq:
            await comparaison(client)
    finally:
        await client.aclose()
        await supa.aclose()
    echecs = [n for n, ok, _ in resultats if not ok]
    print(f"\n{len(resultats) - len(echecs)}/{len(resultats)} vérifications réussies" +
          (f" ; échecs : {', '.join(echecs)}" if echecs else ""))
    print(f"Compte : {compte}")
    return 1 if echecs else 0


async def scenarios_1_a_6(client: httpx.AsyncClient, supa: SupabaseAdmin, compte: str) -> None:
    if True:      # (indentation conservée : scénarios 1 à 6, enchaînés)
        print("\n=== 1-2. Conversation normale et streaming (Claude)")
        r = await flux(client, {"message": "Bonjour JARVIS. En deux phrases : à quoi sers-tu ?"})
        noter("SSE meta → delta → done", noms(r)[0] == "meta" and noms(r)[-1] == "done" and "delta" in noms(r),
              f"{noms(r).count('delta')} fragment(s)")
        noter("fournisseur anthropic", r["entetes"].get("x-jarvis-fournisseur") == "anthropic")
        noter("premier fragment", r["premier"] is not None,
              f"{r['premier']:.1f} s, total {r['duree']:.1f} s" if r["premier"] else "")
        print("   RÉPONSE :", r["texte"][:300])
        conv = donnees(r, "meta")["conversation_id"]
        r2 = await flux(client, {"message": "Répète ta première phrase mot pour mot.", "conversation_id": conv})
        noter("historique (Redis / Supabase)", noms(r2)[-1] == "done", r2["texte"][:120])
        usage = (donnees(r2, "done") or {}).get("usage", {})
        noter("tokens comptés", usage.get("total_tokens", 0) > 0, json.dumps(usage))

        print("\n=== 6. Modèle enregistré")
        await asyncio.sleep(2)          # enregistrement en tâche de fond
        brut = await supa._http.get("/messages", params={
            "conversation_id": f"eq.{conv}", "user_id": f"eq.{compte}", "select": "role,model"})
        modeles = {l.get("model") for l in brut.json() if l["role"] == "assistant"}
        noter("messages.model = modèle Claude servi", bool(modeles) and all(m and m.startswith("claude") for m in modeles),
              ", ".join(sorted(m or "?" for m in modeles)))

        print("\n=== 3. WhatsApp (conversation FICTIVE) : analyse + propositions JSON")
        msgs = messages_zip()
        conversation_wa, consigne = str(uuid4()), str(uuid4())
        rep = await client.post("/api/v1/conversations/contexts", json={
            "context_id": str(uuid4()), "message_id": consigne, "conversation_id": None,
            "instruction": "Aide-moi à répondre à Lina.",
            "context": {"contact_name": "Lina Moreau", "current_user_name": "Alex Martin",
                        "participants": ["Alex Martin", "Lina Moreau"]},
            "messages": msgs,
        })
        noter("pièce jointe enregistrée", rep.status_code == 201, f"{len(msgs)} messages")
        conversation_wa = rep.json()["conversation_id"]
        r3 = await flux(client, {"message": "Aide-moi à répondre à Lina.", "conversation_id": conversation_wa,
                                 "reply_to": consigne, "whatsapp_analysis": "allowed"})
        props = donnees(r3, "propositions") or {}
        noter("réponse terminée", noms(r3)[-1] == "done", f"{r3['duree']:.1f} s")
        noter("propositions (JSON par schéma)", bool(props.get("tons")) or props.get("statut") == "incomplet",
              f"statut={props.get('statut')}, tons={[t['nom'] for t in props.get('tons', [])]}")
        print("   RÉPONSE :", r3["texte"][:300])

        await reprendre(client, conversation_wa, donnees(r3, "meta")["message_id"])

        print("\n=== 5. Erreurs (sans appel facturable)")
        r5 = await flux(client, {"message": "x"}, {"X-Jarvis-Fournisseur": "gemini"})
        noter("fournisseur inconnu ou interdit refusé", r5["statut"] in (400, 403),
              f"HTTP {r5['statut']} {r5['corps']}")
        r6 = await flux(client, {"message": "x", "conversation_id": str(uuid4())})
        noter("conversation d'un autre compte / inconnue → 404", r6["statut"] == 404)


async def comparaison(client: httpx.AsyncClient) -> None:
    print("\n=== 7. Comparaison contrôlée GroqCloud (compte autorisé, hors production)")
    question = "En une phrase : quelle est la différence entre un fichier ZIP et un fichier TXT ?"
    claude = await flux(client, {"message": question})
    groq = await flux(client, {"message": question}, {"X-Jarvis-Fournisseur": "groq"})
    if groq["statut"] == 403:
        noter("GroqCloud refusé (compte non listé dans LLM_ADMINS)", True)
        return
    noter("GroqCloud sur demande explicite", groq["entetes"].get("x-jarvis-fournisseur") == "groq"
          and noms(groq)[-1] == "done", f"HTTP {groq['statut']}")
    for nom, r in (("Claude", claude), ("GroqCloud", groq)):
        u = (donnees(r, "done") or {}).get("usage", {})
        print(f"   {nom:9} {r.get('premier') or 0:5.1f} s → 1er fragment, {r.get('duree', 0):5.1f} s, "
              f"{u.get('total_tokens')} tokens : {r['texte'][:160]}")


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
