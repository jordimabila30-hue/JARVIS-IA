import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/filtre_whatsapp.dart';
import 'package:ia_jarvis/services/importation/index_whatsapp.dart';
import 'package:ia_jarvis/services/importation/selection_whatsapp.dart';

import 'outils/conversations_whatsapp.dart';

// Maintenant : mercredi 14 octobre 2026, 10:00 (heure locale).
final maintenant = DateTime(2026, 10, 14, 10);

List<String> ids(SelectionWhatsApp s) => s.resultat().ids;

void main() {
  // Une conversation qui couvre plusieurs jours, mois et années, un
  // passage de minuit, une date illisible et un événement de WhatsApp.
  late ConversationWhatsApp c;
  late SelectionWhatsApp s;

  setUp(() {
    c = conv([
      msg(0, DateTime(2025, 12, 31, 23, 58), texte: 'avant minuit'),
      msg(1, DateTime(2026, 1, 1, 0, 2), texte: 'après minuit'),
      msg(2, null, texte: 'date illisible'),
      msg(3, DateTime(2026, 9, 30, 12), texte: 'septembre'),
      msg(4, DateTime(2026, 10, 7, 23, 59, 30), texte: 'il y a 7 jours'),
      msg(5, DateTime(2026, 10, 8, 0, 0, 5), texte: 'il y a 6 jours'),
      msg(
        6,
        DateTime(2026, 10, 13, 8),
        type: TypeMessageWhatsApp.systeme,
        texte: 'Alan a rejoint le groupe',
      ),
      msg(7, DateTime(2026, 10, 13, 18), auteur: 'Alan', texte: 'hier'),
      msg(8, DateTime(2026, 10, 14, 9, 15), texte: 'aujourd’hui'),
      msg(9, DateTime(2026, 10, 14, 14, 30, 45), texte: 'cet après-midi'),
    ]);
    s = SelectionWhatsApp(c, horloge: () => maintenant);
  });

  group('index', () {
    test('seuls les messages des participants sont sélectionnables', () {
      expect(s.index.nombre, 9);
      expect(s.estSelectionnable('m6'), isFalse);
      expect(s.estSelectionnable('m2'), isTrue);
      expect(s.index.nombreSansDate, 1);
    });

    test('export dans le désordre : l’index chronologique reste juste', () {
      final i = IndexWhatsApp(
        conv([
          msg(0, DateTime(2026, 10, 1, 12)),
          msg(1, DateTime(2026, 10, 1, 11, 59)),
          msg(2, DateTime(2026, 10, 2, 9)),
          msg(3, DateTime(2026, 9, 30, 9)),
        ]),
      );
      expect(
        i.resultat(FiltrePeriode.jour(DateTime(2026, 10, 1)), maintenant),
        [0, 1],
      );
      expect(
        i.resultat(
          FiltrePeriode(DateTime(2026, 9, 30), DateTime(2026, 10, 1, 11, 59)),
          maintenant,
        ),
        [1, 3],
      );
    });

    test('calendrier : jours, mois et années ayant des messages', () {
      final i = s.index;
      expect(i.annees, [2025, 2026]);
      expect(i.joursDuMois(2026, 10), {7: 1, 8: 1, 13: 1, 14: 2});
      expect(i.joursDuMois(2026, 2), isEmpty);
      expect(i.moisAvecMessages(2026, 9), isTrue);
      expect(i.moisAvecMessages(2026, 8), isFalse);
      expect(i.nombreLeJour(DateTime(2026, 10, 14)), 2);
      // L'événement de WhatsApp n'est pas compté ; la date illisible
      // n'est rattachée à aucun jour.
      expect(i.nombreLeJour(DateTime(2026, 10, 13)), 1);
      expect(i.premierJour, DateTime(2025, 12, 31));
      expect(i.dernierJour, DateTime(2026, 10, 14));
    });
  });

  group('filtres temporels', () {
    test('aujourd’hui, hier, 7 derniers jours (date locale)', () {
      s.choisirCapsule(CapsulePeriode.aujourdhui);
      expect(ids(s), ['m8', 'm9']);
      s.choisirCapsule(CapsulePeriode.hier);
      expect(ids(s), ['m7']);
      s.choisirCapsule(CapsulePeriode.septJours);
      // Du 8 au 14 octobre : le message du 7 à 23:59 n'en est pas.
      expect(ids(s), ['m5', 'm7', 'm8', 'm9']);
    });

    test('aujourd’hui sans message : aucun résultat', () {
      final vide = SelectionWhatsApp(
        c,
        horloge: () => DateTime(2027, 3, 3, 12),
      );
      vide.choisirCapsule(CapsulePeriode.aujourdhui);
      expect(vide.nombreSelectionnes, 0);
      expect(vide.afficheCorrespondants, isTrue);
      expect(vide.visibles, isEmpty);
    });

    test('heures et minutes : bornes comprises, les secondes n’excluent '
        'rien', () {
      s.definirPeriode(
        FiltrePeriode(
          DateTime(2026, 10, 14, 9, 15),
          DateTime(2026, 10, 14, 14, 30),
        ),
      );
      expect(ids(s), ['m8', 'm9']);
      s.definirPeriode(
        FiltrePeriode(
          DateTime(2026, 10, 14, 9, 16),
          DateTime(2026, 10, 14, 14, 29),
        ),
      );
      expect(ids(s), isEmpty);
      // Des secondes données à la période sont ignorées.
      s.definirPeriode(
        FiltrePeriode(
          DateTime(2026, 10, 14, 14, 30, 50),
          DateTime(2026, 10, 14, 14, 30, 10),
        ),
      );
      expect(ids(s), ['m9']);
    });

    test('passage de minuit, plusieurs mois, plusieurs années', () {
      s.definirPeriode(
        FiltrePeriode(
          DateTime(2025, 12, 31, 23, 50),
          DateTime(2026, 1, 1, 0, 10),
        ),
      );
      expect(ids(s), ['m0', 'm1']);
      s.definirPeriode(
        FiltrePeriode.jours(DateTime(2026, 9, 1), DateTime(2026, 10, 8)),
      );
      expect(ids(s), ['m3', 'm4', 'm5']);
      s.definirPeriode(
        FiltrePeriode.jours(DateTime(2025, 1, 1), DateTime(2026, 12, 31)),
      );
      expect(s.nombreSelectionnes, 8);
      // Jamais la date illisible.
      expect(ids(s), isNot(contains('m2')));
    });

    test('intervalle inversé : signalé, la sélection ne change pas', () {
      s.choisirCapsule(CapsulePeriode.aujourdhui);
      s.definirPeriode(
        FiltrePeriode(
          DateTime(2026, 10, 14, 15),
          DateTime(2026, 10, 14, 9, 20),
        ),
      );
      expect(s.erreurPeriode, SelectionWhatsApp.finAvantDebut);
      expect(ids(s), ['m8', 'm9']);
      // Corrigé : appliqué.
      s.modifierDebut(DateTime(2026, 10, 14, 8));
      expect(s.erreurPeriode, isNull);
      expect(ids(s), ['m8']);
    });
  });

  group('derniers messages', () {
    test('10, 25, 50, 100', () {
      final l = SelectionWhatsApp(
        reguliere(240, DateTime(2026, 1, 1), const Duration(minutes: 7)),
        horloge: () => maintenant,
      );
      expect(l.nombresDerniers, [10, 25, 50, 100]);
      for (final n in [10, 25, 50, 100]) {
        l.choisirDerniers(n);
        expect(l.nombreSelectionnes, n);
        expect(ids(l).first, 'm${240 - n}');
        expect(ids(l).last, 'm239');
      }
    });

    test('historique plus court : borné au nombre réel', () {
      final l = SelectionWhatsApp(
        reguliere(30, DateTime(2026, 1, 1), const Duration(minutes: 7)),
        horloge: () => maintenant,
      );
      expect(l.nombresDerniers, [10, 25, 30]);
      l.choisirDerniers(100);
      expect(l.nombreSelectionnes, 30);
      // « Derniers messages » commence par le plus petit nombre.
      final m = SelectionWhatsApp(
        reguliere(6, DateTime(2026, 1, 1), const Duration(minutes: 7)),
      );
      expect(m.nombresDerniers, [6]);
      m.choisirCapsule(CapsulePeriode.derniers);
      expect(m.nombreSelectionnes, 6);
    });
  });

  group('calendrier', () {
    test('personnalisé : dernier jour ayant des messages, mois affiché', () {
      s.choisirCapsule(CapsulePeriode.personnalise);
      expect(s.periode, FiltrePeriode.jour(DateTime(2026, 10, 14)));
      expect(s.moisAffiche, DateTime(2026, 10));
      expect(ids(s), ['m8', 'm9']);
    });

    test('un jour, puis un autre : la période s’étend ; jour sans message '
        'ignoré', () {
      s.choisirCapsule(CapsulePeriode.personnalise);
      s.choisirJour(DateTime(2026, 10, 7));
      expect(s.periode, FiltrePeriode.jour(DateTime(2026, 10, 7)));
      expect(s.calendrierAttendFin, isTrue);
      s.choisirJour(DateTime(2026, 10, 10)); // aucun message
      expect(s.periode, FiltrePeriode.jour(DateTime(2026, 10, 7)));
      s.choisirJour(DateTime(2026, 10, 13));
      expect(
        s.periode,
        FiltrePeriode.jours(DateTime(2026, 10, 7), DateTime(2026, 10, 13)),
      );
      expect(ids(s), ['m4', 'm5', 'm7']);
      // Le toucher suivant recommence.
      s.choisirJour(DateTime(2026, 10, 8));
      expect(ids(s), ['m5']);
    });

    test('affinage par l’heure, puis date d’une borne depuis le '
        'calendrier : un seul état', () {
      s.choisirCapsule(CapsulePeriode.personnalise);
      s.modifierDebut(DateTime(2026, 10, 14, 10));
      expect(ids(s), ['m9']);
      s.ciblerDate(BornePeriode.debut);
      s.choisirJour(DateTime(2026, 10, 13));
      // Date changée, heure gardée (10:00).
      expect(s.periode!.debut, DateTime(2026, 10, 13, 10));
      expect(s.cible, isNull);
      expect(ids(s), ['m7', 'm8', 'm9']);
      expect(s.capsule, CapsulePeriode.personnalise);
    });

    test('navigation : mois et années', () {
      s.afficherMois(2025, 12);
      expect(s.moisAffiche, DateTime(2025, 12));
      s.afficherMois(2026, 1);
      expect(s.moisAffiche, DateTime(2026));
    });
  });

  group('sélection', () {
    test('plage par messages, dans un sens ou l’autre ; dates inconnues '
        'comprises', () {
      s.changerMode(ModeFiltrage.messages);
      s.commencerPlage();
      expect(s.premierDeLaPlage, isNull);
      s.designer('m4');
      expect(s.premierDeLaPlage, 'm4');
      s.designer('m1');
      expect(s.plageEnCours, isFalse);
      expect(ids(s), ['m1', 'm2', 'm3', 'm4']);
      // Un événement de WhatsApp ne peut pas être désigné.
      s.commencerPlage();
      s.designer('m6');
      expect(s.premierDeLaPlage, isNull);
    });

    test('cocher, décocher, recocher, compteur', () {
      s.changerMode(ModeFiltrage.messages);
      s.basculer('m2');
      s.basculer('m9');
      expect(s.nombreSelectionnes, 2);
      expect(ids(s), ['m2', 'm9']);
      s.basculer('m2');
      expect(ids(s), ['m9']);
      s.basculer('m2');
      expect(s.nombreSelectionnes, 2);
      s.basculer('m6'); // événement : sans effet
      expect(s.nombreSelectionnes, 2);
    });

    test('décochés gardés par le filtre suivant s’ils en font partie', () {
      s.choisirCapsule(CapsulePeriode.septJours);
      s.basculer('m8');
      s.basculer('m5');
      expect(ids(s), ['m7', 'm9']);
      // Aujourd'hui contient m8 (décoché) : il reste décoché.
      s.choisirCapsule(CapsulePeriode.aujourdhui);
      expect(ids(s), ['m9']);
      expect(s.correspondants.map((m) => m.id), ['m8', 'm9']);
      // m8 n'est pas dans « hier » : son exclusion n'a plus d'objet.
      s.choisirCapsule(CapsulePeriode.hier);
      s.choisirCapsule(CapsulePeriode.aujourdhui);
      expect(ids(s), ['m8', 'm9']);
    });

    test('groupe de médias : chaque identifiant reste individuel', () {
      final g = SelectionWhatsApp(
        conv([
          for (var i = 0; i < 4; i++)
            msg(
              i,
              DateTime(2026, 10, 1, 9, i),
              type: TypeMessageWhatsApp.media,
            ),
          msg(4, DateTime(2026, 10, 1, 9, 5)),
        ]),
      );
      g.cocher(['m0', 'm1', 'm2', 'm3'], true);
      expect(g.nombreSelectionnes, 4);
      g.basculer('m1');
      expect(ids(g), ['m0', 'm2', 'm3']);
      g.cocherVisibles(true);
      expect(g.nombreSelectionnes, 5);
      g.cocherVisibles(false);
      expect(g.nombreSelectionnes, 0);
    });

    test('affichage : correspondants en mode période, tout sinon', () {
      expect(s.visibles, c.messages);
      s.choisirCapsule(CapsulePeriode.hier);
      expect(s.visibles.map((m) => m.id), ['m7']);
      final v = s.versionAffichage;
      s.basculer('m7');
      // Une coche ne reconstruit pas la liste affichée.
      expect(s.versionAffichage, v);
      s.changerMode(ModeFiltrage.messages);
      expect(s.visibles, c.messages);
      // L'état est gardé d'un mode à l'autre.
      expect(s.nombreSelectionnes, 0);
      s.changerMode(ModeFiltrage.periode);
      expect(s.capsule, CapsulePeriode.hier);
    });

    test('résultat pour l’enregistrement : source, ordre, auteurs, dates, '
        'contenus', () {
      s.changerMode(ModeFiltrage.messages);
      s.basculer('m9');
      s.basculer('m2');
      s.basculer('m7');
      final r = s.resultat();
      expect(r.conversationSource, c.identifiant);
      expect(r.conversationSource, startsWith('wa-'));
      expect(r.ids, ['m2', 'm7', 'm9']);
      expect(r.auteurs, ['Ada', 'Alan']);
      expect(r.messages.last.date, DateTime(2026, 10, 14, 14, 30, 45));
      expect(r.messages.last.texte, 'cet après-midi');
      expect(r.nombreSansDate, 1);
      expect(r.messages.first.dateBrute, isNotEmpty);
      expect(r.nomFichier, 'chat.txt');
      // Identifiant stable pour un même export.
      expect(conv(c.messages).identifiant, c.identifiant);
    });
  });

  group('performances', () {
    test('50 000 messages : index, filtres et coches rapides', () {
      final grand = reguliere(
        50000,
        DateTime(2024, 1, 1),
        const Duration(minutes: 23),
      );
      final chrono = Stopwatch()..start();
      final g = SelectionWhatsApp(grand, horloge: () => maintenant);
      final index = chrono.elapsedMilliseconds;
      chrono.reset();
      g.choisirCapsule(CapsulePeriode.personnalise);
      g.definirPeriode(
        FiltrePeriode.jours(DateTime(2024, 3, 1), DateTime(2024, 9, 30)),
      );
      final periode = chrono.elapsedMilliseconds;
      chrono.reset();
      g.changerMode(ModeFiltrage.messages);
      g.commencerPlage();
      g.designer('m100');
      g.designer('m49000');
      final plage = chrono.elapsedMilliseconds;
      chrono.reset();
      for (var i = 0; i < 1000; i++) {
        g.basculer('m${i * 37}');
      }
      final coches = chrono.elapsedMilliseconds;
      chrono.reset();
      final r = g.resultat();
      final resultat = chrono.elapsedMilliseconds;
      expect(g.index.nombre, 50000);
      expect(r.messages.length, g.nombreSelectionnes);
      // ignore: avoid_print
      print(
        'PERF_FILTRAGE index=${index}ms periode=${periode}ms '
        'plage=${plage}ms 1000coches=${coches}ms resultat=${resultat}ms',
      );
      // Bornes larges (machine de test chargée) : aucune opération ne doit
      // approcher la seconde.
      expect(index, lessThan(1000));
      expect(periode, lessThan(500));
      expect(plage, lessThan(500));
      expect(coches, lessThan(500));
    });
  });
}
