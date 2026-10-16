// Phase 2 : références vérifiées sous les réponses de JARVIS, ouverture
// du vrai message dans « Voir les messages », restauration. Serveur et
// pièces jointes simulés ; conversations fictives.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/piece_jointe_whatsapp.dart';
import 'package:ia_jarvis/models/importation/reference_whatsapp.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/pages/conversation_page.dart';
import 'package:ia_jarvis/pages/resume_whatsapp_page.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_hybride.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_ia.dart';
import 'package:ia_jarvis/services/conversations/correspondance_conversations.dart';
import 'package:ia_jarvis/services/conversations/depot_conversations.dart';
import 'package:ia_jarvis/services/importation/pieces_jointes_serveur.dart';
import 'package:ia_jarvis/theme/gabarit_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/carte_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/references_jarvis.dart';
import 'package:ia_jarvis/widgets/importation/apercu_discussion.dart';

import 'outils/ecriture.dart';

const _conv = '33333333-3333-4333-8333-333333333333';
const _ctx = 'aaaaaaaa-0000-4000-8000-000000000001';

Map<String, Object?> _ref(
  int ordre,
  String auteur,
  String texte, {
  int rang = 0,
  bool moi = false,
}) => {
  'rang': rang,
  'position': 10,
  'context_id': _ctx,
  'context_message_id': 'm$ordre',
  'message_order': ordre,
  'author': auteur,
  'is_me': moi,
  'excerpt': texte,
  'kind': 'text',
  'sent_at': '2026-10-12T18:42:00',
  'sent_at_raw': '12/10/2026 18:42',
  'date_label': '12/10/2026 18:42',
  'dates_uncertain': false,
  'contact_name': 'Pepper Potts',
  'current_user_name': 'Tony Stark',
};

String _evenement(String type, Object donnees) =>
    'event: $type\ndata: ${jsonEncode(donnees)}\n\n';

http.Response _sse(String corps) => http.Response.bytes(
  utf8.encode(corps),
  200,
  headers: {'content-type': 'text/event-stream; charset=utf-8'},
);

/// Pièce jointe de [n] messages, servie par pages comme le backend.
class _Service implements ServicePiecesJointes {
  /// Messages de la pièce jointe.
  static const n = 5000;
  final appels = <(int, int)>[];
  Map<String, ReferencesReponse> refs = {};
  final demandesReferences = <String>[];

  MessageWhatsApp _message(int i) => MessageWhatsApp(
    ordre: i,
    auteur: i.isEven ? 'Pepper Potts' : 'Tony Stark',
    date: DateTime(2026, 1, 1).add(Duration(hours: i)),
    dateBrute: '',
    texte: i == 2500 ? 'mdr, le ministre' : 'message $i',
    type: TypeMessageWhatsApp.texte,
  );

  @override
  Future<ResultatApi<PageWhatsApp>> page(
    String id, {
    required int apres,
    required int limite,
  }) async {
    appels.add((apres, limite));
    final debut = apres + 1;
    final fin = (debut + limite).clamp(0, n);
    return SuccesApi(
      PageWhatsApp(
        premier: debut,
        messages: [for (var i = debut; i < fin; i++) _message(i)],
        suite: fin < n,
      ),
    );
  }

