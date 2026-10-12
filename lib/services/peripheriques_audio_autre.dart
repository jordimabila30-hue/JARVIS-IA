import '../models/voice_settings.dart';
import 'peripheriques_audio.dart';

/// Hors Web : micro par défaut du système uniquement.
PeripheriquesAudio creerPeripheriquesAudio() => _MicroParDefaut();

class _MicroParDefaut implements PeripheriquesAudio {
  @override
  bool get choixPossible => false;

  @override
  Future<List<MicroDisponible>> lister() async => const [];

  @override
  Future<bool> autoriser() async => false;
}
