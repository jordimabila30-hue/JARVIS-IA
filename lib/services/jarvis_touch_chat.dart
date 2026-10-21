import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/capture_jointe.dart';
import '../models/message_conversation.dart';
import 'capture/fichier_capture.dart';
import 'conversation/conversation_session.dart';
import 'conversations/fournisseur_jarvis.dart';
import 'jarvis_touch_vocal.dart';
import 'voice_session.dart';
import 'ecriture/texte_en_direct.dart';

/// Mini-chat de JARVIS Touch (fenêtre native Android) : une autre vue de
/// LA conversation de l'accueil, jamais une copie. Aucun historique ni
/// moteur ici : les envois passent par [ConversationSession.envoyer]
/// (même file, même IA, même enregistrement), et la fenêtre reçoit
/// seulement ce qu'elle affiche.
///
/// Canal `jarvis/touch_chat` :
/// - natif → Dart : `ouvrir` (instantané), `fermer`, `envoyer`
///   ({texte, idEnvoi}), `plusAnciens` (instantané élargi) ;
/// - Dart → natif : `etat` (instantané, seulement si ce qui est affiché a
///   changé) et `fragment` ({id, texte} du message en réception, au plus
///   toutes les [intervalle]).
///
/// Fenêtre réduite : aucun écouteur, aucun travail.
class PasserelleMiniChat {
  PasserelleMiniChat(
    this._session, {
    VoiceSession? vocal,
    MethodChannel? canal,
    this.taillePage = 40,
    this.intervalle = const Duration(milliseconds: 50),
  }) : _canal = canal ?? const MethodChannel('jarvis/touch_chat') {
    if (vocal != null) _vocal = PasserelleVocalTouch(vocal, _canal);
  }

  /// Vocal flottant (même session vocale que l'accueil), null : absent.
  PasserelleVocalTouch? _vocal;
  PasserelleVocalTouch? get vocal => _vocal;

  final ConversationSession _session;
  final MethodChannel _canal;

  /// Messages envoyés à l'ouverture (puis par page de chargement).
  final int taillePage;

  /// Écart minimal entre deux fragments envoyés à la fenêtre (le réseau
  /// n'est jamais ralenti : seul l'affichage est regroupé).
  final Duration intervalle;

  bool _ouvert = false;
  bool get ouvert => _ouvert;
  late int _fenetre = taillePage;
  int _signature = 0;

  // Réception en cours, suivie seulement pendant que la fenêtre est
  // ouverte.
  TexteEnDirect? _flux;
  int? _idFlux;
  Timer? _cadence;
  bool _fragmentEnAttente = false;
  // Arrivée du plus ancien fragment pas encore affiché (mesure de latence
  // côté fenêtre : regroupement + canal + affichage).
  int? _arrivee;

  // Réponses vues en direct dans la fenêtre : déjà lues, elles s'affichent
  // entières dans l'accueil (pas d'écriture rejouée au retour).
  final _vuesEnDirect = <int>{};

  // Un même envoi (double appui, nouvel essai du canal) ne part qu'une fois.
  final _envois = ListQueue<String>();

  void attacher() => _canal.setMethodCallHandler(_surAppel);

  void detacher() {
    _canal.setMethodCallHandler(null);
    _vocal?.detacher();
    _fermer();
  }

  Future<Object?> _surAppel(MethodCall appel) async {
    final vocal = _vocal?.surAppel(appel);
    if (vocal != null) return vocal;
    switch (appel.method) {
      case 'ouvrir':
        if (!_ouvert) {
          _ouvert = true;
          _fenetre = taillePage;
          _session.addListener(_surSession);
        }
        return _instantane(memoriser: true);
      case 'fermer':
        _fermer();
        return null;
      case 'envoyer':
        final args = Map<Object?, Object?>.from(appel.arguments as Map);
        final texte = (args['texte'] as String? ?? '').trim();
        final idEnvoi = args['idEnvoi'] as String? ?? '';
        if (texte.isEmpty) return false;
        if (idEnvoi.isNotEmpty) {
          if (_envois.contains(idEnvoi)) return true;
          _envois.addLast(idEnvoi);
          if (_envois.length > 32) _envois.removeFirst();
        }
        // Capture validée jointe (fichier du cache privé) : lue UNE fois,
        // ici, au moment de l'envoi voulu par l'utilisateur.
        final chemin = args['image'] as String?;
        if (chemin != null && chemin.isNotEmpty) {
          final octets = await lireCapture(chemin);
          if (octets == null) {
            _envois.remove(idEnvoi);
            return 'capture_indisponible';
          }
          unawaited(
            _session.envoyerAvecCapture(
              texte,
              CaptureJointe(chemin: chemin),
              ImageAEnvoyer('image/png', octets),
            ),
          );
          return true;
        }
        // Même chemin que la barre de l'accueil.
        unawaited(_session.envoyer(texte));
        return true;
      case 'plusAnciens':
        _fenetre += taillePage;
        if (_fenetre > _session.messages.length && _session.plusAnciens) {
          await _session.chargerPlusAnciens();
        }
        return _instantane(memoriser: true);
    }
    throw MissingPluginException(appel.method);
  }

