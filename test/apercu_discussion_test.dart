import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/pages/resume_whatsapp_page.dart';
import 'package:ia_jarvis/services/importation/analyseur_whatsapp.dart';
import 'package:ia_jarvis/widgets/importation/apercu_discussion.dart';

ConversationWhatsApp _lire(String texte, {String nom = 'chat.txt'}) {
  final a = AnalyseurWhatsApp();
  for (final l in const LineSplitter().convert(texte)) {
    a.ajouterLigne(l);
  }
  return a.terminer(nomFichier: nom);
}

/// Les messages, dans l'ordre où l'aperçu les présente.
List<MessageWhatsApp> _aplatir(List<ElementApercu> elements) => [
  for (final e in elements)
    ...switch (e) {
      JourApercu() => const <MessageWhatsApp>[],
      MessageApercu(:final message) => [message],
      MediasApercu(:final medias) => medias,
    },
];

/// Chaque séparateur porte le jour réel de tous les messages placés
/// dessous, jusqu'au séparateur suivant.
void _verifierSeparateurs(List<ElementApercu> elements) {
  DateTime? jour;
  var vu = false;
  for (final e in elements) {
    if (e is JourApercu) {
      jour = e.jour;
      vu = true;
      continue;
    }
    expect(vu, isTrue, reason: 'message avant tout séparateur');
    final messages = switch (e) {
      MessageApercu(:final message) => [message],
      MediasApercu(:final medias) => medias,
      JourApercu() => const <MessageWhatsApp>[],
    };
    for (final m in messages) {
      final d = m.date;
      expect(
        d == null ? null : DateTime(d.year, d.month, d.day),
        jour,
        reason: '${m.dateBrute} sous « ${SeparateurJour.libelle(jour)} »',
      );
    }
  }
}

// Export Android (fr) horodaté : passage de minuit, petite inversion
// d'ordre propre à l'export (un message de 23:59 noté après un de 00:01),
// message sur plusieurs lignes, médias en série, date illisible.
const _horodate = '''
06/09/2026 23:57 - Ada: Il est tard
06/09/2026 23:58 - Alan: Oui
on finit demain
07/09/2026 00:01 - Ada: Minuit passé
06/09/2026 23:59 - Alan: (envoyé avant minuit, reçu après)
07/09/2026 00:02 - Ada: IMG-20260907-WA0001.jpg (fichier joint)
07/09/2026 00:02 - Ada: IMG-20260907-WA0002.jpg (fichier joint)
07/09/2026 00:03 - Ada: VID-20260907-WA0003.mp4 (fichier joint)
07/09/2026 00:03 - Ada: IMG-20260907-WA0004.jpg (fichier joint)
Avec une légende
07/09/2026 00:04 - Alan: <Médias omis>
07/09/2026 00:04 - Alan: <Médias omis>
31/02/2026 10:00 - Alan: date illisible
13/09/2026 08:15 - Ada: Bonjour
''';

