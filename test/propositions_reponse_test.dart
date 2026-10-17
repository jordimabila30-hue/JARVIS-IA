// Phase 3 : aide à répondre et à relancer. Propositions reçues du serveur
// (tous les tons d'un coup), carte des tons sous la réponse, copie,
// changement de ton sans appel à l'IA, ton transmis pour « pourquoi la
// deuxième ? », restauration d'un chat rouvert. Serveur simulé ;
// conversations fictives.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/piece_jointe_whatsapp.dart';
import 'package:ia_jarvis/models/importation/propositions_reponse.dart';
import 'package:ia_jarvis/models/importation/reference_whatsapp.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_hybride.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_ia.dart';
import 'package:ia_jarvis/services/conversations/correspondance_conversations.dart';
import 'package:ia_jarvis/services/conversations/depot_conversations.dart';
import 'package:ia_jarvis/services/importation/pieces_jointes_serveur.dart';
import 'package:ia_jarvis/widgets/conversation/carte_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/propositions_jarvis.dart';

const _conv = '33333333-3333-4333-8333-333333333333';
const _ctx = 'aaaaaaaa-0000-4000-8000-000000000001';

Map<String, Object?> _ton(String nom, List<String> textes) => {
  'nom': nom,
  'propositions': [
    for (final (i, t) in textes.indexed)
      {
        'id': '$nom-${i + 1}',
        'texte': t,
        'approche': 'approche ${i + 1}',
        'appuis': [
          if (i == 0)
            {
              'context_id': _ctx,
              'context_message_id': 'm8',
              'message_order': 8,
            },
        ],
      },
  ],
};

final _propositions = {
  'mode': 'reponse',
  'context_id': _ctx,
  'tons': [
    _ton('Taquin', [
      'Ministre, non. Président, à la rigueur 😏',
      'Et toi, depuis quand tu comptes mes minutes ?',
      'OK, j’apporte le café pour me faire pardonner.',
    ]),
    _ton('Naturel', [
      'Désolé pour le retard, j’arrive !',
      'Je suis là dans 10 minutes, promis.',
      'Tu veux que je ramène quelque chose ?',
    ]),
    _ton('Sérieux', [
      'Tu as raison, je dois être plus ponctuel.',
      'J’étais coincé en réunion, désolé.',
      'La prochaine fois je te préviens avant.',
    ]),
  ],
};

String _evenement(String type, Object donnees) =>
    'event: $type\ndata: ${jsonEncode(donnees)}\n\n';

http.Response _sse(String corps) => http.Response.bytes(
  utf8.encode(corps),
  200,
  headers: {'content-type': 'text/event-stream; charset=utf-8'},
);

MessageConversation _reponse(PropositionsReponse p) => MessageConversation(
  id: 7,
  auteur: AuteurMessage.jarvis,
  heure: DateTime(2026, 10, 15, 10),
  texte: 'Pepper t’a écrit en dernier, en te taquinant. Voici des idées.',
  propositions: p,
);

Future<void> _carte(
  WidgetTester tester,
  MessageConversation m, {
  double largeur = 390,
  SurReglagePropositions? surTon,
}) async {
  tester.view.physicalSize = Size(largeur, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CarteJarvis(
            message: m,
            surTon: (_) {},
            surAction: (_) {},
            surTonPropositions: surTon,
          ),
        ),
      ),
    ),
  );
}

class _Service implements ServicePiecesJointes {
  Map<String, ReferencesReponse> refs = {};

  @override
  Future<ResultatApi<Map<String, ReferencesReponse>>> references(
    String conversation,
  ) async => SuccesApi(refs);

  @override
  Future<ResultatApi<PageWhatsApp>> page(
    String id, {
    required int apres,
    required int limite,
  }) async =>
      const SuccesApi(PageWhatsApp(premier: 0, messages: [], suite: false));

  @override
  Future<ResultatApi<PieceJointeEnregistree>> enregistrer({
    required PieceJointeWhatsApp piece,
    required String consigne,
    String? conversation,
  }) async => const EchecApi(ErreurApi.serveur);

  @override
  Future<ResultatApi<List<MessageWhatsApp>>> messages(String id) async =>
      const SuccesApi([]);

  @override
  Future<ResultatApi<void>> supprimer(String id) async => const SuccesApi(null);
}

class _Depot implements DepotConversations {
  _Depot(this.lignes, this.contextes);
  final List<MessageServeur> lignes;
  final List<ContexteServeur> contextes;

  @override
  String? get utilisateur => 'compte-1';

  @override
  Future<List<ConversationServeur>> lister({int limite = 100}) async => [];

  @override
  Future<PageMessages> messages(
    String id, {
    DateTime? avant,
    int limite = 50,
  }) async => PageMessages(List.of(lignes), contextes: contextes);

