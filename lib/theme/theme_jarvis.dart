import 'package:flutter/material.dart';

/// Palette de JARVIS : fond ivoire chaud nuancé de lavande, encre
/// graphite, bleu-violet « signal » pour ce qui attend une action.
class CouleursJarvis {
  CouleursJarvis._();

  /// Fond : ivoire clair au centre, beige chaud vers les bords.
  static const ivoire = Color(0xFFFAF8F2);
  static const ivoirePrincipal = Color(0xFFF8F4EC);
  static const creme = Color(0xFFF3EEE4);
  static const beigeChaud = Color(0xFFEFE7DC);
  static const sable = Color(0xFFEBE3D6);

  /// Nuances lavande, toujours très diluées dans le fond.
  static const violetPoudre = Color(0xFFE8E1F2);
  static const lavande = Color(0xFFDDD5EF);

  /// Panneaux (verre laiteux) et traits fins.
  static const coque = Color(0xFFFFFDF9);
  static const trait = Color(0xFFDCD3C4);

  /// Bleu-violet signature, légèrement désaturé (premium, pas criard).
  static const signal = Color(0xFF5559B8);
  static const violet = Color(0xFF8C7AD2);

  /// Orange chaud des jauges d'utilisation au-delà du seuil critique.
  static const critique = Color(0xFFD9822B);

  static const texte = Color(0xFF272932);

  /// Texte secondaire : gris chaud, contraste ≈ 4,6:1 sur l'ivoire.
  static const texteSecondaire = Color(0xFF6F6A72);
}

/// Police d'affichage (salutation, titres). Le texte courant reste en
/// police système, plus lisible en petite taille.
const policeAffichage = 'Exo2';

/// Dégradé de fond de JARVIS : doux, chaud, jamais blanc pur.
const degradeFondJarvis = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [CouleursJarvis.ivoire, CouleursJarvis.creme, CouleursJarvis.sable],
  stops: [0, 0.62, 1],
);

ThemeData themeJarvis() {
  const schema = ColorScheme.light(
    primary: CouleursJarvis.signal,
    onPrimary: CouleursJarvis.ivoire,
    secondary: CouleursJarvis.violet,
    surface: CouleursJarvis.coque,
    onSurface: CouleursJarvis.texte,
    outline: CouleursJarvis.trait,
  );
  return ThemeData(
    colorScheme: schema,
    scaffoldBackgroundColor: CouleursJarvis.ivoire,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontFamily: policeAffichage,
        fontSize: 40,
        fontWeight: FontWeight.w300,
        height: 1.1,
        color: CouleursJarvis.texte,
      ),
      titleMedium: TextStyle(
        fontFamily: policeAffichage,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: CouleursJarvis.texte,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: CouleursJarvis.texte),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: CouleursJarvis.texteSecondaire,
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: CouleursJarvis.texte,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(color: CouleursJarvis.ivoire, fontSize: 12),
    ),
  );
}

/// Fond de page de JARVIS : centre légèrement plus clair, bords un peu
/// plus chauds. Écarts de teinte très faibles et dégradés larges : pas de
/// contraste agressif (Flutter trame les dégradés, ce qui évite les bandes).
class FondJarvis extends StatelessWidget {
  const FondJarvis({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: degradeFondJarvis),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 1.25,
            colors: [Color(0x80FFFDF8), Color(0x00FFFDF8), Color(0x14C9B79C)],
            stops: [0, 0.6, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}
