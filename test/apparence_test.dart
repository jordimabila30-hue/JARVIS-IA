import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/apparence/preferences_apparence.dart';
import 'package:ia_jarvis/services/apparence/service_apparence.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/motifs_jarvis.dart';
import 'package:ia_jarvis/theme/styles_jarvis.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/apparence/transition_apparence.dart';
import 'package:ia_jarvis/widgets/fond_jarvis_anime.dart';
import 'package:ia_jarvis/widgets/parametres/pages_jarvis_touch.dart';
import 'package:ia_jarvis/widgets/parametres/panneau_general.dart';

/// Contraste WCAG entre deux couleurs opaques.
double contraste(Color a, Color b) {
  double lum(Color c) {
    double canal(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
  }

  final la = lum(a), lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Iterable<(StyleVisuel, Brightness, PaletteJarvis)> toutesLesPalettes() sync* {
  for (final s in StyleVisuel.values) {
    for (final b in Brightness.values) {
      yield (s, b, s.palette(b));
    }
  }
}

void main() {
  tearDown(() => PaletteJarvis.active = PaletteJarvis.jarvisClair);

  group('Préférences (enregistrement, migration)', () {
    test('par défaut : JARVIS original, clair, Aurore, 50 %', () {
      const p = PreferencesApparence.parDefaut;
      expect(p.style, StyleVisuel.jarvis);
      expect(p.mode, ModeAffichage.clair);
      expect(p.motif, MotifJarvis.aurore);
      expect(p.intensite, 0.5);
    });

    test('aller-retour JSON', () {
      const p = PreferencesApparence(
        mode: ModeAffichage.systeme,
        style: StyleVisuel.sape,
        motif: MotifJarvis.kubaTissu,
        intensite: 0.35,
      );
      expect(PreferencesApparence.decoder(p.encoder()), p);
    });

    test('valeurs absentes, illisibles ou inconnues : comportement sûr', () {
      expect(
        PreferencesApparence.decoder(null),
        PreferencesApparence.parDefaut,
      );
      expect(
        PreferencesApparence.decoder('{oups'),
        PreferencesApparence.parDefaut,
      );
      expect(
        PreferencesApparence.decoder('[1,2]'),
        PreferencesApparence.parDefaut,
      );
      final p = PreferencesApparence.decoder(
        '{"v":9,"mode":"nuit","style":42,"motif":"kuba9","intensite":"fort"}',
      );
      expect(p, PreferencesApparence.parDefaut);
      final q = PreferencesApparence.decoder(
        '{"style":"leopards","intensite":7}',
      );
      expect(q.style, StyleVisuel.leopards);
      expect(q.intensite, 1.0);
      expect(q.mode, ModeAffichage.clair);
    });
  });

  group('Service', () {
    test('restauré au prochain lancement', () async {
      final stockage = StockageMemoire();
      final a = ServiceApparence(stockage: stockage);
      await a.charger();
      await a.choisirStyle(StyleVisuel.fleuve);
      await a.choisirMode(ModeAffichage.sombre);
      await a.choisirMotif(MotifJarvis.coeurKuba);
      await a.reglerIntensite(0.8);
      a.dispose();

      // « Redémarrage » : nouveau service, même stockage.
      final b = ServiceApparence(stockage: stockage);
      await b.charger();
      expect(b.style, StyleVisuel.fleuve);
      expect(b.mode, ModeAffichage.sombre);
      expect(b.motif, MotifJarvis.coeurKuba);
      expect(b.intensite, 0.8);
      expect(
        identical(
          PaletteJarvis.active,
          StyleVisuel.fleuve.palette(Brightness.dark),
        ),
        isTrue,
      );
      b.dispose();
    });

    test(
      'utilisateur existant (rien d’enregistré) : apparence d’origine',
      () async {
        final a = ServiceApparence(stockage: StockageMemoire());
        await a.charger();
        expect(identical(a.palette, PaletteJarvis.jarvisClair), isTrue);
        expect(
          identical(PaletteJarvis.active, PaletteJarvis.jarvisClair),
          isTrue,
        );
        a.dispose();
      },
    );

    test('mode Système : suit la luminosité de l’appareil', () async {
      final a = ServiceApparence(
        stockage: StockageMemoire(),
        luminositeSysteme: Brightness.light,
      );
      await a.charger();
      await a.choisirStyle(StyleVisuel.rumba);
      await a.choisirMode(ModeAffichage.systeme);
      expect(a.luminosite, Brightness.light);
      final v = a.versionPalette;
      a.luminositeSysteme = Brightness.dark;
      expect(a.luminosite, Brightness.dark);
      expect(a.palette.sombre, isTrue);
      expect(a.versionPalette, v + 1);
      // En mode Clair, le système n'a plus d'effet.
      await a.choisirMode(ModeAffichage.clair);
      a.luminositeSysteme = Brightness.light;
      a.luminositeSysteme = Brightness.dark;
      expect(a.palette.sombre, isFalse);
      a.dispose();
    });

    test(
      'thème et motif indépendants ; le motif ne change pas la palette',
      () async {
        final a = ServiceApparence(stockage: StockageMemoire());
        await a.charger();
        await a.choisirStyle(StyleVisuel.sape);
        final v = a.versionPalette;
        final palette = a.palette;
        await a.choisirMotif(MotifJarvis.kubaFrises);
        expect(a.versionPalette, v);
        expect(identical(a.palette, palette), isTrue);
        expect(a.style, StyleVisuel.sape);
        a.dispose();
      },
    );

    test('stockage en panne : aucune erreur, choix appliqué', () async {
      final a = ServiceApparence(stockage: _StockageEnPanne());
      await a.charger();
      await a.choisirStyle(StyleVisuel.congotronics);
      expect(a.style, StyleVisuel.congotronics);
      a.dispose();
    });
  });

  group('Registre des styles', () {
    test('JARVIS original clair : exactement les couleurs d’origine', () {
      final p = StyleVisuel.jarvis.palette(Brightness.light);
      expect(p.ivoire, const Color(0xFFFAF8F2));
      expect(p.signal, const Color(0xFF5559B8));
      expect(p.texte, const Color(0xFF272932));
      expect(p.texteSecondaire, const Color(0xFF6F6A72));
      expect(p.coque, const Color(0xFFFFFDF9));
      expect(p.trait, const Color(0xFFDCD3C4));
      expect(p.identite.marquee, isFalse);
      expect(p.identite.frise, isNull);
      expect(p.identite.policeAffichage, 'Exo2');
    });

    test('variantes source : jetons exacts de l’application fournie', () {
      final congo = StyleVisuel.congotronics.palette(Brightness.dark);
      expect(congo.ivoire, const Color(0xFF070A12));
      expect(congo.signal, const Color(0xFFF4B400));
      expect(congo.violet, const Color(0xFF22C3BC));
      final kuba = StyleVisuel.raphiaKuba.palette(Brightness.light);
      expect(kuba.ivoire, const Color(0xFFEFE3C8));
      expect(kuba.signal, const Color(0xFFA8321F));
      expect(kuba.motif, const Color(0xFF23170F));
      final leo = StyleVisuel.leopards.palette(Brightness.dark);
      expect(leo.ivoire, const Color(0xFF072C6B));
      expect(leo.signal, const Color(0xFFF7D618));
      for (final s in StyleVisuel.values.skip(1)) {
        final source = s.palette(s.varianteSource!);
        expect(source.identite.frise, isNotNull, reason: s.nom);
        expect(source.identite.contour, 2, reason: s.nom);
        expect(source.identite.policeAffichage, 'Baloo2', reason: s.nom);
      }
    });

    test('chaque style a une variante claire ET sombre cohérentes', () {
      for (final s in StyleVisuel.values) {
        expect(s.palette(Brightness.light).sombre, isFalse, reason: s.nom);
        expect(s.palette(Brightness.dark).sombre, isTrue, reason: s.nom);
        // Les accents décoratifs (frise) sont ceux du style dans les deux.
        expect(
          s.palette(Brightness.light).identite.ombreCarte,
          s.palette(Brightness.dark).identite.ombreCarte,
          reason: s.nom,
        );
      }
    });

    test('contrastes : texte, texte secondaire, boutons, accent', () {
      for (final (s, b, p) in toutesLesPalettes()) {
        final nom = '${s.nom} ${b.name}';
        expect(
          contraste(p.texte, p.ivoire),
          greaterThanOrEqualTo(7),
          reason: nom,
        );
        expect(
          contraste(p.texte, p.coque),
          greaterThanOrEqualTo(7),
          reason: nom,
        );
        expect(
          contraste(p.texteSecondaire, p.ivoire),
          greaterThanOrEqualTo(4.5),
          reason: nom,
        );
        expect(
          contraste(p.surSignal, p.signal),
          greaterThanOrEqualTo(4.5),
          reason: nom,
        );
        expect(
          contraste(p.signal, p.ivoire),
          greaterThanOrEqualTo(3),
          reason: nom,
        );
        expect(
          contraste(p.signal, p.coque),
          greaterThanOrEqualTo(3),
          reason: nom,
        );
      }
    });

    test('thème Flutter : luminosité, extension et police du style', () {
      final t = themeJarvis(StyleVisuel.sape.palette(Brightness.dark));
      expect(t.brightness, Brightness.dark);
      expect(t.extension<PaletteJarvis>()!.signal, const Color(0xFFF2A7C3));
      expect(t.textTheme.displaySmall!.fontFamily, 'Baloo2');
    });
  });

  group('Motifs', () {
    Future<List<int>> rendu(MotifJarvis m, PaletteJarvis p) async {
      final r = ui.PictureRecorder();
      final c = Canvas(r);
      peindreFondAccueil(
        c,
        const Size(240, 240),
        palette: p,
        motif: m,
        intensite: 1,
        simplifie: true,
      );
      final image = await r.endRecording().toImage(240, 240);
      final octets = await image.toByteData();
      image.dispose();
      return octets!.buffer.asUint8List();
    }

    test('chaque motif a son propre dessin (pas un motif recoloré)', () async {
      final p = StyleVisuel.raphiaKuba.palette(Brightness.light);
      final images = {for (final m in MotifJarvis.values) m: await rendu(m, p)};
      final liste = MotifJarvis.values;
      for (var i = 0; i < liste.length; i++) {
        for (var j = i + 1; j < liste.length; j++) {
          expect(
            _egales(images[liste[i]]!, images[liste[j]]!),
            isFalse,
            reason: '${liste[i].nom} / ${liste[j].nom}',
          );
        }
      }
    });

    test('intensité 0 : rien du motif ; inconnu → Aurore', () async {
      final p = PaletteJarvis.jarvisSombre;
      final r = ui.PictureRecorder();
      dessinerMotifGeometrique(
        Canvas(r),
        const Rect.fromLTWH(0, 0, 50, 50),
        MotifJarvis.kubaLosanges,
        p,
        0,
      );
      r.endRecording().dispose();
      expect(MotifJarvis.depuisNom('n’existe pas'), MotifJarvis.aurore);
      expect(StyleVisuel.depuisNom(null), StyleVisuel.jarvis);
    });
  });

  group('Paramètres › Général › Apparence', () {
    Future<ServiceApparence> ouvrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final a = ServiceApparence(stockage: StockageMemoire());
      await a.charger();
      PageGenerale? page;
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: a,
          builder: (context, _) => MaterialApp(
            theme: themeJarvis(a.palette),
            builder: (context, enfant) => PorteeApparence(
              service: a,
              child: TransitionApparence(service: a, child: enfant!),
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: PanneauGeneral(
                    page: page,
                    surPage: (p) => setState(() => page = p),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return a;
    }

    testWidgets('Apparence → Thèmes : style et mode appliqués aussitôt, '
        '« Revenir au précédent »', (tester) async {
      final a = await ouvrir(tester);
      expect(find.text('Apparence'), findsOneWidget);
      await tester.tap(find.text('Apparence'));
      await tester.pumpAndSettle();
      expect(find.text('Thèmes'), findsOneWidget);
      expect(find.text('Motifs'), findsOneWidget);
      await tester.tap(find.text('Thèmes'));
      await tester.pumpAndSettle();

      for (final s in StyleVisuel.values) {
        expect(find.text(s.nom), findsOneWidget);
      }
      await tester.tap(find.text('La Sape'));
      await tester.pumpAndSettle();
      expect(a.style, StyleVisuel.sape);
      expect(
        CouleursJarvis.signal,
        StyleVisuel.sape.palette(Brightness.light).signal,
      );

      await tester.tap(find.text('Sombre'));
      await tester.pumpAndSettle();
      expect(a.mode, ModeAffichage.sombre);
      expect(PaletteJarvis.active.ivoire, const Color(0xFF1A0F1F));
      final fond = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(fond.theme!.brightness, Brightness.dark);

      await tester.tap(find.text('Revenir au précédent'));
      await tester.pumpAndSettle();
      expect(a.style, StyleVisuel.jarvis);
      expect(a.mode, ModeAffichage.clair);
      expect(
        identical(PaletteJarvis.active, PaletteJarvis.jarvisClair),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Motifs : choix, intensité, sans motif', (tester) async {
      final a = await ouvrir(tester);
      await tester.tap(find.text('Apparence'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Motifs'));
      await tester.pumpAndSettle();
      for (final m in MotifJarvis.values) {
        expect(find.text(m.nom), findsOneWidget);
      }
      await tester.tap(find.text('Kuba 2 · Tissu'));
      await tester.pumpAndSettle();
      expect(a.motif, MotifJarvis.kubaTissu);
      expect(find.text('Intensité du motif'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(a.intensite, lessThan(0.5));

      await tester.tap(find.text('Sans motif'));
      await tester.pumpAndSettle();
      expect(a.motif, MotifJarvis.aucun);
      expect(find.text('Intensité du motif'), findsNothing);
      // Le motif n'a pas touché au style.
      expect(a.style, StyleVisuel.jarvis);
      expect(tester.takeException(), isNull);
    });
  });
}

bool _egales(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _StockageEnPanne implements StockageReglages {
  @override
  Future<String?> lire() async => throw StateError('lecture');
  @override
  Future<void> ecrire(String valeur) async => throw StateError('écriture');
}
