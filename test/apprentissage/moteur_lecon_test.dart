// Module Apprendre : correction des exercices et déroulé d'une séance
// (logique pure, sans interface).

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/apprentissage/exercice.dart';
import 'package:ia_jarvis/models/apprentissage/progression.dart';
import 'package:ia_jarvis/services/apprentissage/seance_lecon.dart';

ExerciceChoix _choix(String id, {String fiche = 'f1'}) => ExerciceChoix(
  id: id,
  fiche: fiche,
  consigne: '?',
  explication: '!',
  type: TypeExercice.choix,
  options: const ['A', 'B', 'C'],
  bonne: 1,
);

const _juste = ReponseChoix(1);
const _faux = ReponseChoix(0);

void main() {
  group('exercices', () {
    test('choix, vrai/faux', () {
      final c = _choix('c');
      expect(c.estJuste(_juste), isTrue);
      expect(c.estJuste(_faux), isFalse);
      expect(c.estJuste(const ReponseVraiFaux(true)), isFalse);
      expect(c.solution, 'B');
      const vf = ExerciceVraiFaux(
        id: 'v',
        fiche: 'f',
        consigne: '?',
        explication: '!',
        affirmation: 'Le ciel est vert.',
        reponse: false,
      );
      expect(vf.estJuste(const ReponseVraiFaux(false)), isTrue);
      expect(vf.estJuste(const ReponseVraiFaux(true)), isFalse);
    });

    test('texte à trous : tous les trous justes, solution reconstruite', () {
      const t = ExerciceTrous(
        id: 't',
        fiche: 'f',
        consigne: '?',
        explication: '!',
        texte: '___ Madame, merci ___.',
        trous: [
          Trou(options: ['Yo', 'Bonjour'], bonne: 1),
          Trou(options: ['beaucoup', 'pas'], bonne: 0),
        ],
      );
      expect(t.verifier(), isEmpty);
      expect(t.estJuste(const ReponseTrous([1, 0])), isTrue);
      expect(t.estJuste(const ReponseTrous([1, 1])), isFalse);
      expect(t.estJuste(const ReponseTrous([1])), isFalse);
      expect(t.solution, 'Bonjour Madame, merci beaucoup.');
      const casse = ExerciceTrous(
        id: 'x',
        fiche: 'f',
        consigne: '?',
        explication: '!',
        texte: 'un seul ___',
        trous: [
          Trou(options: ['a', 'b'], bonne: 0),
          Trou(options: ['a', 'b'], bonne: 0),
        ],
      );
      expect(casse.verifier(), isNotEmpty);
    });

    test('ordre et association', () {
      const o = ExerciceOrdre(
        id: 'o',
        fiche: 'f',
        consigne: '?',
        explication: '!',
        elements: ['1', '2', '3', '4'],
      );
      expect(o.estJuste(const ReponseOrdre([0, 1, 2, 3])), isTrue);
      expect(o.estJuste(const ReponseOrdre([1, 0, 2, 3])), isFalse);
      const a = ExerciceAssociation(
        id: 'a',
        fiche: 'f',
        consigne: '?',
        explication: '!',
        paires: [('x', '1'), ('y', '2'), ('z', '3')],
      );
      expect(a.estJuste(const ReponseAssociation({0: 0, 1: 1, 2: 2})), isTrue);
      expect(a.estJuste(const ReponseAssociation({0: 1, 1: 0, 2: 2})), isFalse);
      expect(a.estJuste(const ReponseAssociation({0: 0})), isFalse);
    });

    test('mélange stable : toujours le même, jamais déjà dans l’ordre', () {
      for (final graine in ['a', 'b', 'cor-l1-e4', 'rel-l1-e3', 'x/d']) {
        for (var n = 2; n <= 7; n++) {
          final m = melangeStable(graine, n);
          expect(m, melangeStable(graine, n));
          expect(m.toSet(), {for (var i = 0; i < n; i++) i});
          expect(m, isNot(List.generate(n, (i) => i)));
        }
      }
    });

    test('lecture JSON : type inconnu ou champ manquant refusés', () {
      expect(
        () => Exercice.depuisJson({
          'id': 'e',
          'type': 'quiz',
          'fiche': 'f',
          'consigne': '?',
          'explication': '!',
        }),
        throwsFormatException,
      );
      expect(
        () => Exercice.depuisJson({
          'id': 'e',
          'type': 'choix',
          'fiche': 'f',
          'consigne': '?',
          'explication': '!',
          'options': ['a', 'b'],
        }),
        throwsFormatException,
      );
    });
  });

  group('séance', () {
    test('introduction, exercices, résultat ; bilan des premiers essais', () {
      final reponses = <String, bool>{};
      BilanSeance? fin;
      final s = SeanceLecon(
        exercices: [
          _choix('e1'),
          _choix('e2', fiche: 'f2'),
        ],
        surReponse: (e, j) => reponses[e.id] = j,
        surFin: (b) => fin = b,
      );
      expect(s.phase, PhaseSeance.introduction);
      s.commencer();
      expect(s.exerciceCourant!.id, 'e1');
      s.repondre(_juste);
      expect(s.correction!.juste, isTrue);
      // Une seule réponse par affichage.
      s.repondre(_faux);
      expect(s.correction!.juste, isTrue);
      s.continuer();
      s.repondre(_faux);
      expect(s.correction!.juste, isFalse);
      // Raté : revient une fois en fin de séance.
      expect(s.longueur, 3);
      s.continuer();
      expect(s.exerciceCourant!.id, 'e2');
      expect(s.estUnRetour, isTrue);
      s.repondre(_juste);
      // Toujours un seul retour, même juste.
      expect(s.longueur, 3);
      s.continuer();
      expect(s.phase, PhaseSeance.resultat);
      expect(reponses, {'e1': true, 'e2': false});
      expect(fin!.justes, 1);
      expect(fin!.total, 2);
      expect(fin!.fichesAcquises, ['f1']);
      expect(fin!.fichesARetravailler, ['f2']);
      expect(fin!.rates.single.id, 'e2');
      expect(s.avancement, 1);
    });

    test('réessayer : réussi tout de suite, l’exercice ne revient pas ; '
        'le premier essai reste compté faux', () {
      final s = SeanceLecon(exercices: [_choix('e1')], introduction: false);
      s.repondre(_faux);
      expect(s.longueur, 2);
      final t = s.tentative;
      s.reessayer();
      expect(s.correction, isNull);
      expect(s.tentative, t + 1);
      s.repondre(_juste);
      expect(s.longueur, 1);
      s.continuer();
      expect(s.phase, PhaseSeance.resultat);
      expect(s.bilan!.justes, 0);
    });

    test('chaque étape est enregistrée ; reprise exacte', () {
      SeanceEnregistree? derniere;
      final ex = [_choix('e1'), _choix('e2'), _choix('e3')];
      final s = SeanceLecon(exercices: ex, surSeance: (v) => derniere = v);
      s.commencer();
      s.repondre(_faux);
      s.continuer();
      expect(derniere!.position, 1);
      expect(derniere!.file, ['e1', 'e2', 'e3', 'e1']);
      expect(derniere!.essais, {'e1': false});

      final reprise = SeanceLecon(exercices: ex, reprise: derniere);
      expect(reprise.phase, PhaseSeance.exercice);
      expect(reprise.exerciceCourant!.id, 'e2');
      expect(reprise.longueur, 4);
      // e1 déjà revenu une fois : une nouvelle erreur ne le rajoute pas.
      reprise.repondre(_juste);
      reprise.continuer();
      reprise.repondre(_juste);
      reprise.continuer();
      reprise.repondre(_faux);
      expect(reprise.longueur, 4);
      reprise.continuer();
      expect(reprise.bilan!.justes, 2);
    });

    test('reprise d’une leçon modifiée : exercices disparus ignorés', () {
      final s = SeanceLecon(
        exercices: [_choix('e1'), _choix('e3')],
        reprise: const SeanceEnregistree(
          file: ['e1', 'ancien', 'e3'],
          position: 1,
          essais: {'e1': true, 'ancien': false},
        ),
      );
      expect(s.exerciceCourant!.id, 'e3');
      s.repondre(_juste);
      s.continuer();
      expect(s.bilan!.justes, 2);
      expect(s.bilan!.total, 2);
    });

    test('reprise inutilisable : on recommence au début', () {
      final s = SeanceLecon(
        exercices: [_choix('e1')],
        reprise: const SeanceEnregistree(file: ['x'], position: 0, essais: {}),
      );
      expect(s.phase, PhaseSeance.introduction);
    });
  });
}
