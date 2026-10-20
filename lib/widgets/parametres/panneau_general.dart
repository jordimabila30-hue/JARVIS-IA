import 'package:flutter/material.dart';

import '../../services/jarvis_touch_service.dart';
import '../../theme/theme_jarvis.dart';
import 'elements_parametres.dart';
import 'pages_jarvis_touch.dart';

/// Paramètres › Général : une entrée JARVIS Touch (Android seulement, page
/// dédiée) et les informations de l'application. [page] : sous-page
/// ouverte (null : Général lui-même).
class PanneauGeneral extends StatelessWidget {
  const PanneauGeneral({super.key, this.touch, this.page, this.surPage});

  /// Null : service unique de l'application.
  final JarvisTouchService? touch;
  final PageGenerale? page;
  final ValueChanged<PageGenerale>? surPage;

  @override
  Widget build(BuildContext context) {
    final t = touch ?? JarvisTouchService.instance;
    void ouvrir(PageGenerale p) => surPage?.call(p);
    return switch (page) {
      PageGenerale.touch => PageJarvisTouch(touch: t, surPage: ouvrir),
      PageGenerale.capture => PageCaptureTouch(touch: t),
      PageGenerale.personnalisation => const PagePersonnalisationTouch(),
      null => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t.disponible) ...[
            CarteReglages(
              enfants: [
                ListenableBuilder(
                  listenable: t,
                  builder: (context, _) => LigneSousPage(
                    icone: Icons.bubble_chart_outlined,
                    titre: 'JARVIS Touch',
                    sousTitre: 'Assistant flottant',
                    statut: t.actif ? 'Activé' : 'Désactivé',
                    surAppui: () => ouvrir(PageGenerale.touch),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          const CarteReglages(
            enfants: [
              LigneReglage(
                titre: 'Langue de l’interface',
                largeurControle: 180,
                controle: _Valeur('Français'),
              ),
              LigneReglage(
                titre: 'Version',
                largeurControle: 180,
                controle: _Valeur('1.0.0'),
              ),
            ],
          ),
        ],
      ),
    };
  }
}

class _Valeur extends StatelessWidget {
  const _Valeur(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    textAlign: TextAlign.right,
    style: TextStyle(fontSize: 14, color: CouleursJarvis.texteSecondaire),
  );
}
