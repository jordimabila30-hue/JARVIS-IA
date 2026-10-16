import 'package:flutter/material.dart';

import '../../../services/importation/selection_whatsapp.dart';
import '../../../theme/theme_jarvis.dart';
import 'selecteur_mode_filtrage.dart';

/// Commandes du mode « Par messages » : choix d'une plage (premier puis
/// dernier message, dans l'ordre réel), sinon cochage message par message.
class CommandesMessages extends StatelessWidget {
  const CommandesMessages({super.key, required this.selection});

  static const choisirPlage = 'Choisir une plage';
  static const annulerPlage = 'Annuler la plage';
  static const touchezPremier = 'Touchez le premier message de la plage.';
  static const touchezDernier =
      'Premier message choisi. Touchez maintenant le dernier message.';
  static const individuel =
      'Touchez un message pour le cocher ou le décocher, ou choisissez une '
      'plage.';

  final SelectionWhatsApp selection;

  @override
  Widget build(BuildContext context) {
    final s = selection;
    final enCours = s.plageEnCours;
    final consigne = !enCours
        ? individuel
        : s.premierDeLaPlage == null
        ? touchezPremier
        : touchezDernier;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: CapsuleChoix(
            libelle: enCours ? annulerPlage : choisirPlage,
            icone: enCours ? Icons.close_rounded : Icons.linear_scale_rounded,
            actif: enCours,
            souple: true,
            surAppui: enCours ? s.annulerPlage : s.commencerPlage,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: enCours
                ? CouleursJarvis.lavande.withValues(alpha: 0.75)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                enCours ? Icons.touch_app_outlined : Icons.info_outline_rounded,
                size: 16,
                color: enCours
                    ? CouleursJarvis.signal
                    : CouleursJarvis.texteSecondaire,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  consigne,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: enCours ? FontWeight.w600 : FontWeight.w400,
                    color: enCours
                        ? CouleursJarvis.signal
                        : CouleursJarvis.texteSecondaire,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
