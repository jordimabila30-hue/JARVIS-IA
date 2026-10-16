// Campagne de tests : les cinq exports FICTIFS de tests_whatsapp/ passent
// réellement dans le parseur de l'application (ZIP → lecture → analyse),
// et correspondent au manifeste (nombre, participants, période, dernier
// auteur, messages de référence). Mesure du temps de lecture.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/export_whatsapp.dart';
import 'package:ia_jarvis/services/importation/lecture_whatsapp.dart';
import 'package:ia_jarvis/services/importation/selection_export_whatsapp.dart';

Future<(ConversationWhatsApp, int)> _lire(File zip) async {
  final octets = await zip.readAsBytes();
  final chrono = Stopwatch()..start();
  final r = await SelectionExportWhatsApp().verifier(
    FichierBrut(
      nom: zip.uri.pathSegments.last,
      source: SourceReception.selecteur,
      tailleOctets: octets.length,
      flux: Stream.value(octets),
    ),
  );
  final lecteur = LecteurWhatsApp((r as SelectionReussie).export);
  final lu = await lecteur.lire();
  await lecteur.liberer();
  chrono.stop();
  return ((lu as LectureReussie).conversation, chrono.elapsedMilliseconds);
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/'
    '${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

void main() {
  final dossier = Directory('tests_whatsapp');
  final manifeste =
      jsonDecode(File('tests_whatsapp/manifeste.json').readAsStringSync())
          as Map<String, dynamic>;

  for (final c
      in (manifeste['conversations'] as List).cast<Map<String, dynamic>>()) {
    test('${c['zip']} : lu par le parseur, conforme au manifeste', () async {
      final (conv, ms) = await _lire(File('${dossier.path}/${c['zip']}'));
      final humains = conv.messages.where((m) => m.auteur != null).toList();
      // ignore: avoid_print
      print(
        '${c['zip']} : ${conv.messages.length} lignes, ${humains.length} '
        'messages, lecture $ms ms, titre « ${conv.titre} »',
      );
      expect(conv.titre, c['contact']);
      expect(conv.messages.length, c['lignes_export']);
      expect(humains.length, c['messages']);
      expect(conv.dateIncertaine, isFalse);
      expect(
        conv.participants.map((p) => p.nom).toSet(),
        (c['participants'] as List).toSet(),
      );
      expect(_date(humains.first.date!), c['debut']);
      expect(_date(humains.last.date!), c['fin']);
      expect(humains.last.auteur, c['dernier_auteur']);
      expect(humains.last.texte, c['dernier_message']);
      // Messages de référence : même auteur, même texte, même date, à leur
      // rang (rang = ordre du message dans l'export).
      (c['ancres'] as Map<String, dynamic>).forEach((nom, a) {
        final m = conv.messages[a['rang'] as int];
        expect(m.ordre, a['rang'], reason: nom);
        expect((m.auteur, m.texte), (a['auteur'], a['texte']), reason: nom);
        expect(_date(m.date!), a['date'], reason: nom);
      });
    });
  }
}
