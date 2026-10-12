// Une seule conversation pour l'écrit et le vocal : messages, ordre,
// contexte partagé dans les deux sens, nouvelle conversation, transcription
// sans doublon.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/bouton_vocal.dart';
import 'package:ia_jarvis/widgets/conversation/bulle_utilisateur.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

class _Micro implements MicrophoneService {
  @override
  Future<AccesMicro> demanderAcces() async => AccesMicro.autorise;
  @override
  Future<void> ouvrirReglages() async {}
}

/// Reconnaissance factice : le test envoie des résultats partiels, une
/// phrase validée, une erreur ou une écoute vide.
class _Reco implements SpeechRecognitionService {
  void Function(String)? phrase;
  void Function(String)? partiel;
  void Function(ErreurReconnaissance)? erreur;
  void Function()? vide;
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
    partiel = surPartiel;
    erreur = surErreur;
    vide = surFinSansResultat;
  }

  @override
  Future<void> annuler() async {}
}

class _Voix implements TtsService {
  final dits = <String>[];
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
  }) async {
    dits.add(texte);
    surDebut?.call();
    await Future<void>.delayed(const Duration(milliseconds: 100));
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

class _Micros implements PeripheriquesAudio {
  @override
  bool get choixPossible => false;
  @override
  Future<List<MicroDisponible>> lister() async => const [];
  @override
  Future<bool> autoriser() async => false;
}

late _Reco _reco;
late _Voix _voix;
late ConversationSession _conversation;

Future<void> _accueil(WidgetTester tester, Size taille) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _reco = _Reco();
  _voix = _Voix();
  _conversation = ConversationSession(
    delaiReflexion: const Duration(milliseconds: 200),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: themeJarvis(),
      home: AccueilPage(
        session: VoiceSession(
          micro: _Micro(),
          reconnaissance: _reco,
          voix: _voix,
          niveau: _Niveau(),
          reglages: VoiceSettingsService(
            tts: _voix,
            stockage: StockageMemoire(),
            peripheriques: _Micros(),
            delaiSauvegarde: Duration.zero,
          ),
        ),
        pim: PimController(),
        conversation: _conversation,
      ),
    ),
  );
  await _attendre(tester, 0.5);
}

