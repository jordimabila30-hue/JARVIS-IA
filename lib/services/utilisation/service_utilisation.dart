import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/utilisation/utilisation.dart';
import '../api_jarvis.dart';

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
///  - retour de l'application au premier plan ;
///  - changement de compte ([changerCompte]) ;
///  - fin de session constatée par l'écran ([actualiser]).
/// Jamais d'appel en double : une lecture en cours est partagée, et une
/// lecture de moins de [intervalleMin] n'est pas refaite (sauf `force`).
/// Lire l'utilisation n'appelle jamais l'IA.
class ServiceUtilisation extends ChangeNotifier with WidgetsBindingObserver {
  ServiceUtilisation(
    this._api, {
    DateTime Function()? horloge,
    this.intervalleSuivi = const Duration(seconds: 30),
    this.intervalleMin = const Duration(seconds: 5),
    this.delaiApresConsommation = const Duration(seconds: 2),
  }) : _horloge = horloge ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
  }

  final ApiJarvis _api;
  final DateTime Function() _horloge;
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
  DateTime? miseAJour;

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
    if (!force && derniere != null && _horloge().difference(derniere) < intervalleMin) {
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
    notifyListeners();
    final r = await _api.utilisation();
    if (_ferme || compte != _compte) return;     // compte changé entre-temps
    chargement = false;
    switch (r) {
      case SuccesApi(:final valeur):
        donnees = valeur;
        erreur = null;
        miseAJour = _horloge();
      case EchecApi(:final type):
        erreur = type;
        if (type == ErreurApi.nonConnecte || type == ErreurApi.sessionExpiree) {
          donnees = null;
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
    if (_suivis == 1) {
      _periodique = Timer.periodic(intervalleSuivi, (_) => actualiser(force: true));
    }
    // Appelé depuis initState : la lecture (qui notifie les autres écrans
    // ouverts) part juste après la construction en cours.
    Future.microtask(() => actualiser(force: true));
  }

  /// Un écran Utilisation se ferme.
  void cesserDeSuivre() {
    if (_suivis == 0) return;
    _suivis--;
    if (_suivis == 0) {
      _periodique?.cancel();
      _periodique = null;
    }
  }

  /// Autre compte (ou déconnexion) : rien de l'ancien compte n'est gardé.
  void changerCompte() {
    _compte++;
    _lecture = null;
    donnees = null;
    erreur = null;
    miseAJour = null;
    chargement = false;
    notifyListeners();
    if (suivie) actualiser(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (suivie || donnees != null)) {
      actualiser();
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
