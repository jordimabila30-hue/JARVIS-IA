// Phase 3 : conversations JARVIS enregistrées sur le serveur, retrouvées
// d'un appareil à l'autre. Supabase est simulé (_DepotFaux) ; le backend
// aussi (_Backend) : il enregistre chaque échange avec l'IA dans le dépôt,
// comme FastAPI le fait dans la table `messages`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/conversations/source_conversation.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_hybride.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_ia.dart';
import 'package:ia_jarvis/services/conversations/conversations_multicanal.dart';
import 'package:ia_jarvis/services/conversations/correspondance_conversations.dart';
import 'package:ia_jarvis/services/conversations/depot_conversations.dart';
import 'package:ia_jarvis/services/conversations/epingles_conversations.dart';
import 'package:ia_jarvis/services/conversations/fournisseur_jarvis.dart';
import 'package:ia_jarvis/services/conversations/synchro_echanges_locaux.dart';
import 'package:ia_jarvis/services/conversations/synchronisation_conversations.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _b = 'bbbbbbbb-0000-4000-8000-000000000002';

final _t0 = DateTime(2026, 10, 13, 9);

/// Tables `conversations` et `messages` d'un compte, en mémoire.
class _DepotFaux implements DepotConversations {
  @override
  String? utilisateur = 'compte-a';

  final titres = <String, String>{};
  final lignes = <String, List<MessageServeur>>{};
  EchecSynchro? panne;
  int listes = 0;
  int lectures = 0;
  var _n = 0;

  void conversation(String id, String titre, List<(String, String)> msgs) {
    titres[id] = titre;
    lignes[id] = [];
    for (final (role, texte) in msgs) {
      ajouter(id, role, texte);
    }
  }

  void inserer(String id, MessageServeur m) => lignes[id]!.add(m);

  String ajouter(String id, String role, String texte) {
    final m = MessageServeur(
      id: 'm${_n++}',
      role: role,
      contenu: texte,
      date: _t0.add(Duration(minutes: _n)),
    );
    lignes[id]!.add(m);
    return m.id;
  }

  @override
  Future<List<ConversationServeur>> lister({int limite = 100}) async {
    if (panne case final p?) throw p;
    listes++;
    DateTime activite(String id) => lignes[id]!.lastOrNull?.date ?? _t0;
    final ids = [...lignes.keys]
      ..sort((x, y) => activite(y).compareTo(activite(x)));
    return [
      for (final id in ids)
        ConversationServeur(
          id: id,
          titre: titres[id]!,
          derniereActivite: activite(id),
          apercu: lignes[id]!.lastOrNull?.contenu ?? '',
        ),
    ];
  }

  @override
  Future<PageMessages> messages(
    String id, {
    DateTime? avant,
    int limite = 50,
  }) async {
    if (panne case final p?) throw p;
    lectures++;
    final toutes = lignes[id];
    if (toutes == null) throw const EchecSynchro(ErreurSynchro.introuvable);
    final avantes = [
      for (final m in toutes)
        if (avant == null || m.date.isBefore(avant)) m,
    ];
    final debut = avantes.length > limite ? avantes.length - limite : 0;
    return PageMessages(avantes.sublist(debut), plusAnciens: debut > 0);
  }

  @override
  Future<void> supprimer(String id) async {
    if (panne case final p?) throw p;
    if (lignes.remove(id) == null) {
      throw const EchecSynchro(ErreurSynchro.introuvable);
    }
    titres.remove(id);
  }
}

/// Backend simulé : chaque question crée (ou reprend) une conversation
/// serveur et enregistre la question et la réponse dans le dépôt.
class _Backend {
  _Backend(this.depot);

  final _DepotFaux depot;
  final corps = <Map<String, dynamic>>[];

  /// Échanges locaux reçus (route `local-exchanges`).
  final locaux = <Map<String, dynamic>>[];
  bool horsLigne = false;
  var _nouvelles = 0;

