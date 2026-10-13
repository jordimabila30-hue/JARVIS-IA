import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/authentification/profil_compte.dart';
import '../../models/authentification/resultat_auth.dart';
import '../../models/authentification/utilisateur_auth.dart';
import 'auth_repository.dart';
import 'horloge_jetons.dart';

/// Authentification réelle par Supabase Auth (e-mail + mot de passe), et
/// profil dans la table `public.users` (protégée par la RLS : chacun ne
/// lit et ne modifie que sa propre ligne).
///
/// La session (jetons) est gardée et renouvelée par `supabase_flutter` ;
/// cette classe ne stocke rien elle-même et ne voit jamais que la clé
/// publique du projet. Les erreurs Supabase sont traduites en
/// [TypeErreurAuth] : les pages n'en connaissent jamais le détail.
class AuthRepositorySupabase implements AuthRepository {
  AuthRepositorySupabase(
    this._client, {
    this.redirection,
    HorlogeJetons? horloge,
  }) : _horloge = horloge ?? HorlogeJetons() {
    // Les événements déjà émis (session initiale, lien de récupération
    // ouvert au démarrage) sont rejoués à l'abonnement.
    _abonnement = _auth.onAuthStateChange.listen(
      _surEvenement,
      onError: (Object _) {},
    );
  }

  final SupabaseClient _client;

  /// Adresse où renvoient les liens envoyés par e-mail (récupération) ;
  /// null : l'adresse du site configurée dans Supabase.
  final String? redirection;

  /// Durée de vie des jetons, indépendante de l'heure de l'appareil.
  final HorlogeJetons _horloge;

  late final StreamSubscription<AuthState> _abonnement;
  final _changements = StreamController<UtilisateurAuth?>.broadcast();
  bool _recuperation = false;
  Future<String>? _renouvellement;

  GoTrueClient get _auth => _client.auth;

  /// Colonnes lues dans `public.users` (jamais `*` : seulement l'utile).
  static const _colonnesProfil =
      'id, email, display_name, avatar_url, plan, daily_message_limit, '
      'daily_token_limit, created_at';

  /// Marge avant expiration en deçà de laquelle le jeton est renouvelé.
  static const _margeJeton = Duration(seconds: 60);

  void _surEvenement(AuthState etat) {
    // Seuls les jetons qui viennent d'être délivrés ont une durée de vie
    // connue (la session restaurée au démarrage n'en a pas).
    if (etat.event
        case AuthChangeEvent.signedIn ||
            AuthChangeEvent.tokenRefreshed ||
            AuthChangeEvent.passwordRecovery) {
      if (etat.session?.accessToken case final j?) _horloge.observer(j);
    }
    switch (etat.event) {
      case AuthChangeEvent.passwordRecovery:
        _recuperation = true;
        _changements.add(_utilisateurDe(etat.session?.user));
      case AuthChangeEvent.signedOut:
        _recuperation = false;
        _horloge.oublier();
        _changements.add(null);
      case AuthChangeEvent.signedIn ||
          AuthChangeEvent.tokenRefreshed ||
          AuthChangeEvent.userUpdated:
        _changements.add(_utilisateurDe(etat.session?.user));
      default:
        break;
    }
  }

  @override
  Stream<UtilisateurAuth?> get changements => _changements.stream;

  @override
  bool get recuperationEnCours => _recuperation;

  // --- Opérations ------------------------------------------------------------

  @override
  Future<ResultatAuth<UtilisateurAuth>> connecter({
    required String email,
    required String motDePasse,
  }) => _protege(() async {
    final r = await _auth.signInWithPassword(
      email: email,
      password: motDePasse,
    );
    final u = r.user;
    final session = r.session;
    if (u == null || session == null) {
      return const EchecAuth(ErreurAuth(TypeErreurAuth.inconnue));
    }
    _horloge.observer(session.accessToken);
    return SuccesAuth(_utilisateurDe(u)!);
  });

  @override
  Future<ResultatAuth<UtilisateurAuth>> inscrire(DemandeInscription demande) =>
      _protege(() async {
        final r = await _auth.signUp(
          email: demande.email,
          password: demande.motDePasse,
          // Repris par le déclencheur SQL `handle_new_user` dans
          // `public.users.display_name`.
          data: {'display_name': demande.nom},
        );
        final u = r.user;
        if (r.session case final s? when u != null) {
          _horloge.observer(s.accessToken);
          return SuccesAuth(_utilisateurDe(u)!);
        }
        // Confirmation exigée et adresse déjà inscrite : Supabase répond
        // sans erreur (pour ne pas révéler les comptes existants), mais
        // sans aucune identité.
        if (u != null && (u.identities?.isEmpty ?? false)) {
          return const EchecAuth(ErreurAuth(TypeErreurAuth.emailDejaUtilise));
        }
        return const EchecAuth(ErreurAuth(TypeErreurAuth.confirmationEnvoyee));
      });

