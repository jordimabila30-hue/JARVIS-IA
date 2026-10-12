// Menu latéral : ouverture depuis la gauche, voile léger, fermetures
// (voile, ×, Échap, Retour), entrées réelles, particules PIM intactes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';
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
import 'package:ia_jarvis/widgets/conversation/signature_jarvis.dart';
import 'package:ia_jarvis/widgets/menu_lateral.dart';
import 'package:ia_jarvis/widgets/parametres/fenetre_parametres.dart';
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

Future<void> _accueil(WidgetTester tester, Size taille) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tts = _Tts();
  _pim = PimController();
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

final _panneau = find.byTooltip('Fermer le menu');

bool _ouvert(WidgetTester tester) => _panneau.evaluate().isNotEmpty;

/// Opacité actuelle du voile.
double _voile(WidgetTester tester) {
  final voiles = find.descendant(
    of: find.byType(MenuLateral),
    matching: find.byType(ColoredBox),
  );
  if (voiles.evaluate().isEmpty) return 0;
  return tester.widget<ColoredBox>(voiles.first).color.a;
}

/// Position affichée du panneau (translation comprise) : bord gauche du
/// bouton × (repère fixe dans le panneau).
double _bordPanneau(WidgetTester tester) => tester.getRect(_panneau).left;

Future<void> _ouvrir(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu'));
  await _images(tester, 25);
}

/// Champ de la barre de saisie (le menu a aussi son champ de recherche).
final _champBarre = find.descendant(
  of: find.byType(LigneDeCommande),
  matching: find.byType(EditableText),
);

