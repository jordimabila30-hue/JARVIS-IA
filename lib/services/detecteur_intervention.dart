import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Détection native (Android) d'une intervention de l'utilisateur pendant
/// que JARVIS parle : interruption automatique EXPÉRIMENTALE (canal
/// `jarvis/voix_detection`). Le micro de détection ne tourne que pendant la
/// parole de JARVIS, sur demande de la session vocale.
///
/// Mode mesure (`--dart-define=JARVIS_MESURE_INTERRUPTION=true`) : la
/// détection tourne et journalise ses candidats, sans jamais interrompre.
class DetecteurIntervention {
  DetecteurIntervention({MethodChannel? canal})
    : _canal = canal ?? const MethodChannel('jarvis/voix_detection') {
    _canal.setMethodCallHandler(_surAppel);
  }

  static const mesure = bool.fromEnvironment('JARVIS_MESURE_INTERRUPTION');

  /// Android seulement (le Web et Windows n'ont pas cette détection).
  static bool get disponible =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final MethodChannel _canal;

  /// Intervention probable (énergie durable au-dessus du fond, structure
  /// vocale) : à confirmer par la session.
  void Function(Map<Object?, Object?> mesures)? surCandidat;

  bool _actif = false;

  Future<void> demarrer() async {
    if (_actif) return;
    _actif = true;
    try {
      final r = await _canal.invokeMapMethod<String, Object?>('demarrer');
      debugPrint('[JARVIS détection] démarrée : $r');
    } catch (e) {
      _actif = false;
      debugPrint('[JARVIS détection] indisponible : $e');
    }
  }

  Future<void> arreter() async {
    if (!_actif) return;
    _actif = false;
    try {
      await _canal.invokeMethod<void>('arreter');
    } catch (_) {}
  }

  Future<Object?> _surAppel(MethodCall appel) async {
    switch (appel.method) {
      case 'candidat':
        final m = Map<Object?, Object?>.from(appel.arguments as Map);
        debugPrint('[JARVIS détection] candidat : $m');
        if (_actif) surCandidat?.call(m);
      case 'fin':
        debugPrint('[JARVIS détection] séance : ${appel.arguments}');
    }
    return null;
  }
}
