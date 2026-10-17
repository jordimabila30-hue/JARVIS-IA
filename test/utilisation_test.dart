// Interface Utilisation (abonnements, phase 3) : lecture de /me/quota,
// actualisation, jauges, messages de limite. Faux serveur (MockClient) :
// aucun appel réel, et aucune route d'IA n'est jamais appelée.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/utilisation/utilisation.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_ia.dart';
import 'package:ia_jarvis/services/utilisation/service_utilisation.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/utils/format_utilisation.dart';
import 'package:ia_jarvis/widgets/utilisation/jauge_utilisation.dart';
import 'package:ia_jarvis/widgets/utilisation/panneau_utilisation.dart';

final maintenant = DateTime.utc(2026, 10, 17, 10, 0);

/// Réponse de /me/quota (valeurs de TEST, jamais dans l'application).
Map<String, dynamic> quota({
  String plan = 'free',
  String fournisseur = 'groq',
  String modele = 'openai/gpt-oss-120b',
  int messages = 42,
  int? messagesLimite = 100,
  int tokens = 33000,
  int? tokensLimite = 50000,
  bool session = true,
  int sessionMessages = 20,
  int? sessionMessagesLimite = 25,
  int sessionTokens = 4000,
  int? sessionTokensLimite = 15000,
  DateTime? finSession,
  int seuil = 80,
  bool routage = true,
  String? fournisseurActif,
  String? modeleActif,
  bool exception = false,
}) => {
  'plan': plan,
  'date': '2026-10-17',
  'messages_used': messages,
  'messages_limit': messagesLimite,
  'messages_remaining': messagesLimite == null ? null : messagesLimite - messages,
  'tokens_used': tokens,
  'tokens_limit': tokensLimite,
  'tokens_remaining': tokensLimite == null ? null : tokensLimite - tokens,
  'resets_in': 50400,
  'resets_at': '2026-10-18T00:00:00+00:00',
  'llm_provider': fournisseur,
  'llm_model': modele,
  'critical_threshold_percent': seuil,
  'exception': exception,
  'session': {
    'active': session,
    'id': session ? 's1' : null,
    'started_at': session ? '2026-10-17T08:00:00+00:00' : null,
    'ends_at': session ? (finSession ?? DateTime.utc(2026, 10, 17, 13)).toIso8601String() : null,
    'resets_in': session ? 10800 : null,
    'duration_minutes': 300,
    'messages_used': session ? sessionMessages : 0,
    'messages_limit': sessionMessagesLimite,
    'tokens_used': session ? sessionTokens : 0,
    'tokens_limit': sessionTokensLimite,
  },
  'fournisseur_actif': {
    'llm_provider': fournisseurActif ?? fournisseur,
    'llm_model': modeleActif ?? modele,
    'routage_abonnement': routage,
  },
};

/// Faux serveur : répond à /me/quota avec [reponse], note chaque chemin.
class Serveur {
  Map<String, dynamic> reponse = quota();
  int statut = 200;
  final chemins = <String>[];

  ApiJarvis api() => ApiJarvis(
    adresse: Uri.parse('http://test'),
    jeton: () async => 'jeton',
    client: MockClient((r) async {
      chemins.add(r.url.path);
      if (r.url.path == '/me/quota') {
        return http.Response(jsonEncode(statut == 200 ? reponse : {'detail': 'indisponible'}), statut,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (r.url.path == '/api/v1/chat/stream') {
        return http.Response(jsonEncode({'detail': {'error': 'quota_exceeded', 'kind': 'session_messages',
          'resets_at': '2026-10-17T13:00:00+00:00', 'quota': {}}}), 429);
      }
      return http.Response('{}', 404);
    }),
  );
}

ServiceUtilisation service(Serveur s, {DateTime Function()? horloge}) => ServiceUtilisation(
  s.api(),
  horloge: horloge ?? () => maintenant,
  delaiApresConsommation: Duration.zero,
);

Widget cadre(Widget enfant) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: enfant)),
);

