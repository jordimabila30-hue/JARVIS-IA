import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/export_whatsapp.dart';
import 'package:ia_jarvis/services/importation/analyseur_whatsapp.dart';
import 'package:ia_jarvis/services/importation/archive_zip.dart';
import 'package:ia_jarvis/services/importation/export_local.dart';
import 'package:ia_jarvis/services/importation/identite_whatsapp.dart';
import 'package:ia_jarvis/services/importation/lecture_whatsapp.dart';
import 'package:ia_jarvis/services/importation/selection_export_whatsapp.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

ConversationWhatsApp _lire(String texte, {String nom = 'chat.txt'}) {
  final a = AnalyseurWhatsApp();
  for (final l in const LineSplitter().convert(texte)) {
    a.ajouterLigne(l);
  }
  return a.terminer(nomFichier: nom);
}

Future<ExportWhatsAppChoisi> _export(String nom, List<int> octets) async {
  final r = await SelectionExportWhatsApp().verifier(
    FichierBrut(
      nom: nom,
      source: SourceReception.selecteur,
      tailleOctets: octets.length,
      flux: Stream.fromIterable([
        for (var i = 0; i < octets.length; i += 3000)
          octets.sublist(
            i,
            i + 3000 > octets.length ? octets.length : i + 3000,
          ),
      ]),
    ),
  );
  return (r as SelectionReussie).export;
}

Uint8List _zip(Map<String, List<int>> fichiers) {
  final archive = Archive();
  fichiers.forEach((nom, octets) {
    archive.addFile(ArchiveFile.bytes(nom, octets));
  });
  return ZipEncoder().encodeBytes(archive);
}

const _android = '''
11/10/2026, 14:30 - Les messages et les appels sont chiffrés de bout en bout.
11/10/2026, 14:30 - Tony Stark: Salut Jordi !
11/10/2026, 14:32 - Jordi: Salut Tony.
11/10/2026, 14:35 - Tony Stark: Tu as terminé le projet ?
11/10/2026, 14:36 - Jordi: Pas encore.
Je termine la dernière partie.

Promis.
12/10/2026, 09:12 - Tony Stark: <Médias omis>
12/10/2026, 09:13 - Tony Stark: Ce message a été supprimé
13/10/2026, 18:01 - Jordi: IMG-20261013-WA0001.jpg (fichier joint)
Regarde ça
13/10/2026, 18:02 - Jordi: PTT-20261013-WA0002.opus (fichier joint)
''';

