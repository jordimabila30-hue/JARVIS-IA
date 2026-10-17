import 'package:flutter/material.dart';

import '../../services/jarvis_touch_service.dart';
import '../../theme/theme_jarvis.dart';
import 'elements_parametres.dart';

/// Paramètres › Général : JARVIS Touch (Android seulement) et les
/// informations de l'application.
class PanneauGeneral extends StatelessWidget {
  const PanneauGeneral({super.key, this.touch});

  /// Null : service unique de l'application.
  final JarvisTouchService? touch;

  @override
  Widget build(BuildContext context) {
    final t = touch ?? JarvisTouchService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (t.disponible) ...[
          CarteReglages(
            enfants: [
              ListenableBuilder(
                listenable: t,
                builder: (context, _) => LigneReglage(
                  titre: 'JARVIS Touch',
                  description:
                      'Afficher JARVIS au-dessus des autres applications '
                      'pour y accéder rapidement.',
                  largeurControle: 60,
                  controle: Align(
                    alignment: Alignment.centerRight,
                    child: t.occupe
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: CouleursJarvis.signal,
                              ),
                            ),
                          )
                        : Switch(
                            value: t.actif,
                            activeThumbColor: Colors.white,
                            activeTrackColor: CouleursJarvis.signal,
                            onChanged: t.choisir,
                          ),
                  ),
                  note:
                      t.message ??
                      (t.etat == EtatJarvisTouch.attenteAutorisation
                          ? 'Autorisez « Afficher par-dessus les autres '
                                'applis » pour JARVIS, puis revenez ici.'
                          : null),
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
    );
  }
}

class _Valeur extends StatelessWidget {
  const _Valeur(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    textAlign: TextAlign.right,
    style: const TextStyle(fontSize: 14, color: CouleursJarvis.texteSecondaire),
  );
}
