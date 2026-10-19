# Moteur de compréhension conversationnelle (phases 1, 2 et 3)

Permet à JARVIS de comprendre les conversations WhatsApp jointes à un chat et
d'en discuter librement. Ce n'est **pas** un nouveau modèle : un module du
backend prépare les instructions et les extraits pour le fournisseur IA déjà
branché (GroqCloud, client OpenAI de `app/api/v1/chat.py`), dans le flux
normal du chat (SSE, quota, enregistrement dans `messages`).

## Fichiers

| Fichier | Rôle |
| --- | --- |
| `backend/app/comprehension/reperes.py` | ce que vise la question : période (« mardi dernier », « le 12 octobre », « en mars »), début / milieu / fin, évolution, tendance générale, mots ; reprise des questions précédentes (suivis) |
| `backend/app/comprehension/extraits.py` | `MessageSource` (contexte, rang, auteur, texte, date, référence), mise en forme, aperçu calculé sur tous les messages, sélection sous budget |
| `backend/app/comprehension/instructions.py` | instructions internes (analyse du discours, pragmatique, second degré, faits / indices / hypothèses, anti-injection, forme des réponses) |
| `backend/app/comprehension/moteur.py` | `MoteurComprehension` : contextes du chat, choix des pièces jointes, chargement (cache Redis), numérotation des messages fournis (`Preparation.fournis`), messages pour le modèle |
| `backend/app/comprehension/references.py` | phase 2 : `FiltreReperes` (repères retirés du flux), `verifier` (existence, citation, auteur), charge exposée à Flutter |
| `backend/app/comprehension/attribution.py` | `CorrecteurAttributions` : chaque phrase contrôlée AVANT diffusion ; attribution fausse remplacée par une phrase factuelle (Supabase), reformulée ou écartée |
| `backend/app/comprehension/propositions.py` | phase 3 : `FiltrePropositions` (bloc retiré du flux), `analyser` (3 propositions distinctes par ton, appuis vérifiés), stockage, `bloc_precedentes` (« pourquoi la deuxième ? ») |
| `backend/app/comprehension/restauration.py` | phase 2 : stockage dans `messages.attachments`, relecture vérifiée, messages cités par les réponses précédentes |
| `backend/app/api/v1/chat.py` | intégration : `reply_to`, `whatsapp_analysis`, 409 `consentement_requis`, attente de la limite de débit, nouvel essai plus petit (413), événement SSE `references` |
| `backend/app/api/v1/contexts.py` | `GET /api/v1/conversations/{id}/references` (restauration) |
| `backend/tests/test_comprehension.py` | 28 tests (conversations fictives) |
| `backend/tests/test_references.py` | 30 tests : attribution (« mdr »), groupes, extraits, filtre, vérification, flux, restauration |
| `backend/tests/test_attribution.py` | 15 tests : deux participants, groupes, réactions courtes, citations ambiguës, suivis, flux morceau par morceau |
| `backend/tests/test_propositions.py` | 15 tests : filtre, validation, dernier auteur, route, restauration, « pourquoi la deuxième ? » |
| `backend/tests/qualite_comprehension.py` | essai **réel** de qualité (à lancer à la main, consomme du quota) |
| `backend/app/comprehension/etat.py` | état de compréhension partagé (habitudes, jalons, gravité, proportion, suite récente, échange en cours) : voir « Optimisation de la compréhension » |
| `backend/tests/scenarios_comprehension.py`, `evaluation_comprehension.py`, `test_evaluation_comprehension.py` | jeu d'évaluation (12 situations), mesure déterministe et réelle |

## Requête de chat

`POST /api/v1/chat/stream` (inchangé pour un chat sans pièce jointe) :

```json
{"message": "…", "conversation_id": "<uuid>", "reply_to": "<uuid consigne>", "whatsapp_analysis": "allowed"}
```

- `reply_to` : consigne **déjà enregistrée** avec sa pièce jointe (route
  `contexts`). Elle devient la question, n'est jamais réinsérée ; seule la
  réponse est enregistrée. Vérifiée : message `user` de ce compte, dans ce
  chat (sinon 404 « Consigne introuvable »).
- `whatsapp_analysis` : `allowed`, `declined`, ou absent. Si le chat a au
  moins un contexte et que le champ est absent : **409**
  `{"detail": {"code": "consentement_requis"}}`, avant tout appel au
  fournisseur (requête rendue au quota). `declined` : aucun contenu
  WhatsApp, le modèle sait qu'il n'y a pas accès.
