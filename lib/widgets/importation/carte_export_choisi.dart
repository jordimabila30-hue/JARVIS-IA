import 'package:flutter/material.dart';

import '../../models/importation/export_whatsapp.dart';
import '../../services/importation/lecture_whatsapp.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/taille_fichier.dart';
import 'accueil_import_whatsapp.dart';

/// Où en est le fichier reçu.
sealed class EtatFichier {
  const EtatFichier();
}

/// Lecture en cours (lancée d'elle-même à la réception).
final class FichierEnLecture extends EtatFichier {
  const FichierEnLecture(this.etape, this.fraction);
  final EtapeLecture etape;

  /// Entre 0 et 1 quand elle se mesure ; null : indéterminée.
  final double? fraction;
}

/// Lecture réussie : la conversation est reconstruite.
final class FichierPret extends EtatFichier {
  const FichierPret();
}

/// Lecture arrêtée (erreur ou annulation) : on peut relancer.
final class FichierNonLu extends EtatFichier {
  const FichierNonLu();
}

/// Le fichier reçu : nom, format, taille ; puis l'état de la lecture et
/// deux actions discrètes (« Voir le résumé », « Changer de fichier »).
/// L'action principale (« Filtrer les messages ») est hors de la carte :
/// [ActionFiltrer], posée en bas de l'écran par la page.
class CarteExportChoisi extends StatelessWidget {
  const CarteExportChoisi({
    super.key,
    required this.fichier,
    required this.etat,
    required this.surChanger,
    required this.surRetirer,
    this.surAnnuler,
    this.surRelire,
    this.surResume,
  });

  static const pret = 'Conversation prête';
  static const lecture = 'Lecture de la conversation…';
  static const filtrer = 'Filtrer les messages';
  static const filtrageAVenir = 'Bientôt disponible';
  static const resume = 'Voir le résumé';
  static const relire = 'Relire le fichier';
  static const changer = 'Changer de fichier';
  static const retirer = 'Retirer le fichier';

  final FichierExportWhatsApp fichier;
  final EtatFichier etat;
  final VoidCallback surChanger;
  final VoidCallback surRetirer;
  final VoidCallback? surAnnuler;
  final VoidCallback? surRelire;
  final VoidCallback? surResume;

