// Banc de mesure des performances de l'accueil.
//
// Web :
//   flutter build web -t tool/banc_perf.dart --dart-define=JARVIS_PERF=true
//   puis ouvrir `?scene=…&etat=…&sans=…` :
//     scene : accueil (page réelle, défaut), fond, pim, vide
//     etat  : repos (défaut), frappe, ecoute, reflexion, parole, cube
//     sans  : parties retirées (pim.halos, pim.flou, pim.reflets,
//             pim.lumieres…)
//   Après 4 s de chauffe, mesure pendant 10 s et écrit le résultat (JSON)
//   dans la console.
//
// Téléphone ou bureau (pas d'adresse de page) : suite complète, une
// mesure par état puis par partie retirée, dans le même lancement :
//   flutter run --profile -t tool/banc_perf.dart --dart-define=JARVIS_PERF=true
//     --dart-define=JARVIS_SUITE=pim     (ou accueil)
//
// Chaque mesure : temps des images (FrameTiming : fil d'interface, fil de
// rasterisation, durée totale), images en retard (> 16,7 ms) et sections
// du moteur (ChronoPerf).
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

const _suite = String.fromEnvironment('JARVIS_SUITE');

/// Une mesure : scène, état, parties retirées, variantes.
typedef _Config = ({
  String scene,
  String etat,
  List<String> sans,
  List<String> avec,
});

List<_Config> _configs() {
  final p = Uri.base.queryParameters;
  if (_suite.isEmpty) {
    return [
      (
        scene: p['scene'] ?? 'accueil',
        etat: p['etat'] ?? 'repos',
        sans: p['sans']?.split(',') ?? const [],
        avec: p['avec']?.split(',') ?? const [],
      ),
    ];
  }
  if (_suite == 'experience') {
    // Coût des points au repos, et variante en atlas : chaque mesure deux
    // fois, en alternance (la fréquence du GPU varie).
    const variantes = <(List<String>, List<String>)>[
      ([], []),
      (['pim.points'], []),
      (['pim.particules'], []),
    ];
    return [
      for (var tour = 0; tour < 2; tour++)
        for (final (sans, avec) in variantes)
          (scene: 'accueil', etat: 'repos', sans: sans, avec: avec),
    ];
  }
  final scene = _suite;
  return [
    for (final etat in const [
      'repos',
      'ecoute',
      'reflexion',
      'parole',
      'cube',
      'frappe',
    ])
      (scene: scene, etat: etat, sans: const <String>[], avec: const []),
    for (final sans in const [
      ['pim.halos'],
      ['pim.flou'],
      ['pim.reflets'],
      ['pim.lumieres'],
      ['pim.halos', 'pim.flou', 'pim.reflets', 'pim.lumieres'],
    ])
      (scene: scene, etat: 'repos', sans: sans, avec: const <String>[]),
  ];
}

void main() {
  final configs = _configs();
  final courante = ValueNotifier(0);
  runApp(
    ValueListenableBuilder<int>(
      valueListenable: courante,
      builder: (_, i, _) {
        final c = configs[i];
        // Nouvelle clé : PIM et la page repartent de zéro pour chaque mesure.
        return _Banc(key: ValueKey(i), scene: c.scene, etat: c.etat);
      },
    ),
  );
  _Mesure(configs, courante).lancer();
}

class _Mesure {
  _Mesure(this.configs, this.courante);
  final List<_Config> configs;
  final ValueNotifier<int> courante;
  final _build = <double>[], _raster = <double>[], _total = <double>[];
  bool _actif = false;

  static const _chauffe = Duration(seconds: 4);
  static const _duree = Duration(seconds: 10);

  void lancer() {
    SchedulerBinding.instance.addTimingsCallback((liste) {
      if (!_actif) return;
      for (final f in liste) {
        _build.add(f.buildDuration.inMicroseconds / 1000);
        _raster.add(f.rasterDuration.inMicroseconds / 1000);
        _total.add(f.totalSpan.inMicroseconds / 1000);
      }
    });
    _mesurer(0);
  }

  void _mesurer(int i) {
    courante.value = i;
    ChronoPerf.retirer(configs[i].sans);
    ChronoPerf.ajouter(configs[i].avec);
    Timer(_chauffe, () {
      ChronoPerf.reinitialiser();
      _build.clear();
      _raster.clear();
      _total.clear();
      _actif = true;
      Timer(_duree, () {
        _rapport(configs[i]);
        if (i + 1 < configs.length) {
          _mesurer(i + 1);
        } else {
          print('BANC_FIN');
        }
      });
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
      'p99Ms': _arrondi(t[(t.length * 0.99).floor().clamp(0, t.length - 1)]),
      'maxMs': _arrondi(t.last),
    };
  }

  static double _arrondi(num v) => (v * 1000).round() / 1000;

  void _rapport(_Config c) {
    _actif = false;
    final r = {
      'scene': c.scene,
      'etat': c.etat,
      if (c.sans.isNotEmpty) 'sans': c.sans,
      if (c.avec.isNotEmpty) 'avec': c.avec,
      'images': _build.length,
      'imagesParSeconde': _arrondi(_build.length / _duree.inSeconds),
      // Une image prête après plus d'un intervalle d'écran (60 Hz).
      'enRetard': _total.where((t) => t > 1000 / 60).length,
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
  const _Banc({super.key, required this.scene, required this.etat});
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
    if (!mounted) return;
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