- Pièce jointe supprimée depuis : le modèle est prévenu, rien d'inventé.

## Ce qui part vers le modèle

```
system : instructions générales de JARVIS (inchangées)
         + instructions du moteur
         + date du jour
         + <donnees_whatsapp>
             <pieces_jointes> catalogue (toutes les pièces jointes du chat) </pieces_jointes>
             <apercu piece="A"> faits comptés sur TOUS les messages </apercu>
             <messages piece="A" couverture="conversation entière | EXTRAITS …"> … </messages>
           </donnees_whatsapp>
historique du chat (borné : COMPREHENSION_HISTORY_TOKENS)
user   : la question (ou la consigne)
```

- Une ligne autonome par message (phase 2) :
  `[12] 06/10/2026 09:14 · Pepper Potts : «mdr»` — numéro de la requête,
  date ET heure du message, auteur ENREGISTRÉ (`(utilisateur)` après le nom
  de « moi »), texte entre « » (guillemets et retours à la ligne internes
  neutralisés). `(événement WhatsApp)`, `<média : image non transmis>`,
  `<message supprimé>`, date illisible ou incertaine signalée (jamais
  réinterprétée, jamais de fuseau).
- Manques signalés : `[… 340 messages non inclus …]`.
- Aperçu (compté, pas interprété) : messages par auteur, « ? », rires /
  émojis rieurs, médias, période, messages par mois, reprises après 6 h de
  silence, plus longs silences, dernier message.
- Sécurité : les messages importés sont des **données** ; les balises de
  délimitation présentes dans un message sont neutralisées (`‹/…›`) ; les
  instructions interdisent d'obéir aux ordres qu'ils contiennent.

## Choix des pièces jointes

1. `reply_to` → la pièce jointe de cette consigne ;
2. sinon, celles dont le contact (ou un participant) est nommé ;
3. sinon, la plus récente, réunie avec les autres imports du même contact.
Les autres restent dans le catalogue (le modèle demande une précision si
la question est ambiguë). Jamais deux contacts mélangés par défaut.

## Conversations longues

Budget : `COMPREHENSION_BUDGET_TOKENS` (6 000 par défaut). Le compte
GroqCloud actuel est limité à **8 000 tokens par minute**
(`x-ratelimit-limit-tokens`), bien en dessous de la fenêtre du modèle
`openai/gpt-oss-120b` (131 072). Estimation prudente : 3 caractères par
token (mesuré ≈ 3,4).

- Tout tient → la conversation entière.
- Sinon, dans l'ordre : messages de la période demandée (≤ 70 %), début /
  milieu / fin demandés, passages contenant les mots de la question (et de
  la précédente) ± 2 messages, derniers échanges, puis fenêtres réparties
  sur toute la période (8 segments pour une question de tendance ou
  d'évolution). Couverture annoncée au modèle (« EXTRAITS seulement : 180
  messages sur 3 000 (choisis : …) »).
- Pas de base vectorielle ni de résumés intermédiaires par l'IA : avec
  8 000 tokens / minute, résumer 5 000 messages prendrait plusieurs minutes.
  L'aperçu déterministe couvre la conversation entière.

## Fournisseur

- Même client que le chat ; `max_tokens` = `COMPREHENSION_MAX_OUTPUT_TOKENS`
  (1 500, raisonnement du modèle compris).
- 429 (débit) : attente conseillée par `retry-after` /
  `x-ratelimit-reset-tokens`, au plus `LLM_RATE_LIMIT_MAX_WAIT` (25 s), flux
  ouvert par des commentaires SSE (`: attente du fournisseur IA`) ; le client
  OpenAI n'attend plus en silence (`max_retries=0` pour cet appel).
- 413 : un seul nouvel essai avec 60 % du budget.
- Codes d'erreur SSE : `llm_rate_limit`, `llm_credit`, `llm_auth`,
  `llm_too_large`, `llm_model`, `llm_timeout`, `llm_unavailable`.
- Échec avant tout texte : rien d'enregistré, requête rendue au quota ; la
  consigne et la pièce jointe restent ; aucun contexte n'est supprimé.

## Cache

`wactx:{context_id}:messages` (Redis, `COMPREHENSION_CACHE_TTL` = 1 h) :
une pièce jointe ne change jamais ; la liste des contextes, elle, est relue
à chaque question (filtrée par le compte du JWT), donc une pièce jointe
supprimée n'est plus utilisée.

