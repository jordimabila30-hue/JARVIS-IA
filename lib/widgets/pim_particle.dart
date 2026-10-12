import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/signal_vocal.dart';
import '../models/voice_state.dart';
import '../utils/chrono_perf.dart';
import 'pim_dynamique.dart';
import 'pim_rendu.dart';

export 'pim_dynamique.dart' show FormePim, PhaseForme;

/// Réglages des particules PIM. Toutes les valeurs ajustables sont ici.
class PimReglages {
  PimReglages._();

  /// Nombre de particules PIM (une majorité de micro-particules).
  static const nombre = 2200;

  // --- Sphère de référence --------------------------------------------------
  // Composition : une coque fine (silhouette nette), une couche épaisse
  // juste dessous (densité, profondeur), un cœur clairsemé (le centre
  // respire) et quelques satellites qui flottent autour.

  /// Coque fine, entre 0,93 et 1 rayon (spirale régulière).
  static const partCoque = 0.40;

  /// Couche épaisse, entre 0,7 et 0,94 rayon, plus dense vers l'extérieur.
  static const partCouche = 0.42;

  /// Satellites, entre 1,06 et 1,32 rayon. Le reste forme le cœur.
  static const partSatellites = 0.035;

  /// Dispersion maximale : de combien (fraction du rayon) la cible d'une
  /// particule peut s'éloigner de la sphère, tous effets confondus.
  static const dispersionMax = 0.30;

  /// Part de cette dispersion gardée sur une petite sphère (téléphone).
  static const dispersionCompacte = 0.8;

  /// Rappel supplémentaire (1/s²) quand une particule s'écarte de sa cible
  /// de plus de [zoneLibre] rayons : elle revient toujours vers la sphère.
  static const rappelHorsZone = 28.0;
  static const zoneLibre = 0.12;

  // --- Transitions entre états vocaux (1/s) --------------------------------
  // Entrée et sortie de chaque état à des vitesses différentes : l'écoute
  // s'ouvre progressivement, la réflexion se recentre, la parole démarre
  // vite (synchronisation) mais s'éteint lentement (inertie).

  static const entreeEcoute = 1.8;
  static const sortieEcoute = 2.2;
  static const entreeReflexion = 2.2;
  static const sortieReflexion = 2.0;
  static const entreeParole = 3.5;
  static const sortieParole = 1.3;

  // --- Physique -------------------------------------------------------------

  /// Raideur du ressort qui attire chaque particule vers sa cible (1/s²).
  /// Plus haut = particules plus « nerveuses », plus bas = plus lentes.
  static const raideur = 11.0;

  /// Amortissement (1 = critique, sans rebond ; < 1 = léger dépassement).
  /// Plus haut = mouvement plus freiné, plus bas = plus de rebond.
  static const amortissement = 0.92;

  /// Vitesse maximale d'une particule (px/s), garde-fou.
  static const vitesseMax = 2400.0;

  /// Distance (px) en dessous de laquelle deux particules se repoussent.
  static const rayonRepulsion = 5.5;

  /// Intensité de la répulsion au contact (px/s²). Rester discret.
  static const forceRepulsion = 600.0;

  /// Accélération maximale due à la répulsion (px/s²), même si beaucoup de
  /// particules se chevauchent : aucune « explosion » possible.
  static const repulsionMax = 500.0;

  // --- Mode vocal -----------------------------------------------------------

  /// Multiplicateur global de la réaction vocale (écoute et parole).
  static const reactionVocale = 1.2;

  /// Expansion à l'écoute selon le volume (fraction du rayon) : base + part
  /// variable selon la particule. (+10 % par rapport aux valeurs d'origine
  /// 0.08 / 0.18, pour que l'écoute se remarque davantage.)
  static const expansionEcoute = 0.088;
  static const expansionEcouteVariable = 0.198;

  /// Vibration des particules à l'écoute (fraction du rayon).
  static const vibrationEcoute = 0.011;

  /// Amplitude des vagues pendant que JARVIS parle (fraction du rayon).
  static const vaguesParole = 0.12;

  /// Légère ouverture de la sphère pendant l'écoute, même en silence.
  static const ouvertureEcoute = 0.035;

  /// Ondes : émission (JARVIS parle, du centre vers le bord) et réception
  /// (l'utilisateur parle, du bord vers le centre), en fraction du rayon.
  static const ondeEmission = 0.085;
  static const ondeReception = 0.055;

  /// Mouvement profond des particules internes porté par les graves.
  static const mouvementGraves = 0.07;

  /// Petite contraction de préparation au début d'une phrase de JARVIS.
  static const preparationParole = 0.04;

  // --- Mouvement ------------------------------------------------------------

  /// Énergie générale du mouvement au repos (flottement, ondulation,
  /// respiration). 1 = réglage d'origine, 0 = sphère immobile.
  static const energieMouvement = 1.0;

  /// Rotation globale au repos (rad/s).
  static const vitesseRotation = 0.12;

  /// Écart de vitesse de rotation entre particules (±, fraction) : la
  /// sphère ne tourne pas comme un bloc rigide.
  static const parallaxeRotation = 0.08;

  /// Ondulation lente de toute la sphère (fraction du rayon).
  static const ondulation = 0.022;

  /// Balancement lent de l'axe de rotation (radians).
  static const precession = 0.08;

  /// Respiration : variation du rayon (0.018 = 1.0 → 1.018 → 1.0).
  static const respiration = 0.018;

  /// Flottement vertical de toute la sphère (fraction du rayon) : objet
  /// suspendu au-dessus de son ombre.
  static const flottementSphere = 0.03;

  /// Flottement au centre, en fraction du rayon.
  static const flottementCentre = 0.018;

  /// Flottement autour du champ (px), calme puis pendant la frappe.
  static const flottementChamp = 2.0;
  static const flottementChampActif = 3.5;

  /// Circulation le long du contour du champ (px/s), calme puis active.
  static const fluxCalme = 7.0;
  static const fluxActif = 24.0;

  // --- Transitions ----------------------------------------------------------

  /// Durée de la transformation centre ↔ champ (s). La physique ajoute
  /// ensuite un court temps d'arrivée.
  static const dureeTransition = 1.0;

  /// Délai sans frappe, champ vide, avant le retour au centre (s).
  static const delaiRetourCentre = 3.0;

  /// Délai sans frappe avant que les particules se calment (s).
  static const delaiCalme = 1.8;

  /// Distance minimale (px) entre le bord du champ et les particules.
  static const ecartChampMin = 5.0;

  /// Espacement visé entre particules autour du champ (px). La largeur de
  /// la bande s'adapte au périmètre du champ pour garder cette densité.
  static const espacementChamp = 9.0;

  /// Largeur de bande minimale et maximale (px).
  static const bandeMin = 14.0;
  static const bandeMax = 56.0;

  /// Aperçu d'une forme : durée (s) pendant laquelle la sphère, au
  /// centre, est montrée telle quelle avant de commencer à se calmer
  /// (stabilisation de la forme : 0,8 s ; 1 s pour le cube).
  static const presentationApercu = 0.25;

  /// Impulsion d'envoi : amplitude (px) et durée de propagation (s).
  static const impulsionAmplitude = 9.0;
  static const impulsionPropagation = 0.35;
}

/// Mode des particules PIM, déduit de la frappe, du texte et de la voix.
enum ParticlePimMode {
  idle,
  movingToInput,
  inputActive,
  inputCalm,
  sending,
  movingToCenter,
  listening,
  thinking,
  speaking,

  /// Formes secondaires : la forme principale devient quelques secondes
  /// sphère, cube, tétraèdre ou Réacteur Arc.
  sphere,
  cube,
  tetraedre,
  reacteur,
}

/// Pilote les particules PIM depuis la page : texte saisi, envoi, voix.
///
/// La page appelle [surTexte], [surEnvoi] et règle [etatVocal] ; tout le
/// reste (délais, transitions, physique) est géré ici et dans la simulation.
class PimController {
  late final _SimulationPim _simulation = _SimulationPim(this);

  bool _texteVide = true;
  double _derniereFrappe = -1e9;
  double _debutImpulsion = -1e9;

  /// État vocal ; null en mode texte. Une voix active annule un aperçu
  /// de forme.
  VoiceState? get etatVocal => _etatVocal;
  VoiceState? _etatVocal;
  set etatVocal(VoiceState? etat) {
    _etatVocal = etat;
    if (etat != null) annulerApercu();
  }

  /// Conversation écrite en cours : les particules restent autour de la
  /// barre de saisie (calmes, puis vivantes pendant la frappe) au lieu de
  /// reformer la sphère au-dessus des messages.
  bool conversation = false;

  /// Amplitude de la voix (0 à 1), lue seulement en mode vocal.
  ValueListenable<double>? amplitude;

  /// Détails de la voix (bandes de fréquence, mots de JARVIS), facultatif.
  SignalVocal? signal;

  /// Zone où les particules se regroupent, dans le repère de l'écran. Ne
  /// change qu'avec la mise en page : le fond s'y centre sans horloge.
  ValueListenable<Rect?> get zone => _zone;
  final _zone = ValueNotifier<Rect?>(null);

  // Horloge de la simulation : les délais s'arrêtent quand l'animation est
  // en pause (onglet masqué…) et restent testables.
  double get _maintenant => _simulation._t;

  /// À appeler à chaque modification du texte saisi (une frappe annule un
  /// aperçu de forme).
  void surTexte(String texte) {
    _texteVide = texte.trim().isEmpty;
    _derniereFrappe = _maintenant;
    annulerApercu();
  }

  /// À appeler à l'envoi d'un message : petite onde le long du contour.
  void surEnvoi() {
    _debutImpulsion = _maintenant;
    annulerApercu();
  }

  /// Vrai si les particules doivent entourer le champ texte. Pendant un
  /// aperçu, elles restent au centre (le texte saisi n'est pas touché).
  bool get _versChamp =>
      etatVocal == null &&
      _apercu == null &&
      (conversation ||
          !_texteVide ||
          _maintenant - _derniereFrappe < PimReglages.delaiRetourCentre);

  bool get _frappeRecente =>
      _maintenant - _derniereFrappe < PimReglages.delaiCalme;

  double get _depuisEnvoi => _maintenant - _debutImpulsion;

  /// Le champ de saisie a le focus : l'utilisateur va interagir, aucune
  /// forme secondaire ne commence (et celle en cours se défait, aperçu
  /// compris).
  bool get saisieFocus => _saisieFocus;
  bool _saisieFocus = false;
  set saisieFocus(bool focus) {
    _saisieFocus = focus;
    if (focus) annulerApercu();
  }

  // ---- Aperçu d'une forme (Paramètres → Particules PIM) ------------------
  //
  // Déclenchement manuel, distinct du tirage au repos : la sphère se
  // présente d'abord au centre, puis la forme choisie suit son cycle
  // habituel (formation, maintien, retour), sans attente ni probabilité.
  // Seule une vraie interaction (frappe, envoi, focus, voix, nouvelle
  // ouverture des Paramètres) l'annule.

  FormePim? _apercu;
  // Moment où la sphère est prête au centre (-1 : pas encore).
  double _debutSphere = -1;
  // Cycle de la forme lancée par l'aperçu (-1 : pas encore lancée).
  int _cycleApercu = -1;
  // Aperçu de la forme principale elle-même : fin de sa présentation.
  double _finApercuRepos = -1;

  /// Un aperçu est en cours (présentation de la sphère ou forme).
  bool get apercuEnCours => _apercu != null;

  /// Montre [forme] : la sphère au centre pendant
  /// [PimReglages.presentationApercu], puis la transformation, le maintien
  /// et le retour habituels. Refusé (false) si un aperçu est déjà en cours.
  bool lancerApercu(FormePim forme) {
    if (_apercu != null) return false;
    _apercu = forme;
    _debutSphere = -1;
    _cycleApercu = -1;
    _finApercuRepos = -1;
    return true;
  }

  /// Annule l'aperçu en cours : les particules reprennent progressivement
  /// leur comportement normal (retour rapide de la forme).
  void annulerApercu() {
    if (_apercu == null) return;
    _apercu = null;
    _simulation._formes.interrompre();
  }

