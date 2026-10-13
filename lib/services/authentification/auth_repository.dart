import '../../models/authentification/profil_compte.dart';
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
/// C'est la seule couche qui parle au backend : requêtes, adresses,
/// format des réponses, jetons et leur stockage. Les pages ne la voient
/// jamais : elles passent par `AuthService`.
///
/// Implémentations : [AuthRepositoryNonConfigure] (aucun serveur) et
/// `AuthRepositorySupabase` (Supabase Auth + table `public.users`).
abstract interface class AuthRepository {
  Future<ResultatAuth<UtilisateurAuth>> connecter({
    required String email,
    required String motDePasse,
  });

  /// Crée le compte. Si la confirmation de l'e-mail est exigée, renvoie
  /// [TypeErreurAuth.confirmationEnvoyee] : le compte existe, mais aucune
  /// session n'est ouverte.
  Future<ResultatAuth<UtilisateurAuth>> inscrire(DemandeInscription demande);

  /// Révoque la session côté serveur et efface ce qui est gardé localement.
  Future<ResultatAuth<void>> deconnecter();

  /// Demande la procédure de récupération du compte pour [email].
  Future<ResultatAuth<void>> demanderRecuperation(String email);

  /// Nouveau mot de passe, une fois le lien de récupération ouvert.
  Future<ResultatAuth<void>> changerMotDePasse(String motDePasse);

  /// Vrai si JARVIS a été ouvert par un lien de récupération du mot de
  /// passe (l'utilisateur doit en choisir un nouveau).
  bool get recuperationEnCours;

  /// Vérifie auprès du serveur la session en cours (null : aucune).
  Future<ResultatAuth<UtilisateurAuth?>> verifierSession();

  /// Au démarrage : relit la session gardée sur l'appareil puis la vérifie
  /// ou la renouvelle auprès du serveur. Null : il faut se connecter.
  Future<ResultatAuth<UtilisateurAuth?>> restaurerSession();

  /// Profil du compte connecté (`public.users`).
  Future<ResultatAuth<ProfilCompte>> lireProfil();

  /// Modifie les informations autorisées du profil (aujourd'hui : le nom
  /// affiché).
  Future<ResultatAuth<ProfilCompte>> modifierProfil({required String nom});

  /// Jeton d'accès valide pour le backend JARVIS (renouvelé s'il expire
  /// bientôt) ; null sans session.
  Future<String?> jetonAcces();

  /// Renouvelle le jeton maintenant (le serveur l'a jugé expiré). Null si
  /// la session ne peut plus être renouvelée : il faut se reconnecter.
  Future<String?> renouvelerJeton();

  /// Écart estimé entre l'heure du serveur et celle de l'appareil
  /// (positif : l'appareil retarde) ; null tant qu'il n'est pas mesuré.
  Duration? get decalageHorloge;

  /// Changements de session venus du serveur ou d'un autre onglet :
  /// déconnexion, session révoquée, utilisateur mis à jour (null : plus de
  /// session).
  Stream<UtilisateurAuth?> get changements;
}

/// Aucun serveur configuré : chaque opération qui en a besoin échoue
/// clairement ([TypeErreurAuth.serveurNonConfigure]) et il n'existe jamais
/// de session. Rien n'est simulé, rien n'est stocké.
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
  Future<ResultatAuth<void>> changerMotDePasse(String motDePasse) async =>
      const EchecAuth(_nonConfigure);

  @override
  bool get recuperationEnCours => false;

  @override
  Future<ResultatAuth<UtilisateurAuth?>> verifierSession() async =>
      const SuccesAuth(null);

  @override
  Future<ResultatAuth<UtilisateurAuth?>> restaurerSession() async =>
      const SuccesAuth(null);

  @override
  Future<ResultatAuth<ProfilCompte>> lireProfil() async =>
      const EchecAuth(_nonConfigure);

  @override
  Future<ResultatAuth<ProfilCompte>> modifierProfil({
    required String nom,
  }) async => const EchecAuth(_nonConfigure);

  @override
  Future<String?> jetonAcces() async => null;

  @override
  Future<String?> renouvelerJeton() async => null;

  @override
  Duration? get decalageHorloge => null;

  @override
  Stream<UtilisateurAuth?> get changements => const Stream.empty();
}
