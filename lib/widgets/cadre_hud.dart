import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/theme_jarvis.dart';

/// Panneau en verre laiteux. Quand [accentue] est vrai (élément actif ou
/// survolé), des crochets de visée apparaissent aux quatre coins.
class CadreHud extends StatelessWidget {
  const CadreHud({
    super.key,
    required this.child,
    this.accentue = false,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final bool accentue;
  final EdgeInsetsGeometry padding;

  static const _rayon = 14.0;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: accentue ? 1 : 0),
      duration: const Duration(milliseconds: 180),
      builder: (context, t, enfant) => CustomPaint(
        foregroundPainter: _Crochets(t),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_rayon),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CouleursJarvis.coque.withValues(alpha: 0.68),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14403A55),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
                borderRadius: BorderRadius.circular(_rayon),
                border: Border.all(
                  color: Color.lerp(
                    CouleursJarvis.trait,
                    CouleursJarvis.signal.withValues(alpha: 0.5),
                    t,
                  )!,
                ),
              ),
              child: enfant,
            ),
          ),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _Crochets extends CustomPainter {
  _Crochets(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0) return;
    final p = Paint()
      ..color = CouleursJarvis.signal.withValues(alpha: t)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 10.0;
    const d = -3.0; // les crochets débordent légèrement du cadre
    final w = size.width, h = size.height;
    final coins = [
      [Offset(d, d + l), Offset(d, d), Offset(d + l, d)],
      [Offset(w - d - l, d), Offset(w - d, d), Offset(w - d, d + l)],
      [Offset(d, h - d - l), Offset(d, h - d), Offset(d + l, h - d)],
      [
        Offset(w - d - l, h - d),
        Offset(w - d, h - d),
        Offset(w - d, h - d - l),
      ],
    ];
    for (final c in coins) {
      canvas.drawPath(
        Path()
          ..moveTo(c[0].dx, c[0].dy)
          ..lineTo(c[1].dx, c[1].dy)
          ..lineTo(c[2].dx, c[2].dy),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_Crochets ancien) => ancien.t != t;
}
