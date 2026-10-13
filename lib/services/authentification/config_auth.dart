import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    this.accesDeveloppement = false,
    this.supabaseUrl = '',
    this.supabaseCle = '',
  });

  /// Configuration de cette compilation.
  factory ConfigAuth.compilation() => const ConfigAuth(
    adresseServeur: String.fromEnvironment('JARVIS_API_URL'),
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

  /// Backend FastAPI. `localhost` ne désigne pas le même appareil
  /// partout : l'émulateur Android joint l'ordinateur par 10.0.2.2 ; un
  /// téléphone physique a besoin de [adresseServeur] (JARVIS_API_URL).
  Uri get adresseApi {
    if (adresseServeur.isNotEmpty) return Uri.parse(adresseServeur);
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return Uri.parse(
      android ? 'http://10.0.2.2:8000' : 'http://localhost:8000',
    );
  }

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

  /// Accès au serveur pour cette configuration : Supabase s'il est
  /// configuré (et initialisé), sinon « non configuré ». C'est le seul
  /// endroit qui choisit.
  AuthRepository creerRepository() {
    if (!supabaseConfigure) return const AuthRepositoryNonConfigure();
    return AuthRepositorySupabase(
      Supabase.instance.client,
      // Web : le lien de récupération revient sur cette même adresse.
      redirection: kIsWeb ? Uri.base.origin : null,
    );
  }
}
