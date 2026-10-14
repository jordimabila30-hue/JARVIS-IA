import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/pages/conversation_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/gabarit_jarvis.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/bulle_utilisateur.dart';
import 'package:ia_jarvis/widgets/conversation/carte_conversation_externe.dart';
import 'package:ia_jarvis/widgets/conversation/carte_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/choix_ton.dart';
import 'package:ia_jarvis/widgets/conversation/reponse_proposee.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

import 'outils/ecriture.dart';

class _Tts implements TtsService {
  @override
  String? voiceChoisie;
  @override
  Future<void> initialiser() async {}
  @override
  Future<void> appliquer(VoiceSettings reglages) async {}
  @override
  Future<List<VoixDisponible>> voixDisponibles({
    bool rafraichir = false,
  }) async => const [];
  @override
  Future<ResultatParole> parler(
    String texte, {
    void Function(int debut, int fin)? surMot,
    void Function()? surDebut,
  }) async => ResultatParole.lue;
  @override
  Future<void> arreter() async {}
}

class _Micros implements PeripheriquesAudio {
  @override
  bool get choixPossible => false;
  @override
  Future<List<MicroDisponible>> lister() async => const [];
  @override
  Future<bool> autoriser() async => false;
}

class _Micro implements MicrophoneService {
  @override
  Future<AccesMicro> demanderAcces() async => AccesMicro.autorise;
  @override
  Future<void> ouvrirReglages() async {}
}

class _Reco implements SpeechRecognitionService {
  @override
  Future<ErreurReconnaissance?> initialiser() async => null;
  @override
  Future<void> ecouter({
    required void Function(String phrase) surPhrase,
    required void Function(ErreurReconnaissance erreur) surErreur,
    required void Function() surFinSansResultat,
    void Function(String texte)? surPartiel,
    void Function(double amplitude)? surNiveau,
  }) async {}
  @override
  Future<void> annuler() async {}
}

class _Niveau implements NiveauMicro {
  @override
  Future<bool> demarrer(
    void Function(double niveau) surNiveau, {
    void Function(double graves, double mediums, double aigus)? surBandes,
    String? microphoneId,
  }) async => false;
  @override
  Future<void> arreter() async {}
}

const _sarah =
    'Sarah : Tu aurais pu me prévenir.\n'
    'Moi : Désolé, j’étais occupé.\n'
    'Sarah : Ce n’est pas la première fois.';

late PimController _pim;
late ConversationSession _conversation;

Widget _page() {
  final tts = _Tts();
  _pim = PimController();
  _conversation = ConversationSession(
    delaiReflexion: const Duration(milliseconds: 300),
  );
  return MaterialApp(
    theme: themeJarvis(),
    home: AccueilPage(
      session: VoiceSession(
        micro: _Micro(),
        reconnaissance: _Reco(),
        voix: tts,
        niveau: _Niveau(),
        reglages: VoiceSettingsService(
          tts: tts,
          stockage: StockageMemoire(),
          peripheriques: _Micros(),
        ),
      ),
      pim: _pim,
      conversation: _conversation,
    ),
  );
}

