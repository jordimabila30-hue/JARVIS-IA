// Phase 2 : conversation avec l'IA du serveur (FastAPI → GroqCloud).
// Le serveur est simulé (MockClient) : flux SSE réel (meta, delta, done,
// error), refus HTTP, coupures. Aucun appel réseau.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/detecteur_intention.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_hybride.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_ia.dart';
import 'package:ia_jarvis/services/flux_sse.dart';

const _uuidA = '11111111-1111-4111-8111-111111111111';
const _uuidB = '22222222-2222-4222-8222-222222222222';

String _evenement(String type, Map<String, Object?> donnees) =>
    'event: $type\ndata: ${jsonEncode(donnees)}\n\n';

/// Flux complet tel que l'envoie `POST /api/v1/chat/stream`.
String _flux(String conversation, List<String> fragments) => [
  _evenement('meta', {
    'conversation_id': conversation,
    'message_id': 'm1',
    'quota': {},
  }),
  for (final f in fragments) _evenement('delta', {'text': f}),
  _evenement('done', {'message_id': 'm1', 'usage': {}, 'quota': {}}),
].join();

http.Response _sse(String corps) => http.Response.bytes(
  utf8.encode(corps),
  200,
  headers: {'content-type': 'text/event-stream; charset=utf-8'},
);

http.Response _json(int statut, Object corps) => http.Response.bytes(
  utf8.encode(jsonEncode(corps)),
  statut,
  headers: {'content-type': 'application/json'},
);

/// Serveur simulé : garde les requêtes reçues, répond avec [reponse].
class _Serveur {
  _Serveur(this.reponse);

  http.Response Function(Map<String, dynamic> corps, int n) reponse;
  final requetes = <http.Request>[];

  /// Réponse retenue jusqu'à ce que ce futur se termine (réponse lente).
  Future<void>? attente;

  List<Map<String, dynamic>> get corps => [
    for (final r in requetes) jsonDecode(r.body) as Map<String, dynamic>,
  ];

  late final client = MockClient((r) async {
    requetes.add(r);
    await attente;
    return reponse(jsonDecode(r.body) as Map<String, dynamic>, requetes.length);
  });

  ApiJarvis api({
    Future<String?> Function()? jeton,
    Future<String?> Function()? renouveler,
  }) => ApiJarvis(
    adresse: Uri.parse('http://localhost:8000'),
    jeton: jeton ?? () async => 'jeton-acces',
    renouveler: renouveler,
    client: client,
  );
}

/// Serveur qui répond « Réponse n » dans la conversation demandée, ou une
/// nouvelle (A, puis B…).
_Serveur _serveurIA() {
  var creees = 0;
  return _Serveur((corps, n) {
    final id =
        corps['conversation_id'] as String? ??
        (creees++ == 0 ? _uuidA : _uuidB);
    return _sse(_flux(id, ['Réponse ', '$n.']));
  });
}

ConversationSession _session(_Serveur s) => ConversationSession(
  delaiReflexion: Duration.zero,
  moteur: MoteurConversationHybride(ia: MoteurConversationIA(s.api())),
);

