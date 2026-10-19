"""Secrets retirés du texte des e-mails AVANT tout envoi au modèle.

La consigne Gmail interdit déjà au modèle de recopier un code ; ce filtre
fait en sorte que le code n'atteigne même pas le fournisseur IA (GroqCloud
ou Claude). Déterministe, sans appel externe. Masqués :
  - codes de vérification / à usage unique / PIN (après un mot qui les
    annonce, ou seuls sur leur ligne) ;
  - mot de passe annoncé (« mot de passe : … ») ;
  - liens : tous réduits à leur domaine ; liens de connexion,
    réinitialisation, vérification, jetons → « [lien de connexion masqué] » ;
  - numéros de carte (contrôle de Luhn) et IBAN.
Les dates, heures, montants et numéros courts ordinaires sont gardés.
"""

from __future__ import annotations

import re
from urllib.parse import urlparse

CODE_MASQUE = "[code masqué]"
LIEN_MASQUE = "[lien de connexion masqué]"
NUMERO_MASQUE = "[numéro masqué]"
MDP_MASQUE = "[mot de passe masqué]"

_URL = re.compile(r"https?://[^\s<>\"')\]]+", re.I)
_URL_SENSIBLE = re.compile(
    r"reset|password|passwd|motdepasse|mot-de-passe|verif|confirm|login|log-in|signin|sign-in|auth|token|"
    r"magic|otp|activat|session|secure|code=|key=|sig=", re.I)
# Mot qui annonce un code, puis (≤ 40 caractères plus loin) le code lui-même :
# 4 à 10 caractères dont au moins un chiffre (123456, G-123456, A7K-29Q), ou
# deux groupes de chiffres (482 913, 482-913). « code_482913.pdf » compris.
_ANNONCE = (r"(?:code|c[oó]digo|otp|pin|passcode|v[ée]rification|verification|s[ée]curit[ée]|security|"
            r"usage unique|one[- ]time|2fa|authentification|authentication)")
_CODE_ANNONCE = re.compile(
    rf"({_ANNONCE}[^\n\d]{{0,40}}?)(?<![A-Za-z0-9])"
    rf"(\d{{3,4}}[ .-]\d{{3,4}}|(?=[A-Z0-9-]*\d)[A-Z0-9][A-Z0-9-]{{2,9}}[A-Z0-9])(?![A-Za-z0-9])", re.I)
_CODE_SEUL = re.compile(r"^(\s*)(?:G-)?(?:\d{4,8}|\d{3} \d{3})(\s*)$", re.M)
_MDP = re.compile(r"((?:mot de passe|password|mdp)\s*(?:temporaire|provisoire)?\s*[:=]\s*)(\S+)", re.I)
_CARTE = re.compile(r"\b(?:\d[ -]?){12,18}\d\b")
_IBAN = re.compile(r"\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{4}){2,7}(?:[ ]?[A-Z0-9]{1,4})?\b")


def _luhn(chiffres: str) -> bool:
    total, double = 0, False
    for c in reversed(chiffres):
        n = int(c)
        if double:
            n = n * 2 - 9 if n > 4 else n * 2
        total += n
        double = not double
    return total % 10 == 0


def _lien(m: re.Match) -> str:
    url = m.group(0)
    if _URL_SENSIBLE.search(url):
        return LIEN_MASQUE
    domaine = urlparse(url).hostname or "site"
    return f"[lien vers {domaine}]"


def _carte(m: re.Match) -> str:
    chiffres = re.sub(r"\D", "", m.group(0))
    return NUMERO_MASQUE if 13 <= len(chiffres) <= 19 and _luhn(chiffres) else m.group(0)


def masquer_secrets(texte: str | None) -> str:
    if not texte:
        return texte or ""
    texte = _URL.sub(_lien, texte)
    texte = _MDP.sub(lambda m: m.group(1) + MDP_MASQUE, texte)
    texte = _CODE_ANNONCE.sub(lambda m: m.group(1) + CODE_MASQUE, texte)
    texte = _CODE_SEUL.sub(lambda m: m.group(1) + CODE_MASQUE + m.group(2), texte)
    texte = _IBAN.sub(NUMERO_MASQUE, texte)
    texte = _CARTE.sub(_carte, texte)
    return texte
