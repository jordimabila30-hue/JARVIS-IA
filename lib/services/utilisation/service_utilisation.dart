import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/utilisation/utilisation.dart';
import '../api_jarvis.dart';
import 'cache_utilisation.dart';

/// Utilisation de l'IA du compte connecté : lit `GET /me/quota` (le
/// serveur calcule tout d'après Supabase) et décide QUAND relire. Aucune
/// règle de quota ici, aucune valeur inventée.
///
/// Actualisation :
///  - ouverture du panneau ou de la page Utilisation ([suivre]) ;
///  - toutes les [intervalleSuivi] tant qu'un écran Utilisation est ouvert
///    (le serveur met les limites en cache 30 s : inutile de lire plus
///    souvent) ;
///  - après une opération IA terminée, interrompue ou refusée (quota
///    dépassé compris) : [signalerConsommation], différée de
///    [delaiApresConsommation] (le serveur enregistre la consommation juste
///    APRÈS la fin du flux) ;
///  - retour de l'application au premier plan (la relecture périodique est
///    suspendue quand l'application est masquée, reprise au retour) ;
///  - changement de compte ([changerCompte]) ;
///  - fin de session constatée par l'écran ([actualiser]).
/// Jamais d'appel en double : une lecture en cours est partagée, et une
/// lecture de moins de [intervalleMin] n'est pas refaite (sauf `force`).
/// Invisible : seule la toute première lecture annonce un chargement ; les
/// suivantes remplacent les valeurs sans état intermédiaire, et un échec
/// garde les dernières valeurs connues ([erreur] les signale).
///
/// Affichage immédiat : la dernière lecture réussie est gardée sur
/// l'appareil ([CacheUtilisation], rattachée au compte) et rechargée dès
/// que le compte est connu ([changerCompte]) ; l'écran l'affiche aussitôt
/// ([depuisCache]) puis la remplace en silence par la réponse du serveur.
/// Une copie d'une journée terminée ([journeeTerminee]) n'est jamais
/// présentée comme la consommation du jour. Copie d'affichage seulement :
/// le serveur seul décide des quotas.
/// Lire l'utilisation n'appelle jamais l'IA.
class ServiceUtilisation extends ChangeNotifier with WidgetsBindingObserver {
  ServiceUtilisation(
    this._api, {
    DateTime Function()? horloge,
    this.intervalleSuivi = const Duration(seconds: 30),
    this.intervalleMin = const Duration(seconds: 5),
    this.delaiApresConsommation = const Duration(seconds: 2),
    CacheUtilisation? cache,
  }) : _horloge = horloge ?? DateTime.now,
       _cache = cache ?? CacheUtilisation() {
    WidgetsBinding.instance.addObserver(this);
  }

  final ApiJarvis _api;
  final DateTime Function() _horloge;
  final CacheUtilisation _cache;
  final Duration intervalleSuivi;
  final Duration intervalleMin;
  final Duration delaiApresConsommation;

  /// Dernière utilisation reçue du serveur (null : jamais lue, ou compte
  /// changé / déconnecté).
  Utilisation? donnees;

  /// Échec de la dernière lecture (les [donnees] précédentes restent
  /// affichées, datées de [miseAJour]).
  ErreurApi? erreur;
  bool chargement = false;

  /// Dernière lecture réussie au serveur (y compris celle de la copie
  /// locale affichée).
  DateTime? miseAJour;

  /// [donnees] viennent de la copie locale, pas encore confirmées par le
  /// serveur depuis l'ouverture de JARVIS.
  bool depuisCache = false;

  /// [donnees] appartiennent à une journée terminée (remise à zéro passée,
  /// serveur pas encore relu) : la consommation du jour est inconnue.
  bool get journeeTerminee {
    final fin = donnees?.finJour;
    return fin != null && !_horloge().isBefore(fin);
  }

  /// Compte connecté (identifiant), pour la copie locale ; null : aucune.
  String? _compteId;

  int _suivis = 0;
  int _compte = 0;
  bool _ferme = false;
  Timer? _periodique;
  Timer? _differe;
  Future<void>? _lecture;

