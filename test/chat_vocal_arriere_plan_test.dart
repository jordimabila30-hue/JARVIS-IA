// Bouton vocal : capsule sombre (aucun chat vocal) ou bleu-violet (chat
// vocal reprenable en arrière-plan, micro coupé), même pendant la saisie.

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

/// Reconnaissance factice : compte les écoutes, laisse le test « dire »
/// une phrase.
class _Reco implements SpeechRecognitionService {
  void Function(String)? phrase;
  int ecoutes = 0;
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
  Future<void> annuler() async {}
}

class _Voix implements TtsService {
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
    surDebut?.call();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return ResultatParole.lue;
  }

  @override
  Future<void> arreter() async {}
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
late _Niveau _niveau;
late VoiceSession _session;
late ConversationSession _conversation;

Future<void> _accueil(WidgetTester tester, Size taille) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _reco = _Reco();
  _niveau = _Niveau();
  final voix = _Voix();
  _session = VoiceSession(
    micro: _Micro(),
    reconnaissance: _reco,
    voix: voix,
    niveau: _niveau,
    reglages: VoiceSettingsService(
      tts: voix,
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

/// Couleurs de la capsule du bouton vocal de la barre.
List<Color> _capsule(WidgetTester tester) {
  final boite = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byType(LigneDeCommande),
          matching: find.byType(AnimatedContainer),
        )
        .last,
  );
  return ((boite.decoration! as BoxDecoration).gradient! as LinearGradient)
      .colors;
}

bool _bleuViolet(WidgetTester tester) {
  final c = _capsule(tester);
  return c.first == BoutonVocal.degradeArrierePlan.first ||
      c.first == BoutonVocal.degradeArrierePlanEclaire.first;
}

/// Mode vocal : ouvre, dit [phrases], puis « Retour au chat » (le chat
/// vocal passe en arrière-plan).
Future<void> _chatVocal(WidgetTester tester, List<String> phrases) async {
  await tester.tap(find.byType(BoutonVocal).last);
  await _attendre(tester, 1);
  for (final p in phrases) {
    _reco.phrase!(p);
    await _attendre(tester, 3);
  }
  await tester.tap(find.text('Retour au chat'));
  await _attendre(tester, 1);
}

