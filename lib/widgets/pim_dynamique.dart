import 'dart:math' as math;
import 'dart:typed_data';

import '../models/forme_pim.dart';
import '../models/signal_vocal.dart';

export '../models/forme_pim.dart';

/// Réglages du comportement des particules PIM face à la voix et au repos.
/// (Les réglages de la sphère et de la physique sont dans `PimReglages`.)
class PimDynamiqueReglages {
  PimDynamiqueReglages._();

  // --- Mémoire courte -------------------------------------------------------

  /// Vitesse à laquelle la mémoire courte oublie un pic de voix (1/s).
  /// Plus bas = les particules gardent l'élan plus longtemps.
  static const decroissanceMemoire = 0.85;

  /// Montée et descente de l'énergie instantanée (1/s). Plus bas = plus
  /// doux, mais moins réactif.
  static const attaqueInstant = 11.0;
  static const relachementInstant = 4.5;

  /// Vitesse de la tendance moyenne (1/s) : très lente, elle donne le
  /// « fond » de l'énergie d'une phrase.
  static const vitesseMoyenne = 0.5;

  /// Part de chaque mémoire dans l'énergie finale (somme = 1).
  static const partInstant = 0.5;
  static const partMemoire = 0.35;
  static const partMoyenne = 0.15;

  // --- Ondes ----------------------------------------------------------------

  /// Temps (s) pour qu'une onde traverse la sphère du centre au bord.
  static const traversee = 0.5;

  /// Épaisseur temporelle d'une onde (s) et durée de vie (s). Large et
  /// lente : une houle, pas un choc.
  static const largeurOnde = 0.16;
  static const vieOnde = 1.6;

  /// Affaiblissement d'une onde pendant sa traversée (1/s).
  static const amortissementOnde = 1.3;

  /// Écart minimal (s) entre deux ondes de réception à l'écoute.
  static const intervalleReception = 0.28;

  // --- Parole de JARVIS ------------------------------------------------------

  /// Durée de montée d'un mot (s) : le mot « s'allume » sans à-coup.
  static const attaqueMot = 0.07;

  /// Modulation par syllabe à l'intérieur d'un mot (0 = aucune).
  static const modulationSyllabes = 0.35;

  /// Énergie de la parole de JARVIS (multiplie l'enveloppe des mots).
  static const energieParole = 1.0;

  // --- Formes secondaires (cube, tétraèdre, réacteur) ----------------------

  /// Repos minimal et maximal (s) avant qu'une forme secondaire puisse
  /// apparaître.
  static const reposAvantCubeMin = 30.0;
  static const reposAvantCubeMax = 60.0;

  /// Probabilité, testée une fois par seconde de repos, qu'une forme
  /// apparaisse. 0.02 ≈ 50 s de plus en moyenne : un événement rare.
  static const probabiliteCube = 0.02;

  /// Temps minimal (s) entre deux formes, même si JARVIS reste au repos.
  static const recuperationCube = 180.0;

  /// Retour accéléré quand une interaction interrompt le cube (s).
  static const dureeRetourInterrompu = 0.9;

  /// Demi-côté du cube, en fraction du rayon de la sphère.
  static const demiCoteCube = 0.66;
}

/// Énergie de la voix vue à trois échelles de temps.
///
/// - [instant] suit l'amplitude presque immédiatement ;
/// - [memoire] (mémoire courte) monte vite et redescend lentement : après
///   un pic, les particules gardent un peu d'élan ;
/// - [moyenne] donne la tendance de la phrase.
///
/// Les bandes graves / médiums / aigus viennent du spectre réel du micro
/// quand il est mesuré, sinon de la dynamique de l'amplitude : la tendance
/// lente nourrit les graves, la mémoire les médiums, les attaques (écart
/// entre l'instant et la mémoire) les aigus.
class MemoireEnergie {
  double instant = 0;
  double memoire = 0;
  double moyenne = 0;
  double graves = 0, mediums = 0, aigus = 0;

