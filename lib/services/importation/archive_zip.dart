import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'export_local.dart';

/// Lecture d'une archive ZIP, commune à toutes les plateformes : seul
/// l'index (à la fin du fichier) est lu, puis l'entrée demandée. Les
/// médias ne sont jamais décompressés, et rien n'est écrit sur le disque
/// (les chemins de l'archive ne peuvent donc rien écraser).
List<EntreeArchive> listerEntreesZip(InputStream entree) {
  final dossier = ZipDirectory()..read(entree);
  return [
    for (final h in dossier.fileHeaders)
      EntreeArchive(
        nom: h.filename,
        taille: h.uncompressedSize,
        tailleCompressee: h.compressedSize,
      ),
  ];
}

/// Décompresse [nom] sans jamais dépasser [limite] octets, ni la taille
/// annoncée par l'archive.
Uint8List extraireEntreeZip(InputStream entree, String nom, int limite) {
  final dossier = ZipDirectory()..read(entree);
  final h = dossier.fileHeaders.firstWhere(
    (h) => h.filename == nom,
    orElse: () => throw ArchiveException('Entrée absente.'),
  );
  if (h.uncompressedSize > limite) throw const ArchiveDemesuree();
  final sortie = _SortieLimitee(h.uncompressedSize);
  final fichier = h.file;
  if (fichier == null) throw ArchiveException('Entrée illisible.');
  fichier.decompress(sortie);
  if (sortie.length != h.uncompressedSize) {
    throw ArchiveException('Taille inattendue.');
  }
  return sortie.getBytes();
}

/// Sortie mémoire qui s'arrête net au-delà de [maximum] octets (une
/// archive qui ment sur sa taille ne peut pas remplir la mémoire).
class _SortieLimitee extends OutputMemoryStream {
  _SortieLimitee(this.maximum);

  final int maximum;

  void _verifier(int ajout) {
    if (length + ajout > maximum) throw const ArchiveDemesuree();
  }

  @override
  void writeByte(int value) {
    _verifier(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _verifier(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _verifier(stream.length);
    super.writeStream(stream);
  }
}
