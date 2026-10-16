import 'package:flutter/foundation.dart';

import '../voice_settings_service.dart';

/// Réponse de l'utilisateur à l'envoi des messages WhatsApp joints au
/// fournisseur IA externe (GroqCloud) pour leur analyse.
enum EtatConsentement {
  /// Jamais demandé : le serveur refuse l'analyse (409) avant tout appel
  /// au fournisseur, JARVIS demande l'accord dans le fil.
  inconnu(null),

  /// Accordé : les extraits utiles partent avec les questions qui portent
  /// sur un chat WhatsApp.
  accorde('allowed'),

  /// Refusé : rien de WhatsApp ne part ; stockage et « Voir les messages »
  /// restent disponibles.
  refuse('declined');

  const EtatConsentement(this.valeurApi);

  /// Valeur de `whatsapp_analysis` pour le serveur (null : non demandé).
  final String? valeurApi;
}

/// Accord pour l'analyse distante des conversations WhatsApp jointes.
///
/// Distinct de l'importation et du stockage dans le compte (qui n'envoient
/// rien à l'IA). Conservé sur l'appareil, par compte : un autre compte, ou
/// un autre appareil, redemande l'accord. Révocable dans les Paramètres.
class ConsentementAnalyse extends ChangeNotifier {
  ConsentementAnalyse({StockageReglages? stockage, String? compte})
    : _stockage =
          stockage ??
          StockagePreferences(cle: '$prefixeCle${compte ?? 'sans_compte'}');

  static const prefixeCle = 'jarvis.analyse_whatsapp.';

  final StockageReglages _stockage;

  EtatConsentement get etat => _etat;
  EtatConsentement _etat = EtatConsentement.inconnu;

  bool get charge => _charge;
  bool _charge = false;

  Future<void> charger() async {
    try {
      final v = await _stockage.lire();
      _etat = EtatConsentement.values.asNameMap()[v] ?? _etat;
    } catch (e) {
      debugPrint('[JARVIS consentement] illisible : $e');
    }
    _charge = true;
    notifyListeners();
  }

  Future<void> accorder() => _choisir(EtatConsentement.accorde);

  Future<void> refuser() => _choisir(EtatConsentement.refuse);

  Future<void> _choisir(EtatConsentement etat) async {
    if (etat == _etat) return;
    _etat = etat;
    notifyListeners();
    try {
      await _stockage.ecrire(etat.name);
    } catch (e) {
      debugPrint('[JARVIS consentement] non enregistré : $e');
    }
  }
}
