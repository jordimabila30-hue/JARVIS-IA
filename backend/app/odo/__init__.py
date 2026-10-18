"""ODO : orchestrateur universel d'outils et de compétences.

  contrat.py         Outil, ContexteOutil, ResultatOutil, Sensibilite, événements
  registre.py        RegistreOutils, registre_actif (vide en production, phase 1)
  permissions.py     PolitiqueOutils (compte, offre, connexion, outils de test)
  validation.py      validation stricte des arguments (JSON Schema, sans dépendance)
  securite.py        résultats = données : enveloppe, neutralisation, taille, empreinte
  confirmations.py   actions sensibles : confirmation explicite, usage unique (Redis)
  orchestrateur.py   ExecutionODO : boucle bornée modèle ↔ outils, usage additionné
  journal.py         métadonnées seulement
  outils_fictifs.py  outils de test (jamais en production)
  service.py         assemblage pour FastAPI (ODO_ACTIF)

ODO ne parle JAMAIS directement à un fournisseur : il reçoit le fournisseur
déjà choisi par la route (MIA universel, routage par abonnement) et utilise
son contrat commun. MIA ne connaît ni les outils réels ni les permissions.
"""
