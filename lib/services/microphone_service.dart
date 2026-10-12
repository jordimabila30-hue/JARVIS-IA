import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Résultat d'une demande d'accès au microphone.
enum AccesMicro { autorise, refuse, refuseDefinitivement, indisponible, erreur }

/// Gère l'autorisation du microphone.
///
/// Sur Android et iOS, la permission est demandée explicitement ici, ce qui
/// permet de distinguer un refus simple d'un refus définitif. Sur Web et
/// Windows, c'est le navigateur ou le système qui demande l'accès au moment
/// où la reconnaissance vocale démarre : on répond donc « autorisé » et
/// l'éventuel refus remonte par la reconnaissance vocale.
class MicrophoneService {
  bool get _gereIci =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Demande l'accès, uniquement quand une fonction vocale en a besoin.
  Future<AccesMicro> demanderAcces() async {
    if (!_gereIci) return AccesMicro.autorise;
    try {
      var statut = await Permission.microphone.status;
      if (statut.isGranted) return AccesMicro.autorise;
      if (statut.isPermanentlyDenied) return AccesMicro.refuseDefinitivement;
      if (statut.isRestricted) return AccesMicro.indisponible;

      statut = await Permission.microphone.request();
      if (statut.isGranted || statut.isLimited) return AccesMicro.autorise;
      if (statut.isPermanentlyDenied) return AccesMicro.refuseDefinitivement;
      if (statut.isRestricted) return AccesMicro.indisponible;
      return AccesMicro.refuse;
    } catch (_) {
      return AccesMicro.erreur;
    }
  }

  /// Ouvre les réglages de l'app (utile après un refus définitif).
  Future<void> ouvrirReglages() async {
    if (!_gereIci) return;
    try {
      await openAppSettings();
    } catch (_) {
      // Rien à faire : l'utilisateur pourra ouvrir les réglages lui-même.
    }
  }
}
