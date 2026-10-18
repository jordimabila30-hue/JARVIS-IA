import 'dart:typed_data';

/// Capture d'écran jointe à un message (JARVIS Touch). Le message ne garde
/// qu'une référence : le fichier local validé (cache privé de JARVIS, tant
/// qu'il existe) ; le serveur n'enregistre jamais l'image, seulement sa
/// trace.
class CaptureJointe {
  const CaptureJointe({this.chemin, this.typeMedia = 'image/png'});

  /// Fichier PNG local (null : capture relue du serveur, image absente).
  final String? chemin;
  final String typeMedia;
}

/// Image prête à partir avec UN message, lue une seule fois au moment où
/// l'utilisateur appuie sur Envoyer (jamais envoyée automatiquement).
class ImageAEnvoyer {
  const ImageAEnvoyer(this.typeMedia, this.octets);

  final String typeMedia;
  final Uint8List octets;
}
