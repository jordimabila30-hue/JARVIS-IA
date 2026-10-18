import 'capture_jointe.dart';
import '../services/ecriture/ecriture_progressive.dart';
import 'importation/piece_jointe_whatsapp.dart';
import 'importation/propositions_reponse.dart';
import '../services/importation/actualisation_whatsapp.dart';
import 'importation/reference_whatsapp.dart';

/// Une ligne d'une conversation externe (« Sarah : Tu aurais pu me
/// prévenir. »).
class LigneConversation {
  const LigneConversation(this.locuteur, this.texte, {this.heure});

  final String locuteur;
  final String texte;

  /// Heure lue dans un export (WhatsApp…), si présente.
  final String? heure;

  static const _moi = {'moi', 'me', 'je', 'perso'};

  /// Locuteurs désignés par un pronom plutôt qu'un nom.
  static const _anonymes = {'il', 'elle', 'lui', 'iel', 'ils', 'elles', 'eux'};

  /// Vrai si la ligne a été écrite par l'utilisateur lui-même.
  bool get estMoi => _moi.contains(locuteur.trim().toLowerCase());

  /// Vrai si le locuteur n'a pas de nom (« Elle : … ») : JARVIS emploie
  /// alors une formulation neutre (« la personne »), sans jamais deviner
  /// un genre.
  bool get sansNom => _anonymes.contains(locuteur.trim().toLowerCase());
}

/// Conversation externe collée ou écrite par l'utilisateur.
class ConversationExterne {
  const ConversationExterne(this.lignes);

  final List<LigneConversation> lignes;

  /// Participants, dans l'ordre d'apparition.
  List<String> get participants {
    final vus = <String>[];
    for (final l in lignes) {
      if (!vus.any((p) => p.toLowerCase() == l.locuteur.toLowerCase())) {
        vus.add(l.locuteur);
      }
    }
    return vus;
  }

  /// Participants autres que l'utilisateur.
  List<String> get autres => [
    for (final p in participants)
      if (!LigneConversation(p, '').estMoi) p,
  ];

  LigneConversation get derniere => lignes.last;

  /// Dernier message d'un autre participant, s'il y en a un.
  LigneConversation? get dernierDesAutres {
    for (final l in lignes.reversed) {
      if (!l.estMoi) return l;
    }
    return null;
  }
}

/// Qui a écrit un message du fil.
enum AuteurMessage { utilisateur, jarvis }

/// Ton d'une réponse proposée.
enum TonReponse {
  naturel('Naturel'),
  amical('Amical'),
  bienveillant('Bienveillant'),
  direct('Direct'),
  poli('Poli'),
  professionnel('Professionnel');

  const TonReponse(this.libelle);

  final String libelle;
}

/// Raccourcis discrets proposés après une conversation collée.
enum ActionRapide {
  comprendre('Comprendre'),
  resumer('Résumer'),
  repondre('Répondre'),
  question('Poser une question');

  const ActionRapide(this.libelle);

  final String libelle;
}

/// Boutons sous une réponse de JARVIS qui attend une décision de
/// l'utilisateur (accord pour l'analyse distante, nouvel essai).
enum ChoixJarvis {
  autoriserAnalyse('Autoriser l’analyse'),
  refuserAnalyse('Pas maintenant'),
  reessayer('Réessayer');

  const ChoixJarvis(this.libelle);

  final String libelle;
}

/// Un message du fil de conversation avec JARVIS.
///
/// Message de l'utilisateur : [texte] (sa demande) et éventuellement la
/// [conversation] qu'il a collée. Message de JARVIS : [texte], des
/// [actions] discrètes, et, pour une demande de réponse, le choix du ton
/// puis la [reponseProposee].
///
/// [heure] : moment réel de création du message (heure locale de
/// l'appareil), affiché « HH:mm » sous le message.
class MessageConversation {
  const MessageConversation({
    required this.id,
    required this.auteur,
    required this.heure,
    this.texte = '',
    this.conversation,
    this.pieceJointe,
    this.actions = const [],
    this.choixTon = false,
    this.ton,
    this.reponseProposee,
    this.vocal = false,
    this.idServeur,
    this.enregistre = false,
    this.provisoire = false,
    this.ecriture,
    this.redaction = false,
    this.incident,
    this.choix = const [],
    this.references = const [],
    this.noteReferences,
    this.propositions,
    this.ajoutWhatsApp,
    this.capture,
  });

  final int id;
  final AuteurMessage auteur;
  final DateTime heure;
  final String texte;
  final ConversationExterne? conversation;

  /// Conversation WhatsApp jointe à la consigne ([texte]) : un objet à
  /// part, jamais mêlé au texte. Ses messages ne partent jamais de
  /// l'appareil vers l'IA : seul le serveur, avec l'accord de
  /// l'utilisateur, en envoie des extraits pour l'analyse.
  final PieceJointeWhatsApp? pieceJointe;
  final List<ActionRapide> actions;

  /// Afficher « Quel ton ? » (demande de réponse).
  final bool choixTon;
  final TonReponse? ton;
  final String? reponseProposee;

  /// Échange du mode vocal (phrase reconnue ou réponse prononcée), dans la
  /// même conversation que l'écrit.
  final bool vocal;

