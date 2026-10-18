import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/voice_settings.dart';
import 'peripheriques_audio.dart';
import 'tts_service.dart';

/// Où les réglages sont conservés entre deux lancements.
abstract class StockageReglages {
  Future<String?> lire();
  Future<void> ecrire(String valeur);
}

/// Stockage local de l'appareil (SharedPreferences : localStorage sur le
/// Web, préférences du système ailleurs).
class StockagePreferences implements StockageReglages {
  const StockagePreferences({this.cle = cleReglagesVocaux});

  static const cleReglagesVocaux = 'jarvis.reglages_vocaux';

  /// Clé de la préférence (une par réglage enregistré).
  final String cle;

  @override
  Future<String?> lire() async =>
      (await SharedPreferences.getInstance()).getString(cle);

  @override
  Future<void> ecrire(String valeur) async =>
      (await SharedPreferences.getInstance()).setString(cle, valeur);
}

/// Stockage en mémoire (tests).
class StockageMemoire implements StockageReglages {
  StockageMemoire([this.valeur]);

  String? valeur;
  int ecritures = 0;

  @override
  Future<String?> lire() async => valeur;

  @override
  Future<void> ecrire(String v) async {
    valeur = v;
    ecritures++;
  }
}

/// Réglages du chat vocal : source de vérité unique.
///
/// Chaque modification met à jour [reglages], prévient les écouteurs
/// (panneau Paramètres) et est enregistrée automatiquement. La synthèse
/// vocale lit [reglages] avant chaque prise de parole : un changement
/// s'entend dès la phrase suivante.
class VoiceSettingsService extends ChangeNotifier {
  VoiceSettingsService({
    TtsService? tts,
    StockageReglages? stockage,
    PeripheriquesAudio? peripheriques,
    this.delaiSauvegarde = const Duration(milliseconds: 350),
  }) : tts = tts ?? TtsService(),
       _stockage = stockage ?? StockagePreferences(),
       _peripheriques = peripheriques ?? PeripheriquesAudio();

  final TtsService tts;
  final StockageReglages _stockage;
  final PeripheriquesAudio _peripheriques;

  /// Les curseurs envoient beaucoup de valeurs : on regroupe les écritures.
  final Duration delaiSauvegarde;

  VoiceSettings _reglages = VoiceSettings.defaut;
  VoiceSettings get reglages => _reglages;

  /// Voix et micros réellement disponibles (vides tant qu'ils ne sont pas
  /// chargés, ou si la plateforme n'en fournit pas).
  List<VoixDisponible> voix = const [];
  List<MicroDisponible> micros = const [];
  bool capacitesChargees = false;

  bool get choixMicroPossible => _peripheriques.choixPossible;

  /// Incrémenté à chaque sauvegarde réussie (indicateur « Enregistré »).
  final sauvegardes = ValueNotifier<int>(0);

  bool _charge = false;
  Timer? _minuteur;

  // --- Chargement --------------------------------------------------------

