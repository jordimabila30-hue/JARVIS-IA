import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/reference_whatsapp.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/export_whatsapp.dart';
import 'package:ia_jarvis/models/importation/piece_jointe_whatsapp.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/pages/filtrage_whatsapp_page.dart';
import 'package:ia_jarvis/pages/importation_whatsapp_page.dart';
import 'package:ia_jarvis/pages/joindre_whatsapp_page.dart';
import 'package:ia_jarvis/pages/resume_whatsapp_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/importation/depot_fichiers.dart';
import 'package:ia_jarvis/services/importation/export_local_web.dart'
    as memoire;
import 'package:ia_jarvis/services/importation/identite_whatsapp.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/importation/pieces_jointes_serveur.dart';
import 'package:ia_jarvis/services/importation/pont_android_importation.dart';
import 'package:ia_jarvis/services/importation/selection_export_whatsapp.dart';
import 'package:ia_jarvis/services/importation/selection_whatsapp.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/carte_piece_jointe.dart';
import 'package:ia_jarvis/widgets/importation/carte_export_choisi.dart';
import 'package:ia_jarvis/widgets/importation/filtrage/barre_selection.dart';
import 'package:ia_jarvis/widgets/importation/filtrage/selecteur_mode_filtrage.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

import 'outils/conversations_whatsapp.dart';
import 'outils/ecriture.dart';

// --- Faux services du mode vocal (aucun micro, aucune voix) --------------

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

class _SansDepot implements DepotFichiers {
  @override
  bool get disponible => false;
  @override
  void demarrer({
    required void Function(bool survol) surSurvol,
    required void Function(List<FichierBrut> fichiers) surDepot,
  }) {}
  @override
  void arreter() {}
}

/// Serveur des pièces jointes : échoue tant que [echec] est défini.
class _ServeurFaux implements ServicePiecesJointes {
  ErreurApi? echec;
  final identifiants = <String>[];

  @override
  Future<ResultatApi<PieceJointeEnregistree>> enregistrer({
    required PieceJointeWhatsApp piece,
    required String consigne,
    String? conversation,
  }) async {
    identifiants.add('${piece.id}/${piece.idConsigne}');
    final e = echec;
    if (e != null) return EchecApi(e);
    return SuccesApi(
      PieceJointeEnregistree(
        conversation: '00000000-0000-4000-8000-000000000001',
        consigne: piece.idConsigne,
        contexte: piece.id,
        nombre: piece.nombre,
        dejaEnregistree: false,
        conversationCreee: conversation == null,
      ),
    );
  }

  @override
  Future<ResultatApi<List<MessageWhatsApp>>> messages(String id) async =>
      const SuccesApi([]);

  @override
  Future<ResultatApi<void>> supprimer(String id) async => const SuccesApi(null);

  @override
  Future<ResultatApi<PageWhatsApp>> page(
    String id, {
    required int apres,
    required int limite,
  }) async => SuccesApi(
    PageWhatsApp(premier: apres + 1, messages: const [], suite: false),
  );

  @override
  Future<ResultatApi<Map<String, ReferencesReponse>>> references(
    String conversation,
  ) async => const SuccesApi({});
}

// --- Données ----------------------------------------------------------------

ConversationWhatsApp _tony() => ConversationWhatsApp(
  titre: 'Tony Stark',
  messages: [
    msg(0, DateTime(2026, 10, 12, 9), auteur: 'Tony Stark', texte: 'Salut'),
    msg(1, DateTime(2026, 10, 12, 9, 5), auteur: 'Jordi', texte: 'Salut Tony'),
    msg(
      2,
      DateTime(2026, 10, 14, 18),
      auteur: 'Tony Stark',
      texte: 'On se voit demain ?',
    ),
  ],
  participants: const [
    ParticipantWhatsApp(nom: 'Tony Stark', messages: 2),
    ParticipantWhatsApp(nom: 'Jordi', messages: 1),
  ],
  ordreDate: OrdreDate.jourMoisAnnee,
  dateIncertaine: false,
  lignesNonRattachees: const [],
  nombreLignesNonRattachees: 0,
  nomFichier: 'chat.txt',
);