void main() {
  group('analyseur : Android', () {
    late ConversationWhatsApp c;
    setUp(
      () => c = _lire(_android, nom: 'Discussion WhatsApp avec Tony Stark.txt'),
    );

    test('nombre exact, ordre d’origine, aucun message inventé', () {
      expect(c.messages, hasLength(9));
      expect(c.messages.map((m) => m.ordre), List.generate(9, (i) => i));
      expect(c.messages.map((m) => m.id).toSet(), hasLength(9));
      expect(c.nombreLignesNonRattachees, 0);
    });

    test('participants, titre d’après le nom du fichier', () {
      expect(c.titre, 'Tony Stark');
      expect(c.participants.map((p) => p.nom), ['Jordi', 'Tony Stark']);
      expect(c.participants.map((p) => p.messages), [4, 4]);
      expect(c.estGroupe, isFalse);
    });

    test('message sur plusieurs lignes : un seul message, texte exact', () {
      final m = c.messages[4];
      expect(m.auteur, 'Jordi');
      expect(m.texte, 'Pas encore.\nJe termine la dernière partie.\n\nPromis.');
    });

    test('système, supprimé, médias (type d’après le fichier)', () {
      expect(c.messages[0].type, TypeMessageWhatsApp.systeme);
      expect(c.messages[0].auteur, isNull);
      expect(c.messages[5].type, TypeMessageWhatsApp.media);
      expect(c.messages[5].typeMedia, TypeMediaWhatsApp.inconnu);
      expect(c.messages[6].type, TypeMessageWhatsApp.supprime);
      expect(c.messages[7].type, TypeMessageWhatsApp.media);
      expect(c.messages[7].typeMedia, TypeMediaWhatsApp.image);
      expect(c.messages[7].nomFichierMedia, 'IMG-20261013-WA0001.jpg');
      expect(c.messages[7].texte, contains('Regarde ça'));
      expect(c.messages[8].typeMedia, TypeMediaWhatsApp.vocal);
      expect(c.nombreMedias, 3);
    });

    test('dates : jour d’abord (13 > 12), période', () {
      expect(c.ordreDate, OrdreDate.jourMoisAnnee);
      expect(c.dateIncertaine, isFalse);
      expect(c.messages[1].date, DateTime(2026, 10, 11, 14, 30));
      expect(c.debut, DateTime(2026, 10, 11, 14, 30));
      expect(c.fin, DateTime(2026, 10, 13, 18, 2));
      expect(c.messages[1].dateBrute, '11/10/2026, 14:30 -');
    });

    test('empreinte stable et distincte', () {
      final d = _lire(_android);
      expect(c.messages[1].empreinte, d.messages[1].empreinte);
      expect(c.messages[1].empreinte, isNot(c.messages[2].empreinte));
      expect(c.messages[1].empreinte, hasLength(16));
    });
  });

  group('analyseur : iOS et autres langues', () {
    test('iOS : crochets, secondes, marques invisibles, système, omis', () {
      final c = _lire(
        '\u200e[11/10/2026, 14:30:12] Tony Stark: \u200eLes messages et les '
        'appels sont chiffrés de bout en bout.\n'
        '[11/10/2026, 14:30:15] Tony Stark: Bonjour !\n'
        '[11/10/2026, 14:31:02] Jordi: \u200eimage absente\n'
        '[11/10/2026, 14:31:40] Jordi: <pièce jointe : 00000012-PHOTO-2026-10-11.jpg>\n'
        '\u200e[11/10/2026, 14:32:00] Tony Stark: \u200eCe message a été supprimé.\n',
        nom: '_chat.txt',
      );
      expect(c.messages, hasLength(5));
      expect(c.messages[0].type, TypeMessageWhatsApp.systeme);
      expect(c.messages[0].auteur, isNull);
      expect(c.messages[1].date, DateTime(2026, 10, 11, 14, 30, 15));
      expect(c.messages[2].typeMedia, TypeMediaWhatsApp.image);
      expect(c.messages[3].nomFichierMedia, '00000012-PHOTO-2026-10-11.jpg');
      expect(c.messages[4].type, TypeMessageWhatsApp.supprime);
      expect(c.participants.map((p) => p.nom), ['Jordi', 'Tony Stark']);
      // Pas de titre dans « _chat.txt » : les participants.
      expect(c.titre, 'Jordi et Tony Stark');
    });

    test('anglais 12 h (AM/PM, espace insécable iOS 17), mois d’abord', () {
      final c = _lire(
        '10/11/26, 2:30\u202fPM - Tony Stark: Hi!\n'
        '10/11/26, 11:59 PM - Jordi: Late\n'
        '10/13/26, 12:05 AM - Tony Stark: Early\n'
        '[10/14/26, 12:00:01 PM] Jordi: Noon\n',
      );
      expect(c.ordreDate, OrdreDate.moisJourAnnee);
      expect(c.dateIncertaine, isFalse);
      expect(c.messages[0].date, DateTime(2026, 10, 11, 14, 30));
      expect(c.messages[1].date, DateTime(2026, 10, 11, 23, 59));
      expect(c.messages[2].date, DateTime(2026, 10, 13, 0, 5));
      expect(c.messages[3].date, DateTime(2026, 10, 14, 12, 0, 1));
    });

    test('espagnol « p. m. », allemand (points), ISO, sans virgule', () {
      final es = _lire('11/10/26, 2:30 p. m. - Ana: Hola\n');
      expect(es.messages.single.date, DateTime(2026, 10, 11, 14, 30));
      expect(es.dateIncertaine, isTrue);
      final de = _lire(
        '11.10.26, 14:30 - Tony: Hallo\n13.10.26, 08:00 - Tony: Na?\n',
      );
      expect(de.messages.first.date, DateTime(2026, 10, 11, 14, 30));
      final iso = _lire('2026-10-11, 14:30 - Tony: Hello\n');
      expect(iso.ordreDate, OrdreDate.anneeMoisJour);
      expect(iso.messages.single.date, DateTime(2026, 10, 11, 14, 30));
      expect(
        _lire('11/10/2026 14:30 - Tony: Salut\n').messages.single.auteur,
        'Tony',
      );
    });

    test('date ambiguë : départagée par l’ordre chronologique', () {
      // 05/03 puis 04/06 : jour/mois donne 5 mars → 4 juin (avance),
      // mois/jour donne 3 mai → 6 avril (recul).
      final c = _lire(
        '05/03/2026, 10:00 - A: un\n04/06/2026, 10:00 - B: deux\n',
      );
      expect(c.ordreDate, OrdreDate.jourMoisAnnee);
      expect(c.dateIncertaine, isFalse);
    });

    test('date indiscernable : signalée incertaine, brute conservée', () {
      final c = _lire(
        '05/03/2026, 10:00 - A: un\n05/03/2026, 11:00 - B: deux\n',
      );
      expect(c.dateIncertaine, isTrue);
      expect(c.messages.first.dateBrute, '05/03/2026, 10:00 -');
    });

    test('date impossible : nulle, jamais corrigée en silence', () {
      final c = _lire(
        '31/02/2026, 10:00 - A: un\n13/02/2026, 10:00 - A: deux\n',
      );
      expect(c.messages.first.date, isNull);
      expect(c.messages.first.dateBrute, startsWith('31/02/2026'));
      expect(c.messages.last.date, DateTime(2026, 2, 13, 10));
    });

    test('groupe : tous les auteurs, aucun « Moi + contact » forcé', () {
      final c = _lire(
        '11/10/2026, 10:00 - Tony: a\n11/10/2026, 10:01 - Pepper: b\n'
        '11/10/2026, 10:02 - Happy: c\n11/10/2026, 10:03 - Tony: d\n'
        '11/10/2026, 10:04 - Tony a ajouté Happy\n',
      );
      expect(c.participants.map((p) => p.nom), ['Tony', 'Happy', 'Pepper']);
      expect(c.estGroupe, isTrue);
      expect(c.messages.last.type, TypeMessageWhatsApp.systeme);
      expect(c.titre, 'Groupe de 3 participants');
    });

    test('lignes avant le premier message : comptées, jamais perdues', () {
      final c = _lire('Ceci n’est pas un message\n11/10/2026, 10:00 - A: un\n');
      expect(c.messages, hasLength(1));
      expect(c.nombreLignesNonRattachees, 1);
      expect(c.lignesNonRattachees.single, 'Ceci n’est pas un message');
    });

    test('titres d’après le nom du fichier', () {
      expect(
        AnalyseurWhatsApp.titreDepuisNom('WhatsApp Chat - Tony Stark.zip'),
        'Tony Stark',
      );
      expect(
        AnalyseurWhatsApp.titreDepuisNom('WhatsApp Chat with Pepper (1).txt'),
        'Pepper',
      );
      expect(AnalyseurWhatsApp.titreDepuisNom('notes.txt'), isNull);
    });

    test('long historique : 30 000 messages sur 6 ans, sans limite', () {
      final b = StringBuffer();
      var d = DateTime(2020, 1, 1, 8);
      for (var i = 0; i < 30000; i++) {
        final j = d.day.toString().padLeft(2, '0');
        final m = d.month.toString().padLeft(2, '0');
        b.writeln(
          '$j/$m/${d.year}, 08:00 - ${i.isEven ? 'Tony' : 'Jordi'}: message $i',
        );
        d = d.add(const Duration(hours: 2));
      }
      final c = _lire(b.toString());
      expect(c.messages, hasLength(30000));
      expect(c.messages.last.texte, 'message 29999');
      expect(c.debut!.year, 2020);
      expect(c.fin!.year, 2026);
    });
  });

  group('lecture complète (TXT, ZIP)', () {
    Future<ResultatLecture> lire(
      String nom,
      List<int> octets, {
      String? entree,
      Annulation? annulation,
    }) async {
      final lecteur = LecteurWhatsApp(await _export(nom, octets));
      final r = await lecteur.lire(
        entreeChoisie: entree,
        annulation: annulation,
      );
      await lecteur.liberer();
      return r;
    }

    test('TXT : messages, progression réelle', () async {
      final etapes = <(EtapeLecture, double?)>[];
      final lecteur = LecteurWhatsApp(
        await _export('chat.txt', utf8.encode(_android)),
      );
      final r = await lecteur.lire(progression: (e, f) => etapes.add((e, f)));
      expect((r as LectureReussie).conversation.messages, hasLength(9));
      expect(etapes.first.$1, EtapeLecture.copie);
      expect(etapes.any((e) => e.$1 == EtapeLecture.messages), isTrue);
      expect(
        etapes.where((e) => e.$2 != null).every((e) => e.$2! <= 1),
        isTrue,
      );
    });

    test('TXT UTF-16 (marque d’ordre)', () async {
      final unites = '\ufeff11/10/2026, 10:00 - Tony: Salut\n'.codeUnits;
      final octets = <int>[
        for (final u in unites) ...[u & 0xFF, u >> 8],
      ];
      final r = await lire('chat.txt', octets);
      expect((r as LectureReussie).conversation.messages.single.texte, 'Salut');
    });

    test('TXT sans aucun message reconnu : refus clair', () async {
      final r = await lire(
        'notes.txt',
        utf8.encode('Liste de courses\nPain\n'),
      );
      expect((r as LectureEchouee).erreur, ErreurLecture.formatNonReconnu);
    });

    test('ZIP avec TXT et médias : seul le texte est lu', () async {
      final r = await lire(
        'WhatsApp Chat - Tony Stark.zip',
        _zip({
          'WhatsApp Chat - Tony Stark.txt': utf8.encode(_android),
          'IMG-20261013-WA0001.jpg': List.filled(5000, 7),
          'PTT-20261013-WA0002.opus': List.filled(3000, 9),
        }),
      );
      final c = (r as LectureReussie).conversation;
      expect(c.messages, hasLength(9));
      expect(c.titre, 'Tony Stark');
      expect(c.nomFichier, 'WhatsApp Chat - Tony Stark.txt');
    });

    test(
      'ZIP iOS (« _chat.txt ») avec un autre TXT : le bon est choisi',
      () async {
        final r = await lire(
          'WhatsApp Chat - Tony Stark.zip',
          _zip({
            '_chat.txt': utf8.encode(_android),
            'notes.txt': utf8.encode('autre chose'),
          }),
        );
        expect((r as LectureReussie).conversation.messages, hasLength(9));
      },
    );

    test(
      'ZIP avec plusieurs TXT indiscernables : l’utilisateur choisit',
      () async {
        final octets = _zip({
          'a.txt': utf8.encode(_android),
          'b.txt': utf8.encode(_android),
        });
        final lecteur = LecteurWhatsApp(await _export('export.zip', octets));
        final r = await lecteur.lire();
        expect((r as ChoixFichierRequis).candidats.map((e) => e.nom), [
          'a.txt',
          'b.txt',
        ]);
        // Deuxième lecture avec le choix, sans relire le fichier d'origine.
        final r2 = await lecteur.lire(entreeChoisie: 'b.txt');
        expect((r2 as LectureReussie).conversation.nomFichier, 'b.txt');
        await lecteur.liberer();
      },
    );

    test('ZIP sans fichier de discussion', () async {
      final r = await lire(
        'export.zip',
        _zip({
          'IMG-1.jpg': [1, 2, 3],
        }),
      );
      expect((r as LectureEchouee).erreur, ErreurLecture.aucuneConversation);
    });

    test('ZIP corrompu (index illisible)', () async {
      final zip = _zip({'_chat.txt': utf8.encode(_android)});
      final abime = Uint8List.fromList(zip.sublist(0, zip.length - 30));
      final r = await lire('export.zip', abime);
      expect((r as LectureEchouee).erreur, ErreurLecture.archiveEndommagee);
    });

    test('chemins dangereux : ignorés (jamais lus ni écrits)', () {
      bool c(String nom) => LecteurWhatsApp.estCandidat(
        EntreeArchive(nom: nom, taille: 10, tailleCompressee: 10),
      );
      expect(c('../../etc/chat.txt'), isFalse);
      expect(c('/abs/chat.txt'), isFalse);
      expect(c('C:/Windows/chat.txt'), isFalse);
      expect(c('..\\chat.txt'), isFalse);
      expect(c('__MACOSX/._chat.txt'), isFalse);
      expect(c('dossier/_chat.txt'), isTrue);
      expect(c('photo.jpg'), isFalse);
    });

    test('décompression au-delà de la limite : arrêtée net', () {
      final zip = _zip({'_chat.txt': List.filled(100000, 0x41)});
      expect(
        () => extraireEntreeZip(InputMemoryStream(zip), '_chat.txt', 1000),
        throwsA(isA<ArchiveDemesuree>()),
      );
      expect(
        extraireEntreeZip(InputMemoryStream(zip), '_chat.txt', 1 << 20),
        hasLength(100000),
      );
    });

    test('annulation : arrêt propre', () async {
      final a = Annulation()..annuler();
      final r = await lire('chat.txt', utf8.encode(_android), annulation: a);
      expect(r, isA<LectureAnnulee>());
    });

    test('archive volumineuse (40 Mo de médias) : seul le texte est '
        'décompressé', () async {
      final r = await lire(
        'export.zip',
        _zip({
          '_chat.txt': utf8.encode(_android),
          for (var i = 0; i < 4; i++) 'VID-$i.mp4': Uint8List(10 << 20),
        }),
      );
      expect((r as LectureReussie).conversation.messages, hasLength(9));
    });
  });

  group('identité « Moi »', () {
    test('confirmée une fois, reconnue ensuite, corrigeable', () async {
      final stockage = StockageMemoire();
      final c = _lire(_android);
      final id = IdentiteWhatsApp(stockage: stockage);
      await id.charger();
      expect(id.reconnaitre(c), isNull);
      await id.confirmer('Jordi');
      final relue = IdentiteWhatsApp(stockage: stockage);
      await relue.charger();
      expect(relue.reconnaitre(c), 'Jordi');
      await relue.confirmer('Tony Stark', ancien: 'Jordi');
      expect(relue.reconnaitre(c), 'Tony Stark');
    });
  });
}
