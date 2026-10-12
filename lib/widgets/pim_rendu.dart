import 'package:flutter/material.dart';

/// Apparence d'une famille de particules PIM.
class StylePim {
  const StylePim({
    required this.couleur,
    required this.taille,
    required this.part,
    this.relief = false,
    this.lueur = 0,
    this.halo = 3.0,
  });

  /// Couleur de base (plan intermédiaire).
  final Color couleur;

  /// Diamètre (px) au plan intermédiaire, pour une sphère de taille moyenne.
  final double taille;

  /// Part des particules qui ont ce style (la somme fait 1).
  final double part;

  /// Petit reflet clair décalé : la particule paraît sphérique.
  final bool relief;

  /// Intensité du halo doux (0 = aucun).
  final double lueur;

  /// Taille du halo par rapport à la particule : elle varie d'un style à
  /// l'autre pour que tous les halos n'aient pas la même taille.
  final double halo;

  /// Micro-particule (ni relief ni halo).
  bool get micro => !relief && lueur == 0;
}

/// Rendu d'un plan de profondeur, du fond (0) vers l'observateur.
class PlanPim {
  const PlanPim({
    required this.taille,
    required this.opacite,
    required this.brume,
    required this.contraste,
    required this.reflet,
    required this.flou,
    required this.lueur,
  });

  /// Facteur de taille des particules.
  final double taille;

  /// Opacité des particules.
  final double opacite;

  /// Mélange avec la couleur du fond (0 = aucun, 1 = invisible).
  final double brume;

  /// Assombrissement vers l'encre (contraste plus fort au premier plan).
  final double contraste;

  /// Visibilité du reflet des particules en relief.
  final double reflet;

  /// Flou (fraction de la taille) ; 0 = net.
  final double flou;

  /// Intensité des halos sur ce plan.
  final double lueur;
}

/// Réglages visuels des particules PIM : palette, tailles, profondeur,
/// lumière.
///
/// Hiérarchie voulue : une majorité de micro-particules graphite et bleu
/// gris, quelques particules moyennes en relief, et environ 2 % de
/// particules lumineuses bleu-lilas avec halo.
class PimRendu {
  PimRendu._();

  static const graphite = Color(0xFF24272F);
  static const anthracite = Color(0xFF343846);
  static const grisBleute = Color(0xFF4D5A76);
  static const bleuNuit = Color(0xFF34416E);
  static const violetGris = Color(0xFF5F5880);
  static const bleuFroid = Color(0xFF4E62C2);
  static const violetDoux = Color(0xFF7866CC);
  static const lilas = Color(0xFFB7A2F6);
  static const bleuLumineux = Color(0xFF86A4FF);
  static const bleuClair = Color(0xFFBFD0FF);

  /// Encre vers laquelle on assombrit le premier plan.
  static const encre = Color(0xFF12141A);

  /// Couleur du fond dans laquelle se fond l'arrière-plan.
  static const fondBrume = Color(0xFFF3EEE5);

  /// Lumière des halos et du cœur.
  static const lumiere = Color(0xFFC9B8FF);

  /// Reflet clair posé sur les particules en relief.
  static const reflet = Color(0xFFF7F4FF);

