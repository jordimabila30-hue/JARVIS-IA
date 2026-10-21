import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../models/apparence/fond_photo.dart';
import 'depot_fonds_photo.dart';

DepotFondsPhoto creerDepot() => _DepotFichiers();

/// Photos dans `<support de l'application>/fonds_jarvis/<id>.img` :
/// dossier privé et durable (pas le cache, que le système peut vider).
class _DepotFichiers implements DepotFondsPhoto {
  Directory? _dossier;

  Future<Directory> _racine() async {
    final d = _dossier;
    if (d != null) return d;
    final base = await getApplicationSupportDirectory();
    final dossier = Directory(
      '${base.path}${Platform.pathSeparator}fonds_jarvis',
    );
    await dossier.create(recursive: true);
    return _dossier = dossier;
  }

  Future<File> _fichier(String id) async {
    if (!FondPhoto.estIdValide(id)) throw ArgumentError.value(id, 'id');
    return File('${(await _racine()).path}${Platform.pathSeparator}$id.img');
  }

  @override
  Future<String> enregistrer(Uint8List octets) async {
    final id = DepotFondsPhoto.nouvelId();
    final f = await _fichier(id);
    // Écriture dans un fichier temporaire puis renommage : jamais de photo
    // à moitié écrite.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(octets, flush: true);
    await tmp.rename(f.path);
    return id;
  }

  @override
  Future<Uint8List?> lire(String id) async {
    if (!FondPhoto.estIdValide(id)) return null;
    final f = await _fichier(id);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> supprimer(String id) async {
    if (!FondPhoto.estIdValide(id)) return;
    final f = await _fichier(id);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<String>> lister() async {
    final ids = <String>[];
    await for (final e in (await _racine()).list()) {
      final nom = e.uri.pathSegments.last;
      if (e is File && nom.endsWith('.img')) {
        ids.add(nom.substring(0, nom.length - 4));
      } else if (e is File && nom.endsWith('.tmp')) {
        await e.delete(); // reste d'une écriture interrompue
      }
    }
    return ids;
  }

  @override
  Future<void> nettoyer(Set<String> garder) async {
    for (final id in await lister()) {
      if (!garder.contains(id)) await supprimer(id);
    }
  }
}
