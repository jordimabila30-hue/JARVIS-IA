import 'package:flutter/material.dart';

import '../../models/apprentissage/contenu_pedagogique.dart';
import '../../services/apprentissage/catalogue_apprentissage.dart';
import '../../services/apprentissage/espace_apprentissage.dart';
import '../../theme/theme_jarvis.dart';
import '../../widgets/apprentissage/elements_apprentissage.dart';
import '../../widgets/apprentissage/fiche_et_correction.dart';
import 'lecon_page.dart';

/// Ouvre un parcours (noté comme dernier parcours ouvert).
Future<void> ouvrirParcours(
  BuildContext context,
  EspaceApprentissage espace,
  ParcoursCharge parcours,
) {
  espace.progression.ouvrirParcours(parcours.resume.id);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ParcoursPage(espace: espace, parcours: parcours),
    ),
  );
}

/// Chemin d'un parcours : sa progression, ses unités et leurs leçons
/// (à commencer, en cours, terminées). Aucun blocage : toute leçon
/// disponible peut être ouverte.
class ParcoursPage extends StatelessWidget {
  const ParcoursPage({super.key, required this.espace, required this.parcours});

  final EspaceApprentissage espace;
  final ParcoursCharge parcours;

  @override
  Widget build(BuildContext context) {
    final progression = espace.progression;
    return PageApprentissage(
      enTete: EnTeteApprentissage(titre: parcours.resume.titre),
      corps: ListenableBuilder(
        listenable: Listenable.merge([progression, espace.catalogue.apercu]),
        builder: (context, _) {
          final apercu = espace.catalogue.apercu.value;
          final visibles = parcours.leconsVisibles(apercu: apercu).toSet();
          final unites = [
            for (final u in parcours.contenu?.unites ?? const <Unite>[])
              (u, u.lecons.where(visibles.contains).toList()),
          ].where((u) => u.$2.isNotEmpty).toList();
          final avancement = progression.avancement(visibles);
          return LayoutBuilder(
            builder: (context, c) {
              final marge = margeApprentissage(c.maxWidth);
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(marge, 8, marge, 32),
                    sliver: SliverList.list(
                      children: [
                        _centre(
                          SurfaceApprentissage(
                            accent: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      iconeParcours(parcours.resume.icone),
                                      color: PaletteJarvis.of(context).texte,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        visibles.isEmpty
                                            ? 'En préparation'
                                            : '${progression.terminees(visibles)} / ${visibles.length} leçon${visibles.length > 1 ? 's' : ''} terminée${progression.terminees(visibles) > 1 ? 's' : ''}',
                                        style: styleDiscret(
                                          context,
                                          taille: 14,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      pourcentage(avancement),
                                      key: const ValueKey(
                                        'parcours-pourcentage',
                                      ),
                                      style: styleTitre(context, taille: 18),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                BarreProgression(valeur: avancement),
                              ],
                            ),
                          ),
                        ),
                        if (unites.isEmpty)
                          _centre(
                            Padding(
                              padding: const EdgeInsets.only(top: 28),
                              child: _EtatVide(apercu: apercu),
                            ),
                          ),
                        for (final (unite, lecons) in unites) ...[
                          _centre(
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 26, 4, 10),
                              child: Text(
                                unite.titre.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: PaletteJarvis.of(
                                    context,
                                  ).texteSecondaire,
                                ),
                              ),
                            ),
                          ),
                          for (final l in lecons)
                            _centre(
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: CarteLecon(
                                  espace: espace,
                                  parcours: parcours,
                                  lecon: l,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static Widget _centre(Widget enfant) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: largeurContenuApprentissage),
      // Pleine largeur : le contenu s'aligne à gauche.
      child: SizedBox(width: double.infinity, child: enfant),
    ),
  );
}

class _EtatVide extends StatelessWidget {
  const _EtatVide({required this.apercu});

  final bool apercu;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.hourglass_empty_rounded,
          size: 36,
          color: PaletteJarvis.of(context).texteSecondaire,
        ),
        const SizedBox(height: 10),
        Text(
          'Leçons en cours de validation',
          style: styleTitre(context, taille: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'Elles apparaîtront ici dès leur relecture.',
          textAlign: TextAlign.center,
          style: styleDiscret(context),
        ),
      ],
    );
  }
}

/// Carte d'une leçon : état, durée, et les actions possibles.
class CarteLecon extends StatelessWidget {
  const CarteLecon({
    super.key,
    required this.espace,
    required this.parcours,
    required this.lecon,
  });

  final EspaceApprentissage espace;
  final ParcoursCharge parcours;
  final Lecon lecon;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final etat = espace.progression.etat(lecon.id);
    final seance = etat?.seance;
    final enCours = seance != null;
    final terminee = etat?.terminee == true;
    final total = lecon.exercices.length;
    final String statut;
    final IconData icone;
    if (enCours) {
      final fait = seance.position.clamp(0, seance.file.length);
      statut = 'En cours · $fait / ${seance.file.length}';
      icone = Icons.play_arrow_rounded;
    } else if (terminee) {
      statut =
          'Terminée · ${etat!.meilleurScore} / ${etat.total} du premier coup';
      icone = Icons.check_rounded;
    } else {
      statut = 'À commencer';
      icone = Icons.play_arrow_rounded;
    }
    void ouvrir({bool recommencer = false, bool consultation = false}) =>
        ouvrirLecon(
          context,
          espace,
          parcours,
          lecon,
          recommencer: recommencer,
          consultation: consultation,
        );
    final validee = parcours.contenu?.leconValidee(lecon) ?? false;
    return SurfaceApprentissage(
      key: ValueKey('lecon-${lecon.id}'),
      etiquette: '${lecon.titre}, $statut',
      surAppui: terminee && !enCours
          ? () => ouvrir(consultation: true)
          : () => ouvrir(),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: terminee
                      ? CouleursJarvis.lisible(p.succes).withValues(alpha: 0.15)
                      : p.signal.withValues(alpha: 0.12),
                ),
                child: SizedBox.square(
                  dimension: 40,
                  child: Icon(
                    icone,
                    size: 22,
                    color: terminee
                        ? CouleursJarvis.lisible(p.succes)
                        : p.signal,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lecon.titre, style: styleTitre(context, taille: 15)),
                    const SizedBox(height: 3),
                    Text(
                      '≈ ${lecon.dureeMinutes} min · $total exercices',
                      style: styleDiscret(context, taille: 12.5),
                    ),
                    const SizedBox(height: 2),
                    Text(statut, style: styleDiscret(context, taille: 12.5)),
                    if (!validee) ...[
                      const SizedBox(height: 6),
                      const EtiquetteBrouillon(),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (enCours || terminee)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  if (terminee && !enCours)
                    TextButton(
                      onPressed: () => ouvrir(consultation: true),
                      child: const Text('Revoir'),
                    ),
                  TextButton(
                    onPressed: () => ouvrir(recommencer: true),
                    child: Text(enCours ? 'Recommencer' : 'Refaire'),
                  ),
                  if (enCours)
                    TextButton(
                      onPressed: () => ouvrir(),
                      child: const Text('Reprendre'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
