import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Chronomètre de performance du moteur graphique (particules, fond).
///
/// Désactivé par défaut : [actif] est une constante, donc les appels sont
/// supprimés à la compilation. Pour mesurer :
/// `flutter build web -t tool/banc_perf.dart --dart-define=JARVIS_PERF=true`.
class ChronoPerf {
  ChronoPerf._();

  static const actif = bool.fromEnvironment('JARVIS_PERF');

  /// Parties retirées du dessin pour mesurer leur coût (banc seulement,
  /// `?sans=pim.halos,fond.flou…`). Toujours vide hors du banc.
  static final Set<String> _retires = actif
      ? {
          ...?Uri.base.queryParameters['sans']?.split(','),
          // Téléphone : `--dart-define=JARVIS_PERF_SANS=indicateur,…`.
          ...const String.fromEnvironment('JARVIS_PERF_SANS').split(','),
        }
      : const {};

  static bool sans(String partie) => actif && _retires.contains(partie);

  /// Banc sur téléphone ou bureau (sans adresse de page) : parties
  /// retirées pour la mesure suivante.
  static void retirer(Iterable<String> parties) {
    if (!actif) return;
    _retires
      ..clear()
      ..addAll(parties);
  }

  /// Variante expérimentale activée (banc seulement, `?avec=…`).
  static final Set<String> _ajouts = actif
      ? {...?Uri.base.queryParameters['avec']?.split(',')}
      : const {};

  static bool avec(String partie) => actif && _ajouts.contains(partie);

  /// Banc sans adresse de page : variantes pour la mesure suivante.
  static void ajouter(Iterable<String> parties) {
    if (!actif) return;
    _ajouts
      ..clear()
      ..addAll(parties);
  }

  static final _horloge = Stopwatch()..start();
  static final _total = <String, int>{};
  static final _nombre = <String, int>{};
  static final _max = <String, int>{};

  /// Début d'une section (µs) ; 0 si inactif.
  static int debut() => actif ? _horloge.elapsedMicroseconds : 0;

  /// Fin de la section [nom] commencée à [depart].
  static void fin(String nom, int depart) {
    if (!actif) return;
    final duree = _horloge.elapsedMicroseconds - depart;
    _total[nom] = (_total[nom] ?? 0) + duree;
    _nombre[nom] = (_nombre[nom] ?? 0) + 1;
    if (duree > (_max[nom] ?? 0)) _max[nom] = duree;
  }

  /// Application réelle mesurée par son service VM (mode profile) :
  /// `ext.jarvis.chrono` renvoie les sections depuis le dernier appel, puis
  /// les remet à zéro. Sans effet hors mesure.
  static void enregistrerExtension() {
    if (!actif) return;
    suivreImages();
    developer.registerExtension('ext.jarvis.chrono', (_, _) async {
      final r = jsonEncode(rapport());
      reinitialiser();
      return developer.ServiceExtensionResponse.result(r);
    });
    // Comparaison dans la même session : `sans=a,b` et `avec=c` changent
    // les parties retirées et les variantes, à chaud.
    developer.registerExtension('ext.jarvis.variante', (_, p) async {
      retirer([...?p['sans']?.split(',').where((x) => x.isNotEmpty)]);
      ajouter([...?p['avec']?.split(',').where((x) => x.isNotEmpty)]);
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'sans': [..._retires],
          'avec': [..._ajouts],
        }),
      );
    });
  }

  static bool _imagesSuivies = false;

  /// Temps de chaque image (fil d'interface, fil de rendu) en sections
  /// `image.ui` / `image.raster` ; `image.hors_budget` : images dont l'un
  /// des deux fils dépasse 16,7 ms (image réellement manquée à 60 Hz) ;
  /// `image.lente` : latence totale > 16,7 ms (inclut l'attente entre les
  /// fils, donc plus large). Sans effet hors mesure.
  static void suivreImages() {
    if (!actif || _imagesSuivies) return;
    _imagesSuivies = true;
    SchedulerBinding.instance.addTimingsCallback((liste) {
      for (final t in liste) {
        _ajouter('image.ui', t.buildDuration.inMicroseconds);
        _ajouter('image.raster', t.rasterDuration.inMicroseconds);
        final pire = t.buildDuration > t.rasterDuration
            ? t.buildDuration
            : t.rasterDuration;
        if (pire.inMicroseconds > 16667) {
          _ajouter('image.hors_budget', pire.inMicroseconds);
        }
        if (t.totalSpan.inMicroseconds > 16700) {
          _ajouter('image.lente', t.totalSpan.inMicroseconds);
        }
      }
    });
  }

  static void _ajouter(String nom, int duree) {
    _total[nom] = (_total[nom] ?? 0) + duree;
    _nombre[nom] = (_nombre[nom] ?? 0) + 1;
    if (duree > (_max[nom] ?? 0)) _max[nom] = duree;
  }

  /// Écrit les sections dans le journal (`[PERF] titre {…}`), puis les
  /// remet à zéro. Sans effet hors mesure.
  static void journal(String titre) {
    if (!actif) return;
    debugPrint('[PERF] $titre ${jsonEncode(rapport())}');
    reinitialiser();
  }

  static void reinitialiser() {
    _total.clear();
    _nombre.clear();
    _max.clear();
  }

  /// Par section : appels, durée moyenne et maximale (ms).
  static Map<String, Map<String, num>> rapport() => {
    for (final nom in _total.keys)
      nom: {
        'appels': _nombre[nom]!,
        'moyenneMs': _total[nom]! / _nombre[nom]! / 1000,
        'maxMs': _max[nom]! / 1000,
      },
  };
}
