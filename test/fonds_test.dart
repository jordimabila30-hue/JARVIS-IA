import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/apparence/fond_photo.dart';
import 'package:ia_jarvis/models/apparence/preferences_apparence.dart';
import 'package:ia_jarvis/pages/editeur_fond_page.dart';
import 'package:ia_jarvis/services/apparence/depot_fonds_photo.dart';
import 'package:ia_jarvis/services/apparence/service_apparence.dart';
import 'package:ia_jarvis/services/apparence/service_fonds.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/motifs_jarvis.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/apparence/feuille_fond_conversation.dart';
import 'package:ia_jarvis/widgets/apparence/rendu_fond_photo.dart';
import 'package:ia_jarvis/widgets/parametres/pages_apparence.dart';

/// PNG uni de [l] × [h] (une vraie photo pour le décodeur).
Future<Uint8List> png(int l, int h) async {
  final r = ui.PictureRecorder();
  Canvas(r).drawRect(
    Rect.fromLTWH(0, 0, l.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF3366AA),
  );
  final image = await r.endRecording().toImage(l, h);
  final octets = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return octets!.buffer.asUint8List();
}

Future<(ServiceApparence, ServiceFonds, DepotFondsPhotoMemoire)> services({
  StockageMemoire? prefs,
  StockageMemoire? fondsStockage,
  DepotFondsPhotoMemoire? depot,
}) async {
  final a = ServiceApparence(stockage: prefs ?? StockageMemoire());
  await a.charger();
  final d = depot ?? DepotFondsPhotoMemoire();
  final f = ServiceFonds(
    apparence: a,
    depot: d,
    stockage: fondsStockage ?? StockageMemoire(),
  );
  await f.charger();
  return (a, f, d);
}

