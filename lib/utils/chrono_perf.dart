/// Chronomètre de performance du moteur graphique (particules, fond).
///
/// Désactivé par défaut : [actif] est une constante, donc les appels sont
/// supprimés à la compilation. Pour mesurer :
/// `flutter build web -t tool/banc_perf.dart --dart-define=JARVIS_PERF=true`.
class ChronoPerf {
  ChronoPerf._();

  static const actif = bool.fromEnvironment('JARVIS_PERF');

  /// Parties retirées du dessin pour mesurer leur coût (banc seulement,
  /// `?sans=pim.halos,fond.flou…`). Toujours vide hors du banc.
  static final Set<String> _retires = actif
      ? (Uri.base.queryParameters['sans']?.split(',').toSet() ?? const {})
      : const {};

  static bool sans(String partie) => actif && _retires.contains(partie);

  /// Variante expérimentale activée (banc seulement, `?avec=…`).
  static final Set<String> _ajouts = actif
      ? (Uri.base.queryParameters['avec']?.split(',').toSet() ?? const {})
      : const {};

  static bool avec(String partie) => actif && _ajouts.contains(partie);

  static final _horloge = Stopwatch()..start();
  static final _total = <String, int>{};
  static final _nombre = <String, int>{};
  static final _max = <String, int>{};

  /// Début d'une section (µs) ; 0 si inactif.
  static int debut() => actif ? _horloge.elapsedMicroseconds : 0;

  /// Fin de la section [nom] commencée à [depart].
  static void fin(String nom, int depart) {
    if (!actif) return;
    final duree = _horloge.elapsedMicroseconds - depart;
    _total[nom] = (_total[nom] ?? 0) + duree;
    _nombre[nom] = (_nombre[nom] ?? 0) + 1;
    if (duree > (_max[nom] ?? 0)) _max[nom] = duree;
  }

  static void reinitialiser() {
    _total.clear();
    _nombre.clear();
    _max.clear();
  }

  /// Par section : appels, durée moyenne et maximale (ms).
  static Map<String, Map<String, num>> rapport() => {
    for (final nom in _total.keys)
      nom: {
        'appels': _nombre[nom]!,
        'moyenneMs': _total[nom]! / _nombre[nom]! / 1000,
        'maxMs': _max[nom]! / 1000,
      },
  };
}
