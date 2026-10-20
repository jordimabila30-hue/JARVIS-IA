import 'package:flutter/material.dart';

import '../services/apparence/service_apparence.dart';
import 'motifs_jarvis.dart';
import 'palette_jarvis.dart';

export 'palette_jarvis.dart';

/// Couleurs de JARVIS, lues dans la palette affichée
/// ([PaletteJarvis.active], changée par `ServiceApparence`). Les noms
/// d'origine sont gardés : en JARVIS original clair, les valeurs sont
/// exactement celles d'avant. Dans un widget, `PaletteJarvis.of(context)`
/// donne la même palette.
class CouleursJarvis {
  CouleursJarvis._();

  static PaletteJarvis get _p => PaletteJarvis.active;

  /// Fond : ivoire clair au centre, beige chaud vers les bords.
  static Color get ivoire => _p.ivoire;
  static Color get ivoirePrincipal => _p.ivoirePrincipal;
  static Color get creme => _p.creme;
  static Color get beigeChaud => _p.beigeChaud;
  static Color get sable => _p.sable;

  /// Nuances lavande, toujours très diluées dans le fond.
  static Color get violetPoudre => _p.violetPoudre;
  static Color get lavande => _p.lavande;

  /// Panneaux (verre laiteux) et traits fins.
  static Color get coque => _p.coque;
  static Color get trait => _p.trait;

  /// Voile « verre » (blanc en clair, panneau en sombre).
  static Color get voile => _p.voile;

  /// Bleu-violet signature, légèrement désaturé (premium, pas criard).
  static Color get signal => _p.signal;

  /// Texte et icônes posés sur [signal].
  static Color get surSignal => _p.surSignal;
  static Color get violet => _p.violet;

  /// Orange chaud des jauges d'utilisation au-delà du seuil critique.
  static Color get critique => _p.critique;

  static Color get texte => _p.texte;

  /// Texte secondaire : gris chaud, contraste ≈ 4,6:1 sur l'ivoire.
  static Color get texteSecondaire => _p.texteSecondaire;

  static Color get erreur => _p.erreur;
  static Color get succes => _p.succes;

  /// Base des ombres (avec une faible opacité).
  static Color get ombre => _p.ombre;

  /// Dégradés de la bulle de l'utilisateur et du menu latéral ; fonds des
  /// champs (repos, survol, appui).
  static List<Color> get bulleUtilisateur => _p.bulleUtilisateur;
  static List<Color> get panneauMenu => _p.panneauMenu;
  static List<Color> get champ => _p.champ;

  /// Ivoire fixe, pour le contenu des surfaces toujours sombres (capsule
  /// vocale) : ne suit pas le thème.
  static const ivoireFixe = Color(0xFFFAF8F2);

  /// Couleur d'origine pensée pour un fond clair (rouge d'erreur, vert de
  /// réussite, couleurs d'auteurs…) : inchangée en clair, éclaircie en
  /// sombre pour rester lisible.
  static Color lisible(Color clair) =>
      _p.sombre ? Color.lerp(clair, const Color(0xFFFFFFFF), 0.38)! : clair;
}

/// Police d'affichage (salutation, titres) du style affiché : Exo 2 pour
/// JARVIS, Baloo 2 pour les styles importés. Le texte courant reste en
/// police système, plus lisible en petite taille.
String get policeAffichage => PaletteJarvis.active.identite.policeAffichage;

/// Dégradé de fond de JARVIS : doux, chaud, jamais blanc pur.
LinearGradient get degradeFondJarvis => degradeFond(PaletteJarvis.active);

LinearGradient degradeFond(PaletteJarvis p) => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [p.ivoire, p.creme, p.sable],
  stops: const [0, 0.62, 1],
);

ThemeData themeJarvis([PaletteJarvis? palette]) {
  final p = palette ?? PaletteJarvis.active;
  final schema = p.sombre
      ? ColorScheme.dark(
          primary: p.signal,
          onPrimary: p.surSignal,
          secondary: p.violet,
          surface: p.coque,
          onSurface: p.texte,
          outline: p.trait,
          error: p.erreur,
          inverseSurface: p.texte,
          onInverseSurface: p.ivoire,
        )
      : ColorScheme.light(
          primary: p.signal,
          onPrimary: p.surSignal,
          secondary: p.violet,
          surface: p.coque,
          onSurface: p.texte,
          outline: p.trait,
        );
  final police = p.identite.policeAffichage;
  return ThemeData(
    brightness: p.luminosite,
    colorScheme: schema,
    scaffoldBackgroundColor: p.ivoire,
    extensions: [p],
    textTheme: TextTheme(
      displaySmall: TextStyle(
        fontFamily: police,
        fontSize: 40,
        fontWeight: FontWeight.w300,
        height: 1.1,
        color: p.texte,
      ),
      titleMedium: TextStyle(
        fontFamily: police,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: p.texte,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: p.texte),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: p.texteSecondaire,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.texte,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(color: p.ivoire, fontSize: 12),
    ),
  );
}

/// Fond de page de JARVIS : centre légèrement plus clair, bords un peu
/// plus chauds, puis le motif choisi (Paramètres › Général › Apparence ›
/// Motifs ; « Aurore » appartient au fond de l'accueil). Écarts de teinte
/// très faibles et dégradés larges : pas de contraste agressif.
class FondJarvis extends StatelessWidget {
  const FondJarvis({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final apparence = ServiceApparence.of(context);
    final motif = apparence?.motif ?? MotifJarvis.aurore;
    Widget contenu = child;
    if (motif != MotifJarvis.aucun && motif != MotifJarvis.aurore) {
      contenu = CustomPaint(
        isComplex: true,
        painter: PeintreMotif(motif, p, apparence!.intensite),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(gradient: degradeFond(p)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.15),
            radius: 1.25,
            colors: p.sombre
                ? [
                    p.fond.centre.withValues(alpha: 0.6),
                    p.fond.centre.withValues(alpha: 0),
                    p.fond.bord.withValues(alpha: 0.4),
                  ]
                : const [
                    Color(0x80FFFDF8),
                    Color(0x00FFFDF8),
                    Color(0x14C9B79C),
                  ],
            stops: const [0, 0.6, 1],
          ),
        ),
        child: contenu,
      ),
    );
  }
}

/// Peint un motif géométrique (registre `MotifJarvis`) sur toute la zone.
class PeintreMotif extends CustomPainter {
  const PeintreMotif(this.motif, this.palette, this.intensite);

  final MotifJarvis motif;
  final PaletteJarvis palette;
  final double intensite;

  @override
  void paint(Canvas canvas, Size size) => dessinerMotifGeometrique(
    canvas,
    Offset.zero & size,
    motif,
    palette,
    intensite,
  );

  @override
  bool shouldRepaint(PeintreMotif ancien) =>
      ancien.motif != motif ||
      !identical(ancien.palette, palette) ||
      ancien.intensite != intensite;
}
