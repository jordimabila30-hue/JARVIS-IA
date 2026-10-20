import 'package:flutter/material.dart';

import '../../services/importation/export_local.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/local_date_time.dart';
import '../../utils/taille_fichier.dart';

/// « 3482 » → « 3 482 » (espace fine insécable).
String nombreEnFrancais(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('\u202f');
    b.write(s[i]);
  }
  return b.toString();
}

/// « 11 octobre 2026 ».
String jourEnFrancais(DateTime d) =>
    '${d.day == 1 ? '1er' : d.day} '
    '${moisEnFrancais(d)} ${d.year}';

/// Plusieurs fichiers texte possibles dans l'archive : l'utilisateur
/// désigne la discussion.
class ChoixDansArchive extends StatelessWidget {
  const ChoixDansArchive({
    super.key,
    required this.candidats,
    required this.surChoix,
  });

  static const titre = 'Quelle discussion lire ?';

  final List<EntreeArchive> candidats;
  final ValueChanged<EntreeArchive> surChoix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: CouleursJarvis.coque,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CouleursJarvis.trait),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titre,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: CouleursJarvis.texte,
            ),
          ),
          const SizedBox(height: 6),
          for (final e in candidats)
            // Material transparent : l'effet au toucher reste visible sur
            // le fond de la carte.
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.description_outlined,
                  color: CouleursJarvis.signal,
                ),
                title: Text(
                  e.nom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, color: CouleursJarvis.texte),
                ),
                subtitle: Text(
                  tailleLisible(e.taille),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: CouleursJarvis.texteSecondaire,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: CouleursJarvis.texteSecondaire,
                ),
                onTap: () => surChoix(e),
              ),
            ),
        ],
      ),
    );
  }
}
