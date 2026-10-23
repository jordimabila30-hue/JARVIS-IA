/// Préparation d'une réponse ÉCRITE pour la VOIX (texte écrit inchangé dans
/// le fil). Règles locales, déterministes et rapides (aucun appel au
/// modèle) :
///
/// - mise en forme retirée : gras, italique, barré, titres, citations,
///   séparateurs, tableaux, liens, émojis ; jamais un symbole prononcé ;
/// - listes numérotées → enchaînement parlé (« D'abord… Ensuite… Enfin… ») ;
///   puces → phrases ; le « : » qui annonce une liste devient une fin de
///   phrase ;
/// - blocs de code non lus (« le code est affiché à l'écran ») ;
/// - symboles et unités courants dits en mots (≈, ≤, →, km/h, °C, m²…),
///   seulement à côté d'un nombre pour les unités ;
/// - chiffres, dates, pourcentages et valeurs JAMAIS modifiés ;
/// - chaque ligne finit par une ponctuation : la synthèse marque la pause.
class TexteOral {
  const TexteOral._();

  static String preparer(String texte) {
    var t = texte.replaceAll('\r\n', '\n');

    // Blocs de code : jamais lus caractère par caractère.
    // Seul sur sa ligne : une phrase ; au milieu d'une phrase : une
    // incise, sans casser la phrase autour.
    t = t.replaceAll(RegExp(r'```[\s\S]*?(```|$)'), _code);

    final lignes = <String>[];
    final liste = <String>[];
    var listeNumerotee = false;

    void viderListe() {
      if (liste.isEmpty) return;
      for (var i = 0; i < liste.length; i++) {
        var item = _phrase(liste[i]);
        if (listeNumerotee && liste.length > 1) {
          final lien = i == 0
              ? 'D’abord'
              : i == liste.length - 1
              ? 'Enfin'
              : (i.isOdd ? 'Ensuite' : 'Puis');
          item = '$lien, ${_minuscule(item)}';
        }
        lignes.add(item);
      }
      liste.clear();
    }

    for (final brute in t.split('\n')) {
      var l = brute.trim();
      if (l.isEmpty) {
        viderListe();
        continue;
      }
      // Séparateurs et lignes de tableau « |---|---| ».
      if (RegExp(r'^([-*_=]\s*){3,}$').hasMatch(l) ||
          RegExp(r'^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$').hasMatch(l)) {
        continue;
      }
      // Ligne de tableau : cellules dites à la suite.
      if (l.startsWith('|') && l.endsWith('|') && l.length > 2) {
        l = l
            .substring(1, l.length - 1)
            .split('|')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .join(', ');
      }
      final numero = RegExp(r'^(\d{1,2})[.)]\s+(.+)$').firstMatch(l);
      final puce = RegExp(r'^[-*•+]\s+(.+)$').firstMatch(l);
      if (numero != null || puce != null) {
        final numerotee = numero != null;
        if (liste.isNotEmpty && numerotee != listeNumerotee) viderListe();
        listeNumerotee = numerotee;
        liste.add(numerotee ? numero.group(2)! : puce!.group(1)!);
        continue;
      }
      viderListe();
      // Titres et citations : une phrase ordinaire.
      l = l.replaceFirst(RegExp(r'^#{1,6}\s+'), '').replaceFirst(RegExp(r'^>\s?'), '');
      lignes.add(_phrase(l));
    }
    viderListe();

    // Un « : » qui annonçait une liste devient une fin de phrase.
    var sortie = lignes.join(' ').replaceAll(RegExp(r'\s*:\s*(?=D’abord,)'), '. ');
    sortie = sortie.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return sortie;
  }

  static const _code = '\u0000code\u0000';

  /// Une ligne nettoyée, terminée par une ponctuation.
  static String _phrase(String ligne) {
    if (ligne.trim() == _code) return 'Le code est affiché à l’écran.';
    var l = _symboles(
      _sansMarques(ligne.replaceAll(_code, ' (le code est affiché à l’écran) ')),
    ).trim();
    if (l.isEmpty) return '';
    if (!RegExp(r'[.!?…:;,»"]$').hasMatch(l)) l = '$l.';
    return l;
  }

