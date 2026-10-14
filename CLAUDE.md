# JARVIS — Contexte du projet

## 1. Présentation

JARVIS est un projet d'application d'intelligence artificielle développé avec Flutter.

L'objectif actuel n'est pas encore de connecter l'intelligence artificielle, le backend ou la base de données.

La priorité actuelle est :

> Développer d'abord le frontend de l'application JARVIS.

Le projet doit pouvoir évoluer vers plusieurs plateformes :

- Android
- iOS
- Web
- Windows

---

## 2. Technologie principale

### Frontend

- Framework : Flutter
- Langage : Dart

Pour l'instant, toute la logique de développement doit se concentrer sur l'interface utilisateur, la navigation, les composants visuels, les animations et l'expérience utilisateur.

Ne pas introduire inutilement de backend ou de logique serveur à ce stade.

---

## 3. Philosophie d'architecture

L'application JARVIS sera progressivement divisée en plusieurs grandes parties fonctionnelles.

Dans les discussions du projet, ces grandes parties peuvent être appelées des **moteurs**.

Exemples futurs :

- moteur Conversation
- moteur Importation
- moteur Analyse
- moteur Suggestions
- moteur Historique
- moteur Paramètres

Dans le code Flutter, ces moteurs pourront plus tard être organisés sous forme de modules ou de features.

Pour le moment, l'architecture doit rester simple et adaptée au développement du frontend.

---

## 4. Organisation actuelle des pages

Chaque grande page de l'application doit avoir son propre fichier Dart.

Structure de départ :

```text
lib/
├── main.dart
└── pages/
    └── ecran_de_lancement.dart
```

Le dossier :

```text
lib/pages/
```

contient les différentes pages principales de l'application.

Convention de nommage recommandée pour les fichiers Dart :

```text
nom_de_la_page.dart
```

Exemples futurs :

```text
ecran_de_lancement.dart
accueil_page.dart
conversation_page.dart
importation_page.dart
historique_page.dart
parametres_page.dart
```

Éviter les noms de fichiers avec des espaces ou des majuscules.

---

## 5. Première page à développer

La première page actuellement développée est :

```text
lib/pages/ecran_de_lancement.dart
```

Il s'agit de l'écran affiché au démarrage de JARVIS.

Pour le moment, le travail doit donc se concentrer principalement sur cette page avant de passer aux autres écrans.

L'écran de lancement pourra notamment contenir :

- le nom JARVIS
- le logo de JARVIS
- une identité visuelle futuriste
- des animations d'apparition
- une transition vers la page suivante

Les détails graphiques exacts seront définis progressivement.

---

## 6. Règles pour Claude Code et Codex

Lorsqu'ils travaillent sur ce projet, Claude Code et Codex doivent respecter les règles suivantes :

1. Ne pas modifier l'architecture globale sans nécessité.
2. Garder le code Flutter propre, lisible et organisé.
3. Éviter de mettre toute l'application dans `main.dart`.
4. Une grande page doit avoir son propre fichier.
5. Créer des widgets réutilisables lorsque plusieurs éléments visuels sont répétés.
6. Ne pas ajouter de backend tant que cela n'est pas demandé.
7. Ne pas connecter une API d'IA tant que cela n'est pas demandé.
8. Ne pas ajouter de dépendances Flutter inutilement.
9. Préserver la fluidité de l'application sur mobile, web et desktop.
10. Préférer les composants Flutter responsives plutôt que des dimensions rigides.
11. Expliquer les changements importants avant ou après leur implémentation.
12. Ne pas supprimer du code existant utile sans raison.
13. Respecter les noms et la logique déjà établis dans le projet.
14. Pour le moment, considérer `ecran_de_lancement.dart` comme la priorité frontend.

---

## 7. Performance et fluidité

La séparation des pages en plusieurs fichiers ne ralentit pas l'application.

La performance dépend surtout de la manière dont les widgets, les animations, les images, les listes et les états sont gérés.

Pour garder JARVIS fluide :

- utiliser `const` lorsque possible
- éviter les reconstructions inutiles
- éviter les widgets trop lourds
- optimiser les images
- garder les animations raisonnables
- construire une interface responsive
- séparer les composants réutilisables

---

## 7 bis. Structure actuelle

