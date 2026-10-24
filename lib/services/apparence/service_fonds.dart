import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../models/apparence/fond_photo.dart';
import '../voice_settings_service.dart';
import 'depot_fonds_photo.dart';
import 'service_apparence.dart';

/// Fonds de JARVIS au-delà du fond général : le fond propre à une
/// conversation (motif ou photo), et la vie des photos dans le dépôt local
/// (import, lecture, nettoyage de celles qui ne servent plus).
///
/// Règle d'affichage : fond de la conversation, sinon fond général
/// (`ServiceApparence.fondGeneral`), qui vaut lui-même le fond JARVIS tant
/// que rien n'est choisi. Les associations sont enregistrées sur l'appareil
/// (clé [cleStockage]) par identifiant de conversation (l'UUID serveur
/// quand il existe : il ne change pas d'un appareil à l'autre ni au
/// redémarrage). Aucune photo ne quitte l'appareil.
class ServiceFonds extends ChangeNotifier {
  ServiceFonds({
    required this.apparence,
    DepotFondsPhoto? depot,
    StockageReglages? stockage,
  }) : depot = depot ?? DepotFondsPhoto(),
       _stockage = stockage ?? const StockagePreferences(cle: cleStockage);

  static const cleStockage = 'jarvis.fonds_conversations';

  final ServiceApparence apparence;
  final DepotFondsPhoto depot;
  final StockageReglages _stockage;

  final _fonds = <String, FondChoisi>{};

  /// Clarté (0 noir, 1 blanc) du fond photo réellement affiché sur
  /// l'accueil, mesurée une fois à la composition ; null : pas de photo.
  /// Le texte posé directement sur le fond (salutation) s'y adapte.
  final clarteFondPhoto = ValueNotifier<double?>(null);

  @override
  void dispose() {
    clarteFondPhoto.dispose();
    super.dispose();
  }

  /// Photos importées pas encore attribuées : jamais nettoyées.
  final _proteges = <String>{};

  /// Lit les fonds par conversation (illisible → aucun), puis retire du
  /// dépôt les photos que plus rien n'utilise.
  Future<void> charger() async {
    try {
      final texte = await _stockage.lire();
      final brut = texte == null ? null : jsonDecode(texte);
      if (brut is Map) {
        for (final e in brut.entries) {
          final fond = FondChoisi.depuisJson(e.value);
          if (e.key is String && fond != null) _fonds[e.key as String] = fond;
        }
      }
    } catch (e) {
      debugPrint('[JARVIS Fonds] fonds illisibles : $e');
    }
    notifyListeners();
    await nettoyer();
  }

  /// Fond propre à la première de ces conversations qui en a un (null :
  /// fond général).
  FondChoisi? fondDe(Iterable<String?> ids) {
    for (final id in ids) {
      final fond = id == null ? null : _fonds[id];
      if (fond != null) return fond;
    }
    return null;
  }

  /// Fond affiché pour ces identifiants de conversation.
  FondChoisi fondAffiche(Iterable<String?> ids) =>
      fondDe(ids) ?? apparence.fondGeneral;

  /// Définit le fond d'une conversation ; null : retour au fond général.
  Future<void> definir(String id, FondChoisi? fond) async {
    if (fond == null) {
      if (_fonds.remove(id) == null) return;
    } else {
      _fonds[id] = fond;
      if (fond case FondPhotoChoisi(:final photo)) _proteges.remove(photo.id);
    }
    notifyListeners();
    await _ecrire();
    await nettoyer();
  }

  /// Photo de « Ma galerie » choisie comme fond général.
  Future<void> definirGeneral(FondPhoto photo) async {
    await apparence.choisirPhoto(photo);
    _proteges.remove(photo.id);
    await nettoyer();
  }

  /// Range une photo choisie par l'utilisateur ; protégée du nettoyage
  /// jusqu'à son attribution (ou [abandonner]).
  Future<String> importer(Uint8List octets) async {
    if (octets.length > DepotFondsPhoto.tailleMax) {
      throw const FormatException('Photo trop lourde (25 Mo au plus).');
    }
    final id = await depot.enregistrer(octets);
    _proteges.add(id);
    return id;
  }

  /// Garde une photo du nettoyage (ex. celle que « Revenir » peut rendre),
  /// jusqu'à [abandonner].
  void proteger(String id) => _proteges.add(id);

  /// Photo importée puis annulée (ou protection levée) : supprimée si plus
  /// rien ne l'utilise.
  Future<void> abandonner(String id) async {
    _proteges.remove(id);
    await nettoyer();
  }

  /// Supprime du dépôt les photos que plus rien n'utilise (fond général,
  /// même inactif ; fonds des conversations ; imports en cours).
  Future<void> nettoyer() async {
    final garder = <String>{..._proteges};
    if (apparence.photo case final p?) garder.add(p.id);
    for (final f in _fonds.values) {
      if (f case FondPhotoChoisi(:final photo)) garder.add(photo.id);
    }
    try {
      await depot.nettoyer(garder);
    } catch (e) {
      debugPrint('[JARVIS Fonds] nettoyage impossible : $e');
    }
  }

  Future<void> _ecrire() async {
    try {
      await _stockage.ecrire(
        jsonEncode({for (final e in _fonds.entries) e.key: e.value.versJson()}),
      );
    } catch (e) {
      debugPrint('[JARVIS Fonds] fonds non enregistrés : $e');
    }
  }

  /// Service de l'application (null hors [PorteeFonds], ex. tests).
  static ServiceFonds? of(BuildContext context, {bool ecouter = true}) =>
      ecouter
      ? context.dependOnInheritedWidgetOfExactType<PorteeFonds>()?.notifier
      : context.getInheritedWidgetOfExactType<PorteeFonds>()?.notifier;
}

/// Rend le [ServiceFonds] accessible à l'arbre.
class PorteeFonds extends InheritedNotifier<ServiceFonds> {
  const PorteeFonds({
    super.key,
    required ServiceFonds service,
    required super.child,
  }) : super(notifier: service);
}