  /// Avance l'aperçu (appelé par la simulation à chaque image).
  void _suivreApercu() {
    final forme = _apercu;
    if (forme == null) return;
    final formes = _simulation._formes;
    if (_cycleApercu < 0) {
      // 1. La sphère se présente : particules au centre, aucune autre forme.
      if (formes.phase != PhaseForme.absent) {
        formes.interrompre();
        _debutSphere = -1;
      } else if (_simulation.morph < 0.001) {
        if (_debutSphere < 0) {
          _debutSphere = _maintenant;
        } else if (_maintenant - _debutSphere >=
            PimReglages.presentationApercu) {
          if (forme == formes.principale) {
            // Déjà la forme principale : simple présentation au repos,
            // sans transformation artificielle.
            _cycleApercu = formes.cycle;
            _finApercuRepos = _maintenant + forme.tenue;
          } else {
            // 2. Transformation : le cycle habituel de la forme.
            formes.declencher(forme);
            _cycleApercu = formes.cycle;
          }
        }
      } else {
        _debutSphere = -1;
      }
    } else if (_finApercuRepos >= 0) {
      if (_maintenant >= _finApercuRepos) _apercu = null;
    } else if (formes.cycle != _cycleApercu ||
        formes.phase == PhaseForme.absent) {
      // 3. Retour à la forme principale terminé : fonctionnement normal.
      _apercu = null;
    }
  }

  /// Forme principale de PIM (sphère par défaut) : au repos comme pendant
  /// l'écoute, la réflexion et la parole.
  FormePim get formePrincipale => _simulation._principale;

  /// Change la forme principale : transition progressive des particules
  /// ([immediat] : sans transition, au lancement). Une forme secondaire en
  /// cours se défait d'abord.
  void definirFormePrincipale(FormePim forme, {bool immediat = false}) =>
      _simulation.changerPrincipale(forme, immediat: immediat);

  /// Étape de la forme secondaire en cours.
  PhaseForme get phaseForme => _simulation._formes.phase;

  /// Forme secondaire en cours (ou la dernière apparue).
  FormePim get forme => _simulation._formes.forme;

  /// Fait apparaître une forme sans attendre le repos (tests,
  /// démonstration) ; tirée au hasard si [forme] est absente.
  @visibleForTesting
  void declencherForme([FormePim? forme]) =>
      _simulation._formes.declencher(forme);

  /// Fait apparaître le cube sans attendre le repos.
  @visibleForTesting
  void declencherCube() => declencherForme(FormePim.cube);

  /// Points visés par les particules pour le tétraèdre ou le réacteur en
  /// cours, dans le repère de la forme, en rayons de la sphère
  /// (diagnostic pour les tests).
  @visibleForTesting
  ({Float32List x, Float32List y, Float32List z, Float32List ordre})
  get ciblesForme => (
    x: _simulation._geoSecondaire.x,
    y: _simulation._geoSecondaire.y,
    z: _simulation._geoSecondaire.z,
    ordre: _simulation._geoSecondaire.ordre,
  );

  /// Points visés par les particules pour la forme principale (tétraèdre ou
  /// réacteur), même repère (diagnostic pour les tests).
  @visibleForTesting
  ({Float32List x, Float32List y, Float32List z}) get ciblesPrincipale => (
    x: _simulation._geoPrincipale.x,
    y: _simulation._geoPrincipale.y,
    z: _simulation._geoPrincipale.z,
  );

  /// Étalement des particules autour du centre (diagnostic pour les tests).
  @visibleForTesting
  ({double moyenne, double maximum}) get etalement => _simulation.etalement;

  ParticlePimMode get mode {
    switch (etatVocal) {
      case VoiceState.listening:
        return ParticlePimMode.listening;
      case VoiceState.thinking:
        return ParticlePimMode.thinking;
      case VoiceState.speaking:
        return ParticlePimMode.speaking;
      case VoiceState.idle:
      case null:
        break;
    }
    final m = _simulation.morph;
    if (_versChamp) {
      if (m < 0.999) return ParticlePimMode.movingToInput;
      if (_depuisEnvoi < 0.8) return ParticlePimMode.sending;
      return _frappeRecente
          ? ParticlePimMode.inputActive
          : ParticlePimMode.inputCalm;
    }
    if (m > 0.001) return ParticlePimMode.movingToCenter;
    final formes = _simulation._formes;
    if (formes.phase == PhaseForme.absent) return ParticlePimMode.idle;
    return switch (formes.forme) {
      FormePim.sphere => ParticlePimMode.sphere,
      FormePim.cube => ParticlePimMode.cube,
      FormePim.tetraedre => ParticlePimMode.tetraedre,
      FormePim.reacteur => ParticlePimMode.reacteur,
    };
  }
}

/// Calque plein écran qui dessine les particules PIM.
///
/// [cleCentre] désigne la zone où les particules se regroupent au centre ;
/// [cleChamp] le champ texte qu'elles entourent pendant l'écriture. Le
/// calque ignore les touches : il se place derrière l'interface.
class PimParticle extends StatefulWidget {
  const PimParticle({
    super.key,
    required this.controleur,
    required this.cleCentre,
    this.cleChamp,
  });

  final PimController controleur;
  final GlobalKey cleCentre;
  final GlobalKey? cleChamp;

  @override
  State<PimParticle> createState() => _PimParticleState();
}

class _PimParticleState extends State<PimParticle>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tic);
  Duration _precedent = Duration.zero;

  _SimulationPim get _simulation => widget.controleur._simulation;

  // Un seul peintre pour toute la vie du calque : ses points flous
  // pré-rendus ne sont pas refaits à chaque reconstruction de la page.
  late _PeintrePim _peintre = _PeintrePim(_simulation);

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _simulation.mouvementReduit = MediaQuery.disableAnimationsOf(context);
    _peintre.densite = View.of(context).devicePixelRatio;
  }

  @override
  void didUpdateWidget(PimParticle ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.controleur != widget.controleur) {
      _peintre = _PeintrePim(_simulation)
        ..densite = View.of(context).devicePixelRatio;
    }
  }

  /// Rectangle d'un widget, exprimé dans le repère du calque.
  Rect? _rect(GlobalKey? cle, RenderBox calque) {
    final objet = cle?.currentContext?.findRenderObject();
    if (objet is! RenderBox || !objet.attached || !objet.hasSize) return null;
    final origine =
        objet.localToGlobal(Offset.zero) - calque.localToGlobal(Offset.zero);
    return origine & objet.size;
  }

  void _tic(Duration ecoule) {
    var dt = (ecoule - _precedent).inMicroseconds / 1e6;
    _precedent = ecoule;
    // Après une vraie pause (onglet masqué…), on évite un saut brutal.
    // Sur un appareil lent, le pas reste réel (jusqu'à 0,1 s, stable pour
    // les ressorts utilisés) pour que l'animation garde sa durée.
    if (dt <= 0 || dt > 0.25) dt = 1 / 60;
    if (dt > 0.1) dt = 0.1;

    final calque = context.findRenderObject();
    if (calque is! RenderBox || !calque.hasSize) return;
    final centre = _rect(widget.cleCentre, calque);
    if (centre == null || centre.isEmpty) return;
    // Mesure déjà faite ici à chaque image : on la partage (le fond n'est
    // prévenu que si elle change).
    widget.controleur._zone.value = centre.shift(
      calque.localToGlobal(Offset.zero),
    );
    final champ = _rect(widget.cleChamp, calque);
    final chrono = ChronoPerf.debut();
    _simulation.avancer(
      dt,
      calque.size,
      centre,
      (champ == null || champ.isEmpty) ? null : champ,
    );
    ChronoPerf.fin('pim.simulation', chrono);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(size: Size.infinite, painter: _peintre),
        ),
      ),
    );
  }
}

/// Physique des particules PIM.
///
/// Chaque particule a une position, une vitesse et une cible. À chaque
/// image : accélération (ressort vers la cible + amortissement + répulsion)
/// → vitesse → position. Les formations (centre, champ) ne déplacent que
/// les cibles ; c'est la physique qui produit le trajet.
class _SimulationPim extends ChangeNotifier {
  _SimulationPim(this._controleur) {
    final hasard = math.Random(7);
    final surface = (n * PimReglages.partCoque).round();
    final couche = surface + (n * PimReglages.partCouche).round();
    final satellites = n - (n * PimReglages.partSatellites).round();
    final orDor = math.pi * (3 - math.sqrt(5));
    for (var i = 0; i < n; i++) {
      if (i < surface) {
        // Coque : spirale de Fibonacci, répartition régulière (pas de trous
        // ni d'amas), avec un très léger écart pour rester organique.
        final y = 1 - 2 * (i + 0.5) / surface;
        final r = math.sqrt(1 - y * y);
        final a = orDor * i + (hasard.nextDouble() - 0.5) * 0.3;
        _dirX[i] = r * math.cos(a);
        _dirY[i] = y;
        _dirZ[i] = r * math.sin(a);
        _rayon[i] = 0.93 + 0.07 * hasard.nextDouble();
      } else {
        final z = hasard.nextDouble() * 2 - 1;
        final phi = hasard.nextDouble() * 2 * math.pi;
        final r = math.sqrt(1 - z * z);
        _dirX[i] = r * math.cos(phi);
        _dirY[i] = z;
        _dirZ[i] = r * math.sin(phi);
        final u = hasard.nextDouble();
        if (i < couche) {
          // Couche épaisse, plus dense vers l'extérieur.
          _rayon[i] = 0.7 + 0.24 * math.pow(u, 0.4).toDouble();
        } else if (i < satellites) {
          // Cœur clairsemé : le centre reste lumineux et respire.
          _rayon[i] = 0.22 + 0.46 * math.pow(u, 0.6).toDouble();
        } else {
          _satellite[i] = 1;
          _rayon[i] = 1.06 + 0.26 * u;
        }
      }
      // Apparence. Certaines zones sont un peu plus riches en particules
      // moyennes et lumineuses : variation lente selon la direction (pas
      // d'amas), de moyenne 1 pour garder les proportions globales.
      final richesse =
          0.5 +
          0.5 *
              math.sin(2.3 * _dirX[i] + 1.7 * _dirY[i] + 0.6) *
              math.cos(1.9 * _dirZ[i] - 1.1 * _dirY[i] + 0.4);
      final poids = 1 + PimRendu.variationRichesse * (richesse - 0.5);
      _style[i] = _tirerStyle(
        hasard.nextDouble() < _partNonMicro * poids,
        hasard.nextDouble(),
      );
      _phase[i] = hasard.nextDouble() * 2 * math.pi;
      _vitesseIndiv[i] = 0.6 + hasard.nextDouble() * 1.2;
      _reactivite[i] = hasard.nextDouble();
      _parallaxe[i] = hasard.nextDouble() - 0.5;

      // Zones audio (une seule structure, réactions différentes) : les
      // graves animent le cœur, les médiums la couche intermédiaire et une
      // partie de la coque, les aigus le reste de la périphérie.
      final rr = _rayon[i];
      final coeur = 1 - _lisse((rr - 0.4) / 0.35);
      final peripherie = _lisse((rr - 0.82) / 0.12);
      final partAigus = peripherie * (0.35 + 0.65 * _reactivite[i]);
      _zoneG[i] = coeur;
      _zoneA[i] = partAigus;
      _zoneM[i] = (1 - coeur - partAigus).clamp(0.0, 1.0);
      // Cube : les particules internes et 30 % de la coque dessinent les
      // arêtes (structure lisible) ; les autres suggèrent les faces.
      _arete[i] = i >= couche || (i >= surface && i % 3 == 0) || i % 10 < 3
          ? 1
          : 0;

      // Ressort propre à chaque particule (inertie légèrement variable).
      final k = PimReglages.raideur * (0.75 + 0.5 * _reactivite[i]);
      _k[i] = k;
      _c[i] = 2 * PimReglages.amortissement * math.sqrt(k);

      // Place autour du champ : position sur le contour, écart au bord
      // (plus de particules près du bord), sens de circulation.
      _contour[i] = hasard.nextDouble();
      // Position dans la bande, de 0 (bord) à 1 (extérieur) ; plus de
      // particules près du bord.
      _ecart[i] = math.pow(hasard.nextDouble(), 1.6).toDouble();
      _sens[i] = hasard.nextDouble() < 0.7 ? 1 : -0.6;
      // Les particules du bas partent les premières vers le champ.
      _retard[i] = 0.28 * (_dirY[i] + 1) / 2 + 0.07 * hasard.nextDouble();
    }
    for (var i = 0; i < n; i++) {
      _parStyle[_style[i]]++;
    }
    // Tirage propre aux formes secondaires (réacteur), avec son propre
    // hasard : la sphère et le cube restent identiques au pixel près.
    final tirage = math.Random(13);
    for (var i = 0; i < n; i++) {
      _tirage[i] = tirage.nextDouble();
    }
    tampons = List.generate(
      profondeurs * nombreStyles,
      (k) => Float32List(_parStyle[k % nombreStyles] * 2),
    );
  }

