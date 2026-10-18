"""Adaptateur GroqCloud (fournisseur de test et de comparaison).

Reprend le comportement de production de `api/v1/chat.py` (`get_openai`,
flux principal, `appel_lot`, `describe_llm_error`, `retry_delay`), qui
reste en place et inchangé tant que la phase 2 n'a pas raccordé les routes :
  - SDK `AsyncOpenAI`, point d'accès Groq si la clé commence par `gsk_`
    (ou `OPENAI_BASE_URL`), sinon OpenAI ;
  - flux `stream=True` avec l'usage à la fin (`include_usage`) ;
  - JSON : `response_format={"type": "json_object"}`, puis texte relu en
    JSON si le fournisseur refuse ce mode (mémorisé pour ce client) ;
  - modèles `gpt-oss` : `reasoning_effort` (« low » par défaut pour le JSON,
    comme les lots de propositions) ; le raisonnement n'est jamais diffusé ;
  - aucun nouvel essai automatique : l'appelant gère les attentes (429) ;
  - outils : `tools` au format fonctions OpenAI ; les `tool_calls` du flux
    arrivent en fragments (par `index`) et sont réassemblés ; arguments JSON
    illisibles → `AppelOutil.erreur_arguments` (jamais exécutés). Suite de
    la conversation : message assistant `tool_calls`, puis un message `tool`
    par résultat (`tool_call_id`).
"""

from __future__ import annotations

import json as _json
from collections.abc import AsyncIterator, Sequence
from typing import Any

import openai
from openai import AsyncOpenAI

from .base import (
    MESSAGES,
    AppelOutil,
    DefinitionOutil,
    Effort,
    ErreurFournisseur,
    ErreurLLM,
    Evenement,
    Fin,
    FournisseurLLM,
    LimiteDebit,
    Message,
    RaisonArret,
    ReponseJSON,
    RequeteTropGrande,
    Texte,
    TourAssistant,
    Usage,
    attente_conseillee,
    estimer_tokens,
    lire_json,
    secondes,
    verifier_messages,
    verifier_outils,
)

BASE_GROQ = "https://api.groq.com/openai/v1"

_RAISONS = {
    "stop": RaisonArret.FIN,
    "length": RaisonArret.LONGUEUR,
    "content_filter": RaisonArret.REFUS,
    "tool_calls": RaisonArret.OUTIL,
    "function_call": RaisonArret.OUTIL,
}


def adresse(cle: str, base_url: str | None) -> str | None:
    """Même règle que `chat.get_openai` : base explicite, sinon Groq pour une
    clé `gsk_`, sinon OpenAI (None)."""
    if base_url:
        return base_url
    return BASE_GROQ if cle.startswith("gsk_") else None


def _effort_groq(modele: str, effort: Effort | None) -> str | None:
    """`reasoning_effort` n'existe que pour les modèles à raisonnement
    (gpt-oss) : low / medium / high."""
    if effort is None or "gpt-oss" not in modele:
        return None
    return {"xhigh": "high", "max": "high"}.get(effort, effort)


def _raison(finish: str | None) -> RaisonArret:
    return _RAISONS.get(finish or "stop", RaisonArret.AUTRE)


def convertir(messages: Sequence[Message]) -> list[dict[str, Any]]:
    """Format commun → messages Chat Completions (format OpenAI)."""
    verifier_messages(messages)
    sortie: list[dict[str, Any]] = []
    for m in messages:
        if m["role"] == "outil":
            sortie += [{"role": "tool", "tool_call_id": r.id, "content": r.contenu} for r in m["resultats"]]
        elif m.get("tour") is not None:
            tour = m["tour"]
            sortie.append({
                "role": "assistant",
                "content": tour.texte or None,
                "tool_calls": [{"id": a.id, "type": "function",
                                "function": {"name": a.nom,
                                             "arguments": _json.dumps(a.arguments, ensure_ascii=False)}}
                               for a in tour.appels],
            })
        else:
            sortie.append({"role": m["role"], "content": m["content"]})
    return sortie


def definitions(outils: Sequence[DefinitionOutil] | None) -> list[dict[str, Any]]:
    """Définitions communes → `tools` (fonctions) de Chat Completions."""
    return [{"type": "function", "function": {"name": o.nom, "description": o.description, "parameters": o.schema}}
            for o in verifier_outils(outils)]


