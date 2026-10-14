import 'dart:math' as math;

import 'package:flutter/foundation.dart';
// `characters` (graphèmes Unicode) est fourni par le SDK Flutter.
import 'package:flutter/widgets.dart' show CharacterRange;

import 'texte_en_direct.dart';

/// Révélation progressive d'un texte : quelle partie d'un [TexteEnDirect]
/// est visible à un instant donné.
///
/// Logique pure, pilotée par le temps ([avancer]) : le widget
/// [TexteProgressif] l'anime avec un `Ticker`, les tests avec des durées
/// exactes. Indépendante de l'origine du texte (réponse locale, flux de
/// l'IA, future proposition de réponse dans un ton choisi).
///
/// - Le texte apparaît mot par mot, comme dans ChatGPT, à un rythme posé
///   ([motsParSeconde]) ; les accents, emojis et caractères composés ne
///   sont jamais coupés (un mot s'arrête toujours avant un espace).
/// - Pendant la réception, le dernier mot reçu est retenu tant qu'il n'est
///   pas suivi d'un espace : un fragment suivant peut encore le compléter
///   (« Pizar » + « ro »).
/// - Seules les très longues réponses accélèrent : leur écriture tient en
///   environ [dureeMax] (« Tout afficher » reste proposé).
/// - Les écouteurs ne sont prévenus que lorsque le texte visible change,
///   pas à chaque image.
///
/// La progression est gardée par l'objet : si le widget disparaît (message
/// sorti de l'écran), l'écriture reprend où elle en était.
class EcritureProgressive extends ChangeNotifier {
  EcritureProgressive(TexteEnDirect source) : _source = source {
    source.addListener(_surSource);
    _etatsDerives();
  }

  /// Texte déjà complet, révélé progressivement.
  EcritureProgressive.complet(String texte)
    : this._possede(TexteEnDirect.complet(texte));

  EcritureProgressive._possede(TexteEnDirect source) : _source = source {
    _possedeSource = true;
    source.addListener(_surSource);
    _etatsDerives();
  }

  /// Rythme d'écriture (mots par seconde) : posé, proche de ChatGPT
  /// (une réponse de 100 mots s'écrit en environ 8 s).
  static const motsParSeconde = 12.0;

  /// Durée maximale visée pour écrire une réponse : au-delà de
  /// [motsParSeconde] × [dureeMax] mots, le rythme accélère juste assez.
  static const dureeMax = Duration(seconds: 20);

  /// Lissage des changements de vitesse (pas d'à-coups quand un gros
  /// fragment arrive).
  static const lissage = Duration(milliseconds: 300);

  /// Pas de temps maximal pris en compte en une fois (une image très en
  /// retard ne fait pas apparaître un gros bloc d'un coup).
  static const pasMax = Duration(milliseconds: 100);

  TexteEnDirect _source;
  bool _possedeSource = false;
  bool _arretee = false;

  /// Fin (en unités UTF-16) de la partie visible, toujours sur une
  /// frontière de graphème.
  int _fin = 0;

  /// Texte de la source au dernier calcul (le texte visible en est un
  /// préfixe).
  String _texte = '';
  int _mots = 0;
  bool _aSynchroniser = true;
  String? _visible;

  double _vitesse = 0;
  double _credit = 0;
  double _depuisNotification = double.infinity;

  /// Afficher sans animation (préférence « réduire les animations ») : le
  /// texte reçu est visible aussitôt.
  bool get immediat => _immediat;
  bool _immediat = false;
  set immediat(bool valeur) {
    if (valeur == _immediat) return;
    _immediat = valeur;
    if (valeur) toutAfficher();
  }

  /// Écriture en pause (texte hors de la vue : l'utilisateur relit plus
  /// haut). La réception continue dans le tampon ; l'écriture reprend où
  /// elle en était dès que la pause est levée.
  bool get suspendue => _suspendue;
  bool _suspendue = false;
  set suspendue(bool valeur) {
    if (valeur == _suspendue) return;
    _suspendue = valeur;
    _vitesse = 0;
    _credit = 0;
    // Reprise : le widget relance son animation.
    if (!valeur && !_arretee) notifyListeners();
  }

  /// Source du texte (réception).
  TexteEnDirect get source => _source;

  /// État de la réception.
  EtatReception get reception => _source.etat;

  /// Partie visible du texte.
  String get visible {
    _synchroniser();
    return _visible ??= _texte.substring(0, _fin);
  }

  /// Tout le texte reçu jusqu'ici est visible.
  bool get toutVisible {
    _synchroniser();
    return _fin >= _limite;
  }

  /// Il reste du texte reçu à révéler : l'animation doit tourner.
  bool get enMouvement => !_arretee && !_suspendue && !toutVisible;

  /// Réception finie et tout le texte visible : l'écriture est terminée
  /// (l'indicateur d'écriture disparaît).
  bool get termine => _arretee || (!_source.enCours && toutVisible);

  /// Vrai quand passe à vrai : [termine] (une seule notification, pour les
  /// éléments qui n'apparaissent qu'à la fin de l'écriture).
  ValueListenable<bool> get finie => _finie;
  late final _finie = ValueNotifier<bool>(termine);

  /// Du texte reçu attend d'être révélé, assez pour qu'un « Tout afficher »
  /// soit utile (jamais pour une réponse courte qui se termine aussitôt).
  ValueListenable<bool> get rattrapable => _rattrapable;
  final _rattrapable = ValueNotifier<bool>(false);

  /// Seuil (unités UTF-16) au-delà duquel « Tout afficher » est proposé.
  static const seuilRattrapage = 160;

