// Forme principale de PIM : choix enregistré, appliqué au moteur, réactions
// vocales sur chaque géométrie, transitions, formes secondaires sans la
// forme principale, aperçus.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/services/preferences_pim_service.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
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

Future<void> _attendre(WidgetTester tester, double s) async {
  for (var i = 0; i < (s * 60).round(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Étalement moyen sur [s] secondes.
Future<double> _moyenne(
  WidgetTester tester,
  PimController pim,
  double s,
) async {
  var somme = 0.0;
  final n = (s * 60).round();
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    somme += pim.etalement.moyenne;
  }
  return somme / n;
}

Future<PimController> _pim(WidgetTester tester, FormePim forme) async {
  final pim = PimController()..definirFormePrincipale(forme, immediat: true);
  await tester.pumpWidget(_scene(pim, GlobalKey()));
  await _attendre(tester, 3);
  return pim;
}

void main() {
  group('Préférence', () {
    test('sphère par défaut, choix enregistré puis relu', () async {
      final stockage = StockageMemoire();
      final p = PreferencesPimService(stockage: stockage);
      await p.charger();
      expect(p.forme, FormePim.sphere);
      expect(p.charge, isTrue);
      await p.choisir(FormePim.tetraedre);
      expect(stockage.valeur, 'tetraedre');
      // Au prochain lancement.
      final relue = PreferencesPimService(stockage: stockage);
      await relue.charger();
      expect(relue.forme, FormePim.tetraedre);
      // Valeur inconnue : sphère.
      final inconnue = PreferencesPimService(
        stockage: StockageMemoire('etoile'),
      );
      await inconnue.charger();
      expect(inconnue.forme, FormePim.sphere);
    });

    test('noms affichés', () {
      expect(FormePim.values.map((f) => f.libelle), [
        'Sphère',
        'Cube 3D',
        'Tétraèdre 3D',
        'Réacteur Arc',
      ]);
    });
  });

  group('Formes secondaires sans la forme principale', () {
    for (final principale in FormePim.values) {
      test('principale ${principale.name} : jamais tirée', () {
        final h = math.Random(1);
        final vues = <FormePim>{};
        for (var i = 0; i < 5000; i++) {
          final f = FormePim.tirer(h.nextDouble(), principale: principale);
          expect(f, isNot(principale));
          vues.add(f);
        }
        expect(vues, hasLength(3));
      });
    }

    test('le cycle exclut la forme principale et garde la rareté', () {
      final f = FormesPim(5)..principale = FormePim.tetraedre;
      final vues = <FormePim>[];
      var precedent = PhaseForme.absent;
      var debut = -1e9;
      for (var i = 0; i < 4 * 3600 * 10; i++) {
        f.avancer(0.1, calme: true);
        if (precedent == PhaseForme.absent && f.phase != PhaseForme.absent) {
          expect(i * 0.1 - debut, greaterThan(180));
          debut = i * 0.1;
          vues.add(f.forme);
        }
        precedent = f.phase;
      }
      expect(vues, isNotEmpty);
      expect(vues, isNot(contains(FormePim.tetraedre)));
      expect(vues, contains(FormePim.sphere));
    });
  });

  group('Moteur', () {
    testWidgets('sphère par défaut', (tester) async {
      final pim = PimController();
      await tester.pumpWidget(_scene(pim, GlobalKey()));
      await _attendre(tester, 1);
      expect(pim.formePrincipale, FormePim.sphere);
    });

    for (final forme in [
      FormePim.cube,
      FormePim.tetraedre,
      FormePim.reacteur,
    ]) {
      testWidgets('${forme.name} principal : forme tenue au repos, vivant à '
          'l’écoute, à la réflexion et à la parole', (tester) async {
        final pim = await _pim(tester, forme);
        expect(pim.formePrincipale, forme);
        expect(pim.mode, ParticlePimMode.idle);
        // Silhouette de la forme, sans éparpillement.
        final repos = await _moyenne(tester, pim, 1);
        expect(pim.etalement.maximum, lessThan(1.45));
        if (forme != FormePim.cube) {
          // Les particules visent bien la géométrie préparée.
          final c = pim.ciblesPrincipale;
          var loin = 0;
          for (var i = 0; i < c.x.length; i++) {
            final d = math.sqrt(
              c.x[i] * c.x[i] + c.y[i] * c.y[i] + c.z[i] * c.z[i],
            );
            if (d > 1.3) loin++;
          }
          expect(loin, 0);
        }

        // Écoute : la voix gonfle la forme (bandes du micro).
        final amplitude = ValueNotifier<double>(0);
        pim.amplitude = amplitude;
        pim.etatVocal = VoiceState.listening;
        var somme = 0.0;
        for (var i = 0; i < 120; i++) {
          amplitude.value = i % 10 < 5 ? 1 : 0.6;
          await tester.pump(const Duration(milliseconds: 16));
          if (i >= 60) somme += pim.etalement.moyenne;
        }
        final ecoute = somme / 60;
        expect(ecoute, greaterThan(repos * 1.01));
        expect(pim.etalement.maximum, lessThan(1.6));
        // Réflexion : pulsation intérieure (la forme se resserre).
        pim.etatVocal = VoiceState.thinking;
        amplitude.value = 0;
        await _attendre(tester, 1.5);
        final reflexion = await _moyenne(tester, pim, 1);
        expect(reflexion, lessThan(repos));
        // Parole : la forme vit (émission du centre vers l'extérieur).
        pim.etatVocal = VoiceState.speaking;
        final valeurs = <double>[];
        for (var i = 0; i < 90; i++) {
          amplitude.value = 0.5 + 0.5 * math.sin(i / 3);
          await tester.pump(const Duration(milliseconds: 16));
          valeurs.add(pim.etalement.moyenne);
        }
        final ecart = valeurs.reduce(math.max) - valeurs.reduce(math.min);
        expect(ecart, greaterThan(0.003));
        expect(pim.etalement.maximum, lessThan(1.6));
        // Retour au repos : la forme principale revient.
        pim.etatVocal = null;
        await _attendre(tester, 3);
        expect(await _moyenne(tester, pim, 1), closeTo(repos, 0.05));
        expect(pim.formePrincipale, forme);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('saisie : autour de la barre, puis retour à la forme '
        'principale', (tester) async {
      final pim = PimController()
        ..definirFormePrincipale(FormePim.tetraedre, immediat: true);
      final centre = GlobalKey();
      final champ = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: PimParticle(
                  controleur: pim,
                  cleCentre: centre,
                  cleChamp: champ,
                ),
              ),
              Center(child: SizedBox.square(key: centre, dimension: 400)),
              Positioned(
                left: 200,
                right: 200,
                bottom: 40,
                height: 56,
                child: SizedBox(key: champ),
              ),
            ],
          ),
        ),
      );
      await _attendre(tester, 3);
      final repos = await _moyenne(tester, pim, 1);
      pim.surTexte('Bonjour');
      await _attendre(tester, 2);
      expect(
        pim.mode,
        isIn([ParticlePimMode.inputActive, ParticlePimMode.inputCalm]),
      );
      pim.surTexte('');
      await _attendre(tester, 6);
      expect(pim.mode, ParticlePimMode.idle);
      expect(await _moyenne(tester, pim, 1), closeTo(repos, 0.05));
    });

    testWidgets('changement de forme principale : transition progressive, '
        'forme secondaire interrompue', (tester) async {
      final pim = await _pim(tester, FormePim.sphere);
      pim.declencherForme(FormePim.cube);
      await _attendre(tester, 2);
      expect(pim.phaseForme, isNot(PhaseForme.absent));
      pim.definirFormePrincipale(FormePim.reacteur);
      await tester.pump(const Duration(milliseconds: 16));
      expect(pim.phaseForme, PhaseForme.retour);
      // Aucune explosion pendant la transition, densité continue.
      var precedent = pim.etalement.moyenne;
      for (var i = 0; i < 60 * 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final e = pim.etalement;
        expect(e.maximum, lessThan(1.5), reason: 'image $i');
        expect((e.moyenne - precedent).abs(), lessThan(0.03));
        precedent = e.moyenne;
      }
      expect(pim.phaseForme, PhaseForme.absent);
      expect(pim.formePrincipale, FormePim.reacteur);
      // Retour à la sphère.
      pim.definirFormePrincipale(FormePim.sphere);
      await _attendre(tester, 4);
      expect(pim.etalement.maximum, lessThan(1.1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('forme secondaire « sphère » quand la principale est le '
        'cube, puis retour au cube', (tester) async {
      final pim = await _pim(tester, FormePim.cube);
      final cube = await _moyenne(tester, pim, 0.5);
      pim.declencherForme(FormePim.sphere);
      await _attendre(tester, 0.8 + 2.4 + 0.5);
      expect(pim.mode, ParticlePimMode.sphere);
      expect(pim.etalement.maximum, lessThan(1.1));
      await _attendre(tester, 5 + 2.6 + 1.5);
      expect(pim.phaseForme, PhaseForme.absent);
      expect(await _moyenne(tester, pim, 0.5), closeTo(cube, 0.05));
    });

    testWidgets('aperçu : cube principal → tétraèdre → cube', (tester) async {
      final pim = await _pim(tester, FormePim.cube);
      expect(pim.lancerApercu(FormePim.tetraedre), isTrue);
      await _attendre(tester, 0.5);
      expect(pim.phaseForme, isNot(PhaseForme.absent));
      expect(pim.forme, FormePim.tetraedre);
      await _attendre(tester, 0.8 + 2.4 + 0.3);
      expect(pim.mode, ParticlePimMode.tetraedre);
      await _attendre(tester, 5 + 2.6 + 1);
      expect(pim.apercuEnCours, isFalse);
      expect(pim.formePrincipale, FormePim.cube);
      expect(pim.mode, ParticlePimMode.idle);
    });

    testWidgets('aperçu de la forme principale elle-même : présentation au '
        'repos, sans transformation', (tester) async {
      final pim = await _pim(tester, FormePim.tetraedre);
      expect(pim.lancerApercu(FormePim.tetraedre), isTrue);
      for (var i = 0; i < 60 * 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(pim.phaseForme, PhaseForme.absent);
      }
      expect(pim.apercuEnCours, isTrue);
      await _attendre(tester, 2);
      expect(pim.apercuEnCours, isFalse);
      expect(pim.mode, ParticlePimMode.idle);
    });
  });
}
