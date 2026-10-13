import 'package:flutter/material.dart';

import 'pages/accueil_page.dart';
import 'pages/authentification/authentification_page.dart';
import 'pages/ecran_de_lancement.dart';
import 'services/api_jarvis.dart';
import 'services/authentification/auth_service.dart';
import 'services/authentification/config_auth.dart';
import 'theme/theme_jarvis.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var config = ConfigAuth.compilation();
  try {
    // Supabase : session gardée sur l'appareil, lien de récupération.
    await config.initialiser();
  } catch (e) {
    // Jamais d'écran bloqué : JARVIS démarre sans serveur, et le dit.
    debugPrint('[JARVIS] Supabase indisponible : $e');
    config = ConfigAuth(accesDeveloppement: config.accesDeveloppement);
  }
  runApp(JarvisApp(config: config));
}

/// Parcours : écran de lancement → vérification de la session → accueil
/// si le serveur l'accepte, sinon connexion (avec l'accès de
/// développement hors production). Ouvert par un lien « mot de passe
/// oublié » : choix du nouveau mot de passe. Déconnexion (ou session
/// révoquée) : retour à la connexion.
class JarvisApp extends StatefulWidget {
  const JarvisApp({super.key, this.config, this.auth, this.api});

  /// Injectables pour les tests ; lus de la compilation sinon.
  final ConfigAuth? config;
  final AuthService? auth;
  final ApiJarvis? api;

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp> {
  late final _config = widget.config ?? ConfigAuth.compilation();
  late final _auth = widget.auth ?? AuthService(_config.creerRepository());
  late final _api =
      widget.api ??
      ApiJarvis(
        adresse: _config.adresseApi,
        jeton: _auth.jetonAcces,
        renouveler: _auth.renouvelerJeton,
      );
  final _navigateur = GlobalKey<NavigatorState>();

  // Lancée pendant l'animation de démarrage.
  late final Future<void> _session = _auth.restaurerSession();

  /// Écran principal affiché après le lancement (null : lancement).
  _Destination? _destination;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_surAuth);
  }

  @override
  void dispose() {
    _auth.removeListener(_surAuth);
    if (widget.auth == null) _auth.dispose();
    if (widget.api == null) _api.fermer();
    super.dispose();
  }

  /// Session perdue pendant que JARVIS est ouvert (déconnexion, session
  /// révoquée) ; ou lien de récupération ouvert.
  void _surAuth() {
    final d = _destination;
    if (d == null) return;
    if (_auth.recuperationEnCours && d != _Destination.nouveauMotDePasse) {
      _aller(_Destination.nouveauMotDePasse);
    } else if (!_auth.connecte && d == _Destination.accueilConnecte) {
      _aller(_Destination.connexion);
    }
  }

  Future<void> _apresLancement() async {
    await _session;
    _aller(
      _auth.recuperationEnCours
          ? _Destination.nouveauMotDePasse
          : _auth.connecte
          ? _Destination.accueilConnecte
          : _Destination.connexion,
    );
  }

  void _aller(_Destination d) {
    final navigateur = _navigateur.currentState;
    if (navigateur == null) return;
    _destination = d;
    final page = switch (d) {
      _Destination.accueilConnecte ||
      _Destination.accueilSansCompte => AccueilPage(
        auth: _auth,
        api: _api,
        surConnexion: () => _aller(_Destination.connexion),
      ),
      _Destination.connexion => _authentification(EcranAuth.connexion),
      _Destination.nouveauMotDePasse => _authentification(
        EcranAuth.nouveauMotDePasse,
      ),
    };
    // Tout ce qui était ouvert (Paramètres…) se ferme.
    navigateur.pushAndRemoveUntil(_routeEnFondu(page), (_) => false);
  }

  Widget _authentification(EcranAuth ecran) => AuthentificationPage(
    key: ValueKey(ecran),
    service: _auth,
    ecranInitial: ecran,
    // Session expirée ou révoquée (pas une déconnexion volontaire).
    messageConnexion: _auth.sessionPerdue
        ? 'Votre session a expiré. Reconnectez-vous.'
        : null,
    surConnecte: (_) => _aller(_Destination.accueilConnecte),
    surAccesDeveloppement: _config.accesDeveloppement
        ? () => _aller(_Destination.accueilSansCompte)
        : null,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS',
      navigatorKey: _navigateur,
      debugShowCheckedModeBanner: false,
      theme: themeJarvis(),
      home: EcranDeLancement(onTermine: _apresLancement),
    );
  }
}

enum _Destination {
  accueilConnecte,
  accueilSansCompte,
  connexion,
  nouveauMotDePasse,
}

/// Transition en fondu entre deux pages.
Route<void> _routeEnFondu(Widget page) {
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 700),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, enfant) =>
        FadeTransition(opacity: animation, child: enfant),
  );
}
