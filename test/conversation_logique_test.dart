import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/conversation/analyse_conversation.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/detecteur_conversation.dart';
import 'package:ia_jarvis/services/conversation/detecteur_intention.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';

const _sarah =
    'Sarah : Tu aurais pu me prévenir.\n'
    'Moi : Désolé, j’étais occupé.\n'
    'Sarah : Ce n’est pas la première fois.';

ConversationSession _session() =>
    ConversationSession(delaiReflexion: Duration.zero);

void main() {
  const detecteur = DetecteurConversation();
  const intentions = DetecteurIntention();

  group('Détection de conversation', () {
    test('lignes « Nom : message », plusieurs locuteurs', () {
      final r = detecteur.analyser(_sarah);
      expect(r.conversation, isNotNull);
      expect(r.conversation!.lignes, hasLength(3));
      expect(r.conversation!.participants, ['Sarah', 'Moi']);
      expect(r.conversation!.lignes[1].estMoi, isTrue);
      expect(r.demande, isEmpty);
    });

    test('conversation + question juste après (sans ligne vide)', () {
      final r = detecteur.analyser(
        '$_sarah\nTu trouves que j’ai mal répondu ?',
        avecDemande: intentions.concerneUneConversation,
      );
      expect(r.conversation!.lignes, hasLength(3));
      expect(
        r.conversation!.lignes.last.texte,
        'Ce n’est pas la première fois.',
      );
      expect(r.demande, 'Tu trouves que j’ai mal répondu ?');
    });

    test('question avant la conversation', () {
      final r = detecteur.analyser(
        'Tu peux me dire quoi répondre à ça ?\n$_sarah',
      );
      expect(r.demande, 'Tu peux me dire quoi répondre à ça ?');
      expect(r.conversation!.lignes, hasLength(3));
    });

    test('export WhatsApp avec horodatages et message sur deux lignes', () {
      final r = detecteur.analyser(
        '[14:32, 12/05/2024] Léo : On se voit ce soir ?\n'
        'Vers 20h si possible\n'
        '12/05/2024, 14:35 - Moi : Je te redis !',
      );
      final l = r.conversation!.lignes;
      expect(l, hasLength(2));
      expect(l.first.locuteur, 'Léo');
      expect(l.first.heure, '14:32');
      expect(l.first.texte, 'On se voit ce soir ? Vers 20h si possible');
      expect(l.last.estMoi, isTrue);
    });

    test('texte normal (même avec « : ») : pas une conversation', () {
      for (final t in [
        'Bonjour JARVIS',
        'Comment fonctionne une batterie ?',
        'Note : penser à acheter du pain.',
        'Voici le lien : https://exemple.fr et la date : demain',
        'il est 14:30, tu peux me rappeler ?',
      ]) {
        expect(detecteur.analyser(t).conversation, isNull, reason: t);
      }
    });

    test('un seul message : conversation seulement avec une demande', () {
      expect(detecteur.analyser('Sarah : tu viens ?').conversation, isNull);
      final r = detecteur.analyser(
        'Sarah : tu viens ce soir ?\nJe lui réponds quoi ?',
        avecDemande: intentions.concerneUneConversation,
      );
      expect(r.conversation!.lignes, hasLength(1));
      expect(r.demande, 'Je lui réponds quoi ?');
    });
  });

  group('Intention', () {
    IntentionMessage i(String t, {bool connue = true}) =>
        intentions.detecter(t, conversationConnue: connue);

    test('demandes de réponse', () {
      for (final t in [
        'Tu peux me dire quoi répondre ?',
        'Réponds-lui pour moi',
        'Qu’est-ce que je peux lui répondre ?',
        'je dis quoi',
        'que répondre à ça',
      ]) {
        expect(i(t), IntentionMessage.reponse, reason: t);
      }
    });

    test('résumé, compréhension, analyse', () {
      expect(i('Fais-moi un résumé'), IntentionMessage.resume);
      expect(i('Résume cette conversation'), IntentionMessage.resume);
      expect(i('Explique-moi cette conversation'), IntentionMessage.comprendre);
      expect(i('Qu’est-ce qui se passe ici ?'), IntentionMessage.comprendre);
      expect(i('Tu trouves que j’ai mal répondu ?'), IntentionMessage.analyse);
      expect(i('Pourquoi elle réagit comme ça ?'), IntentionMessage.analyse);
      expect(i('La conversation devient tendue ?'), IntentionMessage.analyse);
      expect(i('Tu en penses quoi ?'), IntentionMessage.analyse);
    });

    test('discussion normale', () {
      expect(i('Bonjour JARVIS', connue: false), IntentionMessage.discussion);
      expect(
        i('Comment fonctionne une batterie ?'),
        IntentionMessage.discussion,
      );
      // « réponds » seul n'est une demande de réponse qu'avec une
      // conversation connue.
      expect(i('réponds vite', connue: false), IntentionMessage.discussion);
      expect(i('réponds vite'), IntentionMessage.reponse);
    });
  });

  group('Analyse et tons', () {
    final c = detecteur.analyser(_sarah).conversation!;
    final a = AnalyseConversation(c);

    test('reproche, tension, à qui de répondre', () {
      expect(a.situation, Situation.reproche);
      expect(a.tension, greaterThanOrEqualTo(1));
      expect(a.lectureCourte, contains('Sarah'));
      expect(a.lectureCourte, contains('c’est à toi de répondre'));
    });

    test('chaque ton donne une réponse différente', () async {
      final moteur = MoteurConversationLocal();
      final reponses = {
        for (final ton in TonReponse.values)
          ton: await moteur.proposerReponse(c, ton),
      };
      expect(reponses.values.toSet(), hasLength(TonReponse.values.length));
      expect(
        reponses[TonReponse.naturel],
        'Tu as raison, j’aurais dû te prévenir. Désolé, je comprends que ça '
        'ait pu te déranger.',
      );
      expect(reponses[TonReponse.direct], contains('Désolé pour ça'));
    });
  });

  group('Session', () {
    test('TEST 1-2 : discussion normale', () async {
      final s = _session();
      await s.envoyer('Bonjour JARVIS');
      await s.envoyer('Comment fonctionne une batterie ?');
      expect(s.messages, hasLength(4));
      expect(s.messages[1].deJarvis, isTrue);
      expect(s.messages[1].texte, startsWith('Bonjour'));
      expect(s.messages[3].texte, contains('énergie'));
      expect(s.messages.every((m) => !m.choixTon && m.actions.isEmpty), isTrue);
    });

    test(
      'TEST 3 : conversation collée seule → lecture et raccourcis',
      () async {
        final s = _session();
        await s.envoyer(_sarah);
        expect(s.messages.first.conversation!.lignes, hasLength(3));
        final r = s.messages.last;
        expect(r.texte, contains('Sarah'));
        expect(r.actions, ActionRapide.values);
        expect(r.choixTon, isFalse);
      },
    );

    test(
      'TEST 4 : conversation + « mal répondu ? » → analyse, pas de ton',
      () async {
        final s = _session();
        await s.envoyer('$_sarah\n\nTu trouves que j’ai mal répondu ?');
        final r = s.messages.last;
        expect(r.choixTon, isFalse);
        expect(r.texte, contains('excuses'));
      },
    );

    test('TEST 5-8 : demande de réponse → ton → réponse qui change', () async {
      final s = _session();
      await s.envoyer('$_sarah\n\nTu peux me dire quoi répondre ?');
      final r = s.messages.last;
      expect(r.choixTon, isTrue);
      expect(r.reponseProposee, isNull);
      await s.choisirTon(r.id, TonReponse.naturel);
      final naturel = s.messages.last.reponseProposee;
      expect(naturel, contains('j’aurais dû te prévenir'));
      await s.choisirTon(r.id, TonReponse.amical);
      expect(s.messages.last.ton, TonReponse.amical);
      expect(s.messages.last.reponseProposee, isNot(naturel));
      await s.choisirTon(r.id, TonReponse.bienveillant);
      expect(s.messages.last.reponseProposee, contains('blesser'));
      // Aucun message en double.
      expect(s.messages, hasLength(2));
    });

    test('question de suivi sur la conversation déjà collée', () async {
      final s = _session();
      await s.envoyer(_sarah);
      await s.envoyer('Je lui réponds quoi ?');
      expect(s.messages.last.choixTon, isTrue);
      await s.envoyer('Résume');
      expect(s.messages.last.texte, startsWith('En bref'));
    });

    test('raccourcis : Résumer, Répondre, Poser une question', () async {
      final s = _session();
      await s.envoyer(_sarah);
      final id = s.messages.last.id;
      await s.action(id, ActionRapide.resumer);
      expect(s.messages.last.texte, startsWith('En bref'));
      await s.action(id, ActionRapide.repondre);
      expect(s.messages.last.choixTon, isTrue);
      await s.action(id, ActionRapide.question);
      expect(s.questionAttendue, isTrue);
      await s.envoyer('Elle est sérieuse ?');
      expect(s.messages.last.texte, isNot(MoteurConversationLocal.inconnue));
    });

    test('aide à répondre : situation décrite → IA (même hors WhatsApp) ; '
        'demande nue → la conversation est demandée', () {
      for (final t in [
        'Elle m’a dit que j’étais drôle, je réponds quoi ?',
        'Mon professeur m’a demandé de lui envoyer le travail, je réponds quoi ?',
        'Mon ami s’est excusé, qu’est-ce que je lui dis ?',
        'Mon patron m’a demandé si je suis disponible demain, comment je réponds ?',
      ]) {
        expect(DetecteurIntention.decritUneSituation(t), isTrue, reason: t);
      }
      for (final t in [
        'Tu peux me dire quoi répondre ?',
        'Que lui répondre ?',
        'Qu’est-ce que je lui réponds ?',
        'Je réponds quoi à ce message ?',
      ]) {
        expect(DetecteurIntention.decritUneSituation(t), isFalse, reason: t);
      }
    });

    test('demande de réponse sans conversation : JARVIS la demande', () async {
      final s = _session();
      await s.envoyer('Tu peux me dire quoi répondre ?');
      expect(
        s.messages.last.texte,
        MoteurConversationLocal.demandeConversation,
      );
    });

    test(
      'vide, très long, envois rapides : ordre gardé, pas de doublon',
      () async {
        final s = _session();
        await s.envoyer('   ');
        expect(s.messages, isEmpty);
        final long = List.filled(
          400,
          'Sarah : Encore un message.\nMoi : Oui.',
        ).join('\n');
        final a = s.envoyer(long);
        final b = s.envoyer('Bonjour JARVIS');
        await Future.wait([a, b]);
        expect(s.messages, hasLength(4));
        expect(s.messages[0].conversation!.lignes, hasLength(800));
        expect(s.messages[2].texte, 'Bonjour JARVIS');
        expect(s.enReflexion, isFalse);
      },
    );

    test(
      'nouvelle conversation pendant la réflexion : rien ne réapparaît',
      () async {
        final s = ConversationSession(
          delaiReflexion: const Duration(milliseconds: 50),
        );
        final envoi = s.envoyer('Bonjour JARVIS');
        s.effacer();
        await envoi;
        expect(s.messages, isEmpty);
        expect(s.enReflexion, isFalse);
      },
    );
  });
}
