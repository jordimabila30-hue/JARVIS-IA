import 'dart:math' as math;

/// Un mot de la réponse de JARVIS, avec son poids dans la phrase.
class MotProsodique {
  const MotProsodique({
    required this.debut,
    required this.fin,
    required this.accent,
    required this.duree,
    required this.pauseApres,
    required this.syllabes,
  });

  /// Position du mot dans le texte (caractères).
  final int debut, fin;

  /// Force du mot (0 à 1) : sert à la réaction des particules.
  final double accent;

  /// Durée estimée du mot et de la pause qui le suit (s), utilisées
  /// seulement quand la plateforme ne signale pas les mots prononcés.
  final double duree, pauseApres;

  /// Nombre de syllabes (groupes de voyelles), pour moduler l'énergie.
  final int syllabes;
}

/// Structure rythmique d'une phrase à prononcer.
///
/// En français, l'accent tombe à la fin de chaque groupe rythmique (avant
/// une virgule, un point…) ; les petits mots outils sont faibles, les mots
/// longs, les nombres et les noms propres sont plus marqués.
class Prosodie {
  Prosodie.analyser(String texte) : mots = _analyser(texte);

  final List<MotProsodique> mots;

  static final _mot = RegExp(
    r"[\p{L}\p{N}]+(?:[’'-][\p{L}\p{N}]+)*",
    unicode: true,
  );
  static final _voyelles = RegExp(
    r'[aeiouyàâäéèêëîïôöùûüœæ]+',
    caseSensitive: false,
  );

  static const _outils = {
    'le',
    'la',
    'les',
    'l',
    'de',
    'des',
    'du',
    'd',
    'un',
    'une',
    'et',
    'ou',
    'à',
    'a',
    'en',
    'je',
    'j',
    'tu',
    'il',
    'on',
    'vous',
    'nous',
    'me',
    'm',
    'te',
    't',
    'se',
    's',
    'ne',
    'n',
    'pas',
    'que',
    'qu',
    'ce',
    'c',
    'est',
    'au',
    'aux',
    'pour',
    'par',
    'sur',
    'dans',
    'mais',
  };

  static List<MotProsodique> _analyser(String texte) {
    final trouves = _mot.allMatches(texte).toList();
    final resultat = <MotProsodique>[];
    var debutGroupe = true;
    for (var i = 0; i < trouves.length; i++) {
      final m = trouves[i];
      final brut = m.group(0)!;
      final mot = brut.toLowerCase();
      // Ponctuation entre ce mot et le suivant.
      final suite = texte.substring(
        m.end,
        i + 1 < trouves.length ? trouves[i + 1].start : texte.length,
      );
      final finPhrase =
          suite.contains(RegExp(r'[.!?…]')) || i == trouves.length - 1;
      final finGroupe = finPhrase || suite.contains(RegExp(r'[,;:]'));

      var accent = 0.42 + math.min(0.24, math.max(0, brut.length - 3) * 0.04);
      if (_outils.contains(mot.split(RegExp(r"[’']")).first) &&
          brut.length <= 4) {
        accent = 0.25;
      }
      if (finGroupe) accent += 0.3;
      if (debutGroupe) accent += 0.08;
      if (RegExp(r'\d').hasMatch(brut) ||
          (brut.length > 1 && brut == brut.toUpperCase())) {
        accent += 0.15;
      }

      final syllabes = math.max(1, _voyelles.allMatches(mot).length);
      resultat.add(
        MotProsodique(
          debut: m.start,
          fin: m.end,
          accent: accent.clamp(0.2, 1.0),
          duree: 0.05 + 0.16 * syllabes,
          pauseApres: finPhrase ? 0.42 : (finGroupe ? 0.22 : 0.0),
          syllabes: syllabes,
        ),
      );
      debutGroupe = finGroupe;
    }
    return resultat;
  }

  /// Mot qui commence à la position [debut] du texte (signalée par la
  /// synthèse vocale), ou null si la position est hors du texte.
  MotProsodique? motA(int debut) {
    for (final m in mots) {
      if (debut < m.fin) return m;
    }
    return null;
  }

  /// Accent du mot à la position [debut].
  double accentA(int debut) => motA(debut)?.accent ?? 0.5;
}
