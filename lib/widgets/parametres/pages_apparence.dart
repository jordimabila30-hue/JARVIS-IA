import 'package:flutter/material.dart';

import '../../models/apparence/preferences_apparence.dart';
import '../../services/apparence/service_apparence.dart';
import '../../theme/motifs_jarvis.dart';
import '../../theme/styles_jarvis.dart';
import '../../theme/theme_jarvis.dart';
import '../apparence/frise_kuba.dart';
import '../fond_jarvis_anime.dart';
import 'elements_parametres.dart';
import 'pages_jarvis_touch.dart';

/// Paramètres › Général › Apparence : deux entrées, Thèmes (couleurs et
/// style) et Motifs (décoration du fond), deux préférences indépendantes.
class PageApparence extends StatelessWidget {
  const PageApparence({
    super.key,
    required this.apparence,
    required this.surThemes,
    required this.surMotifs,
  });

  final ServiceApparence apparence;
  final VoidCallback surThemes, surMotifs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: apparence,
      builder: (context, _) => CarteReglages(
        enfants: [
          LigneSousPage(
            icone: Icons.palette_outlined,
            titre: 'Thèmes',
            sousTitre: 'Personnaliser les couleurs et le style de JARVIS',
            statut: apparence.style.nom,
            surAppui: surThemes,
          ),
          LigneSousPage(
            icone: Icons.texture_rounded,
            titre: 'Motifs',
            sousTitre: 'Personnaliser l’arrière-plan de JARVIS',
            statut: apparence.motif.nom,
            surAppui: surMotifs,
          ),
        ],
      ),
    );
  }
}

/// Ligne « Revenir au précédent » : sa place est toujours réservée (rien ne
/// bouge sous le doigt pendant qu'on compare les styles) ; elle apparaît en
/// fondu dès que le choix diffère de celui trouvé à l'ouverture de la page.
class _Revenir extends StatelessWidget {
  const _Revenir({required this.visible, required this.surRevenir});

  final bool visible;
  final VoidCallback surRevenir;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 40,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !visible,
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 17,
                  color: CouleursJarvis.signal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Appliqué et enregistré',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: visible ? surRevenir : null,
                  icon: const Icon(Icons.undo_rounded, size: 17),
                  label: const Text('Revenir au précédent'),
                  style: TextButton.styleFrom(
                    foregroundColor: CouleursJarvis.signal,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      texte,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: CouleursJarvis.texteSecondaire,
      ),
    ),
  );
}

/// Grille responsive : 2 colonnes sur téléphone, 3 au-delà de 520 px.
class _Grille extends StatelessWidget {
  const _Grille({required this.nombre, required this.tuile});

  final int nombre;
  final Widget Function(int i, double largeur) tuile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const ecart = 12.0;
        final colonnes = c.maxWidth >= 520 ? 3 : 2;
        final largeur = (c.maxWidth - ecart * (colonnes - 1)) / colonnes;
        return Wrap(
          spacing: ecart,
          runSpacing: ecart,
          children: [
            for (var i = 0; i < nombre; i++)
              SizedBox(width: largeur, child: tuile(i, largeur)),
          ],
        );
      },
    );
  }
}

/// Contour et coche de l'élément choisi, en fondu.
class _Cadre extends StatelessWidget {
  const _Cadre({
    required this.choisi,
    required this.surChoix,
    required this.libelle,
    required this.child,
  });

