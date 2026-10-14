import 'package:flutter/foundation.dart';

/// Où en est la réception d'un texte.
enum EtatReception {
  /// Des fragments peuvent encore arriver.
  enCours,

  /// Texte complet (fin normale).
  terminee,

  /// Réception arrêtée avant la fin (coupure, erreur) : le texte déjà reçu
  /// est gardé, mais n'est jamais présenté comme complet.
  interrompue,
}

/// Tampon de réception d'un texte qui arrive par fragments (flux SSE de
/// l'IA) ou en une seule fois (réponse locale, proposition de réponse).
///
/// Ne s'occupe que de la réception : l'affichage progressif est le rôle
/// d'[EcritureProgressive], l'enregistrement celui de la conversation.
/// Les fragments sont gardés dans l'ordre exact d'arrivée.
///
/// [nettoyer] met en forme le texte brut pour l'affichage (Markdown
/// retiré…) ; il n'est appliqué qu'à la lecture de [texte], au plus une
/// fois après chaque ajout (plusieurs fragments arrivés entre deux images
/// ne coûtent qu'une mise en forme).
class TexteEnDirect extends ChangeNotifier {
  TexteEnDirect({String Function(String brut)? nettoyer})
    : _nettoyer = nettoyer;

  /// Texte déjà complet (réponse locale, proposition).
  TexteEnDirect.complet(String texte)
    : _nettoyer = null,
      _final = texte,
      _etat = EtatReception.terminee {
    _brut.write(texte);
  }

  final String Function(String brut)? _nettoyer;
  final _brut = StringBuffer();
  String? _cache;
  String? _final;
  EtatReception _etat = EtatReception.enCours;
  bool _libere = false;

  EtatReception get etat => _etat;

  /// Vrai tant que des fragments peuvent arriver.
  bool get enCours => _etat == EtatReception.enCours;

  /// Texte à afficher : le texte final s'il est connu, sinon le texte reçu
  /// jusqu'ici, mis en forme.
  String get texte {
    final f = _final;
    if (f != null) return f;
    final nettoyer = _nettoyer;
    return _cache ??= nettoyer == null
        ? _brut.toString()
        : nettoyer(_brut.toString());
  }

  /// Texte brut reçu (fragments mis bout à bout).
  String get brut => _brut.toString();

  /// Ajoute un fragment reçu. Ignoré une fois la réception finie.
  void ajouter(String fragment) {
    if (_libere || !enCours || fragment.isEmpty) return;
    _brut.write(fragment);
    _cache = null;
    notifyListeners();
  }

  /// Fin normale de la réception. [texteFinal] (mis en forme par le moteur)
  /// remplace le texte reçu, s'il est donné.
  void terminer([String? texteFinal]) =>
      _finir(EtatReception.terminee, texteFinal);

  /// Réception arrêtée avant la fin : le texte reçu reste affiché
  /// ([texteRecu] : sa version mise en forme, si elle est donnée).
  void interrompre([String? texteRecu]) =>
      _finir(EtatReception.interrompue, texteRecu);

  void _finir(EtatReception etat, String? texte) {
    if (_libere || !enCours) return;
    _final = texte ?? this.texte;
    _etat = etat;
    notifyListeners();
  }

  @override
  void dispose() {
    _libere = true;
    super.dispose();
  }
}
