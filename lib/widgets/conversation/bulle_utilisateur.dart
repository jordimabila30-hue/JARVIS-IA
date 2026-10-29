import 'package:flutter/material.dart';

import '../../models/capture_jointe.dart';
import '../../models/message_conversation.dart';
import '../../services/capture/fichier_capture.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/chrono_perf.dart';
import 'carte_conversation_externe.dart';
import 'carte_piece_jointe.dart';
import 'heure_message.dart';

/// Message de l'utilisateur : bulle pastel lavande-bleu très douce, à
/// droite, avec l'éventuelle conversation collée intégrée et l'heure en
/// bas à droite.
class BulleUtilisateur extends StatelessWidget {
  const BulleUtilisateur({super.key, required this.message, this.taille = 15});

  final MessageConversation message;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final conversation = message.conversation;
    final piece = message.pieceJointe;
    final p = PaletteJarvis.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: LayoutBuilder(
        builder: (context, contraintes) => ConstrainedBox(
          // Une conversation collée prend plus de place qu'une phrase.
          constraints: BoxConstraints(
            maxWidth:
                contraintes.maxWidth *
                (conversation == null && piece == null ? 0.82 : 0.92),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: p.bulleUtilisateur,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
              // Styles importés : contour marqué et ombre pleine décalée
              // (« box-shadow: 4px 4px 0 » de la source).
              border: Border.all(
                color: p.bordBulle,
                width: p.identite.marquee ? p.identite.contour : 1,
              ),
              // Mesure seulement (JARVIS_PERF) : coût des ombres.
              boxShadow: ChronoPerf.sans('bulle.ombre')
                  ? null
                  : [
                      if (p.identite.ombreBulle case final ombre?)
                        BoxShadow(color: ombre, offset: const Offset(4, 4))
                      else
                        BoxShadow(
                          color: p.ombre.withAlpha(0x0D),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                    ],
            ),
            // Contenu aligné à gauche ; l'heure, en dessous, à droite.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (conversation != null)
                      CarteConversationExterne(
                        conversation: conversation,
                        taille: taille - 0.5,
                      ),
                    if (piece != null)
                      CartePieceJointeEnvoyee(
                        piece: piece,
                        taille: taille - 0.5,
                      ),
                    if (message.capture case final capture?)
                      _CaptureJointe(capture),
                    if ((conversation != null ||
                            piece != null ||
                            message.capture != null) &&
                        message.texte.isNotEmpty)
                      const SizedBox(height: 10),
                    if (message.texte.isNotEmpty)
                      Text(
                        message.texte,
                        style: TextStyle(
                          fontSize: taille,
                          height: 1.5,
                          color: CouleursJarvis.texte,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                HeureMessage(message.heure),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Capture d'écran jointe (JARVIS Touch) : miniature si le fichier local
/// existe encore, sinon une simple mention (l'image n'est jamais gardée
/// par le serveur).
class _CaptureJointe extends StatelessWidget {
  const _CaptureJointe(this.capture);

  final CaptureJointe capture;

  @override
  Widget build(BuildContext context) {
    final chemin = capture.chemin;
    final image = chemin == null ? null : miniatureCapture(chemin);
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160, maxHeight: 220),
          child: Image(
            image: image,
            fit: BoxFit.cover,
            semanticLabel: 'Capture d’écran jointe',
            errorBuilder: (_, _, _) => const _MentionCapture(),
          ),
        ),
      );
    }
    return const _MentionCapture();
  }
}

class _MentionCapture extends StatelessWidget {
  const _MentionCapture();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.screenshot_outlined, size: 16, color: CouleursJarvis.signal),
      SizedBox(width: 6),
      Text(
        'Capture d’écran jointe',
        style: TextStyle(fontSize: 13, color: CouleursJarvis.texteSecondaire),
      ),
    ],
  );
}
