/// Import WhatsApp — interface 3 : la conversation jointe à un message de
/// JARVIS. Trois choses liées mais distinctes :
/// 1. les messages WhatsApp originaux ([MessageWhatsApp], tels que lus) ;
/// 2. la pièce jointe qui les représente ([PieceJointeWhatsApp]) ;
/// 3. la consigne écrite à JARVIS (le texte du message qui la porte).
///
/// Avec un compte, la pièce jointe est enregistrée par le backend à l'envoi
/// de la consigne (jamais transmise à l'IA) ; sinon, elle reste en mémoire.
library;

import '../../utils/identifiant.dart';
import '../conversations/source_conversation.dart';
import 'conversation_whatsapp.dart';
import 'filtre_whatsapp.dart';

/// Conversation WhatsApp filtrée, prête à accompagner une consigne.
class PieceJointeWhatsApp {
  const PieceJointeWhatsApp({
    required this.id,
    required this.titre,
    required this.conversationSource,
    required this.nomFichier,
    required this.participants,
    required this.moi,
    required this.groupe,
    required this.dateIncertaine,
    required this.messages,
    required this.creeLe,
    String? idConsigne,
    this.nombreEnregistre,
    this.debutEnregistre,
    this.finEnregistre,
    this.chargerMessages,
  }) : idConsigne = idConsigne ?? id;

  /// Pièce jointe relue depuis le serveur (autre appareil, redémarrage) :
  /// ses métadonnées seulement ; ses messages sont lus à la demande
  /// ([chargerMessages], par pages).
  factory PieceJointeWhatsApp.enregistree({
    required String id,
    required String idConsigne,
    required String titre,
    required List<String> participants,
    required String? moi,
    required bool groupe,
    required bool dateIncertaine,
    required int nombre,
    required DateTime creeLe,
    DateTime? debut,
    DateTime? fin,
    Future<List<MessageWhatsApp>> Function()? chargerMessages,
  }) => PieceJointeWhatsApp(
    id: id,
    idConsigne: idConsigne,
    titre: titre,
    conversationSource: '',
    nomFichier: '',
    participants: participants,
    moi: moi ?? '',
    groupe: groupe,
    dateIncertaine: dateIncertaine,
    messages: const [],
    creeLe: creeLe,
    nombreEnregistre: nombre,
    debutEnregistre: debut,
    finEnregistre: fin,
    chargerMessages: chargerMessages,
  );

  /// Prépare la pièce jointe des messages [choisis] de [conversation].
  /// [moi] : participant confirmé par l'utilisateur (jamais deviné).
  factory PieceJointeWhatsApp.depuis({
    required ConversationWhatsApp conversation,
    required MessagesChoisisWhatsApp choisis,
    required String moi,
    DateTime? maintenant,
  }) {
    final creeLe = maintenant ?? DateTime.now();
    return PieceJointeWhatsApp(
      id: nouvelUuid(),
      idConsigne: nouvelUuid(),
      titre: titreContact(conversation, moi),
      conversationSource: choisis.conversationSource,
      nomFichier: choisis.nomFichier,
      participants: [for (final p in conversation.participants) p.nom],
      moi: moi,
      groupe: conversation.estGroupe,
      dateIncertaine: choisis.dateIncertaine,
      messages: List.unmodifiable(choisis.messages),
      creeLe: creeLe,
    );
  }

  /// Nom à donner à la conversation, d'après l'utilisateur confirmé :
  /// à deux, l'AUTRE participant (le nom du fichier peut désigner
  /// l'utilisateur lui-même, selon qui a exporté) ; en groupe, le nom du
  /// groupe. Sans réponse sûre, le titre détecté.
  static String titreContact(ConversationWhatsApp c, String? moi) {
    if (c.estGroupe || moi == null) return c.titre;
    final autres = [
      for (final p in c.participants)
        if (p.nom != moi) p.nom,
    ];
    return autres.length == 1 && autres.length < c.participants.length
        ? autres.single
        : c.titre;
  }

  /// Identifiant (UUID) choisi à la préparation, stable pendant toute la
  /// vie de la pièce jointe : c'est aussi celui du contexte enregistré
  /// (`conversation_contexts.id`) ; renvoyé tel quel lors d'un nouvel
  /// essai, il évite tout doublon.
  final String id;

  /// UUID du message de consigne qui la porte (`messages.id`), choisi
  /// lui aussi une fois pour toutes.
  final String idConsigne;

  /// Pièce jointe relue du serveur : nombre de messages et période
  /// enregistrés ([messages] est alors vide jusqu'au chargement).
  final int? nombreEnregistre;
  final DateTime? debutEnregistre;
  final DateTime? finEnregistre;

  /// Lit les messages enregistrés (pièce jointe relue du serveur).
  final Future<List<MessageWhatsApp>> Function()? chargerMessages;

  /// Vrai si les messages sont à lire sur le serveur.
  bool get distante => messages.isEmpty && chargerMessages != null;

