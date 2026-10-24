import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/apparence/fond_photo.dart';

/// Décode une photo de fond réduite à [coteMax] pixels sur son plus grand
/// côté (jamais agrandie) : la mémoire reste celle d'un écran, pas celle de
/// la photo d'origine (souvent 12 Mpx).
Future<ui.Image?> decoderFondPhoto(
  Uint8List octets, {
  int coteMax = 2048,
}) async {
  try {
    final tampon = await ui.ImmutableBuffer.fromUint8List(octets);
    final codec = await ui.instantiateImageCodecWithSize(
      tampon,
      getTargetSize: (l, h) {
        final echelle = math.min(1.0, coteMax / math.max(l, h));
        return ui.TargetImageSize(
          width: math.max(1, (l * echelle).round()),
          height: math.max(1, (h * echelle).round()),
        );
      },
    );
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    return image;
  } catch (_) {
    return null; // format non pris en charge, fichier abîmé
  }
}

/// Rectangle où dessiner la photo [source] dans [cadre] : « remplir »
/// (cover), agrandi par le zoom, décalé du décalage (fraction du cadre).
Rect rectanglePhoto(Size source, Size cadre, ReglagesPhoto r) {
  final echelle =
      math.max(cadre.width / source.width, cadre.height / source.height) *
      r.zoom;
  final taille = Size(source.width * echelle, source.height * echelle);
  final d = limiterDecalage(r.decalage, source, cadre, r.zoom);
  final centre =
      cadre.center(Offset.zero) +
      Offset(d.dx * cadre.width, d.dy * cadre.height);
  return Rect.fromCenter(
    center: centre,
    width: taille.width,
    height: taille.height,
  );
}

/// Décalage permis : la photo couvre toujours tout le cadre.
Offset limiterDecalage(Offset d, Size source, Size cadre, double zoom) {
  final echelle =
      math.max(cadre.width / source.width, cadre.height / source.height) * zoom;
  final mx = math.max(0.0, (source.width * echelle - cadre.width) / 2);
  final my = math.max(0.0, (source.height * echelle - cadre.height) / 2);
  return Offset(
    (d.dx * cadre.width).clamp(-mx, mx) / cadre.width,
    (d.dy * cadre.height).clamp(-my, my) / cadre.height,
  );
}

/// Compose UNE fois le fond photo à la taille de l'écran : cadrage, flou
/// et assombrissement cuits dans l'image. Ensuite, chaque image affichée
/// n'en fait qu'une copie (aucun flou recalculé, PIM inchangé au-dessus).
ui.Image composerFondPhoto(
  ui.Image source,
  Size taille,
  double densite,
  ReglagesPhoto r,
) {
  final enregistreur = ui.PictureRecorder();
  final canvas = Canvas(enregistreur);
  canvas.scale(densite);
  final cadre = Offset.zero & taille;
  canvas.clipRect(cadre);
  final src = Size(source.width.toDouble(), source.height.toDouble());
  final dest = rectanglePhoto(src, taille, r);
  final pinceau = Paint()..filterQuality = FilterQuality.medium;
  if (r.flou > 0.05) {
    canvas.saveLayer(
      cadre,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: r.flou,
          sigmaY: r.flou,
          tileMode: TileMode.clamp,
        ),
    );
  }
  canvas.drawImageRect(source, Offset.zero & src, dest, pinceau);
  if (r.flou > 0.05) canvas.restore();
  if (r.assombrissement > 0) {
    canvas.drawRect(
      cadre,
      Paint()..color = Color.fromRGBO(0, 0, 0, r.assombrissement),
    );
  }
  final dessin = enregistreur.endRecording();
  final image = dessin.toImageSync(
    math.max(1, (taille.width * densite).ceil()),
    math.max(1, (taille.height * densite).ceil()),
  );
  dessin.dispose();
  return image;
}

/// Pose le fond photo composé (à la taille de la fenêtre, depuis le coin
/// haut-gauche : le clavier qui réduit la page ne le recompose pas), avec
/// sa visibilité : le fond du thème transparaît dessous.
void peindreFondPhoto(
  Canvas canvas,
  ui.Image composee,
  double densite,
  double visibilite,
) {
  final taille = Size(composee.width / densite, composee.height / densite);
  canvas.drawImageRect(
    composee,
    Rect.fromLTWH(0, 0, composee.width.toDouble(), composee.height.toDouble()),
    Offset.zero & taille,
    Paint()
      ..filterQuality = FilterQuality.low
      ..color = Color.fromRGBO(0, 0, 0, visibilite.clamp(0.0, 1.0)),
  );
}

/// Clarté moyenne (luminance relative, 0 à 1) d'une image, mesurée sur une
/// vignette de 8 × 8 : une seule lecture, faite une fois par fond composé.
Future<double?> clarteMoyenne(ui.Image image) async {
  try {
    const n = 8;
    final enregistreur = ui.PictureRecorder();
    Canvas(enregistreur).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, n * 1.0, n * 1.0),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final dessin = enregistreur.endRecording();
    final vignette = await dessin.toImage(n, n);
    dessin.dispose();
    final octets = await vignette.toByteData();
    vignette.dispose();
    if (octets == null) return null;
    var somme = 0.0;
    for (var i = 0; i < n * n; i++) {
      somme += Color.fromARGB(
        255,
        octets.getUint8(i * 4),
        octets.getUint8(i * 4 + 1),
        octets.getUint8(i * 4 + 2),
      ).computeLuminance();
    }
    return somme / (n * n);
  } catch (_) {
    return null;
  }
}
