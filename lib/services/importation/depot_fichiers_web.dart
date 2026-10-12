import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import '../../models/importation/export_whatsapp.dart';
import 'depot_fichiers.dart';
import 'selection_export_whatsapp.dart';

/// Navigateur : glisser-déposer sur toute la page. Les fichiers restent
/// des objets du navigateur, lus par tranches (aucun chemin local).
DepotFichiers creerDepotFichiers() => _DepotNavigateur();

class _DepotNavigateur implements DepotFichiers {
  JSFunction? _survol;
  JSFunction? _sortie;
  JSFunction? _depot;

  @override
  bool get disponible => true;

  static bool _avecFichiers(web.DragEvent e) {
    final types = e.dataTransfer?.types.toDart ?? const [];
    return types.any((t) => t.toDart == 'Files');
  }

  @override
  void demarrer({
    required void Function(bool survol) surSurvol,
    required void Function(List<FichierBrut> fichiers) surDepot,
  }) {
    arreter();
    _survol = ((web.DragEvent e) {
      if (!_avecFichiers(e)) return;
      // Sans cela, le navigateur ouvrirait le fichier à la place de la page.
      e.preventDefault();
      e.dataTransfer?.dropEffect = 'copy';
      surSurvol(true);
    }).toJS;
    _sortie = ((web.DragEvent e) {
      // Quitte la fenêtre (relatedTarget nul), pas un élément intérieur.
      if (e.relatedTarget == null) surSurvol(false);
    }).toJS;
    _depot = ((web.DragEvent e) {
      if (!_avecFichiers(e)) return;
      e.preventDefault();
      surSurvol(false);
      final liste = e.dataTransfer?.files;
      if (liste == null) return;
      surDepot([
        for (var i = 0; i < liste.length; i++)
          if (liste.item(i) case final f?) _fichier(f),
      ]);
    }).toJS;
    web.document.addEventListener('dragover', _survol);
    web.document.addEventListener('dragleave', _sortie);
    web.document.addEventListener('drop', _depot);
  }

  @override
  void arreter() {
    if (_survol != null) web.document.removeEventListener('dragover', _survol);
    if (_sortie != null) web.document.removeEventListener('dragleave', _sortie);
    if (_depot != null) web.document.removeEventListener('drop', _depot);
    _survol = _sortie = _depot = null;
  }

  static FichierBrut _fichier(web.File f) => FichierBrut(
    nom: f.name,
    source: SourceReception.glisserDeposer,
    tailleOctets: f.size,
    typeMime: f.type.isEmpty ? null : f.type,
    flux: _lire(f),
  );

  /// Tranches de 1 Mo, lues à la demande.
  static Stream<List<int>> _lire(web.File f) async* {
    const tranche = 1 << 20;
    for (var debut = 0; debut < f.size; debut += tranche) {
      final fin = math.min(debut + tranche, f.size);
      final tampon = await f.slice(debut, fin).arrayBuffer().toDart;
      yield tampon.toDart.asUint8List();
    }
  }
}