  final PimController _controleur;
  static const n = PimReglages.nombre;

  static final double _partNonMicro = PimRendu.styles
      .where((s) => !s.micro)
      .fold(0.0, (somme, s) => somme + s.part);

  /// Style tiré parmi les micro-particules ou les autres, selon leurs parts.
  static int _tirerStyle(bool nonMicro, double tirage) {
    const styles = PimRendu.styles;
    final total = nonMicro ? _partNonMicro : 1 - _partNonMicro;
    var reste = tirage * total;
    var dernier = 0;
    for (var k = 0; k < styles.length; k++) {
      if (styles[k].micro == nonMicro) continue;
      dernier = k;
      if (reste < styles[k].part) return k;
      reste -= styles[k].part;
    }
    return dernier;
  }

  // Paramètres propres à chaque particule, tirés une seule fois.
  final _dirX = Float32List(n), _dirY = Float32List(n), _dirZ = Float32List(n);
  final _rayon = Float32List(n);
  final _phase = Float32List(n);
  final _vitesseIndiv = Float32List(n);
  final _reactivite = Float32List(n);
  final _parallaxe = Float32List(n);
  final _style = Uint8List(n);
  final _satellite = Uint8List(n);
  final _k = Float32List(n), _c = Float32List(n);
  final _contour = Float32List(n);
  final _ecart = Float32List(n);
  final _sens = Float32List(n);
  final _retard = Float32List(n);
  final _zoneG = Float32List(n), _zoneM = Float32List(n);
  final _zoneA = Float32List(n);
  final _arete = Uint8List(n);
  final _tirage = Float32List(n);

  // Géométries préparées (tétraèdre, réacteur) : forme secondaire en cours,
  // forme principale, et ancienne forme principale pendant un changement.
  // Calculées une fois par apparition ou par changement, jamais allouées
  // ensuite.
  final _geoSecondaire = _Geometrie(n);
  final _geoPrincipale = _Geometrie(n);
  final _geoAncienne = _Geometrie(n);

  // Forme principale (sphère par défaut) et changement en cours.
  FormePim _principale = FormePim.sphere;
  FormePim _ancienne = FormePim.sphere;
  double _transitionPrincipale = 1;
  double _lacetPrincipal = 0, _lacetAncien = 0;

  /// Durée du passage d'une forme principale à une autre (s).
  static const dureeChangementPrincipale = 2.4;

  void changerPrincipale(FormePim forme, {bool immediat = false}) {
    if (forme == _principale) return;
    // Une forme secondaire en cours se défait d'abord (retour rapide).
    _formes.interrompre();
    _formes.principale = forme;
    _ancienne = _principale;
    _lacetAncien = _lacetPrincipal;
    _geoAncienne.copier(_geoPrincipale);
    _principale = forme;
    _transitionPrincipale = immediat ? 1 : 0;
    _preparerPrincipale();
  }

  // État physique (repère du calque, z vers l'observateur, en px).
  final _x = Float32List(n), _y = Float32List(n), _z = Float32List(n);
  final _vx = Float32List(n), _vy = Float32List(n), _vz = Float32List(n);
  final _repX = Float32List(n), _repY = Float32List(n);
  bool _initialise = false;

  bool mouvementReduit = false;

  // Temps et valeurs lissées.
  double _t = 0;
  double _lacet = 0;
  // Rotation qui décale les particules entre elles (parallaxe) ; elle se
  // fige pendant le cube pour que sa structure reste nette.
  double _derive = 0;
  double _tourbillon = 0;
  double _flux = 0;
  double _ecoute = 0;
  double _reflexion = 0;
  double _parole = 0;
  double _energie = 0;
  // Lissage du second ordre des états vocaux (départ en douceur).
  final _lisseEcoute = Lisseur();
  final _lisseReflexion = Lisseur();
  final _lisseParole = Lisseur();
  // Montée douce d'énergie pendant la réflexion (avant de parler).
  double _anticipation = 0;
  final _enveloppe = EnveloppeParole();
  // Flottement vertical de la sphère (px), pour l'ombre.
  double _flotteY = 0;

  // Voix : mémoire courte, ondes, événements de la parole de JARVIS.
  final _memoire = MemoireEnergie();
  final _ondes = OndesPim();
  final _formes = FormesPim();
  int _cyclePrepare = 0;
  int _phrasesVues = -1, _motsVus = -1;
  double _debutPhrase = -1e9;
  double _derniereOnde = -1e9;

  /// Avancement de la transformation centre (0) → champ (1).
  double morph = 0;

  // Repères courants, utilisés aussi par le peintre.
  double _cx = 0, _cy = 0, _rayonEcran = 100;
  Rect? _champ;

  // Point et normale sortante sur le contour (évite d'allouer des Offset).
  double _pcX = 0, _pcY = 0, _ncX = 0, _ncY = 0;

  void avancer(double dt, Size taille, Rect centre, Rect? champ) {
    _t += dt;
    final c = _controleur;
    final etat = c.etatVocal;

    double vers(double actuel, double cible, double vitesse) =>
        actuel + (cible - actuel) * (1 - math.exp(-vitesse * dt));

    double etatVers(Lisseur l, bool actif, double entree, double sortie) =>
        l.avancer(actif ? 1 : 0, actif ? entree : sortie, dt);
    _ecoute = etatVers(
      _lisseEcoute,
      etat == VoiceState.listening,
      PimReglages.entreeEcoute,
      PimReglages.sortieEcoute,
    );
    _reflexion = etatVers(
      _lisseReflexion,
      etat == VoiceState.thinking,
      PimReglages.entreeReflexion,
      PimReglages.sortieReflexion,
    );
    _parole = etatVers(
      _lisseParole,
      etat == VoiceState.speaking,
      PimReglages.entreeParole,
      PimReglages.sortieParole,
    );
    _anticipation = vers(
      _anticipation,
      etat == VoiceState.thinking ? 1 : 0,
      etat == VoiceState.thinking ? 0.9 : 2.5,
    );
    _suivreVoix(etat, c.signal);
    var amplitude = etat == null ? 0.0 : (c.amplitude?.value ?? 0);
    // JARVIS parle : l'enveloppe reconstruite mot par mot (syllabes,
    // pauses) remplace les impulsions brutes.
    if (etat == VoiceState.speaking && c.signal != null) {
      amplitude = math.max(_enveloppe.valeur(_t), 0.25 * amplitude);
    }
    _memoire.avancer(dt, amplitude, etat == null ? null : c.signal);
    _energie = vers(_energie, c._frappeRecente && c._versChamp ? 1 : 0, 2.5);

    // Formation visée. Le dernier rectangle connu du champ sert encore
    // pendant le retour (le champ peut disparaître en mode vocal).
    if (champ != null) _champ = champ;
    final versChamp = c._versChamp && _champ != null;
    final pas = dt / PimReglages.dureeTransition;
    morph = (morph + (versChamp ? pas : -pas)).clamp(0.0, 1.0);

    // Formes secondaires : seulement au vrai repos (pas de voix, de frappe,
    // de focus ni de trajet).
    _formes.avancer(
      dt,
      calme:
          etat == null &&
          !mouvementReduit &&
          !c.saisieFocus &&
          !c._versChamp &&
          morph < 0.001 &&
          c._depuisEnvoi > 2,
    );
    // Aperçu demandé dans les Paramètres (après le cycle : sa fin est vue
    // dès l'image où la sphère est revenue).
    c._suivreApercu();
    if (_formes.cycle != _cyclePrepare && _initialise) {
      _cyclePrepare = _formes.cycle;
      _preparerForme();
    }

    final mouvement = mouvementReduit ? 0.0 : 1.0;
    final rotation =
        dt *
        mouvement *
        (PimReglages.vitesseRotation * (1 - 0.5 * _formes.stabilisation) +
            0.25 * _parole +
            0.12 * _memoire.energie +
            0.35 * _reflexion);
    _lacet += rotation;
    // La parallaxe ne sert qu'à la sphère principale : figée sinon, pour
    // que les géométries préparées restent alignées sur les particules.
    if (_principale == FormePim.sphere && _transitionPrincipale >= 1) {
      _derive += rotation * (1 - _formes.stabilisation);
    }
    if (_transitionPrincipale < 1) {
      _transitionPrincipale = math.min(
        1,
        _transitionPrincipale + dt / dureeChangementPrincipale,
      );
    }
    _tourbillon += dt * _reflexion * (mouvementReduit ? 0.6 : 2.0);
    _flux +=
        dt *
        mouvement *
        (PimReglages.fluxCalme +
            (PimReglages.fluxActif - PimReglages.fluxCalme) * _energie);

    _cx = centre.center.dx;
    _cy = centre.center.dy;
    _rayonEcran = centre.shortestSide * 0.36;

    if (!_initialise) {
      _initialiser();
      _initialise = true;
    }
    _ondes.preparer(_t);
    var chrono = ChronoPerf.debut();
    _calculerRepulsion(taille);
    ChronoPerf.fin('pim.repulsion', chrono);
    chrono = ChronoPerf.debut();
    _integrer(dt, mouvement, taille);
    ChronoPerf.fin('pim.integration', chrono);
    notifyListeners();
  }

  /// Transforme les événements de la voix en ondes.
  ///
  /// JARVIS parle : chaque phrase commence par une petite préparation puis
  /// une impulsion du centre vers l'extérieur ; chaque mot envoie une onde
  /// proportionnelle à son accent. L'utilisateur parle : chaque attaque de
  /// la voix envoie une onde du bord vers le centre (réception).
  void _suivreVoix(VoiceState? etat, SignalVocal? signal) {
    if (signal != null) {
      if (signal.phrases != _phrasesVues) {
        if (_phrasesVues >= 0 && etat != null) {
          _debutPhrase = _t;
          _ondes.lancer(_t + 0.3, 0.8, emission: true);
        }
        _phrasesVues = signal.phrases;
      }
      if (signal.mots != _motsVus) {
        if (_motsVus >= 0 && etat == VoiceState.speaking) {
          _enveloppe.mot(_t, signal.accent, signal.dureeMot, signal.syllabes);
          // Seuls les mots portés (accent) envoient une onde visible : le
          // rythme reste lisible sans devenir une pulsation continue.
          if (signal.accent > 0.45 ||
              _t - _derniereOnde >
                  PimDynamiqueReglages.intervalleReception * 2) {
            _ondes.lancer(_t, 0.3 + 0.7 * signal.accent, emission: true);
            _derniereOnde = _t;
          }
        }
        _motsVus = signal.mots;
      }
    }
    // Attaques de la voix (montée nette au-dessus de la mémoire courte).
    // Pour JARVIS, seulement si la plateforme ne signale pas les mots.
    final attaque = _memoire.instant > _memoire.memoire * 1.08 + 0.1;
    if (!attaque ||
        _t - _derniereOnde < PimDynamiqueReglages.intervalleReception) {
      return;
    }
    if (etat == VoiceState.listening) {
      _ondes.lancer(_t, math.min(1.0, _memoire.instant), emission: false);
      _derniereOnde = _t;
    } else if (etat == VoiceState.speaking && signal == null) {
      _ondes.lancer(_t, math.min(1.0, _memoire.instant), emission: true);
      _derniereOnde = _t;
    }
  }

  void _initialiser() {
    for (var i = 0; i < n; i++) {
      _x[i] = _cx + _dirX[i] * _rayon[i] * _rayonEcran;
      _y[i] = _cy - _dirY[i] * _rayon[i] * _rayonEcran;
      _z[i] = _dirZ[i] * _rayon[i] * _rayonEcran;
    }
  }

  static double _lisse(double v) {
    final x = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
    return x * x * (3 - 2 * x);
  }

