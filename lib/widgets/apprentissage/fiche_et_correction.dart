import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/apprentissage/contenu_pedagogique.dart';
import '../../services/apprentissage/seance_lecon.dart';
import '../../theme/theme_jarvis.dart';
import 'elements_apprentissage.dart';

/// Correction affichée sous l'exercice : verdict, bonne réponse (après une
/// erreur), explication courte, accès à la fiche et à ses sources.
class PanneauCorrection extends StatelessWidget {
  const PanneauCorrection({
    super.key,
    required this.correction,
    required this.surContinuer,
    required this.surReessayer,
    this.fiche,
    this.actions,
  });

  /// Actions du professeur IA (Plus simplement, Mon erreur…), facultatives.
  final Widget? actions;

  final Correction correction;
  final VoidCallback surContinuer;
  final VoidCallback surReessayer;
  final FichePedagogique? fiche;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final juste = correction.juste;
    final couleur = CouleursJarvis.lisible(juste ? p.succes : p.erreur);
    return Semantics(
      liveRegion: true,
      child: SurfaceApprentissage(
        key: const ValueKey('correction'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  juste ? Icons.check_circle_rounded : Icons.info_rounded,
                  color: couleur,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    juste ? 'Bonne réponse' : 'Pas tout à fait',
                    style: styleTitre(context).copyWith(color: couleur),
                  ),
                ),
                if (fiche != null)
                  TextButton.icon(
                    onPressed: () => afficherFiche(context, fiche!),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Source'),
                  ),
              ],
            ),
            if (!juste) ...[
              const SizedBox(height: 10),
              Text(
                'Réponse attendue',
                style: styleDiscret(context, taille: 12),
              ),
              const SizedBox(height: 2),
              Text(
                correction.exercice.solution,
                style: TextStyle(fontSize: 14.5, height: 1.4, color: p.texte),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              correction.exercice.explication,
              style: styleDiscret(context, taille: 14).copyWith(height: 1.4),
            ),
            if (actions != null) ...[const SizedBox(height: 10), actions!],
            const SizedBox(height: 14),
            Row(
              children: [
                if (!juste) ...[
                  Expanded(
                    child: BoutonApprentissage(
                      libelle: 'Réessayer',
                      secondaire: true,
                      surAppui: surReessayer,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: BoutonApprentissage(
                    key: const ValueKey('continuer'),
                    libelle: 'Continuer',
                    surAppui: surContinuer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenu d'une fiche : explication, exemples, à éviter.
class ContenuFiche extends StatelessWidget {
  const ContenuFiche({super.key, required this.fiche});

  final FichePedagogique fiche;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final succes = CouleursJarvis.lisible(p.succes);
    final erreur = CouleursJarvis.lisible(p.erreur);
    Widget exemple(String texte, bool bon) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            bon ? Icons.check_rounded : Icons.close_rounded,
            size: 18,
            color: bon ? succes : erreur,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texte,
              style: TextStyle(fontSize: 14.5, height: 1.4, color: p.texte),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(fiche.titre, style: styleTitre(context, taille: 16.5)),
        const SizedBox(height: 8),
        Text(
          fiche.explication,
          style: TextStyle(fontSize: 15, height: 1.45, color: p.texte),
        ),
        for (final e in fiche.exemples) exemple(e, true),
        for (final e in fiche.aEviter) exemple(e, false),
      ],
    );
  }
}

/// Fiche complète et ses sources, en feuille du bas.
Future<void> afficherFiche(BuildContext context, FichePedagogique fiche) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: PaletteJarvis.of(context).coque,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, defilement) => SingleChildScrollView(
          controller: defilement,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!fiche.validee)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: EtiquetteBrouillon(),
                  ),
                ),
              ContenuFiche(fiche: fiche),
              const SizedBox(height: 22),
              Text('Sources', style: styleTitre(context, taille: 14)),
              for (final s in fiche.sources) _LigneSource(s),
            ],
          ),
        ),
      ),
    );

/// « Brouillon · à valider » : fiche non validée (aperçu de développement).
class EtiquetteBrouillon extends StatelessWidget {
  const EtiquetteBrouillon({super.key});

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final c = CouleursJarvis.lisible(p.critique);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          'Brouillon · à valider',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: c,
          ),
        ),
      ),
    );
  }
}

class _LigneSource extends StatelessWidget {
  const _LigneSource(this.source);

  final SourcePedagogique source;

  String get _date {
    final d = DateTime.tryParse(source.consulteLe ?? '');
    if (d == null) return 'Référence bibliographique';
    String deux(int n) => n.toString().padLeft(2, '0');
    return 'Consultée le ${deux(d.day)}/${deux(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final url = source.url;
    final lien = url == null ? null : Uri.tryParse(url);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        lien == null ? Icons.menu_book_outlined : Icons.link_rounded,
        color: PaletteJarvis.of(context).texteSecondaire,
      ),
      title: Text(source.titre, style: styleTitre(context, taille: 14)),
      subtitle: Text(
        '${source.editeur}\n$_date',
        style: styleDiscret(context, taille: 12.5),
      ),
      isThreeLine: true,
      // Ouvert seulement à la demande, dans le navigateur du système.
      onTap: lien == null
          ? null
          : () => launchUrl(lien, mode: LaunchMode.externalApplication),
    );
  }
}
