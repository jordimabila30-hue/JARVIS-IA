import 'package:flutter/material.dart';

import '../theme/theme_jarvis.dart';
import 'importation/logo_whatsapp.dart';

/// Ce que l'utilisateur a choisi dans la feuille « Ajouter à JARVIS ».
enum ChoixAjout { coller, importerWhatsApp }

/// Feuille « Ajouter à JARVIS » (téléphone) : remplace le petit menu du
/// bouton « + », qui pouvait passer sous le clavier. Renvoie le choix, ou
/// null si la feuille est fermée sans choix.
Future<ChoixAjout?> afficherFeuilleAjout(BuildContext context) {
  return showModalBottomSheet<ChoixAjout>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: CouleursJarvis.texte.withValues(alpha: 0.16),
    elevation: 0,
    builder: (context) => const FeuilleAjout(),
  );
}

class FeuilleAjout extends StatelessWidget {
  const FeuilleAjout({super.key});

  static const titre = 'Ajouter à JARVIS';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: CouleursJarvis.coque,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: CouleursJarvis.trait)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A3A3350),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      // La barre de navigation du système ne doit pas couvrir le bas de
      // la feuille (Android en navigation par boutons ou gestes).
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        20 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: CouleursJarvis.trait,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              titre,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: CouleursJarvis.texte,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Choix(
            icone: Icons.content_paste_rounded,
            titre: 'Coller une conversation',
            detail: 'Depuis le presse-papiers',
            surChoix: () => Navigator.of(context).pop(ChoixAjout.coller),
          ),
          const SizedBox(height: 6),
          _Choix(
            visuel: const LogoWhatsApp(taille: 36),
            titre: 'Importer une conversation',
            fleche: true,
            surChoix: () =>
                Navigator.of(context).pop(ChoixAjout.importerWhatsApp),
          ),
        ],
      ),
    );
  }
}

/// Une ligne de la feuille : pastille à icône (ou [visuel], un logo),
/// titre, détail facultatif, flèche facultative. Sans [surChoix], elle est
/// volontairement indisponible (estompée, non cliquable).
class _Choix extends StatelessWidget {
  const _Choix({
    this.icone,
    this.visuel,
    required this.titre,
    this.detail,
    this.fleche = false,
    this.surChoix,
  });

  final IconData? icone;
  final Widget? visuel;
  final String titre;
  final String? detail;
  final bool fleche;
  final VoidCallback? surChoix;

  @override
  Widget build(BuildContext context) {
    final actif = surChoix != null;
    return Semantics(
      button: true,
      enabled: actif,
      child: Opacity(
        opacity: actif ? 1 : 0.55,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: surChoix,
            borderRadius: BorderRadius.circular(16),
            hoverColor: CouleursJarvis.texte.withValues(alpha: 0.03),
            splashColor: CouleursJarvis.signal.withValues(alpha: 0.08),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    if (visuel case final visuel?)
                      SizedBox.square(
                        dimension: 42,
                        child: Center(child: visuel),
                      )
                    else
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: actif
                              ? CouleursJarvis.signal.withValues(alpha: 0.1)
                              : CouleursJarvis.creme,
                        ),
                        child: Icon(
                          icone,
                          size: 20,
                          color: actif
                              ? CouleursJarvis.signal
                              : CouleursJarvis.texteSecondaire,
                        ),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            titre,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: CouleursJarvis.texte,
                            ),
                          ),
                          if (detail case final detail?) ...[
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              style: const TextStyle(
                                fontSize: 13,
                                color: CouleursJarvis.texteSecondaire,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (fleche)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, right: 2),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: CouleursJarvis.texteSecondaire,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
