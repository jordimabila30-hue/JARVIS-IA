import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../conversations/depot_conversations.dart';
import 'auth_repository.dart';
import 'auth_repository_supabase.dart';
import 'stockage_session.dart';

/// Configuration de l'authentification et du backend, lue à la compilation
/// (`--dart-define` ou `--dart-define-from-file=config_locale.json`) :
/// aucune adresse ni clé dans le code source.
///
/// Seules des valeurs publiques arrivent ici : l'adresse du projet
/// Supabase et sa clé publique (« publishable »). Les clés du serveur
/// (service_role, IA) restent dans `backend/.env`, jamais dans Flutter.
class ConfigAuth {
  const ConfigAuth({
    this.adresseServeur = '',
    this.serveur = 'local',
    this.accesDeveloppement = false,
    this.supabaseUrl = '',
    this.supabaseCle = '',
  });

  /// Backend JARVIS hébergé (Render). Seul endroit où figure cette adresse.
  static const adresseHebergee = 'https://jarvis-ia-quq6.onrender.com';

  /// Configuration de cette compilation.
  factory ConfigAuth.compilation() => const ConfigAuth(
    adresseServeur: String.fromEnvironment('JARVIS_API_URL'),
    // Release : le serveur hébergé ; debug et profile : le Docker local,
    // sauf choix explicite : --dart-define=JARVIS_SERVEUR=local|distant.
    serveur: String.fromEnvironment(
      'JARVIS_SERVEUR',
      defaultValue: kReleaseMode ? 'distant' : 'local',
    ),
    // Actif en debug et profile, désactivé en release (production), sauf
    // choix explicite : --dart-define=JARVIS_ACCES_DEV=true|false.
    accesDeveloppement: bool.fromEnvironment(
      'JARVIS_ACCES_DEV',
      defaultValue: !kReleaseMode,
    ),
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseCle: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  /// Adresse du backend FastAPI imposée (téléphone physique : l'adresse
  /// de l'ordinateur sur le réseau local, ex. http://192.168.1.20:8000) ;
  /// vide : adresse locale par défaut de la plateforme ([adresseApi]).
  final String adresseServeur;

  /// Environnement du backend quand [adresseServeur] est vide : 'local'
  /// (Docker de l'ordinateur) ou 'distant' ([adresseHebergee]).
  final String serveur;

  /// Accès de développement : « Continuer sans compte » sur la page de
  /// connexion, pour ouvrir l'accueil sans session (aucun utilisateur,
  /// aucun jeton, aucune ressource protégée).
  final bool accesDeveloppement;

  /// Projet Supabase (adresse et clé publique).
  final String supabaseUrl;
  final String supabaseCle;

  bool get supabaseConfigure =>
      supabaseUrl.isNotEmpty && supabaseCle.isNotEmpty;

  bool get serveurConfigure => supabaseConfigure;

  /// Backend FastAPI : [adresseServeur] si elle est donnée, sinon selon
  /// [serveur]. En local, `localhost` ne désigne pas le même appareil
  /// partout : l'émulateur Android joint l'ordinateur par 10.0.2.2 ; un
  /// téléphone USB passe par `adb reverse` et JARVIS_API_URL.
  Uri get adresseApi {
    if (adresseServeur.isNotEmpty) return Uri.parse(adresseServeur);
    switch (serveur) {
      case 'distant':
        return Uri.parse(adresseHebergee);
      case 'local':
        final android =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
        return Uri.parse(
          android ? 'http://10.0.2.2:8000' : 'http://localhost:8000',
        );
      default:
        throw ArgumentError.value(
          serveur,
          'JARVIS_SERVEUR',
          'valeurs possibles : local, distant',
        );
    }
  }

  /// Serveur hors de l'ordinateur de développement (hébergé) : il peut
  /// être en veille et mettre plusieurs dizaines de secondes à répondre.
  bool get serveurDistant => !const {
    'localhost',
    '127.0.0.1',
    '10.0.2.2',
  }.contains(adresseApi.host);

  /// Retour des liens reçus par e-mail (confirmation, mot de passe
  /// oublié). Web : cette même adresse. Android / iOS : JARVIS par
  /// jarvis://auth (intent-filter, CFBundleURLTypes), à ouvrir sur le
  /// téléphone qui a fait la demande ; Supabase le reçoit seulement s'il
  /// figure dans ses « Redirect URLs ». Ailleurs : l'adresse du site.
  String? get redirectionEmails {
    if (kIsWeb) return Uri.base.origin;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => lienRetourMobile,
      _ => null,
    };
  }

  static const lienRetourMobile = 'jarvis://auth';

  /// Durée de vie de la session pour cette plateforme.
  StrategieSession get strategieSession =>
      kIsWeb ? StrategieSession.navigateur : StrategieSession.durable;

  /// À appeler une fois avant `runApp` : prépare Supabase (session gardée
  /// sur l'appareil, renouvellement automatique des jetons, lien de
  /// récupération ouvert au démarrage). Sans configuration : rien.
  Future<void> initialiser() async {
    if (!supabaseConfigure) return;
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseCle);
  }

  /// Conversations enregistrées du compte connecté, lues avec sa session
  /// (règles RLS du projet) ; null sans Supabase.
  DepotConversations? creerDepotConversations({
    required Future<String?> Function() jeton,
    Future<String?> Function()? renouveler,
  }) {
    if (!supabaseConfigure) return null;
    return DepotConversationsSupabase(
      Supabase.instance.client,
      jeton: jeton,
      renouveler: renouveler,
    );
  }

  /// Accès au serveur pour cette configuration : Supabase s'il est
  /// configuré (et initialisé), sinon « non configuré ». C'est le seul
  /// endroit qui choisit.
  AuthRepository creerRepository() {
    if (!supabaseConfigure) return const AuthRepositoryNonConfigure();
    return AuthRepositorySupabase(
      Supabase.instance.client,
      redirection: redirectionEmails,
    );
  }
}
