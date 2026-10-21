# Passation — validation sur Galaxy S10+ (Windows)

À exécuter par Claude Code / Codex **sur le PC Windows** (Flutter, Android
SDK, ADB, téléphone branché). Le travail précédent a été fait dans un
conteneur cloud sans téléphone : rien de ce qui suit n'a encore été fait.

Branche : `integration/correction-approfondie` (poussée sur GitHub).
Ne pas fusionner dans `main`, pas de force-push, pas de déploiement backend.

## 1. Récupérer sans rien perdre

```powershell
cd <dépôt JARVIS-IA>
git status                      # changements non commités ? → git stash push -u -m "avant-integration"
git fetch origin
git worktree add ..\JARVIS-integration integration/correction-approfondie
cd ..\JARVIS-integration
copy ..\JARVIS-IA\config_locale.json .   # ne jamais afficher son contenu
flutter pub get
```

## 2. Vérifications et build réel

```powershell
flutter doctor -v
adb devices -l                  # le S10+ doit apparaître « device »
flutter analyze
flutter build apk --profile --dart-define-from-file=config_locale.json
```

Le Kotlin modifié (`touch/PerleJarvis.kt`, `BulleJarvis.kt`,
`VocalJarvisTouch.kt`, `FenetresJarvisTouch.kt`, `MoteurJarvis.kt`,
`PontImportation.kt`) n'a été compilé qu'avec kotlinc contre l'API 31 (sans
erreur dans ces fichiers) : **le build Gradle ci-dessus est la première vraie
compilation**. Corriger toute erreur avant de continuer.

Installer SANS effacer les données : `flutter install --profile` ou
`adb install -r build\app\outputs\flutter-apk\app-profile.apk` (jamais
`adb uninstall`). Puis lancer avec mesures :

```powershell
adb reverse tcp:8000 tcp:8000
flutter run --profile --dart-define-from-file=config_locale.json --dart-define=JARVIS_API_URL=http://127.0.0.1:8000
```

## 3. Mesures avant / après (mode profile)

Avant tout correctif de performance : mesurer sur `528b04c^` (ou `d067a85`)
puis sur la branche, mêmes conditions (batterie > 50 %, écran 60 Hz).

- Images : DevTools › Performance (percentiles build/raster, images
  > 16,7 ms) ou `adb shell dumpsys gfxinfo com.example.ia_jarvis reset`
  puis `... gfxinfo com.example.ia_jarvis` après chaque scénario.
- Mémoire : `adb shell dumpsys meminfo com.example.ia_jarvis`.
- Démarrage : `adb shell am start -W -n com.example.ia_jarvis/.MainActivity`.
- Scénarios : démarrage, connexion → accueil, inscription → accueil, menu
  ouvert/fermé, ouverture d'une conversation, défilement long, streaming,
  clavier, PIM, écrit ↔ vocal, Touch, déplacement fenêtre, Kelasi,
  Apparence/fonds.
- Corriger seulement les causes mesurées ; noter avant/après dans
  `AVANCEMENT.md`.

## 4. Parcours fonctionnel (16 corrections)

| # | À vérifier sur le téléphone |
|---|---|
| 2-3 | Compte de TEST dédié : inscription → accueil direct (ou « J'ai confirmé, continuer » si Supabase exige la confirmation) ; adresse déjà utilisée ; mauvais mot de passe ; redémarrage = session gardée ; délai jusqu'à l'accueil utilisable |
| 4-6 | « + » › Ouvrir une application : Instagram, Messenger, Mail (appli installée, sinon Web / composeur), retour à JARVIS. Noter les applis absentes du téléphone |
| 7 | Bulle et fenêtre vocale Touch : perle JARVIS nette, plus de disque bleu à barres |
| 8 | Glisser par l'en-tête et par la perle, bords, rotation, position gardée, boutons toujours actifs |
| 9 | Réduire pendant que JARVIS parle : la phrase se termine, puis micro coupé (icône micro Android éteinte) ; bulle déplaçable ; toucher = vocal rouvert ; Quitter = fin réelle |
| 10 | Pendant la parole : aucun texte de réponse dans la fenêtre ; TalkBack lit la réponse sur la perle |
| 11 | 6+ échanges vocaux → écrit → vocal → écrit : aucune ancienne réponse ne se réécrit ni ne se duplique ; idem après fermeture/réouverture |
| 12 | Voix réelle : nombres, code, liens, réponse longue, arrêt manuel, pas de double lecture |
| 13 | Écrit : « ouvre les paramètres », « ouvre l'agenda », « ouvre Apprendre », « lance Messenger », « nouvelle conversation » ; vocal : « retour au chat écrit » ; Touch vocal : « réduis la fenêtre », « ferme le vocal ». Une vraie question (« comment ouvrir Instagram sur PC ? ») ne doit rien déclencher |
| 14 | Paramètres › Outils › Agenda : « Bientôt disponible », aucune permission |
| 15 | Après REDÉPLOIEMENT du backend (accord requis) : « résume mes mails » (Gmail connecté) → chat sous Gmail ; « comment écrire un e-mail poli ? » → reste sous JARVIS |
| 16 | Après redéploiement : « Elle m'a dit que j'étais drôle, je réponds quoi ? » → 2 à 4 réponses courtes entre guillemets ; idem professeur, ami, patron, excuses, remerciements ; une question ordinaire reste normale |

Plus : Kelasi (ouvrir, une leçon, quitter), Apparence (styles, fonds photo),
PIM stable, WhatsApp import inchangé.

## 5. Livraison

`flutter test`, pytest backend (`OPENAI_MODEL=gpt-4o-mini`), commit des
corrections, `git push origin integration/correction-approfondie`, entrée
datée dans `AVANCEMENT.md` avec les mesures réelles.
