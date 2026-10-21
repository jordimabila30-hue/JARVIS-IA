import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette_jarvis.dart';

/// Registre des motifs décoratifs du fond, indépendant des styles : le
/// style donne les couleurs, le motif la décoration. Chaque motif a son
/// propre dessin (aucun n'est un autre motif recoloré).
enum MotifJarvis {
  aucun('Sans motif', 'Le fond du thème, sans décoration.', null),
  aurore(
    'Aurore JARVIS',
    'Nappes diffuses, courbes et anneaux lumineux d’origine.',
    'JARVIS',
  ),
  kubaLosanges(
    'Kuba 1 · Losanges',
    'Losanges imbriqués du raphia kuba.',
    'Application source : fond « kgrid »',
  ),
  kubaTissu(
    'Kuba 2 · Tissu',
    'Treillis de losanges ponctué de carrés, comme un velours kuba.',
    'Application source : « kubaFill » (vidéo)',
  ),
  kubaFrises(
    'Kuba 3 · Frises',
    'Bandes de losanges tricolores, espacées.',
    'Application source : frise « kband »',
  ),
  coeurKuba(
    'Cœur Kuba',
    'L’emblème de l’application, semé en quinconce.',
    'Application source : orbe « Cœur Kuba »',
  ),
  kubaVelours(
    'Kuba 4 · Velours',
    'Fine trame de losanges tissés, comme un velours de raphia.',
    'Référence fournie (2026-10-20)',
  ),
  kubaLabyrinthe(
    'Kuba 5 · Labyrinthe',
    'Bandes croisées et losanges en spirale, au point pointillé.',
    'Référence fournie (2026-10-20)',
  );

  const MotifJarvis(this.nom, this.description, this.origine);

  final String nom;
  final String description;

  /// D'où vient le motif (null : aucun).
  final String? origine;

  static MotifJarvis depuisNom(String? nom) =>
      values.asNameMap()[nom] ?? MotifJarvis.aurore;
}

/// Intensité par défaut du motif (0 à 1). À 0,5, « Aurore » est
/// exactement le fond d'origine et les motifs kuba ont l'opacité de la
/// source (7 %).
const intensiteMotifParDefaut = 0.5;

/// Dessine un motif géométrique (pas « Aurore », dessiné avec le fond) sur
/// [zone]. Une seule passe par couleur : un chemin pour tout l'écran.
void dessinerMotifGeometrique(
  Canvas canvas,
  Rect zone,
  MotifJarvis motif,
  PaletteJarvis palette,
  double intensite,
) {
  final i = intensite.clamp(0.0, 1.0);
  if (i <= 0.001) return;
  canvas.save();
  canvas.clipRect(zone);
  switch (motif) {
    case MotifJarvis.aucun || MotifJarvis.aurore:
      break;
    case MotifJarvis.kubaLosanges:
      _losanges(canvas, zone, palette, i);
    case MotifJarvis.kubaTissu:
      _tissu(canvas, zone, palette, i);
    case MotifJarvis.kubaFrises:
      _frises(canvas, zone, palette, i);
    case MotifJarvis.coeurKuba:
      _coeurs(canvas, zone, palette, i);
    case MotifJarvis.kubaVelours:
      _velours(canvas, zone, palette, i);
    case MotifJarvis.kubaLabyrinthe:
      _labyrinthe(canvas, zone, palette, i);
  }
  canvas.restore();
}

Paint _trait(Color c, double opacite, double largeur) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = largeur
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true
  ..color = c.withValues(alpha: (c.a * opacite).clamp(0.0, 1.0));

Paint _plein(Color c, double opacite) =>
    Paint()..color = c.withValues(alpha: (c.a * opacite).clamp(0.0, 1.0));

void _losange(Path p, double cx, double cy, double rx, [double? ry]) {
  final h = ry ?? rx;
  p
    ..moveTo(cx, cy - h)
    ..lineTo(cx + rx, cy)
    ..lineTo(cx, cy + h)
    ..lineTo(cx - rx, cy)
    ..close();
}

/// « kgrid » : tuile de 40, losange qui touche les bords + losange
/// intérieur, trait raphia de 2 (opacité source 0,07).
void _losanges(Canvas canvas, Rect zone, PaletteJarvis p, double i) {
  const t = 40.0;
  final chemin = Path();
  for (var y = zone.top - t; y < zone.bottom + t; y += t) {
    for (var x = zone.left - t; x < zone.right + t; x += t) {
      _losange(chemin, x + 20, y + 20, 20);
      _losange(chemin, x + 20, y + 20, 10);
    }
  }
  canvas.drawPath(chemin, _trait(p.motif, 0.14 * i, 2));
}

