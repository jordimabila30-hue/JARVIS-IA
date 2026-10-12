import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/voice_session.dart';
import '../../theme/theme_jarvis.dart';

/// « Écouter un aperçu » : lit une phrase avec les réglages actuels (voix,
/// langue, vitesse, hauteur, volume). Le même bouton arrête la lecture.
class CarteApercuVoix extends StatelessWidget {
  const CarteApercuVoix({super.key, required this.session});

  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        // Demande en cours (le bouton devient « Arrêter ») ; son réellement
        // entendu (« Lecture… ») ; échec expliqué.
        final lecture = session.apercuEnCours;
        final sonore = session.apercuSonore;
        final erreur = session.erreurApercu;
        // Pendant une conversation vocale, le micro et la voix sont pris.
        final possible = !session.actif;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: CouleursJarvis.trait.withValues(alpha: 0.7),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                CouleursJarvis.coque,
                CouleursJarvis.violet.withValues(alpha: 0.08),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Écouter un aperçu',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: CouleursJarvis.texte,
                            ),
                          ),
                        ),
                        if (sonore) ...[
                          const SizedBox(width: 12),
                          const _Onde(),
                          const SizedBox(width: 8),
                          const Text(
                            'Lecture…',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: CouleursJarvis.signal,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      possible
                          ? '« ${VoiceSession.phraseApercu} »'
                          : 'Disponible en dehors d’une conversation vocale.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        fontStyle: FontStyle.italic,
                        color: CouleursJarvis.texteSecondaire,
                      ),
                    ),
                    if (erreur != null && !lecture) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.volume_off_outlined,
                              size: 16,
                              color: CouleursJarvis.texte,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              erreur,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: CouleursJarvis.texte,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Tooltip(
                message: lecture ? 'Arrêter l’aperçu' : 'Écouter l’aperçu',
                child: IconButton.filled(
                  onPressed: !possible
                      ? null
                      : lecture
                      ? session.arreterApercu
                      : () => session.lireApercu(),
                  style: IconButton.styleFrom(
                    backgroundColor: CouleursJarvis.signal,
                    foregroundColor: CouleursJarvis.ivoire,
                    disabledBackgroundColor: CouleursJarvis.trait,
                    minimumSize: const Size(52, 52),
                  ),
                  icon: Icon(
                    lecture ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Petite onde animée pendant la lecture.
class _Onde extends StatefulWidget {
  const _Onde();

  @override
  State<_Onde> createState() => _OndeState();
}

class _OndeState extends State<_Onde> with SingleTickerProviderStateMixin {
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
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 5; i++)
              Container(
                width: 3,
                height:
                    5 +
                    9 *
                        (0.5 +
                            0.5 *
                                math.sin(_anim.value * 2 * math.pi + i * 1.1)),
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: CouleursJarvis.signal.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
