# Abonnements JARVIS Free & Pro

- **Phase 1** (2026-10-17) : configuration des offres dans Supabase (`plan_config`).
- **Phase 2** (2026-10-17) : limites effectives, exceptions explicites, sessions,
  routage MIA par abonnement (activation contrôlée), `/me/quota`, suivi par fournisseur.
- **Phase 3** (2026-10-17) : interface Utilisation Flutter (section 10).
- **Correction** (2026-10-18) : quotas **quotidiens seulement** (sessions
  vidées dans `plan_config`), `users` ↔ `plan_config` synchronisées par
  déclencheurs, Utilisation actualisée sans bouton (section 11).

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

> **Désactivées depuis le 2026-10-18** (migration `20261017200000`) : les
> colonnes de session de `plan_config` sont `NULL`, le backend n'ouvre plus
> aucune session. Mécanisme conservé : remettre une durée le réactiverait.

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

État au 2026-10-18 : étape 1 **faite** — `jarvis-api` (port 8000) sur la
nouvelle image (quotas quotidiens de `plan_config`, `/me/quota` complet),
`ABONNEMENTS_ROUTAGE=false` : Claude sert tous les comptes, Free compris.
Retour arrière du code : image `backend-api:avant-abonnements`.
L'instance de test `jarvis-api-abo` (port 8001) est supprimée ; étape 2
(routage) en attente d'accord.

## 9. Limitations

- GroqCloud : limite de débit **par organisation** (≈ 8 000 tokens / min,
  ≈ 200 000 / jour vus en test), partagée par tous les comptes Free.
- La dernière requête d'une fenêtre peut dépasser légèrement la limite de
  tokens (coût exact connu après) ; bornée par les plafonds de sortie et le
  refus avant appel.
- Avec Redis indisponible, contrôle non atomique sur Supabase (mode dégradé).
- (Corrigé en phase 3 : Flutter affiche la réinitialisation propre à la limite
  atteinte, `detail.resets_at`.)
- Avis Supabase préexistants (hors chantier) : `handle_new_user`,
  `touch_conversation` exécutables par l'API ; protection des mots de passe
  divulgués désactivée.

## 10. Interface Utilisation (Flutter, phase 3)

Paramètres → **Utilisation** (panneau) → **Voir les détails** (page). Tout
vient de `GET /me/quota` : aucune limite, aucun fournisseur ni modèle n'est
écrit dans l'application.

