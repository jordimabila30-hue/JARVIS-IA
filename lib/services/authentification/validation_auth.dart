/// Règles de validation locales, minimales et réglables. Elles évitent les
/// envois inutiles ; la décision finale reste au serveur. À aligner sur
/// ses exigences dès qu'elles seront connues.
class ReglesValidationAuth {
  const ReglesValidationAuth({this.longueurMinMotDePasse = 8});

  /// Longueur minimale d'un nouveau mot de passe (inscription). Valeur
  /// provisoire : à remplacer par celle du backend.
  final int longueurMinMotDePasse;
}

/// Validations des formulaires d'authentification. Chaque méthode renvoie
/// le message à afficher sous le champ, ou null si la valeur convient.
///
/// Espaces : l'adresse e-mail et le nom sont nettoyés (espaces accidentels
/// au début, à la fin, et doublés dans le nom) ; un mot de passe n'est
/// jamais modifié (un espace peut y être voulu).
class ValidationAuth {
  const ValidationAuth([this.regles = const ReglesValidationAuth()]);

  final ReglesValidationAuth regles;

  // Forme générale seulement : un « @ », un domaine avec un point, aucun
  // espace. Le serveur reste juge de l'existence de l'adresse.
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String nettoyerEmail(String valeur) => valeur.trim();

  static String nettoyerNom(String valeur) =>
      valeur.trim().replaceAll(RegExp(r'\s+'), ' ');

  String? email(String? valeur) {
    final v = nettoyerEmail(valeur ?? '');
    if (v.isEmpty) return 'Saisissez votre adresse e-mail.';
    if (!_email.hasMatch(v)) return 'Adresse e-mail invalide.';
    return null;
  }

  /// Connexion : seulement non vide (les règles d'un nouveau mot de passe
  /// ne s'appliquent pas à un compte existant).
  String? motDePasse(String? valeur) {
    if ((valeur ?? '').isEmpty) return 'Saisissez votre mot de passe.';
    return null;
  }

  /// Inscription : non vide, longueur minimale réglable.
  String? nouveauMotDePasse(String? valeur) {
    final v = valeur ?? '';
    if (v.isEmpty) return 'Choisissez un mot de passe.';
    if (v.trim().isEmpty) return 'Le mot de passe ne peut pas être vide.';
    final min = regles.longueurMinMotDePasse;
    if (v.length < min) return 'Au moins $min caractères.';
    return null;
  }

  String? confirmation(String? valeur, String motDePasse) {
    if ((valeur ?? '').isEmpty) return 'Confirmez votre mot de passe.';
    if (valeur != motDePasse) return 'Les mots de passe ne correspondent pas.';
    return null;
  }

  String? nom(String? valeur) {
    if (nettoyerNom(valeur ?? '').isEmpty) {
      return 'Saisissez un nom ou un pseudonyme.';
    }
    return null;
  }
}