void main() {
  testWidgets('le bouton menu remplace les Paramètres en haut à droite', (
    tester,
  ) async {
    await _accueil(tester, const Size(1366, 768));
    final menu = tester.getRect(find.byTooltip('Menu'));
    expect(menu.center.dx, lessThan(200));
    expect(menu.width, greaterThanOrEqualTo(44));
    // L'icône du menu est la perle JARVIS, plus grande que dans les
    // réponses, centrée et non déformée.
    final perle = find.descendant(
      of: find.byTooltip('Menu'),
      matching: find.byType(PerleJarvis),
    );
    expect(perle, findsOneWidget);
    final rPerle = tester.getRect(perle);
    expect(rPerle.width, BoutonMenu.taillePerle);
    expect(rPerle.height, rPerle.width);
    expect(rPerle.center.dx, closeTo(menu.center.dx, 0.5));
    expect(rPerle.center.dy, closeTo(menu.center.dy, 0.5));
    // Plus de bouton Paramètres sur l'accueil : il est dans le menu.
    expect(find.byTooltip('Paramètres'), findsNothing);
    expect(find.byType(MenuLateral), findsOneWidget);
    expect(_ouvert(tester), isFalse);
  });

  testWidgets('ouverture : glisse depuis la gauche, voile progressif, '
      'ralentit en fin de course', (tester) async {
    await _accueil(tester, const Size(1366, 768));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    final bords = <double>[];
    final voiles = <double>[];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      bords.add(_bordPanneau(tester));
      voiles.add(_voile(tester));
    }
    // Position affichée relative à la position ouverte (0 : ouvert).
    final fin = bords.last;
    for (var i = 0; i < bords.length; i++) {
      bords[i] -= fin;
    }
    final largeur = MenuLateral.largeurPour(1366);
    expect(bords.first, lessThan(-largeur * 0.3));
    expect(bords.last, 0);
    for (var i = 1; i < bords.length; i++) {
      expect(bords[i], greaterThanOrEqualTo(bords[i - 1]));
      expect(voiles[i], greaterThanOrEqualTo(voiles[i - 1] - 1e-6));
    }
    // Ralentit à la fin (easeOutCubic) : derniers pas plus courts.
    expect(bords[2] - bords[1], greaterThan(bords[14] - bords[13]));
    // Ouvert en ~260 ms.
    final ouvert = bords.indexWhere((b) => b == 0);
    expect(ouvert * 16, inInclusiveRange(220, 300));
    // Voile léger : l'accueil reste visible.
    expect(voiles.last, closeTo(MenuLateral.opaciteVoile, 0.005));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fermeture : voile, ×, Échap, Retour Android, symbole JARVIS', (
    tester,
  ) async {
    await _accueil(tester, const Size(1366, 768));
    Future<void> fermeParVoile() =>
        tester.tapAt(const Offset(1300, 400)).then((_) => _images(tester, 25));

    for (final (nom, fermer) in <(String, Future<void> Function())>[
      ('voile', fermeParVoile),
      (
        '×',
        () async {
          await tester.tap(_panneau);
          await _images(tester, 25);
        },
      ),
      (
        'Échap',
        () async {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _images(tester, 25);
        },
      ),
      (
        'Retour',
        () async {
          await tester.binding.handlePopRoute();
          await _images(tester, 25);
        },
      ),
      (
        'symbole JARVIS',
        () async {
          await tester.tap(find.byTooltip('Accueil JARVIS'));
          await _images(tester, 25);
        },
      ),
    ]) {
      await _ouvrir(tester);
      expect(_ouvert(tester), isTrue, reason: nom);
      await fermer();
      expect(_ouvert(tester), isFalse, reason: nom);
      expect(_voile(tester), 0, reason: nom);
      // Toujours sur l'accueil.
      expect(find.byTooltip('Menu'), findsOneWidget, reason: nom);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('fermeture inverse et douce, en ~230 ms', (tester) async {
    await _accueil(tester, const Size(1366, 768));
    await _ouvrir(tester);
    await tester.tap(_panneau);
    await tester.pump();
    final bords = <double>[];
    for (var i = 0; i < 20 && _ouvert(tester); i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (_ouvert(tester)) bords.add(_bordPanneau(tester));
    }
    expect(bords.length * 16, inInclusiveRange(180, 260));
    for (var i = 1; i < bords.length; i++) {
      expect(bords[i], lessThanOrEqualTo(bords[i - 1]));
    }
  });

  testWidgets('PIM continue : même moteur, ticker actif, aucune forme '
      'déclenchée, rien de recréé', (tester) async {
    await _accueil(tester, const Size(1366, 768));
    final etat = tester.state(find.byType(PimParticle));
    final zone = _pim.zone.value;
    final mode = _pim.mode;
    await _ouvrir(tester);
    // Les particules bougent toujours derrière le voile.
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    final avant = _pim.etalement.moyenne;
    await _images(tester, 90);
    expect(tester.state(find.byType(PimParticle)), same(etat));
    expect(_pim.zone.value, zone);
    expect(_pim.mode, mode);
    expect(_pim.phaseForme, PhaseForme.absent);
    expect(_pim.etalement.moyenne, closeTo(avant, 0.05));
    await tester.tap(_panneau);
    await _images(tester, 25);
    expect(tester.state(find.byType(PimParticle)), same(etat));
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation et texte conservés ; le voile bloque l’accueil', (
    tester,
  ) async {
    await _accueil(tester, const Size(390, 844));
    await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _images(tester, 60);
    await tester.enterText(find.byType(EditableText), 'Brouillon');
    await _images(tester, 10);

    await _ouvrir(tester);
    // Le clavier se referme, le texte reste (champ de la barre, pas la
    // recherche du menu).
    final champ = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(LigneDeCommande),
        matching: find.byType(EditableText),
      ),
    );
    expect(champ.focusNode.hasFocus, isFalse);
    expect(champ.controller.text, 'Brouillon');
    // Conversation en cours listée, avec son titre : dans « EN COURS » et
    // dans la liste JARVIS (« MES CONVERSATIONS »).
    expect(find.text('EN COURS'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MenuLateral),
        matching: find.text('Bonjour JARVIS'),
      ),
      findsNWidgets(2),
    );
    // Panneau partiel sur téléphone : l'accueil reste visible à droite.
    final bord = tester.getRect(
      find
          .ancestor(of: _panneau, matching: find.byType(FractionalTranslation))
          .first,
    );
    expect(bord.right, lessThan(390));
    // Toucher la barre derrière le voile : rien ne se passe sur l'accueil,
    // le menu se ferme.
    final barre = tester.getCenter(_champBarre);
    await tester.tapAt(Offset(380, barre.dy));
    await _images(tester, 25);
    expect(_ouvert(tester), isFalse);
    expect(
      tester.widget<EditableText>(_champBarre).focusNode.hasFocus,
      isFalse,
    );
    expect(
      tester.widget<EditableText>(_champBarre).controller.text,
      'Brouillon',
    );
    expect(_conversation.messages, hasLength(2));
    // Retour à la conversation depuis le menu (entrée « EN COURS »).
    await _ouvrir(tester);
    await tester.tap(
      find
          .descendant(
            of: find.byType(MenuLateral),
            matching: find.text('Bonjour JARVIS'),
          )
          .first,
    );
    await _images(tester, 25);
    expect(_ouvert(tester), isFalse);
    expect(_conversation.messages, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('entrées réelles : nouvelle conversation, chat vocal', (
    tester,
  ) async {
    await _accueil(tester, const Size(1366, 768));
    await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _images(tester, 60);
    expect(_conversation.vide, isFalse);
    // Pas d'entrée fictive (pas d'historique tant qu'il n'existe pas).
    await _ouvrir(tester);
    expect(find.textContaining('Historique'), findsNothing);
    await tester.tap(find.text('Nouvelle conversation'));
    await _images(tester, 40);
    expect(_ouvert(tester), isFalse);
    expect(_conversation.vide, isTrue);

    await _ouvrir(tester);
    await tester.tap(find.text('Chat vocal'));
    await _images(tester, 60);
    expect(_ouvert(tester), isFalse);
    expect(find.text('Quitter le mode vocal'), findsOneWidget);
    await tester.tap(find.text('Quitter le mode vocal'));
    await _images(tester, 60);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Paramètres depuis le menu : la fenêtre existante, toutes ses '
      'sections', (tester) async {
    await _accueil(tester, const Size(1366, 768));
    await _ouvrir(tester);
    await tester.tap(find.byTooltip('Paramètres'));
    await _images(tester, 30);
    expect(_ouvert(tester), isFalse);
    expect(find.byType(FenetreParametres), findsOneWidget);
    for (final s in ['Général', 'Chat vocal', 'Particules PIM', 'Apparence']) {
      expect(find.text(s), findsWidgets);
    }
    await tester.tap(find.text('Particules PIM'));
    await _images(tester, 10);
    expect(find.text('FORME DE JARVIS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('symbole lumineux : la perle des réponses, agrandie', (
    tester,
  ) async {
    await _accueil(tester, const Size(1366, 768));
    await _ouvrir(tester);
    // La perle du bas (le sélecteur des messageries a son propre logo).
    final perle = find.descendant(
      of: find.byTooltip('Accueil JARVIS'),
      matching: find.byType(PerleJarvis),
    );
    expect(perle, findsOneWidget);
    expect(tester.widget<PerleJarvis>(perle).taille, greaterThan(13));
    // En bas à gauche, Paramètres en bas à droite, alignés.
    final rPerle = tester.getRect(perle);
    final rParam = tester.getRect(find.byTooltip('Paramètres'));
    // Paramètres : roue dentée à contour fin.
    expect(
      find.descendant(
        of: find.byTooltip('Paramètres'),
        matching: find.byIcon(Icons.settings_outlined),
      ),
      findsOneWidget,
    );
    expect(rPerle.center.dx, lessThan(rParam.center.dx));
    expect(rPerle.center.dy, closeTo(rParam.center.dy, 1));
    expect(rPerle.bottom, greaterThan(768 - 80));
  });

  for (final s in const [
    Size(320, 568),
    Size(360, 640),
    Size(390, 844),
    Size(820, 1180),
    Size(1920, 1080),
  ]) {
    testWidgets('$s : aucun débordement, panneau adapté', (tester) async {
      await _accueil(tester, s);
      await _ouvrir(tester);
      expect(tester.takeException(), isNull);
      final panneau = tester.getRect(
        find
            .ancestor(
              of: _panneau,
              matching: find.byType(FractionalTranslation),
            )
            .first,
      );
      expect(panneau.width, MenuLateral.largeurPour(s.width));
      expect(panneau.width, lessThan(s.width));
      expect(panneau.height, s.height);
      // Redimensionnement, menu ouvert.
      tester.view.physicalSize = Size(s.height, s.width);
      await _images(tester, 10);
      expect(tester.takeException(), isNull);
    });
  }
}
