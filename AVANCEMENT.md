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
