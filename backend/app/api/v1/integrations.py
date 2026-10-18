"""Connexion Gmail d'un compte JARVIS (lecture seule).

GET    /api/v1/integrations/gmail             état (JWT) : non_connecte | connecte | a_renouveler,
                                              adresse, portée ; `configure` : identifiants Google présents
POST   /api/v1/integrations/gmail/connexion   (JWT) {"plateforme"} → {"url"} : page Google à ouvrir
                                              dans le navigateur du système (jamais une fausse page)
GET    /api/v1/integrations/gmail/retour      retour de Google (sans JWT : le compte vient du
                                              `state` à usage unique) → page HTML simple
DELETE /api/v1/integrations/gmail             (JWT) déconnexion : accès coupé, révocation Google,
                                              jeton supprimé ; la boîte Gmail n'est pas touchée

Aucune route ne renvoie de jeton. Disponible même si ODO est désactivé
(connecter un compte ne déclenche aucun appel IA).
"""

import html
import logging
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from ...auth import AuthUser, get_current_user
from ...integrations.google import ErreurGoogle, ServiceGoogle, get_google

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/integrations/gmail", tags=["integrations"])

NON_CONFIGURE = {"code": "gmail_non_configure",
                 "message": "Gmail n'est pas encore configuré sur ce serveur JARVIS."}


class ConnexionRequest(BaseModel):
    plateforme: Literal["android", "windows", "web", "ios", "autre"] = "autre"


@router.get("")
async def etat_gmail(user: AuthUser = Depends(get_current_user),
                     google: ServiceGoogle = Depends(get_google)) -> dict:
    return await google.etat(user.id)


@router.post("/connexion")
async def connecter_gmail(body: ConnexionRequest, user: AuthUser = Depends(get_current_user),
                          google: ServiceGoogle = Depends(get_google)) -> dict:
    if not google.configure:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail=NON_CONFIGURE)
    try:
        url = await google.url_autorisation(user.id, body.plateforme)
    except ErreurGoogle:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail=NON_CONFIGURE) from None
    return {"url": url}


@router.delete("")
async def deconnecter_gmail(user: AuthUser = Depends(get_current_user),
                            google: ServiceGoogle = Depends(get_google)) -> dict:
    supprimee = await google.deconnecter(user.id)
    logger.info("Gmail déconnecté (connexion existante : %s)", supprimee)
    return {"statut": "non_connecte"}


TEXTES = {
    "connecte": ("Gmail est connecté", "JARVIS peut maintenant consulter ce compte en lecture seule."),
    "annule": ("Connexion annulée", "Aucune autorisation n'a été donnée. Vous pouvez réessayer depuis JARVIS."),
    "refuse": ("Connexion refusée", "Google n'a pas accordé l'accès. Réessayez depuis JARVIS."),
    "portee": ("Autorisation incomplète",
               "La lecture des e-mails n'a pas été cochée. Réessayez en acceptant la lecture Gmail."),
    "expire": ("Lien expiré", "Ce lien de connexion n'est plus valable. Relancez la connexion depuis JARVIS."),
    "reseau": ("Google injoignable", "Réessayez dans un instant depuis JARVIS."),
    "erreur": ("Connexion impossible", "Réessayez depuis JARVIS."),
}


def _page(code: str, plateforme: str) -> str:
    titre, texte = TEXTES.get(code, TEXTES["erreur"])
    retour = ""
    if plateforme == "android":
        # Ramène l'application JARVIS au premier plan (intent-filter jarvis://gmail).
        lien = f"jarvis://gmail?resultat={html.escape(code)}"
        retour = (f'<p><a class="bouton" href="{lien}">Revenir dans JARVIS</a></p>'
                  f'<script>setTimeout(function(){{location.href="{lien}";}}, 600);</script>')
    elif plateforme == "web":
        retour = ('<p>Vous pouvez fermer cet onglet : JARVIS se met à jour tout seul.</p>'
                  '<script>setTimeout(function(){window.close();}, 1500);</script>')
    else:
        retour = "<p>Vous pouvez fermer cette page et revenir dans JARVIS : l'état se met à jour tout seul.</p>"
    return f"""<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>JARVIS · Gmail</title>
<style>
:root{{--fond:#f7f4ee;--carte:#fffdf9;--texte:#25232b;--doux:#6b6878;--signal:#5b5bd6}}
@media (prefers-color-scheme: dark){{:root{{--fond:#16151b;--carte:#211f28;--texte:#ecebf2;--doux:#a5a3b4;--signal:#8b8bff}}}}
body{{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
background:var(--fond);color:var(--texte);font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif}}
.carte{{background:var(--carte);border-radius:22px;padding:32px 28px;max-width:420px;margin:16px;
box-shadow:0 10px 40px rgba(0,0,0,.08);text-align:center}}
.marque{{letter-spacing:.4em;color:var(--signal);font-size:13px;margin-bottom:18px}}
h1{{font-weight:500;font-size:22px;margin:0 0 10px}} p{{color:var(--doux);line-height:1.5}}
.bouton{{display:inline-block;margin-top:8px;padding:12px 20px;border-radius:14px;background:var(--signal);
color:#fff;text-decoration:none}}
</style></head><body><div class="carte"><div class="marque">JARVIS</div>
<h1>{html.escape(titre)}</h1><p>{html.escape(texte)}</p>{retour}</div></body></html>"""


@router.get("/retour", response_class=HTMLResponse, include_in_schema=False)
async def retour_google(state: str | None = None, code: str | None = None, error: str | None = None,
                        google: ServiceGoogle = Depends(get_google)) -> HTMLResponse:
    try:
        r = await google.retour(state=state, code=code, erreur=error)
    except Exception:                       # noqa: BLE001 : jamais de détail technique affiché
        logger.error("Retour Google : échec inattendu", exc_info=False)
        return HTMLResponse(_page("erreur", "autre"), status_code=500, headers={"Cache-Control": "no-store"})
    logger.info("Retour Google : %s", r.code)
    return HTMLResponse(_page(r.code, r.plateforme), status_code=200 if r.ok else 400,
                        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"})
