"""Faux serveurs Claude et GroqCloud pour les tests de app/llm/.

Les adaptateurs tournent avec les VRAIS SDK (`anthropic`, `openai`) ; seul
le transport HTTP est simulé (MockTransport) : le format des flux SSE, des
erreurs et des en-têtes est donc réellement relu par chaque SDK. Aucun
appel réseau, aucune clé réelle.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

import httpx
import httpx2
from anthropic import AsyncAnthropic
from openai import AsyncOpenAI

from app.llm.anthropic import FournisseurAnthropic
from app.llm.groq import FournisseurGroq

CLE_TEST = "cle-de-test-non-secrete"


@dataclass
class Scenario:
    """Une réponse du fournisseur, décrite une fois pour les deux formats."""

    textes: list[str] = field(default_factory=lambda: ["Bon", "jour ", "Tony."])
    entree: int = 12
    sortie: int = 7
    raison: str = "fin"              # fin | longueur | refus
    reflexion: str = "raisonnement interne secret"
    erreur_milieu: bool = False      # coupure après le premier fragment
    statut: int = 200                # ≠ 200 : réponse d'erreur HTTP
    corps_erreur: dict | None = None
    entetes: dict[str, str] = field(default_factory=dict)
    json_texte: str | None = None    # sortie non diffusée (JSON)
    modele: str = "modele-servi"
    usage_absent: bool = False


@dataclass
class Journal:
    requetes: list[dict] = field(default_factory=list)


# --- Claude ---------------------------------------------------------------------

_RAISONS_ANTHROPIC = {"fin": "end_turn", "longueur": "max_tokens", "refus": "refusal"}


def _sse(evenements: list[tuple[str, dict]]) -> bytes:
    return "".join(f"event: {e}\ndata: {json.dumps(d)}\n\n" for e, d in evenements).encode()


def flux_anthropic(s: Scenario) -> bytes:
    ev: list[tuple[str, dict]] = [("message_start", {"type": "message_start", "message": {
        "id": "msg_test", "type": "message", "role": "assistant", "model": s.modele, "content": [],
        "stop_reason": None, "stop_sequence": None,
        "usage": {"input_tokens": s.entree, "output_tokens": 1,
                  "cache_read_input_tokens": 3, "cache_creation_input_tokens": 2}}})]
    i = 0
    if s.reflexion:
        ev += [
            ("content_block_start", {"type": "content_block_start", "index": i,
                                     "content_block": {"type": "thinking", "thinking": "", "signature": ""}}),
            ("content_block_delta", {"type": "content_block_delta", "index": i,
                                     "delta": {"type": "thinking_delta", "thinking": s.reflexion}}),
            ("content_block_delta", {"type": "content_block_delta", "index": i,
                                     "delta": {"type": "signature_delta", "signature": "sig"}}),
            ("content_block_stop", {"type": "content_block_stop", "index": i}),
        ]
        i += 1
    textes = [s.json_texte] if s.json_texte is not None else s.textes
    ev.append(("content_block_start", {"type": "content_block_start", "index": i,
                                       "content_block": {"type": "text", "text": ""}}))
    for n, t in enumerate(textes):
        ev.append(("content_block_delta", {"type": "content_block_delta", "index": i,
                                           "delta": {"type": "text_delta", "text": t}}))
        if s.erreur_milieu and n == 0:
            ev.append(("error", {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}))
            return _sse(ev)
    ev.append(("content_block_stop", {"type": "content_block_stop", "index": i}))
    delta: dict = {"stop_reason": _RAISONS_ANTHROPIC[s.raison], "stop_sequence": None}
    if s.raison == "refus":
        delta["stop_details"] = {"type": "refusal", "category": "cyber", "explanation": None}
    ev.append(("message_delta", {"type": "message_delta", "delta": delta,
                                 "usage": {"output_tokens": s.sortie}}))
    ev.append(("message_stop", {"type": "message_stop"}))
    return _sse(ev)


def fournisseur_anthropic(s: Scenario, journal: Journal | None = None, **options) -> FournisseurAnthropic:
    journal = journal if journal is not None else Journal()

    def repondre(requete: httpx2.Request) -> httpx2.Response:
        journal.requetes.append(json.loads(requete.content))
        if s.statut != 200:
            corps = s.corps_erreur or {"type": "error", "error": {"type": "api_error", "message": "erreur"}}
            return httpx2.Response(s.statut, json=corps, headers=s.entetes)
        return httpx2.Response(200, content=flux_anthropic(s), headers={"content-type": "text/event-stream"})

    client = AsyncAnthropic(api_key=CLE_TEST, base_url="http://anthropic.test", max_retries=0,
                            http_client=httpx2.AsyncClient(transport=httpx2.MockTransport(repondre)))
    return FournisseurAnthropic(cle=CLE_TEST, modele=options.pop("modele", "claude-modele-test"),
                                client=client, **options)


# --- GroqCloud --------------------------------------------------------------------

_RAISONS_GROQ = {"fin": "stop", "longueur": "length", "refus": "content_filter"}


def _chunk(s: Scenario, delta: dict, finish: str | None = None) -> dict:
    return {"id": "c1", "object": "chat.completion.chunk", "created": 0, "model": s.modele,
            "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}


def flux_groq(s: Scenario) -> bytes:
    morceaux = []
    if s.reflexion:
        morceaux.append(_chunk(s, {"role": "assistant", "reasoning": s.reflexion}))
    for n, t in enumerate(s.textes):
        morceaux.append(_chunk(s, {"content": t}))
        if s.erreur_milieu and n == 0:
            morceaux.append({"error": {"message": "Service unavailable", "type": "server_error"}})
            break
    else:
        morceaux.append(_chunk(s, {}, _RAISONS_GROQ[s.raison]))
        if not s.usage_absent:
            morceaux.append({"id": "c1", "object": "chat.completion.chunk", "created": 0, "model": s.modele,
                             "choices": [], "usage": {"prompt_tokens": s.entree, "completion_tokens": s.sortie,
                                                      "total_tokens": s.entree + s.sortie}})
    texte = "".join(f"data: {json.dumps(m)}\n\n" for m in morceaux)
    if not s.erreur_milieu:
        texte += "data: [DONE]\n\n"
    return texte.encode()


def complet_groq(s: Scenario) -> dict:
    corps = {"id": "c1", "object": "chat.completion", "created": 0, "model": s.modele,
             "choices": [{"index": 0, "finish_reason": _RAISONS_GROQ[s.raison],
                          "message": {"role": "assistant", "content": s.json_texte}}]}
    if not s.usage_absent:
        corps["usage"] = {"prompt_tokens": s.entree, "completion_tokens": s.sortie,
                          "total_tokens": s.entree + s.sortie}
    return corps


def fournisseur_groq(s: Scenario, journal: Journal | None = None, *, refuser_json: bool = False,
                     **options) -> FournisseurGroq:
    journal = journal if journal is not None else Journal()

    def repondre(requete: httpx.Request) -> httpx.Response:
        corps = json.loads(requete.content)
        journal.requetes.append(corps)
        if refuser_json and "response_format" in corps:
            return httpx.Response(400, json={"error": {
                "message": "response_format json_object is not supported", "type": "invalid_request_error"}})
        if s.statut != 200:
            corps_erreur = s.corps_erreur or {"error": {"message": "erreur", "type": "server_error"}}
            return httpx.Response(s.statut, json=corps_erreur, headers=s.entetes)
        if corps.get("stream"):
            return httpx.Response(200, content=flux_groq(s), headers={"content-type": "text/event-stream"})
        return httpx.Response(200, json=complet_groq(s))

    client = AsyncOpenAI(api_key=CLE_TEST, base_url="http://groq.test/openai/v1", max_retries=0,
                         http_client=httpx.AsyncClient(transport=httpx.MockTransport(repondre)))
    return FournisseurGroq(cle=CLE_TEST, modele=options.pop("modele", "openai/gpt-oss-120b"),
                           client=client, **options)


FABRIQUES = {"anthropic": fournisseur_anthropic, "groq": fournisseur_groq}
