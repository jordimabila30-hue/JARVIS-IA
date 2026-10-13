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

Configuration recommandée (PowerShell **en administrateur**) :

```powershell
Set-Service w32time -StartupType Automatic
Start-Service w32time
w32tm /config /manualpeerlist:"time.windows.com,0x9 time.cloudflare.com,0x9 pool.ntp.org,0x9" /syncfromflags:manual /update
# Synchronisation toutes les heures (au lieu de 4 h 30)
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient' SpecialPollInterval 3600
Restart-Service w32time
w32tm /resync /force
w32tm /query /status
```

Vérifier ensuite l'écart : `GET http://localhost:8000/health/clock` (après
redémarrage de l'API), ou les journaux `docker logs jarvis-api`. La VM WSL2
suit Windows ; si elle restait décalée, redémarrer Docker Desktop.

## Serveur de production (Linux)

Synchroniser l'hôte, jamais le conteneur :

- `timedatectl` doit indiquer `System clock synchronized: yes` ;
- service : `systemd-timesyncd` (par défaut sur Ubuntu/Debian) ou `chrony`
  (recommandé sur les serveurs, par ex. Oracle Cloud) ;
- surveiller `GET /health/clock` (503 = jetons refusés) avec l'outil de
  supervision, et les `ERROR app.horloge` dans les journaux.
