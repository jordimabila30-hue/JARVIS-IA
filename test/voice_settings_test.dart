import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

/// Synthèse factice : voix données, réglages et phrases enregistrés.
class _Tts implements TtsService {
  _Tts([this.voix = const []]);

  final List<VoixDisponible> voix;
  final appliques = <VoiceSettings>[];
  final dites = <String>[];
  int arrets = 0;

  @override
  String? voiceChoisie;

  @override
  Future<void> initialiser() async {}

  @override
  Future<void> appliquer(VoiceSettings reglages) async =>
      appliques.add(reglages);

  @override
  Future<List<VoixDisponible>> voixDisponibles({
    bool rafraichir = false,
  }) async => voix;

  @override
  Future<ResultatParole> parler(
    String texte, {
    void Function(int debut, int fin)? surMot,
    void Function()? surDebut,
  }) async {
    surDebut?.call();
    dites.add(texte);
    surMot?.call(0, 4);
    return ResultatParole.lue;
  }

  @override
  Future<void> arreter() async => arrets++;
}

class _Micros implements PeripheriquesAudio {
  _Micros(this.liste);

  List<MicroDisponible> liste;

  @override
  bool get choixPossible => true;

  @override
  Future<List<MicroDisponible>> lister() async => liste;

  @override
  Future<bool> autoriser() async => true;
}

class _Micro implements MicrophoneService {
  @override
  Future<AccesMicro> demanderAcces() async => AccesMicro.autorise;
  @override
  Future<void> ouvrirReglages() async {}
}

class _Reco implements SpeechRecognitionService {
  _Reco(this.phrases);
  final List<String> phrases;
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
    final rang = ecoutes++;
    Future<void>.microtask(() {
      if (rang < phrases.length) surPhrase(phrases[rang]);
    });
  }

  @override
  Future<void> annuler() async {}
}

class _Niveau implements NiveauMicro {
  String? microUtilise;

  @override
  Future<bool> demarrer(
    void Function(double niveau) surNiveau, {
    void Function(double graves, double mediums, double aigus)? surBandes,
    String? microphoneId,
  }) async {
    microUtilise = microphoneId;
    return true;
  }

  @override
  Future<void> arreter() async {}
}

const _voix = [
  VoixDisponible(nom: 'Denise', locale: 'fr-FR'),
  VoixDisponible(nom: 'Henri', locale: 'fr-FR'),
  VoixDisponible(nom: 'Google français', locale: 'fr-FR', enLigne: true),
  VoixDisponible(nom: 'Sylvie', locale: 'fr-CA'),
  VoixDisponible(nom: 'Aria', locale: 'en-US'),
];

VoiceSettingsService _service({
  StockageReglages? stockage,
  List<VoixDisponible> voix = _voix,
  List<MicroDisponible> micros = const [],
}) => VoiceSettingsService(
  tts: _Tts(voix),
  stockage: stockage ?? StockageMemoire(),
  peripheriques: _Micros(micros),
  delaiSauvegarde: Duration.zero,
);

