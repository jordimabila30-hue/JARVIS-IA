// Mode vocal ↔ écrit : « Quitter le mode vocal » (arrêt du chat vocal),
// « Retour au chat » (chat vocal en arrière-plan), lecture vocale
// facultative : haut-parleur à côté de la capsule vocale, seulement quand
// le chat vocal est en arrière-plan.

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
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

class _Micro implements MicrophoneService {
  @override
  Future<AccesMicro> demanderAcces() async => AccesMicro.autorise;
  @override
  Future<void> ouvrirReglages() async {}
}

class _Reco implements SpeechRecognitionService {
  void Function(String)? phrase;
  int ecoutes = 0, annulations = 0;
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
    ecoutes++;
    phrase = surPhrase;
  }

  @override
  Future<void> annuler() async => annulations++;
}

class _Voix implements TtsService {
  final dits = <String>[];
  int arrets = 0;
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
  Future<void> arreter() async => arrets++;
}

class _Niveau implements NiveauMicro {
  int demarrages = 0;
  @override
  Future<bool> demarrer(
    void Function(double niveau) surNiveau, {
    void Function(double graves, double mediums, double aigus)? surBandes,
    String? microphoneId,
  }) async {
    demarrages++;
    return false;
  }

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
late _Niveau _niveau;
late VoiceSession _session;
late ConversationSession _conversation;

Future<void> _accueil(WidgetTester tester, Size taille) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _reco = _Reco();
  _voix = _Voix();
  _niveau = _Niveau();
  _session = VoiceSession(
    micro: _Micro(),
    reconnaissance: _reco,
    voix: _voix,
    niveau: _niveau,
    reglages: VoiceSettingsService(
      tts: _voix,
      stockage: StockageMemoire(),
      peripheriques: _Micros(),
      delaiSauvegarde: Duration.zero,
    ),
  );
  _conversation = ConversationSession(
    delaiReflexion: const Duration(milliseconds: 200),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: themeJarvis(),
      home: AccueilPage(
        session: _session,
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

Future<void> _vocalAvecEchange(WidgetTester tester) async {
  await tester.tap(find.byType(BoutonVocal).last);
  await _attendre(tester, 1);
  _reco.phrase!('Je m’appelle Jordi');
  await _attendre(tester, 3);
}

bool _capsuleBleuViolet(WidgetTester tester) {
  final boite = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byType(LigneDeCommande),
          matching: find.byType(AnimatedContainer),
        )
        .last,
  );
  final c =
      ((boite.decoration! as BoxDecoration).gradient! as LinearGradient).colors;
  return c.first == BoutonVocal.degradeArrierePlan.first ||
      c.first == BoutonVocal.degradeArrierePlanEclaire.first;
}

void main() {
  testWidgets('ordinateur : « Quitter » et « Retour au chat » centrés '
      'ensemble', (tester) async {
    await _accueil(tester, const Size(1366, 768));
    await tester.tap(find.byType(BoutonVocal).last);
    await _attendre(tester, 1);
    final quitter = tester.getRect(
      find
          .ancestor(
            of: find.text('Quitter le mode vocal'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    final retour = tester.getRect(
      find
          .ancestor(
            of: find.text('Retour au chat'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    // Le groupe est centré ; « Quitter » garde sa hauteur (48 px).
    expect((quitter.left + retour.right) / 2, closeTo(683, 1));
    expect(quitter.height, 48);
    expect(retour.left, greaterThan(quitter.right));
    expect(retour.center.dy, closeTo(quitter.center.dy, 1));
    expect(retour.height, greaterThanOrEqualTo(44));
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final s in const [Size(320, 568), Size(360, 640), Size(390, 844)]) {
    testWidgets('$s : « Retour au chat » sous « Quitter », sans débordement', (
      tester,
    ) async {
      await _accueil(tester, s);
      await tester.tap(find.byType(BoutonVocal).last);
      await _attendre(tester, 1);
      expect(tester.takeException(), isNull);
      final quitter = tester.getRect(find.text('Quitter le mode vocal'));
      final retour = tester.getRect(find.text('Retour au chat'));
      expect(retour.top, greaterThan(quitter.bottom));
      expect(retour.bottom, lessThanOrEqualTo(s.height));
    });
  }

  testWidgets('« Retour au chat » : micro, reconnaissance et voix coupés, '
      'conversation retrouvée, chat vocal reprenable', (tester) async {
    await _accueil(tester, const Size(390, 844));
    await _vocalAvecEchange(tester);
    final arrets = _voix.arrets;
    final annulations = _reco.annulations;
    await tester.tap(find.text('Retour au chat'));
    await _attendre(tester, 1);
    expect(find.text('Quitter le mode vocal'), findsNothing);
    expect(_session.actif, isFalse);
    expect(_voix.arrets, greaterThan(arrets));
    expect(_reco.annulations, greaterThan(annulations));
    // Les échanges vocaux sont dans le fil.
    expect(find.text('Je m’appelle Jordi'), findsOneWidget);
    expect(_session.reprenable, isTrue);
    await _attendre(tester, 0.3);
    expect(_capsuleBleuViolet(tester), isTrue);
    // Reprise volontaire : le micro ne rouvre qu'à ce moment.
    final ecoutes = _reco.ecoutes;
    await _attendre(tester, 2);
    expect(_reco.ecoutes, ecoutes);
    await tester.tap(find.byTooltip('Reprendre le chat vocal'));
    await _attendre(tester, 1);
    expect(_session.actif, isTrue);
    expect(_reco.ecoutes, greaterThan(ecoutes));
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Quitter le mode vocal » : le chat vocal s’arrête (rien à '
      'reprendre, pas de haut-parleur), la conversation reste', (tester) async {
    await _accueil(tester, const Size(1366, 768));
    await _vocalAvecEchange(tester);
    await tester.tap(find.text('Quitter le mode vocal'));
    await _attendre(tester, 1);
    expect(_session.actif, isFalse);
    expect(_session.reprenable, isFalse);
    expect(find.byTooltip('Reprendre le chat vocal'), findsNothing);
    expect(find.byTooltip('Ouvrir le chat vocal'), findsOneWidget);
    expect(_capsuleBleuViolet(tester), isFalse);
    expect(find.byTooltip('Activer la lecture vocale'), findsNothing);
    expect(find.text('Je m’appelle Jordi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('haut-parleur : coupé par défaut, lit les réponses écrites '
      'quand il est activé, jamais de micro', (tester) async {
    await _accueil(tester, const Size(1366, 768));
    // Pas de chat vocal en arrière-plan : pas de haut-parleur.
    expect(find.byTooltip('Activer la lecture vocale'), findsNothing);
    await _vocalAvecEchange(tester);
    await tester.tap(find.text('Retour au chat'));
    await _attendre(tester, 1);
    // Capsule bleu-violet : le haut-parleur apparaît juste à sa gauche.
    expect(find.byTooltip('Activer la lecture vocale'), findsOneWidget);
    final capsule = tester.getRect(find.byType(BoutonVocal).last);
    final hautParleur = tester.getRect(
      find.byTooltip('Activer la lecture vocale'),
    );
    expect(hautParleur.right, lessThanOrEqualTo(capsule.left));
    expect(capsule.left - hautParleur.right, lessThan(12));
    expect(hautParleur.center.dy, closeTo(capsule.center.dy, 1));
    final ecoutes = _reco.ecoutes;
    final demarrages = _niveau.demarrages;
    _voix.dits.clear();
    // Par défaut : réponse écrite, rien n'est lu.
    await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _attendre(tester, 1);
    expect(_voix.dits, isEmpty);

    await tester.tap(find.byTooltip('Activer la lecture vocale'));
    await tester.pump();
    expect(find.byTooltip('Couper la lecture vocale'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Quelle heure est-il ?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _attendre(tester, 1);
    expect(_voix.dits, [_conversation.messages.last.texte]);
    // Micro jamais rouvert, le chat vocal reste en arrière-plan.
    expect(_reco.ecoutes, ecoutes);
    expect(_niveau.demarrages, demarrages);
    expect(_session.actif, isFalse);
    expect(_session.reprenable, isTrue);

    // Coupé : la lecture s'arrête, plus rien n'est lu.
    final arrets = _voix.arrets;
    await tester.tap(find.byTooltip('Couper la lecture vocale'));
    await tester.pump();
    expect(_voix.arrets, greaterThanOrEqualTo(arrets));
    await tester.enterText(find.byType(EditableText), 'Merci');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _attendre(tester, 1);
    expect(_voix.dits, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retour du mode vocal : lecture vocale désactivée par défaut', (
    tester,
  ) async {
    await _accueil(tester, const Size(1366, 768));
    await _vocalAvecEchange(tester);
    await tester.tap(find.text('Retour au chat'));
    await _attendre(tester, 1);
    await tester.tap(find.byTooltip('Activer la lecture vocale'));
    await tester.pump();
    await tester.tap(find.byTooltip('Reprendre le chat vocal'));
    await _attendre(tester, 1);
    // En mode vocal : pas de haut-parleur (la voix parle déjà).
    expect(find.byTooltip('Couper la lecture vocale'), findsNothing);
    await tester.tap(find.text('Retour au chat'));
    await _attendre(tester, 1);
    expect(find.byTooltip('Activer la lecture vocale'), findsOneWidget);
    final dits = _voix.dits.length;
    await tester.enterText(find.byType(EditableText), 'Bonjour');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _attendre(tester, 1);
    expect(_voix.dits, hasLength(dits));
    expect(tester.takeException(), isNull);
  });
}
