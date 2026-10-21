// Module Apprendre : publication des seules fiches relues. Filtrage en
// release (aperçu impossible), relecture tracée obligatoire, liens
// exercices ↔ fiches, progression quand une leçon est masquée, aucun
// contenu approuvé.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/apprentissage/catalogue_apprentissage.dart';
import 'package:ia_jarvis/services/apprentissage/selection_exercices.dart';
import 'package:ia_jarvis/services/apprentissage/service_progression.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

const _relue = {'par': 'Équipe pédagogique', 'le': '2026-10-21'};

Map<String, dynamic> _fiche(
  String id, {
  String statut = 'brouillon',
  Map<String, String>? validation,
}) => {
  'id': id,
  'titre': 'Fiche $id',
  'niveau': 1,
  'explication': 'Explication.',
  'sources': [
    {'titre': 'Source', 'editeur': 'Éditeur', 'url': 'https://example.org'},
  ],
  'statut': statut,
  'version': 1,
  'validation': ?validation,
};

Map<String, dynamic> _lecon(String id, String fiche) => {
  'id': id,
  'titre': 'Leçon $id',
  'niveau': 1,
  'duree_minutes': 3,
  'objectif': 'Objectif.',
  'fiches': [fiche],
  'exercices': [
    {
      'id': '$id-e1',
      'type': 'vrai_faux',
      'fiche': fiche,
      'consigne': '?',
      'affirmation': 'Affirmation.',
      'reponse': true,
      'explication': '!',
    },
  ],
};

/// Un parcours : `l-ok` (fiche relue), `l-brouillon`, `l-sans-trace`
/// (« valide » sans relecture tracée).
CatalogueApprentissage _catalogue({required bool release, bool apercu = true}) {
  final parcours = {
    'schema': 1,
    'parcours': 'p',
    'version': 1,
    'fiches': [
      _fiche('f-ok', statut: 'valide', validation: _relue),
      _fiche('f-brouillon'),
      _fiche('f-sans-trace', statut: 'valide'),
    ],
    'unites': [
      {
        'id': 'u',
        'titre': 'Unité',
        'lecons': [
          _lecon('l-ok', 'f-ok'),
          _lecon('l-brouillon', 'f-brouillon'),
          _lecon('l-sans-trace', 'f-sans-trace'),
        ],
      },
    ],
  };
  return CatalogueApprentissage(
    release: release,
    apercu: apercu,
    bundle: _Bundle({
      CatalogueApprentissage.fichierCatalogue: jsonEncode({
        'schema': 1,
        'parcours': [
          {'id': 'p', 'titre': 'P', 'icone': '', 'fichier': 'p.json'},
        ],
      }),
      'p.json': jsonEncode(parcours),
    }),
  );
}

ServiceProgression _progression() => ServiceProgression(
  principal: StockageMemoire(),
  secours: StockageMemoire(),
  corrompue: StockageMemoire(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('release : seules les leçons aux fiches relues sont publiées, '
      'l’aperçu ne peut pas être activé', () async {
    final c = _catalogue(release: true);
    final p = (await c.charger()).single;
    expect(c.apercu.value, isFalse);
    c.apercu.value = true;
    expect(c.apercu.value, isFalse);
    expect(p.leconsVisibles(apercu: c.apercu.value).map((l) => l.id), ['l-ok']);
    // Une leçon masquée n'est pas trouvée, même par son identifiant.
    expect(c.lecon('l-brouillon'), isNull);
    expect(c.lecon('l-ok'), isNotNull);
    c.dispose();
  });

  test('« valide » sans relecture tracée : jamais publiée, signalée', () async {
    final c = _catalogue(release: true);
    final p = (await c.charger()).single;
    expect(p.contenu!.fiches['f-sans-trace']!.validee, isFalse);
    expect(p.contenu!.fiches['f-ok']!.validee, isTrue);
    expect(p.erreurs.join(), contains('sans relecture tracée'));
    c.dispose();
  });

  test('développement : l’aperçu montre aussi les brouillons', () async {
    final c = _catalogue(release: false);
    final p = (await c.charger()).single;
    expect(p.leconsVisibles(apercu: c.apercu.value), hasLength(3));
    c.apercu.value = false;
    expect(p.leconsVisibles(apercu: c.apercu.value).map((l) => l.id), ['l-ok']);
    c.dispose();
  });

  test('chaque exercice publié cite une fiche publiée', () async {
    final c = _catalogue(release: true);
    final p = (await c.charger()).single;
    for (final l in p.leconsVisibles(apercu: false)) {
      for (final e in l.exercices) {
        expect(p.contenu!.fiches[e.fiche]!.validee, isTrue, reason: e.id);
      }
    }
    c.dispose();
  });

  test('leçon masquée : progression gardée, mais hors des pourcentages, '
      'de Continuer et de Réviser', () async {
    final c = _catalogue(release: true);
    final p = (await c.charger()).single;
    final prog = _progression();
    await prog.charger();
    // Progression faite quand la leçon était visible (aperçu, ancienne
    // version…), puis la fiche est masquée.
    await prog.terminerLecon('l-brouillon', justes: 1, total: 1);
    prog.ouvrirLecon('p', 'l-brouillon');
    prog.noterExercice('l-brouillon', 'l-brouillon-e1', juste: false);
    final visibles = p.leconsVisibles(apercu: false);
    expect(prog.avancement(visibles), 0);
    final s = SelectionExercices(c, prog);
    expect(s.aRevoir(), isEmpty);
    // Continuer ignore la leçon masquée.
    expect(s.aContinuer(), isNull);
    // Rien n'est effacé : elle revient telle quelle si elle est publiée.
    expect(prog.etat('l-brouillon')!.terminee, isTrue);
    expect(prog.donnees.aReviser, contains('l-brouillon-e1'));
    prog.dispose();
    c.dispose();
  });

  test('aucun contenu approuvé : rien à proposer, sans erreur', () async {
    final c = CatalogueApprentissage(release: true);
    final parcours = await c.charger();
    final prog = _progression();
    await prog.charger();
    final s = SelectionExercices(c, prog);
    // Corpus réel : toutes les fiches sont en brouillon aujourd'hui.
    final publiees = parcours.expand((p) => p.leconsVisibles(apercu: false));
    if (publiees.isEmpty) {
      expect(s.contenuDisponible, isFalse);
      expect(s.pratique(), isEmpty);
      expect(s.revision(), isEmpty);
      expect(s.aContinuer(), isNull);
    }
    prog.dispose();
    c.dispose();
  });

  test('l’aperçu par défaut suit le mode de compilation', () {
    final c = CatalogueApprentissage();
    expect(c.apercu.value, !kReleaseMode);
    c.dispose();
  });
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.fichiers);

  final Map<String, String> fichiers;

  @override
  Future<ByteData> load(String key) async {
    final t = fichiers[key];
    if (t == null) throw FlutterError('absent : $key');
    return ByteData.sublistView(utf8.encode(t));
  }
}
