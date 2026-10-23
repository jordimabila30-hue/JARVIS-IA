import 'package:flutter/material.dart';

import '../../services/apprentissage/seance_lecon.dart';
import '../../theme/theme_jarvis.dart';
import 'elements_apprentissage.dart';

/// Écran compact de fin de séance : réponses justes, notions acquises et
/// à retravailler, Continuer, et Réviser s'il y a des erreurs.
class ResultatSeance extends StatelessWidget {
  const ResultatSeance({
    super.key,
    required this.titre,
    required this.bilan,
    required this.titresFiches,
    required this.surContinuer,
    this.surReviser,
    this.message,
  });

  /// Ligne sous le titre (niveau estimé ou ajusté), facultative.
  final String? message;

  final String titre;
  final BilanSeance bilan;

  /// Fiche (id) → titre affiché.
  final Map<String, String> titresFiches;
  final VoidCallback surContinuer;

  /// Null : rien à revoir.
  final VoidCallback? surReviser;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final succes = CouleursJarvis.lisible(p.succes);
    Widget notions(String libelle, List<String> ids, IconData icone, Color c) =>
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(libelle, style: styleDiscret(context, taille: 12.5)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in ids)
                    Chip(
                      avatar: Icon(icone, size: 16, color: c),
                      label: Text(titresFiches[id] ?? id),
                      backgroundColor: p.coque,
                      side: BorderSide(color: p.trait),
                      labelStyle: TextStyle(fontSize: 13, color: p.texte),
                    ),
                ],
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Icon(Icons.task_alt_rounded, size: 56, color: succes),
        const SizedBox(height: 12),
        Text(
          titre,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: p.identite.policeAffichage,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: p.texte,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(
            message!,
            key: const ValueKey('resultat-message'),
            textAlign: TextAlign.center,
            style: styleDiscret(context, taille: 14.5),
          ),
        ],
        const SizedBox(height: 18),
        SurfaceApprentissage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '${bilan.justes} / ${bilan.total}',
                    key: const ValueKey('score'),
                    style: styleTitre(context, taille: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'bonnes réponses du premier coup',
                      style: styleDiscret(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BarreProgression(
                valeur: bilan.total == 0 ? 0 : bilan.justes / bilan.total,
              ),
              if (bilan.fichesAcquises.isNotEmpty)
                notions(
                  'Notions acquises',
                  bilan.fichesAcquises,
                  Icons.check_rounded,
                  succes,
                ),
              if (bilan.fichesARetravailler.isNotEmpty)
                notions(
                  'À retravailler',
                  bilan.fichesARetravailler,
                  Icons.refresh_rounded,
                  CouleursJarvis.lisible(p.critique),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        BoutonApprentissage(
          key: const ValueKey('resultat-continuer'),
          libelle: 'Continuer',
          surAppui: surContinuer,
        ),
        if (surReviser != null) ...[
          const SizedBox(height: 10),
          BoutonApprentissage(
            key: const ValueKey('resultat-reviser'),
            libelle: 'Réviser',
            icone: Icons.refresh_rounded,
            secondaire: true,
            surAppui: surReviser,
          ),
        ],
      ],
    );
  }
}