  /// `POST /api/v1/conversations/local-exchanges`, comme FastAPI : rien
  /// n'est généré, l'échange est rangé dans la conversation du compte.
  http.Response _local(Map<String, dynamic> c) {
    locaux.add(c);
    final q = c['question_id'] as String;
    for (final e in depot.lignes.entries) {
      if (e.value.any((m) => m.id == q)) {
        return http.Response('{"conversation_id":"${e.key}"}', 200);
      }
    }
    var id = c['conversation_id'] as String?;
    if (id != null && !depot.lignes.containsKey(id)) {
      return http.Response('{"detail":"Conversation introuvable"}', 404);
    }
    id ??= 'locale-${_nouvelles++}';
    depot.lignes.putIfAbsent(id, () => []);
    depot.titres.putIfAbsent(id, () => c['question'] as String);
    depot.inserer(
      id,
      MessageServeur(
        id: q,
        role: 'user',
        contenu: c['question'] as String,
        date: DateTime.parse(c['question_at'] as String).toLocal(),
      ),
    );
    depot.inserer(
      id,
      MessageServeur(
        id: c['answer_id'] as String,
        role: 'assistant',
        contenu: c['answer'] as String,
        date: DateTime.parse(c['answer_at'] as String).toLocal(),
      ),
    );
    return http.Response('{"conversation_id":"$id"}', 201);
  }

  late final api = ApiJarvis(
    adresse: Uri.parse('http://localhost:8000'),
    jeton: () async => 'jeton',
    client: MockClient((r) async {
      if (horsLigne) throw http.ClientException('Réseau indisponible');
      final c = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.url.path.endsWith('/local-exchanges')) return _local(c);
      corps.add(c);
      final message = c['message'] as String;
      var id = c['conversation_id'] as String?;
      if (id != null && !depot.lignes.containsKey(id)) {
        return http.Response('{"detail":"Conversation introuvable"}', 404);
      }
      id ??= 'nouvelle-${_nouvelles++}';
      depot.lignes.putIfAbsent(id, () => []);
      depot.titres.putIfAbsent(id, () => message);
      final reponse = 'Réponse à « $message »';
      depot.ajouter(id, 'user', message);
      final idReponse = depot.ajouter(id, 'assistant', reponse);
      String ev(String t, Object d) => 'event: $t\ndata: ${jsonEncode(d)}\n\n';
      return http.Response.bytes(
        utf8.encode(
          ev('meta', {'conversation_id': id, 'message_id': idReponse}) +
              ev('delta', {'text': reponse}) +
              ev('done', {'message_id': idReponse}),
        ),
        200,
      );
    }),
  );
}

/// Un appareil : sa session, sa liste, son menu. Plusieurs appareils
/// partagent le même dépôt (le même compte).
class _Appareil {
  _Appareil(this.depot, this.backend, {StockageMemoire? stockage}) {
    echanges = SynchroEchangesLocaux(
      compte: depot.utilisateur!,
      compteActuel: () => depot.utilisateur,
      correspondance: correspondance,
      stockage: stockage ?? StockageMemoire(),
      envoyer: (e, conversation) => backend.api.enregistrerEchangeLocal(
        idQuestion: e.idQuestion,
        idReponse: e.idReponse,
        question: e.question,
        reponse: e.reponse,
        conversation: conversation,
        questionA: e.questionA,
        reponseA: e.reponseA,
      ),
    );
    session = ConversationSession(
      delaiReflexion: Duration.zero,
      moteur: MoteurConversationHybride(
        ia: MoteurConversationIA(
          backend.api,
          correspondance: correspondance,
          avantEnvoi: echanges.attendre,
        ),
      ),
      depot: depot,
      correspondance: correspondance,
    )..surEchangeLocal = echanges.ajouter;
    synchro = SynchronisationConversations(depot, intervalle: Duration.zero);
    fournisseur = FournisseurJarvis(
      session,
      synchronisation: synchro,
      echangesLocaux: echanges,
    );
    menu = ConversationsMulticanal(
      fournisseurs: [fournisseur],
      epingles: EpinglesConversations(stockage: StockageMemoire()),
    );
  }

  final _DepotFaux depot;
  final _Backend backend;
  final correspondance = CorrespondanceConversations();
  late final SynchroEchangesLocaux echanges;
  late final ConversationSession session;
  late final SynchronisationConversations synchro;
  late final FournisseurJarvis fournisseur;
  late final ConversationsMulticanal menu;

  List<String> get titres => [
    for (final c in menu.liste(SourceConversation.jarvis)) c.titre,
  ];

  List<String> get fil => [
    for (final m in session.messages) '${m.deJarvis ? 'J' : 'U'}:${m.texte}',
  ];

