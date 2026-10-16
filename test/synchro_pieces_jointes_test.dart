import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/importation/reference_whatsapp.dart';
import 'package:ia_jarvis/models/conversations/source_conversation.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/piece_jointe_whatsapp.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';
import 'package:ia_jarvis/services/conversations/conversations_multicanal.dart';
import 'package:ia_jarvis/services/conversations/depot_conversations.dart';
import 'package:ia_jarvis/services/conversations/epingles_conversations.dart';
import 'package:ia_jarvis/services/conversations/fournisseur_jarvis.dart';
import 'package:ia_jarvis/services/conversations/synchronisation_conversations.dart';
import 'package:ia_jarvis/services/importation/pieces_jointes_serveur.dart';
import 'package:ia_jarvis/services/importation/selection_whatsapp.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

import 'outils/conversations_whatsapp.dart';

// --- « Serveur » partagé : ce que Supabase garde pour un compte --------------

class _Serveur {
  final conversations = <String, String>{}; // id -> titre
  final messages = <String, List<MessageServeur>>{};
  final contextes = <String, List<ContexteServeur>>{};
  final messagesContexte = <String, List<MessageWhatsApp>>{};
  int _n = 0;
  String nouvelId() =>
      '00000000-0000-4000-8000-${(_n++).toString().padLeft(12, '0')}';
}

class _Service implements ServicePiecesJointes {
  _Service(this.serveur);
  final _Serveur serveur;
  final appels = <Map<String, dynamic>>[];
  ErreurApi? echec;
  Completer<void>? retenue;

  @override
  Future<ResultatApi<PieceJointeEnregistree>> enregistrer({
    required PieceJointeWhatsApp piece,
    required String consigne,
    String? conversation,
  }) async {
    final corps = PiecesJointesApi.corps(
      piece: piece,
      consigne: consigne,
      conversation: conversation,
    );
    appels.add(corps);
    await retenue?.future;
    final e = echec;
    if (e != null) return EchecApi(e);
    // Réessai : le même contexte, rien de plus.
    for (final liste in serveur.contextes.entries) {
      for (final c in liste.value) {
        if (c.id == piece.id) {
          return SuccesApi(
            PieceJointeEnregistree(
              conversation: liste.key,
              consigne: c.consigne!,
              contexte: c.id,
              nombre: c.nombre,
              dejaEnregistree: true,
              conversationCreee: false,
            ),
          );
        }
      }
    }
    final conv = conversation ?? serveur.nouvelId();
    final creee = conversation == null;
    serveur.conversations[conv] = piece.titre;
    (serveur.messages[conv] ??= []).add(
      MessageServeur(
        id: piece.idConsigne,
        role: 'user',
        contenu: consigne,
        date: DateTime(2026, 10, 15, 10, serveur._n),
      ),
    );
    (serveur.contextes[conv] ??= []).add(
      ContexteServeur(
        id: piece.id,
        consigne: piece.idConsigne,
        contact: piece.titre,
        nombre: piece.nombre,
        creeLe: DateTime(2026, 10, 15, 10, serveur._n),
        participants: piece.participants,
        moi: piece.moi,
      ),
    );
    serveur.messagesContexte[piece.id] = [
      for (final m in corps['messages'] as List)
        PiecesJointesApi.versMessage(m as Map<String, dynamic>),
    ];
    return SuccesApi(
      PieceJointeEnregistree(
        conversation: conv,
        consigne: piece.idConsigne,
        contexte: piece.id,
        nombre: piece.nombre,
        dejaEnregistree: false,
        conversationCreee: creee,
      ),
    );
  }

  @override
  Future<ResultatApi<List<MessageWhatsApp>>> messages(String id) async {
    final m = serveur.messagesContexte[id];
    return m == null
        ? const EchecApi(ErreurApi.pieceJointeIntrouvable)
        : SuccesApi(m);
  }

  @override
  Future<ResultatApi<void>> supprimer(String id) async {
    for (final l in serveur.contextes.values) {
      l.removeWhere((c) => c.id == id);
    }
    serveur.messagesContexte.remove(id);
    return const SuccesApi(null);
  }

  @override
  Future<ResultatApi<PageWhatsApp>> page(
    String id, {
    required int apres,
    required int limite,
  }) async => SuccesApi(
    PageWhatsApp(premier: apres + 1, messages: const [], suite: false),
  );

  @override
  Future<ResultatApi<Map<String, ReferencesReponse>>> references(
    String conversation,
  ) async => const SuccesApi({});
}

class _Depot implements DepotConversations {
  _Depot(this.serveur);
  final _Serveur serveur;

  @override
  String? get utilisateur => 'compte-1';

