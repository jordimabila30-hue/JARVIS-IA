# Versions de JARVIS

Décision permanente du projet (2026-10-31). Numérotation sémantique
`MAJEURE.MINEURE.CORRECTIF` (voir
https://umvie.com/guide-pratique-pour-numeroter-les-versions-dun-logiciel/).

| Partie | On l'augmente quand… | Remise à zéro |
|---|---|---|
| MAJEURE | évolution importante ou incompatible (données, API, parcours) | MINEURE et CORRECTIF |
| MINEURE | nouvelle fonctionnalité compatible | CORRECTIF |
| CORRECTIF | correction, sécurité, amélioration compatible | — |

Application Flutter : `X.Y.Z+BUILD`, où `BUILD` augmente à CHAQUE build
livrée (jamais réutilisé, jamais diminué : Android refuse une mise à jour
dont le numéro de build n'augmente pas).

## Qui décide

- Le **numéro** d'une nouvelle version est choisi par ChatGPT (responsable
  des versions).
- Claude l'**intègre** techniquement, une fois la livraison identifiée et
  validée (tests réussis, essais réels faits). Jamais à chaque commit.

## Où est la version

Une seule source : `version:` dans `pubspec.yaml`.
Version actuelle : **1.1.0+2** (validée le 2026-10-31, historique dans
`CHANGELOG.md`).

- Android : `versionName` / `versionCode` lus par Gradle (`flutter.versionName`,
  `flutter.versionCode`).
- Windows : `FLUTTER_VERSION*` injectés dans `Runner.rc`.
- Web : `version.json` généré à la build.
- Code Dart : `VersionJarvis` (`lib/utils/version_jarvis.dart`) lit
  `appBuildName` / `appBuildNumber`, constantes injectées par Flutter dans la
  build : le numéro affiché est celui réellement construit. Affichage :
  Paramètres › Général › Version (« 1.1.0 (build 2) ») et écran de lancement
  (« v1.1.0 »). Aucune version écrite à la main ailleurs.
- Serveur : sa version est son commit déployé, `GET /health` → `commit`
  (variable `RENDER_GIT_COMMIT` de Render). Les deux versions sont
  indépendantes : une application installée doit rester compatible avec le
  serveur suivant (événements SSE et champs seulement ajoutés).

Identifiants techniques inchangés : nom du paquet `ia_jarvis`, nom visible
« Jarvis ».

## Publier une version

1. ChatGPT fixe `X.Y.Z` ; `BUILD` = précédent + 1.
2. Modifier `version:` dans `pubspec.yaml` (seul endroit).
3. Ajouter l'entrée dans `CHANGELOG.md` (date, version, changements
   essentiels).
4. Tests : `flutter analyze`, `flutter test`, tests backend si le serveur
   change.
5. Commit `release: X.Y.Z+BUILD`, puis tag annoté `vX.Y.Z` (après accord
   pour pousser).
6. Vérifier après déploiement : Paramètres › Version affiche le bon numéro ;
   `GET /health` donne le commit attendu.
