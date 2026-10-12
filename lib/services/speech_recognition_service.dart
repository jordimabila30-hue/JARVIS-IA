import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'reconnaissance_navigateur.dart';

/// Pourquoi la reconnaissance vocale n'a pas pu démarrer ou s'est arrêtée.
enum ErreurReconnaissance {
  /// Accès au micro refusé (navigateur, système ou réglages).
  permission,

  /// Pas de reconnaissance vocale sur cet appareil ou ce navigateur.
  indisponible,

  /// Le service de reconnaissance (en ligne) ne répond pas.
  reseau,

  /// Le français n'est pas pris en charge par le service.
  langue,

  /// Rien compris ou silence (Android : `error_no_match`,
  /// `error_speech_timeout`) : on réécoute simplement.
  rienEntendu,

  /// Requête refusée par le moteur (Android : `error_client`,
  /// `error_busy`) : écoute arrêtée en cours ou relancée avant la vraie fin
  /// de la précédente. Passager : on réécoute après une courte pause.
  client,

  /// Autre problème (micro occupé…).
  autre,
}

/// Classement d'une erreur Android de speech_to_text. (Le drapeau
/// « permanente » du plugin n'est pas fiable : il vaut vrai même pour un
/// simple silence.)
ErreurReconnaissance classerErreurAndroid(String code) => switch (code) {
  'error_no_match' ||
  'error_speech_timeout' => ErreurReconnaissance.rienEntendu,
  'error_client' ||
  'error_busy' ||
  'error_recognizer_busy' ||
  'error_too_many_requests' => ErreurReconnaissance.client,
  'error_permission' ||
  'error_insufficient_permissions' => ErreurReconnaissance.permission,
  'error_audio_error' => ErreurReconnaissance.indisponible,
  'error_network' ||
  'error_network_timeout' ||
  'error_server' ||
  'error_server_disconnected' => ErreurReconnaissance.reseau,
  'error_language_not_supported' ||
  'error_language_unavailable' => ErreurReconnaissance.langue,
  _ => ErreurReconnaissance.autre,
};

/// Reconnaissance vocale en français : API Web Speech directe sur le Web
/// ([ReconnaissanceNavigateur]), plugin speech_to_text ailleurs.
///
/// Hors Web, une seule écoute existe à la fois : [ecouter] attend que la
/// précédente soit réellement terminée par le moteur (sinon Android répond
/// `error_client`), chaque écoute rend une seule issue (phrase, erreur ou
/// fin sans résultat), et les signaux d'une écoute annulée sont ignorés.
class SpeechRecognitionService {
  static const _langue = 'fr-FR';

  /// Diagnostic sur appareil (débogage seulement) : phrase « entendue »
  /// pendant une vraie écoute, pour tester la suite du cycle vocal sans
  /// parler (`--dart-define=JARVIS_DIAG_PHRASE=Bonsoir Jarvis`).
  static const _phraseDiagnostic = String.fromEnvironment('JARVIS_DIAG_PHRASE');
  int _injections = 0;

  final _stt = SpeechToText();
  final ReconnaissanceNavigateur? _navigateur = kIsWeb
      ? ReconnaissanceNavigateur.creer()
      : null;
  bool _initialise = false;
  String? _localeFrancaise;

  // Écoute courante : numéro, issue déjà rendue, moteur réellement actif.
  int _numero = 0;
  bool _terminee = true;
  bool _actif = false;
  Completer<void>? _arretMoteur;
  Timer? _surveillance;

  void Function(ErreurReconnaissance erreur)? _surErreur;
  void Function()? _surFinSansResultat;

  // Bornes adaptatives : chaque plateforme renvoie le niveau sonore dans
  // une échelle différente (dB négatifs sur iOS, environ -2..10 sur Android).
  double _niveauMin = double.infinity;
  double _niveauMax = double.negativeInfinity;

  static void _log(String message) {
    if (kDebugMode) debugPrint('[JARVIS voix] $message');
  }

  /// Initialise la reconnaissance. Renvoie null si tout va bien.
  Future<ErreurReconnaissance?> initialiser() async {
    final navigateur = _navigateur;
    if (navigateur != null) {
      return navigateur.disponible ? null : ErreurReconnaissance.indisponible;
    }
    if (_initialise) return null;
    try {
      _initialise = await _stt.initialize(
        onError: _gererErreur,
        onStatus: _gererStatut,
      );
    } catch (_) {
      return ErreurReconnaissance.indisponible;
    }
    if (!_initialise) {
      return await _stt.hasPermission.catchError((_) => false)
          ? ErreurReconnaissance.indisponible
          : ErreurReconnaissance.permission;
    }
    _localeFrancaise = await _choisirLocaleFrancaise();
    _log('langue de reconnaissance : $_localeFrancaise');
    return null;
  }

  Future<String?> _choisirLocaleFrancaise() async {
    try {
      final locales = await _stt.locales();
      String? id(String prefixe) {
        for (final l in locales) {
          final normal = l.localeId.replaceAll('-', '_').toLowerCase();
          if (normal.startsWith(prefixe)) return l.localeId;
        }
        return null;
      }

      // Si l'appareil ne liste pas ses langues, on impose quand même le
      // français plutôt que la langue par défaut du système.
      return id('fr_fr') ?? id('fr') ?? 'fr_FR';
    } catch (_) {
      return 'fr_FR';
    }
  }