  @override
  Future<List<ConversationServeur>> lister({int limite = 100}) async => [
    for (final e in serveur.conversations.entries)
      ConversationServeur(
        id: e.key,
        titre: e.value,
        derniereActivite: DateTime(2026, 10, 15),
        contextes: List.of(serveur.contextes[e.key] ?? const []),
      ),
  ];

  @override
  Future<PageMessages> messages(
    String id, {
    DateTime? avant,
    int limite = 50,
  }) async => PageMessages(
    List.of(serveur.messages[id] ?? const []),
    contextes: List.of(serveur.contextes[id] ?? const []),
  );

  @override
  Future<void> supprimer(String id) async {
    serveur.conversations.remove(id);
    serveur.messages.remove(id);
    serveur.contextes.remove(id);
  }
}

class _Moteur implements MoteurConversation {
  final demandes = <DemandeJarvis>[];
  @override
  Future<ReponseJarvis> repondre(DemandeJarvis d) async {
    demandes.add(d);
    return const ReponseJarvis('Kinshasa.');
  }

  @override
  void reinitialiser() {}
  @override
  Object? capturerContexte() => null;
  @override
  void restaurerContexte(Object? contexte) {}
  @override
  Future<String> proposerReponse(ConversationExterne c, TonReponse t) async =>
      '';
}

PieceJointeWhatsApp _piece({int n = 35, String contact = 'Tony Stark'}) {
  final c = ConversationWhatsApp(
    titre: contact,
    messages: [
      for (var i = 0; i < n; i++)
        msg(
          i,
          i == n - 1 ? null : DateTime(2026, 10, 12, 9, i % 60),
          auteur: i.isEven ? contact : 'Pepper Potts',
          texte: 'message $i',
        ),
    ],
    participants: [
      ParticipantWhatsApp(nom: contact, messages: n),
      const ParticipantWhatsApp(nom: 'Pepper Potts', messages: 1),
    ],
    ordreDate: OrdreDate.jourMoisAnnee,
    dateIncertaine: false,
    lignesNonRattachees: const [],
    nombreLignesNonRattachees: 0,
    nomFichier: 'chat.txt',
  );
  return PieceJointeWhatsApp.depuis(
    conversation: c,
    choisis: (SelectionWhatsApp(c)..cocherVisibles(true)).resultat(),
    moi: 'Pepper Potts',
  );
}