```text
lib/
├── main.dart                         # JarvisApp, thème, lancement → session → accueil ou connexion
├── pages/
│   ├── ecran_de_lancement.dart       # animation HUD de démarrage
│   ├── accueil_page.dart             # PIM + mode texte / mode vocal (+ bascule conversation)
│   ├── conversation_page.dart        # fil (zone qui défile) + zone PIM réservée au-dessus de la barre
│   ├── importation_whatsapp_page.dart # import WhatsApp : recevoir un export ZIP / TXT, le lire (étape 2), résumé + aperçu
│   ├── resume_whatsapp_page.dart     # résumé facultatif : nom, « N messages · période », discussion en bulles (sans « Vous êtes »)
│   └── authentification/            # parcours (authentification_page), connexion, inscription, mot de passe oublié
├── widgets/
│   ├── pim_particle.dart             # PIM : particules 3D (CustomPainter), forme principale, aperçus
│   ├── pim_dynamique.dart            # PIM : mémoire courte, ondes, cycle des formes secondaires (sans la forme principale)
│   ├── pim_rendu.dart                # PIM : palette, tailles, halos, lumière
│   ├── voice_status.dart             # statut du mode vocal / erreurs micro
│   ├── cadre_hud.dart                # panneau verre + crochets HUD (plus utilisé)
│   ├── bouton_vocal.dart             # capsule vocale (sombre / bleu-violet si chat vocal en arrière-plan ; écoute, parole, envoi)
│   ├── fond_jarvis_anime.dart        # fond de l'accueil, FIXE (mémorisé en image) : ivoire, lavande, nappes, courbes
│   ├── ligne_de_commande.dart        # barre de saisie intelligente : repos (1 ligne) / focus-saisie (dépliée vers le haut)
│   ├── feuille_ajout.dart            # « + » sur téléphone : feuille « Ajouter à JARVIS »
│   ├── defilement_sans_barre.dart    # défilement actif, aucune barre visible (accueil, fil, saisie)
│   ├── menu_lateral.dart             # bouton menu (perle JARVIS) + panneau latéral (voile léger, EN COURS, MES CONVERSATIONS, Paramètres)
│   ├── menu/                         # MES CONVERSATIONS : sélecteur de messageries (vrais logos), recherche, listes qui glissent, ligne (balayage : épingler / supprimer), confirmation
│   ├── conversation/                 # bulle, carte JARVIS, signature « • JARVIS », conversation collée, ton, réponse proposée, heure
│   ├── ecriture/                     # TexteProgressif (texte qui s'écrit, curseur), « Tout afficher »
│   ├── importation/                  # logo WhatsApp, accueil (bouton sous la carte), carte du fichier, « Filtrer » en bas, aperçu de discussion (bulles, jours, médias regroupés)
│   ├── parametres/                   # fenêtre Paramètres (Chat vocal : FR/EN/DE/ES, voix aux noms simples ; formes PIM en tuiles)
│   └── authentification/            # logo, en-tête, conteneur, champ, boutons, bandeau, brouillon des saisies
├── services/
│   ├── voice_session.dart            # boucle écoute → réflexion → parole (répond via la conversation partagée), lecture vocale en mode écrit
│   ├── microphone_service.dart       # permission micro (Android / iOS)
│   ├── niveau_micro*.dart            # volume du micro sur le Web (Web Audio)
│   ├── reconnaissance_navigateur*.dart  # voix → texte sur le Web (API Web Speech directe)
│   ├── speech_recognition_service.dart  # voix → texte (speech_to_text)
│   ├── tts_service.dart              # texte → voix (flutter_tts), applique VoiceSettings
│   ├── voice_settings_service.dart   # réglages vocaux : source de vérité + sauvegarde
│   ├── peripheriques_audio*.dart     # liste des micros (Web uniquement)
│   ├── prosodie.dart                 # rythme et accents des réponses (pour PIM)
│   ├── voice_command_service.dart    # conversation locale (contexte) + futur relais IA
│   ├── conversation/                 # LA conversation (écrit + vocal) : session, détecteurs, analyse, tons, moteurs local / IA / hybride
│   ├── ecriture/                     # écriture progressive : TexteEnDirect (réception), EcritureProgressive (affichage)
│   ├── api_jarvis.dart               # client FastAPI : /me, chat SSE (discuter) ; flux_sse.dart : décodage SSE
│   ├── authentification/            # AuthService, contrat AuthRepository (non configuré), validations, session, ConfigAuth
│   ├── importation/                  # réception (vérification, format, pont Android, dépôt) ; lecture : copie locale, ZIP, analyseur, identité « Moi »
│   ├── conversations/                # multicanal (fournisseurs, tri, recherche, épingles) ; synchro Supabase : dépôt, correspondance local ↔ UUID, liste, file des échanges locaux
│   ├── preferences_pim_service.dart  # forme principale PIM (enregistrée sur l'appareil)
│   └── connaissances_techniques.dart # notions techniques (réponse courte + développement)
├── models/
│   ├── voice_state.dart              # idle / listening / thinking / speaking
│   ├── voice_settings.dart           # réglages vocaux (profil, voix, vitesse…)
│   ├── signal_vocal.dart             # bandes du micro + mots de JARVIS → PIM
│   ├── forme_pim.dart                # sphère, cube, tétraèdre, Réacteur Arc : noms, tirage, durées
│   ├── message_conversation.dart     # messages (écrits ou vocaux), conversation externe, tons, raccourcis
│   ├── authentification/            # UtilisateurAuth, ResultatAuth / ErreurAuth
│   ├── importation/                  # FichierExportWhatsApp (fichier reçu) ; ConversationWhatsApp, MessageWhatsApp (conversation lue)
│   └── conversations/                # SourceConversation (JARVIS, WhatsApp, Gmail, Messenger, Instagram), ApercuConversation
├── utils/
│   ├── local_date_time.dart          # heure, date, salutation en français
│   ├── calcul_vocal.dart             # calculs dictés (chiffres ou lettres)
│   ├── chrono_perf.dart              # sondes de performance (inactives hors banc)
│   ├── taille_fichier.dart           # « 12,4 Ko », « 3,1 Mo »
│   ├── noms_locales.dart             # « fr-CA » → « Français (Canada) », nom de langue, de région
│   └── noms_voix.dart                # « Microsoft Denise Online (Natural)… » → « Denise · Naturelle »
└── theme/
    ├── theme_jarvis.dart             # palette ivoire / graphite / bleu-violet + FondJarvis
    └── gabarit_jarvis.dart           # responsive : formats, tailles de texte, taille de la sphère
```

