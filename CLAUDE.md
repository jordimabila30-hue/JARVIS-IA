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
│   ├── resume_whatsapp_page.dart     # « Voir les messages » : discussion en bulles ; .surMessage : ouverte sur un message (référence), éclairé
│   ├── utilisation_page.dart         # « Voir les détails » de l'utilisation (offre, fournisseur, jour, restes, remise à zéro)
│   ├── filtrage_whatsapp_page.dart   # interface 2 : filtrer (par période / par messages), aperçu cochable, compteur, « Continuer vers l'enregistrement »
│   ├── joindre_whatsapp_page.dart    # interface 3 : nom, nombre, période, participants, « Vous êtes : », « Joindre la conversation »
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
│   ├── menu_lateral.dart             # bouton menu (perle JARVIS) + panneau latéral (voile léger, EN COURS, MES CONVERSATIONS, avatar du compte, Paramètres) ; glissement depuis le bord gauche / vers la gauche (doigt seulement)
│   ├── menu/                         # MES CONVERSATIONS : sélecteur de messageries (vrais logos), recherche, listes qui glissent, ligne (balayage court : bouton ; complet ≥ 60 % : épingler / supprimer confirmé), confirmation ; avatar_compte (initiale → Paramètres › Compte)
│   ├── conversation/                 # bulle, carte JARVIS, signature « • JARVIS », conversation collée, ton, réponse proposée, heure, références, propositions par ton (aide à répondre)
│   ├── ecriture/                     # TexteProgressif (texte qui s'écrit, curseur), « Tout afficher »
│   ├── importation/                  # logo WhatsApp, accueil (bouton sous la carte), carte du fichier, « Filtrer » en bas, aperçu de discussion (bulles, jours, médias regroupés) ; filtrage/ : modes, capsules, calendrier, aperçu cochable, barre du bas
│   ├── integrations/                 # Paramètres › Outils (PanneauOutils, OutilJarvis : un outil = une valeur) › Gmail (PanneauGmail : statut, compte, « Gérer la connexion » : changer de compte / déconnecter)
│   ├── parametres/                   # fenêtre Paramètres (Chat vocal : FR/EN/DE/ES, voix aux noms simples ; formes PIM en tuiles ; Confidentialité : accord d'analyse WhatsApp ; Utilisation : jauges de /me/quota ; Apparence : page unique, mode + carrousels styles / motifs + intensité, pages_apparence.dart ; Chat vocal en sections compactes, aperçu ▶ près de la voix ; grille PIM 2 × 2 centrée ; croix = ferme tout (pop), flèche = un niveau)
│   ├── utilisation/                  # jauge (bleu, orange dès le seuil serveur, « Limite atteinte »), panneau Utilisation
│   ├── apparence/                    # TransitionApparence (fondu + reconstruction unique), FriseKuba
│   └── authentification/            # logo, en-tête, conteneur, champ, boutons, bandeau, brouillon des saisies
├── services/
│   ├── voice_session.dart            # boucle écoute → réflexion → parole (répond via la conversation partagée), lecture vocale en mode écrit
│   ├── integrations/                 # ServiceGmail : état Gmail partagé en mémoire (lecture partagée, ≥ 30 s, silencieuse), ouverture de Google (navigateur du système), attente du retour
│   ├── utilisation/                  # ServiceUtilisation : lit /me/quota, quand relire (ouverture, après IA, premier plan, 30 s visible, compte) ; CacheUtilisation : copie locale par compte (affichage immédiat)
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
│   ├── apparence/                    # ServiceApparence (source de vérité, clé jarvis.apparence, mode Système) + PorteeApparence
│   ├── jarvis_touch_service.dart     # JARVIS Touch (Android) : bulle flottante, autorisation, état réel ; natif : android/.../touch/
│   ├── jarvis_touch_chat.dart        # mini-chat de JARVIS Touch : autre vue de LA conversation (canal jarvis/touch_chat ; moteur Flutter du processus : touch/MoteurJarvis.kt)
│   │                                 # « Analyser l'écran » (phase 3A) : 100 % natif, android/.../touch/capture/ (voir plus bas)
│   └── connaissances_techniques.dart # notions techniques (réponse courte + développement)
├── models/
│   ├── voice_state.dart              # idle / listening / thinking / speaking
│   ├── voice_settings.dart           # réglages vocaux (profil, voix, vitesse…)
│   ├── signal_vocal.dart             # bandes du micro + mots de JARVIS → PIM
│   ├── forme_pim.dart                # sphère, cube, tétraèdre, Réacteur Arc : noms, tirage, durées
│   ├── message_conversation.dart     # messages (écrits ou vocaux), conversation externe, tons, raccourcis
│   ├── integrations/                 # EtatGmail (statut, adresse, lecture seule ; jamais de jeton)
│   ├── apparence/                    # PreferencesApparence (mode, style, motif, intensité ; JSON versionné, lecture tolérante)
│   ├── utilisation/                  # Utilisation, Jauge, FournisseurIA (réponse de /me/quota, quotas quotidiens)
│   ├── authentification/            # UtilisateurAuth, ResultatAuth / ErreurAuth
│   ├── importation/                  # FichierExportWhatsApp (fichier reçu) ; ConversationWhatsApp, MessageWhatsApp (conversation lue)
│   └── conversations/                # SourceConversation (JARVIS, WhatsApp, Gmail, Messenger, Instagram), ApercuConversation
├── utils/
│   ├── local_date_time.dart          # heure, date, salutation en français
│   ├── format_utilisation.dart       # « 12 400 », « 2 h 14 min », « demain à 01:00 », phrase de réinitialisation
│   ├── calcul_vocal.dart             # calculs dictés (chiffres ou lettres)
│   ├── chrono_perf.dart              # sondes de performance (inactives hors banc)
│   ├── taille_fichier.dart           # « 12,4 Ko », « 3,1 Mo »
│   ├── noms_locales.dart             # « fr-CA » → « Français (Canada) », nom de langue, de région
│   └── noms_voix.dart                # « Microsoft Denise Online (Natural)… » → « Denise · Naturelle »
└── theme/
    ├── theme_jarvis.dart             # façade CouleursJarvis (suit la palette active), themeJarvis(palette), FondJarvis (+ motif)
    ├── palette_jarvis.dart           # PaletteJarvis (ThemeExtension) : couleurs, fond, identité (frise, ombres pleines, contour, police)
    ├── styles_jarvis.dart            # registre StyleVisuel : JARVIS original + 6 styles importés, chacun clair ET sombre
    ├── motifs_jarvis.dart            # registre MotifJarvis (aucun, Aurore, Kuba 1-3, Cœur Kuba) + dessin des motifs
    └── gabarit_jarvis.dart           # responsive : formats, tailles de texte, taille de la sphère
