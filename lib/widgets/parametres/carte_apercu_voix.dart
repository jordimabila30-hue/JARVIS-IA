import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/voice_session.dart';
import '../../theme/theme_jarvis.dart';

/// Bouton d'aperçu vocal, posé à côté du choix de la voix : lit une phrase
/// avec les réglages actuels (voix, langue, vitesse, hauteur, volume) ; le
/// même bouton arrête la lecture. Indisponible pendant une conversation
/// vocale (le micro et la voix sont pris).
class BoutonApercuVoix extends StatelessWidget {
  const BoutonApercuVoix({super.key, required this.session});

  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final lecture = session.apercuEnCours;
        final possible = !session.actif;
        return Tooltip(
          message: !possible
              ? 'Aperçu indisponible pendant une conversation vocale'
              : lecture
              ? 'Arrêter l’aperçu'
              : 'Écouter un aperçu',
          child: IconButton.filled(
            onPressed: !possible
                ? null
                : lecture
                ? session.arreterApercu
                : () => session.lireApercu(),
            style: IconButton.styleFrom(
              backgroundColor: CouleursJarvis.signal,
              foregroundColor: CouleursJarvis.surSignal,
              disabledBackgroundColor: CouleursJarvis.trait,
              minimumSize: const Size(48, 48),
            ),
            icon: Icon(
              lecture ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 24,
            ),
          ),
        );
      },
    );
  }
}

/// Ligne d'état de l'aperçu, sous la voix, seulement quand elle dit
/// quelque chose : lecture en cours (onde) ou échec expliqué.
class EtatApercuVoix extends StatelessWidget {
  const EtatApercuVoix({super.key, required this.session});

  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final sonore = session.apercuSonore;
        final erreur = session.apercuEnCours ? null : session.erreurApercu;
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: sonore
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const _Onde(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '« ${VoiceSession.phraseApercu} »',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            color: CouleursJarvis.signal,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : erreur != null
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
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
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: CouleursJarvis.texte,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
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