  Future<void> ouvrir(String titre) async {
    final c = menu
        .liste(SourceConversation.jarvis)
        .firstWhere((c) => c.titre == titre);
    expect(menu.ouvrir(c), isTrue);
    await _attendre();
  }

  Future<void> _attendre() async {
    for (var i = 0; i < 20 && session.chargement; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);
  }

  void fermer() {
    menu.dispose();
    synchro.dispose();
    echanges.dispose();
    session.dispose();
  }
}

void main() {
  late _DepotFaux depot;
  late _Backend backend;

  setUp(() {
    depot = _DepotFaux();
    backend = _Backend(depot);
  });

  group('Liste des conversations', () {
    test('chargée depuis le serveur, la plus récente d’abord', () async {
      depot.conversation(_a, 'Volcans', [
        ('user', 'Les volcans ?'),
        ('assistant', 'Ce sont…'),
      ]);
      depot.conversation(_b, 'Océans', [
        ('user', 'Les océans ?'),
        ('assistant', 'Ils…'),
      ]);
      final x = _Appareil(depot, backend);
      await x.synchro.actualiser();
      expect(x.titres, ['Océans', 'Volcans']);
      expect(x.menu.liste(SourceConversation.jarvis).first.apercu, 'Ils…');
      x.fermer();
    });

    test('actualisations rapprochées : une seule lecture', () async {
      final s = SynchronisationConversations(depot);
      await s.actualiser();
      await s.actualiser();
      expect(depot.listes, 1);
      await s.actualiser(force: true);
      expect(depot.listes, 2);
      // Demandes simultanées : une seule lecture.
      await Future.wait([s.actualiser(force: true), s.actualiser(force: true)]);
      expect(depot.listes, 3);
      s.dispose();
    });

    test('hors connexion : dernière liste gardée, avertissement', () async {
      depot.conversation(_a, 'Volcans', [('user', 'Q'), ('assistant', 'R')]);
      final x = _Appareil(depot, backend);
      await x.synchro.actualiser();
      depot.panne = const EchecSynchro(ErreurSynchro.horsLigne);
      await x.synchro.actualiser(force: true);
      expect(x.titres, ['Volcans']);
      expect(
        x.menu.avertissement(SourceConversation.jarvis),
        startsWith('Hors connexion'),
      );
      depot.panne = null;
      await x.menu.actualiser(SourceConversation.jarvis, force: true);
      expect(x.menu.avertissement(SourceConversation.jarvis), isNull);
      x.fermer();
    });

    test('changement de compte pendant la lecture : réponse ignorée', () async {
      depot.conversation(_a, 'Privée', [('user', 'Q'), ('assistant', 'R')]);
      final s = SynchronisationConversations(depot);
      final lecture = s.actualiser();
      depot.utilisateur = 'compte-b';
      await lecture;
      expect(s.conversations, isEmpty);
      s.dispose();
    });
  });

  group('Ouverture et historique', () {
    test('messages dans l’ordre, contexte serveur repris', () async {
      depot.conversation(_a, 'Volcans', [
        ('user', 'Qui a écrit Les Misérables ?'),
        ('assistant', 'Victor **Hugo**.'),
      ]);
      final x = _Appareil(depot, backend);
      await x.synchro.actualiser();
      await x.ouvrir('Volcans');
      expect(x.fil, [
        'U:Qui a écrit Les Misérables ?',
        // Markdown retiré, comme pour les réponses en direct.
        'J:Victor Hugo.',
      ]);
      expect(x.session.idServeurCourant, _a);
      // Liste : une seule entrée, ouverte.
      final l = x.menu.liste(SourceConversation.jarvis);
      expect(l.single.ouverte, isTrue);
      // Suite : même conversation serveur, seul le nouveau message part.
      await x.session.envoyer('Quel âge avait-il ?');
      expect(backend.corps.single, {
        'message': 'Quel âge avait-il ?',
        'conversation_id': _a,
      });
      x.fermer();
    });

    test('historique long : derniers messages, puis les précédents', () async {
      depot.conversation(_a, 'Long', [
        for (var i = 0; i < 60; i++) (i.isEven ? 'user' : 'assistant', 'm$i'),
      ]);
      final x = _Appareil(depot, backend);
      await x.synchro.actualiser();
      await x.ouvrir('Long');
      expect(x.session.messages, hasLength(50));
      expect(x.session.messages.first.texte, 'm10');
      expect(x.session.plusAnciens, isTrue);
      await x.session.chargerPlusAnciens();
      expect(x.session.messages, hasLength(60));
      expect(x.session.messages.first.texte, 'm0');
      expect(x.session.plusAnciens, isFalse);
      x.fermer();
    });

    test('déjà en mémoire : rouverte sans tout recharger', () async {
      depot.conversation(_a, 'Volcans', [('user', 'Q'), ('assistant', 'R')]);
      final x = _Appareil(depot, backend);
      await x.synchro.actualiser();
      await x.ouvrir('Volcans');
      x.session.effacer();
      final lectures = depot.lectures;
      await x.ouvrir('Volcans');
      expect(x.fil, ['U:Q', 'J:R']);
      // Une seule relecture légère (nouveautés d'un autre appareil).
      expect(depot.lectures, lectures + 1);
      x.fermer();
    });

    test(
      'conversation supprimée ailleurs : expliqué, retirée de la liste',
      () async {
        depot.conversation(_a, 'Volcans', [('user', 'Q'), ('assistant', 'R')]);
        final x = _Appareil(depot, backend);
        await x.synchro.actualiser();
        depot.lignes.remove(_a);
        await x.ouvrir('Volcans');
        expect(x.session.messages.single.provisoire, isTrue);
        expect(x.session.messages.single.texte, contains('n’existe plus'));
        expect(x.synchro.conversations, isEmpty);
        x.fermer();
      },
    );

    test('chargement impossible hors ligne, puis rechargée', () async {
      depot.conversation(_a, 'Volcans', [('user', 'Q'), ('assistant', 'R')]);
      final x = _Appareil(depot, backend);
      await x.synchro.actualiser();
      depot.panne = const EchecSynchro(ErreurSynchro.horsLigne);
      await x.ouvrir('Volcans');
      expect(x.session.messages.single.provisoire, isTrue);
      expect(x.session.chargement, isFalse);
      depot.panne = null;
      await x.session.rafraichir();
      expect(x.fil, ['U:Q', 'J:R']);
      x.fermer();
    });
  });

  group('Deux appareils, un compte', () {
    test(
      'Windows → Web : la conversation et son historique apparaissent',
      () async {
        final windows = _Appareil(depot, backend);
        await windows.session.envoyer('Parle-moi des volcans');
        await windows.session.envoyer('Et le plus haut ?');
        final web = _Appareil(depot, backend);
        await web.synchro.actualiser();
        expect(web.titres, ['Parle-moi des volcans']);
        await web.ouvrir('Parle-moi des volcans');
        expect(web.fil, [
          'U:Parle-moi des volcans',
          'J:Réponse à « Parle-moi des volcans »',
          'U:Et le plus haut ?',
          'J:Réponse à « Et le plus haut ? »',
        ]);
        // Le Web poursuit : même conversation serveur.
        await web.session.envoyer('Et en Europe ?');
        expect(backend.corps.last['conversation_id'], 'nouvelle-0');
        // Windows rafraîchit : le message du Web arrive, sans doublon.
        await windows.session.rafraichir();
        expect(windows.fil, web.fil);
        expect(depot.lignes['nouvelle-0'], hasLength(6));
        windows.fermer();
        web.fermer();
      },
    );

    test('actualisations répétées : jamais de doublon', () async {
      final x = _Appareil(depot, backend);
      await x.session.envoyer('Explique-moi la photosynthèse en détail');
      await x.session.envoyer('Quelle heure est-il ?'); // locale
      await x.session.envoyer('Merci pour ta réponse détaillée !');
      await x.echanges.envoyer();
      for (var i = 0; i < 3; i++) {
        await x.session.rafraichir();
      }
      expect(x.session.messages, hasLength(6));
      // Chaque message est rattaché à sa ligne serveur, IA comme locale.
      expect(x.session.messages.every((m) => m.idServeur != null), isTrue);
      // L'échange local a rejoint la même conversation, sans appel à l'IA.
      expect(depot.lignes['nouvelle-0'], hasLength(6));
      expect(backend.corps, hasLength(2));
      x.fermer();
    });

    test('la conversation créée ici n’est listée qu’une fois', () async {
      final x = _Appareil(depot, backend);
      await x.session.envoyer('Parle-moi de la Lune');
      await x.synchro.actualiser(force: true);
      x.session.effacer();
      await x.session.envoyer('Parle-moi de Mars');
      await x.synchro.actualiser(force: true);
      expect(x.titres, ['Parle-moi de Mars', 'Parle-moi de la Lune']);
      x.fermer();
    });
  });

  group('Suppression', () {
    test('confirmée par le serveur : retirée partout', () async {
      depot.conversation(_a, 'Volcans', [('user', 'Q'), ('assistant', 'R')]);
      final x = _Appareil(depot, backend);
      await x.synchro.actualiser();
      await x.ouvrir('Volcans');
      final c = x.menu.liste(SourceConversation.jarvis).single;
      x.menu.epingles.basculer(c);
      expect(await x.menu.supprimer(c), isTrue);
      expect(depot.lignes.containsKey(_a), isFalse);
      expect(x.session.vide, isTrue);
      expect(x.titres, isEmpty);
      expect(x.menu.epingles.estEpinglee(c), isFalse);
      x.fermer();
    });

    test(
      'échec : conversation et épingle conservées, raison affichée',
      () async {
        depot.conversation(_a, 'Volcans', [('user', 'Q'), ('assistant', 'R')]);
        final x = _Appareil(depot, backend);
        await x.synchro.actualiser();
        final c = x.menu.liste(SourceConversation.jarvis).single;
        x.menu.epingles.basculer(c);
        depot.panne = const EchecSynchro(ErreurSynchro.horsLigne);
        expect(await x.menu.supprimer(c), isFalse);
        expect(depot.lignes.containsKey(_a), isTrue);
        expect(x.titres, ['Volcans']);
        expect(x.menu.epingles.estEpinglee(c), isTrue);
        expect(
          x.menu.avertissement(SourceConversation.jarvis),
          startsWith('Suppression impossible'),
        );
        x.fermer();
      },
    );

    test('créée sur cet appareil : supprimée aussi sur le serveur', () async {
      final x = _Appareil(depot, backend);
      await x.session.envoyer('Parle-moi de la Lune');
      final c = x.menu.liste(SourceConversation.jarvis).single;
      expect(await x.menu.supprimer(c), isTrue);
      expect(depot.lignes, isEmpty);
      expect(x.session.vide, isTrue);
      x.fermer();
    });

    test('déjà supprimée sur un autre appareil : réussite', () async {
      depot.conversation(_a, 'Volcans', [('user', 'Q'), ('assistant', 'R')]);
      final x = _Appareil(depot, backend);
      await x.synchro.actualiser();
      depot.lignes.remove(_a);
      final c = x.menu.liste(SourceConversation.jarvis).single;
      expect(await x.menu.supprimer(c), isTrue);
      expect(x.titres, isEmpty);
      x.fermer();
    });

    test('échange local seul : supprimé aussi sur le serveur', () async {
      final x = _Appareil(depot, backend);
      await x.session.envoyer('Quelle heure est-il ?');
      // Suppression immédiate, pendant l'envoi : elle l'attend.
      final c = x.menu.liste(SourceConversation.jarvis).single;
      expect(await x.menu.supprimer(c), isTrue);
      expect(backend.corps, isEmpty);
      expect(depot.lignes, isEmpty);
      x.fermer();
    });

    test(
      'hors connexion : conversation locale supprimée, file abandonnée',
      () async {
        backend.horsLigne = true;
        final x = _Appareil(depot, backend);
        await x.session.envoyer('Quelle heure est-il ?');
        await x.echanges.envoyer();
        expect(x.echanges.enAttente, 1);
        final c = x.menu.liste(SourceConversation.jarvis).single;
        expect(await x.menu.supprimer(c), isTrue);
        expect(x.echanges.enAttente, 0);
        backend.horsLigne = false;
        await x.echanges.envoyer();
        expect(depot.lignes, isEmpty);
        x.fermer();
      },
    );

    test('conversation vide : listée, ouverte et supprimée', () async {
      depot.conversation(_a, 'Vide', []);
      final x = _Appareil(depot, backend);
      await x.synchro.actualiser();
      expect(x.titres, ['Vide']);
      await x.ouvrir('Vide');
      expect(x.session.messages, isEmpty);
      final c = x.menu.liste(SourceConversation.jarvis).single;
      expect(await x.menu.supprimer(c), isTrue);
      expect(depot.lignes, isEmpty);
      expect(x.titres, isEmpty);
      x.fermer();
    });
  });

  group('Échanges locaux synchronisés', () {
    test(
      'Windows → Web : un calcul local retrouvé, sans appel à l’IA',
      () async {
        final windows = _Appareil(depot, backend);
        await windows.session.envoyer('Combien font 6 fois 7 ?');
        await windows.echanges.envoyer();
        expect(backend.corps, isEmpty);
        expect(backend.locaux, hasLength(1));
        final web = _Appareil(depot, backend);
        await web.synchro.actualiser();
        expect(web.titres, ['Combien font 6 fois 7 ?']);
        await web.ouvrir('Combien font 6 fois 7 ?');
        expect(web.fil, windows.fil);
        expect(web.fil.last, contains('42'));
        windows.fermer();
        web.fermer();
      },
    );

    test('puis une question à l’IA : même conversation serveur', () async {
      final x = _Appareil(depot, backend);
      await x.session.envoyer('Combien font 6 fois 7 ?');
      // Envoyée aussitôt : elle attend l'enregistrement de l'échange local.
      await x.session.envoyer('Explique-moi pourquoi ce résultat en détail');
      expect(backend.corps.single['conversation_id'], 'locale-0');
      expect(depot.lignes.keys, ['locale-0']);
      expect(depot.lignes['locale-0'], hasLength(4));
      x.fermer();
    });

    test(
      'hors connexion : affiché tout de suite, envoyé au retour, une fois',
      () async {
        backend.horsLigne = true;
        final x = _Appareil(depot, backend);
        await x.session.envoyer('Combien font 6 fois 7 ?');
        expect(x.fil.last, contains('42'));
        await x.echanges.envoyer();
        expect(x.echanges.enAttente, 1);
        expect(
          x.menu.avertissement(SourceConversation.jarvis),
          startsWith('1 échange local'),
        );
        backend.horsLigne = false;
        await x.menu.actualiser(SourceConversation.jarvis, force: true);
        expect(x.echanges.enAttente, 0);
        expect(x.menu.avertissement(SourceConversation.jarvis), isNull);
        // Envois répétés : jamais réinséré.
        await x.echanges.envoyer();
        await x.session.rafraichir();
        expect(depot.lignes['locale-0'], hasLength(2));
        expect(x.session.messages, hasLength(2));
        x.fermer();
      },
    );

    test('file gardée sur l’appareil : envoyée après redémarrage', () async {
      final stockage = StockageMemoire();
      backend.horsLigne = true;
      final avant = _Appareil(depot, backend, stockage: stockage);
      await avant.session.envoyer('Combien font 6 fois 7 ?');
      await avant.echanges.envoyer();
      avant.fermer();
      backend.horsLigne = false;
      final apres = _Appareil(depot, backend, stockage: stockage);
      await apres.echanges.charger();
      await apres.echanges.envoyer();
      expect(depot.lignes['locale-0'], hasLength(2));
      apres.fermer();
    });

    test('jamais envoyée pour un autre compte', () async {
      backend.horsLigne = true;
      final x = _Appareil(depot, backend);
      await x.session.envoyer('Combien font 6 fois 7 ?');
      await x.echanges.envoyer();
      depot.utilisateur = 'compte-b';
      backend.horsLigne = false;
      await x.echanges.envoyer();
      expect(backend.locaux, isEmpty);
      expect(x.echanges.enAttente, 1);
      x.fermer();
    });

    test('conversation collée : jamais envoyée', () async {
      final x = _Appareil(depot, backend);
      await x.session.envoyer(
        'Sarah : Tu viens ce soir ?\nMoi : Je ne sais pas.\n'
        'Sarah : Réponds-moi.\n\nRésume cette conversation.',
      );
      await x.session.envoyer('Qu’est-ce que je peux répondre ?');
      await x.echanges.envoyer();
      expect(backend.locaux, isEmpty);
      expect(backend.corps, isEmpty);
      x.fermer();
    });
  });

  test('message local seul : jamais marqué enregistré', () {
    final m = MessageConversation(
      id: 1,
      auteur: AuteurMessage.jarvis,
      heure: _t0,
      texte: 'Il est 9 heures.',
    );
    expect(m.enregistre, isFalse);
    expect(m.avecIdServeur('x').enregistre, isTrue);
  });
}
