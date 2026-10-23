import 'package:flutter/material.dart';

import '../../services/apprentissage/catalogue_apprentissage.dart';
import '../../services/apprentissage/espace_apprentissage.dart';
import '../../services/apprentissage/selection_exercices.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/chrono_perf.dart';
import '../../widgets/apprentissage/cartes_apprendre.dart';
import '../../widgets/apprentissage/elements_apprentissage.dart';
import 'lecon_page.dart';
import 'parcours_page.dart';
import 'situation_page.dart';

/// Ouvre le module Apprendre par-dessus l'accueil. Page opaque : l'accueil
/// passe hors scène et Flutter suspend ses animations (PIM compris) ;
/// elles reprennent telles quelles au retour.
Future<void> ouvrirApprendre(
  BuildContext context,
  EspaceApprentissage espace,
) async {
  // Mesures (JARVIS_PERF seulement) : images du module, puis du retour.
  ChronoPerf.suivreImages();
  ChronoPerf.journal('avant module');
  final TransitionRoute<void> route;
  if (ChronoPerf.sans('apprendre.transition')) {
    route = MaterialPageRoute<void>(
      builder: (_) => ApprendrePage(espace: espace),
    );
  } else {
    final duree = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    route = PageRouteBuilder<void>(
      transitionDuration: duree,
      reverseTransitionDuration: duree,
      pageBuilder: (_, _, _) => ApprendrePage(espace: espace),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
        child: child,
      ),
    );
  }
  await Navigator.of(context).push(route);
  // push se termine dès le début du retour. Garder le PIM suspendu
  // jusqu'au retrait effectif de la route et la fin de son animation.
  await route.completed;
  // Ne pas remettre les compteurs à zéro ici : le service VM mesure
  // aussi les images de retour, avec la même fenêtre avant/après.
}

/// Accueil du module Apprendre (Kelasi) : continuer, accès rapides
/// (Parcours, Pratiquer, Réviser) et les quatre parcours avec leur
/// progression réelle.
class ApprendrePage extends StatefulWidget {
  const ApprendrePage({super.key, required this.espace});

  final EspaceApprentissage espace;

  @override
  State<ApprendrePage> createState() => _ApprendrePageState();
}

class _ApprendrePageState extends State<ApprendrePage> {
  late final Future<void> _pret = widget.espace.preparer();

  @override
  void initState() {
    super.initState();
    if (ChronoPerf.actif) {
      final debut = ChronoPerf.debut();
      _pret.then((_) {
        ChronoPerf.fin('apprendre.donnees', debut);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => ChronoPerf.fin('apprendre.affiche', debut),
        );
      });
    }
  }

  EspaceApprentissage get _espace => widget.espace;

  @override
  Widget build(BuildContext context) {
    return PageApprentissage(
      enTete: EnTeteApprentissage(
        titre: 'Apprendre',
        actions: [
          IconButton(
            tooltip: 'Réglages du module',
            onPressed: () => _reglages(context),
            icon: const Icon(Icons.tune_rounded),
            color: PaletteJarvis.of(context).texte,
          ),
        ],
      ),
      corps: FutureBuilder<void>(
        future: _pret,
        builder: (context, etat) {
          if (etat.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return ListenableBuilder(
            listenable: Listenable.merge([
              _espace.progression,
              _espace.catalogue.apercu,
            ]),
            builder: (context, _) => _Contenu(espace: _espace),
          );
        },
      ),
    );
  }

  Future<void> _reglages(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: PaletteJarvis.of(context).coque,
    builder: (context) => _ReglagesModule(espace: _espace),
  );
}

class _Contenu extends StatelessWidget {
  const _Contenu({required this.espace});

  final EspaceApprentissage espace;

