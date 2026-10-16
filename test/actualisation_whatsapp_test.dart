import 'dart:async';
// Phase 5 : actualisation manuelle d'une conversation WhatsApp. Ligne
// « Importer une conversation » glissable, volet « Actualiser la
// conversation WhatsApp », client HTTP. Serveur simulé ; données fictives.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversations/depot_conversations.dart';
import 'package:ia_jarvis/services/importation/actualisation_whatsapp.dart';
import 'package:ia_jarvis/widgets/feuille_ajout.dart';
import 'package:ia_jarvis/widgets/importation/volet_actualisation.dart';

ContexteServeur _ctx(
  String id,
  String contact, {
  List<String>? participants,
  bool groupe = false,
  String? moi = 'Alex Martin',
}) => ContexteServeur(
  id: id,
  consigne: null,
  contact: contact,
  nombre: 96,
  creeLe: DateTime(2026, 10, 15),
  participants: participants ?? [contact, 'Alex Martin'],
  moi: moi,
  groupe: groupe,
);

final _lina = _ctx('c-lina', 'Lina Moreau');
final _nova = _ctx(
  'c-nova',
  'Projet Nova',
  groupe: true,
  participants: ['Alex Martin', 'Nora Laurent', 'Samuel Petit'],
);

class _Service implements ServiceActualisationWhatsApp {
  final envois = <(String, List<Map<String, Object?>>, bool)>[];
  List<ContexteServeur> tous = [];
  ResultatAjout Function(bool confirmer)? reponse;
  List<MessageAjoute> ajoutesListe = [];
  final corrections = <(String, String?)>[];
  final suppressions = <String>[];

  @override
  Future<ResultatApi<List<ContexteServeur>>> contextes() async =>
      SuccesApi(tous);

  @override
  Future<ResultatAjout> ajouter(
    String contexte,
    List<EntreeActualisation> entrees, {
    bool confirmer = false,
  }) async {
    envois.add((contexte, [for (final e in entrees) e.versJson()], confirmer));
    return reponse?.call(confirmer) ??
        AjoutReussi([
          for (final (i, e) in entrees.indexed)
            MessageAjoute(
              id: e.id,
              ordre: 96 + i,
              sens: e.sens,
              auteur: e.auteur ?? 'Alex Martin',
              texte: e.texte,
            ),
        ]);
  }

  @override
  Future<ResultatApi<List<MessageAjoute>>> ajoutes(String contexte) async =>
      SuccesApi(ajoutesListe);

  @override
  Future<ResultatApi<void>> modifier(
    String contexte,
    String message, {
    String? texte,
    String? auteur,
  }) async {
    corrections.add((message, texte));
    return const SuccesApi(null);
  }

  @override
  Future<ResultatApi<void>> supprimer(String contexte, String message) async {
    suppressions.add(message);
    return const SuccesApi(null);
  }
}

/// Une page avec un brouillon, d'où l'on ouvre le volet.
Future<(Future<AjoutsEnregistres?> Function(), TextEditingController)> _page(
  WidgetTester tester,
  _Service service, {
  List<ContexteServeur> contextes = const [],
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final brouillon = TextEditingController(text: 'Mon brouillon pour JARVIS');
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) {
            ctx = c;
            return TextField(
              key: const Key('brouillon'),
              controller: brouillon,
            );
          },
        ),
      ),
    ),
  );
  return (
    () => afficherVoletActualisation(
      ctx,
      service: service,
      contextesDuChat: contextes,
    ),
    brouillon,
  );
}