Future<void> _images(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Écrit dans la barre puis envoie (Entrée), comme l'utilisateur.
Future<void> _envoyer(WidgetTester tester, String texte) async {
  await tester.enterText(find.byType(EditableText), texte);
  await _images(tester, 5);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  // Réflexion de JARVIS puis réponse.
  await _images(tester, 40);
  // Réponse écrite progressivement jusqu'au bout (phase 4).
  await finirEcritures(tester);
}

const _formats = {
  '1920x1080': Size(1920, 1080),
  '1366x768': Size(1366, 768),
  '820x1180': Size(820, 1180),
  '429x599': Size(429, 599),
  '390x844': Size(390, 844),
};

void main() {
  String? copie;
  setUp(() => copie = null);

  void simulerPressePapiers(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (appel) async {
        if (appel.method == 'Clipboard.setData') {
          copie = (appel.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
  }

  Future<void> taille(WidgetTester tester, Size s) async {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('TEST 1-2 + 13 : discussion normale, PIM autour de la barre', (
    tester,
  ) async {
    await taille(tester, const Size(1366, 768));
    await tester.pumpWidget(_page());
    await _images(tester, 20);
    expect(find.byType(ConversationPage), findsNothing);
    expect(_pim.mode, ParticlePimMode.idle);

    // Pendant la saisie, les particules descendent vers la barre.
    await tester.enterText(find.byType(EditableText), 'Bonjour');
    await _images(tester, 10);
    expect(_pim.mode, isNot(ParticlePimMode.idle));
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _images(tester, 40);

    expect(find.byType(ConversationPage), findsOneWidget);
    expect(find.byType(BulleUtilisateur), findsOneWidget);
    expect(find.byType(CarteJarvis), findsOneWidget);
    expect(find.textContaining('Bonjour'), findsWidgets);
    // En conversation, les particules restent autour de la barre.
    await _images(tester, 120);
    expect(_pim.mode, isNot(ParticlePimMode.idle));
    expect(_pim.mode, isNot(ParticlePimMode.movingToCenter));

    await _envoyer(tester, 'Comment fonctionne une batterie ?');
    expect(find.textContaining('énergie'), findsOneWidget);
    expect(find.byType(ChoixTon), findsNothing);
    expect(find.text('Comprendre'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TEST 3 : conversation collée → carte intégrée et raccourcis', (
    tester,
  ) async {
    await taille(tester, const Size(1366, 768));
    await tester.pumpWidget(_page());
    await _images(tester, 10);
    await _envoyer(tester, _sarah);
    expect(find.byType(CarteConversationExterne), findsOneWidget);
    expect(find.textContaining('Tu aurais pu me prévenir'), findsOneWidget);
    for (final r in [
      'Comprendre',
      'Résumer',
      'Répondre',
      'Poser une question',
    ]) {
      expect(find.text(r), findsOneWidget);
    }
    // Raccourci « Résumer ».
    await tester.tap(find.text('Résumer'));
    await _images(tester, 40);
    expect(find.textContaining('En bref'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TEST 4 : conversation + « mal répondu ? » → analyse sans ton', (
    tester,
  ) async {
    await taille(tester, const Size(1366, 768));
    await tester.pumpWidget(_page());
    await _images(tester, 10);
    await _envoyer(tester, '$_sarah\nTu trouves que j’ai mal répondu ?');
    expect(find.byType(ChoixTon), findsNothing);
    expect(find.textContaining('excuses'), findsOneWidget);
  });

  testWidgets('TEST 5-9 : Quel ton ? → réponse qui change → Copier', (
    tester,
  ) async {
    await taille(tester, const Size(1366, 768));
    simulerPressePapiers(tester);
    await tester.pumpWidget(_page());
    await _images(tester, 10);
    await _envoyer(tester, '$_sarah\n\nTu peux me dire quoi répondre ?');
    expect(find.text(ChoixTon.titre), findsOneWidget);
    expect(find.byType(ReponseProposee), findsNothing);

    await tester.tap(find.text('Naturel'));
    await _images(tester, 20);
    expect(find.text(ReponseProposee.titre), findsOneWidget);
    expect(find.textContaining('j’aurais dû te prévenir'), findsWidgets);

    await tester.tap(find.text('Amical'));
    await _images(tester, 20);
    expect(find.textContaining('pas contre toi'), findsOneWidget);

    await tester.tap(find.text('Bienveillant'));
    await _images(tester, 20);
    expect(find.textContaining('blesser'), findsOneWidget);
    // Une seule réponse proposée, jamais de doublon.
    expect(find.byType(ReponseProposee), findsOneWidget);

    await tester.tap(find.text('Copier'));
    await _images(tester, 10);
    expect(copie, contains('blesser'));
    expect(find.text('Copié'), findsOneWidget);
    await _images(tester, 120);
    expect(tester.takeException(), isNull);
  });

  for (final f in _formats.entries) {
    testWidgets('TEST 10-12 ${f.key} : conversation longue, clavier, '
        'défilement, aucun débordement', (tester) async {
      await taille(tester, f.value);
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      final longue = List.generate(
        30,
        (i) => i.isEven ? 'Sarah : Message $i.' : 'Moi : Réponse $i.',
      ).join('\n');
      await _envoyer(tester, 'Bonjour JARVIS');
      await _envoyer(tester, longue);
      await _envoyer(tester, 'Tu peux me dire quoi répondre ?');
      await tester.tap(find.text('Direct'));
      await _images(tester, 20);
      expect(tester.takeException(), isNull);

      // Clavier ouvert : barre visible, aucun débordement.
      await tester.tap(find.byType(EditableText));
      for (var i = 1; i <= 10; i++) {
        tester.view.viewInsets = FakeViewPadding(
          bottom: f.value.height * 0.38 * i / 10,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _images(tester, 30);
      expect(tester.takeException(), isNull);
      final barre = tester.getRect(find.byType(LigneDeCommande));
      expect(barre.bottom, lessThanOrEqualTo(f.value.height * 0.62 + 0.5));

      // Le plus récent est visible ; les anciens restent accessibles.
      expect(find.byType(ReponseProposee), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await _images(tester, 30);
      expect(find.text('Bonjour JARVIS'), findsOneWidget);
      // Nouvelle réponse : retour au plus récent.
      await _envoyer(tester, 'Merci');
      await _images(tester, 30);
      expect(find.text('Merci'), findsOneWidget);

      // Largeur du fil : celle de la barre, centrée.
      final fil = tester.getRect(find.byType(ListView));
      expect(
        fil.width,
        lessThanOrEqualTo(GabaritJarvis.de(f.value).largeurSaisie + 0.5),
      );
      tester.view.viewInsets = FakeViewPadding.zero;
      await _images(tester, 30);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TEST 14 : Nouvelle conversation → retour à l’accueil', (
    tester,
  ) async {
    await taille(tester, const Size(390, 844));
    await tester.pumpWidget(_page());
    await _images(tester, 10);
    expect(find.byTooltip('Nouvelle conversation'), findsNothing);
    await _envoyer(tester, 'Bonjour JARVIS');
    expect(find.byType(ConversationPage), findsOneWidget);
    expect(_pim.conversation, isTrue);

    await tester.tap(find.byTooltip('Nouvelle conversation'));
    await _images(tester, 300);
    expect(find.byType(ConversationPage), findsNothing);
    expect(_conversation.vide, isTrue);
    expect(_pim.conversation, isFalse);
    // La sphère revient au centre, la salutation réapparaît.
    expect(_pim.mode, isIn([ParticlePimMode.idle, ParticlePimMode.cube]));
    final salut = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.textContaining('vous aide à comprendre'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(salut.opacity, 1);
    // L'accueil fonctionne toujours : nouvelle conversation possible.
    await _envoyer(tester, 'Bonjour JARVIS');
    expect(find.byType(CarteJarvis), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
