import 'package:flutter/material.dart';

import '../../models/message_conversation.dart';
import '../../theme/theme_jarvis.dart';

/// Conversation collée, intégrée au message de l'utilisateur : un bloc
/// doux où chaque participant est clairement séparé. Une longue
/// conversation est repliée (« Afficher les N messages »).
class CarteConversationExterne extends StatefulWidget {
  const CarteConversationExterne({
    super.key,
    required this.conversation,
    this.taille = 14.5,
  });

  final ConversationExterne conversation;
  final double taille;

  /// Messages visibles avant de replier.
  static const visibles = 8;

  @override
  State<CarteConversationExterne> createState() =>
      _CarteConversationExterneState();
}

class _CarteConversationExterneState extends State<CarteConversationExterne> {
  bool _deplie = false;

  @override
  Widget build(BuildContext context) {
    final lignes = widget.conversation.lignes;
    final replie =
        !_deplie && lignes.length > CarteConversationExterne.visibles;
    final montrees = replie
        ? lignes.sublist(lignes.length - CarteConversationExterne.visibles)
        : lignes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replie)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _deplie = true),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Afficher les ${lignes.length} messages',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: CouleursJarvis.signal,
                    ),
                  ),
                ),
              ),
            ),
          for (var i = 0; i < montrees.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: _Ligne(ligne: montrees[i], taille: widget.taille),
            ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.ligne, required this.taille});

  final LigneConversation ligne;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final moi = ligne.estMoi;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${ligne.locuteur} : ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: moi ? CouleursJarvis.signal : CouleursJarvis.violet,
            ),
          ),
          TextSpan(text: ligne.texte),
        ],
      ),
      style: TextStyle(
        fontSize: taille,
        height: 1.45,
        color: CouleursJarvis.texte,
      ),
    );
  }
}
