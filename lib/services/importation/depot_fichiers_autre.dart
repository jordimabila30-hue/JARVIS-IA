import 'dart:io';

import 'package:flutter/services.dart';

import '../../models/importation/export_whatsapp.dart';
import 'depot_fichiers.dart';
import 'selection_export_whatsapp.dart';

/// Windows : fichiers déposés signalés par la fenêtre native
/// (`windows/runner/flutter_window.cpp`). Autres plateformes : rien.
DepotFichiers creerDepotFichiers() => _DepotNatif();

class _DepotNatif implements DepotFichiers {
  static const _canal = MethodChannel('jarvis/depot');

  @override
  bool get disponible => Platform.isWindows;

  @override
  void demarrer({
    required void Function(bool survol) surSurvol,
    required void Function(List<FichierBrut> fichiers) surDepot,
  }) {
    if (!disponible) return;
    _canal.setMethodCallHandler((appel) async {
      if (appel.method != 'fichiersDeposes') return;
      final chemins = (appel.arguments as List<Object?>).cast<String>();
      surDepot([for (final c in chemins) _fichier(c)]);
    });
  }

  @override
  void arreter() {
    if (disponible) _canal.setMethodCallHandler(null);
  }

  FichierBrut _fichier(String chemin) {
    final fichier = File(chemin);
    int? taille;
    try {
      taille = fichier.lengthSync();
    } on FileSystemException {
      taille = null;
    }
    return FichierBrut(
      nom: fichier.uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => chemin,
      ),
      source: SourceReception.glisserDeposer,
      tailleOctets: taille,
      // Lecture paresseuse ; un dossier ou un fichier verrouillé échoue
      // à la lecture, ce qui donne un refus clair.
      flux: fichier.openRead(),
    );
  }
}
