import 'dart:math' as math;

/// Calculs dictés à la voix, en français.
///
/// Comprend les nombres en chiffres (« 12 », « 3,5 ») ou en lettres
/// (« douze », « quatre-vingt-dix-sept », « deux mille ») et les opérations :
/// plus, moins, fois / multiplié par / x, divisé par / sur, puissance,
/// au carré, au cube, racine carrée de, pour cent de.
/// Les priorités habituelles sont respectées (× et ÷ avant + et −).
class CalculVocal {
  CalculVocal._();

  static const _unites = {
    'zero': 0,
    'un': 1,
    'une': 1,
    'deux': 2,
    'trois': 3,
    'quatre': 4,
    'cinq': 5,
    'six': 6,
    'sept': 7,
    'huit': 8,
    'neuf': 9,
    'dix': 10,
    'onze': 11,
    'douze': 12,
    'treize': 13,
    'quatorze': 14,
    'quinze': 15,
    'seize': 16,
    'vingt': 20,
    'vingts': 20,
    'trente': 30,
    'quarante': 40,
    'cinquante': 50,
    'soixante': 60,
  };

  /// Calcule l'expression contenue dans [phrase] (minuscules, sans
  /// accents). Renvoie null si la phrase ne contient pas de calcul.
  static ResultatCalcul? calculer(String phrase) {
    final jetons = _lexer(phrase);
    if (jetons == null) return null;
    final nombres = jetons.whereType<_Nombre>().length;
    final operations = jetons.whereType<_Operateur>().length;
    if (nombres == 0 || operations == 0) return null;
    try {
      final valeur = _evaluer(jetons);
      if (valeur == null) return null;
      return ResultatCalcul(_lisible(jetons), valeur);
    } on _DivisionParZero {
      return ResultatCalcul(_lisible(jetons), null);
    }
  }

  // ---- Découpage en jetons -------------------------------------------------