| Fichier | Rôle |
|---|---|
| `lib/models/utilisation/utilisation.dart` | lecture de la réponse (`Utilisation`, `Jauge`, `FournisseurIA`) ; `null` = illimité, rien d'inventé |
| `lib/services/api_jarvis.dart` | `utilisation()` (`GET /me/quota`, jamais l'IA) ; `surConsommation` après chaque opération IA (réponse, interruption, refus, « Reprendre ») ; `messageLimite` (429) |
| `lib/services/utilisation/service_utilisation.dart` | quand relire : ouverture, toutes les 30 s pendant l'affichage, 2 s après une opération IA, retour au premier plan, changement de compte ; suspendu quand l'application est masquée ; jamais de lecture en double |
| `lib/widgets/utilisation/jauge_utilisation.dart` | jauge en lecture seule, animée 450 ms ; bleu (`CouleursJarvis.signal`) puis orange (`CouleursJarvis.critique`) dès `critical_threshold_percent` ; « Limite atteinte » à 100 % |
| `lib/widgets/utilisation/panneau_utilisation.dart` | synthèse : offre, fournisseur et modèle, messages et tokens du jour, remise à zéro, « Voir les détails » (aucun bouton d'actualisation) |
| `lib/pages/utilisation_page.dart` | détail : offre, fournisseur utilisé, journée (restants, prochaine remise à zéro) |

Délai d'affichage d'une modification faite dans Supabase : **≤ 30 s** de
cache serveur + **≤ 30 s** d'actualisation périodique de l'écran ouvert
(mesuré : ≈ 7 s à 35 s sur le S10+).

Limites atteintes (429) : message selon `detail.kind` (messages / tokens, du
jour ou de la session) et SA réinitialisation (`detail.resets_at` : fin de
session, jamais minuit pour une limite de session). La limite d'un
fournisseur IA (événement `error` du flux) reste un message distinct.

Routage par abonnement inactif : la page indique le fournisseur réellement
utilisé (`fournisseur_actif`) en plus de celui de l'offre ; elle n'annonce
jamais un fournisseur qui ne sert pas.

## 11. Quotas quotidiens seulement et synchronisation (2026-10-18)

Migration `supabase/migrations/20261017200000_quotas_quotidiens_synchro.sql`
(appliquée, tests `supabase/tests/70_quotas_quotidiens_synchro_test.sql`) :

- `plan_config.session_*` : facultatives et vidées → aucun quota de session
  (ni hebdomadaire). Jauges Flutter : Messages aujourd'hui, Tokens aujourd'hui.
- `users.daily_message_limit` / `daily_token_limit` = limites EFFECTIVES :
  déclencheur `users_suivre_offre` (création, changement de `plan`, exception
  retirée, écriture à la main sans exception → valeurs de l'offre) et
  `plan_config_propager` (offre modifiée → tous ses comptes sans exception).
  Exception (`limits_override = true`) : valeurs personnelles gardées.
  Fonctions SECURITY DEFINER, non appelables par anon / authenticated.
- Consommation (`quota_usage`, `usage_sessions`, `llm_usage`) jamais touchée.

Flutter : plus de bouton ni de « Mis à jour » ; `ServiceUtilisation` relit à
l'ouverture du panneau et de la page de détails, toutes les 30 s tant que
l'un d'eux est affiché (suspendu quand l'application est masquée, repris au
retour), après chaque réponse IA ou refus de quota, au retour au premier
plan, au changement de compte. Seule la première lecture montre un
chargement ; ensuite les valeurs sont remplacées sur place (jauges animées).
Erreur réseau : dernières valeurs gardées + note discrète « Dernières
valeurs connues : elles peuvent ne plus être à jour. »

## 12. Routage Free / Pro : vérification et activation (ODO phase 1, 2026-10-18)

Revue du code : le routage était déjà correct. `fournisseur_attendu` lit
le fournisseur et le modèle de `limites_effectives`, donc de `plan_config`.
`get_fournisseur` se fonde sur l'identité du JWT ; l'en-tête est réservé aux
tests et aucun repli n'existe (503 `llm_config`). Le cache est de 30 s et
`/me/quota` affiche la même règle. Il manquait seulement :

- au démarrage, avec `ABONNEMENTS_ROUTAGE=true`, une alerte si un
  fournisseur n'est pas configuré (`main.py`) ;
- `python -m scripts.verifier_routage` : pour chaque offre, fournisseur et
  modèle, et adaptateur prêt (sans appel ni clé affichée) ;
- les tests de bout en bout `tests/test_routage.py`.

Instance de test (port 8001, `jarvis-api-test`, image `backend-api:odo-test`,
Redis base 1) : routage actif, ODO inactif. Résultat : Free → `groq /
openai/gpt-oss-120b` prêt, Pro → `anthropic / claude-opus-5-5` prêt, compte
réel (Free) routé vers GroqCloud.

Activation en production (avec accord) : ajouter `ABONNEMENTS_ROUTAGE=true`
dans `backend/.env`, puis `docker compose up -d api` (image de production
actuelle, sans ODO), puis `docker exec jarvis-api python -m
scripts.verifier_routage`. Retour arrière : `ABONNEMENTS_ROUTAGE=false`, puis
`docker compose up -d api`. GroqCloud : limite de débit par organisation,
partagée par tous les comptes Free.

**Activé en production le 2026-10-18 à 13:55:40 UTC** : `ABONNEMENTS_ROUTAGE=true`
dans `backend/.env`, conteneur `jarvis-api` recréé sur la même image
(`954d097068c5`, sans le code ODO). Contrôles sans appel IA : santé ok,
`Routage par abonnement : ACTIF`, deux fournisseurs prêts, Free → groq /
openai/gpt-oss-120b, Pro → anthropic / claude-opus-5-5, compte réel (Free) →
GroqCloud. Retour arrière : `ABONNEMENTS_ROUTAGE=false`, puis `docker compose up -d api`.