## Journaux

Volumes seulement (« 2 pièce(s) jointe(s), 180 message(s) fournis, ~5 800
tokens ») ; jamais de contenu, jamais le prompt (erreurs : type seulement).

## Flutter

- `ConsentementAnalyse` (`lib/services/conversation/consentement_analyse.dart`) :
  inconnu / accordé / refusé, par compte, sur l'appareil ; Paramètres ›
  Confidentialité (interrupteur « Analyse par l'IA »).
- `ConversationSession.envoyerAvecPieceJointe` : après l'enregistrement,
  `DemandeJarvis(repondreA: consigne, contexteImporte: true)` → moteur IA.
- 409 → `ReponseJarvis(accordRequis)` → carte de JARVIS avec « Autoriser
  l'analyse » / « Pas maintenant » (`ChoixJarvis`) ; `ConversationSession
  .choisir` relance la MÊME demande (aucun doublon).
- Échec d'une analyse sans texte reçu : « Réessayer » (même demande).
- Chat classé WhatsApp : `contexteImporte` → seules les commandes locales
  (heure, calcul…) restent sur l'appareil, le reste va au serveur.

## Phase 2 : attribution et références vérifiées

### Origine des erreurs d'attribution

La chaîne de DONNÉES conservait déjà l'auteur de chaque message (analyseur
→ `PiecesJointesApi.corps` → `context_messages.author` → `MessageSource`) ;
aucun auteur n'était recalculé. Les erreurs venaient de la présentation au
modèle et de l'absence de contrôle :

1. date seulement dans un en-tête de jour : le modèle devait suivre les
   en-têtes (erreur d'heure observée en phase 1) ;
2. texte non délimité : un message contenant « Nom : … » ou plusieurs
   lignes pouvait ressembler à une autre ligne ;
3. « vous » employé pour l'utilisateur comme pour les deux personnes ;
4. aucun contrôle des citations ni des attributions écrites par le modèle.

Corrections : format canonique (ci-dessus) ; instructions « qui a écrit
quoi » (auteur de la ligne exacte, réactions courtes, « vous deux ») ;
guillemets réservés aux citations exactes ; vérification côté serveur.
Le modèle peut encore se tromper (essais réels : « Explosent… » attribué à
Pepper) : depuis la correction d'attribution (ci-dessous), la phrase
fausse est corrigée ou retirée AVANT d'être diffusée.

### Repères et flux SSE

- Le modèle cite un message par `[[12]]` (plusieurs : `[[12, 14]]`).
- `FiltreReperes` diffuse le texte phrase par phrase (le reste attend la
  fin de sa phrase) et retire tous les repères, y compris les formes
  relâchées vues avec le vrai modèle : `[[20‑24]]` (tirets Unicode, plage
  ramenée à 4 numéros), `[12]`, `(message 5)`, `« … », message 22)`,
  `message 7`. Aucun identifiant technique n'atteint Flutter.
- Fin de réponse : événement `references` (avant `done`) :
  `{"message_id", "references": [...], "note"}`.

### Vérification (`verifier`)

| Cas | Résultat |
| --- | --- |
| numéro absent des messages fournis à CETTE requête | refusé (`refusees`) |
| la phrase cite « … » et aucun message visé ne le contient | refusé |
| le sujet de la proposition (« tu », ou un nom) n'est pas l'auteur enregistré | refusé, `attributions_contredites` + avertissement |
| repère qui groupe un passage autour d'une citation | message cité gardé, les autres écartés sans erreur |
| citation entre « » sans repère, un seul message cohérent | référence ajoutée |
| citation de 3 mots ou plus introuvable | avertissement « reformulation » |

Limites : 6 références par réponse, 3 par repère. Le sujet n'est reconnu
que s'il est explicite (nom, « tu », « toi ») ; « elle », « il », « vous »
ne déclenchent pas de contrôle. Une interprétation (« elle plaisante »)
n'est jamais vérifiable : seuls l'existence, le texte et l'auteur des
messages cités le sont.

### Charge exposée à Flutter

`context_id`, `context_message_id`, `message_order`, `author`, `is_me`,
`excerpt` (280 caractères), `kind`, `sent_at`, `sent_at_raw`,
`date_label`, `dates_uncertain`, `contact_name`, `current_user_name`,
`rang`, `position` (dans le texte visible). Tout vient de Supabase.

### Stockage, sans migration

`messages.attachments` (colonne JSON existante, inutilisée jusqu'ici),
dans la MÊME ligne que la réponse (une seule insertion) :
`{"type": "reference_whatsapp", "context_id", "context_message_id",
"message_order", "rang", "position"}` et éventuellement
`{"type": "note_references", "text"}`. Identifiants seulement : à la
relecture (`GET /api/v1/conversations/{id}/references` → `{"items": [...]}`),
chaque message est relu dans `context_messages` filtré par le compte du JWT
et rattaché à SON contexte ; un message supprimé ou d'un autre compte n'est
jamais renvoyé. Une table dédiée (`message_references`, clés composites,
cascade) serait plus stricte ; elle n'est pas nécessaire et n'a pas été
créée.

### « Pourquoi tu dis ça ? »

Les messages cités par les deux dernières réponses (relus dans
`attachments`) sont fournis de nouveau, avec leurs voisins (± 2), avant les
autres extraits : la justification porte sur les mêmes messages.

### Flutter

- `ReferenceWhatsApp` (`lib/models/importation/reference_whatsapp.dart`),
  `ReferencesReponse` ; `ApiJarvis` lit l'événement `references` et
  `referencesConversation` ; `ServicePiecesJointes.page` (une page autour
  d'un rang) et `.references`.
- `MessageConversation.references` / `noteReferences` ; restauration par
  `ConversationSession` à l'ouverture d'un chat qui a des contextes.
- `ReferencesJarvis` / `CarteReference` sous la réponse (auteur, date,
  extrait ; 3 d'emblée, « Voir les autres » ; avertissement discret).
- Appui : `ResumeWhatsAppPage.surMessage` — une page de 120 messages
  autour du message (40 avant), message visé comme centre du défilement
  (affiché au premier quart, sans mesure ni défilement manuel), éclairage
  lavande 2,6 s, pages précédentes / suivantes chargées en faisant défiler.
  Retour : le chat est intact dessous (même position).

## Correction des attributions (avant diffusion)

Constat : GroqCloud prête parfois une réaction (« mdr », « haha ») à la
mauvaise personne ; les auteurs enregistrés sont justes. Avant, la phrase
fausse était diffusée puis signalée par un avertissement. Désormais :

- `FiltreReperes` ne coupe jamais au milieu d'une citation et passe chaque
  segment (phrases complètes) au `CorrecteurAttributions` AVANT l'événement
  `delta` : une phrase fausse n'est jamais affichée, même un instant, et le
  texte enregistré (et l'historique du modèle) est le texte corrigé.
- Contrôlé : une affirmation FACTUELLE qui associe un message (citation
  entre guillemets, ou repère `[[n]]`) à UNE personne explicite (nom, « tu /
  toi »). Les interprétations (« elle plaisante sans doute ») ne sont ni
  corrigées ni signalées.

| Cas | Décision |
| --- | --- |
| auteur réel unique (message visé, ou citation dont toutes les occurrences sont d'une seule personne) | phrase remplacée : « C'est Pepper Potts qui a écrit « mdr ». » (« C'est toi qui as écrit… » pour l'utilisateur), repère gardé si le message est unique |
| citation présente chez plusieurs auteurs, aucun n'étant celui annoncé | reformulée sans choisir : « « oui » apparaît dans des messages de Rhodey et de toi. » |
| citation présente chez plusieurs auteurs dont celui annoncé | laissée telle quelle (rien de faux), aucune carte choisie au hasard |
| plus de deux attributions fausses dans une phrase, ou auteur inconnu | phrase écartée |

Jamais de substitution de nom dans la phrase du modèle (accords, pronoms) :
la phrase de remplacement est construite avec les données de Supabase. Le
texte cité est le message original s'il est court (≤ 120 caractères),
sinon la citation du modèle, déjà retrouvée dans le message. Note sous la
réponse : « J'ai rectifié qui a écrit un message… » / « J'ai retiré une
affirmation… » ; l'ancien avertissement (« mauvaise personne ») ne reste
qu'en dernier recours. Les citations de propositions de JARVIS (phase 3)
ne sont jamais prises pour des messages WhatsApp.

Limites : « elle », « il », « vous » ne sont pas vérifiés ; une phrase dont
le sujet est implicite reste celle du modèle.

## Phase 3 : aider à répondre et à relancer

### Intention

Aucune liste de formulations : le modèle comprend la demande (« aide-moi
à lui répondre », « qu'est-ce que je pourrais dire ? », « je veux reprendre
avec humour »…) d'après les instructions. `reperes.aide_reponse` n'est
qu'un INDICE pour le budget : il privilégie la fin de la conversation et
déplace `COMPREHENSION_EXTRA_OUTPUT_TOKENS` (500) de l'entrée vers la
sortie (6 000 → 5 500 en entrée, 1 500 → 2 000 en sortie : même total sous
les 8 000 tokens/minute). La discussion libre reste la règle.

Budget mesuré sur le vrai chat (943 messages) : instructions ~2 700 tokens
estimés à 3 caractères/token, historique ~970, aperçu ~370 ; il ne restait
que 8 à 19 messages WhatsApp. Les instructions (prose fixe) sont désormais
estimées à 4 caractères/token (`TOKENS_INSTRUCTIONS`, mesuré : 3 779 réels
pour 4 507 estimés) : 58 messages fournis pour la même question.

Quotas GroqCloud (compte gratuit) : 8 000 tokens/minute ET 200 000
tokens/JOUR (fenêtre glissante ; chaque requête compte entrée +
`max_tokens`). Quota quotidien atteint : code `llm_daily_quota`, message
« Le quota quotidien du service IA est presque épuisé. Réessaie dans
environ N minutes. » (d'après `retry-after`), aucune attente dans la
requête.

### Situation

L'aperçu ajoute une ligne `Situation : Pepper Potts a écrit en dernier
(2 messages d'affilée), il y a 3 jours ; l'utilisateur n'a pas encore
répondu : une RÉPONSE est attendue de lui` (ou « RELANCE possible »),
calculée sur tous les messages ; temps écoulé seulement si les dates sont
fiables. La demande explicite de l'utilisateur passe avant.

### Format et flux

Le modèle écrit une ou deux phrases, puis :

```
<propositions mode="reponse">
# Naturel
1. [rebondir sur sa pique] message à envoyer [[12]]
2. [poser une question] …
3. [proposer quelque chose] …
# Taquin
…
</propositions>
```

`FiltrePropositions` retire le bloc du flux (même coupé, ``` compris) ;
`analyser` garde, par ton, EXACTEMENT 3 propositions distinctes (Jaccard
des mots < 0,75 ; ton incomplet ou répétitif écarté ; 5 tons au plus),
retire les guillemets extérieurs (jamais ceux du message), transforme les
`[[n]]` en appuis (messages réellement fournis : `context_id`,
`context_message_id`, `message_order`). Événement SSE (avant `done`) :
`propositions {"message_id", "mode", "context_id", "tons": [{"nom",
"propositions": [{"texte", "approche", "appuis"}]}]}`. Bloc illisible :
aucune proposition, phrase honnête ajoutée ; bloc seul : introduction
minimale (jamais de réponse vide). Une balise `<propositions>` dans un
message importé est neutralisée.

