import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'niveau_micro.dart';

/// Sur le Web : volume et spectre mesurés avec l'API Web Audio (analyseur
/// sur le flux du micro), 20 fois par seconde.
NiveauMicro creerNiveauMicro() => _NiveauMicroWeb();

class _NiveauMicroWeb implements NiveauMicro {
  web.MediaStream? _flux;
  web.AudioContext? _contexte;
  Timer? _minuteur;

  static const _taille = 512;
  final _tampon = JSUint8Array.withLength(_taille);
  final _spectre = JSUint8Array.withLength(_taille ~/ 2);

  /// Bandes de la voix (Hz) : graves, médiums, aigus.
  static const _limites = [80.0, 300.0, 2000.0, 6000.0];

  /// Bruit de fond de chaque bande, suivi en continu : il descend tout de
  /// suite au minimum observé et remonte lentement.
  final _plancher = [1.0, 1.0, 1.0];

  @override
  Future<bool> demarrer(
    void Function(double niveau) surNiveau, {
    void Function(double graves, double mediums, double aigus)? surBandes,
    String? microphoneId,
  }) async {
    await arreter();
    try {
      // Micro choisi dans les Paramètres (préférence : si le périphérique
      // a disparu, le navigateur reprend le micro par défaut).
      final JSAny audio = microphoneId == null
          ? true.toJS
          : web.MediaTrackConstraints(deviceId: microphoneId.toJS);
      final flux = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: audio))
          .toDart;
      final contexte = web.AudioContext();
      final analyseur = contexte.createAnalyser()..fftSize = _taille;
      contexte.createMediaStreamSource(flux).connect(analyseur);
      _flux = flux;
      _contexte = contexte;

      _minuteur = Timer.periodic(const Duration(milliseconds: 50), (_) {
        analyseur.getByteTimeDomainData(_tampon);
        final echantillons = _tampon.toDart;
        // Valeur efficace (RMS) du signal, centré sur 128.
        var somme = 0.0;
        for (final v in echantillons) {
          final x = (v - 128) / 128;
          somme += x * x;
        }
        final rms = math.sqrt(somme / echantillons.length);
        // Une voix normale donne un RMS d'environ 0,03 à 0,25 ; on retire
        // le bruit de fond puis on ramène entre 0 et 1.
        surNiveau(((rms - 0.015) * 5.5).clamp(0.0, 1.0));

        if (surBandes != null) {
          analyseur.getByteFrequencyData(_spectre);
          final b = _bandes(_spectre.toDart, contexte.sampleRate);
          surBandes(b[0], b[1], b[2]);
        }
      });
      return true;
    } catch (_) {
      // Micro refusé ou Web Audio indisponible : la session garde son
      // animation de secours.
      await arreter();
      return false;
    }
  }

  final _resultat = [0.0, 0.0, 0.0];

  /// Énergie moyenne de chaque bande, au-dessus du bruit de fond (0 à 1).
  List<double> _bandes(List<int> spectre, double frequence) {
    final largeur = frequence / _taille;
    for (var b = 0; b < 3; b++) {
      final i0 = math.max(1, (_limites[b] / largeur).floor());
      final i1 = math.min(spectre.length, (_limites[b + 1] / largeur).ceil());
      var somme = 0.0;
      for (var i = i0; i < i1; i++) {
        somme += spectre[i];
      }
      final v = i1 > i0 ? somme / (i1 - i0) / 255 : 0.0;
      _plancher[b] = math.min(_plancher[b] + 0.0015, v);
      _resultat[b] = ((v - _plancher[b]) / 0.3).clamp(0.0, 1.0);
    }
    return _resultat;
  }

  @override
  Future<void> arreter() async {
    _plancher.fillRange(0, 3, 1.0);
    _minuteur?.cancel();
    _minuteur = null;
    final flux = _flux;
    if (flux != null) {
      for (final piste in flux.getTracks().toDart) {
        piste.stop();
      }
    }
    _flux = null;
    final contexte = _contexte;
    _contexte = null;
    if (contexte != null) {
      try {
        await contexte.close().toDart;
      } catch (_) {}
    }
  }
}
