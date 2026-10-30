// Recherche du menu (session EF, opt. 31) : exactitude et coût par frappe
// sur un historique volumineux.

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/conversations/apercu_conversation.dart';
import 'package:ia_jarvis/models/conversations/source_conversation.dart';
import 'package:ia_jarvis/services/conversations/conversations_multicanal.dart';
import 'package:ia_jarvis/services/conversations/epingles_conversations.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

import 'fixtures/conversations_demo.dart';

const _titres = [
  'Réunion de l’équipe',
  'Anniversaire de Léa',
  'Facture électricité',
  'Vacances à Kinshasa',
  'Projet Jarvis',
  'Cœur de métier',
];

List<ApercuConversation> _historique(int n) => [
  for (var i = 0; i < n; i++)
    ApercuConversation(
      source: SourceConversation.jarvis,
      id: 'c$i',
      titre: '${_titres[i % _titres.length]} n°$i',
      apercu: 'Dernier message échangé à propos du sujet numéro $i, déjà lu.',
      derniereActivite: DateTime(2026, 1, 1).add(Duration(minutes: i)),
    ),
];

ConversationsMulticanal _multicanal(int n) => ConversationsMulticanal(
  fournisseurs: [FournisseurDemo(SourceConversation.jarvis, _historique(n))],
  epingles: EpinglesConversations(stockage: StockageMemoire()),
);

void main() {
  test('casse et accents ignorés, résultat du texte actuel', () {
    final m = _multicanal(60);
    List<String> ids(String q) => [
      for (final c in m.liste(SourceConversation.jarvis, requete: q)) c.id,
    ];
    expect(ids('REUNION'), hasLength(10));
    expect(ids('lea'), hasLength(10));
    expect(ids('coeur'), hasLength(10));
    expect(ids('kinshasa n°3'), containsAll(['c3', 'c33']));
    expect(ids('introuvable'), isEmpty);
    expect(ids(''), hasLength(60));
    // Plus récente d'abord, inchangé par la recherche.
    expect(ids('').first, 'c59');
    m.dispose();
  });

  test('saisie rapide sur 2 000 conversations : coût par frappe', () {
    final m = _multicanal(2000);
    const requete = 'facture electricite';
    // Première liste (comme l'ouverture du menu), puis une frappe à la fois.
    m.liste(SourceConversation.jarvis);
    final chrono = Stopwatch()..start();
    var resultats = 0;
    for (var k = 1; k <= requete.length; k++) {
      resultats = m
          .liste(SourceConversation.jarvis, requete: requete.substring(0, k))
          .length;
    }
    chrono.stop();
    final parFrappe = chrono.elapsedMicroseconds / requete.length / 1000;
    // ignore: avoid_print
    print(
      'RECHERCHE 2000 conversations : ${parFrappe.toStringAsFixed(2)} ms '
      'par frappe',
    );
    expect(resultats, 333);
    m.dispose();
  });
}