  static List<_Jeton>? _lexer(String phrase) {
    var texte = phrase
        .replaceAll('×', ' fois ')
        .replaceAll('÷', ' divise par ')
        .replaceAll('*', ' fois ')
        .replaceAll('+', ' plus ')
        .replaceAll('/', ' divise par ')
        .replaceAll('%', ' pour cent ')
        .replaceAll('^', ' puissance ')
        .replaceAll(RegExp(r'(?<=\d)\s*-\s*(?=\d)'), ' moins ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'(?<=\d)x(?=\d)'), ' fois ')
        .replaceAll(RegExp(r'(?<=\d),(?=\d)'), '.')
        .replaceAll(RegExp(r"[?!;:'’]"), ' ');
    final mots = texte
        .split(RegExp(r'\s+'))
        .where((m) => m.isNotEmpty)
        .toList();

    final jetons = <_Jeton>[];
    var i = 0;
    bool suite(List<String> attendus) {
      if (i + attendus.length > mots.length) return false;
      for (var k = 0; k < attendus.length; k++) {
        if (mots[i + k] != attendus[k]) return false;
      }
      return true;
    }

    while (i < mots.length) {
      final m = mots[i];

      // Nombre en chiffres.
      final valeur = double.tryParse(m);
      if (valeur != null) {
        jetons.add(_Nombre(valeur, m.replaceAll('.', ',')));
        i++;
        continue;
      }

      // Nombre en lettres.
      final (lettres, longueur) = _lireNombreEnLettres(mots, i);
      if (longueur > 0) {
        jetons.add(_Nombre(lettres.toDouble(), '$lettres'));
        i += longueur;
        continue;
      }

      // Opérateurs (du plus long au plus court).
      if (suite(['racine', 'carree', 'de']) || suite(['racine', 'de'])) {
        jetons.add(const _Operateur('racine', 'racine carrée de'));
        i += mots[i + 1] == 'carree' ? 3 : 2;
      } else if (suite(['au', 'carre'])) {
        jetons.add(const _Operateur('carre', 'au carré'));
        i += 2;
      } else if (suite(['au', 'cube'])) {
        jetons.add(const _Operateur('cube', 'au cube'));
        i += 2;
      } else if (suite(['pour', 'cent', 'de']) || suite(['pourcent', 'de'])) {
        jetons.add(const _Operateur('%', 'pour cent de'));
        i += mots[i] == 'pourcent' ? 2 : 3;
      } else if (suite(['multiplie', 'par'])) {
        jetons.add(const _Operateur('*', 'fois'));
        i += 2;
      } else if (suite(['divise', 'par'])) {
        jetons.add(const _Operateur('/', 'divisé par'));
        i += 2;
      } else if (suite(['a', 'la', 'puissance'])) {
        jetons.add(const _Operateur('^', 'puissance'));
        i += 3;
      } else if (m == 'plus' || m == 'et' && jetons.lastOrNull is _Nombre) {
        // « et » entre deux nombres (« 3 et 4 ») vaut une addition.
        jetons.add(const _Operateur('+', 'plus'));
        i++;
      } else if (m == 'moins') {
        jetons.add(const _Operateur('-', 'moins'));
        i++;
      } else if (m == 'fois' || m == 'x') {
        jetons.add(const _Operateur('*', 'fois'));
        i++;
      } else if (m == 'sur') {
        jetons.add(const _Operateur('/', 'divisé par'));
        i++;
      } else if (m == 'puissance' || m == 'exposant') {
        jetons.add(const _Operateur('^', 'puissance'));
        i++;
      } else {
        // Mots de liaison (« combien font », « calcule »…) ignorés.
        i++;
      }
    }
    // « fais un calcul, 3 plus 4 » : deux nombres de suite (« un », « 3 ») ;
    // seul le dernier fait partie du calcul.
    for (var k = jetons.length - 2; k >= 0; k--) {
      if (jetons[k] is _Nombre && jetons[k + 1] is _Nombre) jetons.removeAt(k);
    }
    // Un « et » final ou isolé n'est pas une opération.
    while (jetons.isNotEmpty &&
        jetons.last is _Operateur &&
        (jetons.last as _Operateur).code == '+' &&
        jetons.length < 3) {
      jetons.removeLast();
    }
    return jetons;
  }

  /// Lit un nombre écrit en lettres à partir de [debut]. Renvoie la valeur
  /// et le nombre de mots consommés (0 si ce n'est pas un nombre).
  static (int, int) _lireNombreEnLettres(List<String> mots, int debut) {
    var total = 0, courant = 0, i = debut;
    var lu = false;
    while (i < mots.length) {
      final m = mots[i];
      final u = _unites[m];
      if (u != null) {
        // « quatre vingt » = 80.
        if ((m == 'vingt' || m == 'vingts') && courant % 100 == 4) {
          courant += 76;
        } else {
          courant += u;
        }
        lu = true;
      } else if (m == 'cent' || m == 'cents') {
        courant = (courant == 0 ? 1 : courant) * 100;
        lu = true;
      } else if (m == 'mille') {
        total += (courant == 0 ? 1 : courant) * 1000;
        courant = 0;
        lu = true;
      } else if (m == 'million' || m == 'millions') {
        total += (courant == 0 ? 1 : courant) * 1000000;
        courant = 0;
        lu = true;
      } else if (m == 'et' &&
          lu &&
          i + 1 < mots.length &&
          (mots[i + 1] == 'un' || mots[i + 1] == 'onze')) {
        // « vingt et un », « soixante et onze ».
      } else {
        break;
      }
      i++;
    }
    return lu ? (total + courant, i - debut) : (0, 0);
  }

  // ---- Évaluation (priorités) ----------------------------------------------

  static double? _evaluer(List<_Jeton> jetons) {
    // 1. Opérations unaires : racine (préfixe), carré et cube (suffixes).
    final simples = <_Jeton>[];
    for (var i = 0; i < jetons.length; i++) {
      final j = jetons[i];
      if (j is _Operateur && j.code == 'racine') {
        if (i + 1 >= jetons.length || jetons[i + 1] is! _Nombre) return null;
        final n = jetons[i + 1] as _Nombre;
        if (n.valeur < 0) return null;
        simples.add(_Nombre(math.sqrt(n.valeur), ''));
        i++;
      } else if (j is _Operateur && (j.code == 'carre' || j.code == 'cube')) {
        if (simples.isEmpty || simples.last is! _Nombre) return null;
        final n = simples.removeLast() as _Nombre;
        final p = j.code == 'carre' ? 2 : 3;
        simples.add(_Nombre(math.pow(n.valeur, p).toDouble(), ''));
      } else {
        simples.add(j);
      }
    }

    // 2a. Phrases parlées : « fais un calcul, 3 plus 4 » donne deux nombres
    // de suite (« un », « 3 ») : on garde le dernier. Un « moins » en tête
    // ou après une opération rend le nombre suivant négatif.
    final propres = <_Jeton>[];
    var negatif = false;
    for (final j in simples) {
      if (j is _Operateur &&
          j.code == '-' &&
          (propres.isEmpty || propres.last is _Operateur)) {
        negatif = !negatif;
        continue;
      }
      if (j is _Nombre) {
        final n = negatif ? _Nombre(-j.valeur, '') : j;
        negatif = false;
        if (propres.isNotEmpty && propres.last is _Nombre) {
          propres.removeLast();
        }
        propres.add(n);
      } else {
        propres.add(j);
      }
    }
    simples
      ..clear()
      ..addAll(propres);

    // 2b. Alternance nombre / opérateur obligatoire.
    if (simples.isEmpty || simples.length.isEven) return null;
    final valeurs = <double>[];
    final ops = <String>[];
    for (var i = 0; i < simples.length; i++) {
      final j = simples[i];
      if (i.isEven) {
        if (j is! _Nombre) return null;
        valeurs.add(j.valeur);
      } else {
        if (j is! _Operateur) return null;
        ops.add(j.code);
      }
    }
    if (ops.isEmpty) return valeurs.first;

    // 3. Priorités : puissance, puis × ÷ %, puis + −.
    for (final niveau in [
      {'^'},
      {'*', '/', '%'},
      {'+', '-'},
    ]) {
      var k = 0;
      while (k < ops.length) {
        if (!niveau.contains(ops[k])) {
          k++;
          continue;
        }
        final a = valeurs[k], b = valeurs[k + 1];
        final r = switch (ops[k]) {
          '^' => math.pow(a, b).toDouble(),
          '*' => a * b,
          '/' => b == 0 ? throw _DivisionParZero() : a / b,
          '%' => a / 100 * b,
          '+' => a + b,
          _ => a - b,
        };
        valeurs[k] = r;
        valeurs.removeAt(k + 1);
        ops.removeAt(k);
      }
    }
    return valeurs.single;
  }

  static String _lisible(List<_Jeton> jetons) => jetons
      .map((j) => j is _Nombre ? j.texte : (j as _Operateur).texte)
      .join(' ');

  /// Nombre en français : virgule décimale, au plus 4 décimales, sans zéros
  /// inutiles ; grands nombres groupés par milliers (espaces).
  static String formater(double valeur) {
    if (valeur.isNaN || valeur.isInfinite) return 'un nombre trop grand';
    final arrondi = double.parse(valeur.toStringAsFixed(4));
    final negatif = arrondi < 0;
    final absolu = arrondi.abs();
    final entier = absolu.truncate();
    var decimales = (absolu - entier).toStringAsFixed(4).substring(2);
    decimales = decimales.replaceAll(RegExp(r'0+$'), '');

    final chiffres = entier.toString();
    final groupes = StringBuffer();
    for (var k = 0; k < chiffres.length; k++) {
      if (k > 0 && (chiffres.length - k) % 3 == 0) groupes.write(' ');
      groupes.write(chiffres[k]);
    }
    final texte = decimales.isEmpty ? '$groupes' : '$groupes,$decimales';
    return negatif ? 'moins $texte' : texte;
  }
}

/// Résultat d'un calcul : l'expression comprise et sa valeur (null en cas de
/// division par zéro).
class ResultatCalcul {
  const ResultatCalcul(this.expression, this.valeur);

  final String expression;
  final double? valeur;

  String get phrase => valeur == null
      ? 'Je ne peux pas diviser par zéro.'
      : '$expression égale ${CalculVocal.formater(valeur!)}.';
}

sealed class _Jeton {
  const _Jeton();
}

class _Nombre extends _Jeton {
  const _Nombre(this.valeur, this.texte);
  final double valeur;
  final String texte;
}

class _Operateur extends _Jeton {
  const _Operateur(this.code, this.texte);
  final String code;
  final String texte;
}

class _DivisionParZero implements Exception {}