  /// Démarre une écoute. [surNiveau] reçoit l'amplitude entre 0 et 1,
  /// [surPartiel] le texte en cours, [surPhrase] la phrase finale.
  Future<void> ecouter({
    required void Function(String phrase) surPhrase,
    required void Function(ErreurReconnaissance erreur) surErreur,
    required void Function() surFinSansResultat,
    void Function(String texte)? surPartiel,
    void Function(double amplitude)? surNiveau,
  }) async {
    final navigateur = _navigateur;
    if (navigateur != null) {
      navigateur.ecouter(
        langue: _langue,
        surPhrase: surPhrase,
        surPartiel: surPartiel,
        surFinSansResultat: surFinSansResultat,
        surErreur: (erreur, _) => surErreur(erreur),
      );
      return;
    }

    // Verrou : l'écoute précédente doit être réellement finie.
    await _attendreArretMoteur();
    final numero = ++_numero;
    _terminee = false;
    _surErreur = surErreur;
    _surFinSansResultat = surFinSansResultat;
    _log('écoute #$numero');

    void phraseFinale(String texte) {
      if (texte.isEmpty) {
        _issue(numero, surFinSansResultat);
      } else {
        _issue(numero, () => surPhrase(texte));
      }
    }

    // Le moteur doit confirmer l'écoute ; sinon on considère la requête
    // comme refusée (et la session réécoute).
    _surveillance?.cancel();
    _surveillance = Timer(const Duration(seconds: 3), () {
      if (numero == _numero && !_terminee && !_actif) {
        _log('le moteur n\'a pas démarré l\'écoute #$numero');
        _issue(numero, () => surErreur(ErreurReconnaissance.client));
      }
    });

    if (kDebugMode &&
        _phraseDiagnostic.isNotEmpty &&
        _injections < 2 &&
        defaultTargetPlatform == TargetPlatform.android) {
      _injections++;
      Timer(const Duration(milliseconds: 1800), () {
        if (numero != _numero || _terminee) return;
        _log('diagnostic : phrase injectée « $_phraseDiagnostic »');
        phraseFinale(_phraseDiagnostic);
      });
    }

    try {
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) {
          if (numero != _numero || _terminee) return;
          if (r.finalResult) {
            phraseFinale(r.recognizedWords.trim());
          } else {
            surPartiel?.call(r.recognizedWords);
          }
        },
        onSoundLevelChange: surNiveau == null
            ? null
            : (niveau) => surNiveau(_normaliser(niveau)),
        listenOptions: SpeechListenOptions(
          localeId: _localeFrancaise,
          listenFor: const Duration(seconds: 30),
          // Android détecte lui-même la fin de la phrase. Le délai du
          // plugin y arrêtait l'écoute au bout de 3 s de silence, ce qui
          // provoquait error_client et des relances en boucle.
          pauseFor: defaultTargetPlatform == TargetPlatform.android
              ? null
              : const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.confirmation,
        ),
      );
    } catch (e) {
      _log('écoute impossible : $e');
      _issue(numero, () => surErreur(ErreurReconnaissance.client));
    }
  }

  /// Rend l'issue de l'écoute [numero], une seule fois.
  void _issue(int numero, void Function() issue) {
    if (numero != _numero || _terminee) return;
    _terminee = true;
    _surveillance?.cancel();
    issue();
  }

  /// Attend que le moteur ait vraiment fini l'écoute précédente (au plus
  /// une seconde).
  Future<void> _attendreArretMoteur() async {
    if (!_actif && !_stt.isListening) return;
    _arretMoteur ??= Completer<void>();
    final attente = _arretMoteur!.future;
    try {
      await _stt.cancel();
    } catch (_) {}
    await attente.timeout(const Duration(seconds: 1), onTimeout: () {});
    _actif = false;
    _arretMoteur = null;
  }

  double _normaliser(double niveau) {
    _niveauMin = math.min(_niveauMin, niveau);
    _niveauMax = math.max(_niveauMax, niveau);
    final ecart = math.max(_niveauMax - _niveauMin, 8.0);
    return ((niveau - _niveauMin) / ecart).clamp(0.0, 1.0);
  }

  void _gererErreur(SpeechRecognitionError e) {
    final erreur = classerErreurAndroid(e.errorMsg);
    _log('erreur : ${e.errorMsg} → ${erreur.name} (écoute #$_numero)');
    final rappel = _surErreur;
    if (rappel == null) return;
    _issue(_numero, () => rappel(erreur));
  }

  void _gererStatut(String statut) {
    _log('statut : $statut');
    if (statut == SpeechToText.listeningStatus) {
      _actif = true;
      return;
    }
    if (statut == SpeechToText.notListeningStatus ||
        statut == SpeechToText.doneStatus) {
      _actif = false;
      final arret = _arretMoteur;
      if (arret != null && !arret.isCompleted) arret.complete();
    }
    // Fin d'écoute sans phrase finale (silence) : la session réécoute.
    if (statut == SpeechToText.doneStatus) {
      final rappel = _surFinSansResultat;
      if (rappel != null) _issue(_numero, rappel);
    }
  }

  /// Arrête l'écoute en cours sans traiter le résultat.
  Future<void> annuler() async {
    _navigateur?.annuler();
    _terminee = true;
    _surveillance?.cancel();
    _surErreur = null;
    _surFinSansResultat = null;
    if (_navigateur != null) return;
    try {
      await _attendreArretMoteur();
    } catch (_) {}
  }
}
