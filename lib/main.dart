import 'package:flutter/material.dart';

import 'models/authentification/utilisateur_auth.dart';
import 'pages/accueil_page.dart';
import 'pages/authentification/authentification_page.dart';
import 'pages/ecran_de_lancement.dart';
import 'services/authentification/auth_service.dart';
import 'services/authentification/config_auth.dart';
import 'theme/theme_jarvis.dart';

void main() {
  runApp(const JarvisApp());
}

/// Parcours : écran de lancement → vérification de la session → accueil
/// si le serveur l'accepte, sinon connexion (avec l'accès de
/// développement hors production).
class JarvisApp extends StatefulWidget {
  const JarvisApp({super.key, this.config, this.auth});

  /// Injectables pour les tests ; lus de la compilation sinon.
  final ConfigAuth? config;
  final AuthService? auth;

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp> {
  late final _config = widget.config ?? ConfigAuth.compilation();
  late final _auth = widget.auth ?? AuthService(_config.creerRepository());

  // Lancée pendant l'animation de démarrage.
  late final Future<UtilisateurAuth?> _session = _auth.restaurerSession();

  @override
  void dispose() {
    if (widget.auth == null) _auth.dispose();
    super.dispose();
  }

  Future<void> _apresLancement(NavigatorState navigateur) async {
    final utilisateur = await _session;
    navigateur.pushReplacement(
      _routeEnFondu(
        utilisateur != null ? const AccueilPage() : _authentification(),
      ),
    );
  }

  Widget _authentification() => Builder(
    builder: (context) {
      void ouvrirAccueil() => Navigator.of(
        context,
      ).pushReplacement(_routeEnFondu(const AccueilPage()));
      return AuthentificationPage(
        service: _auth,
        surConnecte: (_) => ouvrirAccueil(),
        surAccesDeveloppement: _config.accesDeveloppement
            ? ouvrirAccueil
            : null,
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS',
      debugShowCheckedModeBanner: false,
      theme: themeJarvis(),
      // Builder : donne un context sous MaterialApp (avec un Navigator) pour
      // quitter l'écran de lancement à la fin de l'animation.
      home: Builder(
        builder: (context) => EcranDeLancement(
          onTermine: () => _apresLancement(Navigator.of(context)),
        ),
      ),
    );
  }
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
