import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

class _Micro implements MicrophoneService {
  @override
  Future<AccesMicro> demanderAcces() async => AccesMicro.autorise;
  @override
  Future<void> ouvrirReglages() async {}
}

class _Reco implements SpeechRecognitionService {
  void Function(String)? phrase;
  void Function(double)? niveau;
  @override
  Future<ErreurReconnaissance?> initialiser() async => null;
  @override
  Future<void> ecouter({
    required void Function(String phrase) surPhrase,
    required void Function(ErreurReconnaissance erreur) surErreur,
    required void Function() surFinSansResultat,
    void Function(String texte)? surPartiel,
    void Function(double amplitude)? surNiveau,
  }) async {
    phrase = surPhrase;
    niveau = surNiveau;
  }

  @override
  Future<void> annuler() async {}
}

class _Voix implements TtsService {
  @override
  String? voiceChoisie;
  @override
  Future<void> initialiser() async {}

  @override
  Future<void> appliquer(VoiceSettings reglages) async =>
      appliques.add(reglages);

  final appliques = <VoiceSettings>[];

  @override
  Future<List<VoixDisponible>> voixDisponibles({
    bool rafraichir = false,
  }) async => const [];
  @override
  Future<ResultatParole> parler(
    String texte, {
    void Function(int debut, int fin)? surMot,
    void Function()? surDebut,
  }) async {
    surDebut?.call();
    for (var i = 0; i < 10; i++) {
      surMot?.call(i * 5, i * 5 + 4);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return ResultatParole.lue;
  }

  @override
  Future<void> arreter() async {}
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

void main() {
  testWidgets('mode vocal : particules groupées, puis retour à la forme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1887, 872);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reco = _Reco();
    final session = VoiceSession(
      micro: _Micro(),
      reconnaissance: reco,
      voix: _Voix(),
      niveau: _Niveau(),
    );
    final pim = PimController();
    await tester.pumpWidget(
      MaterialApp(
        theme: themeJarvis(),
        home: AccueilPage(session: session, pim: pim),
      ),
    );

    Future<void> attendre(double s) async {
      for (var i = 0; i < (s * 60).round(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await attendre(1);
    await tester.tap(find.byTooltip('Ouvrir le chat vocal'));
    await attendre(1.5);
    for (var i = 0; i < 60; i++) {
      reco.niveau?.call(i.isEven ? 1 : 0.3);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pim.etalement.maximum, lessThan(1.4));
    reco.phrase?.call('Bonjour JARVIS');
    await attendre(1.5);
    await attendre(1.5);
    expect(pim.etalement.maximum, lessThan(1.4));
    await tester.tap(find.text('Quitter le mode vocal'));
    await attendre(2);
    // L'échange vocal est dans la conversation (partagée avec l'écrit) : les
    // particules entourent maintenant la barre, comme en conversation
    // écrite.
    expect(find.text('Bonjour JARVIS'), findsOneWidget);
    expect(
      pim.mode,
      isIn([ParticlePimMode.inputCalm, ParticlePimMode.sending]),
    );
    expect(tester.takeException(), isNull);
  });
}
