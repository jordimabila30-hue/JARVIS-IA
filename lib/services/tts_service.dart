import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/voice_settings.dart';

/// Paramètres envoyés au moteur de synthèse d'une plateforme.
typedef ParametresMoteur = ({double debit, double hauteur, double volume});

/// Issue d'une prise de parole.
enum IssueParole {
  /// La phrase a été lue jusqu'au bout.
  lue,

  /// Arrêtée avant la fin ([TtsService.arreter]).
  interrompue,

  /// Aucune voix n'a pu la lire (voir [ResultatParole.message]).
  echec,
}

/// Résultat de [TtsService.parler].
class ResultatParole {
  const ResultatParole(this.issue, [this.message]);

  static const lue = ResultatParole(IssueParole.lue);
  static const interrompue = ResultatParole(IssueParole.interrompue);

  final IssueParole issue;

  /// Explication utile quand la lecture a échoué.
  final String? message;

  bool get reussie => issue != IssueParole.echec;
}

/// Synthèse vocale de JARVIS.
///
/// Les réglages ([VoiceSettings]) sont appliqués avant chaque prise de
/// parole avec [appliquer] : voix, langue, débit, hauteur, volume. Une voix
/// enregistrée sur une autre plateforme (une voix du navigateur sur
/// Android…) n'est jamais envoyée telle quelle : on retombe sur une voix
/// réellement disponible.
///
/// [parler] suit les signaux du moteur (début, fin, erreur) au lieu
/// d'attendre simplement `speak()` : sur Android, une lecture qui échoue ne
/// termine jamais ce `Future`, et un nouveau `speak()` serait alors refusé
/// en silence.
class TtsService {
  final _tts = FlutterTts();
  bool _initialise = false;
  List<VoixDisponible>? _voix;

  /// Nom de la voix réellement utilisée (pour information / débogage).
  String? voiceChoisie;

  // Lecture en cours : prévenue par les signaux du moteur.
  Completer<IssueParole>? _fin;
  void Function()? _surDebut;
  bool _demarree = false;

  /// Réglages de la dernière [appliquer] (pour réessayer avec la voix
  /// système en gardant la langue).
  VoiceSettings? _reglages;

