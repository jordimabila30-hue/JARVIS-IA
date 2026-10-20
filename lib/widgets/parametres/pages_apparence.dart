import 'package:flutter/gestures.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/apparence/fond_photo.dart';
import '../../models/apparence/preferences_apparence.dart';
import '../../pages/editeur_fond_page.dart';
import '../../services/apparence/depot_fonds_photo.dart';
import '../../services/apparence/service_fonds.dart';
import '../../services/apparence/service_apparence.dart';
import '../../theme/motifs_jarvis.dart';
import '../../theme/styles_jarvis.dart';
import '../../theme/theme_jarvis.dart';
import '../apparence/frise_kuba.dart';
import '../fond_jarvis_anime.dart';
import 'elements_parametres.dart';

/// Paramètres › Apparence, sur une seule page : mode d'affichage (Clair /
/// Sombre / Système), styles visuels puis motifs du fond, chacun dans son
/// carrousel horizontal (sélection directe, accrochage aux cartes), et
/// l'intensité du motif. Tout s'applique tout de suite et s'enregistre ;
/// « Revenir » rend le choix trouvé à l'ouverture de la page.
class PageApparence extends StatefulWidget {
  const PageApparence({super.key, required this.apparence});

  final ServiceApparence apparence;

  @override
  State<PageApparence> createState() => _PageApparenceState();
}

class _PageApparenceState extends State<PageApparence> {
  late final PreferencesApparence _initial = widget.apparence.preferences;

