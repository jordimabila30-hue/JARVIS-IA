# Abonnements JARVIS Free & Pro

Phase 1 (2026-10-17) : configuration des offres dans Supabase. Le backend ne
la lit PAS encore : quotas, fournisseur IA et comptes existants sont
inchangés. Le raccordement (choix du fournisseur, quotas de session) est la
phase 2 ; les jauges Flutter, la phase 3.

## Table `public.plan_config`

Migration : `supabase/migrations/20261017130000_plan_config.sql`
(additive, ré-exécutable ; retour arrière : `drop table public.plan_config;`).
Une ligne par abonnement (`public.plan_tier` : `free`, `pro`).

| Colonne | Rôle | Free | Pro |
|---|---|---|---|
| `plan` | abonnement (clé : une seule ligne par abonnement) | `free` | `pro` |
| `llm_provider` | fournisseur de MIA universel (`anthropic` ou `groq`) | `groq` | `anthropic` |
| `llm_model` | modèle du fournisseur | `openai/gpt-oss-120b` | `claude-opus-5-5` |
| `daily_message_limit` | messages IA par jour (minuit UTC) | 100 | 200 |
| `daily_token_limit` | tokens IA par jour (entrée + sortie, réflexion comprise) | 50 000 | 100 000 |
| `session_duration_minutes` | durée d'une session (nouvelles sessions) | 300 | 300 |
| `session_message_limit` | messages IA par session | 25 | 50 |
| `session_token_limit` | tokens IA par session | 15 000 | 30 000 |
| `critical_threshold_percent` | seuil critique des jauges (%) | 80 | 80 |
| `updated_at` | dernière modification (automatique) | | |

Contraintes : fournisseur connu ; modèle non vide (100 caractères au plus) ;
limites ≥ 0 ; limites de session ≤ limites quotidiennes ; durée > 0 ; seuil
de 0 à 100 ; aucune valeur vide (une cellule vide ne peut jamais devenir
« illimité » par erreur). Aucune clé API dans la table.

## Modifier une offre soi-même

1. Tableau de bord Supabase → projet « Jarvis » → **Table Editor** →
   schéma `public` → table **`plan_config`**.
2. Double-cliquer sur la cellule (ex. `daily_message_limit` de `free`),
   saisir la valeur, **Save**. `updated_at` se met à jour seul.
3. Une valeur incohérente (seuil 120, session > jour, fournisseur inconnu…)
   est refusée avec le nom de la contrainte.

Changer de fournisseur ou de modèle : `llm_provider` doit être `anthropic`
ou `groq` (noms de `backend/app/llm/selection.py`) ; un nouveau
fournisseur demande d'abord son adaptateur, puis l'ajout à la contrainte
`plan_config_llm_provider_connu`. À partir de la phase 2, une modification
sera prise en compte sans redéploiement (cache de lecture court).

## Sécurité (vérifiée sur la base réelle)

- `anon`, `authenticated` : aucun droit (ni lecture, ni écriture, ni
  TRUNCATE — les droits par défaut de Supabase sont retirés) ; RLS active sans
  politique (avis Supabase « RLS sans politique » : voulu).
- `service_role` (backend) : **lecture seule** ; une clé backend divulguée ne
  modifie pas les offres.
- Modification : administrateur du tableau de bord (éditeur de tables, SQL).
- Abonnement d'un utilisateur : `public.users.plan`, non modifiable par
  l'utilisateur (droit de mise à jour limité à `display_name`, `avatar_url`,
  `preferences`) ; changement par `backend/scripts/set_plan.py` (service_role).

## Priorité entre `plan_config` et les limites d'un utilisateur (phase 2)

État actuel : `public.users.daily_message_limit` / `daily_token_limit` ont des
valeurs PAR DÉFAUT (30 / 50 000) remplies pour tout nouveau compte, et `NULL`
y signifie « illimité ». On ne peut donc pas distinguer une limite choisie
pour un utilisateur d'une valeur par défaut. Le compte Pro existant a des
limites personnalisées (60 messages, 100 000 tokens par jour), conservées.

Règle recommandée (à appliquer en phase 2, avec votre accord sur la
migration) :
1. **Limite personnelle explicite** d'un utilisateur, si elle existe : elle
   prime (dérogation commerciale ou de test).
2. Sinon, **limite de l'offre** (`plan_config` du `plan` de l'utilisateur).
3. « Illimité » : seulement par une dérogation explicite, jamais par défaut.

Pour l'appliquer sans ambiguïté, il faudra rendre la dérogation explicite :
soit des colonnes nullables dédiées (`NULL` = suivre l'offre), soit retirer
les valeurs par défaut des colonnes actuelles et convertir les lignes qui
valent exactement l'ancien défaut (30 / 50 000) — transformation de données
à valider avant. Le compte Pro (60 / 100 000) resterait une dérogation, donc
plus limité que l'offre Pro (200 / 100 000) : à confirmer ou effacer.

## Sessions (préparation de la phase 2)

Une session = fenêtre de temps persistante, ouverte au PREMIER appel IA
facturable (`chat_stream`, `contexts.completer`), d'une durée
`session_duration_minutes` lue à l'ouverture (une modification ne raccourcit
pas une session en cours). Quotas de session et quotidiens indépendants : un
appel doit respecter les deux.

Stockage persistant nécessaire : oui. La session doit être la même sur
Android, Windows, Web et JARVIS Touch, et survivre à un redémarrage du
backend ou à une éviction Redis (comme aujourd'hui `quota_usage` pour les
compteurs du jour). Solution recommandée, sur le modèle du quota quotidien :
- table `public.usage_sessions` (une ligne par session : `user_id`, `plan`,
  `started_at`, `ends_at`, `messages_used`, `tokens_used` ; lecture par
  l'utilisateur de ses lignes, écriture par le backend seulement, comme
  `quota_usage`) avec une fonction atomique « ouvrir ou reprendre la session
  active puis incrémenter » ;
- Redis comme compteur rapide (clé `session:{user}` expirant à `ends_at`,
  réservation atomique en Lua comme `reserve()`), réhydraté depuis la table ;
- l'appareil ne fournit jamais l'heure : seule l'horloge du serveur compte.

## Prêt pour la phase 2

- Lecture de `plan_config` par `service_role` (cache court, ex. 60 s).
- `QuotaService.get_limits` (palier de l'utilisateur, cache Redis) +
  `selection.fournisseur(nom)` : base du choix Free → GroqCloud, Pro → Claude
  (à résoudre avant la réservation du quota, comme `get_fournisseur`).
- Réservation atomique Lua et réhydratation : modèle pour le quota de session.
- `critical_threshold_percent` et les en-têtes `X-Quota-*` : base des jauges.
- Avis Supabase préexistants (hors chantier) : `handle_new_user` et
  `touch_conversation` (fonctions de déclencheur) exécutables par l'API,
  protection des mots de passe divulgués désactivée.
