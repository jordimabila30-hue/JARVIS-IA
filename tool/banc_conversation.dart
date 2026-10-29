// Banc de mesure de la conversation écrite (session AB, optimisations 1-13).
//
// Bureau ou téléphone, mode profile :
//   flutter run --profile -d windows -t tool/banc_conversation.dart
//     --dart-define=JARVIS_PERF=true
// Web :
//   flutter run --profile -d chrome -t tool/banc_conversation.dart
//     --dart-define=JARVIS_PERF=true
//
// Page réelle (AccueilPage) avec un long historique local (60 échanges,
// réponses de longueurs variées), puis, dans le même lancement :
//   defilement : aller-retour continu dans l'historique ;
//   ecriture   : une longue réponse reçue en fragments (≈ 25 par seconde)
//                et écrite dans sa bulle, fil en bas ;
//   frappe     : saisie continue dans la barre (≈ 12 caractères / s) ;
//   ouverture  : bascule répétée entre deux conversations déjà chargées
//                (temps jusqu'à l'image affichée).
// Chaque mesure : temps des images (FrameTiming : interface, rasterisation,
// total), p50 / p90 / p95 / p99, images en retard (> 16,7 ms).
// Le moteur ci-dessous ne sert qu'à produire du texte À L'ÉCRAN : ce banc
// mesure le rendu, jamais une intégration (celle-ci se vérifie avec le
// vrai serveur).
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/utils/chrono_perf.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

const _phrases = [
  'Voici ce que je retiens de ta question.',
  'Le plus simple est de commencer par une liste courte des priorités.',
  'Ensuite, on vérifie chaque point avant de passer au suivant.',
  'Si tu veux, je peux détailler les étapes une par une.',
  'Attention aux dates : la réunion a été déplacée à jeudi.',
  'En résumé, rien ne presse, mais il vaut mieux répondre aujourd\'hui.',
];

String _reponse(int i) {
  final n = 1 + (i * 7) % 9;
  return [
    for (var k = 0; k < n; k++) _phrases[(i + k) % _phrases.length],
  ].join(' ');
}

/// Moteur de rendu : répond tout de suite (historique) ou en fragments
/// réguliers (mesure d'écriture).
class _MoteurBanc extends MoteurConversationLocal {
  bool flux = false;

  @override
  Future<ReponseJarvis> repondre(DemandeJarvis demande) async {
    final i = demande.historique.length;
    if (!flux) return ReponseJarvis(_reponse(i));
    final texte = List.filled(14, _phrases.join(' ')).join('\n\n');
    final mots = texte.split(' ');
    final surFragment = demande.surFragment;
    for (var k = 0; k < mots.length; k += 3) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      surFragment?.call('${mots.skip(k).take(3).join(' ')} ');
    }
    return ReponseJarvis(texte);
  }
}

/// Variante changée : toute la page est reconstruite (même état).
final _reconstruire = ValueNotifier(0);

/// Variantes alternées dans le même lancement (A/B fiable malgré l'état
/// changeant de la machine) : `JARVIS_VARIANTES=fil.fondu;bulle.ombre`.
const _variantes = String.fromEnvironment('JARVIS_VARIANTES');
const _tours = int.fromEnvironment('JARVIS_TOURS', defaultValue: 1);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final moteur = _MoteurBanc();
  final session = ConversationSession(
    moteur: moteur,
    delaiReflexion: Duration.zero,
  );
  final pim = PimController();
  runApp(
    ValueListenableBuilder<int>(
      valueListenable: _reconstruire,
      builder: (_, _, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeJarvis(),
        home: AccueilPage(conversation: session, pim: pim),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 2));
  // Deux conversations chargées : B (courte) mise de côté, A (longue).
  for (var i = 0; i < 4; i++) {
    await session.envoyer('Question courte $i');
  }
  final idB = session.idCourant!;
  session.effacer();
  for (var i = 0; i < 60; i++) {
    await session.envoyer('Question numéro $i : peux-tu m\'aider ?');
  }
  final idA = session.idCourant!;
  await _finirEcritures(session);
  await _Mesure().lancer(session, moteur, idA, idB);
}

