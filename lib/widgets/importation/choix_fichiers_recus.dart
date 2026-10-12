import 'package:flutter/material.dart';

import '../../services/importation/selection_export_whatsapp.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/taille_fichier.dart';

/// Plusieurs fichiers reçus d'un coup (partage ou dépôt) : rien n'est
/// choisi à la place de l'utilisateur, il désigne l'export de la
/// discussion.
class ChoixFichiersRecus extends StatelessWidget {
  const ChoixFichiersRecus({
    super.key,
    required this.fichiers,
    required this.surChoix,
    required this.surAnnuler,
  });

  static const titre = 'Plusieurs fichiers reçus';
  static const consigne =
      'Choisissez l’export de la discussion (ZIP ou TXT). Les autres '
      'fichiers ne sont pas encore pris en charge.';

  final List<FichierBrut> fichiers;
  final ValueChanged<FichierBrut> surChoix;
  final VoidCallback surAnnuler;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      decoration: BoxDecoration(
        color: CouleursJarvis.coque,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CouleursJarvis.trait),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            titre,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: CouleursJarvis.texte,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            consigne,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
          const SizedBox(height: 10),
          for (final f in fichiers)
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                minTileHeight: 52,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(
                  Icons.insert_drive_file_outlined,
                  color: CouleursJarvis.signal,
                ),
                // Deux lignes : l'extension (.zip, .txt) reste visible.
                title: Text(
                  f.nom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: CouleursJarvis.texte,
                  ),
                ),
                subtitle: f.tailleOctets == null
                    ? null
                    : Text(
                        tailleLisible(f.tailleOctets!),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: CouleursJarvis.texteSecondaire,
                        ),
                      ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: CouleursJarvis.texteSecondaire,
                ),
                onTap: () => surChoix(f),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: surAnnuler,
              style: TextButton.styleFrom(
                foregroundColor: CouleursJarvis.texteSecondaire,
                minimumSize: const Size(0, 44),
              ),
              child: const Text('Annuler'),
            ),
          ),
        ],
      ),
    );
  }
}
