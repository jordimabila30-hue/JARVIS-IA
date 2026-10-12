/// Utilisateur authentifié, tel que le serveur le décrira.
///
/// Champs provisoires : les noms et le contenu exacts seront fixés avec le
/// développeur backend (voir docs/integration_backend_auth.md). Aucun
/// mot de passe ni jeton ici.
class UtilisateurAuth {
  const UtilisateurAuth({
    required this.identifiant,
    required this.email,
    this.nom,
  });

  /// Identifiant attribué par le serveur (format à confirmer).
  final String identifiant;
  final String email;

  /// Nom ou pseudonyme choisi à l'inscription.
  final String? nom;
}
