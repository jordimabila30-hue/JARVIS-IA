import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/signal_vocal.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/services/prosodie.dart';
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

void main() {
  group('Mémoire courte', () {
    test('après un pic, l’énergie retombe doucement', () {
      final m = MemoireEnergie();
      for (var i = 0; i < 10; i++) {
        m.avancer(1 / 60, 1, null);
      }
      final pic = m.memoire;
      // La voix s'arrête net : l'instant chute vite, la mémoire garde de
      // l'élan.
      for (var i = 0; i < 15; i++) {
        m.avancer(1 / 60, 0, null);
      }
      expect(m.instant, lessThan(0.4));
      expect(m.memoire, greaterThan(pic * 0.6));
      // Puis tout revient au calme.
      for (var i = 0; i < 400; i++) {
        m.avancer(1 / 60, 0, null);
      }
      expect(m.energie, lessThan(0.02));
    });

    test('bandes mesurées utilisées quand elles existent', () {
      final m = MemoireEnergie();
      final s = SignalVocal()..bandes(1, 0, 0);
      for (var i = 0; i < 60; i++) {
        m.avancer(1 / 60, 0.5, s);
      }
      expect(m.graves, greaterThan(0.9));
      expect(m.aigus, lessThan(0.05));
    });
  });

  group('Ondes', () {
    test('émission : du centre vers le bord ; réception : l’inverse', () {
      final o = OndesPim()..lancer(0, 1, emission: true);
      o.preparer(0.03);
      expect(o.valeur(0.1, 1, 1), greaterThan(o.valeur(0.9, 1, 1)));
      final r = OndesPim()..lancer(0, 1, emission: false);
      r.preparer(0.03);
      // Négative (vers l'intérieur), d'abord au bord.
      expect(r.valeur(0.95, 1, 1), lessThan(r.valeur(0.2, 1, 1)));
      expect(r.valeur(0.95, 1, 1), lessThan(0));
    });
  });

  group('Prosodie', () {
    test('accent en fin de groupe, mots outils faibles, pauses', () {
      final p = Prosodie.analyser('Bonjour. Comment puis-je vous aider ?');
      // « puis-je » compte pour un mot.
      expect(p.mots.length, 5);
      final vous = p.mots[3], aider = p.mots[4];
      expect(aider.accent, greaterThan(vous.accent));
      expect(p.mots[0].pauseApres, greaterThan(0.3));
      expect(p.accentA(aider.debut), aider.accent);
    });
  });

  group('Formes secondaires : cycle', () {
    test('apparaît seulement après un vrai repos, puis revient', () {
      final c = FormesPim();
      // Interactions continues : jamais de cube.
      for (var i = 0; i < 60 * 60; i++) {
        c.avancer(1 / 60, calme: false);
      }
      expect(c.phase, PhaseForme.absent);
      // Moins de 30 s de repos : toujours rien.
      for (var i = 0; i < 60 * 28; i++) {
        c.avancer(1 / 60, calme: true);
      }
      expect(c.phase, PhaseForme.absent);
      // Repos prolongé : le cube finit par venir, puis repart seul.
      var vu = false;
      for (var i = 0; i < 60 * 600 && !vu; i++) {
        c.avancer(1 / 60, calme: true);
        vu = c.phase == PhaseForme.tenue;
      }
      expect(vu, isTrue);
      expect(c.progres, 1);
      for (var i = 0; i < 60 * 10; i++) {
        c.avancer(1 / 60, calme: true);
      }
      expect(c.phase, PhaseForme.absent);
      expect(c.progres, 0);
      // Recharge : pas de nouveau cube avant 3 minutes.
      for (var i = 0; i < 60 * 150; i++) {
        c.avancer(1 / 60, calme: true);
        expect(c.phase, PhaseForme.absent);
      }
    });

    test('une interaction rend immédiatement la priorité à la sphère', () {
      final c = FormesPim()..declencher();
      for (var i = 0; i < 60 * 3; i++) {
        c.avancer(1 / 60, calme: true);
      }
      expect(c.progres, greaterThan(0));
      c.avancer(1 / 60, calme: false);
      expect(c.phase, PhaseForme.retour);
      for (var i = 0; i < 60; i++) {
        c.avancer(1 / 60, calme: false);
      }
      expect(c.phase, PhaseForme.absent);
    });
  });

  testWidgets('sphère → cube → sphère, sans éparpillement', (tester) async {
    final pim = PimController();
    final centre = GlobalKey();
    await tester.pumpWidget(_scene(pim, centre));
    Future<void> attendre(double s) async {
      for (var i = 0; i < (s * 60).round(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await attendre(1);
    pim.declencherCube();
    await attendre(5);
    expect(pim.mode, ParticlePimMode.cube);
    // Coins du cube : un peu au-delà du rayon, jamais au loin.
    expect(pim.etalement.maximum, lessThan(1.4));
    await attendre(10);
    expect(pim.phaseForme, PhaseForme.absent);
    expect(pim.mode, ParticlePimMode.idle);
    expect(pim.etalement.maximum, lessThan(1.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('parole de JARVIS : mots et phrase pilotent les ondes', (
    tester,
  ) async {
    final pim = PimController();
    final amplitude = ValueNotifier<double>(0);
    final signal = SignalVocal();
    pim
      ..amplitude = amplitude
      ..signal = signal;
    final centre = GlobalKey();
    await tester.pumpWidget(_scene(pim, centre));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    pim.etatVocal = VoiceState.speaking;
    signal.debutPhrase();
    for (var i = 0; i < 180; i++) {
      if (i % 12 == 0) {
        signal.mot(i % 36 == 0 ? 1 : 0.3);
        amplitude.value = 0.9;
      } else {
        amplitude.value *= 0.9;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pim.etalement.maximum, lessThan(1.4));
    pim.etatVocal = null;
    amplitude.value = 0;
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pim.etalement.maximum, lessThan(1.1));
    expect(tester.takeException(), isNull);
    amplitude.dispose();
  });
}
