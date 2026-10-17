# Abonnements JARVIS Free & Pro

- **Phase 1** (2026-10-17) : configuration des offres dans Supabase (`plan_config`).
- **Phase 2** (2026-10-17) : limites effectives, exceptions explicites, sessions,
  routage MIA par abonnement (activation contrôlée), `/me/quota`, suivi par fournisseur.
- **Phase 3** (à venir) : jauges Flutter.

Règle : **`plan_config` définit les limites de chaque offre ; `users.plan` dit
à quelle offre appartient un compte.** Une limite personnelle ne s'applique
que si l'exception est activée explicitement.

## 1. Tables et fonctions

| Objet | Rôle | Migration |
|---|---|---|
| `public.plan_config` | une ligne par offre : fournisseur, modèle, limites jour / session, durée de session, seuil critique | `20261017130000_plan_config.sql` |
| `public.users.limits_override` | `false` (défaut) : le compte suit son offre ; `true` : exception (`daily_message_limit` / `daily_token_limit` du compte, `NULL` = illimité) | `20261017160000_abonnements_sessions.sql` |
| `public.limites_effectives(user)` | SEUL calcul des limites appliquées (backend, `get_my_quota`, vue admin) | idem |
| `public.usage_sessions` | sessions (fenêtre, consommation) ; l'utilisateur lit les siennes | idem |
| `ouvrir_session`, `session_active`, `increment_session_usage` | gestion atomique des sessions (backend seulement) | idem |
| `public.llm_usage` + `increment_llm_usage` | tokens entrée / sortie par jour, compte, fournisseur, modèle (coûts estimés) | idem |
| `admin.limites_appliquees` | limites RÉELLEMENT appliquées à chaque compte | idem |
| `admin.consommation_llm` | consommation par jour, fournisseur et modèle | idem |

Valeurs initiales de `plan_config` :

| | Free | Pro |
|---|---|---|
| Fournisseur / modèle | `groq` / `openai/gpt-oss-120b` | `anthropic` / `claude-opus-5-5` |
| Par jour | 100 messages, 50 000 tokens | 200 messages, 100 000 tokens |
| Session | 300 min, 25 messages, 15 000 tokens | 300 min, 50 messages, 30 000 tokens |
| Seuil critique | 80 % | 80 % |

Sécurité (vérifiée sur la base réelle) : `anon` / `authenticated` n'ont aucun
droit sur `plan_config`, `llm_usage`, les fonctions de calcul et de session ;
ils ne peuvent modifier ni `plan`, ni les limites, ni `limits_override`
(droit de mise à jour limité à `display_name`, `avatar_url`, `preferences`).
`service_role` (backend) : lecture de `plan_config`, sessions et suivi
uniquement par les fonctions (aucune écriture directe). Les vues `admin.*`
ne sont lisibles que depuis le tableau de bord.

## 2. Modifier depuis Supabase (Table Editor)

Délai d'application : **30 secondes au plus** (cache Redis des limites,
`QUOTA_LIMITS_CACHE_TTL`), sans redémarrage. Durée de session : vaut pour les
**nouvelles** sessions (celle en cours garde sa fin).

- **Une offre** : table `plan_config` → cellule → *Save*. Exemples : Free
  `daily_message_limit` 100 → 150 ; Pro 200 → 250 ; `session_duration_minutes`
  300 → 360 ; `llm_model`. Les valeurs incohérentes sont refusées (seuil
  > 100, session > jour, fournisseur inconnu, cellule vide…).
- **L'abonnement d'un compte** : table `users` → colonne `plan` (`free` /
  `pro`). Ou : `python -m scripts.set_plan <email> pro` (vide aussi le cache).
- **Activer une exception** : table `users` → `daily_message_limit` /
  `daily_token_limit` (vide = illimité), puis `limits_override` = `true`. Ou :
  `python -m scripts.set_plan <email> pro --messages 500 --tokens 1000000`
  (`--illimite` pour aucune limite quotidienne).
- **Modifier une exception** : changer les deux colonnes (`limits_override`
  reste `true`).
