import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';
import 'elements_apprentissage.dart';

/// Cartes de l'accueil « Apprendre » : continuer, accès rapides, parcours.

/// Carte « Continuer » : la leçon à reprendre, son parcours et son
/// avancement ; ou, sans leçon commencée, une invitation à découvrir.
class CarteContinuer extends StatelessWidget {
  const CarteContinuer({
    super.key,
    required this.titre,
    required this.sousTitre,
    required this.surAppui,
    this.avancement,
    this.icone = Icons.play_arrow_rounded,
  });

  final String titre;
  final String sousTitre;

  /// Null : pas de barre (invitation).
  final double? avancement;
  final IconData icone;
  final VoidCallback? surAppui;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    return SurfaceApprentissage(
      key: const ValueKey('apprendre-continuer'),
      accent: true,
      etiquette: '$titre. $sousTitre',
      surAppui: surAppui,
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre, style: styleTitre(context, taille: 18)),
                    const SizedBox(height: 4),
                    Text(
                      sousTitre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: styleDiscret(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: p.signal,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 44,
                  child: Icon(icone, color: p.surSignal),
                ),
              ),
            ],
          ),
          if (avancement != null) ...[
            const SizedBox(height: 16),
            BarreProgression(valeur: avancement!),
          ],
        ],
      ),
    );
  }
}

/// Accès rapide (Parcours, Pratiquer, Réviser) : icône, libellé, et un
/// compteur discret ou une raison s'il est indisponible.
class AccesRapide extends StatelessWidget {
  const AccesRapide({
    super.key,
    required this.icone,
    required this.libelle,
    required this.surAppui,
    this.note,
  });

  final IconData icone;
  final String libelle;

  /// Null : indisponible (grisé, [note] dit pourquoi).
  final VoidCallback? surAppui;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final actif = surAppui != null;
    final couleur = actif ? p.texte : p.texteSecondaire.withValues(alpha: 0.6);
    return SurfaceApprentissage(
      surAppui: surAppui,
      etiquette: note == null ? libelle : '$libelle, $note',
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 22, color: couleur),
            const SizedBox(height: 8),
            Text(
              libelle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: couleur,
              ),
            ),
            SizedBox(
              height: 18,
              child: note == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styleDiscret(context, taille: 11.5),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte d'un parcours : icône, nom, barre de progression (toujours
/// présente), pourcentage réel, indicateur d'ouverture.
class CarteParcours extends StatelessWidget {
  const CarteParcours({
    super.key,
    required this.titre,
    required this.icone,
    required this.avancement,
    required this.surAppui,
    this.etat,
  });

  final String titre;
  final IconData icone;
  final double avancement;

  /// Remplace « 45 % terminé » (« En préparation » sans leçon publiée).
  final String? etat;
  final VoidCallback? surAppui;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final legende = etat ?? '${pourcentage(avancement)} terminé';
    return SurfaceApprentissage(
      surAppui: surAppui,
      etiquette: '$titre, $legende',
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Icon(icone, size: 22, color: p.texte),
            ),
            const SizedBox(height: 10),
            Text(
              titre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: styleTitre(context, taille: 15.5).copyWith(height: 1.2),
            ),
            const SizedBox(height: 10),
            BarreProgression(valeur: avancement),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    legende,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styleDiscret(context, taille: 12.5),
                  ),
                ),
                Icon(
                  Icons.north_east_rounded,
                  size: 16,
                  color: surAppui == null ? p.trait : p.texteSecondaire,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Grille responsive : 2 colonnes (1 sur un écran très étroit).
class GrilleCartes extends StatelessWidget {
  const GrilleCartes({super.key, required this.enfants, this.espace = 12});

  final List<Widget> enfants;
  final double espace;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final colonnes = c.maxWidth < 300 ? 1 : 2;
        final lignes = <Widget>[];
        for (var i = 0; i < enfants.length; i += colonnes) {
          if (i > 0) lignes.add(SizedBox(height: espace));
          lignes.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var k = 0; k < colonnes; k++) ...[
                    if (k > 0) SizedBox(width: espace),
                    Expanded(
                      child: i + k < enfants.length
                          ? enfants[i + k]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: lignes,
        );
      },
    );
  }
}