  /// Photos (null hors application : la carte « Ma galerie » est absente).
  ServiceFonds? _fonds;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fonds != null) return;
    _fonds = ServiceFonds.of(context, ecouter: false);
    // « Revenir » peut rendre la photo d'avant : elle n'est pas nettoyée
    // tant que la page est ouverte.
    if (_initial.photo case final p?) _fonds?.proteger(p.id);
  }

  @override
  void dispose() {
    if (_initial.photo case final p?) _fonds?.abandonner(p.id);
    super.dispose();
  }

  /// « Ma galerie » : choisir une photo (aucune encore), la remettre comme
  /// fond (inactive), ou l'ajuster (déjà le fond).
  Future<void> _galerie() async {
    final a = widget.apparence;
    if (a.photo == null) return _nouvellePhoto();
    if (!a.photoActive) return a.activerPhoto();
    return _ajusterPhoto();
  }

  Future<void> _nouvellePhoto() async {
    final fonds = _fonds;
    if (fonds == null) return;
    final octets = await choisirPhotoFond();
    if (octets == null || !mounted) return;
    final photo = await ouvrirEditeurFond(
      context,
      fonds: fonds,
      octets: octets,
    );
    if (photo != null) await fonds.definirGeneral(photo);
  }

  Future<void> _ajusterPhoto() async {
    final fonds = _fonds;
    final actuelle = widget.apparence.photo;
    if (fonds == null || actuelle == null) return;
    final photo = await ouvrirEditeurFond(
      context,
      fonds: fonds,
      existante: actuelle,
    );
    if (photo != null) await fonds.definirGeneral(photo);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.apparence;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final styleChange =
            a.mode != _initial.mode || a.style != _initial.style;
        final motifChange =
            a.motif != _initial.motif ||
            a.intensite != _initial.intensite ||
            a.photo != _initial.photo ||
            a.photoActive != (_initial.photoActive && _initial.photo != null);
        final palette = a.palette;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Titre('Mode d’affichage', revenable: false),
            _Segments(
              valeurs: ModeAffichage.values,
              choisie: a.mode,
              libelle: (m) => m.libelle,
              surChoix: a.choisirMode,
            ),
            const SizedBox(height: 28),
            _Titre(
              'Styles visuels',
              revenir: styleChange
                  ? () => a.restaurer(
                      a.preferences.copyWith(
                        mode: _initial.mode,
                        style: _initial.style,
                      ),
                    )
                  : null,
            ),
            _Carrousel(
              cle: 'styles',
              nombre: StyleVisuel.values.length,
              choisie: StyleVisuel.values.indexOf(a.style),
              carte: (i) {
                final s = StyleVisuel.values[i];
                return _CarteChoix(
                  nom: s.nom,
                  police: s.palette(a.luminosite).identite.policeAffichage,
                  choisie: a.style == s,
                  surChoix: () => a.choisirStyle(s),
                  // Mini-interface dessinée pour 220 × 112, agrandie
                  // d'un bloc pour remplir la carte.
                  apercu: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: 220,
                      height: 112,
                      child: ApercuStyle(palette: s.palette(a.luminosite)),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 26),
            _Titre(
              'Motifs du fond',
              revenir: motifChange
                  ? () => a.restaurer(
                      a.preferences.copyWith(
                        motif: _initial.motif,
                        intensite: _initial.intensite,
                        photo: _initial.photo,
                        photoActive: _initial.photoActive,
                      ),
                    )
                  : null,
            ),
            CarrouselFonds(
              cle: 'motifs',
              palette: palette,
              intensite: a.intensite,
              fond: a.fondGeneral,
              photo: a.photo,
              depot: _fonds?.depot,
              surMotif: a.choisirMotif,
              surGalerie: _fonds == null ? null : _galerie,
            ),
            // Sous les motifs, sans autre page : l'intensité d'un motif, ou
            // pour la photo « Ajuster » et « Changer » (l'intensité ne
            // concerne que les motifs).
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: a.photoActive
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _ActionsPhoto(
                        surAjuster: _ajusterPhoto,
                        surChanger: _nouvellePhoto,
                      ),
                    )
                  : a.motif == MotifJarvis.aucun
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: CurseurReglage(
                        titre: 'Intensité',
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
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Titre de section ; [revenir] (choix modifié sur cette page) fait
/// apparaître « Revenir » à droite, sans rien décaler.
class _Titre extends StatelessWidget {
  const _Titre(this.texte, {this.revenir, this.revenable = true});

  final String texte;
  final VoidCallback? revenir;

  /// Faux : aucun « Revenir » pour ce titre (mode d'affichage).
  final bool revenable;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                texte,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                  color: CouleursJarvis.texte,
                ),
              ),
            ),
          ),
          if (revenable)
            AnimatedOpacity(
              opacity: revenir == null ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: revenir == null,
                child: TextButton.icon(
                  onPressed: revenir,
                  icon: const Icon(Icons.undo_rounded, size: 17),
                  label: const Text('Revenir'),
                  style: TextButton.styleFrom(
                    foregroundColor: CouleursJarvis.signal,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sélecteur segmenté : segments de même largeur, le choisi marqué en
/// fondu (fond et contour de l'accent, coche).
class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.valeurs,
    required this.choisie,
    required this.libelle,
    required this.surChoix,
  });

  final List<T> valeurs;
  final T choisie;
  final String Function(T) libelle;
  final ValueChanged<T> surChoix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CouleursJarvis.coque.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CouleursJarvis.trait.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          for (final v in valeurs)
            Expanded(
              child: _Segment(
                libelle: libelle(v),
                choisi: v == choisie,
                surChoix: () => surChoix(v),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.libelle,
    required this.choisi,
    required this.surChoix,
  });

  final String libelle;
  final bool choisi;
  final VoidCallback surChoix;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: choisi,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: choisi
              ? CouleursJarvis.signal.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: choisi
                ? CouleursJarvis.signal.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: surChoix,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (choisi) ...[
                        Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: CouleursJarvis.signal,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          libelle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: choisi
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: choisi
                                ? CouleursJarvis.signal
                                : CouleursJarvis.texte,
                          ),
                        ),
                      ),
                    ],
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

