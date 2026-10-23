"""Kelasi : tuteur pédagogique en SSE, par MIA universel.

POST /api/v1/apprentissage/tuteur   (Authorization: Bearer <jwt Supabase>)
  corps : {"action": "simplifier|exemple|erreur|entrainer|situation|dialogue|bilan",
           "fiches": ["cor-f-appel"], "exercice": "cor-l1-e1"?, "reponse": "..."?,
           "texte": "..."?, "situation": "sit-professeur"?, "historique": [...]?,
           "niveau": "debutant|intermediaire|avance"?, "oral": false,
           "corpus_version": "<empreinte>"?}

Mêmes protections que le chat : identité vérifiée (JWT), fournisseur de
l'offre (`chat.get_fournisseur`), quota du jour réservé AVANT le flux et
rendu si rien n'est généré (`enforce_quota`), erreurs typées
(`describe_llm_error`), refus / plafond → `error`, jamais `done`.

Contenu : le serveur lit lui-même les fiches (corpus contrôlé) ; le client
n'envoie que des identifiants. Production : fiches validées seulement.
Aucun texte de l'élève n'est enregistré (ni messages, ni contexte) : seuls
les tokens sont comptés.

Flux :
  event: meta    {"corpus_version", "meme_version", "quota"}
  event: delta   {"text"}             repères [[id]] retirés
  event: sources {"sources": [...], "inventes": n}   après validation, avant done
  event: done    {"usage", "quota"}
  event: error   {"code", "message"}
"""

from __future__ import annotations

import logging
import time
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from ...apprentissage import corpus as corpus_kelasi
from ...apprentissage.tuteur import SORTIE, FiltreCitations, construire, sources_de
from ...config import Settings, get_settings
from ...llm import ErreurFournisseur, Fin, FournisseurLLM, RaisonArret, Texte
from ...llm.base import MESSAGES as MESSAGES_LLM
from ...quota import QuotaReservation, QuotaService, enforce_quota, get_quota_service, quota_exceeded
from .chat import _avec_battement, _spawn, _token_counts, describe_llm_error, estimate_tokens, get_fournisseur, plafond, sse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/apprentissage", tags=["apprentissage"])


class Replique(BaseModel):
    role: Literal["eleve", "jarvis"]
    texte: str = Field(max_length=1000)


class DemandeTuteur(BaseModel):
    action: Literal["simplifier", "exemple", "erreur", "entrainer", "situation", "dialogue", "bilan"]
    fiches: list[str] = Field(default_factory=list, max_length=4)
    exercice: str | None = Field(default=None, max_length=40)
    reponse: str | None = Field(default=None, max_length=600)
    texte: str | None = Field(default=None, max_length=2000)
    situation: str | None = Field(default=None, max_length=40)
    historique: list[Replique] = Field(default_factory=list, max_length=16)
    niveau: Literal["debutant", "intermediaire", "avance"] | None = None
    oral: bool = False
    corpus_version: str | None = Field(default=None, max_length=20)


def _inconnu(code: str, message: str) -> HTTPException:
    return HTTPException(422, detail={"code": code, "message": message})


def preparer(body: DemandeTuteur, production: bool):
    """Fiches, exercice et situation lus dans le corpus du serveur."""
    corpus = corpus_kelasi.charger()
    autorisees = corpus.autorisees(production)
    situation = None
    if body.action in ("situation", "dialogue", "bilan"):
        situation = corpus.situation_autorisee(body.situation or "", production)
        if situation is None:
            raise _inconnu("situation_inconnue", "Cette situation n'est pas disponible.")
        ids = list(situation.fiches)
    else:
        ids = list(dict.fromkeys(body.fiches))
    if not ids or any(i not in autorisees for i in ids):
        raise _inconnu("fiche_inconnue", "Cette notion n'est pas disponible.")
    exercice = None
    if body.action == "erreur":
        exercice = corpus.exercices.get(body.exercice or "")
        if exercice is None or exercice.fiche not in ids:
            raise _inconnu("exercice_inconnu", "Cet exercice n'est pas disponible.")
    if body.action == "situation" and not (body.texte or "").strip():
        raise _inconnu("texte_vide", "Écris d'abord ta réponse.")
    fiches = [autorisees[i] for i in ids]
    return corpus, fiches, exercice, situation