  @override
  Future<ResultatAuth<void>> deconnecter() async {
    _recuperation = false;
    try {
      await _auth.signOut();
      return const SuccesAuth(null);
    } catch (e) {
      // La session locale est effacée même si le serveur est injoignable.
      return EchecAuth(erreurDe(e));
    }
  }

  @override
  Future<ResultatAuth<void>> demanderRecuperation(String email) =>
      _protege(() async {
        await _auth.resetPasswordForEmail(email, redirectTo: redirection);
        return const SuccesAuth(null);
      });

  @override
  Future<ResultatAuth<void>> changerMotDePasse(String motDePasse) =>
      _protege(() async {
        await _auth.updateUser(UserAttributes(password: motDePasse));
        _recuperation = false;
        return const SuccesAuth(null);
      });

  @override
  Future<ResultatAuth<UtilisateurAuth?>> verifierSession() =>
      _protege(() async {
        if (_auth.currentSession == null) return const SuccesAuth(null);
        final r = await _auth.getUser();
        return SuccesAuth(_utilisateurDe(r.user));
      });

  @override
  Future<ResultatAuth<UtilisateurAuth?>> restaurerSession() async {
    final session = _auth.currentSession;
    if (session == null) return const SuccesAuth(null);
    // Seule la réponse du serveur prouve que la session est valide. On ne
    // se fie pas à l'heure de l'appareil pour juger le jeton expiré : on
    // demande au serveur, et s'il refuse le jeton, on tente un
    // renouvellement avant de conclure.
    try {
      final r = await _auth.getUser();
      return SuccesAuth(_utilisateurDe(r.user));
    } catch (e) {
      final erreur = erreurDe(e);
      if (erreur.type == TypeErreurAuth.reseau) {
        // Hors ligne : la session gardée reste utilisable ; elle sera
        // renouvelée dès que le serveur répondra.
        return SuccesAuth(_utilisateurDe(session.user));
      }
    }
    // Jeton refusé (souvent simplement expiré) : renouvellement. En cas
    // d'échec définitif, renouvelerJeton efface la session de l'appareil.
    if (await renouvelerJeton() == null) {
      if (_auth.currentSession != null) {
        // Échec réseau pendant le renouvellement : session gardée.
        return SuccesAuth(_utilisateurDe(session.user));
      }
      return const EchecAuth(ErreurAuth(TypeErreurAuth.sessionExpiree));
    }
    try {
      final r = await _auth.getUser();
      return SuccesAuth(_utilisateurDe(r.user));
    } catch (e) {
      return EchecAuth(erreurDe(e));
    }
  }

  @override
  Future<ResultatAuth<ProfilCompte>> lireProfil() => _protege(() async {
    final id = _auth.currentUser?.id;
    if (id == null) {
      return const EchecAuth(ErreurAuth(TypeErreurAuth.sessionExpiree));
    }
    final ligne = await _client
        .from('users')
        .select(_colonnesProfil)
        .eq('id', id)
        .maybeSingle();
    if (ligne == null) return const EchecAuth(_profilIntrouvable);
    return SuccesAuth(ProfilCompte.depuisLigne(ligne));
  });

  @override
  Future<ResultatAuth<ProfilCompte>> modifierProfil({required String nom}) =>
      _protege(() async {
        final id = _auth.currentUser?.id;
        if (id == null) {
          return const EchecAuth(ErreurAuth(TypeErreurAuth.sessionExpiree));
        }
        // Seules display_name, avatar_url et preferences sont modifiables
        // par le client (droits SQL et RLS du projet).
        final ligne = await _client
            .from('users')
            .update({'display_name': nom})
            .eq('id', id)
            .select(_colonnesProfil)
            .maybeSingle();
        if (ligne == null) return const EchecAuth(_profilIntrouvable);
        return SuccesAuth(ProfilCompte.depuisLigne(ligne));
      });

  @override
  Duration? get decalageHorloge => _horloge.decalage;