  void _integrer(double dt, double mouvement, Size taille) {
    final rayon = _rayonEcran;
    final champ = _champ;
    final t = _t;

    // Inclinaison vers l'avant, avec un lent balancement de l'axe.
    // Pendant le cube, la vue s'incline un peu plus pour montrer trois
    // faces.
    final inclinaison =
        -0.32 -
        _formes.forme.inclinaison * _formes.stabilisation +
        PimReglages.precession * math.sin(t * 0.13) * mouvement;
    final ci = math.cos(inclinaison), si = math.sin(inclinaison);
    const voix = PimReglages.reactionVocale;
    const ondulation = PimReglages.ondulation;
    // Petite sphère (téléphone) : dispersion et ondes un peu retenues, pour
    // que la silhouette reste nette ; flottement jamais imperceptible.
    final ample = ((rayon - 80) / 90).clamp(0.0, 1.0);
    final dispersion =
        PimReglages.dispersionMax *
        (PimReglages.dispersionCompacte +
            (1 - PimReglages.dispersionCompacte) * ample);
    final ampleurOndes = 0.85 + 0.15 * ample;

    // Avant et pendant le cube, la sphère se calme (sans s'arrêter).
    final stab = _formes.stabilisation;
    final vivant = mouvement * PimReglages.energieMouvement * (1 - 0.6 * stab);
    final respiration =
        1 + PimReglages.respiration * math.sin(t * 0.9) * vivant;

    // Voix : énergie avec mémoire courte, et bandes par zone.
    final energie = _memoire.energie;
    final graves = _memoire.graves * voix;
    final mediums = _memoire.mediums * voix;
    final aigus = _memoire.aigus * voix;
    // Parole : l'ampleur suit la phrase (mots accentués, pauses) ; les
    // passages calmes bougent moins.
    final enveloppe = _parole * math.max(0.15, energie) * voix;
    final ecouteVoix = _ecoute * voix;
    // Vibration fine (aigus) : plus visible à l'écoute, plus maîtrisée
    // quand JARVIS parle.
    final vibration =
        (_ecoute + 0.4 * _parole) *
        voix *
        rayon *
        PimReglages.vibrationEcoute *
        mouvement;
    final profond =
        (_ecoute + 0.6 * _parole) * PimReglages.mouvementGraves * mouvement;
    // Début de phrase : petite contraction juste avant l'impulsion.
    final depuisPhrase = t - _debutPhrase;
    final x = (depuisPhrase - 0.16) / 0.12;
    final preparation = depuisPhrase < 0.7
        ? PimReglages.preparationParole * math.exp(-x * x)
        : 0.0;
    final ondes = _ondes.actives;
    final flotteCentre =
        math.max(rayon * PimReglages.flottementCentre, 2.0) * vivant;
    // Toute la sphère flotte lentement au-dessus de son ombre.
    _flotteY =
        rayon *
        PimReglages.flottementSphere *
        vivant *
        (math.sin(t * 0.55) * 0.7 + math.sin(t * 0.23 + 1) * 0.3);

    // Forme secondaire : avancement global, rotation commune (sans
    // parallaxe).
    final forme = _formes.forme;
    final avance = _formes.progres;
    final cube = forme == FormePim.cube ? avance : 0.0;
    final sphereSecondaire = forme == FormePim.sphere ? avance : 0.0;
    final autreForme = forme == FormePim.tetraedre || forme == FormePim.reacteur
        ? avance
        : 0.0;
    // Tétraèdre : il tourne lentement avec la sphère. Réacteur : tourné
    // vers l'utilisateur, il oscille doucement (jamais vu par la tranche).
    final reacteur = forme == FormePim.reacteur;
    final lacetForme = reacteur
        ? 0.32 * math.sin(t * 0.42) * mouvement
        : _lacet - _lacetDepart + _decalageTetraedre;
    final penteForme = reacteur
        ? -0.08 + 0.07 * math.sin(t * 0.31) * mouvement
        : inclinaison;
    final fcl = math.cos(lacetForme), fsl = math.sin(lacetForme);
    final fci = math.cos(penteForme), fsi = math.sin(penteForme);
    // Noyau du réacteur : pulsation très discrète, seulement une fois formé.
    final pulsation = reacteur
        ? 0.07 * math.sin(t * 2.6) * autreForme * mouvement
        : 0.0;
    // Forme principale autre que la sphère (ou changement en cours) : ses
    // particules gardent les réactions de la sphère (échelle radiale).
    final principale =
        _principale != FormePim.sphere || _transitionPrincipale < 1;
    final precession = PimReglages.precession * math.sin(t * 0.13) * mouvement;
    final (pLacet, pPente) = _orientation(
      _principale,
      _lacetPrincipal,
      t,
      mouvement,
      precession,
    );
    final (aLacet, aPente) = _orientation(
      _ancienne,
      _lacetAncien,
      t,
      mouvement,
      precession,
    );
    final pcl = math.cos(pLacet), psl = math.sin(pLacet);
    final pci = math.cos(pPente), psi = math.sin(pPente);
    final acl = math.cos(aLacet), asl = math.sin(aLacet);
    final aci = math.cos(aPente), asi = math.sin(aPente);
    // Réacteur principal : noyau vivant, pulsation plus marquée pendant la
    // réflexion et la parole.
    final pulsationPrincipale =
        mouvement *
        (0.03 * math.sin(t * 1.3) +
            (0.09 * _reflexion + 0.05 * _parole) * math.sin(t * 2.6));
    // Cube tourné de 45° : on le voit par une arête, pas de face.
    const quart = math.pi / 4;
    final cl0 = math.cos(_lacet + quart), sl0 = math.sin(_lacet + quart);
    const demiCote = PimDynamiqueReglages.demiCoteCube;
    final flotteChamp =
        mouvement *
        (PimReglages.flottementChamp +
            (PimReglages.flottementChampActif - PimReglages.flottementChamp) *
                _energie);

    // Repères du champ et de l'étirement intermédiaire.
    double perimetre = 0, rayonCoin = 0, etirX = 1, etirY = 1;
    double champCx = _cx, champCy = _cy, demiLargeur = 1;
    if (champ != null) {
      rayonCoin = math.min(14.0, champ.shortestSide / 2);
      perimetre =
          2 * (champ.width - 2 * rayonCoin) +
          2 * (champ.height - 2 * rayonCoin) +
          2 * math.pi * rayonCoin;
      champCx = champ.center.dx;
      champCy = champ.center.dy;
      demiLargeur = champ.width / 2;
      etirX = math.max(1.0, demiLargeur * 0.9 / rayon);
      etirY = math.max(0.2, champ.height * 0.6 / rayon);
    }

    // Largeur de bande pour garder un espacement régulier, puis place
    // disponible de chaque côté (la bande se resserre au bord de l'écran).
    var bande = PimReglages.bandeMin;
    var placeHaut = 1.0, placeBas = 1.0, placeGauche = 1.0, placeDroite = 1.0;
    if (champ != null && perimetre > 0) {
      const e = PimReglages.espacementChamp;
      bande = (n * e * e / perimetre - PimReglages.ecartChampMin).clamp(
        PimReglages.bandeMin,
        PimReglages.bandeMax,
      );
      final total = PimReglages.ecartChampMin + bande;
      double place(double marge) => ((marge - 3) / total).clamp(0.15, 1.0);
      placeHaut = place(champ.top);
      placeBas = place(taille.height - champ.bottom);
      placeGauche = place(champ.left);
      placeDroite = place(taille.width - champ.right);
    }
    final depuisEnvoi = _controleur._depuisEnvoi;
    // Un sous-pas par 1/60 s, avec une tolérance de 10 % : une image à
    // 16,8 ms (rythme réel du navigateur) ne double pas le calcul.
    final sousPas = (dt * 60).ceil().clamp(1, 6);
    // La vibration n'existe qu'en mode vocal : sans elle, on évite un sinus
    // par particule.
    final vibre = vibration > 1e-4;
    final h = dt / sousPas;

    for (var i = 0; i < n; i++) {
      final ph = _phase[i];
      final f = _vitesseIndiv[i];

      // ---- Cible au centre (structure 3D) --------------------------------
      var dx = _dirX[i], dy = _dirY[i], dz = _dirZ[i];
      final r = _rayon[i];

      // Réflexion : les particules intérieures tournent plus vite.
      if (_reflexion > 0.01) {
        final a = _tourbillon * (1.3 - r);
        final ca = math.cos(a), sa = math.sin(a);
        final nx = dx * ca - dz * sa;
        dz = dx * sa + dz * ca;
        dx = nx;
      }

      // Rayon de base : respiration et ondulation lente de toute la sphère.
      final base =
          r *
          respiration *
          (1 + ondulation * vivant * math.sin(dy * 3 + dx * 2 + t * 0.8));
      var echelle = base;
      // Bande qui anime cette particule (graves au cœur, aigus au bord).
      final zg = _zoneG[i], za = _zoneA[i];
      final bande = zg * graves + _zoneM[i] * mediums + za * aigus;
      // Écoute : légère ouverture, puis la sphère gonfle par zones (bosses
      // locales qui se déplacent) selon la bande de chaque particule.
      if (_ecoute > 0.001) {
        final zone = 0.6 + 0.4 * math.sin(dx * 4 + dz * 3 + t * 1.8);
        echelle +=
            _ecoute * PimReglages.ouvertureEcoute * r +
            ecouteVoix *
                bande *
                zone *
                (PimReglages.expansionEcoute +
                    PimReglages.expansionEcouteVariable * _reactivite[i]);
      }
      // Graves : mouvement lent et profond du cœur.
      if (profond > 0.001 && zg > 0.01) {
        echelle += profond * graves * zg * math.sin(t * 1.5 * f + ph);
      }
      // Réflexion : concentration vers le centre, avec une pulsation
      // interne régulière (le « calcul »).
      if (_reflexion > 0.001) {
        echelle -=
            _reflexion *
            r *
            (0.1 + 0.025 * (0.5 + 0.5 * math.sin(t * 2.6 - r * 7)));
      }
      // Parole : vagues qui traversent la masse, au rythme de la phrase.
      if (enveloppe > 0.001) {
        echelle +=
            enveloppe *
            PimReglages.vaguesParole *
            (0.5 + 0.5 * math.sin(dy * 4 - t * 4.5 + ph * 0.3));
      }
      echelle -= preparation * r;
      // Ondes d'émission (vers l'extérieur) ou de réception (vers le
      // centre).
      if (ondes) {
        echelle +=
            voix *
            _ondes.valeur(
              r,
              PimReglages.ondeEmission * ampleurOndes,
              PimReglages.ondeReception * ampleurOndes,
            );
      }
      // Dispersion bornée : la sphère peut s'ouvrir, jamais se défaire.
      final bas = base * 0.6, haut = base + dispersion;
      if (echelle < bas) {
        echelle = bas;
      } else if (echelle > haut) {
        echelle = haut;
      }

      dx *= echelle;
      dy *= echelle;
      dz *= echelle;

      // Rotation propre à la particule (vitesse légèrement différente) :
      // vraie rotation, donc la distance au centre est conservée quel que
      // soit le temps écoulé.
      final ecartAngle =
          2 * PimReglages.parallaxeRotation * _parallaxe[i] * _derive;
      final angle = _lacet + ecartAngle;
      final cl = math.cos(angle), sl = math.sin(angle);
      final rx = dx * cl - dz * sl;
      var rz = dx * sl + dz * cl;
      final ry = dy * ci - rz * si;
      rz = dy * si + rz * ci;

      var cibleX = _cx + rx * rayon;
      var cibleY = _cy - ry * rayon + _flotteY;
      var cibleZ = rz * rayon;
      // Point de la sphère (forme secondaire « sphère »).
      final sphereX = cibleX, sphereY = cibleY, sphereZ = cibleZ;

      // ---- Forme principale ------------------------------------------------
      if (principale) {
        // Mêmes réactions que la sphère : la respiration (proportionnelle)
        // et les réactions de la voix (écoute, réflexion, parole, ondes),
        // ajoutées comme pour une particule de la coque. Sur une forme,
        // toutes les particules sont en surface : une réaction n'est jamais
        // amplifiée par un petit rayon de repos.
        final facteur = base / math.max(r, 0.05) + (echelle - base);
        if (_principale != FormePim.sphere) {
          _cibleForme(
            i,
            _principale,
            _geoPrincipale,
            pcl,
            psl,
            pci,
            psi,
            facteur,
            pulsationPrincipale,
            ecartAngle,
            rayon,
          );
        } else {
          _tx = sphereX;
          _ty = sphereY;
          _tz = sphereZ;
          _tOrdre = 0.5;
        }
        if (_transitionPrincipale < 1) {
          final nx = _tx, ny = _ty, nz = _tz;
          final ordre = _tOrdre;
          if (_ancienne != FormePim.sphere) {
            _cibleForme(
              i,
              _ancienne,
              _geoAncienne,
              acl,
              asl,
              aci,
              asi,
              facteur,
              pulsationPrincipale,
              ecartAngle,
              rayon,
            );
          } else {
            _tx = sphereX;
            _ty = sphereY;
            _tz = sphereZ;
          }
          final p = _lisse(_transitionPrincipale * 1.4 - 0.4 * ordre);
          cibleX = _tx + (nx - _tx) * p;
          cibleY = _ty + (ny - _ty) * p;
          cibleZ = _tz + (nz - _tz) * p;
        } else {
          cibleX = _tx;
          cibleY = _ty;
          cibleZ = _tz;
        }
      }

      // ---- Forme secondaire : sphère (forme principale ≠ sphère) --------
      if (sphereSecondaire > 0) {
        final ps = _lisse(sphereSecondaire * 1.4 - 0.4 * (1 - r));
        cibleX += (sphereX - cibleX) * ps;
        cibleY += (sphereY - cibleY) * ps;
        cibleZ += (sphereZ - cibleZ) * ps;
      }

      // ---- Forme secondaire : tétraèdre, réacteur ------------------------
      if (autreForme > 0) {
        // Ordre d'arrivée propre à la forme (sommets, arêtes, faces ;
        // anneau, arcs, triangle, noyau).
        final g = _geoSecondaire;
        final pf = _lisse(autreForme * 1.4 - 0.4 * g.ordre[i]);
        if (pf > 0) {
          final taille = respiration * (1 + pulsation * g.pulse[i]);
          final qx = g.x[i] * taille, qy = g.y[i] * taille;
          final qz = g.z[i] * taille;
          final kx = qx * fcl - qz * fsl;
          var kz = qx * fsl + qz * fcl;
          final ky = qy * fci - kz * fsi;
          kz = qy * fsi + kz * fci;
          cibleX += (_cx + kx * rayon - cibleX) * pf;
          cibleY += (_cy - ky * rayon + _flotteY - cibleY) * pf;
          cibleZ += (kz * rayon - cibleZ) * pf;
        }
      }

      // ---- Forme secondaire : cube --------------------------------------
      if (cube > 0) {
        _cibleCube(i, ecartAngle - quart);
        // Les coins se forment d'abord, puis les arêtes, puis les faces ;
        // au retour, les faces se défont les premières.
        final pc = _lisse(cube * 1.4 - 0.4 * _versCoin);
        if (pc > 0) {
          final taille = demiCote * respiration;
          final qx = _qx * taille, qy = _qy * taille, qz = _qz * taille;
          final kx = qx * cl0 - qz * sl0;
          var kz = qx * sl0 + qz * cl0;
          final ky = qy * ci - kz * si;
          kz = qy * si + kz * ci;
          cibleX += (_cx + kx * rayon - cibleX) * pc;
          cibleY += (_cy - ky * rayon + _flotteY - cibleY) * pc;
          cibleZ += (kz * rayon - cibleZ) * pc;
        }
      }

      // Flottement individuel au centre, plus la vibration des aigus.
      final flotte = flotteCentre * (1 - morph);
      cibleX += math.sin(t * 0.6 * f + ph) * flotte;
      if (vibre) {
        cibleX +=
            vibration *
            (0.4 * energie + 0.6 * za * aigus) *
            math.sin(t * 8 * f + ph);
      }
      cibleY += math.cos(t * 0.5 * f + ph * 1.7) * flotte;
      cibleZ += math.sin(t * 0.4 * f + ph * 2.3) * flotte;

      // ---- Transformation vers le champ ----------------------------------
      if (morph > 0.0005 && champ != null) {
        // Avancement propre à la particule (départ décalé).
        final p = ((morph - _retard[i]) / (1 - 0.35)).clamp(0.0, 1.0);
        final descente = _lisse(p / 0.45);
        final etirement = _lisse((p - 0.15) / 0.45);
        final arrivee = _lisse((p - 0.4) / 0.6);

        // 1-2 : la masse descend vers le champ et s'étire à l'horizontale.
        final relX = cibleX - _cx, relY = cibleY - _cy;
        final sx = 1 + (etirX - 1) * etirement;
        final sy = 1 + (etirY - 1) * etirement;
        final ex = _cx + (champCx - _cx) * descente + relX * sx;
        final ey = _cy + (champCy - _cy) * descente + relY * sy;
        final ez = cibleZ * (1 - 0.7 * etirement);

        // 3-4 : place autour du contour, qui circule lentement.
        if (arrivee > 0) {
          var s = (_contour[i] * perimetre + _flux * _sens[i] * f) % perimetre;
          if (s < 0) s += perimetre;
          _pointContour(champ, rayonCoin, s);
          // Resserrement selon le côté (les coins mélangent deux côtés).
          final place =
              1 -
              (math.max(_ncY, 0) * (1 - placeBas) +
                  math.max(-_ncY, 0) * (1 - placeHaut) +
                  math.max(_ncX, 0) * (1 - placeDroite) +
                  math.max(-_ncX, 0) * (1 - placeGauche));
          var ecart =
              (PimReglages.ecartChampMin + bande * _ecart[i]) *
              place.clamp(0.15, 1.0);

          // Impulsion d'envoi : une onde part du centre vers les côtés.
          if (depuisEnvoi < 0.9) {
            final retard =
                (_pcX - champCx).abs() /
                demiLargeur *
                PimReglages.impulsionPropagation;
            final l = depuisEnvoi - retard;
            ecart += PimReglages.impulsionAmplitude * math.exp(-l * l / 0.006);
          }

          final bx =
              _pcX + _ncX * ecart + math.sin(t * 0.9 * f + ph) * flotteChamp;
          final by =
              _pcY +
              _ncY * ecart +
              math.cos(t * 0.8 * f + ph * 1.3) * flotteChamp;
          final bz = rayon * 0.06 * math.sin(t * 0.7 * f + ph);

          cibleX = ex + (bx - ex) * arrivee;
          cibleY = ey + (by - ey) * arrivee;
          cibleZ = ez + (bz - ez) * arrivee;
        } else {
          cibleX = ex;
          cibleY = ey;
          cibleZ = ez;
        }
      }

      // ---- Physique : accélération → vitesse → position ------------------
      // Petits pas (≤ 1/60 s) même si l'image arrive tard : le mouvement
      // reste stable quel que soit le rythme d'affichage.
      final k = _k[i], amort = _c[i];
      final repX = _repX[i], repY = _repY[i];
      // Au centre (pas pendant les trajets vers le champ), une particule
      // trop écartée de sa cible est rappelée plus fort.
      final rappel = morph < 0.001 ? PimReglages.rappelHorsZone : 0.0;
      final zoneLibre = PimReglages.zoneLibre * rayon;
      var x = _x[i], y = _y[i], z = _z[i];
      var vx = _vx[i], vy = _vy[i], vz = _vz[i];
      for (var etape = 0; etape < sousPas; etape++) {
        final ex = cibleX - x, ey = cibleY - y, ez = cibleZ - z;
        var kx = k;
        if (rappel > 0) {
          final d = math.sqrt(ex * ex + ey * ey + ez * ez);
          if (d > zoneLibre) kx += rappel * (d - zoneLibre) / d;
        }
        vx += (kx * ex - amort * vx + repX) * h;
        vy += (kx * ey - amort * vy + repY) * h;
        vz += (kx * ez - amort * vz) * h;

        final v2 = vx * vx + vy * vy + vz * vz;
        const vMax = PimReglages.vitesseMax;
        if (v2 > vMax * vMax) {
          final s = vMax / math.sqrt(v2);
          vx *= s;
          vy *= s;
          vz *= s;
        }
        x += vx * h;
        y += vy * h;
        z += vz * h;
      }
      // La profondeur reste bornée : une particule ne passe jamais « devant
      // la caméra » (elle serait projetée loin du centre).
      final zMax = rayon * 1.6;
      if (z > zMax) {
        z = zMax;
        vz = 0;
      } else if (z < -zMax) {
        z = -zMax;
        vz = 0;
      }
      _x[i] = x;
      _y[i] = y;
      _z[i] = z;
      _vx[i] = vx;
      _vy[i] = vy;
      _vz[i] = vz;
    }
  }

