// Captures des styles et des motifs (Paramètres › Général › Apparence).
//
//   CAPTURE_DIR=chemin flutter test tool/capture_apparence_test.dart
//
// Pour chaque style, en clair puis en sombre : la vraie page d'accueil
// (fond, particules, barre) avec une conversation (réponse, conversation
// collée, choix du ton). Puis chaque motif sur l'accueil vide, et les pages
// Apparence des Paramètres (page unique, carrousels).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/apparence/preferences_apparence.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/models/apparence/fond_photo.dart';
import 'package:ia_jarvis/pages/editeur_fond_page.dart';
import 'package:ia_jarvis/services/apparence/depot_fonds_photo.dart';
import 'package:ia_jarvis/services/apparence/service_apparence.dart';
import 'package:ia_jarvis/services/apparence/service_fonds.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/motifs_jarvis.dart';
import 'package:ia_jarvis/theme/styles_jarvis.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/apparence/transition_apparence.dart';
import 'package:ia_jarvis/widgets/parametres/pages_apparence.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

import '../test/outils/ecriture.dart';

const _polices = r'C:\flutter\bin\cache\artifacts\material_fonts';

Future<void> _charger(String famille, List<String> fichiers) async {
  final f = FontLoader(famille);
  for (final nom in fichiers) {
    final octets = File(nom).readAsBytesSync();
    f.addFont(Future.value(ByteData.view(octets.buffer)));
  }
  await f.load();
}

const _sarah =
    'Sarah : Tu aurais pu me prévenir.\n'
    'Moi : Désolé, j’étais occupé.\n'
    'Sarah : Ce n’est pas la première fois.';

