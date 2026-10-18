import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// Octets de la capture, lus une seule fois (null : fichier absent).
Future<Uint8List?> lireCapture(String chemin) async {
  try {
    return await File(chemin).readAsBytes();
  } on FileSystemException {
    return null;
  }
}

/// Miniature décodée à petite taille (jamais l'image entière en mémoire) ;
/// null : fichier supprimé depuis.
ImageProvider? miniatureCapture(String chemin, {int largeur = 240}) {
  final f = File(chemin);
  if (!f.existsSync()) return null;
  return ResizeImage(FileImage(f), width: largeur, allowUpscaling: false);
}
