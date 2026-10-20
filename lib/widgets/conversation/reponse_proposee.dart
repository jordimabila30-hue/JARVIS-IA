import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme_jarvis.dart';

/// « Réponse proposée » : le texte à envoyer, avec un bouton Copier.
class ReponseProposee extends StatefulWidget {
  const ReponseProposee({super.key, required this.texte, this.taille = 15});

  final String texte;
  final double taille;

  static const titre = 'Réponse proposée';

  @override
  State<ReponseProposee> createState() => _ReponseProposeeState();
}

class _ReponseProposeeState extends State<ReponseProposee> {
  bool _copie = false;
  Timer? _retour;

  Future<void> _copier() async {
    await Clipboard.setData(ClipboardData(text: widget.texte));
    if (!mounted) return;
    setState(() => _copie = true);
    _retour?.cancel();
    _retour = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copie = false);
    });
  }

  @override
  void didUpdateWidget(ReponseProposee ancien) {
    super.didUpdateWidget(ancien);
    // Nouveau ton, nouveau texte : « Copié » ne vaut plus.
    if (ancien.texte != widget.texte && _copie) {
      _retour?.cancel();
      _copie = false;
    }
  }

  @override
  void dispose() {
    _retour?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ReponseProposee.titre,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
        const SizedBox(height: 10),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            decoration: BoxDecoration(
              color: CouleursJarvis.voile.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: CouleursJarvis.violet.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    widget.texte,
                    style: TextStyle(
                      fontSize: widget.taille,
                      height: 1.5,
                      color: CouleursJarvis.texte,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _copier,
                    icon: Icon(
                      _copie ? Icons.check_rounded : Icons.content_copy_rounded,
                      size: 16,
                    ),
                    label: Text(_copie ? 'Copié' : 'Copier'),
                    style: TextButton.styleFrom(
                      foregroundColor: CouleursJarvis.signal,
                      minimumSize: const Size(0, 40),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