  @override
  Widget build(BuildContext context) {
    final catalogue = espace.catalogue;
    final progression = espace.progression;
    final selection = SelectionExercices(catalogue, progression);
    final apercu = catalogue.apercu.value;
    final parcours = catalogue.parcours ?? const <ParcoursCharge>[];
    final disponible = selection.contenuDisponible;
    final continuer = selection.aContinuer();
    final aRevoir = selection.aRevoir().length;
    final revision = selection.revision();

    ParcoursCharge? premierAvecContenu() {
      for (final p in parcours) {
        if (p.leconsVisibles(apercu: apercu).isNotEmpty) return p;
      }
      return null;
    }

    final ParcoursCharge? parcoursCourant =
        catalogue.parcoursDe(progression.donnees.dernierParcours ?? '') ??
        premierAvecContenu();

    final Widget carte;
    if (!disponible) {
      carte = const CarteContinuer(
        titre: 'Contenus en validation',
        sousTitre: 'Les leçons seront proposées dès leur relecture.',
        icone: Icons.hourglass_empty_rounded,
        surAppui: null,
      );
    } else if (continuer == null) {
      final premier = premierAvecContenu()!;
      carte = CarteContinuer(
        titre: 'Prêt à apprendre ?',
        sousTitre: 'Commencez par ${premier.resume.titre}',
        surAppui: () => ouvrirParcours(context, espace, premier),
      );
    } else {
      final l = continuer.lecon;
      final seance = progression.etat(l.id)?.seance;
      carte = CarteContinuer(
        titre: switch (continuer.etat) {
          EtatContinuer.enCours => 'On continue ?',
          EtatContinuer.suivante => 'Leçon suivante',
          EtatContinuer.terminee => 'Tout est terminé',
        },
        sousTitre: '${continuer.parcours.resume.titre} · ${l.titre}',
        icone: continuer.etat == EtatContinuer.terminee
            ? Icons.replay_rounded
            : Icons.play_arrow_rounded,
        avancement: seance == null || seance.file.isEmpty
            ? progression.avancement(
                continuer.parcours.leconsVisibles(apercu: apercu),
              )
            : seance.position / seance.file.length,
        surAppui: () => ouvrirLecon(
          context,
          espace,
          continuer.parcours,
          l,
          recommencer: continuer.etat == EtatContinuer.terminee,
        ),
      );
    }

    final acces = Row(
      children: [
        Expanded(
          child: AccesRapide(
            key: const ValueKey('acces-parcours'),
            icone: Icons.menu_book_outlined,
            libelle: 'Parcours',
            surAppui: parcoursCourant == null
                ? null
                : () => ouvrirParcours(context, espace, parcoursCourant),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AccesRapide(
            key: const ValueKey('acces-pratiquer'),
            icone: Icons.edit_note_rounded,
            libelle: 'Pratiquer',
            surAppui: disponible
                ? () => ouvrirEntrainement(
                    context,
                    espace,
                    titre: 'Pratiquer',
                    exercices: selection.pratique(),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AccesRapide(
            key: const ValueKey('acces-reviser'),
            icone: Icons.refresh_rounded,
            libelle: 'Réviser',
            note: revision.isEmpty
                ? 'Rien à revoir'
                : aRevoir > 0
                ? '$aRevoir à revoir'
                : null,
            surAppui: revision.isEmpty
                ? null
                : () => ouvrirEntrainement(
                    context,
                    espace,
                    titre: 'Réviser',
                    exercices: revision,
                  ),
          ),
        ),
      ],
    );

    final cartes = [
      for (final p in parcours)
        () {
          final lecons = p.leconsVisibles(apercu: apercu);
          return CarteParcours(
            key: ValueKey('parcours-${p.resume.id}'),
            titre: p.resume.titre,
            icone: iconeParcours(p.resume.icone),
            avancement: progression.avancement(lecons),
            etat: lecons.isEmpty ? 'En préparation' : null,
            surAppui: () => ouvrirParcours(context, espace, p),
          );
        }(),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final marge = margeApprentissage(c.maxWidth);
        Widget centre(Widget w) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: largeurContenuApprentissage,
            ),
            child: SizedBox(width: double.infinity, child: w),
          ),
        );
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(marge, 8, marge, 32),
              sliver: SliverList.list(
                children: [
                  if (apercu) centre(const _BandeauApercu()),
                  centre(carte),
                  const SizedBox(height: 14),
                  centre(acces),
                  const SizedBox(height: 26),
                  centre(
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Mes parcours',
                          style: styleTitre(context, taille: 17),
                        ),
                      ),
                    ),
                  ),
                  centre(GrilleCartes(enfants: cartes)),
                  if (catalogue.situations.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    centre(
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Situations',
                            style: styleTitre(context, taille: 17),
                          ),
                        ),
                      ),
                    ),
                    centre(
                      SizedBox(
                        height: 96,
                        child: ListView.separated(
                          key: const ValueKey('liste-situations'),
                          scrollDirection: Axis.horizontal,
                          itemCount: catalogue.situations.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, i) {
                            final s = catalogue.situations[i];
                            return SizedBox(
                              width: 168,
                              child: SurfaceApprentissage(
                                key: ValueKey('situation-${s.id}'),
                                etiquette: s.titre,
                                padding: const EdgeInsets.all(12),
                                surAppui: () => ouvrirSituation(context, espace, s),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(iconeParcours(s.icone), size: 20),
                                    const Spacer(),
                                    Text(
                                      s.titre,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: styleTitre(context, taille: 13.5),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
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
  }
}

/// Aperçu de développement : les brouillons sont visibles.
class _BandeauApercu extends StatelessWidget {
  const _BandeauApercu();

  @override
  Widget build(BuildContext context) {
    final c = CouleursJarvis.lisible(PaletteJarvis.of(context).critique);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, size: 16, color: c),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Aperçu développeur : fiches en brouillon visibles',
              style: TextStyle(fontSize: 12.5, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReglagesModule extends StatelessWidget {
  const _ReglagesModule({required this.espace});

  final EspaceApprentissage espace;

  Future<void> _effacer(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Effacer la progression ?'),
        content: const Text(
          'Leçons terminées, séances en cours et révisions seront effacées de cet appareil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await espace.progression.effacer();
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final apercu = espace.catalogue.apercu;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (CatalogueApprentissage.apercuDisponible)
              ValueListenableBuilder<bool>(
                valueListenable: apercu,
                builder: (context, v, _) => SwitchListTile(
                  key: const ValueKey('reglage-apercu'),
                  title: const Text('Aperçu des brouillons'),
                  subtitle: const Text('Développement seulement'),
                  value: v,
                  onChanged: (n) => apercu.value = n,
                ),
              ),
            ListTile(
              key: const ValueKey('reglage-effacer'),
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Effacer ma progression'),
              onTap: () => _effacer(context),
            ),
          ],
        ),
      ),
    );
  }
}