  /// Énergie combinée, utilisée pour l'ampleur générale du mouvement.
  double get energie =>
      PimDynamiqueReglages.partInstant * instant +
      PimDynamiqueReglages.partMemoire * memoire +
      PimDynamiqueReglages.partMoyenne * moyenne;

  static double _vers(double actuel, double cible, double vitesse, double dt) =>
      actuel + (cible - actuel) * (1 - math.exp(-vitesse * dt));

  void avancer(double dt, double amplitude, SignalVocal? signal) {
    instant = _vers(
      instant,
      amplitude,
      amplitude > instant
          ? PimDynamiqueReglages.attaqueInstant
          : PimDynamiqueReglages.relachementInstant,
      dt,
    );
    memoire = instant > memoire
        ? _vers(memoire, instant, 4.5, dt)
        : _vers(memoire, instant, PimDynamiqueReglages.decroissanceMemoire, dt);
    moyenne = _vers(moyenne, instant, PimDynamiqueReglages.vitesseMoyenne, dt);

    double g, m, a;
    if (signal != null && signal.bandesMesurees) {
      g = signal.graves;
      m = signal.mediums;
      a = signal.aigus;
    } else {
      g = 0.6 * moyenne + 0.4 * memoire;
      m = memoire;
      a = ((instant - memoire) * 2.2 + instant * 0.3).clamp(0.0, 1.0);
    }
    graves = _vers(graves, g, g > graves ? 6 : 2, dt);
    mediums = _vers(mediums, m, m > mediums ? 9 : 3, dt);
    aigus = _vers(aigus, a, a > aigus ? 12 : 4, dt);
  }
}

/// Lissage du second ordre : deux filtres en cascade. Contrairement à un
/// lissage simple, la valeur démarre sans à-coup (courbe en S), ce qui
/// évite les cassures de vitesse aux changements d'état.
class Lisseur {
  double _etage = 0;
  double valeur = 0;

  double avancer(double cible, double vitesse, double dt) {
    final k = 1 - math.exp(-vitesse * 1.8 * dt);
    _etage += (cible - _etage) * k;
    valeur += (_etage - valeur) * k;
    return valeur;
  }
}

/// Enveloppe d'énergie de la parole de JARVIS, reconstruite mot par mot.
///
/// La synthèse vocale ne donne pas le son : on connaît le début de chaque
/// mot, son accent, sa durée estimée et son nombre de syllabes. Chaque mot
/// monte en douceur, porte une petite modulation par syllabe et s'éteint
/// vers sa fin ; le mot précédent s'efface progressivement au lieu d'être
/// coupé. Les pauses (ponctuation) laissent donc l'énergie retomber.
class EnveloppeParole {
  double _debut = -1e9, _duree = 0.3, _force = 0, _syllabes = 1;
  double _queue = 0, _debutQueue = -1e9;

  void mot(double t, double accent, double duree, int syllabes) {
    // Le mot en cours devient une traîne qui s'éteint.
    _queue = math.max(_queue * _decroissanceQueue(t), valeur(t));
    _debutQueue = t;
    _debut = t;
    _duree = duree.clamp(0.12, 1.2);
    _force = accent;
    _syllabes = syllabes.toDouble();
  }

  double _decroissanceQueue(double t) => math.exp(-(t - _debutQueue) * 7);

  static double _lisse(double x) {
    final v = x.clamp(0.0, 1.0);
    return v * v * (3 - 2 * v);
  }

  double valeur(double t) {
    final age = t - _debut;
    var v = 0.0;
    if (age >= 0 && age < _duree * 1.4) {
      final attaque = _lisse(age / PimDynamiqueReglages.attaqueMot);
      final fin = 1 - _lisse((age - _duree * 0.7) / (_duree * 0.7));
      final phase = age / _duree * _syllabes;
      const m = PimDynamiqueReglages.modulationSyllabes;
      final syllabe = 1 - m + m * (0.5 + 0.5 * math.cos(2 * math.pi * phase));
      v = _force * attaque * fin * syllabe;
    }
    final queue = _queue * _decroissanceQueue(t);
    return math.max(v, queue) * PimDynamiqueReglages.energieParole;
  }
}