void main() {
  group('Bouton seul', () {
    Future<void> afficher(
      WidgetTester tester, {
      required bool arrierePlan,
      bool envoi = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: BoutonVocal(
              onPressed: () {},
              libelle: 'test',
              envoi: envoi,
              chatEnArrierePlan: arrierePlan,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    List<Color> couleurs(WidgetTester tester) =>
        ((tester
                            .widget<AnimatedContainer>(
                              find.byType(AnimatedContainer).first,
                            )
                            .decoration!
                        as BoxDecoration)
                    .gradient!
                as LinearGradient)
            .colors;

    testWidgets('capsule sombre sans chat vocal, bleu-violet sinon', (
      tester,
    ) async {
      await afficher(tester, arrierePlan: false);
      final sombre = couleurs(tester);
      expect(sombre.first.computeLuminance(), lessThan(0.05));
      await afficher(tester, arrierePlan: true);
      expect(couleurs(tester), BoutonVocal.degradeArrierePlan);
      // Bleu doux en haut, violet en bas : ni noir, ni bleu agressif.
      final bleu = HSVColor.fromColor(BoutonVocal.degradeArrierePlan.first);
      final violet = HSVColor.fromColor(BoutonVocal.degradeArrierePlan.last);
      expect(bleu.hue, inInclusiveRange(225, 245));
      expect(violet.hue, inInclusiveRange(250, 275));
      expect(bleu.saturation, lessThan(0.6));
      // Icône vocale toujours visible.
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    });

    testWidgets('envoi : la flèche remplace l’onde, la capsule reste '
        'bleu-violet', (tester) async {
      await afficher(tester, arrierePlan: true, envoi: true);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(couleurs(tester), BoutonVocal.degradeArrierePlan);
      await afficher(tester, arrierePlan: false, envoi: true);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(couleurs(tester).first.computeLuminance(), lessThan(0.05));
    });

    testWidgets('transition douce (≤ 220 ms), sans débordement', (
      tester,
    ) async {
      await afficher(tester, arrierePlan: false);
      await afficher(tester, arrierePlan: true);
      final c = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer).first,
      );
      expect(c.duration.inMilliseconds, lessThanOrEqualTo(220));
      expect(tester.takeException(), isNull);
    });
  });

  for (final (taille, nom) in [
    (const Size(1366, 768), 'ordinateur'),
    (const Size(390, 844), 'téléphone'),
  ]) {
    testWidgets('$nom : ouvrir, retour au chat (arrière-plan), écrire et '
        'envoyer, '
        'reprendre avec le contexte', (tester) async {
      await _accueil(tester, taille);
      // 1. Aucun chat vocal : capsule sombre, « Ouvrir ».
      expect(_bleuViolet(tester), isFalse);
      expect(find.byTooltip('Ouvrir le chat vocal'), findsOneWidget);

      // 2-3. Chat vocal avec un échange, puis retour au mode écrit.
      await _chatVocal(tester, ['Je m’appelle Jordi']);
      expect(_session.reprenable, isTrue);
      expect(_session.actif, isFalse); // micro et voix coupés
      // 4-5. Capsule bleu-violet, « Reprendre ».
      await _attendre(tester, 0.3);
      expect(_bleuViolet(tester), isTrue);
      expect(find.byTooltip('Reprendre le chat vocal'), findsOneWidget);

      // 8-10. Saisie : la flèche d'envoi, capsule toujours bleu-violet,
      // aucun micro ouvert.
      final ecoutes = _reco.ecoutes;
      final niveaux = _niveau.demarrages;
      await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
      await _attendre(tester, 0.3);
      expect(find.byTooltip('Envoyer le message'), findsOneWidget);
      expect(_bleuViolet(tester), isTrue);
      await tester.tap(find.byTooltip('Envoyer le message'));
      await _attendre(tester, 1);
      // Une seule conversation : l'échange vocal puis l'échange écrit.
      expect(_conversation.messages, hasLength(4));
      expect(_conversation.messages[0].texte, 'Je m’appelle Jordi');
      expect(_conversation.messages[0].vocal, isTrue);
      expect(_conversation.messages[1].vocal, isTrue);
      expect(_conversation.messages[2].vocal, isFalse);
      expect(_reco.ecoutes, ecoutes);
      expect(_niveau.demarrages, niveaux);
      expect(_session.actif, isFalse);
      expect(_bleuViolet(tester), isTrue);

      // 6-7. Reprise : le mode vocal revient, le contexte aussi.
      await tester.tap(find.byTooltip('Reprendre le chat vocal'));
      await _attendre(tester, 1);
      expect(find.text('Quitter le mode vocal'), findsOneWidget);
      expect(_session.actif, isTrue);
      expect(_session.reprenable, isFalse);
      _reco.phrase!('Comment je m’appelle ?');
      await _attendre(tester, 3);
      expect(_session.reponse, contains('Jordi'));
      await tester.tap(find.text('Retour au chat'));
      await _attendre(tester, 1);
      expect(_bleuViolet(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('retour au chat sans avoir parlé : rien à reprendre', (
    tester,
  ) async {
    await _accueil(tester, const Size(1366, 768));
    await _chatVocal(tester, []);
    expect(_session.reprenable, isFalse);
    expect(_bleuViolet(tester), isFalse);
    expect(find.byTooltip('Ouvrir le chat vocal'), findsOneWidget);
  });

  testWidgets('« Au revoir JARVIS » termine le chat vocal', (tester) async {
    await _accueil(tester, const Size(1366, 768));
    await tester.tap(find.byType(BoutonVocal).last);
    await _attendre(tester, 1);
    _reco.phrase!('Bonjour');
    await _attendre(tester, 3);
    _reco.phrase!('Au revoir JARVIS');
    await _attendre(tester, 4);
    expect(find.text('Quitter le mode vocal'), findsNothing);
    expect(_session.reprenable, isFalse);
    expect(_bleuViolet(tester), isFalse);
  });

  testWidgets('nouvelle conversation : le chat vocal se termine, contexte '
      'oublié', (tester) async {
    await _accueil(tester, const Size(1366, 768));
    await _chatVocal(tester, ['Je m’appelle Jordi']);
    await tester.enterText(find.byType(EditableText), 'Bonjour');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _attendre(tester, 1);
    expect(_bleuViolet(tester), isTrue);
    await tester.tap(find.byTooltip('Nouvelle conversation'));
    await _attendre(tester, 1);
    expect(_session.reprenable, isFalse);
    await _attendre(tester, 0.3);
    expect(_bleuViolet(tester), isFalse);
    // Nouveau chat vocal : le prénom n'est plus connu.
    await tester.tap(find.byTooltip('Ouvrir le chat vocal'));
    await _attendre(tester, 1);
    _reco.phrase!('Comment je m’appelle ?');
    await _attendre(tester, 3);
    expect(_session.reponse, isNot(contains('Jordi')));
    await tester.tap(find.text('Quitter le mode vocal'));
    await _attendre(tester, 1);
    expect(tester.takeException(), isNull);
  });
}
