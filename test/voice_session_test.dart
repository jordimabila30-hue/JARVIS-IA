import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';

class _MicroFactice implements MicrophoneService {
  _MicroFactice(this.reponse);
  final AccesMicro reponse;

  @override
  Future<AccesMicro> demanderAcces() async => reponse;

  @override
  Future<void> ouvrirReglages() async {}
}

/// Reconnaissance factice : « entend » les phrases données, une par écoute,
/// ou signale une erreur.
class _ReconnaissanceFactice implements SpeechRecognitionService {
  _ReconnaissanceFactice({this.phrases = const [], this.erreur});
  final List<String> phrases;
  final ErreurReconnaissance? erreur;
  int ecoutes = 0;
  int annulations = 0;

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
    final rang = ecoutes++;
    Future<void>.microtask(() {
      if (erreur != null) return surErreur(erreur!);
      if (rang < phrases.length) surPhrase(phrases[rang]);
    });
  }

  @override
  Future<void> annuler() async => annulations++;
}

class _VoixFactice implements TtsService {
  final dites = <String>[];

  @override
  String? voiceChoisie;

  @override
  Future<void> initialiser() async {}

  @override
  Future<void> appliquer(VoiceSettings reglages) async =>
      appliques.add(reglages);

  final appliques = <VoiceSettings>[];

  @override
  Future<List<VoixDisponible>> voixDisponibles({
    bool rafraichir = false,
  }) async => const [];

  @override
  Future<ResultatParole> parler(
    String texte, {
    void Function(int debut, int fin)? surMot,
    void Function()? surDebut,
  }) async {
    surDebut?.call();
    dites.add(texte);
    return ResultatParole.lue;
  }

  @override
  Future<void> arreter() async {}
}

class _NiveauFactice implements NiveauMicro {
  bool enCours = false;

  @override
  Future<bool> demarrer(
    void Function(double niveau) surNiveau, {
    void Function(double graves, double mediums, double aigus)? surBandes,
    String? microphoneId,
  }) async {
    enCours = true;
    return true;
  }

  @override
  Future<void> arreter() async => enCours = false;
}

void main() {
  test('micro refusé : message clair et session vraiment arrêtée', () async {
    final niveau = _NiveauFactice();
    final session = VoiceSession(
      micro: _MicroFactice(AccesMicro.refuse),
      reconnaissance: _ReconnaissanceFactice(),
      voix: _VoixFactice(),
      niveau: niveau,
    );
    await session.demarrer();
    expect(session.actif, isFalse);
    expect(session.probleme, isNotNull);
    expect(session.probleme!.reglages, isFalse);
    expect(session.etat, VoiceState.idle);
    expect(niveau.enCours, isFalse);
    session.dispose();
  });

  test('refus définitif : propose les réglages', () async {
    final session = VoiceSession(
      micro: _MicroFactice(AccesMicro.refuseDefinitivement),
      reconnaissance: _ReconnaissanceFactice(),
      voix: _VoixFactice(),
      niveau: _NiveauFactice(),
    );
    await session.demarrer();
    expect(session.probleme!.reglages, isTrue);
    session.dispose();
  });

  test(
    'erreur de reconnaissance : la boucle et la mesure s’arrêtent',
    () async {
      final niveau = _NiveauFactice();
      final session = VoiceSession(
        micro: _MicroFactice(AccesMicro.autorise),
        reconnaissance: _ReconnaissanceFactice(
          erreur: ErreurReconnaissance.permission,
        ),
        voix: _VoixFactice(),
        niveau: niveau,
      );
      await session.demarrer();
      await Future<void>.delayed(Duration.zero);
      expect(session.actif, isFalse);
      expect(session.probleme, isNotNull);
      expect(niveau.enCours, isFalse);
      session.dispose();
    },
  );

  test('« Au revoir » : JARVIS répond puis la session se termine', () async {
    final voix = _VoixFactice();
    final niveau = _NiveauFactice();
    final session = VoiceSession(
      micro: _MicroFactice(AccesMicro.autorise),
      reconnaissance: _ReconnaissanceFactice(
        phrases: ['Bonjour JARVIS', 'Au revoir JARVIS'],
      ),
      voix: voix,
      niveau: niveau,
    );
    var fin = false;
    session.surFin = () => fin = true;

    await session.demarrer();
    expect(niveau.enCours, isTrue);
    // Deux phrases × réflexion de 0,6 à 1,2 s.
    await Future<void>.delayed(const Duration(milliseconds: 2800));

    expect(voix.dites, ['Bonjour. Comment puis-je vous aider ?', 'À bientôt.']);
    expect(fin, isTrue);
    expect(session.actif, isFalse);
    expect(session.probleme, isNull);
    expect(niveau.enCours, isFalse);
    session.dispose();
  });
}
