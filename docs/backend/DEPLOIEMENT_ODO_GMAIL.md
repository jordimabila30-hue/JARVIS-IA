# Déploiement d'ODO et de Gmail sur le backend principal (port 8000)

> Plan préparé le 2026-10-18, **exécuté le 2026-10-18 avec l'accord explicite
> de l'utilisateur** (URI de retour 8000 confirmée par lui dans Google Cloud).
> Résultat : section 9.

## 1. État constaté (lecture seule)

| Élément | État |
|---|---|
| `jarvis-api` (8000) | image `954d097068c5` (= `backend-api:latest` = `backend-api:avant-odo`), créée par Compose (`backend/api`), `.env` du 2026-10-18 14:55 ; `ABONNEMENTS_ROUTAGE=true`, `LLM_PROVIDER=anthropic` ; **sans ODO ni Gmail** (`GET /api/v1/integrations/gmail` → 404) ; `/health/ready` ok |
| `jarvis-api-gmail` (8001) | image `backend-api:gmail-test` (`d257fbec9d0f`), lancée par `docker run` (hors Compose), `ODO_ACTIF=true`, `ENVIRONNEMENT=development`, Redis base 2, `GOOGLE_REDIRECT_URI=http://localhost:8001/…/retour` ; `/health/ready` ok ; route Gmail → 401 sans jeton |
| Code de l'image de test | identique au dépôt au commit `12cf681` (empreintes des 51 fichiers `app/*.py` comparées) |
| Code du dépôt aujourd'hui | + 2 phrases d'ODO : « Paramètres › **Outils** › Gmail » (`odo/service.py`, `odo/outils_gmail.py`) suite à la nouvelle navigation |
| Image candidate | `backend-api:odo-gmail-prod` construite depuis le dépôt actuel ; pytest dedans : **506 réussis, 1 ignoré** (1 test de durée sensible à la charge, réussi seul) |
| Supabase | 9 migrations appliquées, dont `connexions_externes` (2026-10-18) ; 1 connexion Gmail `active`, jeton dans Vault |
| `backend/.env` | `GOOGLE_CLIENT_ID` / `SECRET` présents ; `GOOGLE_REDIRECT_URI` = **8001** ; pas de `ODO_ACTIF` (→ `false`) ; pas d'`ENVIRONNEMENT` (→ `production`) |
| Google Cloud | client « Application Web » ; URI de retour 8001 **et** 8000 déclarées (selon la mise en place du 2026-10-18 ; à reconfirmer dans la console) ; mode Test |

## 2. Ce qui change réellement (pas seulement le port)

1. **Code** : nouvelle image (ODO, Gmail, routes `/api/v1/integrations/gmail*`, `/api/v1/odo/confirmations`).
2. **`.env`** :
   - `GOOGLE_REDIRECT_URI=http://localhost:8000/api/v1/integrations/gmail/retour` ;
   - `ODO_ACTIF=true` ;
   - `ENVIRONNEMENT` laissé absent (= `production` : outils fictifs et choix manuel du fournisseur refusés).
3. **Redis** : base 0 (celle de la production) pour l'état OAuth (`state` + PKCE, quelques minutes). Une connexion Google commencée sur 8001 doit se terminer sur 8001.
4. **Applications** :
   - Windows / Web : `localhost:8000` par défaut (aucune option) ;
   - S10+ : `JARVIS_API_URL=http://127.0.0.1:8000` et `adb reverse tcp:8000 tcp:8000` (le navigateur du téléphone appelle aussi `localhost:8000/…/retour`).
5. **Connexion Gmail existante** : conservée. Elle est dans Supabase (+ Vault), commune aux deux instances, liée au même client Google : aucune reconnexion nécessaire.

L'instance 8001 n'est pas touchée : elle a sa propre URI de retour (`-e GOOGLE_REDIRECT_URI=…8001…`), elle ne relit pas `.env` tant qu'elle n'est pas recréée.

## 3. Sauvegardes (avant toute opération)

```bash
docker tag backend-api:latest backend-api:avant-odo-gmail
cp backend/.env backend/.env.sauvegarde-20261018
docker inspect jarvis-api > backend/.env.inspect-jarvis-api-20261018.json
```

