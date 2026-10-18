"""Journal technique d'ODO : métadonnées seulement.

Jamais : arguments, contenu des résultats, texte des e-mails, identité de
l'utilisateur, jetons. Seulement l'outil, le statut, la durée, la taille et
l'identifiant technique de la demande (pour relier les lignes entre elles).
"""

from __future__ import annotations

import logging

logger = logging.getLogger("app.odo")


def journaliser(evenement: str, *, outil: str | None = None, statut: str | None = None,
                demande: str | None = None, duree_ms: float | None = None, taille: int | None = None,
                **extra: int | str | None) -> None:
    morceaux = [f"ODO {evenement}"]
    for cle, valeur in (("outil", outil), ("statut", statut), ("demande", (demande or "")[:8] or None),
                        ("duree_ms", None if duree_ms is None else int(duree_ms)), ("taille", taille),
                        *extra.items()):
        if valeur is not None:
            morceaux.append(f"{cle}={valeur}")
    logger.info(" ".join(morceaux))