```text
backend/                              # FastAPI (Docker : jarvis-api + jarvis-redis) — seul backend actif
├── app/                              # auth JWT Supabase, chat SSE (GroqCloud), échanges locaux (/api/v1/conversations/local-exchanges), quotas Redis, horloge.py
├── tests/                            # pytest (60)
├── docker-compose.yml, Dockerfile    # lancer depuis backend/ : docker compose up -d --build
└── .env                              # SECRETS serveur, jamais versionné (modèle : .env.example)
supabase/schema.sql                   # schéma de référence (users, conversations, messages, quota_usage, RLS)
deploy/oracle/                        # déploiement futur (non utilisé pour l'instant)
scripts/windows/                      # synchroniser_horloge.ps1 (admin), verifier_horloge.ps1 (diagnostic)
docs/backend/                         # README, GUIDE_DEV, DEPLOIEMENT, HORLOGE
config_locale.json                    # URL + clé PUBLIQUE Supabase pour Flutter (non versionné ; modèle : config_locale.example.json)
```

```text
tool/
├── banc_perf.dart                    # banc de mesure Web (images, sections du moteur)
├── capture_rendu_test.dart           # non-régression visuelle (captures déterministes)
├── capture_fond_test.dart            # non-régression du fond seul
├── capture_conversation_test.dart    # captures de la conversation écrite (vraies polices)
├── mesure_zone_pim_test.dart         # hauteur réellement dessinée par les PIM au-dessus de la barre
├── capture_barre_test.dart           # captures des états de la barre de saisie
├── capture_apercu_formes_test.dart   # captures de la forme principale (Paramètres) et d'une démonstration
├── capture_menu_test.dart            # captures du menu latéral (dont MES CONVERSATIONS, données de démo)
├── capture_bouton_vocal_test.dart    # captures du bouton vocal et du haut-parleur (chat vocal en arrière-plan)
├── capture_auth_test.dart            # captures des trois pages d'authentification
├── capture_parametres_test.dart      # captures des Paramètres (Chat vocal, formes PIM)
├── capture_importation_test.dart     # captures du menu « + » et de la page d'import WhatsApp (réception, lecture, résultat)
└── diag_tts.dart                     # diagnostic direct de la synthèse vocale sur appareil
```

