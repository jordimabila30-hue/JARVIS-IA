# Horloge du serveur et jetons JWT

## Pourquoi c'est important

FastAPI vérifie les jetons Supabase avec une tolérance de **10 s**
(`TOLERANCE_JWT_SECONDES` dans `backend/app/horloge.py`). Si l'horloge de la
machine qui exécute l'API retarde de plus de 10 s, chaque jeton paraît
« émis dans le futur » (`iat`) et il est refusé : `401 Token invalide`. Si
elle avance de plus de 10 s, les jetons paraissent expirés trop tôt.

La tolérance ne doit **pas** être augmentée pour masquer le problème : c'est
l'horloge qu'il faut corriger.

Un conteneur Docker n'a pas d'horloge propre : il partage celle de sa
machine hôte (sous Docker Desktop : la VM WSL2, qui suit Windows). Installer
NTP dans un conteneur ne sert à rien ; on synchronise l'hôte.

## Le diagnostic intégré (non destructif)

- **Mesure** : au démarrage de l'API puis toutes les 15 min, l'en-tête HTTP
  `Date` du serveur qui émet les jetons (Supabase Auth,
  `{SUPABASE_URL}/auth/v1/health`) est comparé à l'heure locale. Précision
  ±1 s environ ; aucune clé envoyée, aucune dépendance ajoutée.
- **Journaux** (`app.horloge`) :
  - `INFO` : écart normal ;
  - `WARNING` : écart > `CLOCK_SKEW_WARN_SECONDS` (5 s par défaut) ;
  - `ERROR` : écart > 10 s : les jetons sont refusés, avec la marche à
    suivre ;
  - `WARNING` si la référence est injoignable (rien n'est bloqué).
- **Refus d'un jeton « émis dans le futur »** (`app.auth`) : la réponse
  reste `401 Token invalide`, mais le journal indique la cause probable et
  le dernier écart mesuré.
- **Supervision** : `GET /health/clock` renvoie l'état (`ok`, `decale`,
  `critique`, `inconnu`, `desactivee`), l'écart, la référence et la date de
  la mesure ; code **503** si l'état est `critique`. `/health` et
  `/health/ready` ne changent pas (le contrôle de santé Docker non plus).

Réglages (facultatifs, `backend/.env`) :

| Variable | Défaut | Rôle |
|---|---|---|
| `CLOCK_REFERENCE_URL` | `{SUPABASE_URL}/auth/v1/health` | Serveur dont l'en-tête `Date` sert de référence |
| `CLOCK_SKEW_WARN_SECONDS` | `5` | Seuil d'alerte |
| `CLOCK_CHECK_INTERVAL` | `900` | Secondes entre deux mesures ; `0` désactive |

Le diagnostic est actif au prochain démarrage de l'API.

## Poste de développement Windows (Docker Desktop + WSL2)

Constat du 13/10/2026 : service **Windows Time arrêté et désactivé**
(`Type = NoSync`) → Windows, la VM WSL2 et le conteneur avaient tous environ
**3 min 20 s de retard**, et FastAPI refusait tous les jetons.

Correction durable (mécanisme natif de Windows, aucun NTP dans les
conteneurs) : **`scripts/windows/synchroniser_horloge.ps1`**, à lancer une
fois dans PowerShell **en administrateur** :

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows\synchroniser_horloge.ps1
```

Il met Windows Time en démarrage automatique, configure trois sources
(`time.windows.com`, `time.cloudflare.com`, `pool.ntp.org`), synchronise
toutes les heures et ajoute la tâche planifiée « JARVIS - Resynchroniser
l'horloge » (au démarrage et au réveil de veille, cause fréquente de
dérive). Relançable sans risque.

Diagnostic (lecture seule, sans droits administrateur) :
**`scripts/windows/verifier_horloge.ps1`** : état du service, écart de
Windows, de la VM WSL2 et du conteneur avec l'heure réelle, et
`/health/clock`. La VM WSL2 suit Windows ; si elle restait décalée,
redémarrer Docker Desktop.

## Horloge des appareils des utilisateurs (Flutter)

FastAPI ne lit jamais l'heure de l'appareil : il vérifie signature et
dates du jeton avec **sa propre horloge**. Le fuseau horaire n'a aucun
effet (tout est en temps universel).

Côté application, `supabase_flutter` décide de renouveler le jeton en
comparant son expiration à l'heure de l'appareil : une horloge fausse
(avancée ou retardée de plus d'une heure) peut donc envoyer des jetons
expirés ou renouveler sans cesse. JARVIS s'en protège sans toucher aux
contrôles de sécurité :

- `HorlogeJetons` (`lib/services/authentification/horloge_jetons.dart`) :
  durée de vie = `exp - iat` (deux dates du serveur), temps écoulé mesuré
  par un chronomètre monotone ; `jetonAcces()` renouvelle à moins d'une
  minute de la fin, sans consulter l'heure de l'appareil ;
- session restaurée au démarrage : on demande au serveur (`getUser`) ; si
  le jeton est refusé, renouvellement avant de conclure (pas de
  déconnexion inutile) ;
- `ApiJarvis` : si FastAPI répond « Token expiré », un renouvellement puis
  une seule nouvelle tentative ; renouvellement impossible → « Votre
  session a expiré. Reconnectez-vous. » et retour à la connexion ;
- écart serveur/appareil estimé (`iat` comparé à l'heure locale) :
  au-delà de 2 min, Paramètres → Compte le signale.

Limite assumée : avec une horloge extrêmement fausse, les connexions HTTPS
elles-mêmes peuvent échouer (certificats jugés « pas encore » ou « plus »
valides) ; JARVIS ne contourne jamais ces contrôles. Sur Android, le
chronomètre monotone peut ne pas compter la veille profonde : le serveur
répond alors « Token expiré » et le renouvellement automatique prend le
relais.

## Serveur de production (Linux)

Synchroniser l'hôte, jamais le conteneur :

- `timedatectl` doit indiquer `System clock synchronized: yes` ;
- service : `systemd-timesyncd` (par défaut sur Ubuntu/Debian) ou `chrony`
  (recommandé sur les serveurs, par ex. Oracle Cloud) ;
- surveiller `GET /health/clock` (503 = jetons refusés) avec l'outil de
  supervision, et les `ERROR app.horloge` dans les journaux ;
- garder la tolérance JWT à 10 s et `CLOCK_CHECK_INTERVAL` actif ;
- `CLOCK_REFERENCE_URL` peut viser un autre serveur de référence si
  Supabase n'est pas joignable depuis l'hébergeur.