### Persistance (sans migration)

Dans `messages.attachments` de la réponse : `{"type":
"propositions_reponse", "mode", "context_id", "tons"}` — même ligne, même
insertion que le texte. `GET /api/v1/conversations/{id}/references`
renvoie `propositions` avec chaque réponse (forme revalidée). Tous les
tons sont générés d'un coup : changer de ton n'appelle jamais l'IA.

### « Pourquoi tu me proposes la deuxième ? »

Les dernières propositions du chat (3 dernières réponses à pièces jointes)
sont redonnées au modèle (`<propositions_precedentes>`), appuis
renumérotés pour la requête en cours et messages d'appui refournis (comme
les messages cités). `ton_propose` (corps de la requête) : ton affiché par
l'utilisateur ; « la deuxième » = proposition 2 de ce ton (sinon du
premier). Les citations de ces propositions ne déclenchent aucune note.
Essai réel : le modèle avait mélangé deux propositions en justifiant « la
deuxième » ; `rang_vise` (« la deuxième », « la 3e », « la première »…)
donne désormais le texte EXACT de la proposition visée dans le bloc.
Repères « ([[24]]) » et « (message [[24]]) » retirés en entier.

### Flutter

- `PropositionsReponse` / `TonPropose` / `PropositionReponse`
  (`lib/models/importation/propositions_reponse.dart`), portés par
  `ReferencesReponse.propositions` (événement SSE et restauration) puis
  `MessageConversation.propositions`.
