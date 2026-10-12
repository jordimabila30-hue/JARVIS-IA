// Banc de mesure des performances de l'accueil (Web).
//
//   flutter build web -t tool/banc_perf.dart --dart-define=JARVIS_PERF=true
//
// Puis ouvrir `?scene=…&etat=…` :
//   scene : accueil (page réelle, défaut), fond, pim, vide
//   etat  : repos (défaut), frappe, ecoute, reflexion, parole, cube
//
// Après 4 s de chauffe, mesure pendant 10 s et écrit le résultat (JSON)
// dans la console : temps des images (FrameTiming) et sections du moteur
// (ChronoPerf).
// ignore_for_file: invalid_use_of_visible_for_testing_member, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ia_jarvis/models/signal_vocal.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/utils/chrono_perf.dart';
import 'package:ia_jarvis/widgets/fond_jarvis_anime.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

void main() {
  final p = Uri.base.queryParameters;
  final scene = p['scene'] ?? 'accueil';
  final etat = p['etat'] ?? 'repos';
  runApp(_Banc(scene: scene, etat: etat));
  _Mesure(scene, etat).lancer();
}

class _Mesure {
  _Mesure(this.scene, this.etat);
  final String scene, etat;
  final _build = <double>[], _raster = <double>[], _total = <double>[];
  bool _actif = false;

  void lancer() {
    SchedulerBinding.instance.addTimingsCallback((liste) {
      if (!_actif) return;
      for (final f in liste) {
        _build.add(f.buildDuration.inMicroseconds / 1000);
        _raster.add(f.rasterDuration.inMicroseconds / 1000);
        _total.add(f.totalSpan.inMicroseconds / 1000);
      }
    });
    Timer(const Duration(seconds: 4), () {
      ChronoPerf.reinitialiser();
      _actif = true;
      Timer(const Duration(seconds: 10), _rapport);
    });
  }

  Map<String, num> _stats(List<double> v) {
    if (v.isEmpty) return {'n': 0};
    final t = [...v]..sort();
    final moyenne = v.reduce((a, b) => a + b) / v.length;
    return {
      'n': v.length,
      'moyenneMs': _arrondi(moyenne),
      'p90Ms': _arrondi(t[(t.length * 0.9).floor().clamp(0, t.length - 1)]),
      'maxMs': _arrondi(t.last),
    };
  }

  static double _arrondi(num v) => (v * 1000).round() / 1000;

  void _rapport() {
    _actif = false;
    final r = {
      'scene': scene,
      'etat': etat,
      'images': _build.length,
      'build': _stats(_build),
      'raster': _stats(_raster),
      'total': _stats(_total),
      'sections': ChronoPerf.rapport().map(
        (k, v) => MapEntry(k, v.map((a, b) => MapEntry(a, _arrondi(b)))),
      ),
    };
    print('BANC_PERF ${jsonEncode(r)}');
  }
}

class _Banc extends StatefulWidget {
  const _Banc({required this.scene, required this.etat});
  final String scene, etat;

  @override
  State<_Banc> createState() => _BancState();
}

class _BancState extends State<_Banc> {
  final _pim = PimController();
  final _amplitude = ValueNotifier<double>(0);
  final _signal = SignalVocal();
  final _cleCentre = GlobalKey();
  Timer? _voix;
  double _t = 0;
  int _lettres = 0;

  @override
  void initState() {
    super.initState();
    // Après le premier rendu : la page a branché sa propre session, on la
    // remplace par une voix simulée.
    WidgetsBinding.instance.addPostFrameCallback((_) => _piloter());
  }

  void _piloter() {
    _pim
      ..amplitude = _amplitude
      ..signal = _signal;
    switch (widget.etat) {
      case 'ecoute':
        _pim.etatVocal = VoiceState.listening;
      case 'reflexion':
        _pim.etatVocal = VoiceState.thinking;
      case 'parole':
        _pim.etatVocal = VoiceState.speaking;
      case 'cube':
        _pim.declencherCube();
    }
    final hasard = math.Random(3);
    _voix = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _t += 0.05;
      switch (widget.etat) {
        case 'ecoute':
          // Voix simulée : syllabes et pauses, spectre variable.
          final a =
              (0.5 + 0.5 * math.sin(_t * 9)) *
              (math.sin(_t * 1.3) > -0.3 ? 1 : 0.1);
          _amplitude.value = a;
          _signal.bandes(a * 0.8, a * hasard.nextDouble(), a * 0.5);
        case 'parole':
          if ((_t * 20).round() % 6 == 0) {
            _signal.mot(hasard.nextDouble(), duree: 0.25, syllabes: 2);
            _amplitude.value = 0.6;
          }
          if ((_t * 20).round() % 80 == 0) _signal.debutPhrase();
          _amplitude.value *= 0.86;
        case 'frappe':
          // Frappe continue (≈ 7 caractères par seconde).
          if ((_t * 20).round() % 3 == 0) {
            _lettres = (_lettres + 1) % 40;
            _pim.surTexte('Bonjour JARVIS'.padRight(_lettres, 'a'));
          }
      }
    });
  }

  @override
  void dispose() {
    _voix?.cancel();
    _amplitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget page;
    switch (widget.scene) {
      case 'fond':
        page = const Scaffold(body: FondJarvisAnime(child: SizedBox.expand()));
      case 'pim':
        page = Scaffold(
          backgroundColor: CouleursJarvis.ivoirePrincipal,
          body: Stack(
            children: [
              Positioned.fill(
                child: PimParticle(controleur: _pim, cleCentre: _cleCentre),
              ),
              Center(child: SizedBox.square(key: _cleCentre, dimension: 520)),
            ],
          ),
        );
      case 'vide':
        page = const Scaffold(backgroundColor: CouleursJarvis.ivoirePrincipal);
      default:
        page = AccueilPage(pim: _pim);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themeJarvis(),
      home: page,
    );
  }
}
