// Gmail (ODO phase 2) côté application : état de la connexion, page
// Paramètres › Gmail, ouverture de Google dans le navigateur, et demandes
// « mes mails » envoyées au serveur au lieu d'être interceptées localement.
// Faux serveur (MockClient) : aucun appel réel, aucun jeton.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/integrations/etat_gmail.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/detecteur_intention.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';
import 'package:ia_jarvis/services/integrations/service_gmail.dart';
import 'package:ia_jarvis/widgets/integrations/panneau_gmail.dart';

Map<String, dynamic> etat(String statut, {bool configure = true, String? email, String? le}) => {
  'statut': statut,
  'configure': configure,
  if (email != null) 'email': email,
  if (email != null) 'portee': 'lecture_seule',
  if (le != null) 'connecte_le': le,
};

/// Faux serveur des routes Gmail : l'état change quand [connecter] est appelé.
class Serveur {
  Map<String, dynamic> reponse = etat('non_connecte');
  final requetes = <http.Request>[];

  ApiJarvis api() => ApiJarvis(
    adresse: Uri.parse('http://test'),
    jeton: () async => 'jeton-jarvis',
    client: MockClient((r) async {
      requetes.add(r);
      final json = {'content-type': 'application/json; charset=utf-8'};
      if (r.url.path == '/api/v1/integrations/gmail' && r.method == 'GET') {
        return http.Response(jsonEncode(reponse), 200, headers: json);
      }
      if (r.url.path == '/api/v1/integrations/gmail/connexion') {
        return http.Response(jsonEncode({'url': 'https://accounts.google.com/o/oauth2/v2/auth?state=abc'}), 200,
            headers: json);
      }
      if (r.url.path == '/api/v1/integrations/gmail' && r.method == 'DELETE') {
        reponse = etat('non_connecte');
        return http.Response(jsonEncode({'statut': 'non_connecte'}), 200, headers: json);
      }
      return http.Response('{}', 404);
    }),
  );
}