def _appel(fragment: dict[str, Any]) -> AppelOutil:
    """Appel réassemblé ; arguments illisibles signalés, jamais devinés."""
    brut = "".join(fragment["arguments"]).strip() or "{}"
    try:
        arguments = _json.loads(brut)
    except ValueError:
        return AppelOutil(id=fragment["id"], nom=fragment["nom"], erreur_arguments="JSON illisible")
    if not isinstance(arguments, dict):
        return AppelOutil(id=fragment["id"], nom=fragment["nom"], erreur_arguments="arguments non objet")
    return AppelOutil(id=fragment["id"], nom=fragment["nom"], arguments=arguments)


class FournisseurGroq(FournisseurLLM):
    nom = "groq"

    def __init__(self, *, cle: str, modele: str, base_url: str | None = None,
                 client: AsyncOpenAI | None = None) -> None:
        super().__init__(modele)
        if client is None:
            if not cle:
                raise ValueError("clé GroqCloud absente")
            client = AsyncOpenAI(api_key=cle, base_url=adresse(cle, base_url), max_retries=0)
        self._client = client
        self._json_accepte = True

    # --- Erreurs ----------------------------------------------------------------

    def erreur(self, exc: Exception, *, apres_texte: bool = False) -> ErreurLLM:
        """Équivalent de `chat.describe_llm_error` + `retry_delay`."""
        n = self.nom
        if isinstance(exc, openai.APITimeoutError):
            return ErreurFournisseur("llm_timeout", fournisseur=n, apres_texte=apres_texte)
        statut = getattr(exc, "status_code", None)
        texte = str(exc)
        if statut == 413 or (isinstance(exc, openai.BadRequestError) and "context_length" in texte):
            return RequeteTropGrande(fournisseur=n, apres_texte=apres_texte, statut=statut)
        if isinstance(exc, openai.NotFoundError) or (
            isinstance(exc, openai.BadRequestError) and "model" in texte.lower()
        ):
            return ErreurFournisseur("llm_model", fournisseur=n, apres_texte=apres_texte, statut=statut)
        if isinstance(exc, openai.RateLimitError):
            body = getattr(exc, "body", None) or {}
            code = body.get("code") if isinstance(body, dict) else None
            entetes = getattr(getattr(exc, "response", None), "headers", None) or {}
            if code in ("insufficient_quota", "credit_balance_exhausted") or "insufficient_quota" in texte:
                return LimiteDebit(fournisseur=n, attente=None, code="llm_credit", apres_texte=apres_texte)
            if "per day" in texte:
                # Quota QUOTIDIEN de GroqCloud : attendre dans la requête ne sert à rien.
                attente = secondes(entetes.get("retry-after"))
                minutes = max(1, round((attente or 600) / 60))
                return LimiteDebit(fournisseur=n, attente=None, code="llm_daily_quota", apres_texte=apres_texte,
                                   message=("Le quota quotidien du service IA est presque épuisé. "
                                            f"Réessaie dans environ {minutes} minute{'s' if minutes > 1 else ''}."))
            return LimiteDebit(fournisseur=n, apres_texte=apres_texte, attente=attente_conseillee(
                entetes, ("retry-after", "x-ratelimit-reset-tokens", "x-ratelimit-reset-requests")))
        if isinstance(exc, openai.AuthenticationError):
            return ErreurFournisseur("llm_auth", fournisseur=n, apres_texte=apres_texte, statut=statut)
        return ErreurFournisseur("llm_unavailable", fournisseur=n, apres_texte=apres_texte, statut=statut,
                                 message=MESSAGES["llm_unavailable"])

    # --- Flux -------------------------------------------------------------------

    async def flux(self, messages: Sequence[Message], *, max_sortie: int, effort: Effort | None = None,
                   outils: Sequence[DefinitionOutil] | None = None) -> AsyncIterator[Evenement]:
        options: dict[str, Any] = {
            "model": self.modele, "messages": convertir(messages), "max_tokens": max_sortie,
            "stream": True, "stream_options": {"include_usage": True},
        }
        if outils:
            options["tools"] = definitions(outils)
        raisonnement = _effort_groq(self.modele, effort)
        if raisonnement:
            options["extra_body"] = {"reasoning_effort": raisonnement}

        parts: list[str] = []
        usage = None
        modele = self.modele
        finish = None
        fragments: dict[int, dict[str, Any]] = {}     # tool_calls par index
        try:
            stream = await self._client.chat.completions.create(**options)
            async for chunk in stream:
                # Champs lus avec tolérance : certains fournisseurs compatibles
                # OpenAI en omettent (comme le faisait la route de production).
                if getattr(chunk, "model", None):
                    modele = chunk.model
                if getattr(chunk, "usage", None) is not None:
                    usage = chunk.usage
                if not getattr(chunk, "choices", None):
                    continue
                choix = chunk.choices[0]
                if getattr(choix, "finish_reason", None):
                    finish = choix.finish_reason
                # `delta.reasoning` (gpt-oss) n'est jamais diffusé.
                delta = getattr(choix, "delta", None)
                contenu = getattr(delta, "content", None)
                if contenu:
                    parts.append(contenu)
                    yield Texte(contenu)
                for tc in getattr(delta, "tool_calls", None) or ():
                    f = fragments.setdefault(getattr(tc, "index", 0) or 0, {"id": "", "nom": "", "arguments": []})
                    if getattr(tc, "id", None):
                        f["id"] = tc.id
                    fonction = getattr(tc, "function", None)
                    if getattr(fonction, "name", None):
                        f["nom"] += fonction.name
                    if getattr(fonction, "arguments", None):
                        f["arguments"].append(fonction.arguments)
        except openai.APIError as exc:
            raise self.erreur(exc, apres_texte=bool(parts)) from exc

        tour = None
        if fragments:
            appels = tuple(_appel(fragments[i]) for i in sorted(fragments))
            tour = TourAssistant(texte="".join(parts), appels=appels, fournisseur=self.nom)
        raison = RaisonArret.OUTIL if tour is not None else _raison(finish)
        yield Fin(raison=raison, usage=self._usage(usage, messages, "".join(parts)),
                  modele=modele, detail=finish, tour=tour)

    # --- JSON -------------------------------------------------------------------

    async def json(self, messages: Sequence[Message], *, max_sortie: int,
                   schema: dict[str, Any] | None = None, effort: Effort | None = None) -> ReponseJSON:
        """`schema` n'est pas imposé par GroqCloud (mode JSON simple) : la
        consigne du prompt décrit la forme, la lecture reste tolérante."""
        options: dict[str, Any] = {"model": self.modele, "messages": convertir(messages),
                                   "max_tokens": max_sortie}
        raisonnement = _effort_groq(self.modele, effort or "low")
        if raisonnement:
            # Modèle à raisonnement : raisonnement court, la sortie va aux messages.
            options["extra_body"] = {"reasoning_effort": raisonnement}
        while True:
            try:
                if self._json_accepte:
                    r = await self._client.chat.completions.create(
                        **options, response_format={"type": "json_object"})
                else:
                    r = await self._client.chat.completions.create(**options)
                break
            except openai.BadRequestError as exc:
                if self._json_accepte and ("response_format" in str(exc) or "json" in str(exc).lower()):
                    self._json_accepte = False     # mode JSON refusé : texte relu en JSON
                    continue
                raise self.erreur(exc) from exc
            except openai.APIError as exc:
                raise self.erreur(exc) from exc
        choix = r.choices[0] if getattr(r, "choices", None) else None
        texte = getattr(getattr(choix, "message", None), "content", None) or ""
        return ReponseJSON(
            texte=texte, donnees=lire_json(texte),
            usage=self._usage(getattr(r, "usage", None), messages, texte),
            modele=getattr(r, "model", None) or self.modele,
            raison=_raison(getattr(choix, "finish_reason", None)),
        )

    # --- Divers -----------------------------------------------------------------

    @staticmethod
    def _usage(usage, messages: Sequence[Message], texte: str) -> Usage:
        if usage is not None:
            return Usage(entree=getattr(usage, "prompt_tokens", 0) or 0,
                         sortie=getattr(usage, "completion_tokens", 0) or 0)
        return Usage(entree=estimer_tokens("".join(m["content"] for m in messages)),
                     sortie=estimer_tokens(texte), estime=True)

    async def fermer(self) -> None:
        await self._client.close()
