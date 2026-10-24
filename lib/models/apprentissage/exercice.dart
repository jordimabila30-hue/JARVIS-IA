/// Exercices du module Apprendre (Kelasi) : des données pures, lues dans
/// les JSON des parcours, et leur correction. Aucune interface ici : les
/// widgets de `widgets/apprentissage/exercices/` les affichent.
library;

/// Types d'exercices pris en charge (valeur `type` du JSON).
enum TypeExercice {
  choix('choix'),
  vraiFaux('vrai_faux'),
  trous('trous'),
  ordre('ordre'),
  association('association'),
  meilleurMessage('meilleur_message'),
  ecoute('ecoute');

  const TypeExercice(this.cle);

  final String cle;

  static TypeExercice? depuis(Object? cle) {
    for (final t in values) {
      if (t.cle == cle) return t;
    }
    return null;
  }
}

/// Réponse donnée par l'utilisateur.
sealed class ReponseExercice {
  const ReponseExercice();
}

/// Option choisie (choix multiple, meilleur message, écoute).
class ReponseChoix extends ReponseExercice {
  const ReponseChoix(this.index);
  final int index;
}

class ReponseVraiFaux extends ReponseExercice {
  const ReponseVraiFaux(this.valeur);
  final bool valeur;
}

/// Option choisie pour chaque trou, dans l'ordre du texte.
class ReponseTrous extends ReponseExercice {
  const ReponseTrous(this.choix);
  final List<int> choix;
}

/// Éléments dans l'ordre proposé, par leur index dans l'ordre correct.
class ReponseOrdre extends ReponseExercice {
  const ReponseOrdre(this.ordre);
  final List<int> ordre;
}

/// Élément de gauche (index) → élément de droite (index d'origine).
class ReponseAssociation extends ReponseExercice {
  const ReponseAssociation(this.paires);
  final Map<int, int> paires;
}

/// Exercice d'une leçon. Chaque exercice se rattache à une fiche ([fiche]).
sealed class Exercice {
  const Exercice({
    required this.id,
    required this.fiche,
    required this.consigne,
    required this.explication,
  });

  final String id;

  /// Identifiant de la fiche pédagogique de référence.
  final String fiche;
  final String consigne;

  /// Explication courte affichée après la réponse.
  final String explication;

  TypeExercice get type;

  bool estJuste(ReponseExercice reponse);

  /// La bonne réponse, en clair (affichée après une erreur).
  String get solution;

  /// Erreurs de cohérence internes (index hors limites…), vides si valide.
  List<String> verifier();

  /// Lit un exercice ; [FormatException] si le JSON est inutilisable.
  static Exercice depuisJson(Map<String, dynamic> j) {
    final type = TypeExercice.depuis(j['type']);
    final id = _texte(j, 'id');
    final fiche = _texte(j, 'fiche');
    final consigne = _texte(j, 'consigne');
    final explication = _texte(j, 'explication');
    switch (type) {
      case TypeExercice.choix:
      case TypeExercice.meilleurMessage:
      case TypeExercice.ecoute:
        return ExerciceChoix(
          id: id,
          fiche: fiche,
          consigne: consigne,
          explication: explication,
          type: type!,
          options: _textes(j, 'options'),
          bonne: _entier(j, 'bonne'),
          contexte: j['contexte'] as String?,
          audio: type == TypeExercice.ecoute ? _texte(j, 'audio') : null,
        );
      case TypeExercice.vraiFaux:
        final r = j['reponse'];
        if (r is! bool) throw FormatException('$id : « reponse » booléen');
        return ExerciceVraiFaux(
          id: id,
          fiche: fiche,
          consigne: consigne,
          explication: explication,
          affirmation: _texte(j, 'affirmation'),
          reponse: r,
        );
      case TypeExercice.trous:
        final trous = j['trous'];
        if (trous is! List) throw FormatException('$id : « trous » liste');
        return ExerciceTrous(
          id: id,
          fiche: fiche,
          consigne: consigne,
          explication: explication,
          texte: _texte(j, 'texte'),
          trous: [
            for (final t in trous)
              if (t is Map<String, dynamic>)
                Trou(options: _textes(t, 'options'), bonne: _entier(t, 'bonne'))
              else
                throw FormatException('$id : trou illisible'),
          ],
        );
      case TypeExercice.ordre:
        return ExerciceOrdre(
          id: id,
          fiche: fiche,
          consigne: consigne,
          explication: explication,
          elements: _textes(j, 'elements'),
        );
      case TypeExercice.association:
        final paires = j['paires'];
        if (paires is! List) throw FormatException('$id : « paires » liste');
        return ExerciceAssociation(
          id: id,
          fiche: fiche,
          consigne: consigne,
          explication: explication,
          paires: [
            for (final p in paires)
              if (p is List &&
                  p.length == 2 &&
                  p[0] is String &&
                  p[1] is String)
                (p[0] as String, p[1] as String)
              else
                throw FormatException('$id : paire illisible'),
          ],
        );
      case null:
        throw FormatException('$id : type inconnu « ${j['type']} »');
    }
  }
}

