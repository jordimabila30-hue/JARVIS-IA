import 'package:flutter/foundation.dart';

import 'auth_repository.dart';
import 'stockage_session.dart';

/// Configuration de l'authentification, lue à la compilation
/// (`--dart-define`) : aucune adresse ni secret dans le code source.
class ConfigAuth {
  const ConfigAuth({this.adresseServeur = '', this.accesDeveloppement = false});

  /// Configuration de cette compilation.
  factory ConfigAuth.compilation() => const ConfigAuth(
    adresseServeur: String.fromEnvironment('JARVIS_API_URL'),
    // Actif en debug et profile, désactivé en release (production), sauf
    // choix explicite : --dart-define=JARVIS_ACCES_DEV=true|false.
    accesDeveloppement: bool.fromEnvironment(
      'JARVIS_ACCES_DEV',
      defaultValue: !kReleaseMode,
    ),
  );

  /// Adresse du serveur fournie par le développeur backend ; vide tant
  /// qu'il n'existe pas.
  final String adresseServeur;

  /// Accès de développement : « Continuer sans compte » sur la page de
  /// connexion, pour ouvrir l'accueil sans session (aucun utilisateur,
  /// aucun jeton, aucune ressource protégée).
  final bool accesDeveloppement;

  bool get serveurConfigure => adresseServeur.isNotEmpty;

  /// Durée de vie de la session pour cette plateforme.
  StrategieSession get strategieSession =>
      kIsWeb ? StrategieSession.navigateur : StrategieSession.durable;

  /// Accès au serveur pour cette configuration. Tant que l'implémentation
  /// réelle n'existe pas : toujours « non configuré ». À l'intégration,
  /// c'est le seul endroit à changer.
  AuthRepository creerRepository() => const AuthRepositoryNonConfigure();
}
