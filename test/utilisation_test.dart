// Interface Utilisation (abonnements) : quotas QUOTIDIENS seulement, lecture
// de /me/quota, actualisation automatique et invisible, jauges, messages de
// limite. Faux serveur (MockClient) : aucun appel réel ; les actualisations
// n'appellent jamais la route d'IA.

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
const _quota = '/me/quota';
const _chat = '/api/v1/chat/stream';

/// Réponse de /me/quota (valeurs de TEST, jamais dans l'application). Le
/// serveur envoie encore un bloc `session` vide (sans durée) : ignoré.
Map<String, dynamic> quota({
  String plan = 'free',
  String fournisseur = 'groq',
  String modele = 'openai/gpt-oss-120b',
  int messages = 42,
  int? messagesLimite = 100,
  int tokens = 33000,
  int? tokensLimite = 50000,
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
  'session': {'active': false, 'duration_minutes': null, 'messages_limit': null, 'tokens_limit': null},
  'fournisseur_actif': {
    'llm_provider': fournisseurActif ?? fournisseur,
    'llm_model': modeleActif ?? modele,
    'routage_abonnement': routage,
  },
};

String _evenement(String type, Map<String, Object?> donnees) => 'event: $type\ndata: ${jsonEncode(donnees)}\n\n';

/// Faux serveur : /me/quota renvoie [reponse] ; la route de chat répond
/// (flux complet) ou refuse (429 quotidien). Chaque chemin est noté.
class Serveur {
  Map<String, dynamic> reponse = quota();
  int statut = 200;
  bool reseauCoupe = false;
  bool quotaAtteint = false;
  final chemins = <String>[];

  int get lectures => chemins.where((c) => c == _quota).length;

  ApiJarvis api() => ApiJarvis(
    adresse: Uri.parse('http://test'),
    jeton: () async => 'jeton',
    client: MockClient((r) async {
      chemins.add(r.url.path);
      if (reseauCoupe) throw http.ClientException('réseau coupé');
      if (r.url.path == _quota) {
        return http.Response(jsonEncode(statut == 200 ? reponse : {'detail': 'indisponible'}), statut,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (r.url.path == _chat) {
        if (quotaAtteint) {
          return http.Response(jsonEncode({'detail': {'error': 'quota_exceeded', 'kind': 'messages',
            'resets_at': '2026-10-18T00:00:00+00:00', 'quota': {}}}), 429);
        }
        return http.Response.bytes(
          utf8.encode([
            _evenement('meta', {'conversation_id': '11111111-1111-4111-8111-111111111111', 'message_id': 'm1', 'quota': {}}),
            _evenement('delta', {'text': 'Bonjour.'}),
            _evenement('done', {'message_id': 'm1', 'usage': {}, 'quota': {}}),
          ].join()),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      }
      return http.Response('{}', 404);
    }),
  );
}

ServiceUtilisation service(
  Serveur s, {
  ApiJarvis? api,
  Duration intervalle = const Duration(seconds: 30),
}) => ServiceUtilisation(
  api ?? s.api(),
  horloge: () => maintenant,
  intervalleSuivi: intervalle,
  delaiApresConsommation: Duration.zero,
);

Future<void> attendre([int ms = 20]) => Future<void>.delayed(Duration(milliseconds: ms));

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

/// Lecture faite hors du temps simulé des tests d'écran.
Future<void> relire(WidgetTester t, ServiceUtilisation u) async {
  await t.runAsync(() => u.actualiser(force: true));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Modèle (valeurs du serveur, rien en dur)', () {
    test('offre Free et Pro', () {
      final free = Utilisation.depuisJson(quota());
      expect(free.nomOffre, 'JARVIS Free');
      expect(free.offre.libelle, 'GroqCloud');
      expect((free.messagesJour.utilise, free.messagesJour.limite), (42, 100));
      final pro = Utilisation.depuisJson(quota(plan: 'pro', fournisseur: 'anthropic', modele: 'claude-opus-5-5',
          messagesLimite: 300, tokensLimite: 100000));
      expect(pro.nomOffre, 'JARVIS Pro');
      expect(pro.offre.libelle, 'Claude · Anthropic');
      expect(pro.messagesJour.limite, 300);
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

    test('réponse incomplète refusée', () {
      expect(() => Utilisation.depuisJson({'plan': 'free'}), throwsFormatException);
    });
  });

  group('Remise à zéro quotidienne', () {
    test('prochaine remise à zéro en heure locale', () {
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
    String corps(String kind) => jsonEncode({
      'detail': {'error': 'quota_exceeded', 'kind': kind, 'resets_at': '2026-10-18T00:00:00+00:00', 'quota': {}},
    });

    test('limites quotidiennes : messages et tokens, heure réelle de remise à zéro', () {
      expect(ApiJarvis.messageLimite(corps('messages'), maintenant: maintenant),
          startsWith('Votre limite quotidienne de messages est atteinte. Réinitialisation'));
      expect(ApiJarvis.messageLimite(corps('tokens'), maintenant: maintenant), contains('(dans 14 h)'));
    });

    test('limite du fournisseur IA : distincte (événement error, pas 429)', () {
      expect(MoteurConversationIA.messageErreur(ErreurApi.iaIndisponible,
          'Le service IA est très sollicité. Réessaie dans quelques secondes.'), contains('très sollicité'));
      expect(ApiJarvis.messageLimite('{"detail":"Token expiré"}'), isNull);
    });
  });

  group('Actualisation automatique', () {
    test('à l’ouverture : une lecture de /me/quota, rien d’autre', () async {
      final s = Serveur();
      final u = service(s);
      u.suivre();
      await attendre();
      expect(s.chemins, [_quota]);
      expect(u.donnees!.messagesJour.utilise, 42);
      u.cesserDeSuivre();
      u.dispose();
    });

    test('périodique tant que l’écran est ouvert, arrêtée à sa fermeture', () async {
      final s = Serveur();
      final u = service(s, intervalle: const Duration(milliseconds: 40));
      u.suivre();
      await attendre(150);
      final pendant = s.lectures;
      expect(pendant, greaterThanOrEqualTo(3));               // ouverture + ≥ 2 relectures
      u.cesserDeSuivre();
      await attendre(150);
      expect(s.lectures, pendant);                            // fermé : plus aucune lecture
      u.dispose();
    });

    test('application masquée : relecture suspendue, reprise au retour', () async {
      final s = Serveur();
      final u = service(s, intervalle: const Duration(milliseconds: 40));
      u.suivre();
      await attendre(60);
      u.didChangeAppLifecycleState(AppLifecycleState.hidden);
      final masquee = s.lectures;
      await attendre(150);
      expect(s.lectures, masquee);
      u.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await attendre(100);
      expect(s.lectures, greaterThan(masquee));
      u.cesserDeSuivre();
      u.dispose();
    });

    test('après une réponse IA : relecture, une seule, jamais d’appel IA en plus', () async {
      final s = Serveur();
      final api = s.api();
      final u = service(s, api: api);
      api.surConsommation = u.signalerConsommation;
      final r = await api.discuter('Bonjour');
      expect(r, isA<SuccesApi<ReponseChat>>());
      await attendre();
      expect(s.chemins, [_chat, _quota]);
      u.dispose();
    });

    test('après une erreur de quota : relecture, sans nouvel appel IA', () async {
      final s = Serveur()..quotaAtteint = true;
      final api = s.api();
      final u = service(s, api: api);
      api.surConsommation = u.signalerConsommation;
      final r = await api.discuter('Bonjour') as EchecApi;
      expect(r.type, ErreurApi.quotaAtteint);
      expect(r.detail, startsWith('Votre limite quotidienne de messages est atteinte.'));
      await attendre();
      expect(s.chemins, [_chat, _quota]);
      u.dispose();
    });

    test('aucune requête inutile : lecture partagée, lecture récente non refaite', () async {
      final s = Serveur();
      final u = service(s);
      await Future.wait([u.actualiser(), u.actualiser(), u.actualiser()]);
      await u.actualiser();                                   // < 5 s : pas refaite
      u.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await attendre();
      expect(s.lectures, 1);
      u.dispose();
    });

    test('changement d’abonnement (users.plan) : nouvelle offre et ses limites', () async {
      final s = Serveur();
      final u = service(s);
      await u.actualiser(force: true);
      expect(u.donnees!.nomOffre, 'JARVIS Free');
      s.reponse = quota(plan: 'pro', fournisseur: 'anthropic', modele: 'claude-opus-5-5',
          messagesLimite: 300, tokensLimite: 100000);
      await u.actualiser(force: true);
      final d = u.donnees!;
      expect((d.nomOffre, d.offre.libelle, d.messagesJour.limite), ('JARVIS Pro', 'Claude · Anthropic', 300));
      expect(d.messagesJour.utilise, 42);                     // consommation conservée
      u.dispose();
    });

    test('limites modifiées (plan_config) : nouvelles limites, consommation conservée', () async {
      final s = Serveur();
      final u = service(s);
      await u.actualiser(force: true);
      s.reponse = quota(messagesLimite: 150, tokensLimite: 70000);
      await u.actualiser(force: true);
      final d = u.donnees!;
      expect((d.messagesJour.utilise, d.messagesJour.limite), (42, 150));
      expect((d.tokensJour.utilise, d.tokensJour.limite), (33000, 70000));
      u.dispose();
    });

    test('erreur réseau : dernières données gardées, puis effacée au retour', () async {
      final s = Serveur();
      final u = service(s);
      await u.actualiser(force: true);
      s.reseauCoupe = true;
      await u.actualiser(force: true);
      expect(u.erreur, ErreurApi.injoignable);
      expect(u.donnees!.messagesJour.utilise, 42);
      expect(texteDonneesAnciennes(u), contains('peuvent ne plus être à jour'));
      s.reseauCoupe = false;
      await u.actualiser(force: true);
      expect(u.erreur, isNull);
      expect(texteDonneesAnciennes(u), isNull);
      u.dispose();
    });

    test('invisible : une seule notification par relecture, aucun chargement annoncé', () async {
      final s = Serveur();
      final u = service(s);
      await u.actualiser(force: true);
      var notifications = 0;
      var chargementVu = false;
      u.addListener(() {
        notifications++;
        if (u.chargement) chargementVu = true;
      });
      await u.actualiser(force: true);
      expect(notifications, 1);
      expect(chargementVu, isFalse);
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
    testWidgets('deux jauges quotidiennes seulement, aucune actualisation visible', (t) async {
      final s = Serveur();
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await relire(t, u);
      expect(find.text('JARVIS Free'), findsOneWidget);
      expect(find.text('GroqCloud — openai/gpt-oss-120b'), findsOneWidget);
      expect(find.byType(JaugeUtilisation), findsNWidgets(2));
      expect(find.byKey(const ValueKey('jauge-messages-jour')), findsOneWidget);
      expect(find.byKey(const ValueKey('jauge-tokens-jour')), findsOneWidget);
      expect(find.text('42 / 100 messages'), findsOneWidget);
      expect(find.text('33 000 / 50 000 tokens'), findsOneWidget);
      expect(find.textContaining('session'), findsNothing);
      expect(find.textContaining('hebdomadaire'), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.textContaining('Mis à jour'), findsNothing);
      expect(find.text('Voir les détails'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);              // lecture seule
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('relecture : valeurs remplacées sans chargement ni rechargement', (t) async {
      final s = Serveur();
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await relire(t, u);
      final carte = t.element(find.byKey(const ValueKey('jauge-messages-jour')));
      s.reponse = quota(messages: 60);
      await t.runAsync(() => u.actualiser(force: true));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.pumpAndSettle();
      expect(find.text('60 / 100 messages'), findsOneWidget);
      // Même élément : la jauge a été mise à jour (animée), pas reconstruite.
      expect(t.element(find.byKey(const ValueKey('jauge-messages-jour'))), same(carte));
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('Free → Pro → Free et nouvelles limites', (t) async {
      final s = Serveur();
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await relire(t, u);
      s.reponse = quota(plan: 'pro', fournisseur: 'anthropic', modele: 'claude-opus-5-5',
          messagesLimite: 300, tokensLimite: 100000);
      await relire(t, u);
      expect(find.text('JARVIS Pro'), findsOneWidget);
      expect(find.text('Claude · Anthropic — claude-opus-5-5'), findsOneWidget);
      expect(find.text('42 / 300 messages'), findsOneWidget);
      s.reponse = quota(messagesLimite: 150);
      await relire(t, u);
      expect(find.text('JARVIS Free'), findsOneWidget);
      expect(find.text('42 / 150 messages'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('erreur réseau : valeurs gardées, note discrète, retirée au retour', (t) async {
      final s = Serveur();
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await relire(t, u);
      s.reseauCoupe = true;
      await relire(t, u);
      expect(find.text('42 / 100 messages'), findsOneWidget);
      expect(find.byKey(const ValueKey('donnees-anciennes')), findsOneWidget);
      s.reseauCoupe = false;
      await relire(t, u);
      expect(find.byKey(const ValueKey('donnees-anciennes')), findsNothing);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('routage inactif : jamais annoncer GroqCloud comme actif', (t) async {
      final s = Serveur()
        ..reponse = quota(routage: false, fournisseurActif: 'anthropic', modeleActif: 'claude-opus-5-5');
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await relire(t, u);
      expect(find.textContaining('Actuellement servi par Claude · Anthropic'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('première lecture impossible : message clair, aucun bouton', (t) async {
      final s = Serveur()..statut = 503;
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await relire(t, u);
      expect(find.text('Utilisation indisponible pour le moment.'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('sans compte : invitation à se connecter, aucun appel', (t) async {
      await t.pumpWidget(cadre(const PanneauUtilisation(service: null)));
      expect(find.textContaining('Connectez-vous'), findsOneWidget);
    });

    testWidgets('« Voir les détails » : relue à l’ouverture, journée seulement', (t) async {
      t.view.physicalSize = const Size(1200, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = Serveur();
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await relire(t, u);
      final avant = s.lectures;
      await t.tap(find.text('Voir les détails'));
      await t.pumpAndSettle();
      await t.runAsync(attendre);
      await t.pumpAndSettle();
      expect(s.lectures, greaterThan(avant));                 // ouverture de la page
      expect(find.text('Modèle associé'), findsOneWidget);
      expect(find.text('Restants : 58 messages'), findsOneWidget);          // 100 - 42
      expect(find.text('Restants : 17 000 tokens'), findsOneWidget);   // 50 000 - 33 000
      expect(find.text('Prochaine remise à zéro'), findsOneWidget);
      expect(find.textContaining('session'), findsNothing);
      expect(find.textContaining('hebdomadaire'), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(s.chemins.toSet(), {_quota});                    // jamais l'IA
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });

    testWidgets('100 % : orange et « Limite atteinte »', (t) async {
      final s = Serveur()..reponse = quota(messages: 100);
      final u = service(s);
      await t.pumpWidget(cadre(PanneauUtilisation(service: u, horloge: () => maintenant)));
      await relire(t, u);
      expect(find.text('Limite atteinte'), findsWidgets);
      expect(couleurBarre(t, 'jauge-messages-jour'), CouleursJarvis.critique);
      await t.pumpWidget(const SizedBox());
      u.dispose();
    });
  });
}

String heureDeux(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
