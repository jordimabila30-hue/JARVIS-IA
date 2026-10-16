import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/conversations/apercu_conversation.dart';
import '../voice_settings_service.dart';

/// Conversations épinglées, gardées sur l'appareil (même stockage que les
/// autres préférences) et retrouvées à la réouverture.
///
/// Une épingle appartient à une conversation d'une source précise (clé
/// « source:id ») : elle ne mélange jamais les messageries. L'ordre
/// d'épinglage est conservé : la dernière épinglée passe en tête, puis
/// l'ordre ne bouge plus.
///
/// Le jour où les épingles seront synchronisées par le backend, il suffira
/// de fournir un autre [StockageReglages].
class EpinglesConversations extends ChangeNotifier {
  EpinglesConversations({StockageReglages? stockage})
    : _stockage = stockage ?? const StockagePreferences(cle: cleStockage);

  static const cleStockage = 'jarvis.conversations_epinglees';

  final StockageReglages _stockage;

  // Clés, la plus récemment épinglée d'abord.
  final List<String> _cles = [];

  /// Relit les épingles enregistrées (silencieux si rien ou illisible).
  Future<void> charger() async {
    try {
      final brut = await _stockage.lire();
      if (brut == null) return;
      final liste = (jsonDecode(brut) as List).whereType<String>();
      _cles
        ..clear()
        ..addAll(liste);
      notifyListeners();
    } catch (e) {
      debugPrint('[JARVIS épingles] lecture impossible : $e');
    }
  }

  bool estEpinglee(ApercuConversation c) => _cles.contains(c.cle);

  /// Rang d'épinglage (0 : la plus récente), ou -1.
  int rang(ApercuConversation c) => _cles.indexOf(c.cle);

  void basculer(ApercuConversation c) {
    if (!_cles.remove(c.cle)) _cles.insert(0, c.cle);
    notifyListeners();
    _enregistrer();
  }

  /// Retire l'épingle (conversation supprimée) : aucune référence
  /// invalide ne reste enregistrée.
  void retirer(ApercuConversation c) {
    if (!_cles.remove(c.cle)) return;
    notifyListeners();
    _enregistrer();
  }

  /// La même conversation change de clé (reclassée sous une autre
  /// source) : son épingle la suit, au même rang.
  void deplacer(String ancienne, String nouvelle) {
    final i = _cles.indexOf(ancienne);
    if (i < 0 || ancienne == nouvelle) return;
    _cles
      ..remove(nouvelle)
      ..[_cles.indexOf(ancienne)] = nouvelle;
    notifyListeners();
    _enregistrer();
  }

  Future<void> _enregistrer() async {
    try {
      await _stockage.ecrire(jsonEncode(_cles));
    } catch (e) {
      debugPrint('[JARVIS épingles] écriture impossible : $e');
    }
  }
}
