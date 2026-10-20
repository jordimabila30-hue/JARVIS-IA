import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/apprentissage/contenu_pedagogique.dart';
import 'validation_corpus.dart';

/// Un parcours du catalogue, lu (ou non) et validé.
class ParcoursCharge {
  const ParcoursCharge(this.resume, this.contenu, this.erreurs);

  final ResumeParcours resume;

  /// Null : fichier absent ou illisible (la carte reste affichée, vide).
  final Parcours? contenu;
  final List<String> erreurs;

  /// Leçons proposées : seulement les leçons validées, sauf en aperçu de
  /// développement (brouillons compris).
  List<Lecon> leconsVisibles({required bool apercu}) => [
    for (final l in contenu?.lecons ?? const <Lecon>[])
      if (apercu || contenu!.leconValidee(l)) l,
  ];
}

/// Corpus pédagogique hors ligne (`assets/apprentissage/`).
///
/// Jamais lu au démarrage de JARVIS : le premier [charger] (ouverture du
/// module) lit le petit catalogue puis les parcours en parallèle ; le
/// résultat est gardé (aucune relecture). Un JSON de plus de
/// [seuilIsolat] octets est décodé hors du fil de l'interface.
class CatalogueApprentissage {
  CatalogueApprentissage({AssetBundle? bundle, bool? apercu, bool? release})
    : _bundle = bundle ?? rootBundle,
      apercu = _ApercuProtege(
        autorise: !(kReleaseMode || (release ?? false)),
        valeur: apercu ?? apercuDisponible,
      );

  static const fichierCatalogue = 'assets/apprentissage/catalogue.json';
  static const seuilIsolat = 100 * 1024;

  /// Aperçu des fiches en brouillon : réservé au développement (debug,
  /// profile) ; impossible dans une version publiée.
  static bool get apercuDisponible => !kReleaseMode;

  final AssetBundle _bundle;

  /// Brouillons visibles (aperçu de développement). En release, toujours
  /// faux : une demande d'aperçu est ignorée.
  final ValueNotifier<bool> apercu;

  Future<List<ParcoursCharge>>? _chargement;
  List<ParcoursCharge>? _parcours;

  /// Parcours déjà chargés (null avant la fin du premier [charger]).
  List<ParcoursCharge>? get parcours => _parcours;

  Future<List<ParcoursCharge>> charger() => _chargement ??= _lire();

  ParcoursCharge? parcoursDe(String id) {
    for (final p in _parcours ?? const <ParcoursCharge>[]) {
      if (p.resume.id == id) return p;
    }
    return null;
  }

  /// Leçon (id) et son parcours, parmi les leçons visibles.
  (ParcoursCharge, Lecon)? lecon(String id) {
    for (final p in _parcours ?? const <ParcoursCharge>[]) {
      for (final l in p.leconsVisibles(apercu: apercu.value)) {
        if (l.id == id) return (p, l);
      }
    }
    return null;
  }

  Future<List<ParcoursCharge>> _lire() async {
    List<ResumeParcours> resumes;
    try {
      resumes = _resumes(await _json(fichierCatalogue));
    } catch (e) {
      debugPrint('[JARVIS Apprendre] catalogue illisible : $e');
      resumes = const [];
    }
    final charges = await Future.wait(resumes.map(_parcoursDe));
    return _parcours = List.unmodifiable(charges);
  }

  Future<ParcoursCharge> _parcoursDe(ResumeParcours r) async {
    try {
      final v = validerParcours(await _json(r.fichier), r);
      for (final e in v.erreurs) {
        debugPrint('[JARVIS Apprendre] ${r.id} : $e');
      }
      return ParcoursCharge(r, v.parcours, v.erreurs);
    } catch (e) {
      debugPrint('[JARVIS Apprendre] ${r.id} illisible : $e');
      return ParcoursCharge(r, null, ['$e']);
    }
  }

  Future<Object?> _json(String chemin) async {
    final texte = await _bundle.loadString(chemin, cache: false);
    return texte.length > seuilIsolat
        ? compute(jsonDecode, texte)
        : jsonDecode(texte);
  }

  static List<ResumeParcours> _resumes(Object? j) {
    if (j is! Map || j['parcours'] is! List) {
      throw const FormatException('catalogue : « parcours » attendu');
    }
    return [
      for (final p in j['parcours'] as List)
        if (p is Map &&
            p['id'] is String &&
            p['titre'] is String &&
            p['fichier'] is String)
          ResumeParcours(
            id: p['id'] as String,
            titre: p['titre'] as String,
            icone: p['icone'] is String ? p['icone'] as String : '',
            fichier: p['fichier'] as String,
          ),
    ];
  }

  void dispose() => apercu.dispose();
}

/// Aperçu des brouillons qui ne peut pas être activé en release.
class _ApercuProtege extends ValueNotifier<bool> {
  _ApercuProtege({required this.autorise, required bool valeur})
    : super(autorise && valeur);

  final bool autorise;

  @override
  set value(bool v) => super.value = autorise && v;
}
