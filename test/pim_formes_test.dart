// Formes secondaires de PIM : cube (inchangé), tétraèdre, réacteur
// énergétique. Tirage, durées, interruptions, géométries, retour à la
// sphère.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/widgets/pim_dynamique.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

Widget _scene(PimController pim, GlobalKey centre) => MaterialApp(
  home: Stack(
    children: [
      Positioned.fill(
        child: PimParticle(controleur: pim, cleCentre: centre),
      ),
      Center(child: SizedBox.square(key: centre, dimension: 400)),
    ],
  ),
);

/// Avance le cycle de [s] secondes au repos.
void _repos(FormesPim f, double s, {bool calme = true}) {
  for (var i = 0; i < (s * 60).round(); i++) {
    f.avancer(1 / 60, calme: calme);
  }
}

void main() {
  group('Tirage des formes', () {
    test('bornes : 50 % cube, 35 % tétraèdre, 15 % réacteur', () {
      expect(FormePim.tirer(0), FormePim.cube);
      expect(FormePim.tirer(0.499), FormePim.cube);
      expect(FormePim.tirer(0.5), FormePim.tetraedre);
      expect(FormePim.tirer(0.849), FormePim.tetraedre);
      expect(FormePim.tirer(0.85), FormePim.reacteur);
      expect(FormePim.tirer(0.9999), FormePim.reacteur);
      // Sans la sphère (forme principale par défaut), les poids d'origine.
      expect(
        FormePim.values
            .where((f) => f != FormePim.sphere)
            .fold(0, (s, f) => s + f.poids),
        100,
      );
    });

    test('répartition sur 20 000 tirages', () {
      final h = math.Random(3);
      final compte = {for (final f in FormePim.values) f: 0};
      for (var i = 0; i < 20000; i++) {
        compte.update(FormePim.tirer(h.nextDouble()), (c) => c + 1);
      }
      expect(compte[FormePim.cube]! / 20000, closeTo(0.50, 0.015));
      expect(compte[FormePim.tetraedre]! / 20000, closeTo(0.35, 0.015));
      expect(compte[FormePim.reacteur]! / 20000, closeTo(0.15, 0.015));
    });

    test('rareté conservée : jamais avant 30 s de repos, 3 min entre deux '
        'formes, les trois formes apparaissent', () {
      final f = FormesPim(5);
      _repos(f, 29);
      expect(f.phase, PhaseForme.absent);
      final vues = <FormePim>[];
      var debut = -1e9;
      var precedent = PhaseForme.absent;
      // Six heures de repos simulées (10 images/s).
      for (var i = 0; i < 6 * 3600 * 10; i++) {
        f.avancer(0.1, calme: true);
        final t = i * 0.1;
        if (precedent == PhaseForme.absent && f.phase != PhaseForme.absent) {
          // Au moins 3 min depuis le début de la forme précédente.
          expect(t - debut, greaterThan(180));
          debut = t;
          vues.add(f.forme);
        }
        precedent = f.phase;
      }
      // Rare : de l'ordre d'une forme toutes les 4 à 5 minutes au plus.
      expect(vues.length, inInclusiveRange(40, 110));
      // Les trois formes secondaires, jamais la forme principale (sphère).
      expect(vues.toSet(), {
        FormePim.cube,
        FormePim.tetraedre,
        FormePim.reacteur,
      });
      expect(
        vues.where((v) => v == FormePim.reacteur).length,
        lessThan(vues.where((v) => v == FormePim.cube).length),
      );
    });
  });

  group('Durées et interruptions', () {
    test('tétraèdre : 0,8 s + 2,4 s, tenu 5 s, retour 2,6 s', () {
      final f = FormesPim()..declencher(FormePim.tetraedre);
      _repos(f, 0.75);
      expect(f.phase, PhaseForme.preparation);
      _repos(f, 0.1);
      expect(f.phase, PhaseForme.formation);
      _repos(f, 2.45);
      expect(f.phase, PhaseForme.tenue);
      expect(f.progres, 1);
      _repos(f, 4.9);
      expect(f.phase, PhaseForme.tenue);
      _repos(f, 0.2);
      expect(f.phase, PhaseForme.retour);
      // (Le retour a commencé il y a 0,1 s.)
      _repos(f, 2.4);
      expect(f.phase, PhaseForme.retour);
      _repos(f, 0.2);
      expect(f.phase, PhaseForme.absent);
      expect(f.progres, 0);
    });

    test('réacteur : mêmes durées que le tétraèdre', () {
      final f = FormesPim()..declencher(FormePim.reacteur);
      _repos(f, 0.8 + 2.4 + 0.1);
      expect(f.phase, PhaseForme.tenue);
      _repos(f, 5.0);
      expect(f.phase, PhaseForme.retour);
      _repos(f, 2.7);
      expect(f.phase, PhaseForme.absent);
    });

    test('cube : durées d’origine inchangées (1 + 3, 5,5, 3,2 s)', () {
      final f = FormesPim()..declencher(FormePim.cube);
      _repos(f, 3.9);
      expect(f.phase, PhaseForme.formation);
      _repos(f, 0.2);
      expect(f.phase, PhaseForme.tenue);
      _repos(f, 5.4);
      expect(f.phase, PhaseForme.tenue);
      _repos(f, 0.2);
      expect(f.phase, PhaseForme.retour);
      _repos(f, 3.3);
      expect(f.phase, PhaseForme.absent);
    });

    for (final (nom, apres) in [
      ('pendant la formation', 1.5),
      ('pendant le maintien', 5.0),
      ('pendant le retour', 9.5),
    ]) {
      test('interruption $nom : retour à la sphère en 0,9 s', () {
        for (final forme in FormePim.values) {
          final f = FormesPim()..declencher(forme);
          _repos(f, apres);
          expect(f.phase, isNot(PhaseForme.absent), reason: '$forme');
          final progres = f.progres;
          // Une interaction : retour accéléré, sans saut (progrès continu).
          f.avancer(1 / 60, calme: false);
          expect(f.phase, PhaseForme.retour, reason: '$forme');
          expect(f.progres, closeTo(progres, 0.03), reason: '$forme');
          _repos(f, 0.92, calme: false);
          expect(f.phase, PhaseForme.absent, reason: '$forme');
        }
      });
    }
  });

  group('Géométries', () {
    Future<PimController> former(WidgetTester tester, FormePim forme) async {
      final pim = PimController();
      final centre = GlobalKey();
      await tester.pumpWidget(_scene(pim, centre));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      pim.declencherForme(forme);
      // Préparation + formation + 1 s de maintien.
      for (var i = 0; i < 60 * 4.2; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      return pim;
    }

    testWidgets('tétraèdre : 4 sommets, 6 arêtes, 4 faces', (tester) async {
      final pim = await former(tester, FormePim.tetraedre);
      expect(pim.mode, ParticlePimMode.tetraedre);
      expect(pim.phaseForme, PhaseForme.tenue);
      final c = pim.ciblesForme;
      final n = c.x.length;
      // Sommets du tétraèdre régulier (rayon 1,1, un sommet en haut).
      const r = 1.1;
      final h = r * 2 * math.sqrt(2) / 3;
      final sommets = [
        [0.0, r, 0.0],
        for (var k = 0; k < 3; k++)
          [
            h * math.cos(math.pi / 2 + k * 2 * math.pi / 3),
            -r / 3,
            h * math.sin(math.pi / 2 + k * 2 * math.pi / 3),
          ],
      ];
      double distance(List<double> a, double x, double y, double z) =>
          math.sqrt(
            (a[0] - x) * (a[0] - x) +
                (a[1] - y) * (a[1] - y) +
                (a[2] - z) * (a[2] - z),
          );
      // Distance d'un point au segment [a, b].
      double segment(
        List<double> a,
        List<double> b,
        double x,
        double y,
        double z,
      ) {
        final ex = b[0] - a[0], ey = b[1] - a[1], ez = b[2] - a[2];
        final t =
            (((x - a[0]) * ex + (y - a[1]) * ey + (z - a[2]) * ez) /
                    (ex * ex + ey * ey + ez * ez))
                .clamp(0.0, 1.0);
        final px = a[0] + ex * t, py = a[1] + ey * t, pz = a[2] + ez * t;
        return math.sqrt(
          (x - px) * (x - px) + (y - py) * (y - py) + (z - pz) * (z - pz),
        );
      }

      var surArete = 0;
      final parSommet = List.filled(4, 0);
      final parArete = List.filled(6, 0);
      final parFace = List.filled(4, 0);
      for (var i = 0; i < n; i++) {
        final x = c.x[i], y = c.y[i], z = c.z[i];
        // Chaque point est sur une face (plan à r / 3 du centre).
        var face = 0;
        var meilleur = -1e9;
        for (var k = 0; k < 4; k++) {
          final d =
              -(x * sommets[k][0] + y * sommets[k][1] + z * sommets[k][2]) / r;
          if (d > meilleur) {
            meilleur = d;
            face = k;
          }
        }
        // (Les nœuds des sommets débordent de quelques centièmes.)
        expect(meilleur, closeTo(r / 3, 0.05));
        parFace[face]++;
        for (var k = 0; k < 4; k++) {
          if (distance(sommets[k], x, y, z) < 0.12) parSommet[k]++;
        }
        var a = 0;
        var proche = false;
        for (var p = 0; p < 4; p++) {
          for (var q = p + 1; q < 4; q++) {
            if (segment(sommets[p], sommets[q], x, y, z) < 0.03) {
              parArete[a]++;
              proche = true;
            }
            a++;
          }
        }
        if (proche) surArete++;
      }
      // Les 4 sommets, les 6 arêtes et les 4 faces sont occupés.
      expect(parSommet.every((v) => v > 10), isTrue, reason: '$parSommet');
      expect(parArete.every((v) => v > 60), isTrue, reason: '$parArete');
      expect(parFace.every((v) => v > n / 8), isTrue, reason: '$parFace');
      // Arêtes plus denses que les faces, sans que les faces disparaissent.
      expect(surArete / n, inInclusiveRange(0.3, 0.8));
      // Sans éparpillement.
      expect(pim.etalement.maximum, lessThan(1.4));
    });

    testWidgets('tétraèdre : rotation lente pendant le maintien', (
      tester,
    ) async {
      final pim = await former(tester, FormePim.tetraedre);
      final avant = pim.etalement;
      for (var i = 0; i < 60 * 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(pim.mode, ParticlePimMode.tetraedre);
        // La forme reste nette pendant qu'elle tourne.
        expect(pim.etalement.maximum, lessThan(1.4));
      }
      expect(pim.etalement.moyenne, closeTo(avant.moyenne, 0.08));
    });

    testWidgets('réacteur : anneau, triangle pointe en bas, noyau dense', (
      tester,
    ) async {
      final pim = await former(tester, FormePim.reacteur);
      expect(pim.mode, ParticlePimMode.reacteur);
      final c = pim.ciblesForme;
      final n = c.x.length;
      var anneau = 0, noyau = 0, triangle = 0, bas = 0;
      for (var i = 0; i < n; i++) {
        final x = c.x[i], y = c.y[i];
        final r = math.sqrt(x * x + y * y);
        // Forme plate, avec un peu de profondeur seulement.
        expect(c.z[i].abs(), lessThan(0.3));
        expect(r, lessThan(1.25));
        if (r >= 0.9 && r <= 1.01) anneau++;
        if (r < 0.2) noyau++;
        // Côtés du triangle (sommets à 30°, 150°, 270°) : à la distance de
        // l'apothème du centre selon la normale de chaque côté.
        for (final normale in [90.0, 210.0, 330.0]) {
          final a = normale * math.pi / 180;
          final d = x * math.cos(a) + y * math.sin(a);
          if ((d - 0.44).abs() < 0.01 || (d - 0.395).abs() < 0.01) {
            triangle++;
            break;
          }
        }
        if (y < -0.85 && x.abs() < 0.1) bas++;
      }
      expect(anneau / n, greaterThan(0.3));
      expect(triangle / n, greaterThan(0.2));
      expect(noyau / n, greaterThan(0.1));
      // Pointe du triangle en bas (sommet à 270°).
      expect(bas, greaterThan(20));
      // Formation dans l'ordre : anneau d'abord, noyau en dernier.
      for (var i = 0; i < n; i++) {
        final r = math.sqrt(c.x[i] * c.x[i] + c.y[i] * c.y[i]);
        if (r < 0.2) expect(c.ordre[i], 1);
      }
      expect(pim.etalement.maximum, lessThan(1.4));
    });

    for (final forme in [FormePim.tetraedre, FormePim.reacteur]) {
      testWidgets('$forme → sphère : retour complet, sans éparpillement', (
        tester,
      ) async {
        final pim = await former(tester, forme);
        for (var i = 0; i < 60 * 9; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(pim.etalement.maximum, lessThan(1.45));
        }
        expect(pim.phaseForme, PhaseForme.absent);
        expect(pim.mode, ParticlePimMode.idle);
        expect(pim.etalement.maximum, lessThan(1.1));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('interactions : focus du champ et mode vocal interrompent', (
      tester,
    ) async {
      final pim = await former(tester, FormePim.reacteur);
      pim.saisieFocus = true;
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(pim.phaseForme, PhaseForme.absent);
      // Tant que le focus reste, aucune forme ne commence.
      pim.declencherForme(FormePim.tetraedre);
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(pim.phaseForme, PhaseForme.absent);
      pim.saisieFocus = false;

      // Écoute vocale pendant le maintien d'un tétraèdre.
      pim.declencherForme(FormePim.tetraedre);
      for (var i = 0; i < 60 * 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(pim.phaseForme, PhaseForme.tenue);
      pim.etatVocal = VoiceState.listening;
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(pim.phaseForme, PhaseForme.absent);
      expect(pim.mode, ParticlePimMode.listening);
      expect(pim.etalement.maximum, lessThan(1.4));
      expect(tester.takeException(), isNull);
    });
  });
}
