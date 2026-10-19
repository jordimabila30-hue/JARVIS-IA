import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/voice_state.dart';
import 'voice_session.dart';

/// Vocal flottant de JARVIS Touch : la fenêtre native pilote LA session
/// vocale de l'application ([VoiceSession], celle de l'accueil) : même
/// reconnaissance, même voix, même conversation (`repondeur` de l'accueil),
/// donc les échanges s'écrivent dans l'historique comme en mode vocal
/// principal. Aucun second moteur, aucune seconde session.
///
/// Canal `jarvis/touch_chat` (partagé avec le mini-chat) :
/// - natif → Dart : `vocalOuvrir`, `vocalMicro` (couper / réactiver),
///   `vocalQuitter` (fin réelle : micro et voix libérés), `vocalFermer`
///   (fenêtre fermée : écoute suspendue, chat reprenable) ;
/// - Dart → natif : `vocal` (état, quelques fois par phrase) et `niveau`
///   (amplitude réelle, au plus ~16 fois par seconde, seulement fenêtre
///   ouverte).
class PasserelleVocalTouch {
  PasserelleVocalTouch(this._session, this._canal);

  final VoiceSession _session;
  final MethodChannel _canal;

  bool _ouverte = false;
  Timer? _cadence;
  double? _niveauEnAttente;
  String _dernierEtat = '';

  /// Méthodes `vocal…` reçues du natif (null : pas pour le vocal).
  Future<Object?>? surAppel(MethodCall appel) {
    switch (appel.method) {
      case 'vocalOuvrir':
        return _ouvrir();
      case 'vocalMicro':
        return _micro();
      case 'vocalQuitter':
        return _quitter();
      case 'vocalFermer':
        return _fermer();
      // L'état suit par `vocal` (poussé dans l'ordre) : jamais renvoyé ici,
      // une réponse arrivée après lui afficherait un état périmé.
      case 'vocalArreterParole':
        return _session.arreterParole().then((_) => null);
    }
    return null;
  }

  Future<Object?> _ouvrir() async {
    if (!_ouverte) {
      _ouverte = true;
      _session.addListener(_surSession);
      _session.amplitude.addListener(_surNiveau);
    }
    // Une seule session : déjà active (accueil ou bulle), on la rejoint.
    if (!_session.actif) unawaited(_session.demarrer());
    return _etat();
  }

  Future<Object?> _micro() async {
    if (_session.actif) {
      await _session.mettreEnArrierePlan();
    } else {
      unawaited(_session.demarrer());
    }
    return _etat();
  }

  Future<Object?> _quitter() async {
    _detacher();
    await _session.quitterChatVocal();
    return null;
  }

  /// JARVIS revenu au premier plan, service arrêté : écoute suspendue
  /// (jamais un micro ouvert sans fenêtre visible), chat reprenable.
  Future<Object?> _fermer() async {
    _detacher();
    if (_session.actif) await _session.mettreEnArrierePlan();
    return null;
  }

  void _detacher() {
    if (!_ouverte) return;
    _ouverte = false;
    _session.removeListener(_surSession);
    _session.amplitude.removeListener(_surNiveau);
    _cadence?.cancel();
    _cadence = null;
    _niveauEnAttente = null;
  }

  void detacher() => _detacher();

  Map<String, Object?> _etat() => {
    'etat': switch (_session.etat) {
      VoiceState.listening => 'ecoute',
      VoiceState.thinking => 'reflexion',
      VoiceState.speaking => 'parole',
      VoiceState.idle => 'repos',
    },
    'actif': _session.actif,
    'statut': _session.statut,
    'transcription': _session.transcription,
    'reponse': _session.reponse,
    'probleme': _session.probleme?.message,
  };

  void _surSession() {
    if (!_ouverte) return;
    final e = _etat();
    final signature = e.toString();
    if (signature == _dernierEtat) return;
    _dernierEtat = signature;
    _envoyer('vocal', e);
  }

  /// Amplitude réelle (micro ou voix de JARVIS), regroupée : jamais un
  /// message par image.
  void _surNiveau() {
    _niveauEnAttente = _session.amplitude.value;
    if (_cadence != null) return;
    _cadence = Timer(const Duration(milliseconds: 60), () {
      _cadence = null;
      final n = _niveauEnAttente;
      _niveauEnAttente = null;
      if (n != null && _ouverte) _envoyer('niveau', n);
    });
  }

  void _envoyer(String methode, Object? donnees) {
    _canal.invokeMethod<void>(methode, donnees).catchError((Object e) {
      debugPrint('[JARVIS Touch] vocal : $e');
    });
  }
}
