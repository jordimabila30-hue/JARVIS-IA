import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/apprentissage/tuteur.dart';
import '../api_jarvis.dart';

/// Appel du tuteur (`ApiJarvis.tuteur`), injectable pour les tests.
typedef AppelTuteur =
    Future<ResultatApi<ReponseTuteur>> Function(
      DemandeTuteur demande, {
      Future<void>? annulation,
      void Function(String fragment)? surFragment,
    });

enum EtatTuteur { attente, enCours, termine, erreur }

/// Une demande au tuteur, affichée en direct : texte reçu par fragments,
/// sources validées seulement à la fin, annulation (la requête est
/// abandonnée ; rien n'est relancé tout seul), erreur claire.
class SessionTuteur extends ChangeNotifier {
  SessionTuteur(this._appel);

  /// Null : sans compte (le professeur IA demande une connexion).
  final AppelTuteur? _appel;

  EtatTuteur _etat = EtatTuteur.attente;
  EtatTuteur get etat => _etat;

  final _texte = StringBuffer();
  String get texte => _texte.toString();

  List<SourceTuteur> _sources = const [];
  List<SourceTuteur> get sources => _sources;

  String? _erreur;
  String? get erreur => _erreur;

  bool _memeVersion = true;

  /// Corpus de l'appli différent de celui du serveur (mise à jour à faire).
  bool get versionDifferente => !_memeVersion;

  Completer<void>? _annulation;
  DemandeTuteur? _derniere;
  int _tour = 0;
  bool _fermee = false;

  static const sansCompte =
      'Le professeur IA demande une connexion à votre compte. '
      'Les leçons et exercices restent disponibles hors ligne.';

  Future<void> demander(DemandeTuteur demande) async {
    annuler();
    _derniere = demande;
    final tour = ++_tour;
    _texte.clear();
    _sources = const [];
    _erreur = null;
    final appel = _appel;
    if (appel == null) {
      _etat = EtatTuteur.erreur;
      _erreur = sansCompte;
      _notifier();
      return;
    }
    _etat = EtatTuteur.enCours;
    _notifier();
    final annulation = _annulation = Completer<void>();
    final r = await appel(
      demande,
      annulation: annulation.future,
      surFragment: (f) {
        if (tour != _tour) return;
        _texte.write(f);
        _notifier();
      },
    );
    if (tour != _tour || _fermee) return;
    _annulation = null;
    switch (r) {
      case SuccesApi(:final valeur):
        _texte
          ..clear()
          ..write(valeur.texte);
        _sources = valeur.sources;
        _memeVersion = valeur.memeVersion;
        _etat = EtatTuteur.termine;
      case EchecApi(type: final erreur, :final detail):
        _etat = EtatTuteur.erreur;
        _erreur =
            erreur == ErreurApi.injoignable ||
                erreur == ErreurApi.fluxInterrompu
            ? 'Le professeur IA demande Internet. Réessayez une fois connecté.'
            : (detail ?? erreur.message);
    }
    _notifier();
  }

  /// Nouvel essai de la même demande (après une panne).
  Future<void> reessayer() async {
    final d = _derniere;
    if (d != null) await demander(d);
  }

  /// Arrête la réponse en cours : requête abandonnée, texte reçu gardé.
  void annuler() {
    final a = _annulation;
    if (a == null) return;
    _annulation = null;
    _tour++;
    if (!a.isCompleted) a.complete();
    if (_etat == EtatTuteur.enCours) {
      _etat = _texte.isEmpty ? EtatTuteur.attente : EtatTuteur.termine;
      _notifier();
    }
  }

  void _notifier() {
    if (!_fermee) notifyListeners();
  }

  @override
  void dispose() {
    annuler();
    _fermee = true;
    super.dispose();
  }
}
