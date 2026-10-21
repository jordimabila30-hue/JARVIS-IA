import 'dart:convert';

/// Progression locale du module Apprendre : JSON versionné, lecture
/// tolérante (une entrée illisible est ignorée, jamais tout le reste).
/// Prête pour une future synchronisation (identifiants stables, dates).

/// Séance en cours d'une leçon (reprise après une interruption).
class SeanceEnregistree {
  const SeanceEnregistree({
    required this.file,
    required this.position,
    required this.essais,
  });

  /// Exercices à faire, dans l'ordre (un exercice raté peut y revenir).
  final List<String> file;

  /// Index du prochain exercice de [file] (0 : introduction pas finie).
  final int position;

  /// Premier essai de chaque exercice (juste ou non).
  final Map<String, bool> essais;

  Map<String, dynamic> versJson() => {
    'file': file,
    'position': position,
    'essais': essais,
  };

  static SeanceEnregistree? depuisJson(Object? j) {
    if (j is! Map) return null;
    final file = j['file'], position = j['position'], essais = j['essais'];
    if (file is! List || position is! int || essais is! Map) return null;
    return SeanceEnregistree(
      file: file.whereType<String>().toList(),
      position: position < 0 ? 0 : position,
      essais: {
        for (final e in essais.entries)
          if (e.key is String && e.value is bool)
            e.key as String: e.value as bool,
      },
    );
  }
}

/// État d'une leçon pour cet appareil.
class EtatLecon {
  const EtatLecon({
    this.terminee = false,
    this.termineeLe,
    this.meilleurScore = 0,
    this.total = 0,
    this.seance,
    this.consulteeLe,
  });

  final bool terminee;
  final DateTime? termineeLe;

  /// Meilleur nombre de bonnes réponses au premier essai, sur [total].
  final int meilleurScore;
  final int total;

  /// Séance en cours (null : aucune).
  final SeanceEnregistree? seance;
  final DateTime? consulteeLe;

  bool get commencee => seance != null;

  EtatLecon copier({
    bool? terminee,
    DateTime? termineeLe,
    int? meilleurScore,
    int? total,
    SeanceEnregistree? Function()? seance,
    DateTime? consulteeLe,
  }) => EtatLecon(
    terminee: terminee ?? this.terminee,
    termineeLe: termineeLe ?? this.termineeLe,
    meilleurScore: meilleurScore ?? this.meilleurScore,
    total: total ?? this.total,
    seance: seance == null ? this.seance : seance(),
    consulteeLe: consulteeLe ?? this.consulteeLe,
  );

  Map<String, dynamic> versJson() => {
    'terminee': terminee,
    if (termineeLe != null) 'terminee_le': termineeLe!.toIso8601String(),
    'meilleur': meilleurScore,
    'total': total,
    if (seance != null) 'seance': seance!.versJson(),
    if (consulteeLe != null) 'consultee_le': consulteeLe!.toIso8601String(),
  };

  static EtatLecon? depuisJson(Object? j) {
    if (j is! Map) return null;
    return EtatLecon(
      terminee: j['terminee'] == true,
      termineeLe: DateTime.tryParse('${j['terminee_le']}'),
      meilleurScore: j['meilleur'] is int ? j['meilleur'] as int : 0,
      total: j['total'] is int ? j['total'] as int : 0,
      seance: SeanceEnregistree.depuisJson(j['seance']),
      consulteeLe: DateTime.tryParse('${j['consultee_le']}'),
    );
  }
}

/// Toute la progression (une seule valeur enregistrée).
class ProgressionApprentissage {
  const ProgressionApprentissage({
    this.lecons = const {},
    this.aReviser = const {},
    this.dernierParcours,
    this.derniereLecon,
  });

  /// Version du format écrit ; une version plus récente reste lue au mieux.
  static const version = 1;

  static const vide = ProgressionApprentissage();

  /// Leçon (id) → état.
  final Map<String, EtatLecon> lecons;

  /// Exercice à revoir (id) → sa leçon (id).
  final Map<String, String> aReviser;
  final String? dernierParcours;
  final String? derniereLecon;

  ProgressionApprentissage copier({
    Map<String, EtatLecon>? lecons,
    Map<String, String>? aReviser,
    String? dernierParcours,
    String? derniereLecon,
  }) => ProgressionApprentissage(
    lecons: lecons ?? this.lecons,
    aReviser: aReviser ?? this.aReviser,
    dernierParcours: dernierParcours ?? this.dernierParcours,
    derniereLecon: derniereLecon ?? this.derniereLecon,
  );

  String encoder() => jsonEncode({
    'version': version,
    'lecons': {for (final e in lecons.entries) e.key: e.value.versJson()},
    'a_reviser': aReviser,
    'dernier_parcours': ?dernierParcours,
    'derniere_lecon': ?derniereLecon,
  });

  /// Lit une progression enregistrée. [FormatException] si le texte n'est
  /// pas une progression (JSON invalide, autre structure) : l'appelant
  /// décide de la récupération. Une entrée isolée illisible est ignorée.
  static ProgressionApprentissage decoder(String texte) {
    final j = jsonDecode(texte);
    if (j is! Map || j['version'] is! int || j['lecons'] is! Map) {
      throw const FormatException('progression : structure inconnue');
    }
    final lecons = <String, EtatLecon>{};
    for (final e in (j['lecons'] as Map).entries) {
      final etat = EtatLecon.depuisJson(e.value);
      if (e.key is String && etat != null) lecons[e.key as String] = etat;
    }
    final reviser = <String, String>{};
    final r = j['a_reviser'];
    if (r is Map) {
      for (final e in r.entries) {
        if (e.key is String && e.value is String) {
          reviser[e.key as String] = e.value as String;
        }
      }
    }
    return ProgressionApprentissage(
      lecons: lecons,
      aReviser: reviser,
      dernierParcours: switch (j['dernier_parcours']) {
        final String s => s,
        _ => null,
      },
      derniereLecon: switch (j['derniere_lecon']) {
        final String s => s,
        _ => null,
      },
    );
  }
}
