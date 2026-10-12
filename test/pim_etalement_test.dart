import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

void main() {
  testWidgets(
    'particules groupées en mode vocal, même avec des images lentes',
    (tester) async {
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
      Future<void> attendre(double s, {int ms = 16}) async {
        for (var i = 0; i < (s * 1000 / ms).round(); i++) {
          await tester.pump(Duration(milliseconds: ms));
        }
      }

      await attendre(2);
      pim.etatVocal = VoiceState.listening;
      for (var i = 0; i < 120; i++) {
        amplitude.value = i.isEven ? 1 : 0.2;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(pim.etalement.maximum, lessThan(1.4));
      pim.etatVocal = VoiceState.thinking;
      await attendre(1);
      pim.etatVocal = VoiceState.speaking;
      for (var i = 0; i < 40; i++) {
        amplitude.value = i % 3 == 0 ? 1 : amplitude.value;
        // Images lentes, comme un navigateur occupé par la synthèse vocale.
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(pim.etalement.maximum, lessThan(1.4));
      pim.etatVocal = null;
      amplitude.value = 0;
      await attendre(2);
      expect(pim.etalement.maximum, lessThan(1.1));
      await attendre(2, ms: 100);
      expect(pim.etalement.maximum, lessThan(1.1));
      amplitude.dispose();
    },
  );
}
