import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/export_whatsapp.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/pages/importation_whatsapp_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/importation/pont_android_importation.dart';
import 'package:ia_jarvis/services/importation/selection_export_whatsapp.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/bouton_vocal.dart';
import 'package:ia_jarvis/widgets/feuille_ajout.dart';
import 'package:ia_jarvis/widgets/fond_jarvis_anime.dart';
import 'package:ia_jarvis/widgets/importation/logo_whatsapp.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';
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

const _formats = {
  '1920x1080': Size(1920, 1080),
  '1366x768': Size(1366, 768),
  '820x1180': Size(820, 1180),
  '429x599': Size(429, 599),
  '390x844': Size(390, 844),
};

/// Page d'accueil avec des services vocaux factices.
/// Partages Android simulés : [envoyer] fait comme MainActivity.
class _Partages implements ReceptionPartages {
  final _annonces = ValueNotifier(0);
  final _file = <PartageRecu>[];

  void envoyer(PartageRecu p) {
    _file.add(p);
    _annonces.value++;
  }

  @override
  ValueListenable<int> get annonces => _annonces;
  @override
  Future<PartageRecu?> prendre() async =>
      _file.isEmpty ? null : _file.removeAt(0);
}

PartageRecu _partage(String id, String nom) => PartageRecu(
  id: id,
  fichiers: [
    FichierBrut(
      nom: nom,
      source: SourceReception.partageAndroid,
      flux: Stream.value(const [0x50, 0x4B, 0x03, 0x04]),
    ),
  ],
);

Widget _page({ReceptionPartages? partages, ConversationSession? conversation}) {
  final tts = _Tts();
  final session = VoiceSession(
    micro: _Micro(),
    reconnaissance: _Reco(),
    voix: tts,
    niveau: _Niveau(),
    reglages: VoiceSettingsService(
      tts: tts,
      stockage: StockageMemoire(),
      peripheriques: _Micros(),
    ),
  );
  return MaterialApp(
    theme: themeJarvis(),
    home: AccueilPage(
      session: session,
      pim: PimController(),
      partages: partages ?? _Partages(),
      conversation: conversation,
    ),
  );
}

Future<void> _images(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Clavier qui monte comme sur Android : l'encart grandit image après
/// image (c'est pendant cette montée que l'ancien débordement apparaissait).
Future<void> _ouvrirClavier(WidgetTester tester, double hauteur) async {
  for (var i = 1; i <= 12; i++) {
    tester.view.viewInsets = FakeViewPadding(bottom: hauteur * i / 12);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  }
  await _images(tester, 40);
}

const _claviers = {
  '390x844': (Size(390, 844), 336.0),
  '412x915': (Size(412, 915), 350.0),
  '360x800': (Size(360, 800), 320.0),
  '429x599': (Size(429, 599), 280.0),
};

String? _pressePapiers;

void _simulerPressePapiers(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (appel) async {
      if (appel.method == 'Clipboard.getData') {
        return _pressePapiers == null ? null : {'text': _pressePapiers};
      }
      return null;
    },
  );
}

