# Audit d'architecture avant ODO

Audit en lecture seule réalisé le 2026-10-18 sur la branche
`integration-backend-unifie`. Aucun code applicatif modifié, aucun service
redémarré, aucun appel à Claude ou GroqCloud, aucune écriture dans Supabase.

Légende utilisée partout :

- **[EXISTE]** : implémenté et vérifié dans le code.
- **[PARTIEL]** : une partie existe (souvent une réservation de place).
- **[MANQUE]** : absent du code.
- **[RECOMMANDÉ]** : proposition pour ODO, rien n'est construit.

---

## 1. Résumé exécutif

- MIA universel (`backend/app/llm/`) est une couche propre et isolée
  (aucune dépendance à FastAPI, Redis, Supabase ni au SSE). Elle a **réservé
  la place des outils** (`DefinitionOutil`, `AppelOutil`,
  `RaisonArret.OUTIL`) mais **ne les implémente pas** : un paramètre
  `outils` non vide lève `NotImplementedError` dans les deux adaptateurs,
  et aucun `AppelOutil` n'est jamais produit.
- Les messages du contrat ne peuvent contenir que du **texte**
  (`Message = Mapping[str, str]`). Le tool calling demande d'étendre ce
  format (blocs d'appel et de résultat), sans casser l'existant.
- La route de chat (`backend/app/api/v1/chat.py`, `chat_stream`) a un point
  d'insertion naturel pour ODO : la boucle `while True` autour de
  `llm.flux(...)` dans `event_stream`. Les battements SSE, la gestion des
  limites de débit, la finalisation en tâche de fond et la comptabilisation
  unique y sont déjà en place.
- Les quotas comptent **1 message et la somme des tokens par demande**, même
  quand une demande fait plusieurs appels au modèle (déjà le cas pour les
  lots de propositions WhatsApp). Ce modèle convient tel quel à ODO.
- Aucune infrastructure OAuth ni de stockage de jetons tiers n'existe. Gmail
  n'existe que comme valeur d'énumération, logo et fournisseur vide.
- Un conflit concret est identifié côté Flutter : le moteur local
  intercepte « résume le dernier mail » et répond « colle-moi la
  conversation » sans jamais interroger le serveur (section 8.3).

**Conclusion : la phase 1 d'ODO peut démarrer sans refonte majeure de MIA
universel.** Il faut une extension ciblée et rétrocompatible du contrat
(format des messages et événement d'appel d'outil), puis l'implémentation
dans les deux adaptateurs. Le reste de MIA (sélection, erreurs, usage,
streaming) se réutilise tel quel.

---

## 2. État actuel vérifié du projet

### 2.1 Git

| Élément | Valeur observée |
|---|---|
| Branche active | `integration-backend-unifie` |
| Dernier commit | `17af89e` docs(abonnements): déploiement du backend en production |
| Commits récents | `2d2b84d` quotas quotidiens + synchro, `d3f519f` Utilisation, `0255922` abonnements phase 2, `e13c3a9` / `ddf844a` MIA |
| Non commité | `comparaison_points_pim.png` seulement (hors chantier) |
| Secrets suivis par Git | aucun (`backend/.env` et `config_locale.json` ignorés, vérifié avec `git check-ignore`) |

### 2.2 Structure du dépôt

- `lib/` : application Flutter (pages, widgets, services, modèles).
- `backend/app/` : API FastAPI.
  - `api/v1/` : `chat.py`, `contexts.py`, `local_exchanges.py`.
  - `llm/` : MIA universel.
  - `comprehension/` : moteur WhatsApp.
  - Fichiers racine : `quota.py`, `auth.py`, `supabase_client.py`, `config.py`, `main.py`.
- `backend/tests/` : 346 fonctions de test pytest (417 cas avec les
  paramétrages, chiffre de la phase 2 validée).
- `supabase/` : `schema.sql`, `migrations/`, `tests/`.
- `android/app/src/main/kotlin/…/` : `MainActivity`, `PontImportation`,
  `touch/` (JARVIS Touch).
- `docs/backend/` : `MIA_UNIVERSEL`, `ABONNEMENTS`, `CONTEXTES_WHATSAPP`,
  `COMPREHENSION_CONVERSATIONNELLE`, `DEPLOIEMENT`, `GUIDE_DEV`, `HORLOGE`,
  `README`.

### 2.3 Dépendances

Backend (`backend/requirements.txt`), versions installées dans `jarvis-api` :

| Paquet | Version |
|---|---|
| fastapi | 0.143.3 |
| pydantic | 2.14.1 |
| anthropic | 1.15.0 (contrainte `>=1.15,<2`) |
| openai | 3.33.0 (pour GroqCloud) |

Autres paquets : redis, httpx, PyJWT[crypto], uvicorn.

Flutter (`pubspec.yaml`) :

- `supabase_flutter`, `http`, `speech_to_text`, `flutter_tts` ;
- `permission_handler`, `shared_preferences`, `file_picker`, `archive` ;
- `web`, `flutter_svg`.
- **Aucun paquet OAuth, `url_launcher` ou de liens profonds.**

### 2.4 Services Docker et environnements

| Conteneur | Image | État | Rôle |
|---|---|---|---|
| `jarvis-api` | `backend-api:latest` = `954d097068c5` | démarré 2026-10-18 12:26:41 UTC, 0 redémarrage, sain | **production, port 8000** |
| `jarvis-redis` | `redis:7-alpine` | sain | compteurs de quota, cache des limites (30 s), contexte court du chat (`ctx:{id}`, 1 h), cache des messages WhatsApp, verrous |

Images de retour arrière : `backend-api:avant-abonnements` (`1e0a52b54b6f`)
et `backend-api:avant-mia`.

**Port 8001 : plus aucun service.** L'instance de test `jarvis-api-abo` et
ses images ont été supprimées. `curl localhost:8001` ne répond pas.

### 2.5 Déploiement des abonnements

Le déploiement est **terminé** (vérifié sans appel à l'IA) :

- `/health` → ok ; `/health/ready` → redis ok, supabase ok ;
- `/me/quota` sans jeton → 401 ;
- CORS `localhost:3000` → 200 ;
- configuration active :
  - `ENVIRONNEMENT=production` ;
  - `LLM_PROVIDER=anthropic` (`claude-opus-5-5`) ;
  - `ABONNEMENTS_ROUTAGE=False` : **Claude sert tous les comptes, Free compris** ;
  - cache des limites 30 s ;
  - choix manuel du fournisseur désactivé, `LLM_ADMINS` vide.
- Les deux fournisseurs sont configurés (clés présentes, valeurs non lues).
- Le modèle GroqCloud est `openai/gpt-oss-120b`, avec une URL de base dédiée.

### 2.6 Rôle de Supabase

- **Auth** : comptes et JWT.
- **Données** : `users`, `conversations`, `messages`, `quota_usage`,
  `conversation_contexts`, `context_messages`, `usage_sessions`,
  `llm_usage`, `plan_config`.
- **RLS** : activée sur les 9 tables. `llm_usage` et `plan_config` n'ont
  aucune politique, volontairement : l'accès passe par `service_role`.
- **Extensions installées** : `pgcrypto`, `supabase_vault`, `uuid-ossp`.
- Le backend utilise la clé `service_role` (`SupabaseAdmin`). Flutter
  n'utilise que la clé publique et la session de l'utilisateur.

---

## 3. Architecture de MIA universel

Fichiers : `backend/app/llm/__init__.py`, `base.py`, `anthropic.py`,
`groq.py`, `selection.py`.

### 3.1 Contrat (`base.py`) [EXISTE]

| Élément | Rôle |
|---|---|
| `FournisseurLLM` (ABC) | `flux(messages, *, max_sortie, effort, outils)` → itérateur asynchrone d'`Evenement` ; `json(messages, *, max_sortie, schema, effort)` → `ReponseJSON` ; `fermer()` |
| Attributs du contrat | `nom`, `modele`, `reflexion_dans_sortie`, `budget_comprehension` |
| `Message` | `Mapping[str, str]` : `{"role": system\|user\|assistant, "content": str}` |
| `Texte(texte)` | fragment visible |
| `Fin(raison, usage, modele, detail)` | une fois, à la fin |
| `RaisonArret` | `FIN`, `LONGUEUR`, `REFUS`, `OUTIL`, `AUTRE` |
| `Usage` | `entree`, `sortie`, `cache_lecture`, `cache_ecriture`, `estime` ; `entree_totale`, `total` |
| `ReponseJSON` | `texte`, `donnees`, `usage`, `modele`, `raison` |
| Erreurs | `ErreurLLM(code, message, fournisseur, apres_texte, statut)` et ses sous-classes `LimiteDebit(attente)`, `RequeteTropGrande`, `Refus`, `ErreurFournisseur` ; codes `llm_*` repris tels quels dans l'événement SSE `error` |
| `DefinitionOutil(nom, description, schema)`, `AppelOutil(id, nom, arguments)` | **[PARTIEL]** types déclarés, jamais utilisés |
| `refuser_outils()` | lève `NotImplementedError` si `outils` est non vide |
| Utilitaires | `verifier_messages()` (rôles et contenu texte obligatoires), `estimer_tokens()`, `lire_json()`, `attente_conseillee()` |

### 3.2 Sélection (`selection.py`) [EXISTE]

- `FABRIQUES = {"anthropic": _anthropic, "groq": _groq}`.
- `creer(nom, settings, modele)` ; `fournisseur(nom, settings, modele)`
  renvoie une instance partagée par couple (fournisseur, modèle).
- `nom_configure()` lit `LLM_PROVIDER`.
- `choix_manuel_possible()` : jamais en production.
- `configures()` : état des fournisseurs, sans aucune valeur.
- `fermer_tous()`.
- Erreurs : `FournisseurInconnu`, `FournisseurNonConfigure` (nomme la
  variable, jamais sa valeur). Aucun repli automatique vers un autre
  fournisseur.
- Le routage par abonnement est fait **hors de MIA**, dans
  `chat.fournisseur_attendu()` et `chat.get_fournisseur()`.

### 3.3 Délais, erreurs, streaming, historique, tokens

| Sujet | Implémentation observée |
|---|---|
| Délais | clients des SDK créés avec `max_retries=0`. Le `timeout` SDK par défaut n'est pas surchargé. `APITimeoutError` → `llm_timeout`. Aucun délai global par appel dans MIA. |
| Limites de débit | `LimiteDebit.attente` lue dans les en-têtes. L'attente est faite par la route (`chat.py:725-734`, plafond `LLM_RATE_LIMIT_MAX_WAIT` = 25 s), jamais après du texte. |
| Streaming | Claude : `messages.stream` ; seuls les `text_delta` deviennent des `Texte`, la réflexion est ignorée. Groq : `stream=True`, `include_usage` ; `delta.reasoning` ignoré. |
| Historique | transmis en entier à chaque appel sous forme de liste de messages texte. Claude : `system` du début extrait, rappels système ultérieurs enveloppés dans `<consignes_systeme>`, rôles consécutifs fusionnés, balise neutralisée. |
| Tokens | `Usage` du fournisseur (cache compris en entrée, réflexion comprise en sortie), sinon estimation à 4 caractères par token (`estime=True`). |

### 3.4 Points d'attention

- La docstring de `llm/__init__.py` dit encore « Phase 1 : les routes
  utilisent leur propre client GroqCloud ». **Elle est périmée** : les
  routes passent par MIA depuis `e13c3a9`. C'est de la documentation
  seulement, le code n'est pas concerné.

---

## 4. Fonctionnement des fournisseurs IA

### 4.1 Claude (`anthropic.py`, `FournisseurAnthropic`)

**[EXISTE]**

- `convertir()` ; `parametres()` (`output_config.effort` si le modèle
  l'accepte, `output_config.format` pour un schéma JSON garanti) ;
  `effort_accepte()`.
- Erreurs : 413 / « prompt is too long », crédit, 429 / 529, 401 / 403, 404.
- `_RAISONS` associe déjà `tool_use` à `RaisonArret.OUTIL`.
- `flux()` lit `get_final_message()` ; `json()` passe par le flux.

**[MANQUE] pour les outils :**

1. Le paramètre `tools` n'est jamais envoyé : `refuser_outils` lève avant.
2. Les blocs `tool_use` de `final.content` ne sont jamais lus et aucun
   `AppelOutil` n'est émis : seul `stop_reason` est converti.
3. Les messages ne peuvent pas porter de blocs `tool_use` (assistant) ni
   `tool_result` (user) : `verifier_messages` exige un `content` texte.
4. **Réflexion et outils.** Le modèle garde sa réflexion adaptative (le
   paramètre `thinking` n'est pas envoyé) et l'adaptateur jette les blocs
   de réflexion. Avec des outils, l'API exige de renvoyer tels quels
   (signature comprise) les blocs `thinking` du tour qui a demandé l'outil.
   **Il faudra conserver `final.content` brut pour le tour suivant.**
5. Les deltas `input_json_delta` ne sont pas gérés en flux. Ce n'est pas
   nécessaire si l'on lit les arguments complets dans `get_final_message()`.

Le SDK 1.15.0 installé fournit tous ces types (vérifié par introspection
de `anthropic.types`, sans appel).

### 4.2 GroqCloud (`groq.py`, `FournisseurGroq`)

**[EXISTE]**

- SDK `openai` 3.33.0 ; `adresse()` ; `_effort_groq()` (`reasoning_effort`
  pour gpt-oss).
- Mode JSON `json_object` avec repli sur du texte relu ; lecture tolérante
  des chunks.
- `_RAISONS` associe déjà `tool_calls` et `function_call` à `OUTIL`.

**[MANQUE] :**

1. `tools` et `tool_choice` ne sont pas envoyés.
2. `delta.tool_calls` n'est pas accumulé : arguments fragmentés par `index`.
3. Les messages `tool` (`tool_call_id`) et `assistant.tool_calls` ne sont pas
   pris en charge.
4. Les arguments JSON ne sont pas validés.

Le SDK 3.33 expose les types (`ChatCompletionFunctionToolParam`,
`ChatCompletionMessageToolCall`…).

### 4.3 Capacités annoncées et capacités vérifiées

| Capacité | SDK | Notre code | Vérifiable sans appel payant |
|---|---|---|---|
| Définitions d'outils | oui (les deux) | **non** | oui (types) |
| Arguments JSON structurés | oui | **non** | oui |
| Résultats d'outil renvoyés au modèle | oui | **non** | oui (format) |
| Échanges successifs LLM ↔ outil | oui | **non** | avec faux serveurs (`tests/faux_llm.py`) |
| Streaming + demande d'outil | oui | **non** | avec faux serveurs |
| Qualité du tool calling de gpt-oss-120b sur Groq | annoncée par Groq | — | **non : nécessite un appel réel**, non fait |
| Respect du schéma `strict` sur Groq | variable selon le modèle | — | **non vérifiable sans appel réel** |

### 4.4 Comment ODO communiquera avec MIA sans fusionner les deux

[RECOMMANDÉ] MIA reste seul à parler aux modèles, ODO reste seul à
connaître les outils et les permissions. Le contrat s'étend ainsi, de façon
rétrocompatible :

1. **Messages.** `content` accepte en plus une liste de blocs normalisés :

   ```text
   BlocTexte(texte)
   BlocAppelOutil(id, nom, arguments)         dans un message assistant
   BlocResultatOutil(id, contenu, erreur)     dans un message user / tool
   BlocBrut(fournisseur, donnees)             réflexion signée, à renvoyer telle quelle
   ```

   Un message texte simple reste valide.
2. **Événement.** `flux()` émet, avant la `Fin(raison=OUTIL)`, un ou
   plusieurs `AppelOutil` complets (jamais d'arguments partiels), plus un
   `TourAssistant(blocs)` qui permet de rejouer le tour exact.
3. **Paramètre.** `outils: Sequence[DefinitionOutil]` est honoré ;
   `refuser_outils` est retiré.
4. **Interdits pour MIA** : connaître les permissions, exécuter un outil,
   décider d'une confirmation.

---

## 5. Architecture du backend et du streaming

### 5.1 Parcours complet d'une question [EXISTE]

```text
Utilisateur
  │ saisie / voix / mini-chat Touch
  ▼
Flutter
  ConversationSession.envoyer (lib/services/conversation/conversation_session.dart:162,
                               file unique _file : un traitement à la fois)
  → MoteurConversationHybride.repondre (moteur_conversation_hybride.dart:35)
      ├─ MoteurConversationLocal.repondreLocalement(avecIA: true)  ← réponse locale possible
      └─ MoteurConversationIA.repondre (moteur_conversation_ia.dart:65)
           → ApiJarvis.discuter (api_jarvis.dart, enveloppé par _consommer → surConsommation)
               POST /api/v1/chat/stream (JWT Supabase) ; lecture decoderSse, inactivité 30 s
  ▼
FastAPI (backend/app/api/v1/chat.py)
  dépendances : get_fournisseur (avant quota) → enforce_quota (reserve) → …
  chat_stream :
    préparation : conversation, load_context (Redis ctx:{id} ou Supabase),
                  contextes WhatsApp, consentement 409, compréhension
    budget_depasse (avant tout appel facturable)
    event_stream :
      meta → boucle llm.flux (avec _avec_battement, LimiteDebit, RequeteTropGrande)
           → delta… → [references] [preparation] [propositions] → done | error
      finally : _spawn(_finalize_safely) → insert_messages, record_usage, append_context
  ▼
MIA universel (app/llm) : FournisseurAnthropic.flux | FournisseurGroq.flux
  ▼
Fournisseur IA (API Messages Claude | GroqCloud compatible OpenAI)
  ▼ (même chemin en retour)
Flutter : TexteEnDirect / EcritureProgressive (affichage mot à mot), TTS en fin
```

### 5.2 Mécanismes

| Sujet | Où | État |
|---|---|---|
| Contexte court | `chat.load_context`, `append_context` : Redis `ctx:{id}`, 20 messages, TTL 1 h ; **texte seulement** | [EXISTE] |
| Battements SSE | `_avec_battement` : commentaire toutes les 10 s ; le client coupe après 30 s de silence | [EXISTE] |
| Reprise | « Reprendre » des propositions : `contexts.completer_propositions` (verrou Redis `propgen:{id}` posé en `NX` pour 180 s, comptabilisation unique) | [EXISTE] |
| Échanges locaux | `local_exchanges.save_local_exchange` : idempotent par `question_id`, `model = "jarvis-local"`, aucun quota | [EXISTE] |
| Erreurs réseau | côté client : `TimeoutException` → `delaiDepasse`, flux coupé → `fluxInterrompu`, texte partiel gardé + `incident` | [EXISTE] |
| Annulation | **aucune annulation explicite par le client.** Une déconnexion stoppe le générateur, et le bloc `finally` enregistre et facture le partiel | [PARTIEL] |
| Asynchrone | tâches de fond `_background_tasks`, attendues à l'arrêt (`wait_background_tasks`) | [EXISTE] |
| Concurrence | quota atomique (script Lua) ; verrous Redis `NX` (propositions) ; côté app, une seule file `ConversationSession._file` | [EXISTE] |
| Événements inconnus côté Flutter | `api_jarvis.dart:743` : `switch` sans `default`, donc **ignorés** sans erreur | [EXISTE] |

### 5.3 Où ODO peut intervenir sans perturber le streaming

[RECOMMANDÉ] Dans `event_stream`, remplacer l'appel unique
`llm.flux(prompt, …)` (`chat.py:710-724`) par une boucle
`OrchestrateurODO.executer(...)` qui :

- relaie les `Texte` exactement comme aujourd'hui (`delta`) ;
- sur `AppelOutil` : n'émet **rien de nouveau dans le texte**, émet un
  événement SSE optionnel `outil` (`{"etat": "en_cours", "nom": …}`,
  ignoré par les anciennes applis), garde des battements pendant
  l'exécution, puis relance `llm.flux` avec le résultat ;
- respecte les mêmes règles : jamais de nouvel essai après du texte
  diffusé, `Fin` obligatoire, `error` et jamais `done` sur un échec.

Les chemins sans outils (chat sans outils autorisés, WhatsApp) restent
**strictement identiques** : la liste d'outils exposée est vide, donc pas
de boucle.

---

## 6. Abonnements et quotas

| Élément | État vérifié |
|---|---|
| `plan_config` | Free : groq / `openai/gpt-oss-120b`, 150 messages / 50 000 tokens. Pro : anthropic / `claude-opus-5-5`, 300 / 100 000. Seuil 80 %. Colonnes de session à `NULL`. |
| `users` | `plan`, `limits_override` ; `daily_*` synchronisées avec l'offre par les déclencheurs `users_suivre_offre` et `plan_config_propager` (migration `20261017200000`) |
| `limites_effectives()` | seule source des limites (offre, sauf exception) |
| `QuotaService` (`quota.py:363`) | `get_limits` (cache 30 s), `reserve`, `budget_depasse`, `record_usage`, `release`, `get_status` |
| Sessions | **désactivées** : `session_duration_minutes` NULL, donc aucune clé de session et aucune ouverture. 0 session ouverte en base. Le code de session reste présent mais inactif. |
| `/me/quota` (`main.py:133`) | état du jour + `fournisseur_actif` |
| 429 | `quota_exceeded(kind)` : `messages` ou `tokens`, avec `resets_at` et `Retry-After` |
| Fournisseur | `fournisseur_attendu` : par l'offre si `ABONNEMENTS_ROUTAGE`, sinon `LLM_PROVIDER` (aujourd'hui Claude pour tous) |
| Comptabilisation | `record_usage` une fois par demande : +1 message, +tokens totaux, `llm_usage` par fournisseur / modèle (+1 requête). Les lots de propositions sont additionnés dans la même demande. |

### Quotas et ODO : appels d'outils sans contournement ni double comptage

[RECOMMANDÉ]

1. **Une demande utilisateur = une réservation** (`enforce_quota`) = **un
   message** compté, quel que soit le nombre de tours LLM ↔ outil.
2. **Tokens = somme de tous les tours LLM** de la demande : chaque `Fin.usage`
   est additionné, comme `lots[0]` / `lots[1]` aujourd'hui. Un seul
   `record_usage` dans le `finally`.
3. **L'exécution d'un outil ne consomme aucun token LLM.**
   - Son coût éventuel (appels Gmail, quotas Google) est suivi à part.
   - Nouveau compteur proposé : `outils_usage` ou une colonne dans `llm_usage`.
   - Il n'est **pas** mêlé aux tokens.
4. **Contrôle entre deux tours.** Avant de relancer le modèle, reprendre
   `budget_depasse` avec les tokens déjà consommés. En cas de dépassement :
   fin propre du flux (`error` `llm_incomplet` ou message « limite
   atteinte »), sans nouvel appel.
5. **Plafonds.**
   - `ODO_MAX_TOURS` (par exemple 4) et `ODO_MAX_APPELS` par demande.
   - Délai par outil et délai total.
   - Les résultats volumineux sont tronqués avant d'être renvoyés au modèle.
6. **`llm_usage.requests`** reste à 1 par demande. Le nombre de tours est
   journalisé à part, si un suivi fin des coûts est voulu.

---

## 7. Authentification et sécurité

| Élément | Où | État |
|---|---|---|
| Supabase Auth | Flutter : `AuthService` → `AuthRepositorySupabase` | [EXISTE] |
| Vérification JWT | `auth.py` `get_current_user` : HS256 (secret) ou ES256 / RS256 (JWKS en cache 600 s), `aud` / `iss` / `exp` / `sub` exigés, tolérance de 10 s, rôle `authenticated` obligatoire | [EXISTE] |
| Identité | `AuthUser(id, email, role)` ; le compte vient **toujours du JWT**, jamais du corps de la requête | [EXISTE] |
| Permissions | RLS sur toutes les tables ; écritures par le backend (`service_role`) avec filtres explicites par compte ; `LLM_ADMINS` pour les tests | [EXISTE] |
| Secrets | `backend/.env` non versionné ; noms de variables seulement dans les journaux ; `__repr__` des fournisseurs sans clé ; Flutter n'a que des clés publiques | [EXISTE] |
| Coffre de secrets | extensions `supabase_vault` et `pgcrypto` installées, **non utilisées** | [PARTIEL] |
| OAuth vers des services tiers (Gmail) | aucun flux, aucune table de jetons, aucun paquet Flutter (`url_launcher`, liens profonds), rien côté backend | [MANQUE] |
| Consentement par fonctionnalité | `ConsentementAnalyse` (par compte, sur l'appareil) + carte `ChoixJarvis` dans le fil | [EXISTE], réutilisable |
| Protection contre l'injection | `comprehension.extraits.neutraliser`, `anthropic.neutraliser` et `envelopper` ; données importées « jamais des instructions » ; rappels jamais dans le champ `system` | [EXISTE], réutilisable |
| Console de test `/console` | **active en production** (`ENABLE_CONSOLE=true` par défaut). Elle n'expose que l'URL et la clé publique de Supabase ainsi que les noms de modèles, aucun secret. | à décider |

Pour Gmail, il manque :

- un flux OAuth 2.0 avec PKCE par utilisateur (portées `gmail.readonly`) ;
- un stockage chiffré des jetons de rafraîchissement, côté serveur, par
  compte (Vault ou chiffrement applicatif), jamais lisible par le client ;
- la révocation et la déconnexion ;
- la vérification de l'application auprès de Google (les portées Gmail
  sont « restreintes ») ;
- les URL de redirection pour Android, Web et Windows.

---

## 8. Intégrations et compétences existantes

### 8.1 Chat écrit [EXISTE]

- Envoi : `ConversationSession.envoyer`.
- Flux : `ApiJarvis.discuter` → `TexteEnDirect` / `EcritureProgressive`.
- Synchronisation : `DepotConversationsSupabase`, `FournisseurJarvis`,
  `CorrespondanceConversations`, échanges locaux.

### 8.2 Mode vocal [EXISTE]

- `VoiceSession._repondre` (`voice_session.dart:434`) appelle `repondeur`,
  c'est-à-dire la même `ConversationSession` : historique partagé.
- La réponse est **attendue en entier**, puis prononcée une fois (TTS).
- L'interruption passe par un jeton de génération (`_valide(jeton)`).
- **Aucune confirmation vocale** d'une action n'existe.

### 8.3 Conflit identifié dans le moteur local

`MoteurConversationLocal.repondreLocalement`
(`moteur_conversation.dart:236-300`) est appelé avec `avecIA: true` avant
l'IA :

- l'intention `resume` est détectée par le mot « résume » ;
- sans conversation collée, `_parleDUneConversation` est vrai si la phrase
  a 3 mots ou moins, ou contient ` mail `, `message`, `conversation`… ;
- résultat : « résume le dernier mail » et « résume mes mails » reçoivent la
  réponse locale « Colle-moi la conversation… », **sans appel au serveur**.

C'est vérifié par lecture du code, pas exécuté. **Point à traiter en
phase 2.**

### 8.4 JARVIS Touch [EXISTE]

- `PasserelleMiniChat` (`jarvis_touch_chat.dart`) passe par
  `ConversationSession.envoyer`, sur le canal `jarvis/touch_chat`.
- Un seul moteur Flutter (`touch/MoteurJarvis.kt`), donc aucun chemin
  backend propre.
- ODO lui sera **transparent** si les confirmations s'affichent aussi
  dans le mini-chat (à prévoir, voir 13).

### 8.5 WhatsApp [EXISTE]

- Import et lecture locaux, filtrage, pièce jointe, stockage
  (`conversation_contexts`, `context_messages`).
- Moteur de compréhension (`app/comprehension/`).
- Références vérifiées, propositions par lots (`generation.py`, sortie JSON
  structurée), « Reprendre », réponses déclarées envoyées, ajouts manuels.
- Aucun appel d'outil : tout est préparé **avant** l'appel au modèle.

### 8.6 Gmail

| Élément | État |
|---|---|
| `SourceConversation.gmail` + `assets/logos/gmail.svg` | [EXISTE] (affichage du menu) |
| `FournisseurNonIntegre(gmail)` : listes vides, jamais « connecté » | [EXISTE] (vide) |
| Écran de connexion, service, import, OAuth | [MANQUE] |

---

## 9. Mécanismes ressemblant à des outils, et leur réutilisation

| Composant | Rôle actuel | Fichiers | Réutilisable ? | Indépendant ? | Risque de conflit |
|---|---|---|---|---|---|
| `VoiceCommandService` + `MoteurConversationLocal` | commandes locales (heure, calcul, prénom, notions, au revoir), sans réseau | `lib/services/voice_command_service.dart`, `conversation/moteur_conversation.dart` | non comme outils ODO (sur l'appareil) | **oui, garder** (prioritaire, hors ligne, sans quota) | **élevé** : interceptions par mots-clés (8.3) |
| `DetecteurIntention` | intention par mots-clés (`reponse`, `resume`, `comprendre`, `analyse`) | `conversation/detecteur_intention.dart` | non | oui | **élevé** : « résume » est capté avant l'IA |
| `ActionRapide`, `ChoixJarvis` + `ConversationSession.choisir` | boutons sous une réponse (accord, refus, réessayer) | `models/message_conversation.dart:84-102`, `conversation_session.dart:1160` | **oui** : modèle pour la carte de confirmation ODO | — | faible |
| `reperes.analyser`, `ciblage.cibler` | indices déterministes avant l'IA (période, message visé) | `backend/app/comprehension/` | non comme outils ; modèle de « décision avant l'appel » | oui | faible |
| `generation.py` + `appel_lot` | appels JSON structurés multiples dans une demande, validation, lots, `LimiteAtteinte` | `comprehension/generation.py`, `chat.py:425` | **oui** (schéma de validation et comptabilisation additionnée) | oui | faible |
| `FiltrePropositions`, `FiltreReperes`, `CorrecteurAttributions` | retirent ou corrigent des blocs dans le flux avant diffusion | `comprehension/propositions.py`, `references.py`, `attribution.py` | **oui** (modèle de filtrage du flux) | oui | moyen si ODO change l'ordre des fragments |
| `completer_propositions` (verrou `NX`, comptabilisation unique) | reprise idempotente | `api/v1/contexts.py:224` | **oui** : modèle anti-doublon d'exécution | — | faible |
| `local_exchanges` (idempotence par `question_id`) | enregistrement idempotent | `api/v1/local_exchanges.py` | **oui** (clés d'idempotence choisies par l'appareil) | — | faible |
| `ConsentementAnalyse` | accord de l'utilisateur par fonction | `conversation/consentement_analyse.dart` | **oui** (modèle des autorisations par outil) | — | faible |
| `DefinitionOutil`, `AppelOutil`, `RaisonArret.OUTIL` | place réservée | `llm/base.py` | **oui**, à compléter | — | aucun |

**Aucun registre de fonctions ni système de tool calling n'existe** : ODO
ne fera pas doublon.

---

## 10. Capacités manquantes

1. Le tool calling dans MIA : format des messages, envoi des outils,
   lecture des appels, renvoi des résultats, réflexion signée (Claude),
   accumulation des deltas (Groq).
2. Le moteur ODO lui-même :
   - registre ;
   - permissions par compte ;
   - validation des paramètres ;
   - confirmations ;
   - exécution bornée ;
   - normalisation des résultats ;
   - journal.
3. Un événement SSE d'état des outils (optionnel) et les cartes de
   confirmation dans l'app, le vocal et Touch.
4. La comptabilisation multi-tours avec contrôle du budget entre les tours.
5. OAuth par utilisateur et coffre des jetons tiers.
6. L'annulation explicite d'une demande en cours, utile si une action
   attend une confirmation.
7. La persistance des tours d'outil : aujourd'hui l'historique Redis et
   Supabase ne garde que du texte.

---

## 11. Architecture ODO recommandée [RECOMMANDÉ]

```text
                        ┌──────────────────────────── Flutter ────────────────────────────┐
                        │ ConversationSession (file unique) ← écrit / vocal / Touch        │
                        │ cartes : ChoixJarvis étendu (Confirmer / Annuler une action)     │
                        └───────────────┬─────────────────────────────────▲───────────────┘
                                POST /api/v1/chat/stream            SSE : meta, delta,
                                        │                            outil (nouveau, optionnel),
                                        ▼                            confirmation (nouveau), done/error
┌────────────────────────────── FastAPI (chat.py) ──────────────────────────────────────────┐
│ auth JWT → get_fournisseur → enforce_quota → préparation (inchangée)                      │
│ event_stream ─► OrchestrateurODO.executer(prompt, outils_autorises, contexte_demande)    │
│                   │  ▲                                                                    │
│                   │  │ Texte / AppelOutil / Fin                                           │
│                   ▼  │                                                                    │
│             MIA universel (app/llm) ──► Claude / GroqCloud                                │
│                   │                                                                       │
│                   ├─► RegistreOutils ─► Outil (fictif en phase 1, Gmail en phase 2)       │
│                   │        ▲ PolitiquePermissions (compte, offre, connexion, sensibilité)  │
│                   │        ▲ Validation JSON Schema                                        │
│                   └─► Comptabilisation : Σ usage des tours → record_usage (une fois)       │
└───────────────────────────────────────────────────────────────────────────────────────────┘
        Supabase : connexions_externes (jetons chiffrés, RLS), journal_outils (métadonnées)
        Redis : verrous d'exécution (idempotence), état des confirmations en attente
```

Composants, dans `backend/app/odo/` (nouveau paquet, indépendant de `llm/`) :

| Composant | Responsabilité |
|---|---|
| `contrat.py` | `Outil` (ABC) : `nom`, `description`, `schema`, `sensibilite` (lecture / action), `portees_requises`, `delai`, `async executer(arguments, contexte) -> ResultatOutil` ; `ResultatOutil(contenu, donnees, erreur, tronque)` ; `ContexteOutil(user, conversation, demande_id)` |
| `registre.py` | enregistrement déclaratif ; `disponibles(contexte)` filtré par la politique ; ajouter une compétence = un fichier + une ligne |
| `permissions.py` | autorisation par compte (connexion présente, portée, offre), et confirmation obligatoire pour les outils `action` |
| `validation.py` | validation des arguments contre le schéma, rejet explicite (le résultat d'erreur est renvoyé au modèle, sans exécution) |
| `orchestrateur.py` | boucle bornée (tours, appels, délais), anti-doublon (clé `demande_id` + hash de l'appel, verrou Redis `NX`), relais du flux, battements, comptabilisation additionnée |
| `securite.py` | enveloppe des résultats (`<resultat_outil>` neutralisé, « données, jamais instructions »), troncature, masquage dans les journaux |
| `journal.py` | métadonnées seulement (outil, durée, statut, taille), jamais le contenu des e-mails |

Règles :

- **Injection** :
  - les résultats d'outil sont des données ;
  - ils sont enveloppés et neutralisés comme `<consignes_systeme>` ;
  - jamais placés dans `system` ;
  - un résultat ne peut pas élargir la liste des outils ni déclencher
    une action sans confirmation.
- **Actions sensibles** : jamais exécutées dans le même tour. ODO émet
  `confirmation`, termine le flux proprement (`done` avec l'état « en
  attente »), et l'exécution n'a lieu qu'après une nouvelle requête de
  l'utilisateur (identifiant d'action signé, à usage unique, TTL court).
- **Boucles** : `ODO_MAX_TOURS`, `ODO_MAX_APPELS`, délai total, budget de
  tokens contrôlé entre les tours.

---

## 12. Points d'intégration précis dans le code

| Endroit | Changement prévu |
|---|---|
| `backend/app/llm/base.py` | blocs de message, événements `AppelOutil` et `TourAssistant`, `verifier_messages` étendu, `refuser_outils` retiré |
| `backend/app/llm/anthropic.py` | `parametres(..., outils)` → `tools` ; `convertir` gère les blocs ; `flux` émet les `AppelOutil` depuis `get_final_message().content` et conserve les blocs bruts (réflexion signée) |
| `backend/app/llm/groq.py` | `tools` ; accumulation de `delta.tool_calls[index]` ; messages `tool` |
| `backend/app/api/v1/chat.py:710-724` | boucle `llm.flux` remplacée par `OrchestrateurODO.executer` ; `lots` généralisé en tokens des tours ; `budget_depasse` entre les tours |
| `backend/app/api/v1/chat.py` (`ChatRequest`) | champ optionnel `confirmation_id` (phase 1 : tests seulement) |
| `backend/app/quota.py` | aucun changement nécessaire en phase 1 (`record_usage` accepte déjà des tokens additionnés) |
| `backend/app/config.py` | `odo_actif` (par défaut `false`), `odo_max_tours`, `odo_max_appels`, `odo_delai_outil` |
| `lib/services/api_jarvis.dart:743` | cas `outil` et `confirmation` (phase 2) ; sans eux, ignorés |
| `lib/services/conversation/moteur_conversation.dart:236` | phase 2 : exceptions pour les demandes Gmail |
| `lib/models/message_conversation.dart:97` | phase 2 : `ChoixJarvis.confirmerAction` / `annulerAction` |

---

## 13. Risques et protections

| Risque | Protection proposée |
|---|---|
| Régression du streaming SSE | ODO activé seulement si des outils sont exposés (`odo_actif` + liste non vide) ; mêmes règles qu'aujourd'hui (pas de nouvel essai après du texte, `Fin` obligatoire) ; tests de contrat existants rejoués |
| Latence | battement pendant les outils (déjà `_avec_battement`) ; délai par outil ; pas d'outil exposé si la question n'en a pas besoin (filtrage du registre) |
| Multiplication des appels LLM | `ODO_MAX_TOURS` ; un seul tour sans outil = coût actuel inchangé |
| Consommation de tokens | somme des tours ; `budget_depasse` entre les tours ; résultats tronqués ; descriptions d'outils courtes |
| Conflits avec les quotas | une réservation par demande, un `record_usage`, `release` si aucune réponse |
| Authentification | compte pris du JWT dans le `ContexteOutil`, jamais des arguments du modèle |
| Fuite entre utilisateurs | chaque outil reçoit `user.id` du contexte ; jetons tiers filtrés par compte (RLS + filtre explicite) ; aucun cache partagé entre comptes |
| Autorisations externes mal gérées | portées minimales (`gmail.readonly`), révocation, jetons chiffrés côté serveur, jamais renvoyés au client |
| Action sans confirmation | sensibilité déclarée par outil ; confirmation hors tour, identifiant à usage unique |
| Exécutions en double | clé d'idempotence (`demande_id` + hash de l'appel), verrou `NX` comme `propgen:` |
| Injection via e-mails | enveloppe neutralisée, consigne « données », pas de chaînage automatique vers une action |
| Android / Web / Windows | événements SSE nouveaux ignorés par les anciennes applis ; OAuth : redirections propres à chaque plateforme (phase 2) |
| Vocal | la confirmation vocale doit être explicite (« dis confirmer ») ou renvoyer à l'écran ; lecture TTS du texte final seulement |
| Conflit avec l'import WhatsApp | ODO désactivé dans les chats à contextes WhatsApp en phase 1 (chemin de compréhension inchangé) |
| Interception locale « mail » | phase 2 : exception explicite dans `_parleDUneConversation` / `DetecteurIntention` quand Gmail est connecté |

---

## 14. Plan technique des deux phases

La séparation en deux phases est **compatible** avec l'architecture
actuelle. Adaptations proposées à l'intérieur de ces deux phases, sans en
ajouter une troisième :

### Phase 1 : moteur universel ODO (aucune intégration réelle)

1. Extension de MIA (`base.py`, `anthropic.py`, `groq.py`) : blocs,
   `AppelOutil`, renvoi des résultats, réflexion signée conservée, deltas
   Groq. Tests avec les faux serveurs (`tests/faux_llm.py`) pour les deux
   formats, sans appel réel.
2. Paquet `app/odo/` : contrat, registre, permissions, validation,
   orchestrateur borné, sécurité, journal.
3. Outils fictifs : `heure` (lecture), `recherche_fictive` (résultat
   volumineux + injection simulée), `action_fictive` (sensible →
   confirmation).
4. Raccordement dans `chat.py` derrière `ODO_ACTIF=false` par défaut ;
   comptabilisation multi-tours ; événements SSE `outil` et
   `confirmation`.
5. Non-régression : suites backend, SQL et Flutter complètes ; contrat MIA
   inchangé pour les appels sans outils.
6. Optionnel, avec ton accord explicite : un essai réel minimal par
   fournisseur pour vérifier le tool calling (coût de quelques centimes).

### Phase 2 : Gmail et intégration dans JARVIS

1. OAuth Google par utilisateur (`gmail.readonly`) :
   - redirections pour Android, Web et Windows ;
   - jetons chiffrés (Vault ou `pgcrypto`) dans une table
     `connexions_externes` avec RLS ;
   - déconnexion et révocation.
2. Outils Gmail en lecture : rechercher, lire un message, lister un fil.
   Résultats normalisés et tronqués.
3. Flutter :
   - écran de connexion (Paramètres) ;
   - fournisseur Gmail réel dans le menu, si cela est voulu ;
   - cartes de confirmation ;
   - exception au moteur local pour « mail ».
4. Vocal (réponse lue à la fin) et Touch (même `ConversationSession`).
5. Validation Android, Windows et Web.

Hors périmètre : envoi, suppression, modification d'e-mails.

---

## 15. Tests de non-régression recommandés

- **MIA** : `tests/test_llm_contrat.py` (le test
  `test_outils_reserves_a_odo` sera remplacé), `test_llm_anthropic`,
  `test_llm_groq`, `test_llm_selection` ; plus de nouveaux tests de contrat
  pour les outils, sur les deux formats.
- **Chat** :
  - `test_chat.py`, `test_mia_chat.py`, `test_mia_whatsapp.py` ;
  - flux sans outils identique octet pour octet (sauf les commentaires de
    battement) ;
  - `done` et `error` inchangés.
- **Quotas** :
  - `test_abonnements.py`, `test_quota.py` ;
  - un message par demande multi-tours, tokens additionnés ;
  - aucun `record_usage` en double ;
  - `release` sans réponse.
- **Sécurité** :
  - injection dans un résultat d'outil ;
  - outil non autorisé demandé par le modèle ;
  - arguments invalides ;
  - action sensible jamais exécutée sans confirmation ;
  - double exécution impossible ;
  - compte A ne lit jamais les connexions de B.
- **Robustesse** : délai d'outil, boucle infinie bornée, déconnexion du
  client pendant un outil, limite de débit entre deux tours.
- **SQL** : `supabase/tests/lancer_tests.sh` (+ tests des futures tables).
- **Flutter** :
  - suite complète ;
  - événements SSE inconnus ignorés ;
  - cartes de confirmation ;
  - vocal et Touch inchangés quand ODO est inactif.

---

## 16. Questions et décisions à valider avant de coder

1. **Fournisseur pour les tests réels du tool calling.** Faut-il autoriser un
   essai réel minimal (Claude et gpt-oss-120b), ou rester en phase 1
   uniquement sur de faux serveurs ?
2. **Routage.** `ABONNEMENTS_ROUTAGE` est inactif : tout le monde est servi
   par Claude. ODO doit-il fonctionner pareil pour Free et Pro, ou les
   outils sont-ils réservés à une offre ?
3. **Confirmation.**
   - Option recommandée : la confirmation se fait hors tour (nouvelle
     requête). Faut-il l'adopter ?
   - En vocal : confirmation orale, ou renvoi à l'écran ?
4. **Persistance des tours d'outil.** Faut-il garder seulement le texte final
   (comme aujourd'hui) ou aussi les tours d'outil (dans
   `messages.attachments`) pour les questions de suivi ?
5. **Activation.** ODO derrière `ODO_ACTIF=false` par défaut, puis activé en
   production avec ton accord, comme les abonnements ?
6. **Coût des outils.** Faut-il un compteur séparé (appels Gmail) et une
   limite par offre ?
7. **WhatsApp.** Faut-il exclure ODO des chats à contextes WhatsApp en phase 1 ?
8. **Console de test.** Faut-il la désactiver en production
   (`ENABLE_CONSOLE=false`) ?
9. **Gmail et Google.** Qui crée le projet Google Cloud et l'écran de
   consentement OAuth ? La vérification des portées restreintes peut
   prendre du temps : elle doit être lancée tôt pour la phase 2.
10. **Annulation.** Ajouter une annulation explicite d'une demande en cours
    (bouton « Arrêter ») dans le périmètre de la phase 2 ?