- `PropositionsJarvis` (`lib/widgets/conversation/propositions_jarvis.dart`)
  sous le texte de la réponse : « Idées de réponse / de relance »,
  capsules de ton (Wrap, jamais de défilement caché), trois
  `CarteProposition` (numéro, approche, texte sélectionnable, « Copier »
  → « Copié »). Changement de ton : simple affichage.
- `ConversationSession.regarderTon` mémorise le ton affiché des dernières
  propositions ; `DemandeJarvis.tonPropose` → `ApiJarvis.discuter(tonPropose:)`.

### Identifiants (phase 3 finale)

Chaque proposition porte `id` (uuid4, enregistré). Anciennes propositions
sans identifiant : `uuid5("jarvis:proposition:{message}:{ton}:{rang}")`,
identique à chaque lecture. Justification : l'appli envoie
`propositions_message_id` (réponse qui porte les propositions) et
`ton_propose` ; le serveur la relit filtrée par compte ET chat (sinon :
ignorée, repli sur les propositions récentes du chat) et donne au modèle
« PROPOSITION VISÉE (identifiant …) : ton, n°, approche, texte exact,
appuis ». Citation d'une proposition inexistante (≥ 4 mots, absente des
messages et des propositions) : rétablie mot pour mot (la plus proche si
Jaccard ≥ 0,5, sinon la proposition visée si la phrase parle d'une
proposition).

