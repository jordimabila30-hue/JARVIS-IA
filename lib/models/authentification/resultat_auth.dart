/// Résultat d'une opération d'authentification : succès (avec sa valeur)
/// ou échec (avec une erreur compréhensible).
sealed class ResultatAuth<T> {
  const ResultatAuth();
}

final class SuccesAuth<T> extends ResultatAuth<T> {
  const SuccesAuth(this.valeur);

  final T valeur;
}

final class EchecAuth<T> extends ResultatAuth<T> {
  const EchecAuth(this.erreur);

  final ErreurAuth erreur;
}

/// Familles d'erreurs vues par l'interface. Les codes d'erreur du serveur
/// seront traduits vers ces familles par l'implémentation réelle de
/// `AuthRepository` : l'interface n'a jamais à les connaître.
enum TypeErreurAuth {
  /// Aucun serveur d'authentification n'est encore configuré.
  serveurNonConfigure,

  /// Adresse e-mail ou mot de passe refusés.
  identifiantsInvalides,

  /// Adresse e-mail déjà associée à un compte.
  emailDejaUtilise,

  /// Données refusées par les règles du serveur.
  donneesRefusees,

  /// Session expirée ou révoquée : nouvelle connexion nécessaire.
  sessionExpiree,

  /// Serveur injoignable (réseau, délai dépassé).
  reseau,

  /// Une opération est déjà en cours (double envoi).
  operationEnCours,

  inconnue,
}

class ErreurAuth {
  const ErreurAuth(this.type, [this.detail]);

  final TypeErreurAuth type;

  /// Précision éventuelle du serveur, déjà rédigée pour l'utilisateur.
  final String? detail;

  /// Message affiché sous le formulaire.
  String get message =>
      detail ??
      switch (type) {
        TypeErreurAuth.serveurNonConfigure =>
          'Cette fonctionnalité sera disponible après l’intégration du '
              'serveur JARVIS.',
        TypeErreurAuth.identifiantsInvalides =>
          'Adresse e-mail ou mot de passe incorrect.',
        TypeErreurAuth.emailDejaUtilise =>
          'Un compte existe déjà avec cette adresse e-mail.',
        TypeErreurAuth.donneesRefusees =>
          'Certaines informations ont été refusées. Vérifiez le formulaire.',
        TypeErreurAuth.sessionExpiree =>
          'Votre session a expiré. Reconnectez-vous.',
        TypeErreurAuth.reseau =>
          'Impossible de joindre le serveur. Vérifiez votre connexion.',
        TypeErreurAuth.operationEnCours => 'Une opération est déjà en cours.',
        TypeErreurAuth.inconnue => 'Une erreur est survenue. Réessayez.',
      };
}