  /// Lit les réglages enregistrés (valeurs par défaut sûres sinon).
  Future<void> charger() async {
    if (_charge) return;
    _charge = true;
    try {
      final brut = await _stockage.lire();
      if (brut != null) {
        final json = jsonDecode(brut);
        if (json is Map<String, Object?>) {
          _reglages = VoiceSettings.fromJson(json);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[JARVIS réglages] lecture impossible : $e');
    }
  }

  /// Charge les voix et les micros disponibles (à l'ouverture du panneau).
  Future<void> chargerCapacites() async {
    voix = await tts.voixDisponibles();
    micros = await _peripheriques.lister();
    capacitesChargees = true;
    // Micro enregistré qui n'existe plus : retour au micro par défaut.
    final id = _reglages.microphoneId;
    if (id != null && micros.isNotEmpty && !micros.any((m) => m.id == id)) {
      _reglages = _reglages.copyWith(microphoneId: () => null);
    }
    notifyListeners();
  }

  /// Demande l'accès au micro (Web) puis relit la liste avec les noms.
  Future<void> autoriserMicros() async {
    if (await _peripheriques.autoriser()) {
      micros = await _peripheriques.lister();
      notifyListeners();
    }
  }

  // --- Langues et voix ----------------------------------------------------

  /// Locales qui ont au moins une voix. Le français d'abord. Sans aucune
  /// voix connue, seule la locale actuelle est proposée (voix système).
  List<String> get locales {
    final liste = {for (final v in voix) v.locale}.toList();
    if (liste.isEmpty) return [_reglages.locale];
    liste.sort((a, b) {
      final fa = a.startsWith('fr'), fb = b.startsWith('fr');
      if (fa != fb) return fa ? -1 : 1;
      if (a == 'fr-FR') return -1;
      if (b == 'fr-FR') return 1;
      return a.compareTo(b);
    });
    return liste;
  }

  /// Langues proposées, dans cet ordre (codes ISO).
  static const languesJarvis = ['fr', 'en', 'de', 'es'];

  /// Région utilisée par défaut pour chaque langue.
  static const _regionParDefaut = {
    'fr': 'fr-FR',
    'en': 'en-US',
    'de': 'de-DE',
    'es': 'es-ES',
  };

  /// Langue de la locale choisie (« fr-CA » → « fr »).
  String get langue => _reglages.locale.split('-').first;

  /// Langues de JARVIS qui ont au moins une voix (français d'abord). Sans
  /// voix connue, seule la langue actuelle est proposée (voix système).
  List<String> get langues {
    final presentes = {for (final v in voix) v.locale.split('-').first};
    final liste = [
      for (final l in languesJarvis)
        if (presentes.contains(l)) l,
    ];
    if (!liste.contains(langue) && (liste.isEmpty || voix.isEmpty)) {
      liste.insert(0, langue);
    }
    return liste;
  }

  /// Voix de la langue choisie, toutes régions : la région par défaut
  /// d'abord, puis les autres ; par nom dans chaque région.
  List<VoixDisponible> get voixDeLaLangue {
    final principale = _regionParDefaut[langue];
    return voix.where((v) => v.locale.split('-').first == langue).toList()
      ..sort((a, b) {
        final pa = a.locale == principale, pb = b.locale == principale;
        if (pa != pb) return pa ? -1 : 1;
        final l = a.locale.compareTo(b.locale);
        return l != 0 ? l : a.nom.compareTo(b.nom);
      });
  }

  /// Nouvelle langue : la région actuelle est gardée si elle est déjà dans
  /// cette langue ; sinon la région par défaut si elle a une voix, sinon
  /// la première région disponible.
  void choisirLangue(String code) {
    if (code == langue) return;
    final disponibles = {
      for (final v in voix)
        if (v.locale.split('-').first == code) v.locale,
    };
    final defaut = _regionParDefaut[code] ?? code;
    final locale = disponibles.contains(defaut) || disponibles.isEmpty
        ? defaut
        : (disponibles.toList()..sort()).first;
    choisirLocale(locale);
  }

  /// Choix d'une voix précise : sa région devient l'accent utilisé.
  void choisirVoixDisponible(VoixDisponible v) =>
      _mettreAJour(_reglages.copyWith(locale: v.locale, voix: () => v.nom));

  /// Voix de la locale choisie.
  List<VoixDisponible> get voixDeLaLocale =>
      voix.where((v) => v.locale == _reglages.locale).toList()
        ..sort((a, b) => a.nom.compareTo(b.nom));

  /// Voix qui sera réellement utilisée (null = voix système par défaut).
  VoixDisponible? get voixEffective => TtsService.voixPour(_reglages, voix);

  // --- Modifications (appliquées et enregistrées automatiquement) ---------

  void _mettreAJour(VoiceSettings nouveaux) {
    if (nouveaux == _reglages) return;
    _reglages = nouveaux;
    notifyListeners();
    _minuteur?.cancel();
    _minuteur = Timer(delaiSauvegarde, enregistrer);
  }

  /// Écrit tout de suite les réglages (aussi appelé à la fermeture).
  Future<void> enregistrer() async {
    _minuteur?.cancel();
    try {
      await _stockage.ecrire(jsonEncode(_reglages.toJson()));
      sauvegardes.value++;
    } catch (e) {
      debugPrint('[JARVIS réglages] écriture impossible : $e');
    }
  }

  void choisirProfil(ProfilVocal p) => _mettreAJour(_reglages.avecProfil(p));

  /// Nouvelle locale : la voix choisie est gardée si elle existe dans
  /// cette locale, sinon une voix valide est prise automatiquement.
  void choisirLocale(String locale) {
    final garder = voix.any(
      (v) => v.locale == locale && v.nom == _reglages.voix,
    );
    var r = _reglages.copyWith(locale: locale, voix: () => null);
    if (garder) r = r.copyWith(voix: () => _reglages.voix);
    final effective = TtsService.voixPour(r, voix);
    _mettreAJour(r.copyWith(voix: () => effective?.nom));
  }

  void choisirVoix(String? nom) =>
      _mettreAJour(_reglages.copyWith(voix: () => nom));

  void choisirVitesse(double v) =>
      _mettreAJour(_reglages.avecReglageManuel(vitesse: v));

  void choisirHauteur(double h) =>
      _mettreAJour(_reglages.avecReglageManuel(hauteur: h));

  void choisirVolume(double v) => _mettreAJour(_reglages.copyWith(volume: v));

  void choisirMicro(String? id) =>
      _mettreAJour(_reglages.copyWith(microphoneId: () => id));

  void choisirReponseAutomatique(bool actif) =>
      _mettreAJour(_reglages.copyWith(reponseAutomatique: actif));

  /// Un mode indisponible (automatique non validé) n'est jamais choisi.
  void choisirInterruption(ModeInterruption m) {
    if (m.disponible) _mettreAJour(_reglages.copyWith(interruption: m));
  }

  @override
  void dispose() {
    if (_minuteur?.isActive ?? false) enregistrer();
    _minuteur?.cancel();
    sauvegardes.dispose();
    super.dispose();
  }
}
