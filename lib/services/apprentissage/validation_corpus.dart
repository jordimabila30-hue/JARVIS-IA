import '../../models/apprentissage/contenu_pedagogique.dart';
import '../../models/apprentissage/exercice.dart';

/// Validation d'un parcours lu en JSON. Rien n'est jamais fatal : une
/// fiche ou une leçon défectueuse est écartée (et signalée dans
/// [ResultatValidation.erreurs]), le reste du parcours reste utilisable.
///
/// Une leçon est gardée seulement si :
/// - elle a un identifiant unique, un objectif, au moins un exercice ;
/// - chaque fiche citée existe et a au moins une source ;
/// - chaque exercice est cohérent ([Exercice.verifier]), a un identifiant
///   unique dans le parcours et se rattache à une fiche de la leçon.
class ResultatValidation {
  const ResultatValidation(this.parcours, this.erreurs);

  /// Null : parcours entièrement illisible.
  final Parcours? parcours;
  final List<String> erreurs;
}

/// Version de schéma lue par cette version de JARVIS.
const versionSchemaCorpus = 1;

ResultatValidation validerParcours(Object? json, ResumeParcours resume) {
  final erreurs = <String>[];
  if (json is! Map<String, dynamic>) {
    return ResultatValidation(null, ['${resume.id} : JSON non reconnu']);
  }
  final schema = json['schema'];
  if (schema is! int || schema > versionSchemaCorpus) {
    return ResultatValidation(null, [
      '${resume.id} : schéma $schema non pris en charge',
    ]);
  }
  if (json['parcours'] != resume.id) {
    erreurs.add('${resume.id} : identifiant de parcours différent');
  }

  final fiches = <String, FichePedagogique>{};
  final fichesJson = json['fiches'];
  if (fichesJson is List) {
    for (final f in fichesJson) {
      try {
        final fiche = FichePedagogique.depuisJson(f as Map<String, dynamic>);
        if (fiches.containsKey(fiche.id)) {
          erreurs.add('fiche ${fiche.id} : identifiant en double');
        } else if (fiche.sources.isEmpty) {
          erreurs.add('fiche ${fiche.id} : aucune source');
        } else {
          // « valide » sans relecture tracée : gardée, jamais publiée
          // (FichePedagogique.validee reste faux).
          if (fiche.statut == StatutValidation.valide &&
              fiche.validation == null) {
            erreurs.add('fiche ${fiche.id} : « valide » sans relecture tracée');
          }
          fiches[fiche.id] = fiche;
        }
      } catch (e) {
        erreurs.add('fiche illisible : $e');
      }
    }
  }

  final idsLecons = <String>{};
  final idsExercices = <String>{};
  final unites = <Unite>[];
  final unitesJson = json['unites'];
  if (unitesJson is List) {
    for (final u in unitesJson) {
      if (u is! Map<String, dynamic> ||
          u['id'] is! String ||
          u['titre'] is! String ||
          u['lecons'] is! List) {
        erreurs.add('unité illisible');
        continue;
      }
      final lecons = <Lecon>[];
      for (final l in u['lecons'] as List) {
        final Lecon lecon;
        try {
          lecon = Lecon.depuisJson(l as Map<String, dynamic>);
        } catch (e) {
          erreurs.add('leçon illisible : $e');
          continue;
        }
        final problemes = _problemes(lecon, fiches, idsExercices);
        if (!idsLecons.add(lecon.id)) problemes.add('identifiant en double');
        if (problemes.isEmpty) {
          lecons.add(lecon);
          idsExercices.addAll(lecon.exercices.map((e) => e.id));
        } else {
          erreurs.addAll(problemes.map((p) => 'leçon ${lecon.id} : $p'));
        }
      }
      unites.add(
        Unite(
          id: u['id'] as String,
          titre: u['titre'] as String,
          lecons: lecons,
        ),
      );
    }
  }

  return ResultatValidation(
    Parcours(
      resume: resume,
      version: json['version'] is int ? json['version'] as int : 0,
      fiches: Map.unmodifiable(fiches),
      unites: List.unmodifiable(unites),
    ),
    erreurs,
  );
}

List<String> _problemes(
  Lecon lecon,
  Map<String, FichePedagogique> fiches,
  Set<String> idsExercices,
) {
  final p = <String>[];
  if (lecon.exercices.isEmpty) p.add('aucun exercice');
  if (lecon.fiches.isEmpty) p.add('aucune fiche');
  for (final f in lecon.fiches) {
    if (!fiches.containsKey(f)) p.add('fiche $f absente ou invalide');
  }
  final vus = <String>{};
  for (final e in lecon.exercices) {
    if (!vus.add(e.id) || idsExercices.contains(e.id)) {
      p.add('exercice ${e.id} en double');
    }
    if (!lecon.fiches.contains(e.fiche)) {
      p.add('exercice ${e.id} : fiche ${e.fiche} hors de la leçon');
    }
    p.addAll(e.verifier());
  }
  return p;
}
