import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/conversations/apercu_conversation.dart';
import 'package:ia_jarvis/models/conversations/source_conversation.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/piece_jointe_whatsapp.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';
import 'package:ia_jarvis/services/conversations/conversations_multicanal.dart';
import 'package:ia_jarvis/services/conversations/epingles_conversations.dart';
import 'package:ia_jarvis/services/conversations/fournisseur_conversations.dart';
import 'package:ia_jarvis/services/conversations/fournisseur_jarvis.dart';
import 'package:ia_jarvis/services/importation/selection_whatsapp.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

import 'outils/conversations_whatsapp.dart';

class _Moteur implements MoteurConversation {
  @override
  Future<ReponseJarvis> repondre(DemandeJarvis demande) async =>
      const ReponseJarvis('Kinshasa.');
  @override
  void reinitialiser() {}
  @override
  Object? capturerContexte() => null;
  @override
  void restaurerContexte(Object? contexte) {}
  @override
  Future<String> proposerReponse(
    ConversationExterne conversation,
    TonReponse ton,
  ) async => '';
}

/// Pièce jointe de la conversation [titre] (contact) où l'utilisateur est
/// « Jordi ».
PieceJointeWhatsApp _piece(String titre, {List<String>? autres}) {
  final noms = autres ?? [titre];
  final c = ConversationWhatsApp(
    titre: titre,
    messages: [
      for (var i = 0; i < noms.length; i++)
        msg(i, DateTime(2026, 10, 14, 9, i), auteur: noms[i], texte: 'Salut'),
      msg(noms.length, DateTime(2026, 10, 14, 10), auteur: 'Jordi'),
    ],
    participants: [
      for (final n in noms) ParticipantWhatsApp(nom: n, messages: 1),
      const ParticipantWhatsApp(nom: 'Jordi', messages: 1),
    ],
    ordreDate: OrdreDate.jourMoisAnnee,
    dateIncertaine: false,
    lignesNonRattachees: const [],
    nombreLignesNonRattachees: 0,
    nomFichier: '$titre.txt',
  );
  return PieceJointeWhatsApp.depuis(
    conversation: c,
    choisis: (SelectionWhatsApp(c)..cocherVisibles(true)).resultat(),
    moi: 'Jordi',
  );
}

