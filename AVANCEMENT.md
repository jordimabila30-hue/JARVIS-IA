# JARVIS — Suivi d'avancement

Journal des avancées du projet, de la plus récente à la plus ancienne.

---

## 2026-10-04

### Fait
- Ajout de `CLAUDE.md` à la racine (contexte et règles du projet).
- Création de ce fichier `AVANCEMENT.md`.
- Renommage `Ecran_de_lancement.dart` → `ecran_de_lancement.dart` (convention minuscules).
- `main.dart` : l'app exemple Flutter (compteur) est remplacée par `JarvisApp`, thème sombre, qui démarre sur l'écran de lancement.
- **Écran de lancement v1** (`lib/pages/ecran_de_lancement.dart`), environ 3,2 s :
  - fond sombre uni, légère lueur au centre ;
  - anneaux HUD qui se tracent, graduations et segments de viseur qui tournent lentement, arc de progression ;
  - lettres J-A-R-V-I-S qui se « décodent » en 3D (symboles qui défilent) puis se verrouillent avec un flash ;
  - version discrète en bas (`v1.0.0`).
  - Aucune dépendance ajoutée.
- Test widget mis à jour (`test/widget_test.dart`).
- `.claude/launch.json` : aperçu Web pour Claude (sert `build/web` sur le port 8090 ; relancer `flutter build web` pour voir les changements).
- Correctif responsive : le contenu était collé en haut à gauche → maintenant centré sur tout l'écran, version tout en bas. Vérifié en format ordinateur et téléphone (375×812).
- Correctif : espacement irrégulier autour du « I » (place plus étroite pour cette lettre).

