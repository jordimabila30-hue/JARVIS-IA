// Captures de l'interface 3 de l'import WhatsApp (vraies polices) : page
// « Joindre la conversation », barre de saisie avec la pièce jointe en
// attente, message envoyé avec sa carte.
//
//   CAPTURE_DIR=chemin flutter test tool/capture_joindre_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/piece_jointe_whatsapp.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/pages/joindre_whatsapp_page.dart';
import 'package:ia_jarvis/services/importation/identite_whatsapp.dart';
import 'package:ia_jarvis/services/importation/selection_whatsapp.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/bulle_utilisateur.dart';
import 'package:ia_jarvis/widgets/conversation/carte_piece_jointe.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';

const _polices = r'C:\flutter\bin\cache\artifacts\material_fonts';

Future<void> _charger(String famille, List<String> fichiers) async {
  final f = FontLoader(famille);
  for (final nom in fichiers) {
    final octets = File(nom).readAsBytesSync();
    f.addFont(Future.value(ByteData.view(octets.buffer)));
  }
  await f.load();
}

ThemeData _theme() => themeJarvis().copyWith(
  textTheme: Typography.material2021().black
      .merge(themeJarvis().textTheme)
      .apply(fontFamily: 'Roboto'),
);

MessageWhatsApp _m(int o, DateTime d, String a, String t) => MessageWhatsApp(
  ordre: o,
  auteur: a,
  date: d,
  dateBrute: '$d',
  texte: t,
  type: TypeMessageWhatsApp.texte,
);

final _conversation = ConversationWhatsApp(
  titre: 'Tony Stark',
  messages: [
    for (var i = 0; i < 35; i++)
      _m(
        i,
        DateTime(2026, 10, 3 + i ~/ 4, 9, i),
        i.isEven ? 'Tony Stark' : 'Jordi',
        'Message $i',
      ),
  ],
  participants: const [
    ParticipantWhatsApp(nom: 'Tony Stark', messages: 18),
    ParticipantWhatsApp(nom: 'Jordi', messages: 17),
  ],
  ordreDate: OrdreDate.jourMoisAnnee,
  dateIncertaine: false,
  lignesNonRattachees: const [],
  nombreLignesNonRattachees: 0,
  nomFichier: 'Discussion WhatsApp avec Tony Stark.txt',
);

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

  Future<void> photo(WidgetTester tester, GlobalKey cle, String nom) async {
    if (dossier == null) return;
    final objet =
        cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.runAsync(() async {
      final image = await objet.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '$dossier/joindre_$nom.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<GlobalKey> afficher(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final cle = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: cle,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: page,
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return cle;
  }

  final selection = SelectionWhatsApp(_conversation)..cocherVisibles(true);
  final piece = PieceJointeWhatsApp.depuis(
    conversation: _conversation,
    choisis: selection.resultat(),
    moi: 'Jordi',
  );

  testWidgets('page « Joindre la conversation »', (tester) async {
    final cle = await afficher(
      tester,
      JoindreWhatsAppPage(
        conversation: _conversation,
        choisis: selection.resultat(),
        identite: IdentiteWhatsApp(stockage: StockageMemoire()),
      ),
    );
    await photo(tester, cle, 'page');
    await tester.tap(find.text('Jordi'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await photo(tester, cle, 'page_choisi');
    expect(tester.takeException(), isNull);
  });

  testWidgets('barre et historique', (tester) async {
    final controleur = TextEditingController(
      text: 'Propose-moi une réponse naturelle.',
    );
    final focus = FocusNode();
    addTearDown(controleur.dispose);
    addTearDown(focus.dispose);
    final cle = await afficher(
      tester,
      Scaffold(
        backgroundColor: CouleursJarvis.ivoire,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              BulleUtilisateur(
                message: MessageConversation(
                  id: 0,
                  auteur: AuteurMessage.utilisateur,
                  heure: DateTime(2026, 10, 15, 10, 2),
                  texte: 'JARVIS, analyse cette discussion et propose-moi '
                      'une réponse.',
                  pieceJointe: piece,
                ),
              ),
              const SizedBox(height: 60),
              LigneDeCommande(
                controleur: controleur,
                focus: focus,
                onEnvoyer: (_) {},
                onChatVocal: () {},
                compacte: true,
                surImporterWhatsApp: () {},
                pieceJointe: PieceJointeEnAttente(
                  piece: piece,
                  surRetirer: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await photo(tester, cle, 'barre_historique');
    expect(tester.takeException(), isNull);
  });
}