/// Ondes qui traversent la sphère : émission (du centre vers le bord,
/// quand JARVIS parle) ou réception (du bord vers le centre, quand
/// l'utilisateur parle). Tampon circulaire fixe : aucune allocation.
class OndesPim {
  static const capacite = 6;

  final _debut = Float64List(capacite);
  final _force = Float32List(capacite);
  final _emission = Uint8List(capacite);
  int _prochaine = 0;

  // Ondes vivantes, recopiées une fois par image pour la boucle des
  // particules.
  final _aDecalage = Float32List(capacite);
  final _aForce = Float32List(capacite);
  final _aEmission = Uint8List(capacite);
  int _actives = 0;

  OndesPim() {
    _debut.fillRange(0, capacite, -1e9);
  }

  bool get actives => _actives > 0;

  /// Ajoute une onde qui démarre à l'instant [t] (éventuellement futur).
  void lancer(double t, double force, {required bool emission}) {
    _debut[_prochaine] = t;
    _force[_prochaine] = force;
    _emission[_prochaine] = emission ? 1 : 0;
    _prochaine = (_prochaine + 1) % capacite;
  }

  /// Prépare les ondes vivantes à l'instant [t].
  void preparer(double t) {
    _actives = 0;
    for (var k = 0; k < capacite; k++) {
      final age = t - _debut[k];
      if (age < -0.05 || age > PimDynamiqueReglages.vieOnde) continue;
      _aDecalage[_actives] = age;
      // L'onde s'affaiblit en avançant.
      _aForce[_actives] =
          _force[k] *
          math.exp(-math.max(age, 0) * PimDynamiqueReglages.amortissementOnde);
      _aEmission[_actives] = _emission[k];
      _actives++;
    }
  }

  /// Déformation radiale à la distance [r] du centre (0 à 1) : positive
  /// pour l'émission (poussée vers l'extérieur), négative pour la réception
  /// (aspiration vers l'intérieur).
  double valeur(double r, double amplitudeEmission, double amplitudeReception) {
    var somme = 0.0;
    const traversee = PimDynamiqueReglages.traversee;
    const largeur = PimDynamiqueReglages.largeurOnde;
    for (var k = 0; k < _actives; k++) {
      final emission = _aEmission[k] == 1;
      // Instant où le front de l'onde passe à cette distance.
      final passage = (emission ? r : 1.05 - r) * traversee;
      final x = (_aDecalage[k] - passage) / largeur;
      if (x.abs() > 2.6) continue;
      final g = _aForce[k] * math.exp(-x * x);
      somme += emission ? g * amplitudeEmission : -g * amplitudeReception;
    }
    return somme;
  }
}

/// Étapes d'une forme secondaire.
enum PhaseForme { absent, preparation, formation, tenue, retour }

/// Cycle des formes secondaires : rare, seulement après un vrai repos, et
/// la forme principale ([principale]) reprend toujours la priorité.
///
/// La rareté globale est celle du cube d'origine (repos de 30 à 60 s, puis
/// 2 % par seconde, 3 min entre deux formes) ; une fois l'apparition
/// décidée, [FormePim.tirer] choisit la forme parmi les trois autres que
/// la forme principale.
///
/// [progres] va de 0 (sphère) à 1 (forme) ; [stabilisation] (0 à 1) calme
/// le flottement de la sphère juste avant et pendant la forme ; [cycle]
/// change à chaque apparition (les géométries sont préparées une fois).
class FormesPim {
  FormesPim([int graine = 11]) : _hasard = math.Random(graine) {
    _tirerAttente();
  }

  final math.Random _hasard;

  PhaseForme phase = PhaseForme.absent;
  FormePim forme = FormePim.cube;

  /// Forme principale : jamais tirée comme forme secondaire.
  FormePim principale = FormePim.sphere;
  double progres = 0;
  double stabilisation = 0;
  int cycle = 0;

