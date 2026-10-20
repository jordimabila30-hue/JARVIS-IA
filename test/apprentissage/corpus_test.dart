// Module Apprendre : corpus hors ligne réel (assets) et validation du
// schéma (données invalides écartées sans tout casser).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/apprentissage/contenu_pedagogique.dart';
import 'package:ia_jarvis/models/apprentissage/exercice.dart';
import 'package:ia_jarvis/services/apprentissage/catalogue_apprentissage.dart';
import 'package:ia_jarvis/services/apprentissage/validation_corpus.dart';

const _resume = ResumeParcours(
  id: 'essai',
  titre: 'Essai',
  icone: '',
  fichier: 'essai.json',
);

Map<String, dynamic> _fiche(String id, {String statut = 'brouillon'}) => {
  'id': id,
  'titre': 'Fiche $id',
  'niveau': 1,
  'explication': 'Explication.',
  'exemples': ['Bon'],
  'a_eviter': ['Mauvais'],
  'sources': [
    {'titre': 'Source', 'editeur': 'Éditeur', 'url': 'https://example.org'},
  ],
  'statut': statut,
  if (statut == 'valide')
    'validation': {'par': 'Équipe pédagogique', 'le': '2026-10-21'},
  'version': 1,
};

Map<String, dynamic> _choix(String id, {String fiche = 'f1', int bonne = 0}) =>
    {
      'id': id,
      'type': 'choix',
      'fiche': fiche,
      'consigne': 'Question ?',
      'options': ['A', 'B'],
      'bonne': bonne,
      'explication': 'Parce que.',
    };

Map<String, dynamic> _lecon(String id, List<Map<String, dynamic>> ex) => {
  'id': id,
  'titre': 'Leçon $id',
  'niveau': 1,
  'duree_minutes': 3,
  'objectif': 'Objectif.',
  'fiches': ['f1'],
  'exercices': ex,
};

