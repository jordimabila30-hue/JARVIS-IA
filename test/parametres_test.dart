import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/widgets/parametres/elements_parametres.dart';
import 'package:ia_jarvis/widgets/parametres/icone_reacteur_arc.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

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
  }) async => const [
    VoixDisponible(nom: 'Microsoft Denise', locale: 'fr-FR'),
    VoixDisponible(nom: 'Google français', locale: 'fr-FR', enLigne: true),
    VoixDisponible(nom: 'Microsoft Sylvie', locale: 'fr-CA'),
  ];
  @override
  Future<ResultatParole> parler(
    String texte, {
    void Function(int debut, int fin)? surMot,
    void Function()? surDebut,
  }) async {
    surDebut?.call();
    return ResultatParole.lue;
  }

  @override
  Future<void> arreter() async {}
}

class _Micros implements PeripheriquesAudio {
  @override
  bool get choixPossible => true;
  @override
  Future<List<MicroDisponible>> lister() async => const [
    MicroDisponible(id: 'usb', nom: 'Microphone USB'),
    MicroDisponible(id: 'casque', nom: 'Microphone du casque'),
  ];
  @override
  Future<bool> autoriser() async => true;
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

/// Page d'accueil avec des services factices, au format [taille].
Future<VoiceSettingsService> _ouvrir(WidgetTester tester, Size taille) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tts = _Tts();
  final reglages = VoiceSettingsService(
    tts: tts,
    stockage: StockageMemoire(),
    peripheriques: _Micros(),
    delaiSauvegarde: Duration.zero,
  );
  final session = VoiceSession(
    micro: _Micro(),
    reconnaissance: _Reco(),
    voix: tts,
    niveau: _Niveau(),
    reglages: reglages,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: themeJarvis(),
      home: AccueilPage(session: session, pim: PimController()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  // Paramètres : depuis le menu latéral.
  await tester.tap(find.byTooltip('Menu'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byTooltip('Paramètres'));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return reglages;
}

void main() {
  testWidgets('ordinateur : fenêtre, navigation, réglage, Échap', (
    tester,
  ) async {
    final reglages = await _ouvrir(tester, const Size(1366, 768));
    expect(find.text('Paramètres'), findsWidgets);
    expect(find.text('Profil vocal'), findsOneWidget);
    // Aucun compte inventé : sans serveur de comptes, « Sans compte ».
    expect(find.text('jordi'), findsNothing);
    expect(find.text('Sans compte'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Dynamique'));
    await tester.pump();
    expect(reglages.reglages.profil.name, 'dynamique');

    await tester.tap(find.text('Confidentialité'));
    await tester.pump();
    expect(find.text('Bientôt'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Profil vocal'), findsNothing);
    expect(find.text('Bientôt'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('téléphone : liste des sections puis section', (tester) async {
    await _ouvrir(tester, const Size(390, 844));
    expect(find.text('Chat vocal'), findsOneWidget);
    expect(find.text('Profil vocal'), findsNothing);

    await tester.tap(find.text('Chat vocal'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Profil vocal'), findsOneWidget);
    expect(find.byTooltip('Retour aux paramètres'), findsOneWidget);
    // Tout le panneau défile sans débordement.
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
    await tester.pump();
    expect(find.text('Écouter un aperçu'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Retour aux paramètres'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Profil vocal'), findsNothing);
    expect(find.text('Confidentialité'), findsOneWidget);
  });

  testWidgets('Particules PIM : les quatre formes en tuiles, sans texte '
      'technique', (tester) async {
    await _ouvrir(tester, const Size(1366, 768));
    await tester.tap(find.text('Particules PIM'));
    await tester.pump();
    expect(find.text('FORME DE JARVIS'), findsOneWidget);
    expect(find.byType(TuileChoix), findsNWidgets(4));
    // Réacteur Arc : son vrai dessin, pas une icône générique.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Réacteur Arc'),
          matching: find.byType(TuileChoix),
        ),
        matching: find.byType(IconeReacteurArc),
      ),
      findsOneWidget,
    );
    // Une seule ligne de quatre tuiles sur grand écran.
    final hauts = find
        .byType(TuileChoix)
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)).top)
        .toSet();
    expect(hauts, hasLength(1));
    expect(find.text('2 200'), findsNothing);
    expect(find.textContaining('Par défaut'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
