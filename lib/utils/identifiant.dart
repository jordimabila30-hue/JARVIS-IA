import 'dart:math';

/// UUID v4 choisi par l'appareil (pièces jointes, consignes) : une fois
/// attribué, il rend un nouvel envoi sans risque de doublon côté serveur.
String nouvelUuid() {
  final r = Random.secure();
  final o = List<int>.generate(16, (_) => r.nextInt(256));
  o[6] = (o[6] & 0x0f) | 0x40;
  o[8] = (o[8] & 0x3f) | 0x80;
  final h = [for (final b in o) b.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