Future<void> _finirEcritures(ConversationSession s) async {
  for (var t = 0; t < 400; t++) {
    if (s.messages.every((m) => m.ecriture == null || m.ecriture!.termine)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

ScrollPosition? _position() {
  ScrollPosition? trouvee;
  void visiter(Element e) {
    if (trouvee != null) return;
    // Le fil : seule liste verticale inversée de la page.
    if (e is StatefulElement &&
        e.state is ScrollableState &&
        (e.state as ScrollableState).widget.axisDirection == AxisDirection.up) {
      trouvee = (e.state as ScrollableState).position;
      return;
    }
    e.visitChildren(visiter);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visiter);
  return trouvee;
}

EditableTextState? _champ() {
  EditableTextState? trouve;
  void visiter(Element e) {
    if (trouve != null) return;
    if (e is StatefulElement && e.state is EditableTextState) {
      trouve = e.state as EditableTextState;
      return;
    }
    e.visitChildren(visiter);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visiter);
  return trouve;
}

class _Mesure {
  final _build = <double>[], _raster = <double>[], _total = <double>[];
  bool _actif = false;

  Future<void> lancer(
    ConversationSession session,
    _MoteurBanc moteur,
    String idA,
    String idB,
  ) async {
    SchedulerBinding.instance.addTimingsCallback((liste) {
      if (!_actif) return;
      for (final f in liste) {
        _build.add(f.buildDuration.inMicroseconds / 1000);
        _raster.add(f.rasterDuration.inMicroseconds / 1000);
        _total.add(f.totalSpan.inMicroseconds / 1000);
      }
    });

    final variantes = ['', ..._variantes.split(';').where((v) => v.isNotEmpty)];
    for (var tour = 0; tour < _tours; tour++) {
      for (final v in variantes) {
        ChronoPerf.retirer(v.split(','));
        _variante = v.isEmpty ? 'ref' : v;
        _reconstruire.value++;
        await _scenarios(session, moteur, idA, idB);
      }
    }
    print('BANC_FIN');
  }

  String _variante = 'ref';

  Future<void> _scenarios(
    ConversationSession session,
    _MoteurBanc moteur,
    String idA,
    String idB,
  ) async {
    // 1. Défilement continu dans l'historique.
    await _mesurer('defilement', () async {
      final p = _position();
      if (p == null) {
        print('BANC_ERREUR pas de défilement');
        return;
      }
      final fin = DateTime.now().add(const Duration(seconds: 6));
      var haut = true;
      while (DateTime.now().isBefore(fin)) {
        final cible = haut ? p.maxScrollExtent.clamp(0, 6000).toDouble() : 0.0;
        await p.animateTo(
          cible,
          duration: const Duration(milliseconds: 1800),
          curve: Curves.linear,
        );
        haut = !haut;
      }
      p.jumpTo(0);
    });

    // 2. Longue réponse reçue en fragments.
    await _mesurer('ecriture', () async {
      moteur.flux = true;
      final envoi = session.envoyer('Explique-moi tout en détail');
      await Future<void>.delayed(const Duration(seconds: 6));
      await envoi;
      moteur.flux = false;
    });
    await _finirEcritures(session);

    // 3. Frappe continue dans la barre.
    await _mesurer('frappe', () async {
      final champ = _champ();
      if (champ == null) {
        print('BANC_ERREUR pas de champ');
        return;
      }
      const phrase =
          'Bonjour Jarvis, peux-tu me rappeler ce que nous avons décidé ? ';
      var texte = '';
      for (var k = 0; k < 96; k++) {
        texte = k % 80 == 79 ? '' : texte + phrase[k % phrase.length];
        champ.userUpdateTextEditingValue(
          TextEditingValue(
            text: texte,
            selection: TextSelection.collapsed(offset: texte.length),
          ),
          SelectionChangedCause.keyboard,
        );
        await Future<void>.delayed(const Duration(milliseconds: 63));
      }
      champ.userUpdateTextEditingValue(
        TextEditingValue.empty,
        SelectionChangedCause.keyboard,
      );
    });

    // 4. Ouverture d'une conversation déjà chargée (A ↔ B).
    final ouvertures = <double>[];
    await _mesurer('ouverture', () async {
      for (var k = 0; k < 16; k++) {
        final chrono = Stopwatch()..start();
        session.ouvrir(k.isEven ? idB : idA);
        await SchedulerBinding.instance.endOfFrame;
        ouvertures.add(chrono.elapsedMicroseconds / 1000);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }, extra: () => {'ouvertureMs': _stats(ouvertures)});
  }

  Future<void> _mesurer(
    String nom,
    Future<void> Function() scenario, {
    Map<String, Object> Function()? extra,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    ChronoPerf.reinitialiser();
    _build.clear();
    _raster.clear();
    _total.clear();
    _actif = true;
    final debut = DateTime.now();
    await scenario();
    _actif = false;
    final duree = DateTime.now().difference(debut).inMilliseconds / 1000;
    print(
      'BANC_PERF ${jsonEncode({'scenario': nom, 'variante': _variante, 'images': _build.length, 'imagesParSeconde': _arrondi(_build.length / duree), 'enRetard': _total.where((t) => t > 1000 / 60).length, 'build': _stats(_build), 'raster': _stats(_raster), 'total': _stats(_total), ...?extra?.call()})}',
    );
  }

  static Map<String, num> _stats(List<double> v) {
    if (v.isEmpty) return {'n': 0};
    final t = [...v]..sort();
    num q(double p) =>
        _arrondi(t[(t.length * p).floor().clamp(0, t.length - 1)]);
    return {
      'n': v.length,
      'moyenne': _arrondi(v.reduce((a, b) => a + b) / v.length),
      'p50': q(0.5),
      'p90': q(0.9),
      'p95': q(0.95),
      'p99': q(0.99),
      'max': _arrondi(t.last),
    };
  }

  static double _arrondi(num v) => (v * 1000).round() / 1000;
}