/// Carrousel horizontal : sur téléphone une grande carte entière et le
/// début de la suivante (on devine le glissement) ; sur grand écran autant
/// de cartes que la largeur le permet. Accrochage aux cartes, glissement au
/// doigt, à la souris et au pavé tactile ; le défilement vertical de la
/// page n'est pas gêné (axes différents). Il se place sur la carte choisie
/// à l'ouverture et la suit si le choix change ailleurs.
class _Carrousel extends StatefulWidget {
  const _Carrousel({
    required this.cle,
    required this.nombre,
    required this.choisie,
    required this.carte,
  });

  final String cle;
  final int nombre;
  final int choisie;
  final Widget Function(int i) carte;

  /// Écart entre deux cartes.
  static const ecart = 12.0;

  @override
  State<_Carrousel> createState() => _CarrouselState();
}

class _CarrouselState extends State<_Carrousel> {
  PageController? _controle;
  double _fraction = 0;

  /// Première carte entièrement visible, suivie pour les flèches.
  int _page = 0;

  @override
  void didUpdateWidget(_Carrousel ancien) {
    super.didUpdateWidget(ancien);
    final c = _controle;
    if (widget.choisie != ancien.choisie && c != null && c.hasClients) {
      // Carte touchée à moitié visible, ou choix fait ailleurs
      // (« Revenir ») : on montre la carte choisie en entier.
      final page = c.page ?? 0;
      final visibles = (1 / _fraction).floor();
      if (widget.choisie < page.floor() ||
          widget.choisie >= page.floor() + visibles) {
        _aller(widget.choisie);
      }
    }
  }

  @override
  void dispose() {
    _controle?.dispose();
    super.dispose();
  }

  void _surDefilement() {
    final p = (_controle?.page ?? 0).round();
    if (p != _page && mounted) setState(() => _page = p);
  }

  void _aller(int page) => _controle?.animateToPage(
    page.clamp(0, widget.nombre - 1),
    duration: const Duration(milliseconds: 380),
    curve: Curves.easeOutCubic,
  );

