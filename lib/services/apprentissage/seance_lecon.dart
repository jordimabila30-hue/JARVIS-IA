import 'package:flutter/foundation.dart';

import '../../models/apprentissage/exercice.dart';
import '../../models/apprentissage/progression.dart';

/// Étape affichée d'une séance.
enum PhaseSeance { introduction, exercice, resultat }

/// Réponse corrigée de l'exercice courant.
class Correction {
  const Correction(this.exercice, this.reponse, {required this.juste});

  final Exercice exercice;
  final ReponseExercice reponse;
  final bool juste;
}

/// Bilan de fin de séance (premiers essais seulement).
class BilanSeance {
  const BilanSeance({
    required this.justes,
    required this.total,
    required this.fichesAcquises,
    required this.fichesARetravailler,
    required this.rates,
  });

  final int justes;
  final int total;
  final List<String> fichesAcquises;
  final List<String> fichesARetravailler;

  /// Exercices ratés au premier essai (pour « Réviser »).
  final List<Exercice> rates;
}

/// Déroulé d'une séance : leçon (introduction, exercices, résultat) ou
/// entraînement libre (Pratiquer, Réviser : exercices, résultat).
///
/// Logique pure, sans interface : la page l'affiche et relaie les
/// rappels vers la progression. Une réponse fausse est corrigée tout de
/// suite ; l'exercice peut être retenté aussitôt (« Réessayer ») et revient
/// une fois en fin de séance s'il n'a pas été réussi entre-temps. Seul le
/// premier essai compte dans le bilan.
class SeanceLecon extends ChangeNotifier {
  SeanceLecon({
    required List<Exercice> exercices,
    bool introduction = true,
    SeanceEnregistree? reprise,
    this.surSeance,
    this.surReponse,
    this.surFin,
  }) : _exercices = {for (final e in exercices) e.id: e},
       _initiaux = [for (final e in exercices) e.id] {
    final file = reprise?.file.where(_exercices.containsKey).toList();
    if (file != null && file.isNotEmpty && reprise!.position < file.length) {
      // Reprise : là où l'utilisateur s'était arrêté (contenu mis à jour
      // depuis : exercices disparus ignorés).
      _file = file;
      _position = reprise.position;
      _essais = {
        for (final e in reprise.essais.entries)
          if (_exercices.containsKey(e.key)) e.key: e.value,
      };
      _phase = PhaseSeance.exercice;
      // Exercices déjà revenus en fin de file.
      final vus = <String>{};
      for (final id in _file) {
        if (!vus.add(id)) _revenus.add(id);
      }
    } else {
      _file = List.of(_initiaux);
      _phase = introduction ? PhaseSeance.introduction : PhaseSeance.exercice;
    }
    if (_exercices.isEmpty) _phase = PhaseSeance.resultat;
  }

  final Map<String, Exercice> _exercices;
  final List<String> _initiaux;

  /// Chaque changement à enregistrer (reprise possible).
  final ValueChanged<SeanceEnregistree>? surSeance;

  /// Premier essai d'un exercice dans cette séance.
  final void Function(Exercice exercice, bool juste)? surReponse;
  final ValueChanged<BilanSeance>? surFin;

  late List<String> _file;
  int _position = 0;
  Map<String, bool> _essais = {};
  final _revenus = <String>{};
  late PhaseSeance _phase;
  Correction? _correction;
  int _tentative = 0;
  BilanSeance? _bilan;

  PhaseSeance get phase => _phase;
  Correction? get correction => _correction;
  BilanSeance? get bilan => _bilan;

  /// Change à chaque nouvel essai du même exercice (réinitialise son widget).
  int get tentative => _tentative;
  int get position => _position;
  int get longueur => _file.length;

  /// Avancement affiché (0 à 1).
  double get avancement {
    if (_phase == PhaseSeance.resultat) return 1;
    if (_file.isEmpty) return 0;
    final fait = _position + (_correction == null ? 0 : 1);
    return fait / _file.length;
  }

  Exercice? get exerciceCourant =>
      _phase == PhaseSeance.exercice ? _exercices[_file[_position]] : null;

  /// L'exercice courant est un retour en fin de séance.
  bool get estUnRetour {
    if (_phase != PhaseSeance.exercice) return false;
    return _file.indexOf(_file[_position]) < _position;
  }

  SeanceEnregistree get instantane => SeanceEnregistree(
    file: List.unmodifiable(_file),
    position: _position,
    essais: Map.unmodifiable(_essais),
  );

  void commencer() {
    if (_phase != PhaseSeance.introduction) return;
    _phase = PhaseSeance.exercice;
    _publier();
  }

  void repondre(ReponseExercice reponse) {
    final ex = exerciceCourant;
    if (ex == null || _correction != null) return;
    final juste = ex.estJuste(reponse);
    _correction = Correction(ex, reponse, juste: juste);
    if (!_essais.containsKey(ex.id)) {
      _essais[ex.id] = juste;
      surReponse?.call(ex, juste);
    }
    if (!juste && _revenus.add(ex.id)) {
      _file.add(ex.id); // revient une fois en fin de séance
    } else if (juste && _tentative > 0 && !estUnRetour) {
      // Réussi en réessayant tout de suite : inutile d'y revenir.
      final retour = _file.lastIndexOf(ex.id);
      if (retour > _position) {
        _file.removeAt(retour);
        _revenus.remove(ex.id);
      }
    }
    _publier();
  }

  /// Nouvel essai immédiat du même exercice (après une erreur).
  void reessayer() {
    if (_correction == null || _correction!.juste) return;
    _correction = null;
    _tentative++;
    notifyListeners();
  }

  void continuer() {
    if (_phase != PhaseSeance.exercice || _correction == null) return;
    _correction = null;
    _tentative = 0;
    _position++;
    if (_position >= _file.length) {
      _phase = PhaseSeance.resultat;
      _bilan = _calculerBilan();
      notifyListeners();
      surFin?.call(_bilan!);
      return;
    }
    _publier();
  }

  void _publier() {
    notifyListeners();
    surSeance?.call(instantane);
  }

  BilanSeance _calculerBilan() {
    final parFiche = <String, bool>{};
    final rates = <Exercice>[];
    var justes = 0;
    for (final id in _initiaux) {
      final ex = _exercices[id]!;
      final ok = _essais[id] ?? false;
      if (ok) {
        justes++;
      } else {
        rates.add(ex);
      }
      parFiche[ex.fiche] = (parFiche[ex.fiche] ?? true) && ok;
    }
    return BilanSeance(
      justes: justes,
      total: _initiaux.length,
      fichesAcquises: [
        for (final e in parFiche.entries)
          if (e.value) e.key,
      ],
      fichesARetravailler: [
        for (final e in parFiche.entries)
          if (!e.value) e.key,
      ],
      rates: rates,
    );
  }
}
