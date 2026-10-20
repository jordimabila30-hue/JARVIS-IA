import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/apparence/service_apparence.dart';
import '../theme/motifs_jarvis.dart';
import '../theme/theme_jarvis.dart';
import '../utils/chrono_perf.dart';

/// Réglages du fond de l'accueil (purement graphiques : le fond est fixe).
class ReglagesFond {
  ReglagesFond._();

  /// Lumière ivoire au centre, derrière les particules (0 à 1), et son
  /// étendue (fraction du petit côté de l'écran).
  static const lumiereCentrale = 0.9;
  static const etendueLumiere = 0.5;

  /// Halo lavande autour des particules (0 = aucun, 1 = discret,
  /// 1,35 = conseillé).
  static const intensiteLavande = 1.35;

  /// Nappes violettes : décalage (fraction du petit côté de l'écran),
  /// opacité et taille.
  static const amplitudeNappes = 0.07;
  static const opaciteNappes = 0.85;
  static const tailleNappes = 1.15;

  /// Courbes lumineuses : opacité et largeur de leur lueur lavande (px).
  static const opaciteCourbes = 0.7;
  static const largeurLueur = 10.0;

  /// Largeur (px) en dessous de laquelle le fond est simplifié (2 nappes,
  /// 2 courbes, 1 anneau, lueur sans flou).
  static const largeurSimplifiee = 600.0;
}

/// Fond de l'accueil, fixe : ivoire lumineux au centre, beige chaud vers
/// les bords, lavande sur les côtés et autour des particules, nappes
/// violettes diffuses, fines courbes lumineuses et anneaux d'énergie qui
/// passent derrière la sphère. Le fond est l'identité visuelle ; les
/// particules PIM sont l'élément vivant.
///
/// (Ce fond était animé ; il reprend exactement l'image de son instant de
/// départ.)
///
/// Aucune horloge : il n'est redessiné que si la mise en page change
/// (taille de l'écran, clavier, zone des particules). Une fois la mise en
/// page stable, il est mémorisé dans une image : chaque image de l'écran
/// ne fait plus qu'une copie, au lieu de redessiner dégradés, nappes et
/// courbes floutées.
class FondJarvisAnime extends StatefulWidget {
  const FondJarvisAnime({super.key, required this.child, this.zoneParticules});

  final Widget child;

  /// Zone des particules, dans le repère de l'écran : halo, lumière et
  /// anneaux s'y centrent. Fournie par le moteur PIM (qui la mesure déjà) ;
  /// elle ne change qu'avec la mise en page.
  final ValueListenable<Rect?>? zoneParticules;

  @override
  State<FondJarvisAnime> createState() => _FondJarvisAnimeState();
}

class _FondJarvisAnimeState extends State<FondJarvisAnime> {
  final _cle = GlobalKey();
  final _peintre = _PeintreFond();

  @override
  void initState() {
    super.initState();
    widget.zoneParticules?.addListener(_surZone);
  }

  @override
  void didUpdateWidget(FondJarvisAnime ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.zoneParticules != widget.zoneParticules) {
      ancien.zoneParticules?.removeListener(_surZone);
      widget.zoneParticules?.addListener(_surZone);
      _surZone();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _peintre
      ..densite = View.of(context).devicePixelRatio
      ..simplifie =
          MediaQuery.sizeOf(context).width < ReglagesFond.largeurSimplifiee;
    _surZone();
  }

  /// Zone des particules ramenée dans le repère du fond.
  void _surZone() {
    final globale = widget.zoneParticules?.value;
    if (globale == null) {
      _peintre.zone = null;
      return;
    }
    final fond = _cle.currentContext?.findRenderObject();
    if (fond is! RenderBox || !fond.attached || !fond.hasSize) {
      // Pas encore disposé : on reprend après cette image.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _surZone();
      });
      return;
    }
    _peintre.zone = globale.shift(-fond.localToGlobal(Offset.zero));
  }

  @override
  void dispose() {
    widget.zoneParticules?.removeListener(_surZone);
    _peintre.liberer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Style et motif choisis : l'image mémorisée est refaite une fois.
    final apparence = ServiceApparence.of(context);
    _peintre.apparence(
      PaletteJarvis.of(context),
      apparence?.motif ?? MotifJarvis.aurore,
      apparence?.intensite ?? intensiteMotifParDefaut,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(key: _cle, painter: _peintre),
        ),
        widget.child,
      ],
    );
  }
}

