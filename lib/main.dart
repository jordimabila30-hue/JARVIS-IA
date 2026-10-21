import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/accueil_page.dart';
import 'pages/authentification/authentification_page.dart';
import 'pages/ecran_de_lancement.dart';
import 'services/api_jarvis.dart';
import 'services/apparence/service_apparence.dart';
import 'services/authentification/auth_service.dart';
import 'services/authentification/config_auth.dart';
import 'services/integrations/service_gmail.dart';
import 'services/utilisation/service_utilisation.dart';
import 'theme/theme_jarvis.dart';
import 'utils/chrono_perf.dart';
import 'widgets/apparence/transition_apparence.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Mesures de performance (JARVIS_PERF) : rien hors mesure.
  ChronoPerf.enregistrerExtension();
  var config = ConfigAuth.compilation();
  try {
    // Supabase : session gardée sur l'appareil, lien de récupération.
    await config.initialiser();
  } catch (e) {
    // Jamais d'écran bloqué : JARVIS démarre sans serveur, et le dit.
    debugPrint('[JARVIS] Supabase indisponible : $e');
    config = ConfigAuth(accesDeveloppement: config.accesDeveloppement);
  }
  // Apparence lue avant le premier écran : aucun éclair de l'ancien style.
  final apparence = ServiceApparence(
    luminositeSysteme:
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );
  await apparence.charger();
  runApp(JarvisApp(config: config, apparence: apparence));
}

/// Parcours : écran de lancement → vérification de la session → accueil
/// si le serveur l'accepte, sinon connexion (avec l'accès de
/// développement hors production). Ouvert par un lien « mot de passe
/// oublié » : choix du nouveau mot de passe. Déconnexion (ou session
/// révoquée) : retour à la connexion.
class JarvisApp extends StatefulWidget {
  const JarvisApp({
    super.key,
    this.config,
    this.auth,
    this.api,
    this.apparence,
  });

  /// Préférences d'apparence (thème, motif). Null : créées et lues ici.
  final ServiceApparence? apparence;

  /// Injectables pour les tests ; lus de la compilation sinon.
  final ConfigAuth? config;
  final AuthService? auth;
  final ApiJarvis? api;

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp> with WidgetsBindingObserver {
  late final _apparence =
      widget.apparence ??
      (ServiceApparence(
        luminositeSysteme:
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
      )..charger());
  late final _config = widget.config ?? ConfigAuth.compilation();
  late final _auth = widget.auth ?? AuthService(_config.creerRepository());
  late final _api =
      widget.api ??
      ApiJarvis(
        adresse: _config.adresseApi,
        jeton: _auth.jetonAcces,
        renouveler: _auth.renouvelerJeton,
      );
  late final _depotConversations = _config.creerDepotConversations(
    jeton: _auth.jetonAcces,
    renouveler: _auth.renouvelerJeton,
  );
  final _navigateur = GlobalKey<NavigatorState>();

  /// Utilisation de l'IA du compte (`/me/quota`) : une seule instance,
  /// actualisée après chaque opération IA ([ApiJarvis.surConsommation]).
  late final _utilisation = ServiceUtilisation(_api);

  /// Connexion Gmail (lecture seule) : état lu au serveur, jamais de jeton.
  late final _gmail = ServiceGmail(_api);
  String? _compteUtilisation;

  // Lancée pendant l'animation de démarrage.
  late final Future<void> _session = _auth.restaurerSession();

  /// Écran principal affiché après le lancement (null : lancement).
  _Destination? _destination;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_surAuth);
    _api.surConsommation = _utilisation.signalerConsommation;
  }

  /// Mode « Système » : suit le clair / sombre du système d'exploitation.
  @override
  void didChangePlatformBrightness() {
    _apparence.luminositeSysteme =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.apparence == null) _apparence.dispose();
    _auth.removeListener(_surAuth);
    _api.surConsommation = null;
    _utilisation.dispose();
    _gmail.dispose();
    if (widget.auth == null) _auth.dispose();
    if (widget.api == null) _api.fermer();
    super.dispose();
  }

  /// Session perdue pendant que JARVIS est ouvert (déconnexion, session
  /// révoquée) ; ou lien de récupération ouvert.
  void _surAuth() {
    // Autre compte (ou déconnexion) : rien de l'ancienne utilisation ; la
    // copie locale du nouveau compte s'affiche aussitôt.
    final compte = _auth.utilisateur?.identifiant;
    if (compte != _compteUtilisation) {
      _compteUtilisation = compte;
      _utilisation.changerCompte(compte);
      _gmail.changerCompte();
      // État Gmail connu avant l'ouverture d'Outils, sans gêner l'accueil.
      if (compte != null) _gmail.lireBientot();
    }
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
        // Sans compte : aucune conversation enregistrée.
        depotConversations: d == _Destination.accueilConnecte
            ? _depotConversations
            : null,
        utilisation: d == _Destination.accueilConnecte ? _utilisation : null,
        gmail: d == _Destination.accueilConnecte ? _gmail : null,
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
    // Style et mode : le thème suit la palette affichée ; tout l'arbre
    // atteint le service (Paramètres › Général › Apparence, fonds).
    return ListenableBuilder(
      listenable: _apparence,
      builder: (context, _) {
        final palette = _apparence.palette;
        return MaterialApp(
          title: 'JARVIS',
          navigatorKey: _navigateur,
          debugShowCheckedModeBanner: false,
          theme: themeJarvis(palette),
          builder: (context, enfant) => PorteeApparence(
            service: _apparence,
            child: TransitionApparence(
              service: _apparence,
              child: palette.sombre
                  ? AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle.light,
                      child: enfant!,
                    )
                  : enfant!,
            ),
          ),
          home: EcranDeLancement(onTermine: _apresLancement),
        );
      },
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
    // Court : l'accueil est utilisable sans attendre la fin du fondu.
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, enfant) =>
        FadeTransition(opacity: animation, child: enfant),
  );
}