Map<String, dynamic> _parcours(
  List<Map<String, dynamic>> lecons, {
  List<Map<String, dynamic>>? fiches,
}) => {
  'schema': 1,
  'parcours': 'essai',
  'version': 1,
  'fiches': fiches ?? [_fiche('f1')],
  'unites': [
    {'id': 'u1', 'titre': 'Unité', 'lecons': lecons},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('corpus réel', () {
    late List<ParcoursCharge> parcours;

    setUpAll(() async {
      parcours = await CatalogueApprentissage(apercu: true).charger();
    });

    test('quatre parcours, chacun avec une leçon complète, sans erreur', () {
      expect(parcours.map((p) => p.resume.id), [
        'correspondance',
        'communication',
        'relations',
        'technique',
      ]);
      for (final p in parcours) {
        expect(p.erreurs, isEmpty, reason: p.resume.id);
        final lecons = p.leconsVisibles(apercu: true);
        expect(lecons, hasLength(1), reason: p.resume.id);
        expect(lecons.single.exercices.length, inInclusiveRange(5, 8));
        expect(lecons.single.dureeMinutes, inInclusiveRange(2, 4));
      }
    });

    test('identifiants uniques, chaque exercice cite une fiche existante', () {
      final lecons = <String>{}, exercices = <String>{}, fiches = <String>{};
      for (final p in parcours) {
        for (final f in p.contenu!.fiches.keys) {
          expect(fiches.add(f), isTrue, reason: f);
        }
        for (final l in p.contenu!.lecons) {
          expect(lecons.add(l.id), isTrue, reason: l.id);
          for (final e in l.exercices) {
            expect(exercices.add(e.id), isTrue, reason: e.id);
            expect(p.contenu!.fiches, contains(e.fiche));
            expect(e.verifier(), isEmpty);
          }
        }
      }
    });

    test('tous les types d’exercices sont présents', () {
      final types = {
        for (final p in parcours)
          for (final l in p.contenu!.lecons)
            for (final e in l.exercices) e.type,
      };
      expect(types, containsAll(TypeExercice.values));
    });

    test('fiches : sources identifiables, statut, version', () {
      for (final p in parcours) {
        for (final f in p.contenu!.fiches.values) {
          expect(f.sources, isNotEmpty);
          for (final s in f.sources) {
            expect(s.titre, isNotEmpty);
            expect(s.editeur, isNotEmpty);
            // Une page web citée a été consultée (date) ; un livre non.
            if (s.url != null) {
              expect(Uri.parse(s.url!).scheme, 'https');
              expect(s.consulteLe, isNotNull);
            }
          }
          expect(f.version, greaterThanOrEqualTo(1));
        }
      }
    });

    test(
      'hors aperçu, seules les leçons aux fiches validées sont publiées',
      () {
        for (final p in parcours) {
          final publiees = p.leconsVisibles(apercu: false);
          for (final l in p.contenu!.lecons) {
            final validees = l.fiches.every(
              (f) => p.contenu!.fiches[f]!.statut == StatutValidation.valide,
            );
            expect(publiees.contains(l), validees, reason: l.id);
          }
        }
      },
    );

    test('le corpus pèse moins de 1,5 Mo', () async {
      var octets = 0;
      for (final chemin in [
        CatalogueApprentissage.fichierCatalogue,
        for (final p in parcours) p.resume.fichier,
      ]) {
        octets += utf8.encode(await rootBundle.loadString(chemin)).length;
      }
      expect(octets, lessThan(1.5 * 1024 * 1024));
    });
  });

  group('validation', () {
    test('parcours valide : leçon publiée seulement si ses fiches le sont', () {
      final brouillon = validerParcours(
        _parcours([
          _lecon('l1', [_choix('e1')]),
        ]),
        _resume,
      );
      expect(brouillon.erreurs, isEmpty);
      final l = brouillon.parcours!.lecons.single;
      expect(brouillon.parcours!.leconValidee(l), isFalse);
      final valide = validerParcours(
        _parcours(
          [
            _lecon('l1', [_choix('e1')]),
          ],
          fiches: [_fiche('f1', statut: 'valide')],
        ),
        _resume,
      );
      expect(
        valide.parcours!.leconValidee(valide.parcours!.lecons.single),
        isTrue,
      );
    });

    test('une leçon défectueuse est écartée, les autres restent', () {
      final r = validerParcours(
        _parcours([
          _lecon('bonne', [_choix('e1')]),
          _lecon('index', [_choix('e2', bonne: 5)]),
          _lecon('fiche', [_choix('e3', fiche: 'absente')]),
          _lecon('type', [
            {..._choix('e4'), 'type': 'inconnu'},
          ]),
          _lecon('vide', []),
          _lecon('doublon', [_choix('e1')]),
        ]),
        _resume,
      );
      expect(r.parcours!.lecons.map((l) => l.id), ['bonne']);
      expect(r.erreurs, hasLength(greaterThanOrEqualTo(5)));
    });

    test('fiche sans source ou incomplète : écartée, ses leçons aussi', () {
      final sansSource = {..._fiche('f1'), 'sources': <Object>[]};
      final r = validerParcours(
        _parcours(
          [
            _lecon('l1', [_choix('e1')]),
          ],
          fiches: [sansSource],
        ),
        _resume,
      );
      expect(r.parcours!.fiches, isEmpty);
      expect(r.parcours!.lecons, isEmpty);
      expect(r.erreurs.join(), contains('aucune source'));
    });

    test('JSON inutilisable ou schéma trop récent : rien, sans exception', () {
      expect(validerParcours('texte', _resume).parcours, isNull);
      expect(validerParcours(<String, dynamic>{}, _resume).parcours, isNull);
      expect(
        validerParcours({..._parcours([]), 'schema': 99}, _resume).parcours,
        isNull,
      );
    });

    test(
      'catalogue absent ou illisible : liste vide, aucune exception',
      () async {
        final vide = await CatalogueApprentissage(
          bundle: _BundleVide(),
        ).charger();
        expect(vide, isEmpty);
        final casse = await CatalogueApprentissage(
          bundle: _BundleTexte({
            CatalogueApprentissage.fichierCatalogue: jsonEncode({
              'parcours': [
                {'id': 'x', 'titre': 'X', 'fichier': 'x.json'},
              ],
            }),
            'x.json': '{ pas du json',
          }),
        ).charger();
        expect(casse.single.contenu, isNull);
        expect(casse.single.leconsVisibles(apercu: true), isEmpty);
      },
    );

    test('le catalogue n’est lu qu’une fois (cache)', () async {
      final bundle = _BundleTexte({
        CatalogueApprentissage.fichierCatalogue: jsonEncode({'parcours': []}),
      });
      final c = CatalogueApprentissage(bundle: bundle);
      await c.charger();
      await c.charger();
      expect(bundle.lectures, 1);
    });
  });
}

class _BundleVide extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('absent');
}

class _BundleTexte extends CachingAssetBundle {
  _BundleTexte(this.fichiers);

  final Map<String, String> fichiers;
  int lectures = 0;

  @override
  Future<ByteData> load(String key) async {
    lectures++;
    final t = fichiers[key];
    if (t == null) throw FlutterError('absent : $key');
    return ByteData.sublistView(utf8.encode(t));
  }
}
