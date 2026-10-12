import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/voice_settings.dart';
import 'peripheriques_audio.dart';

/// Sur le Web : micros listés par le navigateur.
PeripheriquesAudio creerPeripheriquesAudio() => _MicrosNavigateur();

class _MicrosNavigateur implements PeripheriquesAudio {
  @override
  bool get choixPossible => true;

  @override
  Future<List<MicroDisponible>> lister() async {
    try {
      final appareils = await web.window.navigator.mediaDevices
          .enumerateDevices()
          .toDart;
      final micros = <MicroDisponible>[];
      var rang = 0;
      for (final a in appareils.toDart) {
        // « default » et « communications » sont des alias (Chrome).
        if (a.kind != 'audioinput' ||
            a.deviceId.isEmpty ||
            a.deviceId == 'default' ||
            a.deviceId == 'communications') {
          continue;
        }
        rang++;
        micros.add(
          MicroDisponible(
            id: a.deviceId,
            nom: a.label.isEmpty ? 'Microphone $rang' : a.label,
            nomConnu: a.label.isNotEmpty,
          ),
        );
      }
      return micros;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> autoriser() async {
    try {
      final flux = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
      for (final piste in flux.getTracks().toDart) {
        piste.stop();
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