void main() {
  for (final f in _formats.entries) {
    testWidgets('accueil ${f.key} : aucun débordement, barre complète', (
      tester,
    ) async {
      tester.view.physicalSize = f.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tts = _Tts();
      final session = VoiceSession(
        micro: _Micro(),
        reconnaissance: _Reco(),
        voix: tts,
        niveau: _Niveau(),
        reglages: VoiceSettingsService(
          tts: tts,
          stockage: StockageMemoire(),
          peripheriques: _Micros(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: themeJarvis(),
          home: AccueilPage(session: session, pim: PimController()),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      final ecran = Offset.zero & f.value;

      // Barre, bouton « + » et bouton vocal visibles en entier.
      final barre = tester.getRect(find.byType(LigneDeCommande));
      final plus = tester.getRect(find.byTooltip('Ajouter une conversation'));
      final vocal = tester.getRect(find.byType(BoutonVocal));
      for (final r in [barre, plus, vocal]) {
        expect(
          ecran.contains(r.topLeft) && ecran.contains(r.bottomRight),
          isTrue,
        );
      }
      expect(plus.width, greaterThanOrEqualTo(40));
      expect(vocal.width, greaterThanOrEqualTo(48));
      // Centrage vertical dans la barre, sur la page réelle.
      expect(plus.center.dy, closeTo(barre.center.dy, 0.5));
      expect(vocal.center.dy, closeTo(barre.center.dy, 0.5));
      expect(
        tester.getRect(find.byType(EditableText)).center.dy,
        closeTo(barre.center.dy - MesuresBarre.decalageOptique, 0.6),
      );
      // La salutation et la mission commencent au-dessus de la barre (la
      // police de test, plus large, ajoute des lignes : le bloc défile
      // alors au lieu de déborder).
      final mission = tester.getRect(
        find.textContaining('vous aide à comprendre'),
      );
      expect(mission.top, lessThan(barre.top - 20));
      expect(find.text('Chat vocal'), findsNothing);
    });
  }

  testWidgets('fond : fixe, aucune horloge, redessiné seulement si la '
      'mise en page change', (tester) async {
    final zone = ValueNotifier<Rect?>(null);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: FondJarvisAnime(
            zoneParticules: zone,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    // Aucun ticker, aucune image demandée : le fond ne tourne pas.
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    // La zone des particules change (clavier, mode vocal) : un dessin
    // direct, puis l'image est mémorisée, puis plus rien.
    zone.value = const Rect.fromLTWH(200, 100, 400, 400);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final c in _claviers.entries) {
    testWidgets('clavier ${c.key} : aucun débordement, barre au-dessus du '
        'clavier, sphère préservée', (tester) async {
      final (taille, clavier) = c.value;
      tester.view.physicalSize = taille;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_page());
      await _images(tester, 30);
      final sphereFermee = tester
          .getSize(find.byType(PimParticle))
          .shortestSide;
      expect(sphereFermee, greaterThan(0));

      // Focus du champ, puis montée du clavier.
      await tester.tap(find.byType(EditableText));
      await _ouvrirClavier(tester, clavier);
      expect(tester.takeException(), isNull);
      final barre = tester.getRect(find.byType(LigneDeCommande));
      expect(barre.bottom, lessThanOrEqualTo(taille.height - clavier));
      expect(barre.top, greaterThan(0));

      // Texte long (5 lignes) : toujours aucun débordement.
      await tester.enterText(
        find.byType(EditableText),
        List.filled(12, 'Une très longue conversation collée ici.').join(' '),
      );
      await _images(tester, 120);
      expect(tester.takeException(), isNull);
      final barreLongue = tester.getRect(find.byType(LigneDeCommande));
      expect(barreLongue.bottom, lessThanOrEqualTo(taille.height - clavier));
      expect(barreLongue.top, greaterThan(0));

      // Clavier refermé : retour à la composition d'origine.
      await tester.enterText(find.byType(EditableText), '');
      tester.view.viewInsets = FakeViewPadding.zero;
      await _images(tester, 300);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('téléphone : « + » ouvre la feuille, « Coller » insère le '
      'texte au curseur et garde le focus', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _simulerPressePapiers(tester);
    await tester.pumpWidget(_page());
    await _images(tester, 20);
    await tester.tap(find.byType(EditableText));
    await _ouvrirClavier(tester, 336);

    await tester.tap(find.byTooltip('Ajouter une conversation'));
    await _images(tester, 30);
    expect(find.byType(FeuilleAjout), findsOneWidget);
    expect(find.text(FeuilleAjout.titre), findsOneWidget);
    expect(find.text('Importer une conversation'), findsOneWidget);
    expect(find.text('Bientôt'), findsNothing);
    final feuille = tester.getRect(find.byType(FeuilleAjout));
    expect(feuille.bottom, lessThanOrEqualTo(844));
    expect(feuille.top, greaterThan(0));

    _pressePapiers = 'Marc : tu viens ce soir ?';
    await tester.tap(find.text('Coller une conversation'));
    await _images(tester, 40);
    expect(find.byType(FeuilleAjout), findsNothing);
    final champ = tester.widget<EditableText>(find.byType(EditableText));
    expect(champ.controller.text, 'Marc : tu viens ce soir ?');
    expect(champ.controller.selection.baseOffset, 25);
    expect(champ.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('presse-papiers vide : message discret', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _simulerPressePapiers(tester);
    _pressePapiers = null;
    await tester.pumpWidget(_page());
    await _images(tester, 20);
    await tester.tap(find.byTooltip('Ajouter une conversation'));
    await _images(tester, 30);
    await tester.tap(find.text('Coller une conversation'));
    await _images(tester, 30);
    expect(find.text(LigneDeCommande.pressePapiersVide), findsOneWidget);
    final champ = tester.widget<EditableText>(find.byType(EditableText));
    expect(champ.controller.text, isEmpty);
    await _images(tester, 200);
  });

  testWidgets('ordinateur : « + » garde le petit menu flottant', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_page());
    await _images(tester, 20);
    await tester.tap(find.byTooltip('Ajouter une conversation'));
    await _images(tester, 20);
    expect(find.byType(FeuilleAjout), findsNothing);
    expect(find.text('Coller une conversation'), findsOneWidget);
    expect(find.text('Importer une conversation'), findsOneWidget);
    expect(find.byType(LogoWhatsApp), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    // Le menu se ferme et la page d'import s'ouvre.
    await tester.tap(find.text('Importer une conversation'));
    await _images(tester, 30);
    expect(find.text('Coller une conversation'), findsNothing);
    expect(find.byType(ImportationWhatsAppPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('téléphone : « Importer une conversation » (logo WhatsApp, '
      'flèche, sans sous-titre) ouvre l’import, le retour rend l’accueil '
      'intact', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_page());
    await _images(tester, 20);
    await tester.tap(find.byTooltip('Ajouter une conversation'));
    await _images(tester, 30);

    final ligne = find.ancestor(
      of: find.text('Importer une conversation'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: ligne, matching: find.byType(LogoWhatsApp)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: ligne,
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsOneWidget,
    );
    // Aucun sous-titre : un seul texte dans la ligne.
    expect(
      find.descendant(of: ligne, matching: find.byType(Text)),
      findsOneWidget,
    );
    expect(find.text('Depuis un export WhatsApp'), findsNothing);
    // Logo, texte et flèche sur le même axe horizontal.
    final centre = tester.getCenter(find.text('Importer une conversation')).dy;
    expect(tester.getCenter(find.byType(LogoWhatsApp)).dy, closeTo(centre, 1));
    expect(
      tester.getCenter(find.byIcon(Icons.chevron_right_rounded)).dy,
      closeTo(centre, 1),
    );

    await tester.tap(find.text('Importer une conversation'));
    await _images(tester, 40);
    expect(find.byType(FeuilleAjout), findsNothing);
    expect(find.byType(ImportationWhatsAppPage), findsOneWidget);
    expect(find.text(ImportationWhatsAppPage.titre), findsOneWidget);

    await tester.tap(find.byTooltip('Retour'));
    await _images(tester, 40);
    expect(find.byType(ImportationWhatsAppPage), findsNothing);
    expect(find.byType(LigneDeCommande), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feuille « + » : jamais sous la barre de navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 48);
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_page());
    await _images(tester, 20);
    await tester.tap(find.byTooltip('Ajouter une conversation'));
    await _images(tester, 30);
    final dernier = tester.getRect(find.text('Importer une conversation'));
    expect(dernier.bottom, lessThanOrEqualTo(844 - 48));
  });

  testWidgets('partage Android : lancement à froid puis JARVIS ouvert, une '
      'seule page, la conversation reste', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final partages = _Partages();
    // Lancement à froid : le partage attend l'accueil.
    partages.envoyer(_partage('p1', 'WhatsApp Chat with Marc.zip'));
    await tester.pumpWidget(_page(partages: partages));
    await _images(tester, 40);
    expect(find.byType(ImportationWhatsAppPage), findsOneWidget);
    expect(find.text('WhatsApp Chat with Marc.zip'), findsOneWidget);

    // JARVIS déjà ouvert : nouveau partage, même page, fichier remplacé.
    partages.envoyer(_partage('p2', 'WhatsApp Chat with Léa.zip'));
    await _images(tester, 40);
    expect(find.byType(ImportationWhatsAppPage), findsOneWidget);
    expect(find.text('WhatsApp Chat with Léa.zip'), findsOneWidget);
    expect(find.text('WhatsApp Chat with Marc.zip'), findsNothing);

    // Annonce sans partage en attente (événement rejoué) : rien de plus.
    partages._annonces.value++;
    await _images(tester, 20);
    expect(find.byType(ImportationWhatsAppPage), findsOneWidget);

    // Retour : l'accueil est intact.
    await tester.tap(find.byTooltip('Retour'));
    await _images(tester, 40);
    expect(find.byType(ImportationWhatsAppPage), findsNothing);
    expect(find.byType(LigneDeCommande), findsOneWidget);

    // Partage après la fermeture : la page se rouvre.
    partages.envoyer(_partage('p3', 'chat.zip'));
    await _images(tester, 40);
    expect(find.byType(ImportationWhatsAppPage), findsOneWidget);
    expect(find.text('chat.zip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('G7 : envoi, clavier, brouillons', () {
    /// Écrit puis touche le bouton Envoyer de la barre (comme au doigt).
    Future<void> ecrireEtEnvoyer(WidgetTester tester, String texte) async {
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), texte);
      await tester.pump();
      await tester.tap(find.byType(BoutonVocal));
      await _images(tester, 20);
    }

    FocusNode focusDuChamp(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).focusNode!;

    testWidgets('Android : message accepté → clavier fermé, champ vidé', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final s = ConversationSession(delaiReflexion: Duration.zero);
      addTearDown(s.dispose);
      await tester.pumpWidget(_page(conversation: s));
      await _images(tester, 10);
      await ecrireEtEnvoyer(tester, 'Quelle heure est-il ?');
      expect(s.messages.first.texte, 'Quelle heure est-il ?');
      expect(focusDuChamp(tester).hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('ordinateur (clavier physique) : le focus reste', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final s = ConversationSession(delaiReflexion: Duration.zero);
      addTearDown(s.dispose);
      await tester.pumpWidget(_page(conversation: s));
      await _images(tester, 10);
      await ecrireEtEnvoyer(tester, 'Quelle heure est-il ?');
      // Déjà dans la conversation : le focus reste après l'envoi.
      await ecrireEtEnvoyer(tester, 'Quelle date ?');
      expect(focusDuChamp(tester).hasFocus, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('brouillon gardé par conversation, jamais dans une autre ; '
        'envoyé → effacé', (tester) async {
      final s = ConversationSession(delaiReflexion: Duration.zero);
      addTearDown(s.dispose);
      await tester.pumpWidget(_page(conversation: s));
      await _images(tester, 10);
      TextEditingController champ() =>
          tester.widget<TextField>(find.byType(TextField)).controller!;
      await ecrireEtEnvoyer(tester, 'Quelle heure est-il ?');
      final premiere = s.idCourant!;
      await tester.enterText(find.byType(TextField), 'brouillon de la 1');
      await tester.pump();
      s.effacer(); // Nouvelle conversation
      await _images(tester, 10);
      expect(champ().text, isEmpty); // jamais dans une autre conversation
      await tester.enterText(find.byType(TextField), 'Quelle date ?');
      await tester.pump();
      s.ouvrir(premiere);
      await _images(tester, 10);
      expect(champ().text, 'brouillon de la 1');
      expect(champ().selection.baseOffset, 'brouillon de la 1'.length);
      expect(s.messages.length, 2); // la restauration n'envoie rien
      // Envoyé : le brouillon n'existe plus nulle part.
      await tester.tap(find.byType(BoutonVocal));
      await _images(tester, 20);
      expect(champ().text, isEmpty);
      s.effacer();
      await _images(tester, 10);
      expect(champ().text, 'Quelle date ?'); // brouillon de la nouvelle
    });
  });

  group('Accessibilité (GH : 41, 42, 46)', () {
    Future<ConversationSession> conversation() async {
      final c = ConversationSession(delaiReflexion: Duration.zero);
      await c.envoyer('Quelle heure est-il ?');
      await c.envoyer('Merci beaucoup pour ton aide');
      return c;
    }

    for (final (nom, taille) in [
      ('390x844', const Size(390, 844)),
      ('820x1180', const Size(820, 1180)),
      ('1366x768', const Size(1366, 768)),
    ]) {
      for (final echelle in [1.0, 1.3, 1.6, 2.0]) {
        testWidgets(
          '$nom, texte ×$echelle : accueil, fil, menu sans débordement',
          (tester) async {
            tester.view.physicalSize = taille;
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = echelle;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );

            await tester.pumpWidget(_page());
            await _images(tester, 30);
            expect(tester.takeException(), isNull, reason: 'accueil');

            final c = (await tester.runAsync(conversation))!;
            await tester.pumpWidget(_page(conversation: c));
            await _images(tester, 60);
            expect(tester.takeException(), isNull, reason: 'fil');

            await tester.tap(find.byTooltip('Menu'));
            await _images(tester, 30);
            expect(tester.takeException(), isNull, reason: 'menu');
            c.dispose();
          },
        );
      }
    }

    testWidgets('redimensionnement : brouillon, focus et fil gardés', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = (await tester.runAsync(conversation))!;
      await tester.pumpWidget(_page(conversation: c));
      await _images(tester, 40);
      final champ = find.byType(EditableText);
      await tester.tap(champ);
      await tester.enterText(champ, 'Brouillon en cours\nsur deux lignes');
      await _images(tester, 10);
      for (final taille in const [
        Size(390, 844),
        Size(844, 390),
        Size(500, 700),
        Size(1920, 1080),
      ]) {
        tester.view.physicalSize = taille;
        await _images(tester, 20);
        expect(tester.takeException(), isNull, reason: '$taille');
        expect(
          tester.widget<EditableText>(champ).controller.text,
          'Brouillon en cours\nsur deux lignes',
        );
        expect(
          find.textContaining(
            'Merci beaucoup',
            findRichText: true,
            skipOffstage: false,
          ),
          findsOneWidget,
          reason: 'fil $taille',
        );
      }
      expect(tester.widget<EditableText>(champ).focusNode.hasFocus, isTrue);
      c.dispose();
    });

    testWidgets(
      'libellés partout ; « + » touchable dans la marge de la capsule',
      (tester) async {
        tester.view.physicalSize = const Size(1366, 768);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantique = tester.ensureSemantics();
        await tester.pumpWidget(_page());
        await _images(tester, 30);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        // Juste au-dessus du « + », dans la marge de la capsule : son menu
        // s'ouvre (avant : le curseur allait dans le champ).
        final plus = tester.getRect(find.byTooltip('Ajouter une conversation'));
        await tester.tapAt(Offset(plus.center.dx, plus.top - 5));
        await _images(tester, 20);
        expect(find.text('Coller une conversation'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await _images(tester, 20);

        await tester.tap(find.byTooltip('Menu'));
        await _images(tester, 30);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        // Hauteurs voulues par le design, au-dessus du minimum de 24 px
        // (WCAG 2.2) mais sous les 48 px d'Android : champ de recherche du
        // menu (40), bouton Menu (40 sur téléphone). Mesurées, pas imposées.
        expect(
          tester.getSize(find.byTooltip('Menu')).height,
          greaterThanOrEqualTo(40),
        );
        semantique.dispose();
      },
    );
  });
}
