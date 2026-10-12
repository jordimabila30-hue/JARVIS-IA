import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/export_whatsapp.dart';
import 'package:ia_jarvis/services/importation/detection_format.dart';
import 'package:ia_jarvis/services/importation/selection_export_whatsapp.dart';
import 'package:ia_jarvis/utils/taille_fichier.dart';

const _zip = [0x50, 0x4B, 0x03, 0x04, 0x14, 0x00];
final _txt = '12/03/2025, 21:04 - Marc: Salut !\n'.codeUnits;

/// Fichier factice ; [ouvertures] compte les lectures réellement lancées.
FichierBrut _brut(
  String nom,
  List<int> contenu, {
  int? taille,
  bool tailleInconnue = false,
  String? mime,
  SourceReception source = SourceReception.selecteur,
  List<int>? ouvertures,
}) => FichierBrut(
  nom: nom,
  source: source,
  tailleOctets: tailleInconnue ? null : taille ?? contenu.length,
  typeMime: mime,
  // Paresseux, comme les vrais flux : rien n'est lu avant l'écoute.
  flux: () async* {
    ouvertures?.add(1);
    yield contenu;
  }(),
);

SelectionExportWhatsApp _selection(FutureOr<FichierBrut?> Function() f) =>
    SelectionExportWhatsApp(ouvrirSelecteur: () async => f());

/// Aucun glisser-déposer (tests de page).

