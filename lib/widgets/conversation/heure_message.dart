import 'package:flutter/material.dart';

import '../../utils/local_date_time.dart';

/// Heure d'un message (« 13:08 »), très discrète : petite, lavande grisée,
/// sans icône.
class HeureMessage extends StatelessWidget {
  const HeureMessage(this.heure, {super.key});

  final DateTime heure;

  /// Gris doux nuancé de lavande, peu contrasté sur l'ivoire et le pastel.
  static const couleur = Color(0xFF9A94AE);

  @override
  Widget build(BuildContext context) {
    return Text(
      heureCourte(heure),
      style: const TextStyle(
        fontSize: 11,
        height: 1.2,
        letterSpacing: 0.4,
        color: couleur,
        // Chiffres de même largeur : les heures restent alignées.
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