Performance : mesurer avec `flutter build web -t tool/banc_perf.dart
--dart-define=JARVIS_PERF=true`, vérifier le rendu avec
`CAPTURE_DIR=… flutter test tool/capture_rendu_test.dart` (avant / après).

Règle : la logique vocale reste dans `services/`, jamais dans les pages.

Authentification : Supabase Auth réel. Les pages appellent `AuthService`,
qui appelle `AuthRepository` (`AuthRepositorySupabase` ; sans configuration :
`AuthRepositoryNonConfigure`). Point de bascule unique :
`ConfigAuth.creerRepository()`. Configuration Flutter (publique seulement) :
`--dart-define-from-file=config_locale.json` (`SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEY`, `JARVIS_API_URL` facultatif ; émulateur Android :
10.0.2.2, téléphone USB : `adb reverse tcp:8000 tcp:8000`). Jamais de clé
serveur dans Flutter. Backend : `ApiJarvis` (`GET /me` avec le JWT ;
« Token expiré » → renouvellement + une nouvelle tentative). Durée de vie des
jetons sans l'heure de l'appareil : `HorlogeJetons`. Tolérance JWT du
backend : 10 s, ne pas l'augmenter ; dérive d'horloge : `docs/backend/HORLOGE.md`.
Flutter Web : port 3000 (seule origine CORS autorisée). Accès de
développement « Continuer sans compte » : debug / profile seulement
(`JARVIS_ACCES_DEV`).
Les commandes locales (heure, date…) restent prioritaires sur l'IA.

Conversation IA : `ConversationSession` → `MoteurConversationHybride`
(local d'abord, `reponseLocale(avecIA: true)`) → `MoteurConversationIA` →
`ApiJarvis.discuter` (`POST /api/v1/chat/stream`, SSE). Seul le nouveau
message part ; le serveur garde l'historique (UUID rattaché à l'id local de
la conversation). Écrit et vocal : même moteur. Conversations collées ou
importées : jamais envoyées.

Écriture progressive (phase 4) : toutes les réponses de JARVIS s'écrivent
dans leur bulle. Trois étapes séparées : réception (`TexteEnDirect` :
fragments SSE via `DemandeJarvis.surFragment`, ou texte local complet),
affichage (`EcritureProgressive`, logique pure pilotée par le temps :
mot par mot à 12 mots/s, rythme choisi par l'utilisateur (proche de
ChatGPT) ; seules les réponses très longues accélèrent (≈ 20 s au plus) ;
mot non terminé retenu pendant la réception ; pause quand la carte est
hors de la vue ; « Tout afficher », `remplacer`
pour les futures propositions de ton ; `TexteProgressif` l'anime avec un
Ticker actif seulement quand du texte attend), enregistrement (réponse
finale, une fois, par `ConversationSession`). Une bulle (`redaction: true`)
naît au premier fragment, puis est remplacée avec le même `id`. Coupure :
texte reçu gardé + `incident`, rattaché à l'UUID annoncé par `meta`
(le serveur enregistre le partiel). Markdown inachevé masqué
(`MoteurConversationIA.texteSimpleProvisoire`). TTS : une fois, texte
entier, à la fin de la réception (jamais par fragment). PIM n'est pas lié
à l'écriture. Tests : `test/outils/ecriture.dart` (`finirEcritures`).