Color couleurBarre(WidgetTester t, String jauge) => (t
        .widget<DecoratedBox>(find.descendant(
          of: find.byKey(ValueKey(jauge)),
          matching: find.byKey(const ValueKey('barre-remplie')),
        ))
        .decoration as BoxDecoration)
    .color!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Modèle (valeurs du serveur, rien en dur)', () {
    test('offre Free et Pro', () {
      final free = Utilisation.depuisJson(quota());
      expect(free.nomOffre, 'JARVIS Free');
      expect(free.offre.libelle, 'GroqCloud');
      expect((free.messagesJour.utilise, free.messagesJour.limite), (42, 100));
      final pro = Utilisation.depuisJson(quota(plan: 'pro', fournisseur: 'anthropic', modele: 'claude-opus-5-5',
          messagesLimite: 200, tokensLimite: 100000, sessionMessagesLimite: 50, sessionTokensLimite: 30000));
      expect(pro.nomOffre, 'JARVIS Pro');
      expect(pro.offre.libelle, 'Claude · Anthropic');
      expect(pro.session.messages.limite, 50);
    });

    test('seuil critique lu du serveur : 79 % bleu, 80 % orange, 100 % atteinte', () {
      Jauge j(int u, {int seuil = 80}) => Jauge(utilise: u, limite: 100, seuilCritique: seuil);
      expect([30, 65, 79].map((u) => j(u).critique), everyElement(isFalse));
      expect([80, 95, 100].map((u) => j(u).critique), everyElement(isTrue));
      expect(j(100).atteinte && !j(99).atteinte, isTrue);
      expect(couleurJauge(j(79)), CouleursJarvis.signal);
      expect(couleurJauge(j(80)), CouleursJarvis.critique);
      expect(j(65, seuil: 60).critique, isTrue);          // seuil modifié dans Supabase
    });

    test('illimité : aucune valeur inventée', () {
      final u = Utilisation.depuisJson(quota(tokensLimite: null));
      expect(u.tokensJour.illimitee, isTrue);
      expect(u.tokensJour.reste, isNull);
      expect(u.tokensJour.critique, isFalse);
      expect(valeurJauge(u.tokensJour, 'tokens'), '33 000 tokens · illimité');
    });

    test('jauge de session = la ressource la plus consommée', () {
      final u = Utilisation.depuisJson(quota(sessionMessages: 5, sessionTokens: 14000));
      expect(identical(u.session.principale, u.session.tokens), isTrue);
    });

    test('réponse incomplète refusée', () {
      expect(() => Utilisation.depuisJson({'plan': 'free'}), throwsFormatException);
    });
  });

  group('Réinitialisations', () {
    test('session : durée restante et heure de fin du serveur', () {
      final u = Utilisation.depuisJson(quota(finSession: DateTime.utc(2026, 10, 17, 12, 14)));
      expect(texteSession(u, maintenant), startsWith('Réinitialisation dans 2 h 14 min'));
      expect(u.session.termineeA(DateTime.utc(2026, 10, 17, 12, 15)), isTrue);
      expect(texteSession(u, DateTime.utc(2026, 10, 17, 12, 15)), startsWith('Session terminée'));
    });

    test('sans session en cours : commence au prochain message', () {
      final u = Utilisation.depuisJson(quota(session: false));
      expect(texteSession(u, maintenant), contains('elle commencera au prochain message et durera 5 h'));
      expect(u.session.messages.utilise, 0);
    });

    test('quotidien : prochaine remise à zéro en heure locale', () {
      final u = Utilisation.depuisJson(quota());
      final local = u.finJour!.toLocal();
      expect(texteJour(u, maintenant), contains(heureDeux(local)));
    });

    test('formats : nombres groupés, durées', () {
      expect(nombreGroupe(1250000), '1 250 000');
      expect(dureeRestante(const Duration(minutes: 45)), '45 min');
      expect(dureeRestante(const Duration(hours: 3)), '3 h');
    });
  });

  group('Limites atteintes (429)', () {
    final fin = DateTime.utc(2026, 10, 17, 13);
    String corps(String kind, DateTime quand) => jsonEncode({
      'detail': {'error': 'quota_exceeded', 'kind': kind, 'resets_at': quand.toIso8601String(), 'quota': {}},
    });

    test('quatre limites distinctes, réinitialisation propre à chacune', () {
      final s = ApiJarvis.messageLimite(corps('session_messages', fin), maintenant: maintenant)!;
      expect(s, startsWith('Vous avez atteint votre limite de messages pour cette session. '
          'Réessayez après sa réinitialisation. Réinitialisation'));
      expect(s, contains('(dans 3 h)'));                     // fin de SESSION, pas minuit UTC
      expect(ApiJarvis.messageLimite(corps('session_tokens', fin), maintenant: maintenant),
          contains('limite de tokens pour cette session'));
      expect(ApiJarvis.messageLimite(corps('messages', DateTime.utc(2026, 10, 18)), maintenant: maintenant),
          startsWith('Votre limite quotidienne de messages est atteinte. Réinitialisation'));
      expect(ApiJarvis.messageLimite(corps('tokens', DateTime.utc(2026, 10, 18)), maintenant: maintenant),
          contains('(dans 14 h)'));
    });

    test('limite du fournisseur IA : distincte (événement error, pas 429)', () {
      expect(MoteurConversationIA.messageErreur(ErreurApi.iaIndisponible,
          'Le service IA est très sollicité. Réessaie dans quelques secondes.'), contains('très sollicité'));
      expect(ApiJarvis.messageLimite('{"detail":"Token expiré"}'), isNull);
    });

    test('un refus de quota déclenche une actualisation, sans appel IA supplémentaire', () async {
      final s = Serveur();
      final api = s.api();
      var signaux = 0;
      api.surConsommation = () => signaux++;
      final r = await api.discuter('Bonjour') as EchecApi;
      expect(r.type, ErreurApi.quotaAtteint);
      expect(r.detail, contains('cette session'));
      expect(signaux, 1);
      expect(s.chemins, ['/api/v1/chat/stream']);
    });
  });

  group('Service d’actualisation', () {
    test('lecture : uniquement /me/quota, jamais l’IA', () async {
      final s = Serveur();
      final u = service(s);
      u.suivre();
      await u.actualiser(force: true);
      u.signalerConsommation();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      u.cesserDeSuivre();
      expect(s.chemins.toSet(), {'/me/quota'});
      u.dispose();
    });

    test('pas de lecture en double (récente ou en cours)', () async {
      final s = Serveur();
      final u = service(s);
      await Future.wait([u.actualiser(), u.actualiser(), u.actualiser()]);
      await u.actualiser();                          // < 5 s : pas refaite
      expect(s.chemins.length, 1);
      await u.actualiser(force: true);
      expect(s.chemins.length, 2);
      u.dispose();
    });

    test('limites modifiées dans Supabase : nouvelles limites, consommation conservée', () async {
      final s = Serveur();
      final u = service(s);
      await u.actualiser(force: true);
      expect((u.donnees!.messagesJour.utilise, u.donnees!.messagesJour.limite), (42, 100));
      s.reponse = quota(messagesLimite: 150, tokensLimite: 70000, sessionMessagesLimite: 40);
      await u.actualiser(force: true);
      final d = u.donnees!;
      expect((d.messagesJour.utilise, d.messagesJour.limite), (42, 150));
      expect((d.tokensJour.utilise, d.tokensJour.limite), (33000, 70000));
      expect((d.session.messages.utilise, d.session.messages.limite), (20, 40));
      u.dispose();
    });

    test('données indisponibles : dernières données gardées, erreur signalée', () async {
      final s = Serveur();
      final u = service(s);
      await u.actualiser(force: true);
      s.statut = 503;
      await u.actualiser(force: true);
      expect(u.erreur, ErreurApi.indisponible);
      expect(u.donnees!.messagesJour.utilise, 42);
      u.dispose();
    });

    test('changement de compte : rien de l’ancien compte', () async {
      final s = Serveur();
      final u = service(s);
      await u.actualiser(force: true);
      u.changerCompte();
      expect(u.donnees, isNull);
      expect(u.miseAJour, isNull);
      u.dispose();
    });
  });

  group('Panneau Utilisation', () {
    testWidgets('Free : offre, fournisseur, jauges du serveur', (t) async {
      final s = Serveur();
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await t.pumpAndSettle();
      expect(find.text('JARVIS Free'), findsOneWidget);
      expect(find.text('GroqCloud — openai/gpt-oss-120b'), findsOneWidget);
      expect(find.text('42 / 100 messages'), findsOneWidget);
      expect(find.text('33 000 / 50 000 tokens'), findsOneWidget);
      expect(find.text('20 / 25 messages'), findsOneWidget);  // session : 80 % > 27 %
      expect(couleurBarre(t, 'jauge-session'), CouleursJarvis.critique);
      expect(couleurBarre(t, 'jauge-messages-jour'), CouleursJarvis.signal);
      expect(find.byType(Slider), findsNothing);              // lecture seule
      expect(find.text('Voir les détails'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('Free → Pro → Free et nouvelles limites après actualisation', (t) async {
      final s = Serveur();
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await t.pumpAndSettle();
      s.reponse = quota(plan: 'pro', fournisseur: 'anthropic', modele: 'claude-opus-5-5',
          messagesLimite: 200, tokensLimite: 100000, sessionMessagesLimite: 50, sessionTokensLimite: 30000);
      await t.runAsync(() => u.actualiser(force: true));
      await t.pumpAndSettle();
      expect(find.text('JARVIS Pro'), findsOneWidget);
      expect(find.text('Claude · Anthropic — claude-opus-5-5'), findsOneWidget);
      expect(find.text('42 / 200 messages'), findsOneWidget);
      s.reponse = quota(messagesLimite: 150);
      await t.runAsync(() => u.actualiser(force: true));
      await t.pumpAndSettle();
      expect(find.text('JARVIS Free'), findsOneWidget);
      expect(find.text('42 / 150 messages'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('routage inactif : jamais annoncer GroqCloud comme actif', (t) async {
      final s = Serveur()
        ..reponse = quota(routage: false, fournisseurActif: 'anthropic', modeleActif: 'claude-opus-5-5');
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await t.pumpAndSettle();
      expect(find.textContaining('Actuellement servi par Claude · Anthropic'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('serveur indisponible : message clair et « Réessayer »', (t) async {
      final s = Serveur()..statut = 503;
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await t.pumpAndSettle();
      expect(find.text('Utilisation indisponible pour le moment.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('sans compte : invitation à se connecter, aucun appel', (t) async {
      await t.pumpWidget(cadre(const PanneauUtilisation(service: null)));
      expect(find.textContaining('Connectez-vous'), findsOneWidget);
    });

    testWidgets('« Voir les détails » : offre, restants, fin de session, remise à zéro', (t) async {
      t.view.physicalSize = const Size(1200, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = Serveur();
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await t.pumpAndSettle();
      await t.tap(find.text('Voir les détails'));
      await t.pumpAndSettle();
      expect(find.text('Modèle associé'), findsOneWidget);
      expect(find.text('openai/gpt-oss-120b'), findsWidgets);
      expect(find.text('Restants : 58 messages'), findsOneWidget);          // 100 - 42
      expect(find.text('Restants : 17 000 tokens'), findsOneWidget);   // 50 000 - 33 000
      expect(find.text('Restants : 5 messages'), findsOneWidget);           // session 25 - 20
      expect(find.text('Fin de session'), findsOneWidget);
      expect(find.text('Prochaine remise à zéro'), findsOneWidget);
      expect(find.textContaining('hebdomadaire'), findsNothing);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('100 % : orange et « Limite atteinte »', (t) async {
      final s = Serveur()..reponse = quota(messages: 100);
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await t.pumpAndSettle();
      expect(find.text('Limite atteinte'), findsWidgets);
      expect(couleurBarre(t, 'jauge-messages-jour'), CouleursJarvis.critique);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });
  });
}

String heureDeux(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
