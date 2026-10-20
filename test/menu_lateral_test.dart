// Menu latéral : ouverture depuis la gauche (bouton ou glissement depuis le
// bord), voile léger, fermetures (voile, ×, Échap, Retour, glissement),
// avatar du compte, entrées réelles, particules PIM intactes.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/models/authentification/utilisateur_auth.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/authentification/auth_repository.dart';
import 'package:ia_jarvis/services/authentification/auth_service.dart';
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
import 'package:ia_jarvis/widgets/menu/avatar_compte.dart';
import 'package:ia_jarvis/widgets/menu_lateral.dart';
import 'package:ia_jarvis/widgets/parametres/fenetre_parametres.dart';
import 'package:ia_jarvis/widgets/parametres/panneau_compte.dart';
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

/// Dépôt de comptes de test : aucun serveur, la session change quand le
/// test l’annonce ([annoncer]).
class _Comptes extends AuthRepositoryNonConfigure {
  _Comptes();

  final _flux = StreamController<UtilisateurAuth?>.broadcast();

  void annoncer(UtilisateurAuth? u) => _flux.add(u);

  @override
  Stream<UtilisateurAuth?> get changements => _flux.stream;
}

late PimController _pim;
late ConversationSession _conversation;

Future<void> _accueil(
  WidgetTester tester,
  Size taille, {
  AuthService? auth,
}) async {
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
        auth: auth,
      ),
    ),
  );
  await _images(tester, 30);
}

final _avatar = find.byKey(const ValueKey('avatar-compte'));