void main() {
  group('détection du format', () {
    ({FormatExportWhatsApp? format, ErreurSelectionExport? erreur}) d(
      String nom,
      List<int> debut, {
      String? mime,
      bool entier = true,
    }) => detecterFormat(
      nom: nom,
      typeMime: mime,
      debut: debut,
      fichierEntier: entier,
    );

    test('le contenu prime sur le nom et le type', () {
      expect(d('chat.zip', _zip).format, FormatExportWhatsApp.zip);
      expect(d('chat.txt', _txt).format, FormatExportWhatsApp.txt);
      // Nom sans extension (partage Android), type absent ou faux.
      expect(d('1234567', _zip).format, FormatExportWhatsApp.zip);
      expect(
        d('export', _zip, mime: 'application/octet-stream').format,
        FormatExportWhatsApp.zip,
      );
      expect(d('export', _txt).format, FormatExportWhatsApp.txt);
      expect(
        d('export', _txt, mime: 'text/plain').format,
        FormatExportWhatsApp.txt,
      );
      expect(
        d('Discussion avec M. Dupont', _txt).format,
        FormatExportWhatsApp.txt,
      );
      // Archive renommée en .txt : c'est une archive.
      expect(d('chat.txt', _zip).format, FormatExportWhatsApp.zip);
      // Texte UTF-16 (marque d'ordre).
      expect(
        d('chat.txt', const [0xFF, 0xFE, 0x41, 0x00]).format,
        FormatExportWhatsApp.txt,
      );
    });

    test('refus expliqués', () {
      expect(d('chat.txt', const []).erreur, ErreurSelectionExport.fichierVide);
      expect(
        d('chat.txt', '  \r\n'.codeUnits).erreur,
        ErreurSelectionExport.fichierVide,
      );
      expect(
        d('chat.zip', const [0x50, 0x4B, 5, 6, 0, 0]).erreur,
        ErreurSelectionExport.fichierVide,
      );
      // Extension ou type ZIP, contenu qui n'en est pas un.
      expect(
        d('chat.zip', _txt).erreur,
        ErreurSelectionExport.archiveEndommagee,
      );
      expect(
        d('export', const [1, 2, 0, 3], mime: 'application/zip').erreur,
        ErreurSelectionExport.archiveEndommagee,
      );
      expect(
        d('chat.txt', const [0x41, 0x00, 0x42]).erreur,
        ErreurSelectionExport.texteIllisible,
      );
      expect(
        d('photo.jpg', const [0xFF, 0xD8, 0xFF, 0x00]).erreur,
        ErreurSelectionExport.formatNonPrisEnCharge,
      );
      // Du texte, mais pas un export (HTML, PDF…).
      expect(
        d('page.html', '<html></html>'.codeUnits).erreur,
        ErreurSelectionExport.formatNonPrisEnCharge,
      );
      expect(
        d('export', '<p>'.codeUnits, mime: 'text/html').erreur,
        ErreurSelectionExport.formatNonPrisEnCharge,
      );
      expect(
        d('photo.png', _zip.sublist(0, 2)).erreur,
        ErreurSelectionExport.formatNonPrisEnCharge,
      );
    });

    test('début d’un gros fichier : les blancs ne le rendent pas vide', () {
      expect(
        natureDuContenu('   '.codeUnits, fichierEntier: false),
        NatureContenu.texte,
      );
    });

    test('taille lisible en français', () {
      expect(tailleLisible(0), '0 octet');
      expect(tailleLisible(840), '840 octets');
      expect(tailleLisible(1024), '1 Ko');
      expect(tailleLisible(12698), '12,4 Ko');
      expect(tailleLisible(3 * 1024 * 1024 + 104858), '3,1 Mo');
      expect(tailleLisible(512 * 1024 * 1024), '512 Mo');
      expect(tailleLisible(1288490189), '1,2 Go');
    });
  });

  group('réception', () {
    test('annulation : rien n’est choisi', () async {
      final r = await _selection(() => null).choisir();
      expect(r, isA<SelectionAnnulee>());
    });

    Future<ErreurSelectionExport?> refus(FichierBrut brut) async {
      final r = await SelectionExportWhatsApp().verifier(brut);
      return r is SelectionRefusee ? r.erreur : null;
    }

    test('trop volumineux : refusé sans rien lire', () async {
      final ouvertures = <int>[];
      expect(
        await refus(
          _brut(
            'chat.zip',
            _zip,
            taille: SelectionExportWhatsApp.tailleMaximale + 1,
            ouvertures: ouvertures,
          ),
        ),
        ErreurSelectionExport.tropVolumineux,
      );
      expect(ouvertures, isEmpty);
    });

    test(
      'accès refusé, URI devenue inaccessible, sélecteur en échec',
      () async {
        expect(
          await refus(
            const FichierBrut(
              nom: 'chat.txt',
              source: SourceReception.selecteur,
            ),
          ),
          ErreurSelectionExport.accesImpossible,
        );
        expect(
          await refus(
            FichierBrut(
              nom: 'chat.txt',
              source: SourceReception.partageAndroid,
              flux: Stream.error(PlatformException(code: 'acces')),
            ),
          ),
          ErreurSelectionExport.accesImpossible,
        );
        final r = await SelectionExportWhatsApp(
          ouvrirSelecteur: () => throw Exception('refusé par le système'),
        ).choisir();
        expect(
          (r as SelectionRefusee).erreur,
          ErreurSelectionExport.accesImpossible,
        );
      },
    );

    test(
      'ZIP et TXT valides, toutes sources ; contenu entier, lu une fois',
      () async {
        for (final (nom, format, source) in [
          (
            'Discussion avec Marc.zip',
            FormatExportWhatsApp.zip,
            SourceReception.partageAndroid,
          ),
          (
            'Discussion avec Marc.txt',
            FormatExportWhatsApp.txt,
            SourceReception.selecteur,
          ),
          (
            'chat.txt',
            FormatExportWhatsApp.txt,
            SourceReception.glisserDeposer,
          ),
        ]) {
          final contenu = format == FormatExportWhatsApp.zip
              ? [..._zip, ...List.filled(9000, 7)]
              : [for (var i = 0; i < 300; i++) ..._txt];
          final morceaux = [
            for (var i = 0; i < contenu.length; i += 1000)
              contenu.sublist(i, (i + 1000).clamp(0, contenu.length)),
          ];
          final r = await SelectionExportWhatsApp().verifier(
            FichierBrut(
              nom: nom,
              source: source,
              tailleOctets: contenu.length,
              typeMime: 'application/octet-stream',
              flux: Stream.fromIterable(morceaux),
            ),
          );
          final export = (r as SelectionReussie).export;
          expect(export.fichier.nom, nom);
          expect(export.fichier.format, format);
          expect(export.fichier.source, source);
          expect(export.fichier.tailleOctets, contenu.length);
          expect(export.fichier.validation, ValidationInitiale.formatReconnu);
          expect(export.fichier.id, startsWith('export-'));
          final relu = [await for (final m in export.lireContenu()) ...m];
          expect(relu, contenu);
          expect(() => export.lireContenu().first, throwsStateError);
          await export.liberer();
        }
      },
    );

    test(
      'taille inconnue (partage) : déduite si le fichier est court',
      () async {
        final court = await SelectionExportWhatsApp().verifier(
          _brut('chat.txt', _txt, tailleInconnue: true),
        );
        expect(
          (court as SelectionReussie).export.fichier.tailleOctets,
          _txt.length,
        );
        final long = await SelectionExportWhatsApp().verifier(
          FichierBrut(
            nom: 'chat.zip',
            source: SourceReception.partageAndroid,
            flux: Stream.fromIterable([
              [..._zip, ...List.filled(5000, 1)],
              List.filled(5000, 1),
            ]),
          ),
        );
        expect((long as SelectionReussie).export.fichier.tailleOctets, isNull);
        await long.export.liberer();
      },
    );

    test('identifiants temporaires distincts', () async {
      final a = await SelectionExportWhatsApp().verifier(_brut('a.txt', _txt));
      final b = await SelectionExportWhatsApp().verifier(_brut('a.txt', _txt));
      expect(
        (a as SelectionReussie).export.fichier.id,
        isNot((b as SelectionReussie).export.fichier.id),
      );
    });
  });
}
