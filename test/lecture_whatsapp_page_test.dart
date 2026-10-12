import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/export_whatsapp.dart';
import 'package:ia_jarvis/pages/importation_whatsapp_page.dart';
import 'package:ia_jarvis/pages/resume_whatsapp_page.dart';
import 'package:ia_jarvis/services/importation/depot_fichiers.dart';
import 'package:ia_jarvis/services/importation/export_local_web.dart'
    as memoire;
import 'package:ia_jarvis/services/importation/identite_whatsapp.dart';
import 'package:ia_jarvis/services/importation/import_en_cours.dart';
import 'package:ia_jarvis/services/importation/lecture_whatsapp.dart';
import 'package:ia_jarvis/services/importation/pont_android_importation.dart';
import 'package:ia_jarvis/services/importation/selection_export_whatsapp.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/importation/accueil_import_whatsapp.dart';
import 'package:ia_jarvis/widgets/importation/apercu_discussion.dart';
import 'package:ia_jarvis/widgets/importation/carte_export_choisi.dart';
import 'package:ia_jarvis/widgets/importation/choix_fichiers_recus.dart';
import 'package:ia_jarvis/widgets/importation/lecture_whatsapp_widgets.dart';
import 'package:ia_jarvis/widgets/importation/logo_whatsapp.dart';

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

class _DepotTest implements DepotFichiers {
  void Function(List<FichierBrut>)? deposer;
  @override
  bool get disponible => true;
  @override
  void demarrer({
    required void Function(bool survol) surSurvol,
    required void Function(List<FichierBrut> fichiers) surDepot,
  }) => deposer = surDepot;
  @override
  void arreter() => deposer = null;
}

const _texte = '''
11/10/2026, 14:30 - Les messages et les appels sont chiffrés de bout en bout.
11/10/2026, 14:30 - Tony Stark: Salut Jordi !
11/10/2026, 14:32 - Jordi: Salut Tony.
13/10/2026, 09:12 - Tony Stark: <Médias omis>
13/10/2026, 09:15 - Tony Stark: Parfait, tiens-moi au courant.
''';

/// Fichier factice, lu paresseusement ; [lectures] compte les lectures.
FichierBrut _brut(
  String nom,
  List<int> octets, {
  SourceReception source = SourceReception.partageAndroid,
  List<int>? lectures,
}) => FichierBrut(
  nom: nom,
  source: source,
  tailleOctets: octets.length,
  flux: () async* {
    lectures?.add(1);
    yield octets;
  }(),
);

