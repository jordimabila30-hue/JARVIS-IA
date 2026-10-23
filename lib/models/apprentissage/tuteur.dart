/// Échanges avec le tuteur de Kelasi (`POST /api/v1/apprentissage/tuteur`).
///
/// L'application n'envoie que des identifiants (fiches, exercice,
/// situation) et les textes de l'élève : le serveur lit lui-même les
/// fiches. Les sources affichées viennent de l'événement `sources`, après
/// validation par le serveur, jamais du texte du modèle.
library;

/// Actions pédagogiques comprises par le serveur.
enum ActionTuteur {
  simplifier('simplifier', 'Plus simplement'),
  exemple('exemple', 'Un exemple'),
  erreur('erreur', 'Mon erreur'),
  entrainer('entrainer', 'M’entraîner'),
  situation('situation', 'Correction'),
  dialogue('dialogue', 'Dialogue'),
  bilan('bilan', 'Bilan');

  const ActionTuteur(this.cle, this.libelle);

  final String cle;
  final String libelle;
}

/// Une réplique d'un dialogue de situation (oral ou écrit).
class Replique {
  const Replique.eleve(this.texte) : deJarvis = false;
  const Replique.jarvis(this.texte) : deJarvis = true;

  final bool deJarvis;
  final String texte;

  Map<String, String> versJson() => {
    'role': deJarvis ? 'jarvis' : 'eleve',
    'texte': texte,
  };
}

/// Demande au tuteur.
class DemandeTuteur {
  const DemandeTuteur({
    required this.action,
    this.fiches = const [],
    this.exercice,
    this.reponse,
    this.texte,
    this.situation,
    this.historique = const [],
    this.niveau,
    this.oral = false,
    this.versionCorpus,
  });

  final ActionTuteur action;
  final List<String> fiches;
  final String? exercice;

  /// Réponse de l'élève à l'exercice (« Mon erreur »), en clair.
  final String? reponse;

  /// Production de l'élève (situation écrite).
  final String? texte;
  final String? situation;
  final List<Replique> historique;

  /// `debutant` / `intermediaire` / `avance`.
  final String? niveau;
  final bool oral;
  final String? versionCorpus;

  Map<String, dynamic> versJson() => {
    'action': action.cle,
    if (fiches.isNotEmpty) 'fiches': fiches,
    'exercice': ?exercice,
    'reponse': ?reponse,
    'texte': ?texte,
    'situation': ?situation,
    if (historique.isNotEmpty)
      'historique': [
        // Le serveur garde les 16 dernières répliques au plus.
        for (final r
            in historique.length > 16
                ? historique.sublist(historique.length - 16)
                : historique)
          r.versJson(),
      ],
    'niveau': ?niveau,
    if (oral) 'oral': true,
    'corpus_version': ?versionCorpus,
  };
}

/// Source validée par le serveur (fiche du corpus et ses références).
class SourceTuteur {
  const SourceTuteur({
    required this.fiche,
    required this.titre,
    required this.validee,
    required this.references,
  });

  final String fiche;
  final String titre;

  /// Fiche relue par l'équipe (sinon : brouillon, développement).
  final bool validee;
  final List<({String titre, String editeur, String? url})> references;

  static List<SourceTuteur> listeDepuisJson(Object? j) {
    if (j is! List) return const [];
    return [
      for (final s in j)
        if (s is Map && s['fiche'] is String && s['titre'] is String)
          SourceTuteur(
            fiche: s['fiche'] as String,
            titre: s['titre'] as String,
            validee: s['validee'] == true,
            references: [
              for (final r
                  in (s['sources'] is List ? s['sources'] as List : const []))
                if (r is Map && r['titre'] is String)
                  (
                    titre: r['titre'] as String,
                    editeur: (r['editeur'] as String?) ?? '',
                    url: r['url'] as String?,
                  ),
            ],
          ),
    ];
  }
}

/// Réponse complète du tuteur.
class ReponseTuteur {
  const ReponseTuteur({
    required this.texte,
    required this.sources,
    this.memeVersion = true,
  });

  final String texte;
  final List<SourceTuteur> sources;

  /// Corpus de l'application identique à celui du serveur.
  final bool memeVersion;
}

/// Une ligne de réponse, d'après son préfixe : règle (fiche), exemple
/// inventé pour illustrer, conseil de style, ou texte simple.
enum GenreLigne { regle, exemple, conseil, reussi, ameliorer, texte }

/// Découpe une réponse en lignes typées (affichage distinct).
List<(GenreLigne, String)> lignesTuteur(String texte) {
  const prefixes = {
    'Règle :': GenreLigne.regle,
    'Exemple :': GenreLigne.exemple,
    'Conseil :': GenreLigne.conseil,
    'Réussi :': GenreLigne.reussi,
    'À améliorer :': GenreLigne.ameliorer,
  };
  final lignes = <(GenreLigne, String)>[];
  for (final brute in texte.split('\n')) {
    final l = brute.trim();
    if (l.isEmpty) continue;
    var genre = GenreLigne.texte;
    var contenu = l;
    for (final p in prefixes.entries) {
      if (l.startsWith(p.key)) {
        genre = p.value;
        contenu = l.substring(p.key.length).trim();
        break;
      }
    }
    lignes.add((genre, contenu));
  }
  return lignes;
}
