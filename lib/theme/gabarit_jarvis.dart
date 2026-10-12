import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Format d'écran de JARVIS.
enum FormatEcran {
  /// Téléphone, petite fenêtre : largeur < 600 ou hauteur < 640.
  compact,

  /// Tablette, ordinateur portable.
  moyen,

  /// Grand écran : largeur ≥ 1200 et hauteur ≥ 800.
  large,
}

/// Mesures de mise en page selon la taille de l'écran : marges, tailles de
/// texte et taille de la zone des particules PIM.
///
/// Hiérarchie voulue : particules PIM, puis statut, puis conversation,
/// puis actions secondaires. Les textes restent donc modestes ; c'est la
/// sphère qui occupe l'espace.
class GabaritJarvis {
  const GabaritJarvis._({
    required this.format,
    required this.marges,
    required this.hauteurBarre,
    required this.tailleLogo,
    required this.tailleSalutation,
    required this.tailleMission,
    required this.largeurMission,
    required this.ecartSphereTexte,
    required this.largeurSaisie,
    required this.tailleStatut,
    required this.tailleCitation,
    required this.tailleReponse,
    required this.lignesReponse,
    required this.largeurTexte,
    required this.zoneMin,
    required this.zoneMaxTexte,
    required this.zoneMaxVocal,
    required this.reserveTexte,
    required this.reserveVocal,
  });

  // --- Points de rupture ----------------------------------------------------

  static const largeurCompacte = 600.0;
  static const hauteurCompacte = 640.0;
  static const largeurLarge = 1200.0;
  static const hauteurLarge = 800.0;

  factory GabaritJarvis.de(Size ecran) {
    if (ecran.width < largeurCompacte || ecran.height < hauteurCompacte) {
      return const GabaritJarvis._(
        format: FormatEcran.compact,
        marges: EdgeInsets.fromLTRB(16, 4, 16, 24),
        hauteurBarre: 40,
        tailleLogo: 13,
        tailleSalutation: 30,
        tailleMission: 14,
        largeurMission: 300,
        ecartSphereTexte: 2,
        largeurSaisie: 680,
        tailleStatut: 12.5,
        tailleCitation: 13,
        tailleReponse: 15,
        lignesReponse: 3,
        largeurTexte: 380,
        zoneMin: 220,
        zoneMaxTexte: 440,
        zoneMaxVocal: 460,
        reserveTexte: 96,
        reserveVocal: 150,
      );
    }
    if (ecran.width >= largeurLarge && ecran.height >= hauteurLarge) {
      return const GabaritJarvis._(
        format: FormatEcran.large,
        marges: EdgeInsets.fromLTRB(40, 24, 40, 72),
        hauteurBarre: 48,
        tailleLogo: 15,
        tailleSalutation: 46,
        tailleMission: 16.5,
        largeurMission: 620,
        ecartSphereTexte: 10,
        largeurSaisie: 760,
        tailleStatut: 13.5,
        tailleCitation: 14.5,
        tailleReponse: 17,
        lignesReponse: 4,
        largeurTexte: 540,
        zoneMin: 320,
        zoneMaxTexte: 560,
        zoneMaxVocal: 660,
        reserveTexte: 124,
        reserveVocal: 200,
      );
    }
    return const GabaritJarvis._(
      format: FormatEcran.moyen,
      marges: EdgeInsets.fromLTRB(28, 16, 28, 52),
      hauteurBarre: 48,
      tailleLogo: 14,
      tailleSalutation: 40,
      tailleMission: 15.5,
      largeurMission: 560,
      ecartSphereTexte: 6,
      largeurSaisie: 720,
      tailleStatut: 13,
      tailleCitation: 14,
      tailleReponse: 16,
      lignesReponse: 4,
      largeurTexte: 480,
      zoneMin: 260,
      zoneMaxTexte: 540,
      zoneMaxVocal: 580,
      reserveTexte: 112,
      reserveVocal: 190,
    );
  }

  static GabaritJarvis of(BuildContext context) =>
      GabaritJarvis.de(MediaQuery.sizeOf(context));

  final FormatEcran format;
  final EdgeInsets marges;
  final double hauteurBarre;
  final double tailleLogo;

  /// Tailles de texte (px) : salutation du mode texte, statut du mode
  /// vocal, phrase entendue, réponse de JARVIS.
  final double tailleSalutation;

  /// Phrase de mission sous la salutation, et écart entre la zone des
  /// particules et la salutation.
  final double tailleMission;

  /// Largeur maximale de la phrase de mission : une ligne sur grand écran,
  /// deux lignes équilibrées sur téléphone.
  final double largeurMission;
  final double ecartSphereTexte;

  /// Largeur maximale de la barre de saisie.
  final double largeurSaisie;
  final double tailleStatut;
  final double tailleCitation;
  final double tailleReponse;
  final int lignesReponse;

  /// Largeur maximale des textes du mode vocal.
  final double largeurTexte;

  /// Côté minimal et maximal de la zone des particules (px). Le rayon de
  /// la sphère vaut 0,36 × ce côté.
  final double zoneMin;
  final double zoneMaxTexte;
  final double zoneMaxVocal;

  /// Hauteur gardée sous la zone pour le texte (salutation ou conversation).
  final double reserveTexte;
  final double reserveVocal;

  bool get compact => format == FormatEcran.compact;

  /// Côté de la zone des particules dans l'espace [largeur] × [hauteur]
  /// disponible : borné entre [zoneMin] et le maximum du mode, et jamais
  /// plus grand que la place réelle (aucun débordement).
  double zone(double largeur, double hauteur, {required bool vocal}) {
    final reserve = vocal ? reserveVocal : reserveTexte;
    final maximum = vocal ? zoneMaxVocal : zoneMaxTexte;
    final voulu = math.min(largeur - 16, hauteur - reserve);
    final borne = voulu.clamp(zoneMin, maximum);
    return math.max(120.0, math.min(borne, math.min(largeur, hauteur - 24)));
  }
}
