import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../theme/motifs_jarvis.dart';
import '../../theme/styles_jarvis.dart';

/// Mode d'affichage, indépendant du style visuel.
enum ModeAffichage {
  clair('Clair'),
  sombre('Sombre'),
  systeme('Système');

  const ModeAffichage(this.libelle);

  final String libelle;
}

/// Préférences d'apparence : quatre choix indépendants. Par défaut (et pour
/// les utilisateurs existants) : JARVIS original, clair, fond « Aurore »
/// d'origine — exactement l'apparence d'avant.
@immutable
class PreferencesApparence {
  const PreferencesApparence({
    this.mode = ModeAffichage.clair,
    this.style = StyleVisuel.jarvis,
    this.motif = MotifJarvis.aurore,
    this.intensite = intensiteMotifParDefaut,
  });

  static const parDefaut = PreferencesApparence();

  /// Version du format enregistré.
  static const version = 1;

  final ModeAffichage mode;
  final StyleVisuel style;
  final MotifJarvis motif;

  /// Intensité du motif, de 0 à 1.
  final double intensite;

  PreferencesApparence copyWith({
    ModeAffichage? mode,
    StyleVisuel? style,
    MotifJarvis? motif,
    double? intensite,
  }) => PreferencesApparence(
    mode: mode ?? this.mode,
    style: style ?? this.style,
    motif: motif ?? this.motif,
    intensite: (intensite ?? this.intensite).clamp(0.0, 1.0),
  );

  String encoder() => jsonEncode({
    'v': version,
    'mode': mode.name,
    'style': style.name,
    'motif': motif.name,
    'intensite': intensite,
  });

  /// Lecture tolérante : texte absent, illisible, version future ou valeur
  /// inconnue → valeur par défaut de ce champ, jamais d'erreur.
  static PreferencesApparence decoder(String? texte) {
    if (texte == null || texte.isEmpty) return parDefaut;
    Object? brut;
    try {
      brut = jsonDecode(texte);
    } catch (_) {
      return parDefaut;
    }
    if (brut is! Map) return parDefaut;
    final intensite = brut['intensite'];
    return PreferencesApparence(
      mode:
          ModeAffichage.values.asNameMap()[brut['mode']] ?? ModeAffichage.clair,
      style: StyleVisuel.depuisNom(_texte(brut['style'])),
      motif: MotifJarvis.depuisNom(_texte(brut['motif'])),
      intensite: intensite is num && intensite.isFinite
          ? intensite.toDouble().clamp(0.0, 1.0)
          : intensiteMotifParDefaut,
    );
  }

  static String? _texte(Object? v) => v is String ? v : null;

  @override
  bool operator ==(Object other) =>
      other is PreferencesApparence &&
      other.mode == mode &&
      other.style == style &&
      other.motif == motif &&
      other.intensite == intensite;

  @override
  int get hashCode => Object.hash(mode, style, motif, intensite);
}
