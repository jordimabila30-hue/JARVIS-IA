import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Icône du Réacteur Arc, au trait : anneau extérieur, dix bobines
/// rectangulaires réparties tout autour, anneaux intérieurs et noyau
/// alvéolé. Dessinée à la taille demandée, dans la couleur demandée.
class IconeReacteurArc extends StatelessWidget {
  const IconeReacteurArc({super.key, this.taille = 32, required this.couleur});

  final double taille;
  final Color couleur;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: taille,
    child: CustomPaint(painter: _ReacteurArc(couleur)),
  );
}

class _ReacteurArc extends CustomPainter {
  const _ReacteurArc(this.couleur);

  final Color couleur;

  static const _bobines = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final trait = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * 0.07)
      ..strokeCap = StrokeCap.round;
    final fin = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.045);
    final plein = Paint()..color = couleur;

    // Anneau extérieur.
    canvas.drawCircle(c, r * 0.94, trait);

    // Bobines : petits blocs radiaux entre l'anneau extérieur et le
    // premier anneau intérieur.
    for (var i = 0; i < _bobines; i++) {
      final angle = 2 * math.pi * i / _bobines - math.pi / 2;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(angle + math.pi / 2);
      final bloc = RRect.fromRectAndRadius(
        Rect.fromLTRB(-r * 0.15, -r * 0.89, r * 0.15, -r * 0.58),
        Radius.circular(r * 0.03),
      );
      canvas.drawRRect(bloc, fin);
      canvas.restore();
    }

    // Anneaux intérieurs.
    canvas.drawCircle(c, r * 0.56, trait);
    canvas.drawCircle(c, r * 0.42, fin);

    // Noyau : disque léger et alvéoles (points en nid d'abeille).
    canvas.drawCircle(
      c,
      r * 0.3,
      Paint()..color = couleur.withValues(alpha: 0.18),
    );
    canvas.drawCircle(c, r * 0.3, fin);
    final pas = r * 0.12;
    final point = math.max(0.6, r * 0.04);
    for (var ligne = -2; ligne <= 2; ligne++) {
      final y = ligne * pas * math.sqrt(3) / 2;
      final decalage = ligne.isOdd ? pas / 2 : 0.0;
      for (var col = -3; col <= 3; col++) {
        final p = Offset(col * pas + decalage, y);
        if (p.distance <= r * 0.24) {
          canvas.drawCircle(c + p, point, plein);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ReacteurArc ancien) => ancien.couleur != couleur;
}
