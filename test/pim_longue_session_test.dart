import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

void main() {
  testWidgets('longue session vocale : la sphère reste groupée et revient', (
    tester,
  ) async {
    final pim = PimController();
    final amplitude = ValueNotifier<double>(0);
    pim.amplitude = amplitude;
    final centre = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: PimParticle(controleur: pim, cleCentre: centre),
            ),
            Center(child: SizedBox.square(key: centre, dimension: 500)),
          ],
        ),
      ),
    );

    // Environ 2 minutes simulées : écoute, réflexion, parole en boucle.
    final etats = [
      VoiceState.listening,
      VoiceState.thinking,
      VoiceState.speaking,
    ];
    var pire = 0.0;
    for (var cycle = 0; cycle < 40; cycle++) {
      pim.etatVocal = etats[cycle % 3];
      for (var i = 0; i < 30; i++) {
        amplitude.value = (i * 7 % 10) / 10;
        await tester.pump(const Duration(milliseconds: 100));
      }
      final e = pim.etalement.maximum;
      if (e > pire) pire = e;
    }
    debugPrint('étalement maximal pendant la session : $pire');
    expect(pire, lessThan(1.45));

    // Fin du vocal : la sphère se reforme.
    pim.etatVocal = null;
    amplitude.value = 0;
    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugPrint('après retour : ${pim.etalement}');
    expect(pim.etalement.maximum, lessThan(1.1));
    amplitude.dispose();
  });
}
