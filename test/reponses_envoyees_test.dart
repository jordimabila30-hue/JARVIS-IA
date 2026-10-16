// Phase 4 : réponses déclarées envoyées (appui long), statut confirmé par
// le serveur, annulation, double appui, restauration, actualisation (autre
// appareil), référence explicite des propositions dans le chat. Serveur
// simulé ; conversations fictives.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/piece_jointe_whatsapp.dart';
import 'package:ia_jarvis/models/importation/propositions_reponse.dart';
import 'package:ia_jarvis/models/importation/reference_whatsapp.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_hybride.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_ia.dart';
import 'package:ia_jarvis/services/conversation/reponses_envoyees.dart';
import 'package:ia_jarvis/services/conversations/correspondance_conversations.dart';
import 'package:ia_jarvis/services/conversations/depot_conversations.dart';
import 'package:ia_jarvis/services/importation/pieces_jointes_serveur.dart';
import 'package:ia_jarvis/widgets/conversation/carte_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/propositions_jarvis.dart';

const _conv = '33333333-3333-4333-8333-333333333333';
const _ctx = 'aaaaaaaa-0000-4000-8000-000000000001';

Map<String, Object?> _json({String? envoyeeAmical2}) => {
  'mode': 'reponse',
  'tons': [
    for (final nom in ['Amical', 'Taquin'])
      {
        'nom': nom,
        'propositions': [
          for (var i = 1; i <= 3; i++)
            {
              'id': '$nom-$i',
              'texte': '$nom proposition $i',
              'appuis': [],
              if (nom == 'Amical' && i == 2) 'envoyee': envoyeeAmical2,
            },
        ],
      },
  ],
};

class _Envois implements ServiceReponsesEnvoyees {
  final appels = <(String, String, String, bool)>[];
  bool reussir = true;
  Duration delai = Duration.zero;

  @override
  Future<ResultatApi<DateTime?>> statut({
    required String conversation,
    required String message,
    required String proposition,
    required bool envoyee,
  }) async {
    appels.add((conversation, message, proposition, envoyee));
    await Future<void>.delayed(delai);
    if (!reussir) return const EchecApi(ErreurApi.injoignable);
    return SuccesApi(envoyee ? DateTime(2026, 10, 16, 9, 30) : null);
  }

  // « Reprendre » : ce que le serveur renvoie, et les reprises demandées.
  PropositionsReponse? complete;
  final reprises = <(String, String)>[];

  @override
  Future<ResultatApi<PropositionsReponse?>> completer({
    required String conversation,
    required String message,
  }) async {
    reprises.add((conversation, message));
    await Future<void>.delayed(delai);
    if (!reussir) return const EchecApi(ErreurApi.iaIndisponible);
    return SuccesApi(complete);
  }
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
  @override
  String? get utilisateur => 'compte-1';

  @override
  Future<List<ConversationServeur>> lister({int limite = 100}) async => [];

  @override
  Future<PageMessages> messages(
    String id, {
    DateTime? avant,
    int limite = 50,
  }) async => PageMessages(
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
    contextes: [
      ContexteServeur(
        id: _ctx,
        consigne: 'c1',
        contact: 'Pepper Potts',
        nombre: 9,
        creeLe: DateTime(2026, 10, 15, 10),
      ),
    ],
  );

  @override
  Future<void> supprimer(String id) async {}
}

Future<(ConversationSession, _Service, _Envois)> _session({
  String? envoyee,
}) async {
  final service = _Service()
    ..refs = {
      'r0': ReferencesReponse(
        const [],
        propositions: PropositionsReponse.depuisJson(
          _json(envoyeeAmical2: envoyee),
        ),
      ),
    };
  final envois = _Envois();
  final s = ConversationSession(
    delaiReflexion: Duration.zero,
    piecesJointes: service,
    reponsesEnvoyees: envois,
    correspondance: CorrespondanceConversations(),
    depot: _Depot(),
  );
  await s.ouvrirServeur(_conv);
  await Future<void>.delayed(Duration.zero);
  return (s, service, envois);
}

Future<List<bool?>> _carte(
  WidgetTester tester, {
  Future<bool> Function(PropositionReponse, bool)? statut,
  String? envoyee,
}) async {
  final appels = <bool?>[];
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var p = PropositionsReponse.depuisJson(_json(envoyeeAmical2: envoyee))!;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => PropositionsJarvis(
              propositions: p,
              surStatut: (prop, envoi) async {
                appels.add(envoi);
                final ok =
                    await (statut?.call(prop, envoi) ?? Future.value(true));
                if (ok) {
                  setState(
                    () => p = p.avecEnvoyee(
                      prop.id,
                      envoi ? DateTime(2026, 10, 16) : null,
                    ),
                  );
                }
                return ok;
              },
            ),
          ),
        ),
      ),
    ),
  );
  return appels;
}

