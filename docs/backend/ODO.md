# ODO — orchestrateur universel d'outils

Phase 1 (2026-10-18) : moteur universel, outils fictifs, appels d'outils
dans MIA universel. Phase 2 : compétences Gmail en lecture seule
(`docs/backend/GMAIL.md`). **ODO est désactivé en production**
(`ODO_ACTIF=false`).

Responsabilités séparées :

- **MIA universel** (`app/llm/`) parle aux modèles. Il transmet les
  définitions d'outils, lit les appels demandés et renvoie les résultats.
- **ODO** (`app/odo/`) décide :
  - quels outils sont proposés à un compte ;
  - si un appel est permis et valide ;
  - s'il faut une confirmation ;
  - comment exécuter un outil, dans quel délai, et comment présenter
    son résultat au modèle.

ODO ne touche jamais aux SDK des fournisseurs.

## Parcours d'une demande avec outils

```text
Flutter ──POST /api/v1/chat/stream──► chat_stream (JWT, get_fournisseur = routage, enforce_quota)
                                          │ chat ordinaire, ODO actif, outils autorisés ?
                                          ├─ non → llm.flux (chemin actuel, inchangé)
                                          └─ oui → ExecutionODO.flux
                                                    tour 1 : MIA (fournisseur choisi) + définitions
                                                    Fin(OUTIL) → permission, validation, doublon
                                                       lecture → exécution bornée → résultat enveloppé
                                                       action  → confirmation préparée (jamais exécutée)
                                                    budget du jour revérifié → tour 2 … (≤ ODO_MAX_TOURS)
                                                    Fin(FIN) : usage = somme des tours
SSE : meta, delta…, outil (état), confirmation, done | error
Confirmation : POST /api/v1/odo/confirmations/{id} {"decision": "confirmer" | "refuser"}
```

## Fichiers

| Fichier | Rôle |
|---|---|
| `app/odo/contrat.py` | `Outil` (nom, description, schéma, `Sensibilite` LECTURE / ACTION, `offres`, `connexion`, `test_seulement`, `delai`, `executer`, `resume`), `ContexteOutil`, `ResultatOutil`, `Decision`, `EtatOutil`, `DemandeConfirmation` |
| `app/odo/registre.py` | `RegistreOutils` (contrôle à l'enregistrement), `registre_actif` (vide en production, fictifs hors production avec `ODO_OUTILS_FICTIFS=true`) |
| `app/odo/permissions.py` | `PolitiqueOutils` : outil de test en production, offre, connexion externe |
| `app/odo/validation.py` | validation stricte (types, obligatoires, champs inconnus refusés, enum, bornes, listes), sans dépendance |
| `app/odo/securite.py` | `CONSIGNE_OUTILS`, `envelopper` (`<resultat_outil>`, rappel « données »), `neutraliser`, `tronquer`, `empreinte` |
| `app/odo/confirmations.py` | `Confirmations` : Redis `odo:confirmation:{user}:{id}` (TTL), consommation atomique `GETDEL` |
| `app/odo/orchestrateur.py` | `ExecutionODO` (boucle bornée, doublons, budget, interruption), `executer_outil` (délai) |
| `app/odo/journal.py` | métadonnées seulement (outil, statut, durée, taille, 8 caractères de l'identifiant de demande) |
| `app/odo/outils_fictifs.py` | `lecture_fictive`, `recherche_fictive` (volumineux + injection), `action_fictive` (sensible) |
| `app/odo/service.py` | `ServiceODO`, `get_odo` : assemblage pour FastAPI, `ODO_ACTIF` |
| `app/api/v1/odo.py` | `POST /api/v1/odo/confirmations/{id}` |
| `app/api/v1/chat.py` | raccordement autour de `llm.flux`, événements `outil` / `confirmation`, usage des tours |

## Garanties

- **ODO désactivé**, ou aucun outil autorisé pour le compte : chemin du chat
  strictement identique. Pas de champ `tools`, pas de consigne d'outils,
  aucun appel en plus.
- **WhatsApp et consignes de pièce jointe** : jamais d'ODO, la condition
  est `preparation is None and consigne is None`. Testé avec ODO forcé.
- **Identité** : le `ContexteOutil` est construit par le serveur (JWT, offre
  issue de `limites_effectives`). Un argument en trop (`user_id`…) est
  refusé par la validation.
- **Outils proposés** : seulement ceux que la politique autorise. Un appel
  à un autre outil, même présent dans le registre, reçoit « Cet outil n'est
  pas disponible », sans exécution.
- **Résultats = données** :
  - enveloppés dans `<resultat_outil>` et neutralisés, ils ne peuvent ni
    fermer l'enveloppe ni imiter `<consignes_systeme>` ;
  - bornés (`ODO_RESULTAT_MAX_CARACTERES`) ;
  - jamais placés dans le champ système ;
  - une consigne fixe (`CONSIGNE_OUTILS`) est ajoutée au message système du
    début ;
  - un résultat ne peut pas déclencher d'action sans confirmation.
- **Actions sensibles** :
  - préparées, jamais exécutées dans la demande ;
  - le modèle est prévenu (« PAS exécutée ») ;
  - événement `confirmation`, et pièce `odo_confirmation` dans
    `messages.attachments` (restauration en phase 2) ;
  - exécution seulement par `POST /api/v1/odo/confirmations/{id}` : même
    compte (clé Redis par compte), usage unique (`GETDEL`), expiration
    (`ODO_CONFIRMATION_TTL`) ;
  - permission et arguments revérifiés avant exécution ;
  - aucun appel au modèle à ce moment.
  - Sans Redis, aucune action n'est préparée.
- **Garde-fous techniques par demande** (jamais des quotas utilisateur) :
  - `ODO_MAX_TOURS` (erreur `odo_limite`) ;
  - `ODO_MAX_APPELS` (appels en trop refusés) ;
  - `ODO_DELAI_OUTIL` (`delai_depasse`) ;
  - un même appel (même outil, mêmes arguments) n'est exécuté qu'une fois
    par demande ;
  - une panne d'outil devient un résultat d'erreur, sans le texte de
    l'exception.
- **Interruption** : client parti, outil en cours annulé, usage déjà
  consommé compté (`usage_consomme`). Une erreur du fournisseur après des
  outils n'est jamais rejouée en entier (`apres_texte`).

## Comptabilisation

**Une demande utilisateur = un message du jour**, quel que soit le nombre
de tours :

- tokens = somme des tours (`Fin.usage`, cache Claude compris) ;
- le budget du jour est revérifié avant chaque nouveau tour : erreur
  `llm_budget` sans nouvel appel facturable ;
- un seul `record_usage`, par la finalisation existante.

L'exécution d'un outil ne consomme aucun token, et la confirmation d'une
action non plus. Aucun quota de session.

## Paramètres (`backend/.env`)

| Paramètre | Défaut | Effet |
|---|---|---|
| `ABONNEMENTS_ROUTAGE` | `false` | `true` : fournisseur et modèle de l'offre du compte (`plan_config` : Free → GroqCloud, Pro → Claude). `false` : `LLM_PROVIDER` pour tous. **Indépendant d'ODO.** |
| `ODO_ACTIF` | `false` | `true` : outils autorisés proposés au modèle dans le chat ordinaire. `false` : aucun outil, route de confirmation 404. **Indépendant du routage.** |
| `ODO_OUTILS_FICTIFS` | `false` | outils fictifs chargés, **hors production seulement** |
| `ODO_MAX_TOURS` / `ODO_MAX_APPELS` | 4 / 8 | garde-fous par demande |
| `ODO_DELAI_OUTIL` | 10 s | délai d'une exécution |
| `ODO_RESULTAT_MAX_CARACTERES` | 6000 | taille d'un résultat renvoyé au modèle |
| `ODO_CONFIRMATION_TTL` | 300 s | validité d'une action à confirmer |

Les deux fonctions s'activent séparément (modifier `.env`, puis
`docker compose up -d api`) et se désactivent de la même façon.

## Ajouter une compétence (phase 2 : Gmail)

1. Créer une sous-classe d'`Outil` (schéma strict, sensibilité, `connexion`
   si un service externe est requis).