  void _fermer() {
    if (!_ouvert) return;
    _ouvert = false;
    _session.removeListener(_surSession);
    _suivre(null, null);
    _vuesEnDirect.clear();
  }

  void _surSession() {
    if (!_ouvert) return;
    // Réponse vue en direct, maintenant finalisée : rien à rejouer.
    for (final m in _session.messages.reversed.take(3)) {
      if (!m.redaction && _vuesEnDirect.remove(m.id)) {
        m.ecriture?.toutAfficher();
      }
    }
    final s = _signer();
    if (s != _signature) {
      _signature = s;
      _envoyer('etat', _instantane());
    }
    final enCours = _session.messages.isEmpty ? null : _session.messages.last;
    if (enCours != null && enCours.redaction && enCours.ecriture != null) {
      _suivre(enCours.ecriture!.source, enCours.id);
    } else {
      _suivre(null, null);
    }
  }

  /// Ce qui est affiché a-t-il changé ? (Messages remplacés, ajoutés,
  /// conversation changée, réflexion…) Les fragments n'y entrent pas.
  int _signer() {
    final m = _session.messages;
    final debut = m.length > _fenetre ? m.length - _fenetre : 0;
    return Object.hash(
      _session.idCourant,
      _session.enReflexion,
      _session.chargement,
      _session.plusAnciens,
      _fenetre,
      Object.hashAll([
        for (var i = debut; i < m.length; i++) identityHashCode(m[i]),
      ]),
    );
  }

  Map<String, Object?> _instantane({bool memoriser = false}) {
    if (memoriser) _signature = _signer();
    final m = _session.messages;
    final debut = m.length > _fenetre ? m.length - _fenetre : 0;
    final id = _session.idCourant;
    final classe = id == null ? null : _session.classement(id)?.titre;
    return {
      'idConversation': id,
      'titre': m.isEmpty
          ? 'Nouvelle conversation'
          : (classe ?? FournisseurJarvis.titre(m)),
      'plusAnciens': debut > 0 || _session.plusAnciens,
      'reflexion': _session.enReflexion,
      'chargement': _session.chargement,
      'messages': [for (var i = debut; i < m.length; i++) _message(m[i])],
    };
  }

  Map<String, Object?> _message(MessageConversation m) {
    final note = switch (m) {
      _ when m.capture != null => 'Capture d’écran jointe',
      _ when m.pieceJointe != null =>
        'Conversation WhatsApp « ${m.pieceJointe!.titre} » jointe',
      _ when m.ajoutWhatsApp != null => 'Message WhatsApp ajouté',
      _ when m.propositions != null =>
        'Propositions de réponse : ouvrez JARVIS pour les voir.',
      _ when m.choix.isNotEmpty => 'Un choix vous attend dans JARVIS.',
      _ when m.conversation != null && m.texte.trim().isEmpty =>
        'Conversation collée',
      _ => null,
    };
    final texte = m.redaction ? (m.ecriture?.source.texte ?? '') : m.texte;
    return {
      'id': m.id,
      'moi': !m.deJarvis,
      'texte': texte,
      'redaction': m.redaction,
      'incident': ?m.incident,
      'note': ?note,
    };
  }

  // ── Fragments ─────────────────────────────────────────────────────────

  void _suivre(TexteEnDirect? flux, int? id) {
    if (identical(flux, _flux)) return;
    _flux?.removeListener(_surFragment);
    _cadence?.cancel();
    _cadence = null;
    _fragmentEnAttente = false;
    _arrivee = null;
    _flux = flux;
    _idFlux = id;
    if (flux != null && id != null) {
      _vuesEnDirect.add(id);
      flux.addListener(_surFragment);
    }
  }

  void _surFragment() {
    _arrivee ??= DateTime.now().millisecondsSinceEpoch;
    if (_cadence != null) {
      _fragmentEnAttente = true;
      return;
    }
    _envoyerFragment();
    _cadence = Timer(intervalle, _finCadence);
  }

  void _finCadence() {
    _cadence = null;
    if (!_fragmentEnAttente) return;
    _fragmentEnAttente = false;
    _envoyerFragment();
    _cadence = Timer(intervalle, _finCadence);
  }

  void _envoyerFragment() {
    final flux = _flux;
    final id = _idFlux;
    if (flux == null || id == null) return;
    _envoyer('fragment', {'id': id, 'texte': flux.texte, 't': _arrivee});
    _arrivee = null;
  }

  void _envoyer(String methode, Object? arguments) {
    _canal.invokeMethod<void>(methode, arguments).catchError((Object e) {
      // Fenêtre fermée entre-temps : rien à afficher.
      debugPrint('[JARVIS Touch] mini-chat injoignable ($methode)');
    });
  }
}