PieceJointeWhatsApp _piece() {
  final c = _tony();
  final s = SelectionWhatsApp(c)..cocherVisibles(true);
  return PieceJointeWhatsApp.depuis(
    conversation: c,
    choisis: s.resultat(),
    moi: 'Jordi',
  );
}

Future<void> _images(WidgetTester tester, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _taille(WidgetTester tester, Size s) async {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('interface 3 : « Joindre la conversation »', () {
    Future<PieceJointeWhatsApp?> ouvrir(
      WidgetTester tester, {
      String? moiConnu,
      IdentiteWhatsApp? identite,
      ConversationWhatsApp? conversation,
    }) async {
      final c = conversation ?? _tony();
      final s = SelectionWhatsApp(c)
        ..basculer('m1')
        ..basculer('m2');
      PieceJointeWhatsApp? resultat;
      await tester.pumpWidget(
        MaterialApp(
          theme: themeJarvis(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                resultat = await Navigator.of(context)
                    .push<PieceJointeWhatsApp>(
                      MaterialPageRoute(
                        builder: (_) => JoindreWhatsAppPage(
                          conversation: c,
                          choisis: s.resultat(),
                          identite:
                              identite ??
                              IdentiteWhatsApp(stockage: StockageMemoire()),
                          moiConnu: moiConnu,
                        ),
                      ),
                    );
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await _images(tester);
      return resultat;
    }

    testWidgets('l’essentiel, « Vous êtes : » obligatoire, jamais deviné', (
      tester,
    ) async {
      await _taille(tester, const Size(390, 844));
      final stockage = StockageMemoire();
      final identite = IdentiteWhatsApp(stockage: stockage);
      PieceJointeWhatsApp? piece;
      final c = _tony();
      final s = SelectionWhatsApp(c)
        ..basculer('m1')
        ..basculer('m2');
      await tester.pumpWidget(
        MaterialApp(
          theme: themeJarvis(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                piece = await Navigator.of(context).push<PieceJointeWhatsApp>(
                  MaterialPageRoute(
                    builder: (_) => JoindreWhatsAppPage(
                      conversation: c,
                      choisis: s.resultat(),
                      identite: identite,
                    ),
                  ),
                );
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await _images(tester);
      expect(find.text(JoindreWhatsAppPage.titre), findsWidgets);
      expect(find.text('Tony Stark'), findsWidgets);
      expect(find.text('2 messages sélectionnés'), findsOneWidget);
      expect(find.text('12 – 14 octobre 2026'), findsOneWidget);
      expect(find.text('Tony Stark, Jordi'), findsOneWidget);
      expect(find.text(JoindreWhatsAppPage.vousEtes), findsOneWidget);
      // Les messages eux-mêmes ne sont pas réaffichés.
      expect(find.textContaining('On se voit'), findsNothing);
      // Rien n'est choisi pour l'utilisateur.
      expect(find.text(JoindreWhatsAppPage.choisirIdentite), findsOneWidget);
      FilledButton bouton() => tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(JoindreWhatsAppPage.titre).last,
          matching: find.byType(FilledButton),
        ),
      );
      expect(bouton().onPressed, isNull);
      await tester.tap(find.text('Jordi'));
      await _images(tester);
      expect(bouton().onPressed, isNotNull);
      await tester.tap(find.text(JoindreWhatsAppPage.titre).last);
      // Double appui : sans effet.
      await tester.tap(
        find.text(JoindreWhatsAppPage.titre).last,
        warnIfMissed: false,
      );
      await _images(tester);
      expect(piece!.moi, 'Jordi');
      expect(piece!.ids, ['m1', 'm2']);
      expect(find.byType(JoindreWhatsAppPage), findsNothing);
      // « Moi » retenu sur l'appareil pour les imports suivants.
      expect(await stockage.lire(), contains('Jordi'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('nom déjà confirmé : proposé, modifiable', (tester) async {
      await _taille(tester, const Size(390, 844));
      await ouvrir(tester, moiConnu: 'Jordi');
      expect(find.text(JoindreWhatsAppPage.choisirIdentite), findsNothing);
      await tester.tap(find.text('Tony Stark').last);
      await _images(tester);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('retour : rien n’est joint', (tester) async {
      await _taille(tester, const Size(390, 844));
      PieceJointeWhatsApp? r = await ouvrir(tester);
      await tester.tap(find.byTooltip('Retour'));
      await _images(tester);
      expect(find.byType(JoindreWhatsAppPage), findsNothing);
      expect(r, isNull);
    });

    for (final (taille, police) in const [
      (Size(320, 568), 1.0),
      (Size(320, 568), 1.8),
      (Size(1366, 768), 1.0),
    ]) {
      testWidgets('aucun débordement ($taille, police × $police)', (
        tester,
      ) async {
        await _taille(tester, taille);
        tester.platformDispatcher.textScaleFactorTestValue = police;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await ouvrir(tester);
        // Grande police : la page défile jusqu'au choix.
        await tester.ensureVisible(find.text('Jordi'));
        await _images(tester);
        await tester.tap(find.text('Jordi'));
        await _images(tester);
        expect(find.text(JoindreWhatsAppPage.choisirIdentite), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('parcours : lecture → filtrage → joindre → la pièce jointe '
      'revient à l’appelant, l’import se referme', (tester) async {
    await _taille(tester, const Size(390, 844));
    const texte = '''
11/10/2026, 14:30 - Tony Stark: Salut Jordi !
11/10/2026, 14:32 - Jordi: Salut Tony.
13/10/2026, 09:15 - Tony Stark: Parfait, tiens-moi au courant.
''';
    PieceJointeWhatsApp? piece;
    var termine = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: themeJarvis(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              piece = await Navigator.of(context).push<PieceJointeWhatsApp>(
                MaterialPageRoute(
                  builder: (_) => ImportationWhatsAppPage(
                    parcours: ParcoursImport.partageAndroid,
                    partageInitial: PartageRecu(
                      id: 'p',
                      fichiers: [
                        FichierBrut(
                          nom: 'Discussion WhatsApp avec Tony Stark.txt',
                          source: SourceReception.partageAndroid,
                          tailleOctets: utf8.encode(texte).length,
                          flux: Stream.value(utf8.encode(texte)),
                        ),
                      ],
                    ),
                    depot: _SansDepot(),
                    creerLocal: memoire.creerExportLocal,
                    identite: IdentiteWhatsApp(stockage: StockageMemoire()),
                  ),
                ),
              );
              termine = true;
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await _images(tester, 60);
    await tester.tap(find.text(CarteExportChoisi.filtrer));
    await _images(tester);
    await tester.tap(find.text(SelecteurModeFiltrage.parMessages));
    await _images(tester);
    await tester.tap(find.text('Tout cocher'));
    await _images(tester);
    final continuer = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(BarreSelection.continuer),
        matching: find.byType(FilledButton),
      ),
    );
    expect(continuer.onPressed, isNotNull);
    await tester.tap(find.text(BarreSelection.continuer));
    await _images(tester);
    expect(find.byType(JoindreWhatsAppPage), findsOneWidget);
    expect(find.text('3 messages sélectionnés'), findsOneWidget);
    // Retour : le filtrage est intact.
    await tester.tap(find.byTooltip('Retour'));
    await _images(tester);
    expect(find.byType(FiltrageWhatsAppPage), findsOneWidget);
    expect(find.text(BarreSelection.compteur(3)), findsOneWidget);
    await tester.tap(find.text(BarreSelection.continuer));
    await _images(tester);
    await tester.tap(find.text('Jordi'));
    await _images(tester);
    await tester.tap(find.text(JoindreWhatsAppPage.titre).last);
    await _images(tester, 60);
    expect(termine, isTrue);
    expect(piece!.titre, 'Tony Stark');
    expect(piece!.nombre, 3);
    expect(piece!.moi, 'Jordi');
    expect(find.byType(ImportationWhatsAppPage), findsNothing);
    expect(find.byType(FiltrageWhatsAppPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('dans le chat JARVIS', () {
    late ConversationSession conversation;
    late List<PieceJointeWhatsApp?> aRenvoyer;
    late int ouvertures;

    Widget page({ServicePiecesJointes? serveur}) {
      final tts = _Tts();
      conversation = ConversationSession(
        delaiReflexion: const Duration(milliseconds: 300),
        piecesJointes: serveur,
      );
      return MaterialApp(
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
            ),
          ),
          pim: PimController(),
          conversation: conversation,
          ouvrirImport: (context, {partageInitial, partages}) async {
            ouvertures++;
            return aRenvoyer.removeAt(0);
          },
        ),
      );
    }

    setUp(() {
      aRenvoyer = [];
      ouvertures = 0;
    });

    Future<void> importer(WidgetTester tester, PieceJointeWhatsApp? p) async {
      aRenvoyer.add(p);
      await tester.tap(find.byTooltip('Ajouter une conversation'));
      await _images(tester, 20);
      await tester.tap(find.text('Importer une conversation').last);
      await _images(tester, 20);
    }

    Finder carteEnAttente() => find.byType(PieceJointeEnAttente);

    Future<void> ecrire(WidgetTester tester, String texte) async {
      await tester.enterText(find.byType(EditableText), texte);
      await _images(tester, 5);
    }

    testWidgets('accueil vide : carte dans la barre, texte gardé, retrait, '
        'pas d’envoi sans consigne, puis envoi lié et consultation', (
      tester,
    ) async {
      await _taille(tester, const Size(1366, 768));
      await tester.pumpWidget(page());
      await _images(tester, 40);
      await ecrire(tester, 'Bonjour');
      await importer(tester, _piece());
      expect(ouvertures, 1);
      // Carte dans la barre de saisie, texte conservé.
      expect(
        find.descendant(
          of: find.byType(LigneDeCommande),
          matching: carteEnAttente(),
        ),
        findsOneWidget,
      );
      expect(find.text('Tony Stark'), findsOneWidget);
      expect(find.text('WhatsApp · 3 messages'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Bonjour',
      );
      // Aucune conversation créée, rien d'envoyé.
      expect(conversation.vide, isTrue);
      expect(conversation.idCourant, isNull);

      // Retrait : la carte part, le texte reste.
      await tester.tap(find.byTooltip(PieceJointeEnAttente.retirer));
      await _images(tester, 20);
      expect(carteEnAttente(), findsNothing);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Bonjour',
      );
      expect(conversation.vide, isTrue);

      // De nouveau jointe ; sans consigne, pas de bouton d'envoi.
      await importer(tester, _piece());
      await ecrire(tester, '');
      expect(find.text(LigneDeCommande.inviteConsigne), findsOneWidget);
      expect(find.byTooltip('Envoyer le message'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _images(tester, 20);
      expect(conversation.vide, isTrue);
      expect(carteEnAttente(), findsOneWidget);

      // Consigne libre, envoi (deux appuis : un seul envoi).
      await ecrire(tester, 'Propose-moi une réponse naturelle.');
      await tester.tap(find.byTooltip('Envoyer le message'));
      await tester.tap(
        find.byTooltip('Envoyer le message'),
        warnIfMissed: false,
      );
      await _images(tester, 40);
      await finirEcritures(tester);
      expect(carteEnAttente(), findsNothing);
      final avecPiece = conversation.messages.where(
        (m) => m.pieceJointe != null,
      );
      expect(avecPiece, hasLength(1));
      expect(avecPiece.single.texte, 'Propose-moi une réponse naturelle.');
      expect(find.byType(CartePieceJointeEnvoyee), findsOneWidget);
      expect(find.text('Propose-moi une réponse naturelle.'), findsOneWidget);
      expect(
        conversation.classement(conversation.idCourant!)!.titre,
        'Tony Stark',
      );
      expect(
        find.textContaining('n’ont été envoyés à aucun serveur'),
        findsOneWidget,
      );

      // « Voir les messages » : les vrais messages WhatsApp.
      await tester.tap(find.text(CartePieceJointeEnvoyee.voirMessages));
      await _images(tester, 30);
      expect(find.byType(ResumeWhatsAppPage), findsOneWidget);
      expect(find.text(CartePieceJointeEnvoyee.titrePage), findsOneWidget);
      expect(find.textContaining('On se voit demain ?'), findsOneWidget);
      // Les messages de « moi » à droite.
      final tony = tester.getRect(find.textContaining('On se voit demain ?'));
      final moi = tester.getRect(find.textContaining('Salut Tony'));
      expect(moi.left, greaterThan(tony.left));
      expect(tester.takeException(), isNull);
    });

    testWidgets('chat déjà commencé : mêmes échanges, même conversation', (
      tester,
    ) async {
      await _taille(tester, const Size(390, 844));
      await tester.pumpWidget(page());
      await _images(tester, 40);
      await ecrire(tester, 'Quelle heure est-il ?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _images(tester, 40);
      await finirEcritures(tester);
      final id = conversation.idCourant;
      final avant = conversation.messages.length;
      expect(avant, 2);
      await ecrire(tester, 'Analyse');
      await importer(tester, _piece());
      // Rien n'a changé avant l'envoi.
      expect(conversation.idCourant, id);
      expect(conversation.messages, hasLength(avant));
      expect(conversation.classement(id!), isNull);
      expect(carteEnAttente(), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Analyse',
      );
      await ecrire(tester, 'Analyse ces messages.');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _images(tester, 40);
      await finirEcritures(tester);
      expect(conversation.idCourant, id);
      expect(conversation.messages, hasLength(avant + 2));
      expect(conversation.messages.first.texte, 'Quelle heure est-il ?');
      expect(conversation.classement(id)!.titre, 'Tony Stark');
      expect(tester.takeException(), isNull);
    });

    testWidgets('compte connecté, enregistrement impossible : carte et '
        'consigne gardées, message clair, nouvel essai', (tester) async {
      await _taille(tester, const Size(390, 844));
      final serveur = _ServeurFaux()..echec = ErreurApi.injoignable;
      await tester.pumpWidget(page(serveur: serveur));
      await _images(tester, 40);
      await importer(tester, _piece());
      await ecrire(tester, 'Analyse ces messages.');
      await tester.tap(find.byTooltip('Envoyer le message'));
      await _images(tester, 20);
      expect(
        find.textContaining(ErreurApi.injoignable.message),
        findsOneWidget,
      );
      expect(
        find.textContaining(AccueilPage.pieceJointeGardee),
        findsOneWidget,
      );
      expect(carteEnAttente(), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Analyse ces messages.',
      );
      expect(conversation.vide, isTrue);
      // Nouvel essai : mêmes identifiants, enregistré cette fois.
      serveur.echec = null;
      await tester.tap(find.byTooltip('Envoyer le message'));
      await _images(tester, 40);
      await finirEcritures(tester);
      expect(serveur.identifiants.toSet(), hasLength(1));
      expect(serveur.identifiants, hasLength(2));
      expect(carteEnAttente(), findsNothing);
      expect(find.byType(CartePieceJointeEnvoyee), findsOneWidget);
      expect(
        find.textContaining('J’ai bien enregistré votre consigne'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('retour de l’import sans joindre : rien ne change', (
      tester,
    ) async {
      await _taille(tester, const Size(390, 844));
      await tester.pumpWidget(page());
      await _images(tester, 40);
      await importer(tester, null);
      expect(carteEnAttente(), findsNothing);
      expect(conversation.vide, isTrue);
    });

    for (final taille in const [Size(320, 568), Size(390, 844)]) {
      testWidgets('téléphone $taille : barre avec carte et texte long, '
          'aucun débordement', (tester) async {
        await _taille(tester, taille);
        await tester.pumpWidget(page());
        await _images(tester, 40);
        await importer(tester, _piece());
        await ecrire(
          tester,
          'JARVIS, explique-moi ce que Tony veut dire et propose-moi une '
          'réponse naturelle, sur plusieurs lignes pour voir.',
        );
        expect(carteEnAttente(), findsOneWidget);
        // La carte est dans la barre, au-dessus du texte.
        expect(
          tester.getRect(carteEnAttente()).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(EditableText)).top),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
