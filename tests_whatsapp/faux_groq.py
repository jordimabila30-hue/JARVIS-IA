"""Faux fournisseur GroqCloud DÉTERMINISTE pour les tests sur appareil.

Compatible avec `POST /v1/chat/completions` (stream) du client OpenAI :
JARVIS l'utilise sans aucune modification de code, via OPENAI_BASE_URL
(instance de l'API réservée à la campagne). Aucun appel réel, aucun token.

Réponses, selon la dernière question :
  - aide / répondre / relancer → une phrase + la balise qui ANNONCE les tons
    (<propositions mode=… tons="Naturel, Amical, Taquin">) ; les messages
    viennent ensuite des LOTS (requêtes sans streaming, JSON) ;
  - « pourquoi … » → cite mot pour mot la « PROPOSITION VISÉE » que le
    serveur JARVIS a identifiée (contrôle de bout en bout), et mentionne la
    mémoire des réponses déclarées envoyées si elle est fournie ;
  - sinon → « Le dernier message est de X : « … » [[n]] » (référence réelle).

    uvicorn faux_groq:app --host 0.0.0.0 --port 9000

Lots (génération par lots, phase 5.1) : réponse JSON déterministe pour ce
qui est demandé. Pannes réglables à chaud (essais « Génération incomplète ») :
    POST /panne {"mode": "aucune" | "quota_jour" | "limite_minute" |
                 "une_par_longueur" | "json_casse" | "coupure" | "repetitions" | "lent"}
    (« quota_jour » : TOUS les lots refusés jusqu'au retour à « aucune »).
"""

import asyncio
import json
import re
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

app = FastAPI()
PANNE = {"mode": "aucune"}
_DEMANDE = re.compile(r"^- (.+?) : ((?:(?:court|moyen|long) ×\d(?:, )?)+)", re.M)
_TEXTES = {
    # Neutres (ni « tu » ni « vous ») : valables quel que soit le registre.
    "court": ["Bien reçu, je m'en occupe {x}.", "Merci, on en reparle bientôt {x} ?",
              "D'accord, je garde ça en tête {x}."],
    "moyen": ["Merci pour le message {x}. Je regarde ça et je reviens rapidement.",
              "Je comprends le point {x}. On peut en parler tranquillement ce soir ?",
              "Bonne idée {x}. On fixe un moment pour faire le point."],
    "long": ["Merci pour ce message {x}. Je l'ai bien lu. Je veux répondre sérieusement. "
             "On fait le point ensemble cette semaine ?",
             "Je comprends ce ressenti {x}. Je n'ai pas été assez clair. Je vais corriger ça. "
             "Quel moment arrangerait le mieux ?",
             "C'est juste de le soulever {x}. C'est important pour moi aussi. Je préfère qu'on en parle "
             "de vive voix. Un appel demain, ça irait ?"],
}


@app.post("/panne")
async def panne(request: Request):
    PANNE["mode"] = (await request.json()).get("mode", "aucune")
    return PANNE


def _lot(messages: list[dict]) -> str:
    texte = messages[-1]["content"]
    tons = []
    for nom, parts in _DEMANDE.findall(texte):
        t = {"nom": nom}
        for lo, n in re.findall(r"(court|moyen|long) ×(\d)", parts):
            n = 1 if PANNE["mode"] == "une_par_longueur" else int(n)
            # Marque propre à l'appel : jamais deux fois le même texte.
            t[lo] = [{"approche": f"approche {i}",
                      "texte": _TEXTES[lo][(i - 1) % 3].format(x=f"({nom.lower()} {i}·{int(time.time() * 1000) % 100000})"),
                      "appuis": []}
                     for i in range(1, n + 1)]
            if PANNE["mode"] == "repetitions":
                t[lo] = [t[lo][0]] * len(t[lo])
        tons.append(t)
    return json.dumps({"tons": tons}, ensure_ascii=False)
_LIGNE = re.compile(r"^\[(\d+)\] (.+?) · (.+?)(?: \(utilisateur\))? : «(.*)»$", re.M)


def _repondre(messages: list[dict]) -> str:
    question = next((m["content"] for m in reversed(messages) if m["role"] == "user"), "")
    tout = "\n".join(m["content"] for m in messages if m["role"] == "system")
    lignes = _LIGNE.findall(tout)
    n, _, auteur, texte = lignes[-1] if lignes else ("1", "", "quelqu'un", "")
    q = question.lower()
    if "pourquoi" in q:
        vise = re.search(r"PROPOSITION VISÉE \(identifiant ([^)]+)\) : ton « ([^»]+) », n° (\d)[^:]*: «(.+?)»", tout)
        memoire = re.search(r"ton « ([^»]+) » : «(.+?)»", tout.split("<reponses_declarees_envoyees>")[-1]) \
            if "<reponses_declarees_envoyees>" in tout else None
        if not vise:
            return "Je ne vois pas de proposition précise dans ta question."
        rep = (f"Je t'ai proposé « {vise.group(4)} » (ton {vise.group(2)}, n° {vise.group(3)}) "
               f"parce que {auteur} a écrit en dernier [[{n}]].")
        if memoire:
            rep += f" Tu lui as déjà envoyé « {memoire.group(2)} », je n'ai pas répété ce message."
        return rep
    if any(m in q for m in ("aide", "repond", "répond", "relanc", "propose", "dire")):
        mode = "relance" if "relanc" in q else "reponse"
        return (f"{auteur} a écrit en dernier [[{n}]]. Voici des idées.\n"
                f"<propositions mode=\"{mode}\" tons=\"Naturel, Amical, Taquin\"></propositions>")
    return f"Le dernier message est de {auteur} : « {texte} » [[{n}]]."


@app.post("/v1/chat/completions")
async def completions(request: Request):
    corps = await request.json()
    if not corps.get("stream"):
        # Lot de propositions (JSON), avec la panne choisie.
        mode = PANNE["mode"]
        if mode in ("quota_jour", "limite_minute"):
            quoi = "tokens per day (TPD)" if mode == "quota_jour" else "tokens per minute (TPM)"
            return JSONResponse(status_code=429, headers={"retry-after": "600" if mode == "quota_jour" else "1"},
                                content={"error": {"message": f"Rate limit reached: {quoi}",
                                                   "type": "tokens", "code": "rate_limit_exceeded"}})
        if mode == "lent":
            # Lot lent (vérifier que l'appli reste vivante : « … » animés).
            await asyncio.sleep(4)
        if mode == "coupure":
            return JSONResponse(status_code=503, content={"error": {"message": "service unavailable"}})
        contenu = "Voici mes idées : 1. Coucou" if mode == "json_casse" else _lot(corps.get("messages", []))
        return {"id": "faux", "object": "chat.completion", "created": int(time.time()), "model": corps.get("model"),
                "choices": [{"index": 0, "message": {"role": "assistant", "content": contenu}, "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}}
    texte = _repondre(corps.get("messages", []))

    def flux():
        for i in range(0, len(texte), 12):
            morceau = {"id": "faux", "object": "chat.completion.chunk", "created": int(time.time()),
                       "model": corps.get("model"), "choices": [{"index": 0, "delta": {"content": texte[i:i + 12]},
                                                                 "finish_reason": None}]}
            yield f"data: {json.dumps(morceau, ensure_ascii=False)}\n\n"
        fin = {"id": "faux", "object": "chat.completion.chunk", "created": int(time.time()),
               "model": corps.get("model"), "choices": [],
               "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}}
        yield f"data: {json.dumps(fin)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(flux(), media_type="text/event-stream")
