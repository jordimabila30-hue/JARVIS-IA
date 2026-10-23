import 'exercice.dart';

/// Contenus du module Apprendre (Kelasi) : parcours → unités → leçons,
/// fiches pédagogiques et sources. Lus dans `assets/apprentissage/`
/// (un JSON par parcours) ; la logique vit dans `services/apprentissage/`.

/// Statut de validation humaine d'une fiche. Seules les fiches [valide]
/// sont publiées hors du mode d'aperçu de développement.
enum StatutValidation {
  brouillon,
  valide;

  static StatutValidation? depuis(Object? v) => switch (v) {
    'brouillon' => brouillon,
    'valide' => valide,
    _ => null,
  };
}

/// Référence pédagogique d'une fiche.
class SourcePedagogique {
  const SourcePedagogique({
    required this.titre,
    required this.editeur,
    this.url,
    this.consulteLe,
  });

  final String titre;

  /// Organisme, auteur ou éditeur (« Office québécois de la langue
  /// française »…).
  final String editeur;
  final String? url;

  /// Date à laquelle la page a réellement été consultée (null : référence
  /// bibliographique non consultée en ligne).
  final String? consulteLe;

  factory SourcePedagogique.depuisJson(Map<String, dynamic> j) {
    final titre = j['titre'], editeur = j['editeur'];
    if (titre is! String || editeur is! String) {
      throw const FormatException('source : « titre » et « editeur »');
    }
    return SourcePedagogique(
      titre: titre,
      editeur: editeur,
      url: j['url'] as String?,
      consulteLe: j['consulte_le'] as String?,
    );
  }
}

/// Trace de la relecture humaine qui a validé une fiche.
class ValidationHumaine {
  const ValidationHumaine({required this.par, required this.le});

  /// Personne ou équipe qui a relu (« Équipe SEVEN TECH »…).
  final String par;

  /// Date de la relecture (AAAA-MM-JJ).
  final DateTime le;

  static ValidationHumaine? depuisJson(Object? j) {
    if (j is! Map) return null;
    final par = j['par'], le = DateTime.tryParse('${j['le']}');
    if (par is! String || par.trim().isEmpty || le == null) return null;
    return ValidationHumaine(par: par, le: le);
  }
}

/// Fiche pédagogique : une notion, son explication, ses exemples et ses
/// sources. Les exercices s'y rattachent par [id].
class FichePedagogique {
  const FichePedagogique({
    required this.id,
    required this.titre,
    required this.niveau,
    required this.explication,
    required this.exemples,
    required this.aEviter,
    required this.sources,
    required this.statut,
    required this.version,
    this.validation,
  });

  final String id;
  final String titre;
  final int niveau;
  final String explication;

  /// Bons exemples, puis exemples à éviter (facultatifs).
  final List<String> exemples;
  final List<String> aEviter;
  final List<SourcePedagogique> sources;
  final StatutValidation statut;
  final int version;

  /// Relecture humaine tracée (obligatoire pour être publiée).
  final ValidationHumaine? validation;

  /// Publiable : marquée `valide` ET relue (qui, quand). Un statut
  /// `valide` sans trace de relecture reste traité comme un brouillon.
  bool get validee => statut == StatutValidation.valide && validation != null;

  factory FichePedagogique.depuisJson(Map<String, dynamic> j) {
    final id = j['id'];
    final statut = StatutValidation.depuis(j['statut']);
    final sources = j['sources'];
    if (id is! String ||
        j['titre'] is! String ||
        j['explication'] is! String ||
        j['niveau'] is! int ||
        j['version'] is! int ||
        statut == null ||
        sources is! List) {
      throw FormatException('fiche ${id ?? '?'} incomplète');
    }
    return FichePedagogique(
      id: id,
      titre: j['titre'] as String,
      niveau: j['niveau'] as int,
      explication: j['explication'] as String,
      exemples: _liste(j['exemples']),
      aEviter: _liste(j['a_eviter']),
      sources: [
        for (final s in sources)
          SourcePedagogique.depuisJson(s as Map<String, dynamic>),
      ],
      statut: statut,
      version: j['version'] as int,
      validation: ValidationHumaine.depuisJson(j['validation']),
    );
  }
}