@router.post("/tuteur")
async def tuteur(
    body: DemandeTuteur,
    llm: FournisseurLLM = Depends(get_fournisseur),
    reservation: QuotaReservation = Depends(enforce_quota),
    quota_service: QuotaService = Depends(get_quota_service),
    settings: Settings = Depends(get_settings),
) -> StreamingResponse:
    production = settings.environnement == "production"
    try:
        corpus, fiches, exercice, situation = preparer(body, production)
    except HTTPException:
        await quota_service.release(reservation)
        raise
    prompt = construire(action=body.action, fiches=fiches, niveau=body.niveau, oral=body.oral,
                        exercice=exercice, reponse=body.reponse, texte=body.texte,
                        situation=situation, historique=[h.model_dump() for h in body.historique])
    depassement = quota_service.budget_depasse(reservation, estimate_tokens("".join(m["content"] for m in prompt)))
    if depassement:
        await quota_service.release(reservation)
        raise quota_exceeded(depassement, reservation.status)
    max_sortie = plafond(llm, SORTIE[body.action], settings)
    filtre = FiltreCitations({f.id for f in fiches})
    fiches_par_id = {f.id: f for f in fiches}

    async def flux():
        parts: list[str] = []
        fin: Fin | None = None
        debut = time.perf_counter()
        premier = None
        try:
            yield sse("meta", {
                "corpus_version": corpus.version,
                "meme_version": body.corpus_version in (None, corpus.version),
                "quota": reservation.status.to_dict(),
            })
            async for ev in _avec_battement(llm.flux(prompt, max_sortie=max_sortie)):
                if ev is None:
                    yield b": le modele reflechit\n\n"
                elif isinstance(ev, Texte):
                    premier = premier or time.perf_counter()
                    parts.append(ev.texte)
                    visible = filtre.ajouter(ev.texte)
                    if visible:
                        yield sse("delta", {"text": visible})
                elif isinstance(ev, Fin):
                    fin = ev
            if fin is None:
                raise ErreurFournisseur("llm_unavailable", fournisseur=llm.nom, apres_texte=bool(parts))
            if fin.raison is not RaisonArret.FIN:
                raise ErreurFournisseur(
                    "llm_refus" if fin.raison is RaisonArret.REFUS else "llm_incomplet",
                    fournisseur=llm.nom, apres_texte=bool(parts),
                    message=MESSAGES_LLM["llm_refus"] if fin.raison is RaisonArret.REFUS
                    else "L'explication a été coupée. Redemande-la pour la version complète.")
            reste = filtre.terminer()
            if reste:
                yield sse("delta", {"text": reste})
            # Sources seulement après la fin et la validation des repères.
            yield sse("sources", {"sources": sources_de(fiches_par_id, filtre.cites),
                                  "inventes": filtre.inventes})
            entree, sortie = _token_counts(fin.usage, prompt, "".join(parts))
            yield sse("done", {"usage": {"total_tokens": entree + sortie},
                               "quota": reservation.status.to_dict()})
        except Exception as exc:
            logger.error("Tuteur Kelasi (%s, %s) : %s %s", body.action, llm.nom,
                         type(exc).__name__, getattr(exc, "code", ""))
            yield sse("error", describe_llm_error(exc))
        finally:
            # Aussi en cas de déconnexion (annulation par l'appli) : tokens
            # consommés comptés, requête rendue si rien n'a été généré.
            texte = "".join(parts)
            entree, sortie = _token_counts(fin.usage if fin else None, prompt, texte)
            if premier is not None:
                logger.info("Tuteur Kelasi %s : 1er fragment %.0f ms, total %.0f ms",
                            body.action, (premier - debut) * 1000, (time.perf_counter() - debut) * 1000)
            _spawn(_compter(quota_service, reservation, texte, entree, sortie, llm.nom,
                            fin.modele if fin else llm.modele))

    return StreamingResponse(flux(), media_type="text/event-stream", headers={
        **reservation.status.headers(), "Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


async def _compter(service, reservation, texte, entree, sortie, fournisseur, modele) -> None:
    try:
        if texte:
            await service.record_usage(reservation, entree + sortie, tokens_input=entree,
                                       tokens_output=sortie, provider=fournisseur, model=modele)
        else:
            await service.release(reservation)
    except Exception:
        logger.warning("Comptage du tuteur Kelasi impossible", exc_info=True)