Future<void> _feuille(
  WidgetTester tester,
  List<ChoixAjout?> choix, {
  bool actualisation = true,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () async => choix.add(
              await afficherFeuilleAjout(c, actualisation: actualisation),
            ),
            child: const Text('plus'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('plus'));
  await tester.pumpAndSettle();
}

void main() {
  group('ligne « Importer une conversation »', () {
    testWidgets('appui normal : import classique, inchangé', (tester) async {
      final choix = <ChoixAjout?>[];
      await _feuille(tester, choix);
      await tester.tap(find.text('Importer une conversation'));
      await tester.pumpAndSettle();
      expect(choix, [ChoixAjout.importerWhatsApp]);
    });

    testWidgets(
      'glisser à gauche révèle l’action ; elle ouvre l’actualisation',
      (tester) async {
        final choix = <ChoixAjout?>[];
        await _feuille(tester, choix);
        await tester.drag(
          find.byKey(const Key('ligne-importer')),
          const Offset(-200, 0),
        );
        await tester.pumpAndSettle();
        expect(choix, isEmpty); // le glissement n'importe rien
        await tester.tap(
          find.byKey(const Key('action-glissee-ajouter-message')),
        );
        await tester.pumpAndSettle();
        expect(choix, [ChoixAjout.ajouterMessageWhatsApp]);
      },
    );

    testWidgets('glissement trop court : retour ; ligne ouverte + appui : '
        'elle se referme sans importer', (tester) async {
      final choix = <ChoixAjout?>[];
      await _feuille(tester, choix);
      final ligne = find.byKey(const Key('ligne-importer'));
      await tester.drag(ligne, const Offset(-50, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(ligne).dx,
        tester.getTopLeft(find.byType(LigneImportGlissante)).dx,
      );
      await tester.drag(ligne, const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Importer une conversation'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(choix, isEmpty);
      expect(
        tester.getTopLeft(ligne).dx,
        tester.getTopLeft(find.byType(LigneImportGlissante)).dx,
      );
    });

    testWidgets('défilement vertical : jamais d’action', (tester) async {
      final choix = <ChoixAjout?>[];
      await _feuille(tester, choix);
      await tester.drag(
        find.byKey(const Key('ligne-importer')),
        const Offset(-10, 120),
      );
      await tester.pumpAndSettle();
      final ligne = find.byKey(const Key('ligne-importer'));
      expect(
        tester.getTopLeft(ligne).dx,
        tester.getTopLeft(find.byType(LigneImportGlissante)).dx,
      );
    });

    testWidgets('sans compte : aucune action secondaire', (tester) async {
      final choix = <ChoixAjout?>[];
      await _feuille(tester, choix, actualisation: false);
      expect(find.byKey(const Key('ligne-importer')), findsNothing);
      await tester.tap(find.text('Importer une conversation'));
      await tester.pumpAndSettle();
      expect(choix, [ChoixAjout.importerWhatsApp]);
    });

    testWidgets('souris (Windows / Web) : petite action au survol', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final choix = <ChoixAjout?>[];
      await _feuille(tester, choix);
      expect(find.byKey(const Key('action-ajouter-message')), findsNothing);
      final souris = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await souris.addPointer(
        location: tester.getCenter(find.text('Importer une conversation')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-ajouter-message')));
      await tester.pumpAndSettle();
      expect(choix, [ChoixAjout.ajouterMessageWhatsApp]);
      await souris.removePointer();
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('volet', () {
    testWidgets('fermé par erreur (appui à côté) : saisie rendue à la '
        'réouverture, mêmes identifiants ; vidé après l’ajout', (tester) async {
      brouillonsActualisation.clear();
      final service = _Service();
      final (ouvrir, _) = await _page(tester, service, contextes: [_lina]);
      unawaited(ouvrir());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Envoyé').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('texte-entree-0')),
        "Je voulais justement t'en parler aujourd'hui.",
      );
      // Appui sur le voile, hors du volet : fermeture accidentelle.
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.byType(VoletActualisation), findsNothing);
      expect(service.envois, isEmpty);
      final resultat = ouvrir();
      await tester.pumpAndSettle();
      expect(
        find.text("Je voulais justement t'en parler aujourd'hui."),
        findsOneWidget,
      );
      expect(find.text('De : Alex Martin (vous)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmer-ajout')));
      await tester.pumpAndSettle();
      expect(await resultat, isNotNull);
      final envoi = service.envois.single.$2.single;
      expect(envoi['content'], "Je voulais justement t'en parler aujourd'hui.");
      expect(envoi['direction'], 'sent');
      expect(brouillonsActualisation, isEmpty);
    });

    testWidgets('contact proposé, reçu puis envoyé, ordre gardé ; brouillon '
        'intact', (tester) async {
      final service = _Service();
      final (ouvrir, brouillon) = await _page(
        tester,
        service,
        contextes: [_lina],
      );
      late Future<AjoutsEnregistres?> resultat;
      resultat = ouvrir();
      await tester.pumpAndSettle();
      expect(find.text('Lina Moreau'), findsOneWidget);
      expect(find.text(VoletActualisation.sousTitre), findsOneWidget);
      expect(find.text('De : Lina Moreau'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('texte-entree-0')),
        'Ah bon ? Et tu comptais me le dire quand ?',
      );
      // Vue principale minimale : plusieurs messages et date dans Options.
      expect(find.byKey(const Key('ajouter-entree')), findsNothing);
      expect(find.byKey(const Key('date-entree-0')), findsNothing);
      await tester.tap(find.byKey(const Key('options-actualisation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ajouter-entree')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('sens-1')),
          matching: find.text('Envoyé'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('De : Alex Martin (vous)'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('texte-entree-1')),
        'Finalement je serai disponible samedi.',
      );
      await tester.enterText(
        find.byKey(const Key('date-entree-1')),
        '16/10/2026 09:12',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmer-ajout')));
      await tester.pumpAndSettle();
      expect((await resultat)!.messages.length, 2);
      expect((await resultat)!.contexte.id, 'c-lina');
      final (ctx, messages, confirmer) = service.envois.single;
      expect(ctx, 'c-lina');
      expect(confirmer, isFalse);
      expect(messages.map((m) => (m['direction'], m['author'], m['content'])), [
        (
          'received',
          'Lina Moreau',
          'Ah bon ? Et tu comptais me le dire quand ?',
        ),
        ('sent', null, 'Finalement je serai disponible samedi.'),
      ]);
      expect(messages[0].containsKey('sent_at'), isFalse); // rien d'inventé
      expect(messages[1]['sent_at'], '2026-10-16T09:12:00');
      expect(brouillon.text, 'Mon brouillon pour JARVIS');
    });

    testWidgets('groupe : auteur obligatoire, choisi parmi les participants', (
      tester,
    ) async {
      final service = _Service();
      final (ouvrir, _) = await _page(tester, service, contextes: [_nova]);
      ouvrir();
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('texte-entree-0')), 'oui');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirmer-ajout')))
            .onPressed,
        isNull,
      );
      expect(
        find.byKey(const Key('auteur-0-Alex Martin')),
        findsNothing,
      ); // jamais « moi » en reçu
      await tester.tap(find.byKey(const Key('auteur-0-Samuel Petit')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmer-ajout')));
      await tester.pumpAndSettle();
      expect(service.envois.single.$2.single['author'], 'Samuel Petit');
    });

    testWidgets(
      'plusieurs contextes : choix demandé ; aucun : liste du compte',
      (tester) async {
        final service = _Service()..tous = [_lina, _nova];
        final (ouvrir, _) = await _page(
          tester,
          service,
          contextes: [_lina, _nova],
        );
        ouvrir();
        await tester.pumpAndSettle();
        expect(find.text('Choisissez la conversation'), findsOneWidget);
        expect(find.byKey(const Key('texte-entree-0')), findsNothing);
        await tester.tap(find.byKey(const Key('contexte-c-nova')));
        await tester.pumpAndSettle();
        expect(find.text('Projet Nova'), findsWidgets);
        Navigator.of(
          tester.element(find.byKey(const Key('volet-actualisation'))),
        ).pop();
        await tester.pumpAndSettle();

        final (ouvrir2, _) = await _page(tester, service);
        ouvrir2();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('contexte-c-lina')), findsOneWidget);
        expect(find.byKey(const Key('contexte-c-nova')), findsOneWidget);
      },
    );

    testWidgets('réorganiser et retirer avant confirmation', (tester) async {
      final service = _Service();
      final (ouvrir, _) = await _page(tester, service, contextes: [_lina]);
      ouvrir();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('texte-entree-0')),
        'Premier',
      );
      await tester.tap(find.byKey(const Key('options-actualisation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ajouter-entree')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('texte-entree-1')), 'Second');
      await tester.tap(find.byKey(const Key('ajouter-entree')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('texte-entree-2')),
        'À retirer',
      );
      await tester.tap(find.byKey(const Key('retirer-entree-2')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('entree-1')),
          matching: find.byTooltip('Monter'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmer-ajout')));
      await tester.pumpAndSettle();
      expect(service.envois.single.$2.map((m) => m['content']), [
        'Second',
        'Premier',
      ]);
    });

    testWidgets('extrait WhatsApp collé : séparé sur demande, auteurs du '
        'contexte, sens déduit de « Vous êtes »', (tester) async {
      final service = _Service();
      final (ouvrir, _) = await _page(tester, service, contextes: [_lina]);
      ouvrir();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('texte-entree-0')),
        '16/10/2026 09:10 - Lina Moreau: Tu viens samedi ?\n'
        '16/10/2026 09:12 - Alex Martin: Oui !\nÀ 20h ?',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('separer-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmer-ajout')));
      await tester.pumpAndSettle();
      final m = service.envois.single.$2;
      expect(m.map((x) => (x['direction'], x['content'], x['sent_at'])), [
        ('received', 'Tu viens samedi ?', '2026-10-16T09:10:00'),
        ('sent', 'Oui !\nÀ 20h ?', '2026-10-16T09:12:00'),
      ]);
    });

    testWidgets('texte sur plusieurs lignes sans en-tête : un seul message', (
      tester,
    ) async {
      final service = _Service();
      final (ouvrir, _) = await _page(tester, service, contextes: [_lina]);
      ouvrir();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('texte-entree-0')),
        'Ligne un\nLigne deux\nLigne trois',
      );
      await tester.pump();
      expect(find.byKey(const Key('separer-0')), findsNothing);
    });

    testWidgets('doublons signalés : retirer ou confirmer', (tester) async {
      final service = _Service()
        ..reponse = (confirmer) => confirmer
            ? const AjoutReussi([])
            : const DoublonsPossibles([
                Correspondance(
                  index: 0,
                  declaration: true,
                  texte: 'Hâte de te voir !',
                ),
              ]);
      final (ouvrir, _) = await _page(tester, service, contextes: [_lina]);
      ouvrir();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('sens-0')),
          matching: find.text('Envoyé'),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('texte-entree-0')),
        'Hâte de te voir !',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmer-ajout')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doublons')), findsOneWidget);
      expect(
        find.textContaining('proposition déjà déclarée envoyée'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('ajouter-quand-meme')));
      await tester.pumpAndSettle();
      expect(service.envois.map((e) => e.$3), [false, true]);
    });

    testWidgets('erreur : message affiché, volet et saisie conservés', (
      tester,
    ) async {
      final service = _Service()
        ..reponse = (_) =>
            const EchecAjout('Serveur JARVIS injoignable. Réessayez.');
      final (ouvrir, _) = await _page(tester, service, contextes: [_lina]);
      ouvrir();
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('texte-entree-0')), 'Coucou');
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmer-ajout')));
      await tester.pumpAndSettle();
      expect(
        find.text('Serveur JARVIS injoignable. Réessayez.'),
        findsOneWidget,
      );
      expect(find.text('Coucou'), findsOneWidget);
    });

    testWidgets('ajouts consultés, corrigés et supprimés', (tester) async {
      final service = _Service()
        ..ajoutesListe = [
          const MessageAjoute(
            id: 'a1',
            ordre: 96,
            sens: SensMessage.recu,
            auteur: 'Lina Moreau',
            texte: 'Ah bon',
          ),
        ];
      final (ouvrir, _) = await _page(tester, service, contextes: [_lina]);
      ouvrir();
      await tester.pumpAndSettle();
      expect(find.text('Ajoutés à la main (1)'), findsNothing); // dans Options
      await tester.tap(find.byKey(const Key('options-actualisation')));
      await tester.pumpAndSettle();
      expect(find.text('Ajoutés à la main (1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('corriger-a1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('edition-ajout')),
        'Ah bon ?',
      );
      await tester.tap(find.byKey(const Key('enregistrer-correction')));
      await tester.pumpAndSettle();
      expect(service.corrections.single, ('a1', 'Ah bon ?'));
      await tester.tap(find.byKey(const Key('supprimer-a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmer-suppression-ajout')));
      await tester.pumpAndSettle();
      expect(service.suppressions.single, 'a1');
    });
  });

  group('client', () {
    test('corps envoyé et doublons lus (409)', () async {
      final requetes = <http.Request>[];
      final api = ApiJarvis(
        adresse: Uri.parse('http://localhost:8000'),
        jeton: () async => 'jeton',
        client: MockClient((r) async {
          requetes.add(r);
          final corps = jsonDecode(r.body) as Map<String, dynamic>;
          if (corps['confirm_duplicates'] == false) {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'detail': {
                    'code': 'correspondances',
                    'items': [
                      {
                        'index': 0,
                        'type': 'message',
                        'texte': 'Bonne nuit',
                        'message_order': 41,
                      },
                    ],
                  },
                }),
              ),
              409,
            );
          }
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'id': 'm1',
                  'message_order': 96,
                  'origin': 'manual_received',
                  'author': 'Lina Moreau',
                  'content': 'Bonne nuit',
                  'sent_at': null,
                },
              ],
            }),
            201,
          );
        }),
      );
      final service = ActualisationWhatsAppApi(api);
      final e = EntreeActualisation(texte: 'Bonne nuit', auteur: 'Lina Moreau');
      final r1 = await service.ajouter('c-lina', [e]);
      expect((r1 as DoublonsPossibles).items.single.texte, 'Bonne nuit');
      final r2 = await service.ajouter('c-lina', [e], confirmer: true);
      expect((r2 as AjoutReussi).messages.single.auteur, 'Lina Moreau');
      expect(requetes.first.url.path, '/api/v1/contexts/c-lina/messages');
      final envoye = jsonDecode(requetes.last.body) as Map<String, dynamic>;
      expect(
        envoye['messages'][0]['id'],
        e.id,
      ); // même identifiant : sans doublon
    });
  });
}
