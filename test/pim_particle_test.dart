import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

/// Zone centrale en haut, champ texte en bas, calque de particules derrière.
Widget _scene(PimController pim, GlobalKey centre, GlobalKey champ) {
  return MaterialApp(
    home: Stack(
      children: [
        Positioned.fill(
          child: PimParticle(
            controleur: pim,
            cleCentre: centre,
            cleChamp: champ,
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 40),
            SizedBox.square(key: centre, dimension: 300),
            const Spacer(),
            SizedBox(key: champ, width: 500, height: 56),
            const SizedBox(height: 20),
          ],
        ),
      ],
    ),
  );
}

Future<void> _attendre(WidgetTester tester, double secondes) async {
  for (var i = 0; i < (secondes * 60).round(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  late PimController pim;
  final centre = GlobalKey(), champ = GlobalKey();

  setUp(() => pim = PimController());

  testWidgets('scénarios du mode écrit', (tester) async {
    await tester.pumpWidget(_scene(pim, centre, champ));

    // Test 1 : rien ne se passe, les particules restent au centre.
    await _attendre(tester, 1);
    expect(pim.mode, ParticlePimMode.idle);

    // Test 2 : première lettre → départ vers le champ.
    pim.surTexte('B');
    await _attendre(tester, 0.3);
    expect(pim.mode, ParticlePimMode.movingToInput);
    await _attendre(tester, 1);

    // Test 3 : l'utilisateur continue d'écrire.
    pim.surTexte('Bonjour');
    await _attendre(tester, 0.2);
    expect(pim.mode, ParticlePimMode.inputActive);

    // Test 4 : il s'arrête, les particules se calment mais restent.
    await _attendre(tester, 2);
    expect(pim.mode, ParticlePimMode.inputCalm);

    // Test 5 : envoi → impulsion, puis toujours autour du champ.
    pim.surEnvoi();
    await _attendre(tester, 0.1);
    expect(pim.mode, ParticlePimMode.sending);
    await _attendre(tester, 1);
    expect(pim.mode, ParticlePimMode.inputCalm);

    // Test 6 : texte effacé, 3 s plus tard retour au centre.
    pim.surTexte('');
    await _attendre(tester, 2.5);
    expect(pim.mode, isNot(ParticlePimMode.movingToCenter));
    await _attendre(tester, 0.8);
    expect(pim.mode, ParticlePimMode.movingToCenter);

    // Test 7 : on réécrit pendant le retour → demi-tour vers le champ.
    pim.surTexte('A');
    await _attendre(tester, 0.1);
    expect(pim.mode, ParticlePimMode.movingToInput);
    await _attendre(tester, 1.2);
    expect(pim.mode, ParticlePimMode.inputActive);

    // Retour complet au centre.
    pim.surTexte('');
    await _attendre(tester, 4.5);
    expect(pim.mode, ParticlePimMode.idle);
    expect(tester.takeException(), isNull);
  });

  testWidgets('les états vocaux s’animent sans erreur', (tester) async {
    final amplitude = ValueNotifier<double>(0);
    pim.amplitude = amplitude;
    await tester.pumpWidget(_scene(pim, centre, champ));
    for (final etat in [
      VoiceState.listening,
      VoiceState.thinking,
      VoiceState.speaking,
    ]) {
      pim.etatVocal = etat;
      for (var i = 0; i < 40; i++) {
        amplitude.value = (i % 10) / 10;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(pim.mode.name, etat.name);
    }
    expect(tester.takeException(), isNull);
    amplitude.dispose();
  });
}