- **Désactiver une exception** : `limits_override` = `false` (les anciennes
  valeurs restent stockées mais ne sont plus lues). Ou : `set_plan <email> pro`.
- **Vérifier ce qui s'applique** : vue `admin.limites_appliquees` (éditeur SQL :
  `select * from admin.limites_appliquees;`). Les colonnes
  `users.daily_*` seules ne disent PAS ce qui s'applique.

Les limites de SESSION sont toujours celles de l'offre (une exception ne
porte que sur les limites quotidiennes).

## 3. Quotas (backend `app/quota.py`)

- `enforce_quota` → `QuotaService.reserve` : limites effectives (cache 30 s),
  puis UN script Lua atomique qui contrôle **jour + session** et compte la
  requête dans les deux (aucun dépassement par appels simultanés, aucun double
  comptage). Réhydratation depuis Supabase si Redis a perdu une clé.
- `record_usage` (une fois par requête, appels internes compris : lots de
  propositions, « Reprendre ») : `quota_usage`, `usage_sessions`, `llm_usage`
  (entrée / sortie, fournisseur, modèle ; jamais bloquant).
- `release` : aucune réponse → la requête est rendue (jour et session).
- Limite atteinte : **429** `{"error": "quota_exceeded", "kind":
  "messages" | "tokens" | "session_messages" | "session_tokens", "resets_in",
  "resets_at", "quota": {…}}` + `Retry-After` (fin de session pour une limite de
  session, minuit UTC sinon).
- Chemins couverts : chat écrit, vocal, JARVIS Touch, analyse WhatsApp (avec
  ses lots), « Reprendre ». Non couverts (aucun appel IA) : échanges locaux,
  enregistrement des pièces jointes.

## 4. Sessions

- Ouverte au **premier appel IA autorisé** (le quota du jour est vérifié
  AVANT : un appel refusé n'ouvre rien), par `ouvrir_session` (verrou par
  compte : deux premiers appels simultanés obtiennent la même session).
- Fin = début + `session_duration_minutes` lue à l'ouverture, **heure du
  serveur**. Exemple : 10 h premier appel → fin 15 h ; limite atteinte à 13 h →
  429 `session_*`, `resets_at` 15 h ; après 15 h, l'appel suivant ouvre une
  nouvelle session.
- Persistante (`usage_sessions`) : fermer l'application, changer d'appareil
  (Android, Windows, Web, JARVIS Touch) ou redémarrer Redis / le backend ne
  change pas la session ; compteurs Redis réhydratés depuis la base.
- Indépendante du jour : renouveler une session ne remet jamais le jour à zéro.
- Les sessions terminées restent en base (historique).

## 5. Routage MIA (`chat.get_fournisseur`)

- `ABONNEMENTS_ROUTAGE=true` : fournisseur et modèle **de l'offre du compte**
  (identité = JWT vérifié, plan = Supabase). Free → GroqCloud
  `openai/gpt-oss-120b`, Pro → Claude `claude-opus-5-5`. Le corps de la
  requête n'y joue aucun rôle ; l'en-tête `X-Jarvis-Fournisseur` reste
  réservé aux tests (hors production, `LLM_SELECTION_MANUELLE`, `LLM_ADMINS`),
  sinon 403. Fournisseur de l'offre non configuré → 503 `llm_config`, **sans
  repli** vers un autre fournisseur.
- `ABONNEMENTS_ROUTAGE=false` (défaut) : `LLM_PROVIDER` pour tous (comportement
  de la production actuelle).
- Clés : `ANTHROPIC_API_KEY` (Pro), `OPENAI_API_KEY` GroqCloud (Free) ; le
  modèle vient de `plan_config` (les `*_MODEL` du `.env` ne servent qu'au
  mode sans routage).

## 6. `/me/quota` (pour les jauges Flutter, phase 3)

