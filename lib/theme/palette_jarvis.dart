import 'package:flutter/material.dart';

/// Couleurs du fond de l'accueil (base du thème, sous le motif).
@immutable
class CouleursFond {
  const CouleursFond({
    required this.centre,
    required this.base,
    required this.bord,
    required this.voileLateral,
    required this.halo,
    required this.peripherie,
    required this.lumiere,
    required this.nappe,
    required this.nappeDouce,
    required this.courbe,
    required this.lueur,
    this.courbeMilieu,
  });

  /// Dégradé radial : centre, milieu, bords.
  final Color centre, base, bord;

  /// Voile sur les côtés (lavande pour JARVIS).
  final Color voileLateral;

  /// Halo autour des particules.
  final Color halo;

  /// Réchauffement en haut et en bas.
  final Color peripherie;

  /// Lumière centrale : 5 arrêts, du centre vers l'extérieur.
  final List<Color> lumiere;

  /// Motif « Aurore » : nappes diffuses (vive, douce), traits des courbes
  /// et des anneaux, et leur lueur.
  final Color nappe, nappeDouce, courbe, lueur;

  /// Milieu des courbes (null : [courbe]).
  final Color? courbeMilieu;
}

/// Personnalité graphique d'un style : ce qui va au-delà des couleurs
/// (contours marqués, ombres décalées pleines, frise, police des titres).
@immutable
class IdentiteVisuelle {
  const IdentiteVisuelle({
    this.policeAffichage = 'Exo2',
    this.frise,
    this.ombreBulle,
    this.ombreCarte,
    this.contour = 0,
  });

  /// Police des titres et de la salutation.
  final String policeAffichage;

  /// Frise kuba (losanges, dans cet ordre) en haut des cartes de JARVIS ;
  /// null : aucune.
  final List<Color>? frise;

  /// Ombre pleine décalée sous la bulle de l'utilisateur / les cartes de
  /// JARVIS (null : ombre douce d'origine).
  final Color? ombreBulle, ombreCarte;

  /// Épaisseur du contour marqué des bulles et cartes (0 : contour fin
  /// d'origine).
  final double contour;

  bool get marquee => contour > 0;

  static const jarvis = IdentiteVisuelle();
}

/// Palette complète d'un style dans un mode (clair ou sombre). Exposée
/// dans `ThemeData.extensions` ([PaletteJarvis.of]) ; le code existant la
/// lit par la façade `CouleursJarvis`, qui suit [PaletteJarvis.active].
@immutable
class PaletteJarvis extends ThemeExtension<PaletteJarvis> {
  const PaletteJarvis({
    required this.luminosite,
    required this.ivoire,
    required this.ivoirePrincipal,
    required this.creme,
    required this.beigeChaud,
    required this.sable,
    required this.violetPoudre,
    required this.lavande,
    required this.coque,
    required this.trait,
    required this.voile,
    required this.signal,
    required this.surSignal,
    required this.violet,
    required this.critique,
    required this.texte,
    required this.texteSecondaire,
    required this.heure,
    required this.erreur,
    required this.succes,
    required this.ombre,
    required this.bulleUtilisateur,
    required this.bordBulle,
    required this.carteJarvis,
    required this.panneauMenu,
    required this.champ,
    required this.signature,
    required this.fond,
    required this.motif,
    required this.accentsMotif,
    this.identite = IdentiteVisuelle.jarvis,
  });

  final Brightness luminosite;
  bool get sombre => luminosite == Brightness.dark;

  /// Fonds, du plus clair (centre) aux bords (sombres : l'inverse).
  final Color ivoire, ivoirePrincipal, creme, beigeChaud, sable;

  /// Teintes très diluées de l'accent (sélections, puces).
  final Color violetPoudre, lavande;

  /// Panneaux, traits fins, voile « verre » (blanc en clair).
  final Color coque, trait, voile;

  /// Accent d'action, contenu posé sur l'accent, accent secondaire,
  /// alerte (jauges au-delà du seuil).
  final Color signal, surSignal, violet, critique;

  final Color texte, texteSecondaire, heure;
  final Color erreur, succes;

  /// Base des ombres (toujours utilisée avec une faible opacité).
  final Color ombre;

  /// Bulle de l'utilisateur (dégradé 2 couleurs) et son bord.
  final List<Color> bulleUtilisateur;
  final Color bordBulle;

  /// Carte de JARVIS (dégradé), panneau du menu latéral (dégradé).
  final List<Color> carteJarvis, panneauMenu;

  /// Fond des champs : repos, survol, appui.
  final List<Color> champ;

  /// Point de la signature « • JARVIS ».
  final Color signature;

  final CouleursFond fond;

  /// Trait des motifs décoratifs (raphia) et leurs accents.
  final Color motif;
  final List<Color> accentsMotif;

  final IdentiteVisuelle identite;

  /// Palette suivie par la façade `CouleursJarvis` (code sans contexte :
  /// peintres, constantes d'origine). Changée par `ServiceApparence`
  /// seulement ; JARVIS clair par défaut (tests, JARVIS Touch).
  static PaletteJarvis active = jarvisClair;