  /// « ZIP · 17,5 Mo », « TXT · taille inconnue · reçu par partage ».
  static String detail(FichierExportWhatsApp f) {
    final taille = f.tailleOctets;
    return [
      f.format.libelle,
      taille == null ? 'taille inconnue' : tailleLisible(taille),
      ?switch (f.source) {
        SourceReception.partageAndroid => 'reçu par partage',
        SourceReception.glisserDeposer => 'déposé',
        SourceReception.selecteur => null,
      },
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final archive = fichier.format == FormatExportWhatsApp.zip;
    final etat = this.etat;
    final pret = etat is FichierPret;
    // Même taille que la carte du premier écran ; contenu centré.
    return Container(
      constraints: const BoxConstraints(
        minHeight: CarteImporterWhatsApp.hauteurMin,
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      decoration: BoxDecoration(
        color: CouleursJarvis.coque,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CouleursJarvis.trait.withValues(alpha: 0.8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D3A3350),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: CouleursJarvis.violetPoudre.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    archive
                        ? Icons.folder_zip_outlined
                        : Icons.insert_drive_file_outlined,
                    size: 28,
                    color: CouleursJarvis.signal,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Marges latérales : la place du × reste libre.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Text(
                  fichier.nom,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: CouleursJarvis.texte,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail(fichier),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
              const SizedBox(height: 16),
              ..._suite(etat, pret),
            ],
          ),
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              tooltip: retirer,
              onPressed: surRetirer,
              icon: const Icon(Icons.close_rounded, size: 18),
              style: IconButton.styleFrom(
                foregroundColor: CouleursJarvis.texteSecondaire,
                minimumSize: const Size(40, 40),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// État de la lecture, puis le pied de carte.
  List<Widget> _suite(EtatFichier etat, bool pret) {
    return [
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: switch (etat) {
            FichierEnLecture(:final etape, :final fraction) => _Lecture(
              key: const ValueKey('lecture'),
              etape: etape,
              fraction: fraction,
              surAnnuler: surAnnuler,
            ),
            FichierPret() => const _Pret(key: ValueKey('pret')),
            FichierNonLu() => Column(
              key: const ValueKey('nonlu'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BoutonPrincipalImport(
                  libelle: relire,
                  icone: Icons.refresh_rounded,
                  surAppui: surRelire,
                ),
              ],
            ),
          },
        ),
      ),
      const SizedBox(height: 14),
      Divider(height: 1, color: CouleursJarvis.trait.withValues(alpha: 0.5)),
      const SizedBox(height: 4),
      // Pied de carte : actions secondaires, discrètes, à parts égales
      // (les libellés passent à la ligne plutôt que de déborder).
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pret) ...[
              Expanded(
                child: _ActionCarte(
                  libelle: resume,
                  icone: Icons.forum_outlined,
                  couleur: CouleursJarvis.signal,
                  surAppui: surResume,
                ),
              ),
              VerticalDivider(
                width: 9,
                indent: 10,
                endIndent: 10,
                color: CouleursJarvis.trait.withValues(alpha: 0.5),
              ),
            ],
            Expanded(
              child: _ActionCarte(
                libelle: changer,
                icone: Icons.swap_horiz_rounded,
                couleur: CouleursJarvis.texteSecondaire,
                surAppui: etat is FichierEnLecture ? null : surChanger,
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

/// Action discrète du pied de carte.
class _ActionCarte extends StatelessWidget {
  const _ActionCarte({
    required this.libelle,
    required this.icone,
    required this.couleur,
    required this.surAppui,
  });

  final String libelle;
  final IconData icone;
  final Color couleur;
  final VoidCallback? surAppui;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: surAppui,
      icon: Icon(icone, size: 18),
      label: Text(libelle, textAlign: TextAlign.center),
      style: TextButton.styleFrom(
        foregroundColor: couleur,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// Action principale de l'import, hors de la carte, en bas de l'écran :
/// « Filtrer les messages ». Inactive tant que le filtrage n'existe pas
/// ([surFiltrer] null) ; violette dès qu'il sera branché.
class ActionFiltrer extends StatelessWidget {
  const ActionFiltrer({super.key, required this.surFiltrer});

  final VoidCallback? surFiltrer;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BoutonPrincipalImport(
          libelle: CarteExportChoisi.filtrer,
          icone: Icons.tune_rounded,
          surAppui: surFiltrer,
        ),
        if (surFiltrer == null) ...[
          const SizedBox(height: 6),
          const Text(
            CarteExportChoisi.filtrageAVenir,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ],
      ],
    );
  }
}

/// Lecture : anneau compact (progression réelle ou indéterminée), étape,
/// « Annuler ».
class _Lecture extends StatelessWidget {
  const _Lecture({
    super.key,
    required this.etape,
    required this.fraction,
    required this.surAnnuler,
  });

  final EtapeLecture etape;
  final double? fraction;
  final VoidCallback? surAnnuler;

  static Widget _anneau(double? valeur) => CircularProgressIndicator(
    value: valeur,
    strokeWidth: 2.6,
    strokeCap: StrokeCap.round,
    color: CouleursJarvis.signal,
    backgroundColor: CouleursJarvis.lavande.withValues(alpha: 0.6),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: CouleursJarvis.violetPoudre.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 26,
            child: switch (fraction) {
              // Taille inconnue : anneau indéterminé.
              null => _anneau(null),
              // Mesurée : l'anneau avance en douceur entre deux mesures.
              final f => TweenAnimationBuilder<double>(
                tween: Tween(end: f),
                duration: const Duration(milliseconds: 220),
                builder: (context, valeur, _) => _anneau(valeur),
              ),
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    CarteExportChoisi.lecture,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: CouleursJarvis.texte,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    etape.libelle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: surAnnuler,
            style: TextButton.styleFrom(
              foregroundColor: CouleursJarvis.texteSecondaire,
              minimumSize: const Size(0, 40),
            ),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }
}

/// Lecture réussie : « Conversation prête ».
class _Pret extends StatelessWidget {
  const _Pret({super.key});

  @override
  Widget build(BuildContext context) {
    const vert = Color(0xFF2E8B57);
    return Center(
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
          decoration: BoxDecoration(
            color: vert.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: vert.withValues(alpha: 0.2)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 20, color: vert),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  CarteExportChoisi.pret,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF256F47),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