Lecture seule (n'ouvre aucune session). Clés historiques conservées, plus :

```json
{
  "plan": "pro", "date": "2026-10-17",
  "messages_used": 1, "messages_limit": 200, "messages_remaining": 199,
  "tokens_used": 46, "tokens_limit": 100000, "tokens_remaining": 99954,
  "resets_in": 36000, "resets_at": "2026-10-18T00:00:00+00:00",
  "llm_provider": "anthropic", "llm_model": "claude-opus-5-5",
  "critical_threshold_percent": 80, "exception": false,
  "session": {"active": true, "id": "…", "started_at": "…", "ends_at": "…",
              "resets_in": 18000, "duration_minutes": 300,
              "messages_used": 1, "messages_limit": 50, "messages_remaining": 49,
              "tokens_used": 46, "tokens_limit": 30000, "tokens_remaining": 29954},
  "fournisseur_actif": {"llm_provider": "anthropic", "llm_model": "claude-opus-5-5",
                        "routage_abonnement": true}
}
```

`llm_provider` / `llm_model` : l'offre ; `fournisseur_actif` : ce qui sert
réellement (diffère tant que le routage est désactivé). Sans session en
cours : `session.active = false`, limites et durée de l'offre. Les événements
SSE `meta` / `done` portent le même objet `quota`. En-têtes ajoutés :
`X-Quota-Session-Messages-Remaining`, `X-Quota-Session-Tokens-Remaining`,
`X-Quota-Session-Reset`.

## 7. Protection financière

Actives : plafonds de sortie (`CHAT_MAX_OUTPUT_TOKENS`,
`COMPREHENSION_MAX_OUTPUT_TOKENS`, lots, marge de réflexion), quotas
jour + session en tokens, **refus avant l'appel** si l'entrée estimée dépasse
déjà les tokens restants (jour ou session, `QuotaService.budget_depasse`),
budget d'entrée WhatsApp par fournisseur, aucun repli vers un autre
fournisseur. Suivi : `llm_usage` / `admin.consommation_llm` (coût estimé =
tokens × tarif ; tarifs non stockés).

À définir (votre décision) : un plafond en dollars (par jour / mois, par
compte ou global) et les limites de dépense dans les consoles Anthropic et
GroqCloud. Les quotas en tokens ne sont pas un plafond financier : un même
token coûte différemment selon le fournisseur, l'entrée ou la sortie.

## 8. Activation et retour arrière

1. Déployer la nouvelle image (`docker compose build api && docker compose up -d api`)
   avec `ABONNEMENTS_ROUTAGE=false` : quotas jour + session de `plan_config`
   actifs, fournisseur inchangé (Claude pour tous).
2. Activer le routage : `ABONNEMENTS_ROUTAGE=true` dans `.env`, puis
   `docker compose up -d api` (vérifier que `OPENAI_API_KEY` GroqCloud est
   présente pour les comptes Free).
3. Retour arrière : `ABONNEMENTS_ROUTAGE=false` + `docker compose up -d api` ;
   code : image `backend-api:avant-mia` / tag Git
   `sauvegarde-avant-abonnements-phase2` ; base : la migration est additive
   (les anciens backends lisent toujours `users`).

Instance de test (isolée) : `jarvis-api-abo`, port 8001, image
`backend-api:abo-test`, Redis base 1, `ABONNEMENTS_ROUTAGE=true`.

## 9. Limitations

- GroqCloud : limite de débit **par organisation** (≈ 8 000 tokens / min,
  ≈ 200 000 / jour vus en test), partagée par tous les comptes Free.
- La dernière requête d'une fenêtre peut dépasser légèrement la limite de
  tokens (coût exact connu après) ; bornée par les plafonds de sortie et le
  refus avant appel.
- Avec Redis indisponible, contrôle non atomique sur Supabase (mode dégradé).
- Flutter actuel : un 429 de session affiche encore l'heure de réinitialisation
  du jour (`quota.resets_in`) ; la phase 3 utilisera `detail.resets_in`.
- Avis Supabase préexistants (hors chantier) : `handle_new_user`,
  `touch_conversation` exécutables par l'API ; protection des mots de passe
  divulgués désactivée.
