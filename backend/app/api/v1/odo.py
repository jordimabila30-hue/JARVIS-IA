"""Confirmation des actions sensibles préparées par ODO.

POST /api/v1/odo/confirmations/{id}   (Authorization: Bearer <jwt Supabase>)
  corps : {"decision": "confirmer" | "refuser"}

  - le compte vient du JWT ; une confirmation d'un autre compte est
    introuvable (même réponse qu'une confirmation expirée) ;
  - usage unique : consommée de façon atomique, une seconde requête
    (double appui, réseau qui renvoie) reçoit 410 et rien n'est réexécuté ;
  - l'outil est revérifié AVANT exécution : permission du compte (offre,
    connexion), arguments contre le schéma ;
  - aucun appel au modèle, aucun quota de tokens consommé : seule l'action
    s'exécute (délai borné).
ODO désactivé : 404.
"""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ...auth import AuthUser, get_current_user
from ...odo.journal import journaliser
from ...odo.orchestrateur import executer_outil
from ...odo.securite import tronquer
from ...odo.service import ServiceODO, get_odo
from ...odo.validation import valider
from ...quota import QuotaService, get_quota_service

router = APIRouter(prefix="/odo", tags=["odo"])

EXPIREE = {"code": "confirmation_expiree",
           "message": "Cette action a expiré ou a déjà été traitée : redemande-la à JARVIS si besoin."}


class DecisionRequest(BaseModel):
    decision: Literal["confirmer", "refuser"]


@router.post("/confirmations/{confirmation_id}")
async def confirmer_action(
    confirmation_id: str,
    body: DecisionRequest,
    user: AuthUser = Depends(get_current_user),
    odo: ServiceODO = Depends(get_odo),
    quota_service: QuotaService = Depends(get_quota_service),
) -> dict:
    if not odo.actif:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="ODO désactivé")
    if not (8 <= len(confirmation_id) <= 64) or not confirmation_id.replace("-", "").replace("_", "").isalnum():
        raise HTTPException(status.HTTP_410_GONE, detail=EXPIREE)
    try:
        action = await odo.confirmations.consommer(user.id, confirmation_id)
    except Exception:              # noqa: BLE001 : Redis absent → rien d'exécuté
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail={"code": "odo_indisponible", "message": "Action impossible pour le moment."})
    if action is None:
        raise HTTPException(status.HTTP_410_GONE, detail=EXPIREE)
    if body.decision == "refuser":
        journaliser("confirmation", outil=action.outil, statut="refusee", demande=action.demande_id)
        return {"statut": "refusee", "outil": action.outil}

    outil = odo.registre.obtenir(action.outil)
    limites = await quota_service.get_limits(user.id)
    contexte = odo.contexte(user_id=user.id, demande_id=action.demande_id, plan=limites.plan,
                            conversation_id=action.conversation_id)
    decision = odo.politique.decider(outil, contexte) if outil is not None else None
    if outil is None or not decision.autorise:
        journaliser("confirmation", outil=action.outil, statut="non_autorise", demande=action.demande_id)
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail={
            "code": "outil_non_autorise", "message": "Cette action n'est plus autorisée pour ce compte."})
    if valider(outil.schema, action.arguments):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail={
            "code": "arguments_invalides", "message": "Action invalide : rien n'a été exécuté."})
    r = await executer_outil(outil, action.arguments, contexte, odo.settings.odo_delai_outil)
    journaliser("confirmation", outil=outil.nom, statut="executee" if not r.erreur else r.erreur,
                demande=action.demande_id)
    contenu, _ = tronquer(r.contenu, odo.settings.odo_resultat_max_caracteres)
    return {"statut": "executee" if not r.erreur else "echec", "outil": outil.nom,
            "resultat": contenu, "erreur": r.erreur}