  /// Familles de particules, des plus nombreuses aux plus rares.
  static const styles = <StylePim>[
    // Micro-particules (≈ 80 %) : graphite, bleu gris, bleu nuit, violet gris.
    StylePim(couleur: graphite, taille: 2.3, part: 0.30),
    StylePim(couleur: anthracite, taille: 2.7, part: 0.16),
    StylePim(couleur: grisBleute, taille: 2.4, part: 0.18),
    StylePim(couleur: bleuNuit, taille: 2.4, part: 0.09),
    StylePim(couleur: violetGris, taille: 2.4, part: 0.07),
    // Particules moyennes, en relief (≈ 18 %).
    StylePim(couleur: anthracite, taille: 4.6, part: 0.085, relief: true),
    StylePim(couleur: bleuFroid, taille: 4.4, part: 0.055, relief: true),
    StylePim(
      couleur: violetDoux,
      taille: 4.6,
      part: 0.038,
      relief: true,
      lueur: 0.3,
      halo: 2.2,
    ),
    // Accents lumineux (≈ 2,2 %), halos de tailles différentes.
    StylePim(
      couleur: bleuLumineux,
      taille: 6.6,
      part: 0.008,
      relief: true,
      lueur: 0.9,
      halo: 2.6,
    ),
    StylePim(
      couleur: lilas,
      taille: 7.4,
      part: 0.008,
      relief: true,
      lueur: 1,
      halo: 3.4,
    ),
    StylePim(
      couleur: bleuClair,
      taille: 5.4,
      part: 0.006,
      relief: true,
      lueur: 0.7,
      halo: 4.0,
    ),
  ];

  /// Plans de profondeur, du fond vers l'observateur. Le plan du milieu
  /// porte la majorité de la sphère ; le fond est plus petit, plus doux et
  /// fondu dans le beige ; l'avant est plus grand, plus net, plus contrasté.
  static const plans = <PlanPim>[
    PlanPim(
      taille: 0.62,
      opacite: 0.55,
      brume: 0.48,
      contraste: 0,
      reflet: 0,
      flou: 0.3,
      lueur: 0.45,
    ),
    PlanPim(
      taille: 0.8,
      opacite: 0.72,
      brume: 0.26,
      contraste: 0,
      reflet: 0.35,
      flou: 0,
      lueur: 0.65,
    ),
    PlanPim(
      taille: 0.96,
      opacite: 0.9,
      brume: 0.06,
      contraste: 0.05,
      reflet: 0.55,
      flou: 0,
      lueur: 0.85,
    ),
    PlanPim(
      taille: 1.1,
      opacite: 0.97,
      brume: 0,
      contraste: 0.12,
      reflet: 0.7,
      flou: 0,
      lueur: 1,
    ),
    PlanPim(
      taille: 1.27,
      opacite: 1,
      brume: 0,
      contraste: 0.2,
      reflet: 0.85,
      flou: 0,
      lueur: 1.15,
    ),
  ];

  /// Profondeur couverte par les plans (en rayons) : au-delà de ±1,1
  /// rayon, une particule est au tout premier plan ou au fond.
  static const etendueProfondeur = 1.1;

  // --- Répartition --------------------------------------------------------

  /// Variation spatiale de la richesse : certaines zones ont un peu plus de
  /// particules moyennes et lumineuses (0 = uniforme). Variation lente et
  /// douce, pas d'amas.
  static const variationRichesse = 0.9;

  // --- Lumière et finition ---------------------------------------------------

  /// Intensité générale des halos (0 = aucun, 1 = réglage conseillé).
  static const intensiteLueur = 1.0;

  /// Lumière diffuse au cœur de la sphère (0 à 1) : une présence, pas une
  /// boule lumineuse.
  static const lumiereCentrale = 0.32;

  /// Étendue de la lumière centrale, en rayons.
  static const etendueLumiere = 1.25;

  /// Opacité de l'ombre portée sous la sphère.
  static const ombre = 0.12;

  /// Largeur de l'ombre (en rayons) et sensibilité au flottement : plus
  /// haut = ombre plus large et plus pâle ; plus bas = plus petite et plus
  /// marquée.
  static const largeurOmbre = 1.05;
  static const reactionOmbre = 1.5;

  // --- Petits écrans -------------------------------------------------------

  /// Rayon de sphère (px) en dessous duquel le rendu est simplifié (pas de
  /// flou sur les micro-particules du fond, halos des particules moyennes
  /// retirés) : coût réduit sur téléphone, différence invisible à cette
  /// taille.
  static const rayonQualiteReduite = 110.0;
}