  /// Palette du thème courant (celle de [active] hors application).
  static PaletteJarvis of(BuildContext context) =>
      Theme.of(context).extension<PaletteJarvis>() ?? active;

  @override
  PaletteJarvis copyWith() => this;

  /// Pas d'interpolation couleur par couleur : la transition entre deux
  /// styles est un fondu de l'écran entier (`TransitionApparence`).
  @override
  PaletteJarvis lerp(covariant PaletteJarvis? autre, double t) =>
      autre == null || t < 0.5 ? this : autre;

  // ---------------------------------------------------------------------
  // JARVIS original
  // ---------------------------------------------------------------------

  /// JARVIS original, clair : les valeurs d'origine, à l'identique.
  static const jarvisClair = PaletteJarvis(
    luminosite: Brightness.light,
    ivoire: Color(0xFFFAF8F2),
    ivoirePrincipal: Color(0xFFF8F4EC),
    creme: Color(0xFFF3EEE4),
    beigeChaud: Color(0xFFEFE7DC),
    sable: Color(0xFFEBE3D6),
    violetPoudre: Color(0xFFE8E1F2),
    lavande: Color(0xFFDDD5EF),
    coque: Color(0xFFFFFDF9),
    trait: Color(0xFFDCD3C4),
    voile: Color(0xFFFFFFFF),
    signal: Color(0xFF5559B8),
    surSignal: Color(0xFFFAF8F2),
    violet: Color(0xFF8C7AD2),
    critique: Color(0xFFD9822B),
    texte: Color(0xFF272932),
    texteSecondaire: Color(0xFF6F6A72),
    heure: Color(0xFF9A94AE),
    erreur: Color(0xFFB3261E),
    succes: Color(0xFF2E8B57),
    ombre: Color(0xFF3A3350),
    bulleUtilisateur: [Color(0xE8ECE8FB), Color(0xDDE2E7FA)],
    bordBulle: Color(0xBFFFFFFF),
    carteJarvis: [Color(0xF0FFFDF9), Color(0xF0F7F3FD)],
    panneauMenu: [Color(0xFFFBF9F4), Color(0xFFF6F2FA)],
    champ: [Color(0xFFF4EFE6), Color(0xFFEDE6DA), Color(0xFFE6DED0)],
    signature: Color(0xFF6E71C4),
    fond: CouleursFond(
      centre: Color(0xFFFFFCF6),
      base: Color(0xFFF8F4EC),
      bord: Color(0xFFF2E6D6),
      voileLateral: Color(0xFFD3C5F3),
      halo: Color(0xFFDACDF5),
      peripherie: Color(0xFFF4E6D3),
      lumiere: [
        Color(0xFFFFFDF7),
        Color(0xE6FFF9EE),
        Color(0x8CFFF4E4),
        Color(0x26FFF1E0),
        Color(0x00FFF1E0),
      ],
      nappe: Color(0xFFD3C5F3),
      nappeDouce: Color(0xFFE0D4F6),
      courbe: Color(0xFFFFFFFF),
      lueur: Color(0xFFC9B9F0),
      courbeMilieu: Color(0xFFF3EEFC),
    ),
    motif: Color(0xFF5559B8),
    accentsMotif: [Color(0xFF8C7AD2), Color(0xFF5559B8), Color(0xFFB7A2F6)],
  );

  /// JARVIS original, sombre : graphite profond, même bleu-violet signal
  /// (éclairci pour le contraste), lavande devenue lueur.
  static const jarvisSombre = PaletteJarvis(
    luminosite: Brightness.dark,
    ivoire: Color(0xFF14151B),
    ivoirePrincipal: Color(0xFF17181F),
    creme: Color(0xFF1B1C24),
    beigeChaud: Color(0xFF1E1F28),
    sable: Color(0xFF23242E),
    violetPoudre: Color(0xFF2A2842),
    lavande: Color(0xFF39345E),
    coque: Color(0xFF1F2029),
    trait: Color(0xFF353746),
    voile: Color(0xFF2A2B36),
    signal: Color(0xFF9EA2F5),
    surSignal: Color(0xFF14151B),
    violet: Color(0xFFB6A6F2),
    critique: Color(0xFFF0A257),
    texte: Color(0xFFECEAF2),
    texteSecondaire: Color(0xFFA6A2B2),
    heure: Color(0xFF8E89A3),
    erreur: Color(0xFFFF8A80),
    succes: Color(0xFF6FD39B),
    ombre: Color(0xFF000000),
    bulleUtilisateur: [Color(0xF02B2A47), Color(0xE8262742)],
    bordBulle: Color(0x33B6A6F2),
    carteJarvis: [Color(0xF01D1E27), Color(0xF0201F2D)],
    panneauMenu: [Color(0xFF191A21), Color(0xFF1D1C27)],
    champ: [Color(0xFF22232D), Color(0xFF282935), Color(0xFF2E2F3C)],
    signature: Color(0xFF9EA2F5),
    fond: CouleursFond(
      centre: Color(0xFF1D1E28),
      base: Color(0xFF15161D),
      bord: Color(0xFF0E0F14),
      voileLateral: Color(0xFF3A3070),
      halo: Color(0xFF332B66),
      peripherie: Color(0xFF0B0B10),
      lumiere: [
        Color(0x4D6F66C8),
        Color(0x33605AB5),
        Color(0x1A4F4A9A),
        Color(0x084F4A9A),
        Color(0x004F4A9A),
      ],
      nappe: Color(0xFF3A3070),
      nappeDouce: Color(0xFF2E2A5A),
      courbe: Color(0xFFD9D2FF),
      lueur: Color(0xFF6E5FD0),
    ),
    motif: Color(0xFFB6A6F2),
    accentsMotif: [Color(0xFFB6A6F2), Color(0xFF9EA2F5), Color(0xFFD0C2FF)],
  );