  // Point du cube visé par une particule (résultat dans _qx/_qy/_qz, sur
  // la surface du cube de côté 2) et sa distance au coin le plus proche
  // (0 à 1, dans _versCoin).
  double _qx = 0, _qy = 0, _qz = 0, _versCoin = 0;

  static double _versBord(double u) => u * (1.5 - 0.5 * u * u);

  void _cibleCube(int i, double ecartAngle) {
    // Direction de la particule dans le repère commun (sans son écart de
    // rotation) : elle rejoint le point du cube le plus proche, sans
    // traverser la sphère.
    final ce = math.cos(ecartAngle), se = math.sin(ecartAngle);
    final ox = _dirX[i] * ce - _dirZ[i] * se;
    final oz = _dirX[i] * se + _dirZ[i] * ce;
    final oy = _dirY[i];
    final ax = ox.abs(), ay = oy.abs(), az = oz.abs();
    final m = math.max(ax, math.max(ay, az));
    var qx = ox / m, qy = oy / m, qz = oz / m;
    // Les particules s'écartent du centre des faces vers les arêtes (faces
    // suggérées, arêtes lisibles), et une partie se place exactement sur
    // une arête.
    final arete = _arete[i] == 1;
    if (ax == m) {
      qy = _versBord(qy);
      qz = _versBord(qz);
      if (arete) {
        if (qy.abs() > qz.abs()) {
          qy = qy.sign;
        } else {
          qz = qz.sign;
        }
      }
    } else if (ay == m) {
      qx = _versBord(qx);
      qz = _versBord(qz);
      if (arete) {
        if (qx.abs() > qz.abs()) {
          qx = qx.sign;
        } else {
          qz = qz.sign;
        }
      }
    } else {
      qx = _versBord(qx);
      qy = _versBord(qy);
      if (arete) {
        if (qx.abs() > qy.abs()) {
          qx = qx.sign;
        } else {
          qy = qy.sign;
        }
      }
    }
    final dcx = 1 - qx.abs(), dcy = 1 - qy.abs(), dcz = 1 - qz.abs();
    _versCoin = math.min(
      1.0,
      math.sqrt(dcx * dcx + dcy * dcy + dcz * dcz) / 1.42,
    );
    _qx = qx;
    _qy = qy;
    _qz = qz;
  }

  // ---- Formes secondaires préparées --------------------------------------

  /// Au départ, un sommet de la base est tourné vers l'utilisateur,
  /// légèrement de biais ; le tétraèdre tourne ensuite lentement avec la
  /// sphère.
  static const _decalageTetraedre = -0.5;

  // Rotation de la sphère quand la forme a été préparée.
  double _lacetDepart = 0;

  /// Rayon circonscrit du tétraèdre (en rayons de la sphère) : même
  /// présence que le cube.
  static const _rayonTetraedre = 1.1;

  /// Sommets du tétraèdre régulier, un sommet en haut.
  static final List<List<double>> _sommets = () {
    const r = _rayonTetraedre;
    final horizontal = r * 2 * math.sqrt(2) / 3;
    return [
      [0.0, r, 0.0],
      for (var k = 0; k < 3; k++)
        [
          horizontal * math.cos(math.pi / 2 + k * 2 * math.pi / 3),
          -r / 3,
          horizontal * math.sin(math.pi / 2 + k * 2 * math.pi / 3),
        ],
    ];
  }();

  /// Prépare la forme qui commence, à partir de la position actuelle de
  /// chaque particule : elle rejoint le point le plus proche de la forme,
  /// sans traverser la sphère. Le cube, lui, est calculé à chaque image.
  void _preparerForme() {
    final forme = _formes.forme;
    if (forme == FormePim.cube || forme == FormePim.sphere) return;
    _lacetDepart = _lacet;
    _preparerGeometrie(forme, _geoSecondaire);
  }

  /// Prépare la forme principale (tétraèdre, réacteur) à partir de la
  /// position actuelle des particules.
  void _preparerPrincipale() {
    _lacetPrincipal = _lacet;
    if (_principale == FormePim.tetraedre || _principale == FormePim.reacteur) {
      _preparerGeometrie(_principale, _geoPrincipale);
    }
  }

