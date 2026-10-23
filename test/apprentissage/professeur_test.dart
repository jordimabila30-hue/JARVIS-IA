// Kelasi phase 2 (B et C), logique : progression v2 (migration v1),
// adaptation, client SSE du tuteur (ApiJarvis.tuteur), séance du tuteur,
// dialogue de situation et oral sur LA session vocale de JARVIS.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/apprentissage/contenu_pedagogique.dart';
import 'package:ia_jarvis/models/apprentissage/exercice.dart';
import 'package:ia_jarvis/models/apprentissage/progression.dart';
import 'package:ia_jarvis/models/apprentissage/tuteur.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/apprentissage/adaptation.dart';
import 'package:ia_jarvis/services/apprentissage/dialogue_situation.dart';
import 'package:ia_jarvis/services/apprentissage/service_progression.dart';
import 'package:ia_jarvis/services/apprentissage/session_tuteur.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_command_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

// --- Aides ------------------------------------------------------------------------

ExerciceChoix _choix(String id, String fiche) => ExerciceChoix(
  id: id,
  fiche: fiche,
  consigne: '?',
  explication: '!',
  type: TypeExercice.choix,
  options: const ['a', 'b'],
  bonne: 0,
);

const _ordre = ExerciceOrdre(
  id: 'o1',
  fiche: 'f2',
  consigne: '?',
  explication: '!',
  elements: ['1', '2', '3'],
);

Lecon _lecon(String id, List<Exercice> ex) => Lecon(
  id: id,
  titre: id,
  niveau: 1,
  dureeMinutes: 3,
  objectif: '',
  fiches: {for (final e in ex) e.fiche}.toList(),
  exercices: ex,
);

ServiceProgression _progression([StockageMemoire? s]) => ServiceProgression(
  principal: s ?? StockageMemoire(),
  secours: StockageMemoire(),
  corrompue: StockageMemoire(),
);

String _sse(List<(String, Map<String, dynamic>)> evenements) => evenements
    .map((e) => 'event: ${e.$1}\ndata: ${jsonEncode(e.$2)}\n\n')
    .join();

ApiJarvis _api(
  Future<http.StreamedResponse> Function(http.BaseRequest r) repondre, {
  List<http.BaseRequest>? requetes,
}) => ApiJarvis(
  adresse: Uri.parse('http://test/'),
  jeton: () async => 'jeton',
  renouveler: () async => 'neuf',
  client: MockClient.streaming((r, _) {
    requetes?.add(r);
    return repondre(r);
  }),
);

http.StreamedResponse _flux(String corps, [int statut = 200]) =>
    http.StreamedResponse(Stream.value(utf8.encode(corps)), statut);

const _situation = SituationPratique(
  id: 'sit-entretien',
  titre: 'Entretien',
  icone: 'dialogue',
  fiches: ['com-f-ecoute'],
  objectif: 'o',
  consigne: 'c',
  role: 'recruteuse',
  ouverture: 'Bonjour, présentez-vous.',
);

// --- Session vocale factice (mêmes doublures que menu_lateral_test) ------------

class _Tts implements TtsService {
  final dits = <String>[];
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
  }) async {
    dits.add(texte);
    surDebut?.call();
    return ResultatParole.lue;
  }

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

class _Micro implements MicrophoneService {
  @override
  Future<AccesMicro> demanderAcces() async => AccesMicro.autorise;
  @override
  Future<void> ouvrirReglages() async {}
}

