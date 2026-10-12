import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'archive_zip.dart';
import 'export_local.dart';

/// Navigateur : aucun disque accessible, la copie reste en mémoire le
/// temps de la lecture.
Future<ExportLocal> creerExportLocal() async => _ExportMemoire();

class _ExportMemoire implements ExportLocal {
  BytesBuilder? _tampon = BytesBuilder(copy: false);
  Uint8List _octets = Uint8List(0);

  @override
  int get taille => _tampon?.length ?? _octets.length;

  @override
  Future<void> ecrire(List<int> morceau) async => _tampon!.add(morceau);

  @override
  Future<void> fermerEcriture() async {
    _octets = _tampon?.takeBytes() ?? _octets;
    _tampon = null;
  }

  @override
  Stream<List<int>> lire() async* {
    const tranche = 1 << 20;
    for (var i = 0; i < _octets.length; i += tranche) {
      final fin = i + tranche < _octets.length ? i + tranche : _octets.length;
      yield Uint8List.sublistView(_octets, i, fin);
    }
  }

  @override
  Future<List<EntreeArchive>> listerArchive() async =>
      listerEntreesZip(InputMemoryStream(_octets));

  @override
  Future<Uint8List> extraire(String nom, {required int limite}) async =>
      extraireEntreeZip(InputMemoryStream(_octets), nom, limite);

  @override
  Future<void> supprimer() async {
    _tampon = null;
    _octets = Uint8List(0);
  }
}
