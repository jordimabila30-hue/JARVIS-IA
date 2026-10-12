import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'reconnaissance_navigateur.dart';
import 'speech_recognition_service.dart';

// Chrome et Edge n'exposent la reconnaissance que sous le nom préfixé.
@JS('webkitSpeechRecognition')
extension type _ReconnaissanceWebkit._(web.SpeechRecognition _)
    implements web.SpeechRecognition {
  external factory _ReconnaissanceWebkit();
}

ReconnaissanceNavigateur? creerReconnaissanceNavigateur() =>
    _ReconnaissanceWeb();

class _ReconnaissanceWeb implements ReconnaissanceNavigateur {
  web.SpeechRecognition? _courante;

  // Chaque écoute a son numéro : les événements d'une écoute annulée sont
  // ignorés.
  int _numero = 0;

  bool get _webkit =>
      web.window.hasProperty('webkitSpeechRecognition'.toJS).toDart;

  @override
  bool get disponible =>
      _webkit || web.window.hasProperty('SpeechRecognition'.toJS).toDart;

  @override
  void ecouter({
    required String langue,
    required void Function(String phrase) surPhrase,
    required void Function(ErreurReconnaissance erreur, String code) surErreur,
    required void Function() surFinSansResultat,
    void Function(String texte)? surPartiel,
    void Function()? surSon,
  }) {
    annuler();
    final numero = ++_numero;
    bool actuelle() => numero == _numero;

    // Une nouvelle instance par écoute : réutiliser la même provoque des
    // erreurs « already started » dans certains navigateurs.
    final web.SpeechRecognition r = _webkit
        ? _ReconnaissanceWebkit()
        : web.SpeechRecognition();
    _courante = r;
    r.lang = langue;
    // Une phrase à la fois : le navigateur termine dès que l'utilisateur
    // s'arrête de parler et marque le résultat comme final.
    r.continuous = false;
    r.interimResults = true;
    r.maxAlternatives = 1;

    var termine = false;
    var texteFinal = '';

    r.onsoundstart = ((web.Event _) {
      if (actuelle()) surSon?.call();
    }).toJS;

    r.onresult = ((web.SpeechRecognitionEvent e) {
      if (!actuelle()) return;
      final resultats = e.results;
      var texte = '';
      var final_ = false;
      for (var i = 0; i < resultats.length; i++) {
        final resultat = resultats.item(i);
        if (resultat.length > 0) texte += resultat.item(0).transcript;
        if (resultat.isFinal) final_ = true;
      }
      texte = texte.trim();
      if (final_) {
        texteFinal = texte;
      } else {
        surPartiel?.call(texte);
      }
    }).toJS;

    r.onerror = ((web.SpeechRecognitionErrorEvent e) {
      if (!actuelle()) return;
      final code = e.error;
      debugPrint('[JARVIS voix] erreur navigateur : $code');
      termine = true;
      surErreur(_traduire(code), code);
    }).toJS;

    r.onend = ((web.Event _) {
      if (!actuelle() || termine) return;
      termine = true;
      _courante = null;
      if (texteFinal.isNotEmpty) {
        surPhrase(texteFinal);
      } else {
        surFinSansResultat();
      }
    }).toJS;

    try {
      r.start();
    } catch (e) {
      debugPrint('[JARVIS voix] démarrage impossible : $e');
      termine = true;
      surErreur(ErreurReconnaissance.autre, 'start');
    }
  }

  static ErreurReconnaissance _traduire(String code) => switch (code) {
    'no-speech' || 'aborted' => ErreurReconnaissance.rienEntendu,
    'not-allowed' || 'service-not-allowed' => ErreurReconnaissance.permission,
    'audio-capture' => ErreurReconnaissance.indisponible,
    'network' => ErreurReconnaissance.reseau,
    'language-not-supported' => ErreurReconnaissance.langue,
    _ => ErreurReconnaissance.autre,
  };

  @override
  void annuler() {
    _numero++;
    final r = _courante;
    _courante = null;
    if (r != null) {
      try {
        r.abort();
      } catch (_) {}
    }
  }
}
