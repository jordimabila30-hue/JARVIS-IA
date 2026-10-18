import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/integrations/etat_gmail.dart';
import '../api_jarvis.dart';

/// Ouvre une adresse dans le navigateur du SYSTÈME (jamais une vue web
/// intégrée : règles OAuth de Google). Faux dans les tests.
typedef OuvrirUrl = Future<bool> Function(Uri url);

Future<bool> ouvrirDansLeNavigateur(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');

/// Plateforme annoncée au serveur (page de retour adaptée : retour
/// automatique dans l'application sur Android).
String plateformeCourante() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.windows => 'windows',
    TargetPlatform.iOS => 'ios',
    _ => 'autre',
  };
}

/// Connexion Gmail du compte JARVIS (lecture seule).
///
/// La connexion se fait dans le navigateur, chez Google (choix du compte,
/// consentement) ; le serveur garde les jetons. L'application suit
/// seulement l'état : après l'ouverture de Google, elle relit l'état toutes
/// les [intervalleAttente] (au plus [attenteMax]) et au retour au premier
/// plan, jusqu'à constater le changement.
class ServiceGmail extends ChangeNotifier with WidgetsBindingObserver {
  ServiceGmail(
    this._api, {
    OuvrirUrl? ouvrir,
    String? plateforme,
    this.intervalleAttente = const Duration(seconds: 3),
    this.attenteMax = const Duration(minutes: 3),
  }) : _ouvrir = ouvrir ?? ouvrirDansLeNavigateur,
       _plateforme = plateforme ?? plateformeCourante() {
    WidgetsBinding.instance.addObserver(this);
  }

  final ApiJarvis _api;
  final OuvrirUrl _ouvrir;
  final String _plateforme;
  final Duration intervalleAttente;
  final Duration attenteMax;

  EtatGmail? etat;
  ErreurApi? erreur;
  bool chargement = false;

  /// Google est ouvert dans le navigateur : l'application attend le retour.
  bool enAttente = false;

  /// Message ponctuel (connexion annulée, ouverture impossible…).
  String? information;

  Timer? _sondage;
  DateTime? _finAttente;
  EtatGmail? _avant;
  bool _ferme = false;
  int _compte = 0;

  Future<void> actualiser() async {
    if (_ferme) return;
    final compte = _compte;
    final premiere = etat == null;
    chargement = true;
    if (premiere) notifyListeners();
    final r = await _api.etatGmail();
    if (_ferme || compte != _compte) return;
    chargement = false;
    switch (r) {
      case SuccesApi(:final valeur):
        etat = valeur;
        erreur = null;
        if (enAttente && _change(valeur)) _terminerAttente();
      case EchecApi(:final type):
        erreur = type;
    }
    notifyListeners();
  }

  bool _change(EtatGmail neuf) {
    final avant = _avant;
    if (neuf.statut != StatutGmail.connecte) return false;
    return avant == null ||
        avant.statut != StatutGmail.connecte ||
        avant.email != neuf.email ||
        avant.connecteLe != neuf.connecteLe;
  }

  /// « Choisir un compte Google », « Changer de compte », « Reconnecter » :
  /// toujours un nouveau consentement complet chez Google.
  Future<void> connecter() async {
    information = null;
    final r = await _api.urlConnexionGmail(_plateforme);
    if (_ferme) return;
    switch (r) {
      case EchecApi(:final type):
        erreur = type;
        information = type == ErreurApi.indisponible
            ? 'Gmail n’est pas encore configuré sur ce serveur JARVIS.'
            : 'Impossible de préparer la connexion Google. Réessayez.';
        notifyListeners();
        return;
      case SuccesApi(:final valeur):
        final ouvert = await _ouvrir(Uri.parse(valeur));
        if (_ferme) return;
        if (!ouvert) {
          information = 'Le navigateur n’a pas pu s’ouvrir.';
          notifyListeners();
          return;
        }
        _avant = etat;
        enAttente = true;
        _finAttente = DateTime.now().add(attenteMax);
        _sondage?.cancel();
        _sondage = Timer.periodic(intervalleAttente, (_) {
          if (_finAttente != null && DateTime.now().isAfter(_finAttente!)) {
            _terminerAttente();
            information = 'Connexion non terminée. Vous pouvez réessayer.';
            notifyListeners();
            return;
          }
          actualiser();
        });
        notifyListeners();
    }
  }

  /// Arrête d'attendre (bouton « Annuler » pendant l'attente).
  void annulerAttente() {
    _terminerAttente();
    notifyListeners();
  }

  void _terminerAttente() {
    enAttente = false;
    _sondage?.cancel();
    _sondage = null;
    _finAttente = null;
  }

  Future<bool> deconnecter() async {
    final r = await _api.deconnecterGmail();
    if (_ferme) return false;
    if (r case SuccesApi()) {
      etat = const EtatGmail(statut: StatutGmail.nonConnecte);
      erreur = null;
      information = null;
      notifyListeners();
      return true;
    }
    information = 'La déconnexion a échoué. Réessayez.';
    notifyListeners();
    return false;
  }

  /// Autre compte JARVIS (ou déconnexion) : rien de l'ancien compte.
  void changerCompte() {
    _compte++;
    _terminerAttente();
    etat = null;
    erreur = null;
    information = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour depuis le navigateur (Windows, Web) : état relu aussitôt.
    if (state == AppLifecycleState.resumed && (enAttente || etat != null)) actualiser();
  }

  @override
  void dispose() {
    _ferme = true;
    _terminerAttente();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
