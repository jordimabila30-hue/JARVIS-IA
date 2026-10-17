import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/conversations/source_conversation.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/piece_jointe_whatsapp.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';
import 'package:ia_jarvis/services/importation/selection_whatsapp.dart';

import 'outils/conversations_whatsapp.dart';

/// Moteur espion : compte les demandes (aucune ne doit concerner une
/// pièce jointe).
class _MoteurEspion implements MoteurConversation {
  final demandes = <DemandeJarvis>[];

  @override
  Future<ReponseJarvis> repondre(DemandeJarvis demande) async {
    demandes.add(demande);
    return ReponseJarvis('Kinshasa.');
  }

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

ConversationWhatsApp _tony() => conv([
  msg(0, DateTime(2026, 10, 12, 9), auteur: 'Tony Stark', texte: 'Salut'),
  msg(1, DateTime(2026, 10, 12, 9, 5), auteur: 'Jordi', texte: 'Salut Tony'),
  msg(
    2,
    DateTime(2026, 10, 13, 8),
    type: TypeMessageWhatsApp.systeme,
    texte: 'Tony a changé de numéro',
  ),
  msg(
    3,
    DateTime(2026, 10, 14, 18),
    auteur: 'Tony Stark',
    texte: 'On se voit ?',
  ),
  msg(4, null, auteur: 'Jordi', texte: 'date illisible'),
]);

/// Les messages 1, 3 et 4 choisis dans l'interface 2.
PieceJointeWhatsApp _piece({String moi = 'Jordi'}) {
  final c = _tony();
  final s = SelectionWhatsApp(c)
    ..basculer('m1')
    ..basculer('m3')
    ..basculer('m4');
  return PieceJointeWhatsApp.depuis(
    conversation: c,
    choisis: s.resultat(),
    moi: moi,
    maintenant: DateTime(2026, 10, 15, 10),
  );
}

/// La réponse de JARVIS suit le message (délai de réflexion nul ici).
Future<void> _reponses() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('pièce jointe', () {
    test('exactement les messages choisis, dans l’ordre, avec leurs '
        'métadonnées', () {
      final p = _piece();
      expect(p.ids, ['m1', 'm3', 'm4']);
      expect(p.nombre, 3);
      expect(p.titre, 'Test');
      expect(p.source, SourceConversation.whatsapp);
      expect(p.moi, 'Jordi');
      expect(p.messages.first.auteur, 'Jordi');
      expect(p.messages[1].date, DateTime(2026, 10, 14, 18));
      expect(p.messages.last.date, isNull);
      expect(p.messages.last.dateBrute, isNotEmpty);
      expect(p.debut, DateTime(2026, 10, 12, 9, 5));
      expect(p.fin, DateTime(2026, 10, 14, 18));
      expect(p.estDeMoi(p.messages.first), isTrue);
      expect(p.estDeMoi(p.messages[1]), isFalse);
      expect(p.conversationSource, startsWith('wa-'));
      expect(p.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4')));
      expect(p.idConsigne, isNot(p.id));
      expect(_piece().id, isNot(p.id));
      // Relecture : la conversation des seuls messages joints.
      final relue = p.commeConversation;
      expect(relue.messages.map((m) => m.id), ['m1', 'm3', 'm4']);
      expect(relue.titre, 'Test');
    });

    test('à deux : le contact est l’autre participant, selon « Vous '
        'êtes »', () {
      // Fichier « … avec Pepper Potts » : le titre détecté ne dit pas qui
      // est l'utilisateur.
      final c = ConversationWhatsApp(
        titre: 'Pepper Potts',
        messages: [
          msg(0, DateTime(2026, 10, 1), auteur: 'Tony Stark'),
          msg(1, DateTime(2026, 10, 1, 1), auteur: 'Pepper Potts'),
        ],
        participants: const [
          ParticipantWhatsApp(nom: 'Tony Stark', messages: 1),
          ParticipantWhatsApp(nom: 'Pepper Potts', messages: 1),
        ],
        ordreDate: OrdreDate.jourMoisAnnee,
        dateIncertaine: false,
        lignesNonRattachees: const [],
        nombreLignesNonRattachees: 0,
        nomFichier: 'Discussion WhatsApp avec Pepper Potts.txt',
      );
      PieceJointeWhatsApp joindre(String moi) => PieceJointeWhatsApp.depuis(
        conversation: c,
        choisis: (SelectionWhatsApp(c)..cocherVisibles(true)).resultat(),
        moi: moi,
      );
      expect(joindre('Tony Stark').titre, 'Pepper Potts');
      expect(joindre('Pepper Potts').titre, 'Tony Stark');
      expect(PieceJointeWhatsApp.titreContact(c, null), 'Pepper Potts');
    });

    test('groupe : plusieurs participants, aucun « deux auteurs » supposé', () {
      final c = ConversationWhatsApp(
        titre: 'Avengers',
        messages: [
          msg(0, DateTime(2026, 10, 1), auteur: 'Tony'),
          msg(1, DateTime(2026, 10, 1, 1), auteur: 'Steve'),
          msg(2, DateTime(2026, 10, 1, 2), auteur: 'Natasha'),
        ],
        participants: const [
          ParticipantWhatsApp(nom: 'Tony', messages: 1),
          ParticipantWhatsApp(nom: 'Steve', messages: 1),
          ParticipantWhatsApp(nom: 'Natasha', messages: 1),
        ],
        ordreDate: OrdreDate.jourMoisAnnee,
        dateIncertaine: false,
        lignesNonRattachees: const [],
        nombreLignesNonRattachees: 0,
        nomFichier: 'g.txt',
      );
      final s = SelectionWhatsApp(c)..cocherVisibles(true);
      final p = PieceJointeWhatsApp.depuis(
        conversation: c,
        choisis: s.resultat(),
        moi: 'Steve',
      );
      expect(p.groupe, isTrue);
      expect(p.participants, ['Tony', 'Steve', 'Natasha']);
      expect(p.titre, 'Avengers');
    });
  });

  group('envoi avec la consigne', () {
    late _MoteurEspion moteur;
    late ConversationSession session;
    late List<EnvoiPieceJointe> envois;

    setUp(() {
      moteur = _MoteurEspion();
      session = ConversationSession(
        moteur: moteur,
        delaiReflexion: Duration.zero,
        horloge: () => DateTime(2026, 10, 15, 10),
      );
      envois = [];
      session.surPieceJointe = envois.add;
      addTearDown(session.dispose);
    });

    test('consigne vide : rien n’est envoyé', () async {
      await session.envoyerAvecPieceJointe('   ', _piece());
      await _reponses();
      expect(session.messages, isEmpty);
      expect(session.idCourant, isNull);
      expect(envois, isEmpty);
    });

    test('accueil vide : la conversation commence à l’envoi, consigne et '
        'pièce jointe liées, rien pour l’IA', () async {
      final p = _piece();
      expect(session.idCourant, isNull);
      await session.envoyerAvecPieceJointe('  Propose-moi une réponse.  ', p);
      await _reponses();
      expect(session.messages, hasLength(2));
      final question = session.messages.first;
      expect(question.texte, 'Propose-moi une réponse.');
      expect(identical(question.pieceJointe, p), isTrue);
      // Les messages WhatsApp ne deviennent ni du texte ni des messages
      // du fil.
      expect(question.conversation, isNull);
      expect(question.texte, isNot(contains('On se voit')));
      final reponse = session.messages.last;
      expect(reponse.deJarvis, isTrue);
      expect(reponse.texte, ConversationSession.reponsePieceJointe(p));
      expect(reponse.texte, contains('n’ont été envoyés à aucun serveur'));
      expect(reponse.enregistre, isFalse);
      // Jamais transmis au moteur (donc jamais à l'IA).
      expect(moteur.demandes, isEmpty);
      // Classement et événement préparés (aucune persistance).
      final id = session.idCourant!;
      expect(session.classement(id)!.titre, 'Test');
      expect(session.classement(id)!.source, SourceConversation.whatsapp);
      expect(envois.single.nouvelleConversation, isTrue);
      expect(envois.single.idConversation, id);
      expect(envois.single.consigne, 'Propose-moi une réponse.');
      expect(identical(envois.single.pieceJointe, p), isTrue);
    });

    test('chat déjà commencé : anciens échanges gardés, même conversation, '
        'classement seulement après l’envoi', () async {
      await session.envoyer('Quelle est la capitale de la RDC ?');
      final id = session.idCourant;
      expect(session.messages, hasLength(2));
      expect(session.classement(id!), isNull);
      await session.envoyerAvecPieceJointe('Analyse ces messages.', _piece());
      await _reponses();
      expect(session.idCourant, id);
      expect(session.messages, hasLength(4));
      expect(
        session.messages.first.texte,
        'Quelle est la capitale de la RDC ?',
      );
      expect(session.messages.first.pieceJointe, isNull);
      expect(session.messages[1].texte, 'Kinshasa.');
      expect(session.classement(id)!.titre, 'Test');
      expect(envois.single.nouvelleConversation, isFalse);
      // Seule la question ordinaire est passée par le moteur.
      expect(moteur.demandes, hasLength(1));
    });

    test('appuis répétés : une seule fois', () async {
      final p = _piece();
      final a = session.envoyerAvecPieceJointe('Résume.', p);
      final b = session.envoyerAvecPieceJointe('Résume.', p);
      await Future.wait([a, b]);
      expect(
        session.messages.where((m) => m.pieceJointe != null),
        hasLength(1),
      );
      expect(envois, hasLength(1));
    });

    test('aucun échange local confié au serveur', () async {
      var confies = 0;
      session.surEchangeLocal = (_) => confies++;
      await session.envoyerAvecPieceJointe('Explique.', _piece());
      await _reponses();
      expect(confies, 0);
    });

    test(
      'suppression de la conversation : son classement est oublié',
      () async {
        await session.envoyerAvecPieceJointe('Explique.', _piece());
        await _reponses();
        final id = session.idCourant!;
        session.supprimer(id);
        expect(session.classement(id), isNull);
      },
    );
  });
}
