// Captures du menu latéral (vraies polices) : accueil, ouverture, menu
// ouvert.
//
//   CAPTURE_DIR=chemin flutter test tool/capture_menu_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/conversations/source_conversation.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversations/conversations_multicanal.dart';
import 'package:ia_jarvis/services/conversations/epingles_conversations.dart';
import 'package:ia_jarvis/services/conversations/fournisseur_conversations.dart';
import 'package:ia_jarvis/services/conversations/fournisseur_jarvis.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/widgets/menu/ligne_conversation.dart';
import 'package:ia_jarvis/widgets/menu/selecteur_sources.dart';

// Données de démonstration (tests uniquement).
import '../test/fixtures/conversations_demo.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

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

  const formats = {
    '1366x768': (Size(1366, 768), 1.0),
    '390x844': (Size(390, 844), 2.0),
  };

  for (final f in formats.entries) {
    testWidgets('menu ${f.key}', (tester) async {
      final (taille, densite) = f.value;
      tester.view.physicalSize = taille * densite;
      tester.view.devicePixelRatio = densite;
      addTearDown(tester.view.reset);
      final cle = GlobalKey();
      final conversation = ConversationSession(
        delaiReflexion: const Duration(milliseconds: 200),
      );
      final multicanal = ConversationsMulticanal(
        fournisseurs: [
          FournisseurJarvis(conversation),
          FournisseurDemo(SourceConversation.whatsapp, whatsappDemo()),
          FournisseurDemo(SourceConversation.gmail, gmailDemo()),
          FournisseurNonIntegre(SourceConversation.messenger),
          FournisseurNonIntegre(SourceConversation.instagram),
        ],
        epingles: EpinglesConversations(stockage: StockageMemoire()),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: cle,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: themeJarvis().copyWith(
              textTheme: themeJarvis().textTheme.apply(fontFamily: 'Roboto'),
            ),
            home: AccueilPage(
              pim: PimController(),
              conversation: conversation,
              multicanal: multicanal,
            ),
          ),
        ),
      );
      var n = 0;
      Future<void> images(int k) async {
        for (var i = 0; i < k; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      Future<void> photo(String nom) async {
        n++;
        if (dossier == null) return;
        final objet =
            cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await objet.toImage(pixelRatio: densite);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$dossier/menu_${f.key}_${n.toString().padLeft(2, '0')}_$nom.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
      }

      await images(40);
      await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await images(120);
      FocusManager.instance.primaryFocus?.unfocus();
      await images(60);
      await photo('accueil');
      await tester.tap(find.byTooltip('Menu'));
      await images(8);
      await photo('ouverture');
      await images(30);
      await photo('menu_ouvert');
      // « MES CONVERSATIONS » : WhatsApp (une épinglée), glissement vers
      // Gmail, Gmail.
      Finder onglet(SourceConversation s) => find.descendant(
        of: find.byType(SelecteurSources),
        matching: find.text(s.libelle),
      );
      await tester.tap(onglet(SourceConversation.whatsapp));
      await images(20);
      multicanal.epingles.basculer(
        multicanal.liste(SourceConversation.whatsapp)[3],
      );
      await images(5);
      await photo('whatsapp');
      // Balayage : « Épingler » (vers la droite), « Supprimer » (vers la
      // gauche), puis la confirmation.
      Finder ligne(int i) => find.byType(LigneConversation).at(i);
      await tester.drag(ligne(1), const Offset(120, 0));
      await images(20);
      await photo('balayage_epingler');
      await tester.drag(ligne(2), const Offset(-120, 0));
      await images(20);
      await photo('balayage_supprimer');
      await tester.tap(find.text(LigneConversation.boutonSupprimer));
      await images(20);
      await photo('confirmation_suppression');
      await tester.tap(find.text('Annuler'));
      await images(25);
      await tester.tap(onglet(SourceConversation.gmail));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      await photo('glissement');
      await images(20);
      await photo('gmail');
      await tester.tap(onglet(SourceConversation.messenger));
      await images(20);
      await photo('messenger_vide');
      await tester.tap(onglet(SourceConversation.jarvis));
      await images(20);
      // Mode vocal : « Quitter le mode vocal » et « Retour au chat ».
      await tester.tap(find.byTooltip('Fermer le menu'));
      await images(30);
      await tester.tap(find.byTooltip('Ouvrir le chat vocal'));
      await images(90);
      await photo('mode_vocal');
      await tester.tap(find.text('Retour au chat'));
      await images(60);
      await photo('retour_au_chat');
      expect(tester.takeException(), isNull);
    });
  }
}