Synchronisation des conversations (compte connecté) : Supabase est la
source des conversations enregistrées. Flutter lit et supprime avec la
session de l'utilisateur (`DepotConversationsSupabase`, RLS, jamais de clé
administrative) ; le backend seul écrit les messages : réponses IA (chat
SSE) et échanges locaux (`local-exchanges`, `model = "jarvis-local"`,
identifiants choisis par l'appareil, aucun quota). `ConversationSession`
reste le seul gestionnaire ; `FournisseurJarvis` réunit mémoire et serveur
sans doublon (`CorrespondanceConversations`). Pas d'interrogation
continue : connexion, menu, échange, retour au premier plan (≥ 30 s
masqué). Conversations collées et imports WhatsApp : jamais envoyés.

Conversations multicanal (menu latéral) : le panneau ne connaît que
`ConversationsMulticanal` ; chaque messagerie est un
`FournisseurConversations` (JARVIS : `FournisseurJarvis`, réel ; les autres :
`FournisseurNonIntegre`, listes vides, jamais « connectées »). Ajouter une
source : une valeur de `SourceConversation`, son logo dans `assets/logos/`
(origine notée dans `assets/logos/SOURCES.md`), son fournisseur. Données de
démonstration : `test/fixtures/` uniquement, jamais dans l'application.
« Nouvelle conversation » met la conversation JARVIS de côté (en mémoire,
avec son contexte) au lieu de l'effacer.
Suppression (balayage à gauche ou menu, toujours confirmée) :
`ConversationsMulticanal.supprimer` → `FournisseurConversations.supprimer`
(données locales de JARVIS seulement, jamais d'API externe) + retrait de
l'épingle ; la conversation affichée supprimée ramène l'accueil vide.

Import WhatsApp (bouton « + » → « Importer une conversation », logo
WhatsApp, sans sous-titre) : étape 1 seulement, recevoir un export ZIP ou
TXT et le présenter. Trois sources, un seul chemin : partage Android
(`MainActivity` + `PontImportation.kt`, canal `jarvis/importation`),
sélecteur (natif sur Android, `file_picker` ailleurs), glisser-déposer
(Web : paquet `web` ; Windows : `WM_DROPFILES` dans
`windows/runner/flutter_window.cpp`, canal `jarvis/depot`) →
`FichierBrut` → `SelectionExportWhatsApp.verifier` (taille, puis format
d'après le contenu : `detection_format.dart`) → `ExportWhatsAppChoisi`.
Seuls les 4 premiers Ko sont lus ; `lireContenu()` donne le reste en flux
(une seule lecture) pour l'étape 2. Android : `content://` lu en flux,
aucune copie, aucune permission de stockage ; `singleTask` pour qu'un
partage rejoigne le JARVIS ouvert. L'accueil reçoit les partages
(`ReceptionPartages`) et n'ouvre qu'une page d'import à la fois. Rien
n'est inventé : ni participants, ni messages, ni conversation créée avant
l'analyse réelle du fichier ; aucun envoi hors de l'appareil.

Lecture (étape 2) : `LecteurWhatsApp` copie l'export dans un fichier privé
temporaire (cache ; mémoire sur le Web, `ExportLocal`), puis lit le TXT ligne
à ligne, ou dans un ZIP (paquet `archive`) seulement le fichier de
discussion (index lu, médias jamais décompressés, sortie bornée contre les
bombes, chemins dangereux ignorés, plusieurs TXT plausibles → l'utilisateur
choisit). `AnalyseurWhatsApp` : parseur local déterministe (Android / iOS,
24 h / AM-PM, plusieurs langues, multilignes, système, supprimés, médias) ;
ordre jour/mois déduit des nombres > 12 puis de l'ordre chronologique,
sinon `dateIncertaine` (date brute toujours gardée). Résultat en mémoire
(`importWhatsAppEnCours`) pour le filtrage (étape 3) ; « Moi » mémorisé
par `IdentiteWhatsApp`. Aucune IA, aucun réseau.

---

## 8. État actuel du projet

Décisions déjà prises :

- Nom du projet : JARVIS
- Framework : Flutter
- Langage : Dart
- Étape actuelle : frontend
- Organisation : une page principale par fichier
- Dossier des pages : `lib/pages/`
- Première page : `ecran_de_lancement.dart`

Les éléments suivants seront définis plus tard :

- design complet
- navigation définitive
- autres pages
- moteurs/modules
- backend
- base de données
- authentification
- API d'intelligence artificielle
- logique d'importation des conversations

---

## 9. Suivi d'avancement

Les avancées du projet sont notées dans `AVANCEMENT.md` à la racine.

Après chaque étape importante, ajouter une entrée datée (fait, état, prochaine étape).

---

## 10. Instruction importante

Avant de créer une nouvelle fonctionnalité importante, vérifier si elle appartient bien à l'étape actuelle du projet.

Actuellement :

> priorité au frontend et à l'écran de lancement.

Le projet doit évoluer progressivement, sans construire plusieurs couches techniques en même temps.