void main() {
  final dossier = Platform.environment['CAPTURE_DIR'];

  setUpAll(() async {
    await _charger('Roboto', [
      for (final s in ['regular', 'medium', 'bold', 'italic', 'light'])
        '$_polices\\roboto-$s.ttf',
    ]);
    await _charger('MaterialIcons', ['$_polices\\materialicons-regular.otf']);
    await _charger('Exo2', ['assets/polices/Exo2.ttf']);
    await _charger('Baloo2', ['assets/polices/Baloo2.ttf']);
  });
  tearDown(() => PaletteJarvis.active = PaletteJarvis.jarvisClair);

  Future<ServiceApparence> apparence(PreferencesApparence p) async {
    final s = ServiceApparence(stockage: StockageMemoire(p.encoder()));
    await s.charger();
    return s;
  }

  Widget app(
    ServiceApparence a,
    Widget page,
    GlobalKey cle, {
    ServiceFonds? fonds,
  }) => RepaintBoundary(
    key: cle,
    child: ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final theme = themeJarvis(a.palette);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
          ),
          builder: (context, enfant) => PorteeApparence(
            service: a,
            child: fonds == null
                ? TransitionApparence(service: a, child: enfant!)
                : PorteeFonds(
                    service: fonds,
                    child: TransitionApparence(service: a, child: enfant!),
                  ),
          ),
          home: page,
        );
      },
    ),
  );

  Future<void> photo(WidgetTester tester, GlobalKey cle, String nom) async {
    if (dossier == null) return;
    final objet =
        cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await objet.toImage(
        pixelRatio: tester.view.devicePixelRatio,
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dossier/$nom.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> images(WidgetTester tester, int k) async {
    for (var i = 0; i < k; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  void telephone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  for (final style in StyleVisuel.values) {
    for (final mode in [ModeAffichage.clair, ModeAffichage.sombre]) {
      testWidgets('style ${style.name} ${mode.name}', (tester) async {
        telephone(tester);
        final a = await apparence(
          PreferencesApparence(style: style, mode: mode),
        );
        final cle = GlobalKey();
        await tester.pumpWidget(
          app(
            a,
            AccueilPage(
              pim: PimController(),
              conversation: ConversationSession(
                delaiReflexion: const Duration(milliseconds: 200),
              ),
            ),
            cle,
          ),
        );
        await images(tester, 60);
        Future<void> envoyer(String t) async {
          await tester.enterText(find.byType(EditableText), t);
          await images(tester, 5);
          await tester.testTextInput.receiveAction(TextInputAction.send);
          await images(tester, 60);
          await finirEcritures(tester);
        }

        await envoyer('Comment fonctionne une batterie ?');
        await envoyer(_sarah);
        await envoyer('Tu peux me dire quoi répondre ?');
        await images(tester, 30);
        await photo(tester, cle, 'style_${style.name}_${mode.name}');
        expect(tester.takeException(), isNull);
        a.dispose();
      });
    }
  }

  for (final motif in MotifJarvis.values) {
    for (final (style, mode) in [
      (StyleVisuel.jarvis, ModeAffichage.clair),
      (StyleVisuel.raphiaKuba, ModeAffichage.clair),
      (StyleVisuel.congotronics, ModeAffichage.sombre),
    ]) {
      testWidgets('motif ${motif.name} ${style.name} ${mode.name}', (
        tester,
      ) async {
        telephone(tester);
        final a = await apparence(
          PreferencesApparence(style: style, mode: mode, motif: motif),
        );
        final cle = GlobalKey();
        await tester.pumpWidget(app(a, AccueilPage(pim: PimController()), cle));
        await images(tester, 90);
        await photo(
          tester,
          cle,
          'motif_${motif.name}_${style.name}_${mode.name}',
        );
        expect(tester.takeException(), isNull);
        a.dispose();
      });
    }
  }

  {
    const nom = 'apparence';
    for (final (style, mode) in [
      (StyleVisuel.jarvis, ModeAffichage.clair),
      (StyleVisuel.sape, ModeAffichage.sombre),
    ]) {
      testWidgets('page $nom ${style.name} ${mode.name}', (tester) async {
        telephone(tester);
        final a = await apparence(
          PreferencesApparence(
            style: style,
            mode: mode,
            motif: MotifJarvis.kubaLosanges,
          ),
        );
        final cle = GlobalKey();
        await tester.pumpWidget(
          app(
            a,
            Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: PageApparence(apparence: a),
                ),
              ),
            ),
            cle,
          ),
        );
        await images(tester, 20);
        await photo(tester, cle, 'page_${nom}_${style.name}_${mode.name}');
        expect(tester.takeException(), isNull);
        a.dispose();
      });
    }
  }

  // --- Fonds photo ------------------------------------------------------------

  /// « Photo » d'essai : coucher de soleil et collines (aucun fichier).
  Future<Uint8List> photoEssai() async {
    final r = ui.PictureRecorder();
    final c = Canvas(r);
    const t = Size(900, 1400);
    c.drawRect(
      Offset.zero & t,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFD39A), Color(0xFFF08A5D), Color(0xFF8E5A86)],
        ).createShader(Offset.zero & t),
    );
    c.drawCircle(
      const Offset(620, 520),
      90,
      Paint()..color = const Color(0xFFFFF1C9),
    );
    for (final (y, couleur) in [
      (900.0, const Color(0xFF6B4A78)),
      (1050.0, const Color(0xFF4A3459)),
    ]) {
      final p = Path()..moveTo(0, t.height);
      for (var x = 0.0; x <= t.width; x += 60) {
        p.lineTo(x, y - 80 * (0.5 + 0.5 * ((x / 170) % 2 - 1).abs()));
      }
      p
        ..lineTo(t.width, t.height)
        ..close();
      c.drawPath(p, Paint()..color = couleur);
    }
    final image = await r.endRecording().toImage(900, 1400);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png!.buffer.asUint8List();
  }

  Future<(ServiceApparence, ServiceFonds, Uint8List)> avecPhoto(
    WidgetTester tester,
    PreferencesApparence p,
    ReglagesPhoto reglages,
  ) async {
    final r = await tester.runAsync(() async {
      final a = await apparence(p);
      final f = ServiceFonds(
        apparence: a,
        depot: DepotFondsPhotoMemoire(),
        stockage: StockageMemoire(),
      );
      final octets = await photoEssai();
      final id = await f.importer(octets);
      await f.definirGeneral(FondPhoto(id: id, reglages: reglages));
      return (a, f, octets);
    });
    return r!;
  }

  Future<void> attendre(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await images(tester, 10);
    }
  }

  for (final (style, mode) in [
    (StyleVisuel.jarvis, ModeAffichage.clair),
    (StyleVisuel.congotronics, ModeAffichage.sombre),
  ]) {
    testWidgets('fond photo ${style.name} ${mode.name}', (tester) async {
      telephone(tester);
      final (a, f, _) = await avecPhoto(
        tester,
        PreferencesApparence(style: style, mode: mode),
        const ReglagesPhoto(flou: 4, assombrissement: 0.3, visibilite: 0.9),
      );
      final cle = GlobalKey();
      await tester.pumpWidget(
        app(
          a,
          AccueilPage(
            pim: PimController(),
            conversation: ConversationSession(
              delaiReflexion: const Duration(milliseconds: 200),
            ),
          ),
          cle,
          fonds: f,
        ),
      );
      await attendre(tester);
      await tester.enterText(find.byType(EditableText), _sarah);
      await images(tester, 5);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await images(tester, 60);
      await finirEcritures(tester);
      await attendre(tester);
      await photo(tester, cle, 'fond_photo_${style.name}_${mode.name}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editeur fond', (tester) async {
    telephone(tester);
    final (a, f, octets) = await avecPhoto(
      tester,
      const PreferencesApparence(),
      ReglagesPhoto.parDefaut,
    );
    final cle = GlobalKey();
    await tester.pumpWidget(
      app(
        a,
        EditeurFondPage(fonds: f, octets: octets),
        cle,
        fonds: f,
      ),
    );
    await attendre(tester);
    await photo(tester, cle, 'editeur_fond');
    expect(tester.takeException(), isNull);
  });

  testWidgets('apparence galerie', (tester) async {
    telephone(tester);
    final (a, f, _) = await avecPhoto(
      tester,
      const PreferencesApparence(),
      ReglagesPhoto.parDefaut,
    );
    final cle = GlobalKey();
    await tester.pumpWidget(
      app(
        a,
        Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: PageApparence(apparence: a),
            ),
          ),
        ),
        cle,
        fonds: f,
      ),
    );
    await attendre(tester);
    await photo(tester, cle, 'apparence_galerie');
    expect(tester.takeException(), isNull);
  });
}
