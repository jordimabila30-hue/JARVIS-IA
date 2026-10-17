import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'voice_settings_service.dart';

/// État de JARVIS Touch tel qu'il est réellement (jamais « actif » si la
/// bulle n'a pas pu s'afficher).
enum EtatJarvisTouch {
  /// Bulle absente.
  desactive,

  /// Réglages Android ouverts : on attend le retour de l'utilisateur.
  attenteAutorisation,

  /// Service lancé, confirmation de la bulle attendue.
  demarrage,

  /// Bulle affichée.
  actif,
}

/// Accès au module natif (canal `jarvis/touch`). Séparé pour les tests.
abstract class PlateformeJarvisTouch {
  Future<bool> autorisationAccordee();
  Future<void> demanderAutorisation();

  /// Vrai si la bulle est affichée ; sinon une [PlatformException]
  /// explique l'échec.
  Future<bool> demarrer();
  Future<void> arreter();
  Future<bool> estActif();
}

class PlateformeJarvisTouchAndroid implements PlateformeJarvisTouch {
  const PlateformeJarvisTouchAndroid();

  static const _canal = MethodChannel('jarvis/touch');

  @override
  Future<bool> autorisationAccordee() async =>
      await _canal.invokeMethod<bool>('autorisationAccordee') ?? false;

  @override
  Future<void> demanderAutorisation() =>
      _canal.invokeMethod<void>('demanderAutorisation');

  @override
  Future<bool> demarrer() async =>
      await _canal.invokeMethod<bool>('demarrer') ?? false;

  @override
  Future<void> arreter() => _canal.invokeMethod<void>('arreter');

  @override
  Future<bool> estActif() async =>
      await _canal.invokeMethod<bool>('estActif') ?? false;
}

/// JARVIS Touch : bulle flottante au-dessus des autres applications
/// (Android seulement pour l'instant). Le choix de l'utilisateur est
/// enregistré sur l'appareil ; l'état affiché suit toujours l'état réel du
/// service et de l'autorisation, relus au retour au premier plan.
class JarvisTouchService extends ChangeNotifier with WidgetsBindingObserver {
  JarvisTouchService({
    PlateformeJarvisTouch? plateforme,
    StockageReglages? stockage,
    bool? disponible,
  }) : _plateforme = plateforme ?? const PlateformeJarvisTouchAndroid(),
       _stockage = stockage ?? const StockagePreferences(cle: cleStockage),
       disponible =
           disponible ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// Service unique de l'application (une seule bulle native).
  static final instance = JarvisTouchService();

  static const cleStockage = 'jarvis.touch_active';

  final PlateformeJarvisTouch _plateforme;
  final StockageReglages _stockage;

  /// Faux sur le Web, Windows, iOS… : le réglage n'est pas proposé.
  final bool disponible;

  EtatJarvisTouch get etat => _etat;
  EtatJarvisTouch _etat = EtatJarvisTouch.desactive;

  bool get actif => _etat == EtatJarvisTouch.actif;
  bool get occupe =>
      _etat == EtatJarvisTouch.demarrage ||
      _etat == EtatJarvisTouch.attenteAutorisation;

  /// Explication simple du dernier échec (autorisation refusée…), effacée
  /// au prochain changement.
  String? get message => _message;
  String? _message;

  bool _souhaite = false;
  bool _observe = false;

  static const refus =
      'Autorisation refusée : JARVIS Touch a besoin de « Afficher par-dessus '
      'les autres applis » pour placer sa bulle sur l’écran.';

  /// Au lancement : relit le choix enregistré et rallume la bulle si elle
  /// était activée (et toujours autorisée).
  Future<void> restaurer() async {
    if (!disponible) return;
    _observer();
    try {
      _souhaite = await _stockage.lire() == 'oui';
    } catch (e) {
      debugPrint('[JARVIS Touch] préférence illisible : $e');
    }
    await synchroniser();
  }

  /// Interrupteur des Paramètres.
  Future<void> choisir(bool oui) => oui ? activer() : desactiver();

  Future<void> activer() async {
    if (!disponible || occupe) return;
    _observer();
    _message = null;
    if (!await _autorise()) {
      _changer(EtatJarvisTouch.attenteAutorisation);
      try {
        await _plateforme.demanderAutorisation();
      } catch (e) {
        _echec('Impossible d’ouvrir les réglages d’Android ($e).');
      }
      // La suite au retour dans JARVIS (didChangeAppLifecycleState).
      return;
    }
    await _demarrer();
  }

  Future<void> desactiver() async {
    if (!disponible) return;
    _message = null;
    _souhaite = false;
    await _enregistrer();
    try {
      await _plateforme.arreter();
    } catch (e) {
      debugPrint('[JARVIS Touch] arrêt : $e');
    }
    _changer(EtatJarvisTouch.desactive);
  }

  /// Aligne l'état affiché sur la réalité : autorisation retirée, service
  /// arrêté par le système, retour des réglages d'Android.
  Future<void> synchroniser() async {
    if (!disponible) return;
    if (_etat == EtatJarvisTouch.attenteAutorisation) {
      // Certains Android annoncent l'autorisation avec un léger retard.
      var oui = await _autorise();
      if (!oui) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        oui = await _autorise();
      }
      if (oui) {
        await _demarrer();
      } else {
        _echec(refus);
      }
      return;
    }
    if (_etat == EtatJarvisTouch.demarrage) return;
    bool enMarche = false;
    try {
      enMarche = await _plateforme.estActif();
    } catch (_) {}
    if (enMarche) {
      if (!await _autorise()) {
        await _plateforme.arreter();
        _echec('Autorisation retirée : la bulle a été masquée.');
        return;
      }
      _changer(EtatJarvisTouch.actif);
    } else if (_souhaite) {
      if (await _autorise()) {
        await _demarrer();
      } else {
        _echec(
          'Autorisation retirée : réactivez JARVIS Touch pour la '
          'redemander.',
        );
      }
    } else {
      _changer(EtatJarvisTouch.desactive);
    }
  }

  Future<void> _demarrer() async {
    _changer(EtatJarvisTouch.demarrage);
    try {
      if (await _plateforme.demarrer()) {
        _souhaite = true;
        await _enregistrer();
        _message = null;
        _changer(EtatJarvisTouch.actif);
        return;
      }
      _echec('La bulle n’a pas pu s’afficher.');
    } on PlatformException catch (e) {
      _echec(e.message ?? 'La bulle n’a pas pu s’afficher.');
    } catch (e) {
      _echec('La bulle n’a pas pu s’afficher ($e).');
    }
  }

  void _echec(String message) {
    _message = message;
    _souhaite = false;
    _enregistrer();
    _changer(EtatJarvisTouch.desactive);
  }

  Future<bool> _autorise() async {
    try {
      return await _plateforme.autorisationAccordee();
    } catch (_) {
      return false;
    }
  }

  Future<void> _enregistrer() async {
    try {
      await _stockage.ecrire(_souhaite ? 'oui' : 'non');
    } catch (e) {
      debugPrint('[JARVIS Touch] préférence non enregistrée : $e');
    }
  }

  void _changer(EtatJarvisTouch e) {
    _etat = e;
    notifyListeners();
  }

  void _observer() {
    if (_observe) return;
    _observe = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) synchroniser();
  }

  @override
  void dispose() {
    if (_observe) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