/// « kubaFill » : losanges jointifs en treillis (raphia) et petit carré
/// central (couleur soleil) dans chaque maille.
void _tissu(Canvas canvas, Rect zone, PaletteJarvis p, double i) {
  const st = 34.0;
  final mailles = Path();
  final carres = Path();
  for (var y = zone.top - st; y < zone.bottom + st; y += st) {
    for (var x = zone.left - st; x < zone.right + st; x += st) {
      _losange(mailles, x + st / 2, y + st / 2, st / 2);
      carres.addRect(
        Rect.fromCenter(
          center: Offset(x + st / 2, y + st / 2),
          width: 5,
          height: 5,
        ),
      );
    }
  }
  canvas.drawPath(mailles, _trait(p.motif, 0.13 * i, 2.4));
  canvas.drawPath(carres, _plein(p.accentsMotif[1], 0.3 * i));
}

/// « kband » : bandes de losanges pleins en trois couleurs (période 30,
/// hauteur 10), répétées tous les 72 px.
void _frises(Canvas canvas, Rect zone, PaletteJarvis p, double i) {
  const ecart = 72.0;
  final couleurs = p.accentsMotif;
  final chemins = List.generate(couleurs.length, (_) => Path());
  var rang = 0;
  for (var y = zone.top + 24; y < zone.bottom + ecart; y += ecart) {
    // Une bande sur deux décalée d'un losange : le rythme varie.
    final decale = rang.isOdd ? 10.0 : 0.0;
    var k = 0;
    for (var x = zone.left - 30 + decale; x < zone.right + 30; x += 10) {
      _losange(chemins[k % couleurs.length], x + 5, y, 5);
      k++;
    }
    rang++;
  }
  for (var k = 0; k < couleurs.length; k++) {
    canvas.drawPath(chemins[k], _plein(couleurs[k], 0.2 * i));
  }
}

/// Orbe « Cœur Kuba » : losanges concentriques tournés (acc3, acc, acc2,
/// raphia) et étoile à quatre branches au centre, en quinconce.
void _coeurs(Canvas canvas, Rect zone, PaletteJarvis p, double i) {
  const pas = 116.0;
  const r = 26.0;
  final a = p.accentsMotif;
  final anneaux = <(Color, double, double)>[
    (a[0], 0.86, 0),
    (a[1], 0.74, math.pi / 4),
    (a[2 % a.length], 0.54, math.pi / 8),
    (p.motif, 0.34, 0),
  ];
  final chemins = List.generate(anneaux.length, (_) => Path());
  final etoiles = Path();
  var rang = 0;
  for (var y = zone.top + pas / 2; y < zone.bottom + pas; y += pas * 0.86) {
    final decale = rang.isOdd ? pas / 2 : 0.0;
    for (var x = zone.left + decale; x < zone.right + pas; x += pas) {
      for (var k = 0; k < anneaux.length; k++) {
        final (_, f, angle) = anneaux[k];
        final rr = r * f;
        final c = math.cos(angle), s = math.sin(angle);
        Offset pt(double dx, double dy) =>
            Offset(x + dx * c - dy * s, y + dx * s + dy * c);
        chemins[k]
          ..moveTo(pt(0, -rr).dx, pt(0, -rr).dy)
          ..lineTo(pt(rr, 0).dx, pt(rr, 0).dy)
          ..lineTo(pt(0, rr).dx, pt(0, rr).dy)
          ..lineTo(pt(-rr, 0).dx, pt(-rr, 0).dy)
          ..close();
      }
      // Étoile (chemin de la source, échelle r / 100 × 1,1).
      const e = r * 0.011;
      etoiles
        ..moveTo(x, y - 20 * e)
        ..cubicTo(x + 2 * e, y - 5 * e, x + 5 * e, y - 2 * e, x + 20 * e, y)
        ..cubicTo(x + 5 * e, y + 2 * e, x + 2 * e, y + 5 * e, x, y + 20 * e)
        ..cubicTo(x - 2 * e, y + 5 * e, x - 5 * e, y + 2 * e, x - 20 * e, y)
        ..cubicTo(x - 5 * e, y - 2 * e, x - 2 * e, y - 5 * e, x, y - 20 * e)
        ..close();
    }
    rang++;
  }
  for (var k = 0; k < anneaux.length; k++) {
    canvas.drawPath(chemins[k], _trait(anneaux[k].$1, 0.22 * i, 1.6));
  }
  canvas.drawPath(etoiles, _plein(a[1], 0.3 * i));
}

