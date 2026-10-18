// Arrêt de la parole (manuel) : la voix s'arrête, rien ne reprend seul,
// « Parler » relance UNE écoute ; la voix dit la version orale du texte.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/models/voice_state.dart';
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

  setUp(() async {
    reco = _Reco();
    voix = _Voix();
    demandes = 0;
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
    )..repondeur = (phrase) async {
        demandes++;
        return const ReponseVocale(
          'La photosynthèse comprend trois étapes :\n'
          '1. **Absorption** de la lumière.\n'
          '2. Production de sucres.',
          source: SourceReponse.distante,
        );
      };
    await session.demarrer();
    await _attendre();
  });

  test('arrêter la parole : silence, rien ne reprend seul, Parler relance', () async {
    expect(session.etat, VoiceState.listening);
    expect(reco.ecoutes, 1);
    reco.phrase!('Explique la photosynthèse');
    await _attendre(1400); // réflexion visible des réponses (0,6 à 1,2 s)
    expect(session.etat, VoiceState.speaking);
    // La voix dit la version orale : aucun symbole, enchaînement parlé.
    expect(voix.dits.single, isNot(contains(RegExp(r'[*#]|\d\.'))));
    expect(voix.dits.single, contains('D’abord, absorption de la lumière.'));
    // L'écrit reste celui de la conversation.
    expect(session.reponse, contains('**Absorption**'));

    final arret = session.arreterParole();
    // État changé AVANT la fin de l'arrêt de la voix : aucune interface ne
    // peut lire un « parle » périmé.
    expect(session.etat, VoiceState.idle);
    expect(session.paroleInterrompue, isTrue);
    await arret;
    await _attendre(600);
    expect(voix.arrets, 1);
    expect(session.actif, isTrue); // session ouverte
    expect(session.paroleInterrompue, isTrue);
    expect(session.etat, VoiceState.idle);
    expect(reco.ecoutes, 1); // aucune écoute relancée seule
    expect(voix.dits, hasLength(1)); // aucune reprise de la voix

    // Arrêt hors parole : sans effet.
    await session.arreterParole();
    expect(voix.arrets, 1);

    session.parler();
    await _attendre();
    expect(session.paroleInterrompue, isFalse);
    expect(session.etat, VoiceState.listening);
    expect(reco.ecoutes, 2);
    expect(demandes, 1); // une seule réponse IA demandée
  });

  test('quitter pendant la parole : tout est libéré, rien ne reprend', () async {
    reco.phrase!('Explique la photosynthèse');
    await _attendre(1400);
    expect(session.etat, VoiceState.speaking);
    await session.quitterChatVocal();
    await _attendre(600);
    expect(session.actif, isFalse);
    expect(session.paroleInterrompue, isFalse);
    expect(reco.ecoutes, 1);
  });
}
