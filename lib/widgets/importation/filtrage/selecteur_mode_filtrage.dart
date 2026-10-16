import 'package:flutter/material.dart';

import '../../../models/importation/filtre_whatsapp.dart';
import '../../../theme/theme_jarvis.dart';

/// [Par période] [Par messages] : le mode actif dans une capsule lavande,
/// marqué d'un petit indicateur violet.
class SelecteurModeFiltrage extends StatelessWidget {
  const SelecteurModeFiltrage({
    super.key,
    required this.mode,
    required this.surChoix,
  });

  static const parPeriode = 'Par période';
  static const parMessages = 'Par messages';

  final ModeFiltrage mode;
  final ValueChanged<ModeFiltrage> surChoix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CouleursJarvis.coque.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CouleursJarvis.trait.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          for (final (m, libelle, icone) in const [
            (ModeFiltrage.periode, parPeriode, Icons.calendar_month_outlined),
            (ModeFiltrage.messages, parMessages, Icons.checklist_rounded),
          ])
            Expanded(
              child: _Segment(
                libelle: libelle,
                icone: icone,
                actif: m == mode,
                surAppui: () => surChoix(m),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.libelle,
    required this.icone,
    required this.actif,
    required this.surAppui,
  });

  final String libelle;
  final IconData icone;
  final bool actif;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    final couleur = actif
        ? CouleursJarvis.signal
        : CouleursJarvis.texteSecondaire;
    return Semantics(
      button: true,
      selected: actif,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: surAppui,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: actif ? CouleursJarvis.lavande : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icone, size: 17, color: couleur),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        libelle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: actif ? FontWeight.w600 : FontWeight.w500,
                          color: couleur,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // Indicateur violet du mode actif.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: actif ? 18 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: CouleursJarvis.signal,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Capsule de choix (période, nombre de messages) : lavande quand elle est
/// active, discrète sinon.
class CapsuleChoix extends StatelessWidget {
  const CapsuleChoix({
    super.key,
    required this.libelle,
    required this.actif,
    required this.surAppui,
    this.icone,
    this.souple = false,
  });

  final String libelle;
  final bool actif;
  final VoidCallback? surAppui;
  final IconData? icone;

  /// Largeur bornée par le parent (Wrap, Row) : le libellé se raccourcit
  /// (« … ») plutôt que de déborder. Jamais dans une liste horizontale.
  final bool souple;

  Widget _texte(Color couleur) => Text(
    libelle,
    maxLines: 1,
    overflow: souple ? TextOverflow.ellipsis : null,
    softWrap: false,
    style: TextStyle(
      fontSize: 13.5,
      fontWeight: actif ? FontWeight.w600 : FontWeight.w500,
      color: couleur,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final couleur = actif ? CouleursJarvis.signal : CouleursJarvis.texte;
    return Semantics(
      button: true,
      selected: actif,
      child: Material(
        color: actif
            ? CouleursJarvis.lavande
            : CouleursJarvis.coque.withValues(alpha: 0.92),
        shape: StadiumBorder(
          side: BorderSide(
            color: actif
                ? CouleursJarvis.signal.withValues(alpha: 0.45)
                : CouleursJarvis.trait.withValues(alpha: 0.7),
          ),
        ),
        child: InkWell(
          onTap: surAppui,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icone != null) ...[
                    Icon(icone, size: 16, color: couleur),
                    const SizedBox(width: 6),
                  ],
                  if (souple)
                    Flexible(child: _texte(couleur))
                  else
                    _texte(couleur),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