/// Glissement au doigt, pas à pas, depuis [depart].
Future<TestGesture> _glisser(
  WidgetTester tester,
  Offset depart,
  List<double> pas, {
  PointerDeviceKind type = PointerDeviceKind.touch,
}) async {
  final geste = await tester.startGesture(depart, kind: type);
  for (final dx in pas) {
    await geste.moveBy(Offset(dx, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return geste;
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

  testWidgets('fermeture : voile, ×, Échap, Retour Android, glissement', (
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
        'glissement vers la gauche',
        () async {
          final geste = await _glisser(tester, const Offset(1000, 400), [
            for (var i = 0; i < 12; i++) -20,
          ]);
          await geste.up();
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
    for (final s in ['Général', 'Chat vocal', 'Particules PIM']) {
      expect(find.text(s), findsWidgets);
    }
    await tester.tap(find.text('Particules PIM'));
    await _images(tester, 10);
    expect(find.text('FORME DE JARVIS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('Glissement (téléphone)', () {
    const ecran = Size(390, 844);

    testWidgets('depuis le bord gauche : le panneau suit le doigt, le voile '
        'aussi ; relâché au-delà du seuil, il finit de s’ouvrir', (
      tester,
    ) async {
      await _accueil(tester, ecran);
      final geste = await _glisser(tester, const Offset(6, 500), [30, 30, 30]);
      // Suit le doigt (moins la tolérance de départ du geste).
      final bord1 = _bordPanneau(tester);
      final voile1 = _voile(tester);
      expect(_ouvert(tester), isTrue);
      await geste.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_bordPanneau(tester) - bord1, closeTo(40, 0.5));
      expect(_voile(tester), greaterThan(voile1));
      // Voile proportionnel à la position.
      final t =
          tester
              .widget<FractionalTranslation>(
                find
                    .ancestor(
                      of: _panneau,
                      matching: find.byType(FractionalTranslation),
                    )
                    .first,
              )
              .translation
              .dx +
          1;
      expect(t, inExclusiveRange(0.2, 0.6));
      expect(_voile(tester), closeTo(MenuLateral.opaciteVoile * t, 0.01));
      // Lent, au-delà de 35 % : ouvert.
      await geste.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await geste.up();
      final images = <double>[];
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        images.add(_bordPanneau(tester));
      }
      final ouvert = images.indexWhere((b) => b == images.last);
      expect(
        ouvert * 16,
        lessThanOrEqualTo(MenuLateral.dureeGesteMax.inMilliseconds + 16),
      );
      expect(_voile(tester), closeTo(MenuLateral.opaciteVoile, 0.005));
      // Retour Android : le menu est bien ouvert pour la page.
      await tester.binding.handlePopRoute();
      await _images(tester, 25);
      expect(_ouvert(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('court et lent : revient fermé ; lancer rapide : ouvert', (
      tester,
    ) async {
      await _accueil(tester, ecran);
      var geste = await _glisser(tester, const Offset(6, 500), [20, 20, 20]);
      await tester.pump(const Duration(milliseconds: 300));
      await geste.up();
      await _images(tester, 25);
      expect(_ouvert(tester), isFalse);
      expect(_voile(tester), 0);

      // Même petite distance, mais lancée : s'ouvre.
      await tester.flingFrom(const Offset(6, 500), const Offset(80, 0), 1500);
      await _images(tester, 25);
      expect(_ouvert(tester), isTrue);
      expect(_voile(tester), closeTo(MenuLateral.opaciteVoile, 0.005));
      // Lancer vers la gauche sur le panneau (en-tête) : fermé.
      await tester.flingFrom(
        Offset(120, tester.getCenter(_panneau).dy),
        const Offset(-60, 0),
        1500,
      );
      await _images(tester, 25);
      expect(_ouvert(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('geste inversé ou interrompu : l’état suit la position', (
      tester,
    ) async {
      await _accueil(tester, ecran);
      // Ouvre à moitié puis revient : fermé.
      var geste = await _glisser(tester, const Offset(6, 500), [
        for (var i = 0; i < 8; i++) 25,
        for (var i = 0; i < 7; i++) -25,
      ]);
      await tester.pump(const Duration(milliseconds: 300));
      await geste.up();
      await _images(tester, 25);
      expect(_ouvert(tester), isFalse);
      // Annulé en cours (appel, système) : position la plus proche.
      geste = await _glisser(tester, const Offset(6, 500), [
        for (var i = 0; i < 10; i++) 25,
      ]);
      await tester.pump(const Duration(milliseconds: 300));
      await geste.cancel();
      await _images(tester, 25);
      expect(_ouvert(tester), isTrue);
      expect(_voile(tester), closeTo(MenuLateral.opaciteVoile, 0.005));
      // Fermeture à moitié puis retour vers la droite : reste ouvert.
      geste = await _glisser(tester, const Offset(300, 400), [
        for (var i = 0; i < 4; i++) -20,
        for (var i = 0; i < 4; i++) 20,
      ]);
      await tester.pump(const Duration(milliseconds: 300));
      await geste.up();
      await _images(tester, 25);
      expect(_ouvert(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loin du bord, vertical, ou à la souris : rien ne s’ouvre ; '
        'un toucher près du bord atteint l’accueil', (tester) async {
      await _accueil(tester, ecran);
      var geste = await _glisser(tester, const Offset(150, 500), [
        for (var i = 0; i < 8; i++) 30,
      ]);
      await geste.up();
      await _images(tester, 25);
      expect(_ouvert(tester), isFalse);

      geste = await tester.startGesture(const Offset(6, 400));
      for (var i = 0; i < 8; i++) {
        await geste.moveBy(const Offset(2, 30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await geste.up();
      await _images(tester, 25);
      expect(_ouvert(tester), isFalse);

      geste = await _glisser(tester, const Offset(6, 500), [
        for (var i = 0; i < 8; i++) 30,
      ], type: PointerDeviceKind.mouse);
      await geste.up();
      await _images(tester, 25);
      expect(_ouvert(tester), isFalse);

      // La bande du bord laisse passer les touchers : le bouton menu (en
      // haut à gauche) répond toujours.
      expect(
        tester.getRect(find.byTooltip('Menu')).left,
        lessThan(MenuLateral.zoneBord),
      );
      await tester.tapAt(
        Offset(
          MenuLateral.zoneBord - 4,
          tester.getCenter(find.byTooltip('Menu')).dy,
        ),
      );
      await _images(tester, 25);
      expect(_ouvert(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('réduction des animations : état final aussitôt', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _accueil(tester, ecran);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_voile(tester), closeTo(MenuLateral.opaciteVoile, 0.005));
      final geste = await _glisser(tester, const Offset(300, 400), [
        -40,
        -40,
        -40,
        -40,
      ]);
      await tester.pump(const Duration(milliseconds: 300));
      await geste.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_ouvert(tester), isFalse);
    });
  });

  group('Avatar du compte', () {
    testWidgets('téléphone : l’avatar ouvre directement la page Compte, '
        'Retour mène à la liste', (tester) async {
      final comptes = _Comptes();
      final auth = AuthService(comptes);
      addTearDown(auth.dispose);
      await _accueil(tester, const Size(390, 844), auth: auth);
      comptes.annoncer(
        const UtilisateurAuth(
          identifiant: 'u1',
          email: 'j@exemple.fr',
          nom: 'Jordi',
        ),
      );
      await _images(tester, 3);
      await _ouvrir(tester);
      await tester.tap(_avatar);
      await _images(tester, 30);
      expect(find.byType(PanneauCompte), findsOneWidget);
      expect(find.text('Particules PIM'), findsNothing); // pas la liste
      await tester.binding.handlePopRoute();
      await _images(tester, 30);
      expect(find.byType(PanneauCompte), findsNothing);
      expect(find.text('Particules PIM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('initiale : nom affiché, sinon e-mail, jamais un symbole', () {
      expect(initialeCompte(nom: 'Jordi', email: 'x@y.fr'), 'J');
      expect(initialeCompte(nom: 'ben', email: 'x@y.fr'), 'B');
      expect(initialeCompte(nom: ' Marie ', email: null), 'M');
      expect(initialeCompte(nom: 'Élodie'), 'É');
      expect(initialeCompte(nom: null, email: 'alex@exemple.fr'), 'A');
      expect(initialeCompte(nom: '  ', email: '_zoe@exemple.fr'), 'Z');
      expect(initialeCompte(nom: null, email: null), isNull);
    });

    testWidgets('en bas à gauche, Paramètres à droite ; l’initiale suit le '
        'compte ; appui : section Compte', (tester) async {
      final comptes = _Comptes();
      final auth = AuthService(comptes);
      addTearDown(auth.dispose);
      await _accueil(tester, const Size(1366, 768), auth: auth);
      await _ouvrir(tester);
      // Sans compte : silhouette neutre, aucune lettre.
      expect(_avatar, findsOneWidget);
      expect(
        find.descendant(
          of: _avatar,
          matching: find.byIcon(Icons.person_outline_rounded),
        ),
        findsOneWidget,
      );
      // Plus de symbole JARVIS en bas du panneau.
      expect(find.byTooltip('Accueil JARVIS'), findsNothing);

      comptes.annoncer(
        const UtilisateurAuth(
          identifiant: 'u1',
          email: 'jordi@exemple.fr',
          nom: 'Jordi',
        ),
      );
      await _images(tester, 3);
      expect(
        find.descendant(of: _avatar, matching: find.text('J')),
        findsOneWidget,
      );
      // L'adresse n'est jamais affichée ni annoncée.
      expect(find.textContaining('@'), findsNothing);
      expect(find.byTooltip('Compte de Jordi'), findsOneWidget);

      comptes.annoncer(
        const UtilisateurAuth(
          identifiant: 'u2',
          email: 'ben@exemple.fr',
          nom: 'Ben',
        ),
      );
      await _images(tester, 3);
      expect(
        find.descendant(of: _avatar, matching: find.text('B')),
        findsOneWidget,
      );
      comptes.annoncer(
        const UtilisateurAuth(identifiant: 'u3', email: 'marie@exemple.fr'),
      );
      await _images(tester, 3);
      expect(
        find.descendant(of: _avatar, matching: find.text('M')),
        findsOneWidget,
      );

      // Alignés en bas, avatar à gauche, Paramètres (roue fine) à droite.
      final rAvatar = tester.getRect(_avatar);
      final rParam = tester.getRect(find.byTooltip('Paramètres'));
      expect(
        find.descendant(
          of: find.byTooltip('Paramètres'),
          matching: find.byIcon(Icons.settings_outlined),
        ),
        findsOneWidget,
      );
      expect(rAvatar.center.dx, lessThan(rParam.center.dx));
      expect(rAvatar.center.dy, closeTo(rParam.center.dy, 1));
      expect(rAvatar.bottom, greaterThan(768 - 80));
      expect(rAvatar.width, AvatarCompte.taille);
      // Zone tactile de 48 px.
      expect(
        tester
            .getSize(
              find.ancestor(of: _avatar, matching: find.byType(SizedBox)).first,
            )
            .width,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(_avatar);
      await _images(tester, 30);
      expect(_ouvert(tester), isFalse);
      expect(find.byType(FenetreParametres), findsOneWidget);
      expect(
        tester
            .widget<FenetreParametres>(find.byType(FenetreParametres))
            .sectionInitiale,
        SectionParametres.compte,
      );
      expect(
        tester
            .widget<FenetreParametres>(find.byType(FenetreParametres))
            .ouvrirSection,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
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