/// « Velours » : trame fine de diagonales croisées (pas de 14) et un petit
/// losange plein à une intersection sur deux, en quinconce : une texture
/// serrée et discrète, sans dessin qui accroche l'œil.
void _velours(Canvas canvas, Rect zone, PaletteJarvis p, double i) {
  const pas = 14.0;
  final trame = Path();
  final h = zone.height;
  for (var x = zone.left - h; x < zone.right + h; x += pas) {
    trame
      ..moveTo(x, zone.top)
      ..lineTo(x + h, zone.bottom)
      ..moveTo(x + h, zone.top)
      ..lineTo(x, zone.bottom);
  }
  canvas.drawPath(trame, _trait(p.motif, 0.09 * i, 0.9));
  final points = Path();
  var rang = 0;
  for (var y = zone.top; y < zone.bottom + pas; y += pas / 2) {
    final decale = rang.isOdd ? pas / 2 : 0.0;
    for (var x = zone.left + decale; x < zone.right + pas; x += pas * 2) {
      _losange(points, x, y, 1.8);
    }
    rang++;
  }
  canvas.drawPath(points, _plein(p.motif, 0.22 * i));
}

/// « Labyrinthe » : sur une grille tournée de 45°, des bandes doubles qui
/// se croisent, et dans chaque losange une spirale carrée tracée au point
/// pointillé (le relief des velours kuba brodés).
void _labyrinthe(Canvas canvas, Rect zone, PaletteJarvis p, double i) {
  const cote = 64.0; // côté d'une case, dans le repère tourné
  const bande = 7.0; // largeur des bandes entre deux cases
  const pas = 6.0; // écart entre deux tours de spirale
  canvas.save();
  canvas.translate(zone.center.dx, zone.center.dy);
  canvas.rotate(math.pi / 4);
  final rayon = (zone.size.longestSide * 0.75 / cote).ceil() + 1;
  final bandes = Path();
  final points = Path();
  for (var a = -rayon; a <= rayon; a++) {
    final x = a * cote;
    // Bandes doubles : deux traits de part et d'autre de la limite.
    for (final d in [-bande / 2, bande / 2]) {
      bandes
        ..moveTo(x + d, -rayon * cote)
        ..lineTo(x + d, rayon * cote)
        ..moveTo(-rayon * cote, x + d)
        ..lineTo(rayon * cote, x + d);
    }
  }
  const r2 = 0.7071067811865476;
  final demiL = zone.width / 2 + cote, demiH = zone.height / 2 + cote;
  for (var a = -rayon; a < rayon; a++) {
    for (var b = -rayon; b < rayon; b++) {
      // Seulement les cases visibles (centre ramené dans le repère écran).
      final u = (a + 0.5) * cote, v = (b + 0.5) * cote;
      if (((u - v) * r2).abs() > demiL || ((u + v) * r2).abs() > demiH) {
        continue;
      }
      _spirale(
        points,
        a * cote + bande,
        b * cote + bande,
        cote - 2 * bande,
        pas,
      );
    }
  }
  canvas.drawPath(bandes, _trait(p.motif, 0.18 * i, 1.1));
  canvas.drawPath(points, _plein(p.motif, 0.2 * i));
  canvas.restore();
}

/// Spirale carrée vers l'intérieur dans la case (x, y, c), en petits points
/// (carrés de 1,6) espacés de 3,2 le long du tracé.
void _spirale(Path points, double x, double y, double c, double pas) {
  var gauche = x, haut = y, droite = x + c, bas = y + c;
  final sommets = <Offset>[Offset(gauche, haut)];
  while (droite - gauche > pas && bas - haut > pas) {
    sommets
      ..add(Offset(droite, haut))
      ..add(Offset(droite, bas))
      ..add(Offset(gauche, bas));
    haut += pas;
    sommets.add(Offset(gauche, haut));
    gauche += pas;
    droite -= pas;
    bas -= pas;
    sommets.add(Offset(gauche, haut));
  }
  const ecart = 3.6;
  for (var k = 0; k + 1 < sommets.length; k++) {
    final a = sommets[k], b = sommets[k + 1];
    final longueur = (b - a).distance;
    if (longueur <= 0) continue;
    final n = (longueur / ecart).floor();
    for (var j = 0; j < n; j++) {
      final pt = Offset.lerp(a, b, j / n)!;
      points.addRect(Rect.fromCenter(center: pt, width: 1.6, height: 1.6));
    }
  }
}