## Phase 4 : réponses déclarées envoyées

- `PUT /api/v1/conversations/{c}/messages/{m}/propositions/{p}/envoyee` :
  déclare (idempotent : une déclaration active est renvoyée telle quelle).
  `DELETE` : annule (gardée, `statut = annulee`, `cancelled_at`). 404 si la
  réponse n'est pas de ce compte et de ce chat, ou si l'identifiant n'y
  figure pas. Réponse : `{envoyee, declared_at, cancelled_at}`.
- Stockage (`app/comprehension/memoire.py`), sans migration, dans
  `messages.attachments` de la réponse aux propositions :
  `{"type": "reponse_envoyee", "statut": "declaree_envoyee" | "annulee",
  "proposition_id", "texte", "ton", "context_id", "contact", "groupe",
  "conversation_id", "message_id", "user_id", "declared_at",
  "cancelled_at"}`. Jamais dans `context_messages` : un message WhatsApp
  original, une proposition et une déclaration restent distincts.
- Relecture : `propositions.lues` ajoute `envoyee` (date ou null) à chaque
  proposition ; Flutter reprend les statuts à l'actualisation.
- Mémoire : `memoire.pour_contacts` lit les déclarations actives du compte
  (`list_declared_replies`, filtre `attachments cs [{"type":
  "reponse_envoyee"}]`), garde celles du même contexte ou du même contact
  (8 au plus) et marque `dans_export` celles retrouvées telles quelles
  parmi les messages de l'utilisateur ; `bloc_memoire` les place juste
  avant la question (déclarées, non vérifiées ; pas de répétition ; ton
  non permanent ; doublon d'export à ne pas compter deux fois).
- Flutter : `CarteProposition` (appui long 800 ms, progression, tolérance
  12 px, `HapticFeedback.mediumImpact`, Semantics `onLongPress`, bouton
  « Marquer envoyée » sur Web / Windows / macOS / Linux, « Envoyée » +
  « Annuler », « Non enregistrée, réessayez ») ;
  `ConversationSession.declarerEnvoyee` ; `ServiceReponsesEnvoyees` /
  `ReponsesEnvoyeesApi` ; `ApiJarvis.statutEnvoyee`.
- Limite : lecture-modification de la colonne JSON (pas de verrou) ; une
  table dédiée avec clé unique (compte, proposition) serait plus stricte.

## Optimisation de la compréhension (2026-10-19)

Objectif : comprendre un message à partir de ce qui l'a déclenché, relier la
suite récente (ajouts manuels, réponses déclarées envoyées) et partager UNE
compréhension entre la réponse principale et tous les lots de propositions.
Aucune nouvelle table, aucune migration, aucun nouveau fournisseur.

### État de compréhension partagé (`app/comprehension/etat.py`)

Faits calculés sans IA sur les messages enregistrés, reconstruits à chaque
demande (rien de stocké) :

| Élément | Contenu |
| --- | --- |
| `habitudes` | par auteur : médiane de mots, % émojis, % rires, % questions, tu / vous, réactions courtes récurrentes ; « récemment » si les 40 derniers messages s'écartent nettement. Des tendances, jamais un profil ; dans un groupe, chacun les siennes |
| `jalons` | derniers messages qui annoncent un changement ou une décision (« finalement », « on décale », « mise à jour », « erreur »…) ; forcés dans les extraits (10 % du budget) |
| `indices_serieux` / `grave` | mots de gravité (hôpital, licenciement…) ou de tension (« je suis sérieuse », « pas une blague ») dans les 6 derniers messages : des indices, pas une conclusion |
| `proportion` | `legere` si l'interlocuteur a écrit en dernier un message très court sans question (« Ok 👍 ») |
| `fil` / `bloc_fil` | suite récente dans l'ordre réel : une réponse déclarée envoyée se place avant le premier ajout enregistré après elle (`created_at` de l'ajout, `declared_at` ; jamais une date WhatsApp inventée) ; une déclaration déjà présente comme message n'est jamais comptée deux fois |
| `debut_episode` | l'échange en cours : la suite récente forme un échange à part de l'export ; dans l'export, une pause de plus de 6 h en ouvre un autre |
| `a_repondre` | message auquel les propositions répondent (message visé s'il vient d'un interlocuteur, sinon le dernier reçu, ou le dernier de l'utilisateur pour une relance) |
| `faits` | lignes ajoutées à l'aperçu ; `compact=True` quand le budget est serré (habitudes de l'utilisateur et du dernier interlocuteur, deux jalons) |

