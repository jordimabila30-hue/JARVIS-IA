import '../models/voice_settings.dart';
import 'peripheriques_audio_autre.dart'
    if (dart.library.js_interop) 'peripheriques_audio_web.dart';

/// Liste des micros de l'appareil, quand la plateforme permet de choisir.
///
/// Seul le navigateur expose ses micros (`enumerateDevices`). Sur Android,
/// iOS et Windows, la reconnaissance vocale utilise toujours le micro par
/// défaut du système : [choixPossible] est faux.
abstract class PeripheriquesAudio {
  factory PeripheriquesAudio() => creerPeripheriquesAudio();

  bool get choixPossible;

  /// Micros disponibles. Sur le Web, les noms restent vides tant que
  /// l'accès au micro n'a pas été accordé une première fois.
  Future<List<MicroDisponible>> lister();

  /// Demande l'accès au micro (Web) pour connaître le nom des micros.
  /// Renvoie vrai si l'accès est accordé.
  Future<bool> autoriser();
}
