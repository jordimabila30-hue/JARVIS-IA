import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/utils/version_jarvis.dart';

void main() {
  test('version affichée = version du pubspec (seule source)', () {
    final ligne = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final (nom, build) = switch (ligne.substring(8).trim().split('+')) {
      [final n, final b] => (n, b),
      [final n] => (n, null),
      _ => throw StateError(ligne),
    };
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(nom), isTrue);
    // Flutter injecte la version dans la build (tests compris).
    expect(VersionJarvis.nom, nom);
    expect(VersionJarvis.build, build);
    expect(VersionJarvis.courte, 'v$nom');
    expect(
      VersionJarvis.libelle,
      build == null ? 'Version $nom' : 'Version $nom (build $build)',
    );
  });
}
