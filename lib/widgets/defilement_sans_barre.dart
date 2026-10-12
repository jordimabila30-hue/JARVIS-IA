import 'package:flutter/material.dart';

/// Défilement de JARVIS : molette, trackpad, doigt et stylet comme
/// d'habitude, mais jamais de barre de défilement visible (Web, Windows,
/// Android, iOS).
///
/// Une classe plutôt que `copyWith(scrollbars: false)` : le champ de saisie
/// multi-ligne réactive les barres pour lui-même, mais les fait dessiner
/// par ce comportement, qui n'en dessine aucune.
class DefilementSansBarre extends MaterialScrollBehavior {
  const DefilementSansBarre();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
