# MIA universel — fournisseurs de modèles de langage

MIA universel est la couche commune (`backend/app/llm/`) par laquelle passent
TOUS les appels du backend JARVIS à un modèle de langage. Claude (Anthropic)
est le fournisseur des demandes ordinaires ; GroqCloud reste disponible pour
les tests et les comparaisons autorisés. Aucun basculement automatique.

## Architecture

```text
Flutter (écrit, vocal, JARVIS Touch, WhatsApp)          ← inchangé
  └─ POST /api/v1/chat/stream        (SSE : meta, delta, references, preparation, propositions, done, error)
  └─ POST /api/v1/conversations/{c}/messages/{m}/propositions/completer   (« Reprendre »)
FastAPI
  chat.get_fournisseur  ← en-tête X-Jarvis-Fournisseur (tests autorisés seulement)
  chat_stream           → llm.flux(...)   : Texte… puis Fin(raison, usage, modèle)
  appel_lot             → llm.json(..., schema=generation.schema_lot(...))
  contexts.completer    → completer_ensemble(llm=...) → appel_lot
app/llm/
  base.py        contrat FournisseurLLM, Usage, RaisonArret, erreurs (codes SSE)
  anthropic.py   Claude, SDK officiel `anthropic` (AsyncAnthropic)
  groq.py        GroqCloud, SDK `openai` (AsyncOpenAI, point d'accès Groq)
  selection.py   LLM_PROVIDER, instances partagées, erreurs de configuration
```

Les filtres, validations et règles métier (repères `[[n]]`, correction des
attributions, bloc `<propositions>`, lots, ciblage, consentement) sont
inchangés : ils travaillent sur le texte, quel que soit le fournisseur.

## Comportements garantis

- **Réflexion interne** : jamais diffusée (seuls les `text_delta` de Claude,
  seul `delta.content` de GroqCloud). Elle compte dans le plafond de sortie
  (`LLM_REFLEXION_MARGE_TOKENS` ajoutée) et dans les tokens de sortie (quota).
- **Réponse interrompue** : jamais `done`. Refus du modèle → `error`
  `llm_refus` ; plafond atteint → `error` `llm_incomplet` ; coupure → `error`.
  Le texte déjà reçu est gardé (Flutter : bulle « interrompue »).
- **Limite de débit / surcharge** (429, 529) : attente conseillée, flux
  ouvert (commentaires SSE), nouvel essai SEULEMENT si rien n'a été diffusé.
- **Requête trop grande** (413, « prompt is too long ») : préparation WhatsApp
  réduite une fois.
- **Modèle enregistré** : `messages.model` = modèle réellement servi.
- **Tokens** : entrée = entrée + cache lu + cache écrit ; sortie = sortie
  (réflexion comprise). Quotas Redis / Supabase inchangés.
- **Propositions (Claude)** : `output_config.format` avec un schéma JSON
  strict construit pour chaque lot (seules les longueurs manquantes) ;
  l'exactitude (3 propositions distinctes, longueurs) reste vérifiée par
  `Ensemble.integrer`. GroqCloud : mode JSON simple, comme avant.
- **Rappels du moteur WhatsApp** (message visé, propositions précédentes,
  mémoire) : chez Claude, bloc `<consignes_systeme>` en tête du dernier
  message `user`, jamais dans `system` ; citations importées neutralisées
  (`extraits.citer`), balises impossibles à fermer ou à imiter.

## Configuration (`backend/.env`, jamais commité)

| Variable | Rôle |
|---|---|
| `LLM_PROVIDER` | `anthropic` (défaut) ou `groq` |
| `ANTHROPIC_API_KEY` | clé privée Claude (backend seulement) |
| `ANTHROPIC_MODEL` | modèle Claude (ex. `claude-opus-5-5`) ; aucun modèle imposé par le code |
| `ANTHROPIC_EFFORT` | effort par défaut (`low`…`max`), vide = défaut du modèle |
| `ANTHROPIC_COMPREHENSION_BUDGET_TOKENS` | budget d'entrée WhatsApp avec Claude (20 000) |
| `LLM_REFLEXION_MARGE_TOKENS` | marge de sortie pour la réflexion (8 000) |
| `LLM_EFFORT_PROPOSITIONS` | effort des lots (`low`) |
| `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL` | GroqCloud (tests) |
| `ENVIRONNEMENT`, `LLM_SELECTION_MANUELLE`, `LLM_ADMINS` | choix manuel (ci-dessous) |

Fournisseur non configuré : le chat répond 503 `llm_config` (journal : nom de
la variable manquante), AVANT toute réservation de quota.

## Choix manuel du fournisseur (tests)

En-tête `X-Jarvis-Fournisseur: groq` (console `/console`, scripts) accepté
seulement si `ENVIRONNEMENT` ≠ `production`, `LLM_SELECTION_MANUELLE=true` et
le compte du JWT est dans `LLM_ADMINS` (liste JSON d'identifiants Supabase).
Sinon 403 `fournisseur_interdit`, sans consommer de quota. Flutter n'envoie
jamais cet en-tête (CORS ne l'autorise pas non plus).

## Tests

- Automatiques (sans API réelle) : `test_llm_*` (adaptateurs, vrais SDK,
  transport simulé), `test_mia_chat.py`, `test_mia_whatsapp.py` (routes avec
  Claude simulé : SSE, refus, erreurs, quotas, choix protégé, lots JSON,
  « Reprendre », injections), et toute la suite existante (GroqCloud simulé).
  Lancer avec tout le dépôt monté (`tests_whatsapp/` requis).
- Réels (facturables, manuels) : `backend/scripts/essai_mia.py` contre une
  instance de TEST ; `tests/qualite_comprehension.py` et
  `tests/essai_ciblage_reel.py` (`FOURNISSEUR=anthropic|groq`).

## Instance de test isolée

```bash
docker build -t backend-api:mia-test backend
docker run -d --name jarvis-api-mia --network backend_default -p 8001:8000 --env-file backend/.env -e REDIS_URL=redis://jarvis-redis:6379/1 -e ENVIRONNEMENT=development -v "<dépôt>:/repo:ro" backend-api:mia-test
```

## Déploiement et retour arrière

Avant : `docker tag backend-api:latest backend-api:avant-mia` (fait le
2026-10-17 : image `b2113aa77e17`). Déploiement, depuis `backend/` :

```bash
docker compose build api
docker compose up -d api
```

Contrôle : `/health`, `/health/ready`, journal « Fournisseur IA : anthropic ».

Retours arrière, du plus léger au plus complet :
1. Revenir à GroqCloud sans changer de code : `LLM_PROVIDER=groq` dans
   `.env`, puis `docker compose up -d api` (recréation, quelques secondes).
2. Revenir à l'image précédente : `docker tag backend-api:avant-mia backend-api:latest`
   puis `docker compose up -d --no-build api`.
3. Code : tag Git `sauvegarde-avant-mia-phase2`.