  SourceConversation get source => SourceConversation.whatsapp;

  /// Nom du contact ou du groupe, tel que détecté (« Tony Stark »).
  final String titre;

  /// [ConversationWhatsApp.identifiant] de l'export lu.
  final String conversationSource;
  final String nomFichier;

  /// Participants de la conversation (pas seulement ceux des messages
  /// choisis), du plus actif au moins actif.
  final List<String> participants;

  /// Nom de l'utilisateur dans cette conversation, confirmé par lui.
  final String moi;
  final bool groupe;

  /// Jour et mois des dates supposés (voir [ConversationWhatsApp]).
  final bool dateIncertaine;

  /// Messages originaux choisis, dans l'ordre de l'export (ordre, auteur,
  /// date réelle et brute, texte, type, média).
  final List<MessageWhatsApp> messages;
  final DateTime creeLe;

  int get nombre =>
      messages.isNotEmpty ? messages.length : (nombreEnregistre ?? 0);

  /// Identifiants stables des messages (`m<ordre>`).
  List<String> get ids => [for (final m in messages) m.id];

  DateTime? get debut {
    for (final m in messages) {
      if (m.date != null) return m.date;
    }
    return debutEnregistre;
  }

  DateTime? get fin {
    for (final m in messages.reversed) {
      if (m.date != null) return m.date;
    }
    return finEnregistre;
  }

  /// La même pièce jointe avec ses messages lus.
  PieceJointeWhatsApp avecMessages(List<MessageWhatsApp> lus) =>
      PieceJointeWhatsApp(
        id: id,
        idConsigne: idConsigne,
        titre: titre,
        conversationSource: conversationSource,
        nomFichier: nomFichier,
        participants: participants,
        moi: moi,
        groupe: groupe,
        dateIncertaine: dateIncertaine,
        messages: List.unmodifiable(lus),
        creeLe: creeLe,
        nombreEnregistre: nombreEnregistre,
        debutEnregistre: debutEnregistre,
        finEnregistre: finEnregistre,
      );

  /// Message écrit par l'utilisateur lui-même (et non par le contact).
  bool estDeMoi(MessageWhatsApp m) => m.auteur == moi;

  /// Les messages joints sous forme de conversation, pour les relire avec
  /// l'aperçu existant.
  ConversationWhatsApp get commeConversation {
    final comptes = <String, int>{};
    for (final m in messages) {
      final a = m.auteur;
      if (a != null) comptes[a] = (comptes[a] ?? 0) + 1;
    }
    return ConversationWhatsApp(
      titre: titre,
      messages: messages,
      participants: [
        for (final p in participants)
          ParticipantWhatsApp(nom: p, messages: comptes[p] ?? 0),
      ],
      ordreDate: OrdreDate.jourMoisAnnee,
      dateIncertaine: dateIncertaine,
      lignesNonRattachees: const [],
      nombreLignesNonRattachees: 0,
      nomFichier: nomFichier,
    );
  }
}

/// Classement d'une conversation JARVIS après l'envoi d'une pièce jointe :
/// rangée sous sa source, avec le nom du contact. Préparé en mémoire ; son
/// enregistrement attend le stockage définitif des conversations.
class ClassementConversation {
  const ClassementConversation({
    required this.source,
    required this.titre,
    required this.pieceJointe,
  });

  final SourceConversation source;
  final String titre;

  /// Identifiant de la pièce jointe à l'origine du classement.
  final String pieceJointe;
}

/// Une consigne envoyée avec sa pièce jointe : ce qu'un futur dépôt
/// (conversations et pièces jointes) devra enregistrer.
class EnvoiPieceJointe {
  const EnvoiPieceJointe({
    required this.idConversation,
    required this.idMessage,
    required this.consigne,
    required this.pieceJointe,
    required this.nouvelleConversation,
    required this.envoyeLe,
  });

  /// Conversation JARVIS (identifiant local) qui reçoit le message.
  final String idConversation;

  /// Message de l'utilisateur qui porte la consigne et la pièce jointe.
  final int idMessage;
  final String consigne;
  final PieceJointeWhatsApp pieceJointe;

  /// Vrai si la conversation JARVIS a commencé avec cet envoi (accueil
  /// vide) ; faux si elle existait déjà.
  final bool nouvelleConversation;
  final DateTime envoyeLe;
}

/// Contrat du futur dépôt des pièces jointes (stockage définitif, à
/// définir). Aucune implémentation pour l'instant : rien n'est enregistré.
abstract interface class DepotPiecesJointes {
  /// Enregistre l'envoi (conversation, consigne, pièce jointe et ses
  /// messages originaux).
  Future<void> enregistrer(EnvoiPieceJointe envoi);

  /// Pièces jointes d'une conversation JARVIS.
  Future<List<PieceJointeWhatsApp>> deConversation(String idConversation);
}
