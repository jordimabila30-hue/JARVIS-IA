import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../theme/motifs_jarvis.dart';
import 'fond_photo.dart';
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
    this.photo,
    this.photoActive = false,
  });

  static const parDefaut = PreferencesApparence();

  /// Version du format enregistré.
  static const version = 1;

  final ModeAffichage mode;
  final StyleVisuel style;
  final MotifJarvis motif;

  /// Intensité du motif, de 0 à 1.
  final double intensite;

  /// Photo personnelle (« Ma galerie ») gardée même quand un motif est
  /// choisi ; [photoActive] : c'est elle le fond général.
  final FondPhoto? photo;
  final bool photoActive;

  /// Fond général affiché : la photo si elle est active, sinon le motif.
  FondChoisi get fondGeneral => photoActive && photo != null
      ? FondPhotoChoisi(photo!)
      : FondMotif(motif, intensite);

  PreferencesApparence copyWith({
    ModeAffichage? mode,
    StyleVisuel? style,
    MotifJarvis? motif,
    double? intensite,
    Object? photo = _inchange,
    bool? photoActive,
  }) => PreferencesApparence(
    mode: mode ?? this.mode,
    style: style ?? this.style,
    motif: motif ?? this.motif,
    intensite: (intensite ?? this.intensite).clamp(0.0, 1.0),
    photo: identical(photo, _inchange) ? this.photo : photo as FondPhoto?,
    photoActive: photoActive ?? this.photoActive,
  );

  static const _inchange = Object();

  String encoder() => jsonEncode({
    'v': version,
    'mode': mode.name,
    'style': style.name,
    'motif': motif.name,
    'intensite': intensite,
    if (photo case final p?) 'photo': p.versJson(),
    'photoActive': photoActive,
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
      photo: FondPhoto.depuisJson(brut['photo']),
      photoActive: brut['photoActive'] == true,
    );
  }

  static String? _texte(Object? v) => v is String ? v : null;

  @override
  bool operator ==(Object other) =>
      other is PreferencesApparence &&
      other.mode == mode &&
      other.style == style &&
      other.motif == motif &&
      other.intensite == intensite &&
      other.photo == photo &&
      other.photoActive == photoActive;

  @override
  int get hashCode =>
      Object.hash(mode, style, motif, intensite, photo, photoActive);
}