  @override
  Future<void> supprimer(String id) async {}
}

void main() {
  group('modèle', () {
    test('exactement trois propositions par ton ; ton incomplet ignoré', () {
      final p = PropositionsReponse.depuisJson({
        'mode': 'relance',
        'tons': [
          _ton('Amical', ['a', 'b']),
          _ton('Direct', ['On se voit samedi ?', 'Libre ce soir ?', 'Café ?']),
          {'nom': '', 'propositions': []},
        ],
      })!;
      expect(p.mode, ModeProposition.relance);
      expect(p.mode.titre, 'Idées de relance');
      expect(p.tons.map((t) => t.nom), ['Direct']);
      expect(p.tons.single.propositions.length, 3);
      expect(PropositionsReponse.depuisJson({'tons': []}), isNull);
      expect(PropositionsReponse.depuisJson('x'), isNull);
    });

    test('jamais un ton à moitié : 3 par longueur, les 3 longueurs', () {
      Map<String, dynamic> ton(String nom, Map<String, int> parLongueur) => {
        'nom': nom,
        'propositions': [
          for (final MapEntry(key: l, value: n) in parLongueur.entries)
            for (var i = 1; i <= n; i++)
              {'id': '$nom-$l-$i', 'texte': '$nom $l $i', 'longueur': l},
        ],
      };
      final complet = ton('Amical', {'court': 3, 'moyen': 3, 'long': 3});
      final p = PropositionsReponse.depuisJson({
        'longueurs': ['court', 'moyen', 'long'],
        'tons': [
          complet,
          ton('Taquin', {'court': 1, 'moyen': 1, 'long': 1}), // défaut réel
          ton('Direct', {'court': 3, 'moyen': 3}), // longueur absente
        ],
      })!;
      expect(p.tons.map((t) => t.nom), ['Amical']);
      expect(p.incomplet, isFalse);
      // Un ancien mode « partiel » n'existe plus : rien n'est accepté.
      expect(
        PropositionsReponse.depuisJson({
          'partiel': true,
          'tons': [
            ton('Taquin', {'court': 1, 'moyen': 1, 'long': 1}),
          ],
        }),
        isNull,
      );
    });

    test('génération incomplète : aucun texte, état à reprendre', () {
      final p = PropositionsReponse.depuisJson({
        'statut': 'incomplet',
        'mode': 'relance',
        'raison': 'quota',
        'ensemble': 'r0',
        'tons': [],
      })!;
      expect(p.incomplet, isTrue);
      expect(p.tons, isEmpty);
      expect(p.raison, 'quota');
      expect(p.ensemble, 'r0');
      expect(p.mode, ModeProposition.relance);
    });

    test('appuis : rangs des messages d’origine', () {
      final p = PropositionsReponse.depuisJson(_propositions)!;
      expect(p.tons.first.propositions.first.appuis, [8]);
      expect(p.tons.first.propositions.first.approche, 'approche 1');
    });
  });

  group('flux et session', () {
    test('événement « propositions » rattaché à la réponse ; changer de ton '
        'n’appelle pas l’IA ; le ton regardé part avec la question '
        'suivante', () async {
      final corps = <Map<String, dynamic>>[];
      final client = MockClient((r) async {
        corps.add(jsonDecode(r.body) as Map<String, dynamic>);
        final premier = corps.length == 1;
        return _sse(
          _evenement('meta', {
                'conversation_id': _conv,
                'message_id': 'r${corps.length}',
              }) +
              _evenement('delta', {
                'text': premier
                    ? 'Pepper t’a écrit en dernier. Voici des idées.'
                    : 'Parce qu’elle te taquine.',
              }) +
              (premier
                  ? _evenement('propositions', {
                      'message_id': 'r1',
                      ..._propositions,
                    })
                  : '') +
              _evenement('done', {'message_id': 'r${corps.length}'}),
        );
      });
      final api = ApiJarvis(
        adresse: Uri.parse('http://localhost:8000'),
        jeton: () async => 'jeton',
        client: client,
      );
      final s = ConversationSession(
        delaiReflexion: Duration.zero,
        moteur: MoteurConversationHybride(
          ia: MoteurConversationIA(api, analyseWhatsApp: () => 'allowed'),
        ),
      );
      addTearDown(s.dispose);
      await s.envoyer('Aide-moi à lui répondre');
      final m = s.messages.last;
      expect(m.texte, 'Pepper t’a écrit en dernier. Voici des idées.');
      expect(m.propositions!.tons.map((t) => t.nom), [
        'Taquin',
        'Naturel',
        'Sérieux',
      ]);
      expect(corps.single.containsKey('ton_propose'), isFalse);

      s.regarderTon(m.id, 'Naturel');
      s.regarderTon(m.id, 'Sérieux');
      expect(corps, hasLength(1)); // aucun appel pour changer de ton

      await s.envoyer('Pourquoi tu me proposes la deuxième ?');
      expect(corps, hasLength(2));
      expect(corps.last['ton_propose'], 'Sérieux');
      expect(s.messages.last.propositions, isNull);
    });
  });

  group('restauration', () {
    test('chat rouvert : propositions relues avec la réponse', () async {
      final service = _Service()
        ..refs = {
          'r0': ReferencesReponse(
            const [],
            propositions: PropositionsReponse.depuisJson(_propositions),
          ),
        };
      final s = ConversationSession(
        delaiReflexion: Duration.zero,
        piecesJointes: service,
        correspondance: CorrespondanceConversations(),
        depot: _Depot(
          [
            MessageServeur(
              id: 'c1',
              role: 'user',
              contenu: 'Aide-moi à lui répondre',
              date: DateTime(2026, 10, 15, 10),
            ),
            MessageServeur(
              id: 'r0',
              role: 'assistant',
              contenu: 'Voici des idées.',
              date: DateTime(2026, 10, 15, 10, 1),
            ),
          ],
          [
            ContexteServeur(
              id: _ctx,
              consigne: 'c1',
              contact: 'Pepper Potts',
              nombre: 9,
              creeLe: DateTime(2026, 10, 15, 10),
            ),
          ],
        ),
      );
      addTearDown(s.dispose);
      await s.ouvrirServeur(_conv);
      await Future<void>.delayed(Duration.zero);
      final p = s.messages.last.propositions!;
      expect(p.tons.length, 3);
      expect(
        p.tons[1].propositions[2].texte,
        'Tu veux que je ramène quelque chose ?',
      );
      expect(s.messages.first.propositions, isNull);
    });

    test('client : liste des références avec propositions', () async {
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode({
            'items': [
              {
                'message_id': 'r0',
                'references': [],
                'note': null,
                'propositions': _propositions,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final api = ApiJarvis(
        adresse: Uri.parse('http://localhost:8000'),
        jeton: () async => 'jeton',
        client: client,
      );
      final r = await api.referencesConversation(_conv);
      final valeur = (r as SuccesApi<Map<String, ReferencesReponse>>).valeur;
      expect(valeur['r0']!.propositions!.tons.first.nom, 'Taquin');
    });
  });

  group('carte des tons', () {
    for (final largeur in [320.0, 390.0, 1366.0]) {
      testWidgets('tons, trois propositions, changement de ton, aucun '
          'débordement ($largeur px)', (tester) async {
        final tons = <String>[];
        await _carte(
          tester,
          _reponse(PropositionsReponse.depuisJson(_propositions)!),
          largeur: largeur,
          surTon: (ton, _) => tons.add(ton),
        );
        expect(find.text('Idées de réponse'), findsOneWidget);
        for (final nom in ['Taquin', 'Naturel', 'Sérieux']) {
          expect(find.byKey(Key('ton-propose-$nom')), findsOneWidget);
        }
        expect(find.byType(CarteProposition), findsNWidgets(3));
        expect(
          find.text('Ministre, non. Président, à la rigueur 😏'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('ton-propose-Naturel')));
        await tester.pumpAndSettle();
        expect(find.byType(CarteProposition), findsNWidgets(3));
        expect(find.text('Désolé pour le retard, j’arrive !'), findsOneWidget);
        expect(
          find.text('Ministre, non. Président, à la rigueur 😏'),
          findsNothing,
        );
        expect(tons, ['Naturel']);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Copier met la proposition dans le presse-papiers', (
      tester,
    ) async {
      String? copie;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (appel) async {
          if (appel.method == 'Clipboard.setData') {
            copie = (appel.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _carte(
        tester,
        _reponse(PropositionsReponse.depuisJson(_propositions)!),
      );
      await tester.tap(find.byKey(const Key('copier-proposition-2')));
      await tester.pump();
      expect(copie, 'Et toi, depuis quand tu comptes mes minutes ?');
      expect(find.text('Copié'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Copié'), findsNothing);
    });

    testWidgets('propositions et références ensemble', (tester) async {
      final ref = ReferenceWhatsApp.depuisJson({
        'context_id': _ctx,
        'message_order': 8,
        'author': 'Pepper Potts',
        'excerpt': 'mdr',
      })!;
      await _carte(
        tester,
        MessageConversation(
          id: 1,
          auteur: AuteurMessage.jarvis,
          heure: DateTime(2026, 10, 15),
          texte: 'Voici des idées.',
          propositions: PropositionsReponse.depuisJson(_propositions),
          references: [ref],
        ),
      );
      expect(find.byType(PropositionsJarvis), findsOneWidget);
      expect(find.text('« mdr »'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
