// Diagnostic direct de la synthèse vocale sur l'appareil (temporaire).
//
//   flutter run -t tool/diag_tts.dart -d <appareil>
//
// Interroge flutter_tts sans passer par la conversation et journalise
// chaque étape avec le préfixe [JARVIS TTS].
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() => runApp(const MaterialApp(home: _Diag()));

class _Diag extends StatefulWidget {
  const _Diag();
  @override
  State<_Diag> createState() => _DiagState();
}

class _DiagState extends State<_Diag> {
  final _tts = FlutterTts();
  final _journal = <String>[];

  void _log(String m) {
    print('[JARVIS TTS] $m');
    setState(() => _journal.add(m));
  }

  @override
  void initState() {
    super.initState();
    _lancer();
  }

  Future<void> _essai(String nom, Future<void> Function() reglage) async {
    _log('--- essai : $nom');
    await reglage();
    final debut = DateTime.now();
    final fin = Completer<String>();
    _tts
      ..setStartHandler(() => _log('start (+${_ms(debut)} ms)'))
      ..setCompletionHandler(() {
        _log('complete (+${_ms(debut)} ms)');
        if (!fin.isCompleted) fin.complete('complete');
      })
      ..setCancelHandler(() {
        _log('cancel (+${_ms(debut)} ms)');
        if (!fin.isCompleted) fin.complete('cancel');
      })
      ..setErrorHandler((m) {
        _log('error = $m (+${_ms(debut)} ms)');
        if (!fin.isCompleted) fin.complete('error');
      });
    _log('speak');
    final r = await _tts
        .speak('Bonjour, je suis JARVIS.')
        .timeout(const Duration(seconds: 8), onTimeout: () => 'délai dépassé');
    _log('speak() a renvoyé $r (+${_ms(debut)} ms)');
    final issue = await fin.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => 'aucun rappel',
    );
    _log('issue : $issue');
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  int _ms(DateTime d) => DateTime.now().difference(d).inMilliseconds;

  Future<void> _lancer() async {
    _log('initialize');
    final attente = await _tts.awaitSpeakCompletion(true);
    _log('awaitSpeakCompletion -> $attente');
    _log('moteur par défaut = ${await _tts.getDefaultEngine}');
    _log('moteurs = ${await _tts.getEngines}');
    final langues = (await _tts.getLanguages as List).map((e) => '$e');
    _log(
      'langues (${langues.length}) fr = ${langues.where((l) => l.toLowerCase().startsWith('fr')).toList()}',
    );
    _log('fr-FR disponible = ${await _tts.isLanguageAvailable('fr-FR')}');
    _log('fr-FR installée = ${await _tts.isLanguageInstalled('fr-FR')}');
    final voix = (await _tts.getVoices as List).cast<Map>();
    final fr = voix
        .where((v) => '${v['locale']}'.toLowerCase().startsWith('fr'))
        .toList();
    _log('voix : ${voix.length} au total, ${fr.length} en français');
    for (final v in fr.take(12)) {
      _log(
        'voix disponible = ${v['name']} | ${v['locale']} | réseau ${v['network_required']} | qualité ${v['quality']}',
      );
    }
    _log('voix par défaut = ${await _tts.getDefaultVoice}');

    await _essai('voix système, réglages bruts', () async {});
    await _essai(
      'fr-FR, débit 0.5, hauteur 1, volume 1 (réglages JARVIS)',
      () async {
        _log('locale = fr-FR -> ${await _tts.setLanguage('fr-FR')}');
        _log('rate = 0.5 -> ${await _tts.setSpeechRate(0.5)}');
        _log('pitch = 1.0 -> ${await _tts.setPitch(1.0)}');
        _log('volume = 1.0 -> ${await _tts.setVolume(1.0)}');
      },
    );
    if (fr.isNotEmpty) {
      final v = fr.first;
      await _essai('voix fr appliquée ${v['name']}', () async {
        _log(
          'voix appliquée = ${v['name']} -> ${await _tts.setVoice({'name': '${v['name']}', 'locale': '${v['locale']}'})}',
        );
      });
    }
    await _essai('voix Web enregistrée (inexistante sur Android)', () async {
      _log(
        'voix demandée = Microsoft Denise Online (Natural) - French (France)',
      );
      _log(
        'setVoice -> ${await _tts.setVoice({'name': 'Microsoft Denise Online (Natural) - French (France)', 'locale': 'fr-FR'})}',
      );
    });
    _log('FIN DU DIAGNOSTIC');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final l in _journal)
            Text(l, style: const TextStyle(fontSize: 11)),
        ],
      ),
    ),
  );
}
