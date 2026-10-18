import 'package:flutter/material.dart';

import '../../models/utilisation/utilisation.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/format_utilisation.dart';

/// Couleur d'une jauge : bleu (signal JARVIS) en utilisation normale,
/// orange dès le seuil critique donné par le serveur.
Color couleurJauge(Jauge j) =>
    j.critique ? CouleursJarvis.critique : CouleursJarvis.signal;

/// « 42 / 100 messages », « 1 200 messages · illimité ».
String valeurJauge(Jauge j, String unite) => j.illimitee
    ? '${nombreGroupe(j.utilise)} $unite · illimité'
    : '${nombreGroupe(j.utilise)} / ${nombreGroupe(j.limite!)} $unite';

/// Jauge d'utilisation en LECTURE SEULE (aucune interaction possible) :
/// titre, valeur, barre animée, pourcentage ou « Limite atteinte ».
/// Sans [jauge] (valeur inconnue) : « — », barre vide, jamais un faux zéro.
class JaugeUtilisation extends StatelessWidget {
  const JaugeUtilisation({
    super.key,
    required this.titre,
    required this.jauge,
    required this.unite,
    this.sousTitre,
    this.compacte = false,
  });

  final String titre;

  /// null : consommation inconnue (pas encore lue, ou journée terminée).
  final Jauge? jauge;

  /// « messages », « tokens ».
  final String unite;

  /// Réinitialisation, précision (gris).
  final String? sousTitre;

  /// Variante plus discrète (détails d'une session).
  final bool compacte;

  @override
  Widget build(BuildContext context) {
    final jauge = this.jauge;
    final couleur = jauge == null ? CouleursJarvis.signal : couleurJauge(jauge);
    final valeur = jauge == null ? '— $unite' : valeurJauge(jauge, unite);
    final etat = jauge == null || jauge.illimitee
        ? null
        : jauge.atteinte
        ? 'Limite atteinte'
        : '${jauge.pourcentage} %';
    return Semantics(
      label: titre,
      value: jauge == null
          ? 'indisponible'
          : '$valeur${etat == null ? '' : ', $etat'}',
      readOnly: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compacte ? 8 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 2,
                children: [
                  Text(
                    titre,
                    style: TextStyle(
                      fontSize: compacte ? 13 : 14.5,
                      fontWeight: FontWeight.w500,
                      color: CouleursJarvis.texte,
                    ),
                  ),
                  Text(
                    valeur,
                    style: TextStyle(
                      fontSize: compacte ? 12.5 : 13.5,
                      color: CouleursJarvis.texteSecondaire,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              SizedBox(height: compacte ? 6 : 9),
              _Barre(
                fraction: jauge?.fraction ?? 0,
                couleur: couleur,
                epaisseur: compacte ? 6 : 8,
              ),
              if (sousTitre != null || etat != null) ...[
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        sousTitre ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: CouleursJarvis.texteSecondaire,
                        ),
                      ),
                    ),
                    if (etat != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        etat,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: jauge!.critique
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: jauge.critique
                              ? CouleursJarvis.critique
                              : CouleursJarvis.texteSecondaire,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Barre arrondie : longueur et couleur animées brièvement à chaque
/// nouvelle valeur (aucune animation continue).
class _Barre extends StatelessWidget {
  const _Barre({
    required this.fraction,
    required this.couleur,
    required this.epaisseur,
  });

  final double fraction;
  final Color couleur;
  final double epaisseur;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: epaisseur,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CouleursJarvis.sable.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(epaisseur),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: fraction),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, valeur, _) => TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: couleur),
            duration: const Duration(milliseconds: 300),
            builder: (context, teinte, _) => Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: valeur.clamp(0.0, 1.0),
                heightFactor: 1,
                child: DecoratedBox(
                  key: const ValueKey('barre-remplie'),
                  decoration: BoxDecoration(
                    color: teinte ?? couleur,
                    borderRadius: BorderRadius.circular(epaisseur),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