Future<void> _images(WidgetTester tester, [int n = 40]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  late StockageMemoire stockage;
  late List<FutureOr<FichierBrut?> Function()> suivants;
  late int ouverturesWhatsApp;
  late bool whatsAppInstalle;

  setUp(() {
    stockage = StockageMemoire();
    suivants = [];
    ouverturesWhatsApp = 0;
    whatsAppInstalle = true;
    importWhatsAppEnCours.value = null;
  });

  Future<void> afficher(
    WidgetTester tester, {
    FichierBrut? fichier,
    ParcoursImport parcours = ParcoursImport.partageAndroid,
    Stream<PartageRecu>? partages,
    DepotFichiers? depot,
    Size taille = const Size(390, 844),
  }) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: themeJarvis(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ImportationWhatsAppPage(
                      parcours: parcours,
                      partageInitial: fichier == null
                          ? null
                          : PartageRecu(id: 'p', fichiers: [fichier]),
                      partages: partages,
                      depot: depot ?? _SansDepot(),
                      creerLocal: memoire.creerExportLocal,
                      identite: IdentiteWhatsApp(stockage: stockage),
                      selection: SelectionExportWhatsApp(
                        ouvrirSelecteur: () async => suivants.removeAt(0)(),
                      ),
                      ouvrirWhatsApp: () async {
                        ouverturesWhatsApp++;
                        return whatsAppInstalle;
                      },
                    ),
                  ),
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await _images(tester, 60);
  }

  group('aucun fichier', () {
    testWidgets('Android : « Ouvrir WhatsApp », « Parcourir », « Comment '
        'importer ? »', (tester) async {
      await afficher(tester);
      expect(find.text(CarteImporterWhatsApp.titre), findsOneWidget);
      expect(find.text(CarteImporterWhatsApp.partager), findsOneWidget);
      expect(find.text(CarteParcourir.titre), findsOneWidget);
      expect(find.text(CarteParcourir.formats), findsOneWidget);
      // L'action principale est sous la carte, pas dedans.
      final ouvrir = find.text(CarteImporterWhatsApp.ouvrirWhatsApp);
      expect(
        find.descendant(
          of: find.byType(CarteImporterWhatsApp),
          matching: ouvrir,
        ),
        findsNothing,
      );
      expect(
        tester.getTopLeft(ouvrir).dy,
        greaterThan(
          tester.getBottomLeft(find.byType(CarteImporterWhatsApp)).dy,
        ),
      );
      // Logo centré dans la carte.
      expect(
        tester.getCenter(find.byType(LogoWhatsApp).last).dx,
        moreOrLessEquals(
          tester.getCenter(find.byType(CarteImporterWhatsApp)).dx,
          epsilon: 0.5,
        ),
      );
      // Bloc centré verticalement (de la carte à « Comment importer ? »),
      // en-tête resté en haut.
      final haut = tester.getTopLeft(find.byType(CarteImporterWhatsApp)).dy;
      final bas = tester.getBottomLeft(find.byType(BoutonCommentImporter)).dy;
      expect((haut + bas) / 2, moreOrLessEquals(844 / 2, epsilon: 30));
      expect(tester.getTopLeft(find.byTooltip('Retour')).dy, lessThan(30));
      expect(
        tester.getSize(find.byType(CarteImporterWhatsApp)).height,
        greaterThanOrEqualTo(CarteImporterWhatsApp.hauteurMin),
      );
      // Aucun faux « Recevoir depuis WhatsApp ».
      expect(find.textContaining('Recevoir'), findsNothing);

      await tester.tap(find.text(CarteImporterWhatsApp.ouvrirWhatsApp));
      await _images(tester, 5);
      expect(ouverturesWhatsApp, 1);
      whatsAppInstalle = false;
      await tester.tap(find.text(CarteImporterWhatsApp.ouvrirWhatsApp));
      await _images(tester, 5);
      expect(find.text(ImportationWhatsAppPage.whatsAppAbsent), findsOneWidget);

      await tester.tap(find.text(BoutonCommentImporter.libelle));
      await _images(tester, 30);
      for (final e in ImportationWhatsAppPage.etapesAndroid) {
        expect(find.text(e), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Windows / Web : l’action principale ouvre le sélecteur', (
      tester,
    ) async {
      await afficher(tester, parcours: ParcoursImport.selection);
      expect(find.text(CarteImporterWhatsApp.ouvrirWhatsApp), findsNothing);
      suivants.add(() => _brut('chat.txt', utf8.encode(_texte)));
      await tester.tap(find.text(CarteParcourir.titre));
      await _images(tester, 60);
      expect(find.text(CarteExportChoisi.pret), findsOneWidget);
    });
  });

  group('lecture automatique', () {
    testWidgets('partage reçu : lu sans rien toucher, « Conversation prête », '
        'filtrage non disponible, une seule lecture', (tester) async {
      final lectures = <int>[];
      await afficher(
        tester,
        fichier: _brut(
          'Discussion WhatsApp avec Tony Stark.txt',
          utf8.encode(_texte),
          lectures: lectures,
        ),
      );
      expect(
        find.text('Discussion WhatsApp avec Tony Stark.txt'),
        findsOneWidget,
      );
      expect(find.text(CarteExportChoisi.pret), findsOneWidget);
      expect(find.textContaining('reçu par partage'), findsOneWidget);
      final filtrer = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(CarteExportChoisi.filtrer),
          matching: find.byType(FilledButton),
        ),
      );
      expect(filtrer.onPressed, isNull);
      expect(find.text(CarteExportChoisi.filtrageAVenir), findsOneWidget);
      // Au moins la taille de la carte du premier écran (identique avec
      // les vraies polices ; la police des tests est plus large).
      expect(
        tester.getSize(find.byType(CarteExportChoisi)).height,
        greaterThanOrEqualTo(CarteImporterWhatsApp.hauteurMin),
      );
      // « Filtrer » est hors de la carte, en bas de l'écran.
      expect(
        find.descendant(
          of: find.byType(CarteExportChoisi),
          matching: find.text(CarteExportChoisi.filtrer),
        ),
        findsNothing,
      );
      expect(
        tester.getBottomLeft(find.byType(ActionFiltrer)).dy,
        greaterThan(844 - 40),
      );
      expect(
        tester.getTopLeft(find.byType(ActionFiltrer)).dy,
        greaterThan(tester.getBottomLeft(find.byType(CarteExportChoisi)).dy),
      );
      // Les messages ne sont plus sur l'écran principal.
      expect(find.byType(BulleApercu), findsNothing);
      // Reconstructions : jamais de seconde lecture.
      await _images(tester, 60);
      expect(lectures, hasLength(1));
      expect(importWhatsAppEnCours.value!.conversation.messages, hasLength(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('lecture en cours : progression compacte, « Annuler », '
        'puis relire', (tester) async {
      final flux = StreamController<List<int>>();
      addTearDown(flux.close);
      final octets = utf8.encode(_texte * 40);
      flux.add(octets.sublist(0, 5000));
      await afficher(
        tester,
        fichier: FichierBrut(
          nom: 'chat.txt',
          source: SourceReception.partageAndroid,
          tailleOctets: octets.length,
          flux: flux.stream,
        ),
      );
      expect(find.text(CarteExportChoisi.lecture), findsOneWidget);
      expect(find.text(EtapeLecture.copie.libelle), findsOneWidget);
      expect(find.text(CarteExportChoisi.pret), findsNothing);
      await tester.tap(find.text('Annuler'));
      await _images(tester, 20);
      expect(find.text(CarteExportChoisi.lecture), findsNothing);
      expect(find.text(CarteExportChoisi.relire), findsOneWidget);
    });

    testWidgets('fichier illisible : erreur claire, jamais « prête »', (
      tester,
    ) async {
      await afficher(
        tester,
        fichier: _brut('notes.txt', utf8.encode('a\nb\n')),
      );
      expect(find.text(ErreurLecture.formatNonReconnu.message), findsOneWidget);
      expect(find.text(CarteExportChoisi.pret), findsNothing);
      expect(find.text(CarteExportChoisi.relire), findsOneWidget);
    });

    testWidgets('ZIP avec deux discussions possibles : l’utilisateur choisit', (
      tester,
    ) async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('a.txt', utf8.encode(_texte)))
        ..addFile(ArchiveFile.bytes('b.txt', utf8.encode(_texte)));
      await afficher(
        tester,
        fichier: _brut('export.zip', ZipEncoder().encodeBytes(archive)),
      );
      expect(find.text(ChoixDansArchive.titre), findsOneWidget);
      await tester.tap(find.text('b.txt'));
      await _images(tester, 60);
      expect(find.text(CarteExportChoisi.pret), findsOneWidget);
    });

    testWidgets('plusieurs fichiers partagés : rien n’est lu avant le choix', (
      tester,
    ) async {
      final lectures = <int>[];
      final partages = StreamController<PartageRecu>();
      addTearDown(partages.close);
      await afficher(tester, partages: partages.stream);
      partages.add(
        PartageRecu(
          id: 'p',
          fichiers: [
            _brut('IMG-1.jpg', const [0xFF, 0xD8, 0, 0], lectures: lectures),
            _brut('chat.txt', utf8.encode(_texte), lectures: lectures),
          ],
        ),
      );
      await _images(tester);
      expect(find.text(ChoixFichiersRecus.titre), findsOneWidget);
      expect(lectures, isEmpty);
      await tester.tap(find.text('chat.txt'));
      await _images(tester, 60);
      expect(find.text(CarteExportChoisi.pret), findsOneWidget);
      expect(lectures, hasLength(1));
    });

    testWidgets('nouveau partage : remplace le fichier et relance la lecture', (
      tester,
    ) async {
      final partages = StreamController<PartageRecu>();
      addTearDown(partages.close);
      await afficher(
        tester,
        fichier: _brut('premier.txt', utf8.encode(_texte)),
        partages: partages.stream,
      );
      expect(find.text('premier.txt'), findsOneWidget);
      partages.add(
        PartageRecu(
          id: 'q',
          fichiers: [_brut('second.txt', utf8.encode(_texte))],
        ),
      );
      await _images(tester, 60);
      expect(find.text('second.txt'), findsOneWidget);
      expect(find.text('premier.txt'), findsNothing);
      expect(find.text(CarteExportChoisi.pret), findsOneWidget);
      partages.add(const PartageRecu(id: 'r', fichiers: []));
      await _images(tester);
      expect(
        find.text(ErreurSelectionExport.aucunFichier.message),
        findsOneWidget,
      );
      expect(find.text('second.txt'), findsOneWidget);
    });

    testWidgets('sélecteur : annulation et refus gardent le fichier ; '
        'changer relit ; retirer revient à l’accueil', (tester) async {
      await afficher(tester, fichier: _brut('chat.txt', utf8.encode(_texte)));
      suivants.add(() => null);
      await tester.tap(find.text(CarteExportChoisi.changer));
      await _images(tester);
      expect(find.text('chat.txt'), findsOneWidget);
      expect(find.text(CarteExportChoisi.pret), findsOneWidget);

      suivants.add(() => _brut('photo.png', const [0xFF, 0xD8, 0, 0]));
      await tester.tap(find.text(CarteExportChoisi.changer));
      await _images(tester);
      expect(find.text('chat.txt'), findsOneWidget);
      expect(
        find.text(ErreurSelectionExport.formatNonPrisEnCharge.message),
        findsOneWidget,
      );

      suivants.add(
        () => _brut(
          'autre.txt',
          utf8.encode(_texte),
          source: SourceReception.selecteur,
        ),
      );
      await tester.tap(find.text(CarteExportChoisi.changer));
      await _images(tester, 60);
      expect(find.text('autre.txt'), findsOneWidget);
      expect(find.text(CarteExportChoisi.pret), findsOneWidget);

      await tester.tap(find.byTooltip(CarteExportChoisi.retirer));
      await _images(tester);
      expect(find.text(CarteImporterWhatsApp.titre), findsOneWidget);
      expect(importWhatsAppEnCours.value, isNull);
    });

    testWidgets('glisser-déposer (Windows, Web)', (tester) async {
      final depot = _DepotTest();
      await afficher(
        tester,
        parcours: ParcoursImport.selection,
        depot: depot,
        taille: const Size(1366, 768),
      );
      depot.deposer!([
        _brut(
          'chat.txt',
          utf8.encode(_texte),
          source: SourceReception.glisserDeposer,
        ),
      ]);
      await _images(tester, 60);
      expect(find.textContaining('déposé'), findsOneWidget);
      expect(find.text(CarteExportChoisi.pret), findsOneWidget);
    });
  });

  group('résumé facultatif', () {
    testWidgets('« Voir le résumé » : discussion en bulles, aucun « Vous '
        'êtes », retour sans rien perdre', (tester) async {
      await afficher(
        tester,
        fichier: _brut(
          'Discussion WhatsApp avec Tony Stark.txt',
          utf8.encode(_texte),
        ),
      );
      await tester.tap(find.text(CarteExportChoisi.resume));
      await _images(tester, 30);
      expect(find.byType(ResumeWhatsAppPage), findsOneWidget);
      expect(find.text('Tony Stark'), findsWidgets);
      expect(find.text('5 messages · 11 – 13 octobre 2026'), findsOneWidget);
      expect(find.text(ResumeWhatsAppPage.mediasNonImportes), findsOneWidget);
      // L'avis de chiffrement de WhatsApp n'est pas montré.
      expect(find.textContaining('chiffrés de bout en bout'), findsNothing);
      // Plus aucun choix d'identité sur cette page.
      expect(find.textContaining('Vous êtes'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      // Séparateurs : le jour réel des messages placés dessous.
      final dimanche = find.text('dimanche 11 octobre 2026');
      final mardi = find.text('mardi 13 octobre 2026');
      expect(dimanche, findsOneWidget);
      expect(mardi, findsOneWidget);
      double haut(Finder f) => tester.getTopLeft(f).dy;
      expect(
        haut(dimanche),
        lessThan(haut(find.textContaining('Salut Tony.'))),
      );
      expect(haut(find.textContaining('Salut Tony.')), lessThan(haut(mardi)));
      expect(
        haut(mardi),
        lessThan(haut(find.textContaining('Parfait, tiens-moi au courant.'))),
      );
      // Deux auteurs : côtés stables (le premier qui écrit à gauche),
      // nom en tête de suite.
      final gauche = tester.getRect(find.textContaining('Salut Jordi !')).left;
      final droite = tester.getRect(find.textContaining('Salut Tony.')).left;
      expect(droite, greaterThan(gauche));
      expect(find.text('Jordi'), findsOneWidget);
      // Média : petite bulle discrète.
      expect(find.text(BulleApercu.mediaNonImporte), findsOneWidget);

      await tester.tap(find.byTooltip('Retour'));
      await _images(tester, 30);
      expect(find.byType(ResumeWhatsAppPage), findsNothing);
      expect(find.text(CarteExportChoisi.pret), findsOneWidget);
      expect(importWhatsAppEnCours.value!.conversation.messages, hasLength(5));
      // Rien n'est choisi pour l'utilisateur.
      expect(importWhatsAppEnCours.value!.moi, isNull);
    });

    testWidgets('groupe, long historique, médias en série : aperçu '
        'virtualisé, ouvert sur les plus récents, sans débordement (320 px)', (
      tester,
    ) async {
      final b = StringBuffer();
      final auteurs = [
        'Tony',
        'Pepper',
        'Happy Hogan, chef de la sécurité de Stark Industries',
      ];
      for (var i = 0; i < 5000; i++) {
        final jour = (i ~/ 200 + 1).toString().padLeft(2, '0');
        b.writeln(
          '$jour/01/2020, 10:00 - ${auteurs[i % 3]}: message numéro $i, '
          'un peu long pour tester la mise en page des bulles',
        );
      }
      for (var i = 0; i < 6; i++) {
        b.writeln('15/03/2026, 21:0$i - Pepper: <Médias omis>');
      }
      b.writeln('15/03/2026, 22:00 - Tony: dernier\nsur deux lignes');
      await afficher(
        tester,
        fichier: _brut(
          'Discussion WhatsApp avec Avengers.txt',
          utf8.encode('$b'),
        ),
        taille: const Size(320, 640),
      );
      expect(find.text(CarteExportChoisi.pret), findsOneWidget);
      await tester.ensureVisible(find.text(CarteExportChoisi.resume));
      await tester.pump();
      await tester.tap(find.text(CarteExportChoisi.resume));
      await _images(tester, 30);
      expect(
        find.text(
          '${nombreEnFrancais(5007)} messages · '
          '1er janvier 2020 – 15 mars 2026',
        ),
        findsOneWidget,
      );
      // Ouvert sur la fin, sans rien construire du début.
      // Multiligne : une seule bulle, retours à la ligne d'origine.
      expect(find.textContaining('dernier\nsur deux lignes'), findsOneWidget);
      expect(find.textContaining('message numéro 0,'), findsNothing);
      expect(find.byType(BulleApercu).evaluate().length, lessThan(40));
      // Six médias consécutifs : une seule petite bulle.
      expect(find.text(BulleMediasGroupes.libelle(6)), findsOneWidget);
      expect(find.text('21:00 – 21:05'), findsOneWidget);
      expect(find.text('dimanche 15 mars 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('grande police, noms longs (320 px) : aucun débordement', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await afficher(tester, taille: const Size(320, 568));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    const long = 'Marie-Christine de la Tour-Beauregard Nzuzi Mukendi';
    await afficher(
      tester,
      taille: const Size(320, 568),
      fichier: _brut(
        'Discussion WhatsApp avec $long.zip.txt',
        utf8.encode(
          '11/10/2026, 14:30 - $long: Bonjour, voici un message assez long '
          'pour occuper plusieurs lignes dans la bulle\n'
          'et une deuxième ligne\n'
          '11/10/2026, 14:31 - Jean-Baptiste Kalonji Tshibanda wa Mutombo: '
          'Ok\n'
          '11/10/2026, 14:32 - $long: <Médias omis>\n',
        ),
      ),
    );
    expect(find.text(CarteExportChoisi.pret), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(CarteExportChoisi.resume));
    await tester.pump();
    await tester.tap(find.text(CarteExportChoisi.resume));
    await _images(tester, 30);
    expect(find.byType(ResumeWhatsAppPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retour (bouton ou Échap)', (tester) async {
    await afficher(tester);
    await tester.tap(find.byTooltip('Retour'));
    await _images(tester, 30);
    expect(find.byType(ImportationWhatsAppPage), findsNothing);
    await tester.tap(find.text('ouvrir'));
    await _images(tester, 30);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _images(tester, 30);
    expect(find.byType(ImportationWhatsAppPage), findsNothing);
  });

  for (final taille in const [Size(320, 568), Size(1366, 768)]) {
    for (final parcours in ParcoursImport.values) {
      testWidgets('aucun débordement ($taille, ${parcours.name})', (
        tester,
      ) async {
        await afficher(tester, parcours: parcours, taille: taille);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await afficher(
          tester,
          parcours: parcours,
          taille: taille,
          fichier: _brut(
            'Discussion WhatsApp avec un nom de contact particulièrement '
            'long pour voir la coupure.txt',
            utf8.encode(_texte),
          ),
        );
        expect(find.text(CarteExportChoisi.pret), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
