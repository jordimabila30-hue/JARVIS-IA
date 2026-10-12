import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';
import '../defilement_sans_barre.dart';

/// Cadre commun des pages d'authentification : fond JARVIS, zones sûres,
/// contenu centré à largeur bornée, défilement quand la place manque
/// (clavier ouvert, petite fenêtre). Une seule mise en page pour toutes
/// les plateformes.
class ConteneurAuth extends StatelessWidget {
  const ConteneurAuth({super.key, required this.child});

  final Widget child;

  /// Largeur maximale du formulaire (grands écrans).
  static const largeurMax = 420.0;

  @override
  Widget build(BuildContext context) {
    return FondJarvis(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, contraintes) {
            final compact = contraintes.maxWidth < 600;
            return ScrollConfiguration(
              behavior: const DefilementSansBarre(),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 20 : 32,
                  vertical: compact ? 24 : 40,
                ),
                child: ConstrainedBox(
                  // Centré verticalement quand tout tient à l'écran.
                  constraints: BoxConstraints(
                    minHeight: (contraintes.maxHeight - (compact ? 48 : 80))
                        .clamp(0, double.infinity),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: largeurMax),
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
