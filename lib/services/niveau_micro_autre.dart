import 'niveau_micro.dart';

/// Hors Web : la reconnaissance vocale fournit déjà le niveau sonore.
NiveauMicro creerNiveauMicro() => _NiveauMicroAbsent();

class _NiveauMicroAbsent implements NiveauMicro {
  @override
  Future<bool> demarrer(
    void Function(double niveau) surNiveau, {
    void Function(double graves, double mediums, double aigus)? surBandes,
    String? microphoneId,
  }) async => false;

  @override
  Future<void> arreter() async {}
}