/// Leçon de 2 à 4 minutes : un objectif, ses fiches, ses exercices.
class Lecon {
  const Lecon({
    required this.id,
    required this.titre,
    required this.niveau,
    required this.dureeMinutes,
    required this.objectif,
    required this.fiches,
    required this.exercices,
  });

  final String id;
  final String titre;
  final int niveau;
  final int dureeMinutes;
  final String objectif;

  /// Identifiants des fiches présentées, dans l'ordre.
  final List<String> fiches;
  final List<Exercice> exercices;

  Exercice? exercice(String id) {
    for (final e in exercices) {
      if (e.id == id) return e;
    }
    return null;
  }

  factory Lecon.depuisJson(Map<String, dynamic> j) {
    final id = j['id'];
    final exercices = j['exercices'];
    if (id is! String ||
        j['titre'] is! String ||
        j['objectif'] is! String ||
        j['niveau'] is! int ||
        j['duree_minutes'] is! int ||
        exercices is! List) {
      throw FormatException('leçon ${id ?? '?'} incomplète');
    }
    return Lecon(
      id: id,
      titre: j['titre'] as String,
      niveau: j['niveau'] as int,
      dureeMinutes: j['duree_minutes'] as int,
      objectif: j['objectif'] as String,
      fiches: _liste(j['fiches']),
      exercices: [
        for (final e in exercices)
          Exercice.depuisJson(e as Map<String, dynamic>),
      ],
    );
  }
}

class Unite {
  const Unite({required this.id, required this.titre, required this.lecons});

  final String id;
  final String titre;
  final List<Lecon> lecons;
}

/// Entrée du catalogue (`catalogue.json`) : de quoi afficher la carte d'un
/// parcours sans lire son contenu.
class ResumeParcours {
  const ResumeParcours({
    required this.id,
    required this.titre,
    required this.icone,
    required this.fichier,
  });

  final String id;
  final String titre;

  /// Clé d'icône (`courrier`, `dialogue`, `relations`, `technique`…),
  /// traduite par les widgets.
  final String icone;

  /// Chemin de l'asset JSON du parcours.
  final String fichier;
}

/// Contenu complet d'un parcours (fiches et unités).
class Parcours {
  const Parcours({
    required this.resume,
    required this.version,
    required this.fiches,
    required this.unites,
  });

  final ResumeParcours resume;
  final int version;
  final Map<String, FichePedagogique> fiches;
  final List<Unite> unites;

  String get id => resume.id;

  Iterable<Lecon> get lecons => unites.expand((u) => u.lecons);

  Lecon? lecon(String id) {
    for (final l in lecons) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Publiable : toutes ses fiches existent et sont validées.
  bool leconValidee(Lecon l) =>
      l.fiches.isNotEmpty && l.fiches.every((f) => fiches[f]?.validee == true);
}

List<String> _liste(Object? v) => v is List
    ? List<String>.unmodifiable(v.whereType<String>())
    : const <String>[];

/// Situation du quotidien (`situations.json`) : pratique écrite corrigée
/// par le tuteur, et dialogue oral (JARVIS joue [role]).
class SituationPratique {
  const SituationPratique({
    required this.id,
    required this.titre,
    required this.icone,
    required this.fiches,
    required this.objectif,
    required this.consigne,
    required this.role,
    required this.ouverture,
  });

  final String id;
  final String titre;
  final String icone;
  final List<String> fiches;
  final String objectif;
  final String consigne;
  final String role;

  /// Première réplique de JARVIS dans le dialogue.
  final String ouverture;

  static SituationPratique? depuisJson(Object? j) {
    if (j is! Map) return null;
    final champs = ['id', 'titre', 'objectif', 'consigne', 'role', 'ouverture'];
    if (champs.any((c) => j[c] is! String) || j['fiches'] is! List) return null;
    return SituationPratique(
      id: j['id'] as String,
      titre: j['titre'] as String,
      icone: j['icone'] is String ? j['icone'] as String : '',
      fiches: (j['fiches'] as List).whereType<String>().toList(),
      objectif: j['objectif'] as String,
      consigne: j['consigne'] as String,
      role: j['role'] as String,
      ouverture: j['ouverture'] as String,
    );
  }
}
