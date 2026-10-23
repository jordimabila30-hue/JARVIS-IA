import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/apprentissage/tuteur.dart';
import '../../services/apprentissage/session_tuteur.dart';
import '../../theme/theme_jarvis.dart';
import 'elements_apprentissage.dart';
import 'fiche_et_correction.dart';

/// Les quatre actions pédagogiques, en petites capsules (une ligne, pas de
/// texte permanent). Une action absente (null) n'est pas affichée.
class ActionsTuteur extends StatelessWidget {
  const ActionsTuteur({
    super.key,
    this.surSimplifier,
    this.surExemple,
    this.surErreur,
    this.surEntrainer,
  });

  final VoidCallback? surSimplifier;
  final VoidCallback? surExemple;
  final VoidCallback? surErreur;
  final VoidCallback? surEntrainer;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    Widget capsule(
      String cle,
      IconData icone,
      String libelle,
      VoidCallback? f,
    ) => ActionChip(
      key: ValueKey(cle),
      avatar: Icon(icone, size: 16, color: p.signal),
      label: Text(libelle),
      labelStyle: TextStyle(fontSize: 13, color: p.texte),
      backgroundColor: p.coque,
      side: BorderSide(color: p.trait),
      visualDensity: VisualDensity.compact,
      onPressed: f,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (surSimplifier != null)
          capsule(
            'tuteur-simplifier',
            Icons.auto_fix_high_rounded,
            ActionTuteur.simplifier.libelle,
            surSimplifier,
          ),
        if (surExemple != null)
          capsule(
            'tuteur-exemple',
            Icons.lightbulb_outline_rounded,
            ActionTuteur.exemple.libelle,
            surExemple,
          ),
        if (surErreur != null)
          capsule(
            'tuteur-erreur',
            Icons.manage_search_rounded,
            ActionTuteur.erreur.libelle,
            surErreur,
          ),
        if (surEntrainer != null)
          capsule(
            'tuteur-entrainer',
            Icons.fitness_center_rounded,
            ActionTuteur.entrainer.libelle,
            surEntrainer,
          ),
      ],
    );
  }
}

/// Demande au professeur IA, en feuille du bas : réponse en direct,
/// arrêt possible, sources validées à la fin. La requête est annulée à la
/// fermeture ; l'appelant libère la session ensuite.
Future<void> afficherTuteur(
  BuildContext context, {
  required SessionTuteur session,
  required DemandeTuteur demande,
  required String titre,
}) {
  session.demander(demande);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: PaletteJarvis.of(context).coque,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      builder: (context, defilement) => SingleChildScrollView(
        controller: defilement,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titre, style: styleTitre(context, taille: 16.5)),
            const SizedBox(height: 12),
            VueTuteur(session: session),
          ],
        ),
      ),
    ),
  ).whenComplete(session.annuler);
}

/// Réponse du tuteur : lignes typées (règle, exemple, conseil…), état,
/// sources. Reconstruite seulement par sa session.
class VueTuteur extends StatelessWidget {
  const VueTuteur({super.key, required this.session});

  final SessionTuteur session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final p = PaletteJarvis.of(context);
        final enCours = session.etat == EtatTuteur.enCours;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (genre, texte) in lignesTuteur(session.texte))
              _Ligne(genre: genre, texte: texte),
            if (enCours) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'JARVIS réfléchit…',
                      style: styleDiscret(context),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('tuteur-arreter'),
                    onPressed: session.annuler,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('Arrêter'),
                  ),
                ],
              ),
            ],
            if (session.etat == EtatTuteur.erreur) ...[
              Text(
                session.erreur ?? '',
                key: const ValueKey('tuteur-erreur-texte'),
                style: TextStyle(color: CouleursJarvis.lisible(p.erreur)),
              ),
              if (session.erreur != SessionTuteur.sansCompte)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('tuteur-reessayer'),
                    onPressed: session.reessayer,
                    child: const Text('Réessayer'),
                  ),
                ),
            ],
            if (session.etat == EtatTuteur.termine &&
                session.sources.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Fiches utilisées',
                style: styleDiscret(context, taille: 12),
              ),
              const SizedBox(height: 6),
              for (final s in session.sources) _Source(source: s),
            ],
            if (session.versionDifferente)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Contenus mis à jour sur le serveur : mettez JARVIS à jour.',
                  style: styleDiscret(context, taille: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.genre, required this.texte});

  final GenreLigne genre;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final (IconData? icone, String? etiquette, Color couleur) = switch (genre) {
      GenreLigne.regle => (Icons.menu_book_outlined, 'Règle', p.signal),
      GenreLigne.exemple => (
        Icons.lightbulb_outline_rounded,
        'Exemple',
        p.texteSecondaire,
      ),
      GenreLigne.conseil => (
        Icons.tips_and_updates_outlined,
        'Conseil',
        p.texteSecondaire,
      ),
      GenreLigne.reussi => (
        Icons.check_rounded,
        'Réussi',
        CouleursJarvis.lisible(p.succes),
      ),
      GenreLigne.ameliorer => (
        Icons.trending_up_rounded,
        'À améliorer',
        CouleursJarvis.lisible(p.critique),
      ),
      GenreLigne.texte => (null, null, p.texte),
    };
    final corps = TextStyle(fontSize: 15, height: 1.45, color: p.texte);
    if (icone == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texte, style: corps),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icone, size: 17, color: couleur),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$etiquette · ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: couleur,
                    ),
                  ),
                  TextSpan(text: texte),
                ],
              ),
              style: corps,
            ),
          ),
        ],
      ),
    );
  }
}

class _Source extends StatelessWidget {
  const _Source({required this.source});

  final SourceTuteur source;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final ref = source.references.isEmpty ? null : source.references.first;
    final lien = ref?.url == null ? null : Uri.tryParse(ref!.url!);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.verified_outlined,
        size: 20,
        color: p.texteSecondaire,
      ),
      title: Text(source.titre, style: styleTitre(context, taille: 13.5)),
      subtitle: Text(
        [
          ?ref?.editeur,
          if (!source.validee) 'brouillon · à valider',
        ].join(' · '),
        style: styleDiscret(context, taille: 12),
      ),
      trailing: source.validee ? null : const EtiquetteBrouillon(),
      onTap: lien == null
          ? null
          : () => launchUrl(lien, mode: LaunchMode.externalApplication),
    );
  }
}
