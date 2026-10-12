import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/message_conversation.dart';
import '../../theme/gabarit_jarvis.dart';
import '../../theme/theme_jarvis.dart';
import 'choix_ton.dart';
import 'heure_message.dart';
import 'signature_jarvis.dart';
import 'reponse_proposee.dart';

/// Habillage commun des messages de JARVIS : carte claire ivoire nuancée
/// de lavande, signature « • JARVIS » ([SignatureJarvis]), heure en bas à
/// droite.
class _CadreJarvis extends StatelessWidget {
  const _CadreJarvis({required this.child, this.heure});

  final Widget child;

  /// Heure de la réponse ; aucune pendant la réflexion.
  final DateTime? heure;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(18, 14, 16, heure == null ? 16 : 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // Fond très légèrement translucide (94 %) : les particules qui
            // passent derrière restent devinables, le texte reste net.
            colors: [Color(0xF0FFFDF9), Color(0xF0F7F3FD)],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(
            color: CouleursJarvis.trait.withValues(alpha: 0.6),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A3A3350),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Même signature pour toutes les réponses de JARVIS.
            SignatureJarvis(compacte: GabaritJarvis.of(context).compact),
            const SizedBox(height: 9),
            child,
            if (heure != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: HeureMessage(heure!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Message de JARVIS : texte, et selon le cas raccourcis discrets ou
/// « Quel ton ? » puis « Réponse proposée ».
class CarteJarvis extends StatelessWidget {
  const CarteJarvis({
    super.key,
    required this.message,
    required this.surTon,
    required this.surAction,
    this.taille = 15,
  });

  final MessageConversation message;
  final ValueChanged<TonReponse> surTon;
  final ValueChanged<ActionRapide> surAction;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final reponse = message.reponseProposee;
    return _CadreJarvis(
      heure: message.heure,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.texte,
            style: TextStyle(
              fontSize: taille,
              height: 1.55,
              letterSpacing: 0.1,
              color: CouleursJarvis.texte,
            ),
          ),
          if (message.choixTon) ...[
            const SizedBox(height: 18),
            ChoixTon(ton: message.ton, surChoix: surTon),
          ],
          if (reponse != null) ...[
            const SizedBox(height: 18),
            ReponseProposee(texte: reponse, taille: taille),
          ],
          if (message.actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in message.actions)
                  _Raccourci(action: a, surAction: () => surAction(a)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Raccourci discret (« Comprendre », « Résumer »…).
class _Raccourci extends StatelessWidget {
  const _Raccourci({required this.action, required this.surAction});

  final ActionRapide action;
  final VoidCallback surAction;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: surAction,
      style: OutlinedButton.styleFrom(
        foregroundColor: CouleursJarvis.signal,
        backgroundColor: Colors.white.withValues(alpha: 0.5),
        side: BorderSide(color: CouleursJarvis.signal.withValues(alpha: 0.25)),
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(action.libelle),
    );
  }
}

/// JARVIS prépare sa réponse : trois points qui respirent doucement.
class ReflexionJarvis extends StatefulWidget {
  const ReflexionJarvis({super.key});

  @override
  State<ReflexionJarvis> createState() => _ReflexionJarvisState();
}

class _ReflexionJarvisState extends State<ReflexionJarvis>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'JARVIS réfléchit',
      child: _CadreJarvis(
        child: SizedBox(
          height: 18,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: CouleursJarvis.violet.withValues(
                          alpha:
                              0.25 +
                              0.55 *
                                  (0.5 +
                                      0.5 *
                                          math.sin(
                                            (_anim.value - i * 0.18) *
                                                2 *
                                                math.pi,
                                          )),
                        ),
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
