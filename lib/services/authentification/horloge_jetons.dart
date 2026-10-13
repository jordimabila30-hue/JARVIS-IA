import 'dart:convert';

/// Durée de vie des jetons, mesurée sans dépendre de l'heure de l'appareil.
///
/// L'horloge d'un téléphone ou d'un ordinateur peut être fausse (avancée,
/// retardée, sans mise à l'heure automatique) ; le fuseau horaire, lui, ne
/// compte pas (tout est en temps universel). Le serveur, lui, vérifie les
/// jetons avec SA propre horloge. Pour savoir quand renouveler un jeton,
/// JARVIS ne compare donc pas son expiration à l'heure de l'appareil :
///
/// - la durée de vie vient du jeton lui-même (`exp - iat`, deux dates du
///   serveur : leur différence ne dépend d'aucune horloge locale) ;
/// - le temps écoulé depuis sa réception est mesuré par un chronomètre
///   monotone (insensible aux changements d'heure de l'appareil).
///
/// L'écart entre l'appareil et le serveur (`iat` comparé à l'heure locale
/// de réception) sert seulement à prévenir l'utilisateur. Rien ici ne
/// remplace la vérification cryptographique, faite par le serveur.
class HorlogeJetons {
  HorlogeJetons({DateTime Function()? maintenant, Stopwatch Function()? chrono})
    : _maintenant = maintenant ?? DateTime.now,
      _nouveauChrono = chrono ?? Stopwatch.new;

  final DateTime Function() _maintenant;
  final Stopwatch Function() _nouveauChrono;

  String? _jeton;
  Duration? _duree;
  Stopwatch? _chrono;
  Duration? _decalage;

  /// Au-delà de cet écart, l'heure de l'appareil est signalée comme fausse.
  static const seuilDecalage = Duration(minutes: 2);

  /// Écart estimé : heure du serveur moins heure de l'appareil (positif :
  /// l'appareil retarde). Null tant qu'aucun jeton neuf n'a été reçu.
  Duration? get decalage => _decalage;

  bool get decalageImportant =>
      (_decalage?.abs() ?? Duration.zero) > seuilDecalage;

  /// Un jeton vient d'être délivré par le serveur (connexion,
  /// renouvellement) : début de la mesure de sa durée de vie.
  void observer(String jeton) {
    if (jeton == _jeton) return;
    final revendications = _lire(jeton);
    final iat = revendications?['iat'];
    final exp = revendications?['exp'];
    if (iat is! num || exp is! num || exp <= iat) {
      oublier();
      return;
    }
    _jeton = jeton;
    _duree = Duration(seconds: (exp - iat).toInt());
    _chrono = _nouveauChrono()..start();
    final local = _maintenant().toUtc().millisecondsSinceEpoch / 1000;
    _decalage = Duration(milliseconds: ((iat - local) * 1000).round());
  }

  /// Temps de validité restant de [jeton], mesuré depuis sa réception ;
  /// null s'il n'a pas été reçu pendant cette session de l'application
  /// (session restaurée : durée inconnue, il faut le renouveler).
  Duration? resteValide(String jeton) {
    final duree = _duree, chrono = _chrono;
    if (jeton != _jeton || duree == null || chrono == null) return null;
    return duree - chrono.elapsed;
  }

  void oublier() {
    _jeton = null;
    _duree = null;
    _chrono = null;
  }

  static Map<String, dynamic>? _lire(String jeton) {
    try {
      final partie = base64Url.normalize(jeton.split('.')[1]);
      return jsonDecode(utf8.decode(base64Url.decode(partie)))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
