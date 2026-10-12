import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/importation/conversation_whatsapp.dart';
import '../voice_settings_service.dart';

/// Noms sous lesquels l'utilisateur apparaît dans ses exports WhatsApp
/// (« Jordi », « Moi », son numéro…), gardés sur l'appareil : une fois
/// confirmé, son nom est reconnu dans les imports suivants.
class IdentiteWhatsApp {
  IdentiteWhatsApp({StockageReglages? stockage})
    : _stockage = stockage ?? const StockagePreferences(cle: cleStockage);

  static const cleStockage = 'jarvis.whatsapp.mes_noms';

  final StockageReglages _stockage;
  final _noms = <String>[];
  bool _charge = false;

  Future<void> charger() async {
    if (_charge) return;
    _charge = true;
    try {
      final brut = await _stockage.lire();
      if (brut == null) return;
      _noms.addAll((jsonDecode(brut) as List).whereType<String>());
    } catch (e) {
      debugPrint('[JARVIS identité] lecture impossible : $e');
    }
  }

  /// Le participant déjà confirmé comme « moi », s'il est unique ;
  /// sinon null (la question est posée).
  String? reconnaitre(ConversationWhatsApp c) {
    final trouves = [
      for (final p in c.participants)
        if (_noms.contains(p.nom)) p.nom,
    ];
    return trouves.length == 1 ? trouves.single : null;
  }

  /// Confirme [nom] comme « moi » (le plus récent en tête) ; [ancien] :
  /// choix corrigé, oublié.
  Future<void> confirmer(String nom, {String? ancien}) async {
    if (ancien != null && ancien != nom) _noms.remove(ancien);
    _noms
      ..remove(nom)
      ..insert(0, nom);
    try {
      await _stockage.ecrire(jsonEncode(_noms));
    } catch (e) {
      debugPrint('[JARVIS identité] écriture impossible : $e');
    }
  }
}
