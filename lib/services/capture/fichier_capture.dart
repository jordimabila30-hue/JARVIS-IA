/// Fichier local d'une capture d'écran (JARVIS Touch, Android) : lecture
/// des octets à l'envoi et miniature dans le fil. Sur le Web, aucune
/// capture locale n'existe.
library;

export 'fichier_capture_autre.dart'
    if (dart.library.io) 'fichier_capture_io.dart';
