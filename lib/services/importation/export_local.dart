import 'dart:typed_data';

import 'export_local_web.dart' if (dart.library.io) 'export_local_io.dart';

/// Une entrée d'archive ZIP (sans son contenu).
class EntreeArchive {
  const EntreeArchive({
    required this.nom,
    required this.taille,
    required this.tailleCompressee,
  });

  /// Chemin dans l'archive (« WhatsApp Chat with Tony.txt », « _chat.txt »).
  final String nom;

  /// Taille décompressée annoncée par l'archive.
  final int taille;
  final int tailleCompressee;
}

/// Copie privée et temporaire de l'export, le temps de la lecture :
/// relisible (un fichier partagé ou choisi dans le navigateur ne se lit
/// qu'une fois) et lisible par endroits (index d'un ZIP à la fin du
/// fichier). Android, iOS, Windows : fichier dans le cache de JARVIS ;
/// navigateur : mémoire. Supprimée dès que la page d'import se ferme.
abstract class ExportLocal {
  /// Écrit l'export morceau par morceau ; [ecrire] puis [fermerEcriture].
  static Future<ExportLocal> creer() => creerExportLocal();

  Future<void> ecrire(List<int> morceau);
  Future<void> fermerEcriture();

  int get taille;

  /// Contenu complet, autant de fois que nécessaire.
  Stream<List<int>> lire();

  /// Index de l'archive (lève une exception si l'archive est illisible).
  Future<List<EntreeArchive>> listerArchive();

  /// Contenu décompressé d'une entrée ; [limite] : taille maximale
  /// acceptée (lève [ArchiveDemesuree] au-delà).
  Future<Uint8List> extraire(String nom, {required int limite});

  /// Efface la copie.
  Future<void> supprimer();
}

/// Entrée qui se décompresse au-delà de ce qu'elle annonce, ou de la
/// limite : archive malveillante ou endommagée.
class ArchiveDemesuree implements Exception {
  const ArchiveDemesuree();
}