Widget cadre(Widget enfant) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: enfant)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Modèle', () {
    test('états du serveur', () {
      expect(EtatGmail.depuisJson(etat('non_connecte')).statut, StatutGmail.nonConnecte);
      expect(EtatGmail.depuisJson(etat('non_connecte', configure: false)).statut, StatutGmail.nonConfigure);
      final c = EtatGmail.depuisJson(etat('connecte', email: 'pepper@gmail.com', le: '2026-10-18T10:00:00Z'));
      expect((c.statut, c.email, c.lectureSeule), (StatutGmail.connecte, 'pepper@gmail.com', true));
      expect(EtatGmail.depuisJson(etat('a_renouveler')).statut, StatutGmail.aRenouveler);
    });
  });

  group('Service', () {
    test('connexion : Google ouvert dans le navigateur, retour constaté', () async {
      final s = Serveur();
      final ouvertes = <Uri>[];
      final g = ServiceGmail(s.api(), plateforme: 'android', intervalleAttente: const Duration(milliseconds: 20),
          ouvrir: (u) async {
        ouvertes.add(u);
        return true;
      });
      await g.actualiser();
      expect(g.etat!.statut, StatutGmail.nonConnecte);
      await g.connecter();
      expect(ouvertes.single.host, 'accounts.google.com');
      expect(g.enAttente, isTrue);
      final corps = jsonDecode(s.requetes.firstWhere((r) => r.url.path.endsWith('/connexion')).body);
      expect(corps, {'plateforme': 'android'});
      s.reponse = etat('connecte', email: 'pepper@gmail.com', le: '2026-10-18T10:00:00Z');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(g.enAttente, isFalse);
      expect(g.etat!.email, 'pepper@gmail.com');
      g.dispose();
    });

    test('changer de compte : attente jusqu’au NOUVEAU compte', () async {
      final s = Serveur()..reponse = etat('connecte', email: 'pepper@gmail.com', le: '2026-10-18T10:00:00Z');
      final g = ServiceGmail(s.api(), intervalleAttente: const Duration(milliseconds: 20), ouvrir: (_) async => true);
      await g.actualiser();
      await g.connecter();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(g.enAttente, isTrue);                       // même compte : toujours en attente
      s.reponse = etat('connecte', email: 'tony@gmail.com', le: '2026-10-18T11:00:00Z');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect((g.enAttente, g.etat!.email), (false, 'tony@gmail.com'));
      g.dispose();
    });

    test('déconnexion et navigateur indisponible', () async {
      final s = Serveur()..reponse = etat('connecte', email: 'pepper@gmail.com');
      final g = ServiceGmail(s.api(), ouvrir: (_) async => false);
      await g.actualiser();
      await g.connecter();
      expect((g.enAttente, g.information), (false, 'Le navigateur n’a pas pu s’ouvrir.'));
      expect(await g.deconnecter(), isTrue);
      expect(g.etat!.statut, StatutGmail.nonConnecte);
      expect(s.requetes.any((r) => r.method == 'DELETE'), isTrue);
      g.dispose();
    });

    test('jamais de jeton dans les requêtes de l’application', () async {
      final s = Serveur();
      final g = ServiceGmail(s.api(), ouvrir: (_) async => true);
      await g.actualiser();
      await g.connecter();
      for (final r in s.requetes) {
        expect(r.body.contains('token'), isFalse);
      }
      g.dispose();
    });
  });

  group('Page Paramètres › Gmail', () {
    Future<ServiceGmail> afficher(WidgetTester t, Map<String, dynamic> reponse) async {
      final s = Serveur()..reponse = reponse;
      final g = ServiceGmail(s.api(), ouvrir: (_) async => true);
      await t.pumpWidget(cadre(PanneauGmail(service: g)));
      await t.runAsync(() => g.actualiser());
      await t.pumpAndSettle();
      return g;
    }

    testWidgets('aucun compte : connecter, autorisations expliquées', (t) async {
      final g = await afficher(t, etat('non_connecte'));
      expect(find.text('Connecter Gmail'), findsOneWidget);
      expect(find.textContaining('Connectez le compte Google que vous souhaitez utiliser avec JARVIS'), findsOneWidget);
      expect(find.text('Choisir un compte Google'), findsOneWidget);
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      expect(find.textContaining('mot de passe Google n’est jamais demandé'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);              // aucun champ de mot de passe
      await t.pumpWidget(const SizedBox());
      g.dispose();
    });

    testWidgets('connecté : adresse, lecture seule, changer, déconnecter', (t) async {
      final g = await afficher(t, etat('connecte', email: 'pepper@gmail.com'));
      expect(find.text('Gmail connecté'), findsOneWidget);
      expect(find.text('pepper@gmail.com'), findsOneWidget);
      expect(find.text('Lecture seule'), findsOneWidget);
      expect(find.text('Changer de compte'), findsOneWidget);
      await t.tap(find.text('Déconnecter Gmail'));
      await t.pumpAndSettle();
      expect(find.text('Déconnecter Gmail ?'), findsOneWidget);   // toujours confirmé
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(g.etat!.statut, StatutGmail.connecte);
      await t.pumpWidget(const SizedBox());
      g.dispose();
    });

    testWidgets('à renouveler : message et reconnexion', (t) async {
      final g = await afficher(t, etat('a_renouveler', email: 'pepper@gmail.com'));
      expect(find.text('La connexion Gmail doit être renouvelée.'), findsOneWidget);
      expect(find.text('Reconnecter Gmail'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      g.dispose();
    });

    testWidgets('serveur non configuré et sans compte JARVIS', (t) async {
      final g = await afficher(t, etat('non_connecte', configure: false));
      expect(find.textContaining('pas encore configuré sur ce serveur'), findsOneWidget);
      expect(find.text('Choisir un compte Google'), findsNothing);
      await t.pumpWidget(cadre(const PanneauGmail(service: null)));
      expect(find.textContaining('Connectez-vous à JARVIS'), findsOneWidget);
      g.dispose();
    });
  });

  group('Moteur local : « mes mails » va au serveur', () {
    test('demandes sur les e-mails personnels reconnues', () {
      for (final p in [
        'Résume mes mails',
        'Bonjour JARVIS, regarde si j’ai reçu des mails importants aujourd’hui',
        'Fais-moi un point sur mes e-mails',
        'Trouve le dernier mail de mon professeur',
        'Qu’est-ce que j’ai dans ma boîte de réception ?',
        'Ouvre Gmail',
      ]) {
        expect(DetecteurIntention.concerneMesEmails(p), isTrue, reason: p);
      }
      for (final p in ['Résume ce mail', 'Quelle heure est-il ?', 'Envoie-moi un message', 'Résume la conversation',
                       'Explique-moi les protocoles mail']) {
        expect(DetecteurIntention.concerneMesEmails(p), isFalse, reason: p);
      }
    });

    test('jamais « colle la conversation » pour mes mails ; commandes locales intactes', () async {
      final local = MoteurConversationLocal();
      DemandeJarvis d(String t) => DemandeJarvis(
        texte: t, intention: const DetecteurIntention().detecter(t, conversationConnue: false));
      expect(await local.repondreLocalement(d('Résume mes mails'), avecIA: true), isNull);   // → serveur (ODO)
      expect(await local.repondreLocalement(d('Résume mes derniers mails'), avecIA: true), isNull);
      final sansServeur = await local.repondreLocalement(d('Résume mes mails'));
      expect(sansServeur!.texte, MoteurConversationLocal.emailsSansServeur);
      final colle = await local.repondreLocalement(d('Résume ce mail'), avecIA: true);
      expect(colle!.texte, MoteurConversationLocal.demandeConversation);        // inchangé
      final heure = await local.repondreLocalement(d('Quelle heure est-il ?'), avecIA: true);
      expect(heure, isNotNull);                                                  // commande locale gardée
    });
  });
}
