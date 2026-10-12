import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';

class _Micro implements MicrophoneService {
  @override
  Future<AccesMicro> demanderAcces() async => AccesMicro.autorise;
  @override
  Future<void> ouvrirReglages() async {}
}

/// Reconnaissance scriptée : chaque écoute joue l'événement suivant
/// (« vide », « rien », « client », « partiel:texte », « phrase:texte »).
/// Elle vérifie aussi qu'aucune écoute ne démarre pendant qu'une autre est
/// active, ni pendant que JARVIS parle.
class _Reco implements SpeechRecognitionService {
  _Reco(this.script, {this.voix});
  final List<String> script;
  _Voix? voix;
  int ecoutes = 0;
  bool active = false;
  int ecoutesConcurrentes = 0;
  int ecoutesPendantParole = 0;

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
    if (active) ecoutesConcurrentes++;
    if (voix?.enTrainDeParler ?? false) ecoutesPendantParole++;
    active = true;
    final rang = ecoutes++;
    final e = rang < script.length ? script[rang] : 'attente';
    Timer(const Duration(milliseconds: 50), () {
      if (!active) return;
      if (e == 'attente') return;
      active = false;
      if (e == 'vide') return surFinSansResultat();
      if (e == 'rien') return surErreur(ErreurReconnaissance.rienEntendu);
      if (e == 'client') return surErreur(ErreurReconnaissance.client);
      if (e.startsWith('partiel:')) {
        surPartiel?.call(e.substring(8));
        return surFinSansResultat();
      }
      if (e.startsWith('partiel-nomatch:')) {
        // Android : texte partiel reconnu, puis error_no_match au lieu du
        // résultat final.
        surPartiel?.call(e.substring(16));
        return surErreur(ErreurReconnaissance.rienEntendu);
      }
      if (e.startsWith('phrase:')) return surPhrase(e.substring(7));
    });
  }

  @override
  Future<void> annuler() async => active = false;
}

class _Voix implements TtsService {
  _Voix({this.issue = ResultatParole.lue});
  ResultatParole issue;
  bool enTrainDeParler = false;
  final dites = <String>[];

  @override
  String? voiceChoisie;
  @override
  Future<void> initialiser() async {}
  @override
  Future<void> appliquer(VoiceSettings reglages) async {}
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
    dites.add(texte);
    if (!issue.reussie) return issue;
    enTrainDeParler = true;
    surDebut?.call();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    enTrainDeParler = false;
    return issue;
  }

  @override
  Future<void> arreter() async => enTrainDeParler = false;
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

({VoiceSession session, _Reco reco, _Voix voix}) _session(
  List<String> script, {
  ResultatParole issue = ResultatParole.lue,
}) {
  final voix = _Voix(issue: issue);
  final reco = _Reco(script, voix: voix);
  final session = VoiceSession(
    micro: _Micro(),
    reconnaissance: reco,
    voix: voix,
    niveau: _Niveau(),
  );
  return (session: session, reco: reco, voix: voix);
}

Future<void> _attendre(double secondes) =>
    Future<void>.delayed(Duration(milliseconds: (secondes * 1000).round()));