/// Une option parmi plusieurs : choix multiple, meilleur message (avec un
/// [contexte]) ou écoute (texte [audio] à faire entendre).
class ExerciceChoix extends Exercice {
  const ExerciceChoix({
    required super.id,
    required super.fiche,
    required super.consigne,
    required super.explication,
    required this.type,
    required this.options,
    required this.bonne,
    this.contexte,
    this.audio,
  });

  @override
  final TypeExercice type;
  final List<String> options;
  final int bonne;

  /// Situation présentée avant les options (meilleur message).
  final String? contexte;

  /// Texte à écouter (écoute) ; toujours lisible à l'écran en secours.
  final String? audio;

  @override
  bool estJuste(ReponseExercice r) => r is ReponseChoix && r.index == bonne;

  @override
  String get solution => options[bonne];

  @override
  List<String> verifier() => [
    if (options.length < 2) '$id : au moins 2 options',
    if (bonne < 0 || bonne >= options.length) '$id : « bonne » hors limites',
    if (type == TypeExercice.ecoute && (audio == null || audio!.isEmpty))
      '$id : texte « audio » manquant',
  ];
}

class ExerciceVraiFaux extends Exercice {
  const ExerciceVraiFaux({
    required super.id,
    required super.fiche,
    required super.consigne,
    required super.explication,
    required this.affirmation,
    required this.reponse,
  });

  final String affirmation;
  final bool reponse;

  @override
  TypeExercice get type => TypeExercice.vraiFaux;

  @override
  bool estJuste(ReponseExercice r) =>
      r is ReponseVraiFaux && r.valeur == reponse;

  @override
  String get solution => reponse ? 'Vrai' : 'Faux';

  @override
  List<String> verifier() => const [];
}

/// Un trou du texte : options proposées et la bonne.
class Trou {
  const Trou({required this.options, required this.bonne});
  final List<String> options;
  final int bonne;
}

/// Texte à compléter : chaque `___` du [texte] est un trou, dans l'ordre.
class ExerciceTrous extends Exercice {
  const ExerciceTrous({
    required super.id,
    required super.fiche,
    required super.consigne,
    required super.explication,
    required this.texte,
    required this.trous,
  });

  static const marque = '___';

  final String texte;
  final List<Trou> trous;

  /// Morceaux du texte entre les trous (un de plus que de trous).
  List<String> get morceaux => texte.split(marque);

  @override
  TypeExercice get type => TypeExercice.trous;

  @override
  bool estJuste(ReponseExercice r) {
    if (r is! ReponseTrous || r.choix.length != trous.length) return false;
    for (var i = 0; i < trous.length; i++) {
      if (r.choix[i] != trous[i].bonne) return false;
    }
    return true;
  }

  @override
  String get solution {
    final m = morceaux;
    final b = StringBuffer(m.first);
    for (var i = 0; i < trous.length; i++) {
      b
        ..write(trous[i].options[trous[i].bonne])
        ..write(m[i + 1]);
    }
    return b.toString();
  }

  @override
  List<String> verifier() => [
    if (trous.isEmpty) '$id : aucun trou',
    if (morceaux.length - 1 != trous.length)
      '$id : ${morceaux.length - 1} « ___ » pour ${trous.length} trous',
    for (final t in trous)
      if (t.options.length < 2 || t.bonne < 0 || t.bonne >= t.options.length)
        '$id : trou mal défini',
  ];
}