  @override
  Future<ResultatApi<Map<String, ReferencesReponse>>> references(
    String conversation,
  ) async {
    demandesReferences.add(conversation);
    return SuccesApi(refs);
  }

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

ReferenceWhatsApp _r(int ordre, String auteur, String texte, {int rang = 0}) =>
    ReferenceWhatsApp.depuisJson(_ref(ordre, auteur, texte, rang: rang))!;

MessageConversation _reponse(List<ReferenceWhatsApp> refs, {String? note}) =>
    MessageConversation(
      id: 1,
      auteur: AuteurMessage.jarvis,
      heure: DateTime(2026, 10, 15, 10),
      texte: 'C’est Pepper qui a écrit « mdr ».',
      references: refs,
      noteReferences: note,
    );

Future<void> _carte(
  WidgetTester tester,
  MessageConversation m, {
  double largeur = 390,
  ValueChanged<ReferenceWhatsApp>? surReference,
}) async {
  tester.view.physicalSize = Size(largeur, 900);
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
            surReference: surReference,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('client et modèle', () {
    test('événement SSE « references » : références vérifiées reçues, '
        'texte sans repère', () async {
      final client = MockClient(
        (r) async => _sse(
          _evenement('meta', {'conversation_id': _conv, 'message_id': 'r1'}) +
              _evenement('delta', {
                'text': 'C’est Pepper qui a écrit « mdr ».',
              }) +
              _evenement('references', {
                'message_id': 'r1',
                'references': [_ref(2, 'Pepper Potts', 'mdr')],
                'note': null,
              }) +
              _evenement('done', {'message_id': 'r1'}),
        ),
      );
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
      await s.envoyer('Qui a écrit mdr ?');
      final m = s.messages.last;
      expect(m.texte, 'C’est Pepper qui a écrit « mdr ».');
      expect(m.texte.contains('['), isFalse);
      final [ref] = m.references;
      expect((ref.auteur, ref.extrait, ref.ordre), ('Pepper Potts', 'mdr', 2));
      expect(ref.contexte, _ctx);
      expect(ref.dateAffichee, '12 octobre 2026 · 18:42');
    });

    test('référence incomplète refusée ; date incertaine laissée brute', () {
      expect(ReferenceWhatsApp.depuisJson({'author': 'Pepper'}), isNull);
      final r = ReferenceWhatsApp.depuisJson({
        ..._ref(1, 'Pepper Potts', 'mdr'),
        'dates_uncertain': true,
        'sent_at_raw': '05/06/26 18:42',
      })!;
      expect(r.dateAffichee, '05/06/26 18:42');
    });
  });

  group('restauration', () {
    test('chat WhatsApp rouvert : références relues sur le serveur et '
        'rattachées à leur réponse', () async {
      final service = _Service()
        ..refs = {
          'r0': ReferencesReponse([_r(2, 'Pepper Potts', 'mdr')]),
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
              contenu: 'Qui a écrit mdr ?',
              date: DateTime(2026, 10, 15, 10),
            ),
            MessageServeur(
              id: 'r0',
              role: 'assistant',
              contenu: 'C’est Pepper.',
              date: DateTime(2026, 10, 15, 10, 1),
            ),
          ],
          [
            ContexteServeur(
              id: _ctx,
              consigne: 'c1',
              contact: 'Pepper Potts',
              nombre: 5000,
              creeLe: DateTime(2026, 10, 15, 10),
            ),
          ],
        ),
      );
      addTearDown(s.dispose);
      await s.ouvrirServeur(_conv);
      await Future<void>.delayed(Duration.zero);
      expect(service.demandesReferences, [_conv]);
      final r = s.messages.last.references.single;
      expect((r.auteur, r.extrait), ('Pepper Potts', 'mdr'));
      expect(s.messages.first.references, isEmpty);
    });

