// Captures des styles et des motifs (Paramètres › Général › Apparence).
//
//   CAPTURE_DIR=chemin flutter test tool/capture_apparence_test.dart
//
// Pour chaque style, en clair puis en sombre : la vraie page d'accueil
// (fond, particules, barre) avec une conversation (réponse, conversation
// collée, choix du ton). Puis chaque motif sur l'accueil vide, et les pages
// Thèmes et Motifs des Paramètres.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/apparence/preferences_apparence.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/apparence/service_apparence.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/motifs_jarvis.dart';
import 'package:ia_jarvis/theme/styles_jarvis.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/apparence/transition_apparence.dart';
import 'package:ia_jarvis/widgets/parametres/pages_jarvis_touch.dart';
import 'package:ia_jarvis/widgets/parametres/panneau_general.dart';
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

  Widget app(ServiceApparence a, Widget page, GlobalKey cle) => RepaintBoundary(
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
            child: TransitionApparence(service: a, child: enfant!),
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

  for (final (page, nom) in [
    (PageGenerale.themes, 'themes'),
    (PageGenerale.motifs, 'motifs'),
  ]) {
    for (final (style, mode) in [
      (StyleVisuel.jarvis, ModeAffichage.clair),
      (StyleVisuel.sape, ModeAffichage.sombre),
    ]) {
      testWidgets('page $nom ${style.name} ${mode.name}', (tester) async {
        telephone(tester);
        tester.view.physicalSize = const Size(390, 1500) * 2;
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
                  child: PanneauGeneral(page: page),
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
}