class _Nappe {
  const _Nappe(
    this.x,
    this.y,
    this.rx,
    this.ry,
    this.douce,
    this.phase,
    this.opacite,
  );

  /// Position de base (fraction de l'écran), rayons (fraction du petit
  /// côté), teinte (vive ou douce, prise dans la palette), phase (fixe son
  /// décalage, son souffle et son inclinaison), opacité.
  final double x, y, rx, ry;
  final bool douce;
  final double phase, opacite;
}

class _Courbe {
  const _Courbe(
    this.y,
    this.amplitude,
    this.onde,
    this.phase,
    this.opacite,
    this.creux,
  );

  /// Hauteur au bord de l'écran (fraction de l'écran), amplitude (fraction
  /// du petit côté), nombre d'ondulations sur la largeur, phase, opacité,
  /// et creux au centre (fraction de la hauteur : > 0, la courbe plonge
  /// sous la sphère ; < 0, elle remonte vers elle).
  final double y, amplitude, onde, phase, opacite, creux;
}

/// Ce qui détermine l'image du fond. Tant que la clé ne change pas, l'image
/// mémorisée est réutilisée.
@immutable
class _CleFond {
  const _CleFond(
    this.taille,
    this.densite,
    this.zone,
    this.simplifie,
    this.palette,
    this.motif,
    this.intensite,
  );

  final Size taille;
  final double densite;
  final Rect? zone;
  final bool simplifie;
  final PaletteJarvis palette;
  final MotifJarvis motif;
  final double intensite;

  @override
  bool operator ==(Object other) =>
      other is _CleFond &&
      other.taille == taille &&
      other.densite == densite &&
      other.zone == zone &&
      other.simplifie == simplifie &&
      identical(other.palette, palette) &&
      other.motif == motif &&
      other.intensite == intensite;

  @override
  int get hashCode =>
      Object.hash(taille, densite, zone, simplifie, palette, motif, intensite);
}

/// Redessine le fond quand un paramètre change.
class _Signal extends ChangeNotifier {
  void signaler() => notifyListeners();
}

class _PeintreFond extends CustomPainter {
  _PeintreFond() : this._(_Signal());
  _PeintreFond._(this._signal) : super(repaint: _signal);

  final _Signal _signal;

  double _densite = 1;
  set densite(double v) {
    if (v == _densite) return;
    _densite = v;
    _signal.signaler();
  }

  bool _simplifie = false;
  set simplifie(bool v) {
    if (v == _simplifie) return;
    _simplifie = v;
    _signal.signaler();
  }

  Rect? _zone;
  set zone(Rect? v) {
    if (v == _zone) return;
    _zone = v;
    _signal.signaler();
  }

  // Apparence : palette du style affiché, motif et son intensité.
  PaletteJarvis _palette = PaletteJarvis.jarvisClair;
  MotifJarvis _motif = MotifJarvis.aurore;
  double _intensite = intensiteMotifParDefaut;
  void apparence(PaletteJarvis palette, MotifJarvis motif, double intensite) {
    if (identical(palette, _palette) &&
        motif == _motif &&
        intensite == _intensite) {
      return;
    }
    _palette = palette;
    _motif = motif;
    _intensite = intensite;
    _signal.signaler();
  }

  // Image mémorisée, sa clé, et la clé du dernier dessin direct.
  ui.Image? _image, _precedente;
  _CleFond? _cleImage, _derniereCle;
  final _copie = Paint()..filterQuality = FilterQuality.none;

  void liberer() {
    _image?.dispose();
    _precedente?.dispose();
    _image = _precedente = null;
  }

  _CleFond _cle(Size size) =>
      _CleFond(size, _densite, _zone, _simplifie, _palette, _motif, _intensite);

