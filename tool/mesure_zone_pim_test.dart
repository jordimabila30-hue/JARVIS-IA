// Mesure la hauteur réellement dessinée par les particules PIM au-dessus
// de la barre, en conversation (pixels du calque PIM, sans toucher au
// moteur) : repos, impulsion d'envoi, clavier qui s'ouvre et se ferme vite.
//
//   flutter test tool/mesure_zone_pim_test.dart
//
// Sert à régler `MesuresConversation` (zone PIM réservée).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

/// Ligne la plus haute du calque PIM où un pixel dépasse [seuil] d'opacité.
Future<double> hautDessine(WidgetTester tester, {int seuil = 12}) async {
  final objet = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(PimParticle),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  late double haut;
  await tester.runAsync(() async {
    final image = await objet.toImage();
    final octets = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    haut = double.infinity;
    for (var y = 0; y < image.height && haut.isInfinite; y++) {
      for (var x = 0; x < image.width; x++) {
        if (octets.getUint8((y * image.width + x) * 4 + 3) > seuil) {
          haut = y.toDouble();
          break;
        }
      }
    }
  });
  return haut + tester.getTopLeft(find.byType(PimParticle)).dy;
}

void main() {
  const formats = [
    Size(390, 844),
    Size(412, 915),
    Size(360, 800),
    Size(429, 599),
    Size(820, 1180),
    Size(1366, 768),
    Size(1920, 1080),
  ];
  for (final ecran in formats) {
    testWidgets('dépassement PIM $ecran', (tester) async {
      tester.view.physicalSize = ecran;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: themeJarvis(),
          home: AccueilPage(
            pim: PimController(),
            conversation: ConversationSession(
              delaiReflexion: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );
      Future<void> images(int n) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      var repos = 0.0, envoi = 0.0, clavier = 0.0;
      Future<double> depasse() async =>
          tester.getRect(find.byType(LigneDeCommande)).top -
          await hautDessine(tester);

      await images(30);
      await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
      await images(120);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        envoi = math.max(envoi, await depasse());
      }
      await images(120);
      // Envois suivants, au régime normal.
      var envoiNormal = 0.0;
      for (var m = 0; m < 3; m++) {
        await tester.enterText(find.byType(EditableText), 'Message $m');
        await images(60);
        await tester.testTextInput.receiveAction(TextInputAction.send);
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          envoiNormal = math.max(envoiNormal, await depasse());
        }
        await images(60);
      }
      // ignore: avoid_print
      print('MESURE $ecran envoi normal=${envoiNormal.toStringAsFixed(1)}');
      for (var i = 0; i < 20; i++) {
        await images(6);
        repos = math.max(repos, await depasse());
      }
      // Clavier : ouverture puis fermeture, en [n] images. Mesure le
      // dépassement par rapport à la barre et l'écart restant avec le bas
      // du fil (négatif = particule dessinée sur le fil).
      final fil = find.byKey(const Key('fil-conversation'));
      Future<void> clavierAnime(double de, double a, int n, String nom) async {
        var pire = 0.0, ecart = double.infinity;
        for (var i = 1; i <= n + 25; i++) {
          if (i <= n) {
            final t = Curves.easeInOutCubic.transform(i / n);
            tester.view.viewInsets = FakeViewPadding(bottom: de + (a - de) * t);
          }
          await tester.pump(const Duration(milliseconds: 16));
          final haut = await hautDessine(tester);
          pire = math.max(
            pire,
            tester.getRect(find.byType(LigneDeCommande)).top - haut,
          );
          ecart = math.min(ecart, haut - tester.getRect(fil).bottom);
        }
        // ignore: avoid_print
        print(
          'MESURE $ecran $nom ($n images) dépassement=${pire.toStringAsFixed(1)} '
          'écart fil=${ecart.toStringAsFixed(1)}',
        );
      }

      await tester.tap(find.byType(EditableText));
      final k = ecran.height * 0.42;
      await clavierAnime(0, k, 15, 'ouverture');
      await clavierAnime(k, 0, 15, 'fermeture');
      await clavierAnime(0, k, 15, 'ouverture');
      await clavierAnime(k, 0, 8, 'fermeture rapide');
      await clavierAnime(0, k, 15, 'ouverture');
      await clavierAnime(k, 0, 1, 'fermeture instantanée');
      // ignore: avoid_print
      print(
        'MESURE $ecran repos=${repos.toStringAsFixed(1)} '
        'envoi=${envoi.toStringAsFixed(1)} '
        'clavier=${clavier.toStringAsFixed(1)}',
      );
    });
  }
}
