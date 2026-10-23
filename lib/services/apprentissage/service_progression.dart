import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/apprentissage/contenu_pedagogique.dart';
import '../../models/apprentissage/progression.dart';
import '../voice_settings_service.dart';

/// Progression du module Apprendre, sur l'appareil.
///
/// Source de vérité unique : les pages la lisent et l'écoutent ; chaque
/// changement s'affiche aussitôt ([notifyListeners]). Réponses et étapes
/// d'une séance sont écrites aussitôt ; les marques de navigation sont
/// regroupées ([delaiEcriture]) et forcées à la fin d'une leçon, quand
/// JARVIS passe en arrière-plan et à la fermeture du module.
///
/// Récupération : une valeur illisible n'est jamais effacée. Elle est
/// copiée sous [cleCorrompue], puis la dernière copie saine
/// ([cleSecours], refaite à chaque lecture réussie) est reprise.
class ServiceProgression extends ChangeNotifier with WidgetsBindingObserver {
  ServiceProgression({
    StockageReglages? principal,
    StockageReglages? secours,
    StockageReglages? corrompue,
    this.delaiEcriture = const Duration(milliseconds: 1500),
    DateTime Function()? horloge,
  }) : _principal = principal ?? const StockagePreferences(cle: cle),
       _secours = secours ?? const StockagePreferences(cle: cleSecours),
       _corrompue = corrompue ?? const StockagePreferences(cle: cleCorrompue),
       _horloge = horloge ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
  }

  static const cle = 'jarvis.apprentissage.progression';
  static const cleSecours = 'jarvis.apprentissage.progression.secours';
  static const cleCorrompue = 'jarvis.apprentissage.progression.corrompue';

  final StockageReglages _principal, _secours, _corrompue;
  final DateTime Function() _horloge;
  final Duration delaiEcriture;

  ProgressionApprentissage _p = ProgressionApprentissage.vide;
  ProgressionApprentissage get donnees => _p;

  /// Vrai si la progression a dû être reprise d'une copie de secours (ou
  /// repartir de zéro) parce que la valeur enregistrée était illisible.
  bool get recuperee => _recuperee;
  bool _recuperee = false;

  Future<void>? _chargement;
  Timer? _ecriture;
  bool _sale = false;
  Future<void>? _enCours;

  Future<void> charger() => _chargement ??= _lire();

  Future<void> _lire() async {
    final texte = await _lireSur(_principal);
    if (texte == null) return;
    try {
      _p = ProgressionApprentissage.decoder(texte);
      // Copie saine pour une éventuelle récupération.
      unawaited(_ecrireSur(_secours, texte));
    } catch (e) {
      debugPrint('[JARVIS Apprendre] progression illisible : $e');
      _recuperee = true;
      await _ecrireSur(_corrompue, texte);
      final secours = await _lireSur(_secours);
      if (secours != null) {
        try {
          _p = ProgressionApprentissage.decoder(secours);
        } catch (_) {
          _p = ProgressionApprentissage.vide;
        }
      }
    }
    notifyListeners();
  }

  // --- Lecture -------------------------------------------------------------

  EtatLecon? etat(String lecon) => _p.lecons[lecon];

  /// Part des leçons [lecons] terminées (0 à 1) ; 0 sans leçon.
  double avancement(Iterable<Lecon> lecons) {
    var total = 0, faites = 0;
    for (final l in lecons) {
      total++;
      if (_p.lecons[l.id]?.terminee == true) faites++;
    }
    return total == 0 ? 0 : faites / total;
  }

  int terminees(Iterable<Lecon> lecons) =>
      lecons.where((l) => _p.lecons[l.id]?.terminee == true).length;

  // --- Changements ---------------------------------------------------------

  void ouvrirParcours(String parcours) {
    if (_p.dernierParcours == parcours) return;
    _changer(_p.copier(dernierParcours: parcours));
  }

  /// Leçon ouverte (début, reprise ou consultation).
  void ouvrirLecon(String parcours, String lecon) {
    final etat = _p.lecons[lecon] ?? const EtatLecon();
    _changer(
      _p.copier(
        dernierParcours: parcours,
        derniereLecon: lecon,
        lecons: {
          ..._p.lecons,
          lecon: etat.copier(consulteeLe: _horloge()),
        },
      ),
    );
  }

  /// Séance en cours d'une leçon (après chaque réponse ou étape) : écrite
  /// aussitôt. Une interruption avant la fin de l'écriture peut perdre
  /// cette étape ; SharedPreferences ne garantit pas la durabilité disque.
  void enregistrerSeance(String lecon, SeanceEnregistree seance) {
    final etat = _p.lecons[lecon] ?? const EtatLecon();
    _changer(
      _p.copier(
        lecons: {
          ..._p.lecons,
          lecon: etat.copier(seance: () => seance),
        },
      ),
      immediat: true,
    );
  }

  /// Abandonne la séance en cours (« Recommencer »).
  void oublierSeance(String lecon) {
    final etat = _p.lecons[lecon];
    if (etat?.seance == null) return;
    _changer(
      _p.copier(
        lecons: {
          ..._p.lecons,
          lecon: etat!.copier(seance: () => null),
        },
      ),
    );
  }

  /// Fin de leçon : terminée, meilleur score gardé, écrite aussitôt.
  Future<void> terminerLecon(
    String lecon, {
    required int justes,
    required int total,
  }) {
    final etat = _p.lecons[lecon] ?? const EtatLecon();
    _changer(
      _p.copier(
        lecons: {
          ..._p.lecons,
          lecon: etat.copier(
            terminee: true,
            termineeLe: _horloge(),
            meilleurScore: justes > etat.meilleurScore || !etat.terminee
                ? justes
                : etat.meilleurScore,
            total: total,
            seance: () => null,
          ),
        },
      ),
    );
    return enregistrerMaintenant();
  }

  /// Résultat d'un exercice : raté → à réviser ; réussi → retiré. Avec
  /// [fiche], la maîtrise de la notion évolue (moyenne glissante : une
  /// erreur isolée ne fait pas tout chuter, la régularité compte).
  void noterExercice(
    String lecon,
    String exercice, {
    required bool juste,
    String? fiche,
  }) {
    if (fiche == null && juste == !_p.aReviser.containsKey(exercice)) return;
    final reviser = Map<String, String>.of(_p.aReviser);
    if (juste) {
      reviser.remove(exercice);
    } else {
      reviser[exercice] = lecon;
    }
    Map<String, double>? maitrise;
    if (fiche != null) {
      final avant = _p.maitrise[fiche] ?? 0.5;
      maitrise = {
        ..._p.maitrise,
        fiche: (avant * (1 - poidsReponse) + (juste ? poidsReponse : 0)).clamp(
          0.0,
          1.0,
        ),
      };
    }
    _changer(_p.copier(aReviser: reviser, maitrise: maitrise), immediat: true);
  }

  /// Poids d'une réponse dans la maîtrise d'une fiche.
  static const poidsReponse = 0.35;

  NiveauApprenant? niveau(String parcours) => _p.niveaux[parcours];

  double? maitriseDe(String fiche) => _p.maitrise[fiche];

  /// Le test de niveau est-il à proposer d'office pour ce parcours ?
  bool testAProposer(String parcours) =>
      !_p.niveaux.containsKey(parcours) &&
      !_p.testSansNiveau.contains(parcours);

  /// Niveau estimé (test, ou ajustement après une leçon). Écrit aussitôt.
  Future<void> fixerNiveau(String parcours, NiveauApprenant niveau) {
    _changer(_p.copier(niveaux: {..._p.niveaux, parcours: niveau}));
    return enregistrerMaintenant();
  }

  /// « Commencer directement » : le test reste disponible, jamais imposé.
  void passerTest(String parcours) {
    if (_p.testSansNiveau.contains(parcours)) return;
    _changer(_p.copier(testSansNiveau: {..._p.testSansNiveau, parcours}));
  }

  /// Efface toute la progression (demande confirmée de l'utilisateur).
  Future<void> effacer() {
    _changer(ProgressionApprentissage.vide);
    return enregistrerMaintenant();
  }

  /// [immediat] : écrit tout de suite (réponses, étapes) ; sinon l'écriture
  /// est regroupée ([delaiEcriture] : navigation, dernier ouvert).
  void _changer(ProgressionApprentissage p, {bool immediat = false}) {
    _p = p;
    _sale = true;
    notifyListeners();
    _ecriture?.cancel();
    if (immediat) {
      unawaited(enregistrerMaintenant());
    } else {
      _ecriture = Timer(delaiEcriture, enregistrerMaintenant);
    }
  }

  /// Écrit tout de suite ce qui attend (sans effet si rien n'a changé).
  Future<void> enregistrerMaintenant() {
    _ecriture?.cancel();
    _ecriture = null;
    // Tous les appelants attendent aussi les écritures déjà engagées.
    // Une seule écriture à la fois : un ancien état ne peut pas finir
    // après un état récent et l'écraser.
    if (_enCours != null) return _enCours!;
    if (!_sale) return Future<void>.value();
    return _enCours = _viderEcritures();
  }

  Future<void> _viderEcritures() async {
    try {
      while (_sale) {
        _sale = false;
        final texte = _p.encoder();
        if (!await _ecrireSur(_principal, texte)) {
          // Garder le dernier état en mémoire pour une prochaine tentative.
          // Ne pas boucler sans délai si le stockage reste indisponible.
          _sale = true;
          return;
        }
        // Les changements arrivés pendant l'attente sont regroupés dans
        // l'instantané suivant, sans bloquer le fil graphique.
      }
    } finally {
      _enCours = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Arrière-plan : le système peut fermer JARVIS sans prévenir.
    if (state != AppLifecycleState.resumed) unawaited(enregistrerMaintenant());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(enregistrerMaintenant());
    super.dispose();
  }

  static Future<String?> _lireSur(StockageReglages s) async {
    try {
      return await s.lire();
    } catch (e) {
      debugPrint('[JARVIS Apprendre] lecture impossible : $e');
      return null;
    }
  }

  static Future<bool> _ecrireSur(StockageReglages s, String v) async {
    try {
      await s.ecrire(v);
      return true;
    } catch (e) {
      debugPrint('[JARVIS Apprendre] progression non enregistrée : $e');
      return false;
    }
  }
}
