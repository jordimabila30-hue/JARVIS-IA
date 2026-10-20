import 'dart:math';
import 'dart:typed_data';

import 'depot_fonds_photo_web.dart'
    if (dart.library.io) 'depot_fonds_photo_io.dart'
    as plateforme;

/// Dépôt LOCAL des photos de fond : les octets d'origine, rangés sous un
/// identifiant. Fichiers du dossier de l'application (Android, iOS,
/// Windows : jamais un cache temporaire), IndexedDB du navigateur (Web).
/// Rien ne quitte l'appareil : ni serveur, ni IA, ni base distante.
abstract class DepotFondsPhoto {
  /// Dépôt de la plateforme.
  factory DepotFondsPhoto() => plateforme.creerDepot();

  /// Taille maximale d'une photo importée.
  static const tailleMax = 25 * 1024 * 1024;

  /// Range [octets] et rend leur identifiant.
  Future<String> enregistrer(Uint8List octets);

  /// Octets d'une photo (null : absente).
  Future<Uint8List?> lire(String id);

  Future<void> supprimer(String id);

  /// Identifiants présents.
  Future<List<String>> lister();

  /// Supprime toutes les photos sauf [garder] (fonds plus utilisés).
  Future<void> nettoyer(Set<String> garder) async {
    for (final id in await lister()) {
      if (!garder.contains(id)) await supprimer(id);
    }
  }

  /// Nouvel identifiant (lettres et chiffres, impossible à deviner).
  static String nouvelId() {
    final r = Random.secure();
    return List.generate(20, (_) => r.nextInt(36).toRadixString(36)).join();
  }
}

/// Dépôt en mémoire (tests).
class DepotFondsPhotoMemoire implements DepotFondsPhoto {
  final fichiers = <String, Uint8List>{};

  @override
  Future<String> enregistrer(Uint8List octets) async {
    final id = DepotFondsPhoto.nouvelId();
    fichiers[id] = octets;
    return id;
  }

  @override
  Future<Uint8List?> lire(String id) async => fichiers[id];

  @override
  Future<void> supprimer(String id) async => fichiers.remove(id);

  @override
  Future<List<String>> lister() async => fichiers.keys.toList();

  @override
  Future<void> nettoyer(Set<String> garder) async =>
      fichiers.removeWhere((id, _) => !garder.contains(id));
}