Future<void> _attendre(WidgetTester tester, double s) async {
  for (var i = 0; i < (s * 60).round(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _ouvrirVocal(WidgetTester tester) async {
  await tester.tap(find.byType(BoutonVocal).last);
  await _attendre(tester, 1);
}

Future<void> _dire(WidgetTester tester, String phrase) async {
  _reco.phrase!(phrase);
  await _attendre(tester, 3);
}

Future<void> _ecrire(WidgetTester tester, String texte) async {
  await tester.enterText(find.byType(EditableText), texte);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await _attendre(tester, 1);
}

void main() {
  group('Session de conversation', () {
    ConversationSession session() =>
        ConversationSession(delaiReflexion: Duration.zero);

    test(
      'une phrase vocale ajoute deux messages et renvoie la réponse',
      () async {
        final s = session();
        final r = await s.repondreVocal('Bonjour JARVIS');
        expect(s.messages, hasLength(2));
        expect(s.messages[0].texte, 'Bonjour JARVIS');
        expect(s.messages[0].deJarvis, isFalse);
        expect(s.messages[1].deJarvis, isTrue);
        expect(s.messages.every((m) => m.vocal), isTrue);
        expect(r!.texte, s.messages[1].texte);
        // Phrase vide : rien.
        expect(await s.repondreVocal('   '), isNull);
        expect(s.messages, hasLength(2));
      },
    );

    test('contexte partagé : vocal → écrit', () async {
      final s = session();
      await s.repondreVocal('Je m’appelle Jordi');
      await s.envoyer('Comment je m’appelle ?');
      expect(s.messages.last.texte, contains('Jordi'));
    });

    test('contexte partagé : écrit → vocal', () async {
      final s = session();
      await s.envoyer('Je m’appelle Léa');
      final r = await s.repondreVocal('Comment je m’appelle ?');
      expect(r!.texte, contains('Léa'));
      expect(s.messages.last.texte, contains('Léa'));
    });

    test('ordre chronologique conservé, ids croissants', () async {
      final s = session();
      await s.envoyer('Bonjour');
      await s.repondreVocal('Quelle heure est-il ?');
      await s.envoyer('Merci');
      await s.repondreVocal('Combien font 2 plus 2 ?');
      expect(s.messages.map((m) => m.vocal).toList(), [
        false, false, true, true, false, false, true, true, //
      ]);
      for (var i = 1; i < s.messages.length; i++) {
        expect(s.messages[i].id, greaterThan(s.messages[i - 1].id));
        expect(s.messages[i].heure.isBefore(s.messages[i - 1].heure), isFalse);
      }
    });

    test('nouvelle conversation : contexte distinct', () async {
      final s = session();
      await s.repondreVocal('Je m’appelle Jordi');
      s.effacer();
      expect(s.messages, isEmpty);
      final r = await s.repondreVocal('Comment je m’appelle ?');
      expect(r!.texte, isNot(contains('Jordi')));
    });

    test(
      '« Au revoir » : réponse enregistrée, fin du chat vocal signalée',
      () async {
        final s = session();
        final r = await s.repondreVocal('Au revoir JARVIS');
        expect(r!.terminerSession, isTrue);
        expect(s.messages, hasLength(2));
        // À l'écrit, la même phrase ne termine rien.
        await s.envoyer('Au revoir JARVIS');
        expect(s.messages, hasLength(4));
      },
    );
  });

  group('Sur l’accueil', () {
    testWidgets('vocal puis écrit : tous les échanges vocaux visibles, '
        'contexte et brouillon conservés', (tester) async {
      await _accueil(tester, const Size(390, 844));
      // Brouillon commencé avant de passer au vocal.
      await tester.enterText(find.byType(EditableText), 'Brouillon');
      await _attendre(tester, 0.2);
      // Avec un brouillon, le bouton de la barre envoie : le vocal s'ouvre
      // depuis le menu.
      expect(find.byTooltip('Envoyer le message'), findsOneWidget);
      await tester.tap(find.byTooltip('Menu'));
      await _attendre(tester, 0.4);
      await tester.tap(find.text('Chat vocal'));
      await _attendre(tester, 1);
      // Résultats partiels : aucun message ajouté.
      _reco.partiel?.call('Je');
      _reco.partiel?.call('Je m’appelle');
      await _attendre(tester, 0.3);
      expect(_conversation.messages, isEmpty);
      await _dire(tester, 'Je m’appelle Jordi');
      await _dire(tester, 'Quelle heure est-il ?');
      // La réponse prononcée est celle enregistrée.
      expect(_voix.dits.last, _conversation.messages.last.texte);
      await tester.tap(find.text('Quitter le mode vocal'));
      await _attendre(tester, 1);

      // Quatre messages vocaux, dans l'ordre, sans doublon, visibles.
      expect(_conversation.messages, hasLength(4));
      expect(_conversation.messages.every((m) => m.vocal), isTrue);
      expect(find.byType(BulleUtilisateur), findsNWidgets(2));
      expect(find.text('Je m’appelle Jordi'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Brouillon',
      );
      // Suite à l'écrit, avec le contexte du vocal.
      await _ecrire(tester, 'Comment je m’appelle ?');
      expect(_conversation.messages.last.texte, contains('Jordi'));
      expect(_conversation.messages, hasLength(6));
      expect(tester.takeException(), isNull);
    });

    testWidgets('écrit puis vocal : le vocal connaît le contexte écrit', (
      tester,
    ) async {
      await _accueil(tester, const Size(1366, 768));
      await _ecrire(tester, 'Je m’appelle Léa');
      await _ouvrirVocal(tester);
      await _dire(tester, 'Comment je m’appelle ?');
      expect(_voix.dits.last, contains('Léa'));
      expect(_conversation.messages, hasLength(4));
      await tester.tap(find.text('Quitter le mode vocal'));
      await _attendre(tester, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('échec de reconnaissance : aucune transcription inventée', (
      tester,
    ) async {
      await _accueil(tester, const Size(1366, 768));
      await _ouvrirVocal(tester);
      _reco.vide?.call();
      await _attendre(tester, 2);
      _reco.erreur?.call(ErreurReconnaissance.client);
      await _attendre(tester, 2);
      expect(_conversation.messages, isEmpty);
      await tester.tap(find.text('Quitter le mode vocal'));
      await _attendre(tester, 1);
    });

    testWidgets('nouvelle conversation : tout repart de zéro', (tester) async {
      await _accueil(tester, const Size(1366, 768));
      await _ouvrirVocal(tester);
      await _dire(tester, 'Je m’appelle Jordi');
      await tester.tap(find.text('Quitter le mode vocal'));
      await _attendre(tester, 1);
      await tester.tap(find.byTooltip('Nouvelle conversation'));
      await _attendre(tester, 1);
      expect(_conversation.messages, isEmpty);
      await _ecrire(tester, 'Comment je m’appelle ?');
      expect(_conversation.messages.last.texte, isNot(contains('Jordi')));
      expect(tester.takeException(), isNull);
    });
  });
}