  void _preparerGeometrie(FormePim forme, _Geometrie g) {
    // Inclinaison moyenne de la vue (balancement lent négligé).
    const pente = -0.32;
    final ci = math.cos(pente), si = math.sin(pente);
    for (var i = 0; i < n; i++) {
      final ecartAngle =
          2 * PimReglages.parallaxeRotation * _parallaxe[i] * _derive;
      if (forme == FormePim.tetraedre) {
        // Angle de la particule dans le repère du tétraèdre.
        _cibleTetraedre(i, _lacet + ecartAngle - _decalageTetraedre, g);
      } else {
        // Direction de la particule telle qu'on la voit à l'écran.
        final a = _lacet + ecartAngle;
        final ca = math.cos(a), sa = math.sin(a);
        final vx = _dirX[i] * ca - _dirZ[i] * sa;
        final vz = _dirX[i] * sa + _dirZ[i] * ca;
        final vy = _dirY[i] * ci - vz * si;
        final vz2 = _dirY[i] * si + vz * ci;
        _cibleReacteur(i, vx, vy, vz2, g);
      }
    }
  }

  /// Tétraèdre : la direction de la particule touche une face (projection
  /// depuis le centre) ; sur la face, elle s'écarte du centre vers les
  /// arêtes, et une partie se place exactement sur une arête (les mêmes
  /// particules que les arêtes du cube).
  void _cibleTetraedre(int i, double angle, _Geometrie g) {
    final ce = math.cos(angle), se = math.sin(angle);
    final dx = _dirX[i] * ce - _dirZ[i] * se;
    final dz = _dirX[i] * se + _dirZ[i] * ce;
    final dy = _dirY[i];
    final v = _sommets;
    // Face touchée : celle opposée au sommet le plus éloigné de la
    // direction (normale sortante = -sommet).
    var face = 0;
    var meilleur = -double.infinity;
    for (var k = 0; k < 4; k++) {
      final p = -(dx * v[k][0] + dy * v[k][1] + dz * v[k][2]);
      if (p > meilleur) {
        meilleur = p;
        face = k;
      }
    }
    // La face est à rayon / 3 du centre ; sa normale vaut -sommet / rayon.
    const r = _rayonTetraedre;
    final t = (r * r / 3) / math.max(meilleur, 1e-6);
    final px = dx * t, py = dy * t, pz = dz * t;
    final a = v[(face + 1) % 4], b = v[(face + 2) % 4], c = v[(face + 3) % 4];
    // Coordonnées barycentriques sur la face.
    final e0x = b[0] - a[0], e0y = b[1] - a[1], e0z = b[2] - a[2];
    final e1x = c[0] - a[0], e1y = c[1] - a[1], e1z = c[2] - a[2];
    final e2x = px - a[0], e2y = py - a[1], e2z = pz - a[2];
    final d00 = e0x * e0x + e0y * e0y + e0z * e0z;
    final d01 = e0x * e1x + e0y * e1y + e0z * e1z;
    final d11 = e1x * e1x + e1y * e1y + e1z * e1z;
    final d20 = e2x * e0x + e2y * e0y + e2z * e0z;
    final d21 = e2x * e1x + e2y * e1y + e2z * e1z;
    final den = d00 * d11 - d01 * d01;
    var bb = ((d11 * d20 - d01 * d21) / den).clamp(0.0, 1.0);
    var bc = ((d00 * d21 - d01 * d20) / den).clamp(0.0, 1.0);
    var ba = math.max(0.0, 1 - bb - bc);
    var somme = ba + bb + bc;
    ba /= somme;
    bb /= somme;
    bc /= somme;
    // Vers les arêtes : les faces restent suggérées, les arêtes lisibles.
    final m = math.min(ba, math.min(bb, bc));
    final vers = 1 - 3 * m;
    if (vers > 1e-4) {
      final k = (1 - math.pow(1 - vers, 1.8)) / vers;
      ba = 1 / 3 + (ba - 1 / 3) * k;
      bb = 1 / 3 + (bb - 1 / 3) * k;
      bc = 1 / 3 + (bc - 1 / 3) * k;
    }
    if (_arete[i] == 1) {
      if (ba <= bb && ba <= bc) {
        ba = 0;
      } else if (bb <= bc) {
        bb = 0;
      } else {
        bc = 0;
      }
      somme = ba + bb + bc;
      ba /= somme;
      bb /= somme;
      bc /= somme;
    }
    // Sommets : 4 % des particules forment un petit nœud lumineux sur le
    // sommet le plus proche (comme sur la référence).
    if (_tirage[i] < 0.04) {
      final s = ba >= bb && ba >= bc ? a : (bb >= bc ? b : c);
      g.x[i] = s[0] + dx * 0.045;
      g.y[i] = s[1] + dy * 0.045;
      g.z[i] = s[2] + dz * 0.045;
      g.ordre[i] = 0;
      g.pulse[i] = 0;
      return;
    }
    final qx = a[0] * ba + b[0] * bb + c[0] * bc;
    final qy = a[1] * ba + b[1] * bb + c[1] * bc;
    final qz = a[2] * ba + b[2] * bb + c[2] * bc;
    // Distance au sommet le plus proche (0 au sommet, 1 au centre d'une
    // face) : les sommets se forment d'abord, puis les arêtes, les faces.
    final arete = r * math.sqrt(8 / 3);
    var proche = double.infinity;
    for (final s in [a, b, c]) {
      final ex = qx - s[0], ey = qy - s[1], ez = qz - s[2];
      proche = math.min(proche, math.sqrt(ex * ex + ey * ey + ez * ez));
    }
    g.x[i] = qx;
    g.y[i] = qy;
    g.z[i] = qz;
    g.ordre[i] = math.min(1.0, proche / (arete / math.sqrt(3)));
    g.pulse[i] = 0;
  }

  /// Réacteur énergétique (d'après la référence, en particules PIM), dans
  /// le plan de l'écran avec un peu de profondeur :
  /// - anneau double (38 %), cadre discret ;
  /// - triangle pointe en bas, sommets contre l'anneau, tracé double (28 %) ;
  /// - nœuds aux sommets du triangle et sur l'anneau (5 %) ;
  /// - rayons de l'anneau vers le milieu des côtés du triangle (4 %) ;
  /// - noyau dense (12 %) entouré d'un cercle en pointillés (6 %) ;
  /// - deux arcs extérieurs très discrets, à gauche et à droite (7 %).
  /// Chaque particule garde son angle à l'écran : trajets courts.
  void _cibleReacteur(int i, double vx, double vy, double vz, _Geometrie g) {
    final u = _tirage[i];
    final theta = math.atan2(vy, vx);
    const tour = 2 * math.pi;
    const degre = math.pi / 180;
    // Fraction dans la catégorie, pour les choix secondaires.
    double dans(double debut, double fin) => (u - debut) / (fin - debut);
    double qx, qy, qz, ordre, pulse;
    if (u < 0.38) {
      // Anneau : deux cercles proches, l'un devant, l'autre derrière.
      final f = dans(0, 0.38);
      final r = (f * 977).floor().isEven ? 1.0 : 0.92;
      qx = r * math.cos(theta);
      qy = r * math.sin(theta);
      qz = (f * 631).floor().isEven ? 0.05 : -0.05;
      ordre = 0;
      pulse = 0;
    } else if (u < 0.45) {
      // Arcs extérieurs, à gauche et à droite (± 35°).
      final centre = math.cos(theta) >= 0 ? 0.0 : math.pi;
      var d = theta - centre;
      d = math.atan2(math.sin(d), math.cos(d));
      final a = centre + d * (35 / 90);
      final r = 1.13 + 0.05 * dans(0.38, 0.45);
      qx = r * math.cos(a);
      qy = r * math.sin(a);
      qz = -0.06;
      ordre = 0.25;
      pulse = 0;
    } else if (u < 0.73) {
      // Triangle pointe en bas (sommets à 30°, 150°, 270°), en avant de
      // l'anneau ; deux tracés parallèles.
      final f = dans(0.45, 0.73);
      final echelle = (f * 977).floor().isEven ? 0.88 : 0.79;
      var p = ((theta - 30 * degre) / tour) % 1.0;
      if (p < 0) p += 1;
      final cote = (p * 3).floor().clamp(0, 2);
      final w = p * 3 - cote;
      final a0 = 30 * degre + cote * tour / 3;
      final a1 = a0 + tour / 3;
      qx = echelle * (math.cos(a0) * (1 - w) + math.cos(a1) * w);
      qy = echelle * (math.sin(a0) * (1 - w) + math.sin(a1) * w);
      qz = 0.08;
      ordre = 0.6;
      pulse = 0.2;
    } else if (u < 0.77) {
      // Rayons : de l'anneau au milieu des côtés (90°, 210°, 330°).
      final k = (((theta - 90 * degre) / (tour / 3)).round()) % 3;
      final a = 90 * degre + k * tour / 3;
      final r = 0.44 + 0.48 * dans(0.73, 0.77);
      qx = r * math.cos(a);
      qy = r * math.sin(a);
      qz = 0.04;
      ordre = 0.45;
      pulse = 0;
    } else if (u < 0.82) {
      // Nœuds : petites boules aux sommets du triangle (30°, 150°, 270°)
      // et aux pieds des rayons sur l'anneau (90°, 210°, 330°).
      final k = (((theta - 30 * degre) / (tour / 6)).round()) % 6;
      final a = 30 * degre + k * tour / 6;
      final r = k.isEven ? 0.88 : 0.96;
      qx = r * math.cos(a) + vx * 0.05;
      qy = r * math.sin(a) + vy * 0.05;
      qz = 0.1 + vz * 0.05;
      ordre = 0.3;
      pulse = 0.3;
    } else if (u < 0.88) {
      // Cercle en pointillés autour du noyau (36 points).
      const pas = 2 * math.pi / 36;
      final a = (theta / pas).round() * pas;
      qx = 0.3 * math.cos(a);
      qy = 0.3 * math.sin(a);
      qz = 0.1;
      ordre = 0.85;
      pulse = 0.5;
    } else {
      // Noyau : petite boule dense au centre.
      final r = 0.17 * (0.3 + 0.7 * dans(0.88, 1));
      qx = vx * r;
      qy = vy * r;
      qz = vz * r + 0.12;
      ordre = 1;
      pulse = 1;
    }
    g.x[i] = qx;
    g.y[i] = qy;
    g.z[i] = qz;
    g.ordre[i] = ordre;
    g.pulse[i] = pulse;
  }

  // Point visé pour une forme (résultat dans _tx/_ty/_tz, repère du calque)
  // et son ordre d'arrivée (_tOrdre).
  double _tx = 0, _ty = 0, _tz = 0, _tOrdre = 0;

  /// Point de la forme [forme] pour la particule [i], tourné selon
  /// ([cl], [sl]) puis ([ci], [si]), à l'échelle [facteur] (réactions de
  /// la sphère).
  void _cibleForme(
    int i,
    FormePim forme,
    _Geometrie g,
    double cl,
    double sl,
    double ci,
    double si,
    double facteur,
    double pulsation,
    double ecartAngle,
    double rayon,
  ) {
    double qx, qy, qz;
    if (forme == FormePim.cube) {
      _cibleCube(i, ecartAngle - math.pi / 4);
      final taille = PimDynamiqueReglages.demiCoteCube * facteur;
      qx = _qx * taille;
      qy = _qy * taille;
      qz = _qz * taille;
      _tOrdre = _versCoin;
    } else {
      final taille = facteur * (1 + pulsation * g.pulse[i]);
      qx = g.x[i] * taille;
      qy = g.y[i] * taille;
      qz = g.z[i] * taille;
      _tOrdre = g.ordre[i];
    }
    final kx = qx * cl - qz * sl;
    var kz = qx * sl + qz * cl;
    final ky = qy * ci - kz * si;
    kz = qy * si + kz * ci;
    _tx = _cx + kx * rayon;
    _ty = _cy - ky * rayon + _flotteY;
    _tz = kz * rayon;
  }

