import 'niveau_micro_autre.dart'
    if (dart.library.js_interop) 'niveau_micro_web.dart';

/// Mesure le volume du microphone (0 à 1), en parallèle de la
/// reconnaissance vocale.
///
/// Utile sur le Web, où la reconnaissance vocale du navigateur ne fournit
/// pas de niveau sonore. Sur les autres plateformes, la reconnaissance
/// vocale le fournit déjà : [demarrer] renvoie alors false.
abstract class NiveauMicro {
  factory NiveauMicro() => creerNiveauMicro();

  /// Démarre la mesure. Renvoie false si elle n'est pas disponible.
  /// [surBandes] reçoit graves, médiums et aigus (0 à 1) quand la plateforme
  /// fournit le spectre. [microphoneId] : micro choisi dans les Paramètres
  /// (null = micro par défaut).
  Future<bool> demarrer(
    void Function(double niveau) surNiveau, {
    void Function(double graves, double mediums, double aigus)? surBandes,
    String? microphoneId,
  });

  /// Arrête la mesure et libère le microphone.
  Future<void> arreter();
}