  /// Jeton valide : renouvelé s'il lui reste moins d'une minute, d'après
  /// sa durée de vie mesurée depuis sa réception (jamais d'après l'heure
  /// de l'appareil). Session restaurée au démarrage : durée inconnue, il
  /// est renouvelé une fois.
  @override
  Future<String?> jetonAcces() async {
    final session = _auth.currentSession;
    if (session == null) return null;
    final reste = _horloge.resteValide(session.accessToken);
    if (reste != null && reste > _margeJeton) return session.accessToken;
    return renouvelerJeton();
  }

  @override
  Future<String?> renouvelerJeton() async {
    if (_auth.currentSession == null) return null;
    try {
      // Plusieurs appels simultanés partagent un seul renouvellement.
      return await (_renouvellement ??= _renouveler().whenComplete(
        () => _renouvellement = null,
      ));
    } catch (e) {
      if (erreurDe(e).type == TypeErreurAuth.reseau) return null;
      // Session refusée (révoquée, jeton de renouvellement expiré) :
      // effacée ; l'application revient à la connexion.
      try {
        await _auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
      return null;
    }
  }

  Future<String> _renouveler() async {
    final r = await _auth.refreshSession();
    final jeton = r.session?.accessToken;
    if (jeton == null) throw const AuthException('Session expirée');
    _horloge.observer(jeton);
    return jeton;
  }

  /// Libère l'écoute des événements (tests, fermeture).
  @visibleForTesting
  Future<void> fermer() async {
    await _abonnement.cancel();
    await _changements.close();
  }

  // --- Traductions -----------------------------------------------------------

  static const _profilIntrouvable = ErreurAuth(
    TypeErreurAuth.inconnue,
    'Votre profil est introuvable sur le serveur JARVIS.',
  );

  static UtilisateurAuth? _utilisateurDe(User? u) {
    if (u == null) return null;
    final nom = u.userMetadata?['display_name'];
    return UtilisateurAuth(
      identifiant: u.id,
      email: u.email ?? '',
      nom: nom is String && nom.trim().isNotEmpty ? nom.trim() : null,
    );
  }

  Future<ResultatAuth<T>> _protege<T>(
    Future<ResultatAuth<T>> Function() operation,
  ) async {
    try {
      return await operation();
    } catch (e) {
      return EchecAuth(erreurDe(e));
    }
  }

  /// Traduit une erreur Supabase ou réseau en famille d'erreur JARVIS.
  @visibleForTesting
  static ErreurAuth erreurDe(Object e) {
    if (e is AuthRetryableFetchException ||
        e is http.ClientException ||
        e is TimeoutException) {
      return const ErreurAuth(TypeErreurAuth.reseau);
    }
    if (e is AuthException) {
      final type = switch (e.code) {
        'invalid_credentials' => TypeErreurAuth.identifiantsInvalides,
        'email_not_confirmed' => TypeErreurAuth.emailNonConfirme,
        'user_already_exists' ||
        'email_exists' => TypeErreurAuth.emailDejaUtilise,
        'weak_password' => TypeErreurAuth.motDePasseFaible,
        'over_request_rate_limit' ||
        'over_email_send_rate_limit' => TypeErreurAuth.tropDeTentatives,
        'session_not_found' ||
        'session_expired' ||
        'refresh_token_not_found' ||
        'refresh_token_already_used' ||
        'bad_jwt' ||
        'user_not_found' => TypeErreurAuth.sessionExpiree,
        'email_address_invalid' ||
        'validation_failed' ||
        'same_password' => TypeErreurAuth.donneesRefusees,
        'signup_disabled' => null,
        _ => switch (e.statusCode) {
          '429' => TypeErreurAuth.tropDeTentatives,
          '401' || '403' => TypeErreurAuth.sessionExpiree,
          _ =>
            e.message.toLowerCase().contains('invalid login credentials')
                ? TypeErreurAuth.identifiantsInvalides
                : TypeErreurAuth.inconnue,
        },
      };
      if (type == null) {
        return const ErreurAuth(
          TypeErreurAuth.donneesRefusees,
          'Les inscriptions sont fermées pour le moment.',
        );
      }
      return ErreurAuth(type);
    }
    if (e is PostgrestException) {
      return ErreurAuth(
        e.code == 'PGRST301' || e.code == '401'
            ? TypeErreurAuth.sessionExpiree
            : TypeErreurAuth.inconnue,
      );
    }
    debugPrint('[JARVIS auth] erreur inattendue : ${e.runtimeType}');
    return const ErreurAuth(TypeErreurAuth.inconnue);
  }
}