  bool get suivie => _suivis > 0;

  /// Relit l'utilisation (rien si une lecture récente ou en cours, sauf
  /// [force] : la lecture en cours est alors attendue puis refaite).
  Future<void> actualiser({bool force = false}) async {
    if (_ferme) return;
    final enCours = _lecture;
    if (enCours != null) {
      await enCours;
      if (!force) return;
    }
    final derniere = miseAJour;
    if (!force &&
        derniere != null &&
        _horloge().difference(derniere) < intervalleMin) {
      return;
    }
    final lecture = _lire();
    _lecture = lecture;
    try {
      await lecture;
    } finally {
      if (identical(_lecture, lecture)) _lecture = null;
    }
  }

  Future<void> _lire() async {
    final compte = _compte;
    chargement = true;
    // Valeurs déjà affichées : rien à annoncer (pas de chargement visible).
    if (donnees == null) notifyListeners();
    final r = await _api.utilisation();
    if (_ferme || compte != _compte) return; // compte changé entre-temps
    chargement = false;
    switch (r) {
      case SuccesApi(:final valeur):
        donnees = valeur;
        erreur = null;
        depuisCache = false;
        final lu = miseAJour = _horloge();
        final id = _compteId;
        if (id != null) unawaited(_cache.ecrire(id, valeur, lu));
      case EchecApi(:final type):
        erreur = type;
        if (type == ErreurApi.nonConnecte || type == ErreurApi.sessionExpiree) {
          donnees = null;
          depuisCache = false;
        }
    }
    notifyListeners();
  }

  /// Une opération IA vient de se terminer (ou d'être refusée).
  void signalerConsommation() {
    if (_ferme) return;
    _differe?.cancel();
    _differe = Timer(delaiApresConsommation, () => actualiser(force: true));
  }

  /// Un écran Utilisation s'ouvre : lecture immédiate, puis périodique.
  void suivre() {
    _suivis++;
    if (_suivis == 1) _demarrerPeriodique();
    // Appelé depuis initState : la lecture (qui notifie les autres écrans
    // ouverts) part juste après la construction en cours.
    Future.microtask(() => actualiser(force: true));
  }

  void _demarrerPeriodique() {
    _periodique?.cancel();
    _periodique = Timer.periodic(
      intervalleSuivi,
      (_) => actualiser(force: true),
    );
  }

  void _arreterPeriodique() {
    _periodique?.cancel();
    _periodique = null;
  }

  /// Un écran Utilisation se ferme.
  void cesserDeSuivre() {
    if (_suivis == 0) return;
    _suivis--;
    if (_suivis == 0) _arreterPeriodique();
  }

  /// Autre compte (ou déconnexion) : rien de l'ancien compte n'est gardé.
  /// [compte] (identifiant du compte connecté) : sa copie locale est
  /// rechargée aussitôt ; null (déconnexion) : la copie est effacée.
  void changerCompte([String? compte]) {
    _compte++;
    _lecture = null;
    donnees = null;
    erreur = null;
    miseAJour = null;
    depuisCache = false;
    chargement = false;
    final ancien = _compteId;
    _compteId = compte;
    if (compte != null) {
      _chargerCopie(compte, _compte);
    } else if (ancien != null) {
      unawaited(_cache.effacer());
    }
    notifyListeners();
    if (suivie) actualiser(force: true);
  }

  Future<void> _chargerCopie(String compte, int jeton) async {
    final copie = await _cache.lire(compte);
    // Compte changé entre-temps, ou serveur déjà lu (plus récent) : ignorée.
    if (copie == null || _ferme || jeton != _compte || donnees != null) return;
    donnees = copie.utilisation;
    miseAJour = copie.luLe;
    depuisCache = true;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (suivie) _demarrerPeriodique();
        if (suivie || donnees != null) actualiser();
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _arreterPeriodique(); // écran invisible : aucune relecture
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    _ferme = true;
    _periodique?.cancel();
    _differe?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