  double _repos = 0;
  double _attente = 0;
  // Temps écoulé depuis la fin de la dernière forme (recharge).
  double _depuisForme = 1e9;
  double _prochainTest = 0;
  double _dansPhase = 0;
  bool _interrompu = false;

  /// Temps passé dans la phase en cours (s).
  double get dansPhase => _dansPhase;

  void _tirerAttente() {
    const min = PimDynamiqueReglages.reposAvantCubeMin;
    const max = PimDynamiqueReglages.reposAvantCubeMax;
    _attente = min + (max - min) * _hasard.nextDouble();
    _prochainTest = _attente;
  }

  /// Lance une forme tout de suite (tests, démonstration) ; tirée au
  /// hasard si [choix] est absent.
  void declencher([FormePim? choix]) {
    if (phase != PhaseForme.absent) return;
    _demarrer(
      choix ?? FormePim.tirer(_hasard.nextDouble(), principale: principale),
    );
  }

  /// Défait la forme en cours (retour rapide), sans attendre d'image
  /// agitée : aperçu annulé, fenêtre ouverte par-dessus l'accueil…
  void interrompre() {
    if (phase == PhaseForme.absent) return;
    _interrompu = true;
    if (phase != PhaseForme.retour) _passer(PhaseForme.retour);
  }

  void _demarrer(FormePim f) {
    forme = f;
    cycle++;
    _passer(PhaseForme.preparation);
  }

  void _passer(PhaseForme p) {
    phase = p;
    _dansPhase = 0;
  }

  /// [calme] : aucune voix, aucune frappe, aucun focus, particules au
  /// centre.
  void avancer(double dt, {required bool calme}) {
    _dansPhase += dt;
    _depuisForme += dt;
    if (!calme) {
      _repos = 0;
      _prochainTest = _attente;
      if (phase == PhaseForme.preparation ||
          phase == PhaseForme.formation ||
          phase == PhaseForme.tenue ||
          (phase == PhaseForme.retour && !_interrompu)) {
        // Interruption, même pendant un retour normal : retour accéléré.
        _interrompu = true;
        if (phase != PhaseForme.retour) _passer(PhaseForme.retour);
      }
    }

    switch (phase) {
      case PhaseForme.absent:
        if (!calme) break;
        _repos += dt;
        // Après le repos minimal, un test par seconde, avec une faible
        // probabilité : les formes restent rares et ne s'enchaînent pas.
        if (_repos >= _prochainTest &&
            _depuisForme >= PimDynamiqueReglages.recuperationCube) {
          _prochainTest = _repos + 1;
          if (_hasard.nextDouble() < PimDynamiqueReglages.probabiliteCube) {
            _demarrer(
              FormePim.tirer(_hasard.nextDouble(), principale: principale),
            );
          }
        }
      case PhaseForme.preparation:
        if (_dansPhase >= forme.preparation) _passer(PhaseForme.formation);
      case PhaseForme.formation:
        progres += dt / forme.formation;
        if (progres >= 1) {
          progres = 1;
          _passer(PhaseForme.tenue);
        }
      case PhaseForme.tenue:
        if (_dansPhase >= forme.tenue) _passer(PhaseForme.retour);
      case PhaseForme.retour:
        progres -=
            dt /
            (_interrompu
                ? PimDynamiqueReglages.dureeRetourInterrompu
                : forme.retour);
        if (progres <= 0) {
          progres = 0;
          _interrompu = false;
          _repos = 0;
          _depuisForme = 0;
          _tirerAttente();
          _passer(PhaseForme.absent);
        }
    }

    final cible = (phase == PhaseForme.absent || phase == PhaseForme.retour)
        ? 0.0
        : 1.0;
    final vitesse = cible > stabilisation ? 2.0 : (_interrompu ? 4.0 : 1.0);
    stabilisation += (cible - stabilisation) * (1 - math.exp(-vitesse * dt));
  }
}
