// Photos importées (session GH, opt. 55) : l'orientation EXIF est
// appliquée au décodage (une photo portrait n'apparaît jamais couchée),
// y compris avec la réduction de taille des fonds photo.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/widgets/apparence/rendu_fond_photo.dart';

void main() {
  test('EXIF « tourner de 90° » : décodée en portrait (20 × 40)', () async {
    final octets = File(
      'test/fixtures/images/portrait_exif6.jpg',
    ).readAsBytesSync();
    final image = (await decoderFondPhoto(octets))!;
    expect((image.width, image.height), (20, 40));
    image.dispose();
  });

  test('sans EXIF : décodée telle quelle (40 × 20)', () async {
    final octets = File(
      'test/fixtures/images/paysage_sans_exif.jpg',
    ).readAsBytesSync();
    final image = (await decoderFondPhoto(octets))!;
    expect((image.width, image.height), (40, 20));
    image.dispose();
  });

  test('réduction (côté max 16) : orientation gardée', () async {
    final octets = File(
      'test/fixtures/images/portrait_exif6.jpg',
    ).readAsBytesSync();
    final image = (await decoderFondPhoto(octets, coteMax: 16))!;
    expect(image.height, greaterThan(image.width));
    expect(image.height, lessThanOrEqualTo(16));
    image.dispose();
  });
}
