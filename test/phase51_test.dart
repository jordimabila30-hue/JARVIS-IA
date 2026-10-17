// Phase 5.1 : tons × longueurs (dont Professionnel), changement instantané,
// réglages gardés, bulle du choix et annulation, grand glissement, bulles
// des messages WhatsApp collés. Serveur simulé ; données fictives.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/piece_jointe_whatsapp.dart';
import 'package:ia_jarvis/models/importation/propositions_reponse.dart';
import 'package:ia_jarvis/models/importation/reference_whatsapp.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversations/correspondance_conversations.dart';
import 'package:ia_jarvis/services/conversations/depot_conversations.dart';
import 'package:ia_jarvis/services/importation/actualisation_whatsapp.dart';
import 'package:ia_jarvis/services/importation/pieces_jointes_serveur.dart';
import 'package:ia_jarvis/widgets/conversation/bulle_ajout_whatsapp.dart';
import 'package:ia_jarvis/widgets/conversation/propositions_jarvis.dart';
import 'package:ia_jarvis/widgets/feuille_ajout.dart';

const _conv = '33333333-3333-4333-8333-333333333333';
const _ctx = 'aaaaaaaa-0000-4000-8000-000000000001';

Map<String, Object?> _json({String? choisie}) => {
  'mode': 'reponse',
  'longueurs': ['court', 'moyen', 'long'],
  'ensemble': 'r0',
  'tons': [
    for (final ton in ['Naturel', 'Amical', 'Professionnel'])
      {
        'nom': ton,
        'propositions': [
          for (final lo in ['court', 'moyen', 'long'])
            for (var i = 1; i <= 3; i++)
              {
                'id': '$ton-$lo-$i',
                'texte': '$ton $lo $i',
                'longueur': lo,
                'rang': i,
                'appuis': [],
                if (choisie == '$ton-$lo-$i') 'envoyee': '2026-10-16T08:00:00Z',
              },
        ],
      },
  ],
};

Future<void> _pompe(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: w)),
    ),
  );
}

class _Actu implements ServiceActualisationWhatsApp {
  List<MessageAjoute> serveur = [];
  final modifies = <String>[];
  final supprimes = <String>[];

  @override
  Future<ResultatApi<List<MessageAjoute>>> ajoutes(String contexte) async =>
      SuccesApi(serveur);
  @override
  Future<ResultatAjout> ajouter(
    String contexte,
    List<EntreeActualisation> entrees, {
    bool confirmer = false,
  }) async => const AjoutReussi([]);
  @override
  Future<ResultatApi<List<ContexteServeur>>> contextes() async =>
      const SuccesApi([]);
  @override
  Future<ResultatApi<void>> modifier(
    String contexte,
    String message, {
    String? texte,
    String? auteur,
  }) async {
    modifies.add('$message:$texte');
    return const SuccesApi(null);
  }

  @override
  Future<ResultatApi<void>> supprimer(String contexte, String message) async {
    supprimes.add(message);
    return const SuccesApi(null);
  }
}

class _Service implements ServicePiecesJointes {
  @override
  Future<ResultatApi<Map<String, ReferencesReponse>>> references(
    String conversation,
  ) async => SuccesApi({
    'r0': ReferencesReponse(
      const [],
      propositions: PropositionsReponse.depuisJson(_json()),
    ),
  });
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
      MessageServeur(
        id: 'c2',
        role: 'user',
        contenu: 'Tu penses quoi de sa réponse ?',
        date: DateTime(2026, 10, 15, 12),
      ),
    ],
    contextes: [
      ContexteServeur(
        id: _ctx,
        consigne: 'c1',
        contact: 'Lina Moreau',
        nombre: 96,
        creeLe: DateTime(2026, 10, 15, 10),
        participants: const ['Lina Moreau', 'Alex Martin'],
        moi: 'Alex Martin',
      ),
    ],
  );
  @override
  Future<void> supprimer(String id) async {}
}

