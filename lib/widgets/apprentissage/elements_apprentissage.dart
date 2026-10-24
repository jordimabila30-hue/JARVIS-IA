import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';

/// Éléments visuels communs du module Apprendre : surfaces, barres de
/// progression, en-tête, boutons. Toutes les couleurs viennent de la
/// palette active (style et mode choisis dans Apparence).

/// Icône d'un parcours d'après la clé du catalogue.
IconData iconeParcours(String cle) => switch (cle) {
  'courrier' => Icons.mail_outline_rounded,
  'dialogue' => Icons.forum_outlined,
  'relations' => Icons.handshake_outlined,
  'technique' => Icons.memory_rounded,
  _ => Icons.school_outlined,
};

/// Surface du module : verre de la palette, contour fin, coins arrondis ;
/// touchable si [surAppui] est donné.
class SurfaceApprentissage extends StatelessWidget {
  const SurfaceApprentissage({
    super.key,
    required this.child,
    this.surAppui,
    this.padding = const EdgeInsets.all(16),
    this.accent = false,
    this.etiquette,
  });

  final Widget child;
  final VoidCallback? surAppui;
  final EdgeInsetsGeometry padding;

  /// Surface mise en avant (fond légèrement teinté).
  final bool accent;

  /// Nom lu par les lecteurs d'écran (surface touchable).
  final String? etiquette;

  static const rayon = 18.0;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final forme = BorderRadius.circular(rayon);
    final identite = p.identite;
    final decoration = BoxDecoration(
      color: accent
          ? Color.alphaBlend(p.signal.withValues(alpha: 0.07), p.coque)
          : p.coque.withValues(alpha: 0.88),
      borderRadius: forme,
      border: Border.all(
        color: identite.marquee ? p.texte : p.trait.withValues(alpha: 0.75),
        width: identite.marquee ? identite.contour : 1,
      ),
      boxShadow: identite.ombreCarte != null
          ? [BoxShadow(color: identite.ombreCarte!, offset: const Offset(3, 3))]
          : null,
    );
    final contenu = Padding(padding: padding, child: child);
    if (surAppui == null) {
      return DecoratedBox(decoration: decoration, child: contenu);
    }
    return Semantics(
      button: true,
      label: etiquette,
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: surAppui, borderRadius: forme, child: contenu),
        ),
      ),
    );
  }
}

/// Barre de progression fine. Toujours visible (même à 0 %) ; la valeur
/// glisse en douceur quand elle change (animation implicite, aucun
/// contrôleur à gérer).
class BarreProgression extends StatelessWidget {
  const BarreProgression({super.key, required this.valeur, this.hauteur = 6});

  /// De 0 à 1.
  final double valeur;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final v = valeur.clamp(0.0, 1.0);
    return Semantics(
      value: '${(v * 100).round()} %',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(hauteur),
        child: SizedBox(
          height: hauteur,
          child: ColoredBox(
            color: p.trait.withValues(alpha: 0.6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: v),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (_, t, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: t,
                heightFactor: 1,
                child: ColoredBox(color: p.signal),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// « 45 % » d'un avancement de 0 à 1.
String pourcentage(double v) => '${(v.clamp(0.0, 1.0) * 100).round()} %';

/// En-tête des pages du module : retour, titre, actions.
class EnTeteApprentissage extends StatelessWidget {
  const EnTeteApprentissage({
    super.key,
    required this.titre,
    this.actions = const [],
    this.iconeRetour = Icons.arrow_back_rounded,
    this.libelleRetour = 'Retour',
  });

  final String titre;
  final List<Widget> actions;
  final IconData iconeRetour;
  final String libelleRetour;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: libelleRetour,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(iconeRetour),
            color: p.texte,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              titre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: p.identite.policeAffichage,
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: p.texte,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Bouton principal (plein, couleur signal).
class BoutonApprentissage extends StatelessWidget {
  const BoutonApprentissage({
    super.key,
    required this.libelle,
    required this.surAppui,
    this.secondaire = false,
    this.icone,
  });

  final String libelle;
  final VoidCallback? surAppui;
  final bool secondaire;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(120, 50)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
    final texte = Text(libelle, textAlign: TextAlign.center);
    final enfant = icone == null
        ? texte
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 18),
              const SizedBox(width: 8),
              Flexible(child: texte),
            ],
          );
    if (secondaire) {
      return OutlinedButton(
        onPressed: surAppui,
        style: style.copyWith(
          foregroundColor: WidgetStatePropertyAll(p.texte),
          side: WidgetStatePropertyAll(BorderSide(color: p.trait)),
        ),
        child: enfant,
      );
    }
    return FilledButton(
      onPressed: surAppui,
      style: style.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? p.trait : p.signal,
        ),
        foregroundColor: WidgetStatePropertyAll(p.surSignal),
      ),
      child: enfant,
    );
  }
}

/// Petit texte secondaire.
TextStyle styleDiscret(BuildContext context, {double taille = 13}) => TextStyle(
  fontSize: taille,
  color: PaletteJarvis.of(context).texteSecondaire,
);

/// Titre de carte.
TextStyle styleTitre(BuildContext context, {double taille = 16}) => TextStyle(
  fontSize: taille,
  fontWeight: FontWeight.w600,
  color: PaletteJarvis.of(context).texte,
);

/// Largeur maximale du contenu (lisibilité sur grand écran).
const largeurContenuApprentissage = 760.0;

/// Corps d'une page du module : fond JARVIS, zone sûre, contenu centré.
class PageApprentissage extends StatelessWidget {
  const PageApprentissage({
    super.key,
    required this.enTete,
    required this.corps,
  });

  final Widget enTete;
  final Widget corps;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaletteJarvis.of(context).ivoirePrincipal,
      body: FondJarvis(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: largeurContenuApprentissage,
                  ),
                  child: enTete,
                ),
              ),
              Expanded(child: corps),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marge latérale selon la largeur.
double margeApprentissage(double largeur) => largeur < 600 ? 16 : 28;
