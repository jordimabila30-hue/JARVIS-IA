/// Où la future implémentation de `AuthRepository` gardera la preuve de
/// session délivrée par le serveur (jeton, identifiant de session… format
/// à définir avec le backend).
///
/// Stratégie prévue selon la plateforme ([StrategieSession]) :
/// - Android, iOS, Windows, desktop : session durable, gardée dans le
///   stockage sécurisé du système (Keychain, Keystore, Credential
///   Manager), restaurée à l'ouverture tant que le serveur l'accepte ;
/// - Web : session du navigateur, de préférence un cookie `HttpOnly`,
///   `Secure`, `SameSite` posé par le serveur (rien à stocker côté
///   Flutter) ; une actualisation de la page la conserve.
///
/// Jamais de mot de passe ici, et une simple préférence locale n'est
/// jamais une preuve d'authentification : seule la réponse du serveur
/// l'est. Aucune implémentation n'existe encore : elle sera écrite avec le
/// backend (paquet de stockage sécurisé choisi à ce moment-là).
abstract interface class StockageSession {
  Future<String?> lire();
  Future<void> ecrire(String preuve);
  Future<void> effacer();
}

/// Durée de vie voulue de la session selon la plateforme.
enum StrategieSession {
  /// Restaurée à chaque ouverture tant que le serveur l'accepte (mobile,
  /// desktop).
  durable,

  /// Limitée à la session du navigateur, conservée à l'actualisation (Web).
  navigateur,
}