/// La réponse de JARVIS suit le message (délai de réflexion nul ici).
Future<void> _reponses() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late ConversationSession session;
  late FournisseurJarvis jarvis;
  late ConversationsMulticanal multicanal;

  setUp(() {
    session = ConversationSession(
      moteur: _Moteur(),
      delaiReflexion: Duration.zero,
    );
    jarvis = FournisseurJarvis(session);
    final epingles = EpinglesConversations(stockage: StockageMemoire());
    // Comme l'accueil : l'épingle suit le chat reclassé.
    session.surPieceJointe = (e) => epingles.deplacer(
      'jarvis:${e.idConversation}',
      '${e.pieceJointe.source.name}:${e.idConversation}',
    );
    multicanal = ConversationsMulticanal(
      fournisseurs: [
        jarvis,
        FournisseurSourceClassee(SourceConversation.whatsapp, jarvis),
        FournisseurNonIntegre(SourceConversation.gmail),
      ],
      epingles: epingles,
    );
    addTearDown(multicanal.dispose);
    addTearDown(session.dispose);
  });

  List<ApercuConversation> liste(SourceConversation s, [String q = '']) =>
      multicanal.liste(s, requete: q);

  test('accueil vide : le chat naît à l’envoi, sous WhatsApp, au nom du '
      'contact, jamais sous JARVIS', () async {
    expect(liste(SourceConversation.whatsapp), isEmpty);
    await session.envoyerAvecPieceJointe('analyse', _piece('Pepper Potts'));
    await _reponses();
    final w = liste(SourceConversation.whatsapp);
    expect(w, hasLength(1));
    expect(w.single.titre, 'Pepper Potts');
    expect(w.single.id, session.idCourant);
    expect(w.single.source, SourceConversation.whatsapp);
    expect(w.single.ouverte, isTrue);
    expect(liste(SourceConversation.jarvis), isEmpty);
    expect(liste(SourceConversation.gmail), isEmpty);
  });

  test('chat JARVIS commencé : même chat reclassé à l’envoi seulement, '
      'historique intact, aucun doublon', () async {
    await session.envoyer('Quelle est la capitale de la RDC ?');
    final id = session.idCourant!;
    expect(
      liste(SourceConversation.jarvis).single.titre,
      'Quelle est la capitale de la RDC ?',
    );
    // Pièce jointe préparée puis retirée (rien n'est envoyé) : aucun
    // reclassement.
    _piece('Tony Stark');
    expect(liste(SourceConversation.jarvis), hasLength(1));
    expect(liste(SourceConversation.whatsapp), isEmpty);
    // Consigne vide : toujours rien.
    await session.envoyerAvecPieceJointe('  ', _piece('Tony Stark'));
    await _reponses();
    expect(liste(SourceConversation.whatsapp), isEmpty);

    await session.envoyerAvecPieceJointe(
      'Analyse ces messages.',
      _piece('Tony Stark'),
    );

    await _reponses();
    expect(session.idCourant, id);
    expect(liste(SourceConversation.jarvis), isEmpty);
    final w = liste(SourceConversation.whatsapp);
    expect(w, hasLength(1));
    expect(w.single.id, id);
    expect(w.single.titre, 'Tony Stark');
    // Jamais la consigne ni le nom de l'utilisateur comme titre.
    expect(w.single.titre, isNot('Analyse ces messages.'));
    expect(w.single.titre, isNot('Jordi'));
    // Historique déplacé avec le chat, pas copié ni effacé.
    expect(session.messages.map((m) => m.texte), [
      'Quelle est la capitale de la RDC ?',
      'Kinshasa.',
      'Analyse ces messages.',
      ConversationSession.reponsePieceJointe(session.messages[2].pieceJointe!),
    ]);
  });

  test('recherche dans le bon onglet', () async {
    await session.envoyerAvecPieceJointe('analyse', _piece('Tony Stark'));
    await _reponses();
    expect(liste(SourceConversation.whatsapp, 'tony'), hasLength(1));
    expect(liste(SourceConversation.jarvis, 'tony'), isEmpty);
  });

  test('chat mis de côté (« Nouvelle conversation ») : toujours sous '
      'WhatsApp, rouvrable', () async {
    await session.envoyerAvecPieceJointe('analyse', _piece('Pepper Potts'));
    await _reponses();
    final id = session.idCourant!;
    session.effacer();
    await session.envoyer('Quelle heure est-il ?');
    final w = liste(SourceConversation.whatsapp);
    expect(w.single.id, id);
    expect(w.single.ouverte, isFalse);
    expect(liste(SourceConversation.jarvis), hasLength(1));
    expect(multicanal.ouvrir(w.single), isTrue);
    expect(session.idCourant, id);
    expect(session.messages.first.texte, 'analyse');
  });

  test('épingle : suit le chat reclassé', () async {
    await session.envoyer('Bonjour');
    multicanal.epingles.basculer(liste(SourceConversation.jarvis).single);
    await session.envoyerAvecPieceJointe('analyse', _piece('Tony Stark'));
    await _reponses();
    final w = liste(SourceConversation.whatsapp).single;
    expect(multicanal.epingles.estEpinglee(w), isTrue);
  });

  test('suppression depuis l’onglet WhatsApp', () async {
    await session.envoyerAvecPieceJointe('analyse', _piece('Tony Stark'));
    await _reponses();
    final w = liste(SourceConversation.whatsapp).single;
    multicanal.epingles.basculer(w);
    expect(await multicanal.supprimer(w), isTrue);
    expect(liste(SourceConversation.whatsapp), isEmpty);
    expect(liste(SourceConversation.jarvis), isEmpty);
    expect(session.vide, isTrue);
    expect(multicanal.epingles.estEpinglee(w), isFalse);
  });

  test('groupe : son nom', () async {
    await session.envoyerAvecPieceJointe(
      'résume',
      _piece('Avengers', autres: ['Tony', 'Steve', 'Natasha']),
    );
    await _reponses();
    expect(liste(SourceConversation.whatsapp).single.titre, 'Avengers');
  });

  test('le panneau est prévenu du reclassement', () async {
    var avis = 0;
    multicanal.addListener(() => avis++);
    await session.envoyerAvecPieceJointe('analyse', _piece('Tony Stark'));
    await _reponses();
    expect(avis, greaterThan(0));
  });
}
