import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';
import 'package:ia_jarvis/services/jarvis_touch_chat.dart';

/// IA simulée : les fragments sont poussés par le test, la réponse finale
/// arrive quand [fin] est complété.
class _MoteurFlux extends MoteurConversationLocal {
  Completer<void> fin = Completer<void>();
  DemandeJarvis? demande;
  int appels = 0;

  @override
  Future<ReponseJarvis> repondre(DemandeJarvis d) async {
    appels++;
    demande = d;
    await fin.future;
    return const ReponseJarvis('Bonjour Jordi, je suis là.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('jarvis/touch_chat');
  final messager =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _MoteurFlux moteur;
  late ConversationSession session;
  late PasserelleMiniChat passerelle;
  late List<MethodCall> recus;

  /// Appel venu de la fenêtre native.
  Future<Object?> natif(String methode, [Object? args]) async {
    final reponse = Completer<ByteData?>();
    await messager.handlePlatformMessage(
      canal.name,
      canal.codec.encodeMethodCall(MethodCall(methode, args)),
      reponse.complete,
    );
    return canal.codec.decodeEnvelope((await reponse.future)!);
  }

  setUp(() {
    moteur = _MoteurFlux();
    session = ConversationSession(
      moteur: moteur,
      delaiReflexion: Duration.zero,
    );
    passerelle = PasserelleMiniChat(
      session,
      intervalle: const Duration(milliseconds: 40),
    )..attacher();
    recus = [];
    messager.setMockMethodCallHandler(canal, (appel) async {
      recus.add(appel);
      return null;
    });
  });

  tearDown(() {
    passerelle.detacher();
    session.dispose();
    messager.setMockMethodCallHandler(canal, null);
  });

  List<Map> messagesDe(Object? etat) =>
      ((etat as Map)['messages'] as List).cast<Map>();

  test('ouvrir : la conversation de l’accueil, mêmes identifiants', () async {
    moteur.fin.complete();
    await session.envoyer('Bonjour JARVIS.');
    final etat = await natif('ouvrir');
    final m = messagesDe(etat);
    expect(m.map((e) => e['id']), session.messages.map((e) => e.id));
    expect(m.first['texte'], 'Bonjour JARVIS.');
    expect(m.first['moi'], isTrue);
    expect(m.last['texte'], 'Bonjour Jordi, je suis là.');
    expect((etat as Map)['titre'], 'Bonjour JARVIS.');
  });

  test(
    'envoyer : un seul message, une seule requête, flux puis final',
    () async {
      await natif('ouvrir');
      final args = {'texte': 'Explique-moi ce problème.', 'idEnvoi': 'e1'};
      expect(await natif('envoyer', args), isTrue);
      // Même envoi reçu deux fois (double appui) : ignoré.
      expect(await natif('envoyer', args), isTrue);
      await pumpEventQueue();
      expect(moteur.appels, 1);
      expect(session.messages.where((m) => !m.deJarvis), hasLength(1));

      // Réflexion annoncée à la fenêtre.
      final reflexion = recus.where((c) => c.method == 'etat').last;
      expect((reflexion.arguments as Map)['reflexion'], isTrue);

      moteur.demande!.surFragment!('Bien sûr, ');
      moteur.demande!.surFragment!('voici ');
      moteur.demande!.surFragment!('l’explication.');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final fragments = recus.where((c) => c.method == 'fragment').toList();
      // Regroupés : le premier tout de suite, la suite d'un coup.
      expect(fragments, hasLength(2));
      expect(
        (fragments.last.arguments as Map)['texte'],
        'Bien sûr, voici l’explication.',
      );
      final idBulle = (fragments.last.arguments as Map)['id'];

      moteur.fin.complete();
      await pumpEventQueue();
      final finale = messagesDe(
        recus.where((c) => c.method == 'etat').last.arguments,
      );
      // Même bulle (même identifiant), finalisée ; aucun doublon.
      expect(finale.map((m) => m['id']).toSet(), hasLength(finale.length));
      expect(finale.last['id'], idBulle);
      expect(finale.last['redaction'], isFalse);
      expect(finale.last['texte'], 'Bonjour Jordi, je suis là.');
      expect(session.messages, hasLength(2));
      // Lue en direct : l'accueil ne la réécrit pas mot à mot.
      expect(session.messages.last.ecriture!.toutVisible, isTrue);
    },
  );

  test('fermée : plus aucun travail ni envoi vers la fenêtre', () async {
    await natif('ouvrir');
    await natif('fermer');
    recus.clear();
    moteur.fin.complete();
    await session.envoyer('Toujours là ?');
    await pumpEventQueue();
    expect(recus, isEmpty);
    // La conversation, elle, continue (même session).
    expect(session.messages, hasLength(2));
  });

  test('plusAnciens : la fenêtre s’élargit sans copier l’historique', () async {
    final p = PasserelleMiniChat(session, taillePage: 2)..attacher();
    addTearDown(p.detacher);
    moteur.fin.complete();
    await session.envoyer('un');
    await session.envoyer('deux');
    expect(session.messages, hasLength(4));
    var etat = await natif('ouvrir');
    expect(messagesDe(etat), hasLength(2));
    expect((etat as Map)['plusAnciens'], isTrue);
    etat = await natif('plusAnciens');
    expect(messagesDe(etat), hasLength(4));
    expect((etat as Map)['plusAnciens'], isFalse);
  });
}