  static String _sansMarques(String l) => l
      // Liens : le texte seulement ; adresse nue : jamais épelée.
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'https?://\S+'), 'le lien affiché')
      .replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m.group(2)!)
      .replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'(?<![\w*])[*_](?!\s)([^*_\n]+?)[*_](?!\w)'), (m) => m.group(1)!)
      // Code en ligne : le mot seul (« print() » → « print »).
      .replaceAllMapped(
        RegExp(r'`([^`]+)`'),
        (m) => m.group(1)!.replaceAll(RegExp(r'\(\)$'), ''),
      )
      // « ~ 5 € » : environ (jamais « tilde »).
      .replaceAll(RegExp(r'~\s*(?=\d)'), 'environ ')
      // Calculs : « 2 * 3 » → « 2 fois 3 » (jamais « 2 3 », le sens
      // changerait) ; puissances dites en mots.
      .replaceAllMapped(RegExp(r'(\w)\s*\*\s*(\w)'), (m) => '${m.group(1)} fois ${m.group(2)}')
      .replaceAllMapped(RegExp(r'(\w)\^2(?!\d)'), (m) => '${m.group(1)} au carré')
      .replaceAllMapped(RegExp(r'(\w)\^3(?!\d)'), (m) => '${m.group(1)} au cube')
      .replaceAllMapped(RegExp(r'(\w)\^(\d+)'), (m) => '${m.group(1)} puissance ${m.group(2)}')
      // Marques restantes (non refermées) : jamais prononcées.
      .replaceAll(RegExp(r'[*`#]+'), '')
      .replaceAll(RegExp(r'(?<!\w)_+|_+(?!\w)'), ' ')
      // Émojis et pictogrammes.
      .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]', unicode: true), '');

  static final _unites = <String, String>{
    'km/h': 'kilomètres par heure',
    'm/s': 'mètres par seconde',
    'km²': 'kilomètres carrés',
    'cm²': 'centimètres carrés',
    'm²': 'mètres carrés',
    'm³': 'mètres cubes',
    '°C': 'degrés Celsius',
    '°F': 'degrés Fahrenheit',
    '°': 'degrés',
  };

  static String _symboles(String l) {
    // Unités seulement juste après un nombre (« 90 km/h », « 25°C »).
    for (final e in _unites.entries) {
      l = l.replaceAllMapped(
        RegExp('(\\d)\\s?${RegExp.escape(e.key)}(?![\\w²³])'),
        (m) => '${m.group(1)} ${e.value}',
      );
    }
    return l
        .replaceAll(RegExp(r'\s*(→|=>|⇒|->)\s*'), ', puis ')
        .replaceAll('≈', ' environ ')
        .replaceAll('≤', ' inférieur ou égal à ')
        .replaceAll('≥', ' supérieur ou égal à ')
        .replaceAll('≠', ' différent de ')
        .replaceAll('±', ' plus ou moins ')
        .replaceAllMapped(RegExp(r'(\d)\s*[×x]\s*(\d)'), (m) => '${m.group(1)} fois ${m.group(2)}')
        .replaceAll('÷', ' divisé par ')
        .replaceAll(' & ', ' et ')
        // Abréviations courantes, dites en entier.
        .replaceAll(RegExp(r'\bvs\.?(?=\s)'), 'contre')
        .replaceAll(RegExp(r'\bRDV\b'), 'rendez-vous')
        .replaceAllMapped(RegExp(r'\bp\.\s?(\d)'), (m) => 'page ${m.group(1)}')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'\(\s+'), '(');
  }

  /// « Absorption » → « absorption » (jamais un sigle : « ADN » reste).
  static String _minuscule(String s) {
    if (s.length < 2) return s;
    final a = s[0];
    final b = s[1];
    if (a != a.toUpperCase() || b != b.toLowerCase() || b == b.toUpperCase()) return s;
    return a.toLowerCase() + s.substring(1);
  }
}