void main() {
  group('Statut micro', () {
    test('trois écoutes vides sans texte : « aucun son »', () async {
      final s = _session(['vide', 'rien', 'vide', 'vide']);
      await s.session.demarrer();
      await _attendre(5);
      expect(s.session.etat, VoiceState.listening);
      expect(s.session.etatMicro, EtatMicro.aucunSon);
      await s.session.arreter();
    });

    test(
      'du texte reconnu : micro disponible, même après des écoutes vides',
      () async {
        final s = _session([
          'partiel:bonsoir Jarvis',
          'vide',
          'rien',
          'vide',
          'vide',
        ]);
        await s.session.demarrer();
        await _attendre(7);
        expect(s.reco.ecoutes, greaterThanOrEqualTo(4));
        expect(s.session.etatMicro, EtatMicro.disponible);
        expect(s.session.microSilencieux, isFalse);
        await s.session.arreter();
      },
    );

    test('phrase reconnue => micro disponible', () async {
      final s = _session(['phrase:Bonsoir Jarvis', 'vide', 'vide', 'vide']);
      await s.session.demarrer();
      await _attendre(6);
      expect(s.session.etatMicro, EtatMicro.disponible);
      await s.session.arreter();
    });
  });

  group('Erreurs Android', () {
    test('texte partiel puis error_no_match : la phrase est traitée', () async {
      final s = _session(['partiel-nomatch:Bonsoir Jarvis', 'attente']);
      await s.session.demarrer();
      await _attendre(2.5);
      expect(s.voix.dites, hasLength(1));
      expect(s.session.transcription, 'Bonsoir Jarvis');
      expect(s.session.etatMicro, EtatMicro.disponible);
      await s.session.arreter();
    });

    test('classement des codes speech_to_text', () {
      expect(
        classerErreurAndroid('error_no_match'),
        ErreurReconnaissance.rienEntendu,
      );
      expect(
        classerErreurAndroid('error_speech_timeout'),
        ErreurReconnaissance.rienEntendu,
      );
      expect(classerErreurAndroid('error_client'), ErreurReconnaissance.client);
      expect(classerErreurAndroid('error_busy'), ErreurReconnaissance.client);
      expect(
        classerErreurAndroid('error_insufficient_permissions'),
        ErreurReconnaissance.permission,
      );
      expect(
        classerErreurAndroid('error_network'),
        ErreurReconnaissance.reseau,
      );
    });

    test(
      'error_no_match : petite pause puis réécoute, session intacte',
      () async {
        final s = _session(['rien', 'rien']);
        await s.session.demarrer();
        await _attendre(0.2);
        // Pas de relance instantanée.
        expect(s.reco.ecoutes, 1);
        await _attendre(1.6);
        expect(s.reco.ecoutes, greaterThanOrEqualTo(2));
        expect(s.session.actif, isTrue);
        expect(s.session.probleme, isNull);
        expect(s.session.etat, VoiceState.listening);
        await s.session.arreter();
      },
    );

    test(
      'error_client passager : réécoute ; répété : problème expliqué',
      () async {
        final passager = _session(['client', 'phrase:Bonsoir']);
        await passager.session.demarrer();
        await _attendre(2);
        expect(passager.session.probleme, isNull);
        expect(passager.voix.dites, isNotEmpty);
        await passager.session.arreter();

        final repete = _session(['client', 'client', 'client', 'client']);
        await repete.session.demarrer();
        await _attendre(8);
        expect(repete.session.actif, isFalse);
        expect(repete.session.probleme, isNotNull);
      },
    );
  });

  group('Cycle vocal', () {
    test('écoute → phrase → micro coupé → parole → micro rouvert', () async {
      final s = _session([
        'phrase:Bonsoir Jarvis',
        'phrase:Quelle heure est-il',
        'attente',
      ]);
      await s.session.demarrer();
      await _attendre(6);
      expect(s.voix.dites.length, 2);
      // Jamais d'écoute pendant que JARVIS parle, jamais deux à la fois.
      expect(s.reco.ecoutesPendantParole, 0);
      expect(s.reco.ecoutesConcurrentes, 0);
      expect(s.session.etat, VoiceState.listening);
      await s.session.arreter();
    });

    test('voix en échec : la session continue et le signale', () async {
      final s = _session([
        'phrase:Bonsoir',
        'attente',
      ], issue: const ResultatParole(IssueParole.echec, 'Pas de voix'));
      await s.session.demarrer();
      await _attendre(3);
      expect(s.session.erreurVoix, 'Pas de voix');
      expect(s.session.etat, VoiceState.listening);
      await s.session.arreter();
    });
  });

  group('Aperçu de la voix', () {
    test('« Lecture… » seulement quand le son démarre', () async {
      final s = _session(const []);
      final etats = <bool>[];
      s.session.addListener(() => etats.add(s.session.apercuSonore));
      await s.session.lireApercu();
      expect(etats, contains(true));
      expect(s.session.apercuSonore, isFalse);
      expect(s.session.erreurApercu, isNull);
    });

    test('échec : jamais « Lecture… », erreur utile affichée', () async {
      final s = _session(
        const [],
        issue: const ResultatParole(IssueParole.echec, 'Aucune voix'),
      );
      final etats = <bool>[];
      s.session.addListener(() => etats.add(s.session.apercuSonore));
      await s.session.lireApercu();
      expect(etats, isNot(contains(true)));
      expect(s.session.erreurApercu, 'Aucune voix');
    });
  });

  group('Voix et réglages par plateforme', () {
    const voixAndroid = [
      VoixDisponible(nom: 'fr-FR-language', locale: 'fr-FR'),
      VoixDisponible(nom: 'fr-fr-x-frc-local', locale: 'fr-FR'),
      VoixDisponible(
        nom: 'fr-fr-x-frd-network',
        locale: 'fr-FR',
        enLigne: true,
      ),
      VoixDisponible(nom: 'fr-ca-x-cab-local', locale: 'fr-CA'),
    ];

    test('voix Web enregistrée, inexistante sur Android : voix fr-FR', () {
      const r = VoiceSettings(
        voix: 'Microsoft Denise Online (Natural) - French (France)',
      );
      final v = TtsService.voixPour(r, voixAndroid)!;
      expect(v.locale, 'fr-FR');
      expect(v.enLigne, isFalse);
    });

    test('voix enregistrée disponible : gardée', () {
      const r = VoiceSettings(voix: 'fr-fr-x-frc-local');
      expect(TtsService.voixPour(r, voixAndroid)!.nom, 'fr-fr-x-frc-local');
    });

    test('locale absente : même langue, sinon voix système', () {
      const r = VoiceSettings(locale: 'fr-BE');
      expect(TtsService.voixPour(r, voixAndroid)!.locale, startsWith('fr'));
      expect(TtsService.voixPour(r, const []), isNull);
    });

    test('débit : 0.75x / 1.0x / 1.2x convertis selon la plateforme', () {
      double debit(double v, {bool web = false, TargetPlatform? p}) =>
          TtsService.parametresMoteur(
            VoiceSettings(vitesse: v),
            web: web,
            plateforme: p ?? TargetPlatform.android,
          ).debit;
      // Web Speech : 1.0 = normal.
      expect(debit(1.0, web: true), 1.0);
      expect(debit(1.2, web: true), closeTo(1.2, 1e-9));
      // Android : le plugin double la valeur (0.5 → 1.0 natif).
      expect(debit(0.75), closeTo(0.375, 1e-9));
      expect(debit(1.0), 0.5);
      expect(debit(1.2), closeTo(0.6, 1e-9));
      // iOS : 0.5 = débit par défaut d'AVSpeech.
      expect(debit(1.0, p: TargetPlatform.iOS), 0.5);
      // Hauteur et volume restent dans les plages acceptées.
      final p = TtsService.parametresMoteur(
        const VoiceSettings(hauteur: 0.1, volume: 0.8),
        web: false,
        plateforme: TargetPlatform.android,
      );
      expect(p.hauteur, closeTo(1.1, 1e-9));
      expect(p.volume, 0.8);
    });
  });
}
