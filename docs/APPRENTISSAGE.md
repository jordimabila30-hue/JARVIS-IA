# Module Apprendre (Kelasi) — phase 1

Espace pédagogique **hors ligne** : interface, moteur de leçons, progression
locale. Aucun appel réseau, aucune IA, aucun backend dans cette phase.

## Organisation

```text
lib/models/apprentissage/
├── contenu_pedagogique.dart   # Parcours, Unite, Lecon, FichePedagogique, SourcePedagogique, StatutValidation
├── exercice.dart              # 7 types d'exercices (sealed) + correction + mélange stable
└── progression.dart           # ProgressionApprentissage, EtatLecon, SeanceEnregistree (JSON versionné)
lib/services/apprentissage/
├── espace_apprentissage.dart  # interrupteur ModuleApprentissage, EspaceApprentissage, LecteurEcoute
├── catalogue_apprentissage.dart # lecture à la demande des assets, cache, aperçu des brouillons
├── validation_corpus.dart     # validation tolérante d'un parcours JSON
├── seance_lecon.dart          # déroulé d'une séance (logique pure)
├── selection_exercices.dart   # Continuer, Pratiquer, Réviser
└── service_progression.dart   # stockage local, écritures regroupées, récupération
lib/pages/apprentissage/       # apprendre_page, parcours_page, lecon_page
lib/widgets/apprentissage/     # éléments, cartes, exercices/vue_exercice, correction + fiche, résultat
assets/apprentissage/          # catalogue.json + parcours/*.json
test/apprentissage/            # corpus, moteur, progression, interface
```

Entrée : menu latéral › **Apprendre** (`MenuLateral.surApprendre`) →
`AccueilPage._ouvrirApprendre` → `ouvrirApprendre`. L'`EspaceApprentissage`
est créé **à la première ouverture** seulement, puis gardé (corpus en cache,
progression lue) jusqu'à la fermeture de l'accueil.

## Interrupteur

`ModuleApprentissage.actif` (`--dart-define=JARVIS_APPRENTISSAGE=false`
pour le masquer) : l'entrée du menu disparaît, rien du module n'est créé.
Le pilotage distant viendra avec l'intégration serveur.

## Contenus (schéma 1)

`catalogue.json` : `{ "schema": 1, "parcours": [{ id, titre, icone, fichier }] }`.

Un fichier par parcours :

```json
{
  "schema": 1, "parcours": "<id>", "version": 1,
  "fiches": [{ "id", "titre", "niveau", "explication", "exemples": [], "a_eviter": [],
               "sources": [{ "titre", "editeur", "url", "consulte_le" }],
               "statut": "brouillon | valide", "version": 1 }],
  "unites": [{ "id", "titre", "lecons": [{ "id", "titre", "niveau", "duree_minutes",
               "objectif", "fiches": [], "exercices": [] }] }]
}
```

Exercices (`type`) : `choix` (options, bonne), `vrai_faux` (affirmation,
reponse), `trous` (texte avec `___`, trous[{options, bonne}]), `ordre`
(elements dans l'ordre correct ; affiché mélangé de façon stable),
`association` (paires [gauche, droite]), `meilleur_message` (contexte,
options, bonne), `ecoute` (audio, options, bonne). Chacun a `id`, `fiche`
(fiche de la leçon), `consigne`, `explication`.

Validation (`validerParcours`) : une fiche sans source ou incomplète, une
leçon dont un exercice est incohérent, cite une fiche absente ou a un
identifiant en double est **écartée** et signalée ; le reste du parcours
reste utilisable. Schéma plus récent ou JSON illisible : parcours vide,
jamais d'exception.

## Publication

Une leçon est proposée seulement si **toutes ses fiches** sont `valide`
et comportent une trace de validation humaine (`validation.par`, `validation.le`).
Aperçu des brouillons : réservé au développement
(`CatalogueApprentissage.apercuDisponible` = `!kReleaseMode`), activé par
défaut en debug / profile, désactivable dans le module (icône réglages),
**impossible en release**. Sans leçon validée, l'accueil le dit
(« Contenus en validation », cartes « En préparation »). Inventaire des
sources : `docs/APPRENTISSAGE_SOURCES.md`.

## Séance

`SeanceLecon` : introduction (objectif, fiches, sources) → exercices →
résultat. Réponse corrigée aussitôt (explication, réponse attendue, fiche
et sources). Faux : « Réessayer » immédiat, et l'exercice revient **une
fois** en fin de séance s'il n'a pas été réussi entre-temps. Seul le premier
essai compte au bilan (notions acquises / à retravailler par fiche).
Pratiquer : 6 exercices (leçons étudiées d'abord). Réviser : exercices
ratés d'abord, complétés par les leçons étudiées. Écoute : voix de JARVIS
(`LecteurEcouteSession` → `VoiceSession.lireApercu`) ; sans voix, pendant un
chat vocal ou en cas d'échec, le texte s'affiche : une leçon n'est jamais
bloquée.

## Progression

Clé `jarvis.apprentissage.progression` (SharedPreferences, JSON versionné,
lecture tolérante). Changement affiché aussitôt ; réponses et étapes écrites
immédiatement, navigation regroupée (1,5 s). Les écritures sont asynchrones
et sérialisées : une seule à la fois, le dernier état complet suit les
changements arrivés pendant une écriture. `enregistrerMaintenant` attend
aussi les écritures en cours. Écriture forcée en fin de leçon, en quittant une séance et dès que JARVIS
passe en arrière-plan. Illisible : copie gardée sous `….corrompue`, reprise
de `….secours` (copie saine refaite à chaque lecture réussie), sinon départ
vide — jamais d'effacement silencieux. Pourcentage d'un parcours = leçons
terminées / leçons proposées. Pas de synchronisation (identifiants stables
et dates prêts pour plus tard). Progression par appareil, pas par compte.

Limite : une interruption avant l'achèvement d'une écriture peut perdre la
dernière étape. SharedPreferences ne garantit pas la durabilité disque au
retour de l'appel ; les essais de fermeture forcée sont des observations
sur l'appareil, pas une garantie contre toute coupure. En cas d'échec, le
dernier état reste à écrire et sera retenté à la prochaine sauvegarde.

## Performance

- Rien au démarrage : ni lecture d'asset ni création de service.
- Corpus : catalogue + 4 fichiers (≈ 27 Ko) lus en parallèle à la première
  ouverture, puis en cache ; décodage hors du fil d'interface au-delà de
  100 Ko (`compute`).
- PIM : son `TickerMode` est suspendu dès l'ouverture, avant que la page
  opaque couvre l'accueil, et jusqu'à la fin de la transition inverse
  (`route.completed`). Reprise du même moteur au retour, sans capture
  d'image ni allocation graphique supplémentaire.
- Aucune nouvelle dépendance, aucun `AnimationController` ajouté
  (animations implicites seulement).
- Mesures sur appareil : `--dart-define=JARVIS_PERF=true` (mode profile),
  compteurs `ext.jarvis.chrono`. Le banc peut désactiver la suspension par
  `ext.jarvis.variante` avec `sans=apprendre.pause` pour comparer dans la
  même compilation. Cette option n'a aucun effet hors instrumentation.

## Préparé pour la suite (non développé)

Avatars (aucun affiché ; un futur `LecteurEcoute` / présentateur pourra être
injecté dans `EspaceApprentissage`), exercices IA, professeur, test de
niveau (aucun blocage de leçon : sauter des unités sera direct), XP,
badges, synchronisation Supabase (format versionné, identifiants stables).