void main() {
  tearDown(() => PaletteJarvis.active = PaletteJarvis.jarvisClair);

  group('Modèle', () {
    test('réglages : aller-retour JSON, bornes, valeurs illisibles', () {
      const r = ReglagesPhoto(
        visibilite: 0.6,
        flou: 8,
        assombrissement: 0.4,
        zoom: 1.5,
        decalage: Offset(0.1, -0.05),
      );
      expect(ReglagesPhoto.depuisJson(r.versJson()), r);
      final b = ReglagesPhoto.depuisJson({
        'visibilite': 0,
        'flou': 99,
        'assombrissement': 'fort',
        'zoom': 50,
      });
      expect(b.visibilite, ReglagesPhoto.visibiliteMin);
      expect(b.flou, ReglagesPhoto.flouMax);
      expect(b.assombrissement, ReglagesPhoto.parDefaut.assombrissement);
      expect(b.zoom, ReglagesPhoto.zoomMax);
    });

    test('identifiants de photo : jamais de chemin', () {
      expect(FondPhoto.depuisJson({'id': '../secret'}), isNull);
      expect(FondPhoto.depuisJson({'id': 'abc123'})?.id, 'abc123');
    });

    test(
      'préférences : photo enregistrée ; anciennes préférences intactes',
      () {
        const p = PreferencesApparence(
          motif: MotifJarvis.kubaVelours,
          photo: FondPhoto(id: 'p1'),
          photoActive: true,
        );
        final relu = PreferencesApparence.decoder(p.encoder());
        expect(relu, p);
        expect(relu.fondGeneral, isA<FondPhotoChoisi>());
        // Préférences d'avant (sans photo) : motif, aucune photo.
        final ancien = PreferencesApparence.decoder(
          '{"v":1,"motif":"kubaTissu","intensite":0.3}',
        );
        expect(ancien.photo, isNull);
        expect(ancien.fondGeneral, const FondMotif(MotifJarvis.kubaTissu, 0.3));
      },
    );

    test('deux nouveaux motifs dans le registre, les anciens gardés', () {
      expect(MotifJarvis.values, contains(MotifJarvis.kubaVelours));
      expect(MotifJarvis.values, contains(MotifJarvis.kubaLabyrinthe));
      for (final m in [
        MotifJarvis.aucun,
        MotifJarvis.aurore,
        MotifJarvis.kubaLosanges,
        MotifJarvis.kubaTissu,
        MotifJarvis.kubaFrises,
        MotifJarvis.coeurKuba,
      ]) {
        expect(MotifJarvis.values, contains(m));
      }
    });
  });

  group('Fond général et fonds par conversation', () {
    test(
      'photo générale ; motif choisi → photo gardée mais inactive',
      () async {
        final (a, f, d) = await services();
        final id = await f.importer(await png(40, 30));
        await f.definirGeneral(FondPhoto(id: id));
        expect(a.photoActive, isTrue);
        expect(a.fondGeneral, isA<FondPhotoChoisi>());
        await a.choisirMotif(MotifJarvis.kubaLabyrinthe);
        expect(a.photoActive, isFalse);
        expect(a.photo?.id, id);
        await f.nettoyer();
        expect(d.fichiers.keys, contains(id)); // gardée pour « Ma galerie »
        await a.activerPhoto();
        expect(a.fondGeneral, isA<FondPhotoChoisi>());
      },
    );

    test('conversation : son fond, sinon le général ; retour au général ; '
        'restauré après redémarrage', () async {
      final prefs = StockageMemoire();
      final stock = StockageMemoire();
      final depot = DepotFondsPhotoMemoire();
      var (a, f, _) = await services(
        prefs: prefs,
        fondsStockage: stock,
        depot: depot,
      );
      await a.choisirMotif(MotifJarvis.kubaFrises);
      final id = await f.importer(await png(20, 20));
      await f.definir('c1', FondPhotoChoisi(FondPhoto(id: id)));
      await f.definir('c2', const FondMotif(MotifJarvis.coeurKuba, 0.7));
      expect(f.fondAffiche(['c1']), isA<FondPhotoChoisi>());
      expect(
        f.fondAffiche(['c2']),
        const FondMotif(MotifJarvis.coeurKuba, 0.7),
      );
      expect(f.fondAffiche(['c3']), a.fondGeneral);
      // Identifiant serveur d'abord, local ensuite.
      expect(f.fondDe(['inconnu', 'c2']), isA<FondMotif>());

      // « Redémarrage ».
      (a, f, _) = await services(
        prefs: prefs,
        fondsStockage: stock,
        depot: depot,
      );
      expect(f.fondAffiche(['c1']), isA<FondPhotoChoisi>());
      expect(a.motif, MotifJarvis.kubaFrises);

      await f.definir('c1', null);
      expect(f.fondDe(['c1']), isNull);
      expect(f.fondAffiche(['c1']), a.fondGeneral);
      // Photo plus utilisée : supprimée du dépôt.
      expect(depot.fichiers.keys, isNot(contains(id)));
    });

    test('nettoyage : seules les photos inutilisées disparaissent', () async {
      final (a, f, d) = await services();
      final orpheline = await d.enregistrer(await png(4, 4));
      final enCours = await f.importer(await png(4, 4)); // pas attribuée
      final generale = await f.importer(await png(4, 4));
      await f.definirGeneral(FondPhoto(id: generale));
      await f.nettoyer();
      expect(d.fichiers.keys, isNot(contains(orpheline)));
      expect(d.fichiers.keys, containsAll([enCours, generale]));
      await f.abandonner(enCours);
      expect(d.fichiers.keys, isNot(contains(enCours)));
      // Nouvelle photo générale : l'ancienne est supprimée.
      final nouvelle = await f.importer(await png(4, 4));
      await f.definirGeneral(FondPhoto(id: nouvelle));
      expect(d.fichiers.keys, [nouvelle]);
      expect(a.photo?.id, nouvelle);
    });

    test('photo trop lourde refusée', () async {
      final (_, f, _) = await services();
      expect(
        () => f.importer(Uint8List(DepotFondsPhoto.tailleMax + 1)),
        throwsFormatException,
      );
    });
  });

  group('Rendu', () {
    test('décodage réduit, composition à la taille de l’écran', () async {
      final octets = await png(1200, 800);
      final source = (await decoderFondPhoto(octets, coteMax: 600))!;
      expect(source.width, 600);
      expect(source.height, 400);
      final composee = composerFondPhoto(
        source,
        const Size(100, 200),
        2,
        const ReglagesPhoto(flou: 6, assombrissement: 0.3),
      );
      expect(composee.width, 200);
      expect(composee.height, 400);
      source.dispose();
      composee.dispose();
      expect(await decoderFondPhoto(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('cadrage : la photo couvre toujours l’écran', () {
      const source = Size(1000, 500), cadre = Size(400, 800);
      final r = rectanglePhoto(
        source,
        cadre,
        const ReglagesPhoto(zoom: 1, decalage: Offset(5, 5)),
      );
      expect(r.left, lessThanOrEqualTo(0));
      expect(r.top, lessThanOrEqualTo(0));
      expect(r.right, greaterThanOrEqualTo(cadre.width));
      expect(r.bottom, greaterThanOrEqualTo(cadre.height));
    });
  });

  group('Interface', () {
    Future<(ServiceApparence, ServiceFonds, DepotFondsPhotoMemoire)> ouvrir(
      WidgetTester tester,
      Widget Function(ServiceApparence, ServiceFonds) page, {
      bool avecPhoto = false,
    }) async {
      tester.view.physicalSize = const Size(412, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = await tester.runAsync(() async {
        final r = await services();
        if (avecPhoto) {
          final id = await r.$2.importer(await png(60, 40));
          await r.$2.definirGeneral(FondPhoto(id: id));
          await r.$1.choisirMotif(MotifJarvis.kubaTissu);
        }
        return r;
      });
      final (a, f, _) = s!;
      await tester.pumpWidget(
        MaterialApp(
          theme: themeJarvis(),
          builder: (context, enfant) => PorteeApparence(
            service: a,
            child: PorteeFonds(service: f, child: enfant!),
          ),
          home: Scaffold(body: page(a, f)),
        ),
      );
      await tester.pumpAndSettle();
      return s;
    }

    testWidgets('Apparence : nouveaux motifs et « Ma galerie » en fin de '
        'carrousel ; photo inactive réactivée d’un toucher', (tester) async {
      final (a, _, _) = await ouvrir(
        tester,
        (a, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: PageApparence(apparence: a),
        ),
        avecPhoto: true,
      );
      final motifs = find.byType(PageView).at(1);
      for (var i = 0; i < 10; i++) {
        await tester.drag(motifs, const Offset(-300, 0));
        await tester.pumpAndSettle();
      }
      expect(find.text(CarrouselFonds.nomGalerie), findsOneWidget);
      expect(a.photoActive, isFalse);
      expect(find.text('Intensité'), findsOneWidget);
      await tester.tap(find.text(CarrouselFonds.nomGalerie));
      await tester.pumpAndSettle();
      expect(a.photoActive, isTrue);
      // Photo active : plus d'intensité (motifs seulement), mais
      // « Ajuster la photo ».
      expect(find.text('Intensité'), findsNothing);
      expect(find.text('Ajuster la photo'), findsOneWidget);
      expect(find.text('Changer de photo'), findsOneWidget);
      // Les deux nouveaux motifs sont dans ce carrousel.
      await tester.drag(motifs, const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(
        find.text('Kuba 4 · Velours').evaluate().isNotEmpty ||
            find.text('Kuba 5 · Labyrinthe').evaluate().isNotEmpty,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('éditeur : réglages en direct, Appliquer range la photo, '
        'Annuler ne garde rien', (tester) async {
      FondPhoto? rendue;
      var fini = false;
      late ServiceFonds fonds;
      late DepotFondsPhotoMemoire depot;
      final octets = (await tester.runAsync(() => png(300, 200)))!;
      (_, fonds, depot) = await ouvrir(
        tester,
        (a, f) => Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                rendue = await ouvrirEditeurFond(
                  context,
                  fonds: f,
                  octets: octets,
                );
                fini = true;
              },
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      );
      Future<void> ouvrirEditeur() async {
        fini = false;
        await tester.tap(find.text('Ouvrir'));
        await tester.pump();
        // Décodage réel de la photo.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();
      }

      await ouvrirEditeur();
      expect(find.text('Personnaliser le fond'), findsOneWidget);
      expect(find.text('Visibilité de la photo'), findsOneWidget);
      expect(find.text('Flou de l’arrière-plan'), findsOneWidget);
      expect(find.text('Assombrissement'), findsOneWidget);
      // Conversation de démonstration.
      expect(find.text('Bonjour JARVIS'), findsOneWidget);
      // Annuler : rien de gardé.
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(fini, isTrue);
      expect(rendue, isNull);
      expect(depot.fichiers, isEmpty);

      await ouvrirEditeur();
      await tester.drag(find.byType(Slider).at(1), const Offset(200, 0));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Appliquer'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(rendue, isNotNull);
      expect(rendue!.reglages.flou, greaterThan(0));
      expect(depot.fichiers.keys, contains(rendue!.id));
      await tester.runAsync(() => fonds.abandonner(rendue!.id));
      expect(tester.takeException(), isNull);
    });

    testWidgets('fiche d’une conversation : motif propre puis retour au '
        'fond général', (tester) async {
      final (_, f, _) = await ouvrir(
        tester,
        (a, f) => FeuilleFondConversation(fonds: f, id: 'c9', titre: 'Sarah'),
      );
      expect(find.text(FeuilleFondConversation.general), findsOneWidget);
      expect(find.text(FeuilleFondConversation.photo), findsOneWidget);
      await tester.tap(find.text(FeuilleFondConversation.motif));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sans motif'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(f.fondDe(['c9']), const FondMotif(MotifJarvis.aucun, 0.5));
      await tester.tap(find.text(FeuilleFondConversation.general));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(f.fondDe(['c9']), isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
