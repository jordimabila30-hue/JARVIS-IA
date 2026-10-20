// Module Apprendre : progression locale (sauvegarde regroupée,
// restauration, fermeture inattendue, données corrompues, pourcentages).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/apprentissage/contenu_pedagogique.dart';
import 'package:ia_jarvis/models/apprentissage/progression.dart';
import 'package:ia_jarvis/services/apprentissage/service_progression.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

Lecon _lecon(String id) => Lecon(
  id: id,
  titre: id,
  niveau: 1,
  dureeMinutes: 3,
  objectif: '',
  fiches: const ['f'],
  exercices: const [],
);

class _Stockages {
  final principal = StockageMemoire();
  final secours = StockageMemoire();
  final corrompue = StockageMemoire();

  ServiceProgression service({Duration delai = const Duration(seconds: 1)}) =>
      ServiceProgression(
        principal: principal,
        secours: secours,
        corrompue: corrompue,
        delaiEcriture: delai,
      );
}

const _seance = SeanceEnregistree(
  file: ['e1', 'e2'],
  position: 1,
  essais: {'e1': true},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('appel sans changement suivi immédiatement d’une réponse', () async {
    final s = _Stockages();
    final p = s.service();
    await p.charger();
    final vide = p.enregistrerMaintenant();
    p.enregistrerSeance('l1', _seance);
    await p.enregistrerMaintenant();
    await vide;
    expect(
      ProgressionApprentissage.decoder(
        s.principal.valeur!,
      ).lecons['l1']!.seance!.position,
      1,
    );
    p.dispose();
  });

  test(
    'écritures lentes : ordonnées, regroupées, attente du dernier état',
    () async {
      final stockage = _StockageRetarde();
      final p = ServiceProgression(
        principal: stockage,
        secours: StockageMemoire(),
        corrompue: StockageMemoire(),
      );
      await p.charger();
      p.enregistrerSeance('l1', _seance);
      p.noterExercice('l1', 'e1', juste: false);
      final fin = p.terminerLecon('l1', justes: 1, total: 2);
      var termine = false;
      final attente = p.enregistrerMaintenant().then((_) => termine = true);
      expect(stockage.ecritures.length, 1);
      expect(termine, isFalse);
      stockage.debloquer();
      await Future<void>.delayed(Duration.zero);
      expect(stockage.ecritures.length, 2);
      expect(termine, isFalse);
      stockage.debloquer();
      await fin;
      await attente;
      expect(stockage.maximumSimultane, 1);
      final relue = ProgressionApprentissage.decoder(stockage.valeur!);
      expect(relue.lecons['l1']!.terminee, isTrue);
      expect(relue.lecons['l1']!.seance, isNull);
      expect(relue.aReviser, {'e1': 'l1'});
      p.dispose();
    },
  );

  test(
    'échec pendant une écriture : réessai du dernier état complet',
    () async {
      final stockage = _StockageRetarde();
      final p = ServiceProgression(
        principal: stockage,
        secours: StockageMemoire(),
        corrompue: StockageMemoire(),
      );
      await p.charger();
      p.enregistrerSeance('l1', _seance);
      final fin = p.terminerLecon('l1', justes: 2, total: 2);
      stockage.debloquer(erreur: true);
      await fin;
      expect(stockage.valeur, isNull);
      final reprise = p.enregistrerMaintenant();
      stockage.debloquer();
      await reprise;
      expect(
        ProgressionApprentissage.decoder(
          stockage.valeur!,
        ).lecons['l1']!.terminee,
        isTrue,
      );
      expect(stockage.maximumSimultane, 1);
      p.dispose();
    },
  );

  test('navigation regroupée, réponses écrites aussitôt, puis restaurées '
      'à l’identique', () async {
    final s = _Stockages();
    final p = s.service(delai: const Duration(milliseconds: 30));
    await p.charger();
    p.ouvrirParcours('cor');
    p.ouvrirLecon('cor', 'l1');
    // Marques de navigation : rien d'écrit à chaque petite interaction…
    expect(s.principal.ecritures, 0);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    // … une seule écriture pour les deux.
    expect(s.principal.ecritures, 1);
    // Une réponse (étape de séance) est écrite tout de suite : une
    // fermeture brutale ne la perd pas.
    p.enregistrerSeance('l1', _seance);
    await Future<void>.delayed(Duration.zero);
    expect(s.principal.ecritures, 2);
    p.noterExercice('l1', 'e1', juste: false);
    await Future<void>.delayed(Duration.zero);
    expect(s.principal.ecritures, 3);

    final relu = s.service();
    await relu.charger();
    expect(relu.donnees.dernierParcours, 'cor');
    expect(relu.donnees.derniereLecon, 'l1');
    expect(relu.etat('l1')!.seance!.position, 1);
    expect(relu.etat('l1')!.seance!.essais, {'e1': true});
    expect(relu.donnees.aReviser, {'e1': 'l1'});
    expect(relu.recuperee, isFalse);
    p.dispose();
    relu.dispose();
  });

  test(
    'fin de leçon : écrite aussitôt, séance effacée, meilleur score',
    () async {
      final s = _Stockages();
      final p = s.service(delai: const Duration(hours: 1));
      await p.charger();
      p.enregistrerSeance('l1', _seance);
      await Future<void>.delayed(Duration.zero);
      final avant = s.principal.ecritures;
      await p.terminerLecon('l1', justes: 4, total: 6);
      // Écrite aussitôt, sans attendre le regroupement (1 h ici).
      expect(s.principal.ecritures, avant + 1);
      expect(s.principal.valeur, contains('"terminee":true'));
      expect(p.etat('l1')!.terminee, isTrue);
      expect(p.etat('l1')!.seance, isNull);
      await p.terminerLecon('l1', justes: 2, total: 6);
      expect(p.etat('l1')!.meilleurScore, 4);
      await p.terminerLecon('l1', justes: 6, total: 6);
      expect(p.etat('l1')!.meilleurScore, 6);
      p.dispose();
    },
  );

  test('fermeture inattendue : écrit dès le passage en arrière-plan', () async {
    final s = _Stockages();
    final p = s.service(delai: const Duration(hours: 1));
    await p.charger();
    // Marque de navigation (regroupée) en attente d'écriture.
    p.ouvrirLecon('cor', 'l1');
    expect(s.principal.ecritures, 0);
    p.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(s.principal.ecritures, 1);
    final relu = s.service();
    await relu.charger();
    expect(relu.donnees.derniereLecon, 'l1');
    p.dispose();
    relu.dispose();
  });

  test(
    'progression corrompue : gardée de côté, copie de secours reprise',
    () async {
      final s = _Stockages();
      final p = s.service();
      await p.charger();
      await p.terminerLecon('l1', justes: 3, total: 3);
      p.dispose();
      // Lecture saine : la copie de secours est faite.
      final sain = s.service();
      await sain.charger();
      await Future<void>.delayed(Duration.zero);
      expect(s.secours.valeur, isNotNull);
      sain.dispose();

      s.principal.valeur = '{"version": 1, "lecons": [tronqué';
      final r = s.service();
      await r.charger();
      expect(r.recuperee, isTrue);
      expect(r.etat('l1')!.terminee, isTrue);
      // Jamais effacée : la valeur illisible reste disponible.
      expect(s.corrompue.valeur, '{"version": 1, "lecons": [tronqué');
      r.dispose();
    },
  );

  test('corrompue sans secours : départ vide, sans exception', () async {
    final s = _Stockages()..principal.valeur = 'pas du json';
    final p = s.service();
    await p.charger();
    expect(p.recuperee, isTrue);
    expect(p.donnees.lecons, isEmpty);
    expect(s.corrompue.valeur, 'pas du json');
    p.dispose();
  });

  test('lecture tolérante : entrée illisible ignorée, le reste gardé', () {
    final p = ProgressionApprentissage.decoder(
      '{"version": 3, "lecons": {"l1": {"terminee": true, "total": 5}, '
      '"l2": 42}, "a_reviser": {"e1": "l1", "e2": 7}, '
      '"dernier_parcours": 12, "champ_futur": true}',
    );
    expect(p.lecons.keys, ['l1']);
    expect(p.lecons['l1']!.terminee, isTrue);
    expect(p.aReviser, {'e1': 'l1'});
    expect(p.dernierParcours, isNull);
  });

  test('pourcentages : leçons terminées sur leçons proposées', () async {
    final p = _Stockages().service();
    await p.charger();
    final lecons = [_lecon('a'), _lecon('b'), _lecon('c'), _lecon('d')];
    expect(p.avancement(lecons), 0);
    expect(p.avancement(const []), 0);
    await p.terminerLecon('a', justes: 1, total: 1);
    expect(p.avancement(lecons), 0.25);
    // Commencée n'est pas terminée.
    p.enregistrerSeance('b', _seance);
    expect(p.avancement(lecons), 0.25);
    await p.terminerLecon('b', justes: 1, total: 1);
    expect(p.avancement(lecons), 0.5);
    expect(p.terminees(lecons), 2);
    p.dispose();
  });

  test('révisions : raté ajouté, réussi retiré', () async {
    final p = _Stockages().service();
    await p.charger();
    p.noterExercice('l1', 'e1', juste: false);
    p.noterExercice('l1', 'e2', juste: false);
    expect(p.donnees.aReviser.keys, ['e1', 'e2']);
    p.noterExercice('l1', 'e1', juste: true);
    expect(p.donnees.aReviser.keys, ['e2']);
    p.dispose();
  });

  test('effacer : tout repart de zéro et est écrit', () async {
    final s = _Stockages();
    final p = s.service();
    await p.charger();
    await p.terminerLecon('l1', justes: 1, total: 1);
    await p.effacer();
    final relu = s.service();
    await relu.charger();
    expect(relu.donnees.lecons, isEmpty);
    p.dispose();
    relu.dispose();
  });

  test('échec d’écriture : nouvel essai à la suivante', () async {
    final stockage = _StockageCapricieux();
    final p = ServiceProgression(
      principal: stockage,
      secours: StockageMemoire(),
      corrompue: StockageMemoire(),
    );
    await p.charger();
    stockage.panne = true;
    await p.terminerLecon('l1', justes: 1, total: 1);
    expect(stockage.valeur, isNull);
    stockage.panne = false;
    await p.enregistrerMaintenant();
    expect(stockage.valeur, contains('l1'));
    p.dispose();
  });
}

class _StockageCapricieux implements StockageReglages {
  String? valeur;
  bool panne = false;

  @override
  Future<String?> lire() async => valeur;

  @override
  Future<void> ecrire(String v) async {
    if (panne) throw StateError('disque plein');
    valeur = v;
  }
}

class _StockageRetarde implements StockageReglages {
  String? valeur;
  final ecritures = <String>[];
  Completer<void>? _attente;
  int _simultane = 0;
  int maximumSimultane = 0;

  @override
  Future<String?> lire() async => valeur;

  @override
  Future<void> ecrire(String v) async {
    ecritures.add(v);
    _simultane++;
    if (_simultane > maximumSimultane) maximumSimultane = _simultane;
    final attente = _attente = Completer<void>();
    try {
      await attente.future;
      valeur = v;
    } finally {
      _simultane--;
    }
  }

  void debloquer({bool erreur = false}) {
    if (erreur) {
      _attente!.completeError(StateError('stockage indisponible'));
    } else {
      _attente!.complete();
    }
  }
}
