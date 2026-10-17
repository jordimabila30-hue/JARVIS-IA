

## Phase 5.1 : finition UX

### Tons × longueurs
- **Génération par lots** (correction finale, `app/comprehension/generation.py`).
  Cause du défaut : une seule grande réponse devait contenir 4 tons × 3
  longueurs × 3 propositions ; le vrai modèle n'en écrivait parfois qu'une
  par longueur (essai du 2026-10-16), et un repli « partiel » les
  affichait à moitié. Ce repli est SUPPRIMÉ.
  1. La réponse principale (streaming) annonce seulement mode et tons :
     `<propositions mode="reponse" tons="Naturel, Taquin, Chaleureux"></propositions>`
     (3 tons adaptés, complétés par des tons de secours ; « Professionnel »
     toujours ajouté en dernier). Des propositions déjà valides écrites
     dans ce bloc sont gardées.
  2. Lots : `PROPOSITIONS_TONS_PAR_LOT` (2) tons par requête, JSON strict
     (`response_format: json_object`, sinon texte relu en JSON ;
     `reasoning_effort: low` pour gpt-oss), contexte court (demande,
     analyse de JARVIS, Situation, 24 derniers messages numérotés,
     mémoire des réponses envoyées), sortie estimée selon ce qui manque
     (≤ `PROPOSITIONS_LOT_MAX_TOKENS`, 2 600).
  3. Validation par combinaison ton × longueur : EXACTEMENT 3 propositions
     distinctes (similarité < 0,75, pas de doublon dans le ton), texte
     propre (≤ 600 caractères, aucune balise), Court ≤ 40 mots, Long ≥ 3
     phrases (ou ≥ 30 mots) et ≥ 15 mots. JSON illisible, ton ou longueur
     absents, répétitions : refusés.
  4. Complétion : seules les combinaisons incomplètes sont redemandées
     (« il en manque 2 », celles déjà retenues données « à ne pas
     répéter ») ; les tons sans rien d'abord. Les propositions valides et
     leurs identifiants ne changent jamais.
  5. Bornes : `PROPOSITIONS_MAX_REQUETES` (5) par génération ou reprise ;
     429 par minute : attente conseillée, cumul ≤ `PROPOSITIONS_ATTENTE_MAX`
     (45 s, flux SSE gardé ouvert par des commentaires) ; quota quotidien :
     arrêt immédiat. Tokens des lots comptés dans le quota de la requête.
- Événement `propositions` : `statut: "complet"` (toutes les combinaisons,
  seul cas affiché) ou `statut: "incomplet"` + `raison` (quota | erreur |
  invalide), `tons: []`. Stockage (`messages.attachments`, version 2) :
  `statut`, `prevus`, `demande_id`, lots valides conservés.
- « Reprendre » : `POST /api/v1/conversations/{c}/messages/{m}/propositions/completer`
  (JWT + quota) : relit l'ensemble, ne génère que ce qui manque, réécrit la
  seule entrée des propositions de la MÊME réponse (aucun nouveau message,
  aucune consigne renvoyée) ; déjà complet → renvoyé sans appel IA ; verrou
  Redis `propgen:{m}` (180 s) → 409 `generation_en_cours`. Un ensemble
  incomplet ne peut pas être déclaré envoyé (404).
- Budget : `COMPREHENSION_EXTRA_OUTPUT_TOKENS` (2 500) retiré de l'entrée de
  la réponse principale quand l'aide est probable (~34 extraits au lieu de
  ~45) ; sortie principale normale (1 500). Réponse principale + 2 lots
  dépassent souvent 8 000 tokens/min : le 2e lot attend alors (≤ 45 s).
- « Pourquoi la deuxième ? » : `ton_propose` + `longueur_proposee` +
  `propositions_message_id` ; le bloc ne détaille que les trois propositions
  affichées.

### Une seule réponse envoyée par ensemble
- Migration `20261016150000_reponse_envoyee_unique.sql` (appliquée,
  autorisée) : `declarer_reponse_envoyee` / `annuler_reponse_envoyee`
  verrouillent la ligne de la réponse (`select … for update`). Autre
  proposition du même ensemble alors qu'un choix est actif → 409
  `deja_choisi` (tous tons et longueurs) ; même proposition → idempotent ;
  après annulation, un autre choix est possible ; nouvel ensemble
  indépendant. Deux appareils simultanés : un seul choix (testé en local).

### Interface
- `PropositionsJarvis` : capsules de ton, capsules de longueur, trois
  cartes ; réglages gardés par la session (`tonRegarde`, `longueurRegardee`).
- Après confirmation du serveur, la carte devient `BulleReponseChoisie`
  (« Vous → contact », texte, menu `···` : Copier, Annuler le choix, date de
  la déclaration) ; annulation → retour au ton et à la longueur choisis.
  Même message, rien de dupliqué. Choix déjà fait ailleurs (409) : relu.
- Messages collés : bulles `BulleAjoutWhatsApp` dans le fil (reçu à gauche
  au nom de l'auteur, envoyé à droite « Vous → contact », menu `···` :
  Modifier, Supprimer). `MessageConversation.ajoutWhatsApp`, texte vide ;
  jamais dans l'historique donné aux moteurs. Restaurées à l'ouverture du
  chat (`GET …/messages?manual=true`, placées selon `created_at`), sans
  doublon ; corrigées / supprimées ailleurs : la bulle suit. Plus de message
  « ajouté avec succès ».
- Geste : petit glissement = action révélée ; au-delà de 60 % de la largeur
  (bouton rempli, vibration légère) puis relâcher = volet ouvert directement.
- Volet : vue principale (contact, Reçu / Envoyé, auteur si besoin, texte,
  « Ajouter ») ; « Options » : plusieurs messages, date, ajouts précédents.