  /// Orientation (lacet, inclinaison) d'une forme principale : le cube et
  /// le tétraèdre tournent lentement avec la sphère ; le réacteur reste
  /// tourné vers l'utilisateur et oscille doucement.
  (double, double) _orientation(
    FormePim forme,
    double lacetDepart,
    double t,
    double mouvement,
    double precession,
  ) => switch (forme) {
    FormePim.reacteur => (
      0.32 * math.sin(t * 0.42) * mouvement,
      -0.08 + 0.07 * math.sin(t * 0.31) * mouvement,
    ),
    FormePim.tetraedre => (
      _lacet - lacetDepart + _decalageTetraedre,
      -0.32 - forme.inclinaison + precession,
    ),
    _ => (_lacet + math.pi / 4, -0.32 - forme.inclinaison + precession),
  };

  /// Point du contour d'un rectangle arrondi à l'abscisse curviligne [s],
  /// avec sa normale sortante. Résultat dans _pcX/_pcY et _ncX/_ncY.
  void _pointContour(Rect r, double rc, double s) {
    final haut = r.width - 2 * rc;
    final cote = r.height - 2 * rc;
    final arc = math.pi / 2 * rc;

    // Haut, de gauche à droite.
    if (s < haut) {
      _pcX = r.left + rc + s;
      _pcY = r.top;
      _ncX = 0;
      _ncY = -1;
      return;
    }
    s -= haut;
    if (s < arc) return _arc(r.right - rc, r.top + rc, rc, -math.pi / 2, s);
    s -= arc;
    // Droite, de haut en bas.
    if (s < cote) {
      _pcX = r.right;
      _pcY = r.top + rc + s;
      _ncX = 1;
      _ncY = 0;
      return;
    }
    s -= cote;
    if (s < arc) return _arc(r.right - rc, r.bottom - rc, rc, 0, s);
    s -= arc;
    // Bas, de droite à gauche.
    if (s < haut) {
      _pcX = r.right - rc - s;
      _pcY = r.bottom;
      _ncX = 0;
      _ncY = 1;
      return;
    }
    s -= haut;
    if (s < arc) return _arc(r.left + rc, r.bottom - rc, rc, math.pi / 2, s);
    s -= arc;
    // Gauche, de bas en haut.
    if (s < cote) {
      _pcX = r.left;
      _pcY = r.bottom - rc - s;
      _ncX = -1;
      _ncY = 0;
      return;
    }
    s -= cote;
    _arc(r.left + rc, r.top + rc, rc, math.pi, s);
  }

  void _arc(double cx, double cy, double rc, double debut, double s) {
    final a = debut + (rc > 0 ? s / rc : 0);
    _ncX = math.cos(a);
    _ncY = math.sin(a);
    _pcX = cx + _ncX * rc;
    _pcY = cy + _ncY * rc;
  }

  // ---- Répulsion locale via une grille (évite de tester toutes les paires).
  // La grille ne couvre que la zone occupée par les particules (et non tout
  // l'écran) et chaque paire de voisines n'est calculée qu'une fois : la
  // force est appliquée aux deux, en sens opposés.
  Int32List _tete = Int32List(0);
  final _suivant = Int32List(n);
  final _colonne = Int32List(n), _ligne = Int32List(n);
  final _forceX = Float64List(n), _forceY = Float64List(n);

  void _calculerRepulsion(Size taille) {
    const rr = PimReglages.rayonRepulsion;
    // Zone occupée, limitée à l'écran : une particule hors de l'écran est
    // rangée dans la case du bord, comme avant.
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var i = 0; i < n; i++) {
      final x = _x[i], y = _y[i];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    minX = math.max(minX, 0);
    minY = math.max(minY, 0);
    maxX = math.max(math.min(maxX, taille.width), minX);
    maxY = math.max(math.min(maxY, taille.height), minY);
    final colonnes = ((maxX - minX) / rr).floor() + 1;
    final lignes = ((maxY - minY) / rr).floor() + 1;
    final cases = colonnes * lignes;
    if (cases > _tete.length) _tete = Int32List(cases);
    _tete.fillRange(0, cases, -1);

    for (var i = 0; i < n; i++) {
      var c = ((_x[i] - minX) / rr).floor();
      if (c < 0) c = 0;
      if (c >= colonnes) c = colonnes - 1;
      var l = ((_y[i] - minY) / rr).floor();
      if (l < 0) l = 0;
      if (l >= lignes) l = lignes - 1;
      _colonne[i] = c;
      _ligne[i] = l;
      final idx = l * colonnes + c;
      _suivant[i] = _tete[idx];
      _tete[idx] = i;
      _forceX[i] = 0;
      _forceY[i] = 0;
    }

    // Chaque paire une seule fois : même case (voisines suivantes dans la
    // liste), case de droite, puis les trois cases de la ligne suivante.
    for (var i = 0; i < n; i++) {
      final c = _colonne[i], l = _ligne[i];
      for (var j = _suivant[i]; j != -1; j = _suivant[j]) {
        _paire(i, j);
      }
      if (c + 1 < colonnes) {
        for (var j = _tete[l * colonnes + c + 1]; j != -1; j = _suivant[j]) {
          _paire(i, j);
        }
      }
      if (l + 1 < lignes) {
        final base = (l + 1) * colonnes;
        final c0 = c > 0 ? c - 1 : 0;
        final c1 = c + 1 < colonnes ? c + 1 : c;
        for (var cc = c0; cc <= c1; cc++) {
          for (var j = _tete[base + cc]; j != -1; j = _suivant[j]) {
            _paire(i, j);
          }
        }
      }
    }

    for (var i = 0; i < n; i++) {
      var fx = _forceX[i], fy = _forceY[i];
      // Plafond : même un amas de particules superposées ne peut pas en
      // projeter une au loin.
      final f2 = fx * fx + fy * fy;
      const fMax = PimReglages.repulsionMax;
      if (f2 > fMax * fMax) {
        final s = fMax / math.sqrt(f2);
        fx *= s;
        fy *= s;
      }
      _repX[i] = fx;
      _repY[i] = fy;
    }
  }

  /// Répulsion entre deux voisines proches (aussi en profondeur).
  void _paire(int i, int j) {
    const rr = PimReglages.rayonRepulsion;
    final ddx = _x[i] - _x[j], ddy = _y[i] - _y[j];
    final d2 = ddx * ddx + ddy * ddy;
    if (d2 >= rr * rr || d2 <= 1e-6) return;
    final dz = _z[i] - _z[j];
    if (dz >= rr * 2 || dz <= -rr * 2) return;
    final d = math.sqrt(d2);
    final force = PimReglages.forceRepulsion * (1 - d / rr) / d;
    final fx = ddx * force, fy = ddy * force;
    _forceX[i] += fx;
    _forceY[i] += fy;
    _forceX[j] -= fx;
    _forceY[j] -= fy;
  }

  // ---- Projection pour le dessin ------------------------------------------
  static final profondeurs = PimRendu.plans.length;
  static final nombreStyles = PimRendu.styles.length;
  final _parStyle = List<int>.filled(PimRendu.styles.length, 0);

  /// Points projetés, par profondeur puis par style.
  late final List<Float32List> tampons;
  final List<int> compteurs = List.filled(
    profondeurs * PimRendu.styles.length,
    0,
  );

  /// Perspective centrée sur la zone centrale ; z ≈ 0 autour du champ,
  /// donc aucune déformation là-bas.
  void projeter() {
    for (var k = 0; k < compteurs.length; k++) {
      compteurs[k] = 0;
    }
    if (!_initialise) return;
    final focale = 3.2 * _rayonEcran;
    for (var i = 0; i < n; i++) {
      final z = _z[i];
      // Grossissement de perspective limité à environ ×1,4.
      final p = focale / math.max(focale - z, focale * 0.7);
      final profondeur =
          ((z / (_rayonEcran * PimRendu.etendueProfondeur) + 1) / 2).clamp(
            0.0,
            0.999,
          );
      final seau =
          (profondeur * profondeurs).floor() * nombreStyles + _style[i];
      final c = compteurs[seau];
      tampons[seau][c * 2] = _cx + (_x[i] - _cx) * p;
      tampons[seau][c * 2 + 1] = _cy + (_y[i] - _cy) * p;
      compteurs[seau] = c + 1;
    }
  }

  double get rayonEcran => _rayonEcran;

  /// Distance moyenne et maximale des particules au centre, en rayons
  /// (diagnostic, utilisé par les tests).
  ({double moyenne, double maximum}) get etalement {
    // Les satellites, qui flottent volontairement hors de la sphère, ne
    // comptent pas.
    var somme = 0.0, maximum = 0.0, compte = 0;
    for (var i = 0; i < n; i++) {
      if (_satellite[i] == 1) continue;
      compte++;
      final dx = _x[i] - _cx, dy = _y[i] - _cy - _flotteY, dz = _z[i];
      final d = math.sqrt(dx * dx + dy * dy + dz * dz) / _rayonEcran;
      somme += d;
      if (d > maximum) maximum = d;
    }
    return (moyenne: somme / compte, maximum: maximum);
  }

  /// Lumière au cœur : elle rayonne quand JARVIS parle, monte doucement
  /// pendant la réflexion, et s'efface un peu quand il écoute.
  double get lumiereCoeur =>
      (1 - morph) *
      (PimRendu.lumiereCentrale * (1 - 0.35 * _ecoute + 0.35 * _anticipation) +
          0.4 * _parole * (0.3 + _memoire.energie));

  /// Lumière sur le pourtour : la sphère reçoit quand l'utilisateur parle.
  double get lumiereBord =>
      (1 - morph) * _ecoute * (0.3 + 0.7 * _memoire.energie);

  /// Présence de l'ombre portée (absente quand les particules entourent
  /// le champ texte).
  double get presenceOmbre => 1 - morph;

  double get cx => _cx;
  double get cy => _cy;
  double get flotteY => _flotteY;

  /// Intensité globale (plus lumineux quand JARVIS est sollicité).
  double get eclat =>
      0.75 +
      0.15 * _ecoute +
      0.25 * _memoire.energie +
      0.08 * _formes.stabilisation +
      0.15 * _reflexion +
      0.2 * _parole +
      0.1 * _energie;
}

/// Dessin des particules PIM sur fond clair.
///
/// Ordre : ombre portée, lumière diffuse du cœur et du pourtour, puis les
/// plans de profondeur du fond vers l'avant ([PimRendu.plans]). Chaque plan
/// combine taille, opacité, brume (fondu dans le beige), contraste, reflet
/// et flou : le fond est petit, doux et légèrement flou ; le milieu porte
/// la sphère ; l'avant est plus grand, net et contrasté. Les dégradés et
/// les flous sont créés une seule fois, pas à chaque image.
///
/// Les points flous (plan du fond, halos) ne sont pas floutés un par un à
/// chaque image : chaque plan × style a son point flou pré-rendu une fois
/// (même pinceau, même flou) dans une petite image, recopiée à la position
/// de chaque particule en un seul appel ([Canvas.drawRawAtlas]). Skia
/// dessinait déjà ces points un par un, superposés : le rendu est le même,
/// pour une fraction du coût.
class _PeintrePim extends CustomPainter {
  _PeintrePim(this.simulation) : super(repaint: simulation);

  final _SimulationPim simulation;

  /// Densité de pixels de l'écran : les points flous sont pré-rendus à la
  /// résolution réelle.
  double get densite => _densite;
  double _densite = 1;
  set densite(double valeur) {
    if (valeur == _densite) return;
    _densite = valeur;
    _echelleFlous = -1;
  }

  // Pinceaux réutilisés.
  final _point = Paint()..strokeCap = StrokeCap.round;
  final _reflet = Paint()..strokeCap = StrokeCap.round;
  final _lumiere = Paint();

  // Dégradés de rayon 1 centrés sur l'origine, mis à l'échelle au dessin.
  // Lumière du cœur : large et diffuse, sans « boule » au centre.
  static final _degradeCoeur = ui.Gradient.radial(
    Offset.zero,
    1,
    [
      const Color(0xFFFFFFFF).withValues(alpha: 0.6),
      PimRendu.lumiere.withValues(alpha: 0.3),
      PimRendu.lumiere.withValues(alpha: 0.1),
      PimRendu.lumiere.withValues(alpha: 0),
    ],
    const [0, 0.35, 0.7, 1],
  );
  static final _degradeBord = ui.Gradient.radial(
    Offset.zero,
    1,
    [
      PimRendu.lumiere.withValues(alpha: 0),
      PimRendu.lumiere.withValues(alpha: 0),
      PimRendu.lumiere.withValues(alpha: 0.55),
      PimRendu.lumiere.withValues(alpha: 0),
    ],
    const [0, 0.7, 0.9, 1],
  );
  static final _degradeOmbre = ui.Gradient.radial(
    Offset.zero,
    1,
    [
      const Color(0xFF2F2A40).withValues(alpha: 0.75),
      const Color(0xFF2F2A40).withValues(alpha: 0.32),
      const Color(0xFF2F2A40).withValues(alpha: 0.08),
      const Color(0x002F2A40),
    ],
    const [0, 0.4, 0.75, 1],
  );

