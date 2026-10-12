import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'archive_zip.dart';
import 'export_local.dart';
import 'pont_android_importation.dart';

/// Android, iOS, Windows : copie dans un dossier privé de JARVIS
/// (cache de l'application sur Android), effacée après la lecture.
Future<ExportLocal> creerExportLocal() async {
  final racine = await _dossierRacine();
  // Restes d'une lecture interrompue (application fermée en cours).
  try {
    for (final ancien in racine.listSync()) {
      ancien.deleteSync(recursive: true);
    }
  } on FileSystemException {
    // Dossier partagé avec une autre lecture en cours : sans gravité.
  }
  final dossier = await racine.createTemp('lecture_');
  final fichier = File('${dossier.path}${Platform.pathSeparator}export');
  return _ExportFichier(dossier, fichier, fichier.openWrite());
}

Future<Directory> _dossierRacine() async {
  final base = Platform.isAndroid
      ? await PontAndroidImportation.instance.dossierTemporaire()
      : Directory.systemTemp.path;
  final racine = Directory('$base${Platform.pathSeparator}jarvis_import');
  await racine.create(recursive: true);
  return racine;
}

class _ExportFichier implements ExportLocal {
  _ExportFichier(this._dossier, this._fichier, this._ecriture);

  final Directory _dossier;
  final File _fichier;
  IOSink? _ecriture;
  int _taille = 0;

  @override
  int get taille => _taille;

  @override
  Future<void> ecrire(List<int> morceau) async {
    _ecriture!.add(morceau);
    _taille += morceau.length;
    // Laisse le système écrire au fil de l'eau (gros fichiers).
    if (_taille % (8 << 20) < morceau.length) await _ecriture!.flush();
  }

  @override
  Future<void> fermerEcriture() async {
    await _ecriture?.close();
    _ecriture = null;
  }

  @override
  Stream<List<int>> lire() => _fichier.openRead();

  @override
  Future<List<EntreeArchive>> listerArchive() async {
    final entree = InputFileStream(_fichier.path);
    try {
      return listerEntreesZip(entree);
    } finally {
      entree.closeSync();
    }
  }

  @override
  Future<Uint8List> extraire(String nom, {required int limite}) =>
      // Décompression dans un autre isolate : l'interface reste fluide.
      compute(_extraire, (_fichier.path, nom, limite));

  @override
  Future<void> supprimer() async {
    try {
      await _ecriture?.close();
    } catch (_) {}
    try {
      await _dossier.delete(recursive: true);
    } on FileSystemException {
      // Déjà effacé.
    }
  }
}

Uint8List _extraire((String, String, int) demande) {
  final (chemin, nom, limite) = demande;
  final entree = InputFileStream(chemin);
  try {
    return extraireEntreeZip(entree, nom, limite);
  } finally {
    entree.closeSync();
  }
}
