import 'dart:math';

import '../../models/apprentissage/contenu_pedagogique.dart';
import '../../models/apprentissage/exercice.dart';
import '../../models/apprentissage/progression.dart';
import 'adaptation.dart';
import 'catalogue_apprentissage.dart';
import 'service_progression.dart';

/// Choix des contenus proposés par l'accueil du module (logique pure) :
/// leçon à continuer, exercices de Pratiquer et de Réviser.

/// Un exercice et la leçon d'où il vient.
class ExerciceSitue {
  const ExerciceSitue(this.exercice, this.lecon);

  final Exercice exercice;
  final String lecon;
}

/// Nombre d'exercices d'une séance libre (Pratiquer, Réviser).
const tailleSeanceLibre = 6;

/// Leçon proposée par « Continuer ».
class LeconAContinuer {
  const LeconAContinuer(this.parcours, this.lecon, {required this.etat});

  final ParcoursCharge parcours;
  final Lecon lecon;

  /// enCours : séance à reprendre ; suivante : pas encore faite ;
  /// terminee : tout est fait (refaire).
  final EtatContinuer etat;
}

enum EtatContinuer { enCours, suivante, terminee }

class SelectionExercices {
  const SelectionExercices(this.catalogue, this.progression);

  final CatalogueApprentissage catalogue;
  final ServiceProgression progression;

  bool get _apercu => catalogue.apercu.value;

  Iterable<(ParcoursCharge, Lecon)> get _visibles sync* {
    for (final p in catalogue.parcours ?? const <ParcoursCharge>[]) {
      for (final l in p.leconsVisibles(apercu: _apercu)) {
        yield (p, l);
      }
    }
  }

  bool get contenuDisponible => _visibles.isNotEmpty;

  /// Dernière leçon ouverte si elle est en cours ; sinon la suivante non
  /// terminée (même parcours d'abord) ; null si rien n'a été commencé.
  LeconAContinuer? aContinuer() {
    final derniere = progression.donnees.derniereLecon;
    final trouvee = derniere == null ? null : catalogue.lecon(derniere);
    if (trouvee == null) return null;
    final (parcours, lecon) = trouvee;
    if (progression.etat(lecon.id)?.commencee == true) {
      return LeconAContinuer(parcours, lecon, etat: EtatContinuer.enCours);
    }
    final ordre = [
      ..._visibles.where((v) => v.$1.resume.id == parcours.resume.id),
      ..._visibles.where((v) => v.$1.resume.id != parcours.resume.id),
    ];
    for (final (p, l) in ordre) {
      if (progression.etat(l.id)?.terminee != true) {
        final enCours = progression.etat(l.id)?.commencee == true;
        return LeconAContinuer(
          p,
          l,
          etat: enCours ? EtatContinuer.enCours : EtatContinuer.suivante,
        );
      }
    }
    return LeconAContinuer(parcours, lecon, etat: EtatContinuer.terminee);
  }

  /// Exercices ratés encore à revoir (leçons visibles seulement).
  List<ExerciceSitue> aRevoir() {
    final r = <ExerciceSitue>[];
    for (final e in progression.donnees.aReviser.entries) {
      final ex = catalogue.lecon(e.value)?.$2.exercice(e.key);
      if (ex != null) r.add(ExerciceSitue(ex, e.value));
    }
    return r;
  }

  double _maitrise(String fiche) => progression.maitriseDe(fiche) ?? 0.5;

  /// Niveau du parcours de la leçon [lecon].
  NiveauApprenant? _niveauDe(String lecon) {
    final p = catalogue.lecon(lecon)?.$1;
    return p == null ? null : progression.niveau(p.resume.id);
  }

  /// Ordre adaptatif ([AdaptationKelasi.ordonner]), le niveau suivant le parcours
  /// de chaque exercice ; [hasard] départage les égalités.
  List<ExerciceSitue> _adapter(List<ExerciceSitue> liste, Random? hasard) {
    liste.shuffle(hasard);
    final parNiveau = <NiveauApprenant?, List<ExerciceSitue>>{};
    for (final e in liste) {
      (parNiveau[_niveauDe(e.lecon)] ??= []).add(e);
    }
    final tries = [
      for (final entree in parNiveau.entries)
        ...AdaptationKelasi.ordonner(
          entree.value,
          exercice: (e) => e.exercice,
          maitrise: _maitrise,
          niveau: entree.key,
        ),
    ];
    return tries;
  }

  /// Réviser : d'abord les exercices ratés (notions les plus fragiles en
  /// premier), complétés par ceux des leçons déjà étudiées. Vide : rien à
  /// réviser.
  List<ExerciceSitue> revision({Random? hasard}) {
    final r = aRevoir()
      ..sort(
        (a, b) =>
            _maitrise(a.exercice.fiche).compareTo(_maitrise(b.exercice.fiche)),
      );
    final deja = r.map((e) => e.exercice.id).toSet();
    final etudies = [
      for (final (_, l) in _visibles)
        if (progression.etat(l.id) case final e? when e.terminee || e.commencee)
          for (final ex in l.exercices)
            if (!deja.contains(ex.id)) ExerciceSitue(ex, l.id),
    ]..shuffle(hasard);
    return [...r, ...etudies].take(tailleSeanceLibre).toList();
  }

  /// Pratiquer : exercices des leçons étudiées en priorité, sinon de
  /// toutes les leçons disponibles, mélangés.
  List<ExerciceSitue> pratique({Random? hasard}) {
    List<ExerciceSitue> de(bool Function(Lecon) garder) => [
      for (final (_, l) in _visibles)
        if (garder(l))
          for (final ex in l.exercices) ExerciceSitue(ex, l.id),
    ];
    bool etudiee(Lecon l) {
      final e = progression.etat(l.id);
      return e != null && (e.terminee || e.commencee);
    }

    // Leçons étudiées d'abord ; dans chaque groupe, ordre adaptatif
    // (notions fragiles, difficulté proche du niveau).
    return [
      ..._adapter(de(etudiee), hasard),
      ..._adapter(de((l) => !etudiee(l)), hasard),
    ].take(tailleSeanceLibre).toList();
  }
}
