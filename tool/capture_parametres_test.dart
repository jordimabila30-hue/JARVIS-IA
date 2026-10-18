// Captures des Paramètres (vraies polices) : Chat vocal (langue, voix aux
// noms simples, diction), Particules PIM (formes en tuiles), avec des
// voix comme celles d'Edge, et Outils › Gmail (états simulés, faux serveur).
//
//   CAPTURE_DIR=chemin flutter test tool/capture_parametres_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/integrations/service_gmail.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/preferences_pim_service.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/parametres/fenetre_parametres.dart';

const _polices = r'C:\flutter\bin\cache\artifacts\material_fonts';

Future<void> _charger(String famille, List<String> fichiers) async {
  final f = FontLoader(famille);
  for (final nom in fichiers) {
    final octets = File(nom).readAsBytesSync();
    f.addFont(Future.value(ByteData.view(octets.buffer)));
  }
  await f.load();
}

const _voixEdge = [
  'Microsoft Denise Online (Natural) - French (France)',
  'Microsoft Eloise Online (Natural) - French (France)',
  'Microsoft Henri Online (Natural) - French (France)',
  'Microsoft Hortense - French (France)',
  'Microsoft Julie - French (France)',
  'Microsoft Paul - French (France)',
  'Microsoft Rémy Multilingual Online (Natural) - French (France)',
  'Microsoft Vivienne Multilingual Online (Natural) - French (France)',
];

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
  }) async => [
    for (final n in _voixEdge) VoixDisponible(nom: n, locale: 'fr-FR'),
    const VoixDisponible(
      nom: 'Microsoft Sylvie Online (Natural) - French (Canada)',
      locale: 'fr-CA',
    ),
    const VoixDisponible(
      nom: 'Microsoft Aria Online (Natural) - English (United States)',
      locale: 'en-US',
    ),
    const VoixDisponible(nom: 'Microsoft Katja - German', locale: 'de-DE'),
    const VoixDisponible(nom: 'Microsoft Elvira - Spanish', locale: 'es-ES'),
    const VoixDisponible(nom: 'Microsoft Elsa - Italian', locale: 'it-IT'),
    const VoixDisponible(nom: 'Microsoft Hamed - Arabic', locale: 'ar-SA'),
  ];
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
  bool get choixPossible => true;
  @override
  Future<List<MicroDisponible>> lister() async => const [
    MicroDisponible(id: 'usb', nom: 'Microphone USB'),
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

  for (final (section, taille, nom) in const [
    (SectionParametres.chatVocal, Size(1100, 1500), 'chat_vocal'),
    (SectionParametres.particules, Size(1100, 700), 'particules'),
    (SectionParametres.particules, Size(390, 844), 'particules_telephone'),
  ]) {
    testWidgets(nom, (tester) async {
      tester.view.physicalSize = taille * 2;
      tester.view.devicePixelRatio = 2;
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
      await reglages.chargerCapacites();
      final cle = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: cle,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: themeJarvis().copyWith(
              textTheme: themeJarvis().textTheme.apply(fontFamily: 'Roboto'),
            ),
            home: Scaffold(
              body: FenetreParametres(
                session: session,
                formes: PreferencesPimService(stockage: StockageMemoire()),
                sectionInitiale: section,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      if (dossier != null) {
        final objet =
            cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await objet.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$dossier/parametres_$nom.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      expect(tester.takeException(), isNull);
      // Minuteries de la fenêtre (indicateur « Enregistré »).
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    });
  }

  // Outils › Gmail : états simulés (aucun appel réel). Parcours tapé comme
  // un utilisateur : Outils, puis Gmail, puis « Gérer la connexion ».
  for (final (taille, nom, reponse, parcours) in [
    (const Size(412, 869), 'outils_telephone', _connecte, const ['Outils']),
    (const Size(412, 869), 'gmail_connecte_telephone', _connecte, const ['Outils', 'Gmail']),
    (const Size(412, 869), 'gmail_gerer_telephone', _connecte, const ['Outils', 'Gmail', 'Gérer la connexion']),
    (const Size(412, 869), 'gmail_deconnecte_telephone', _deconnecte, const ['Outils', 'Gmail']),
    (const Size(360, 640), 'gmail_connecte_petit', _connecte, const ['Outils', 'Gmail']),
    (const Size(1280, 800), 'outils_ordinateur', _connecte, const <String>[]),
    (const Size(1280, 800), 'gmail_connecte_ordinateur', _connecte, const ['Gmail']),
    (const Size(1280, 800), 'gmail_deconnecte_ordinateur', _deconnecte, const ['Gmail']),
    (const Size(1280, 800), 'gmail_gerer_ordinateur', _connecte, const ['Gmail', 'Gérer la connexion']),
  ]) {
    testWidgets(nom, (tester) async {
      tester.view.physicalSize = taille * 2;
      tester.view.devicePixelRatio = 2;
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
      await reglages.chargerCapacites();
      final api = ApiJarvis(
        adresse: Uri.parse('http://test'),
        jeton: () async => 'jeton',
        client: MockClient((_) async => http.Response(jsonEncode(reponse), 200,
            headers: {'content-type': 'application/json; charset=utf-8'})),
      );
      final gmail = ServiceGmail(api, ouvrir: (_) async => true);
      await tester.runAsync(() => gmail.actualiser());
      final cle = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: cle,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: themeJarvis().copyWith(
              textTheme: themeJarvis().textTheme.apply(fontFamily: 'Roboto'),
            ),
            home: Scaffold(
              body: FenetreParametres(
                session: session,
                formes: PreferencesPimService(stockage: StockageMemoire()),
                sectionInitiale: SectionParametres.outils,
                gmail: gmail,
              ),
            ),
          ),
        ),
      );
      Future<void> attendre() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await attendre();
      for (final etape in parcours) {
        await tester.tap(find.text(etape).last);
        await attendre();
      }
      if (dossier != null) {
        final objet =
            cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await objet.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$dossier/parametres_$nom.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      gmail.dispose();
    });
  }
}

const _connecte = {
  'statut': 'connecte',
  'configure': true,
  'email': 'pepper.potts@gmail.com',
  'portee': 'lecture_seule',
};
const _deconnecte = {'statut': 'non_connecte', 'configure': true};