  void _dessiner(Canvas canvas, Size size) => peindreFondAccueil(
    canvas,
    size,
    palette: _palette,
    motif: _motif,
    intensite: _intensite,
    zone: _zone,
    simplifie: _simplifie,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final chrono = ChronoPerf.debut();
    final cle = _cle(size);
    if (_image == null || cle != _cleImage) {
      if (cle == _derniereCle) {
        // Mise en page stable depuis le dessin précédent : on mémorise.
        _memoriser(cle);
      } else {
        // La mise en page change (clavier, transition) : dessin direct, et
        // on revient à l'image suivante voir si elle s'est stabilisée.
        _derniereCle = cle;
        final direct = ChronoPerf.debut();
        _dessiner(canvas, size);
        ChronoPerf.fin('fond.direct', direct);
        SchedulerBinding.instance.addPostFrameCallback(
          (_) => _signal.signaler(),
        );
        ChronoPerf.fin('fond.peinture', chrono);
        return;
      }
    }
    final image = _image!;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, image.width / _densite, image.height / _densite),
      _copie,
    );
    ChronoPerf.fin('fond.peinture', chrono);
  }

  /// Dessine le fond une fois, à la résolution réelle de l'écran.
  void _memoriser(_CleFond cle) {
    final chrono = ChronoPerf.debut();
    final d = cle.densite;
    final largeur = (cle.taille.width * d).ceil();
    final hauteur = (cle.taille.height * d).ceil();
    final enregistreur = ui.PictureRecorder();
    final canvas = Canvas(enregistreur);
    canvas.scale(d);
    _dessiner(canvas, cle.taille);
    final dessin = enregistreur.endRecording();
    final image = dessin.toImageSync(largeur, hauteur);
    dessin.dispose();
    // L'image précédente peut encore servir à l'image affichée : elle est
    // libérée au remplacement suivant.
    _precedente?.dispose();
    _precedente = _image;
    _image = image;
    _cleImage = cle;
    ChronoPerf.fin('fond.memoriser', chrono);
  }

  @override
  bool shouldRepaint(_PeintreFond ancien) => ancien != this;
}

// ---- Composition ----------------------------------------------------------

/// Les deux premières (côtés) restent sur téléphone.
const _nappes = [
  _Nappe(0.13, 0.46, 0.60, 0.48, false, 0.0, 1.0),
  _Nappe(0.87, 0.42, 0.56, 0.46, false, 2.1, 0.95),
  _Nappe(0.50, 0.68, 0.70, 0.28, true, 4.0, 0.8),
];

/// Courbes venues des bords, qui plongent sous la sphère ou remontent vers
/// elle. Les deux premières restent sur téléphone.
const _courbes = [
  _Courbe(0.30, 0.035, 0.9, 0.0, 1.0, 0.24),
  _Courbe(0.66, 0.03, 1.1, 1.7, 0.85, -0.14),
  _Courbe(0.36, 0.04, 1.3, 3.1, 0.7, 0.20),
  _Courbe(0.72, 0.03, 0.8, 4.6, 0.6, -0.10),
  _Courbe(0.24, 0.03, 1.5, 2.4, 0.5, 0.30),
];

// Dégradés de rayon 1, mis à l'échelle au dessin. Bords très diffus : la
// chute est progressive jusqu'au rayon.
final _halo = <Color, ui.Gradient>{};
ui.Gradient _degradeRond(Color c) => _halo.putIfAbsent(
  c,
  () => ui.Gradient.radial(
    Offset.zero,
    1,
    [
      c,
      c.withValues(alpha: 0.7),
      c.withValues(alpha: 0.32),
      c.withValues(alpha: 0.1),
      c.withValues(alpha: 0),
    ],
    const [0, 0.25, 0.55, 0.8, 1],
  ),
);

/// Lumière centrale (ivoire légèrement dorée pour JARVIS), sans bord
/// visible : une par palette.
final _lumieres = Expando<ui.Gradient>();
ui.Gradient _lumiere(CouleursFond f) => _lumieres[f] ??= ui.Gradient.radial(
  Offset.zero,
  1,
  f.lumiere,
  const [0, 0.25, 0.5, 0.78, 1],
);

const _flou = MaskFilter.blur(BlurStyle.normal, 4);

final _pinceau = Paint();
final _ligne = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round;

void _ellipse(
  Canvas canvas,
  ui.Gradient g,
  double opacite,
  Offset c,
  double rx,
  double ry, [
  double angle = 0,
]) {
  if (opacite <= 0.002) return;
  canvas.save();
  canvas.translate(c.dx, c.dy);
  if (angle != 0) canvas.rotate(angle);
  canvas.scale(rx, ry);
  _pinceau
    ..shader = g
    ..color = Color.fromRGBO(0, 0, 0, opacite.clamp(0.0, 1.0));
  canvas.drawCircle(Offset.zero, 1, _pinceau);
  canvas.restore();
}

