import 'package:flutter/foundation.dart';

import '../../models/authentification/resultat_auth.dart';
import '../../models/authentification/utilisateur_auth.dart';
import 'auth_repository.dart';
import 'validation_auth.dart';

/// Logique d'authentification utilisée par les pages : une opération à la
/// fois (pas de double envoi), état de chargement, utilisateur courant.
///
/// Ne connaît ni le serveur ni le stockage : tout passe par
/// [AuthRepository], remplaçable. Ne garde aucun mot de passe : il est
/// transmis au dépôt puis oublié.
class AuthService extends ChangeNotifier {
  AuthService(this._depot);

  final AuthRepository _depot;

  /// Utilisateur authentifié par le serveur (null : aucune session). Seule
  /// une réponse réussie du dépôt peut le renseigner.
  UtilisateurAuth? get utilisateur => _utilisateur;
  UtilisateurAuth? _utilisateur;

  bool get connecte => _utilisateur != null;

  /// Vrai pendant une opération (bouton en chargement).
  bool get enCours => _enCours;
  bool _enCours = false;

  Future<ResultatAuth<UtilisateurAuth>> connecter({
    required String email,
    required String motDePasse,
  }) => _executer(() async {
    final r = await _depot.connecter(
      email: ValidationAuth.nettoyerEmail(email),
      motDePasse: motDePasse,
    );
    if (r is SuccesAuth<UtilisateurAuth>) _utilisateur = r.valeur;
    return r;
  });

  Future<ResultatAuth<UtilisateurAuth>> inscrire({
    required String nom,
    required String email,
    required String motDePasse,
  }) => _executer(() async {
    final r = await _depot.inscrire(
      DemandeInscription(
        nom: ValidationAuth.nettoyerNom(nom),
        email: ValidationAuth.nettoyerEmail(email),
        motDePasse: motDePasse,
      ),
    );
    if (r is SuccesAuth<UtilisateurAuth>) _utilisateur = r.valeur;
    return r;
  });

  Future<ResultatAuth<void>> demanderRecuperation(String email) => _executer(
    () => _depot.demanderRecuperation(ValidationAuth.nettoyerEmail(email)),
  );

  Future<ResultatAuth<void>> deconnecter() => _executer(() async {
    final r = await _depot.deconnecter();
    // Quoi que réponde le serveur, l'appareil n'est plus connecté.
    _utilisateur = null;
    return r;
  });

  /// Au lancement : restaure la session gardée sur l'appareil, si le
  /// serveur l'accepte. Renvoie l'utilisateur, ou null s'il faut se
  /// connecter (aucune session, serveur absent, erreur).
  Future<UtilisateurAuth?> restaurerSession() async {
    try {
      final r = await _depot.restaurerSession();
      _utilisateur = r is SuccesAuth<UtilisateurAuth?> ? r.valeur : null;
    } catch (_) {
      _utilisateur = null;
    }
    notifyListeners();
    return _utilisateur;
  }

  Future<ResultatAuth<T>> _executer<T>(
    Future<ResultatAuth<T>> Function() operation,
  ) async {
    if (_enCours) {
      return const EchecAuth(ErreurAuth(TypeErreurAuth.operationEnCours));
    }
    _enCours = true;
    notifyListeners();
    try {
      return await operation();
    } catch (_) {
      return const EchecAuth(ErreurAuth(TypeErreurAuth.inconnue));
    } finally {
      _enCours = false;
      notifyListeners();
    }
  }
}