Faits / interprétations / inconnues : l'aperçu ne contient que des faits et
des indices (ligne « Inconnu » : dates d'ajout, ordre jour/mois, utilisateur
non confirmé). L'interprétation est celle du modèle, écrite UNE fois :
attribut `lecture` du bloc `<propositions … lecture="…">` (une phrase ≤ 30
mots), enregistré avec l'ensemble (`lecture` dans `messages.attachments`,
relu par « Reprendre »).

### Ciblage des suivis naturels (`ciblage.py`)

« Pourquoi elle me dit ça ? », « Tu crois qu'il plaisante ? », « Qu'est-ce
que je devrais répondre ? » (`_DEICTIQUE`) visent le message actif :
personne nommée, sinon celle de la question précédente, sinon le contact
(discussion à deux). Groupe sans nom : le dernier ajout reçu (message qu'il
vient de coller), le dernier reçu pour « que répondre ? », sinon
clarification. Question ancrée sur un autre message (citation « … »,
« quand il m'a dit… ») ou qui suit une telle question : aucune cible, le
modèle garde ce référent. `<message_vise>` sépare désormais l'« Échange en
cours » (même moment, réponses déclarées envoyées comprises) de ce qui est
« Plus tôt » (montré seulement si l'échange en cours est vide), et dit
quand le message visé est arrivé après une réponse déclarée envoyée.

### Lots de propositions (`generation.py`)

- `brief` : demande, lecture commune, analyse (250 caractères quand la
  lecture existe), « Message auquel répondre » (numéroté, inclus même s'il
  est plus ancien que les derniers messages), situation, registre, habitudes de
  l'utilisateur et de l'interlocuteur, proportion, sérieux, trois dernières
  décisions, mémoire, derniers messages (14 avec une lecture commune,
  `DERNIERS_AVEC_LECTURE`, sinon 24). Identique pour tous les lots.
- `CONSIGNES_LOT` : tons qui changent la manière de répondre, longueurs
  proportionnées, 3 approches par ton alignées entre longueurs (n°1 court /
  moyen / long = même orientation), voix de l'utilisateur et non d'un
  assistant, aucun souvenir ni détail inventé.
- Validation (`_mots_valides`) : Moyen 6 à 70 mots, ≤ 4 phrases ; Long
  ≤ 140 mots ; proportion `legere` : Moyen dès 4 mots, Long dès 12 mots et
  deux phrases (au lieu d'un remplissage pour atteindre trois phrases).

### Instructions (`instructions.py`)

Section « Comprendre un message en contexte » : d'abord l'échange qui a
déclenché le message, puis les réactions, les événements récents, enfin les
habitudes ; chercher ce qui contredit la première lecture ; certain /
probable / ambigu / inconnu (sans titres « Faits / Indices » dans la
réponse) ; intention seulement si les indices la montrent ; habitudes ≠
situation actuelle ; dernière décision écrite prime ; fils croisés dans un
groupe. Taille ≈ celle d'avant (+50 tokens).

### Évaluation (`tests/scenarios_comprehension.py`, `tests/evaluation_comprehension.py`)

Douze situations sur les 5 exports fictifs (même message dans deux
contextes, ironie, désaccord puis réconciliation, changement de décision,
ajout sans date, dernier message d'un participant de groupe, annonce grave
dans une amitié blagueuse, suivi ambigu en groupe, réponse déclarée envoyée
puis réponse reçue, « Ok 👍 », « tu crois qu'elle plaisante ? »).

- Déterministe (gratuit, aussi sur l'ancienne version) :
  `python tests/evaluation_comprehension.py` ; test pytest
  `tests/test_evaluation_comprehension.py`.
- Réel (`--reel --scenarios a,b`, GroqCloud par défaut, 60 s entre deux
  scénarios, reprise après 429) : mesures automatiques (longueurs, diversité
  par similarité de Jaccard, approches distinctes, plaisanteries en
  situation grave, nombres absents des sources, mots attendus / interdits)
  + textes à juger. Ne prouve pas à lui seul une meilleure compréhension.

### Limites

- Habitudes, jalons et gravité sont des heuristiques lexicales (français) :
  un jalon peut être manqué ou superflu ; la gravité ne voit que les 6
  derniers messages.
- Demandes d'aide sur GroqCloud : la partie fixe dépasse le budget réservé
  (3 500 tokens) de 350 à 650 tokens, car les messages gardent leur
  plancher de 1 000 tokens (l'ancienne version dépassait déjà sur un
  scénario). Lots : ~+66 tokens chacun par rapport à avant l'optimisation ;
  un ensemble « annonce grave » a utilisé les 5 lots permis (complet).
- Une lecture commune erronée est appliquée à tous les lots (cohérente,
  mais fausse partout) ; aucun contrôle des doublons entre tons.
- `created_at` d'un ajout = moment de l'enregistrement, pas de l'envoi
  WhatsApp : il ne sert qu'à ordonner ajouts et déclarations.

## Fiabilité de la compréhension partagée (2026-10-19, déployée)

Cause du contresens « annonce grave » : la réponse principale avait écrit
« proposer ton soutien ou une alternative » (et « le remplacer plus tard »
pour reporter l'escalade) ; les lots recevaient cette lecture comme
« fixée, la même pour toutes les propositions », donc comme une consigne,
et rien ne contrôlait les engagements proposés : 15 propositions sur 36
offraient de « prendre ta place ».

- `app/comprehension/controle.py` (sans IA) :
  - `nettoyer_interpretation` (avant les lots, lecture ET analyse) :
    découpe en propositions, confrontées aux 10 derniers messages + demande ;
    retire initiative non justifiée (alternative, remplacer, venir,
    promettre, appeler, rendez-vous), humour en situation grave, décision
    non écrite, citation introuvable, date / heure / jour absents, participant
    absent de l'échange ; nuance « clairement, forcément… » → « probablement ».
  - `Controle.examiner` (chaque proposition) : engagement pris à la place de
    l'utilisateur sans justification dans les 8 derniers messages, la
    demande ou ses réponses déclarées envoyées ; date, heure ou jour
    inventés ; rire en situation grave. `Ensemble.integrer` refuse aussi les
    vrais doublons entre tons (même longueur). Seule la combinaison
    concernée est redemandée, avec la raison du refus (`Ensemble.refus`).
- `brief` : blocs FAITS (message auquel répondre, situation, registre, mots
  graves, décisions écrites) / INTERPRÉTATION POSSIBLE (« une piste, jamais
  une consigne ; les messages priment ») / INCONNU (intentions exactes, tout
  projet, aide, remplacement, visite, rendez-vous ou promesse non écrits).
- `CONSIGNES_LOT` : « l'utilisateur décide de ses engagements » ; situation
  grave : sobre, sans solution improvisée.
- Journaux (volumes seulement) : « Contrôle de la compréhension : lecture n
  retrait(s) [raisons]… ms », « Contrôle des propositions : n refus [raisons] ;
  lots … ms ».
- Essai réel sur `jarvis-api` déployée (GroqCloud, compte de test Free,
  conversation fictive « Amitié » + annonce collée) : 36/36 en 3 lots
  (37 s de lots, 42 s au total ; avant : 5 lots, 53 s), 12 619 tokens, 1 refus
  (visite non justifiée), aucune proposition de remplacement, aucune
  plaisanterie. Limite : la réponse principale s'est réduite à « Voici
  quelques idées de réponse » (aucune analyse visible).