/// Trace [dessin] deux fois : une lueur large et douce (floutée sur grand
/// écran), puis un trait très fin.
void _tracer(
  bool simple,
  void Function(Paint) dessin,
  Shader trait,
  Shader lueur,
  double opacite,
) {
  _ligne
    ..shader = lueur
    ..maskFilter = simple ? null : _flou
    ..color = Color.fromRGBO(0, 0, 0, (opacite * 0.5).clamp(0.0, 1.0))
    ..strokeWidth = ReglagesFond.largeurLueur * (simple ? 0.6 : 1);
  dessin(_ligne);
  _ligne
    ..shader = trait
    ..maskFilter = null
    ..color = Color.fromRGBO(0, 0, 0, opacite.clamp(0.0, 1.0))
    ..strokeWidth = simple ? 1.1 : 1.3;
  dessin(_ligne);
}

/// Fond de l'accueil : base du style (dégradés, voile, halo, lumière
/// autour des particules) puis le motif. « Aurore » (nappes, courbes et
/// anneaux d'origine) s'intercale dans la base comme avant ; un motif
/// géométrique se pose par-dessus. Sert aussi aux aperçus des Paramètres.
void peindreFondAccueil(
  Canvas canvas,
  Size size, {
  required PaletteJarvis palette,
  required MotifJarvis motif,
  required double intensite,
  Rect? zone,
  bool simplifie = false,
}) {
  final f = palette.fond;
  final aurore = motif == MotifJarvis.aurore;
  // « Aurore » : à l'intensité par défaut, exactement le fond d'origine.
  final force = aurore ? intensite / intensiteMotifParDefaut : 0.0;
  final cote = size.shortestSide;
  final centre = zone?.center ?? Offset(size.width / 2, size.height * 0.42);
  final rayonSphere = 0.36 * (zone?.shortestSide ?? cote * 0.5);
  final tout = Offset.zero & size;

  // 1. Base : clair au centre, plus chaud vers les bords, voile diffus sur
  //    les côtés.
  canvas.drawRect(
    tout,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.15),
        radius: 1.0,
        colors: [f.centre, f.base, f.bord],
        stops: const [0, 0.45, 1],
      ).createShader(tout),
  );
  canvas.drawRect(
    tout,
    Paint()
      ..shader = LinearGradient(
        colors: [
          f.voileLateral.withValues(alpha: 0.38),
          f.voileLateral.withValues(alpha: 0),
          f.voileLateral.withValues(alpha: 0),
          f.voileLateral.withValues(alpha: 0.38),
        ],
        stops: const [0, 0.32, 0.68, 1],
      ).createShader(tout),
  );

  // 2. Aurore : nappes diffuses, décalées et inclinées selon leur phase.
  if (force > 0) {
    final nappes = simplifie ? 2 : _nappes.length;
    for (var i = 0; i < nappes; i++) {
      final n = _nappes[i];
      final a = ReglagesFond.amplitudeNappes * cote;
      _ellipse(
        canvas,
        _degradeRond(n.douce ? f.nappeDouce : f.nappe),
        ReglagesFond.opaciteNappes *
            n.opacite *
            (0.8 + 0.2 * math.sin(n.phase)) *
            force,
        Offset(
          size.width * n.x + a * math.sin(n.phase),
          size.height * n.y + 0.6 * a * math.sin(n.phase * 1.3),
        ),
        cote * n.rx * ReglagesFond.tailleNappes,
        cote * n.ry * ReglagesFond.tailleNappes,
        0.25 * math.sin(n.phase),
      );
    }
  }

  // 3. Halo autour des particules.
  final rayonHalo = cote * 0.62;
  _ellipse(
    canvas,
    _degradeRond(f.halo),
    0.55 * ReglagesFond.intensiteLavande,
    centre,
    rayonHalo,
    rayonHalo * 0.92,
  );

  // Périphérie réchauffée en haut et en bas : le voile reste sur les côtés
  // et autour de la sphère.
  canvas.drawRect(
    tout,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          f.peripherie.withValues(alpha: 0.6),
          f.peripherie.withValues(alpha: 0),
          f.peripherie.withValues(alpha: 0),
          f.peripherie.withValues(alpha: 0.65),
        ],
        stops: const [0, 0.28, 0.62, 1],
      ).createShader(tout),
  );

  // 4. Lumière au centre, plus petite que le halo (qui l'entoure donc).
  final rayonLumiere = cote * ReglagesFond.etendueLumiere;
  _ellipse(
    canvas,
    _lumiere(f),
    ReglagesFond.lumiereCentrale * 0.85,
    centre,
    rayonLumiere,
    rayonLumiere * 0.94,
  );

  if (!aurore) {
    // Motif géométrique (ou aucun) par-dessus la base.
    dessinerMotifGeometrique(canvas, tout, motif, palette, intensite);
    return;
  }
  if (force <= 0) return;

  // 5. Courbes lumineuses : venues des bords, elles passent sous la sphère
  //    ou remontent vers elle ; plus vives sur les côtés.
  final c0 = f.courbe;
  final trait = LinearGradient(
    colors: [
      c0.withValues(alpha: 0),
      c0,
      f.courbeMilieu ?? c0,
      c0,
      c0.withValues(alpha: 0),
    ],
    stops: const [0, 0.18, 0.5, 0.82, 1],
  ).createShader(tout);
  final traitLueur = LinearGradient(
    colors: [
      f.lueur.withValues(alpha: 0),
      f.lueur,
      f.lueur.withValues(alpha: 0.6),
      f.lueur,
      f.lueur.withValues(alpha: 0),
    ],
    stops: const [0, 0.18, 0.5, 0.82, 1],
  ).createShader(tout);
  const tour = 2 * math.pi;
  final courbes = simplifie ? 2 : _courbes.length;
  final segments = simplifie ? 28 : 48;
  for (var i = 0; i < courbes; i++) {
    final c = _courbes[i];
    final houle = 1 + 0.25 * math.sin(c.phase);
    final chemin = Path();
    for (var k = 0; k <= segments; k++) {
      final u = -0.05 + 1.1 * k / segments;
      final m = 2 * u - 1;
      final x = u * size.width;
      final y =
          size.height * (c.y + c.creux * (1 - m * m)) +
          cote *
              c.amplitude *
              houle *
              (math.sin(tour * c.onde * u + c.phase) +
                  0.35 * math.sin(tour * c.onde * 2.3 * u - c.phase * 0.7));
      if (k == 0) {
        chemin.moveTo(x, y);
      } else {
        chemin.lineTo(x, y);
      }
    }
    _tracer(
      simplifie,
      (p) => canvas.drawPath(chemin, p),
      trait,
      traitLueur,
      ReglagesFond.opaciteCourbes *
          c.opacite *
          (0.7 + 0.3 * math.sin(c.phase * 2)) *
          force,
    );
  }

  // 6. Anneaux d'énergie inclinés autour de la sphère (les particules sont
  //    dessinées par-dessus : ils passent derrière elle). Vifs sur les
  //    côtés, presque effacés devant.
  final rx = rayonSphere * 1.65;
  final anneau = ui.Gradient.linear(
    Offset(-rx, 0),
    Offset(rx, 0),
    [
      c0.withValues(alpha: 0),
      c0,
      c0.withAlpha(0x40),
      c0,
      c0.withValues(alpha: 0),
    ],
    const [0, 0.14, 0.5, 0.86, 1],
  );
  final anneauLueur = ui.Gradient.linear(
    Offset(-rx, 0),
    Offset(rx, 0),
    [
      f.lueur.withValues(alpha: 0),
      f.lueur,
      f.lueur.withValues(alpha: 0.25),
      f.lueur,
      f.lueur.withValues(alpha: 0),
    ],
    const [0, 0.14, 0.5, 0.86, 1],
  );
  final anneaux = simplifie ? 1 : 2;
  for (var j = 0; j < anneaux; j++) {
    final ry = rx * (0.22 + 0.04 * math.sin(j * 2.3));
    final ovale = Rect.fromCenter(
      center: Offset.zero,
      width: 2 * rx * (j == 0 ? 1 : 1.12),
      height: 2 * ry,
    );
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate((j == 0 ? -0.16 : 0.1) + 0.05 * math.sin(j.toDouble()));
    _tracer(
      simplifie,
      (p) => canvas.drawOval(ovale, p),
      anneau,
      anneauLueur,
      ReglagesFond.opaciteCourbes *
          (j == 0 ? 0.85 : 0.55) *
          (0.75 + 0.25 * math.sin(j * 1.9)) *
          force,
    );
    canvas.restore();
  }
}