Future<void> _reponses() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late _Serveur serveur;
  late _Service service;
  late _Moteur moteur;

  ConversationSession appareil() => ConversationSession(
    moteur: moteur,
    delaiReflexion: Duration.zero,
    depot: _Depot(serveur),
    piecesJointes: service,
  );

  setUp(() {
    serveur = _Serveur();
    service = _Service(serveur);
    moteur = _Moteur();
  });

  group('sauvegarde à l’envoi', () {
    test(
      'accueil vide : enregistrée, conversation créée, puis analysée',
      () async {
        final s = appareil();
        addTearDown(s.dispose);
        final p = _piece();
        final r = await s.envoyerAvecPieceJointe(
          'Analyse cette conversation.',
          p,
        );
        await _reponses();
        expect(r, isA<PieceJointeEnvoyee>());
        expect((r as PieceJointeEnvoyee).enregistree, isTrue);
        final appel = service.appels.single;
        expect(appel['conversation_id'], isNull);
        expect(appel['context_id'], p.id);
        expect(appel['message_id'], p.idConsigne);
        expect(appel['instruction'], 'Analyse cette conversation.');
        expect((appel['messages'] as List), hasLength(35));
        final consigne = s.messages.first;
        expect(consigne.idServeur, p.idConsigne);
        expect(consigne.enregistre, isTrue);
        expect(identical(consigne.pieceJointe, p), isTrue);
        expect(s.idServeurCourant, serveur.conversations.keys.single);
        // Une fois enregistrée, la consigne part au moteur comme réponse
        // à attendre (jamais renvoyée ni réinsérée par le serveur).
        final d = moteur.demandes.single;
        expect(d.repondreA, p.idConsigne);
        expect(d.contexteImporte, isTrue);
        expect(d.texte, 'Analyse cette conversation.');
        expect(d.idConversation, s.idCourant);
        expect(s.messages.last.texte, 'Kinshasa.');
        expect(s.messages, hasLength(2));
      },
    );

    test('chat existant : même conversation serveur, anciens messages '
        'gardés', () async {
      final s = appareil();
      addTearDown(s.dispose);
      serveur.conversations['conv-rdc'] = 'Capitale de la RDC';
      serveur.messages['conv-rdc'] = [
        MessageServeur(
          id: 'q1',
          role: 'user',
          contenu: 'Quelle est la capitale de la RDC ?',
          date: DateTime(2026, 10, 14),
        ),
        MessageServeur(
          id: 'r1',
          role: 'assistant',
          contenu: 'Kinshasa.',
          date: DateTime(2026, 10, 14, 0, 1),
        ),
      ];
      await s.ouvrirServeur('conv-rdc');
      await s.envoyerAvecPieceJointe('Analyse.', _piece());
      await _reponses();
      expect(service.appels.single['conversation_id'], 'conv-rdc');
      expect(s.idCourant, 'conv-rdc');
      expect(s.messages.map((m) => m.texte).take(3), [
        'Quelle est la capitale de la RDC ?',
        'Kinshasa.',
        'Analyse.',
      ]);
      expect(s.classement('conv-rdc')!.titre, 'Tony Stark');
      expect(serveur.conversations, hasLength(1));
    });

    test('erreur réseau : rien d’ajouté, puis nouvel essai avec les mêmes '
        'identifiants, sans doublon', () async {
      final s = appareil();
      addTearDown(s.dispose);
      await s.envoyer('Quelle heure est-il ?');
      await _reponses();
      final avant = s.messages.length;
      final p = _piece();
      service.echec = ErreurApi.injoignable;
      final r = await s.envoyerAvecPieceJointe('Analyse.', p);
      expect(r, isA<PieceJointeNonEnvoyee>());
      expect(
        (r as PieceJointeNonEnvoyee).raison,
        ErreurApi.injoignable.message,
      );
      expect(s.messages, hasLength(avant)); // rien de faux, rien de perdu
      expect(s.classement(s.idCourant!), isNull);
      service.echec = null;
      final r2 = await s.envoyerAvecPieceJointe('Analyse.', p);
      await _reponses();
      expect(r2, isA<PieceJointeEnvoyee>());
      expect(service.appels, hasLength(2));
      expect(service.appels[0]['context_id'], service.appels[1]['context_id']);
      expect(service.appels[0]['message_id'], service.appels[1]['message_id']);
      expect(serveur.contextes.values.single, hasLength(1));
    });

    test('double envoi simultané : un seul enregistrement', () async {
      final s = appareil();
      addTearDown(s.dispose);
      final p = _piece();
      service.retenue = Completer<void>();
      final a = s.envoyerAvecPieceJointe('Analyse.', p);
      final b = s.envoyerAvecPieceJointe('Analyse.', p);
      service.retenue!.complete();
      final r = await Future.wait([a, b]);
      await _reponses();
      expect(r.whereType<PieceJointeEnvoyee>(), hasLength(1));
      expect(r.whereType<PieceJointeIgnoree>(), hasLength(1));
      expect(service.appels, hasLength(1));
      expect(s.messages.where((m) => m.pieceJointe != null), hasLength(1));
    });

    test('compte refusé par le serveur : pas de succès affiché', () async {
      final s = appareil();
      addTearDown(s.dispose);
      service.echec = ErreurApi.jetonRefuse;
      final r = await s.envoyerAvecPieceJointe('Analyse.', _piece());
      expect(r, isA<PieceJointeNonEnvoyee>());
      expect(s.messages, isEmpty);
      expect(s.idCourant, isNull);
    });
  });

  group('restauration et synchronisation', () {
    test('autre appareil (ou redémarrage) : chat retrouvé sous WhatsApp, '
        'carte rattachée à la consigne, messages lus à la demande', () async {
      // Appareil 1 (Android) : envoie.
      final android = appareil();
      addTearDown(android.dispose);
      final p = _piece();
      await android.envoyerAvecPieceJointe('Analyse cette conversation.', p);
      await _reponses();
      final conv = android.idServeurCourant!;

      // Appareil 2 (Windows / Web), même compte : rien en mémoire.
      final windows = appareil();
      addTearDown(windows.dispose);
      final sync = SynchronisationConversations(_Depot(serveur));
      addTearDown(sync.dispose);
      final jarvis = FournisseurJarvis(windows, synchronisation: sync);
      final multicanal = ConversationsMulticanal(
        fournisseurs: [
          jarvis,
          FournisseurSourceClassee(SourceConversation.whatsapp, jarvis),
        ],
        epingles: EpinglesConversations(stockage: StockageMemoire()),
      );
      addTearDown(multicanal.dispose);
      await sync.actualiser(force: true);
      final w = multicanal.liste(SourceConversation.whatsapp);
      expect(w.single.id, conv);
      expect(w.single.titre, 'Tony Stark');
      expect(multicanal.liste(SourceConversation.jarvis), isEmpty);

      // Ouverture : consigne + carte (métadonnées), classement gardé.
      expect(multicanal.ouvrir(w.single), isTrue);
      await _reponses();
      final consigne = windows.messages.single;
      expect(consigne.texte, 'Analyse cette conversation.');
      final restauree = consigne.pieceJointe!;
      expect(restauree.id, p.id);
      expect(restauree.nombre, 35);
      expect(restauree.messages, isEmpty);
      expect(restauree.distante, isTrue);
      expect(windows.classement(conv)!.titre, 'Tony Stark');
      expect(
        multicanal.liste(SourceConversation.whatsapp).single.ouverte,
        isTrue,
      );
      // « Voir les messages » : lus sur le serveur, dans l'ordre.
      final lus = await restauree.chargerMessages!();
      expect(lus, hasLength(35));
      expect(lus.first.texte, 'message 0');
      expect(lus.last.date, isNull); // date illisible : jamais inventée
      expect(
        restauree.avecMessages(lus).commeConversation.messages,
        hasLength(35),
      );

      // Nouvel import depuis Windows, dans le même chat.
      await windows.envoyerAvecPieceJointe('Et les nouveaux ?', _piece(n: 10));
      await _reponses();
      expect(service.appels.last['conversation_id'], conv);
      expect(serveur.contextes[conv], hasLength(2));

      // Android relit : les deux pièces jointes, sur leurs consignes.
      final android2 = appareil();
      addTearDown(android2.dispose);
      await android2.ouvrirServeur(conv);
      await _reponses();
      final cartes = [
        for (final m in android2.messages)
          if (m.pieceJointe != null) m.pieceJointe!.nombre,
      ];
      expect(cartes, [35, 10]);
    });

    test('suppression d’une pièce jointe : absente après actualisation, '
        'les autres restent', () async {
      final s = appareil();
      addTearDown(s.dispose);
      final a = _piece(), b = _piece(n: 3);
      await s.envoyerAvecPieceJointe('Premier.', a);
      await _reponses();
      await s.envoyerAvecPieceJointe('Second.', b);
      await _reponses();
      final conv = s.idServeurCourant!;
      await service.supprimer(a.id);
      final autre = appareil();
      addTearDown(autre.dispose);
      await autre.ouvrirServeur(conv);
      await _reponses();
      expect([for (final m in autre.messages) ?m.pieceJointe?.id], [b.id]);
      // La consigne d'origine reste (le contexte seul est supprimé).
      expect(autre.messages.map((m) => m.texte), contains('Premier.'));
    });
  });

  group('format d’échange', () {
    test('uniquement les messages sélectionnés, sans fichier ni fuseau', () {
      final p = _piece(n: 3);
      final c = PiecesJointesApi.corps(
        piece: p,
        consigne: 'Analyse.',
        conversation: 'conv',
      );
      expect(c['context']['contact_name'], 'Tony Stark');
      expect(c['context']['current_user_name'], 'Pepper Potts');
      expect(c['context']['source'], 'whatsapp');
      final m = c['messages'] as List;
      expect(m, hasLength(3));
      expect(m.first['message_order'], 0);
      expect(m.first['sent_at'], '2026-10-12T09:00:00');
      expect(m.last['sent_at'], isNull);
      expect(m.first['kind'], 'text');
      expect(jsonEncode(c), isNot(contains('.zip')));
      final relu = PiecesJointesApi.versMessage(
        m.first as Map<String, dynamic>,
      );
      expect(relu.date, DateTime(2026, 10, 12, 9));
      expect(relu.texte, 'message 0');
    });

    test('client HTTP : codes du serveur traduits', () async {
      Future<ResultatApi<Map<String, dynamic>>> avec(int code, String corps) {
        final api = ApiJarvis(
          adresse: Uri.parse('http://127.0.0.1:8000'),
          jeton: () async => 'jeton',
          client: MockClient((r) async {
            expect(r.headers['Authorization'], 'Bearer jeton');
            expect(r.url.path, '/api/v1/conversations/contexts');
            return http.Response(corps, code);
          }),
        );
        return api.enregistrerContexte({'context_id': 'x'});
      }

      expect(
        await avec(
          201,
          '{"conversation_id":"c","message_id":"m","context_id":"x",'
          '"messages_count":2,"conversation_created":true,"already_saved":false}',
        ),
        isA<SuccesApi<Map<String, dynamic>>>(),
      );
      for (final (code, attendu) in [
        (409, ErreurApi.pieceJointeRefusee),
        (422, ErreurApi.pieceJointeRefusee),
        (413, ErreurApi.pieceJointeTropVolumineuse),
        (404, ErreurApi.conversationIntrouvable),
        (503, ErreurApi.indisponible),
        (401, ErreurApi.jetonRefuse),
      ]) {
        final r = await avec(code, '{"detail":"x"}');
        expect((r as EchecApi).type, attendu, reason: '$code');
      }
    });
  });
}