/// Remettre dans l'ordre : [elements] est l'ordre correct ; l'affichage
/// les mélange de façon stable ([melange]).
class ExerciceOrdre extends Exercice {
  const ExerciceOrdre({
    required super.id,
    required super.fiche,
    required super.consigne,
    required super.explication,
    required this.elements,
  });

  final List<String> elements;

  @override
  TypeExercice get type => TypeExercice.ordre;

  /// Ordre d'affichage (index des éléments), jamais déjà correct.
  List<int> get melange => melangeStable(id, elements.length);

  @override
  bool estJuste(ReponseExercice r) {
    if (r is! ReponseOrdre || r.ordre.length != elements.length) return false;
    for (var i = 0; i < elements.length; i++) {
      if (r.ordre[i] != i) return false;
    }
    return true;
  }

  @override
  String get solution => [
    for (var i = 0; i < elements.length; i++) '${i + 1}. ${elements[i]}',
  ].join('\n');

  @override
  List<String> verifier() => [
    if (elements.length < 3) '$id : au moins 3 éléments',
  ];
}

/// Associer : chaque élément de gauche avec celui de droite de sa paire.
class ExerciceAssociation extends Exercice {
  const ExerciceAssociation({
    required super.id,
    required super.fiche,
    required super.consigne,
    required super.explication,
    required this.paires,
  });

  final List<(String, String)> paires;

  @override
  TypeExercice get type => TypeExercice.association;

  /// Ordre d'affichage de la colonne de droite.
  List<int> get melangeDroite => melangeStable('$id/d', paires.length);

  @override
  bool estJuste(ReponseExercice r) {
    if (r is! ReponseAssociation || r.paires.length != paires.length) {
      return false;
    }
    for (var i = 0; i < paires.length; i++) {
      if (r.paires[i] != i) return false;
    }
    return true;
  }

  @override
  String get solution =>
      [for (final p in paires) '${p.$1} → ${p.$2}'].join('\n');

  @override
  List<String> verifier() => [if (paires.length < 2) '$id : au moins 2 paires'];
}

/// Permutation de 0..n-1 déterminée par [graine] (toujours la même pour un
/// exercice), différente de l'ordre naturel dès que n ≥ 2.
List<int> melangeStable(String graine, int n) {
  final ordre = List<int>.generate(n, (i) => i);
  if (n < 2) return ordre;
  // Générateur congruentiel simple, initialisé par le texte (FNV-1a).
  var etat = 0x811C9DC5;
  for (final c in graine.codeUnits) {
    etat = ((etat ^ c) * 0x01000193) & 0x7FFFFFFF;
  }
  int suivant() => etat = (etat * 1103515245 + 12345) & 0x7FFFFFFF;
  for (var i = n - 1; i > 0; i--) {
    final j = suivant() % (i + 1);
    final t = ordre[i];
    ordre[i] = ordre[j];
    ordre[j] = t;
  }
  var identite = true;
  for (var i = 0; i < n; i++) {
    if (ordre[i] != i) identite = false;
  }
  if (identite) {
    // Rotation d'un cran : jamais l'ordre correct d'emblée.
    ordre.add(ordre.removeAt(0));
  }
  return ordre;
}

String _texte(Map<String, dynamic> j, String cle) {
  final v = j[cle];
  if (v is String && v.trim().isNotEmpty) return v;
  throw FormatException('« $cle » manquant (${j['id'] ?? '?'})');
}

int _entier(Map<String, dynamic> j, String cle) {
  final v = j[cle];
  if (v is int) return v;
  throw FormatException('« $cle » entier attendu (${j['id'] ?? '?'})');
}

List<String> _textes(Map<String, dynamic> j, String cle) {
  final v = j[cle];
  if (v is List && v.every((e) => e is String && e.trim().isNotEmpty)) {
    return List<String>.unmodifiable(v.cast<String>());
  }
  throw FormatException('« $cle » : liste de textes (${j['id'] ?? '?'})');
}
