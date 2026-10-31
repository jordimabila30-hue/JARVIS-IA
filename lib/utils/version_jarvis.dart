import 'package:flutter/services.dart';

/// Version de l'application, lue dans la build elle-même (`version:` du
/// pubspec.yaml, `X.Y.Z+BUILD`, injectée par Flutter) : une seule source,
/// jamais écrite à la main ailleurs. Politique : docs/VERSIONING.md.
///
/// C'est la version de l'APPLICATION ; celle du serveur est son commit
/// (`GET /health` → `commit`).
class VersionJarvis {
  VersionJarvis._();

  /// `X.Y.Z` (null : build sans version, par exemple certains tests).
  static const String? nom = appBuildName;

  /// Numéro de build croissant (`+BUILD`).
  static const String? build = appBuildNumber;

  /// « Version 1.0.0 (build 1) » (Paramètres).
  static String get libelle {
    if (nom == null) return 'Version inconnue';
    return build == null ? 'Version $nom' : 'Version $nom (build $build)';
  }

  /// « 1.0.0 (build 1) » (valeur d'une ligne de réglage).
  static String get valeur =>
      nom == null ? 'inconnue' : (build == null ? nom! : '$nom (build $build)');

  /// « v1.0.0 » (écran de lancement), vide si inconnue.
  static String get courte => nom == null ? '' : 'v$nom';
}