  // ---------------------------------------------------------------------
  // Styles importés : construits depuis les jetons de l'application source
  // (--bg, --deep, --panel, --line, --txt, --dim, --acc, --acc2, --acc3,
  // --raf, --onacc, --user) ; le reste en est dérivé.
  // ---------------------------------------------------------------------

  factory PaletteJarvis.depuisJetons({
    required Brightness luminosite,
    required Color bg,
    required Color deep,
    required Color panel,
    required Color line,
    required Color txt,
    required Color dim,
    required Color acc,
    required Color acc2,
    required Color acc3,
    required Color raf,
    required Color onacc,
    required Color user,
    required List<Color> frise,
    required Color ombreBulle,
    required Color ombreCarte,
    Color? critique,
  }) {
    final sombre = luminosite == Brightness.dark;
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    Color vers(Color c, Color cible, double t) => mix(c, cible, t);
    const blanc = Color(0xFFFFFFFF);
    const noir = Color(0xFF000000);
    final clarte = sombre ? blanc : noir;
    return PaletteJarvis(
      luminosite: luminosite,
      ivoire: bg,
      ivoirePrincipal: bg,
      creme: deep,
      beigeChaud: deep,
      sable: mix(deep, line, 0.3),
      violetPoudre: mix(bg, acc, sombre ? 0.16 : 0.12),
      lavande: mix(bg, acc, sombre ? 0.3 : 0.24),
      coque: panel,
      trait: line,
      voile: sombre ? panel : blanc,
      signal: acc,
      surSignal: onacc,
      violet: acc2,
      critique: critique ?? acc3,
      texte: txt,
      texteSecondaire: dim,
      heure: dim,
      erreur: sombre ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
      succes: sombre ? const Color(0xFF6FD39B) : const Color(0xFF2E7D4F),
      ombre: sombre ? noir : mix(txt, noir, 0.2),
      bulleUtilisateur: [user, user],
      // Source : contour 2 px « color-mix(txt 55 %) ».
      bordBulle: txt.withValues(alpha: 0.55),
      carteJarvis: [deep, deep],
      panneauMenu: [bg, deep],
      champ: [
        vers(panel, clarte, 0.03),
        vers(panel, clarte, 0.07),
        vers(panel, clarte, 0.11),
      ],
      signature: acc,
      fond: CouleursFond(
        centre: sombre ? mix(bg, acc, 0.07) : mix(bg, blanc, 0.45),
        base: bg,
        bord: sombre ? mix(bg, noir, 0.3) : deep,
        voileLateral: sombre ? mix(bg, acc2, 0.3) : mix(bg, acc2, 0.2),
        halo: mix(bg, acc, sombre ? 0.22 : 0.18),
        peripherie: sombre ? mix(bg, noir, 0.45) : deep,
        // Source : « --glow » (accent à 20-22 %).
        lumiere: sombre
            ? [
                acc.withValues(alpha: 0.2),
                acc.withValues(alpha: 0.12),
                acc.withValues(alpha: 0.06),
                acc.withValues(alpha: 0.02),
                acc.withValues(alpha: 0),
              ]
            : [
                blanc.withValues(alpha: 0.9),
                blanc.withValues(alpha: 0.7),
                blanc.withValues(alpha: 0.35),
                blanc.withValues(alpha: 0.1),
                blanc.withValues(alpha: 0),
              ],
        nappe: mix(bg, acc2, sombre ? 0.35 : 0.3),
        nappeDouce: mix(bg, acc, sombre ? 0.25 : 0.2),
        courbe: sombre ? raf : blanc,
        lueur: sombre ? acc : mix(bg, acc, 0.45),
      ),
      motif: raf,
      // Ordre de la frise source : acc3, acc, acc2.
      accentsMotif: frise,
      identite: IdentiteVisuelle(
        policeAffichage: 'Baloo2',
        frise: frise,
        ombreBulle: ombreBulle,
        ombreCarte: ombreCarte,
        contour: 2,
      ),
    );
  }
}