void main() {
  group('modèle et client', () {
    test('identifiant et statut « envoyée » lus ; ancien format accepté', () {
      final p = PropositionsReponse.depuisJson(
        _json(envoyeeAmical2: '2026-10-16T07:30:00+00:00'),
      )!;
      expect(p.tons.first.propositions[1].id, 'Amical-2');
      expect(p.tons.first.propositions[1].envoyee, isNotNull);
      expect(p.tons.first.propositions[0].envoyee, isNull);
      final ancienne = PropositionReponse.depuisJson({'texte': 'Salut'})!;
      expect(ancienne.id, isEmpty);
    });

    test('PUT / DELETE vers la bonne route ; date confirmée', () async {
      final requetes = <String>[];
      final api = ApiJarvis(
        adresse: Uri.parse('http://localhost:8000'),
        jeton: () async => 'jeton',
        client: MockClient((r) async {
          requetes.add('${r.method} ${r.url.path}');
          return http.Response(
            jsonEncode(
              r.method == 'PUT'
                  ? {'envoyee': true, 'declared_at': '2026-10-16T07:30:00Z'}
                  : {'envoyee': false, 'declared_at': null},
            ),
            200,
          );
        }),
      );
      final ok = await ReponsesEnvoyeesApi(api).statut(
        conversation: _conv,
        message: 'r0',
        proposition: 'Amical-2',
        envoyee: true,
      );
      expect((ok as SuccesApi<DateTime?>).valeur, isNotNull);
      final annule = await ReponsesEnvoyeesApi(api).statut(
        conversation: _conv,
        message: 'r0',
        proposition: 'Amical-2',
        envoyee: false,
      );
      expect((annule as SuccesApi<DateTime?>).valeur, isNull);
      expect(requetes, [
        'PUT /api/v1/conversations/$_conv/messages/r0/propositions/Amical-2/envoyee',
        'DELETE /api/v1/conversations/$_conv/messages/r0/propositions/Amical-2/envoyee',
      ]);
    });

    test('la question suivante porte la référence explicite des '
        'propositions affichées (réponse + ton)', () async {
      final corps = <Map<String, dynamic>>[];
      final api = ApiJarvis(
        adresse: Uri.parse('http://localhost:8000'),
        jeton: () async => 'jeton',
        client: MockClient((r) async {
          corps.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response.bytes(
            utf8.encode(
              'event: meta\ndata: {"conversation_id": "$_conv", "message_id": "r9"}\n\n'
              'event: delta\ndata: {"text": "Parce que."}\n\n'
              'event: done\ndata: {"message_id": "r9"}\n\n',
            ),
            200,
          );
        }),
      );
      final service = _Service()
        ..refs = {
          'r0': ReferencesReponse(
            const [],
            propositions: PropositionsReponse.depuisJson(_json()),
          ),
        };
      final correspondance = CorrespondanceConversations();
      final s = ConversationSession(
        delaiReflexion: Duration.zero,
        piecesJointes: service,
        correspondance: correspondance,
        depot: _Depot(),
        moteur: MoteurConversationHybride(
          ia: MoteurConversationIA(
            api,
            correspondance: correspondance,
            analyseWhatsApp: () => 'allowed',
          ),
        ),
      );
      addTearDown(s.dispose);
      await s.ouvrirServeur(_conv);
      await Future<void>.delayed(Duration.zero);
      final m = s.messages.last;
      s.regarderTon(m.id, 'Taquin');
      await s.envoyer('Pourquoi la deuxième ?');
      expect(corps.single['propositions_message_id'], 'r0');
      expect(corps.single['ton_propose'], 'Taquin');
    });
  });

  group('session', () {
    test('« Envoyée » seulement après confirmation ; échec : inchangé ; '
        'double appui : un seul appel ; annulation', () async {
      final (s, _, envois) = await _session();
      addTearDown(s.dispose);
      final m = s.messages.last;

      envois.reussir = false;
      expect(await s.declarerEnvoyee(m.id, 'Amical-2'), isFalse);
      expect(
        s.messages.last.propositions!.tons[0].propositions[1].envoyee,
        isNull,
      );

      envois
        ..reussir = true
        ..appels.clear()
        ..delai = const Duration(milliseconds: 20);
      final premier = s.declarerEnvoyee(m.id, 'Amical-2');
      final second = s.declarerEnvoyee(m.id, 'Amical-2'); // double appui
      expect(await second, isFalse);
      expect(await premier, isTrue);
      expect(envois.appels.single, (_conv, 'r0', 'Amical-2', true));
      expect(
        s.messages.last.propositions!.tons[0].propositions[1].envoyee,
        isNotNull,
      );
      expect(
        s.messages.last.propositions!.tons[0].propositions[0].envoyee,
        isNull,
      );

      expect(await s.declarerEnvoyee(m.id, 'Amical-2', envoyee: false), isTrue);
      expect(
        s.messages.last.propositions!.tons[0].propositions[1].envoyee,
        isNull,
      );
    });

    test('restauration et actualisation : le statut d’un autre appareil '
        'est repris', () async {
      final (s, service, _) = await _session(
        envoyee: '2026-10-16T07:30:00+00:00',
      );
      addTearDown(s.dispose);
      expect(
        s.messages.last.propositions!.tons[0].propositions[1].envoyee,
        isNotNull,
      );
      // Annulée ailleurs, puis actualisation.
      service.refs = {
        'r0': ReferencesReponse(
          const [],
          propositions: PropositionsReponse.depuisJson(_json()),
        ),
      };
      await s.rafraichir();
      await Future<void>.delayed(Duration.zero);
      expect(
        s.messages.last.propositions!.tons[0].propositions[1].envoyee,
        isNull,
      );
    });
  });

  testWidgets('carte recréée (défilement) : le ton choisi est gardé', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PropositionsJarvis(
            propositions: PropositionsReponse.depuisJson(_json())!,
            tonInitial: 'Taquin',
          ),
        ),
      ),
    );
    expect(find.text('Taquin proposition 2'), findsOneWidget);
    expect(find.text('Amical proposition 2'), findsNothing);
  });

  test('la session donne le ton regardé des dernières propositions', () async {
    final (s, _, _) = await _session();
    addTearDown(s.dispose);
    final m = s.messages.last;
    expect(s.tonRegarde(m.id), isNull);
    s.regarderTon(m.id, 'Taquin');
    expect(s.tonRegarde(m.id), 'Taquin');
    expect(s.tonRegarde(s.messages.first.id), isNull);
  });

  group('appui long sur la carte', () {
    testWidgets(
      '800 ms sur la DEUXIÈME réponse : la carte devient la bulle du choix',
      (tester) async {
        final appels = await _carte(tester);
        final carte = find.byKey(const Key('proposition-Amical-1'));
        final geste = await tester.startGesture(tester.getCenter(carte));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const Key('progression-appui')), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 450));
        await geste.up();
        await tester.pumpAndSettle();
        expect(appels, [true]);
        // Phase 5.1 : plus de tons, plus d'autres propositions, une bulle.
        expect(find.byKey(const Key('reponse-choisie')), findsOneWidget);
        expect(find.text('Amical proposition 2'), findsOneWidget);
        expect(find.byType(CarteProposition), findsNothing);
        expect(find.byKey(const Key('ton-propose-Taquin')), findsNothing);
        // Menu ··· : Copier, Annuler le choix.
        await tester.tap(find.byKey(const Key('menu-reponse-choisie')));
        await tester.pumpAndSettle();
        expect(find.text('Copier'), findsOneWidget);
        await tester.tap(find.text('Annuler le choix'));
        await tester.pumpAndSettle();
        expect(appels, [true, false]);
        // Retour aux propositions, même ton.
        expect(find.byKey(const Key('reponse-choisie')), findsNothing);
        expect(find.byType(CarteProposition), findsNWidgets(3));
        expect(find.text('Amical proposition 2'), findsOneWidget);
      },
    );

    testWidgets('dans un fil sélectionnable : aucune sélection de texte', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final appels = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: SingleChildScrollView(
                child: PropositionsJarvis(
                  propositions: PropositionsReponse.depuisJson(_json())!,
                  surStatut: (_, e) async {
                    appels.add(e);
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final g = await tester.startGesture(
        tester.getCenter(find.text('Amical proposition 2')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await g.up();
      await tester.pumpAndSettle();
      expect(appels, [true]);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Select all'), findsNothing);
    });

    testWidgets('relâché trop tôt ou défilement : rien', (tester) async {
      final appels = await _carte(tester);
      final carte = find.byKey(const Key('proposition-Amical-0'));
      final g = await tester.startGesture(tester.getCenter(carte));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await g.up();
      await tester.pump(const Duration(seconds: 1));
      final g2 = await tester.startGesture(tester.getCenter(carte));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await g2.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(seconds: 1));
      await g2.up();
      await tester.pumpAndSettle();
      expect(appels, isEmpty);
      expect(find.text('Envoyée'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('échec du serveur : pas de « Envoyée », message discret', (
      tester,
    ) async {
      await _carte(tester, statut: (_, _) async => false);
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('proposition-Amical-2'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('Envoyée'), findsNothing);
      expect(find.text('Non enregistrée, réessayez'), findsOneWidget);
    });

    testWidgets(
      'Windows / Web : bouton « Marquer envoyée » (souris, clavier)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final appels = await _carte(tester);
        expect(find.byKey(const Key('marquer-envoyee-1')), findsNWidgets(1));
        await tester.tap(find.byKey(const Key('marquer-envoyee-3')));
        await tester.pumpAndSettle();
        expect(appels, [true]);
        expect(find.byKey(const Key('reponse-choisie')), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('clavier : focus sur « Marquer envoyée » puis Entrée', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final appels = await _carte(tester);
      final libelle = find.descendant(
        of: find.byKey(const Key('marquer-envoyee-2')),
        matching: find.text('Marquer envoyée'),
      );
      Focus.of(tester.element(libelle)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(appels, [true]);
      expect(find.byKey(const Key('reponse-choisie')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('vibration légère à la validation', (tester) async {
      final vibrations = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (appel) async {
          if (appel.method == 'HapticFeedback.vibrate') {
            vibrations.add('${appel.arguments}');
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
      await _carte(tester);
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('proposition-Amical-0'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 850));
      await g.up();
      await tester.pumpAndSettle();
      expect(vibrations, isNotEmpty);
    });
  });

  group('génération incomplète (lots)', () {
    Map<String, Object?> complet() => {
      'mode': 'reponse',
      'longueurs': ['court', 'moyen', 'long'],
      'ensemble': 'r0',
      'tons': [
        for (final nom in ['Amical', 'Professionnel'])
          {
            'nom': nom,
            'propositions': [
              for (final l in ['court', 'moyen', 'long'])
                for (var i = 1; i <= 3; i++)
                  {'id': '$nom-$l-$i', 'texte': '$nom $l $i', 'longueur': l},
            ],
          },
      ],
    };

    Future<(ConversationSession, _Envois)> incomplete() async {
      final service = _Service()
        ..refs = {
          'r0': ReferencesReponse(
            const [],
            propositions: PropositionsReponse.depuisJson({
              'statut': 'incomplet',
              'mode': 'reponse',
              'raison': 'quota',
              'ensemble': 'r0',
              'tons': [],
            }),
          ),
        };
      final envois = _Envois();
      final s = ConversationSession(
        delaiReflexion: Duration.zero,
        piecesJointes: service,
        reponsesEnvoyees: envois,
        correspondance: CorrespondanceConversations(),
        depot: _Depot(),
      );
      await s.ouvrirServeur(_conv);
      await Future<void>.delayed(Duration.zero);
      return (s, envois);
    }

    test('restaurée incomplète ; « Reprendre » complète le même message, '
        'une seule reprise à la fois', () async {
      final (s, envois) = await incomplete();
      final m = s.messages.firstWhere((m) => m.propositions != null);
      expect(m.propositions!.incomplet, isTrue);
      final nombre = s.messages.length;
      envois
        ..complete = PropositionsReponse.depuisJson(complet())
        ..delai = const Duration(milliseconds: 20);
      final premiere = s.reprendrePropositions(m.id);
      expect(s.repriseEnCours(m.id), isTrue);
      expect(await s.reprendrePropositions(m.id), isFalse); // double appui
      expect(await premiere, isTrue);
      expect(envois.reprises, [(_conv, 'r0')]);
      final apres = s.messages.firstWhere((x) => x.id == m.id);
      expect(apres.propositions!.incomplet, isFalse);
      expect(apres.propositions!.tons.length, 2);
      // Aucun message ajouté (ni réponse, ni consigne en double).
      expect(s.messages.length, nombre);
      // Changer de ton et de longueur ensuite : aucun appel réseau.
      s.regarderTon(m.id, 'Professionnel', longueur: LongueurProposition.long);
      expect(envois.reprises.length, 1);
      expect(envois.appels, isEmpty);
    });

    test('échec de la reprise : toujours incomplète, rien inventé', () async {
      final (s, envois) = await incomplete();
      final m = s.messages.firstWhere((m) => m.propositions != null);
      envois.reussir = false;
      expect(await s.reprendrePropositions(m.id), isFalse);
      expect(
        s.messages.firstWhere((x) => x.id == m.id).propositions!.incomplet,
        isTrue,
      );
      expect(s.repriseEnCours(m.id), isFalse);
    });

    testWidgets('état discret « Génération incomplète » + « Reprendre »', (
      tester,
    ) async {
      var reprises = 0;
      var p = PropositionsReponse.depuisJson({
        'statut': 'incomplet',
        'raison': 'quota',
        'tons': [],
      })!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PropositionsJarvis(
                propositions: p,
                surReprendre: () async {
                  reprises++;
                  setState(() => p = PropositionsReponse.depuisJson(complet())!);
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Génération incomplète'), findsOneWidget);
      expect(find.textContaining('Limite du service IA'), findsOneWidget);
      expect(find.byType(CarteProposition), findsNothing);
      await tester.tap(find.byKey(const Key('reprendre-propositions')));
      await tester.pumpAndSettle();
      expect(reprises, 1);
      expect(find.textContaining('Génération incomplète'), findsNothing);
      expect(find.byType(CarteProposition), findsNWidgets(3));
      // Longueur et ton : instantané, au même endroit.
      await tester.tap(find.byKey(const Key('longueur-long')));
      await tester.pump();
      expect(find.text('Amical long 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ton-propose-Professionnel')));
      await tester.pump();
      expect(find.text('Professionnel long 1'), findsOneWidget);
      expect(reprises, 1);
    });

    testWidgets('reprise en cours : indicateur, pas de second bouton', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PropositionsJarvis(
              propositions: PropositionsReponse.depuisJson({
                'statut': 'incomplet',
                'tons': [],
              })!,
              repriseEnCours: true,
              surReprendre: () async => true,
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('reprendre-propositions')), findsNothing);
    });
  });

  testWidgets('propositions en préparation : trois points toujours animés', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PreparationPropositions())),
    );
    expect(find.text('Je prépare les propositions'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.hasScheduledFrame, isTrue); // jamais figé
    }
  });

  testWidgets('fil inversé : Court → Long ne déplace pas les capsules '
      '(défaut vu sur le S10+)', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String texte(String l, int i) => l == 'long'
        ? List.filled(40, 'mot$i').join(' ')
        : 'Texte $l $i';
    final p = PropositionsReponse.depuisJson({
      'longueurs': ['court', 'moyen', 'long'],
      'tons': [
        for (final nom in ['Amical', 'Professionnel'])
          {
            'nom': nom,
            'propositions': [
              for (final l in ['court', 'moyen', 'long'])
                for (var i = 1; i <= 3; i++)
                  {'id': '$nom-$l-$i', 'texte': texte(l, i), 'longueur': l},
            ],
          },
      ],
    })!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            reverse: true, // comme le fil de conversation
            padding: const EdgeInsets.only(bottom: 60), // margeBas du fil
            children: [
              PropositionsJarvis(propositions: p),
              for (var i = 0; i < 12; i++)
                SizedBox(height: 120, child: Text('Message $i')),
            ],
          ),
        ),
      ),
    );
    final capsule = find.byKey(const Key('longueur-long'));
    final avant = tester.getTopLeft(capsule).dy;
    await tester.tap(capsule);
    await tester.pumpAndSettle();
    expect(find.textContaining('mot1 mot1'), findsOneWidget);
    expect(tester.getTopLeft(capsule).dy, moreOrLessEquals(avant, epsilon: 1));
    // Et retour à Court : toujours sous le doigt.
    await tester.tap(find.byKey(const Key('longueur-court')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('longueur-court'))).dy,
      moreOrLessEquals(tester.getTopLeft(capsule).dy, epsilon: 1),
    );
    expect(tester.getTopLeft(capsule).dy, moreOrLessEquals(avant, epsilon: 1));
    // Long puis choix : la bulle compacte n'est jamais cachée en bas.
    await tester.tap(capsule);
    await tester.pumpAndSettle();
    final choisie = p.affichees(p.tons.first, LongueurProposition.long)[1];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            reverse: true,
            padding: const EdgeInsets.only(bottom: 60),
            children: [
              PropositionsJarvis(
                propositions: p.avecEnvoyee(choisie.id, DateTime(2026, 10, 16)),
              ),
              for (var i = 0; i < 12; i++)
                SizedBox(height: 120, child: Text('Message $i')),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final bulle = find.byKey(const Key('reponse-choisie'));
    expect(bulle, findsOneWidget);
    expect(tester.getBottomLeft(bulle).dy, lessThanOrEqualTo(800 - 48 + 1));
  });
}
