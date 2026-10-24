import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'depot_fonds_photo.dart';

DepotFondsPhoto creerDepot() => _DepotIndexedDb();

/// Photos dans IndexedDB (base `jarvis_fonds`, magasin `fonds`) : durable,
/// sans la limite de 5 Mo du stockage local, propre à cette origine.
class _DepotIndexedDb implements DepotFondsPhoto {
  static const _base = 'jarvis_fonds', _magasin = 'fonds';

  Future<web.IDBDatabase>? _ouverture;

  Future<web.IDBDatabase> _db() => _ouverture ??= () {
    final fini = Completer<web.IDBDatabase>();
    final requete = web.window.indexedDB.open(_base, 1);
    requete.onupgradeneeded = ((web.Event _) {
      final db = requete.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_magasin)) {
        db.createObjectStore(_magasin);
      }
    }).toJS;
    requete.onsuccess = ((web.Event _) {
      fini.complete(requete.result as web.IDBDatabase);
    }).toJS;
    requete.onerror = ((web.Event _) {
      _ouverture = null;
      fini.completeError(StateError('IndexedDB indisponible'));
    }).toJS;
    return fini.future;
  }();

  Future<JSAny?> _attendre(web.IDBRequest r) {
    final fini = Completer<JSAny?>();
    r.onsuccess = ((web.Event _) => fini.complete(r.result)).toJS;
    r.onerror = ((web.Event _) => fini.completeError(
      StateError('IndexedDB : échec'),
    )).toJS;
    return fini.future;
  }

  Future<web.IDBObjectStore> _store(String mode) async =>
      (await _db()).transaction(_magasin.toJS, mode).objectStore(_magasin);

  @override
  Future<String> enregistrer(Uint8List octets) async {
    final id = DepotFondsPhoto.nouvelId();
    await _attendre((await _store('readwrite')).put(octets.toJS, id.toJS));
    return id;
  }

  @override
  Future<Uint8List?> lire(String id) async {
    final r = await _attendre((await _store('readonly')).get(id.toJS));
    if (r == null || !r.isA<JSUint8Array>()) return null;
    return (r as JSUint8Array).toDart;
  }

  @override
  Future<void> supprimer(String id) async {
    await _attendre((await _store('readwrite')).delete(id.toJS));
  }

  @override
  Future<List<String>> lister() async {
    final r = await _attendre((await _store('readonly')).getAllKeys());
    if (r == null) return const [];
    return [
      for (final k in (r as JSArray<JSAny?>).toDart)
        if (k != null && k.isA<JSString>()) (k as JSString).toDart,
    ];
  }

  @override
  Future<void> nettoyer(Set<String> garder) async {
    for (final id in await lister()) {
      if (!garder.contains(id)) await supprimer(id);
    }
  }
}
