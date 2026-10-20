import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';

/// Signature des réponses de JARVIS : une petite perle lumineuse
/// (bleu-violet, halo ivoire, anneau blanc ouvert) suivie de « JARVIS » en
/// capitales fines et espacées, dans la police du logo.
///
/// Dessin fixe et léger : dégradés seulement, ni flou ni animation.
class SignatureJarvis extends StatelessWidget {
  const SignatureJarvis({super.key, this.compacte = false});

  /// Téléphone : un peu plus petite.
  final bool compacte;

  static const texte = 'JARVIS';

  /// Bleu-violet doux, plus léger que le signal plein.
  static Color get couleur => PaletteJarvis.active.signature;

  @override
  Widget build(BuildContext context) {
    final perle = compacte ? 12.0 : 13.0;
    return Semantics(
      label: 'Réponse de JARVIS',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PerleJarvis(taille: perle),
          SizedBox(width: compacte ? 7 : 8),
          Text(
            texte,
            style: TextStyle(
              fontFamily: policeAffichage,
              fontSize: compacte ? 10 : 10.5,
              height: 1,
              fontWeight: FontWeight.w300,
              // Police variable : vrai trait fin, sans graisse simulée.
              fontVariations: const [FontVariation('wght', 340)],
              letterSpacing: compacte ? 3.0 : 3.4,
              color: couleur.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// Symbole lumineux de JARVIS : petite perle bleu-violet (halo ivoire,
/// anneau blanc ouvert). Le même dessin sert à la signature des réponses
/// et, agrandi, au menu latéral.
class PerleJarvis extends StatelessWidget {
  const PerleJarvis({super.key, this.taille = 13});

  final double taille;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: taille,
    child: const CustomPaint(painter: _PerleJarvis()),
  );
}

/// Perle de la signature, d'après la référence : disque ivoire-lavande
/// très doux, sphère bleu-violet éclairée en haut à gauche avec un reflet
/// pêche en bas, anneau blanc ouvert au centre.
class _PerleJarvis extends CustomPainter {
  const _PerleJarvis();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // Halo : disque clair à bord fondu.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xF2FBF8FF), Color(0xCCF1ECFA), Color(0x00F1ECFA)],
          stops: [0.55, 0.8, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Sphère bleu-violet.
    final rs = r * 0.68;
    final sphere = Rect.fromCircle(center: c, radius: rs);
    canvas.drawCircle(
      c,
      rs,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.45, -0.5),
          radius: 1.15,
          colors: [
            Color(0xFFDCE6FE),
            Color(0xFFAAB6F8),
            Color(0xFF9398EC),
            Color(0xFFB9ADEE),
            Color(0xFFF6DED8),
          ],
          stops: [0, 0.32, 0.62, 0.86, 1],
        ).createShader(sphere),
    );
    // Anneau blanc ouvert (en haut à gauche).
    final ra = rs * 0.48;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: ra),
      -math.pi * 0.42,
      math.pi * 1.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.8, r * 0.13)
        ..color = const Color(0xF2FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_PerleJarvis ancien) => false;
}
