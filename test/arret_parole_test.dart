// Interruption en un toucher : la voix s'arrête, la génération est arrêtée,
// l'écoute reprend aussitôt ; lecture pendant la réception (phrases
// complètes) ; la voix dit la version orale du texte.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/services/jarvis_touch_vocal.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_command_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

class _Micro implements MicrophoneService {
  @override
  Future<AccesMicro> demanderAcces() async => AccesMicro.autorise;
  @override
  Future<void> ouvrirReglages() async {}
}

class _Reco implements SpeechRecognitionService {
  void Function(String)? phrase;
  int ecoutes = 0;
  @override
  Future<ErreurReconnaissance?> initialiser() async => null;
  @override
  Future<void> ecouter({
    required void Function(String phrase) surPhrase,
    required void Function(ErreurReconnaissance erreur) surErreur,
    required void Function() surFinSansResultat,
    void Function(String texte)? surPartiel,
    void Function(double amplitude)? surNiveau,
  }) async {
    ecoutes++;
    phrase = surPhrase;
  }

  @override
  Future<void> annuler() async {}
}

/// Voix factice : parle jusqu'à ce qu'on l'arrête (comme une longue réponse).
class _Voix implements TtsService {
  final dits = <String>[];
  Completer<ResultatParole>? _encours;
  int arrets = 0;

  @override
  String? voiceChoisie;
  @override
  Future<void> initialiser() async {}
  @override
  Future<void> appliquer(VoiceSettings reglages) async {}
  @override
  Future<List<VoixDisponible>> voixDisponibles({bool rafraichir = false}) async =>
      const [];
  @override
  Future<ResultatParole> parler(
    String texte, {
    void Function(int debut, int fin)? surMot,
    void Function()? surDebut,
  }) {
    dits.add(texte);
    surDebut?.call();
    return (_encours = Completer<ResultatParole>()).future;
  }

  /// Le segment en cours se termine normalement.
  void finir() {
    final c = _encours;
    _encours = null;
    if (c != null && !c.isCompleted) c.complete(ResultatParole.lue);
  }

  @override
  Future<void> arreter() async {
    arrets++;
    final c = _encours;
    _encours = null;
    if (c != null && !c.isCompleted) c.complete(ResultatParole.lue);
  }
}

class _Niveau implements NiveauMicro {
  @override
  Future<bool> demarrer(
    void Function(double niveau) surNiveau, {
    void Function(double graves, double mediums, double aigus)? surBandes,
    String? microphoneId,
  }) async => false;
  @override
  Future<void> arreter() async {}
}

class _Micros implements PeripheriquesAudio {
  @override
  bool get choixPossible => false;
  @override
  Future<List<MicroDisponible>> lister() async => const [];
  @override
  Future<bool> autoriser() async => false;
}

