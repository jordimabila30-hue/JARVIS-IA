// Captures des pages d'authentification (vraies polices) : connexion,
// inscription, mot de passe oublié, sur téléphone et ordinateur, au repos
// puis avec les erreurs et le message « pas encore disponible ». Les
// libellés des boutons Material restent en police de test (blocs).
//
//   CAPTURE_DIR=chemin flutter test tool/capture_auth_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/pages/authentification/authentification_page.dart';
import 'package:ia_jarvis/services/authentification/auth_repository.dart';
import 'package:ia_jarvis/services/authentification/auth_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/authentification/bouton_auth.dart';

const _polices = r'C:\flutter\bin\cache\artifacts\material_fonts';

Future<void> _charger(String famille, List<String> fichiers) async {
  final f = FontLoader(famille);
  for (final nom in fichiers) {
    final octets = File(nom).readAsBytesSync();
    f.addFont(Future.value(ByteData.view(octets.buffer)));
  }
  await f.load();
}

void main() {
  final dossier = Platform.environment['CAPTURE_DIR'];

  setUpAll(() async {
    await _charger('Roboto', [
      for (final s in ['regular', 'medium', 'bold', 'italic', 'light'])
        '$_polices\\roboto-$s.ttf',
    ]);
    await _charger('MaterialIcons', ['$_polices\\materialicons-regular.otf']);
    await _charger('Exo2', ['assets/polices/Exo2.ttf']);
  });

  for (final (taille, nom) in const [
    (Size(390, 844), 'telephone'),
    (Size(1366, 900), 'ordinateur'),
  ]) {
    for (final ecran in EcranAuth.values) {
      testWidgets('${ecran.name} $nom', (tester) async {
        tester.view.physicalSize = taille * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final cle = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: cle,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              // Toutes les polices du thème (boutons compris) en Roboto.
              theme: themeJarvis().copyWith(
                textTheme: Typography.material2021().black
                    .merge(themeJarvis().textTheme)
                    .apply(fontFamily: 'Roboto'),
              ),
              home: AuthentificationPage(
                service: AuthService(const AuthRepositoryNonConfigure()),
                ecranInitial: ecran,
                surConnecte: (_) {},
                surAccesDeveloppement: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Future<void> photo(String etat) async {
          if (dossier == null) return;
          final objet =
              cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await objet.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File(
              '$dossier/auth_${ecran.name}_${nom}_$etat.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
          });
        }

        await photo('repos');
        // Erreurs : envoi du formulaire vide.
        await tester.tap(find.byType(BoutonAuth));
        await tester.pumpAndSettle();
        await photo('erreurs');
        // Formulaire valide : message « pas encore disponible ».
        final champs = find.byType(EditableText);
        final valeurs = switch (ecran) {
          EcranAuth.connexion => ['jordi@exemple.com', 'secret'],
          EcranAuth.inscription => [
            'Jordi',
            'jordi@exemple.com',
            'motdepasse1',
            'motdepasse1',
          ],
          EcranAuth.recuperation => ['jordi@exemple.com'],
        };
        for (var i = 0; i < valeurs.length; i++) {
          await tester.enterText(champs.at(i), valeurs[i]);
        }
        await tester.tap(find.byType(BoutonAuth));
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await photo('envoye');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