void main() {
  group('Modèle VoiceSettings', () {
    test('valeurs par défaut sûres', () {
      const r = VoiceSettings.defaut;
      expect(r.locale, 'fr-FR');
      expect(r.vitesse, 1.0);
      expect(r.hauteur, 0.0);
      expect(r.volume, 1.0);
      expect(r.reponseAutomatique, isTrue);
      expect(r.voix, isNull);
      expect(r.microphoneId, isNull);
    });

    test('aller-retour JSON', () {
      const r = VoiceSettings(
        profil: ProfilVocal.clair,
        locale: 'fr-CA',
        voix: 'Sylvie',
        vitesse: 0.88,
        hauteur: 0.04,
        volume: 0.6,
        microphoneId: 'usb-1',
        reponseAutomatique: false,
      );
      final relu = VoiceSettings.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>,
      );
      expect(relu, r);
    });

    test('lecture tolérante : valeurs invalides corrigées ou bornées', () {
      final r = VoiceSettings.fromJson({
        'profil': 'inconnu',
        'vitesse': 9,
        'hauteur': -3,
        'volume': 'fort',
        'reponseAutomatique': 'oui',
      });
      expect(r.profil, ProfilVocal.naturel);
      expect(r.vitesse, VoiceSettings.vitesseMax);
      expect(r.hauteur, VoiceSettings.hauteurMin);
      expect(r.volume, 1.0);
      expect(r.reponseAutomatique, isTrue);
    });

    test('profils : préréglages, puis Personnalisé après réglage manuel', () {
      final classique = VoiceSettings.defaut
          .copyWith(volume: 0.5)
          .avecProfil(ProfilVocal.classique);
      expect(classique.vitesse, 0.92);
      expect(classique.hauteur, -0.05);
      expect(classique.volume, 0.5, reason: 'le volume reste personnel');

      final perso = classique.avecReglageManuel(vitesse: 1.2);
      expect(perso.profil, ProfilVocal.personnalise);
      // Retour exact aux valeurs d'un profil : il est reconnu.
      expect(
        perso.avecReglageManuel(vitesse: 1.0, hauteur: 0).profil,
        ProfilVocal.naturel,
      );
    });
  });

  group('TtsService (conversion par plateforme)', () {
    const r = VoiceSettings(vitesse: 1.2, hauteur: 0.1, volume: 0.4);

    test('débit, hauteur, volume', () {
      final web = TtsService.parametresMoteur(
        r,
        web: true,
        plateforme: TargetPlatform.windows,
      );
      expect(web.debit, closeTo(1.2, 1e-9));
      final android = TtsService.parametresMoteur(
        r,
        web: false,
        plateforme: TargetPlatform.android,
      );
      expect(android.debit, closeTo(0.6, 1e-9));
      final windows = TtsService.parametresMoteur(
        r,
        web: false,
        plateforme: TargetPlatform.windows,
      );
      expect(windows.debit, closeTo(0.7, 1e-9));
      expect(android.hauteur, closeTo(1.1, 1e-9));
      expect(android.volume, 0.4);
    });

    test('voix du plugin lues et normalisées', () {
      final v = TtsService.lireVoix([
        {'name': 'Amélie', 'locale': 'fr_ca'},
        {'name': 'Amélie', 'locale': 'fr_ca'},
        {'name': '', 'locale': 'fr-FR'},
        {'name': 'Réseau', 'locale': 'fr-FR', 'network_required': '1'},
        'n’importe quoi',
      ]);
      expect(v.map((e) => '${e.nom}|${e.locale}'), [
        'Amélie|fr-CA',
        'Réseau|fr-FR',
      ]);
      expect(v.last.enLigne, isTrue);
      expect(TtsService.lireVoix(null), isEmpty);
    });

    test('choix de la voix', () {
      // Voix choisie et disponible.
      expect(
        TtsService.voixPour(const VoiceSettings(voix: 'Henri'), _voix)?.nom,
        'Henri',
      );
      // Automatique : voix locale plutôt qu'en ligne, ordre alphabétique.
      expect(TtsService.voixPour(const VoiceSettings(), _voix)?.nom, 'Denise');
      // Voix d'une autre locale : remplacée par une voix compatible.
      expect(
        TtsService.voixPour(
          const VoiceSettings(locale: 'fr-CA', voix: 'Denise'),
          _voix,
        )?.nom,
        'Sylvie',
      );
      // Aucune voix : voix système par défaut.
      expect(TtsService.voixPour(const VoiceSettings(), const []), isNull);
    });
  });

  group('VoiceSettingsService', () {
    test('chargement des réglages enregistrés', () async {
      final stockage = StockageMemoire(
        jsonEncode(
          const VoiceSettings(vitesse: 1.2, reponseAutomatique: false).toJson(),
        ),
      );
      final s = _service(stockage: stockage);
      await s.charger();
      expect(s.reglages.vitesse, 1.2);
      expect(s.reglages.reponseAutomatique, isFalse);
    });

    test('stockage vide ou illisible : valeurs par défaut', () async {
      final s = _service(stockage: StockageMemoire('{pas du json'));
      await s.charger();
      expect(s.reglages, VoiceSettings.defaut);
    });

    test('chaque modification est enregistrée automatiquement', () async {
      final stockage = StockageMemoire();
      final s = _service(stockage: stockage);
      s.choisirVitesse(1.15);
      s.choisirHauteur(0.05);
      s.choisirVolume(0.7);
      s.choisirReponseAutomatique(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final relu = VoiceSettings.fromJson(
        jsonDecode(stockage.valeur!) as Map<String, Object?>,
      );
      expect(relu.vitesse, 1.15);
      expect(relu.hauteur, 0.05);
      expect(relu.volume, 0.7);
      expect(relu.reponseAutomatique, isFalse);
      expect(relu.profil, ProfilVocal.personnalise);
      expect(s.sauvegardes.value, greaterThan(0));
    });

    test('profil vocal', () {
      final s = _service()..choisirProfil(ProfilVocal.dynamique);
      expect(s.reglages.profil, ProfilVocal.dynamique);
      expect(s.reglages.vitesse, 1.12);
    });

    test('langues et voix réellement disponibles', () async {
      final s = _service();
      await s.chargerCapacites();
      expect(s.locales, ['fr-FR', 'fr-CA', 'en-US']);
      expect(s.voixDeLaLocale.map((v) => v.nom), [
        'Denise',
        'Google français',
        'Henri',
      ]);
      // Aucune voix : seule la locale actuelle, voix système.
      final vide = _service(voix: const []);
      await vide.chargerCapacites();
      expect(vide.locales, ['fr-FR']);
      expect(vide.voixEffective, isNull);
    });

    test(
      'changement de langue : voix valide choisie automatiquement',
      () async {
        final s = _service();
        await s.chargerCapacites();
        s.choisirVoix('Henri');
        expect(s.voixEffective?.nom, 'Henri');
        s.choisirLocale('fr-CA');
        expect(s.reglages.locale, 'fr-CA');
        expect(s.reglages.voix, 'Sylvie');
        s.choisirLocale('fr-FR');
        expect(s.reglages.voix, 'Denise');
      },
    );

    test('micro enregistré disparu : retour au micro par défaut', () async {
      final s = VoiceSettingsService(
        tts: _Tts(),
        stockage: StockageMemoire(
          jsonEncode(const VoiceSettings(microphoneId: 'ancien').toJson()),
        ),
        peripheriques: _Micros([
          const MicroDisponible(id: 'usb', nom: 'Micro USB'),
        ]),
      );
      await s.charger();
      await s.chargerCapacites();
      expect(s.reglages.microphoneId, isNull);
      s.choisirMicro('usb');
      expect(s.reglages.microphoneId, 'usb');
    });
  });

  group('Session vocale et réglages', () {
    VoiceSession session(
      _Tts tts,
      List<String> phrases, {
      VoiceSettings reglages = VoiceSettings.defaut,
      _Niveau? niveau,
    }) {
      final service = VoiceSettingsService(
        tts: tts,
        stockage: StockageMemoire(jsonEncode(reglages.toJson())),
        peripheriques: _Micros(const []),
      );
      return VoiceSession(
        micro: _Micro(),
        reconnaissance: _Reco(phrases),
        voix: tts,
        niveau: niveau ?? _Niveau(),
        reglages: service,
      );
    }

    test('les réglages sont appliqués avant de parler', () async {
      final tts = _Tts();
      final s = session(tts, ['Bonjour JARVIS']);
      await s.reglages.charger();
      s.reglages.choisirVitesse(1.25);
      await s.demarrer();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(tts.dites, ['Bonjour. Comment puis-je vous aider ?']);
      expect(tts.appliques.last.vitesse, 1.25);
      s.dispose();
    });

    test('micro choisi transmis à la mesure du volume', () async {
      final niveau = _Niveau();
      final s = session(
        _Tts(),
        const [],
        reglages: const VoiceSettings(microphoneId: 'usb'),
        niveau: niveau,
      );
      await s.reglages.charger();
      await s.demarrer();
      expect(niveau.microUtilise, 'usb');
      s.dispose();
    });

    test('réponse automatique désactivée : la phrase attend', () async {
      final tts = _Tts();
      final s = session(tts, [
        'Bonjour JARVIS',
      ], reglages: const VoiceSettings(reponseAutomatique: false));
      await s.reglages.charger();
      await s.demarrer();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.phraseEnAttente, 'Bonjour JARVIS');
      expect(s.etat, VoiceState.idle);
      expect(tts.dites, isEmpty);

      await s.envoyerPhrase();
      expect(tts.dites, ['Bonjour. Comment puis-je vous aider ?']);
      expect(s.phraseEnAttente, isNull);
      s.dispose();
    });

    test('aperçu de la voix avec les réglages actuels', () async {
      final tts = _Tts();
      final s = session(tts, const []);
      s.reglages.choisirProfil(ProfilVocal.clair);
      final lecture = s.lireApercu();
      expect(s.apercuEnCours, isTrue);
      expect(s.etat, VoiceState.speaking);
      await lecture;
      expect(tts.dites, [VoiceSession.phraseApercu]);
      expect(tts.appliques.last.profil, ProfilVocal.clair);
      expect(s.apercuEnCours, isFalse);
      expect(s.etat, VoiceState.idle);
      s.dispose();
    });

    test('aperçu arrêté à la demande', () async {
      final tts = _Tts();
      final s = session(tts, const []);
      final lecture = s.lireApercu();
      await s.arreterApercu();
      await lecture;
      expect(s.apercuEnCours, isFalse);
      expect(tts.arrets, greaterThan(0));
      s.dispose();
    });
  });

  group('Langues de JARVIS', () {
    const voix = [
      VoixDisponible(nom: 'Elsa', locale: 'it-IT'),
      VoixDisponible(nom: 'Hamed', locale: 'ar-SA'),
      VoixDisponible(nom: 'Katja', locale: 'de-DE'),
      VoixDisponible(nom: 'Dalia', locale: 'es-MX'),
      VoixDisponible(nom: 'Elvira', locale: 'es-ES'),
      VoixDisponible(nom: 'Libby', locale: 'en-GB'),
      VoixDisponible(nom: 'Aria', locale: 'en-US'),
      VoixDisponible(nom: 'Sylvie', locale: 'fr-CA'),
      VoixDisponible(nom: 'Denise', locale: 'fr-FR'),
    ];

    test(
      'seulement français, anglais, allemand, espagnol, dans cet ordre',
      () async {
        final s = _service(voix: voix);
        await s.chargerCapacites();
        expect(s.langues, ['fr', 'en', 'de', 'es']);
        expect(s.langue, 'fr');
        // Toutes les régions de la langue, la région par défaut d'abord.
        expect(s.voixDeLaLangue.map((v) => v.nom), ['Denise', 'Sylvie']);
      },
    );

    test('choisir une langue : région par défaut, voix valide', () async {
      final s = _service(voix: voix);
      await s.chargerCapacites();
      s.choisirLangue('es');
      expect(s.reglages.locale, 'es-ES');
      expect(s.reglages.voix, 'Elvira');
      expect(s.voixDeLaLangue.map((v) => v.nom), ['Elvira', 'Dalia']);
      // Choisir une voix d'une autre région change l'accent.
      s.choisirVoixDisponible(s.voixDeLaLangue.last);
      expect(s.reglages.locale, 'es-MX');
      expect(s.reglages.voix, 'Dalia');
      // Rechoisir la même langue garde la région.
      s.choisirLangue('es');
      expect(s.reglages.locale, 'es-MX');
    });

    test(
      'langue sans région par défaut disponible : première région',
      () async {
        final s = _service(
          voix: const [
            VoixDisponible(nom: 'Denise', locale: 'fr-FR'),
            VoixDisponible(nom: 'Ingrid', locale: 'de-AT'),
          ],
        );
        await s.chargerCapacites();
        s.choisirLangue('de');
        expect(s.reglages.locale, 'de-AT');
        expect(s.reglages.voix, 'Ingrid');
      },
    );

    test('aucune voix : seule la langue actuelle', () async {
      final s = _service(voix: const []);
      await s.chargerCapacites();
      expect(s.langues, ['fr']);
      expect(s.voixDeLaLangue, isEmpty);
    });
  });
}
