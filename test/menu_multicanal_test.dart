// Menu latéral multicanal : sélecteur des messageries (vrais logos),
// listes qui glissent, défilement gardé par source, recherche, épingles,
// ouverture des conversations, sans régression du panneau existant.
// Données de démonstration : test/fixtures/ uniquement.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/conversations/source_conversation.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversations/conversations_multicanal.dart';
import 'package:ia_jarvis/services/conversations/epingles_conversations.dart';
import 'package:ia_jarvis/services/conversations/fournisseur_conversations.dart';
import 'package:ia_jarvis/services/conversations/fournisseur_jarvis.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/utils/local_date_time.dart';
import 'package:ia_jarvis/widgets/menu/ligne_conversation.dart';
import 'package:ia_jarvis/widgets/menu/section_conversations.dart';
import 'package:ia_jarvis/widgets/menu/selecteur_sources.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

import 'fixtures/conversations_demo.dart';

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
late ConversationsMulticanal _multicanal;
late FournisseurDemo _whatsapp;
late FournisseurDemo _gmail;

Future<void> _accueil(
  WidgetTester tester,
  Size taille, {
  double echelleTexte = 1,
}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Taille du texte choisie dans les réglages du téléphone.
  tester.platformDispatcher.textScaleFactorTestValue = echelleTexte;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final tts = _Tts();
  _pim = PimController();
  _conversation = ConversationSession(
    delaiReflexion: const Duration(milliseconds: 200),
  );
  _whatsapp = FournisseurDemo(SourceConversation.whatsapp, whatsappDemo());
  _gmail = FournisseurDemo(SourceConversation.gmail, gmailDemo());
  _multicanal = ConversationsMulticanal(
    fournisseurs: [
      FournisseurJarvis(_conversation),
      _whatsapp,
      _gmail,
      FournisseurNonIntegre(SourceConversation.messenger),
      FournisseurNonIntegre(SourceConversation.instagram),
    ],
    epingles: EpinglesConversations(stockage: StockageMemoire()),
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
        multicanal: _multicanal,
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

Future<void> _ouvrir(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu'));
  await _images(tester, 25);
}

bool _menuOuvert() => find.byTooltip('Fermer le menu').evaluate().isNotEmpty;

/// Onglet d'une source dans le sélecteur.
Finder _onglet(SourceConversation s) => find.descendant(
  of: find.byType(SelecteurSources),
  matching: find.text(s.libelle),
);

Future<void> _choisir(WidgetTester tester, SourceConversation s) async {
  // Fait défiler la rangée jusqu'au logo s'il dépasse (comme au doigt).
  await tester.ensureVisible(_onglet(s));
  await tester.pump();
  await tester.tap(_onglet(s));
  await _images(tester, 20);
}

Future<void> _envoyer(WidgetTester tester, String texte) async {
  await tester.enterText(find.byType(EditableText).first, texte);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await _images(tester, 40);
}

Finder get _lignes => find.byType(LigneConversation);

double _gauche(WidgetTester tester, String texte) =>
    tester.getRect(find.text(texte).first).left;

void main() {
  group('Modèle et tri', () {
    late ConversationsMulticanal m;
    late StockageMemoire stockage;

    setUp(() {
      stockage = StockageMemoire();
      m = ConversationsMulticanal(
        fournisseurs: [
          FournisseurDemo(SourceConversation.whatsapp, whatsappDemo()),
          FournisseurDemo(SourceConversation.gmail, gmailDemo()),
          FournisseurNonIntegre(SourceConversation.messenger),
        ],
        epingles: EpinglesConversations(stockage: stockage),
      );
    });
    tearDown(() => m.dispose());

    test('sources fournies dans l’ordre ; plus récente d’abord', () {
      expect(m.sources, [
        SourceConversation.whatsapp,
        SourceConversation.gmail,
        SourceConversation.messenger,
      ]);
      final l = m.liste(SourceConversation.whatsapp);
      expect(l, hasLength(40));
      expect(l.first.titre, 'Tony Stark');
      expect(l[1].titre, 'Contact 1');
      expect(l.last.titre, 'Contact 39');
    });

    test('19-21. épinglées d’abord, ordre stable, jamais mélangées, '
        'sauvegardées', () async {
      final wa = m.liste(SourceConversation.whatsapp);
      m.epingles.basculer(wa[10]); // Contact 10
      m.epingles.basculer(wa[20]); // Contact 20, épinglée en dernier
      var l = m.liste(SourceConversation.whatsapp);
      expect(l.take(3).map((c) => c.titre), [
        'Contact 20',
        'Contact 10',
        'Tony Stark',
      ]);
      // Même identifiant dans Gmail : la conversation Gmail reste à part.
      final tonyWa = l.firstWhere((c) => c.id == 'wa-tony');
      m.epingles.basculer(tonyWa);
      final gm = m.liste(SourceConversation.gmail);
      expect(gm.map((c) => c.titre), [
        'Pepper Potts',
        'Équipe Stark Industries',
        'Happy Hogan',
      ]);
      expect(m.epingles.estEpinglee(gm.last), isFalse);
      // Désépingler : retour à sa place chronologique.
      l = m.liste(SourceConversation.whatsapp);
      m.epingles.basculer(l.firstWhere((c) => c.titre == 'Contact 20'));
      l = m.liste(SourceConversation.whatsapp);
      expect(l.take(3).map((c) => c.titre), [
        'Tony Stark',
        'Contact 10',
        'Contact 1',
      ]);
      // Relues par un nouveau service (réouverture de l'application).
      await Future<void>.delayed(Duration.zero);
      final relues = EpinglesConversations(stockage: stockage);
      await relues.charger();
      expect(relues.estEpinglee(tonyWa), isTrue);
      expect(relues.estEpinglee(gm.last), isFalse);
      relues.dispose();
    });

    test('14. recherche : titre ou aperçu, sans casse ni accents, une '
        'source à la fois', () {
      expect(
        m
            .liste(SourceConversation.gmail, requete: 'equipe')
            .map((c) => c.titre),
        ['Équipe Stark Industries'],
      );
      expect(
        m.liste(SourceConversation.gmail, requete: 'CONSEIL').single.titre,
        'Pepper Potts',
      );
      expect(m.liste(SourceConversation.gmail, requete: 'Tony'), isEmpty);
      expect(
        m.liste(SourceConversation.whatsapp, requete: 'tony'),
        hasLength(1),
      );
    });

    test('changer de source remet la recherche à zéro', () {
      m.recherche.value = 'tony';
      m.choisir(SourceConversation.gmail);
      expect(m.selection.value, SourceConversation.gmail);
      expect(m.recherche.value, '');
    });

    test('22. messagerie non intégrée : vide, rien à ouvrir', () {
      expect(m.liste(SourceConversation.messenger), isEmpty);
      final f = FournisseurNonIntegre(SourceConversation.instagram);
      expect(f.ouvrir('x'), isFalse);
      f.dispose();
    });

    test('date courte', () {
      final n = DateTime(2026, 10, 11, 20);
      expect(dateCourte(DateTime(2026, 10, 11, 18, 42), n), '18:42');
      expect(dateCourte(DateTime(2026, 10, 10, 9), n), 'Hier');
      expect(dateCourte(DateTime(2026, 10, 7, 9), n), 'mer.');
      expect(dateCourte(DateTime(2026, 9, 12), n), '12/09');
      expect(dateCourte(DateTime(2025, 9, 12), n), '12/09/25');
    });
  });

  group('Conversations JARVIS réelles', () {
    test('nouvelle conversation : l’ancienne est gardée et rouvrable avec '
        'son contexte', () async {
      final s = ConversationSession(delaiReflexion: Duration.zero);
      final f = FournisseurJarvis(s);
      await s.envoyer('Je m’appelle Jordi');
      expect(f.conversations.single.titre, 'Je m’appelle Jordi');
      expect(f.conversations.single.ouverte, isTrue);
      final premiere = s.idCourant!;
      s.effacer();
      expect(s.messages, isEmpty);
      expect(f.conversations.single.id, premiere);
      expect(f.conversations.single.ouverte, isFalse);
      // Nouvelle conversation : le prénom est oublié.
      await s.envoyer('Comment je m’appelle ?');
      expect(s.messages.last.texte, isNot(contains('Jordi')));
      final seconde = s.idCourant!;
      // Reprise : messages et contexte reviennent.
      expect(f.ouvrir(premiere), isTrue);
      expect(s.idCourant, premiere);
      expect(s.messages.first.texte, 'Je m’appelle Jordi');
      await s.envoyer('Comment je m’appelle ?');
      expect(s.messages.last.texte, contains('Jordi'));
      // L'autre est gardée à son tour.
      expect(f.conversations.map((c) => c.id), [premiere, seconde]);
      expect(f.ouvrir('inconnue'), isFalse);
      f.dispose();
      s.dispose();
    });
  });

  group('Suppression (données)', () {
    test('JARVIS : conversation mise de côté ou affichée, réellement '
        'retirée de la session ; épingle retirée', () async {
      final s = ConversationSession(delaiReflexion: Duration.zero);
      final stockage = StockageMemoire();
      final m = ConversationsMulticanal(
        fournisseurs: [FournisseurJarvis(s)],
        epingles: EpinglesConversations(stockage: stockage),
      );
      await s.envoyer('Première');
      final premiere = s.idCourant!;
      s.effacer();
      await s.envoyer('Seconde');
      final seconde = s.idCourant!;
      var l = m.liste(SourceConversation.jarvis);
      expect(l, hasLength(2));
      // Mise de côté et épinglée : supprimée, épingle comprise.
      final ancienne = l.firstWhere((c) => c.id == premiere);
      m.epingles.basculer(ancienne);
      expect(await m.supprimer(ancienne), isTrue);
      expect(m.epingles.estEpinglee(ancienne), isFalse);
      expect(s.archives, isEmpty);
      expect(s.ouvrir(premiere), isFalse);
      // Affichée : l'accueil revient vide, sans la mettre de côté.
      final courante = m.liste(SourceConversation.jarvis).single;
      expect(courante.id, seconde);
      expect(await m.supprimer(courante), isTrue);
      expect(s.messages, isEmpty);
      expect(s.idCourant, isNull);
      expect(s.archives, isEmpty);
      expect(m.liste(SourceConversation.jarvis), isEmpty);
      // Inconnue : rien.
      expect(await m.supprimer(courante), isFalse);
      // L'épingle supprimée n'est plus enregistrée.
      await Future<void>.delayed(Duration.zero);
      final relues = EpinglesConversations(stockage: stockage);
      await relues.charger();
      expect(relues.estEpinglee(ancienne), isFalse);
      relues.dispose();
      m.dispose();
      s.dispose();
    });

    test(
      'réponse en préparation : n’arrive pas après la suppression',
      () async {
        final s = ConversationSession(
          delaiReflexion: const Duration(milliseconds: 50),
        );
        final envoi = s.envoyer('Bonjour');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(s.supprimer(s.idCourant!), isTrue);
        await envoi;
        expect(s.messages, isEmpty);
        s.dispose();
      },
    );

    test('messagerie non intégrée : rien à supprimer, aucun appel externe', () {
      final f = FournisseurNonIntegre(SourceConversation.gmail);
      expect(f.supprimer('x'), isFalse);
      f.dispose();
    });
  });

  group('Balayage et suppression', () {
    Finder bouton(String libelle) => find.text(libelle);

    testWidgets('vers la droite : « Épingler » révélé, rien avant le '
        'toucher ; puis épinglée en tête, ligne refermée', (tester) async {
      await _accueil(tester, const Size(390, 844));
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.whatsapp);
      final depart = _gauche(tester, 'Contact 2');
      // Pendant le geste : la ligne suit le doigt.
      final geste = await tester.startGesture(
        tester.getCenter(find.text('Contact 2')),
      );
      await geste.moveBy(const Offset(20, 0));
      await geste.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(_gauche(tester, 'Contact 2'), greaterThan(depart + 20));
      expect(bouton(LigneConversation.boutonEpingler), findsOneWidget);
      await geste.moveBy(const Offset(60, 0));
      await geste.up();
      await _images(tester, 20);
      // Révélé, mais rien n'est épinglé tant qu'on ne touche pas.
      expect(bouton(LigneConversation.boutonEpingler), findsOneWidget);
      expect(
        _multicanal.epingles.rang(
          _whatsapp.conversations.firstWhere((c) => c.titre == 'Contact 2'),
        ),
        -1,
      );
      expect(bouton(LigneConversation.boutonSupprimer), findsNothing);
      await tester.tap(bouton(LigneConversation.boutonEpingler));
      await _images(tester, 30);
      final premiere = tester.widget<LigneConversation>(_lignes.first);
      expect(premiere.conversation.titre, 'Contact 2');
      expect(premiere.epinglee, isTrue);
      expect(bouton(LigneConversation.boutonEpingler), findsNothing);
      expect(_gauche(tester, 'Contact 2'), closeTo(depart, 0.5));
      // Épinglée : le balayage propose « Désépingler ».
      await tester.drag(find.text('Contact 2'), const Offset(120, 0));
      await _images(tester, 20);
      expect(bouton(LigneConversation.boutonDesepingler), findsOneWidget);
      // Toucher la ligne ouverte la referme seulement.
      await tester.tap(find.text('Contact 2'));
      await _images(tester, 20);
      expect(bouton(LigneConversation.boutonDesepingler), findsNothing);
      expect(_whatsapp.ouvertes, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('petit geste : la ligne revient, rien n’est révélé', (
      tester,
    ) async {
      await _accueil(tester, const Size(390, 844));
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.whatsapp);
      final depart = _gauche(tester, 'Contact 3');
      await tester.timedDrag(
        find.text('Contact 3'),
        const Offset(-25, 0),
        const Duration(milliseconds: 400),
      );
      await _images(tester, 20);
      expect(_gauche(tester, 'Contact 3'), closeTo(depart, 0.5));
      expect(find.text(LigneConversation.boutonSupprimer), findsNothing);
    });

    testWidgets('vers la gauche : « Supprimer » seul ; annuler garde tout ; '
        'confirmer supprime', (tester) async {
      await _accueil(tester, const Size(390, 844));
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.whatsapp);
      final c = _whatsapp.conversations.firstWhere(
        (c) => c.titre == 'Contact 4',
      );
      _multicanal.epingles.basculer(c);
      await _images(tester, 5);
      await tester.drag(find.text('Contact 4'), const Offset(-120, 0));
      await _images(tester, 20);
      expect(bouton(LigneConversation.boutonSupprimer), findsOneWidget);
      expect(find.text('Options'), findsNothing);
      expect(find.text('Archiver'), findsNothing);
      // Le balayage seul ne supprime rien.
      expect(_whatsapp.conversations, contains(c));

      await tester.tap(bouton(LigneConversation.boutonSupprimer));
      await _images(tester, 20);
      expect(find.text('Supprimer cette conversation ?'), findsOneWidget);
      expect(
        find.text('Cette action supprimera la conversation de JARVIS.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await _images(tester, 30);
      expect(_whatsapp.conversations, contains(c));
      expect(bouton(LigneConversation.boutonSupprimer), findsNothing);

      await tester.drag(find.text('Contact 4'), const Offset(-120, 0));
      await _images(tester, 20);
      await tester.tap(bouton(LigneConversation.boutonSupprimer));
      await _images(tester, 20);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Supprimer'),
        ),
      );
      await _images(tester, 30);
      expect(find.text('Contact 4'), findsNothing);
      expect(_whatsapp.conversations, isNot(contains(c)));
      expect(_multicanal.epingles.estEpinglee(c), isFalse);
      expect(_menuOuvert(), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('une seule ligne ouverte à la fois', (tester) async {
      await _accueil(tester, const Size(390, 844));
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.whatsapp);
      await tester.drag(find.text('Contact 2'), const Offset(-120, 0));
      await _images(tester, 20);
      await tester.drag(find.text('Contact 5'), const Offset(120, 0));
      await _images(tester, 20);
      expect(find.text(LigneConversation.boutonSupprimer), findsNothing);
      expect(find.text(LigneConversation.boutonEpingler), findsOneWidget);
    });

    testWidgets('conversation affichée supprimée : accueil vide, chat vocal '
        'terminé, PIM intact', (tester) async {
      await _accueil(tester, const Size(390, 844));
      final pim = tester.state(find.byType(PimParticle));
      await _envoyer(tester, 'Conversation à supprimer');
      expect(_conversation.messages, isNotEmpty);
      await _ouvrir(tester);
      final ligne = find.descendant(
        of: find.byType(LigneConversation),
        matching: find.text('Conversation à supprimer'),
      );
      await tester.drag(ligne, const Offset(-120, 0));
      await _images(tester, 20);
      await tester.tap(find.text(LigneConversation.boutonSupprimer));
      await _images(tester, 20);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Supprimer'),
        ),
      );
      await _images(tester, 40);
      expect(_conversation.messages, isEmpty);
      expect(_conversation.idCourant, isNull);
      expect(_conversation.archives, isEmpty);
      expect(find.text('Aucune conversation pour l’instant'), findsOneWidget);
      expect(find.text('EN COURS'), findsNothing);
      await tester.tap(find.byTooltip('Fermer le menu'));
      await _images(tester, 30);
      expect(tester.state(find.byType(PimParticle)), same(pim));
      // L'accueil fonctionne normalement ensuite.
      await _envoyer(tester, 'Nouvelle question');
      expect(_conversation.messages.first.texte, 'Nouvelle question');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ordinateur : clic droit → Supprimer (confirmé) ; la souris '
        'ne fait pas glisser la ligne', (tester) async {
      await _accueil(tester, const Size(1366, 900));
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.gmail);
      final souris = await tester.startGesture(
        tester.getCenter(find.text('Happy Hogan')),
        kind: PointerDeviceKind.mouse,
      );
      final avant = _gauche(tester, 'Happy Hogan');
      await souris.moveBy(const Offset(-120, 0));
      await tester.pump();
      expect(_gauche(tester, 'Happy Hogan'), closeTo(avant, 0.5));
      await souris.up();
      await _images(tester, 10);
      await tester.tap(find.text('Happy Hogan'), buttons: kSecondaryButton);
      await _images(tester, 20);
      expect(find.text(LigneConversation.epingler), findsOneWidget);
      await tester.tap(find.text(LigneConversation.supprimer));
      await _images(tester, 20);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Supprimer'),
        ),
      );
      await _images(tester, 30);
      expect(find.text('Happy Hogan'), findsNothing);
      expect(_lignes, findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('Panneau', () {
    testWidgets('1-5. panneau existant conservé, sélecteur et vrais logos', (
      tester,
    ) async {
      await _accueil(tester, const Size(1366, 900));
      await _envoyer(tester, 'Bonjour JARVIS');
      await _ouvrir(tester);
      expect(_menuOuvert(), isTrue);
      // Existant : entrées, « EN COURS », perle, Paramètres.
      expect(find.text('Nouvelle conversation'), findsWidgets);
      expect(find.text('Chat vocal'), findsOneWidget);
      expect(find.text('EN COURS'), findsOneWidget);
      expect(find.byTooltip('Accueil JARVIS'), findsOneWidget);
      expect(find.byTooltip('Paramètres'), findsOneWidget);
      // Nouveau : titre, cinq sources dans l'ordre, logos locaux.
      expect(find.text(SectionConversations.titre), findsOneWidget);
      final xs = [
        for (final s in SourceConversation.values)
          tester.getCenter(_onglet(s)).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(find.byType(LogoSource), findsNWidgets(5));
      expect(
        find.descendant(
          of: find.byType(SelecteurSources),
          matching: find.byType(SvgPicture),
        ),
        findsNWidgets(4),
      );
      // Liste JARVIS : la conversation réelle.
      expect(_lignes, findsOneWidget);
      // Ordre vertical : EN COURS, MES CONVERSATIONS, Paramètres en bas.
      final enCours = tester.getRect(find.text('EN COURS'));
      final mes = tester.getRect(find.text(SectionConversations.titre));
      final param = tester.getRect(find.byTooltip('Paramètres'));
      expect(mes.top, greaterThan(enCours.bottom));
      expect(param.top, greaterThan(mes.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('6-7, 16. sélection : contour violet ; la conversation '
        'ouverte ne change pas', (tester) async {
      await _accueil(tester, const Size(1366, 900));
      await _envoyer(tester, 'Bonjour JARVIS');
      final messages = List.of(_conversation.messages);
      await _ouvrir(tester);
      for (final s in SourceConversation.values.reversed) {
        await _choisir(tester, s);
        expect(_multicanal.selection.value, s);
        final zone = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.ancestor(
                  of: _onglet(s),
                  matching: find.byType(InkWell),
                ),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        final bord = (zone.decoration! as BoxDecoration).border! as Border;
        expect(bord.top.width, greaterThan(1));
        expect(bord.top.color.b, greaterThan(bord.top.color.g));
      }
      // Seuls les logos ont été touchés : rien n'a changé dans l'accueil.
      expect(_menuOuvert(), isTrue);
      expect(_conversation.messages, messages);
      expect(_gmail.ouvertes, isEmpty);
      expect(_whatsapp.ouvertes, isEmpty);
    });

    testWidgets('8-11. glissement horizontal selon l’ordre ; le reste ne '
        'bouge pas', (tester) async {
      await _accueil(tester, const Size(1366, 900));
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.whatsapp);
      final logos = tester.getRect(find.byType(SelecteurSources));
      final titre = tester.getRect(find.text(SectionConversations.titre));
      final param = tester.getRect(find.byTooltip('Paramètres'));
      final xTony = _gauche(tester, 'Tony Stark');

      // Vers la droite (Gmail) : WhatsApp part à gauche, Gmail arrive de
      // la droite.
      await tester.tap(_onglet(SourceConversation.gmail));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Tony Stark'), findsOneWidget);
      expect(find.text('Pepper Potts'), findsOneWidget);
      expect(_gauche(tester, 'Tony Stark'), lessThan(xTony));
      expect(_gauche(tester, 'Pepper Potts'), greaterThan(xTony));
      expect(tester.getRect(find.byType(SelecteurSources)), logos);
      expect(tester.getRect(find.text(SectionConversations.titre)), titre);
      expect(tester.getRect(find.byTooltip('Paramètres')), param);
      await _images(tester, 15);
      expect(find.text('Tony Stark'), findsNothing);
      expect(_gauche(tester, 'Pepper Potts'), closeTo(xTony, 0.5));

      // Vers la gauche (WhatsApp) : sens inverse.
      await tester.tap(_onglet(SourceConversation.whatsapp));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_gauche(tester, 'Pepper Potts'), greaterThan(xTony));
      expect(_gauche(tester, 'Tony Stark'), lessThan(xTony));
      await _images(tester, 15);
      expect(_gauche(tester, 'Tony Stark'), closeTo(xTony, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('12. chaque source garde sa position de défilement', (
      tester,
    ) async {
      await _accueil(tester, const Size(1366, 900));
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.whatsapp);
      await tester.drag(find.text('Contact 3'), const Offset(0, -600));
      await _images(tester, 40);
      expect(
        _multicanal.position(SourceConversation.whatsapp),
        greaterThan(300),
      );
      final y = tester.getRect(find.text('Contact 15')).top;
      await _choisir(tester, SourceConversation.gmail);
      // Gmail commence en haut.
      expect(find.text('Pepper Potts'), findsOneWidget);
      await _choisir(tester, SourceConversation.whatsapp);
      expect(tester.getRect(find.text('Contact 15')).top, closeTo(y, 0.5));
      // Fermer puis rouvrir le menu : la position est toujours là.
      await tester.tap(find.byTooltip('Fermer le menu'));
      await _images(tester, 25);
      await _ouvrir(tester);
      expect(_multicanal.selection.value, SourceConversation.whatsapp);
      expect(tester.getRect(find.text('Contact 15')).top, closeTo(y, 0.5));
    });

    testWidgets('13. changements rapides : la liste suit toujours le logo', (
      tester,
    ) async {
      await _accueil(tester, const Size(1366, 900));
      await _ouvrir(tester);
      for (final s in [
        SourceConversation.whatsapp,
        SourceConversation.gmail,
        SourceConversation.jarvis,
        SourceConversation.instagram,
        SourceConversation.gmail,
      ]) {
        await tester.ensureVisible(_onglet(s));
        await tester.tap(_onglet(s));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await _images(tester, 20);
      expect(_multicanal.selection.value, SourceConversation.gmail);
      expect(find.text('Pepper Potts'), findsOneWidget);
      expect(find.text('Tony Stark'), findsNothing);
      expect(find.text('Aucune conversation Instagram'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('14, 22. recherche dans la source, états vides, aucun '
        'bouton de connexion', (tester) async {
      await _accueil(tester, const Size(1366, 900));
      await _ouvrir(tester);
      expect(find.text('Aucune conversation pour l’instant'), findsOneWidget);
      await _choisir(tester, SourceConversation.whatsapp);
      final recherche = find.descendant(
        of: find.byType(SectionConversations),
        matching: find.byType(EditableText),
      );
      expect(find.text('Rechercher une conversation'), findsOneWidget);
      await tester.enterText(recherche, 'tony');
      await tester.pump();
      expect(_lignes, findsOneWidget);
      expect(find.text('Tony Stark'), findsOneWidget);
      await tester.enterText(recherche, 'zzz');
      await tester.pump();
      expect(find.text('Aucun résultat'), findsOneWidget);
      // Autre source : la recherche repart de zéro.
      await _choisir(tester, SourceConversation.gmail);
      expect(_lignes, findsNWidgets(3));
      await _choisir(tester, SourceConversation.messenger);
      expect(find.text('Aucune conversation Messenger'), findsOneWidget);
      expect(find.textContaining('Connecter'), findsNothing);
      expect(find.textContaining('Importer'), findsNothing);
    });

    testWidgets('15. ouvrir : conversation JARVIS rouverte ; Gmail '
        'transmise à sa messagerie', (tester) async {
      await _accueil(tester, const Size(1366, 900));
      await _envoyer(tester, 'Première conversation');
      await tester.tap(find.byTooltip('Nouvelle conversation'));
      await _images(tester, 30);
      expect(_conversation.messages, isEmpty);
      await _ouvrir(tester);
      await tester.tap(find.text('Première conversation'));
      await _images(tester, 30);
      expect(_menuOuvert(), isFalse);
      expect(_conversation.messages.first.texte, 'Première conversation');
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.gmail);
      await tester.tap(find.text('Pepper Potts'));
      await _images(tester, 30);
      expect(_menuOuvert(), isFalse);
      expect(_gmail.ouvertes, ['gm-1']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('17, 19-20. téléphone : appui prolongé, épingler, '
        'désépingler', (tester) async {
      await _accueil(tester, const Size(390, 844));
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.whatsapp);
      await tester.longPress(find.text('Contact 2'));
      await _images(tester, 20);
      expect(find.text(LigneConversation.epingler), findsOneWidget);
      await tester.tap(find.text(LigneConversation.epingler));
      await _images(tester, 20);
      expect(_menuOuvert(), isTrue);
      final premiere = tester.widget<LigneConversation>(_lignes.first);
      expect(premiere.conversation.titre, 'Contact 2');
      expect(premiere.epinglee, isTrue);
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
      await tester.longPress(find.text('Contact 2'));
      await _images(tester, 20);
      await tester.tap(find.text(LigneConversation.desepingler));
      await _images(tester, 20);
      expect(
        tester.widget<LigneConversation>(_lignes.first).conversation.titre,
        'Tony Stark',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('18. ordinateur : clic droit et bouton ⋯ au survol', (
      tester,
    ) async {
      await _accueil(tester, const Size(1366, 900));
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.gmail);
      await tester.tap(find.text('Happy Hogan'), buttons: kSecondaryButton);
      await _images(tester, 20);
      await tester.tap(find.text(LigneConversation.epingler));
      await _images(tester, 20);
      expect(
        tester.widget<LigneConversation>(_lignes.first).conversation.titre,
        'Happy Hogan',
      );
      final souris = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await souris.addPointer(location: Offset.zero);
      addTearDown(souris.removePointer);
      await souris.moveTo(tester.getCenter(find.text('Pepper Potts')));
      await tester.pump();
      await tester.tap(find.byTooltip('Options de la conversation'));
      await _images(tester, 20);
      expect(find.text(LigneConversation.epingler), findsOneWidget);
      await tester.tapAt(const Offset(1300, 20));
      await _images(tester, 20);
      expect(tester.takeException(), isNull);
    });

    for (final (taille, nom) in const [
      (Size(320, 568), '23. petit téléphone'),
      (Size(390, 844), 'téléphone'),
      (Size(1920, 1080), '24. grand écran'),
    ]) {
      testWidgets('$nom : aucun débordement, Paramètres en bas', (
        tester,
      ) async {
        await _accueil(tester, taille);
        await _ouvrir(tester);
        expect(tester.takeException(), isNull);
        await _choisir(tester, SourceConversation.whatsapp);
        expect(tester.takeException(), isNull);
        final param = tester.getRect(find.byTooltip('Paramètres'));
        expect(param.bottom, lessThanOrEqualTo(taille.height));
        expect(param.top, greaterThan(taille.height - 120));
        expect(_lignes, findsWidgets);
        // Clavier ouvert (recherche) : toujours sans débordement.
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await _images(tester, 10);
        expect(tester.takeException(), isNull);
      });
    }

    // Sélecteur de messageries : la police agrandie du téléphone (×1,3)
    // débordait d'1 px sous les logos et coupait les noms.
    for (final largeur in const [
      320.0,
      360.0,
      375.0,
      390.0,
      425.0,
      1366.0,
      1920.0,
    ]) {
      for (final echelle in const [1.0, 1.3, 2.0]) {
        final taille = Size(largeur, largeur < 600 ? 800 : 1000);
        testWidgets('sélecteur ${largeur.toInt()} px, texte ×$echelle : '
            'logos et noms entiers, aucun débordement', (tester) async {
          await _accueil(tester, taille, echelleTexte: echelle);
          await _ouvrir(tester);
          expect(tester.takeException(), isNull);

          final selecteur = tester.getRect(find.byType(SelecteurSources));
          final recherche = tester.getRect(
            find.widgetWithText(TextField, 'Rechercher une conversation'),
          );
          // Aucun chevauchement avec la recherche.
          expect(selecteur.bottom, lessThanOrEqualTo(recherche.top));

          for (final s in SourceConversation.values) {
            // Fait défiler les logos si besoin, puis choisit la source.
            await tester.ensureVisible(_onglet(s));
            await _images(tester, 10);
            await _choisir(tester, s);
            expect(tester.takeException(), isNull, reason: s.libelle);
            final onglet = find.ancestor(
              of: _onglet(s),
              matching: find.byType(InkWell),
            );
            final zone = tester.getRect(onglet.first);
            final nom = tester.getRect(_onglet(s));
            final logo = tester.getRect(
              find.descendant(
                of: onglet.first,
                matching: find.byType(LogoSource),
              ),
            );
            // Nom entier dans son onglet (aucune coupure), sous le logo.
            final p = tester.renderObject<RenderParagraph>(_onglet(s));
            expect(p.didExceedMaxLines, isFalse, reason: s.libelle);
            expect(nom.left, greaterThanOrEqualTo(zone.left - 0.5));
            expect(nom.right, lessThanOrEqualTo(zone.right + 0.5));
            expect(nom.bottom, lessThanOrEqualTo(zone.bottom + 0.5));
            expect(logo.bottom, lessThanOrEqualTo(nom.top));
            // Zone tactile confortable.
            expect(zone.width, greaterThanOrEqualTo(48));
            expect(zone.height, greaterThanOrEqualTo(48));
          }
          // La rangée ne bouge pas verticalement d'une source à l'autre.
          expect(
            tester.getRect(find.byType(SelecteurSources)).top,
            selecteur.top,
          );

          // Longue liste (WhatsApp, 40 conversations) qui défile, puis
          // recherche, puis liste vide (Messenger).
          await tester.ensureVisible(_onglet(SourceConversation.whatsapp));
          await _choisir(tester, SourceConversation.whatsapp);
          await tester.drag(_lignes.first, const Offset(0, -400));
          await _images(tester, 20);
          expect(tester.takeException(), isNull);
          await tester.enterText(
            find.widgetWithText(TextField, 'Rechercher une conversation'),
            'contact 1',
          );
          await _images(tester, 20);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(_onglet(SourceConversation.messenger));
          await _choisir(tester, SourceConversation.messenger);
          expect(_lignes, findsNothing);
          expect(tester.takeException(), isNull);

          // Paramètres toujours accessibles en bas.
          final param = tester.getRect(find.byTooltip('Paramètres'));
          expect(param.bottom, lessThanOrEqualTo(taille.height));
        });
      }
    }

    testWidgets('faire défiler les logos ne change pas la source choisie', (
      tester,
    ) async {
      await _accueil(tester, const Size(360, 800), echelleTexte: 1.3);
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.gmail);
      final rangee = find.byType(SelecteurSources);
      final avant = tester.getRect(_onglet(SourceConversation.jarvis)).left;
      for (final dx in const [-300.0, 300.0, -300.0]) {
        await tester.timedDrag(
          rangee,
          Offset(dx, 0),
          const Duration(milliseconds: 300),
        );
        await _images(tester, 30);
        expect(_multicanal.selection.value, SourceConversation.gmail);
      }
      expect(
        tester.getRect(_onglet(SourceConversation.jarvis)).left,
        lessThan(avant),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('26-27. particules intactes ; Paramètres toujours ouvrables', (
      tester,
    ) async {
      await _accueil(tester, const Size(1366, 900));
      final etat = tester.state(find.byType(PimParticle));
      await _ouvrir(tester);
      await _choisir(tester, SourceConversation.whatsapp);
      await _choisir(tester, SourceConversation.gmail);
      expect(tester.state(find.byType(PimParticle)), same(etat));
      await tester.tap(find.byTooltip('Paramètres'));
      await _images(tester, 30);
      expect(_menuOuvert(), isFalse);
      expect(find.text('Chat vocal'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(5, 5));
      await _images(tester, 150);
    });
  });
}