void main() {
  group('tons et longueurs', () {
    test('modèle : 3 longueurs × 3 par ton, Moyen par défaut', () {
      final p = PropositionsReponse.depuisJson(_json())!;
      expect(p.longueurs, LongueurProposition.values);
      expect(p.longueurParDefaut, LongueurProposition.moyen);
      final pro = p.tons.last;
      expect(pro.nom, 'Professionnel');
      expect(p.affichees(pro, LongueurProposition.long).map((x) => x.texte), [
        'Professionnel long 1',
        'Professionnel long 2',
        'Professionnel long 3',
      ]);
    });

    testWidgets('Professionnel et longueurs visibles ; changement instantané ; '
        'réglages remontés', (tester) async {
      final reglages = <(String, LongueurProposition?)>[];
      await _pompe(
        tester,
        PropositionsJarvis(
          propositions: PropositionsReponse.depuisJson(_json())!,
          surTon: (t, l) => reglages.add((t, l)),
        ),
      );
      expect(
        find.byKey(const Key('ton-propose-Professionnel')),
        findsOneWidget,
      );
      for (final l in ['court', 'moyen', 'long']) {
        expect(find.byKey(Key('longueur-$l')), findsOneWidget);
      }
      expect(find.text('Naturel moyen 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ton-propose-Professionnel')));
      await tester.pump(); // aucun chargement : une seule image
      expect(find.text('Professionnel moyen 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('longueur-long')));
      await tester.pump();
      expect(find.text('Professionnel long 1'), findsOneWidget);
      expect(find.text('Professionnel moyen 1'), findsNothing);
      expect(reglages.last, ('Professionnel', LongueurProposition.long));
      expect(tester.takeException(), isNull);
    });

    testWidgets('carte recréée : ton et longueur gardés', (tester) async {
      await _pompe(
        tester,
        PropositionsJarvis(
          propositions: PropositionsReponse.depuisJson(_json())!,
          tonInitial: 'Amical',
          longueurInitiale: LongueurProposition.court,
        ),
      );
      expect(find.text('Amical court 3'), findsOneWidget);
    });

    testWidgets('choix : bulle seule ; annulation : retour au ton et à la '
        'longueur de la réponse choisie', (tester) async {
      var p = PropositionsReponse.depuisJson(_json())!;
      late StateSetter maj;
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                maj = setState;
                return PropositionsJarvis(
                  propositions: p,
                  contact: 'Lina Moreau',
                  surStatut: (prop, envoyee) async {
                    setState(
                      () => p = p.avecEnvoyee(
                        prop.id,
                        envoyee ? DateTime(2026, 10, 16) : null,
                      ),
                    );
                    return true;
                  },
                );
              },
            ),
          ),
        ),
      );
      // Choix fait ailleurs (Professionnel / Long / 2), relu du serveur.
      maj(
        () => p = PropositionsReponse.depuisJson(
          _json(choisie: 'Professionnel-long-2'),
        )!,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reponse-choisie')), findsOneWidget);
      expect(find.text('Professionnel long 2'), findsOneWidget);
      expect(find.text('Vous → Lina Moreau'), findsOneWidget);
      expect(find.byKey(const Key('ton-propose-Naturel')), findsNothing);
      expect(find.byType(CarteProposition), findsNothing);
      await tester.tap(find.byKey(const Key('menu-reponse-choisie')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Déclarée envoyée le'), findsOneWidget);
      await tester.tap(find.text('Annuler le choix'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reponse-choisie')), findsNothing);
      expect(find.text('Professionnel long 2'), findsOneWidget);
      expect(find.byType(CarteProposition), findsNWidgets(3));
    });

    testWidgets('Copier depuis le menu de la bulle', (tester) async {
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
      await _pompe(
        tester,
        PropositionsJarvis(
          propositions: PropositionsReponse.depuisJson(
            _json(choisie: 'Amical-moyen-1'),
          )!,
        ),
      );
      await tester.tap(find.byKey(const Key('menu-reponse-choisie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copier'));
      await tester.pumpAndSettle();
      expect(copie, 'Amical moyen 1');
    });
  });

  group('grand glissement', () {
    Future<List<ChoixAjout?>> feuille(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final choix = <ChoixAjout?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () async => choix.add(
                  await afficherFeuilleAjout(c, actualisation: true),
                ),
                child: const Text('plus'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('plus'));
      await tester.pumpAndSettle();
      return choix;
    }

    testWidgets('au-delà du seuil puis relâcher : volet ouvert directement', (
      tester,
    ) async {
      final choix = await feuille(tester);
      await tester.drag(
        find.byKey(const Key('ligne-importer')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      expect(choix, [ChoixAjout.ajouterMessageWhatsApp]);
    });

    testWidgets('petit glissement : action seulement révélée', (tester) async {
      final choix = await feuille(tester);
      await tester.drag(
        find.byKey(const Key('ligne-importer')),
        const Offset(-140, 0),
      );
      await tester.pumpAndSettle();
      expect(choix, isEmpty);
      expect(
        find.byKey(const Key('action-glissee-ajouter-message')),
        findsOneWidget,
      );
    });
  });

  group('bulles des messages collés', () {
    Future<(ConversationSession, _Actu)> session() async {
      final actu = _Actu()
        ..serveur = [
          MessageAjoute(
            id: 'a1',
            ordre: 96,
            sens: SensMessage.recu,
            auteur: 'Lina Moreau',
            texte: 'Ah bon ? Et tu comptais me le dire quand ?',
            ajouteLe: DateTime(2026, 10, 15, 11),
          ),
        ];
      final s = ConversationSession(
        delaiReflexion: Duration.zero,
        piecesJointes: _Service(),
        actualisation: actu,
        correspondance: CorrespondanceConversations(),
        depot: _Depot(),
      );
      await s.ouvrirServeur(_conv);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      return (s, actu);
    }

    test('restaurées à leur place (moment de l’ajout), sans doublon', () async {
      final (s, _) = await session();
      addTearDown(s.dispose);
      final ids = s.messages.map((m) => m.idServeur).toList();
      expect(ids, ['c1', 'r0', 'ajout:a1', 'c2']);
      final b = s.messages[2].ajoutWhatsApp!;
      expect((b.contact, b.message.auteur), ('Lina Moreau', 'Lina Moreau'));
      expect(s.messages[2].texte, isEmpty); // rien pour les détecteurs ni l'IA
      await s.rafraichir();
      await Future<void>.delayed(Duration.zero);
      expect(s.messages.where((m) => m.idServeur == 'ajout:a1').length, 1);
    });

    test('nouveaux ajouts affichés dans le fil ; autre chat : rien', () async {
      final (s, _) = await session();
      addTearDown(s.dispose);
      final lina = s.contextesCourants.single;
      s.afficherAjouts(lina, const [
        MessageAjoute(
          id: 'a2',
          ordre: 97,
          sens: SensMessage.envoye,
          auteur: 'Alex Martin',
          texte: 'Finalement, je suis disponible samedi.',
        ),
      ]);
      expect(s.messages.last.ajoutWhatsApp!.message.sens, SensMessage.envoye);
      final n = s.messages.length;
      s.afficherAjouts(
        ContexteServeur(
          id: 'autre',
          consigne: null,
          contact: 'Samuel Petit',
          nombre: 1,
          creeLe: DateTime(2026),
        ),
        const [
          MessageAjoute(
            id: 'x',
            ordre: 1,
            sens: SensMessage.recu,
            auteur: 'Samuel Petit',
            texte: 'Yo',
          ),
        ],
      );
      expect(s.messages.length, n);
    });

    test('corriger et supprimer depuis la bulle', () async {
      final (s, actu) = await session();
      addTearDown(s.dispose);
      final id = s.messages.firstWhere((m) => m.ajoutWhatsApp != null).id;
      expect(await s.corrigerAjout(id, 'Ah bon ?'), isTrue);
      expect(actu.modifies.single, 'a1:Ah bon ?');
      expect(
        s.messages.firstWhere((m) => m.id == id).ajoutWhatsApp!.message.texte,
        'Ah bon ?',
      );
      expect(await s.supprimerAjout(id), isTrue);
      expect(actu.supprimes.single, 'a1');
      expect(s.messages.any((m) => m.ajoutWhatsApp != null), isFalse);
    });

    testWidgets('bulle reçue / envoyée et menu ···', (tester) async {
      var supprime = false;
      await _pompe(
        tester,
        Column(
          children: [
            BulleAjoutWhatsApp(
              ajout: const AjoutDansLeFil(
                contexte: _ctx,
                contact: 'Lina Moreau',
                message: MessageAjoute(
                  id: 'a1',
                  ordre: 96,
                  sens: SensMessage.recu,
                  auteur: 'Lina Moreau',
                  texte: 'Ah bon ? Et tu comptais me le dire quand ?',
                ),
              ),
              surCorriger: (_) async => true,
              surSupprimer: () async => supprime = true,
            ),
            const BulleAjoutWhatsApp(
              ajout: AjoutDansLeFil(
                contexte: _ctx,
                contact: 'Lina Moreau',
                message: MessageAjoute(
                  id: 'a2',
                  ordre: 97,
                  sens: SensMessage.envoye,
                  auteur: 'Alex Martin',
                  texte: 'Finalement, je suis disponible samedi.',
                ),
              ),
            ),
          ],
        ),
      );
      expect(find.text('Lina Moreau'), findsOneWidget);
      expect(find.text('Vous → Lina Moreau'), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-ajout-a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('valider-supprimer-ajout')));
      await tester.pumpAndSettle();
      expect(supprime, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