Future<void> _attendre([int ms = 50]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late _Reco reco;
  late _Voix voix;
  late VoiceSession session;
  var demandes = 0;
  final entendus = <String>[];
  // Fragments envoyés par le « serveur » pendant la réponse.
  late void Function(String) envoyer;
  late Completer<void> finReponse;

  setUp(() async {
    reco = _Reco();
    voix = _Voix();
    demandes = 0;
    entendus.clear();
    finReponse = Completer<void>();
    session = VoiceSession(
      micro: _Micro(),
      reconnaissance: reco,
      voix: voix,
      niveau: _Niveau(),
      reglages: VoiceSettingsService(
        tts: voix,
        stockage: StockageMemoire(),
        peripheriques: _Micros(),
        delaiSauvegarde: Duration.zero,
      ),
    )
      ..repondeur = (phrase, {surFragment}) async {
        demandes++;
        envoyer = (f) => surFragment?.call(f);
        await finReponse.future;
        return const ReponseVocale(
          'Un moteur électrique transforme l’énergie. Il comporte un rotor. '
          'Et un stator fixe.',
          source: SourceReponse.distante,
        );
      }
      ..annulerReponse = entendus.add;
    await session.demarrer();
    await _attendre();
  });

  test('lecture pendant la réception : phrases complètes, sans attendre la fin', () async {
    reco.phrase!('Explique le moteur électrique');
    await _attendre();
    expect(session.etat, VoiceState.thinking);
    envoyer('Un moteur électrique transforme l’énergie. Il comporte un ro');
    await _attendre();
    envoyer('tor. Et un st');
    await _attendre();
    // Deux phrases complètes : la voix parle avant la fin de la réponse.
    expect(session.etat, VoiceState.speaking);
    expect(voix.dits, ['Un moteur électrique transforme l’énergie.']);
    voix.finir();
    await _attendre();
    expect(voix.dits.last, 'Il comporte un rotor.');
    envoyer('ator fixe.');
    finReponse.complete();
    voix.finir();
    await _attendre();
    voix.finir();
    await _attendre(500);
    expect(voix.dits, [
      'Un moteur électrique transforme l’énergie.',
      'Il comporte un rotor.',
      'Et un stator fixe.',
    ]);
    expect(session.etat, VoiceState.listening);
    expect(demandes, 1);
  });

  test('un toucher : silence, génération arrêtée, écoute aussitôt', () async {
    reco.phrase!('Explique le moteur électrique');
    await _attendre();
    envoyer('Un moteur électrique transforme l’énergie. Il comporte un rotor. ');
    await _attendre();
    expect(session.parle, isTrue);

    final arret = session.arreterParole();
    // Transition contrôlée, jamais « parle » après le toucher.
    expect(session.parle, isFalse);
    await arret;
    expect(voix.arrets, 1);
    expect(entendus.single, 'Un moteur électrique transforme l’énergie.');
    expect(session.etat, VoiceState.listening); // une seule action
    expect(reco.ecoutes, 2);

    // Fragments et fin tardifs de l'ancienne réponse : jamais dits.
    envoyer('Et un stator fixe. ');
    finReponse.complete();
    voix.finir();
    await _attendre(500);
    expect(voix.dits, hasLength(1));
    expect(reco.ecoutes, 2); // aucune écoute relancée en double
    expect(demandes, 1);

    // Arrêt hors parole : sans effet.
    await session.arreterParole();
    expect(voix.arrets, 1);
  });

  test('quitter pendant la parole : tout est libéré, rien ne reprend', () async {
    reco.phrase!('Explique le moteur électrique');
    await _attendre();
    envoyer('Un moteur électrique transforme l’énergie. Il comporte un rotor. ');
    await _attendre();
    expect(session.parle, isTrue);
    await session.quitterChatVocal();
    finReponse.complete();
    await _attendre(500);
    expect(session.actif, isFalse);
    expect(reco.ecoutes, 1);
  });

  test('JARVIS Touch réduit : la réponse en cours finit, puis plus aucun '
      'micro ouvert ; la bulle rouvre l’écoute', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const canal = MethodChannel('test/touch_vocal');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (_) async => null);
    final passerelle = PasserelleVocalTouch(session, canal);
    await passerelle.surAppel(const MethodCall('vocalOuvrir'));
    reco.phrase!('Explique le moteur électrique');
    await _attendre();
    envoyer('Un moteur électrique transforme l’énergie. Il comporte un rotor. ');
    await _attendre();
    expect(session.parle, isTrue);

    await passerelle.surAppel(const MethodCall('vocalReduire'));
    // Jamais coupée par la réduction.
    expect(session.parle, isTrue);
    expect(voix.arrets, 0);
    finReponse.complete();
    for (var i = 0; i < 4; i++) {
      voix.finir();
      await _attendre(200);
    }
    expect(session.actif, isFalse, reason: 'micro suspendu fenêtre réduite');
    final ecoutes = reco.ecoutes;

    await passerelle.surAppel(const MethodCall('vocalOuvrir'));
    await _attendre();
    expect(session.actif, isTrue);
    expect(reco.ecoutes, greaterThan(ecoutes));
    passerelle.detacher();
  });
}
