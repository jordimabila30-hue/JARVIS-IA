import 'package:flutter/material.dart';

import '../../../theme/theme_jarvis.dart';
import '../lecture_whatsapp_widgets.dart';

/// Barre du bas, stable : nombre de messages sélectionnés et « Continuer
/// vers l'enregistrement ». Le bouton reste inactif sans sélection, et
/// tant que l'enregistrement (interface 3) n'existe pas ([surContinuer]
/// null) : une ligne discrète dit pourquoi.
class BarreSelection extends StatelessWidget {
  const BarreSelection({
    super.key,
    required this.nombre,
    required this.surContinuer,
  });

  static const continuer = 'Continuer vers l’enregistrement';
  static const aucun = 'Aucun message sélectionné';
  static const choisirUn = 'Choisissez au moins un message.';
  static const indisponible =
      'Enregistrement bientôt disponible : rien n’est enregistré.';

  final int nombre;
  final VoidCallback? surContinuer;

  static String compteur(int n) => n == 0
      ? aucun
      : '${nombreEnFrancais(n)} message${n > 1 ? 's' : ''} '
            'sélectionné${n > 1 ? 's' : ''}';

  @override
  Widget build(BuildContext context) {
    final actif = nombre > 0 && surContinuer != null;
    final aide = nombre == 0
        ? choisirUn
        : surContinuer == null
        ? indisponible
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: nombre > 0 ? CouleursJarvis.signal : CouleursJarvis.trait,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  compteur(nombre),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CouleursJarvis.texte,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: actif ? surContinuer : null,
          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
          iconAlignment: IconAlignment.end,
          label: const Text(continuer, textAlign: TextAlign.center),
          style: FilledButton.styleFrom(
            backgroundColor: CouleursJarvis.signal,
            foregroundColor: CouleursJarvis.ivoire,
            disabledBackgroundColor: CouleursJarvis.signal.withValues(
              alpha: 0.14,
            ),
            disabledForegroundColor: CouleursJarvis.signal.withValues(
              alpha: 0.55,
            ),
            minimumSize: const Size(0, 52),
            textStyle: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        if (aide != null) ...[
          const SizedBox(height: 6),
          Text(
            aide,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ],
      ],
    );
  }
}