### Décisions prises
- 3D « en perspective » (lettres plates qui pivotent), pas de vraie 3D en volume.
- Fond sombre uni : pas de dégradé de fond, pas de particules.
- Les lettres ne viennent pas du fond (pas d'effet de zoom depuis la profondeur).
- Direction visuelle : interface HUD (anneaux, graduations), liée au cercle du logo de la startup.
- Pas de phrases ni de slogan sur l'écran de lancement.
- Version affichée en bas, de façon discrète.

### Idées pour plus tard
- Son de démarrage synchronisé avec le flash de verrouillage (dépendance audio à prévoir ; attention, le son automatique est bloqué sur Web).
- Transition « traverser l'anneau » vers la page suivante (via `onTermine`).
- Version longue au premier lancement, version courte ensuite, avec un tap pour passer.
- Parallaxe (le mot réagit à la souris ou à l'inclinaison du téléphone).
- Logo de l'app JARVIS (pas encore créé).
- Vérifier les droits sur le nom « JARVIS » (marque Marvel) avant une publication sur les stores.

### Page d'accueil v1
- Inspirée de ChatGPT, fond blanc, palette blanc / bleu / violet / gris.
- `lib/pages/accueil_page.dart` : titre « Par où commencer ? », champ de saisie, 3 suggestions cliquables (elles remplissent le champ).
  - Grand écran (≥ 900 px) : barre latérale à gauche, repliable, et champ centré.
  - Petit écran : menu ☰ (drawer) et champ de saisie en bas.
- `lib/widgets/barre_laterale.dart` : Nouvelle conversation, Rechercher, Importer, Bibliothèque, sections Épinglés / Récents (exemples factices), compte en bas.
- `lib/widgets/champ_de_saisie.dart` : +, texte, micro, bouton rond en dégradé (vocal → envoi dès qu'il y a du texte).
- `lib/widgets/logo_jarvis.dart` : « JARVIS » en dégradé bleu → violet.
- `lib/theme/couleurs_jarvis.dart` : palette centralisée.
- Navigation : l'écran de lancement passe à l'accueil en fondu (600 ms) à la fin de l'animation.
- Rien n'est encore connecté : envoyer un message vide simplement le champ, et les boutons du menu ne mènent nulle part.

### Prochaine étape
- Retours sur l'accueil, puis amélioration côté motion.
- À prévoir : passer l'interface en français pour les infobulles système (« Open navigation menu » → « Ouvrir le menu »), via `flutter_localizations` (fourni avec le SDK Flutter).

---

## 2026-10-04 — Accueil v2 : le noyau et les trois modes

### Fait
- Nouveau widget `lib/widgets/noyau_jarvis.dart` : version calme et claire des anneaux HUD du lancement (anneaux, graduations en rotation lente, 3 segments de viseur, cœur en dégradé). Il fait le lien visuel entre le lancement et l'accueil.
- Accueil organisé en trois modes : **Discuter**, **Analyser**, **Répondre** (ils annoncent les moteurs Conversation, Analyse et Suggestions).
  - Le noyau pivote pour mettre le segment du mode choisi en haut (en violet).
  - La question, le texte d'aide du champ et les 3 suggestions changent avec le mode.
  - Le cœur du noyau grossit quand du texte est saisi.
- Suggestions en simples lignes (petite graduation à gauche, flèche ↖ « remplir le champ »), sans cartes ni icônes colorées.
- `champ_de_saisie.dart` : paramètre `indication`, bordure bleue et ombre plus nette au focus.
- Palette : texte en encre bleu nuit (#141A33), gris secondaire plus froid (#626A84).
- Rotation automatique coupée si l'appareil demande moins d'animations.

### Prochaine étape
- Retours sur l'accueil v2.
- Infobulles système en français (`flutter_localizations`).

---

## 2026-10-04 — Remise à zéro

- Accueil et tout ce qui l'accompagnait retirés (page d'accueil, widgets, palette, police Bricolage).
- Le projet ne contient plus que `main.dart` et `pages/ecran_de_lancement.dart` ; l'app affiche uniquement l'écran de lancement.
- Prochaine étape : repartir de l'écran de lancement et redéfinir ensemble la direction de l'accueil avant de coder.

---

## 2026-10-04 — Accueil v3 : hologramme 3D (style HUD)

### Fait
- Direction choisie avec `ui-ux-pro-max` (style HUD/Sci-Fi tempéré par du minimalisme, palette nuit indigo + violet, police Exo 2), construite avec `frontend-design`, vérifiée avec `web-design-guidelines`.
- `sphere_holographique.dart` : hologramme en vraie 3D (rotation + perspective) dessiné en Flutter, sans dépendance : sphère en fil de fer, 3 anneaux orbitaux avec satellites, nœuds qui scintillent, noyau qui pulse. Pivote au doigt / à la souris, accélère quand on écrit, s'arrête si l'appareil demande moins d'animations.
- Accueil : nom JARVIS + historique / réglages en haut, hologramme et salutation (Bonjour / Bonsoir) au centre, ligne de commande en bas.
- Retirés à la demande : le panneau « À traiter » et l'indicateur « En ligne ».
- Thème sombre centralisé (`theme_jarvis.dart`), contrastes vérifiés (≥ 6:1), couleur de fond Web alignée (`index.html`, `manifest.json`).

### Prochaine étape
- Retours sur l'hologramme (couleur : bleu actuel ou or façon Iron Man ?).
- Remettre plus tard la liste des conversations, quand le moteur Importation sera prévu.

---

## 2026-10-04 — Mode vocal et PIM

### Fait
- PIM remplace l'hologramme « atome » : ~650 particules en 3D (un seul CustomPainter, tampons préalloués, dessin groupé par profondeur). États idle / listening / thinking / speaking, réaction à l'amplitude, mouvement réduit respecté.
- Bouton « Chat vocal » dans la ligne de commande ; transition douce vers un mode minimaliste (PIM agrandi, statut, « Quitter le mode vocal »).
- Boucle vocale (`voice_session.dart`) : permission micro → écoute → réflexion (0,6–1,2 s) → réponse locale → synthèse vocale → réécoute. « Au revoir » ferme le mode vocal.
- Commandes locales (`voice_command_service.dart`) : bonjour, comment vas-tu, qui es-tu, que peux-tu faire, au revoir, heure et date réelles de l'appareil. Phrases normalisées (casse, accents, ponctuation). Commande inconnue : « Cette commande n'est pas encore disponible. » Point d'entrée `AssistantDistant` prêt pour une future IA.
- Permissions : refus, refus définitif (lien vers les réglages), micro indisponible, erreurs — sans plantage.
- Packages : speech_to_text, flutter_tts, permission_handler (^12 : la 13 exige AGP 9 + Kotlin 2.3). Droits ajoutés (AndroidManifest, Info.plist). Build Android debug OK.
- Tests : 15 tests (commandes, date/heure, PIM dans chaque état).

### À faire / limites connues
- Windows : installer nuget.exe (requis par flutter_tts) avant `flutter build windows`.
- iOS : après le premier `pod install`, activer PERMISSION_MICROPHONE=1 dans le Podfile.
- Tester sur appareil réel (le panneau de prévisualisation bloque le micro).

---

## 2026-10-04 — Physique des particules PIM et mode écrit

### Fait
- Particules PIM dessinées dans un calque plein écran derrière l'interface (zone centrale et champ texte repérés par des GlobalKey).
- Vraie physique : ressort doux vers une cible + amortissement + répulsion locale (grille spatiale), accélération → vitesse → position. Paramètres individuels tirés une seule fois.
- Mode écrit : à la première lettre, les particules descendent, s'étirent puis entourent le champ (bande irrégulière qui circule). Plus énergiques pendant la frappe, calmes après 1,8 s, petite onde à l'envoi, retour au centre 3 s après que le champ est vide ; une frappe pendant le retour inverse la transition sans saut.
- `PimController` + `ParticlePimMode` (idle, movingToInput, inputActive, inputCalm, sending, movingToCenter, listening, thinking, speaking).
- Tous les réglages sont regroupés dans `PimReglages` (lib/widgets/pim_particle.dart).
- Tests : les 7 scénarios du mode écrit + états vocaux.

### Prochaine étape
- Corriger le système de reconnaissance vocale (tâche séparée).

---

## 2026-10-04 — Mode vocal : corrections

### Fait
- Après une erreur micro (refus, indisponible…), la session s'arrête vraiment (`actif = false`) : plus d'écoute, de voix ni de mesure ; le message et « Réessayer » restent affichés.
- Fin de session explicite (`VoiceSession.surFin`) après « Au revoir JARVIS » : la page ne déduit plus la fin de `actif`.
- Web : volume réel du micro mesuré avec Web Audio (`niveau_micro_web.dart`), pris en compte uniquement pendant l'écoute. Hors Web, la reconnaissance vocale fournit déjà le niveau.
- Package `web` déclaré en direct (il était déjà présent via speech_to_text).
- Tests de la session avec des services factices (refus, refus définitif, erreur de reconnaissance, « Au revoir »).

---

## 2026-10-04 — Mode vocal Web : JARVIS restait sur « Écoute… »

### Cause
- Sur le Web, le plugin speech_to_text ne marque jamais un résultat comme final (validation après 3 s de silence + 2 s), n'impose pas le français (sa liste de langues est vide) et signale toutes les erreurs du navigateur comme non bloquantes : une erreur `network` relançait l'écoute en boucle sans message.

### Fait
- Sur le Web, reconnaissance directe via l'API Web Speech (`reconnaissance_navigateur_web.dart`) : `fr-FR` imposé, une phrase par écoute, résultat final dès que l'utilisateur s'arrête, erreurs remontées avec leur code (journal `[JARVIS voix]` dans la console).
- Nouveaux messages : service de reconnaissance injoignable (réseau), français non disponible, et « Je ne t'entends pas. Vérifie le micro choisi. » après 3 écoutes vides.
- Hors Web, le français est imposé même si l'appareil ne liste pas ses langues.
- Barre du haut : icônes Historique et Réglages retirées.

---

## 2026-10-04 — Particules trop éparpillées en mode vocal

### Constat
- Signalé : en mode vocal les particules s'étalent sur tout l'écran et ne reviennent pas en mode texte.
- Non reproduit en test (page complète, écran 1887×872, écoute / réflexion / parole / sortie) : étalement ≈ 1 rayon.

### Fait (robustesse + rendu plus compact)
- Physique en sous-pas (≤ 1/60 s) quelle que soit la cadence d'affichage.
- Répulsion plafonnée (`repulsionMax`), profondeur bornée (±1,6 rayon), grossissement de perspective limité à ×1,4.
- Mode vocal plus serré : `expansionEcoute`, `expansionEcouteVariable`, `vaguesParole` (≈ −40 %).
- Tests avec seuils : étalement < 1,4 rayon en mode vocal, < 1,1 après retour.

---

## 2026-10-04 — Conversation, calculs et notions techniques

### Fait
- Particules : ampleur d'origine rétablie en mode vocal, réaction à la voix +10 % (`expansionEcoute`, `expansionEcouteVariable`, `vibrationEcoute`, sensibilité du micro Web).
- Conversation suivie (`ContexteConversation`) : prénom retenu (« je m'appelle… », ou réponse à « comment vous appelez-vous ? »), « Et vous ? » après « comment ça va », réponses à l'humeur, « répète », « dis-m'en plus » sur le sujet en cours, salutations et au revoir avec le prénom.
- Calculs dictés (`calcul_vocal.dart`) : chiffres ou lettres, plus / moins / fois / divisé / puissance / au carré / au cube / racine carrée / pour cent, priorités respectées, division par zéro gérée.
- ~30 notions techniques (IA, machine learning, Flutter, API, JSON, cloud, chiffrement…) avec réponse courte et développement.
- Date de demain / d'hier, mois, année ; réponses honnêtes pour météo et musique (« pas encore »).
- La réponse de JARVIS s'affiche en texte sous la phrase entendue.
- 38 tests.

---

## 2026-10-04 — Sphère de particules : composition et contrôle

### Cause de l'éparpillement (corrigée)
- Le décalage de « parallaxe » était calculé comme angle de rotation cumulé × 0,06 : il grandissait sans fin avec le temps et projetait les cibles hors de la sphère (plus vite en mode vocal, où la rotation accélère). Les particules ne pouvaient pas revenir puisque leurs cibles étaient elles-mêmes éparpillées.
- Remplacé par une vraie rotation par particule (vitesse légèrement différente), qui conserve la distance au centre.
- Test de non-régression : ~2 min de session vocale simulée → étalement max 1,23 rayon (1,97 avant), retour à 1,03.

### Fait
- 900 particules (600 avant) : 68 % sur la coque en spirale de Fibonacci (silhouette nette et régulière), 32 % dans le volume (densité).
- Dispersion bornée (`dispersionMax`) et rappel renforcé hors d'une petite zone libre (`rappelHorsZone`, `zoneLibre`).
- Plus de vie : ondulation lente, précession de l'axe, flottement accru, écoute qui gonfle la sphère par zones ; réaction vocale ×1,2 (bornée).
- Coût mesuré : ~1,9 ms par image en test (budget 16 ms).

---

## 2026-10-05 — Personnalité des particules PIM, cube, conversations locales

### Fait
- Mémoire courte de la voix (`MemoireEnergie`) : énergie instantanée, mémoire courte (monte vite, oublie lentement) et moyenne. Après un pic, les particules gardent l'élan puis reviennent doucement.
- Zones audio dans une seule sphère : graves → cœur (mouvement lent et profond), médiums → couche intermédiaire, aigus → périphérie (vibration fine). Sur le Web, vraies bandes de fréquence du micro (Web Audio) ; ailleurs, déduites de la dynamique de l'amplitude.
- Utilisateur ≠ JARVIS : à l'écoute, légère ouverture et ondes du bord vers le centre (réception) ; quand JARVIS parle, petite contraction de préparation puis ondes du centre vers l'extérieur (émission), une par mot, proportionnelle à l'accent.
- Grammaire de la parole : `Prosodie` analyse la réponse (accent en fin de groupe rythmique, mots outils faibles, pauses après la ponctuation). Mots signalés par la synthèse vocale quand la plateforme le permet, sinon rythme estimé depuis le texte.
- Transitions : vitesses d'entrée et de sortie propres à chaque état (écoute qui s'ouvre progressivement, parole qui démarre vite et s'éteint avec inertie).
- Forme secondaire : cube de particules, rare (après 8 à 20 s de vrai repos, 10 % de chance par seconde), stabilisation → coins → arêtes → faces, tenue 5 s avec léger mouvement, retour progressif. Toute interaction rend aussitôt la priorité à la sphère.
- Conversations : état du système, nom, « c'est quoi JARVIS », capacités, « je te remercie », « bye », bonne nuit ; salutations suivantes plus brèves ; au revoir selon la formule et l'heure.
- 52 tests ; coût mesuré 1,6 à 3,3 ms par image en test.

### État
- Compile pour le Web. La compilation Windows échoue dans le plugin `permission_handler_windows` avec Visual Studio 18 (problème de chaîne de compilation, indépendant de cette étape).

### Prochaine étape
- Essai réel au micro sur le Web et Android pour affiner les réglages (sensibilité, ondes, fréquence du cube).

---

## 2026-10-05 — Direction visuelle premium (fond ivoire, sphère raffinée)

### Fait
- Thème clair : fond ivoire → crème (`FondJarvis`), texte graphite, accent bleu-violet ; écran de lancement, ligne de commande et panneaux adaptés.
- Rendu PIM (`pim_rendu.dart`) : 2 200 particules ; ~80 % de micro-particules graphite / anthracite / gris bleuté / violet, ~17 % de particules moyennes en relief (reflet), ~2,5 % d'accents bleu-lilas avec halo doux. Brume de profondeur, flou de profondeur de champ, lumière au cœur, ombre portée sous la sphère qui flotte.
- Composition : coque fine, couche épaisse dense vers l'extérieur, cœur clairsemé, quelques satellites.
- Douceur : lissage du second ordre des états (départ en courbe en S), ressort plus souple et plus amorti, ondes plus larges et plus lentes, vibrations ralenties, mémoire courte plus longue.
- Voix : enveloppe de parole reconstruite mot par mot (montée, syllabes, extinction, traîne), ondes seulement sur les mots accentués, montée d'énergie pendant la réflexion. Écoute = pourtour éclairé ; parole = lumière qui rayonne du cœur.
- Cube plus rare : 30 à 60 s de repos, 2 % par seconde, 3 min de recharge entre deux cubes, transitions plus lentes.
- 52 tests ; Web compile ; ~5 ms par image en test (budget 16 ms).

### Prochaine étape
- Essai réel (micro, Android) pour affiner densité, halos et sensibilité.

---

## 2026-10-05 — Finition visuelle, profondeur et responsive

### Fait
- Hiérarchie : particules PIM → statut → conversation → actions. Statut petit et gris avec un point de couleur ; phrase entendue en citation ; réponse de JARVIS en texte principal mesuré (largeur maximale, interligne 1,5).
- Micro : pastille discrète « Micro non détecté » (au lieu d'une phrase en titre) ; erreurs affichées comme « Micro indisponible », détail en petit, boutons compacts.
- Responsive (`gabarit_jarvis.dart`) : formats compact / moyen / large, sphère bornée (min / max par format), textes adaptés, texte du mode vocal qui défile au lieu de déborder, « Quitter le mode vocal » discret avec zone tactile de 48 px.
- Profondeur : 5 plans (taille, opacité, brume, contraste, reflet, flou, halo), micro-particules plus lisibles (graphite, bleu gris, bleu nuit, violet gris), 3 types d'accents (≈ 2,2 %) aux halos de tailles différentes, richesse qui varie doucement selon les zones.
- Lumière centrale diffuse et plus faible ; ombre plus douce et plus large, qui réagit au flottement.
- Petites sphères : dispersion, ondes et halos légèrement retenus ; rendu simplifié sous 110 px de rayon.
- Fond : centre plus clair, bords plus chauds. Bleu-violet signature légèrement désaturé.
- Vérifié sur 1920×1080, 1366×768, 429×599, 390×844, 820×1180 : aucun débordement.

### Prochaine étape
- Essai sur un vrai téléphone (fluidité avec 2 200 particules, lisibilité).

---

## 2026-10-05 — Paramètres : Chat vocal fonctionnel

### Fait
- Fenêtre Paramètres (bouton en haut à droite) : grande fenêtre centrée avec navigation à gauche et compte en bas sur ordinateur et tablette ; plein écran à deux niveaux (liste → section) sur téléphone. Fermeture par X, Échap, clic à côté ; retour Android.
- `VoiceSettings` (profil, langue, voix, vitesse, hauteur, volume, micro, réponse automatique) : source de vérité unique, sauvegardée automatiquement (SharedPreferences), relue au démarrage.
- `TtsService` étendu (pas de second système) : voix réelles, conversion débit / hauteur / volume par plateforme, réglages appliqués avant chaque prise de parole.
- Profils Classique / Naturel / Clair / Dynamique ; réglage manuel → « Personnalisé ».
- Langues = celles qui ont une voix installée ; changement de langue → voix valide choisie automatiquement.
- Micro : liste réelle sur le Web (mesure du volume) ; ailleurs, micro par défaut, expliqué dans l'interface.
- Réponse automatique désactivable : la phrase reconnue attend « Envoyer » ou « Réécouter ».
- Aperçu de la voix (lecture / arrêt), avec réaction des particules PIM.
- Sections Général, Particules PIM, Apparence, Confidentialité : informations réelles, marquées « Bientôt ».
- 21 nouveaux tests (73 au total) ; vérifié à 1920×1080, 1366×768, 820×1180, 390×844 ; persistance vérifiée dans le navigateur après rechargement.

### Prochaine étape
- Essai réel sur Android / Windows (voix listées, débit).

---

## 2026-10-06 — Accueil finalisé : barre de saisie et bouton vocal

### Fait
- Logo JARVIS centré et discret ; Paramètres à droite.
- Sous les particules : « Bonjour » et la mission « JARVIS vous aide à comprendre et répondre à vos conversations. » (une ligne sur grand écran, deux lignes équilibrées sur téléphone). La salutation s'efface pendant la saisie (les particules entourent alors la barre) et revient avec elles.
- Barre de saisie : capsule claire, ombre douce, lueur discrète au focus ; bouton « + » rond (coller une conversation ; import marqué « bientôt ») ; séparateur ; invite « Collez une conversation ou demandez conseil à JARVIS… » (« Collez une conversation… » sur téléphone).
- Bouton vocal sans texte (`bouton_vocal.dart`) : capsule sombre, pastille bleue ; respiration lente, survol, appui, écoute (pulsation), parole (onde) ; devient le bouton d'envoi quand du texte est saisi. Libellés accessibles et infobulles.
- Mode vocal : la même capsule, animée selon l'état, accompagne « Quitter le mode vocal ».
- `cadre_hud.dart` n'est plus utilisé (conservé).
- 78 tests ; vérifié à 1920×1080, 1366×768, 820×1180, 429×599, 390×844.

---

## 2026-10-06 — Accueil : centrage de la barre et fond animé

### Fait
- Barre de saisie : centrage vertical corrigé (interligne réparti également, hauteur de ligne imposée et arrondie au pixel, même taille pour l'invite et le texte saisi, correction optique de 1 px). Mesuré au rendu réel : majuscules et minuscules équilibrées autour du centre (écart moyen ≈ 0,1 px). Mesures regroupées dans `MesuresBarre`.
- Bouton « + » : fond beige clair, contour très fin, survol et appui plus nets.
- Fond animé (`fond_jarvis_anime.dart`) : centre ivoire lumineux, bords beige chaud, halo lavande autour des particules, nappes violettes qui dérivent (boucles de 50 à 80 s), fines courbes lumineuses qui glissent. Réagit à l'écoute (lavande resserrée) et à la parole (courbes plus vives, lumière centrale). 30 images/s (20 sur téléphone), version simplifiée sur petit écran, immobile si « réduire les animations ».
- Palette : ivoire principal, beige chaud, violet poudré, lavande ; accent #5559B8, graphite #272932.
- 85 tests (centrage, responsive sur 5 formats, réduction des animations).

---

## 2026-10-06 — Accueil : calibrage du fond et position de la barre

### Fait
- Fond animé plus présent, sans toucher aux particules, au texte ni à la barre :
  - lavandes propres au fond (`#D3C5F3`, `#E0D4F6`…), celles du thème étant trop proches de l'ivoire pour se voir ;
  - nappes plus opaques (0,85) et plus grandes (×1,15), placées sur les côtés de la sphère, bords très diffus ;
  - courbes plus visibles (0,7) : trait blanc fin + lueur lavande (10 px, floutée sur grand écran), venant des bords et passant sous la sphère ;
  - 1 à 2 anneaux d'énergie inclinés qui passent derrière la sphère ;
  - lumière centrale ivoire plus forte (0,9, étendue 0,5) entourée d'un halo lavande (1,35) ;
  - périphérie haut/bas réchauffée (beige), lavande sur les côtés.
- Barre de saisie remontée : marge du bas 72 px (grand écran), 52 px (moyen), 24 px (téléphone).
- Mobile : 2 nappes, 2 courbes, 1 anneau, lueur sans flou.
- `flutter analyze` propre, 85 tests OK ; vérifié à 1280×760, 800×870 et 375×812.

### Prochaine étape
- Ajuster finement les valeurs de `ReglagesFond` à l'œil si besoin.

---

## 2026-10-06 — Performance du moteur graphique (sans changement visuel)

### Mesuré d'abord
- Banc Web (`tool/banc_perf.dart`, Edge + GPU Intel) : temps des images, sections du moteur (`ChronoPerf`), coût de chaque élément en le retirant.
- Goulots : rasterisation des points floutés un par un (plan du fond + halos ≈ 6,6 ms), lueur floutée des courbes du fond (≈ 8 ms, refaite à chaque image sur le Web), répulsion des particules (2,4 ms), repeint de toute la page par la pastille animée du bouton vocal.

### Fait
- Particules : points flous et halos pré-rendus une fois (même pinceau, même flou) puis recopiés par `drawRawAtlas` → rasterisation PIM −45 %.
- Répulsion : grille limitée à la zone occupée, chaque paire calculée une fois → −57 % (positions identiques au pixel près).
- Couleurs par plan × style pré-calculées ; peintre PIM conservé (sprites jamais refaits aux reconstructions).
- `RepaintBoundary` : pastille du bouton vocal, barre de saisie, statut vocal.
- Fond : cadence adaptative (30 → 20 i/s, 20 → 15 sur téléphone) si les images dépassent durablement 18 ms.
- Non-régression : 12 captures déterministes, écart moyen 0,01/255, PSNR ≈ 70 dB (invisible).

### Résultats (avant → après, mêmes conditions)
- 1280×800, accueil repos : 64 → 43 ms/image ; écoute : 65 → 24 ms ; raster 44 → 28 ms (machine sur batterie, chiffres absolus bridés).
- 390×844, accueil repos : 40 → 25 ms ; interactions : latence moyenne 184 → 93 ms.

### Prochaine étape
- Lueur des courbes du fond : seul gros coût restant ; toute réduction changerait le rendu (à décider).
- Essayer le rendu Web `--wasm` (skwasm) et mesurer sur Android.

---

## 2026-10-07 — Fond statique, Android (clavier, micro, voix), menu « + »

### Fait
- Fond figé (image exacte de l'ancien fond à t = 0, 0 pixel d'écart) : plus d'horloge, mémorisé en image, redessiné seulement si la mise en page change. Raster accueil 1280×800 : 17,3 → 5,7 ms.
- Clavier Android : débordement de ~20 px causé par la taille animée de la sphère pendant la montée du clavier ; taille bornée à la place réelle, salutation en fondu si la place manque.
- Micro : état réel (`EtatMicro`) ; « Aucun son détecté » jamais après un texte reconnu.
- Reconnaissance : verrou d'écoute, une seule issue par écoute, `pauseFor` supprimé sur Android (cause des error_client / no_match), no_match → pause puis réécoute, texte partiel traité comme phrase.
- TTS : suivi start / complete / error, repli de voix, nouvel essai avec la voix système, journaux `[JARVIS TTS]` (debug).
- « + » sur téléphone : feuille « Ajouter à JARVIS » (coller, importer bientôt).
- Vérifié sur Galaxy S23 (Android 15) : accueil, clavier, feuille, collage, cycle vocal complet avec voix jouée, no_match récupéré, aperçu vocal.
- 108 tests, analyse propre, build web, APK debug.

---

## 2026-10-07 — Conversation écrite (prototype local)

### Fait
- La zone centrale de l'accueil devient un fil de discussion au premier message (même fond, même barre, particules autour de la barre) ; « Nouvelle conversation » ramène à l'accueil.
- Détection locale : conversation collée (« Nom : message », horodatages WhatsApp, messages sur plusieurs lignes, question avant/après) et intention (discussion, réponse, résumé, compréhension, analyse).
- Réponses : discussion par les règles locales existantes ; lecture courte + raccourcis (Comprendre, Résumer, Répondre, Poser une question) ; « Quel ton ? » (6 tons) puis « Réponse proposée » + Copier.
- Moteur derrière une interface `MoteurConversation` : l'API remplacera `MoteurConversationLocal` sans toucher à l'écran.
- 138 tests ; builds : Web (profile), Android debug, Windows debug (correctif MSVC pour permission_handler_windows).

### Prochaine étape
- Brancher l'API IA (implémenter `MoteurConversation`) ; importer un fichier.

---

## 2026-10-07 — Conversation écrite : zones, défilement, clavier, heures

### Fait
- Zones séparées : fil (seule surface qui défile) → écart de sécurité → zone PIM réservée (hauteur maximale réelle des particules au-dessus de la barre, d'après `PimReglages`, en lecture seule) → barre. Particules inchangées.
- Aucune barre de défilement visible (`DefilementSansBarre`, aussi pour le champ multi-ligne) ; molette, trackpad et doigt fonctionnent.
- Fondus haut/bas du fil, marges internes ; une seule surface de défilement.
- Auto-défilement : message de l'utilisateur → toujours en bas ; réponse de JARVIS → seulement si l'utilisateur est à moins de 120 px du bas ; sinon sa position est conservée.
- Heures « HH:mm » (heure locale réelle, stockée dans `MessageConversation.heure`) en bas à droite de la bulle et de la carte JARVIS.
- Plus de genre deviné d'après le prénom (`genre.dart` supprimé) : nom tel qu'écrit, sinon « la personne » / « ton interlocuteur ».
- `DemandeJarvis` transmet aussi le texte réel et l'historique (moteur IA remplaçable).
- 171 tests (33 nouveaux), 42 captures (5 formats), builds Web, Windows debug, APK debug.

### Prochaine étape
- Import / formats (WhatsApp, Messenger, SMS, e-mail) dans une étape séparée.

---

## 2026-10-07 — Finition : espace fil / PIM, signature JARVIS

### Fait
- Hauteur des PIM mesurée sur les pixels dessinés (`tool/mesure_zone_pim_test.dart`) : 29–41 px au repos, 35–42 px à l'envoi.
- Zone PIM : 76,5 px → 44 px (téléphone) / 46 px ; sécurité 8/12/14 → 6/9/10 px ; marge sous le dernier message 14/20 → 8/12 px. Dernier message → barre : ~105–118 px → 65–74 px.
- Inertie des PIM à la fermeture du clavier conservée (moteur inchangé) mais jamais dessinée sur le fil : découpage `LimiteHautePim` au bord haut de la zone.
- Position conservée quand l'utilisateur relit l'historique (repère : premier message visible).
- Signature `SignatureJarvis` : perle bleu-violet (halo, anneau blanc ouvert, d'après la référence) + « JARVIS » Exo2 fin (wght 340), 10–10,5 px, espacé ; la même sur toutes les cartes JARVIS.
- 182 tests ; builds Web, Windows debug, APK debug.

---

## 2026-10-07 — Barre de saisie intelligente

### Fait
- Trois états : repos (vide, sans focus : une ligne, inchangée), focus et saisie (dépliée vers le haut : texte en haut sur toute la largeur, « + » et capsule vocale/envoi sur la ligne du bas).
- Un seul arbre de widgets : boutons ancrés aux coins bas, une animation (230 ms dépliage, 260 ms repli) élargit le champ et ouvre la ligne des boutons ; le champ n'est jamais recréé ni reconstruit pendant l'animation.
- 6 lignes puis défilement interne ; toucher la barre ou ses boutons ne retire pas le focus.
- PIM inchangé : il suit déjà le rectangle réel de la barre à chaque image.
- 195 tests (13 nouveaux) ; builds Web, Windows debug, APK debug.

---

## 2026-10-07 — Barre 4 lignes, espace fil / PIM, particules derrière les cartes

### Fait
- Champ limité à 4 lignes (puis défilement interne, curseur suivi).
- Écart dernière carte → barre : 65 → 51 px (téléphone), 74 → 57 px (ordinateur) : marge du fil 8/12 → 2/4 px, sécurité 6/9/10 → 4/6 px, zone PIM 44/46 → 38/40 px (repos des particules ≈ 33 px).
- Découpage `LimiteHautePim` retiré : pendant la descente (clavier qui se ferme), les particules passent derrière les cartes (calque PIM sous le fil), visibles à travers leur fond, désormais à 94 % d'opacité.
- 196 tests ; builds Web, Windows debug, APK debug.

---

## 2026-10-08 — Formes secondaires PIM : tétraèdre et réacteur énergétique

### Fait
- Cycle commun `FormesPim` (ex-`CubePim`) : chaque forme (`FormeSecondaire`) définit son poids de tirage, ses durées et l'inclinaison de la vue. Rareté inchangée (repos 30–60 s, 2 %/s, 3 min entre deux formes) ; tirage cube 50 %, tétraèdre 35 %, réacteur 15 %.
- Tétraèdre régulier (4 sommets avec nœuds, 6 arêtes, 4 faces), vu légèrement par-dessous, rotation lente ; réacteur d'après la référence : anneau double, triangle pointe en bas, nœuds, rayons, noyau dense avec pulsation discrète, cercle en pointillés, arcs latéraux. Durées 0,8 + 2,4 s, 5 s de maintien, 2,6 s de retour ; cube inchangé.
- Géométries calculées une fois par apparition (tableaux réutilisés), à partir de la position de chaque particule : trajets courts, aucune allocation pendant l'animation.
- Toucher le champ (focus) interrompt aussi une forme ; retour accéléré même pendant un retour normal.
- Paramètres « Particules PIM » : « Formes secondaires : Cube · Tétraèdre · Réacteur énergétique » (lu dans le moteur).
- 212 tests ; captures `tool/capture_rendu_test.dart` (tetraedre, reacteur).

---

## 2026-10-08 — Aperçu des formes PIM depuis les Paramètres

### Fait
- Paramètres → Particules PIM : section « Aperçu des formes » (Cube 3D, Tétraèdre 3D, Réacteur énergétique ; une seule choisie) et bouton « Voir l'aperçu ».
- La fenêtre se ferme en renvoyant la forme ; `ouvrirParametres` attend la fin réelle de sa fermeture (`route.completed`), puis l'accueil (jamais recréé) appelle `PimController.lancerApercu`.
- Séquence dans le moteur : particules au centre (même en conversation, texte intact), sphère présentée, puis cycle habituel de la forme (sans repos, probabilité ni délai), retour, comportement normal.
- Annulé par une vraie interaction (frappe, envoi, focus, voix, réouverture des Paramètres) ; un seul aperçu à la fois.
- `PastilleReglage` partagée (profil vocal, formes) ; libellé souple sur écran étroit.
- 222 tests ; captures `tool/capture_apercu_formes_test.dart`.

---

## 2026-10-08 — Menu latéral

### Fait
- Bouton menu (deux traits) en haut à gauche ; le bouton Paramètres de l'accueil passe dans le menu ; « Nouvelle conversation » passe à droite pendant une conversation.
- `MenuLateral` : panneau posé par-dessus l'accueil (Stack), glisse depuis la gauche (260 ms easeOutCubic, fermeture inverse 230 ms), voile noir lavande à 11 % ; ne dessine rien une fois fermé ; calques propres (le contenu du panneau n'est pas reconstruit pendant l'animation).
- Fermeture : voile, ×, Échap, Retour Android (`PopScope`), symbole JARVIS, choix d'une entrée.
- Entrées réelles : Nouvelle conversation, Chat vocal, conversation en cours (titre) ; pas d'historique fictif. En bas : `PerleJarvis` (symbole des réponses, 28 px) → accueil ; Paramètres → fenêtre existante.
- PIM jamais touché (même état, même ticker, aucune forme déclenchée) ; texte et conversation conservés.
- 236 tests ; captures `tool/capture_menu_test.dart`.

### Prochaine étape
- Historique des conversations (le menu a déjà sa place « En cours »).

---

## 2026-10-08 — Icônes du menu

### Fait
- Bouton menu : la perle JARVIS (`PerleJarvis`, 28 px, centrée, zone tactile 44 px) remplace les deux traits.
- Paramètres du menu : roue dentée `Icons.settings_outlined` à la place des curseurs.

---

## 2026-10-08 — Chat vocal en arrière-plan (bouton vocal)

### Fait
- `VoiceSession.reprenable` : vrai après « Quitter le mode vocal » s'il y a eu au moins un échange (micro et voix coupés, contexte vocal gardé) ; faux à la reprise, après « Au revoir JARVIS » et à une nouvelle conversation (`terminerChatVocal`, contexte vocal oublié).
- Bouton vocal : la capsule indique le chat vocal (graphite / dégradé bleu doux → violet, 220 ms), le contenu garde la logique de saisie (onde vocale / flèche d'envoi) ; libellé « Reprendre le chat vocal ».
- « Quitter le mode vocal » : libellé souple (débordait de 12 px sur 390 px avec la police de test).
- 244 tests ; captures `tool/capture_bouton_vocal_test.dart`.

### À noter
- Les conversations écrite et vocale ne sont pas encore partagées : le vocal garde son propre contexte et ses échanges ne sont pas transcrits dans le fil écrit.

---

## 2026-10-08 — Conversation unique, navigation vocale, forme principale PIM

### Fait
- Une seule conversation : la session vocale répond par `ConversationSession.repondreVocal` ; chaque phrase validée et sa réponse sont ajoutées au fil (`MessageConversation.vocal`), avec le même moteur et le même contexte (`VoiceCommandService` unique). Contexte partagé dans les deux sens ; « Nouvelle conversation » remet le contexte à zéro (`MoteurConversation.reinitialiser`).
- Mode vocal : « Retour au chat » (à droite de « Quitter le mode vocal » sur grand écran, dessous sur téléphone) ; « Quitter » inchangé. Lecture vocale facultative en mode écrit (haut-parleur en haut à droite), coupée par défaut et à chaque retour du vocal ; micro jamais ouvert.
- Forme principale (`FormePim`, modèle commun) : Sphère (défaut), Cube 3D, Tétraèdre 3D, Réacteur Arc ; choisie dans Paramètres → Particules PIM → « Forme principale » (pastilles + « Voir l'aperçu » avec liste), enregistrée (`PreferencesPimService`, SharedPreferences).
- Moteur : la forme principale garde les réactions de la sphère (même échelle radiale : écoute, réflexion, parole, ondes) ; transition de 2,4 s ; formes secondaires tirées parmi les trois autres (sphère comprise), rareté inchangée ; aperçu de la forme principale = présentation au repos.
- Sphère par défaut : rendu identique au pixel près (12 captures comparées).
- 278 tests ; builds Web, Windows debug, APK debug.

---

## 2026-10-10 — Mode vocal : quitter ≠ retour au chat, haut-parleur, barre plus fluide

### Fait
- Paramètres → Particules PIM : bloc « Aperçu » (liste + « Voir l'aperçu ») retiré ; le choix de la forme principale suffit. `ouvrirParametres` ne renvoie plus rien. Le moteur garde `PimController.lancerApercu` (tests, captures).
- « Quitter le mode vocal » arrête vraiment le chat vocal (`VoiceSession.quitterChatVocal`) : rien à reprendre, capsule sombre, pas de haut-parleur ; la conversation et son contexte restent. « Retour au chat » garde le chat vocal en arrière-plan (capsule bleu-violet).
- Les deux commandes du mode vocal sont centrées ensemble sur grand écran (l'une sous l'autre sur téléphone, inchangé).
- Haut-parleur (lecture vocale) : retiré de la barre du haut, placé dans la barre de saisie juste à gauche de la capsule vocale, seulement quand elle est bleu-violet. Lecture coupée par défaut et dès que le chat vocal se termine.
- Barre de saisie : repli/dépliage plus doux (même courbe dans les deux sens, repli 300 ms) ; l'invite s'efface à mi-chemin puis réapparaît à sa place au lieu de glisser en diagonale.
- 278 tests ; capture `tool/capture_bouton_vocal_test.dart` (avec haut-parleur).

---

## 2026-10-10 — Authentification : interfaces et préparation du backend

### Fait
- Trois pages (`lib/pages/authentification/`) : connexion (« Heureux de vous revoir »), inscription (« Rejoindre JARVIS », 4 champs), mot de passe oublié ; parcours commun `AuthentificationPage` (fondu 220 ms, Retour → connexion, saisies conservées entre les pages, e-mail partagé, mots de passe effacés à la sortie).
- Composants réutilisables (`lib/widgets/authentification/`) : `LogoAuth` (perle JARVIS provisoire, un seul endroit à changer), `EnteteAuth`, `ConteneurAuth` (fond, SafeArea, défilement, largeur max 420), `ChampAuth` (afficher / masquer le mot de passe), `BoutonAuth` (chargement), liens, `BandeauAuth`, `BrouillonAuth`.
- Validation locale réglable (`ValidationAuth`, `ReglesValidationAuth` : 8 caractères provisoires) ; e-mail et nom nettoyés des espaces, mots de passe jamais modifiés ; erreurs sous les champs ; Tab / Entrée.
- Architecture : pages → `AuthService` (une opération à la fois) → `AuthRepository` (contrat) ; implémentation actuelle `AuthRepositoryNonConfigure` : échec clair « disponible après l'intégration du serveur », jamais de session. `StockageSession` / `StrategieSession` (durable mobile-desktop, navigateur sur le Web) : contrats seulement. `ConfigAuth` : `JARVIS_API_URL`, `JARVIS_ACCES_DEV`.
- Navigation : lancement → `restaurerSession()` → accueil si session, sinon connexion. « Continuer sans compte » (debug / profile, absent en release) ouvre l'accueil sans session.
- Documentation backend : `docs/integration_backend_auth.md`.
- 33 tests (`test/authentification_test.dart`) ; captures `tool/capture_auth_test.dart` ; vérifié dans le navigateur (build Web release : pas d'accès de développement, validation, Tab / Entrée, message « pas encore disponible »). Builds Web, Windows debug, APK debug.

### Limites
- Aucune déconnexion dans l'accueil (pas encore de session réelle à fermer).
- Capture d'écran du design non reçue : style déduit de la description et du thème JARVIS.

### Prochaine étape
- Recevoir le contrat du backend (questions listées dans la documentation), puis écrire `AuthRepositoryServeur` et le stockage sécurisé.

---

## 2026-10-10 — Chargement Web : fond ivoire

### Fait
- `web/index.html` et `web/manifest.json` : fond de chargement `#070B16` (reste de l'ancien thème sombre) remplacé par l'ivoire `#FAF8F2` du thème actuel ; `color-scheme` clair ; titre de l'onglet « JARVIS ».

---

## 2026-10-10 — Paramètres plus simples

### Fait
- Langue : seulement Français, Anglais, Allemand, Espagnol (dans cet ordre, s'ils ont une voix) ; la région par défaut est choisie (fr-FR, en-US, de-DE, es-ES), choisir une voix d'une autre région change l'accent (`VoiceSettingsService.langues`, `choisirLangue`, `voixDeLaLangue`, `choisirVoixDisponible`).
- Voix : noms simples (`utils/noms_voix.dart`) : « Denise · Naturelle », « Sylvie · Canada · Naturelle », « Voix 1 » pour les identifiants système.
- Diction : icônes de chaque côté des curseurs (marche / course, flèches, volume) à la place des légendes ; valeurs lisibles (« Normale », « ×1,25 », « +20 % ») ; plus de remarque technique.
- Textes d'explication retirés (profil, langue, voix, micro) ; réponse automatique : « Dès que vous avez fini de parler. »
- Particules PIM : carte technique (2 200, liste des formes, « Bientôt ») retirée ; « Forme de JARVIS » en 4 tuiles à icônes (2 par ligne sur téléphone), sans « — Par défaut ».
- Tests : `test/noms_voix_test.dart`, langues dans `voice_settings_test.dart` ; captures `tool/capture_parametres_test.dart`.

---

## 2026-10-11 — Icône du Réacteur Arc

### Fait
- Tuile « Réacteur Arc » des Paramètres : vrai dessin au trait (`widgets/parametres/icone_reacteur_arc.dart`, CustomPainter) : anneau extérieur, dix bobines entre deux anneaux, anneau intérieur, noyau alvéolé ; suit la couleur de la tuile (graphite / bleu-violet).
- `TuileChoix` accepte n'importe quel visuel (icône Material ou dessin).

---

## 2026-10-11 — Menu latéral : conversations multicanal

### Fait
- Panneau existant conservé (en-tête, entrées, « EN COURS », perle et Paramètres en bas, animation, voile) ; nouvelle partie « MES CONVERSATIONS » dessous : sélecteur horizontal (JARVIS, WhatsApp, Gmail, Messenger, Instagram), recherche, liste de la source choisie.
- Vrais logos SVG officiels en local (`assets/logos/`, origine dans `SOURCES.md`), paquet `flutter_svg`. Logo JARVIS du sélecteur : emplacement `assets/logos/jarvis.png`, perle JARVIS affichée en attendant l'image.
- Sélection : contour et fond violet léger, libellé marqué (140 ms) ; seule la zone de la liste glisse (200 ms, easeOutCubic), dans le sens de l'ordre des onglets ; changements rapides sans désynchronisation.
- Défilement gardé par source (et après fermeture du menu) ; listes `ListView.builder` à hauteur fixe ; seules les listes affichées existent.
- Épingles : appui prolongé (téléphone), clic droit ou bouton ⋯ au survol (ordinateur), touche Menu / Maj+F10 (clavier) ; épinglées en tête (dernière épinglée d'abord), sans rubrique ; propres à chaque source ; enregistrées sur l'appareil (`EpinglesConversations`, stockage existant).
- Recherche limitée à la source choisie (titre et aperçu, sans casse ni accents), remise à zéro au changement de source ; états vides discrets, aucun bouton « Connecter / Importer ».
- Architecture : `SourceConversation`, `ApercuConversation`, `FournisseurConversations` (une par messagerie), `ConversationsMulticanal` (sélection, tri, recherche, positions). JARVIS réel : « Nouvelle conversation » met la conversation de côté (messages + contexte du moteur) ; la rouvrir depuis le menu la restaure (`ConversationSession.ouvrir`). Autres messageries : `FournisseurNonIntegre` (vides). Aucun backend, aucune intégration externe.
- Tests : `test/menu_multicanal_test.dart` (20), données de démonstration `test/fixtures/conversations_demo.dart` ; captures `tool/capture_menu_test.dart`.

### À faire
- Déposer l'image du logo JARVIS (`assets/logos/jarvis.png`).
- Historique JARVIS permanent (aujourd'hui en mémoire pendant la session).
- Modules Gmail, WhatsApp, Messenger, Instagram (fournisseurs réels).

---

## 2026-10-11 — Import WhatsApp, étape 1 : choisir un export

### Fait
- Bouton « + » : « Importer un fichier — bientôt » devient « Importer une conversation », avec le vrai logo WhatsApp (`assets/logos/whatsapp.svg`) à gauche et une flèche à droite, sans sous-titre. Sur ordinateur, c'est une entrée du menu flottant ; sur téléphone, une ligne de la feuille « Ajouter à JARVIS ». « Coller une conversation » ne change pas.
- Un clic ferme le menu et ouvre `ImportationWhatsAppPage` (fondu + léger glissement, 260 ms) par-dessus l'accueil : la conversation en cours et le chat vocal ne sont pas touchés, et les particules PIM se mettent en pause tant que la page les recouvre. Retour : bouton ← ou Échap.
- Page : zone « Sélectionner un fichier / Formats acceptés : ZIP, TXT ». Après le choix : nom, format, taille (« ZIP · 17,5 Mo »), « Fichier sélectionné », « Changer de fichier », « Retirer », et un message indiquant que l'analyse viendra à l'étape suivante. Aucune conversation n'est simulée.
- Sélection réelle avec le paquet `file_picker` (^11.0.2) sur Android, iOS, Web et Windows. Vérifications : extension, fichier vide, plus de 1 Go, premiers octets (signature ZIP, texte non binaire), annulation, erreurs d'accès. Seuls les 4 premiers Ko sont lus ; le reste reste ouvert en flux pour l'étape 2 (aucun chemin sur le Web).
- Architecture : `models/importation/`, `services/importation/`, `widgets/importation/`, `utils/taille_fichier.dart`.
- Tests : `test/importation_whatsapp_test.dart` (10) et `accueil_responsive_test.dart` mis à jour ; captures dans `tool/capture_importation_test.dart`.

### Prochaine étape (étape 2)
- Décompresser le ZIP, trouver le fichier texte des messages, extraire participants, dates, heures et contenus, et repérer les médias.

---

## 2026-10-11 — Import WhatsApp, étape 1 : partage Android et réception multiplateforme

### Fait
- **Sélecteur corrigé.** Sur Android, `file_picker` limitait le choix aux types `text/plain` et `application/zip`, si bien qu'un export étiqueté `x-zip-compressed` ou `octet-stream` apparaissait grisé. Il recopiait aussi tout le fichier dans le cache avant de répondre, ce qui figeait la page sur un gros ZIP. Désormais, Android utilise son propre sélecteur de documents (`ACTION_OPEN_DOCUMENT`, sans filtre de type) : le fichier est lu en flux depuis son `content://`, sans copie, et le format est reconnu d'après le contenu. Windows, Web et iOS gardent `file_picker`, filtré sur ZIP et TXT.
- **Partage Android** (« Exporter la discussion » puis JARVIS) : filtres `SEND` (text/plain, zip, x-zip, x-zip-compressed, octet-stream) et `SEND_MULTIPLE`, `singleTask`, `PontImportation.kt` (canal `jarvis/importation`). Aucune permission de stockage n'est demandée, seules les URI `content://` sont acceptées, et rien du contenu n'est journalisé.
- **Lancement à froid** : le partage attend l'accueil, y compris après la page de connexion, puis la page d'import s'ouvre avec le fichier déjà sélectionné. **JARVIS déjà ouvert** : le partage arrive par `onNewIntent` dans la même instance ; une seule page d'import est ouverte, et le nouveau fichier remplace l'ancien. Chaque partage n'est traité qu'une fois (file native consommée, identifiants vus côté Dart, intent neutralisé).
- **Plusieurs fichiers reçus** : l'utilisateur désigne l'export ; rien n'est lu avant ce choix. Un partage de texte sans fichier affiche un message clair.
- **Modèle et chemin communs** : `FichierBrut` → `SelectionExportWhatsApp.verifier` → `FichierExportWhatsApp` (id temporaire, nom, format, taille éventuelle, type MIME, source, validation initiale). Le format est détecté d'après le contenu (signature ZIP, texte ou binaire), puis le nom et le type MIME servent à départager et à expliquer un refus (archive endommagée, texte illisible, format non pris en charge, vide, plus de 1 Go, accès impossible).
- **Interface** : sur Android, un guide « Depuis WhatsApp » en 3 étapes et « Parcourir les fichiers » en second choix ; sur Windows, Web et iOS, une zone compacte avec un bouton « Parcourir les fichiers ». La carte affiche « Fichier sélectionné » (jamais « importé » ni « analysé ») et précise « reçu par partage » ou « déposé » selon la source.
- **Glisser-déposer** : Web (paquet `web`, fichiers lus par tranches, aucun chemin) et Windows (`WM_DROPFILES`, canal `jarvis/depot`), actif seulement pendant que la page est ouverte.
- **Tests** : `test/importation_whatsapp_test.dart` (détection, réception, page, partages, dépôt) et un test de partage à froid et à chaud dans `accueil_responsive_test.dart`. Sur un Galaxy S23 Ultra (Android 15) : JARVIS apparaît dans le menu de partage ; un ZIP partagé est reçu à froid et à chaud ; deux fichiers partagés ensemble donnent un choix qui aboutit au TXT ; le sélecteur natif permet de remplacer le fichier ; le retour ramène à l'accueil intact.

### Limites connues
- Le partage depuis l'application WhatsApp elle-même n'a pas été testé : je l'ai simulé depuis le gestionnaire de fichiers (même mécanisme `SEND` / `content://`).
- iOS : sélection manuelle seulement ; le partage direct demandera une Share Extension native (non développée).
- Dans le menu de partage, l'application s'appelle « ia_jarvis » (nom actuel de l'application), avec « JARVIS » en sous-titre.
- Taille parfois inconnue lors d'un partage : la limite de 1 Go sera alors appliquée pendant la lecture (étape 2).

### Prochaine étape (étape 2)
- Lire le TXT, décompresser le ZIP (avec des limites contre les archives démesurées ou malveillantes), trouver le fichier des messages, extraire participants, dates, heures et contenus, et repérer les médias.

---

## 2026-10-11 — Import WhatsApp, étape 2 : lecture réelle et aperçu

### Fait
- **Parcours sur une seule page**, avec des transitions de 180 à 280 ms (fondu, léger glissement, hauteur animée) : fichier sélectionné → « Lire la conversation » (« Le fichier sera analysé sur cet appareil. ») → lecture (anneau de progression réelle, étape en une ligne, « Annuler ») → résultat.
- **Résultat** : « Conversation détectée », le titre (nom du contact d'après le nom du fichier, sinon les participants), « 3 482 messages · 2020 — 2026 », « Médias non importés » (discret), « Vous êtes : » (une puce par participant, groupes compris), puis les 100 derniers messages (liste virtualisée, séparateurs de jour, bulles lavande à droite pour « Moi », claires à gauche, nom de l'auteur seulement dans les groupes). « Filtrer les messages » est affiché mais inactif (« Prochaine étape du développement ») : rien n'est simulé.
- **Moteur** (local, déterministe, sans IA ni réseau) :
  - `LecteurWhatsApp` : copie privée temporaire (cache de l'application ; mémoire sur le Web), relisible même si le fichier partagé ne l'est plus, effacée après la lecture ; progression en octets ; annulation ; la main est rendue à l'interface toutes les 2 000 lignes ; aucune limite sur le nombre de messages.
  - ZIP (paquet `archive`) : seul l'index est lu, puis le fichier de discussion ; les médias ne sont jamais décompressés ; décompression dans un isolate séparé (sauf sur le Web) ; sortie bornée (texte de 512 Mo au maximum, jamais au-delà de la taille annoncée) ; « bombes » refusées ; chemins dangereux ignorés ; s'il y a plusieurs TXT plausibles, l'utilisateur choisit.
  - `AnalyseurWhatsApp` : formats Android et iOS, 24 h et AM/PM (dont « p. m. » et l'espace insécable d'iOS 17), séparateurs `/ . -`, ISO, plusieurs langues, marques invisibles, messages sur plusieurs lignes, messages système (sans auteur), messages supprimés, médias omis ou joints (type d'après le fichier : photo, vocal, vidéo…). Ordre jour/mois déduit des nombres supérieurs à 12, puis de l'ordre chronologique ; sinon l'ordre retenu est signalé comme incertain. La date brute est toujours gardée ; une date impossible n'est jamais corrigée en silence. Les lignes situées avant le premier message sont comptées.
  - `MessageWhatsApp` : identifiant, ordre d'origine, auteur brut, date et date brute, texte exact, type et média, empreinte (FNV-1a, exacte aussi sur le Web) pour un futur repérage des doublons.
- **« Moi »** : choisi d'un toucher, mémorisé sur l'appareil (`IdentiteWhatsApp`), reconnu aux imports suivants et corrigeable.
- **Stockage temporaire** : le résultat reste en mémoire (`importWhatsAppEnCours`) pour le filtrage, et est oublié à la fermeture de la page.
- **Tests** : `test/lecture_whatsapp_test.dart` (29 : formats, dates, ZIP, sécurité, 30 000 messages) et `test/lecture_whatsapp_page_test.dart` (6 : parcours, « Moi », annulation, choix dans l'archive, erreur, 5 001 messages à 320 px). Captures de rendu dans `tool/capture_importation_test.dart`.

### Limites connues
- AM/PM écrits dans d'autres alphabets (coréen, japonais, arabe…) : non reconnus ; ces lignes deviennent la suite du message précédent.
- Un message système qui contient « : » peut être pris pour un message d'un participant.
- Sur le Web, l'export est gardé en mémoire le temps de la lecture.

### Prochaine étape (étape 3 : filtrage)
- Aujourd'hui, hier, dernières heures, période ou plage de dates, heures et minutes, sélection entre deux messages ou message par message, à partir de `importWhatsAppEnCours`.

---

## 2026-10-11 — Import WhatsApp : interface compacte, lecture automatique

### Fait
- **Aucun fichier** : carte « Importer depuis WhatsApp » (logo sur une tuile claire, halo lavande et deux anneaux fins, sans animation). Sur Android, sous-titre « Partagez un export avec JARVIS » et bouton « Ouvrir WhatsApp », qui lance réellement WhatsApp (ou WhatsApp Business ; message clair s'il est absent) ; l'export revient ensuite par le partage. Aucun faux « Recevoir ». Puis la carte « Parcourir les fichiers · ZIP, TXT » et le bouton « Comment importer ? » (étapes dans une feuille en bas). Sur Windows et le Web, le bouton principal est « Parcourir les fichiers », et le glisser-déposer reste actif.
- **Fichier reçu** : la lecture démarre seule, une seule fois par fichier accepté (jamais depuis `build`). Progression compacte dans la carte (réelle ou indéterminée) avec « Annuler ». Puis « Conversation prête », uniquement après une lecture réussie ; « Filtrer les messages » (action principale, inactive avec « Filtrage : prochaine étape du développement ») ; « Voir le résumé ». « Changer de fichier » et × pour retirer. En cas d'erreur : le message et « Relire le fichier ».
- **Résumé facultatif** (`ResumeWhatsAppPage`) : ampleur, « Vous êtes : », derniers messages ; au retour, rien n'est perdu. Plus aucun message sur l'écran principal.
- **Android** : méthode `ouvrirWhatsApp` dans le pont ; `<queries>` pour `com.whatsapp` et `com.whatsapp.w4b`.
- Corrigé : anneau de progression indéterminé (une taille inconnue faisait échouer l'animation) ; pastille « Conversation prête » sans débordement en très grande police.
- Supprimés (remplacés) : `guide_partage_android.dart`, `zone_selection_export.dart`, ancien indicateur plein écran.
- Tests : `test/lecture_whatsapp_page_test.dart` réécrit (19 : accueil Android et ordinateur, ouverture de WhatsApp, lecture automatique unique, annulation, erreur, ZIP à choisir, plusieurs fichiers, remplacement, sélecteur, dépôt, résumé et retour, 5 001 messages, débordements).

---

## 2026-10-11 — Import WhatsApp : actions hors des cartes, résumé en discussion

### Fait
- **Aucun fichier** : la grande carte ne contient plus que le logo (centré, marges égales en haut et en bas), le titre et la description. Le bouton violet (« Ouvrir WhatsApp » sur Android, « Parcourir les fichiers » ailleurs) est sous la carte, dans sa propre zone, sans changer son fonctionnement. Puis « Parcourir les fichiers » (Android) et « Comment importer ? », devenu un simple lien. La composition est un peu plus basse (espace proportionnel à la hauteur, de 20 à 44 px).
- **Conversation prête** : la carte garde le nom du fichier (2 lignes au maximum, coupé proprement), le format, la taille, la source et « Conversation prête ». Son pied contient deux actions discrètes à parts égales : « Voir le résumé » et « Changer de fichier » (plus × pour retirer). « Filtrer les messages » est sorti de la carte : zone d'action en bas de l'écran (`ActionFiltrer`, hors du défilement, `SafeArea`), visible seulement quand la conversation est prête, inactive avec « Bientôt disponible ». La lecture automatique est inchangée.
- **Résumé** (`ResumeWhatsAppPage`), refait comme une discussion :
  - En-tête compact : « Résumé de la conversation » en petit, le nom réel, puis « 172 messages · 3 juillet – 11 octobre 2026 » (période réelle), et la mention discrète des médias non importés (et des dates incertaines s'il y en a).
  - « Vous êtes » est supprimé de cette page. « Moi » reste reconnu s'il a déjà été confirmé et gardé dans `importWhatsAppEnCours` pour l'interface 3 ; rien n'est choisi à la place de l'utilisateur.
  - Toute la conversation dans une liste virtualisée et inversée : elle s'ouvre sur les messages les plus récents, et seules les bulles visibles sont construites.
  - Bulles (`apercu_discussion.dart`) : leur largeur suit le contenu (80 % au plus, 440 px maximum) ; l'heure est sur la dernière ligne si elle y tient ; les retours à la ligne d'origine sont gardés ; un message reste toujours une seule bulle ; aucun faux accusé de lecture. À deux, côtés stables (le premier qui écrit à gauche sur fond clair, l'autre à droite en lavande) qui ne désignent pas l'utilisateur ; le nom figure en tête de chaque suite. En groupe, tout est à gauche, avec une couleur par participant.
  - Médias non importés : petite bulle (icône selon le type, « Média non importé », heure réelle). À partir de 3 médias consécutifs du même auteur, le même jour et sans légende, une seule bulle « 4 médias non importés · 21:01 – 21:04 ». Ce regroupement ne concerne que l'affichage.
  - Séparateurs : petite capsule centrée, « dimanche 6 septembre 2026 ».
- **Vérification des dates** :
  - Sur un vrai export iOS (7 750 messages), contrôlé sans afficher aucun contenu : date brute = date interprétée pour 100 % des messages, aucune date illisible, ordre jour/mois sûr. L'export contient 7 petites inversions d'ordre (2 min 15 s au plus, aucune au passage de minuit) : elles viennent du fichier lui-même et sont gardées telles quelles. Dans l'aperçu, chaque séparateur correspond au jour réel des messages placés dessous (0 écart, ordre intact).
  - Aucun défaut du parseur trouvé. Deux défauts d'affichage corrigés :
    - l'ancien aperçu commençait au 100ᵉ message avant la fin, si bien que la première date visible n'était pas la plus récente ;
    - un message à date illisible se rangeait sous le jour précédent ; il a maintenant son séparateur « Date non reconnue » et garde sa date brute.
  - Un séparateur est posé à chaque changement de jour, même en arrière : un message de 23:59 noté après minuit reste sous son vrai jour.
  - L'export Android « Jordi Mabila » des captures n'était pas sur l'ordinateur : il n'a pas pu être contrôlé directement.
- **Tests** :
  - `test/apercu_discussion_test.dart` (nouveau, 11 tests) : export horodaté avec passage de minuit, inversion, multiligne, médias en série et date impossible. Il vérifie la date brute, l'interprétation, l'heure, l'ordre et le regroupement par jour, ainsi que la date du nom des photos (IMG-AAAAMMJJ), qui confirme l'interprétation. Il couvre aussi le jour ambigu (≤ 12), 30 000 messages, les côtés et la période.
  - `test/lecture_whatsapp_page_test.dart` mis à jour : bouton hors de la carte, logo centré, « Filtrer » en bas de l'écran, résumé sans « Vous êtes », séparateurs, côtés, médias regroupés, et grande police (×1,6) avec noms longs à 320 px.
  - `tool/capture_importation_test.dart` : scénario plus riche.

### Limites restantes
- Le regroupement des médias ne se déplie pas : il donne le nombre et la plage horaire.
- Si un export ne contient que des jours ≤ 12 sans ordre chronologique décisif, l'ordre jour/mois reste une supposition (signalée). Les dates dans les noms des médias (exports avec médias) pourraient servir à trancher : piste non mise en œuvre.

### Prochaine étape
- Interface 2 : filtrage des messages (brancher `ActionFiltrer.surFiltrer`).

---

## 2026-10-12 — Menu latéral : balayage, épinglage et suppression

### Fait
- **Balayage** (téléphone, doigt ou stylet) sur chaque ligne de « MES CONVERSATIONS » (`LigneConversation`) :
  - **vers la droite**, la ligne suit le doigt et révèle, à gauche, un bouton violet « Épingler » (« Désépingler » si la conversation l'est déjà) ;
  - **vers la gauche**, il révèle, à droite, un bouton rouge doux « Supprimer », avec une corbeille. Il n'y a ni « Options » ni « Archiver ».
- **Comportement du geste** :
  - au-delà du bouton, la ligne résiste ;
  - un léger retour haptique signale que le bouton est révélé ;
  - au lâcher, la ligne s'ouvre ou se referme selon la distance ou la vitesse (240 ms, easeOutCubic) ;
  - une seule ligne est ouverte à la fois ; toucher la ligne ouverte ou faire défiler la liste la referme.
  - Le geste ne fait que révéler : rien n'est épinglé ni supprimé sans appui sur le bouton.
- **Épingler** : la ligne se referme, puis la conversation passe en tête de sa propre liste, avec l'épingle discrète. Il n'y a pas de rubrique « Épinglées », et chaque messagerie garde ses épingles. L'état reste enregistré comme avant (`EpinglesConversations`).
- **Supprimer** : la confirmation « Supprimer cette conversation ? » s'affiche (« Cette action supprimera la conversation de JARVIS. », boutons Annuler / Supprimer). Annuler referme la ligne sans rien changer. Confirmer supprime réellement la conversation.
- **Ordinateur et clavier** : le menu existant (clic droit, bouton ⋯, appui prolongé, touche Menu ou Maj+F10) propose aussi « Supprimer la conversation », avec la même confirmation. La souris ne fait pas glisser les lignes. Les actions d'accessibilité « Épingler » et « Supprimer » ont été ajoutées.
- **Suppression réelle** :
  - `FournisseurConversations.supprimer` : seules les données locales de JARVIS sont touchées, sans aucun appel externe ;
  - `ConversationSession.supprimer` : la conversation est retirée de la session (mise de côté ou affichée) et n'est jamais remise de côté ;
  - `ConversationsMulticanal.supprimer` retire aussi l'épingle (`EpinglesConversations.retirer`) : aucune référence invalide ne reste enregistrée.
- **Conversation affichée supprimée** : l'accueil revient vide (même chemin que « Nouvelle conversation », sans mise de côté). Le chat vocal qui lui appartenait se termine et le mode vocal se ferme. Une réponse en préparation n'arrive jamais. PIM n'est pas touché.
- **Tests** : 9 nouveaux dans `test/menu_multicanal_test.dart` :
  - données : JARVIS mise de côté ou affichée, épingle retirée et relue, réponse en retard, messagerie non intégrée ;
  - geste : balayage vers la droite (suivi du doigt, révélation sans action, épinglage, « Désépingler », toucher qui referme), petit geste sans effet, balayage vers la gauche (annuler puis confirmer), une ligne ouverte à la fois ;
  - accueil : conversation affichée supprimée ;
  - ordinateur : clic droit → Supprimer, souris sans glissement.
- **Captures** (`tool/capture_menu_test.dart`) : « Épingler » révélé, « Supprimer » révélé, confirmation.

### Limites
- Les conversations JARVIS ne sont encore gardées qu'en mémoire : elles ne sont pas enregistrées sur l'appareil, donc une suppression ne « survit » à rien de plus (tout disparaît déjà au redémarrage). Les épingles, elles, sont enregistrées et nettoyées.
- WhatsApp, Gmail, Messenger, Instagram : aucune conversation locale pour l'instant (fournisseurs non intégrés). `supprimer` y répond « rien supprimé ». Les conversations WhatsApp importées n'existeront dans la liste qu'avec l'enregistrement (interface 3).

### Prochaine étape
- Enregistrer les conversations sur l'appareil, pour que la suppression soit aussi persistante.

---

## 2026-10-13 — Backend unifié, comptes Supabase, horloge fiable

### Fait
- **Fusion** : le backend FastAPI (Redis, Supabase, GroqCloud) vit dans `backend/` du projet, avec `supabase/schema.sql`, `deploy/`, la CI `.github/`, les scripts `.bat` et `docs/backend/`. L'ancien dossier `C:\Users\jordi\Jarvis-Backend-Ami` n'est plus exécuté : il reste une sauvegarde.
- **Docker** : `jarvis-api` et `jarvis-redis` tournent depuis `backend/` du projet unifié (projet Compose `backend`, volume Redis `backend_redis-data` conservé, ports 8000 et 6379).
- **Comptes (Supabase Auth)** : `AuthRepositorySupabase` ; inscription avec confirmation d'e-mail, connexion, restauration de session, déconnexion, mot de passe oublié et nouveau mot de passe, profil `public.users` (nom modifiable). Paramètres → Compte : profil réel, vérification par le serveur (`GET /me`), déconnexion.
- **Horloge** :
  - cause du « Token invalide » : service Windows Time désactivé (`NoSync`), 202 s de retard, hérités par WSL2 et Docker ; corrigé par `scripts/windows/synchroniser_horloge.ps1` (sources NTP, synchro horaire, resynchro au démarrage et au réveil) ; diagnostic en lecture seule : `scripts/windows/verifier_horloge.ps1` ;
  - backend : `app/horloge.py`, `GET /health/clock`, journaux INFO / WARNING / ERROR, nouvel essai rapide après une mesure ratée ; tolérance JWT inchangée (10 s) ;
  - appareils des utilisateurs : `HorlogeJetons` (durée de vie `exp - iat`, chronomètre monotone) ; FastAPI « Token expiré » → renouvellement puis une seule nouvelle tentative ; session expirée → retour à la connexion avec un message ; décalage de l'appareil signalé dans Paramètres → Compte.
- **Correction backend** : l'enregistrement des messages du chat échouait (400 PGRST102, clés différentes entre message utilisateur et assistant) ; insertion avec la liste des colonnes, vérifiée dans Supabase.
- **Tests** : 476 tests Flutter, 49 tests backend ; réponse IA réelle (GroqCloud `openai/gpt-oss-120b`) par l'API avec un vrai jeton.

### Limites
- Connecteur Supabase MCP non installé : RLS, fonctions et déclencheurs non relus en direct (structure des tables vérifiée par l'API PostgREST, identique à `schema.sql`).
- Clés utilisées pendant les tests (service_role, GroqCloud) : à renouveler avant une mise en production.

### Prochaine étape
- Moteur de conversation hybride (commandes locales + IA du backend), puis MIA universel.

---

## 2026-10-13 — Conversation reliée à l'IA du backend (moteur hybride)

### Fait
- **Moteur hybride** (`MoteurConversationHybride`) : règles locales d'abord (heure, date, calcul, prénom, notions, « au revoir », conversation collée), sinon `MoteurConversationIA` → `ApiJarvis.discuter` → `POST /api/v1/chat/stream` → GroqCloud. Un seul moteur pour l'écrit et le vocal (`VoiceSession` inchangé : il passe déjà par `ConversationSession`).
- **Mode « IA disponible »** des règles locales (`reponseLocale(avecIA: true)`) : les échanges courants (« ok », « merci », « demain », « bonjour »…) ne captent plus que les phrases courtes ; les réponses écrites faute d'IA (« je n'ai pas d'IA branchée », liste des capacités, « ton fonctionnement ») laissent la main à l'IA ; « résume / explique / que répondre » sans conversation connue ne demandent de coller une conversation que si la phrase en parle. Aucune règle supprimée ; sans IA, comportement identique.
- **Flux SSE** (`flux_sse.dart`) : décodage UTF-8 et lignes en flux (paquets coupés), `meta` / `delta` / `done` / `error`, réponse affichée une fois complète ; flux lu jusqu'à sa fermeture ; `surFragment` prêt pour l'affichage progressif. Web : `http` 1.6 (fetch + ReadableStream) reçoit bien le flux.
- **Identifiants** : conversation locale → UUID serveur (rattaché dès `meta`) ; seul le nouveau message est envoyé (historique gardé par le serveur) ; nouvelle conversation → nouvel UUID ; conversation rouverte → son UUID ; 404 → nouvelle conversation, une seule fois.
- **Réponses tardives** : fil changé pendant la réflexion → rien n'est envoyé ; réponse arrivée après un changement → rangée dans sa propre conversation (jamais dans le fil affiché), perdue si la conversation a été supprimée.
- **Erreurs** en français dans le fil (et dites en vocal) : serveur injoignable, délai, session expirée (renouvellement puis un seul nouvel essai), quota (heure de renouvellement), GroqCloud indisponible, flux interrompu, réponse vide, message trop long. Jamais de réponse partielle présentée comme complète, jamais d'état « réflexion » bloqué ; les commandes locales restent disponibles hors ligne.
- **Markdown** des réponses du modèle retiré (gras, italique, code, titres) : affichage et voix propres.
- **Confidentialité** : conversations collées et imports WhatsApp jamais envoyés au serveur.
- **Tests** : 508 tests Flutter (32 nouveaux : `test/conversation_ia_test.dart`), 49 tests backend ; tests réels Flutter Web : commande locale sans appel, question IA, contexte conservé, nouvelle conversation distincte, reprise d'une conversation du menu, serveur arrêté puis relancé, mode vocal (vérifié par l'utilisateur). Compilations Web et Windows.

### Limites
- Les réponses locales ne sont pas connues du serveur (ex. « combien font 2 + 2 » puis « et fois 3 ? » envoyé à l'IA).
- Une réponse en erreur après un début de génération est enregistrée partiellement côté serveur (comportement du backend, non modifié).
- Le test `test_tone_is_injected_in_system_prompt` du backend lit `backend/.env` (modèle `openai/gpt-oss-120b`) : il échoue si `.env` change le modèle.
- Android et iOS non testés sur appareil.

### Prochaine étape
- Test sur le Galaxy S10+ (`adb reverse tcp:8000 tcp:8000`), puis affichage progressif des fragments, synchronisation des conversations enregistrées, MIA universel.

---

## 2026-10-13 — Phase 3 : conversations synchronisées entre appareils

### Fait
- **Supabase examiné en direct (MCP)** : RLS active sur les 4 tables, aucun droit `anon` ; `conversations` (lecture, création, modification, suppression : propriétaire seulement), `messages` (lecture et suppression : propriétaire ; insertion `user` seulement ; aucune modification) ; suppression en cascade des messages. Aucune modification de schéma ni de RLS.
- **Liste et historique** : Flutter lit ses conversations et messages avec la session de l'utilisateur (`DepotConversationsSupabase`, règles RLS appliquées, aucune clé administrative) ; conversations vides comprises (supprimables) ; 50 derniers messages, puis « Afficher les messages précédents ».
- **Identifiants** : `CorrespondanceConversations` (conversation du fil ↔ UUID serveur, partagée par le moteur IA et la synchronisation) ; une conversation ouverte depuis le serveur garde son UUID ; fusion sans doublon (UUID du message, ou texte d'une question envoyée depuis l'appareil).
- **Actualisation** : connexion, ouverture du menu, après un échange, retour au premier plan après au moins 30 s masqué (plus de relecture toutes les 22 s au simple changement de focus : vérifié, une seule lecture en 3 min d'inactivité).
- **Suppression** : d'abord sur le serveur (droits vérifiés par la RLS), retirée de l'interface après confirmation ; échec : conversation et épingle conservées, raison affichée dans le menu.
- **Échanges locaux synchronisés** (heure, calcul…) : exécutés sur l'appareil (aucun appel GroqCloud), affichés tout de suite, puis enregistrés par la nouvelle route `POST /api/v1/conversations/local-exchanges` (JWT vérifié, compte lu dans le jeton, conversation du compte seulement, aucun quota, réponse marquée `model = "jarvis-local"`, identifiants choisis par l'appareil : réessai sans doublon, heure de l'appareil corrigée et bornée). File `SynchroEchangesLocaux` gardée sur l'appareil par compte, envoyée au retour du réseau ; une question à l'IA attend l'enregistrement des échanges locaux de sa conversation (même conversation serveur, contexte connu de l'IA). Conversations collées et imports WhatsApp : jamais envoyés.
- **Tests** : 534 tests Flutter, 60 tests backend (11 nouveaux) ; sécurité RLS en transaction annulée (compte A / compte B / déconnecté) ; tests réels Web (liste, historique, suite de conversation, conversation vide ouverte puis supprimée, échange local hors connexion puis envoyé une fois, question IA dans la même conversation) ; Windows → Web (échange local retrouvé) ; compte Windows différent : rien visible sur le Web. Compilations Web et Windows.

### Limites
- Épingles propres à chaque appareil (synchronisation à décider : colonne `pinned`).
- Pas de cache des conversations sur le disque : hors connexion, seule la liste déjà chargée reste affichée.
- Le serveur ne limite pas encore le nombre d'échanges locaux enregistrés par compte.
- Android et iOS non testés sur appareil ; logo `assets/logos/jarvis.png` absent (404 sur le Web, antérieur à cette phase).

### Prochaine étape
- Test sur le Galaxy S10+, décision sur les épingles, puis affichage progressif des réponses.

---

## 2026-10-14 — Performances : mesures réelles (Galaxy S10+, Windows, Web) et PIM

### Fait
- **Backend local** vérifié (Docker : `jarvis-api` 8000, `jarvis-redis` 6379, sains ; `/health`, `/health/ready`, `/health/clock`, routes protégées en 401 sans jeton). Téléphone relié par `adb reverse tcp:8000 tcp:8000` et `--dart-define=JARVIS_API_URL=http://127.0.0.1:8000` ; mode profile : HTTP autorisé seulement vers 127.0.0.1 et localhost (`android/app/src/profile/res/xml/reseau_developpement.xml`), mode release inchangé. Requêtes du téléphone reçues par FastAPI (`local-exchanges` → 201).
- **Outils de mesure** : banc `tool/banc_perf.dart` en suite (`--dart-define=JARVIS_SUITE=accueil|pim|experience`, tous les états puis chaque effet retiré) ; application réelle mesurée par son service VM (`ext.jarvis.chrono` : sections du moteur, `ext.jarvis.variante` : comparaison A/B à chaud), actifs seulement avec `JARVIS_PERF=true`.
- **PIM, clavier et redimensionnement** : les points flous et halos pré-rendus ne sont plus refaits à chaque image d'une transition ; ils sont recopiés à la taille du moment puis refaits exactement une fois la taille stable, par morceaux (12 plans × styles par image) ; les deux niveaux de qualité gardent leurs images. Rendu au repos identique au pixel près (16 captures).
- **PIM, points nets et reflets en atlas** (décision de l'utilisateur) : plus aucun point dessiné un par un. Bords des petites particules très légèrement plus doux (PSNR 39–44 dB, écart moyen 0,15–0,38 / 255).

### Mesures (mode profile)
- Galaxy S10+ (Impeller OpenGL ES, 1440×3040) : banc PIM, rasterisation moyenne avant → après : repos 12,0 → 5,7 ms ; écoute 13,8 → 6,6 ; réflexion 15,4 → 5,5 ; frappe 14,0 → 5,9 (49,9 → 60 i/s) ; p99 ≤ 9,7 ms partout après. Application réelle : A/B dans la même session non concluant (variations de fréquence GPU / cœurs bien plus fortes que l'écart entre variantes).
- Windows (même session, PC chargé) : pas de régression ni de gain au repos (raster 10,3 ms dans les deux cas) ; dessin PIM +0,4 ms sur le fil d'interface.
- Web (même compilation, A/B) : rasterisation PIM seul 4,8–5,0 → 2,9 ms ; accueil 4,9–5,6 → 3,7–4,1 ms.

### Limites
- Le Galaxy S10+ est réglé en WQHD+ : environ 78 % de pixels de plus qu'en FHD+, principal facteur de charge GPU.
- Pendant l'animation du clavier, le fond (dont la taille suit la place disponible) est redessiné à chaque image.

### Prochaine étape
- Mesures répétées sur un appareil à fréquence plus stable ; pistes : coût du fond pendant les transitions, reste du fil d'interface de l'accueil.

---

## 2026-10-14 — Supabase : vues administratives lisibles

### Fait
- Trois vues de consultation dans un schéma dédié `admin` (migration `vues_admin_lisibles`, reprise dans `supabase/schema.sql`) : `conversations_lisibles`, `messages_lisibles`, `quotas_lisibles`. Elles ajoutent `display_name` et `email` (lus dans `public.users` par jointure, rien n'est copié) à côté de `user_id`.
- Sécurité : schéma non exposé par l'API (vérifié : PostgREST répond « Invalid schema: admin »), aucun droit sur le schéma ni sur les vues pour `PUBLIC`, `anon`, `authenticated`, `service_role` ; `security_invoker = true`. Compte connecté simulé : accès refusé. Tables, RLS et droits d'origine inchangés.
- Contrôles : 9 / 34 / 3 lignes comme les tables sources, noms et e-mails conformes pour toutes les lignes, empreintes des données identiques avant / après.
- Aucun changement Flutter ni FastAPI.

### Prochaine étape
- Alertes de sécurité Supabase antérieures à traiter à part : fonctions `SECURITY DEFINER` appelables par l'API (`handle_new_user`, `touch_conversation`, `get_my_quota`), protection contre les mots de passe divulgués désactivée.

---

## 2026-10-14 — Phase 4 : écriture progressive des réponses

### Fait
- **Diagnostic** : le backend diffusait déjà en vrai streaming (SSE `meta` → `delta` → `done`) et `ApiJarvis` lisait chaque fragment, mais `MoteurConversationIA` ne branchait pas `surFragment` : la réponse n'apparaissait qu'à la fin. Backend inchangé.
- **Réception** (`services/ecriture/texte_en_direct.dart`) : tampon des fragments ou texte complet ; états en cours / terminée / interrompue.
- **Affichage** (`services/ecriture/ecriture_progressive.dart`, logique pure pilotée par le temps) : mot par mot à 12 mots/s (rythme choisi après comparaison avec ChatGPT) ; très longues réponses plafonnées à ≈ 20 s ; mot non terminé retenu pendant la réception (jamais de mot ou d'emoji coupé) ; « Tout afficher » sans couper la réception ; `remplacer` (futures propositions de ton) ; pause quand la carte est hors de la vue ; réduction des animations respectée.
- **Widget** (`widgets/ecriture/texte_progressif.dart`) : Ticker actif seulement quand du texte attend, curseur lavande discret, simple `Text` une fois fini ; « Tout afficher » posé à gauche de l'heure (aucun changement de hauteur).
- **Conversation** : une bulle naît au premier fragment (`redaction: true`) puis est finalisée une seule fois avec le même identifiant ; réception, affichage et enregistrement séparés (l'enregistrement n'attend jamais l'animation). Réponses locales : même effet, aucun appel au serveur. Coupure ou erreur en cours : texte reçu gardé + explication, rattaché à l'UUID annoncé par `meta` (le serveur enregistre le partiel) → pas de doublon à l'actualisation. Changement / suppression de conversation : la réponse ne va jamais dans une autre conversation. Markdown inachevé masqué pendant l'écriture.
- **Vocal** : lecture une seule fois, texte entier, dès la fin de la réception ; PIM inchangé (l'écriture ne déclenche pas l'état « parole »).
- **Tests** : 568 tests Flutter (34 nouveaux dans `test/ecriture_progressive_test.dart`, flux SSE simulé fragment par fragment ; aide `test/outils/ecriture.dart`). Compilations Web, Windows et APK profile.
- **Essai réel** sur Galaxy S10+ avec un compte connecté : questions envoyées à GroqCloud via FastAPI, réponse écrite progressivement, un seul enregistrement Supabase par échange.

### Limites
- Pas d'interruption volontaire du flux côté serveur quand une conversation est supprimée (la réponse est simplement ignorée sur l'appareil).
- Rythme réglé sur le téléphone de test : à confirmer sur Web et Windows.

### Prochaine étape
- Valider le rythme mot par mot sur le téléphone, puis réutiliser `EcritureProgressive` dans le futur composant de choix du ton.

## 2026-10-15 — Import WhatsApp, interface 2 : filtrer les messages

### Fait
- « Filtrer les messages » (interface 1) est actif quand la lecture a réussi : il ouvre `FiltrageWhatsAppPage` avec la conversation déjà lue (aucune relecture). Lecture échouée : pas de passage au filtrage.
- État `SelectionWhatsApp` créé par la page d'import pour la conversation lue : gardé au retour, oublié avec elle (un autre fichier repart de zéro).
- Moteur local `IndexWhatsApp` : index chronologique (recherche dichotomique, tri seulement si l'export est désordonné), nombre de messages par jour, mois et années ; filtres aujourd'hui, hier, 7 derniers jours (date locale), derniers 10/25/50/100 bornés au nombre réel, période personnalisée à la minute (bornes comprises, secondes sans effet), plage par ordre d'origine.
- Sélection par identifiants stables (`m<ordre>`) : un filtre coche ses messages ; décocher / recocher ; les décochés restent visibles (pâlis) et restent décochés au filtre suivant s'ils en font partie. Événements WhatsApp non sélectionnables. Messages sans date : jamais rangés dans une période, cochables dans « Par messages ».
- Interface : sélecteur [Par période] [Par messages] (capsule lavande + indicateur violet), capsules à défilement horizontal, période personnalisée (Début / Fin : date via le calendrier, heure : roues sur téléphone, saisie clavier sur ordinateur et Web), calendrier (jours avec messages mis en évidence et comptés, navigation mois et années, plage de jours), plage par messages avec consigne, médias groupés à case unique (identifiants gardés), aperçu virtualisé réutilisant les bulles existantes, barre du bas (compteur, « Continuer vers l'enregistrement » inactif : interface 3 absente, explication discrète).
- `MessagesChoisisWhatsApp` : résultat prêt pour l'interface 3 (identifiant de la conversation source, messages dans l'ordre avec auteurs, dates réelles et brutes, contenus, types).
- Tests : `filtrage_whatsapp_test.dart` (21, dont 50 000 messages), `filtrage_whatsapp_page_test.dart` (18 : modes, calendrier, heures, plage, médias, 20 000 messages, 320×568 à police ×2, ordinateur), 3 tests d'intégration dans `lecture_whatsapp_page_test.dart`. Captures : `tool/capture_filtrage_test.dart`.

### État
- Rien n'est enregistré ni envoyé : tout reste en mémoire sur l'appareil.

### Prochaine étape
- Interface 3 : enregistrement des messages choisis (désignation de « Moi »).

## 2026-10-15 — Filtrage WhatsApp : cases du côté des bulles, flèches de navigation

### Fait
- Case de sélection du côté de sa bulle (gauche ou droite), centrée verticalement sur la bulle (marge de tête de suite comprise), aussi pour les messages multilignes et les médias groupés ; événements centrés avec retrait symétrique.
- Mode « Par messages » : flèches discrètes (violet léger, icône ivoire, 34 px visibles, 48 px touchables) en haut à gauche (« Monter ») et en bas à gauche (« Descendre ») ; défilement animé rapide (saut puis animation sur les longues listes) ; chaque flèche n'apparaît que si elle a de la distance à parcourir.
- Tests : centrage et côté des cases (320 px, multiligne), flèches sur 3 000 messages, liste courte, absence en mode « Par période ». 75 tests du module réussis.

## 2026-10-15 — Import WhatsApp, interface 3 : joindre la conversation

### Fait
- « Continuer vers l'enregistrement » (interface 2) ouvre `JoindreWhatsAppPage` : nom, nombre de messages choisis, période, participants, puis « Vous êtes : » (obligatoire, jamais deviné ; un nom confirmé lors d'un import précédent est proposé, modifiable ; groupes pris en charge). « Joindre la conversation » (double appui sans effet) prépare une `PieceJointeWhatsApp` : identifiant temporaire, source WhatsApp, titre, participants, « moi », messages originaux choisis (ordre, auteur, date réelle et brute, contenu, type).
- L'import se referme et rend la pièce jointe au chat : même conversation (cas A) ou accueil vide (cas B), texte déjà saisi conservé. Carte compacte dans la barre de saisie (logo WhatsApp, « Tony Stark », « WhatsApp · 35 messages », croix), barre dépliée, invite « Écrivez votre consigne à JARVIS… ».
- Croix : carte retirée, préparation abandonnée, texte et chat intacts ; rien n'avait été enregistré.
- Envoi : consigne non vide obligatoire ; consigne et pièce jointe dans un seul message, une seule fois. Les messages WhatsApp ne sont ni du texte, ni des commandes, ni transmis au moteur ou à l'IA : JARVIS répond honnêtement que leur analyse arrive à l'étape suivante. Conversation créée à l'envoi seulement (accueil vide) ; anciens échanges gardés (chat existant).
- Classement préparé en mémoire (source WhatsApp, titre du contact) et événement `EnvoiPieceJointe` ; contrat `DepotPiecesJointes` pour le futur stockage (sans implémentation).
- Historique : carte de la pièce jointe dans le message + « Voir les messages » (aperçu existant, « moi » à droite).
- Tests : `piece_jointe_whatsapp_test.dart` (8), `joindre_conversation_test.dart` (12 : page, parcours lecture → filtrage → joindre, accueil vide, chat existant, retrait, consigne vide, double envoi, consultation, petits écrans, grandes polices). Captures : `tool/capture_joindre_test.dart`.

### En attente
- Stockage définitif (conversations, pièces jointes, classement visible sous WhatsApp dans le menu) et analyse par MIA universel.

## 2026-10-15 — Panneau : chats reclassés sous WhatsApp

### Fait
- À l'envoi d'une consigne avec une pièce jointe WhatsApp, le chat (nouveau ou JARVIS déjà commencé) quitte la liste JARVIS et apparaît sous le logo WhatsApp, au nom du contact ou du groupe ; même identifiant, même historique, aucun doublon. « EN COURS » affiche aussi ce nom.
- `FournisseurJarvis.conversationsDe(source)` (source explicite d'après le classement, jamais d'après le titre) ; `FournisseurSourceClassee` pour WhatsApp (ouverture et suppression déléguées) ; l'épingle suit le chat (`EpinglesConversations.deplacer`).
- Tests : `classement_whatsapp_test.dart` (8 : accueil vide, chat existant, moment de l'envoi, titre, recherche, mise de côté, épingle, suppression, groupe). Suite complète : 641 réussis.

### Limite
- Classement en mémoire seulement : après redémarrage, il n'existe plus (stockage définitif à venir).

## 2026-10-15 — Stockage WhatsApp, phase 1 : base de données (préparée)

### Fait
- Audit (lecture seule) du projet Supabase « Jarvis » : tables users, conversations (15 lignes), messages (74), quota_usage ; RLS active partout ; clés composites (id, user_id) ; une migration enregistrée (vues_admin_lisibles). Schéma réel conforme à `supabase/schema.sql`.
- Migration `supabase/migrations/20261015103245_contextes_whatsapp.sql` : `conversation_contexts` (contexte joint : propriétaire, conversation, message JARVIS, source, contact, groupe, « moi », participants, période sans fuseau, empreinte de l'export) et `context_messages` (messages sélectionnés : rang, rang d'origine, auteur, contenu, type, trace de média, date locale + texte d'origine). Clés étrangères composites (propriété garantie même pour le backend), cascades (contexte → messages, conversation → contextes), message JARVIS supprimé → `message_id` null. Client : lecture et suppression de ses lignes (RLS) ; écriture par le backend seulement. Nombre de messages calculé (vue `admin.contextes_lisibles`), jamais stocké. Seul ajout sur l'existant : contrainte UNIQUE (id, user_id) sur `messages`.
- Tests : `supabase/tests/` (PostgreSQL 17.11 local jetable, simulation des rôles Supabase) : 31 vérifications réussies, migration appliquée deux fois (ré-exécutable).

### En attente
- Application sur la base distante : après validation.
- Phase 2 : endpoints du backend (user_id pris dans le JWT).

## 2026-10-15 — Stockage WhatsApp, phase 1 : terminée (appliquée sur Supabase)

### Fait
- Vérifications préalables sur le projet « Jarvis » : schéma identique à l'audit, nouvelles tables absentes, aucune migration équivalente.
- Migration `contextes_whatsapp` appliquée (version 20261015103245, transactionnelle ; fichier local renommé à cette version). `conversation_contexts` et `context_messages` existent réellement : colonnes, clés primaires, clés composites vers `conversations` et `messages`, cascades, contraintes, index, RLS, privilèges (`authenticated` : lecture et suppression ; `anon` : rien) et vue `admin.contextes_lisibles` vérifiés sur la base distante.
- Test fonctionnel distant dans une transaction annulée (rien d'enregistré) : ordre des messages, refus d'un rattachement au chat d'un autre compte, isolation entre comptes, écriture client et lecture anonyme refusées, suppression en cascade.
- Données existantes intactes : 3 utilisateurs, 15 conversations, 74 messages, 3 quotas (avant = après).
- Contrôles Supabase : aucune alerte sur les nouvelles tables.

### Reporté volontairement
- Retrait du privilège TRUNCATE de `authenticated` sur `conversations` et `messages`.
- Alertes de sécurité antérieures (fonctions SECURITY DEFINER appelables, protection des mots de passe divulgués désactivée) : non traitées dans cette phase.

### Prochaine étape
- Phase 2 : endpoints FastAPI pour enregistrer et relire les contextes (user_id pris dans le JWT).

## 2026-10-15 — Stockage WhatsApp, phase 2 : backend FastAPI

### Fait
- Routes : `POST /api/v1/conversations/contexts` (consigne + pièce jointe ; chat existant ou nouvelle conversation au nom du contact), `GET /api/v1/conversations/{id}/contexts`, `GET /api/v1/contexts/{id}`, `GET /api/v1/contexts/{id}/messages` (pagination par rang), `DELETE /api/v1/contexts/{id}` (CORS : DELETE ajouté).
- Séparation : routes (`api/v1/contexts.py`), logique (`contextes.py`, `ContextesService`), modèles (`contextes_modeles.py`), accès PostgREST (`supabase_client.py`).
- Compte pris dans le JWT ; filtres explicites par compte ; autre compte → 404. Erreurs sans détail de la base ; aucun contenu de message journalisé. Limites configurables (5 000 messages, 2 M caractères, 8 Mo, pages de 500).
- Transaction : fonction PostgreSQL `enregistrer_contexte_whatsapp` (migration `20261015130254`, préparée et testée en local, **pas encore appliquée**). Idempotence par `context_id` choisi par l'appareil, sans changement de table.
- Tests : backend 80 réussis (60 existants + 20 nouveaux, Supabase simulée) ; SQL 19 vérifications de la fonction en PostgreSQL 17.11 local (cas A/B, réessai, tout ou rien, refus, 5 000 messages) ; lectures validées sur la vraie API Supabase (lecture seule).
- Documentation : `docs/backend/CONTEXTES_WHATSAPP.md`.

### En attente
- Validation puis application de la migration de la fonction (POST renvoie 503 d'ici là).
- Phase 3 : Flutter.

## 2026-10-15 — Moteur de compréhension conversationnelle, phase 1

### Fait
- Audit : GroqCloud via le client OpenAI du chat (`openai/gpt-oss-120b`, fenêtre 131 072 tokens, mais compte limité à **8 000 tokens par minute**, mesuré dans les en-têtes) ; SSE, quotas, historique Redis/Supabase, contextes WhatsApp réutilisés tels quels. Aucune table modifiée, aucun nouveau client IA.
- Backend `app/comprehension/` : repères de la question (périodes, début/fin, évolution, tendance, mots, suivis), aperçu calculé sur tous les messages, sélection d'extraits sous budget (6 000 tokens), instructions internes (pragmatique, second degré, faits / indices / hypothèses, anti-injection, réponses courtes), cache Redis des pièces jointes.
- Route de chat : `reply_to` (consigne jamais réinsérée), `whatsapp_analysis` (absent → 409 `consentement_requis` avant tout appel IA ; `declined` → aucun contenu WhatsApp), attente de la limite de débit avec flux maintenu, nouvel essai plus petit sur 413, nouveaux codes d'erreur.
- Flutter : l'analyse suit l'enregistrement de la pièce jointe ; carte « Autoriser l'analyse / Pas maintenant » ; « Réessayer » sans doublon ; chats WhatsApp : questions envoyées au serveur (seules les commandes restent locales) ; Paramètres › Confidentialité (interrupteur, révocable).
- Tests : backend 108 réussis (28 nouveaux) ; Flutter 663 réussis (11 nouveaux), `flutter analyze` sans nouvelle remarque ; essai réel GroqCloud sur conversations fictives (humour, ironie, ton qui change, dates).
- Galaxy S10+ (APK profile, `adb reverse`) : import de l'export fictif Pepper Potts (943 messages), demande d'accord, résumé réel (159 extraits sur 943), question sur le ton, suivi « vers la fin », deux redémarrages complets avec réponses restaurées, discussion poursuivie. En base : consigne unique, réponses enregistrées (~5 200 tokens réels par question).

### Limites
- 8 000 tokens par minute : environ une question par minute sur une longue conversation (au-delà, attente automatique jusqu'à 25 s, puis message clair). Au-delà de ~150 messages, JARVIS travaille sur des extraits (annoncés).
- Le modèle utilise parfois des listes et se trompe ponctuellement sur un détail (attribution d'un « mdr ») ; ses interprétations restent des hypothèses.
- Accord enregistré par appareil (non synchronisé).
- Restauration non testée sur Web et Windows dans cette phase (pas d'essai réalisé).

### Prochaine étape
- Phase 2 : références interactives (`Preparation.references`, `REFERENCES_DANS_LE_TEXTE`).

## 2026-10-15 — Moteur de compréhension, phase 2 : attribution et références vérifiées

### Fait
- Audit de l'attribution : la chaîne de données (analyseur → `context_messages` → backend) gardait l'auteur ; les erreurs venaient du format envoyé au modèle (date seulement par jour, texte non délimité, « vous » ambigu) et de l'absence de contrôle. Format canonique : une ligne par message `[n] date heure · auteur : «texte»`.
- Références : le modèle cite `[[n]]` ; `FiltreReperes` les retire du flux SSE (formes relâchées comprises : plages, « (message 5) ») ; `verifier` contrôle existence, citation et auteur ; événement SSE `references` ; avertissement si une attribution est contredite.
- Stockage sans migration : `messages.attachments` (identifiants), relu et vérifié par `GET /api/v1/conversations/{id}/references`. « Pourquoi ? » : messages cités par les 2 dernières réponses refournis. Battement SSE pendant la réflexion du modèle (silences de 20 à 40 s observés).
- Flutter : cartes « Messages d'origine » sous la réponse ; appui → « Voir les messages » ouvert sur le message (une page de 120 autour du rang, éclairage lavande temporaire, pages voisines au défilement), retour au chat intact ; restauration après redémarrage.
- Tests : backend 139 (30 nouveaux + adaptations), Flutter 676 + 13 références, `flutter analyze` sans nouvelle remarque. Essais réels GroqCloud : « mdr » correctement attribué à Pepper, aucune fuite de repère, erreur d'attribution du modèle détectée.
- Galaxy S10+ : référence vérifiée affichée (auteur, date, texte), appui → vrai message retrouvé et éclairé, retour au chat, redémarrage → référence restaurée et toujours utilisable.

### Limites
- Le modèle peut encore mal attribuer un message : le serveur le DÉTECTE quand le sujet est explicite (nom, « tu ») et l'affiche en avertissement, sans réécrire la réponse ; « elle / il / vous » ne sont pas vérifiés.
- 8 000 tokens/minute : extraits au-delà de ~150 messages ; deux questions rapprochées attendent.
- Web et Windows non testés dans cette phase.

## 2026-10-15 — Attribution corrigée avant diffusion + phase 3 : aider à répondre et à relancer

### Fait
- **Attribution** : chaque phrase est contrôlée AVANT l'événement SSE `delta` (`app/comprehension/attribution.py`, branché sur `FiltreReperes`, qui ne coupe plus jamais au milieu d'une citation). Une citation ou un repère prêté à la mauvaise personne explicite (nom, « tu ») est remplacé par une phrase factuelle construite avec Supabase (« C'est Pepper Potts qui a écrit « mdr ». ») si l'auteur réel est unique, reformulé si plusieurs auteurs sont possibles, écarté sinon. Citations jamais modifiées, interprétations non touchées, texte enregistré = texte corrigé. Plus d'attribution fausse laissée avec un simple avertissement. Repère « ([[24]]) » retiré avec ses parenthèses.
- **Phase 3, backend** : intention comprise par GroqCloud (aucune liste de formulations ; indice `aide_reponse` pour le budget seulement) ; ligne `Situation` (dernier auteur, messages d'affilée, temps écoulé si dates fiables, réponse ou relance) ; bloc `<propositions>` retiré du flux, validé (3 à 5 tons, EXACTEMENT 3 propositions distinctes par ton, approche, appuis vérifiés) ; événement SSE `propositions` ; stockage sans migration dans `messages.attachments` ; restauration par `GET /conversations/{id}/references` ; « pourquoi la deuxième ? » avec les propositions précédentes, leurs appuis refournis et le ton affiché (`ton_propose`). Sortie +500 tokens prise sur l’entrée (même total sous 8 000 tokens/min ; les vraies réponses d’aide font ~600 tokens).
- **Phase 3, Flutter** : `PropositionsReponse`, `MessageConversation.propositions`, `PropositionsJarvis` sous la réponse (« Idées de réponse / de relance », capsules de ton, trois cartes avec approche et « Copier »). Changer de ton : aucun appel à l'IA. Aucune nouvelle page, aucune nouvelle dépendance.
- Tests : backend 169 (31 nouveaux : `test_attribution.py`, `test_propositions.py`) ; Flutter 686 + 10 nouveaux (`test/propositions_reponse_test.dart`), `flutter analyze` sans nouvelle remarque. Essai réel GroqCloud (`tests/qualite_comprehension.py`, `QUESTIONS=3,7,8,9,10`) : propositions par ton, justification de « la deuxième » appuyée sur le dernier message de Pepper.
- Galaxy S10+ (`flutter run --profile`, `adb reverse`), chat Pepper Potts existant : « Aide-moi à lui répondre » → 3 tons × 3 propositions + référence vérifiée ; changement de ton instantané sans appel serveur ; « Copier » → « Copié » ; redémarrage de l'appli → propositions restaurées depuis Supabase ; correction d'attribution réelle (« Presque. Un souci ? » rendu à Pepper, note « J'ai rectifié… »).
- Corrections issues de l'essai réel : budget (8 → 58 messages fournis : instructions estimées à 4 caractères/token, surplus de sortie ramené à 500) ; repère « (message [[24]]) » retiré en entier ; approche qui répète le nom du ton masquée ; propositions précédentes placées juste avant la question + texte exact de « la deuxième » (`rang_vise`) ; quota QUOTIDIEN GroqCloud (200 000 tokens/jour) : message honnête « Réessaie dans environ N minutes ».
- Builds Web et Windows (debug) réussis. Tests : backend 174, Flutter 686 + 10, `flutter analyze` : une remarque préexistante (accueil_page).

### Limites
- « Pourquoi la deuxième ? » : lors du dernier essai réussi, le modèle a cité une proposition inventée (signalée par la note « citation… reformulation ») ; le correctif (bloc juste avant la question, texte exact) est testé automatiquement mais PAS revérifié avec GroqCloud : quota quotidien épuisé.
- Web et Windows : compilés et testés par widgets (320 / 390 / 1366 px), pas essayés à la main avec un compte connecté.
- « elle / il / vous » non vérifiés par le correcteur d'attribution.
- Aucune migration Supabase nécessaire (stockage dans `messages.attachments`).

### Prochaine étape
- Revérifier « pourquoi la deuxième ? » avec GroqCloud quand le quota quotidien est revenu, puis phase 4 (appui long, « réponse envoyée », mémoire des réponses choisies).

## 2026-10-16 — Phase 3 finalisée + phase 4 : réponses déclarées envoyées

### Fait
- **Phase 3** : identifiant unique et stable par proposition (uuid4 ; anciennes : uuid5 déterministe, identique sur tous les appareils). « Pourquoi la deuxième ? » : référence explicite (`propositions_message_id` + ton affiché), vérifiée par le serveur (compte + chat) ; proposition visée donnée avec son identifiant, son ton, son texte exact et ses appuis, juste avant la question ; une proposition mal recopiée par le modèle est rétablie mot pour mot avant diffusion.
- **Phase 4** : appui long (~800 ms, progression discrète, annulé si relâché ou défilement, vibration légère) sur la carte d'une réponse ; bouton « Marquer envoyée » sur Web / Windows (souris, clavier). « Envoyée » (coche + « Annuler ») seulement après confirmation du serveur ; chat jamais bloqué ; double appui sans doublon (client + serveur idempotent). Rien n'est envoyé à WhatsApp.
- **Stockage sans migration** : entrée `reponse_envoyee` dans `messages.attachments` de la réponse aux propositions (id de proposition, texte, ton, contact / groupe, contexte, chat, message, compte, date, statut `declaree_envoyee` / `annulee`). Distinct des messages WhatsApp originaux (`context_messages`) et des propositions. Routes `PUT` / `DELETE …/propositions/{id}/envoyee` (JWT, 404 hors compte ou chat).
- **Synchronisation** : statut relu avec les propositions (`GET /references`), repris à l'actualisation (annulation faite sur un autre appareil comprise).
- **Mémoire** : réponses déclarées envoyées au même contact (tous les chats du compte) redonnées au modèle avant la question : continuité, pas de répétition, ton non permanent ; doublon avec un nouvel export signalé.
- Tests : backend 184 (10 nouveaux), Flutter ciblés 20 (10 nouveaux).

### Limites
- Pas de table dédiée : écriture par lecture-modification de `messages.attachments` (deux appareils qui déclarent au même instant : la dernière écriture gagne). Une table `reponses_envoyees` (clé unique compte + proposition) serait plus stricte : non créée, à décider.
- Essai GroqCloud réel non refait (quota quotidien préservé) ; campagne multiplateforme à venir.

## 2026-10-16 — Campagne complète de tests du moteur de compréhension

### Fait
- 5 exports WhatsApp FICTIFS générés par script (`tests_whatsapp/`) : sentimental 96, professionnel 248, amitié 782, famille 1 493, groupe « Projet Nova » 4 792 messages ; manifeste déterministe (33 messages de référence). Les 5 passent dans le parseur réel de l'appli (comptes, participants, périodes, dernier auteur, références à leur rang). Transférés dans `/sdcard/Download/` (visibles dans le sélecteur Android).
- Tests simulés : Flutter 705 (dont parseur réel sur les 5 ZIP, appui long dans un fil sélectionnable, ton gardé, clavier) ; backend 210 (26 nouveaux : 22 de campagne et 4 de non-régression — dernier auteur des 5 scénarios, extraits attendus, références au milieu de 4 800 messages, attributions corrigées, réactions identiques, « génie » selon l'auteur, données adverses, deux contacts, mémoire Samuel de bout en bout, double appui et annulations concurrentes, Supabase indisponible, CORS, charge).
- Galaxy S10+ (`flutter run --profile`, compte de TEST) : imports sentimental, amitié, groupe (4 792 messages : enregistrement ~3,7 s, 1ʳᵉ question ~4,7 s), filtrage, « Vous êtes », pièces jointes ; propositions (faux GroqCloud déterministe), changement de ton sans requête, appui long → « Envoyée » enregistrée dans Supabase, annulation, restauration après fermeture complète, « Pourquoi la deuxième ? » juste pour Naturel puis Amical (identifiant visé par le serveur), mémoire redonnée (« Tu lui as déjà envoyé… »), référence ouverte sur le vrai message.
- Web réel (compte de test) : chats créés sur Android retrouvés, propositions et références, statut « Envoyée » d'Android visible, « Marquer envoyée » à la souris, rechargement → statuts conservés.
- GroqCloud réel : 3 requêtes, 11 447 tokens (3 569 + 3 467 + 4 411), puis quota QUOTIDIEN épuisé (429, message « Réessaie dans environ 14 minutes » affiché) → suite en faux GroqCloud.

### Défauts corrigés
- Bloquant : bloc de propositions jamais lu avec le vrai modèle (il écrit « [Naturel] 1. … », les titres « # » étant interdits par les instructions) → exemple « Ton : … » + lecture tolérante + journal de forme.
- Bloquant : Web — déclarer « Envoyée » échouait (CORS sans PUT).
- Important : messages décisifs absents des extraits sur les longs historiques (mots fréquents = mots rares) → pondération IDF.
- Important : appui long qui sélectionnait aussi le texte du fil.
- Important : ton affiché réinitialisé quand la liste recrée la carte, alors que la session gardait l'ancien → « pourquoi la deuxième ? » pouvait viser une autre proposition.

### Non effectué / limites
- Windows réel : compilé et lancé, non testé (connexion du compte de test non faite).
- Clavier sur le Web : non validé à l'écran (couvert par un test automatique).
- Validation GroqCloud réelle des propositions après correctif, des résumés et des références : non faite (quota quotidien) ; une requête réelle courte reste à faire.
- Avec un budget d'extraits réduit (3 500), le modèle ne voyait que 9 à 30 messages : la campagne réelle doit se faire avec le budget normal (6 000).

## 2026-10-16 — Phase 5 WhatsApp : actualisation manuelle par copier-coller

### Fait
- Menu « + » : appui = import inchangé ; glissement à gauche de la ligne → « Ajouter une réponse reçue » (Web / Windows : icône au survol ou au focus, entrée discrète dans le menu d'ordinateur).
- Volet compact au nom du contact : Reçu / Envoyé, auteur vérifié (contact, participant en groupe, « vous »), plusieurs messages réordonnables, date facultative jamais inventée, extrait WhatsApp séparable sur demande, doublons signalés avant écriture, ajouts corrigeables et supprimables.
- Migration appliquée (autorisée) : `context_messages.origin` / `edited_at` / `declared_proposition_id`, fonction atomique `ajouter_messages_contexte`, messages d'export protégés par déclencheur ; 6 655 messages existants passés en `export`.
- API : `GET /contexts`, `POST /contexts/{id}/messages`, `PATCH` / `DELETE /contexts/{id}/messages/{id}` ; CORS : PATCH autorisé. Moteur : provenance dans le prompt et les références, cache vidé, aucun appel IA à l'ajout.
- Tests : SQL 70 vérifications (dont ajouts simultanés) ; backend 225 (16 nouveaux) ; Flutter 721 (16 nouveaux, `test/actualisation_whatsapp_test.dart`), `flutter analyze` sans nouvelle remarque.
- Galaxy S10+ (`flutter run --profile`, compte de test, chat Lina Moreau) : glissement réel → action révélée sans lancer l’import, volet au nom de Lina, un reçu + un envoyé enregistrés (rangs 16 et 17, provenance manuelle, sans date inventée), brouillon de la barre conservé, aucun appel IA.

### Limites
- Doublons : comparaison exacte (texte normalisé, même auteur) sur les 200 derniers messages ; une reformulation n'est pas détectée.
- Date saisie au format texte (jj/mm/aaaa hh:mm), sans calendrier.

## 2026-10-16 — Phase 5.1 WhatsApp : finition UX

### Fait
- Tons × longueurs : 3 tons adaptés + Professionnel, Court / Moyen / Long × 3 propositions (génération par lots depuis la correction finale, voir plus bas) ; ton et longueur changés sans réseau, mémorisés ; « pourquoi la deuxième ? » selon ton ET longueur.
- Un seul choix « envoyée » par ensemble, garanti par la base (migration autorisée et appliquée : deux fonctions verrouillées) ; 409 `deja_choisi`.
- Après le choix : la carte devient une bulle compacte (menu `···` : Copier, Annuler le choix) ; annulation → retour au ton et à la longueur choisis.
- Messages collés affichés en bulles dans le fil (reçu / envoyé, menu `···` Modifier / Supprimer), restaurés à leur place, hors historique des moteurs.
- Grand glissement → volet ouvert directement ; volet épuré (« Options »).
- Tests : SQL 81 ; backend 233 (8 nouveaux) ; Flutter : 11 nouveaux (`test/phase51_test.dart`) + adaptations. Essai GroqCloud réel : 1 requête (3 574 + 820 tokens), format respecté, 2 tons seulement → consignes renforcées (non revérifiées).

### Limites
- Moins d'extraits pour une demande d'aide (~45 messages au lieu de ~60), pour tenir sous 8 000 tokens/minute.
- Consignes « 4 tons » et « Long ≥ 4 phrases » non revérifiées avec le vrai modèle.

## 2026-10-16 — Phase 5.1 : correction finale de la génération des propositions

### Cause
- Une seule grande réponse GroqCloud devait écrire 4 tons × 3 longueurs × 3 propositions ; à l'essai réel, le modèle n'en a écrit qu'UNE par longueur (bloc refusé, aucune carte). Le repli « partiel » ajouté ensuite affichait des ensembles à moitié : supprimé.

### Fait
- Génération par lots (`backend/app/comprehension/generation.py`) : la réponse principale annonce les tons ; 2 tons par requête en JSON strict ; validation de chaque combinaison (3 distinctes, longueur plausible, format propre) ; seules les combinaisons manquantes sont redemandées, les valides gardées avec leurs identifiants ; 5 requêtes au plus ; 429 : attente bornée (45 s), quota quotidien : arrêt.
- Jamais d'ensemble incomplet présenté comme terminé : `statut` complet / incomplet, lots valides enregistrés ; Flutter : « Génération incomplète · Reprendre » ; reprise `POST …/propositions/completer` (même ensemble, aucun doublon, verrou Redis, quota compté).
- Tests : backend 248 (15 nouveaux, faux GroqCloud scénarisé : premier coup, une par longueur, longueur / ton manquants, format invalide, répétitions, complément ciblé, quota, attente 429, reprise, restauration, verrou, justification) ; Flutter : 5 nouveaux (état incomplet, Reprendre, double appui, échec, ton/longueur sans réseau).

### Limites
- Réponse principale + 2 lots dépassent souvent 8 000 tokens/min : le 2e lot attend (jusqu'à 45 s) avant que les propositions apparaissent.
- Moins d'extraits dans la réponse principale d'une demande d'aide (~34 au lieu de ~45).
- Essai GroqCloud réel (un seul, script `tests/qualite_comprehension.py`, QUESTIONS=8) : réponse principale 3 416 + 323 tokens (balise seule, tons Taquin / Chaleureux / Naturel), puis 2 lots (2 794 + 2 480 tokens, 6,7 s, aucun 429) → statut complet, 4 tons × 3 longueurs × 3 propositions distinctes, Long de 3 à 6 phrases.
- Observé : le ton Professionnel vouvoie même un proche ; le modèle n'a écrit aucune phrase d'introduction (la route ajoute « Voici quelques idées de réponse. »).
- Non vérifié sur le téléphone (Galaxy S10+) ni sur Web / Windows.

## 2026-10-16 — Campagne finale WhatsApp (phases 1 à 5.1)

### Corrections faites pendant la campagne
- Professionnel : garde le registre de la discussion (tutoiement / vouvoiement / neutre si incertain), contrôlé ; Court réellement court (≤ 20 mots).
- Proposition avec sauts de ligne en rafale (vu en réel : « Sam » + 4 retours) : réduits.
- Fil inversé : passer à Long faisait sortir les capsules de l'écran (vu sur le S10+) → défilement compensé ; bulle du choix parfois cachée sous la barre → rendue visible.
- Volet : saisie perdue si fermé par un appui à côté → brouillon gardé (mêmes identifiants).
- Continuité : « que penses-tu de sa dernière réponse » réduisait l'analyse à 4 messages (faux indice d'aide + plancher de 200 tokens) → indice corrigé, plancher 1 000 ; ajouts sans date marqués « après l'export » ; rappel des derniers messages avant la question.

### Validé sur appareil réel (Galaxy S10+, `flutter run --profile`, compte de test)
- Ensemble réel complet : 4 tons (Naturel, Chaleureux, Amical, Professionnel) × 3 longueurs × 3 = 36 propositions, 36 identifiants distincts (Supabase), 2 lots.
- 12 combinaisons parcourues : textes adaptés à la longueur, aucune requête réseau, capsules immobiles (après correction).
- Choix → bulle unique ; menu `···` (Copier, Annuler le choix, date) ; annulation → ton et longueur rétablis ; restauration après redémarrage.
- Petit glissement (action révélée, aucun import), grand glissement → volet direct (en partant du bord droit, Android déclenche « Retour » : geste système, pas l'appli).
- Volet compact ; doublon détecté (409) ; envoi et réception en bulles ; correction (PATCH) ; suppression (DELETE) ; provenance `manual_*` en base ; restauration sans doublon.
- Génération incomplète (faux GroqCloud, quota quotidien) : « Génération incomplète · Reprendre », coupure → reste incomplète, puis reprise complète : 1 consigne, 1 réponse, 1 ensemble, 36 propositions.

### Validé sur le Web réel (navigateur intégré, compte de test)
- Bulle du choix synchronisée depuis Android ; `···` ; annulation ; « Marquer envoyée » ; ton / longueur sans requête réseau ; capsules immobiles ; « Ajouter une réponse reçue » dans « + » ; ajout → bulle.
- Synchronisation : choix Android visible sur le Web ; annulation Web visible sur Android ; ajout Web visible sur Android (retour au premier plan) ; suppression Android absente du Web.
- Verrou entre appareils : Web 200, Android 409, une seule déclaration active en base.

### Non validé
- Windows : appli relancée avec la nouvelle version, non pilotée (aucun outil pour l'automatiser) : test manuel à faire.
- « Que penses-tu de la dernière réponse de Lina ? » : toujours faux en réel (3 essais, réponse ancrée sur le dernier message daté) ; corrections validées en tests simulés seulement (budget GroqCloud atteint).
- Copier : appui fait sur l'appareil, contenu du presse-papiers non relu (test automatisé seulement).
- Texte agrandi / petit écran / clavier ouvert sur le volet : non testés (aucun réglage système modifié).

### GroqCloud réel (openai/gpt-oss-120b)
- Génération complète (déclenchée pendant la connexion) : 6 407 + 2 782 = 9 189 tokens ; questions de continuité : 3 817, 4 496 et 4 789 ; ping de quota : 73. Total : 22 364 tokens (budget 25 000). Aucun 429.

### Tests
- Backend : 259 réussis. Flutter : 740 réussis (passe globale). Analyse : seul l’avertissement `axisAlignment` déjà présent.

## 2026-10-16 — Validation réelle : dernier message ajouté à la main

- Question « JARVIS, que penses-tu de la dernière réponse de Lina ? » (chat Lina Moreau, compte de test), GroqCloud réel `openai/gpt-oss-120b`, script hors appli, historique vide : **juste**. JARVIS commente « Bon, je te pardonne pour cette fois. » comme phrase finale et [18] → [21] dans l'ordre (ajouts « après l'export »), plus le 8 octobre.
- Prompt vérifié sans IA d'abord (`diag_preparation.py`, TEXTE=1) : conversation entière (21 messages), [21] dernier, rappel `<derniers_messages>` juste avant la question.
- Défaut trouvé : le correcteur d'attributions a remplacé à tort une phrase exacte (« Après que tu aies annoncé … — « … » [[18]] — elle a d'abord exprimé … (« … » [[19]]) … [[20]] ») : le tiret d'incise ne coupait pas la proposition, le « tu » de l'incise était pris pour le sujet de la suite. Corrigé : « — » et « – » coupent une proposition (`references._FIN_PROPOSITION`) ; 2 tests (`test_attribution.py`). Réponse réelle rejouée sans IA : phrase intacte, 4 références justes, aucune correction.
- Tokens : 3 686 + 653 = 4 339 (essai) ; pings de quota : 72 + 73 (le premier refusé en 429 : TPM occupé ailleurs à ce moment). 1 seule question posée.
- Non validé : la même question DANS l'appli (historique réel, 3 réponses fausses qui ancrent le modèle) ; le conteneur `jarvis-api` doit être reconstruit pour avoir la correction du tiret.
- Tests backend : 261 réussis.

## 2026-10-17 — Correction finale WhatsApp : message visé et fluidité

### Cause
- Le message « visé » (« sa dernière réponse ») était laissé au modèle : il retenait le dernier message DATÉ de l'export plutôt que l'ajout manuel sans date, et l'historique contenait ses anciennes réponses fausses, qui l'ancraient (3 essais faux dans l'appli).
- Pendant la préparation des propositions (lots), la bulle n'affichait plus rien de vivant : impression d'appli figée.

### Fait
- `backend/app/comprehension/ciblage.py` : ciblage déterministe AVANT l'appel IA (conversation, participant — groupe compris —, reçu, envoyé, ajout manuel ; suivi par la personne de la question précédente ; clarification si plusieurs contacts ou groupe sans nom). Message et voisins forcés dans les extraits, bloc `<message_vise>` (identifiant, auteur, provenance, [[n]]) juste avant la question, anciennes questions/réponses « dernier message » retirées de l'historique.
- SSE `preparation` + trois points animés (`PreparationPropositions`) sous le texte jusqu'aux propositions ; battements pendant les lots ; durées journalisées (préparation, premier fragment, réponse principale, chaque lot, enregistrement Supabase).
- Tests : `test_ciblage.py` (9, dont route : le prompt porte l'identifiant visé AVANT l'appel IA), événement `preparation` (backend), session + animation (Flutter, 3).

### Preuve et essai réel
- Sans IA : sur l'ensemble Lina (101 messages + 5 ajouts), la cible est `ajout-101` « Bon, je te pardonne pour cette fois. » ; groupe Projet Nova : « dernière réponse de Samuel » = son message même si Nora a parlé après ; 4 795 messages sous 2 500 tokens : message visé toujours fourni.
- GroqCloud réel (1 requête, `tests/essai_ciblage_reel.py`, historique avec 3 réponses fausses) : JUSTE — commente « Bon, je te pardonne pour cette fois. », 4 références vérifiées (ajouts manuels) ; 6 168 + 360 tokens, 1,6 s.
- Essai DANS l'appli non fait : le compte de test a été vidé (6 chats supprimés depuis l'appli native à 21 h 48 et 22 h 08 UTC) et le téléphone était en cours d'utilisation.

### Mesures
- Préparation des extraits : 18 ms (Lina) ; enregistrement Supabase : journalisé (`Durée : enregistrement Supabase`).
- Goulot : GroqCloud (réponse principale 1,6 à 15 s selon le raisonnement ; lots ~3,3 s chacun, en série). Lots en parallèle : ~3 s gagnés mais double la pression sur 8 000 tokens/min → reporté à la nouvelle API.
- Flutter : traitement des propositions négligeable ; l'impression de blocage venait de l'absence d'indicateur.

### Tests
- Backend : 269 réussis. Flutter : 743 réussis (passe globale). Analyse : seul l'avertissement `axisAlignment` déjà présent.


## 2026-10-17 — JARVIS Touch, phase 1 (bulle flottante Android)

### Fait
- Paramètres › Général : `PanneauGeneral` (interrupteur JARVIS Touch, Android seulement ; Langue / Version gardées). Désactivé par défaut, choix enregistré (`jarvis.touch_active`).
- `services/jarvis_touch_service.dart` : état réel (désactivé / attente d'autorisation / démarrage / actif), jamais « actif » sans confirmation de la bulle ; autorisation demandée puis vérifiée au retour dans JARVIS (refus → explication, interrupteur coupé) ; resynchronisé à chaque retour au premier plan ; bulle rallumée au lancement si elle était activée (`AccueilPage`).
- Android (`kotlin/.../touch/`) : `PontJarvisTouch` (canal `jarvis/touch`), `ServiceJarvisTouch` (service au premier plan `specialUse`, notification discrète, une seule bulle, pas de redémarrage automatique), `FenetresJarvisTouch` (superposition, glisser, rangement animé au bord le plus proche, zones système et encoche respectées, position mémorisée, rotation, estompage au repos), `BulleJarvis` (rendu simplifié derrière l'interface `RenduBulle`, remplaçable par PIM), `MenuJarvisTouch` (Discuter / Vocal / Analyser l'écran / Importer une conversation → « Disponible prochainement » ; fermeture : ✕, toucher extérieur ou bulle).
- Prototype `jarvis--main` : principe seulement (aucune licence fournie → code réécrit).

### Tests
- `test/jarvis_touch_test.dart` (7) + Paramètres, accueil, menu latéral : réussis. Analyse : seul l'avertissement `axisAlignment` déjà présent. APK debug compilé et installé sur le Galaxy S10+ (Android 12) ; section visible.

### Prochaine étape
- Valider à la main sur le téléphone (autorisation, déplacement, menu, désactivation), puis phase 2 : brancher les entrées du menu.

## 2026-10-17 — JARVIS Touch, phase 2 (mini-chat sur la conversation unique)

### Architecture
- Interface NATIVE légère (Kotlin) + LA `ConversationSession` de l'accueil comme seule source de vérité. Écarté : second FlutterEngine (isolat séparé = deuxième conversation, mémoire doublée).
- Le moteur Flutter principal appartient au processus (`MoteurJarvis`, `FlutterEngineCache`, `provideFlutterEngine`) : il survit à la destruction de l'activité tant que la bulle est active ; libéré comme avant (activité quittée + bulle inactive). Jamais de second moteur.
- Canal `jarvis/touch_chat` lié au moteur (`CanalMiniChat`) ↔ `PasserelleMiniChat` (`lib/services/jarvis_touch_chat.dart`, attachée par `AccueilPage`).

### Fait
- « Discuter » ouvre `ChatJarvisTouch` (fenêtre en haut de l'écran, focalisable ; toucher ailleurs = focus rendu ; retour = réduire ; clavier : fenêtre raccourcie au-dessus) ; en-tête (titre, ouvrir dans JARVIS, réduire), liste recyclée, saisie 1-4 lignes, envoi désactivé si vide.
- Envoi = `ConversationSession.envoyer` (même file, même IA, même enregistrement) ; `idEnvoi` : un double envoi ne part qu'une fois. Instantané seulement quand l'affiché change (signature des messages), fragments du message en réception regroupés (≤ 1 / 50 ms, texte complet, une seule bulle mise à jour). Réduit : aucun écouteur. Réponse lue en direct → affichée entière dans l'accueil (pas d'écriture rejouée).
- 40 derniers messages, puis +40 en remontant (`chargerPlusAnciens` existant si besoin).
- JARVIS revenu au premier plan : mini-chat réduit automatiquement. Désactivation : fenêtres retirées comme en phase 1.
- Point de restauration : branche `restauration/avant-touch-phase2` (travail non commité inclus).

### Tests
- `test/jarvis_touch_chat_test.dart` (4) + `jarvis_touch_test.dart` : réussis. Analyse : seul `axisAlignment` (préexistant).
- Galaxy S10+ (profile) : menu → Discuter ; conversation de l'accueil affichée (mêmes messages, même ordre) ; envoi depuis le mini-chat visible dans JARVIS et inversement ; aucun doublon ; activité détruite (retour) → mini-chat toujours fonctionnel, JARVIS relancé sur la même conversation sans redémarrer ; réduction automatique au retour dans JARVIS.
- Mesures : ouverture du mini-chat 130-267 ms ; 40 ouvertures/fermetures → après GC 9 vues, 2 ViewRootImpl, PSS identique (≈ 338 Mo, toute l'app) : aucune fuite.
- MIA réel (compte connecté, `--dart-define=JARVIS_API_URL=http://127.0.0.1:8000`) : question dans JARVIS → réponse ; écran d'accueil Android → bulle → Discuter → même fil → question longue → réponse en streaming dans le mini-chat → réduction → JARVIS : 4 messages, même ordre, réponse entière (pas d'écriture rejouée), aucun doublon ; serveur : exactement 2 `POST /chat/stream` pour 2 questions.
- Latence fragment (arrivée dans Dart → affiché, regroupement inclus) : moyenne 64-67 ms, max 78-84 ms (36 et 16 fragments). Fenêtres natives pendant le streaming : 1 367 images, 1,1 % saccadées, médiane 7 ms, 95ᵉ centile 15 ms.
- Corrigé pendant les essais : premier toucher sur le champ (focus + clavier aussitôt) ; mot « en composition » du clavier Samsung oublié à l'envoi (`restartInput`), sinon message tronqué.
- Cause du « Connectez-vous » vu en cours d'essai : téléphone sans réseau (Supabase injoignable) + lancement sans `JARVIS_API_URL` ; rien à voir avec le mini-chat.
- Tests Dart : 61 réussis (touch, touch_chat, conversation_ia, accueil).
- Reste à valider à la main : coupure réseau PENDANT un streaming, rotation avec le mini-chat ouvert, historique très long (> 40 messages, remontée), passage réel par WhatsApp.

## 2026-10-17 — MIA universel, phase 1 (couche multi-fournisseurs `backend/app/llm/`)

### Fait
- Point de restauration : tag `sauvegarde-avant-mia-phase1` (sur `db498e5`, arbre propre ; `comparaison_points_pim.png` non suivi, laissé tel quel).
- `app/llm/base.py` : contrat `FournisseurLLM` (`flux` → `Texte`… puis une `Fin(raison, usage, modele)` ; `json` → `ReponseJSON`), `Usage` (entrée, sortie, cache lu / écrit, estimé), `RaisonArret` (fin, longueur, refus, outil, autre), erreurs `LimiteDebit(attente)`, `RequeteTropGrande`, `Refus`, `ErreurFournisseur` avec les MÊMES codes / messages que l'événement SSE `error` actuel (`evenement()`), `apres_texte` pour une coupure. Place réservée à ODO (`DefinitionOutil`, `AppelOutil`, `RaisonArret.OUTIL`) : `outils` non vide → `NotImplementedError`.
- `app/llm/groq.py` : `FournisseurGroq` (SDK `AsyncOpenAI`), copie fidèle du comportement de production (point d'accès `gsk_` → Groq, flux + usage final, JSON `json_object` avec repli mémorisé, `reasoning_effort` pour gpt-oss, « low » par défaut en JSON, quotas quotidiens / crédit sans attente, délais `retry-after` / `x-ratelimit-*`).
- `app/llm/anthropic.py` : `FournisseurAnthropic` (SDK officiel `anthropic` 1.15, `AsyncAnthropic`, `max_retries=0`). Conversion : `system` du début → champ `system` ; rappels système suivants (moteur WhatsApp) → bloc `<consignes_systeme>` en tête du `user` qui suit, jamais dans `system` (citations importées non fiables) : note fixe « consignes du serveur, citations = données », balise neutralisée (‹…›) dans tout autre texte (citation, saisie, réponse) ; vides ignorés, rôles identiques fusionnés, `assistant` en tête retiré, fin obligatoire par `user`. Seuls les `text_delta` sont diffusés (réflexion jamais exposée) ; `thinking` non envoyé ; effort `output_config.effort` ramené aux capacités du modèle (rien pour Sonnet / Haiku 4.5 et plus anciens) ; JSON par `output_config.format` (schéma) ou texte relu, toujours en flux ; refus → `Fin.raison=REFUS` (catégorie) en flux, `Refus` en JSON ; 429 / 529 → `LimiteDebit`, 413 ou « prompt is too long » → `RequeteTropGrande`, crédit, clé, modèle. Aucun repli automatique (ni modèle, ni fournisseur).
- `app/llm/selection.py` : `creer(nom)`, `fournisseur(nom)` (une instance par fournisseur), `configures()`, `fermer_tous()`. `LLM_PROVIDER` (anthropic par défaut) ; inconnu → `FournisseurInconnu` ; incomplet → `FournisseurNonConfigure` (nom de la variable, jamais sa valeur). Extensible : une fabrique dans `FABRIQUES`.
- Configuration : `LLM_PROVIDER`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` (aucun modèle imposé par le code), `ANTHROPIC_EFFORT` dans `config.py` et `.env.example` ; variables `OPENAI_*` (GroqCloud) inchangées. `requirements.txt` : `anthropic>=1.15,<2`.

### Inchangé (vérifié par `git diff`)
- `api/v1/chat.py`, `api/v1/contexts.py`, toutes les routes, le contrat SSE, les quotas, Supabase, Flutter : aucune ligne modifiée. Les routes utilisent toujours `chat.get_openai` (GroqCloud) ; rien en production n'importe `app.llm`.

### Tests
- Nouveaux (100) : `test_llm_contrat.py` (mêmes tests pour Claude et GroqCloud : flux, réflexion masquée, plafond, refus, coupure, 429, 413 / 401 / 404 / 500, JSON valide / balisé / illisible / coupé, outils, conversations invalides), `test_llm_anthropic.py` (dont enveloppe impossible à fermer ou imiter), `test_llm_groq.py`, `test_llm_selection.py`. Vrais SDK, transport HTTP simulé (`tests/faux_llm.py`) : aucun appel réseau, aucune clé réelle.
- Contrôle : une fuite volontaire de `thinking_delta` (sur une copie jetable, annulée) est bien détectée (test en échec).
- SDK : les 100 tests MIA réussissent avec `anthropic` 1.0.0, 1.5.0, 1.10.0, 1.12.0, 1.14.0 et 1.15.0 ; contrainte gardée à `>=1.15,<2` (version de la suite complète).
- Suite complète dans un conteneur jetable (image `backend-api` + `requirements-dev.txt` + `anthropic`, dépôt entier monté) : **369 réussis** (269 avant + 100), 0 échec, aucun avertissement sur les nouveaux tests.
- Remarque : sans `tests_whatsapp/` monté, 8 tests de `test_ciblage.py` échouent (`KeyError` sur les ZIP de la campagne) ; c'est l'environnement, pas le code.

### Limites
- Pas de test réel contre l'API Claude (clé non utilisée, comme demandé) : formats vérifiés par le SDK officiel sur des flux simulés.
- L'image `backend-api` en service n'a pas encore `anthropic` (à reconstruire en phase 2 ; inutile tant que rien ne l'importe).
- Copie temporaire de la logique d'erreurs Groq (`describe_llm_error`, `retry_delay`) dans `groq.py`, à retirer de `chat.py` au raccordement.
- Prompt caching Claude non activé (décision de coût à prendre).

### Prochaine étape (phase 2)
- Reconstruire l'image ; brancher `chat_stream`, `appel_lot` et `contexts.completer` sur `selection.fournisseur()` ; plafonds de sortie et budget de compréhension propres à Claude (réflexion comptée dans la sortie) ; schéma JSON des lots ; refus → `incident` ; `messages.model` = modèle servi ; sélection manuelle de Groq réservée (environnement de test + compte administrateur) ; console ; tests de route avec les deux fournisseurs ; essais réels.
- Constat préexistant (hors phase 1, code de compréhension non modifié) : dans `ciblage.bloc`, le texte du message visé est cité via `texte_affiche` sans `neutraliser` ni remplacement des guillemets (contrairement à `extraits.ligne`), et `message_vise` n'est pas dans `extraits._BALISES` ; à corriger en phase 2 (concerne aussi GroqCloud).

## 2026-10-17 — MIA universel, phase 2 (raccordement au backend) — tests automatiques validés, essais réels en attente

### Fait
- Point de restauration : tag Git `sauvegarde-avant-mia-phase2` (sur `ddf844a`) ; image de production conservée sous `backend-api:avant-mia` (`b2113aa77e17`).
- `api/v1/chat.py` : `get_openai`, `describe_llm_error` propre à Groq, `retry_delay`, `_secondes` retirés ; `get_fournisseur` (résolu AVANT le quota) ; `chat_stream` consomme `llm.flux` (Texte / Fin), attente sur `LimiteDebit` et réduction sur `RequeteTropGrande` seulement si rien n'a été diffusé, `Fin.raison` ≠ fin → `error` `llm_refus` / `llm_incomplet` (jamais `done`), plafond + `LLM_REFLEXION_MARGE_TOKENS` si la réflexion compte dans la sortie, budget WhatsApp propre au fournisseur (`budget_comprehension`), `messages.model` = modèle servi, tokens = entrée + cache / sortie (réflexion comprise), en-tête de réponse `X-Jarvis-Fournisseur`. `appel_lot` → `llm.json(schema=…, effort=LLM_EFFORT_PROPOSITIONS)`. `describe_llm_error` = `ErreurLLM.evenement()`.
- `api/v1/contexts.py` (« Reprendre ») : même fournisseur, résolu avant le quota.
- `comprehension/generation.py` : `schema_lot(e, tons)` (schéma strict : `additionalProperties: false`, seules les longueurs manquantes exigées, aucune borne non prise en charge) ; `Appel` reçoit le schéma.
- Sécurité : `extraits.citer` (balises neutralisées, une ligne, guillemets remplacés) utilisé par `extraits.ligne` ET `ciblage.bloc` (point préexistant corrigé) ; `message_vise` et `consignes_systeme` ajoutés aux balises neutralisées.
- Choix manuel : en-tête `X-Jarvis-Fournisseur` accepté seulement hors production + `LLM_SELECTION_MANUELLE` + compte dans `LLM_ADMINS` ; sinon 403 sans quota ; inconnu 400 ; non configuré 503 `llm_config` (aucun repli vers Groq). `selection.choix_manuel_possible`.
- Configuration : `ANTHROPIC_COMPREHENSION_BUDGET_TOKENS` (20 000), `LLM_REFLEXION_MARGE_TOKENS` (8 000), `LLM_EFFORT_PROPOSITIONS` (low), `ENVIRONNEMENT` (production par défaut), `LLM_SELECTION_MANUELLE`, `LLM_ADMINS` ; `OPENAI_API_KEY` facultative. `.env` privé : lignes MIA ajoutées (`LLM_PROVIDER`, `ANTHROPIC_MODEL=claude-opus-5-5`, `ANTHROPIC_API_KEY` VIDE, à remplir par l'utilisateur).
- `main.py` : fournisseur actif annoncé au démarrage (ou erreur claire), clients fermés à l'arrêt. Console : état du fournisseur (nom, modèle, jamais de clé) et sélecteur visible seulement si le choix manuel est ouvert.
- Adaptateur GroqCloud : lecture tolérante des réponses partielles (comme l'ancienne route). `base.reponse_complete` pour les scripts.
- Scripts d'essai : `essai_ciblage_reel.py`, `qualite_comprehension.py` (`FOURNISSEUR=anthropic|groq`), `quota_groq.py` (client Groq direct), nouveau `scripts/essai_mia.py` (scénarios réels 1-7, mot de passe au clavier, conversation WhatsApp FICTIVE).
- Doc : `docs/backend/MIA_UNIVERSEL.md` (architecture, garanties, configuration, tests, déploiement et retour arrière).
- Flutter : aucune modification (tout `error` est déjà traité comme une réponse interrompue).

### Tests (étape A, sans API réelle)
- Tests existants adaptés (simulation `get_fournisseur` au lieu de `get_openai`, erreurs via l'adaptateur) ; nouveaux : `test_mia_chat.py` (19 : SSE, réflexion masquée, requête Claude réelle du SDK, modèle et tokens enregistrés, historique, refus / plafond / coupure, 429 + 529 attendus sans doublon, erreurs, choix protégé, non configuré, aucun basculement), `test_mia_whatsapp.py` (5 : schéma, propositions complètes avec Claude, « Reprendre » + « Pourquoi la deuxième ? », injection depuis un message importé).
- **393 réussis**, 0 échec : conteneur jetable (image `backend-api`) ET image de test `backend-api:mia-test` (`anthropic` 1.15.0).
- SDK 1.15.0 : `OutputConfigParam` (`effort` low…max, `format` json_schema) et `Message.stop_details` présents ; corps des requêtes vérifié tel qu'émis par le SDK.

### Étape B
- Image `backend-api:mia-test` construite ; instance isolée `jarvis-api-mia` (port 8001, Redis base 1, `ENVIRONNEMENT=development`) : démarre, `/health/ready` ok, signale « anthropic non configuré » (clé absente). `jarvis-api` (port 8000) jamais arrêté ni modifié.

### Étape C — essais réels (autorisés, instance de test port 8001, `claude-opus-5-5`)
- Clé collée par l'utilisateur dans `backend/.env` (vérifiée sans affichage : 1 ligne, préfixe `sk-ant-`) ; mot de passe saisi par l'utilisateur dans son terminal (`scripts/essai_mia.py`).
- 1-2. Conversation + streaming : `meta → delta (23) → done`, premier fragment 4,0-5,6 s (réflexion), réponse 5-7 s ; suite de conversation relue (historique) ; usage `342 + 267` tokens.
- 6. `messages.model` = `claude-opus-5-5`.
- 3. WhatsApp FICTIF (Lina Moreau, 97 messages, conversation complète fournie, ~5 300 tokens) : réponse terminée en 32,7 s (texte 3 s, premier fragment 3,5 s), 1 référence vérifiée ; lot JSON par schéma accepté par l'API réelle (`output_config.format` + `effort`), 15 propositions gardées / 3 refusées par les règles de longueur, 25 s pour 2 tons ; instance volontairement limitée à 1 lot → statut `incomplet`.
- 4. « Reprendre » : premier essai 404 (le script appelait avant l'enregistrement en tâche de fond, 100 ms plus tard ; sans effet dans l'appli, script corrigé) ; second essai : HTTP 200, `complet`, 4 tons, 3 lots (23 s, 10 s, 8 s), 44 s au total.
- 5. Erreurs : en-tête de fournisseur non autorisé → 403 `fournisseur_interdit` ; conversation inconnue → 404.
- 7. Comparaison (compte dans `LLM_ADMINS`, instance de test seulement) : Claude 1,8 s / 2,6 s, 320 tokens ; GroqCloud (`openai/gpt-oss-120b`) 1,4 s / 1,5 s, 271 tokens ; réponses équivalentes.
- Bilan : 1er passage 12/13 (seul échec : la course du script sur « Reprendre »), 2e passage 2/2 ; les 7 scénarios sont validés. Coût estimé < 1 $. Données de test : 3 conversations (dont 1 WhatsApp fictive) dans le compte de l'utilisateur, supprimables depuis l'appli.
- Observation : les lots de propositions avec Opus 5.5 prennent 8-25 s chacun (un ensemble complet de 4 tons ≈ 50 s après le texte) ; piste à mesurer si gênant : un modèle plus rapide pour les lots (décision de l'utilisateur).

### Étape D — déploiement (accord de l'utilisateur, 2026-10-17 11:52 UTC)
- `docker compose build api` puis `docker compose up -d api` : `jarvis-api` sur l'image `1e0a52b54b6f` (ancienne : `b2113aa77e17`, gardée sous `backend-api:avant-mia`). Redis non recréé.
- Contrôles : santé `healthy`, `/health/ready` ok (Redis, Supabase), journal « Fournisseur IA : anthropic », `/console/config` : `anthropic` / `claude-opus-5-5` configuré, choix manuel FERMÉ (`ENVIRONNEMENT` absent = production) ; en-tête `X-Jarvis-Fournisseur` sans compte → 401 ; préflight CORS Flutter Web (`localhost:3000`) → 200.
- Instance de test `jarvis-api-mia` arrêtée (elle avait le choix manuel ouvert). Image `backend-api:mia-test` conservée.
- Retour arrière : `LLM_PROVIDER=groq` + `docker compose up -d api`, ou `docker tag backend-api:avant-mia backend-api:latest` + `docker compose up -d --no-build api` (voir `docs/backend/MIA_UNIVERSEL.md`).

### Reste
- Essai depuis l'application Flutter (écrit, vocal, WhatsApp) sur la production ; commit de la phase 2 (rien n'est commité).

## 2026-10-17 — Validation de MIA universel dans les applis (Android, Windows, Web)

### Méthode (économie de tokens)
- Instance de test `jarvis-api-mia` (port 8001, image de la phase 2, Redis base 1) à plafonds réduits : `CHAT_MAX_OUTPUT_TOKENS=300`, `LLM_REFLEXION_MARGE_TOKENS=700`, `ANTHROPIC_EFFORT=low` (pire cas ≈ 0,022 $ par appel) ; modèle inchangé (`claude-opus-5-5`). Applis : `flutter run --dart-define=JARVIS_API_URL=http://127.0.0.1:8001` ; S10+ : `adb reverse tcp:8001 tcp:8001` ; Web : port 3000 (CORS ok).
- Budget : `backend/scripts/budget_mia.py` (lecture seule : tokens enregistrés dans `messages`, coût majorant, arrêt si la prochaine requête peut dépasser 0,20 $ ; ne voit pas les lots de « Reprendre »).
- Gratuit d'abord : 150 tests Flutter (chat IA, écriture progressive, vocal, JARVIS Touch, synchronisation, WhatsApp) réussis ; WhatsApp, propositions, « Reprendre », erreurs : résultats réels du matin réutilisés (aucune nouvelle analyse).

### Résultats réels (4 appels, une seule conversation partagée)
| # | Plateforme | Tokens (entrée + sortie) | Coût | Premier fragment |
|---|---|---|---|---|
| 1 | S10+ écrit | 200 + 83 | 0,0025 $ | 2,9 s |
| 2 | S10+ vocal | 293 + 37 | 0,0019 $ | 2,5 s |
| 3 | Windows écrit | 338 + 90 | 0,0032 $ | 3,7 s |
| 4 | Web (Chrome) écrit | 440 + 117 | 0,0041 $ | 3,7 s |
- Total : **0,0116 $** / 0,20 $.
- S10+ : authentification, écrit (points animés puis écriture progressive), vocal (transcription, réponse de Claude, PIM), retour à l'écrit (échange vocal dans le fil, micro coupé), JARVIS Touch (menu, mini-chat = même conversation, 4 messages, sans envoi).
- Windows et Web : conversation synchronisée (messages du téléphone visibles), questions dépendantes de l'historique correctement comprises (« comme le ZIP », « Lequel des deux »), affichage progressif ; Web : préflight CORS + POST ok.
- Supabase : 1 conversation, 8 messages pour 4 échanges (aucun doublon), `model = claude-opus-5-5` sur les 4 réponses. Quotas JARVIS : compteurs Redis à jour (15 requêtes, 31 086 tokens ce jour). Journal de l'instance : 0 erreur.
- Non testés en réel (volontairement, coût) : nouvelle analyse WhatsApp, interruption de flux, envoi depuis le mini-chat, phrase vocale sur Windows / Web (couverts par les tests automatiques ou les essais du matin).
- Rappel : la production (port 8000) est sur MIA / Claude depuis 11:52 UTC (déploiement autorisé à l'étape D) ; rien n'est commité pour cette validation (`scripts/budget_mia.py` et cette entrée).

## 2026-10-17 — Clôture de MIA universel

### Coût réel de la campagne (lecture Supabase, aucun appel)
- 9 réponses de Claude enregistrées : 13 767 tokens d'entrée + 3 239 de sortie = **0,120 $** (essais backend du matin 0,108 $ ; applis 0,012 $).
- Lots de « Reprendre » (non enregistrés comme messages) : ≈ 11 300 tokens d'après `quota_usage` (31 086 tokens ce jour − réponses Claude − 2 799 tokens GroqCloud) ; coût estimé 0,05-0,23 $, probablement ≈ 0,11 $.
- **Total estimé ≈ 0,23 $** (fourchette 0,17-0,35 $) ; la console Anthropic fait foi. `scripts/budget_mia.py` est conservé (suivi des prochaines campagnes, ODO).

### Remise en état (gratuit)
- Sessions `flutter run` de test arrêtées (Android, Windows, Chrome) ; aucune appli de test ne tourne.
- APK Android réinstallée vers le backend habituel (`JARVIS_API_URL=http://127.0.0.1:8000`, configuration USB documentée) ; redirection ADB : 8001 retirée, `tcp:8000` remise. Windows et Web visent `localhost:8000` par défaut (aucune définition nécessaire).
- Instance de test `jarvis-api-mia` (8001) arrêtée ; `jarvis-api` (production, image `1e0a52b54b6f`, Claude) et `jarvis-redis` inchangés. Images gardées : `backend-api:avant-mia` (retour arrière), `backend-api:mia-test`.

### Limitations restantes
- Le téléphone n'atteint le backend local que par USB (`adb reverse`) ou par l'adresse du PC sur le réseau : vrai hébergement à venir (`deploy/oracle/`).
- Durée des propositions WhatsApp avec Opus 5.5 : ≈ 8-25 s par lot (≈ 50 s pour un ensemble complet) ; mesure d'un modèle plus rapide pour les lots = décision à prendre.
- `budget_mia.py` ne voit pas les lots de « Reprendre » (seulement les réponses enregistrées).
- Base Redis 1 : quelques clés de test (contexte court, quotas) qui expirent seules ; non supprimées.
- Hors MIA, préexistant : `SourceConversation.jarvis` référence `assets/logos/jarvis.png`, absent du dépôt (404 vu sur le Web).

### Prochaine étape
- ODO (orchestrateur d'outils) sur le contrat `FournisseurLLM` (place réservée : `DefinitionOutil`, `AppelOutil`, `RaisonArret.OUTIL`).

## 2026-10-17 — Abonnements Free & Pro, phase 1 (configuration Supabase)

### Fait
- Point de restauration : tag `sauvegarde-avant-abonnements-phase1` (sur `6aa7d1a`).
- Vérifié avant : aucune table d'offres existante (seulement `auth.sessions`, interne) ; `plan_tier` = free, pro ; droits par défaut de Supabase = TOUS les droits à anon / authenticated / service_role sur toute nouvelle table du schéma public.
- Migration `supabase/migrations/20261017130000_plan_config.sql` (additive, ré-exécutable), **appliquée** sur « Jarvis » : table `public.plan_config` (clé `plan` = `plan_tier`, `llm_provider` ∈ {anthropic, groq}, `llm_model`, limites par jour et par session, `session_duration_minutes`, `critical_threshold_percent`, `updated_at` automatique), contraintes de cohérence, commentaires de colonnes (visibles dans l'éditeur), valeurs initiales en `ON CONFLICT DO NOTHING` (jamais d'écrasement d'une valeur modifiée à la main).
- Valeurs enregistrées : Free = groq / openai/gpt-oss-120b, 100 msg et 50 000 tokens par jour, sessions de 300 min, 25 msg et 15 000 tokens par session, seuil 80 % ; Pro = anthropic / claude-opus-5-5, 200 et 100 000 par jour, 300 min, 50 et 30 000 par session, 80 %.
- Sécurité : tous les droits retirés à anon / authenticated (TRUNCATE compris) ET à service_role, qui garde la lecture seule ; RLS active sans politique ; modification par l'administrateur du tableau de bord seulement. `users.plan` toujours non modifiable par l'utilisateur.
- Doc : `docs/backend/ABONNEMENTS.md` (colonnes, procédure de modification, sécurité, règle de priorité offre / limites personnelles, conception des sessions persistantes, prêt pour la phase 2) ; note dans `supabase/schema.sql` ; CLAUDE.md.

### Tests (aucun appel facturable)
- PostgreSQL 17 local jetable (`supabase/tests/lancer_tests.sh`, migration jouée deux fois) : **105 réussis, 0 échec**, dont 24 nouveaux (`50_plan_config_test.sql` : valeurs, refus anon / authenticated en lecture, écriture, ajout, suppression, TRUNCATE, changement de plan ou de limites par l'utilisateur ; backend en lecture seule ; modification par l'administrateur + `updated_at` ; contraintes : seuil, fournisseur, modèle vide, durée nulle, session > jour, négatif, cellule vide, doublon, abonnement inconnu).
- Correction trouvée par les tests : le `service_role` pouvait modifier les offres (droits par défaut) → retiré avant l'application.
- Base réelle : valeurs exactes ; droits anon / authenticated = aucun, service_role = lecture ; RLS active ; modification par l'administrateur acceptée et refus pour `authenticated` (42501), testés dans une transaction ANNULÉE (valeurs restées 100 / 300) ; données existantes identiques avant / après (1 compte pro 60 / 100 000, 4 lignes `quota_usage` 99 messages / 135 209 tokens, 4 conversations, 12 messages) ; avis de sécurité : seulement « RLS sans politique » (voulu) pour `plan_config`.
- Production : `jarvis-api` inchangé (même image, démarré à 11:52, santé ok) ; aucun code ne lit `plan_config` ; fournisseur IA et quotas inchangés.

### Points ouverts (phase 2)
- Règle de priorité offre / limites personnelles : rendre la dérogation explicite (les colonnes `users.daily_*` ont des valeurs par défaut et `NULL` = illimité) — transformation de données à valider ; le compte Pro (60 / 100 000) resterait une dérogation plus basse que l'offre Pro.
- Sessions : table `usage_sessions` + compteur Redis (conception dans la doc).
- Avis Supabase préexistants (hors chantier) : `handle_new_user`, `touch_conversation` exécutables par l'API ; protection des mots de passe divulgués désactivée.

## 2026-10-17 — Abonnements Free & Pro, phase 2 (backend, sessions, routage MIA)

### Fait
- Point de restauration : tag `sauvegarde-avant-abonnements-phase2` (sur `fdeb10e`).
- Migration `supabase/migrations/20261017160000_abonnements_sessions.sql` (additive, ré-exécutable), **appliquée** sur « Jarvis » : `users.limits_override` (exception explicite, `false` par défaut), fonction `limites_effectives` (seul calcul : offre `plan_config`, sauf exception ; `NULL` = illimité gardé pour les exceptions), `get_my_quota` sur ces limites (même signature), `usage_sessions` + `session_active` / `ouvrir_session` (verrou par compte) / `increment_session_usage`, `llm_usage` + `increment_llm_usage` (suivi par fournisseur et modèle), vues `admin.limites_appliquees` et `admin.consommation_llm`.
- Compte Pro existant : suit désormais l'offre Pro (**200 msg / 100 000 tokens par jour**, session 300 min, 50 / 30 000) ; anciennes valeurs 60 / 100 000 conservées mais ignorées ; aucun autre changement de données.
- Backend : `supabase_client` (limites effectives par RPC, sessions, suivi) ; `quota.py` réécrit (cache JSON 30 s, script Lua unique jour + session atomique, réhydratation, ouverture de session après contrôle du jour, `release` sur les deux, `record_usage` unique avec entrée / sortie / fournisseur, mode dégradé, 429 typé avec `resets_in` / `resets_at`, `budget_depasse`) ; `chat.get_fournisseur` asynchrone : routage par l'offre si `ABONNEMENTS_ROUTAGE=true` (désactivé par défaut), en-tête réservé aux tests, 503 sans repli ; refus avant l'appel facturable si l'entrée estimée dépasse le reste ; `contexts.completer` comptabilisé avec le fournisseur ; `/me/quota` (session, offre, seuil, `resets_at`, `fournisseur_actif`) ; en-têtes `X-Quota-Session-*` ; `selection.fournisseur(nom, settings, modele)` ; `scripts/set_plan.py` (héritage par défaut, `--messages / --tokens / --illimite` = exception).
- Configuration : `ABONNEMENTS_ROUTAGE=false`, `QUOTA_LIMITS_CACHE_TTL=30` (défaut, `.env.example`, et `.env` privé : 300 → 30).
- Doc : `docs/backend/ABONNEMENTS.md` (réécrite : tables, procédures Supabase, quotas, sessions, routage, `/me/quota`, protection financière, activation / retour arrière, limitations) ; `supabase/schema.sql` ; CLAUDE.md.

### Tests (aucun appel API réel)
- SQL (PostgreSQL local jetable) : **132 réussis**, 0 échec (27 nouveaux, `60_abonnements_sessions_test.sql` : héritage, modification d'offre, exception activée / désactivée, ouverture / reprise / renouvellement de session, durée pour les nouvelles sessions, consommation par compte, suivi, vues, droits).
- Backend (pytest, image `backend-api` + dépôt monté) : **417 réussis**, 0 échec (393 existants inchangés + 24 `test_abonnements.py` : Free → GroqCloud, Pro → Claude, contournement refusé, admin de test, routage désactivé, fournisseur non configuré sans repli, cache 30 s, exception, compte Pro sur l'offre, session de 5 h, limite de session et renouvellement sans toucher au jour, tokens de session, jour épuisé sans session, redémarrage / réouverture = même session, appareils = même consommation, 80 appels simultanés → exactement 50, release, durée modifiée, comptabilisation unique + suivi, suivi jamais bloquant, chat compté dans jour / session / fournisseur, refus avant l'appel sans appel facturable, `/me/quota`).
- Mutation volontaire (contrôle de session retiré, copie jetable) : 2 tests en échec → les tests détectent la faille.
- Base réelle : limites appliquées au compte (vue admin), droits (authenticated / anon : aucun ; service_role : fonctions, aucune écriture directe), RLS ; données identiques (1 compte, `quota_usage` 4 lignes 99 / 135 209, 4 conversations, 12 messages) ; avis de sécurité : seulement « RLS sans politique » (voulu) pour `llm_usage` / `plan_config`.
- Instance de test `jarvis-api-abo` (port 8001, image `backend-api:abo-test`, routage ACTIF) : santé ok ; sans appel IA : compte Pro → anthropic / claude-opus-5-5, compte Free → groq / openai/gpt-oss-120b.
- Production `jarvis-api` : non modifiée (image `1e0a52b54b6f`, démarrée à 11:52, Claude pour tous, anciennes limites jusqu'au déploiement).

### Limitations
- GroqCloud : limite de débit par organisation, partagée par tous les comptes Free.
- Aucun plafond en dollars (à décider) ; tarifs non stockés.
- Flutter actuel : un 429 de session affiche l'heure de réinitialisation du jour (phase 3).
- Aucun essai réel des sessions avec l'application (prévu après accord).

### Prochaine étape
- Accord pour déployer (quotas jour + session) puis activer le routage (`ABONNEMENTS_ROUTAGE=true`).
- Phase 3 : jauges Flutter à partir de `/me/quota`.

## 2026-10-17 — Abonnements Free & Pro, phase 3 (interface Utilisation Flutter)

### Fait
- Paramètres › **Utilisation** (`PanneauUtilisation`) : en-tête (offre JARVIS Free / Pro, fournisseur, modèle), jauges Limite de session (détail messages / tokens), Messages aujourd'hui, Tokens aujourd'hui ; temps restant de session d'après `ends_at` ; heure exacte de la remise à zéro du jour ; « Voir les détails » → `UtilisationPage` (offre, fournisseur, session, jour, restes, fin de session, prochaine remise à zéro).
- Jauges en lecture seule (`JaugeUtilisation`) : bleu sous le seuil, orange (`CouleursJarvis.critique`) dès `critical_threshold_percent` lu du serveur, « Limite atteinte » à 100 % ; animation courte des changements.
- Données : `ApiJarvis.utilisation()` → `GET /me/quota` → modèle `Utilisation` (rien de codé en dur). `ServiceUtilisation` : ouverture, toutes les 30 s pendant l'affichage, 2 s après chaque appel IA ou refus (`ApiJarvis.surConsommation`), retour au premier plan, changement de compte ; lecture partagée, jamais l'IA.
- 429 typés (`ApiJarvis.messageLimite`) : jour / session × messages / tokens avec l'heure réelle de `resets_at` ; limite du fournisseur IA = message distinct.
- Routage inactif : le panneau indique le fournisseur qui sert réellement (`fournisseur_actif`).
- Doc : `docs/backend/ABONNEMENTS.md` §10 ; CLAUDE.md.

### Tests (aucun appel IA)
- `test/utilisation_test.dart` : 24 tests (modèle, seuils 79 / 80 / 100 et seuil modifié, illimité, remises à zéro, 4 types de 429, service sans doublon, panneau Free → Pro → Free, routage inactif, indisponible, sans compte, page de détails, 100 % orange).
- Suite complète : 777 réussis + 1 test ancien (`ecriture_progressive_test`, texte du quota) mis à jour vers le 429 typé, réussi.
- Applis S10+, Windows, Web lancées contre l'instance de test 8001 : `/me/quota` lu (200) sur les trois ; S10+ : panneau affiché (JARVIS Free, GroqCloud, 15 / 100 messages, 31 086 / 50 000 tokens, remise à zéro « demain à 01:00 »).
- Synchronisation Supabase (base réelle, aucun compteur touché) : Pro 200 → 250 → 200 non observable (compte passé en Free par l'utilisateur) ; Free 100 → 120 à 19:01:06 UTC → S10+ « 15 / 120 messages », 12 %, déjà affiché à +35 s (lecture de 19:01:13, 7 s après) ; remis à 100. `plan_config` identique à l'état initial.

### Limitations
- Aucun changement en production : `jarvis-api` (8000) ne fournit pas encore `/me/quota` avec sessions.
- Délai d'une modification Supabase : ≤ 30 s (cache serveur) + ≤ 30 s (relecture).

### Prochaine étape
- Accord pour déployer la nouvelle image backend puis activer `ABONNEMENTS_ROUTAGE`.

## 2026-10-18 — Utilisation : quotas quotidiens seulement, synchro Supabase, actualisation invisible

### Fait
- Migration `supabase/migrations/20261017200000_quotas_quotidiens_synchro.sql`, **appliquée** sur « Jarvis » : colonnes de session de `plan_config` facultatives et vidées (plus aucun quota de session ; mécanisme backend conservé) ; déclencheurs `users_suivre_offre` et `plan_config_propager` : `users.daily_message_limit` / `daily_token_limit` = limites de l'offre, sauf exception (`limits_override`). Compte aligné : 60 / 100 000 (anciennes valeurs ignorées) → 150 / 50 000 (offre Free). Consommation intacte.
- Flutter : panneau et page Utilisation avec les deux seules jauges quotidiennes ; « Mis à jour à l'instant », icône et bouton d'actualisation, « Réessayer » retirés ; « Voir les détails » conservé. Modèle sans session.
- `ServiceUtilisation` conservé : ouverture du panneau et de la page, toutes les 30 s tant que visible, suspendu quand l'application est masquée et repris au retour, après chaque réponse IA ou refus de quota, premier plan, changement de compte. Seule la première lecture annonce un chargement ; ensuite une seule notification par relecture. Erreur réseau : dernières valeurs + note discrète.
- Doc : `docs/backend/ABONNEMENTS.md` (§4, §10, §11), CLAUDE.md.

### Tests (aucun appel IA)
- SQL : 145 réussis, 0 échec (13 nouveaux, `70_quotas_quotidiens_synchro_test.sql`).
- `test/utilisation_test.dart` : 29 tests (ouverture, périodique et arrêt, appli masquée, après réponse IA, après erreur de quota, aucune requête inutile, changement d'abonnement, limites modifiées, erreur réseau, une notification par relecture, panneau à 2 jauges sans bouton, valeurs remplacées sans chargement, page de détails relue à l'ouverture).
- Suite complète : 781 réussis ; 1 test sans rapport (`reponses_envoyees_test`, défilement) en échec sous charge, réussi seul (20/20).
- Avis de sécurité Supabase : rien de nouveau.

- Windows (instance 8001, capture de la fenêtre) : panneau à 2 jauges, sans actualisation visible ; Free 150 → 160 à 11:46:39 UTC → `users` suit aussitôt (160) → « 0 / 160 messages » affiché en ≤ 65 s ; retour 150 à 11:48:32 → « 0 / 150 » en ≤ 65 s. `plan_config` remis à l'identique. Web (localhost:3000, confirmé par l'utilisateur) : « 0 / 150 messages », deux jauges, aucun bouton d'actualisation. S10+ : non disponible ce jour.

### Prochaine étape
- Valider le S10+ dès qu'il est disponible, puis commit avec accord.

## 2026-10-18 — Déploiement du backend des abonnements en production

### Fait
- Image de production sauvegardée : `backend-api:avant-abonnements` (ancienne `1e0a52b54b6f`).
- `jarvis-api` (port 8000) reconstruite depuis le code actuel (backend inchangé depuis la phase 2 validée, 417 tests) : image `954d097068c5`. Vérifié sans appel IA : santé ok, `/me/quota` 401 sans jeton, CORS localhost:3000 ok, `ABONNEMENTS_ROUTAGE=False`, cache des limites 30 s, `ENVIRONNEMENT=production`, `LLM_PROVIDER=anthropic`, `fournisseur_actif` présent.
- Effet : quotas quotidiens de `plan_config` appliqués à tous (Free 150 / 50 000, Pro 300 / 100 000), aucune session ; Claude sert encore tous les comptes (routage désactivé).
- Instance de test `jarvis-api-abo` (8001) supprimée, ainsi que les images `backend-api:abo-test` et `backend-api:mia-test`. Restent : `jarvis-api`, `jarvis-redis`, images de retour arrière `avant-abonnements` et `avant-mia`.
- Applis Windows et Web relancées sur la production (aucune adresse 8001 dans le code ; `JARVIS_API_URL` absent = 8000).
- Vérifié : Windows et Web lisent `/me/quota` sur la production (200, deux connexions, aucune erreur serveur) ; panneau Utilisation confirmé par l'utilisateur.

### Prochaine étape
- S10+ : réinstaller l'appli (`flutter run`) pour avoir l'interface Utilisation (l'APK installé est antérieur), `adb reverse tcp:8000 tcp:8000`.
- Activer `ABONNEMENTS_ROUTAGE` (Free → GroqCloud) avec accord.

## 2026-10-18 — ODO, phase 1/2 : moteur universel + routage Free/Pro prêt

### Fait
- Point de restauration : tag `sauvegarde-avant-odo-phase1`, image `backend-api:avant-odo`.
- **MIA universel** (`app/llm/`) : appels d'outils, rétrocompatibles (sans outils : requêtes et événements identiques).
  - `base.py` : `TourAssistant`, `ResultatAppel`, `message_appels`, `message_resultats`, `Fin.tour` / `Fin.appels`, `verifier_outils`, messages `outil`.
  - `anthropic.py` : `tools`, lecture des `tool_use`, tour rejoué tel quel (réflexion signée), `tool_result`.
  - `groq.py` : `tools`, `tool_calls` réassemblés par index, JSON illisible signalé, messages `tool`.
- **ODO** (`app/odo/`, nouveau) : contrat, registre, permissions, validation stricte, sécurité (enveloppe `<resultat_outil>`, neutralisation, troncature), confirmations Redis (usage unique, par compte, TTL), orchestrateur borné (tours, appels, délais, doublons, budget entre les tours, interruption), journal sans données, 3 outils fictifs (hors production), `service.py` (`ODO_ACTIF`).
- **Route** :
  - `chat_stream` raccordé autour de `llm.flux` (chat ordinaire seulement) ;
  - événements SSE `outil` / `confirmation` ;
  - usage des tours compté même en cas d'interruption ;
  - `POST /api/v1/odo/confirmations/{id}`.
- **Routage Free / Pro** : code revu, correct (fournisseur et modèle de `plan_config`, identité du JWT, aucun repli). Ajouts : alerte au démarrage si un fournisseur manque, `scripts/verifier_routage.py`, `SupabaseAdmin.list_plan_config`.
- **Configuration** : `ODO_ACTIF=false`, `ODO_OUTILS_FICTIFS=false`, `ODO_MAX_TOURS` / `ODO_MAX_APPELS` / `ODO_DELAI_OUTIL` / `ODO_RESULTAT_MAX_CARACTERES` / `ODO_CONFIRMATION_TTL` ; `.env.example`.
- **Doc** : `docs/backend/ODO.md` (nouveau), `MIA_UNIVERSEL.md`, `ABONNEMENTS.md` §12, CLAUDE.md.

### Tests (aucun appel réel)
- Backend : **478 réussis, 1 ignoré** (sans objet pour Claude), 0 échec. 59 nouveaux :
  - `test_odo` 24, `test_odo_chat` 9, `test_llm_outils` 15, `test_routage` 10, WhatsApp avec ODO forcé 1 ;
  - 1 test de contrat remplacé (« outils refusés » → « sans outils, requête inchangée »).
- Mutations (copie jetable) : retirer la validation, la confirmation ou le routage fait échouer respectivement 1, 4 et 8 tests.
- SQL : 145 réussis (aucune migration dans cette phase).
- Flutter (aucun fichier Flutter modifié) : chat IA, écriture progressive, Utilisation, 96 réussis.
- Instance de test `jarvis-api-test` (port 8001, routage ACTIF, ODO inactif, Redis base 1) : santé ok, `/me/quota` 401 sans jeton, aucune alerte de fournisseur. `verifier_routage` : Free → groq / openai/gpt-oss-120b prêt, Pro → anthropic / claude-opus-5-5 prêt ; compte réel (Free) routé vers GroqCloud.

### État
- Production `jarvis-api` (8000) **inchangée** : `ABONNEMENTS_ROUTAGE=false` (Claude pour tous), sans le code ODO.
- `ODO_ACTIF` : false partout ; jamais activé en production.
- Gmail : non développé.

### Prochaine étape
- Accord pour activer `ABONNEMENTS_ROUTAGE=true` en production (procédure : ABONNEMENTS.md §12).
- Phase 2 : Gmail (OAuth, lecture seule), cartes de confirmation Flutter, interception locale du mot « mail ».

## 2026-10-18 — Routage Free / Pro activé en production

### Fait (avec accord)
- `backend/.env` : `ABONNEMENTS_ROUTAGE=true` ajouté (copie de l'ancien fichier gardée hors du dépôt). `jarvis-api` recréé sur la même image de production (`954d097068c5`, sans ODO), démarré à 13:55:40 UTC.
- Contrôles sans appel IA :
  - santé ok, Redis et Supabase ok, `/me/quota` 401 sans jeton ;
  - route ODO absente (404) ;
  - journal : « Routage par abonnement : ACTIF » ;
  - Free → groq / openai/gpt-oss-120b prêt, Pro → anthropic / claude-opus-5-5 prêt ;
  - compte réel (Free) → GroqCloud.
- `ODO_ACTIF` : absent en production (code ODO non déployé).
- Instance de test `jarvis-api-test` (8001) retirée ; image `backend-api:odo-test` gardée.

### Incident
- Production arrêtée par erreur de 13:45:00 à 13:55:40 UTC (≈ 11 min). Une commande de nettoyage des conteneurs de test (`docker stop` filtré sur l'image `backend-api`) a aussi visé `jarvis-api`. Aucune donnée touchée (Redis, Supabase intacts). Retour en service avec l'activation du routage.
- Mesure : conteneurs visés par leur nom exact uniquement.

### Retour arrière
- `ABONNEMENTS_ROUTAGE=false` dans `backend/.env`, puis `docker compose up -d api`.

### Prochaine étape
- Vérifier un échange réel Free (GroqCloud) depuis l'application quand tu le souhaites (appel facturable, avec ton accord).
- Phase 2 d'ODO : Gmail.

## 2026-10-18 — ODO, phase 2/2 : Gmail en lecture seule

### Partie A — Routage réel Free → GroqCloud (S10+)
- S10+ détecté et autorisé ; l'appli installée visait l'ancienne instance 8001 (supprimée) : réinstallée vers la production (8000) avec `adb reverse tcp:8000`.
- 1er essai (« Réponds juste OK. ») : réponse LOCALE (« Très bien. »), aucun appel, rien compté.
- 2e essai, 1 seul appel réel : « quel est la capital du Canada en 1 mot » → « Ottawa ».
  - `POST https://api.groq.com/openai/v1/chat/completions` 200, modèle `openai/gpt-oss-120b` ;
  - 1er fragment à 1,5 s, flux sans erreur ;
  - jour : 1 → 2 messages, 238 → 503 tokens (+265 = 196 entrée + 69 sortie) ;
  - `llm_usage` groq +1, Claude inchangé ;
  - `/me/quota` relu après la réponse.

### Fait (hors production)
- **Supabase** : migration `20261018100000_connexions_externes` **appliquée** (accord).
  - table `external_connections` sans jeton, RLS + droits par colonne ;
  - jeton de rafraîchissement dans **Vault** ;
  - fonctions `enregistrer_` / `jeton_` / `marquer_` / `supprimer_connexion_externe` (`service_role` seulement) ;
  - secret supprimé avec la ligne ;
  - aucun nouvel avis de sécurité.
- **Backend** :
  - `app/integrations/google.py` : OAuth « authorization code » + PKCE S256, `state` à usage unique lié au JWT, `gmail.readonly` seul, `prompt=select_account consent`, révocation, renouvellement, état « à renouveler » ;
  - `app/integrations/gmail.py` : GET seulement, requête structurée, bornes, pièces jointes jamais téléchargées ;
  - routes `/api/v1/integrations/gmail` (état, connexion, retour HTML, déconnexion) ;
  - compétences ODO `gmail_rechercher`, `gmail_lire_message`, `gmail_lire_fil`, `gmail_preparer_resume` + `CONSIGNE_GMAIL` ;
  - `ServiceODO.contexte_compte` / `note` (« connectez Gmail ») ;
  - validation `pattern` ;
  - `conftest.py` : tests isolés de la configuration privée.
- **Flutter** :
  - Paramètres › Gmail (`PanneauGmail` : connecter, attente, connecté, à renouveler, non configuré ; autorisations expliquées ; déconnexion confirmée) ;
  - `ServiceGmail` (navigateur du système via `url_launcher`, attente du retour, premier plan) ;
  - `EtatGmail` ;
  - `ApiJarvis.etatGmail` / `urlConnexionGmail` / `deconnecterGmail` ;
  - `DetecteurIntention.concerneMesEmails` : « résume mes mails » va au serveur (plus de « colle la conversation ») ;
  - Android : lien `jarvis://gmail`.
- **Vocal et JARVIS Touch** : rien de reconstruit, ils passent par la même `ConversationSession`.
- **Doc** : `docs/backend/GMAIL.md` (+ guide Google Cloud), `ODO.md`, CLAUDE.md, `.env.example`.

### Tests (aucun appel réel)
- Backend : **500 réussis, 1 ignoré** (22 nouveaux `test_gmail`).
- SQL : **169 réussis** (24 nouveaux `80_connexions_externes_test`).
- Flutter : **792 réussis** (11 nouveaux `gmail_test`) ; 1 test vocal (`vocal_android_test`, non modifié) en échec sous charge, réussi seul (15/15).

### État
- Production `jarvis-api` (8000) **inchangée** pendant tout le développement : image `954d097068c5`, routage actif, sans ODO ni Gmail.
- Instance isolée `jarvis-api-gmail` (port 8001, image `backend-api:gmail-test`, Redis base 2, ODO actif) : Gmail « non configuré » tant que les identifiants Google ne sont pas dans `backend/.env`.

### Validation réelle sur le S10+ (instance de test 8001, compte Free → GroqCloud)
- **Google Cloud** (fait par l'utilisateur) :
  - projet JARVIS, API Gmail activée ;
  - client OAuth « Application Web » avec les adresses de retour localhost 8001 et 8000 ;
  - portées `gmail.readonly` (+ `gmail.send` déclarée, non utilisée) ;
  - mode Test.
- **Identifiants** : vérifiés auprès de Google sans appel utile (faux code → `invalid_grant`). Un caractère du secret mal recopié depuis une capture a été corrigé.
- **Connexion Gmail sur le S10+** : choix du compte chez Google, retour automatique dans JARVIS (`jarvis://gmail`), page « Gmail connecté » (adresse, lecture seule). En base : connexion active, portée lecture seule, jeton dans Vault (1 secret).
- **Compte d'école** (Google Workspace) : bloqué tant qu'il n'est pas utilisateur test (`403 access_denied`).
- **« Résume mes 3 derniers mails » (écrit)** :
  - 1er essai : 4 tours (lecture un par un) → `odo_limite`, et tours NON comptés ;
  - corrigé : dernier tour à réponse forcée (`tool_choice` « none » pour Claude et GroqCloud), consigne « résumer en UN appel », tours consommés comptés même sans réponse (`consomme_sans_texte`) ;
  - 2e essai : 3 tours (`gmail_rechercher` + `gmail_preparer_resume`), résumé avec « Interprétation globale », GroqCloud seulement, +1 message, +6 172 tokens, Gmail en GET seulement.
- **Vocal** (« Regarde si j'ai reçu des mails importants aujourd'hui ») : même conversation, 2 tours, réponse lue par la synthèse vocale, +1 message.
- **Défaut de sécurité vu en réel** : le modèle a recopié des codes de vérification reçus par e-mail. La consigne Gmail l'interdit désormais (codes, mots de passe, liens de connexion, numéros de carte ou de compte), avec un test.
- **Lecture vocale** : la consigne demande des phrases simples, sans titres ni séparateurs.
- **Tests après corrections** : backend 506 réussis, 1 ignoré.

## 2026-10-18 — JARVIS Touch, phase 3A : « Analyser l'écran » (capture, aperçu, recadrage, suppression)

### Fait
- **Menu** : « Analyser l'écran » n'affiche plus « Disponible prochainement » ; capture en attente → son aperçu.
- **Capture sans autorisation répétée** (demande de l'utilisateur en cours de phase) : `ServiceAccessibiliteJarvis` (Android 11+, `takeScreenshot`), activé une fois dans Paramètres › Accessibilité ; ne lit aucun contenu, ne traite aucun événement.
- **Secours MediaProjection** (service non activé) : activité transparente dans sa propre tâche (Chrome reste dessous, JARVIS jamais ramené), service premier plan `mediaProjection` le temps d'UNE image, projection / écran virtuel / lecteur / fil libérés aussitôt ; refus → bulle rendue.
- **Aperçu natif** (aucun moteur Flutter de plus) : image, Recadrer, Supprimer, Nouvelle, Réduire (capture gardée) ; « locale et temporaire » ; lien « Ne plus demander l'autorisation » si l'accessibilité n'est pas active ; FLAG_SECURE ; refermé à l'extinction de l'écran.
- **Recadrage** : sélection rectangulaire (coins, bords, déplacement), bornée à l'image, toujours tirée de l'original en pleine résolution ; Annuler / Tout / Valider ; « Annuler le recadrage ».
- **Confidentialité** : PNG dans `cache/captures_touch/` seulement ; suppression = fichiers effacés + images libérées ; captures abandonnées effacées au redémarrage ; aucun journal de contenu (tailles et durées seulement) ; aucun envoi, aucune IA.

### Mesuré sur le S10+ (Android 12, 1440 × 3040, voie MediaProjection)
- Consentement → image : 545-594 ms (dont 450 ms d'attente volontaire de la fermeture du dialogue) ; conversion 21-26 ms ; PNG plein écran 217-249 Ko en 331-359 ms (fil d'arrière-plan) ; recadrage 788 × 1091 : 73 Ko en 81 ms.
- 9 captures + suppressions de suite : PSS stable (~439 Mo), « Graphics » plafonné (cache de textures, redescend ensuite), 0 fichier restant.

### Mesuré sur le S10+ (voie accessibilité, activée par l'utilisateur)
- Aucune fenêtre d'autorisation, aucune icône de diffusion sur l'image ; image en 22-36 ms + copie 55-71 ms ; 6 captures enchaînées : PSS stable (~457 Mo), 0 fichier restant.

### Testé sur le S10+
- Chrome capturé, sans bulle, menu ni dialogue sur l'image ; aperçu, recadrage (image nette), annuler puis recommencer, suppression (fichiers effacés), refus d'autorisation (bulle rendue), captures répétées, mini-chat de la phase 2 qui s'ouvre toujours.
- Correction vue en réel : aperçu rogné en bas (fenêtre placée sous la barre d'état) → fenêtre de la taille de la carte, placée dans la zone utilisable, voile système.

### Limites
- Voie MediaProjection : l'icône système de diffusion apparaît dans la barre d'état de l'image ; Android 14+ (config écran entier, service `mediaProjection`) vérifié dans le code seulement.
- Accessibilité : à activer une fois par l'utilisateur (fait et validé sur le S10+) ; Google Play contrôle ce type de service en cas de publication.
- Captures gardées en mémoire tant qu'elles ne sont pas supprimées (perdues si la bulle s'arrête : effacées).

### Prochaine étape
- Phase 3B : envoi explicite de la capture validée (`CaptureTouch.fichierValide`) à l'analyse IA.


## 2026-10-18 — Paramètres › Outils › Gmail (interface) et préparation du déploiement ODO/Gmail

### Fait
- **Navigation** : l'entrée « Gmail » des Paramètres devient « Outils » (« Gérer les services connectés à JARVIS ») → page Outils → Gmail. Retour Android / Échap : Gmail → Outils → Paramètres.
- **Outils** (`panneau_outils.dart`, `OutilJarvis`) : Gmail seul (aucun Agenda / Documents fictif), logo, nom, statut, chevron ; statut du même `ServiceGmail` que la page Gmail.
- **Gmail** (`panneau_gmail.dart` réécrit) : en-tête logo + statut ; compte Google, « Lecture seule » ; « Gérer la connexion » regroupe Changer de compte / Déconnecter Gmail (confirmation conservée) ; déconnecté : invitation courte + « Choisir un compte Google » (OAuth existant) ; états À reconnecter, Indisponible, Connexion en cours, Vérification…, Non vérifié. Encadré « Autorisations » retiré de la page.
- **Centrage** : colonne de 560 au plus, centrée horizontalement ; la page Gmail est aussi centrée verticalement (défilement si l'écran est trop petit). Correction demandée après une photo du S10+.
- **Sans chargement visible** : `ServiceGmail` partage les lectures, ne relit pas avant 30 s, ne notifie que si l'état change, garde le dernier état en cas d'échec (note discrète), lit l'état 3 s après la connexion au compte (`lireBientot`), efface tout au changement de compte ; rien sur l'appareil, jamais « Connecté » sans réponse du serveur.
- **ODO** : messages « connectez Gmail dans Paramètres › Outils › Gmail » (2 phrases, liées à la nouvelle navigation).
- **Déploiement préparé, non exécuté** : `docs/backend/DEPLOIEMENT_ODO_GMAIL.md` (état, plan, sauvegardes, retour arrière, Google Cloud). Image candidate `backend-api:odo-gmail-prod` construite (nouveau tag ; `latest` et la production intacts).
- Point de restauration : branche locale `sauvegarde/avant-outils-gmail` (`e495ef4`).

### Tests
- Flutter : 801 réussis (suite complète) ; `gmail_test` : 19 (dont lectures partagées, échec réseau, changement de compte, réouverture sans chargement, Outils).
- Captures (`tool/capture_parametres_test.dart`, états simulés) : Outils, Gmail connecté / déconnecté / « Gérer la connexion », téléphone 412 et 360, ordinateur 1280.
- Backend (image candidate) : 506 réussis, 1 ignoré (un test de durée sensible à la charge, réussi seul).
- **Réel, S10+ (instance de test 8001, vrai compte)** : Paramètres → Outils (« Connecté » affiché aussitôt) → Gmail (centré, adresse réelle, données affichées 0,2 s après l'appui à la réouverture), feuille « Gérer la connexion » ouverte puis refermée (rien changé), retour Android.
- Non vérifié en réel : Windows et Chrome Web (captures ordinateur seulement), changement de compte JARVIS (test simulé), redémarrage (lecture 3 s après connexion, test simulé). Aucun appel LLM.

### État
- Production `jarvis-api` (8000) **inchangée** : image `954d097068c5`, sans ODO ni Gmail ; l'appli y affichera « Non vérifié » pour Gmail tant que le déploiement n'est pas fait.
- Instance de test `jarvis-api-gmail` (8001) inchangée, toujours en marche.

### Prochaine étape
- Accord de l'utilisateur pour exécuter `DEPLOIEMENT_ODO_GMAIL.md`.

## 2026-10-18 — ODO et Gmail déployés sur la production (8000)

- Fait avec l'accord de l'utilisateur, selon `docs/backend/DEPLOIEMENT_ODO_GMAIL.md` (section 9) : image `odo-gmail-prod` (`88cb8709a1e9`), `ODO_ACTIF=true`, `GOOGLE_REDIRECT_URI` sur 8000 ; seul `jarvis-api` recréé (Redis et 8001 intacts).
- Vérifié : santé ok, routes Gmail présentes, S10+ sur 8000 : Gmail « Connecté » sans reconnexion (connexion Vault conservée), une seule lecture d'état.
- Retour arrière prêt : `docker tag backend-api:avant-odo-gmail backend-api:latest` + `.env.sauvegarde-20261018` + `docker compose up -d --no-deps --no-build api`.
- Instance de test `jarvis-api-gmail` (8001) toujours en marche (à arrêter seulement sur demande).
- Prochaine étape : essai réel « Résume mes mails » sur 8000 (facturable, sur accord) ; qualité des résumés (chantier séparé).

## 2026-10-18 — JARVIS Touch, phase 3A.1 : menu refait, éditeur de capture plein écran

### Fait
- **Menu** (`MenuJarvisTouch`) : panneau sombre translucide (dégradé violet, coins 30 dp, liseré violet, une seule ombre), grille 2 × 2 séparée par de fins traits, pastilles 56 dp, ouverture 170 ms ; « Analyser l'écran » devient « Capturer » ; « Vocal » / « Importer » : « Disponible prochainement » dans l'en-tête (plus de ligne réservée).
- **Éditeur plein écran** (`EditeurCaptureTouch`, remplace `ApercuCaptureTouch`) ouvert dès la capture : barre du haut Fermer (supprime) · Annuler / Rétablir (cachés tant qu'impossibles) · Valider ; fond sombre, aucun texte.
- **Recadrage** (`RecadrageVue`) : sélection active sur toute l'image, voile extérieur, poignées aux coins et au milieu des bords, grille 3 × 3 seulement pendant le geste, double-toucher = image entière (dans l'historique, jamais pendant un glissement), une étape par geste, 30 au plus, « Rétablir » effacé par une nouvelle modification ; aucune allocation pendant le geste.
- **Validation** (`CaptureTouch.valider`) : recadrage appliqué une seule fois, pixels d'origine copiés tels quels, PNG en arrière-plan, original et son fichier libérés ; capture validée gardée dans le cache privé jusqu'à la suivante.
- **Paramètres › Général › JARVIS Touch · Capture d'écran** : état réel (« Activée » / « Désactivée »), bouton vers l'accessibilité d'Android, note de confidentialité ; aucun faux interrupteur. Retirés de l'éditeur : textes de confidentialité, lien d'autorisation, boutons textuels.

### Testé
- Flutter : `test/jarvis_touch_test.dart` 8/8 (1 nouveau : section Capture d'écran) ; `flutter analyze` sans remarque sur les fichiers touchés.
- S10+ : menu (ouverture, placement à côté de la bulle à gauche, Discuter → mini-chat), Capturer → éditeur direct, Annuler / Rétablir selon l'historique, nouvelle modification qui efface Rétablir, double-toucher réinitialisant (vérifié par l'historique), Valider (749 × 1246, net, original effacé), Fermer (0 fichier restant), bulle rendue.
- Mesures : capture (secours MediaProjection) 583 ms dont 450 ms d'attente volontaire ; PNG plein écran 367 ms, recadré 92 ms, en arrière-plan. Mémoire sur 8 captures + fermetures : « Graphics » plafonné (~116 Mo), PSS 503 → 509 Mo (dérive légère, à surveiller).

### Limites
- Éditeur et grille protégés (FLAG_SECURE) : non photographiables par adb, vérifiés par l'arbre d'accessibilité et les fichiers.
- Une réinstallation de développement désactive le service d'accessibilité : à réactiver (l'appli bascule seule sur MediaProjection).
- Fluidité du geste non chiffrée (pas de mesure d'images par seconde).

### Prochaine étape
- Phase 3B : utiliser la capture validée dans le mini-chat (`CaptureTouch.fichierValide`), sur action explicite.

## 2026-10-18 — JARVIS Touch : Paramètres, capture → IA, vocal flottant, Actions

### Fait
- **Paramètres** : Général n'a plus qu'une entrée « JARVIS Touch · Assistant flottant » ; page dédiée (interrupteur existant, Capture d'écran, Personnalisation) ; page Capture : « Autorisé » / « Non autorisé » / « À chaque capture » selon l'état réel, « Gérer l'autorisation ».
- **Capture → mini-chat** : après Valider, le mini-chat s'ouvre avec la vignette (rien n'est envoyé) ; croix = capture effacée ; gardée si le chat est réduit ; envoi seulement par Envoyer.
- **Image → MIA** : champ `image` de `/chat/stream`, contrôlé (`app/vision.py`) ; Claude seulement (`vision`) ; offre Free → refus clair avant tout appel (décision de l'utilisateur : « Claude seulement en Pro ») ; jamais en base ; 1 h dans Redis pour les questions suivantes.
- **Vocal flottant** : fenêtre compacte « JARVIS — Vocal » (symbole audio bleu, Micro / Chat / Quitter / Réduire) sur la session vocale de l'accueil ; micro déclaré au service au premier plan seulement pendant le vocal.
- **Actions** : remplace « Importer » dans le menu ; 4 compétences affichées, « Bientôt disponible ».
- **Backend de test arrêté** : `jarvis-api-gmail` (8001) arrêté (non supprimé) et `adb reverse 8001` retiré, à la demande de l'utilisateur ; production `jarvis-api` mise à jour (`docker compose up -d --build api`, image précédente gardée : `backend-api:avant-vision`).

### Tests
- Backend : 516 réussis, 1 ignoré (7 nouveaux `test_vision`) ; essai RÉEL `tests/essai_vision_reel.py` : Claude (`claude-opus-5-5`) via MIA lit une image fictive (« Rouge »).
- Flutter : 804 réussis (nouveaux : `capture_jointe_test`, pages Paramètres dans `jarvis_touch_test`).
- S10+ (Android 12, vrai backend) : menu (Actions, Bientôt disponible, retour), capture → éditeur → Valider → mini-chat avec vignette, réduction sans perte, envoi : image reçue par le serveur et refusée (Free) avec le message attendu, même échange dans JARVIS principal ; vocal : ouverture, écoute réelle (indicateur micro Android), Micro coupé / réactivé, Réduire (bulle marquée), réouverture, Quitter (capacité micro du processus retirée).
- Corrigé pendant les essais : `DemandeJarvis.avecFragments` perdait l'image (test ajouté) ; l'appli lancée sans `JARVIS_API_URL` visait 10.0.2.2.

### Mesures (S10+)
- Recadrage (gfxinfo, 200 images : coins, bords, déplacement, double-toucher) : médiane 9 ms, 90e 12 ms, 95e 16 ms, 99e 20 ms, 2 % d'images saccadées.
- Validation : PNG recadré 997 × 2235 en 247 ms (arrière-plan).
- Mémoire : 414 Mo → 456 Mo juste après 6 captures → 430 Mo 10 s après (redescend : pas de fuite constatée) ; 0 fichier restant.

- **Analyse visuelle de bout en bout (S10+, compte passé en Pro le temps de l’essai, avec l’accord de l’utilisateur, puis remis en Free : 150 messages / 50 000 tokens)** : capture Chrome → mini-chat → Envoyer → serveur (« Image jointe : image/png, 244 Ko ») → Claude (claude-opus-5-5) : description exacte de la page (sens de Flutter, Od1n, 10 h 18, batterie 100 %) ; question suivante sur la même image sans renvoi (contexte Redis) : réponse exacte (cinq rubriques) ; en base : référence seulement (118 caractères), aucun octet.

### Non testé / limites
- Vocal : reconnaissance d'une vraie phrase, réponse IA et lecture TTS non testées (personne pour parler au téléphone pendant l'essai).
- Page Paramètres JARVIS Touch vérifiée par tests de widgets, pas ouverte sur le téléphone.
- Un premier essai (avant correction) a enregistré dans le compte une question « Que vois-tu sur cette capture ? » avec une réponse GroqCloud sans image.


## 2026-10-18 — UX : panneau latéral au glissement, avatar du compte, balayage complet, Utilisation immédiate

### Fait
- **Panneau latéral au geste** (`menu_lateral.dart`, panneau existant conservé) : bande invisible de 24 px le long du bord gauche (+ zone du geste Retour d'Android), translucide (les touchers passent à l'accueil) ; le panneau et le voile suivent le doigt (position linéaire, courbe seulement à la fin) ; relâchement : seuil 35 % de la largeur, lancer ≥ 700 px/s (le sens décide), fin en 180-280 ms selon la distance et la vitesse ; fermeture en glissant vers la gauche sur le voile ou le panneau ; ×, voile, Échap, Retour inchangés ; doigt / stylet seulement (souris : bouton) ; réduction des animations du système respectée. Le balayage d'une ligne et le défilement du sélecteur de messageries l'emportent sur la fermeture.
- **Avatar du compte** (`menu/avatar_compte.dart`) à la place du symbole JARVIS en bas du panneau : boule dégradé signal → violet, initiale du nom affiché (sinon de l'e-mail, jamais montré), suit le compte ; sans compte : silhouette ; appui → Paramètres › Compte, ouverte directement sur téléphone (`ouvrirSection`).
- **Balayage complet des conversations** (`ligne_conversation.dart`, même modèle que `LigneImportGlissante`) : court = bouton révélé (inchangé) ; au-delà de 60 % de la ligne (au moins 1,6 bouton) le bouton s'arme (contenu au bord de la ligne, agrandi, vibration) et l'action part au relâchement, une seule fois (verrou pendant l'action) ; revenir en deçà annule. Épingler / Désépingler : même chemin que le bouton. Supprimer : la ligne part puis **la confirmation existante** ; Annuler la ramène.
- **Utilisation sans attente** : `CacheUtilisation` (SharedPreferences, clé `jarvis.utilisation`, une entrée rattachée au compte, format versionné, effacée à la déconnexion) rechargée dès que le compte est connu ; panneau et page s'affichent aussitôt (copie, sinon structure avec « — », jamais 0), relecture silencieuse ; hors ligne : dernières valeurs + note discrète datée ; copie d'une journée terminée (`resets_at` passé) : consommation « — » + « Nouvelle journée ». « Lecture de votre utilisation… » et le chargement supprimés. Copie d'affichage seulement ; quotas toujours décidés par le serveur. Backend inchangé.

### Tests
- Flutter : 825 réussis (804 avant), dont les nouveaux tests du geste (bord, suivi du doigt, voile proportionnel, seuil, lancer, inversé, annulé, loin du bord, vertical, souris, réduction des animations), de l'avatar (initiales, changement de compte, section Compte, téléphone), du balayage complet (3 largeurs, une seule action, annulation, suppression confirmée) et du cache (aller-retour, redémarrage hors ligne, priorité au serveur, autre compte, déconnexion, ancien format, nouvelle journée, affichage immédiat).
- S10+ (Android 12, navigation par gestes, vrai backend) : ouverture depuis le bord (panneau suivant le doigt à mi-course, Retour d'Android non déclenché), fermeture au geste, geste court et lent → refermé ; fluidité sur 10 ouvertures + 10 fermetures, PIM animé : 1 687 images, 0,59 % saccadées, médiane 12 ms, 99e 19 ms ; balayage complet Épingler / Désépingler (liste remise dans son état), Supprimer → confirmation → Annuler (rien supprimé) ; avatar « J » → page Compte ; Utilisation : première ouverture sans copie (« — » puis valeurs), redémarrage hors ligne (valeurs aussitôt + note datée), reconnexion (note retirée automatiquement).

### Non testé / limites
- Gestes simulés par `adb` : sensation réelle au doigt et vibrations à vérifier par l'utilisateur.
- Deux séquences `adb` instantanées (tous les mouvements sans délai) ont refermé le menu ou révélé une autre ligne ; non reproduit à vitesse réaliste ni en test automatisé, cause non établie.
- Web et Windows : couverts par les tests de widgets (souris : geste désactivé, bouton conservé), pas lancés réellement. iOS : non testé.

## 2026-10-19 — Voix naturelle et arrêt de la parole (vocal principal + JARVIS Touch)

### Fait
- **Texte oral** (`TexteOral`, partagé) : plus aucun symbole prononcé (gras, puces, numéros, titres, tableaux, liens, code, émojis) ; listes numérotées dites « D'abord… Ensuite… Enfin… » ; km/h, °C, m², ≈, ≤, → en mots ; chiffres, dates et pourcentages intacts. Appliqué au chat vocal et à la lecture des réponses écrites.
- **Consigne orale** (backend, échanges vocaux seulement, `oral: true`) : réponse naturelle, directe pour une question simple, progressive pour une explication, sans liste ni mise en forme, chiffres exacts. Un seul appel au modèle ; production mise à jour (image précédente : `backend-api:avant-oral`).
- **Arrêt de la parole** (`VoiceSession.arreterParole` / `parler`) : état « Parole interrompue » immédiat, voix coupée, aucune reprise automatique (ni voix ni écoute), « Parler » relance une écoute ; distinct de Micro, Réduire, Quitter.
- **Interfaces** : « À l'écoute… », « JARVIS réfléchit… », « JARVIS parle… » ; bouton rouge « Arrêter la parole » seulement pendant la parole, bouton « Parler » après un arrêt, dans une zone de hauteur fixe (rien ne bouge) ; même comportement dans JARVIS Touch (fenêtre de taille constante).
- **Paramètres › Chat vocal › Interruption de la parole** : Manuelle (par défaut) · « Automatique · bientôt » (indisponible), une seule ligne d'aide ; enregistré, partagé par les deux interfaces.
- **Interruption automatique non activée** : pas de détection fiable de la voix de l'utilisateur pendant la synthèse sur le S10+ (la reconnaissance Android est coupée pendant que JARVIS parle ; écho du haut-parleur non filtré) ; non simulée.

### Tests
- Flutter : `texte_oral_test` (7), `arret_parole_test` (2 : silence, aucune reprise, état immédiat, Parler, une seule demande IA ; quitter pendant la parole) ; suite complète : 833 réussis, 1 échec `gmail_test` sous charge (réussit seul, 19/19, fichier non modifié).
- Backend : 517 réussis, 1 ignoré (dont consigne orale seulement si `oral`).
- S10+ (phrase dite par la synthèse vocale du PC, vrai backend) : vocal principal → réponse orale naturelle (« D'abord, la chlorophylle… »), « Arrêter la parole » visible pendant la parole, arrêt, « Parler », aucune reprise en 16 s ; JARVIS Touch : même bouton, arrêt, « Parole interrompue » + « Parler », Quitter libère le micro.
- Corrigé pendant l'essai : JARVIS Touch pouvait afficher un « JARVIS parle » périmé après l'arrêt (réponse d'appel arrivée après l'état poussé) ; l'état change désormais avant l'arrêt de la voix et la fenêtre ne suit que l'état poussé (test ajouté).

### Mesures (S10+, journaux)
- Début de la voix après réception de la réponse : 10 à 44 ms.
- Arrêt de la voix après le toucher : 4 à 41 ms (6 mesures).
- Mémoire après la séance vocale : 408 Mo PSS.

### Limites
- La réponse est dite en un seul énoncé, à la fin de la réception (comportement existant) : pas de lecture par segments pendant le flux.
- Pendant l'essai, une autre personne a utilisé le téléphone (questions sur le soleil) : échanges réels, enregistrés dans la conversation.


## 2026-10-19 — Gmail, phase 1 sur 3 : compréhension des demandes et recherche intelligente

### Audit (avant)
- Une seule requête Gmail, mots en ET strict, aucun synonyme ni élargissement ; résultats dans l'ordre de Gmail, sans pertinence ni regroupement par fil ; « Aucun e-mail ne correspond » (le modèle pouvait conclure qu'aucun e-mail n'existe).
- Dates calculées par le modèle depuis la date UTC ; `after:AAAA/MM/JJ` interprété par Gmail dans son propre fuseau.
- Identifiants trouvés perdus d'une demande à l'autre ; aucune règle de clarification.
- **Confidentialité** : codes de vérification, liens de connexion, numéros de carte transmis au fournisseur IA (seule une consigne interdisait de les recopier) → corrigé.
- Mesure par outil seulement.

### Fait
- `app/odo/gmail_recherche.py` (déterministe, identique GroqCloud / Claude) : périodes nommées dans le fuseau de l'appareil (secondes), requête sûre avec alternatives en OU et variantes sans accents, élargissement ≤ 3 requêtes, pertinence forte / moyenne / faible, un candidat par fil, expéditeurs distincts signalés, compte rendu de ce qui a été consulté.
- `gmail_rechercher` : nouveaux critères (`expediteurs`, `termes` + reformulations, `periode`, `destinataire`, `pieces_jointes`, `envoyes`) ; consigne Gmail : comprendre, utiliser le contexte, chercher ou poser UNE question, reprendre après la réponse, prudence sur l'absence de résultat.
- `app/odo/gmail_confidentialite.py` : secrets masqués avant le modèle (codes, mots de passe, liens de connexion, cartes, IBAN ; autres liens réduits au domaine).
- Mémoire de la dernière recherche par compte et par chat (Redis 1 h, métadonnées seulement) → `<gmail_derniere_recherche>` jointe à la question suivante.
- Route de chat : `fuseau_minutes` (envoyé par l'appli Flutter, écrit et vocal), date et heure locales dans le message système.
- Mesures `ODO fin` : tours, appels, durée, temps avant le premier outil, tokens, requêtes Gmail, fournisseur (aucun contenu).
- Décision OAuth documentée (GMAIL.md) : option A maintenant (non vérifiée), option C plus tard.
- Point de restauration : branche `sauvegarde/avant-gmail-phase1` (`9657c7b`).

### Tests
- Backend : 539 réussis, 1 ignoré (31 nouveaux : 12 scénarios demandés, GroqCloud et Claude simulés pour les parcours de conversation, masquage, isolation, mesures).
- Flutter : suite complète réussie après mise à jour de 3 tests (corps de requête avec `fuseau_minutes`) ; 7 demandes indirectes vérifiées comme envoyées au serveur.
- Réel (instance temporaire 8002, compte passé en Pro → Claude, essais faits par l'utilisateur) : 2 demandes avec recherche Gmail = 2 tours, 10,7-11,0 s, 1 seul appel d'outil, premier outil après 3,1-3,7 s, 7 583 et 9 697 tokens, 3 et 11 requêtes Gmail ; 3 demandes sans outil (2,3-5 s). Contenu des échanges non vérifiable (aucun message enregistré en base) ; GroqCloud réel non essayé (limite quotidienne atteinte, puis téléphone déconnecté).

### État
- Production `jarvis-api` (8000) inchangée par cette phase ; instance 8002 arrêtée et supprimée ; image `backend-api:gmail-phase1` gardée.
- Rien n'est commité.

### Prochaine étape
- Essais réels guidés (S10+) avec Claude ET GroqCloud sur les exemples A à E, puis déploiement en production sur accord.
- Phase 2 : compréhension approfondie des contenus, importance, relations entre messages.


## 2026-10-19 — Optimisation de la compréhension conversationnelle WhatsApp

### Faiblesses identifiées (audit de `app/comprehension/`)
1. Les lots de propositions ne partageaient aucune compréhension : 24 derniers messages bruts + analyse tronquée ; ni message auquel répondre, ni interprétation commune (chaque lot relisait la situation).
2. Aucune habitude d'écriture observable (seulement des comptes) ; les propositions « dans la voix de l'utilisateur » ignoraient sa longueur, ses émojis, ses expressions.
3. Longueurs non proportionnées : Moyen jamais vérifié, Long forcé à 3 phrases même pour répondre à « Ok 👍 » (réel : 47 mots en moyenne, « PDF » et « pièce jointe » inventés).
4. Suivis naturels non ciblés (« Pourquoi elle me dit ça ? », « Tu crois qu'elle plaisante ? ») ; réponses déclarées envoyées sans place dans la chronologie (réel : la réaction de Lina à la promesse était expliquée par l'ancienne blague du « traitement »).
5. Message lu à la lumière d'anciennes habitudes plutôt que de l'échange qui l'a déclenché (réel : un pardon après un vrai reproche décrit comme une « boutade »).

### Fait
- `app/comprehension/etat.py` (nouveau) : état de compréhension partagé, faits sans IA, rien de stocké — habitudes par auteur, jalons de décision (forcés dans les extraits), indices de sérieux, proportion, suite récente ordonnée (ajouts / réponses déclarées), échange en cours vs plus tôt, message auquel répondre, inconnues ; mode compact si le budget est serré.
- `ciblage.py` : suivis déictiques ciblés (sauf question ancrée sur un autre message) ; groupe : dernier ajout collé, dernier reçu pour « que répondre ? », sinon clarification ; `<message_vise>` : échange en cours, plus tôt, réponse déclarée envoyée placée avant la réponse reçue.
- `generation.py` : attribut `lecture` (interprétation unique écrite par la réponse principale, stockée, reprise par « Reprendre ») ; `brief` commun à tous les lots ; consignes réécrites (tons, longueurs proportionnées, 3 approches alignées entre longueurs, pas de voix d'assistant, rien d'inventé) ; Moyen 6-70 mots, Long ≤ 140 (légère : dès 12 mots et 2 phrases).
- `instructions.py` : « Comprendre un message en contexte » (déclencheur d'abord, contre-indices, certain / probable / ambigu / inconnu, intention, habitudes ≠ situation, dernière décision, fils de groupe), taille quasi inchangée (+50 tokens).
- `reperes.py` : « et avant, c'était pareil ? » = évolution. `extraits.py` : `cree_le` des ajouts, jalons dans la sélection. `chat.py` : message visé transmis aux lots.
- Aucun changement Flutter, aucune migration, aucune nouvelle table, Docker de production non reconstruit.

### Évaluation (`backend/tests/scenarios_comprehension.py`, `evaluation_comprehension.py`)
- 12 situations sur les 5 exports fictifs.
- Déterministe (ce que le moteur prépare, même script sur l'ancienne version) : 41/64 → 62/64. Auteurs 6/11 → 11/11, suivis 0/5 → 5/5, clarification 0/1 → 1/1, chronologie 12/13 → 13/13, contexte récent 1/3 → 3/3, informations aux lots 0/8 → 8/8, sélection 11/11 → 11/11, budget 11/12 → 10/12.
- Réel GroqCloud (gpt-oss-120b), 6 scénarios avant / après + passe finale sur 4 :
  - même « je te pardonne pour cette fois » : avant, deux fois « boutade / humour » (ancienne blague du traitement citée) ; après, déception réelle apaisée (Lina) vs prolongement de la joute (Samuel), sans le traitement ;
  - réponse reçue après une réponse déclarée envoyée : avant, hors sujet (traitement, listes) ; après, scepticisme relié à la promesse, message cité ;
  - suivi ambigu en groupe : clarification en une phrase (avant : une liste de suppositions) ;
  - « Ok 👍 » : Long 47 → 26 mots en moyenne, Moyen 21 → 16, aucun nombre ni détail inventé (avant : « 12 h », « PDF », « pièce jointe ») ;
  - annonce grave : aucune plaisanterie avant comme après ; le souvenir inventé (« mon père était hospitalisé ») a disparu ; « condoléances » employé à tort une fois ;
  - diversité : approches distinctes 12/12 partout, similarité intra-combinaison moyenne 0,12-0,22.
- Jugements linguistiques : les miens sur 10 réponses et ~250 propositions ; pas une preuve statistique.

### Tests
- Backend : 563 réussis, 1 ignoré (24 nouveaux ; 3 anciens ajustés au nouveau comportement voulu : suivi « Pourquoi elle dit ça ? », formulation des ajouts, « oui » de Maya désormais correctement fourni). Image `backend-api` + pytest, pytest-asyncio, fakeredis[lua] (l'image `jarvis-tests` n'a pas `anthropic`).

### Limites
- Lots plus lourds (~+325 tokens chacun) : sur GroqCloud (8 000 tokens/min), l'ensemble « annonce grave » a fini 2 fois sur 2 « incomplet » (quota, Reprendre) alors qu'il était complet avant.
- Demandes d'aide : 350 à 650 tokens au-delà du budget réservé (plancher de 1 000 tokens de messages).
- Heuristiques lexicales (habitudes, jalons, gravité) en français ; habitudes encore parfois sur-invoquées par le modèle (« comme elle le fait souvent »).

### État
- Rien n'est commité ni poussé. Production (`jarvis-api`) inchangée : les modifications seront actives après reconstruction de l'image.

### Allègement des lots (même jour)
- `brief` avec lecture commune : 14 derniers messages au lieu de 24 (`DERNIERS_AVEC_LECTURE`), analyse limitée à 250 caractères. Par lot : 1 539 tokens estimés (d'origine 1 473, version précédente 1 798). Sans lecture (anciens ensembles) : inchangé.
- Tests : 563 réussis, 1 ignoré.
- Un essai réel GroqCloud « annonce grave » : ensemble COMPLET (36/36, 5 lots — le maximum —, 52,9 s, 7 918 + 2 900 tokens), aucune plaisanterie, aucun nombre inventé, Court 9,8 / Moyen 23,3 / Long 48,3 mots en moyenne.
- Défauts observés : la lecture commune du modèle (« proposer une alternative ») a été propagée à TOUS les lots, avec un contresens (« je peux prendre ta place à l'escalade ») ; la cohérence entre lots fonctionne, mais une mauvaise lecture se retrouve partout. Approches distinctes 10/12 (étiquettes répétées) ; une proposition identique dans deux tons (« Je suis désolé, comment va ton père ? »).

### Prochaine étape
- Essais sur appareil après déploiement ; si les ensembles restent à la limite des 5 lots, envisager une attente plus longue (`PROPOSITIONS_ATTENTE_MAX`) ; contrôle des doublons entre tons d'une même longueur.


## 2026-10-19 — Fiabilité de la compréhension partagée + déploiement sur jarvis-api

### Cause du contresens (« annonce grave »)
- La réponse principale avait écrit la lecture « proposer ton soutien ou une alternative » (et « le remplacer plus tard » pour dire reporter l'escalade). Les lots la recevaient comme « fixée, la même pour toutes les propositions », donc comme une consigne, et rien ne vérifiait les engagements proposés : 15 propositions sur 36 offraient de « prendre ta place ».

### Fait
- `app/comprehension/controle.py` (nouveau, sans IA) : `nettoyer_interpretation` avant les lots (lecture et analyse confrontées aux 10 derniers messages : initiative non justifiée, humour en situation grave, décision non écrite, citation / date / participant absents → retirés ; certitude → « probablement ») ; `Controle.examiner` après génération (engagement non justifié par les 8 derniers messages, la demande ou les réponses déclarées : remplacer, venir, promettre, appeler, rendez-vous ; date, heure ou jour inventés ; rire en situation grave). Doublons exacts entre tons refusés. Seule la combinaison concernée est redemandée, avec la raison (`Ensemble.refus`).
- Contexte des lots en trois blocs : FAITS / INTERPRÉTATION POSSIBLE (une piste, jamais une consigne) / INCONNU. Consignes : « l'utilisateur décide de ses engagements », situation grave sobre.
- Journaux du contrôle (raisons et volumes, jamais de contenu) et durées des lots.

### Tests
- Backend : 568 réussis, 1 ignoré (5 nouveaux tests du contrôle).
- Évaluation déterministe : 62/64 (référence avant optimisation : 41/64). Les deux échecs sont le dépassement de budget des demandes d'aide sur GroqCloud (plancher de 1 000 tokens de messages) : une limite du budget, pas un défaut de compréhension.
- Contrôle rejoué sur les 36 propositions fautives de l'essai précédent : 15 refusées (tous les remplacements, sauf une formule vague).

### Déploiement
- Point de restauration : image `backend-api:avant-comprehension` (`c0e5e6e302e3`). Retour arrière : `docker tag backend-api:avant-comprehension backend-api:latest` puis, depuis `backend/`, `docker compose up -d --no-deps api`.
- `docker compose up -d --build --no-deps api` : seul `jarvis-api` a été recréé (image `debb8cfe8ce3`) ; `jarvis-redis` et son volume n'ont pas été touchés ; même `.env` (production, `LLM_PROVIDER=anthropic`, routage par abonnement actif, ODO actif). Aucune migration.
- Vérifié : conteneur sain ; `/health`, `/health/ready` (Redis et Supabase ok) et `/health/clock` en 200 ; `/me`, `/me/quota` et `/api/v1/chat/stream` en 401 sans jeton ou avec un jeton invalide.
- Test fonctionnel avec le compte de test confirmé (Free → GroqCloud). La production n'accepte que les jetons Supabase asymétriques : le scénario a donc été exécuté DANS le processus de `jarvis-api` (application déployée, vrai Supabase, vrai Redis, vrai GroqCloud), avec la seule vérification du jeton remplacée. Étapes : contexte « Amitié » fictif (201), ajout de l'annonce (201), ciblage (`participant`, rang 783, `manual_received`), préparation 2,5 s, contrôle de la lecture 28 ms (rien à retirer), 3 lots en 37 s (14 refusées au format + 1 au contrôle : visite non justifiée), événements SSE `meta` / `preparation` / `propositions` / `done` et 7 battements, 36 identifiants distincts, persistance relue (mêmes 36 identifiants), « Reprendre » sur l'ensemble complet → 200 sans IA (0,8 s), quota du jour 12 619 tokens.
- Qualité : aucun remplacement, aucune plaisanterie, aucune date inventée, report de l'escalade fondé sur « Pas ce samedi » ; Court 7-14 mots, Moyen 13-29, Long 37-59. Réserves : quelques formules professionnelles un peu raides (« relais pour nos projets »), et une réponse principale réduite à « Voici quelques idées de réponse ».
- Non vérifié : la reprise d'un ensemble réellement incomplet sur le serveur réel (couverte par les tests simulés), la chronologie exacte des événements SSE vue par un client (le client en processus reçoit le flux d'un bloc), l'essai depuis l'appli sur téléphone.
- Conversation de test créée dans le compte de test : « [TEST FICTIF] Conversation de démonstration Samuel Petit » (`f5f9a7bb-…`), conservée.

### État
- Déployé sur `jarvis-api`. Rien n'est commité ni poussé.

### Prochaine étape
- Essai depuis l'appli (S10+) sur le même scénario ; commit sur accord.


## 2026-10-19 — Validation finale du module WhatsApp — Galaxy S10+

Appareil : Samsung Galaxy S10+ (SM-G975F, Android 12), `flutter run --profile` (`--dart-define-from-file=config_locale.json`, `JARVIS_API_URL=http://127.0.0.1:8000`), `adb reverse tcp:8000 tcp:8000`, backend principal `jarvis-api` uniquement, compte de test (Free → GroqCloud `openai/gpt-oss-120b`), authentification Supabase réelle (jeton de l'appli, aucun contournement). Pilotage par ADB (captures d'écran, touches) ; saisie ADB sans accents (« derniere reponse »).

### Validé sur appareil réel
- Démarrage : bloqué sur l'écran de lancement avec le Wi-Fi « ULC-Icam Students2 » (33 % de pertes vers Supabase, restauration de session sans réponse) ; normal après changement de réseau.
- Scénario C, annonce grave : ensemble réel (36/36) restauré depuis Supabase ; 4 tons × 3 longueurs ; changement de ton ou de longueur instantané, AUCUN appel au backend ; appui long → « Vous → Samuel Petit » en une bulle (PUT 200, sélecteurs masqués, sans doublon) ; menu `···` (Copier, Annuler le choix, date) ; annulation (DELETE 200) → propositions restaurées ; autre choix (n° 3) → persistant après fermeture et réouverture de l'appli. Aucune proposition de remplacement ni plaisanterie. (« Copier » : menu refermé, presse-papiers non lu.)
- Scénario A, Lina : import ZIP → filtrage (tout cocher, 96) → « Vous êtes : Alex Martin » → consigne. Question 1 : ciblage `participant, rang 95, export`, 2 références justes. Ajout manuel d'une réponse reçue (petit glissement → bouton révélé ; volet « Reçu, De : Lina Moreau » ; 201 ; bulle à gauche). Même question : ciblage `rang 96, manual_received` (le nouveau message, pas l'ancien « traitement »). Suivi « Pourquoi elle dit ça ? » (après correction) : même message visé, lien avec le reproche, prudence (« probablement »).
- Propositions en direct (« propose-moi trois réponses… ») : texte écrit progressivement puis « ••• Je prépare les propositions » pendant les lots ; défilement, clavier et PIM fluides. Génération 65 s (4 lots) → incomplète (contrôle trop strict, voir corrections) ; « Reprendre » (touché par un de mes gestes de défilement) → 4 lots, 24 s, 36/36 complet, enregistré.
- Scénario B, Projet Nova (4 792 messages) : « dernière réponse de Samuel » → ciblage `rang 4786` = « Calomnie !! … ok peut-être un peu » malgré les messages d'Alex, Lina et Nora après ; taquinerie de Lina correctement attribuée ; aucune confusion de participants.
- Actualisation : grand glissement → volet ouvert directement ; groupe : auteur à choisir ; message envoyé (201, bulle à droite « Vous → Projet Nova ») ; modification (PATCH 200, « corrigé ») ; suppression confirmée (DELETE 204) ; brouillon de la barre conservé ; conversation intacte.
- Non-régressions : menu latéral (chats classés sous WhatsApp), références cliquables (anciennes réponses), barre de saisie, PIM, retour Android (clavier puis sortie), authentification. Mode vocal non touché, non testé.

### Défauts trouvés et corrigés (déployés)
1. Réponses avec étiquettes en gras (« **Faits** », « **Indices** », « **Ambiguïté** ») — induites par la consigne qui citait ces mots — habitude inventée (« "je te pardonne" souvent utilisé par elle »), « clairement humoristique » : instructions reformulées (phrases ordinaires, aucune étiquette ni gras, pas de « clairement » sur un ton, habitude seulement si l'aperçu ou plusieurs messages la montrent). Vérifié sur le S10+ : plus d'étiquettes.
2. Contrôle trop strict : « Promis, je te préviendrai » refusé alors que Lina reproche « tu aurais pu me prévenir » (6 refus → ensemble incomplet). Un reproche justifie désormais une promesse simple ; une promesse absolue (« plus jamais », « ça n'arrivera plus ») reste à justifier.
3. Initiatives inventées non détectées : sorties (« un verre / un café ce soir ? », « on en parle ce soir »), organisation (« j'instaure un système de rappel »), excuse inventée (« j'étais pris dans le travail ») → nouvelles familles dans `controle.py` (11 des 36 propositions réelles de Lina seraient désormais refusées, les bonnes gardées) ; consignes des lots : pas d'excuse non écrite, Taquin non théâtral, Professionnel sans procédure, accords corrects.
4. Demande de l'utilisateur : les cartes « Messages d'origine » encombraient chaque réponse → affichées SEULEMENT si la question les demande (`reperes.demande_sources` : « montre-moi », « où est-ce qu'elle a dit ça ? », « pourquoi tu dis ça ? », « sur quoi tu te bases ? »…). Sinon enregistrées `masquee: true` (jamais renvoyées par `GET /references`, toujours utilisées pour « pourquoi tu dis ça ? »). Vérifié sur le S10+ (3 puis 1 référence masquées). Les réponses enregistrées avant gardent leurs cartes.

### Validé par tests automatisés
- Backend : 571 réussis, 1 ignoré (8 tests de références adaptés : leurs questions demandent maintenant les messages ; nouveaux tests : masquage, promesse justifiée par un reproche, sorties, organisation, excuse, instructions sans étiquettes). Image `backend-api` + pytest, pytest-asyncio, fakeredis[lua].
- Flutter : aucun fichier Flutter modifié ; suite non relancée.

### Délais et consommation (GroqCloud réel, compte de test, 2026-10-19)
- Analyse : préparation 2,4-6,7 s (groupe), premier fragment 2,1-3,8 s, réponse 2,4-4,4 s, enregistrement 0,3-0,6 s.
- Génération des propositions : 65 s (4 lots, incomplète) + reprise 24 s ; contrôle de la compréhension 5 ms.
- Tokens du compte ce jour : 48 132 / 50 000 avant les deux derniers essais ; exception temporaire (75 000) posée pour le suivi et le groupe, puis retirée (retour à `limits_override=false`, 150 messages, 50 000 tokens).

### Déploiement
- `jarvis-api` reconstruit une fois (`docker compose up -d --build --no-deps api`) : image `04754e448bc0` ; points de restauration `backend-api:avant-validation-s10` (`debb8cfe8ce3`) et `backend-api:avant-comprehension` (`c0e5e6e302e3`). `jarvis-redis` et ses données intacts. `/health`, `/health/ready` (Redis, Supabase ok) 200 ; routes protégées 401 sans jeton.
- Attention : l'image a été construite depuis l'arbre de travail, qui contenait aussi un travail vocal NON commité d'une autre session (interruption de la réponse : `ChatRequest.interruption`, `note_interruption` dans `chat.py`, `test_vision.py`, fichiers Flutter / Kotlin du vocal). Il est donc en service sur `jarvis-api` (suite backend complète réussie avec lui), mais il n'est pas dans le commit de cette validation ; l'APK installé sur le S10+ le contenait aussi.

### Non testé
- Mode vocal ; « Copier » vérifié dans le presse-papiers ; génération complète de 36 propositions APRÈS les corrections 2-3 (quota épuisé ; contrôle rejoué sur les propositions réelles, déterministe) ; Windows / Web.

### Limites restantes
- Le modèle parle parfois de l'utilisateur à la 3ᵉ personne (« Alex ») et rattache encore une ancienne blague ; formulations Taquin parfois forcées.
- Les sorties et excuses inventées sont filtrées par motifs lexicaux : une formulation nouvelle peut passer.
- Une restauration de session Supabase sans délai d'attente laisse l'appli sur l'écran de lancement quand le réseau est mauvais.

## 2026-10-19 — Voix en flux, interruption en un toucher, continuité

### Fait
- **Lecture en flux** (`LectureEnFlux`) : phrases complètes dites pendant la réception, réserve adaptative (2 phrases / ~140 caractères / 1 phrase après 1,8 s), jamais de fragment ni de répétition ; réponse arrivée avant le début de la lecture : dite d'un seul tenant (comme avant).
- **Réseau** : lent → lecture des phrases prêtes puis attente ; coupé → phrases complètes terminées, bout inachevé jamais lu, phrase discrète ; aucune reprise depuis le début.
- **Interruption en un toucher** (« Arrêter la parole », vocal principal et JARVIS Touch) : voix coupée, file vidée, ancien tour neutralisé, génération arrêtée, écoute aussitôt (plus de bouton « Parler »).
- **Continuité** : ce que l'utilisateur a réellement entendu part avec la question suivante (même conversation, une fois) ; le serveur demande de répondre dans le même sujet sans reprendre l'explication (sauf « continue »). Aucun appel en double ; message coupé marqué « Interrompue par vous. ».
- **Interruption automatique** : détecteur natif expérimental (micro VOICE_COMMUNICATION + AEC + réduction de bruit, énergie durable + structure vocale, jamais un simple pic) en **mode mesure seulement** ; réglage « Automatique · bientôt » toujours indisponible.
- Backend en production mis à jour (image précédente : `backend-api:avant-interruption`).

### Tests
- Flutter : 843 réussis (nouveaux : `lecture_en_flux_test` 7, `arret_parole_test` 3, `interruption_conversation_test` 1). Backend : 569 réussis, 1 ignoré (note d'interruption, seulement dans la même conversation).

### Mesures S10+ (réelles, peu nombreuses)
- Début de la voix : 1 329 à 1 475 ms après la question (GroqCloud : réponse souvent entière avant le début → lue d'un bloc).
- Détection, AEC et NS disponibles : voix de JARVIS seule, 2 séances (≈ 12,7 s) → 0 fausse détection, mais écho résiduel jusqu'à **11,5 dB** au-dessus du fond ; intervention (voix du PC, à distance) → **manquée** (6,3 dB). Les deux distributions se recouvrent : **non fiable en l'état**, mode automatique indisponible.

### Non testé / limites
- Interruption en un toucher et continuité **non essayées sur le téléphone** (essais à voix haute arrêtés : l'utilisateur était en cours ; le micro a capté des phrases de la salle, enregistrées dans la conversation). Couvertes par les tests automatisés.
- Limite quotidienne de tokens (Free) atteinte pendant les essais : les derniers échanges n'ont reçu que le message de limite.
- Écouteurs, bruit ambiant, voix humaine proche du téléphone : non mesurés.


## 2026-10-19 — Gmail phase 1 : campagne de validation (incomplète)

### Résultats
- Flutter : **843 réussis, 0 échec** (suite complète).
- Backend : **576 réussis, 1 ignoré** (dont 5 nouveaux cas de masquage sur les 4 chemins de lecture).
- Masquage renforcé : codes en deux groupes (« 482 913 », « 482-913 »), « código », codes collés à un mot (« code_482913.pdf »), noms de pièces jointes filtrés.
- Masquage sur la VRAIE boîte (script serveur, compteurs seulement) : 10 messages, 6 liens sensibles avant → 0 après, sur recherche, message, fil et résumé ; aucun code de vérification présent dans ces messages (règle des codes vérifiée par les tests seulement).
- Mesures réelles disponibles (Claude, 2026-10-18, instance 8002) : 2 tours, ~11 s, 1 appel d'outil, premier outil après 3,1-3,7 s, 7 583 / 9 697 tokens, 3 / 11 requêtes Gmail.

### Non vérifié
- Comportements réels sur le S10+ (demande indirecte, contexte, clarification, reprise, aucun résultat) : bloqués par la limite quotidienne du compte (offre Free en base : 50 000 tokens/jour, 61 996 consommés le 19/10). Instance 8002 (GroqCloud pour tous) arrêtée et supprimée ; production 8000 intacte.

### Prochaine étape
- Après 01:00 : relancer l'instance 8002 (GroqCloud) et les 6 essais guidés ; Claude seulement avec accord.

## 2026-10-20 — Apparence : thèmes et motifs de l'application « Jarvis » d'une amie

### Fait
- Audit de `Jarvis_projet_complet.zip` (application web Capacitor, tout dans
  `www/index.html`) : 6 thèmes en variables CSS (`data-jt`, `localStorage
  jarvis:theme`), motifs kuba (`kgrid`, `kband`, tissu `kubaFill` de
  `love.html`, orbe « Cœur Kuba »), contours 2 px + ombres pleines décalées,
  police Baloo 2 (OFL). Rien d'autre de l'application n'est repris.
- Architecture : `PaletteJarvis` (ThemeExtension), registre `StyleVisuel`
  (JARVIS original + Congotronics, Raphia Kuba, Fleuve, La Sape, Rumba,
  Léopards ; jetons exacts pour la variante d'origine, autre variante créée),
  registre `MotifJarvis` (Sans motif, Aurore JARVIS, Kuba 1 · Losanges,
  Kuba 2 · Tissu, Kuba 3 · Frises, Cœur Kuba), `ServiceApparence`
  (préférences JSON versionnées, clé `jarvis.apparence`, lecture tolérante,
  mode Système), `TransitionApparence` (fondu 320 ms, reconstruction unique).
  `CouleursJarvis` devient une façade de la palette active (≈ 230 `const`
  retirés automatiquement, aucune autre modification de comportement).
- Paramètres : « Apparence » quitte la liste principale →
  Général › Apparence › Thèmes (Clair / Sombre / Système + 7 styles avec
  aperçus) / Motifs (aperçus réels, intensité, « Revenir au précédent » à
  place réservée).
- Bulles et cartes : contour marqué, ombre pleine décalée, frise kuba
  (styles importés) ; JARVIS original inchangé au pixel près (captures
  avant / après identiques hors horodatage).
- PIM : non touché (demande explicite), ni couleurs ni algorithmes.
- Icône de l'application (lanceur Android + adaptative, iOS, Web, Windows)
  = icône de l'application fournie ; l'intérieur de l'application garde la
  perle JARVIS (logo du menu : plus de requête 404 vers `jarvis.png`).
- Corrigé au passage : outil `capture_conversation_test` (attend la fin de
  l'écriture progressive), dépréciation `axisAlignment`, remarques
  d'analyse des tests.

### Vérifié
- `dart analyze lib test tool` : aucun problème. Tests : suite complète
  (dont `test/apparence_test.dart`, 17 tests, contrastes des 14 palettes).
- Galaxy S10+ (flutter run), Windows (flutter run), Web (port 3000) :
  changement de style et de mode, restauration au redémarrage, icône.
- iOS : non compilé (pas d'environnement macOS) ; icônes générées seulement.

### Prochaine étape
- Valider à l'usage la lisibilité de PIM (couleurs d'origine) sur les fonds
  sombres ; option future si souhaité : teinte PIM par style.

## 2026-10-20 — Gmail phase 1 : validation réelle sur le S10+ (GroqCloud)

Instance temporaire 8002 (GroqCloud pour tous, ODO actif, Redis base 3), vraie boîte Gmail, saisie par adb ; production 8000 non touchée ; 8002 arrêtée et supprimée à la fin.

| Essai | Résultat | Mesures |
|---|---|---|
| Demande vague (« reçu quelque chose d'important cette semaine ? ») | recherche lancée seule, réponse avec les messages trouvés | 2 tours, 5,7 s, 1 outil, 1er outil 1,4 s, 3 757 tokens, 3 requêtes Gmail |
| Demande indirecte (« le mail concernant mon inscription ») | rien de clairement lié → le dit, question de précision | 2 tours, 4,3 s, 11 requêtes |
| Reprise après précision (« C'est pour l'ICAM ») | demande initiale reprise sans répétition | 2 tours, 4,5 s |
| Aucun résultat (Rodrigue, semaine dernière) | « aucun message dans les échanges de la semaine dernière » + propose d'élargir | 2 tours, 3,3 s, 1 requête |
| Contexte (« Oui élargis, regarde ce que je lui ai envoyé ») | nom repris du contexte, envoi + échec de livraison retrouvés, explication juste | 3 tours, 6,3 s, 2 outils, 5 requêtes |
| Ambiguïté (« Le professeur m'a répondu ? ») | cherche d'abord (recherche possible), rien → demande le nom, propose d'élargir | 2 tours, 3,6 s, 2 requêtes |

- **Défauts trouvés et corrigés** : période ajoutée d'office (30 jours, puis 3 mois malgré « peu importe la date ») et adresse inventée « par exemple ». Consigne et description de `periode` corrigées ; essai refait : recherche sur toute la boîte, aucune adresse inventée (3 tours, 5,6 s, 11 requêtes).
- **GroqCloud** : limite de débit (8 000 tokens/min) atteinte une fois après des essais rapprochés → message « Le service IA est très sollicité », réussite après 1 min.
- **Claude** : pas de nouvel essai (payant, sans accord) ; mesures réelles du 18/10 seulement.
- Consommation du compte (Free, 100 000 tokens/jour) : 8 messages, 49 063 tokens.
- Tests : backend 576 réussis, 1 ignoré ; Flutter 843 réussis (19/10, aucun changement Flutter depuis dans ce chantier).

### Reste pour la phase 2
- Juger la pertinence sur le CONTENU (le lien ICAM ↔ inscription n'est qu'une hypothèse prudente) ; « important » au sens de l'utilisateur (aujourd'hui : libellé Gmail et extraits).
- Cas « plusieurs professeurs » non rencontré dans la vraie boîte (vérifié par les tests seulement).

## 2026-10-20 — Refonte UI/UX des Paramètres

### Fait
- Paramètres › Apparence en accès direct (plus de détour par Général) ;
  liste du téléphone repensée : 3 groupes, icônes en pastilles alignées,
  lignes de 56 px, aucune description, compte en bas.
- Apparence sur une seule page : mode (sélecteur segmenté), carrousel des
  styles et carrousel des motifs (PageView, accrochage, carte suivante
  visible, sélection directe, glissement souris / pavé tactile, flèches sur
  grand écran), intensité sous les motifs, « Revenir » sans décalage.
- Chat vocal compact : Voix (profils en grille, langue, voix + aperçu ▶),
  Expression, Écoute, Options avancées repliées (interruption ;
  « Automatique · bientôt » non choisissable).
- Particules PIM : grille 2 × 2 centrée verticalement (défilement si la
  place manque), tuiles agrandies.
- Navigation : la croix ferme tous les Paramètres d'un coup (`pop`, plus
  `maybePop` intercepté par le retour d'un niveau) ; flèche et retour
  d'Android : un niveau.

### Vérifié
- `dart analyze` : aucun problème ; tests : 866 / 866 (nouveaux : accès
  direct, flèche / croix / retour Android sur 5 sections, croix sur
  ordinateur, centrage PIM, carrousels indépendants, intensité, grand
  écran).
- Galaxy S10+ : liste, Apparence (glissement, choix, préférences
  restaurées), croix → accueil.

### Prochaine étape
- Vérifier au doigt la page Chat vocal et le mode paysage sur le S10+.

## 2026-10-20 — Gmail, phase 2 sur 3 : compréhension approfondie des e-mails

### Audit (avant)
- Texte cité des anciens messages mêlé au nouveau (« Le … a écrit : », « > ») : une ancienne information pouvait passer pour nouvelle ; fils pleins de citations répétées.
- Dates brutes dans le fuseau de l'EXPÉDITEUR (vu en réel : « 02 h 03 heure PDT ») ; `gmail_preparer_resume` dans l'ordre choisi par le modèle.
- Consigne muette sur : reçu ≠ accepté, réserve, refus poli, obligation ≠ suggestion, correction / report, pièces jointes non lues, importance hors libellé Gmail.
- E-mails LUS non mémorisés pour les questions de suivi.

### Fait
- `app/odo/gmail_lecture.py` (sans IA, Free = Pro) : texte nouveau / cité / transféré (FR, EN, DE, ES, Outlook, « > »), dates dans l'heure de l'utilisateur, ordre chronologique sans doublon (« le plus récent »), repères multilingues présentés comme indices, pièces jointes « contenu NON lu », expéditeur automatique.
- `gmail_lire_message`, `gmail_lire_fil`, `gmail_preparer_resume` branchés dessus ; recherche : libellé Gmail nommé comme tel + repères de l'extrait.
- Consigne de compréhension (fait / déduction / inconnu en phrases naturelles, sans étiquettes ; date non écrite jamais ajoutée ; relecture par id pour les suivis ; langue de l'utilisateur).
- Mémoire du chat : e-mails LUS (métadonnées, 6, 1 h) redonnés aux questions suivantes.
- Doc : GMAIL.md § Compréhension approfondie + limites du masquage.

### Tests
- Backend : **613 réussis, 1 ignoré** (`test_gmail_comprehension.py` : dossier transmis pour 18 scénarios fictifs, citations, transfert, dates, ordre, repères multilingues, suivi Free / Pro simulés, isolation).
- Évaluation RÉELLE GroqCloud (`tests/evaluation_gmail.py`, corpus fictif `scenarios_gmail.py`, 17 scénarios notés + 1 déterministe) :
  - avant (phase 1) : 16/17 (heures dans le fuseau de l'expéditeur) ;
  - après, 1re consigne : 15/17 (étiquettes « Faits / Interprétation », date « 16 octobre » ajoutée) → consigne corrigée ;
  - après, consigne corrigée : **17/17**.
- Coût : 1 224 → 1 765 tokens par appel en moyenne (+44 %, surtout la consigne) ; latence 1,48 → 1,68 s ; aucun appel IA ajouté.
- Claude : non essayé (payant, accord requis). Aucun vrai e-mail utilisé. Production 8000 inchangée, aucune instance temporaire en marche.

### Prochaine étape
- Évaluation Claude autorisée par l'utilisateur, mais IMPOSSIBLE : le compte API Anthropic a atteint la limite d'utilisation fixée par son propriétaire (« You have reached your specified API usage limits », retour le 2026-11-01 00:00 UTC). 3 appels refusés, rien consommé, évaluation arrêtée. Conséquence : en production, les comptes Pro (Claude) reçoivent une erreur « service indisponible » jusqu'à cette date.
- Relancer `evaluation_gmail.py --fournisseur anthropic` après le 1er novembre (ou après relèvement de la limite) ; essai réel S10+ sur la boîte de l'utilisateur avec son accord.
- Phase 3 : résumés et réduction des tokens (la consigne Gmail est la première cible).

## 2026-10-20 — Module Apprendre (Kelasi), phase 1 : interface, moteur hors ligne, progression

### Fait
- Menu latéral › **Apprendre** (interrupteur local `JARVIS_APPRENTISSAGE`, actif par défaut). Accueil : carte « Continuer », Parcours / Pratiquer / Réviser, quatre parcours (Correspondance, Communication, Relations et respect, Termes techniques) avec barre et pourcentage réels.
- Parcours → unités → leçons (à commencer, en cours, terminée ; reprendre, recommencer, revoir, refaire ; aucun blocage).
- Moteur de leçon hors ligne réutilisable (`SeanceLecon`) : introduction (objectif, fiches, exemples, à éviter, sources), 7 types d'exercices (choix, vrai/faux, trous, ordre, association, meilleur message, écoute avec repli texte), correction immédiate, réessayer, retour en fin de séance, résultat (acquis / à retravailler, Réviser).
- Corpus JSON local (schéma 1, 27 Ko) : une leçon complète par parcours (6-7 exercices), 9 fiches, toutes `brouillon` ; validation tolérante ; publication des seules fiches validées (aperçu des brouillons en debug / profile uniquement). Sources réellement consultées le 2026-10-20 : `docs/APPRENTISSAGE_SOURCES.md`.
- Progression locale versionnée : écritures regroupées, forcées en fin de leçon / arrière-plan / sortie ; copie de secours et copie de la valeur corrompue (jamais d'effacement silencieux).
- Doc : `docs/APPRENTISSAGE.md`. Aucune dépendance ajoutée, aucun backend, aucune IA, aucun avatar.

### Vérifié
- `flutter analyze` : aucun problème. Tests : **909 / 909** (dont 42 du module : corpus, moteur, progression, interface ; + menu / PIM dans menu_lateral_test).
- Galaxy S10+ (profile, vrai backend `jarvis-api` via `adb reverse`) : module, parcours, leçon, correction, reprise après redémarrage, retour au chat.
- Mesures S10+ : premier rendu au démarrage 1 113 ms avant / 1 113 ms après (3 mesures chacun) ; APK release arm64 22 716 114 → 22 923 134 octets (+202 Ko) ; ouverture du module 52-56 ms (données 13-23 ms) ; ouverture d'une leçon 16 ms ; exercices : rendu 4,4 ms en moyenne (max 8), interface 1,8 ms ; PIM : 0 image calculée pendant le module ; retour au chat : 314 images / 5 s, rendu 16,1 ms = chat au repos ; mémoire ≈ 430 Mo RSS (428 Mo avant ouverture).
- Défauts trouvés et corrigés : toucher qui désélectionnait dans « Associer », débordement de la carte de leçon à 320 px, titres centrés à tort, « ? » isolé en début de ligne.

### Limites / à valider
- Validation humaine des 9 fiches (inventaire des sources) avant toute publication en release.
- Transition d'ouverture : quelques images à 20-36 ms (accueil PIM + module dessinés ensemble pendant le fondu) ; le chat au repos est déjà proche de 16 ms (PIM), indépendant du module.
- Écoute : voix de JARVIS (même moteur que l'aperçu) ; fonctionnement hors réseau non vérifié sur l'appareil (dépend de la voix installée), texte toujours disponible.
- Progression par appareil (pas par compte), pas de synchronisation.

### Prochaine étape
- Relecture / validation des fiches ; phase 2 (IA) seulement après accord.

## 2026-10-20 — Fonds photo (général et par conversation) et deux motifs

### Fait
- Motifs « Kuba 4 · Velours » et « Kuba 5 · Labyrinthe » (vrais dessins,
  cases hors écran ignorées) ; tous les anciens gardés.
- Carte « Ma galerie » en fin de carrousel des motifs : choisir une photo,
  la réactiver, ou l'ajuster ; photo active → « Ajuster la photo » /
  « Changer de photo » à la place de l'Intensité (réservée aux motifs).
- Éditeur plein écran (`pages/editeur_fond_page.dart`) : aperçu à la vraie
  taille de l'écran (réduit), conversation de démonstration, glisser /
  pincer / double toucher, visibilité, flou, assombrissement, Annuler /
  Réinitialiser / Appliquer.
- Fond par conversation : « Personnaliser le fond » dans le menu d'une
  conversation (fond général, motif, photo, modifier) ; règle :
  conversation → général → JARVIS.
- Stockage local : fichiers du support de l'application (path_provider,
  ajouté) ou IndexedDB (Web) ; préférences = identifiants et réglages
  seulement ; photos inutilisées supprimées.
- Rendu : photo décodée réduite, composée UNE fois (cadrage, flou,
  assombrissement) puis copiée ; PIM inchangé au-dessus.

### Vérifié
- Analyse : aucun problème ; tests : 922 / 922 (dont `test/fonds_test.dart`).
- Captures : fond photo derrière une conversation (bulles lisibles, PIM
  au-dessus), éditeur, « Ma galerie », nouveaux motifs.
- S10+ : carte « Ma galerie », sélecteur, éditeur (flou en direct),
  Appliquer.

### Reste à vérifier
- S10+ : fond photo sur l'accueil, fond d'une conversation (le téléphone
  était sans Internet : liste vide), redémarrage.

## 2026-10-20 — Kelasi, phase 2 étape A : sources, sauvegarde, transition

### Fait
- Sources : 9 fiches auditées ; Wikipédia et l'ouvrage non consulté retirés ; remplacés par 4 pages BDL (OQLF), 6 fiches GDT (OQLF), la fiche outil « L'écoute active » (académie de Lille), le document CNV du CIUSSS de l'Est-de-l'Île-de-Montréal (non daté, non signé). Corrigés : « Je comprends… » (déconseillé par la source), origine Gordon/Rogers, définition du système d'exploitation. Inventaire : `docs/APPRENTISSAGE_SOURCES.md` ; relecture : `docs/validation_apprentissage/RELECTURE.md`.
- Publication : une fiche `valide` exige une relecture tracée (`validation.par`, `validation.le`) ; aperçu des brouillons impossible en release, même en mémoire. 9 fiches toujours `brouillon`.
- Sauvegarde : réponses et étapes de séance écrites aussitôt (navigation toujours regroupée).
- Transition vers Apprendre (Codex) : fondu court 180 ms, PIM suspendu (`TickerMode`) jusqu'à la fin du retour ; variantes de mesure `ext.jarvis.variante`, outil `tool/mesure_kelasi.py`.

### Vérifié
- `flutter analyze` : aucun problème ; tests : 932 / 932.
- S10+ hors ligne : relance à froid, contenus, sources, corrections, révision, reprise, écoute avec la voix Samsung locale et « Voir le texte ». `force-stop` 0,3 s après « Continuer » : avant 3 / 8 (étape perdue), après 4 / 8.
- S10+, A/B alterné ×5 (profile) : ouverture 45 → 20 images hors budget au total, pire rendu 32,1 → 22,6 ms, images PIM pendant l'ouverture ≈ 27 → 1 ; retour au chat sans gain net (médiane 2-3) ; le chat au repos dépasse déjà le budget par moments (PIM). RSS 416 → 438 Mo sur la série.

### En attente
- Relecture humaine des 9 fiches (rien n'est publié en release).
- Saccade réduite, pas supprimée.

## 2026-10-20 (soir) — Gmail phase 2 : finalisation et validation

- État retrouvé : phase 2 déjà commitée et poussée (`79cfdbf`) ; aucun fichier Gmail / backend modifié depuis ; modifications non commitées = autres chantiers (Apparence, fonds photo, Apprendre), non touchées.
- Docker Desktop était arrêté (production 8000 hors service, sans lien avec Gmail) : relancé, `jarvis-redis` et `jarvis-api` redémarrés à l'identique avec l'accord de l'utilisateur, `/health/ready` ok.
- Tests : backend **613 réussis, 1 ignoré** (Gmail phases 1-2 : 87, ODO + chat : 46, vocal : 3) ; Flutter **932 réussis, 0 échec**.
- GroqCloud réel (corpus fictif) : 17/17 (passage du 20/10), 16/17 (passage du soir : rubriques « Faits / Interprétation » sur le scénario 14), 6/6 sur les scénarios 07 et 14 répétés. Défaut de format intermittent (≈ 1 réponse sur 34) → phase 3.
- Critères corrigés (fausses alertes prouvées par les réponses) : 07 accepte « aucune confirmation » / « en attente » ; 14 reconnaît « aucune réponse urgente ». Règle « pas d'étiquettes » inchangée.
- Claude : nouvelle clé API mise dans `backend/.env` par l'utilisateur ; UN message de test « salut » → réponse correcte (`claude-opus-5-5`, 37 tokens, 2,6 s). Décision de l'utilisateur : évaluation de compréhension sur GroqCloud seulement.
- Production : `jarvis-api` recréé avec l'accord de l'utilisateur (même image `04754e448bc0`, sans reconstruction, Redis intact) : nouvelle clé Anthropic chargée (106 caractères), `/health/ready` ok, routage actif, ODO actif, Gmail configuré.
- Tokens : ≈ 1 650-2 050 par appel (référence pour la phase 3 ; avant phase 2 ≈ 1 100-1 440) ; latence 0,9-1,9 s par appel.
- Verdict : phase 2 validée (GroqCloud réel + Claude joignable) ; compréhension Claude non évaluée par choix.

## 2026-10-29 — Session AB (optimisations 1 à 13) : audit mesuré, corrections ciblées

### Fait
- Démarrage : Supabase et l'apparence chargés en parallèle avant le premier écran (`main.dart`) ; sondes `demarrage.avant_premier_ecran` / `demarrage.premiere_image` (JARVIS_PERF seulement).
- Backend (`chat.py`, NON déployé) : historique (Redis/Supabase) et pièces jointes lus en parallèle après le contrôle de propriété (une requête Supabase de moins sur le chemin critique) ; nouveau journal « Durée : préparation du chat » (part serveur séparée du « premier fragment » fournisseur).
- Fil : clés des messages élaguées au changement de conversation (elles s'accumulaient pour toutes les conversations ouvertes).
- Banc `tool/banc_conversation.dart` (page réelle, 60 échanges) : défilement, écriture en flux, frappe, ouverture A↔B ; variantes alternées dans le même lancement (`JARVIS_VARIANTES`, `JARVIS_TOURS`) ; sondes `fil.fondu`, `bulle.ombre` (+ `pim.*` existantes), inactives hors banc.

### Audit (déjà optimisé, rien changé)
- Streaming : une seule notification au premier fragment, puis seul `TexteProgressif` se repeint (Ticker actif seulement si du texte attend). Accueil : la frappe en conversation ne reconstruit pas la page ; barre G7 : animation seule. Ouverture d'une conversation déjà ouverte : synchrone depuis la mémoire, synchro silencieuse ensuite. Menu : listes paresseuses. Import WhatsApp : lecture par paquets + ZIP dans un isolate. Contrôleurs : tous libérés. Limites du compte : cache Redis (pas de double lecture Supabase).

### Mesures (Windows profile, GPU Intel intégré, 1920×1200 ; A/B alterné ×3, médianes)
- Retirer le fondu du fil, les ombres des bulles ou le dessin de PIM : aucun gain mesurable (ex. écriture raster p50 22,7 / 19,6 / 21,0 ms ; ouverture 38 / 38 / 41 ms ; sans PIM : frappe raster p50 10,8 → 10,9 ms). Rendu gardé à l'identique.
- Variance entre lancements ±50 % (fenêtre masquée = plus d'images) : seules les mesures alternées comptent.
- Ouverture d'une conversation déjà chargée : p50 27-41 ms selon le lancement.
- Web profile + Render réel (compte connecté) : avant premier écran 15,5 ms, première image 530 ms ; réponse courte à chaud : premier fragment 3,4 s, totale 3,8 s (à froid 6,2 / 7,1 s) ; pendant le flux raster moyen 4,5 ms, 3 images hors budget / 558.

### À faire sur le S10+ (non testé)
- `flutter run --profile -t tool/banc_conversation.dart --dart-define=JARVIS_PERF=true --dart-define=JARVIS_TOURS=3 "--dart-define=JARVIS_VARIANTES=fil.fondu;bulle.ombre"` ; puis timeline DevTools sur la frappe multiligne (pics raster quand la barre change de hauteur et que le fil se recompose).
- Démarrage à froid (`[PERF] demarrage`), clavier Samsung (G7), ouverture depuis le menu.
- Après déploiement autorisé du backend : comparer « Durée : préparation du chat » et « premier fragment » dans les journaux Render.

## 2026-10-30 — Session CD (optimisations 14 à 29) : audit ciblé

### Constat (code déjà optimisé, rien changé sans gain démontré)
- 14 / 17 : fil paresseux (seules les bulles visibles sont construites), streaming = une seule notification puis `TexteProgressif` seul. Banc (Windows profile) 120 → 600 messages : défilement raster p50 19,9 → 20,6 ms, ouverture 23 → 28 ms, mémoire 803 → 791 Mo (une série chacune : écarts dans le bruit). `JARVIS_ECHANGES` ajouté au banc.
- 16 / 8 : conversation déjà ouverte = rouverte depuis la mémoire, synchro silencieuse ensuite.
- 20 : chemin critique = animation de lancement voulue (3,2 s + transition 0,7 s) ; session restaurée en parallèle derrière. Avant premier écran : 10,6-15,5 ms (Web).
- 21 / 24 : minuteries bornées (décroissance vocale = session active ; utilisation 30 s seulement écran visible ; Gmail seulement en attente d'OAuth) ; resynchro seulement après ≥ 30 s masqué.
- 22 : coupure = texte reçu gardé + incident, « Réessayer » sans doublon (UUID), brouillons G7 en mémoire.
- 23 : `ChronoPerf` inactif hors `JARVIS_PERF` ; seuls journaux avec texte dicté : `kDebugMode`.
- 25 / 29 : bulle Touch au repos 3 s après interaction (animation coupée), libérée à la fermeture ; niveau vocal regroupé à 60 ms, état envoyé seulement s'il change ; bitmaps recyclés.
- 26 : minuteries vocales annulées à chaque arrêt / erreur / dispose.
- 27 / 28 : vignettes décodées réduites (`ResizeImage`, `cacheWidth`), import WhatsApp en flux, capture lue une fois.

### Décisions de l'utilisateur, appliquées
- Envoi immédiat : la question écrite part au serveur sans attendre `delaiReflexion` (450 ms) ; ce délai ne retarde plus que l'affichage d'une réponse locale. Fil changé juste après l'envoi : une seule demande, réponse rangée dans sa conversation (comme une réponse tardive). Gain ≈ 0,45 s par construction ; Web + Render, réponses courtes à chaud : totale 3,3-4,3 s après contre 3,8-5,8 s avant (variance du fournisseur dominante).
- Écran de lancement : un appui passe l'animation (suite demandée une seule fois, session vérifiée comme avant). Vérifié sur le Web réel.
- Tests : `conversation_ia_test` adapté, `ecran_de_lancement_test` ajouté ; suite complète 973 / 973, analyse propre.

### Campagne Android unique (S10+, non faite)
- Banc : `flutter run --profile -t tool/banc_conversation.dart --dart-define=JARVIS_PERF=true --dart-define=JARVIS_TOURS=3 "--dart-define=JARVIS_VARIANTES=fil.fondu;bulle.ombre"` (+ `JARVIS_ECHANGES=300`) ; timeline DevTools sur la frappe multiligne.
- Démarrage à froid (`[PERF] demarrage`), clavier Samsung (G7), PIM réel, session de 30 min (mémoire `dumpsys meminfo`, température, batterie).
- Cycle de vie : verrouillage, changement d'appli, retour ; chat vocal en arrière-plan ; micro / haut-parleur / Bluetooth / écho.
- JARVIS Touch : bulle (repos 3 s), mini-chat, vocal flottant, capture (accessibilité + MediaProjection), recadrage, envoi d'une capture, canaux `jarvis/touch*`.

## 2026-10-30 — Session EF (optimisations 30 à 40)

### Complément CD
- 15 (ressources selon l'activité) : déjà optimisée. Aucune tâche secondaire pendant la saisie ni le défilement ; synchronisation seulement sur événement (connexion, menu, échange, retour au premier plan ≥ 30 s) ; utilisation relue toutes les 30 s seulement écran visible.

### Fait
- 31 Recherche du menu : titre + aperçu normalisés mis en cache par aperçu (`Expando`, aperçus immuables) et passage rapide ASCII. 2 000 conversations : 11,4 → 3,3 ms par frappe (VM de test, premier remplissage compris). Toujours le texte actuel, aucun réseau. Test `recherche_conversations_test`.
- 39 Erreurs : `ErreursJarvis` (installé dans `main`) ; hors debug, journal = module + TYPE d'erreur, jamais le message (texte de conversation, e-mail possibles) ; erreur asynchrone marquée traitée ; debug inchangé. Test `erreurs_jarvis_test` (y compris : un widget en panne ne remplace que lui-même).

### Déjà en place (vérifié, rien changé)
- 30 Stockage : petites valeurs `SharedPreferences`, écrites seulement sur changement (utilisation : après une lecture réussie, ≤ 1 / 30 s écran ouvert) ; brouillons en mémoire ; aucune base locale à indexer.
- 32 Résultats périmés : chargement d'une conversation vérifié par génération + identifiant ; état « chargement » propre à la conversation affichée ; réponse IA rangée dans sa conversation d'origine.
- 33 Doublons : champ vidé avant l'envoi (G7) ; UUID idempotents (échanges locaux, pièces jointes, « Réessayer ») ; un seul choix « envoyée » par ensemble (SQL verrouillé).
- 34 Synchro : Supabase source de vérité, correspondance locale ↔ UUID, conversation supprimée ailleurs signalée ; aucun cache d'un autre compte (utilisation rattachée au compte, effacée à la déconnexion).
- 35 Sessions : renouvellements simultanés partagés (`_renouvellement ??=`), durée de vie mesurée sans l'heure de l'appareil, jetons jamais journalisés.
- 36 PWA : build de production (`flutter build web --release`, Flutter 3.47) servie localement et testée avec Render : démarrage sans écran blanc, session restaurée, échange réel, recherche ; 0 service worker actif, 0 cache (le service worker de Flutter se désinscrit et ne recharge que les pages d'un ancien service worker). CORRIGÉ en GH : Jarvis Web EST hébergé (site statique Render https://jarvis-ia-web.onrender.com, configuré dans le tableau de bord, reconstruit à chaque push) ; en-têtes vérifiés : `Cache-Control: public, max-age=0, s-maxage=300` + ETag (le navigateur revalide à chaque visite ; le CDN peut servir l'ancienne version ≤ 5 min).
- 37 Navigateur (Web profile, Render) : streaming raster moyen 4,5 ms, 3 images hors budget / 558 ; recherche allégée (31).
- 38 Effets : conclusions AB (fondu, ombres, PIM sans coût mesurable), fond photo composé une fois ; pas de nouvelle hypothèse.

### Résistance (40, Windows profile, 600 messages, 3 tours)
- Tour 1 → 2 : build p50 5,4 → 7,3 ms, mémoire 949 → 1 028 Mo (le fil grandit à chaque tour) ; tour 3 stable (build 7,1-7,6 ms, raster inchangé). Pas de dégradation continue démontrée ; mémoire du 3ᵉ tour non relevée.
- Tests : 977 / 977, analyse propre.

### Android (campagne unique, ajouts)
- Journal release (`[JARVIS erreur]`) sans contenu dans logcat ; recherche sur l'historique réel du compte.

## 2026-10-30 — Session GH (optimisations 41 à 60)

### Fait
- 41 Texte agrandi : tests ×1 / 1,3 / 1,6 / 2 (téléphone 390×844, ordinateur 1366×768) sur l'accueil, le fil et le menu : aucun débordement. L'accueil affiche désormais une conversation déjà commencée dès sa création (avant : seulement à la notification suivante).
- 46 Cible du « + » : un toucher dans la marge de la capsule au-dessus / au-dessous du « + » l'ouvre (avant : curseur dans le champ) ; rendu inchangé. Mesuré : bouton Menu 48×40 (barre du haut de 40 px sur téléphone), recherche du menu 40 px de haut : au-dessus du minimum WCAG (24 px), sous les 48 px d'Android, laissés tels quels (design).
- 43 Clavier (Windows, Android/iOS avec clavier physique) : Maj+Entrée = retour à la ligne, Entrée = envoi. Web : inchangé (le navigateur envoie sur Entrée, le raccourci ne peut pas l'empêcher ; vérifié sur le Web réel).
- 51-54 Réponses : `texteSimple` ne touche plus aux blocs de code (avant : « __init__ » → « init », « ** » et accents graves du code supprimés) ; `TexteRiche` (réponse terminée seulement) : bloc de code à défilement horizontal + « Copier le code » (copie exacte), tableau Markdown à défilement horizontal (colonnes ≤ 260 px, cellules complétées, « \| » gardé), liens http/https cliquables (destination exacte, ponctuation finale exclue, parenthèses équilibrées, autres schémas jamais ouverts). Vérifié sur le Web réel avec Render (code, tableau, lien encodé). Limite : sur le Web, pas de police à chasse fixe (CanvasKit) : indentation gardée, colonnes pas parfaitement alignées.
- 60 Gmail : une recherche dont Gmail annonce une page suivante (`nextPageToken`) est marquée `complet: false` et l'outil impose « au moins N » (avant : N pouvait être donné comme total). Compteur des non-lus : déjà exact (`labels/INBOX`).

### Déjà en place (vérifié)
- 42 Libellés : `labeledTapTargetGuideline` réussie (accueil, menu) ; « Préparation… » : annonce seulement au changement de libellé.
- 44 Animations réduites : menu, indicateur, curseur, transition d'apparence respectent la préférence.
- 45 Contraste : `apparence_test` (14 palettes).
- 47 Haptique : une impulsion au seuil du balayage (protégée), une à la fin de l'appui long ; rien par caractère.
- 48 Gestes, 50 ancrage du fil : tests existants (menu, `_garder`).
- 49 Redimensionnement : test ajouté (390×844 → 844×390 → 500×700 → 1920×1080 : brouillon multiligne, focus et fil gardés, aucun débordement).
- 55 EXIF : photo JPEG à orientation 6 décodée en portrait, y compris réduite (test avec vraies photos).
- 57 Dépôt : plusieurs fichiers → choix, format vérifié d'après le contenu. 58 Collage : sur action seulement, 4 lignes (G7).
- 59 HTML Gmail : converti en texte côté serveur (script/style retirés), jamais rendu : aucun JavaScript, aucune ressource externe.
- 56 Lecteur audio : non applicable (aucun fichier audio lu dans les conversations).

### Tests
- Flutter : 998 / 998, analyse propre.
- Backend : 681 réussis, 1 ignoré (dont Gmail + ODO : 160). Docker Desktop démarré avec l'accord de l'utilisateur.

### Android (campagne unique, ajouts GH)
- TalkBack (liens annoncés « Lien : … », bloc de code, tableau), texte agrandi système, « + » touché dans la marge, clavier physique Bluetooth (Maj+Entrée), rotation, photo EXIF réelle, vibrations du balayage.

## 2026-10-30 — Finition GH + session IJ (optimisations 61 à 80)

### Finition GH
- GH-1 Police du code : Roboto Mono embarquée (`assets/polices/RobotoMono.ttf`, 109 Ko, Apache 2.0, copie locale du cache pub) : le Web (CanvasKit) n'a pas les polices du système. Utilisée par les seuls blocs de code.
- GH-2 Maj+Entrée sur le Web : le champ HTML de Flutter envoyait avant que le framework ne voie la touche. `services/clavier/retour_ligne_web.dart` : écouteur en capture qui arrête la PROPAGATION de Maj+Entrée (textarea seulement, jamais pendant une composition IME) ; le navigateur insère la ligne, Flutter la relit. Vérifié sur le Web réel : Maj+Entrée = ligne, Entrée = envoi du message multiligne. Windows : raccourci Flutter (test).
- GH-3 Site Web : jarvis-ia-web sert la version GH (reconstruite 16:56 UTC ; « Copier le code », liens présents), `max-age=0` + ETag ; aucun déploiement déclenché.
- GH-4 Gmail : trois cas distincts dans le résultat de recherche : total EXACT (pas de page suivante), minimum « au moins N », estimation Gmail (`resultSizeEstimate`, dite « environ »). Pas de pagination exhaustive.
- GH-5 Bouton Menu (40 px) : non modifié (agrandir déplacerait la barre du haut) ; à juger au doigt sur Android.
- Bug trouvé pendant l'essai réel : « Donne un JSON de 3 clés… et une fonction » répondu « 3 plus 1 égale 4 » par le moteur local. `CalculVocal` : un opérateur écrit en mots n'est retenu que collé à un nombre de chaque côté (« 3 et 4 », « 12 sur 4 », « moins 5 » en tête) ; ces demandes vont à l'IA. Tests ajoutés.

### Réseau, streaming, traçage (61-70)
- 61 Déjà : fournisseurs IA en instances partagées (un pool par fournisseur-modèle), client unique Supabase / Google / Flutter.
- 62 Déjà : délais distincts côté appli (requête, en-têtes du chat, silence du flux 30 s), battements SSE pendant les lots.
- 63 Déjà : aucun réessai automatique d'une action non idempotente ; nouvel essai du serveur seulement si rien n'a été diffusé ; « Token expiré » refusé avant toute génération.
- 64 Non applicable : données privées et changeantes (quota, conversations) ; aucun point d'API public à mettre en cache.
- 65-67 Déjà : colonnes explicites, pages de messages et de contextes, rien de secondaire préchargé.
- 68 Déjà (AB) ; 69 Déjà : la reprise d'un flux n'existe pas chez les fournisseurs ; texte partiel gardé + incident, nouvel essai explicite, jamais de concaténation de deux générations.
- 70 Traçage (journaux Render, avant IJ) : préparation serveur 1,1-1,7 s, premier fragment fournisseur 2,1-13,5 s, enregistrement Supabase 0,35-0,79 s. Fait : état des connexions ODO (Gmail) lu dès l'arrivée de la requête en parallèle de la conversation (abandonné s'il ne sert pas) ; ligne « Durée : préparation du chat … (conversation, historique, creation, odo) » sans contenu. Mesuré après déploiement (12883de, 5 messages réels, offre Free / GroqCloud) : préparation 1 113-1 725 ms → 774-1 169 ms ; détail : lecture de la conversation 567-594 ms, historique + pièces jointes 206 ms (Redis) à 573 ms, ODO 1-2 ms (avant : une requête Supabase en série). Prochain coût dominant côté serveur : la lecture de la conversation (une requête Supabase ≈ 0,57 s depuis Render). Étudié : un cache Redis de la propriété est écarté (l'appli supprime les conversations directement dans Supabase : un cache garderait une conversation supprimée → appel IA payant puis échec d'enregistrement). Fait à la place (non déployé) : propriété, historique et pièces jointes lus EN MÊME TEMPS, rien utilisé avant la confirmation de Supabase (conversation d'un autre compte : 404, aucun appel IA, quota rendu — test existant). Mesuré après déploiement (1892eca, conversation existante, 3 messages) : préparation 565-736 ms (avant : 774-1 169 ms ; début de journée : 1 113-1 725 ms) ; nouvelle conversation : 694 ms (création).

### MIA universel, ODO (71-80)
- 71 / 74 / 75 Déjà : 20 derniers messages ; sortie 1 024 tokens (le modèle s'arrête plus tôt pour une phrase ; aide à répondre : 4 000) ; limites de l'offre en cache Redis, aucun repli entre fournisseurs.
- 72 Non fait : aucun résumé des chats ordinaires ; le créer changerait la logique IA sans mesure de qualité.
- 73 En attente de décision : l'adaptateur Claude lit les métriques de cache mais n'envoie aucun `cache_control` ; le prompt système contient l'heure (préfixe changeant) : il faudrait le scinder et valider avec des appels Claude payants.
- 76 Déjà : compteur des non-lus direct (sans IA) ; corrigé : faux calculs locaux (voir plus haut).
- 77 / 78 Déjà : métadonnées Gmail et lectures en parallèle (`asyncio.gather`).
- 79 Déjà : messages des pièces jointes WhatsApp en cache Redis par contexte et par compte.
- 80 Déjà : résultats d'outils plafonnés (`LECTURE_TOTAL`, extraits), secrets masqués.

### Tests IJ
- Flutter : 998 / 998, analyse propre. Backend : 681 réussis, 1 ignoré (Gmail : 150).
- Web réel (Render) : Maj+Entrée, police du code (JSON / Dart alignés), demande « JSON … et une fonction » envoyée à l'IA.

### Android (campagne unique, ajouts IJ)
- Clavier physique Bluetooth : Maj+Entrée ; police du code ; calculs dictés (« 3 et 4 ») toujours locaux.

### Validation finale IJ (2026-10-30, Render `1892eca`, /health/ready ok, Redis et Supabase ok)
- 5 échanges courts dans une conversation existante (offre Free, GroqCloud), journaux Render :
  - préparation du chat : 672 / 568 / 603 / 548 / 623 ms → médiane **603 ms** (avant IJ ≈ 1 480 ms, médiane de 1 113-1 725 ; après `12883de` ≈ 960 ms, de 774-1 169) ; dont propriété + historique + pièces jointes en parallèle 547-671 ms, ODO 1-3 ms (une fois 347 ms quand l'historique venait de Redis : la lecture ODO n'était pas encore finie).
  - premier fragment du fournisseur : 1 350-2 457 ms (médiane 1 417 ms) ; réponse principale : médiane 1 435 ms ; enregistrement Supabase (après la réponse, hors délai perçu) 204-575 ms.
  - Gain MESURÉ côté serveur : ≈ 0,9 s par message depuis le début d'IJ. La latence du fournisseur varie seule (non attribuée au backend).
  - Non mesuré : durée d'authentification (vérification JWT locale, JWKS en cache, avant le chronomètre ; aucun journal dédié) ; premier texte visible côté appli (la page servie n'avait pas les sondes).
- Sécurité : tests ajoutés `test_foreign_conversation_history_never_reaches_llm` (historique d'un autre compte : 404, aucun appel IA, rien enregistré, aucun quota, aucun texte dans le journal) et `test_deleted_conversation_refused` ; chat + MIA + ODO + contextes : 61 réussis. Journaux Render depuis 17:00 : aucun texte de message, aucun jeton / clé / Bearer.
