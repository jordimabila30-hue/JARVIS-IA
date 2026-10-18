import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/utilisation/utilisation.dart';
import '../voice_settings_service.dart';

/// Dernière utilisation lue sur le serveur, gardée sur l'appareil.
class UtilisationEnCache {
  const UtilisationEnCache(this.utilisation, this.luLe);

  final Utilisation utilisation;

  /// Instant de la lecture réussie au serveur.
  final DateTime luLe;
}

/// Copie locale de la dernière réponse de `/me/quota`, pour afficher
/// l'écran Utilisation aussitôt (même hors ligne, même après un
/// redémarrage) pendant que le serveur est relu en silence.
///
/// Une seule entrée, rattachée au compte qui l'a lue : un autre compte ne
/// la voit jamais (elle est ignorée puis remplacée), la déconnexion
/// l'efface. Affichage seulement : les quotas sont décidés par le serveur,
/// jamais d'après cette copie. Format versionné : un ancien format est
/// ignoré. Toute erreur de stockage est silencieuse (rien n'est affiché
/// plutôt qu'une valeur douteuse).
class CacheUtilisation {
  CacheUtilisation({StockageReglages? stockage})
    : _stockage = stockage ?? const StockagePreferences(cle: cle);

  static const cle = 'jarvis.utilisation';
  static const version = 1;

  final StockageReglages _stockage;

  Future<UtilisationEnCache?> lire(String compte) async {
    try {
      final brut = await _stockage.lire();
      if (brut == null || brut.isEmpty) return null;
      final j = jsonDecode(brut);
      if (j is! Map<String, dynamic> ||
          j['v'] != version ||
          j['compte'] != compte) {
        return null;
      }
      final luLe = DateTime.tryParse('${j['lu_le']}');
      final quota = j['quota'];
      if (luLe == null || quota is! Map<String, dynamic>) return null;
      return UtilisationEnCache(Utilisation.depuisJson(quota), luLe);
    } catch (e) {
      debugPrint('[JARVIS utilisation] copie locale illisible : $e');
      return null;
    }
  }

  Future<void> ecrire(String compte, Utilisation u, DateTime luLe) async {
    try {
      await _stockage.ecrire(
        jsonEncode({
          'v': version,
          'compte': compte,
          'lu_le': luLe.toUtc().toIso8601String(),
          'quota': u.versJson(),
        }),
      );
    } catch (e) {
      debugPrint('[JARVIS utilisation] copie locale non enregistrée : $e');
    }
  }

  Future<void> effacer() async {
    try {
      await _stockage.ecrire('');
    } catch (e) {
      debugPrint('[JARVIS utilisation] copie locale non effacée : $e');
    }
  }
}
