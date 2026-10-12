import '../../models/authentification/resultat_auth.dart';
import '../../models/authentification/utilisateur_auth.dart';

/// Données d'une inscription (déjà nettoyées par la validation locale).
class DemandeInscription {
  const DemandeInscription({
    required this.nom,
    required this.email,
    required this.motDePasse,
  });

  final String nom;
  final String email;
  final String motDePasse;
}

/// Contrat d'accès au serveur d'authentification.
///
/// C'est la seule couche qui parlera au backend : requêtes, adresses,
/// format des réponses, jetons et leur stockage (`StockageSession`). Les
/// pages ne la voient jamais : elles passent par `AuthService`.
///
/// Les signatures pourront évoluer selon le backend (voir
/// docs/integration_backend_auth.md).
abstract interface class AuthRepository {
  Future<ResultatAuth<UtilisateurAuth>> connecter({
    required String email,
    required String motDePasse,
  });

  Future<ResultatAuth<UtilisateurAuth>> inscrire(DemandeInscription demande);

  /// Révoque la session côté serveur et efface ce qui est gardé localement.
  Future<ResultatAuth<void>> deconnecter();

  /// Demande la procédure de récupération du compte pour [email].
  Future<ResultatAuth<void>> demanderRecuperation(String email);

  /// Vérifie auprès du serveur la session en cours (null : aucune).
  Future<ResultatAuth<UtilisateurAuth?>> verifierSession();

  /// Au démarrage : relit la session gardée sur l'appareil (stockage
  /// sécurisé, cookie Web) puis la vérifie ou la renouvelle auprès du
  /// serveur. Null : il faut se connecter.
  Future<ResultatAuth<UtilisateurAuth?>> restaurerSession();
}

/// Aucun serveur configuré (situation actuelle) : chaque opération qui en
/// a besoin échoue clairement ([TypeErreurAuth.serveurNonConfigure]) et il
/// n'existe jamais de session. Rien n'est simulé, rien n'est stocké.
class AuthRepositoryNonConfigure implements AuthRepository {
  const AuthRepositoryNonConfigure();

  static const _nonConfigure = ErreurAuth(TypeErreurAuth.serveurNonConfigure);

  @override
  Future<ResultatAuth<UtilisateurAuth>> connecter({
    required String email,
    required String motDePasse,
  }) async => const EchecAuth(_nonConfigure);

  @override
  Future<ResultatAuth<UtilisateurAuth>> inscrire(
    DemandeInscription demande,
  ) async => const EchecAuth(_nonConfigure);

  /// Aucune session à révoquer.
  @override
  Future<ResultatAuth<void>> deconnecter() async => const SuccesAuth(null);

  @override
  Future<ResultatAuth<void>> demanderRecuperation(String email) async =>
      const EchecAuth(_nonConfigure);

  @override
  Future<ResultatAuth<UtilisateurAuth?>> verifierSession() async =>
      const SuccesAuth(null);

  @override
  Future<ResultatAuth<UtilisateurAuth?>> restaurerSession() async =>
      const SuccesAuth(null);
}