  static void _log(String message) {
    if (kDebugMode) debugPrint('[JARVIS TTS] $message');
  }

  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialiser() async {
    if (_initialise) return;
    _initialise = true;
    _log('initialize');
    try {
      // Fin de lecture suivie par les signaux ci-dessous : avec l'attente
      // intégrée, une erreur Android laisserait le moteur « occupé ».
      await _tts.awaitSpeakCompletion(false);
      _tts
        ..setStartHandler(() {
          _log('start');
          _demarree = true;
          _surDebut?.call();
        })
        ..setCompletionHandler(() {
          _log('complete');
          if (_signalPerime) return;
          _terminer(IssueParole.lue);
        })
        ..setCancelHandler(() {
          _log('cancel');
          if (_signalPerime) return;
          _terminer(IssueParole.interrompue);
        })
        ..setErrorHandler((message) {
          _log('error = $message');
          _terminer(IssueParole.echec);
        });
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        _log('moteur = ${await _tts.getDefaultEngine}');
      }
    } catch (e) {
      _log('initialisation partielle : $e');
    }
  }

  /// Sur téléphone, une fin ou une annulation reçue avant le début de la
  /// lecture en cours vient de la lecture précédente (arrêtée) : ignorée.
  bool get _signalPerime => _mobile && !_demarree;

  void _terminer(IssueParole issue) {
    final fin = _fin;
    if (fin != null && !fin.isCompleted) fin.complete(issue);
  }

  /// Débit « normal » de chaque moteur : 1.0 pour le navigateur (Web
  /// Speech) ; 0.5 pour Android (le plugin double la valeur : 1.0 natif) et
  /// iOS (AVSpeech : 0.5 = débit par défaut) ; Windows ajoute 0.5.
  static ParametresMoteur parametresMoteur(
    VoiceSettings r, {
    required bool web,
    required TargetPlatform plateforme,
  }) {
    final double debit;
    if (web) {
      debit = r.vitesse;
    } else if (plateforme == TargetPlatform.windows) {
      // Windows : vitesse réelle = débit + 0,5.
      debit = r.vitesse - 0.5;
    } else {
      debit = 0.5 * r.vitesse;
    }
    // Hauteur : 1.0 = normale partout (Android accepte 0.5 à 2.0).
    // Volume : 0 à 1 partout.
    return (
      debit: debit,
      hauteur: (1 + r.hauteur).clamp(0.5, 2.0),
      volume: r.volume.clamp(0.0, 1.0),
    );
  }

  /// Voix réellement disponibles. Sur le Web, le navigateur charge ses
  /// voix en différé : on réessaie quelques fois avant de conclure.
  Future<List<VoixDisponible>> voixDisponibles({
    bool rafraichir = false,
  }) async {
    if (_voix != null && !rafraichir) return _voix!;
    var liste = <VoixDisponible>[];
    for (var essai = 0; essai < (kIsWeb ? 6 : 1); essai++) {
      try {
        liste = lireVoix(await _tts.getVoices);
      } catch (_) {
        liste = [];
      }
      if (liste.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    // Liste vide : on ne la garde pas en cache, un prochain appel retentera.
    if (liste.isNotEmpty) _voix = liste;
    return liste;
  }

  /// Convertit la réponse brute du plugin (liste de maps) en voix.
  static List<VoixDisponible> lireVoix(Object? brut) {
    if (brut is! List) return const [];
    final resultat = <VoixDisponible>[];
    final vus = <String>{};
    for (final v in brut) {
      if (v is! Map) continue;
      final nom = '${v['name'] ?? ''}'.trim();
      final locale = normaliserLocale('${v['locale'] ?? ''}');
      if (nom.isEmpty || locale.isEmpty || !vus.add('$nom|$locale')) continue;
      final reseau = '${v['network_required'] ?? ''}';
      final qualite = v['quality'];
      resultat.add(
        VoixDisponible(
          nom: nom,
          locale: locale,
          enLigne: reseau == '1' || reseau == 'true',
          qualite: qualite == null ? null : '$qualite',
        ),
      );
    }
    return resultat;
  }

  /// « fr_fr » ou « FR-fr » → « fr-FR ».
  static String normaliserLocale(String locale) {
    final parties = locale.replaceAll('_', '-').split('-');
    if (parties.first.isEmpty) return '';
    final langue = parties.first.toLowerCase();
    if (parties.length < 2 || parties[1].isEmpty) return langue;
    return '$langue-${parties[1].toUpperCase()}';
  }

  /// Voix utilisée pour [r] parmi [voix] :
  /// 1. la voix choisie, si elle existe pour cette locale ;
  /// 2. sinon une autre voix de la locale (locale exacte, voix locale
  ///    plutôt qu'en ligne, puis ordre alphabétique pour toujours retomber
  ///    sur la même), puis une voix de la même langue ;
  /// 3. sinon null : voix système par défaut.
  static VoixDisponible? voixPour(VoiceSettings r, List<VoixDisponible> voix) {
    final compatibles = voix.where((v) => v.locale == r.locale).toList();
    final langue = r.locale.split('-').first;
    final candidates = compatibles.isNotEmpty
        ? compatibles
        : voix.where((v) => v.locale.split('-').first == langue).toList();
    if (candidates.isEmpty) return null;
    for (final v in candidates) {
      if (v.nom == r.voix) return v;
    }
    candidates.sort((a, b) {
      if (a.enLigne != b.enLigne) return a.enLigne ? 1 : -1;
      return a.nom.compareTo(b.nom);
    });
    return candidates.first;
  }

  /// Applique les réglages au moteur ; à appeler avant de parler.
  Future<void> appliquer(VoiceSettings r) async {
    await initialiser();
    _reglages = r;
    final p = parametresMoteur(
      r,
      web: kIsWeb,
      plateforme: defaultTargetPlatform,
    );
    try {
      _log('locale = ${r.locale} -> ${await _tts.setLanguage(r.locale)}');
      final disponibles = await voixDisponibles();
      _log('voix demandée = ${r.voix ?? '(automatique)'}');
      final voix = voixPour(r, disponibles);
      _log('voix disponible = ${voix?.nom ?? '(aucune : voix système)'}');
      voiceChoisie = null;
      if (voix != null) {
        final ok = await _tts.setVoice({
          'name': voix.nom,
          'locale': voix.locale,
        });
        // Le Web renvoie null, les autres 1 en cas de succès.
        if (ok == 0) {
          _log('voix refusée par le moteur : voix système');
          await _voixSysteme(r.locale);
        } else {
          voiceChoisie = voix.nom;
        }
      }
      _log('voix appliquée = ${voiceChoisie ?? '(voix système)'}');
      _log('rate = ${p.debit} -> ${await _tts.setSpeechRate(p.debit)}');
      _log('pitch = ${p.hauteur} -> ${await _tts.setPitch(p.hauteur)}');
      _log('volume = ${p.volume} -> ${await _tts.setVolume(p.volume)}');
    } catch (e) {
      // Réglage refusé par le moteur : il garde ses valeurs par défaut.
      _log('réglage refusé : $e');
    }
  }

  /// Voix par défaut du moteur, dans la langue demandée.
  Future<void> _voixSysteme(String locale) async {
    voiceChoisie = null;
    try {
      await _tts.clearVoice();
    } catch (_) {
      // Non pris en charge (Web) : la langue suffit.
    }
    try {
      await _tts.setLanguage(locale);
    } catch (_) {}
  }

  /// Prononce [texte] et se termine quand la voix a fini.
  ///
  /// [surDebut] est appelé quand le son commence réellement ; [surMot]
  /// reçoit la position (début, fin) de chaque mot quand la plateforme le
  /// signale. Si la lecture ne démarre pas avec la voix choisie, une
  /// seconde tentative est faite avec la voix système.
  Future<ResultatParole> parler(
    String texte, {
    void Function(int debut, int fin)? surMot,
    void Function()? surDebut,
  }) async {
    await initialiser();
    _tts.setProgressHandler((_, debut, fin, _) => surMot?.call(debut, fin));
    var issue = await _essayer(texte, surDebut);
    if (issue == IssueParole.echec && voiceChoisie != null) {
      _log('nouvel essai avec la voix système');
      await _voixSysteme(_reglages?.locale ?? 'fr-FR');
      issue = await _essayer(texte, surDebut);
    }
    return switch (issue) {
      IssueParole.lue => ResultatParole.lue,
      IssueParole.interrompue => ResultatParole.interrompue,
      IssueParole.echec => const ResultatParole(
        IssueParole.echec,
        'La synthèse vocale ne répond pas. Vérifiez qu’une voix française '
        'est installée et que le volume multimédia n’est pas coupé.',
      ),
    };
  }

  Future<IssueParole> _essayer(String texte, void Function()? surDebut) async {
    // Une lecture précédente encore en cours est arrêtée d'abord.
    if (_fin != null && !_fin!.isCompleted) await arreter();
    final fin = _fin = Completer<IssueParole>();
    _demarree = false;
    _surDebut = surDebut;
    _log('speak');
    try {
      final retour = await _tts.speak(texte);
      // Android et iOS : 1 = accepté. Le Web ne renvoie rien.
      if (retour == 0) {
        _log('speak refusé par le moteur');
        _terminer(IssueParole.echec);
      }
    } catch (e) {
      _log('error = $e');
      _terminer(IssueParole.echec);
    }

    // Sur téléphone, le son commence en moins d'une seconde : sans signal
    // de début, la lecture n'a pas eu lieu.
    if (_mobile) {
      final debut = await Future.any([
        fin.future,
        Future<IssueParole?>.delayed(const Duration(seconds: 4), () => null),
      ]);
      if (debut == null && !_demarree) {
        _log('aucun signal de début : lecture considérée comme échouée');
        await arreter();
        _terminer(IssueParole.echec);
      }
    }

    // Fin signalée par le moteur, ou délai de sécurité si une plateforme
    // ne la signale pas.
    final securite = Duration(milliseconds: 4000 + texte.length * 120);
    final issue = await fin.future.timeout(
      securite,
      onTimeout: () {
        _log('fin non signalée : on continue');
        return _demarree || !_mobile ? IssueParole.lue : IssueParole.echec;
      },
    );
    _surDebut = null;
    return issue;
  }

  Future<void> arreter() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _terminer(IssueParole.interrompue);
  }
}