    test('chat JARVIS ordinaire : aucune demande de références', () async {
      final service = _Service();
      final s = ConversationSession(
        delaiReflexion: Duration.zero,
        piecesJointes: service,
        depot: _Depot([
          MessageServeur(
            id: 'r0',
            role: 'assistant',
            contenu: 'Lima.',
            date: DateTime(2026, 10, 15),
          ),
        ], const []),
      );
      addTearDown(s.dispose);
      await s.ouvrirServeur(_conv);
      await Future<void>.delayed(Duration.zero);
      expect(service.demandesReferences, isEmpty);
    });
  });

  group('cartes sous la réponse', () {
    for (final largeur in [320.0, 390.0, 1366.0]) {
      testWidgets('auteur, date, extrait ; appui ; aucun débordement '
          '($largeur px)', (tester) async {
        final touches = <ReferenceWhatsApp>[];
        await _carte(
          tester,
          _reponse([
            _r(2, 'Pepper Potts', 'mdr'),
            _r(3, 'Tony Stark', 'Arrête de te moquer ! ' * 8, rang: 1),
          ]),
          largeur: largeur,
          surReference: touches.add,
        );
        expect(find.text(ReferencesJarvis.titre), findsOneWidget);
        expect(find.textContaining('Pepper Potts'), findsOneWidget);
        expect(
          find.textContaining('12 octobre 2026 · 18:42'),
          findsNWidgets(2),
        );
        expect(find.text('« mdr »'), findsOneWidget);
        await tester.tap(find.text('« mdr »'));
        expect(touches.single.ordre, 2);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('trois d’emblée, puis « Voir les autres » ; avertissement', (
      tester,
    ) async {
      await _carte(
        tester,
        _reponse(
          [
            for (var i = 0; i < 5; i++)
              _r(i, 'Pepper Potts', 'message $i', rang: i),
          ],
          note:
              'Attention : une phrase attribue un message à la mauvaise personne.',
        ),
        surReference: (_) {},
      );
      expect(find.byType(CarteReference), findsNWidgets(3));
      expect(find.textContaining('mauvaise personne'), findsOneWidget);
      await tester.tap(find.text('Voir les 2 autres'));
      await tester.pump();
      expect(find.byType(CarteReference), findsNWidgets(5));
    });

    testWidgets('aucun repère technique visible', (tester) async {
      await _carte(tester, _reponse([_r(2, 'Pepper Potts', 'mdr')]));
      final textes = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join(' ');
      expect(RegExp(r'\[\[|\bA\d+\b|message 2\b').hasMatch(textes), isFalse);
    });
  });

  group('« Voir les messages » ouvert sur le message', () {
    Future<_Service> ouvrir(WidgetTester tester, {int cible = 2500}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _Service();
      await tester.pumpWidget(
        MaterialApp(
          home: ResumeWhatsAppPage.surMessage(
            conversation: const ConversationWhatsApp(
              titre: 'Pepper Potts',
              messages: [],
              participants: [
                ParticipantWhatsApp(nom: 'Pepper Potts', messages: 0),
                ParticipantWhatsApp(nom: 'Tony Stark', messages: 0),
              ],
              ordreDate: OrdreDate.jourMoisAnnee,
              dateIncertaine: false,
              lignesNonRattachees: [],
              nombreLignesNonRattachees: 0,
              nomFichier: '',
            ),
            chargeur: (apres, limite) =>
                service.page(_ctx, apres: apres, limite: limite),
            cible: cible,
            moi: 'Tony Stark',
            nombre: 5000,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return service;
    }

    testWidgets('message au milieu de 5 000 : une seule page lue, message '
        'visible et éclairé, puis l’éclairage s’efface', (tester) async {
      final service = await ouvrir(tester);
      expect(service.appels, [(2459, 120)]);
      final cible = find.textContaining('mdr, le ministre', findRichText: true);
      expect(cible, findsOneWidget);
      final y = tester.getRect(cible).center.dy;
      expect(y, inInclusiveRange(100, 844 - 100));
      final eclairage = find.ancestor(
        of: cible,
        matching: find.byType(AnimatedContainer),
      );
      BoxDecoration deco() =>
          tester.widget<AnimatedContainer>(eclairage.first).decoration!
              as BoxDecoration;
      expect(deco().color!.a, greaterThan(0.3));
      // Contexte : le message précédent et le suivant sont là.
      expect(
        find.textContaining('message 2499', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('message 2501', findRichText: true),
        findsOneWidget,
      );
      await tester.pump(ResumeWhatsAppPage.dureeSurbrillance);
      await tester.pump(const Duration(seconds: 1));
      expect(deco().color!.a, 0);
      expect(find.textContaining(RegExp(r'5\s000 messages')), findsOneWidget);
    });

    testWidgets('en remontant, les messages précédents se chargent sans '
        'déplacer le message visé', (tester) async {
      final service = await ouvrir(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
      await tester.pump();
      await tester.pump();
      expect(service.appels.length, greaterThan(1));
      final (apres, limite) = service.appels[1];
      expect(apres + limite + 1, 2460); // contigu à la première page
      expect(find.byType(BulleApercu), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('premier message de la pièce jointe', (tester) async {
      final service = await ouvrir(tester, cible: 0);
      expect(service.appels.first.$1, -1);
      expect(
        find.textContaining('message 0', findRichText: true),
        findsOneWidget,
      );
    });
  });

  testWidgets('depuis le chat : la carte ouvre le vrai message, le retour '
      'ramène au même chat', (tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _Service();
    final client = MockClient(
      (r) async => _sse(
        _evenement('meta', {'conversation_id': _conv, 'message_id': 'r1'}) +
            _evenement('delta', {'text': 'C’est Pepper.'}) +
            _evenement('references', {
              'message_id': 'r1',
              'references': [_ref(2500, 'Pepper Potts', 'mdr, le ministre')],
            }) +
            _evenement('done', {'message_id': 'r1'}),
      ),
    );
    final s = ConversationSession(
      delaiReflexion: Duration.zero,
      piecesJointes: service,
      moteur: MoteurConversationHybride(
        ia: MoteurConversationIA(
          ApiJarvis(
            adresse: Uri.parse('http://localhost:8000'),
            jeton: () async => 'jeton',
            client: client,
          ),
          analyseWhatsApp: () => 'allowed',
        ),
      ),
    );
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ConversationPage(
              session: s,
              gabarit: GabaritJarvis.of(context),
              surPoserQuestion: () {},
            ),
          ),
        ),
      ),
    );
    s.envoyer('Qui a écrit ça ?');
    // Réponse du serveur simulé (vraie asynchronie), puis écriture.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await finirEcritures(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final carte = find.byType(CarteReference);
    expect(carte, findsOneWidget);
    final avant = List.of(s.messages);
    await tester.tap(carte);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(ResumeWhatsAppPage), findsOneWidget);
    expect(
      find.textContaining('mdr, le ministre', findRichText: true),
      findsWidgets,
    );
    expect(service.appels.single, (2459, 120));
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.byType(ResumeWhatsAppPage), findsNothing);
    expect(s.messages, avant);
    expect(find.byType(CarteReference), findsOneWidget);
  });
}