  PageController _pour(double fraction) {
    final ancien = _controle;
    if (ancien != null && (fraction - _fraction).abs() < 0.001) return ancien;
    final page = ancien != null && ancien.hasClients
        ? (ancien.page ?? widget.choisie.toDouble()).round()
        : widget.choisie;
    ancien?.dispose();
    _fraction = fraction;
    _page = page;
    return _controle = PageController(
      viewportFraction: fraction,
      initialPage: page,
    )..addListener(_surDefilement);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final largeur = c.maxWidth;
        final telephone = largeur < 600;
        // Téléphone : une carte principale (80 %) ; plus large : autant de
        // cartes d'environ 250 px que possible. Toujours un tiers de la
        // suivante visible : on devine qu'il y a de quoi glisser.
        final entieres = telephone ? 1 : (largeur / 250).floor().clamp(1, 6);
        final carte = telephone
            ? largeur * 0.8
            : (largeur - _Carrousel.ecart * entieres) / (entieres + 0.35);
        final pas = carte + _Carrousel.ecart;
        final controle = _pour((pas / largeur).clamp(0.1, 1.0));
        final apercu = (carte * 0.5).clamp(118.0, 168.0);
        final visibles = (1 / _fraction).floor();
        final avant = _page > 0;
        final apres = _page + visibles < widget.nombre;
        return SizedBox(
          height: apercu + 42,
          child: Stack(
            children: [
              ScrollConfiguration(
                // Souris et pavé tactile glissent aussi (Web, Windows).
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: PointerDeviceKind.values.toSet(),
                  scrollbars: false,
                ),
                child: PageView.builder(
                  key: PageStorageKey('carrousel-${widget.cle}'),
                  controller: controle,
                  padEnds: false,
                  itemCount: widget.nombre,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(right: _Carrousel.ecart),
                    child: _HauteurApercu(
                      hauteur: apercu,
                      child: widget.carte(i),
                    ),
                  ),
                ),
              ),
              // Grand écran (souris, clavier) : flèches, seulement du côté
              // où il reste des cartes.
              if (!telephone) ...[
                _Fleche(
                  visible: avant,
                  gauche: true,
                  hauteur: apercu,
                  surAppui: () => _aller(_page - visibles),
                ),
                _Fleche(
                  visible: apres,
                  gauche: false,
                  hauteur: apercu,
                  surAppui: () => _aller(_page + visibles),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Flèche ronde d'un carrousel (grand écran), centrée sur les aperçus.
class _Fleche extends StatelessWidget {
  const _Fleche({
    required this.visible,
    required this.gauche,
    required this.hauteur,
    required this.surAppui,
  });

  final bool visible;
  final bool gauche;
  final double hauteur;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: gauche ? 6 : null,
      right: gauche ? null : 6,
      top: hauteur / 2 - 20,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(
          ignoring: !visible,
          child: IconButton.filledTonal(
            tooltip: gauche ? 'Précédents' : 'Suivants',
            onPressed: surAppui,
            icon: Icon(
              gauche ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            ),
            style: IconButton.styleFrom(
              backgroundColor: CouleursJarvis.coque.withValues(alpha: 0.92),
              foregroundColor: CouleursJarvis.texte,
              minimumSize: const Size(40, 40),
              side: BorderSide(color: CouleursJarvis.trait),
            ),
          ),
        ),
      ),
    );
  }
}

/// Transmet la hauteur des aperçus aux cartes du carrousel.
class _HauteurApercu extends InheritedWidget {
  const _HauteurApercu({required this.hauteur, required super.child});

  final double hauteur;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HauteurApercu>()?.hauteur ??
      140;

  @override
  bool updateShouldNotify(_HauteurApercu ancien) => ancien.hauteur != hauteur;
}

/// Carte d'un carrousel : grand aperçu, puis le nom seul. Choisie :
/// contour de l'accent et coche, en fondu.
class _CarteChoix extends StatelessWidget {
  const _CarteChoix({
    required this.nom,
    required this.choisie,
    required this.surChoix,
    required this.apercu,
    this.police,
  });

  final String nom;
  final bool choisie;
  final VoidCallback surChoix;
  final Widget apercu;

  /// Police du nom (celle du style présenté).
  final String? police;

  @override
  Widget build(BuildContext context) {
    final hauteur = _HauteurApercu.of(context);
    return Semantics(
      button: true,
      selected: choisie,
      label: nom,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: surChoix,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                height: hauteur,
                padding: EdgeInsets.all(choisie ? 3 : 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    width: choisie ? 2 : 1,
                    color: choisie
                        ? CouleursJarvis.signal
                        : CouleursJarvis.trait.withValues(alpha: 0.8),
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(choisie ? 13 : 17),
                      child: RepaintBoundary(child: apercu),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: AnimatedScale(
                        scale: choisie ? 1 : 0,
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
              const SizedBox(height: 9),
              Text(
                nom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: police,
                  fontSize: 14,
                  fontWeight: choisie ? FontWeight.w700 : FontWeight.w500,
                  color: choisie ? CouleursJarvis.signal : CouleursJarvis.texte,
                ),
              ),
            ],
          ),
        ),
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

/// Aperçu d’un motif : le vrai fond de l’accueil, en réduit. L’intensité
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

/// Carrousel des fonds : tous les motifs, puis « Ma galerie » (photo
/// personnelle). Sert à l'Apparence (fond général) et au fond d'une
/// conversation. [fond] : fond choisi (carte marquée) ; [photo] : photo de
/// la galerie, montrée en miniature ; [surGalerie] null : pas de carte
/// « Ma galerie ».
class CarrouselFonds extends StatelessWidget {
  const CarrouselFonds({
    super.key,
    required this.cle,
    required this.palette,
    required this.intensite,
    required this.fond,
    required this.surMotif,
    this.photo,
    this.depot,
    this.surGalerie,
  });

  final String cle;
  final PaletteJarvis palette;
  final double intensite;
  final FondChoisi? fond;
  final FondPhoto? photo;
  final DepotFondsPhoto? depot;
  final ValueChanged<MotifJarvis> surMotif;
  final VoidCallback? surGalerie;

  static const nomGalerie = 'Ma galerie';

  @override
  Widget build(BuildContext context) {
    final motifs = MotifJarvis.values;
    final galerie = surGalerie != null;
    final f = fond;
    final choisie = switch (f) {
      FondPhotoChoisi() => motifs.length,
      FondMotif(:final motif) => motifs.indexOf(motif),
      null => -1,
    };
    return _Carrousel(
      cle: cle,
      nombre: motifs.length + (galerie ? 1 : 0),
      choisie: choisie.clamp(0, motifs.length),
      carte: (i) {
        if (i == motifs.length) {
          return _CarteChoix(
            nom: nomGalerie,
            choisie: f is FondPhotoChoisi,
            surChoix: surGalerie!,
            apercu: _ApercuGalerie(
              photo: f is FondPhotoChoisi ? f.photo : photo,
              depot: depot,
            ),
          );
        }
        final m = motifs[i];
        return _CarteChoix(
          nom: m.nom,
          choisie: f is FondMotif && f.motif == m,
          surChoix: () => surMotif(m),
          apercu: CustomPaint(
            painter: _PeintreApercuMotif(m, palette, intensite),
          ),
        );
      },
    );
  }
}

/// Aperçu de « Ma galerie » : miniature de la photo (décodée petite), ou
/// une invitation à en choisir une.
class _ApercuGalerie extends StatefulWidget {
  const _ApercuGalerie({required this.photo, required this.depot});

  final FondPhoto? photo;
  final DepotFondsPhoto? depot;

  @override
  State<_ApercuGalerie> createState() => _ApercuGalerieState();
}

class _ApercuGalerieState extends State<_ApercuGalerie> {
  Future<Uint8List?>? _octets;
  String? _id;

  void _charger() {
    final id = widget.photo?.id;
    if (id == _id) return;
    _id = id;
    _octets = id == null ? null : widget.depot?.lire(id);
  }

  @override
  Widget build(BuildContext context) {
    _charger();
    final vide = Container(
      color: CouleursJarvis.creme,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 30,
            color: CouleursJarvis.signal,
          ),
          const SizedBox(height: 8),
          Text(
            'Choisir une photo',
            style: TextStyle(
              fontSize: 13,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ],
      ),
    );
    final futur = _octets;
    if (futur == null) return vide;
    final r = widget.photo!.reglages;
    return FutureBuilder<Uint8List?>(
      future: futur,
      builder: (context, s) {
        final octets = s.data;
        if (octets == null) {
          return s.connectionState == ConnectionState.done
              ? vide
              : ColoredBox(color: CouleursJarvis.creme);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: CouleursJarvis.ivoire),
            Opacity(
              opacity: r.visibilite,
              child: Image.memory(
                octets,
                fit: BoxFit.cover,
                cacheWidth: 480,
                gaplessPlayback: true,
              ),
            ),
            ColoredBox(
              color: Color.fromRGBO(0, 0, 0, r.assombrissement * r.visibilite),
            ),
          ],
        );
      },
    );
  }
}

/// Photo active : « Ajuster la photo » (éditeur) et « Changer de photo ».
class _ActionsPhoto extends StatelessWidget {
  const _ActionsPhoto({required this.surAjuster, required this.surChanger});

  final VoidCallback surAjuster;
  final VoidCallback surChanger;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: CouleursJarvis.signal,
      minimumSize: const Size(0, 44),
    );
    return Wrap(
      spacing: 8,
      children: [
        TextButton.icon(
          onPressed: surAjuster,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Ajuster la photo'),
          style: style,
        ),
        TextButton.icon(
          onPressed: surChanger,
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: const Text('Changer de photo'),
          style: style,
        ),
      ],
    );
  }
}
