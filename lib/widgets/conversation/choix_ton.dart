import 'package:flutter/material.dart';

import '../../models/message_conversation.dart';
import '../../theme/theme_jarvis.dart';

/// « Quel ton ? » : capsules élégantes, l'état actif bien visible.
class ChoixTon extends StatelessWidget {
  const ChoixTon({super.key, required this.ton, required this.surChoix});

  final TonReponse? ton;
  final ValueChanged<TonReponse> surChoix;

  static const titre = 'Quel ton ?';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titre,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in TonReponse.values)
              _Capsule(ton: t, choisi: t == ton, surChoix: () => surChoix(t)),
          ],
        ),
      ],
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.ton,
    required this.choisi,
    required this.surChoix,
  });

  final TonReponse ton;
  final bool choisi;
  final VoidCallback surChoix;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: choisi,
      button: true,
      child: Material(
        color: choisi
            ? CouleursJarvis.signal.withValues(alpha: 0.12)
            : CouleursJarvis.ivoire.withValues(alpha: 0.9),
        shape: StadiumBorder(
          side: BorderSide(
            color: choisi
                ? CouleursJarvis.signal.withValues(alpha: 0.55)
                : CouleursJarvis.trait,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: surChoix,
          hoverColor: CouleursJarvis.signal.withValues(alpha: 0.05),
          focusColor: CouleursJarvis.signal.withValues(alpha: 0.12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 38),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (choisi) ...[
                    Icon(Icons.check, size: 15, color: CouleursJarvis.signal),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    ton.libelle,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: choisi ? FontWeight.w600 : FontWeight.w400,
                      color: choisi
                          ? CouleursJarvis.signal
                          : CouleursJarvis.texte,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
