import 'package:flutter/material.dart';

/// Frise kuba (« kband » de l'application source) : losanges pleins posés
/// bout à bout, dans l'ordre de [couleurs], sur le fond [fond]. La hauteur
/// donne la taille des losanges (10 px dans la source).
class FriseKuba extends StatelessWidget {
  const FriseKuba({
    super.key,
    required this.couleurs,
    required this.fond,
    this.hauteur = 8,
  });

  final List<Color> couleurs;
  final Color fond;
  final double hauteur;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: hauteur,
    width: double.infinity,
    child: RepaintBoundary(
      child: CustomPaint(painter: PeintreFrise(couleurs, fond)),
    ),
  );
}

class PeintreFrise extends CustomPainter {
  const PeintreFrise(this.couleurs, this.fond);

  final List<Color> couleurs;
  final Color fond;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fond);
    final h = size.height;
    if (h <= 0 || couleurs.isEmpty) return;
    final chemins = List.generate(couleurs.length, (_) => Path());
    var k = 0;
    for (var x = 0.0; x < size.width; x += h) {
      chemins[k % couleurs.length]
        ..moveTo(x, h / 2)
        ..lineTo(x + h / 2, 0)
        ..lineTo(x + h, h / 2)
        ..lineTo(x + h / 2, h)
        ..close();
      k++;
    }
    for (var i = 0; i < couleurs.length; i++) {
      canvas.drawPath(chemins[i], Paint()..color = couleurs[i]);
    }
  }

  @override
  bool shouldRepaint(PeintreFrise ancien) =>
      ancien.fond != fond || !_memes(ancien.couleurs, couleurs);

  static bool _memes(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