  /// UUID de la ligne enregistrée sur le serveur (table `messages`), si
  /// elle est connue : sert à ne jamais afficher deux fois un message lors
  /// d'une actualisation.
  final String? idServeur;

  /// Enregistré sur le serveur (échange avec l'IA réussi), même si son
  /// [idServeur] n'est pas encore connu. Faux pour les réponses locales
  /// (heure, calcul…), les erreurs et les conversations collées : elles
  /// restent sur cet appareil.
  final bool enregistre;

  /// Message d'état temporaire (chargement impossible…), retiré dès que
  /// la conversation est chargée.
  final bool provisoire;

  /// Écriture progressive de la réponse (réponse produite pendant cette
  /// session). Null : texte affiché d'un coup (message chargé du serveur,
  /// message de l'utilisateur).
  final EcritureProgressive? ecriture;

  /// Bulle d'une réponse encore en réception (fragments de l'IA) : son
  /// [texte] n'est pas encore connu, il arrive par [ecriture]. Remplacée,
  /// avec le même [id], par la réponse finale.
  final bool redaction;

  /// Réponse interrompue (coupure, erreur) : explication affichée sous le
  /// texte déjà reçu, qui n'est jamais présenté comme complet.
  final String? incident;

  /// Décision attendue (boutons) : retirés dès qu'un choix est fait.
  final List<ChoixJarvis> choix;

  /// Messages WhatsApp originaux qui fondent cette réponse, vérifiés par
  /// le serveur (cartes cliquables sous la réponse).
  final List<ReferenceWhatsApp> references;

  /// Avertissement du serveur sur les références (refusées, attribution
  /// contredite par les messages enregistrés…).
  final String? noteReferences;

  /// Messages proposés à l'utilisateur pour répondre ou relancer (par ton,
  /// trois par ton), quand il a demandé de l'aide (phase 3).
  final PropositionsReponse? propositions;

  /// Phase 5.1 : bulle d'un message WhatsApp collé (reçu ou envoyé) ;
  /// [texte] reste vide (rien pour les détecteurs ni pour l'IA).
  final AjoutDansLeFil? ajoutWhatsApp;

  /// Capture d'écran jointe par l'utilisateur (JARVIS Touch) : référence
  /// seulement, jamais les octets.
  final CaptureJointe? capture;

  bool get deJarvis => auteur == AuteurMessage.jarvis;

  MessageConversation avecReponse(TonReponse ton, String reponse) =>
      _copie(ton: ton, reponseProposee: reponse);

  /// Rattaché à sa ligne serveur.
  MessageConversation avecIdServeur(String idServeur) =>
      _copie(idServeur: idServeur, enregistre: true);

  /// Enregistré sur le serveur (identifiant pas encore connu).
  MessageConversation enregistreSurServeur() => _copie(enregistre: true);

  /// Identifiant choisi par l'appareil pour sa future ligne serveur
  /// (échange local en attente d'enregistrement).
  MessageConversation avecIdPrevu(String idServeur) =>
      _copie(idServeur: idServeur);

  /// Message relu du serveur auquel sa pièce jointe est rattachée.
  MessageConversation avecPieceJointe(PieceJointeWhatsApp piece) =>
      _copie(pieceJointe: piece);

  /// Bulle d'ajout WhatsApp corrigée.
  MessageConversation avecAjout(AjoutDansLeFil a) => MessageConversation(
    id: id,
    auteur: auteur,
    heure: heure,
    idServeur: idServeur,
    enregistre: enregistre,
    ajoutWhatsApp: a,
  );

  /// Propositions mises à jour (statut « envoyée »).
  MessageConversation avecPropositions(PropositionsReponse p) =>
      _copie(propositions: p);

  /// Décision prise : les boutons disparaissent.
  MessageConversation sansChoix() => _copie(choix: const []);

  /// Références relues du serveur (chat restauré).
  MessageConversation avecReferences(ReferencesReponse r) => _copie(
    references: r.references,
    noteReferences: r.note,
    remplacerNote: true,
    propositions: r.propositions,
  );

  MessageConversation _copie({
    PieceJointeWhatsApp? pieceJointe,
    TonReponse? ton,
    String? reponseProposee,
    String? idServeur,
    bool? enregistre,
    List<ChoixJarvis>? choix,
    List<ReferenceWhatsApp>? references,
    String? noteReferences,
    bool remplacerNote = false,
    PropositionsReponse? propositions,
  }) => MessageConversation(
    id: id,
    auteur: auteur,
    heure: heure,
    texte: texte,
    conversation: conversation,
    pieceJointe: pieceJointe ?? this.pieceJointe,
    actions: actions,
    choixTon: choixTon,
    ton: ton ?? this.ton,
    reponseProposee: reponseProposee ?? this.reponseProposee,
    vocal: vocal,
    idServeur: idServeur ?? this.idServeur,
    enregistre: enregistre ?? this.enregistre,
    provisoire: provisoire,
    ecriture: ecriture,
    redaction: redaction,
    incident: incident,
    choix: choix ?? this.choix,
    references: references ?? this.references,
    noteReferences: remplacerNote ? noteReferences : this.noteReferences,
    propositions: propositions ?? this.propositions,
    capture: capture,
  );
}