  final bool choisi;
  final VoidCallback surChoix;
  final String libelle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: choisi,
      label: libelle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: CouleursJarvis.coque,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            width: choisi ? 2 : 1,
            color: choisi
                ? CouleursJarvis.signal
                : CouleursJarvis.trait.withValues(alpha: 0.8),
          ),
          boxShadow: choisi
              ? [
                  BoxShadow(
                    color: CouleursJarvis.signal.withValues(alpha: 0.16),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: surChoix,
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              children: [
                child,
                Positioned(
                  top: 8,
                  right: 8,
                  child: AnimatedScale(
                    scale: choisi ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: CouleursJarvis.signal,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: CouleursJarvis.coque,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: CouleursJarvis.surSignal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thèmes
// ---------------------------------------------------------------------------

/// Thèmes : mode d'affichage (Clair / Sombre / Système) et style visuel,
/// appliqués tout de suite, enregistrés ; « Revenir au précédent » rend le
/// choix trouvé à l'ouverture.
class PageThemes extends StatefulWidget {
  const PageThemes({super.key, required this.apparence});

  final ServiceApparence apparence;

  @override
  State<PageThemes> createState() => _PageThemesState();
}

class _PageThemesState extends State<PageThemes> {
  late final PreferencesApparence _initial = widget.apparence.preferences;

  @override
  Widget build(BuildContext context) {
    final a = widget.apparence;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final change = a.mode != _initial.mode || a.style != _initial.style;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Revenir(
              visible: change,
              surRevenir: () => a.restaurer(
                a.preferences.copyWith(
                  mode: _initial.mode,
                  style: _initial.style,
                ),
              ),
            ),
            const _Titre('MODE D’AFFICHAGE'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in ModeAffichage.values)
                  PastilleReglage(
                    libelle: m.libelle,
                    choisie: a.mode == m,
                    surChoix: () => a.choisirMode(m),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            NoteReglage(
              a.mode == ModeAffichage.systeme
                  ? 'Suit le réglage de l’appareil (actuellement : '
                        '${a.luminositeSysteme == Brightness.dark ? 'sombre' : 'clair'}).'
                  : 'Le mode s’applique à tous les styles.',
            ),
            const SizedBox(height: 26),
            const _Titre('STYLE VISUEL'),
            _Grille(
              nombre: StyleVisuel.values.length,
              tuile: (i, _) {
                final s = StyleVisuel.values[i];
                return _CadreStyle(
                  style: s,
                  palette: s.palette(a.luminosite),
                  choisi: a.style == s,
                  surChoix: () => a.choisirStyle(s),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _CadreStyle extends StatelessWidget {
  const _CadreStyle({
    required this.style,
    required this.palette,
    required this.choisi,
    required this.surChoix,
  });

  final StyleVisuel style;
  final PaletteJarvis palette;
  final bool choisi;
  final VoidCallback surChoix;

  @override
  Widget build(BuildContext context) {
    return _Cadre(
      choisi: choisi,
      surChoix: surChoix,
      libelle: 'Style ${style.nom}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: SizedBox(
                height: 104,
                child: ApercuStyle(palette: palette),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  style.nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: palette.identite.policeAffichage,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: CouleursJarvis.texte,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  style.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: CouleursJarvis.texteSecondaire,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aperçu d'un style : fond, frise, une carte de JARVIS, une bulle de
/// l'utilisateur et l'accent d'action, avec leurs vraies couleurs,
/// contours et ombres (sans dépendre de la palette affichée).
class ApercuStyle extends StatelessWidget {
  const ApercuStyle({super.key, required this.palette});

  final PaletteJarvis palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final id = p.identite;
    BoxDecoration bloc(List<Color> fond, Color? ombre, Color bord) =>
        BoxDecoration(
          gradient: LinearGradient(colors: fond),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: id.marquee ? bord : p.trait.withValues(alpha: 0.6),
            width: id.marquee ? 1.4 : 1,
          ),
          boxShadow: [
            if (ombre != null)
              BoxShadow(color: ombre, offset: const Offset(2.5, 2.5))
            else
              BoxShadow(
                color: p.ombre.withAlpha(0x14),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        );
    return DecoratedBox(
      decoration: BoxDecoration(gradient: degradeFond(p)),
      child: Stack(
        children: [
          if (id.frise case final frise?)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 6,
              child: CustomPaint(painter: PeintreFrise(frise, p.ivoire)),
            ),
          // Carte de JARVIS.
          Positioned(
            left: 10,
            top: 16,
            right: 34,
            height: 38,
            child: DecoratedBox(
              decoration: bloc(
                p.carteJarvis,
                id.ombreCarte,
                p.texte.withValues(alpha: 0.35),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Ligne(p.texte.withValues(alpha: 0.7), 0.8),
                    const SizedBox(height: 5),
                    _Ligne(p.texteSecondaire.withValues(alpha: 0.6), 0.55),
                  ],
                ),
              ),
            ),
          ),
          // Bulle de l'utilisateur.
          Positioned(
            right: 10,
            top: 62,
            width: 70,
            height: 22,
            child: DecoratedBox(
              decoration: bloc(p.bulleUtilisateur, id.ombreBulle, p.bordBulle),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: _Ligne(p.texte.withValues(alpha: 0.65), 1),
                ),
              ),
            ),
          ),
          // Accent d'action et couleurs secondaires.
          Positioned(
            left: 10,
            bottom: 10,
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 14,
                  decoration: BoxDecoration(
                    color: p.signal,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                const SizedBox(width: 5),
                for (final c in [p.violet, p.critique])
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne(this.couleur, this.part);

  final Color couleur;
  final double part;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: part,
    child: Container(
      height: 4,
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Motifs
// ---------------------------------------------------------------------------

/// Motifs : décoration du fond (indépendante du style), avec aperçu dans
/// les couleurs du style affiché, et intensité.
class PageMotifs extends StatefulWidget {
  const PageMotifs({super.key, required this.apparence});

  final ServiceApparence apparence;

  @override
  State<PageMotifs> createState() => _PageMotifsState();
}

class _PageMotifsState extends State<PageMotifs> {
  late final PreferencesApparence _initial = widget.apparence.preferences;

  @override
  Widget build(BuildContext context) {
    final a = widget.apparence;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final change =
            a.motif != _initial.motif || a.intensite != _initial.intensite;
        final palette = a.palette;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Revenir(
              visible: change,
              surRevenir: () => a.restaurer(
                a.preferences.copyWith(
                  motif: _initial.motif,
                  intensite: _initial.intensite,
                ),
              ),
            ),
            const _Titre('MOTIF DU FOND'),
            _Grille(
              nombre: MotifJarvis.values.length,
              tuile: (i, _) {
                final m = MotifJarvis.values[i];
                return _CadreMotif(
                  motif: m,
                  palette: palette,
                  intensite: a.intensite,
                  choisi: a.motif == m,
                  surChoix: () => a.choisirMotif(m),
                );
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: a.motif == MotifJarvis.aucun
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: CarteReglages(
                        enfants: [
                          CurseurReglage(
                            titre: 'Intensité du motif',
                            valeurAffichee: '${(a.intensite * 100).round()} %',
                            valeur: a.intensite,
                            min: 0,
                            max: 1,
                            divisions: 20,
                            icones: (
                              Icons.brightness_low_rounded,
                              Icons.brightness_high_rounded,
                            ),
                            surChangement: (v) =>
                                a.reglerIntensite(v, enregistrer: false),
                            surFin: (v) => a.reglerIntensite(v),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            const NoteReglage(
              'Le motif reste derrière les messages, très atténué : il ne '
              'gêne jamais la lecture. Il ne change pas les couleurs du thème.',
            ),
          ],
        );
      },
    );
  }
}

class _CadreMotif extends StatelessWidget {
  const _CadreMotif({
    required this.motif,
    required this.palette,
    required this.intensite,
    required this.choisi,
    required this.surChoix,
  });

  final MotifJarvis motif;
  final PaletteJarvis palette;
  final double intensite;
  final bool choisi;
  final VoidCallback surChoix;

  @override
  Widget build(BuildContext context) {
    return _Cadre(
      choisi: choisi,
      surChoix: surChoix,
      libelle: 'Motif ${motif.nom}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: SizedBox(
                height: 96,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PeintreApercuMotif(motif, palette, intensite),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  motif.nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: CouleursJarvis.texte,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  motif.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: CouleursJarvis.texteSecondaire,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aperçu d'un motif : le vrai fond de l'accueil, en réduit. L'intensité
/// est un peu relevée pour que le motif se voie dans une petite tuile.
class _PeintreApercuMotif extends CustomPainter {
  const _PeintreApercuMotif(this.motif, this.palette, this.intensite);

  final MotifJarvis motif;
  final PaletteJarvis palette;
  final double intensite;

  @override
  void paint(Canvas canvas, Size size) => peindreFondAccueil(
    canvas,
    size,
    palette: palette,
    motif: motif,
    intensite: motif == MotifJarvis.aurore
        ? intensite
        : (intensite * 1.6).clamp(0.0, 1.0),
    simplifie: true,
  );

  @override
  bool shouldRepaint(_PeintreApercuMotif ancien) =>
      ancien.motif != motif ||
      !identical(ancien.palette, palette) ||
      ancien.intensite != intensite;
}
