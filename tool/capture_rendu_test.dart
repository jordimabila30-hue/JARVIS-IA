// Non-régression visuelle du moteur graphique (fond + particules PIM).
//
//   CAPTURE_DIR=chemin flutter test tool/capture_rendu_test.dart
//
// Rend des images déterministes (horloge de test fixe) de chaque état, en
// format ordinateur et téléphone, et les écrit en PNG et en RGBA brut dans
// CAPTURE_DIR. On compare ensuite deux séries (avant / après une
// optimisation) pixel par pixel.
//
// PRINCIPALE=cube|tetraedre|reacteur : même série avec cette forme
// principale (fichiers suffixés), pour vérifier ses réactions vocales.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/signal_vocal.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/widgets/fond_jarvis_anime.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

void main() {
  final dossier = Platform.environment['CAPTURE_DIR'];
  final principale = FormePim.values
      .asNameMap()[Platform.environment['PRINCIPALE']];

  const formats = {
    'ordi': (Size(1280, 800), 1.5, 520.0),
    'tel': (Size(390, 844), 2.0, 300.0),
  };
  const etats = [
    'repos',
    'frappe',
    'ecoute',
    'reflexion',
    'parole',
    'cube',
    'tetraedre',
    'reacteur',
  ];

  for (final format in formats.entries) {
    for (final etat in etats) {
      testWidgets('capture ${format.key} $etat', (tester) async {
        final (taille, densite, zone) = format.value;
        tester.view.physicalSize = taille * densite;
        tester.view.devicePixelRatio = densite;
        addTearDown(tester.view.reset);

        final pim = PimController();
        if (principale != null) {
          pim.definirFormePrincipale(principale, immediat: true);
        }
        final amplitude = ValueNotifier<double>(0);
        final signal = SignalVocal();
        pim
          ..amplitude = amplitude
          ..signal = signal;
        final cleCentre = GlobalKey();
        final cleChamp = GlobalKey();
        final cleImage = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: cleImage,
              child: FondJarvisAnime(
                zoneParticules: pim.zone,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: PimParticle(
                        controleur: pim,
                        cleCentre: cleCentre,
                        cleChamp: cleChamp,
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0, -0.25),
                      child: SizedBox.square(key: cleCentre, dimension: zone),
                    ),
                    Align(
                      alignment: const Alignment(0, 0.86),
                      child: SizedBox(
                        key: cleChamp,
                        width: taille.width * 0.8,
                        height: 56,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        switch (etat) {
          case 'frappe':
            pim.surTexte('Bonjour JARVIS');
          case 'ecoute':
            pim.etatVocal = VoiceState.listening;
          case 'reflexion':
            pim.etatVocal = VoiceState.thinking;
          case 'parole':
            pim.etatVocal = VoiceState.speaking;
          case 'cube':
            pim.declencherCube();
          case 'tetraedre':
            pim.declencherForme(FormePim.tetraedre);
          case 'reacteur':
            pim.declencherForme(FormePim.reacteur);
        }
        // 3 s à 60 images/s (5 s pour le cube, tenu à mi-formation ;
        // 6,2 s pour le tétraèdre et le réacteur, au milieu du maintien).
        final images = switch (etat) {
          'cube' => 300,
          'tetraedre' || 'reacteur' => 372,
          _ => 180,
        };
        for (var i = 0; i < images; i++) {
          if (etat == 'ecoute') {
            amplitude.value = i % 12 < 6 ? 0.8 : 0.3;
            signal.bandes(0.6, 0.4, 0.3);
          }
          if (etat == 'parole' && i % 9 == 0) {
            signal.mot(0.7, duree: 0.25, syllabes: 2);
            amplitude.value = 0.6;
          }
          await tester.pump(const Duration(microseconds: 16667));
        }

        if (dossier == null) return;
        final objet =
            cleImage.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await objet.toImage(pixelRatio: densite);
          final brut = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final nom = principale == null
              ? '$dossier/${format.key}_$etat'
              : '$dossier/${format.key}_${principale.name}_$etat';
          File(
            '$nom.rgba',
          ).writeAsBytesSync(brut!.buffer.asUint8List(), flush: true);
          File('$nom.png').writeAsBytesSync(png!.buffer.asUint8List());
          File(
            '$nom.taille',
          ).writeAsStringSync('${image.width}x${image.height}');
          image.dispose();
        });
      });
    }
  }
}
