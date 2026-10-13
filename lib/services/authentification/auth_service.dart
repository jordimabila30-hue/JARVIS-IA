import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/authentification/profil_compte.dart';
import '../../models/authentification/resultat_auth.dart';
import '../../models/authentification/utilisateur_auth.dart';
import 'auth_repository.dart';
import 'validation_auth.dart';

/// Logique d'authentification utilisée par les pages : une opération à la
/// fois (pas de double envoi), état de chargement, utilisateur courant et
/// son profil.
///
/// Ne connaît ni le serveur ni le stockage : tout passe par
/// [AuthRepository], remplaçable. Ne garde aucun mot de passe : il est
/// transmis au dépôt puis oublié.
class AuthService extends ChangeNotifier {
  AuthService(this._depot) {
    _abonnement = _depot.changements.listen(_surChangement);
  }

  final AuthRepository _depot;
  StreamSubscription<UtilisateurAuth?>? _abonnement;

  /// Utilisateur authentifié par le serveur (null : aucune session). Seule
  /// une réponse réussie du dépôt peut le renseigner.
  UtilisateurAuth? get utilisateur => _utilisateur;
  UtilisateurAuth? _utilisateur;

  bool get connecte => _utilisateur != null;

  /// Profil du compte (`public.users`), une fois lu.
  ProfilCompte? get profil => _profil;
  ProfilCompte? _profil;

  /// Vrai pendant une opération (bouton en chargement).
  bool get enCours => _enCours;
  bool _enCours = false;

  /// JARVIS a été ouvert par un lien « mot de passe oublié » : il faut
  /// choisir un nouveau mot de passe.
  bool get recuperationEnCours => _depot.recuperationEnCours;

  /// La session a été perdue sans déconnexion volontaire (expirée,
  /// révoquée, renouvellement refusé) : la connexion l'explique.
  bool get sessionPerdue => _sessionPerdue;
  bool _sessionPerdue = false;
  bool _deconnexionVolontaire = false;

  /// Écart estimé entre l'heure du serveur et celle de l'appareil
  /// (positif : l'appareil retarde) ; null tant qu'il n'est pas mesuré.
  Duration? get decalageHorloge => _depot.decalageHorloge;

  /// Session perdue ou changée ailleurs (déconnexion depuis un autre
  /// onglet, session révoquée, profil mis à jour).
  void _surChangement(UtilisateurAuth? u) {
    if (u?.identifiant == _utilisateur?.identifiant &&
        u?.nom == _utilisateur?.nom) {
      return;
    }
    if (u == null) {
      _profil = null;
      if (_utilisateur != null && !_deconnexionVolontaire) {
        _sessionPerdue = true;
      }
    }
    _utilisateur = u;
    notifyListeners();
  }

  Future<ResultatAuth<UtilisateurAuth>> connecter({
    required String email,
    required String motDePasse,
  }) => _executer(() async {
    final r = await _depot.connecter(
      email: ValidationAuth.nettoyerEmail(email),
      motDePasse: motDePasse,
    );
    if (r is SuccesAuth<UtilisateurAuth>) _definir(r.valeur);
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
    if (r is SuccesAuth<UtilisateurAuth>) _definir(r.valeur);
    return r;
  });

  Future<ResultatAuth<void>> demanderRecuperation(String email) => _executer(
    () => _depot.demanderRecuperation(ValidationAuth.nettoyerEmail(email)),
  );

  Future<ResultatAuth<void>> changerMotDePasse(String motDePasse) =>
      _executer(() => _depot.changerMotDePasse(motDePasse));

  Future<ResultatAuth<void>> deconnecter() => _executer(() async {
    _deconnexionVolontaire = true;
    try {
      final r = await _depot.deconnecter();
      // Quoi que réponde le serveur, l'appareil n'est plus connecté.
      _utilisateur = null;
      _profil = null;
      return r;
    } finally {
      _deconnexionVolontaire = false;
    }
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

  /// Lit le profil du compte connecté (sans bloquer les autres opérations).
  Future<ResultatAuth<ProfilCompte>> chargerProfil() async {
    final r = await _depot.lireProfil();
    if (r is SuccesAuth<ProfilCompte>) {
      _profil = r.valeur;
      notifyListeners();
    }
    return r;
  }

  /// Change le nom affiché (seule information du profil modifiable).
  Future<ResultatAuth<ProfilCompte>> modifierNom(String nom) =>
      _executer(() async {
        final r = await _depot.modifierProfil(
          nom: ValidationAuth.nettoyerNom(nom),
        );
        if (r is SuccesAuth<ProfilCompte>) _profil = r.valeur;
        return r;
      });

  /// Jeton d'accès valide pour le backend JARVIS (null sans session).
  Future<String?> jetonAcces() => _depot.jetonAcces();

  /// Renouvelle le jeton (le serveur l'a jugé expiré) ; null : il faut se
  /// reconnecter.
  Future<String?> renouvelerJeton() => _depot.renouvelerJeton();

  void _definir(UtilisateurAuth u) {
    if (u.identifiant != _utilisateur?.identifiant) _profil = null;
    _utilisateur = u;
    _sessionPerdue = false;
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

  @override
  void dispose() {
    _abonnement?.cancel();
    super.dispose();
  }
}