  // Limite révélable : pendant la réception, le texte s'arrête au dernier
  // espace reçu (le mot qui suit peut encore être complété).
  int get _limite {
    if (!_source.enCours) return _texte.length;
    for (var i = _texte.length - 1; i >= 0; i--) {
      if (_estSeparateur(_texte.codeUnitAt(i))) return i;
    }
    return 0;
  }

  /// Espace, retour à la ligne, tabulation (l'espace insécable reste dans
  /// le mot : « soir : » apparaît d'un bloc).
  static bool _estSeparateur(int c) =>
      c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0D;

  static final _motRegExp = RegExp(r'\S+');

  /// Fin de la partie visible après [n] mots de plus (jamais au-delà de
  /// [limite]).
  int _apresMots(int depuis, int n, int limite) {
    var i = depuis;
    for (var k = 0; k < n && i < limite; k++) {
      while (i < limite && _estSeparateur(_texte.codeUnitAt(i))) {
        i++;
      }
      while (i < limite && !_estSeparateur(_texte.codeUnitAt(i))) {
        i++;
      }
    }
    return i;
  }

  void _surSource() {
    if (_arretee) return;
    _aSynchroniser = true;
    _visible = null;
    if (_immediat) {
      _synchroniser();
      _fin = _limite;
    }
    _etatsDerives();
    // Prévient le widget : du texte arrive (animation à relancer), ou la
    // réception est finie.
    notifyListeners();
  }

  /// Relit le texte de la source. S'il ne prolonge plus la partie visible
  /// (mise en forme qui a changé en amont), la partie visible est ramenée
  /// au plus long début commun, sur une frontière de graphème.
  void _synchroniser() {
    if (!_aSynchroniser) return;
    _aSynchroniser = false;
    final nouveau = _source.texte;
    if (_fin > 0 && !nouveau.startsWith(_texte.substring(0, _fin))) {
      var commun = 0;
      final n = math.min(_fin, nouveau.length);
      while (commun < n &&
          nouveau.codeUnitAt(commun) == _texte.codeUnitAt(commun)) {
        commun++;
      }
      _fin = commun == 0
          ? 0
          : CharacterRange.at(nouveau, commun).stringBeforeLength;
    }
    _texte = nouveau;
    _mots = _motRegExp.allMatches(nouveau).length;
    _fin = math.min(_fin, _texte.length);
    _visible = null;
  }

  /// Fait avancer l'écriture de [ecoule] (temps depuis l'appel précédent).
  void avancer(Duration ecoule) {
    if (_arretee || _suspendue) return;
    _synchroniser();
    final limite = _limite;
    if (_fin >= limite) {
      _vitesse = 0;
      _credit = 0;
      _etatsDerives();
      return;
    }
    final s =
        math.min(ecoule.inMicroseconds, pasMax.inMicroseconds) /
        Duration.microsecondsPerSecond;
    if (s <= 0) return;
    final dureeS = dureeMax.inMicroseconds / Duration.microsecondsPerSecond;
    final cible = math.max(motsParSeconde, _mots / dureeS);
    final lissageS = lissage.inMicroseconds / Duration.microsecondsPerSecond;
    _vitesse = _vitesse == 0
        ? cible
        : _vitesse + (cible - _vitesse) * math.min(1.0, s / lissageS);
    _credit += _vitesse * s;
    _depuisNotification += s;
    final n = _credit.floor();
    if (n < 1 || _depuisNotification < _intervalle) return;
    _credit -= n;
    _fin = _apresMots(_fin, n, limite);
    _visible = null;
    _depuisNotification = 0;
    _etatsDerives();
    notifyListeners();
  }

  /// Intervalle minimal entre deux mises à jour visibles (une très longue
  /// réponse accélérée regroupe ses mots : sa mise en page coûte plus cher).
  double get _intervalle => _fin > 2000 ? 1 / 32 : 1 / 64;

  /// Affiche aussitôt tout le texte déjà reçu. La réception continue : les
  /// fragments suivants s'afficheront normalement.
  void toutAfficher() {
    if (_arretee) return;
    _synchroniser();
    final limite = _source.enCours ? _limite : _texte.length;
    if (_fin == limite) return;
    _fin = limite;
    _visible = null;
    _credit = 0;
    _etatsDerives();
    notifyListeners();
  }

  /// Remplace le texte (nouvelle proposition à la place de la précédente) :
  /// l'animation précédente est annulée et repart de zéro sur [nouvelle],
  /// sans jamais mélanger les deux textes.
  void remplacer(TexteEnDirect nouvelle) {
    if (identical(nouvelle, _source)) return;
    _source.removeListener(_surSource);
    if (_possedeSource) _source.dispose();
    _source = nouvelle;
    _possedeSource = false;
    _arretee = false;
    _fin = 0;
    _texte = '';
    _aSynchroniser = true;
    _visible = null;
    _vitesse = 0;
    _credit = 0;
    _depuisNotification = double.infinity;
    nouvelle.addListener(_surSource);
    if (_immediat) toutAfficher();
    _etatsDerives();
    notifyListeners();
  }

  /// Remplace le texte par un texte déjà complet.
  void remplacerPar(String texte) {
    remplacer(TexteEnDirect.complet(texte));
    _possedeSource = true;
  }

  /// Arrête l'écriture (message retiré, conversation fermée) : la source
  /// n'est plus suivie, plus aucune notification.
  void arreter() {
    if (_arretee) return;
    _arretee = true;
    _source.removeListener(_surSource);
  }

  void _etatsDerives() {
    _synchroniser();
    _finie.value = termine;
    _rattrapable.value =
        !_arretee &&
        !termine &&
        (_limite - _fin >= seuilRattrapage ||
            (_rattrapable.value && _fin < _limite));
  }

  @override
  void dispose() {
    arreter();
    if (_possedeSource) _source.dispose();
    _finie.dispose();
    _rattrapable.dispose();
    super.dispose();
  }
}
