import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/importation/export_whatsapp.dart';
import 'selection_export_whatsapp.dart';

/// Fichiers reçus par un partage Android (« Exporter la discussion » →
/// JARVIS). [fichiers] vide : rien d'exploitable (texte seul…).
class PartageRecu {
  const PartageRecu({required this.id, required this.fichiers});

  /// Identifiant de l'événement de partage (un seul traitement par id).
  final String id;
  final List<FichierBrut> fichiers;
}

/// Partages arrivés de l'extérieur, à prendre une seule fois chacun.
abstract class ReceptionPartages {
  /// Change à chaque nouveau partage en attente.
  ValueListenable<int> get annonces;

  /// Le partage en attente (retiré de la file), ou null.
  Future<PartageRecu?> prendre();
}

/// Aucune réception (Windows, Web, iOS, tests).
class AucuneReceptionPartages implements ReceptionPartages {
  const AucuneReceptionPartages();
  static final _jamais = ValueNotifier(0);
  @override
  ValueListenable<int> get annonces => _jamais;
  @override
  Future<PartageRecu?> prendre() async => null;
}

/// Pont avec `MainActivity` (Android) : sélecteur de documents et
/// partages reçus. Les fichiers restent des `content://` lus en flux
/// (aucun chemin, aucune copie, aucune permission de stockage) ; le droit
/// de lecture accordé par l'application qui partage suffit.
class PontAndroidImportation implements ReceptionPartages {
  PontAndroidImportation._() {
    _canal.setMethodCallHandler((appel) async {
      if (appel.method == 'partageDisponible') _annonces.value++;
    });
  }

  static final instance = PontAndroidImportation._();

  /// Réception adaptée à la plateforme.
  static ReceptionPartages get reception =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? instance
      : const AucuneReceptionPartages();

  static const _canal = MethodChannel('jarvis/importation');

  // Démarre à 1 : un partage a pu arriver avant le démarrage de Flutter
  // (lancement à froid) ; [prendre] le dira.
  final _annonces = ValueNotifier(1);
  final _dejaPris = <String>{};

  @override
  ValueListenable<int> get annonces => _annonces;

  @override
  Future<PartageRecu?> prendre() async {
    final Map<Object?, Object?>? brut;
    try {
      brut = await _canal.invokeMapMethod<Object?, Object?>('prendrePartage');
    } on MissingPluginException {
      return null;
    }
    if (brut == null) return null;
    final id = brut['id']! as String;
    // Le natif ne rend un partage qu'une fois ; ceci protège en plus d'un
    // événement rejoué.
    if (!_dejaPris.add(id)) return null;
    final fichiers = (brut['fichiers']! as List<Object?>)
        .cast<Map<Object?, Object?>>()
        .map((f) => _fichier(f, SourceReception.partageAndroid))
        .toList();
    return PartageRecu(id: id, fichiers: fichiers);
  }

  /// Dossier de cache privé de JARVIS (copie temporaire d'un export).
  Future<String> dossierTemporaire() async =>
      (await _canal.invokeMethod<String>('dossierTemporaire'))!;

  /// Ouvre WhatsApp (l'export se lance là-bas) ; false s'il est absent.
  Future<bool> ouvrirWhatsApp() async {
    try {
      return await _canal.invokeMethod<bool>('ouvrirWhatsApp') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Sélecteur de documents Android ; null si fermé sans choix.
  Future<FichierBrut?> choisirFichier() async {
    final brut = await _canal.invokeMapMethod<Object?, Object?>(
      'choisirFichier',
    );
    return brut == null ? null : _fichier(brut, SourceReception.selecteur);
  }

  FichierBrut _fichier(Map<Object?, Object?> f, SourceReception source) {
    final ref = f['ref']! as String;
    return FichierBrut(
      nom: (f['nom'] as String?) ?? 'Fichier partagé',
      source: source,
      tailleOctets: f['taille'] as int?,
      typeMime: f['mime'] as String?,
      flux: _lire(ref),
    );
  }

  /// Contenu lu par morceaux à l'écoute ; fermé dès l'arrêt de l'écoute.
  Stream<List<int>> _lire(String ref) async* {
    final session = await _canal.invokeMethod<int>('ouvrirLecture', ref);
    try {
      while (true) {
        final morceau = await _canal.invokeMethod<Uint8List>('lire', session);
        if (morceau == null) break;
        yield morceau;
      }
    } finally {
      await _canal.invokeMethod<void>('fermerLecture', session);
    }
  }
}