2. L'enregistrer dans `registre_actif`.
3. Fournir les connexions du compte dans `ServiceODO.contexte`.

Ni l'orchestrateur ni MIA ne changent.

## Tests

| Fichier | Contenu |
|---|---|
| `tests/test_odo.py` (24) | boucle, appels multiples, outils non autorisés, arguments invalides, délai, panne, doublons, tours et appels bornés, budget entre les tours, erreur après outils, interruption, injection, troncature, production, confirmations (préparation, usage unique, autre compte, expiration, sans Redis), registre, validation |
| `tests/test_odo_chat.py` (9) | route de chat avec Claude et GroqCloud : multi-tours = 1 message, tokens additionnés ; ODO inactif = inchangé ; confirmation de bout en bout (autre compte 410, double confirmation 410, refus, 404, 401) ; budget épuisé entre deux tours ; injection |
| `tests/test_llm_outils.py` (15) | MIA, deux formats |
| `tests/test_routage.py` (10) | routage Free / Pro de bout en bout, dont « ODO utilise le fournisseur sélectionné » |
| `tests/test_mia_whatsapp.py` | analyse WhatsApp inchangée avec ODO forcé actif |

Contrôle par mutations (copie jetable) : retirer la validation, la
confirmation ou le routage fait échouer respectivement 1, 4 et 8 tests.

## Phase 2 : Gmail (2026-10-18)

- Compétences `gmail_rechercher`, `gmail_lire_message`, `gmail_lire_fil` et
  `gmail_preparer_resume` (`app/odo/outils_gmail.py`, `connexion = "gmail"`).
  Elles sont enregistrées par `registre_actif` dès que les identifiants
  Google sont présents.
- `ServiceODO.contexte_compte` lit l'état réel de la connexion du compte
  (active / à renouveler). Les outils ne sont proposés que si la connexion
  est active. Sinon, `ServiceODO.note` ajoute au message système une phrase
  (« connectez / reconnectez Gmail dans Paramètres › Outils › Gmail »), sans outil ni
  appel supplémentaire.
- `Outil.consigne` : consigne partagée par une famille d'outils
  (`CONSIGNE_GMAIL` : faits / interprétations, rien d'inventé, lecture seule),
  ajoutée au message système quand ces outils sont proposés.
- Validation : `pattern` pris en charge (dates, identifiants Gmail).
- Le résumé est écrit par le modèle de l'abonnement au tour final : aucun
  appel IA supplémentaire.