(`.env.*` et le fichier d'inspection restent hors Git ; l'inspection contient des secrets : à effacer après le déploiement.)

## 4. Déploiement (après accord)

```bash
# 1. Image de production = image candidate testée
docker tag backend-api:odo-gmail-prod backend-api:latest
# 2. .env : GOOGLE_REDIRECT_URI → 8000, ajouter ODO_ACTIF=true (édition manuelle, rien d'autre)
# 3. Recréer SEULEMENT l'API (Redis intact, pas de reconstruction)
cd backend && docker compose up -d --no-deps --no-build api
```

Coupure : quelques secondes (recréation du conteneur). Aucune commande de nettoyage, aucun filtre d'image, aucun `docker stop` par motif.

## 5. Vérifications

1. `curl localhost:8000/health/ready` → `ok` ; `curl -o /dev/null -w "%{http_code}" localhost:8000/api/v1/integrations/gmail` → 401.
2. `docker inspect jarvis-api` : image = `odo-gmail-prod`, `ODO_ACTIF=true`, URI 8000.
3. Applis vers 8000 : Paramètres › Outils › Gmail → « Connecté », même adresse (aucune reconnexion).
4. Chat ordinaire (« Quelle heure est-il ? » : local, gratuit) inchangé ; `/me/quota` inchangé.
5. Un seul essai réel facturable « Résume mes 3 derniers mails » (compte Free → GroqCloud), **seulement avec accord**.

## 6. Retour arrière

```bash
docker tag backend-api:avant-odo-gmail backend-api:latest
cp backend/.env.sauvegarde-20261018 backend/.env
cd backend && docker compose up -d --no-deps --no-build api
```

Désactivation partielle possible : `ODO_ACTIF=false` + même commande (Gmail
reste affiché dans l'appli, aucun outil n'est proposé au modèle). Base :
rien à défaire (migration additive, les anciens backends ignorent
`external_connections`) ; la connexion Gmail reste intacte dans Vault.

## 7. Google Cloud

- Vérifier que `http://localhost:8000/api/v1/integrations/gmail/retour` figure bien dans « URI de redirection autorisés » du client « JARVIS serveur » (sinon : `redirect_uri_mismatch`). Aucun autre changement.
- `localhost` ne fonctionne que sur ce PC (et le S10+ via `adb reverse`). Un serveur public exigera une URL HTTPS stable, déclarée chez Google, et `GOOGLE_REDIRECT_URI` identique (hors périmètre).
- Mode Test : jetons de rafraîchissement valables 7 jours → la page affichera « À reconnecter ».

## 8. Après validation

- L'instance 8001 reste en place ; l'arrêter seulement sur demande (`docker stop jarvis-api-gmail`, nom exact).
- Applis remises sur 8000 (S10+ : `adb reverse --remove tcp:8001` quand 8001 n'est plus utilisé).

## 9. Exécution (2026-10-18)

- Sauvegardes : `backend-api:avant-odo-gmail` (= `954d097068c5`), `backend/.env.sauvegarde-20261018` ; fichier d'inspection effacé après coup (secrets).
- `backend-api:latest` = `odo-gmail-prod` (`88cb8709a1e9`) ; `.env` : 2 changements seulement (URI de retour 8000, `ODO_ACTIF=true`).
- `docker compose up -d --no-deps --no-build api` : seul `jarvis-api` recréé ; `jarvis-redis` (8 h) et `jarvis-api-gmail` (8001) non touchés.
- Vérifié : `/health/ready` ok ; `GET /api/v1/integrations/gmail` 401 sans jeton, 200 depuis l'appli ; variables `ODO_ACTIF=true`, `ABONNEMENTS_ROUTAGE=true`, `LLM_PROVIDER=anthropic`, Redis base 0 ; aucune erreur au journal.
- S10+ sur 8000 (`adb reverse tcp:8000 tcp:8000`) : Outils et Gmail « Connecté », même adresse, aucune reconnexion.
- Non fait (facturable, à décider) : un essai réel « Résume mes mails » sur 8000. Non fait : une connexion Google complète via 8000 (la connexion existante n'a pas été touchée).
