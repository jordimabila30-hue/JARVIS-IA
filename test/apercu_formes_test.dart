// Forme principale (Paramètres → Particules PIM, sans bloc « Aperçu ») et
// démonstration d'une forme par le moteur PIM (sphère → forme → sphère).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/pages/conversation_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/preferences_pim_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/bulle_utilisateur.dart';
import 'package:ia_jarvis/widgets/pim_dynamique.dart';
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

late PimController _pim;
late ConversationSession _conversation;
late PreferencesPimService _formes;
late StockageMemoire _stockage;

Future<void> _accueil(WidgetTester tester, Size taille) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tts = _Tts();
  _pim = PimController();
  _stockage = StockageMemoire();
  _formes = PreferencesPimService(stockage: _stockage);
  _conversation = ConversationSession(
    delaiReflexion: const Duration(milliseconds: 200),
  );
  await tester.pumpWidget(
    MaterialApp(
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
            delaiSauvegarde: Duration.zero,
          ),
        ),
        pim: _pim,
        conversation: _conversation,
        formesPim: _formes,
      ),
    ),
  );
  await _images(tester, 30);
}

Future<void> _images(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Démonstration d'une forme par le moteur PIM (le bouton « Voir
/// l'aperçu » des Paramètres a été retiré ; le moteur la garde).
Future<void> _voirApercu(WidgetTester tester, String forme) async {
  _pim.lancerApercu(FormePim.values.firstWhere((f) => f.libelle == forme));
  await tester.pump();
}

void main() {
  for (final (taille, nom) in [
    (const Size(1366, 768), 'ordinateur'),
    (const Size(390, 844), 'téléphone'),
  ]) {
    testWidgets('$nom : section « Forme principale », une seule forme '
        'choisie à la fois, reliée au moteur', (tester) async {
      await _accueil(tester, taille);
      // Paramètres : depuis le menu latéral.
      await tester.tap(find.byTooltip('Menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Paramètres'));
      await _images(tester, 30);
      await tester.tap(find.text('Particules PIM'));
      await _images(tester, 20);
      // Carte technique retirée : seulement le choix visuel des formes.
      expect(find.text('Particules'), findsNothing);
      expect(find.text('Autres formes'), findsNothing);
      expect(find.text('Bientôt'), findsNothing);
      expect(find.text('FORME DE JARVIS'), findsOneWidget);
      expect(find.textContaining('Par défaut'), findsNothing);
      for (final f in ['Sphère', 'Cube 3D', 'Tétraèdre 3D', 'Réacteur Arc']) {
        expect(find.text(f), findsOneWidget);
      }
      bool choisie(String f) => tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: find.text(f),
                  matching: find.byWidgetPredicate(
                    (w) => w is Semantics && w.properties.selected != null,
                  ),
                )
                .first,
          )
          .properties
          .selected!;
      // Sphère par défaut.
      expect(choisie('Sphère'), isTrue);
      expect(_pim.formePrincipale, FormePim.sphere);
      final pastille = find
          .ancestor(
            of: find.text('Réacteur Arc'),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.ensureVisible(pastille);
      await tester.tap(pastille);
      await tester.pump();
      expect(choisie('Sphère'), isFalse);
      expect(choisie('Cube 3D'), isFalse);
      expect(choisie('Tétraèdre 3D'), isFalse);
      // Réellement reliée au moteur PIM et enregistrée.
      expect(_pim.formePrincipale, FormePim.reacteur);
      expect(_formes.forme, FormePim.reacteur);
      expect(_stockage.valeur, 'reacteur');
      // Plus de bloc « Aperçu » : le choix de la forme suffit.
      expect(find.text('Voir l’aperçu'), findsNothing);
      expect(find.text('Aperçu'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (libelle, forme, mode) in [
    ('Cube 3D', FormePim.cube, ParticlePimMode.cube),
    ('Tétraèdre 3D', FormePim.tetraedre, ParticlePimMode.tetraedre),
    ('Réacteur Arc', FormePim.reacteur, ParticlePimMode.reacteur),
  ]) {
    testWidgets('« Voir l’aperçu » $libelle : accueil, sphère, forme, '
        'maintien, sphère', (tester) async {
      await _accueil(tester, const Size(1366, 768));
      await _voirApercu(tester, libelle);
      expect(_pim.apercuEnCours, isTrue);

      // 1. La sphère d'abord, telle quelle.
      expect(_pim.phaseForme, PhaseForme.absent);
      expect(_pim.mode, ParticlePimMode.idle);
      final debut = forme.preparation;
      // 2. Puis la transformation (stabilisation, formation)…
      await _images(tester, 20);
      expect(_pim.phaseForme, PhaseForme.preparation);
      expect(_pim.forme, forme);
      await _images(tester, ((debut + forme.formation) * 60).round() + 30);
      // 3. … la forme tenue environ 5 s, avec son mouvement…
      expect(_pim.phaseForme, PhaseForme.tenue);
      expect(_pim.mode, mode);
      await _images(tester, ((forme.tenue - 0.3) * 60).round());
      expect(_pim.phaseForme, PhaseForme.tenue);
      expect(_pim.etalement.maximum, lessThan(1.4));
      // 4. … puis le retour à la sphère et le fonctionnement normal.
      await _images(tester, ((forme.retour + 1.0) * 60).round());
      expect(_pim.phaseForme, PhaseForme.absent);
      expect(_pim.apercuEnCours, isFalse);
      expect(_pim.mode, ParticlePimMode.idle);
      expect(_pim.etalement.maximum, lessThan(1.1));

      // Un nouvel aperçu peut être lancé.
      await _voirApercu(tester, libelle);
      await _images(tester, 25 + 20);
      expect(_pim.apercuEnCours, isTrue);
      expect(_pim.phaseForme, PhaseForme.preparation);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('conversation et texte saisi conservés ; particules au centre '
      'pour la démonstration, puis de retour autour de la barre', (
    tester,
  ) async {
    await _accueil(tester, const Size(390, 844));
    await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _images(tester, 60);
    await tester.enterText(find.byType(EditableText), 'Brouillon à garder');
    await _images(tester, 120);
    expect(
      _pim.mode,
      isIn([ParticlePimMode.inputCalm, ParticlePimMode.inputActive]),
    );

    FocusManager.instance.primaryFocus?.unfocus();
    await _voirApercu(tester, 'Tétraèdre 3D');
    await _images(tester, 25);
    // L'accueil n'a pas été recréé : même conversation, même brouillon.
    expect(find.byType(ConversationPage), findsOneWidget);
    expect(find.byType(BulleUtilisateur), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'Brouillon à garder',
    );
    expect(
      FocusManager.instance.primaryFocus is FocusScopeNode ||
          !(tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus),
      isTrue,
    );
    // Les particules rejoignent la sphère (1 s), qui se présente, puis la
    // forme.
    expect(_pim.mode, ParticlePimMode.movingToCenter);
    await _images(tester, 60 * 3);
    expect(_pim.mode, ParticlePimMode.tetraedre);
    await _images(tester, 60 * 10);
    expect(_pim.apercuEnCours, isFalse);
    // Retour au comportement normal : autour de la barre (conversation).
    await _images(tester, 90);
    expect(_pim.mode, isNot(ParticlePimMode.idle));
    expect(_pim.mode, isNot(ParticlePimMode.movingToCenter));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'Brouillon à garder',
    );
    expect(_conversation.messages, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('interruption pendant la transformation : toucher le champ', (
    tester,
  ) async {
    await _accueil(tester, const Size(1366, 768));
    await _voirApercu(tester, 'Réacteur Arc');
    await _images(tester, 25 + 20 + 60);
    expect(_pim.phaseForme, PhaseForme.formation);
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    expect(_pim.apercuEnCours, isFalse);
    expect(_pim.phaseForme, PhaseForme.retour);
    await _images(tester, 60);
    expect(_pim.phaseForme, PhaseForme.absent);
    expect(_pim.etalement.maximum, lessThan(1.4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('interruption pendant le maintien : mode vocal, sans conflit', (
    tester,
  ) async {
    await _accueil(tester, const Size(1366, 768));
    await _voirApercu(tester, 'Tétraèdre 3D');
    await _images(tester, 25 + 20 + 60 * 4);
    expect(_pim.phaseForme, PhaseForme.tenue);
    await tester.tap(find.byTooltip('Ouvrir le chat vocal'));
    await tester.pump();
    expect(_pim.apercuEnCours, isFalse);
    await _images(tester, 70);
    expect(_pim.phaseForme, PhaseForme.absent);
    expect(_pim.etatVocal, isNotNull);
    expect(find.text('Quitter le mode vocal'), findsOneWidget);
    // Aucune forme ne revient pendant le mode vocal.
    await _images(tester, 60 * 3);
    expect(_pim.phaseForme, PhaseForme.absent);
    await tester.tap(find.text('Quitter le mode vocal'));
    await _images(tester, 60);
    expect(tester.takeException(), isNull);
  });

  testWidgets('écrire ou rouvrir les Paramètres annule l’aperçu', (
    tester,
  ) async {
    await _accueil(tester, const Size(1366, 768));
    await _voirApercu(tester, 'Cube 3D');
    await _images(tester, 25 + 30);
    expect(_pim.apercuEnCours, isTrue);
    // Paramètres : depuis le menu latéral.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Paramètres'));
    await tester.pump();
    expect(_pim.apercuEnCours, isFalse);
    await tester.tapAt(const Offset(5, 5)); // fermer (fond)
    await _images(tester, 60);

    _pim.lancerApercu(FormePim.cube);
    // Un seul aperçu à la fois.
    expect(_pim.lancerApercu(FormePim.reacteur), isFalse);
    await _images(tester, 30);
    expect(_pim.apercuEnCours, isTrue);
    await tester.enterText(find.byType(EditableText), 'a');
    await tester.pump();
    expect(_pim.apercuEnCours, isFalse);
    expect(tester.takeException(), isNull);
    // Minuteries de la fenêtre (indicateur « Enregistré ») écoulées.
    await _images(tester, 60 * 4);
  });

  testWidgets('la rareté automatique reste inchangée', (tester) async {
    // Paramètres d'apparition d'origine.
    expect(PimDynamiqueReglages.reposAvantCubeMin, 30);
    expect(PimDynamiqueReglages.reposAvantCubeMax, 60);
    expect(PimDynamiqueReglages.probabiliteCube, 0.02);
    expect(PimDynamiqueReglages.recuperationCube, 180);
    // Sans aperçu, aucune forme avant 30 s de repos.
    await _accueil(tester, const Size(1366, 768));
    for (var i = 0; i < 29; i++) {
      await _images(tester, 60);
      expect(_pim.phaseForme, PhaseForme.absent);
    }
  });
}
