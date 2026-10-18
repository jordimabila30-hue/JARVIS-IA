"""Qui peut utiliser quel outil.

Décidé par le SERVEUR pour chaque demande, d'après le [ContexteOutil]
(identité du JWT, offre, connexions externes du compte) : le modèle ne voit
que les outils autorisés, et un appel à un autre outil est refusé sans
exécution (même s'il existe dans le registre).
"""

from __future__ import annotations

from .contrat import ContexteOutil, Decision, Outil
from .registre import RegistreOutils


class PolitiqueOutils:
    def decider(self, outil: Outil, contexte: ContexteOutil) -> Decision:
        if outil.test_seulement and contexte.environnement.strip().lower() in ("production", "prod"):
            return Decision.non("outil_test", "Outil de test indisponible en production.")
        if outil.offres is not None and (contexte.plan or "") not in outil.offres:
            return Decision.non("offre", "Cet outil n'est pas inclus dans l'abonnement du compte.")
        if outil.connexion is not None and outil.connexion not in contexte.connexions:
            return Decision.non("connexion_requise", f"Le compte n'a pas connecté « {outil.connexion} ».")
        return Decision.oui()

    def autorises(self, registre: RegistreOutils, contexte: ContexteOutil) -> list[Outil]:
        return [o for o in registre if self.decider(o, contexte).autorise]