void main() {
  group('dates : interprétation exacte', () {
    final c = _lire(_horodate);

    test('date brute, interprétation, heure, ordre d’origine', () {
      expect(c.ordreDate, OrdreDate.jourMoisAnnee);
      expect(c.dateIncertaine, isFalse);
      expect(c.messages.map((m) => m.ordre), List.generate(12, (i) => i));
      expect(c.messages[0].dateBrute, '06/09/2026 23:57 -');
      expect(c.messages[0].date, DateTime(2026, 9, 6, 23, 57));
      expect(c.messages[2].date, DateTime(2026, 9, 7, 0, 1));
      // Inversion présente dans l'export : gardée telle quelle, sans
      // réordonner ni corriger la date.
      expect(c.messages[3].date, DateTime(2026, 9, 6, 23, 59));
      expect(c.messages[10].date, isNull);
      expect(c.messages[10].dateBrute, startsWith('31/02/2026'));
      expect(c.messages[11].date, DateTime(2026, 9, 13, 8, 15));
    });

    test('la date du nom des photos confirme l’interprétation', () {
      for (final m in c.messages) {
        final f = m.nomFichierMedia;
        if (f == null) continue;
        final d = RegExp(r'-(\d{4})(\d{2})(\d{2})-').firstMatch(f)!;
        expect(
          DateTime(int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!)),
          DateTime(m.date!.year, m.date!.month, m.date!.day),
        );
      }
    });

    test('jour ambigu (≤ 12) départagé : 06/09 reste le 6 septembre', () {
      // Sans aucun jour > 12, l'ordre chronologique tranche (août → sept.).
      final a = _lire(
        '28/08/2026 10:00 - Ada: a\n'
        '06/09/2026 21:01 - Ada: <Médias omis>\n'
        '07/09/2026 09:00 - Alan: b\n',
      );
      expect(a.messages[1].date, DateTime(2026, 9, 6, 21, 1));
      final b = _lire(
        '02/08/2026 10:00 - Ada: a\n'
        '06/09/2026 21:01 - Ada: b\n'
        '01/10/2026 09:00 - Alan: c\n',
      );
      expect(b.dateIncertaine, isFalse);
      expect(b.messages[1].date, DateTime(2026, 9, 6, 21, 1));
    });
  });

  group('aperçu : regroupement par jour', () {
    final c = _lire(_horodate);
    final elements = elementsApercu(c.messages);

    test('aucun message perdu, ajouté ou déplacé', () {
      expect(_aplatir(elements), c.messages);
    });

    test('chaque séparateur correspond aux messages dessous', () {
      _verifierSeparateurs(elements);
      final jours = [
        for (final e in elements)
          if (e is JourApercu) SeparateurJour.libelle(e.jour),
      ];
      expect(jours, [
        'dimanche 6 septembre 2026',
        'lundi 7 septembre 2026',
        // L'inversion de l'export : le message de 23:59 sous son vrai jour.
        'dimanche 6 septembre 2026',
        'lundi 7 septembre 2026',
        SeparateurJour.dateIllisible,
        'dimanche 13 septembre 2026',
      ]);
    });

    test('multiligne : une seule bulle, texte intact', () {
      final m = elements.whereType<MessageApercu>().firstWhere(
        (e) => e.message.auteur == 'Alan',
      );
      expect(m.message.texte, 'Oui\non finit demain');
    });

    test('médias en série regroupés (affichage seulement)', () {
      final groupes = elements.whereType<MediasApercu>().toList();
      // 3 médias d'Ada sans légende ; le 4e a une légende (bulle à part) ;
      // les 2 d'Alan restent séparés (sous le seuil).
      expect(groupes, hasLength(1));
      expect(groupes.single.medias.map((m) => m.ordre), [4, 5, 6]);
      expect(BulleMediasGroupes.plage(groupes.single.medias), '00:02 – 00:03');
      expect(c.nombreMedias, 6);
    });

    test('noms : en tête de chaque suite, et après chaque séparateur', () {
      final debuts = [
        for (final e in elements)
          if (e is MessageApercu && e.debutSuite) e.message.ordre,
      ];
      expect(debuts, [0, 1, 2, 3, 8, 10, 11]);
    });
  });

  test('séparateurs fiables sur un long export (30 000 messages)', () {
    final b = StringBuffer();
    var d = DateTime(2020, 1, 1, 8);
    for (var i = 0; i < 30000; i++) {
      String deux(int v) => v.toString().padLeft(2, '0');
      b.writeln(
        '${deux(d.day)}/${deux(d.month)}/${d.year} '
        '${deux(d.hour)}:${deux(d.minute)} - ${i.isEven ? 'A' : 'B'}: m$i',
      );
      d = d.add(const Duration(minutes: 97));
    }
    final c = _lire(b.toString());
    final elements = elementsApercu(c.messages);
    expect(_aplatir(elements), hasLength(30000));
    _verifierSeparateurs(elements);
  });

  test(
    'avis de chiffrement : masqué dans l’aperçu, gardé dans les données',
    () {
      final c = _lire(
        '06/09/2026 21:00 - Les messages et les appels sont chiffrés de bout '
        'en bout. Appuyez pour en savoir plus.\n'
        '06/09/2026 21:01 - Ada a créé le groupe\n'
        '06/09/2026 21:02 - Ada: Salut\n',
      );
      expect(c.messages, hasLength(3));
      expect(estAvisChiffrement(c.messages.first), isTrue);
      final elements = elementsApercu(c.messages);
      expect(_aplatir(elements), c.messages.sublist(1));
      _verifierSeparateurs(elements);
      // Un autre événement système reste visible.
      expect(estAvisChiffrement(c.messages[1]), isFalse);
    },
  );

  test('côtés stables à deux, tous à gauche en groupe', () {
    final duo = DispositionAuteurs(_lire(_horodate));
    expect(duo.cote('Ada'), CoteBulle.gauche);
    expect(duo.cote('Alan'), CoteBulle.droite);
    final groupe = DispositionAuteurs(
      _lire(
        '11/10/2026 10:00 - A: a\n11/10/2026 10:01 - B: b\n'
        '11/10/2026 10:02 - C: c\n',
      ),
    );
    expect(groupe.cote('B'), CoteBulle.gauche);
    expect(groupe.couleur('A'), isNot(groupe.couleur('B')));
  });

  test('période couverte', () {
    expect(
      ResumeWhatsAppPage.periode(DateTime(2026, 9, 6), DateTime(2026, 9, 6)),
      '6 septembre 2026',
    );
    expect(
      ResumeWhatsAppPage.periode(DateTime(2026, 10, 1), DateTime(2026, 10, 11)),
      '1er – 11 octobre 2026',
    );
    expect(
      ResumeWhatsAppPage.periode(DateTime(2026, 7, 3), DateTime(2026, 10, 11)),
      '3 juillet – 11 octobre 2026',
    );
    expect(
      ResumeWhatsAppPage.periode(DateTime(2020, 1, 1), DateTime(2026, 3, 15)),
      '1er janvier 2020 – 15 mars 2026',
    );
  });
}