  // Flous (profondeur de champ, halos), recréés seulement si la taille de
  // la sphère ou le niveau de qualité change.
  double _echelleFlous = -1;
  bool _qualiteReduite = false;
  final _flouPoint = List<MaskFilter?>.filled(
    PimRendu.plans.length * PimRendu.styles.length,
    null,
  );
  final _flouHalo = List<MaskFilter?>.filled(
    PimRendu.plans.length * PimRendu.styles.length,
    null,
  );
  // Couleur de chaque plan × style (brume et contraste appliqués), avec
  // l'opacité du plan, et couleur de son reflet : calculées une fois.
  final _couleurs = List<Color>.filled(
    PimRendu.plans.length * PimRendu.styles.length,
    PimRendu.graphite,
  );
  final _couleursPoint = List<Color>.filled(
    PimRendu.plans.length * PimRendu.styles.length,
    PimRendu.graphite,
  );
  final _couleursReflet = List<Color>.filled(
    PimRendu.plans.length * PimRendu.styles.length,
    PimRendu.reflet,
  );

  // Points flous pré-rendus, par plan × style.
  final _spriteHalo = List<_Sprite?>.filled(
    PimRendu.plans.length * PimRendu.styles.length,
    null,
  );
  final _spritePoint = List<_Sprite?>.filled(
    PimRendu.plans.length * PimRendu.styles.length,
    null,
  );
  // Transformations de l'atlas (4 valeurs par particule), réutilisées.
  final _transformes = Float32List(_SimulationPim.n * 4);
  final _atlas = Paint()..filterQuality = FilterQuality.low;
  final _pinceauSprite = Paint()..strokeCap = StrokeCap.round;
  final _unPoint = Float32List(2);

  /// Rend une fois un point de [largeur] px avec le [flou] (écart type
  /// [sigma]), au centre d'une petite image à la densité de l'écran.
  _Sprite _sprite(
    Color couleur,
    double largeur,
    MaskFilter flou,
    double sigma,
    int capacite,
  ) {
    final d = _densite;
    final cote = (2 * (largeur / 2 + 3 * sigma + 1) * d).ceil();
    final enregistreur = ui.PictureRecorder();
    final canvas = Canvas(enregistreur);
    canvas.scale(d);
    _unPoint
      ..[0] = cote / d / 2
      ..[1] = cote / d / 2;
    _pinceauSprite
      ..color = couleur
      ..strokeWidth = largeur
      ..maskFilter = flou;
    canvas.drawRawPoints(ui.PointMode.points, _unPoint, _pinceauSprite);
    final dessin = enregistreur.endRecording();
    final image = dessin.toImageSync(cote, cote);
    dessin.dispose();
    final rects = Float32List(capacite * 4);
    for (var i = 0; i < capacite; i++) {
      rects[i * 4 + 2] = cote.toDouble();
      rects[i * 4 + 3] = cote.toDouble();
    }
    return _Sprite(image, largeur, rects);
  }

  void _preparer(double echelle, bool qualiteReduite, double facteurHalo) {
    if ((echelle - _echelleFlous).abs() < 0.02 &&
        qualiteReduite == _qualiteReduite) {
      return;
    }
    _echelleFlous = echelle;
    _qualiteReduite = qualiteReduite;
    const styles = PimRendu.styles;
    const plans = PimRendu.plans;
    for (var d = 0; d < plans.length; d++) {
      final plan = plans[d];
      for (var s = 0; s < styles.length; s++) {
        final style = styles[s];
        final taille = style.taille * echelle * plan.taille;
        final k = d * styles.length + s;
        // Flou de fond : sur téléphone, seulement pour les particules
        // moyennes et lumineuses (les micro-particules y sont trop petites
        // pour que la différence se voie).
        final flou = plan.flou > 0 && !(qualiteReduite && style.micro);
        _flouPoint[k] = flou
            ? MaskFilter.blur(BlurStyle.normal, taille * plan.flou)
            : null;
        final halo = style.lueur > 0 && !(qualiteReduite && style.lueur < 0.5);
        _flouHalo[k] = halo
            ? MaskFilter.blur(BlurStyle.normal, taille * style.halo * 0.28)
            : null;
        final fondu = Color.lerp(
          style.couleur,
          PimRendu.fondBrume,
          plan.brume,
        )!;
        _couleurs[k] = Color.lerp(fondu, PimRendu.encre, plan.contraste)!;
        _couleursPoint[k] = _couleurs[k].withValues(alpha: plan.opacite);
        _couleursReflet[k] = PimRendu.reflet.withValues(
          alpha: plan.reflet * (style.lueur >= 0.7 ? 0.95 : 0.6),
        );

        final capacite = simulation._parStyle[s];
        _spritePoint[k]?.image.dispose();
        _spritePoint[k] = flou
            ? _sprite(
                _couleurs[k],
                taille,
                _flouPoint[k]!,
                taille * plan.flou,
                capacite,
              )
            : null;
        _spriteHalo[k]?.image.dispose();
        _spriteHalo[k] = halo
            ? _sprite(
                PimRendu.lumiere,
                taille * style.halo * facteurHalo,
                _flouHalo[k]!,
                taille * style.halo * 0.28,
                capacite,
              )
            : null;
      }
    }
  }

  /// Recopie [sprite] centré sur chacun des [nombre] [points], à la
  /// largeur de trait [largeur], avec l'opacité [opacite].
  void _dessinerSprites(
    Canvas canvas,
    _Sprite sprite,
    Float32List points,
    int nombre,
    double largeur,
    double opacite,
  ) {
    final echelle = largeur / sprite.largeur / _densite;
    final demi = sprite.image.width / 2 * echelle;
    final t = _transformes;
    for (var i = 0; i < nombre; i++) {
      final j = i * 4;
      t[j] = echelle;
      t[j + 1] = 0;
      t[j + 2] = points[i * 2] - demi;
      t[j + 3] = points[i * 2 + 1] - demi;
    }
    _atlas.color = Color.fromRGBO(255, 255, 255, opacite.clamp(0.0, 1.0));
    canvas.drawRawAtlas(
      sprite.image,
      Float32List.sublistView(t, 0, nombre * 4),
      Float32List.sublistView(sprite.rects, 0, nombre * 4),
      null,
      null,
      null,
      _atlas,
    );
  }

  void _disque(
    Canvas canvas,
    ui.Gradient degrade,
    double opacite,
    double x,
    double y,
    double rx,
    double ry,
  ) {
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(rx, ry);
    _lumiere
      ..shader = degrade
      ..color = Color.fromRGBO(0, 0, 0, opacite.clamp(0.0, 1.0));
    canvas.drawCircle(Offset.zero, 1, _lumiere);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chrono = ChronoPerf.debut();
    final sim = simulation;
    final chronoProjection = ChronoPerf.debut();
    sim.projeter();
    ChronoPerf.fin('pim.projection', chronoProjection);
    final rayon = sim.rayonEcran;
    // Taille des particules proportionnelle à la sphère (un peu moins que
    // linéaire) : sur un petit écran, les halos ne l'envahissent pas.
    final echelle = math.pow(rayon / 165, 0.85).toDouble().clamp(0.4, 1.45);
    final qualiteReduite = rayon < PimRendu.rayonQualiteReduite;
    // Halos un peu plus serrés sur une petite sphère.
    final ample = ((rayon - 80) / 90).clamp(0.0, 1.0);
    final facteurHalo = 0.8 + 0.2 * ample;
    _preparer(echelle, qualiteReduite, facteurHalo);

    // Ombre portée : la sphère monte → ombre plus large et plus pâle ;
    // elle descend → plus petite et un peu plus marquée.
    final ombre = ChronoPerf.sans('pim.lumieres')
        ? 0.0
        : sim.presenceOmbre * PimRendu.ombre;
    if (ombre > 0.003) {
      final descente = (sim.flotteY / rayon).clamp(-0.1, 0.1);
      const reaction = PimRendu.reactionOmbre;
      _disque(
        canvas,
        _degradeOmbre,
        ombre * (1 + descente * reaction * 4),
        sim.cx,
        sim.cy + rayon * 1.3,
        rayon * PimRendu.largeurOmbre * (1 - descente * reaction),
        rayon * 0.15 * (1 - descente * reaction * 0.5),
      );
    }
    // Lumière diffuse du cœur (émission) et du pourtour (réception).
    final coeur = ChronoPerf.sans('pim.lumieres') ? 0.0 : sim.lumiereCoeur;
    if (coeur > 0.003) {
      final r = rayon * PimRendu.etendueLumiere;
      _disque(canvas, _degradeCoeur, coeur, sim.cx, sim.cy + sim.flotteY, r, r);
    }
    final bord = ChronoPerf.sans('pim.lumieres') ? 0.0 : sim.lumiereBord;
    if (bord > 0.003) {
      _disque(
        canvas,
        _degradeBord,
        bord,
        sim.cx,
        sim.cy + sim.flotteY,
        rayon * 1.15,
        rayon * 1.15,
      );
    }

    final eclat = sim.eclat;
    const styles = PimRendu.styles;
    const plans = PimRendu.plans;
    for (var d = 0; d < plans.length; d++) {
      final plan = plans[d];
      for (var s = 0; s < styles.length; s++) {
        final k = d * styles.length + s;
        final nombre = sim.compteurs[k];
        if (nombre == 0) continue;
        final style = styles[s];
        final points = Float32List.sublistView(sim.tampons[k], 0, nombre * 2);
        final taille = style.taille * echelle * plan.taille;

        final halo = _spriteHalo[k];
        if (halo != null && !ChronoPerf.sans('pim.halos')) {
          _dessinerSprites(
            canvas,
            halo,
            points,
            nombre,
            taille * style.halo * facteurHalo,
            0.3 * style.lueur * plan.lueur * PimRendu.intensiteLueur * eclat,
          );
        }

        final flou = _spritePoint[k];
        if (flou != null && !ChronoPerf.sans('pim.flou')) {
          _dessinerSprites(canvas, flou, points, nombre, taille, plan.opacite);
        } else {
          _point
            ..color = _couleursPoint[k]
            ..strokeWidth = taille;
          canvas.drawRawPoints(ui.PointMode.points, points, _point);
        }

        if (style.relief &&
            plan.reflet > 0 &&
            !ChronoPerf.sans('pim.reflets')) {
          // Reflet en haut à gauche : la particule paraît sphérique ; plus
          // marqué au premier plan.
          canvas.save();
          canvas.translate(-taille * 0.17, -taille * 0.2);
          _reflet
            ..color = _couleursReflet[k]
            ..strokeWidth = taille * 0.42;
          canvas.drawRawPoints(ui.PointMode.points, points, _reflet);
          canvas.restore();
        }
      }
    }
    ChronoPerf.fin('pim.peinture', chrono);
  }

  @override
  bool shouldRepaint(_PeintrePim ancien) => ancien.simulation != simulation;
}

/// Point flou pré-rendu : image, largeur de trait (px logiques) pour
/// laquelle il a été rendu, rectangles source de l'atlas (un par
/// particule possible, tous identiques).
class _Sprite {
  _Sprite(this.image, this.largeur, this.rects);

  final ui.Image image;
  final double largeur;
  final Float32List rects;
}

/// Points visés par chaque particule pour une forme préparée (repère de la
/// forme, en rayons de la sphère), ordre d'arrivée et part de pulsation.
class _Geometrie {
  _Geometrie(int n)
    : x = Float32List(n),
      y = Float32List(n),
      z = Float32List(n),
      ordre = Float32List(n),
      pulse = Float32List(n);

  final Float32List x, y, z, ordre, pulse;

  void copier(_Geometrie autre) {
    x.setAll(0, autre.x);
    y.setAll(0, autre.y);
    z.setAll(0, autre.z);
    ordre.setAll(0, autre.ordre);
    pulse.setAll(0, autre.pulse);
  }
}
