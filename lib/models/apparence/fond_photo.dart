import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../theme/motifs_jarvis.dart';

/// Réglages d'un fond photo : rendu (visibilité, flou, assombrissement) et
/// cadrage (zoom au-delà du « remplir l'écran », décalage en fraction de
/// l'écran). Le même cadrage sert à l'aperçu de l'éditeur et au vrai fond :
/// les deux ont les proportions de l'écran.
@immutable
class ReglagesPhoto {
  const ReglagesPhoto({
    this.visibilite = 0.85,
    this.flou = 0,
    this.assombrissement = 0.25,
    this.zoom = 1,
    this.decalage = Offset.zero,
  });

  static const parDefaut = ReglagesPhoto();

  static const visibiliteMin = 0.15, flouMax = 24.0, assombrissementMax = 0.7;
  static const zoomMax = 4.0;

  /// Opacité de la photo sur le fond du thème (0,15 à 1).
  final double visibilite;

  /// Flou (écart type, en points logiques ; 0 : net).
  final double flou;

  /// Voile sombre posé sur la photo (0 à 0,7) : les bulles restent lisibles.
  final double assombrissement;

  /// Agrandissement au-delà du cadrage « remplir » (1 à 4).
  final double zoom;

  /// Décalage du centre de la photo, en fraction de la taille de l'écran.
  final Offset decalage;

  ReglagesPhoto copyWith({
    double? visibilite,
    double? flou,
    double? assombrissement,
    double? zoom,
    Offset? decalage,
  }) => ReglagesPhoto(
    visibilite: (visibilite ?? this.visibilite).clamp(visibiliteMin, 1.0),
    flou: (flou ?? this.flou).clamp(0.0, flouMax),
    assombrissement: (assombrissement ?? this.assombrissement).clamp(
      0.0,
      assombrissementMax,
    ),
    zoom: (zoom ?? this.zoom).clamp(1.0, zoomMax),
    decalage: decalage ?? this.decalage,
  );

  /// Cadrage d'origine (zoom 1, centré), rendu inchangé.
  ReglagesPhoto get cadrageInitial => copyWith(zoom: 1, decalage: Offset.zero);

  Map<String, Object> versJson() => {
    'visibilite': visibilite,
    'flou': flou,
    'assombrissement': assombrissement,
    'zoom': zoom,
    'dx': decalage.dx,
    'dy': decalage.dy,
  };

  /// Lecture tolérante : valeur absente ou illisible → valeur par défaut.
  static ReglagesPhoto depuisJson(Object? brut) {
    if (brut is! Map) return parDefaut;
    double v(String cle, double defaut) {
      final x = brut[cle];
      return x is num && x.isFinite ? x.toDouble() : defaut;
    }

    return parDefaut.copyWith(
      visibilite: v('visibilite', parDefaut.visibilite),
      flou: v('flou', parDefaut.flou),
      assombrissement: v('assombrissement', parDefaut.assombrissement),
      zoom: v('zoom', 1),
      decalage: Offset(
        v('dx', 0).clamp(-2.0, 2.0),
        v('dy', 0).clamp(-2.0, 2.0),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReglagesPhoto &&
      other.visibilite == visibilite &&
      other.flou == flou &&
      other.assombrissement == assombrissement &&
      other.zoom == zoom &&
      other.decalage == decalage;

  @override
  int get hashCode =>
      Object.hash(visibilite, flou, assombrissement, zoom, decalage);
}

/// Photo choisie comme fond : l'identifiant de son fichier dans le dépôt
/// local (`DepotFondsPhoto`) et ses réglages. Jamais d'octets ici.
@immutable
class FondPhoto {
  const FondPhoto({required this.id, this.reglages = ReglagesPhoto.parDefaut});

  final String id;
  final ReglagesPhoto reglages;

  FondPhoto avec(ReglagesPhoto r) => FondPhoto(id: id, reglages: r);

  Map<String, Object> versJson() => {'id': id, 'reglages': reglages.versJson()};

  static FondPhoto? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final id = brut['id'];
    if (id is! String || !estIdValide(id)) return null;
    return FondPhoto(
      id: id,
      reglages: ReglagesPhoto.depuisJson(brut['reglages']),
    );
  }

  /// Identifiants créés par le dépôt : lettres, chiffres, tirets.
  static bool estIdValide(String id) =>
      id.isNotEmpty &&
      id.length <= 64 &&
      RegExp(r'^[A-Za-z0-9-]+$').hasMatch(id);

  @override
  bool operator ==(Object other) =>
      other is FondPhoto && other.id == id && other.reglages == reglages;

  @override
  int get hashCode => Object.hash(id, reglages);
}

/// Fond retenu pour un écran : un motif (avec son intensité) ou une photo.
@immutable
sealed class FondChoisi {
  const FondChoisi();

  Map<String, Object> versJson();

  static FondChoisi? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    switch (brut['type']) {
      case 'motif':
        final i = brut['intensite'];
        return FondMotif(
          MotifJarvis.depuisNom(
            brut['motif'] is String ? brut['motif'] as String : null,
          ),
          i is num && i.isFinite
              ? i.toDouble().clamp(0.0, 1.0)
              : intensiteMotifParDefaut,
        );
      case 'photo':
        final p = FondPhoto.depuisJson(brut['photo']);
        return p == null ? null : FondPhotoChoisi(p);
    }
    return null;
  }
}

final class FondMotif extends FondChoisi {
  const FondMotif(this.motif, this.intensite);

  final MotifJarvis motif;
  final double intensite;

  @override
  Map<String, Object> versJson() => {
    'type': 'motif',
    'motif': motif.name,
    'intensite': intensite,
  };

  @override
  bool operator ==(Object other) =>
      other is FondMotif &&
      other.motif == motif &&
      other.intensite == intensite;

  @override
  int get hashCode => Object.hash(motif, intensite);
}

final class FondPhotoChoisi extends FondChoisi {
  const FondPhotoChoisi(this.photo);

  final FondPhoto photo;

  @override
  Map<String, Object> versJson() => {
    'type': 'photo',
    'photo': photo.versJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is FondPhotoChoisi && other.photo == photo;

  @override
  int get hashCode => photo.hashCode;
}