class _Reco implements SpeechRecognitionService {
  void Function(String phrase)? phrase;
  @override
  Future<ErreurReconnaissance?> initialiser() async => null;
  @override
  Future<void> ecouter({
    required void Function(String phrase) surPhrase,
    required void Function(ErreurReconnaissance erreur) surErreur,
    required void Function() surFinSansResultat,
    void Function(String texte)? surPartiel,
    void Function(double amplitude)? surNiveau,
  }) async => phrase = surPhrase;
  @override
  Future<void> annuler() async {}
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

(VoiceSession, _Reco, _Tts) _voix() {
  final tts = _Tts();
  final reco = _Reco();
  final s = VoiceSession(
    micro: _Micro(),
    reconnaissance: reco,
    voix: tts,
    niveau: _Niveau(),
    reglages: VoiceSettingsService(
      tts: tts,
      stockage: StockageMemoire(),
      peripheriques: _Micros(),
      delaiSauvegarde: Duration.zero,
    ),
  );
  return (s, reco, tts);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('progression v2', () {
    test('une progression v1 est lue, puis réécrite en v2 sans rien perdre', () async {
      final s = StockageMemoire(
        jsonEncode({
          'version': 1,
          'lecons': {
            'l1': {'terminee': true, 'meilleur': 3, 'total': 4},
          },
          'a_reviser': {'e1': 'l1'},
          'dernier_parcours': 'cor',
        }),
      );
      final p = _progression(s);
      await p.charger();
      expect(p.etat('l1')!.terminee, isTrue);
      expect(p.donnees.aReviser, {'e1': 'l1'});
      expect(p.niveau('cor'), isNull);
      expect(p.testAProposer('cor'), isTrue);
      await p.fixerNiveau('cor', NiveauApprenant.intermediaire);
      final j = jsonDecode(s.valeur!) as Map;
      expect(j['version'], 2);
      expect(j['niveaux'], {'cor': 'intermediaire'});
      expect(j['lecons']['l1']['terminee'], isTrue);
      final relu = _progression(s);
      await relu.charger();
      expect(relu.niveau('cor'), NiveauApprenant.intermediaire);
      p.dispose();
      relu.dispose();
    });

    test('maîtrise : moyenne glissante par notion ; « Commencer directement »', () async {
      final p = _progression();
      await p.charger();
      p.noterExercice('l', 'e1', juste: false, fiche: 'f');
      expect(p.maitriseDe('f'), closeTo(0.325, 1e-9));
      p.noterExercice('l', 'e1', juste: true, fiche: 'f');
      expect(p.maitriseDe('f'), closeTo(0.56125, 1e-9));
      expect(p.donnees.aReviser, isEmpty);
      p.passerTest('cor');
      expect(p.testAProposer('cor'), isFalse);
      expect(p.niveau('cor'), isNull);
      p.dispose();
    });

    test('valeurs étranges ignorées (niveau inconnu, maîtrise hors bornes)', () {
      final p = ProgressionApprentissage.decoder(
        jsonEncode({
          'version': 2,
          'lecons': {},
          'niveaux': {'a': 'expert', 'b': 'avance'},
          'maitrise': {'f': 7, 'g': 'x'},
          'test_sans_niveau': ['c', 3],
        }),
      );
      expect(p.niveaux, {'b': NiveauApprenant.avance});
      expect(p.maitrise, {'f': 1.0});
      expect(p.testSansNiveau, {'c'});
    });
  });

  group('adaptation', () {
    test('niveau estimé : seuils 50 % et 80 %', () {
      expect(AdaptationKelasi.niveauPour(0, 5), NiveauApprenant.debutant);
      expect(AdaptationKelasi.niveauPour(2, 5), NiveauApprenant.debutant);
      expect(AdaptationKelasi.niveauPour(3, 5), NiveauApprenant.intermediaire);
      expect(AdaptationKelasi.niveauPour(4, 5), NiveauApprenant.avance);
      expect(AdaptationKelasi.niveauPour(0, 0), NiveauApprenant.debutant);
    });

    test('test de niveau : court, toutes les notions sondées, simple d’abord', () {
      final lecons = [
        _lecon('l1', [_ordre, _choix('a1', 'f1'), _choix('a2', 'f1')]),
        _lecon('l2', [_choix('b1', 'f3'), _choix('b2', 'f3'), _choix('b3', 'f3')]),
      ];
      final test = AdaptationKelasi.exercicesTest(lecons);
      expect(test, hasLength(AdaptationKelasi.tailleTest));
      expect(test.map((e) => e.$1.fiche).toSet(), {'f1', 'f2', 'f3'});
      final difficultes = [
        for (final e in test) AdaptationKelasi.difficulte(e.$1),
      ];
      expect(difficultes, [...difficultes]..sort());
      expect(test.first.$1.id, 'a1');
      expect(test.firstWhere((e) => e.$1.fiche == 'f1').$2, 'l1');
    });

    test('ordre adaptatif : notions fragiles d’abord, difficulté selon le niveau', () {
      final ex = [_choix('a', 'solide'), _choix('b', 'fragile'), _ordre];
      final maitrise = {'solide': 0.9, 'fragile': 0.2, 'f2': 0.5};
      final debutant = AdaptationKelasi.ordonner(
        ex,
        exercice: (e) => e,
        maitrise: (f) => maitrise[f]!,
        niveau: NiveauApprenant.debutant,
      );
      expect(debutant.map((e) => e.id), ['b', 'a', 'o1']);
      final avance = AdaptationKelasi.ordonner(
        ex,
        exercice: (e) => e,
        maitrise: (f) => maitrise[f]!,
        niveau: NiveauApprenant.avance,
      );
      expect(avance.first.id, 'o1');
    });

    test('ajustement après une leçon : un cran, seulement si cohérent', () {
      expect(
        AdaptationKelasi.ajuster(null, justes: 4, total: 5, maitrises: const []),
        NiveauApprenant.avance,
      );
      expect(
        AdaptationKelasi.ajuster(
          NiveauApprenant.debutant,
          justes: 5,
          total: 5,
          maitrises: const [0.8, 0.9],
        ),
        NiveauApprenant.intermediaire,
      );
      // Leçon réussie mais notions encore fragiles : inchangé.
      expect(
        AdaptationKelasi.ajuster(
          NiveauApprenant.debutant,
          justes: 5,
          total: 5,
          maitrises: const [0.4],
        ),
        NiveauApprenant.debutant,
      );
      expect(
        AdaptationKelasi.ajuster(
          NiveauApprenant.avance,
          justes: 1,
          total: 5,
          maitrises: const [0.3],
        ),
        NiveauApprenant.intermediaire,
      );
    });

    test('réponse de l’élève en clair pour « Mon erreur »', () {
      expect(texteReponse(_choix('a', 'f'), const ReponseChoix(1)), 'b');
      expect(texteReponse(_ordre, const ReponseOrdre([2, 0, 1])), '3 / 1 / 2');
    });
  });

  group('client du tuteur (SSE)', () {
    final demande = DemandeTuteur(
      action: ActionTuteur.erreur,
      fiches: const ['cor-f-appel'],
      exercice: 'cor-l1-e1',
      reponse: 'Salut !',
      niveau: 'debutant',
      versionCorpus: 'v1',
    );

    test('fragments, sources après validation, corps minimal', () async {
      final requetes = <http.BaseRequest>[];
      final fragments = <String>[];
      final r = await _api(
        (_) async => _flux(
          _sse([
            ('meta', {'meme_version': true}),
            ('delta', {'text': 'Règle : '}),
            ('delta', {'text': 'dites Madame.'}),
            (
              'sources',
              {
                'sources': [
                  {
                    'fiche': 'cor-f-appel',
                    'titre': 'S’adresser',
                    'validee': false,
                    'sources': [
                      {'titre': 'BDL', 'editeur': 'OQLF', 'url': 'https://x'},
                    ],
                  },
                ],
              },
            ),
            ('done', {}),
          ]),
        ),
        requetes: requetes,
      ).tuteur(demande, surFragment: fragments.add);
      final ok = r as SuccesApi<ReponseTuteur>;
      expect(fragments, ['Règle : ', 'dites Madame.']);
      expect(ok.valeur.texte, 'Règle : dites Madame.');
      expect(ok.valeur.sources.single.references.single.editeur, 'OQLF');
      final corps = jsonDecode((requetes.single as http.Request).body) as Map;
      expect(corps, {
        'action': 'erreur',
        'fiches': ['cor-f-appel'],
        'exercice': 'cor-l1-e1',
        'reponse': 'Salut !',
        'niveau': 'debutant',
        'corpus_version': 'v1',
      });
      expect(requetes.single.url.path, '/api/v1/apprentissage/tuteur');
      expect(requetes.single.headers['Authorization'], 'Bearer jeton');
    });

    test('erreur du fournisseur, quota, jeton expiré, réseau', () async {
      final erreur = await _api(
        (_) async => _flux(
          _sse([
            ('delta', {'text': 'Début'}),
            ('error', {'code': 'llm_refus', 'message': 'Refusé.'}),
          ]),
        ),
      ).tuteur(demande);
      final e = erreur as EchecApi<ReponseTuteur>;
      expect(e.type, ErreurApi.iaIndisponible);
      expect(e.detail, 'Refusé.');

      final quota = await _api(
        (_) async => _flux(jsonEncode({'detail': {'kind': 'messages'}}), 429),
      ).tuteur(demande);
      expect((quota as EchecApi).type, ErreurApi.quotaAtteint);

      var appels = 0;
      final renouvele = await _api((r) async {
        appels++;
        if (r.headers['Authorization'] == 'Bearer jeton') {
          return _flux(jsonEncode({'detail': 'Token expiré'}), 401);
        }
        return _flux(_sse([('delta', {'text': 'Ok'}), ('done', {})]));
      }).tuteur(demande);
      expect(renouvele, isA<SuccesApi<ReponseTuteur>>());
      expect(appels, 2);

      final reseau = await _api((_) async => throw http.ClientException('x'))
          .tuteur(demande);
      expect((reseau as EchecApi).type, ErreurApi.injoignable);

      final coupe = await _api(
        (_) async => _flux(_sse([('delta', {'text': 'à moitié'})])),
      ).tuteur(demande);
      expect((coupe as EchecApi).type, ErreurApi.fluxInterrompu);
    });
  });

  group('séance du tuteur', () {
    test('sans compte : message clair, aucun appel', () async {
      final s = SessionTuteur(null);
      await s.demander(const DemandeTuteur(action: ActionTuteur.exemple));
      expect(s.etat, EtatTuteur.erreur);
      expect(s.erreur, SessionTuteur.sansCompte);
      s.dispose();
    });

    test('texte en direct, sources à la fin ; panne → Réessayer', () async {
      var panne = true;
      final etapes = <String>[];
      final s = SessionTuteur((d, {annulation, surFragment}) async {
        if (panne) return const EchecApi(ErreurApi.injoignable);
        surFragment?.call('Exemple : ');
        etapes.add('fragment');
        return const SuccesApi(
          ReponseTuteur(texte: 'Exemple : bonjour', sources: []),
        );
      });
      await s.demander(const DemandeTuteur(action: ActionTuteur.exemple));
      expect(s.etat, EtatTuteur.erreur);
      expect(s.erreur, contains('Internet'));
      panne = false;
      await s.reessayer();
      expect(s.etat, EtatTuteur.termine);
      expect(s.texte, 'Exemple : bonjour');
      expect(etapes, ['fragment']);
      s.dispose();
    });

    test('annulation : la requête est abandonnée, texte reçu gardé', () async {
      final fin = Completer<ResultatApi<ReponseTuteur>>();
      Future<void>? annulationRecue;
      final s = SessionTuteur((d, {annulation, surFragment}) {
        annulationRecue = annulation;
        surFragment?.call('Début');
        return fin.future;
      });
      unawaited(s.demander(const DemandeTuteur(action: ActionTuteur.exemple)));
      await Future<void>.delayed(Duration.zero);
      s.annuler();
      var annulee = false;
      await annulationRecue!.then((_) => annulee = true);
      expect(annulee, isTrue);
      expect(s.etat, EtatTuteur.termine);
      expect(s.texte, 'Début');
      fin.complete(const EchecApi(ErreurApi.annulee));
      await Future<void>.delayed(Duration.zero);
      expect(s.texte, 'Début');
      s.dispose();
    });

    test('lignes typées : règle, exemple, conseil, réussi, à améliorer', () {
      final l = lignesTuteur(
        'Règle : a\nExemple : b\n\nConseil : c\nRéussi : d\nÀ améliorer : e\nfin',
      );
      expect(l.map((x) => x.$1), [
        GenreLigne.regle,
        GenreLigne.exemple,
        GenreLigne.conseil,
        GenreLigne.reussi,
        GenreLigne.ameliorer,
        GenreLigne.texte,
      ]);
      expect(l.first.$2, 'a');
    });
  });

  group('dialogue et oral', () {
    test('historique partagé, ouverture jamais renvoyée, bilan', () async {
      final demandes = <DemandeTuteur>[];
      final d = DialogueSituation(
        situation: _situation,
        appel: (dm, {annulation, surFragment}) async {
          demandes.add(dm);
          surFragment?.call('Très ');
          return const SuccesApi(ReponseTuteur(texte: 'Très bien. Et ensuite ?', sources: []));
        },
      );
      expect(d.bilanPossible, isFalse);
      final r = await d.repondre('Je suis motivé.');
      expect(r, 'Très bien. Et ensuite ?');
      expect(d.repliques.map((x) => x.deJarvis), [true, false, true]);
      final envoyee = demandes.single.versJson();
      expect(envoyee['action'], 'dialogue');
      expect(envoyee['oral'], isTrue);
      expect(envoyee['historique'], [
        {'role': 'eleve', 'texte': 'Je suis motivé.'},
      ]);
      expect(d.bilanPossible, isTrue);
      expect(d.demandeBilan().versJson()['historique'], hasLength(2));
      d.dispose();
    });

    test('l’oral emprunte LA session vocale puis rend son répondeur', () async {
      final (voix, reco, tts) = _voix();
      Future<ReponseVocale?> chat(
        String phrase, {
        void Function(String fragment)? surFragment,
      }) async => const ReponseVocale('chat', source: SourceReponse.locale);
      voix.repondeur = chat;
      final d = DialogueSituation(
        situation: _situation,
        appel: (dm, {annulation, surFragment}) async =>
            const SuccesApi(ReponseTuteur(texte: 'Merci. Pourquoi ce poste ?', sources: [])),
      );
      expect(OralSituation.empechement(voix, d), isNull);
      final oral = OralSituation(voix, d);
      await oral.ouvrir();
      expect(tts.dits.first, contains('Bonjour, présentez-vous'));
      expect(voix.actif, isTrue);
      expect(voix.repondeur, isNot(same(chat)));
      // Une phrase reconnue : réponse du dialogue, dite par la même voix.
      reco.phrase!('Je veux apprendre.');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(d.repliques.last.texte, 'Merci. Pourquoi ce poste ?');
      expect(tts.dits.last, contains('Pourquoi ce poste'));
      await oral.fermer();
      expect(voix.actif, isFalse);
      expect(voix.repondeur, same(chat));
      voix.dispose();
      d.dispose();
    });

    test('oral refusé pendant un chat vocal, sans voix ou sans compte', () async {
      final (voix, _, _) = _voix();
      final sansCompte = DialogueSituation(situation: _situation, appel: null);
      expect(OralSituation.empechement(null, sansCompte), OralIndisponible.sansVoix);
      expect(OralSituation.empechement(voix, sansCompte), OralIndisponible.sansCompte);
      final d = DialogueSituation(
        situation: _situation,
        appel: (dm, {annulation, surFragment}) async =>
            const SuccesApi(ReponseTuteur(texte: 'x', sources: [])),
      );
      await voix.demarrer();
      expect(OralSituation.empechement(voix, d), OralIndisponible.chatVocal);
      await voix.arreter();
      voix.dispose();
      d.dispose();
      sansCompte.dispose();
    });
  });
}