void main() {
  group('Décodeur SSE', () {
    test('paquets coupés au milieu d’une ligne et d’un caractère', () async {
      final octets = utf8.encode(
        ': ping\r\n'
        'event: delta\r\ndata: {"text":"Été à Montréal"}\r\n\r\n'
        'event: done\ndata: {}\n\n'
        'event: delta\ndata: {"text":"inachevé"}\n',
      );
      // Coupe tous les 3 octets : « É » (2 octets) est coupé en deux.
      final paquets = [
        for (var i = 0; i < octets.length; i += 3)
          octets.sublist(i, (i + 3).clamp(0, octets.length)),
      ];
      final evenements = await decoderSse(
        Stream.fromIterable(paquets),
      ).toList();
      expect(evenements.map((e) => e.type), ['delta', 'done']);
      expect(evenements.first.donnees, '{"text":"Été à Montréal"}');
    });
  });

  group('ApiJarvis.discuter (POST /api/v1/chat/stream)', () {
    test('flux complet : texte reconstitué, conversation créée', () async {
      final s = _Serveur(
        (_, _) => _sse(_flux(_uuidA, ['Paris est ', 'la capitale.'])),
      );
      final fragments = <String>[];
      String? conversation;
      final r = await s.api().discuter(
        'Quelle est la capitale de la France ?',
        surConversation: (id) => conversation = id,
        surFragment: fragments.add,
      );
      final reponse = (r as SuccesApi<ReponseChat>).valeur;
      expect(reponse.texte, 'Paris est la capitale.');
      expect(reponse.conversation, _uuidA);
      expect(conversation, _uuidA);
      expect(fragments, ['Paris est ', 'la capitale.']);

      final requete = s.requetes.single;
      expect(requete.method, 'POST');
      expect(
        requete.url.toString(),
        'http://localhost:8000/api/v1/chat/stream',
      );
      expect(requete.headers['Authorization'], 'Bearer jeton-acces');
      // Seul le nouveau message : l'historique est gardé par le serveur.
      expect(s.corps.single, {
        'message': 'Quelle est la capitale de la France ?',
        'conversation_id': null,
      });
    });

    test('conversation existante : son UUID est envoyé', () async {
      final s = _Serveur((_, _) => _sse(_flux(_uuidA, ['Oui.'])));
      await s.api().discuter('Et ensuite ?', conversation: _uuidA);
      expect(s.corps.single['conversation_id'], _uuidA);
    });

    test('événement error : message du serveur, rien de partiel', () async {
      final s = _Serveur(
        (_, _) => _sse(
          _evenement('meta', {'conversation_id': _uuidA}) +
              _evenement('delta', {'text': 'Début'}) +
              _evenement('error', {
                'code': 'llm_rate_limit',
                'message': 'Le service IA est très sollicité.',
              }),
        ),
      );
      String? conversation;
      final r =
          await s.api().discuter(
                'Bonjour',
                surConversation: (id) {
                  conversation = id;
                },
              )
              as EchecApi;
      expect(r.type, ErreurApi.iaIndisponible);
      expect(r.detail, 'Le service IA est très sollicité.');
      // La conversation serveur existe quand même : elle reste rattachée.
      expect(conversation, _uuidA);
    });

    test('flux coupé avant done : interrompu', () async {
      final s = _Serveur(
        (_, _) => _sse(
          _evenement('meta', {'conversation_id': _uuidA}) +
              _evenement('delta', {'text': 'Une réponse incompl'}),
        ),
      );
      final r = await s.api().discuter('Bonjour') as EchecApi;
      expect(r.type, ErreurApi.fluxInterrompu);
    });

    test('réponse vide : échec', () async {
      final s = _Serveur((_, _) => _sse(_flux(_uuidA, ['  '])));
      expect(
        (await s.api().discuter('Bonjour') as EchecApi).type,
        ErreurApi.reponseVide,
      );
    });

    test('quota atteint (429)', () async {
      final s = _Serveur(
        (_, _) => _json(429, {
          'detail': {
            'error': 'quota_exceeded',
            'kind': 'messages',
            'message': 'Limite quotidienne de messages atteinte',
            'resets_in': 3 * 3600 - 20,
            'resets_at': DateTime.now().toUtc().add(const Duration(hours: 3)).toIso8601String(),
            'quota': {'resets_in': 3 * 3600 - 20},
          },
        }),
      );
      final r = await s.api().discuter('Bonjour') as EchecApi;
      expect(r.type, ErreurApi.quotaAtteint);
      expect(r.detail, startsWith('Votre limite quotidienne de messages est atteinte. Réinitialisation '));
      expect(MoteurConversationIA.messageErreur(r.type, r.detail), r.detail);
    });

    test('jeton expiré : renouvelé, un seul nouvel essai', () async {
      final jetons = <String?>[];
      final s = _Serveur((_, n) {
        return n == 1
            ? _json(401, {'detail': 'Token expiré'})
            : _sse(_flux(_uuidA, ['Bonjour.']));
      });
      final api = s.api(renouveler: () async => 'jeton-neuf');
      final r = await api.discuter('Salut, explique-moi les volcans');
      expect(r, isA<SuccesApi<ReponseChat>>());
      for (final q in s.requetes) {
        jetons.add(q.headers['Authorization']);
      }
      expect(jetons, ['Bearer jeton-acces', 'Bearer jeton-neuf']);
    });

    test('session réellement expirée : reconnexion demandée', () async {
      final s = _Serveur((_, _) => _json(401, {'detail': 'Token expiré'}));
      final r =
          await s.api(renouveler: () async => null).discuter('Bonjour')
              as EchecApi;
      expect(r.type, ErreurApi.sessionExpiree);
      expect(s.requetes, hasLength(1));
    });

    test('jeton invalide : refusé, sans nouvel essai', () async {
      final s = _Serveur((_, _) => _json(401, {'detail': 'Token invalide'}));
      final r =
          await s.api(renouveler: () async => 'x').discuter('Bonjour')
              as EchecApi;
      expect(r.type, ErreurApi.jetonRefuse);
      expect(s.requetes, hasLength(1));
    });

    test('sans session : aucun appel', () async {
      final s = _serveurIA();
      final r =
          await s.api(jeton: () async => null).discuter('Bonjour') as EchecApi;
      expect(r.type, ErreurApi.nonConnecte);
      expect(s.requetes, isEmpty);
    });

    test('message trop long : refusé avant l’envoi', () async {
      final s = _serveurIA();
      final r = await s.api().discuter('a' * 8001) as EchecApi;
      expect(r.type, ErreurApi.messageTropLong);
      expect(s.requetes, isEmpty);
    });

    test('serveur arrêté, erreur interne, conversation inconnue', () async {
      final arrete = ApiJarvis(
        adresse: Uri.parse('http://localhost:8000'),
        jeton: () async => 'j',
        client: MockClient((_) async => throw http.ClientException('refus')),
      );
      expect(
        (await arrete.discuter('Bonjour') as EchecApi).type,
        ErreurApi.injoignable,
      );
      final erreur = _Serveur((_, _) => _json(500, {'detail': 'Boum'}));
      expect(
        (await erreur.api().discuter('Bonjour') as EchecApi).type,
        ErreurApi.serveur,
      );
      final inconnue = _Serveur(
        (_, _) => _json(404, {'detail': 'Conversation introuvable'}),
      );
      expect(
        (await inconnue.api().discuter('Bonjour') as EchecApi).type,
        ErreurApi.conversationIntrouvable,
      );
    });

    test('après done, la connexion est lue jusqu’à sa fermeture', () async {
      final flux = StreamController<List<int>>();
      flux.add(utf8.encode(_flux(_uuidA, ['Complète.'])));
      final api = ApiJarvis(
        adresse: Uri.parse('http://localhost:8000'),
        jeton: () async => 'j',
        delaiInactivite: const Duration(milliseconds: 50),
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(flux.stream, 200),
        ),
      );
      final attente = api.discuter('Bonjour');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Pas encore d'issue : le client attend la fermeture du flux.
      expect(flux.hasListener, isTrue);
      await flux.close();
      final r = await attente;
      expect((r as SuccesApi<ReponseChat>).valeur.texte, 'Complète.');
    });

    test('serveur muet en plein flux : délai dépassé', () async {
      final flux = StreamController<List<int>>();
      flux.add(utf8.encode(_evenement('meta', {'conversation_id': _uuidA})));
      final api = ApiJarvis(
        adresse: Uri.parse('http://localhost:8000'),
        jeton: () async => 'j',
        delaiInactivite: const Duration(milliseconds: 50),
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(flux.stream, 200),
        ),
      );
      final r = await api.discuter('Bonjour') as EchecApi;
      expect(r.type, ErreurApi.delaiDepasse);
      await flux.close();
    });
  });

  test('Markdown du modèle : texte simple à afficher et à dire', () {
    expect(
      MoteurConversationIA.texteSimple(
        '## Réponse\nLa capitale du Pérou est **Lima**, une *grande* ville.\n'
        '- `Cusco` : ancienne capitale\n- 2 * 3 = 6',
      ),
      'Réponse\nLa capitale du Pérou est Lima, une grande ville.\n'
      '- Cusco : ancienne capitale\n- 2 * 3 = 6',
    );
  });

  group('Identifiants de conversation (local → serveur)', () {
    test(
      'même fil : même conversation serveur ; nouveau fil : une autre',
      () async {
        final s = _serveurIA();
        final ia = MoteurConversationIA(s.api());
        DemandeJarvis d(String id) => DemandeJarvis(
          texte: 'Question',
          intention: IntentionMessage.discussion,
          idConversation: id,
        );
        await ia.repondre(d('local-1'));
        await ia.repondre(d('local-1'));
        await ia.repondre(d('local-2'));
        expect(s.corps.map((c) => c['conversation_id']), [null, _uuidA, null]);
        expect(ia.idServeur('local-1'), _uuidA);
        expect(ia.idServeur('local-2'), _uuidB);
      },
    );

    test(
      'conversation effacée côté serveur : une nouvelle, une fois',
      () async {
        // Première réponse : la conversation A est créée et rattachée.
        final s = _Serveur((_, _) => _sse(_flux(_uuidA, ['Un.'])));
        final ia = MoteurConversationIA(s.api());
        const d = DemandeJarvis(
          texte: 'Question',
          intention: IntentionMessage.discussion,
          idConversation: 'local-1',
        );
        await ia.repondre(d);
        s.reponse = (corps, _) => corps['conversation_id'] == _uuidA
            ? _json(404, {'detail': 'Conversation introuvable'})
            : _sse(_flux(_uuidB, ['Deux.']));
        final r = await ia.repondre(d);
        expect(r.texte, 'Deux.');
        expect(r.erreur, isFalse);
        expect(s.corps.map((c) => c['conversation_id']), [null, _uuidA, null]);
        expect(ia.idServeur('local-1'), _uuidB);
      },
    );
  });

  group('Moteur hybride dans la conversation', () {
    test('TEST A : commandes locales, sans appel à l’IA', () async {
      final s = _serveurIA();
      final c = _session(s);
      await c.envoyer('Quelle heure est-il ?');
      await c.envoyer('Combien font 12 fois 8 ?');
      await c.envoyer('Je m’appelle Jordi');
      await c.envoyer('Comment je m’appelle ?');
      await c.envoyer('C’est quoi Flutter ?');
      await c.envoyer('Merci');
      expect(s.requetes, isEmpty);
      expect(c.messages[3].texte, contains('96'));
      expect(c.messages[7].texte, 'Vous vous appelez Jordi.');
    });

    test('TEST B : question inconnue → IA, réponse dans le fil', () async {
      final s = _serveurIA();
      final c = _session(s);
      await c.envoyer('Quelle est la capitale du Canada ?');
      expect(s.corps.single['message'], 'Quelle est la capitale du Canada ?');
      expect(c.messages.map((m) => m.auteur), [
        AuteurMessage.utilisateur,
        AuteurMessage.jarvis,
      ]);
      expect(c.messages.last.texte, 'Réponse 1.');
      expect(c.enReflexion, isFalse);
    });

    test(
      'vraies questions qui contiennent un mot des règles locales',
      () async {
        final s = _serveurIA();
        final c = _session(s);
        for (final q in [
          'Ok, et pour l’Espagne ?',
          'Aide-moi à écrire une lettre de motivation',
          'Que dois-je préparer pour mon entretien demain ?',
          'À quelle heure ouvre généralement une banque ?',
          'Explique-moi la différence entre Flutter et React Native',
          'Est-ce que tu es une IA ?',
          'Bonjour JARVIS, peux-tu me résumer la Révolution française ?',
        ]) {
          await c.envoyer(q);
        }
        expect(s.requetes, hasLength(7));
      },
    );

    test('TEST C : même conversation serveur pour la suite', () async {
      final s = _serveurIA();
      final c = _session(s);
      await c.envoyer('Qui a écrit Les Misérables ?');
      await c.envoyer('Et quel âge avait-il ?');
      expect(s.corps.map((x) => x['conversation_id']), [null, _uuidA]);
      // Jamais l'historique du fil : le serveur l'a déjà.
      expect(
        s.corps.last.keys,
        unorderedEquals(['message', 'conversation_id']),
      );
    });

    test('TEST D : nouvelle conversation, contexte serveur distinct', () async {
      final s = _serveurIA();
      final c = _session(s);
      await c.envoyer('Parle-moi des volcans');
      final premiere = c.idCourant!;
      c.effacer();
      await c.envoyer('Parle-moi des océans');
      await c.envoyer('Combien y en a-t-il ?');
      expect(s.corps.map((x) => x['conversation_id']), [null, null, _uuidB]);
      // Retour à la première : sa conversation serveur reprend.
      expect(c.ouvrir(premiere), isTrue);
      await c.envoyer('Lequel est le plus haut ?');
      expect(s.corps.last['conversation_id'], _uuidA);
    });

    test('conversation collée : analysée localement, jamais envoyée', () async {
      final s = _serveurIA();
      final c = _session(s);
      await c.envoyer(
        'Sarah : Tu viens ce soir ?\nMoi : Je ne sais pas encore.\n'
        'Sarah : Réponds-moi vite.\n\nRésume cette conversation.',
      );
      await c.envoyer('Qu’est-ce que je peux répondre ?');
      expect(s.requetes, isEmpty);
    });

    test('« répète » redit la réponse de l’IA', () async {
      final s = _serveurIA();
      final c = _session(s);
      await c.envoyer('Quelle est la capitale du Japon ?');
      await c.envoyer('Répète');
      expect(s.requetes, hasLength(1));
      expect(c.messages.last.texte, 'Je disais : Réponse 1.');
    });

    test('TEST F : serveur injoignable, puis de nouveau joignable', () async {
      var panne = true;
      final s = _Serveur((_, n) {
        if (panne) throw http.ClientException('Connexion refusée');
        return _sse(_flux(_uuidA, ['Enfin.']));
      });
      final c = _session(s);
      await c.envoyer('Quelle est la capitale du Pérou ?');
      expect(c.enReflexion, isFalse);
      expect(c.messages.first.texte, 'Quelle est la capitale du Pérou ?');
      expect(c.messages.last.texte, contains('joindre le serveur'));
      // Les commandes locales restent disponibles.
      await c.envoyer('Combien font 2 plus 3 ?');
      expect(c.messages.last.texte, contains('5'));
      panne = false;
      await c.envoyer('Quelle est la capitale du Pérou ?');
      expect(c.messages.last.texte, 'Enfin.');
    });

    test('TEST F : quota atteint, sans compte', () async {
      final quota = _Serveur(
        (_, _) => _json(429, {
          'detail': {
            'message': 'Limite quotidienne de messages atteinte',
            'quota': {'resets_in': 1200},
          },
        }),
      );
      final c = _session(quota);
      await c.envoyer('Raconte-moi l’histoire de Rome');
      // Refus sans type de limite (ancien serveur) : message générique.
      expect(c.messages.last.texte, 'Vous avez atteint votre limite d’utilisation de l’IA.');

      final sansCompte = _serveurIA();
      final c2 = ConversationSession(
        delaiReflexion: Duration.zero,
        moteur: MoteurConversationHybride(
          ia: MoteurConversationIA(sansCompte.api(jeton: () async => null)),
        ),
      );
      await c2.envoyer('Raconte-moi l’histoire de Rome');
      expect(c2.messages.last.texte, startsWith('Connectez-vous'));
      expect(sansCompte.requetes, isEmpty);
    });

    test('TEST E : vocal, même moteur et même conversation serveur', () async {
      final s = _serveurIA();
      final c = _session(s);
      await c.envoyer('Parle-moi de la Lune');
      final r = await c.repondreVocal('Et quelle est sa distance à la Terre ?');
      expect(r!.texte, 'Réponse 2.');
      expect(r.terminerSession, isFalse);
      expect(s.corps.last['conversation_id'], _uuidA);
      expect(c.messages.last.vocal, isTrue);
      // « Au revoir » reste local et termine le chat vocal.
      final fin = await c.repondreVocal('Au revoir JARVIS');
      expect(fin!.terminerSession, isTrue);
      expect(s.requetes, hasLength(2));
    });

    test('vocal en erreur : jamais bloqué, explication à dire', () async {
      final s = _Serveur((_, _) => throw http.ClientException('hors ligne'));
      final c = _session(s);
      final r = await c.repondreVocal('Quelle est la capitale du Chili ?');
      expect(r!.texte, contains('joindre le serveur'));
      expect(c.enReflexion, isFalse);
    });

    test(
      'réponse tardive : rangée dans sa conversation, pas le fil affiché',
      () async {
        final feu = Completer<void>();
        final s = _Serveur((_, _) => _sse(_flux(_uuidA, ['Tardive.'])))
          ..attente = feu.future;
        final c = _session(s);
        final envoi = c.envoyer('Une longue question ?');
        // La question est partie : le serveur prépare la réponse.
        while (s.requetes.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        final premiere = c.idCourant!;
        c.effacer();
        feu.complete();
        await envoi;
        // Le nouveau fil reste vide.
        expect(c.vide, isTrue);
        final archivee = c.archives.single;
        expect(archivee.id, premiere);
        expect(archivee.messages.map((m) => m.texte), [
          'Une longue question ?',
          'Tardive.',
        ]);
        // « Répète » dans le nouveau fil ne redit pas l'autre conversation.
        await c.envoyer('Répète');
        expect(c.messages.last.texte, isNot(contains('Tardive')));
      },
    );

    test('fil changé pendant la réflexion : rien n’est envoyé', () async {
      final s = _serveurIA();
      final c = ConversationSession(
        delaiReflexion: const Duration(milliseconds: 30),
        moteur: MoteurConversationHybride(ia: MoteurConversationIA(s.api())),
      );
      final envoi = c.envoyer('Une question ?');
      await Future<void>.delayed(Duration.zero);
      c.effacer();
      await envoi;
      expect(s.requetes, isEmpty);
      expect(c.enReflexion, isFalse);
    });

    test('réponse tardive d’une conversation supprimée : perdue', () async {
      final feu = Completer<void>();
      final s = _serveurIA()..attente = feu.future;
      final c = _session(s);
      final envoi = c.envoyer('Une question ?');
      while (s.requetes.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(c.supprimer(c.idCourant!), isTrue);
      feu.complete();
      await envoi;
      expect(c.vide, isTrue);
      expect(c.archives, isEmpty);
    });
  });

  group('Propositions en préparation (aucun écran figé)', () {
    test('événement `preparation` : signalé, texte final inchangé', () async {
      final s = _Serveur(
        (_, _) => _sse(
          [
            _evenement('meta', {'conversation_id': _uuidA, 'message_id': 'm1'}),
            _evenement('delta', {'text': 'Voici des idées.'}),
            _evenement('preparation', {'message_id': 'm1', 'etape': 'propositions'}),
            _evenement('evenement_inconnu', {'x': 1}),
            _evenement('done', {'message_id': 'm1', 'usage': {}, 'quota': {}}),
          ].join(),
        ),
      );
      var preparations = 0;
      final r = await s.api().discuter(
        'Propose-moi des réponses',
        surPreparation: () => preparations++,
      );
      expect((r as SuccesApi<ReponseChat>).valeur.texte, 'Voici des idées.');
      expect(preparations, 1);
    });

    test('la bulle garde un indicateur vivant jusqu’à la fin du flux', () async {
      final flux = StreamController<List<int>>();
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          flux.stream,
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final c = ConversationSession(
        delaiReflexion: Duration.zero,
        moteur: MoteurConversationHybride(
          ia: MoteurConversationIA(
            ApiJarvis(
              adresse: Uri.parse('http://localhost:8000'),
              jeton: () async => 'jeton-acces',
              client: client,
            ),
          ),
        ),
      );
      final envoi = c.envoyer('Propose-moi des réponses pour Lina');
      flux.add(
        utf8.encode(
          _evenement('meta', {'conversation_id': _uuidA, 'message_id': 'm1'}) +
              _evenement('delta', {'text': 'Voici des idées.'}),
        ),
      );
      await pumpEventQueue();
      final bulle = c.messages.last;
      expect(bulle.auteur, AuteurMessage.jarvis);
      expect(c.preparationEnCours(bulle.id), isFalse);
      // Texte fini, lots en cours côté serveur : indicateur, chat vivant.
      flux.add(utf8.encode(_evenement('preparation', {'message_id': 'm1'})));
      await pumpEventQueue();
      expect(c.preparationEnCours(bulle.id), isTrue);
      expect(c.messages.last.redaction, isTrue);
      flux.add(
        utf8.encode(
          _evenement('done', {'message_id': 'm1', 'usage': {}, 'quota': {}}),
        ),
      );
      await flux.close();
      await envoi;
      expect(c.preparationEnCours(bulle.id), isFalse);
      expect(c.messages.last.texte, 'Voici des idées.');
    });
  });
}
