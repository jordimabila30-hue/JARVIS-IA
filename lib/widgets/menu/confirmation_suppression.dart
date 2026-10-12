import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';

/// Rouge doux des actions destructives (balayage, confirmation).
const rougeSuppression = Color(0xFFC0525E);

/// « Supprimer cette conversation ? » : vrai seulement si l'utilisateur
/// confirme (fermer, Échap ou « Annuler » : faux).
Future<bool> confirmerSuppression(BuildContext context) async {
  final choix = await showDialog<bool>(
    context: context,
    barrierColor: CouleursJarvis.texte.withValues(alpha: 0.18),
    builder: (context) => const _Confirmation(),
  );
  return choix ?? false;
}

class _Confirmation extends StatelessWidget {
  const _Confirmation();

  static const titre = 'Supprimer cette conversation ?';
  static const description =
      'Cette action supprimera la conversation de JARVIS.';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CouleursJarvis.coque,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: CouleursJarvis.trait.withValues(alpha: 0.7)),
      ),
      constraints: const BoxConstraints(maxWidth: 380),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
      actionsPadding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      title: const Text(
        titre,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: CouleursJarvis.texte,
        ),
      ),
      content: const Text(
        description,
        style: TextStyle(
          fontSize: 14,
          height: 1.4,
          color: CouleursJarvis.texteSecondaire,
        ),
      ),
      // Deux boutons côte à côte, à parts égales (jamais empilés).
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: CouleursJarvis.texteSecondaire,
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(fontSize: 14.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Annuler'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: rougeSuppression,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Supprimer'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