```

```text
backend/                              # FastAPI (Docker : jarvis-api + jarvis-redis) — seul backend actif
├── app/                              # auth JWT Supabase, chat SSE (MIA universel : Claude par défaut, GroqCloud pour les tests), comprehension/ (WhatsApp → IA), échanges locaux (/api/v1/conversations/local-exchanges), contextes WhatsApp (api/v1/contexts.py, contextes.py), quotas Redis par jour selon l'abonnement (sessions désactivées : plan_config.session_* NULL) (quota.py, limites de plan_config ; routage MIA par abonnement : ABONNEMENTS_ROUTAGE), horloge.py ; llm/ = MIA universel (contrat FournisseurLLM, Claude via `anthropic`, GroqCloud, selection.py ; LLM_PROVIDER=anthropic ; appels d'outils : DefinitionOutil, TourAssistant, ResultatAppel) — raccordé à chat_stream, appel_lot, contexts.completer ; odo/ = ODO (outils : registre, permissions, validation, sécurité, confirmations, orchestrateur, compétences Gmail lecture seule ; ODO_ACTIF=false) ; integrations/ = Google OAuth (Vault) + client Gmail (GET seulement)
├── tests/                            # pytest (571, dont test_llm_*, test_mia_*, test_abonnements avec faux serveurs tests/faux_llm.py ; monter tout le dépôt : tests_whatsapp/ requis ; image backend-api + pytest, pytest-asyncio, fakeredis[lua]) ; essais manuels : qualite_comprehension.py, quota_groq.py, diag_preparation.py, essai_ciblage_reel.py, evaluation_comprehension.py (--reel)
├── docker-compose.yml, Dockerfile    # lancer depuis backend/ : docker compose up -d --build
└── .env                              # SECRETS serveur, jamais versionné (modèle : .env.example)
supabase/schema.sql                   # schéma de référence (users, conversations, messages, quota_usage, RLS)
supabase/migrations/                  # évolutions datées, appliquées : contextes WhatsApp (conversation_contexts, context_messages), offres Free & Pro (plan_config), abonnements phase 2 (limites_effectives, usage_sessions, llm_usage), quotas quotidiens + synchro users ↔ plan_config (déclencheurs)
supabase/tests/                       # tests SQL en PostgreSQL local jetable (lancer_tests.sh, Docker)
deploy/oracle/                        # déploiement futur (non utilisé pour l'instant)
scripts/windows/                      # synchroniser_horloge.ps1 (admin), verifier_horloge.ps1 (diagnostic)
docs/backend/                         # README, GUIDE_DEV, DEPLOIEMENT, HORLOGE, CONTEXTES_WHATSAPP, COMPREHENSION_CONVERSATIONNELLE, MIA_UNIVERSEL, ABONNEMENTS, ODO, GMAIL (+ guide Google Cloud), AUDIT_ARCHITECTURE_ODO
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
├── capture_filtrage_test.dart        # captures de l'interface 2 « Filtrer les messages » (téléphone, ordinateur)
├── capture_joindre_test.dart         # captures de l'interface 3 (page, pièce jointe dans la barre et dans l'historique)
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
Côté serveur, tout appel au modèle passe par MIA universel (`app/llm/`,
doc `docs/backend/MIA_UNIVERSEL.md`) : `chat.get_fournisseur` →
`FournisseurLLM.flux` / `.json` ; Claude (`LLM_PROVIDER=anthropic`) pour les
demandes ordinaires, GroqCloud seulement par l'en-tête
`X-Jarvis-Fournisseur` (hors production, `LLM_SELECTION_MANUELLE`,
`LLM_ADMINS`). Aucun basculement automatique ; réflexion jamais diffusée ;
refus / plafond → `error` (`llm_refus`, `llm_incomplet`), jamais `done`.

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
Balayage d'une ligne (doigt) : court = bouton révélé (à toucher) ;
complet (≥ `LigneConversation.seuilComplet` = 60 % de la ligne, au moins
1,6 bouton) = action au relâchement, une seule fois. Panneau : bande de
24 px (+ zone Retour d'Android) le long du bord gauche, seuil 35 %, lancer
≥ 700 px/s, fin en 180-280 ms ; le balayage d'une ligne ou le défilement
du sélecteur l'emportent sur la fermeture (détecteur le plus proche).
Avatar en bas du panneau : initiale du nom (sinon de l'e-mail, jamais
affiché) → Paramètres › Compte.
Suppression (balayage à gauche — bouton ou complet — ou menu, toujours
confirmée) :
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

Filtrage (étape 3, interface 2) : « Filtrer les messages » ouvre
`FiltrageWhatsAppPage` avec la conversation lue. État : `SelectionWhatsApp`
(`services/importation/selection_whatsapp.dart`), créé et gardé par la page
d'import pour CETTE conversation (retour sans perte ; autre fichier → état
neuf). Moteur pur : `IndexWhatsApp` (index chronologique, comptes par jour,
filtres → positions) ; filtres et résultat : `models/importation/
filtre_whatsapp.dart` (`FiltreJourRelatif`, `FiltreDerniers`,
`FiltrePeriode` à la minute, bornes comprises, `FiltrePlage`,
`MessagesChoisisWhatsApp`). Sélection par identifiants `m<ordre>`, jamais
l'index affiché ; événements WhatsApp non sélectionnables ; dates nulles
jamais dans une période. Widgets : `widgets/importation/filtrage/`. Pas de
traductions Material : dates par le calendrier, heures par un sélecteur
maison (roues / clavier). « Continuer vers l'enregistrement » ouvre l'interface 3 (`surContinuer`
branché par la page d'import) ; rien n'est enregistré.

Pièce jointe (interface 3) : `JoindreWhatsAppPage` → `PieceJointeWhatsApp`
(`models/importation/piece_jointe_whatsapp.dart` : id temporaire, source,
titre, participants, « moi » confirmé, messages originaux choisis). Trois
choses distinctes : messages WhatsApp originaux / pièce jointe / consigne.
L'import se referme et `ouvrirImportationWhatsApp` renvoie la pièce
jointe à l'accueil (`AccueilPage._pieceJointe`, en mémoire) : carte
`PieceJointeEnAttente` dans `LigneDeCommande(pieceJointe:)`, croix =
abandon (texte et chat gardés). Envoi : consigne non vide obligatoire,
`ConversationSession.envoyerAvecPieceJointe` (un seul message
`MessageConversation.pieceJointe`, une seule fois par pièce jointe).
Analyse : voir « Moteur de compréhension conversationnelle » plus bas
(sans compte : JARVIS dit qu'il faut se connecter, rien ne part). Conversation commencée à l'envoi
seulement (accueil vide) ; chat existant gardé. Classement préparé en
mémoire (`classement(id)`, `ClassementConversation`) + événement
`surPieceJointe(EnvoiPieceJointe)` ; contrat `DepotPiecesJointes` sans
implémentation (aucune persistance). Historique :
`CartePieceJointeEnvoyee` + « Voir les messages » (`ResumeWhatsAppPage`,
« moi » à droite).
Panneau : le chat reclassé quitte la liste JARVIS et apparaît sous
WhatsApp, au nom du contact (`FournisseurJarvis.conversationsDe(source)`
d'après `ConversationSession.classement(id)`, identifiant stable, jamais
le titre ; `FournisseurSourceClassee(whatsapp)` délègue ouverture et
suppression à `FournisseurJarvis`). Même chat, même historique, aucune
copie ; l'épingle suit (`EpinglesConversations.deplacer`). En mémoire
seulement : perdu au redémarrage tant que le stockage n'existe pas.

Stockage WhatsApp, phase 1 (base, appliquée le 2026-10-15) :
`conversation_contexts` (contexte joint : propriétaire, conversation,
message JARVIS, contact, groupe, « moi », participants, période sans
fuseau, empreinte) et `context_messages` (messages sélectionnés : rang,
auteur, contenu, type, trace de média, date locale + texte d'origine).
Clés composites (x, user_id) : propriété garantie même pour le backend
(service_role) ; client : lecture et suppression de ses lignes (RLS) ;
écriture par le backend seulement (phase 2 : user_id pris dans le JWT).
Nombre de messages calculé (`admin.contextes_lisibles`), jamais stocké.
Flutter n'écrit pas encore dans ces tables. Reporté volontairement :
retrait du privilège TRUNCATE de `authenticated` sur les anciennes tables.

Phase 2 (backend) : `docs/backend/CONTEXTES_WHATSAPP.md`. Routes
`POST /api/v1/conversations/contexts` (consigne + pièce jointe, chat
existant ou créé), `GET /conversations/{id}/contexts`, `GET /contexts/{id}`,
`GET /contexts/{id}/messages` (pages par rang), `DELETE /contexts/{id}`.
Compte = JWT ; filtres explicites par compte (service_role) ; écriture en
UNE transaction par la fonction `enregistrer_contexte_whatsapp` ;
idempotence par `context_id` choisi par l'appareil. Aucun appel à l'IA.
Tests backend : lancer pytest dans l'image `backend-api` (le `.venv` local
n'existe plus) avec `OPENAI_MODEL=gpt-4o-mini`.

Phase 3 (Flutter, synchronisation) : à l'envoi, `ConversationSession`
appelle `ServicePiecesJointes` (`PiecesJointesApi`, compte connecté) ; le
message n'apparaît qu'après confirmation ; échec : pièce jointe et texte
gardés dans la barre, nouvel essai avec les mêmes UUID
(`PieceJointeWhatsApp.id` / `idConsigne`). `DepotConversationsSupabase` lit
les métadonnées des contextes (RLS) ; un chat qui en a est classé sous
WhatsApp partout ; cartes restaurées sur les consignes ; « Voir les
messages » lit les pages du backend. Détails : `docs/backend/CONTEXTES_WHATSAPP.md`.

Moteur de compréhension conversationnelle (phase 1, backend
`app/comprehension/`, doc `docs/backend/COMPREHENSION_CONVERSATIONNELLE.md`) :
prépare instructions + extraits WhatsApp pour GroqCloud dans la route de
chat existante (pas de nouveau client, pas de nouvelle table). Chat avec
contextes : `whatsapp_analysis` obligatoire (absent → 409
`consentement_requis`, avant tout appel IA ; `declined` → aucun contenu
WhatsApp). Consigne d'une pièce jointe : `reply_to` (jamais réinsérée).
Budget `COMPREHENSION_BUDGET_TOKENS` (compte Groq : 8 000 tokens/min) :
conversation entière si elle tient, sinon aperçu calculé sur tout + extraits
choisis (période, début/fin, mots, échantillons répartis), manques
annoncés. Messages importés = données, jamais instructions. Flutter :
`ConsentementAnalyse` (par compte, sur l'appareil, Paramètres ›
Confidentialité), carte « Autoriser l'analyse / Pas maintenant »
(`ChoixJarvis`, `ConversationSession.choisir`), « Réessayer » sans doublon,
`DemandeJarvis.contexteImporte` (chat WhatsApp : seules les commandes
restent locales).

Phase 2 (attribution et références vérifiées) : une ligne autonome par
message envoyé au modèle (`[12] date heure · auteur : «texte»`), l'auteur
enregistré n'est jamais recalculé. Le modèle cite par `[[12]]` ;
`FiltreReperes` les retire du flux SSE (phrase par phrase, formes
relâchées comprises) ; `verifier` contrôle existence, citation et auteur
avant l'événement `references` (avertissement si une attribution est
contredite). Stockage SANS migration : `messages.attachments` (identifiants
seulement, relus et vérifiés par `GET /conversations/{id}/references`).
« Pourquoi ? » : messages cités par les 2 dernières réponses refournis.
Flutter : `ReferenceWhatsApp`, `ReferencesJarvis` / `CarteReference` sous la
réponse, appui → `ResumeWhatsAppPage.surMessage` (page autour du rang via
`ServicePiecesJointes.page`, message visé au centre du défilement, éclairage
lavande temporaire, retour au chat intact).

Attribution corrigée AVANT diffusion (`app/comprehension/attribution.py`) :
`FiltreReperes(CorrecteurAttributions(fournis))` contrôle chaque phrase
complète (jamais coupée dans une citation) avant l'événement `delta`.
Message (citation ou `[[n]]`) prêté à la mauvaise personne explicite
(nom, « tu ») : phrase REMPLACÉE par une phrase factuelle construite avec
Supabase (« C'est Pepper Potts qui a écrit « mdr ». ») si l'auteur réel est
unique, reformulée si plusieurs auteurs sont possibles, sinon écartée ;
jamais de nom substitué dans la phrase du modèle, citation jamais modifiée.
Interprétations (ton, second degré) non touchées. Texte enregistré =
texte corrigé ; note « J'ai rectifié… ».

Phase 3 (aider à répondre et à relancer) : le modèle comprend la demande
(aucune liste de formulations ; `reperes.aide_reponse` = simple indice de
budget : fin de conversation, +500 tokens de sortie pris sur l'entrée,
même total sous les 8 000 tokens/min). Ligne `Situation` de l'aperçu
(dernier auteur, d'affilée, temps écoulé si dates fiables → réponse ou
relance ; la demande explicite prime). Il écrit 1-2 phrases puis un bloc
`<propositions mode="reponse|relance">` (`# Ton`, `1. [approche] texte
[[n]]`) que `FiltrePropositions` retire du flux ; `analyser` garde
EXACTEMENT 3 propositions distinctes par ton (3-5 tons). Événement SSE
`propositions` ; stockage SANS migration dans `messages.attachments`
(`propositions_reponse`), relu par `GET /conversations/{id}/references`
(`propositions`). Tous les tons d'un coup : changer de ton n'appelle
jamais l'IA. « Pourquoi la deuxième ? » : `<propositions_precedentes>`
redonné au modèle (appuis refournis), `ton_propose` = ton affiché
(`ConversationSession.regarderTon`). Flutter : `PropositionsReponse`
(via `ReferencesReponse.propositions`), `MessageConversation.propositions`,
`PropositionsJarvis` / `CarteProposition` sous la réponse (capsules de
ton, 3 cartes, « Copier »). Chaque proposition a un `id` unique et stable
(uuid4 ; anciennes propositions : uuid5 déterministe du message, du ton et
du rang). « Pourquoi la deuxième ? » : l'appli envoie la référence
EXPLICITE `propositions_message_id` + `ton_propose` ; le serveur vérifie
compte et chat (`get_assistant_message`), désigne « PROPOSITION VISÉE
(identifiant …) » juste avant la question ; une proposition mal recopiée
par le modèle est rétablie mot pour mot (`CorrecteurAttributions._retablir`).

Phase 4 (réponses déclarées envoyées) : appui long ~800 ms sur la CARTE
d'une réponse (`CarteProposition` : barre de progression, relâcher ou
défiler = annulé, vibration légère ; Web / Windows : bouton « Marquer
envoyée »). `ConversationSession.declarerEnvoyee` →
`ServiceReponsesEnvoyees` (`ReponsesEnvoyeesApi`) → `PUT` / `DELETE
/api/v1/conversations/{c}/messages/{m}/propositions/{p}/envoyee`
(idempotent, 404 hors compte / chat). « Envoyée » (coche + Annuler)
seulement après confirmation du serveur ; jamais d'envoi WhatsApp.
Stockage SANS migration : entrée `reponse_envoyee` (statut
`declaree_envoyee` / `annulee`, texte, ton, contact, contexte, chat,
message, compte, dates) dans `messages.attachments` de la réponse aux
propositions — jamais dans `context_messages`. Restauration : `envoyee`
(date) sur chaque proposition de `GET /references` ; l'actualisation
reprend les statuts changés ailleurs. Mémoire : `memoire.pour_contacts`
(toutes conversations du compte, même contexte ou même contact) →
`<reponses_declarees_envoyees>` juste avant la question (« déclarée, non
vérifiée », pas de répétition, ton non permanent ; message retrouvé dans
un nouvel export → « ne la compte pas deux fois »).

Campagne de tests (2026-10-16) : `tests_whatsapp/` (5 ZIP fictifs, Alex
Martin ; `generer.py`, `manifeste.json`, `faux_groq.py`, README). Tests :
`test/campagne_whatsapp_test.dart` (parseur réel), `backend/tests/test_campagne.py`.
Corrections issues de la campagne : recherche par mots pondérée par la
rareté (IDF, `extraits.selectionner`) ; bloc de propositions : exemple
« Ton : Naturel » (les instructions interdisent les titres Markdown) et
lecture tolérante (`[Naturel] 1. …`, puces, titres sans « # ») + journal
de la FORME d'un bloc illisible (`propositions.forme`, jamais le contenu) ;
CORS : `PUT` autorisé (déclaration « envoyée » depuis le Web) ; carte de
proposition : appui long sans sélection de texte du fil
(`SelectionContainer.disabled` + récepteur d'appui long) ; ton affiché
gardé quand la liste recrée la carte (`ConversationSession.tonRegarde`).

Phase 5 (actualisation par copier-coller, doc `docs/backend/CONTEXTES_WHATSAPP.md`) :
menu « + » → glisser « Importer une conversation » vers la gauche
(`LigneImportGlissante`) → « Ajouter une réponse reçue » → volet
`VoletActualisation` (Reçu / Envoyé, auteur vérifié, plusieurs messages,
extrait WhatsApp séparable, doublons confirmés, ajouts corrigeables).
Service `ActualisationWhatsAppApi` → `POST /api/v1/contexts/{id}/messages`
(`ajouter_messages_contexte`, atomique, idempotent), `PATCH` / `DELETE`
des seuls ajouts. `context_messages.origin` = export | manual_received |
manual_sent (migration 20261016120000, appliquée) ; messages d'export
protégés par déclencheur. Moteur : « (ajouté à la main) » sur la ligne,
`origin` dans les références, cache vidé à chaque ajout, aucun appel IA.

Phase 5.1 (finition UX, doc `docs/backend/CONTEXTES_WHATSAPP.md`) : chaque
ton (3 adaptés + Professionnel) a Court / Moyen / Long × EXACTEMENT 3
propositions (`longueur`, `rang` ; ancien format accepté à la relecture),
générées PAR LOTS (`app/comprehension/generation.py` : la réponse
principale annonce les tons, 2 tons par requête JSON, validation par
combinaison, seules les combinaisons manquantes redemandées, 429 borné).
Jamais d'ensemble à moitié (pas de mode « partiel ») : `statut`
complet / incomplet ; incomplet → « Génération incomplète · Reprendre »
(`POST …/propositions/completer`, même ensemble, verrou Redis ;
`ConversationSession.reprendrePropositions`, `GenerationIncomplete`) ;
`longueur_proposee` pour « pourquoi la deuxième ? ». UN seul choix
« envoyée » par ensemble : fonctions SQL verrouillées
`declarer_reponse_envoyee` / `annuler_reponse_envoyee` (migration
20261016150000, appliquée), 409 `deja_choisi`. Après le choix :
`BulleReponseChoisie` (menu `···` Copier / Annuler le choix). Messages
collés : bulles `BulleAjoutWhatsApp` dans le fil
(`MessageConversation.ajoutWhatsApp`, hors historique des moteurs,
restaurées selon `created_at`). Grand glissement (≥ 60 %) = volet ouvert ;
volet épuré (« Options »).

Campagne finale 5.1 (2026-10-16) : registre (`generation.registre` :
tutoiement / vouvoiement / incertain, mesuré dans la discussion) imposé à
TOUS les tons, Professionnel compris (un « vous » à quelqu'un qu'on tutoie
est refusé) ; Court ≤ 20 mots, ≤ 2 phrases ; sauts de ligne d'une
proposition réduits. Fil inversé : `PropositionsJarvis` corrige le
défilement pendant un changement de ton / longueur (capsules sous le doigt)
et rend la bulle du choix visible. Volet : saisie gardée si fermé par
erreur (`brouillonsActualisation`, mêmes UUID). Continuité : indice d'aide
sans faux positif (« sa dernière réponse » ≠ aide), plancher de 1 000
tokens pour les messages WhatsApp, ajout manuel sans date = « après
l'export », rappel `<derniers_messages>` avant une question sur le dernier
message. Faux GroqCloud (`tests_whatsapp/faux_groq.py`) : lots JSON +
pannes à chaud (`POST /panne`, dont « lent »).

Message visé (correction finale) : `app/comprehension/ciblage.py` choisit
le message AVANT l'appel à l'IA, dans les messages enregistrés (auteur,
provenance, rang réel ; un ajout sans date n'est jamais devancé par
l'export) : dernier de la conversation, d'un participant nommé (groupe :
ses seuls messages), reçu, envoyé, dernier ajout ; « sa dernière réponse »
sans nom = le contact (discussion à deux) ou la personne de la question
précédente, sinon clarification (plusieurs contacts / groupe). Le message
et ses 3 précédents sont FORCÉS dans les extraits (`ciblage.voisins` →
`cites`), un bloc `<message_vise>` (identifiant, auteur, provenance,
[[n]]) précède la question, et les anciennes questions / réponses sur « le
dernier message » sont retirées de l'historique. Remplace le rappel
`<derniers_messages>`.
Propositions en préparation : événement SSE `preparation` (après le texte,
avant les lots) → `ConversationSession.preparationEnCours(id)` →
`PreparationPropositions` (trois points animés sous le texte) jusqu'à
`propositions` / `done` ; battements SSE pendant les lots (le client coupe
après 30 s de silence).

Optimisation de la compréhension (2026-10-19, doc
`docs/backend/COMPREHENSION_CONVERSATIONNELLE.md` § Optimisation) : état
partagé `app/comprehension/etat.py` (faits sans IA, recalculés, rien de
stocké) : habitudes par auteur, jalons (décisions / changements, forcés
dans les extraits), indices de sérieux, proportion (« Ok 👍 » → réponses
proportionnées), suite récente ordonnée (ajouts `created_at` ↔ réponses
déclarées `declared_at`), échange en cours vs plus tôt. Interprétation
écrite UNE fois par la réponse principale : attribut `lecture` du bloc
`<propositions>`, stockée avec l'ensemble, donnée à tous les lots et à
« Reprendre ». Ciblage des suivis naturels (« pourquoi elle me dit ça ? »,
« tu crois qu'il plaisante ? », « que répondre ? ») sauf question ancrée
(citation, « quand il m'a dit… »). Lots : « Message auquel répondre »,
habitudes de l'utilisateur, sérieux, décisions, 14 derniers messages avec lecture (sinon 24), consignes de ton / longueur
/ approches alignées ; Moyen 6-70 mots, Long ≤ 140 (légère : Long dès 12
mots, deux phrases). Évaluation : `tests/scenarios_comprehension.py` (12
situations), `tests/evaluation_comprehension.py` (déterministe ; `--reel`
GroqCloud, coûteux).
Fiabilité (déployée le 2026-10-19) : `app/comprehension/controle.py`, sans
IA. Avant les lots, la lecture et l'analyse sont confrontées aux messages
récents (`nettoyer_interpretation` : initiative non justifiée, humour en
situation grave, décision non écrite, citation, date ou participant absents
→ retirés ; certitude → nuancée). Après, chaque proposition passe
`Controle.examiner` (engagement non justifié : remplacer, venir, promettre,
appeler, rendez-vous ; date ou jour inventés ; rire si grave) et les vrais
doublons entre tons sont refusés ; seule la combinaison est redemandée
(`Ensemble.refus` redonné au lot). `brief` : FAITS / INTERPRÉTATION
POSSIBLE (une piste, jamais une consigne) / INCONNU.
Validation S10+ (2026-10-19) : un reproche (« tu aurais pu me prévenir »)
justifie une promesse simple ; refusés sans justification : sorties
(« un verre ce soir ? »), organisation (« système de rappel »), excuses
non écrites. Cartes « Messages d'origine » seulement si la question les
demande (`reperes.demande_sources`) ; sinon références enregistrées
`masquee: true` (jamais restaurées, toujours utilisées par « pourquoi tu
dis ça ? »). Réponses sans étiquettes ni gras.

Utilisation (abonnements, doc `docs/backend/ABONNEMENTS.md` §10-11) :
Paramètres › Utilisation (`PanneauUtilisation`) et `UtilisationPage` :
quotas QUOTIDIENS seulement (Messages / Tokens aujourd'hui ; aucune
session, aucun hebdomadaire). Tout vient de `GET /me/quota`
(`ApiJarvis.utilisation`) : offre, fournisseur, limites, seuil critique,
remise à zéro ; rien de codé en dur. Aucun bouton d'actualisation :
`ServiceUtilisation` (une instance dans `JarvisApp`) relit à l'ouverture
(panneau, page), toutes les 30 s tant qu'un écran est visible (suspendu
appli masquée), 2 s après chaque appel IA ou refus
(`ApiJarvis.surConsommation`), au retour au premier plan, au changement de
compte ; lecture partagée, jamais l'IA ; aucun chargement visible : la
dernière lecture réussie est gardée sur l'appareil (`CacheUtilisation`,
clé `jarvis.utilisation`, rattachée au compte, effacée à la déconnexion,
format versionné) et affichée dès que le compte est connu, puis remplacée
en silence ; sans copie : structure avec « — » (jamais 0) ; copie d'une
journée terminée (`journeeTerminee`, d'après `resets_at`) : consommation
« — » + « Nouvelle journée » ; erreur → dernières valeurs + note discrète
datée. Copie d'affichage seulement : le serveur seul décide des quotas. Supabase :
`users.daily_*` = limites effectives (déclencheurs `users_suivre_offre`,
`plan_config_propager`, sauf exception). 429 typés
(`ApiJarvis.messageLimite`, heure réelle de `resets_at`) ; limite du
fournisseur IA = autre message. Routage inactif : le panneau dit quel
fournisseur sert réellement (`fournisseur_actif`).

ODO (phase 1, doc `docs/backend/ODO.md`) : orchestrateur d'outils
`backend/app/odo/`, séparé de MIA (MIA parle aux modèles, ODO gère outils,
permissions, validation, confirmations). Raccordé dans `chat_stream` autour
de `llm.flux`, seulement pour un chat ordinaire (jamais WhatsApp ni
consigne). `ODO_ACTIF=false` par défaut : chat strictement inchangé ; registre
de production vide (outils fictifs : hors production, `ODO_OUTILS_FICTIFS`).
Une demande = un message ; tokens des tours additionnés ; budget revérifié
entre les tours ; actions sensibles confirmées par `POST
/api/v1/odo/confirmations/{id}` (usage unique, par compte). SSE en plus :
`outil`, `confirmation` (ignorés par les anciennes applis). Indépendant de
`ABONNEMENTS_ROUTAGE` (Free → GroqCloud, Pro → Claude, `plan_config` ;
vérification : `python -m scripts.verifier_routage`).

Gmail (ODO phase 2, doc `docs/backend/GMAIL.md`) : lecture seule. Paramètres ›
Outils › Gmail → navigateur du système → Google (choix du compte, gmail.readonly) →
retour sur le serveur (`/api/v1/integrations/gmail/retour`, state + PKCE).
Jeton de rafraîchissement dans Supabase Vault (`external_connections`,
fonctions backend seulement) ; jamais dans Flutter. Compétences ODO
`gmail_*` proposées seulement si la connexion est active ; sinon note
« connectez Gmail ». « Résume mes mails » n'est plus intercepté par le
moteur local (`DetecteurIntention.concerneMesEmails`). Android : retour par
`jarvis://gmail`.
Recherche intelligente (phase 1, doc `docs/backend/GMAIL.md`) : le modèle
remplit des critères structurés (expéditeurs, termes + reformulations,
période nommée) ou pose UNE question ; ODO calcule tout le reste,
identique Free / Pro (`odo/gmail_recherche.py` : fuseau `fuseau_minutes`
envoyé par l'appli, OU, élargissement ≤ 3 requêtes, pertinence, fils) ;
secrets masqués avant le fournisseur IA (`odo/gmail_confidentialite.py`) ;
dernière recherche du chat 1 h dans Redis (`ServiceODO.memoriser` /
`rappel`, métadonnées seulement). Décision OAuth : option A (actuelle,
non vérifiée) puis C (vérification Google), voir GMAIL.md.
Compréhension approfondie (phase 2, doc GMAIL.md) : `odo/gmail_lecture.py`
(texte nouveau / cité / transféré, dates locales, ordre chronologique,
repères multilingues = indices, pièces jointes non lues) ; consigne :
fait / déduction / inconnu sans étiquettes, reçu ≠ accepté, réserve,
obligation ≠ suggestion ; e-mails LUS mémorisés pour les suivis.
Évaluation réelle : `tests/evaluation_gmail.py` (corpus fictif
`tests/scenarios_gmail.py`, `--renoter` sans appel).

JARVIS Touch › « Capturer » (phases 3A / 3A.1, natif seulement,
`android/.../touch/capture/`) : capture d'une image puis éditeur plein écran
(`EditeurCaptureTouch` : Fermer = capture supprimée, Annuler / Rétablir
visibles seulement si possible, Valider), sélection active dès l'ouverture
(`RecadrageVue` : grille 3 × 3 pendant le geste seulement, double-toucher
= image entière, un geste = une étape d'historique, 30 au plus) ; aucune
IA, aucun envoi. Voie principale : `ServiceAccessibiliteJarvis` (activé une
fois dans Paramètres › Accessibilité d'Android, Android 11+,
`takeScreenshot`, aucun contenu de fenêtre lu ; désactivé par Android à
chaque réinstallation de développement). Secours : MediaProjection
(`ActiviteCaptureEcran` transparente dans sa propre tâche →
`ServiceCaptureEcran` premier plan `mediaProjection`, une image puis tout
est libéré ; consentement à chaque fois). `CaptureEcran` : une capture à
la fois, issue (`Reussie` / `Echec` / `Annulee`). `CaptureTouch` : le
recadrage n'est appliqué qu'à `valider` (pixels d'origine copiés, original
et son fichier libérés) ; une capture validée reste jusqu'à la suivante ;
phase 3B : `fichierValide`. `DepotCaptures` : PNG dans
`cache/captures_touch/` (un seul fil : écriture, suppression, libération),
tout effacé au démarrage de la bulle / de JARVIS sans bulle. Éditeur :
FLAG_SECURE, abandonné à l'extinction de l'écran, refusé écran verrouillé.
Réglages réels : Paramètres › Général › JARVIS Touch · Capture d'écran
(`JarvisTouchService.capture`, canal `jarvis/touch` : `etatCapture`,
`ouvrirReglagesCapture` ; aucun faux interrupteur).

JARVIS Touch, intégration (2026-10-18) :
- Paramètres › Général : une entrée « JARVIS Touch » → `PageGenerale`
  (`widgets/parametres/pages_jarvis_touch.dart`) : JARVIS Touch
  (interrupteur), Capture d'écran (« Autorisé » seulement si le service
  d'accessibilité est actif ; l'accord MediaProjection ponctuel n'est
  jamais « autorisé »), Personnalisation (structure seulement). Navigation
  dans `FenetreParametres` (`_pageGenerale`, comme `_outil`).
- Capture validée → mini-chat ouvert avec la vignette
  (`ChatJarvisTouch.PieceCapture`, gardée si le chat est réduit, croix =
  fichier effacé) ; Envoyer → `PasserelleMiniChat` lit le PNG UNE fois →
  `ConversationSession.envoyerAvecCapture` (message `capture:
  CaptureJointe`, demande `image: ImageAEnvoyer`, jamais le moteur local)
  → `ApiJarvis.discuter(image:)` → `POST /chat/stream` champ `image`
  (base64). Backend `app/vision.py` : signature, ≤ 5 Mo, ≤ 8000 px ;
  `FournisseurLLM.vision` (Claude seulement) sinon 403 `vision_offre`
  (« L'analyse d'image demande l'offre Pro », avant le quota) ; jamais en
  base (référence `capture_ecran` dans `messages.attachments`), octets
  gardés 1 h dans Redis (`chat:image:{conversation}`, dernière image) pour
  les questions suivantes, puis note « plus disponible ».
- Vocal flottant : `VocalJarvisTouch` (cercle + symbole audio bleu, une
  seule animation, aucune particule PIM) pilote LA `VoiceSession` de
  l'accueil via `PasserelleVocalTouch` (canal `jarvis/touch_chat`,
  `vocalOuvrir` / `vocalMicro` / `vocalQuitter` / `vocalFermer` ; Dart →
  `vocal`, `niveau`) ; service au premier plan type `microphone` le temps
  du vocal seulement ; Réduire = bulle marquée ; JARVIS au premier plan =
  vocal fermé (reprenable dans l'accueil).
- Menu : « Importer » → « Actions » (M'expliquer, Traduire, Aider à
  répondre, Mes raccourcis : « Bientôt disponible », aucun appel IA).
- Voix (vocal principal et JARVIS Touch, même `VoiceSession`) : la voix
  dit `TexteOral.preparer(texte)` (`services/texte_oral.dart` : Markdown
  retiré, listes numérotées → « D'abord… Ensuite… Enfin… », unités et
  symboles en mots, chiffres jamais modifiés) ; l'écrit reste inchangé dans
  la conversation. Échange vocal : `oral: true` sur `/chat/stream` →
  `CONSIGNE_ORALE` ajoutée au système (une seule réponse, formulée pour
  être dite). Arrêt de la parole : `VoiceSession.arreterParole` (état
  « Parole interrompue » immédiat, voix coupée, rien ne reprend seul) /
  `parler` ; distinct de couper le micro, réduire et quitter. Boutons
  contextuels en zone fixe (`VoiceStatus._BoutonParole`,
  `VocalJarvisTouch.contextuel`). Réglage commun : Paramètres › Chat vocal ›
  Interruption de la parole (`VoiceSettings.interruption` ; automatique
  indisponible, jamais relu comme actif).
- Voix en flux (2026-10-19) : `LectureEnFlux` (`services/lecture_en_flux.dart`)
  dit les phrases COMPLÈTES pendant la réception (`repondeur(phrase,
  surFragment:)` ← `ConversationSession.repondreVocal`) ; réponse reçue
  avant le début de la lecture = dite d'un seul tenant ; démarrage dès 2
  phrases / ~140 caractères, ou 1 phrase après 1,8 s ; coupure réseau :
  phrases complètes terminées, bout inachevé jamais dit, phrase « Le réseau
  a coupé la fin de ma réponse. ». Interruption en UN toucher
  (`arreterParole`) : voix coupée, file vidée, tour invalidé (`_tour`),
  génération arrêtée (`DemandeJarvis.annulation` → requête abandonnée,
  `ErreurApi.annulee`, « Interrompue par vous. », le serveur garde le
  partiel), puis écoute aussitôt. Continuité : ce qui a été ENTENDU
  (`LectureEnFlux.entendu`) part avec la question suivante de la même
  conversation (`interruption.entendu` → `note_interruption` côté serveur,
  une seule fois). Interruption automatique : `DetecteurIntervention`
  (Kotlin `voix/`, VOICE_COMMUNICATION + AEC + NS, énergie durable au-dessus
  du fond + structure vocale) en mode mesure seulement
  (`--dart-define=JARVIS_MESURE_INTERRUPTION=true`, n'interrompt jamais) ;
  `ModeInterruption.automatique.disponible = false` tant que non validée.
- Téléphone USB : lancer avec `--dart-define=JARVIS_API_URL=http://127.0.0.1:8000`
  (+ `adb reverse tcp:8000 tcp:8000`), sinon l'appli vise 10.0.2.2.

Apparence (2026-10-19 ; depuis le 2026-10-20 : Paramètres › Apparence, page unique à carrousels) :
quatre préférences indépendantes (`PreferencesApparence`) : mode (Clair /
Sombre / Système), style (`StyleVisuel` : JARVIS original + Congotronics,
Raphia Kuba, Fleuve, La Sape, Rumba, Léopards, repris de l'application
« Jarvis » d'une amie : jetons CSS exacts pour la variante d'origine, autre
variante créée), motif (`MotifJarvis`), intensité. Défaut = JARVIS clair +
Aurore 50 % = apparence d'avant, à l'identique. `ServiceApparence` (une
instance, lue avant `runApp`, clé `jarvis.apparence`, JSON versionné, valeur
inconnue → défaut) publie `PaletteJarvis.active` ; `CouleursJarvis.*` est une
FAÇADE qui la lit (plus de `const` avec ces couleurs) ; dans un widget :
`PaletteJarvis.of(context)` (ThemeExtension). Changement de palette :
`TransitionApparence` = fondu 320 ms + reconstruction / repeinture unique de
tout l'arbre (aucun état perdu). Motif : seul le fond dépend du service
(`FondJarvisAnime` : image mémorisée refaite une fois ; `FondJarvis`).
Personnalité des styles importés (`IdentiteVisuelle`) : contour 2 px, ombre
pleine décalée (bulle, carte), frise kuba (`FriseKuba`) en haut des cartes de
JARVIS, police Baloo 2 (OFL) pour les titres. PIM : NON touché (ni couleurs
ni algorithmes, demande explicite). Couleur pensée pour le clair (rouge,
vert, auteurs) : `CouleursJarvis.lisible`. Tests : `test/apparence_test.dart`
(contrastes des 14 palettes compris).

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
