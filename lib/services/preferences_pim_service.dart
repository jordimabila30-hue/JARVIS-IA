import 'package:flutter/foundation.dart';

import '../models/forme_pim.dart';
import 'voice_settings_service.dart';

/// Préférences des particules PIM : la forme principale (sphère par
/// défaut), enregistrée sur l'appareil avec le même stockage que les
/// réglages vocaux (SharedPreferences), sous sa propre clé.
class PreferencesPimService extends ChangeNotifier {
  PreferencesPimService({StockageReglages? stockage})
    : _stockage = stockage ?? const StockagePreferences(cle: cleStockage);

  static const cleStockage = 'jarvis.forme_principale';

  final StockageReglages _stockage;

  /// Forme principale choisie.
  FormePim get forme => _forme;
  FormePim _forme = FormePim.sphere;

  /// Vrai une fois la préférence enregistrée lue (même absente).
  bool get charge => _charge;
  bool _charge = false;

  /// Lit la forme enregistrée (sphère si aucune, ou valeur inconnue).
  Future<void> charger() async {
    String? valeur;
    try {
      valeur = await _stockage.lire();
    } catch (e) {
      debugPrint('[JARVIS PIM] préférence illisible : $e');
    }
    _forme = FormePim.values.asNameMap()[valeur] ?? _forme;
    _charge = true;
    notifyListeners();
  }

  /// Choisit la forme principale : appliquée tout de suite, puis
  /// enregistrée.
  Future<void> choisir(FormePim forme) async {
    if (forme == _forme) return;
    _forme = forme;
    notifyListeners();
    try {
      await _stockage.ecrire(forme.name);
    } catch (e) {
      debugPrint('[JARVIS PIM] préférence non enregistrée : $e');
    }
  }
}
