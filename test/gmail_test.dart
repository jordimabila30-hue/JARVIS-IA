// Gmail (ODO phase 2) côté application : état de la connexion (partagé,
// sans rechargement visible), Paramètres › Outils › Gmail, ouverture de Google dans le navigateur, et demandes
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
import 'package:ia_jarvis/widgets/integrations/panneau_outils.dart';

Map<String, dynamic> etat(String statut, {bool configure = true, String? email, String? le}) => {
  'statut': statut,
  'configure': configure,
  'email': ?email,
  if (email != null) 'portee': 'lecture_seule',
  'connecte_le': ?le,
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

  group('État partagé, sans rechargement visible', () {
    test('lectures partagées, pas de relecture récente, aucune notification inutile', () async {
      final s = Serveur()..reponse = etat('connecte', email: 'pepper@gmail.com');
      var maintenant = DateTime(2026, 10, 18, 12);
      final g = ServiceGmail(s.api(), ouvrir: (_) async => true, horloge: () => maintenant);
      var notes = 0;
      g.addListener(() => notes++);
      await Future.wait([g.actualiser(), g.actualiser(), g.actualiser()]);
      int lectures() => s.requetes.where((r) => r.method == 'GET').length;
      expect(lectures(), 1);                                   // une seule lecture partagée
      expect((g.fiable, notes), (true, 2));                    // 1re lecture : chargement puis état
      await g.actualiser();
      expect(lectures(), 1);                                   // < 30 s : rien
      maintenant = maintenant.add(const Duration(seconds: 31));
      await g.actualiser();
      expect((lectures(), notes), (2, 2));                     // relu, identique : aucun redessin
      g.dispose();
    });

    test('échec : dernier état gardé, signalé non fiable', () async {
      final s = Serveur()..reponse = etat('connecte', email: 'pepper@gmail.com');
      var panne = false;
      final api = ApiJarvis(
        adresse: Uri.parse('http://test'),
        jeton: () async => 'jeton-jarvis',
        client: MockClient((r) async => panne
            ? throw http.ClientException('hors ligne')
            : http.Response(jsonEncode(s.reponse), 200, headers: {'content-type': 'application/json'})),
      );
      final g = ServiceGmail(api, ouvrir: (_) async => true);
      await g.actualiser();
      panne = true;
      await g.actualiser(force: true);
      expect((g.etat!.statut, g.etat!.email, g.fiable), (StatutGmail.connecte, 'pepper@gmail.com', false));
      g.dispose();
    });

    test('changement de compte JARVIS : rien de l’ancien compte, même une lecture en vol', () async {
      final s = Serveur()..reponse = etat('connecte', email: 'pepper@gmail.com');
      final g = ServiceGmail(s.api(), ouvrir: (_) async => true);
      final enVol = g.actualiser();
      g.changerCompte();
      await enVol;
      expect((g.etat, g.miseAJour, g.chargement), (null, null, false));
      g.dispose();
    });

    test('lecture discrète après la connexion au compte', () async {
      final s = Serveur()..reponse = etat('connecte', email: 'pepper@gmail.com');
      final g = ServiceGmail(s.api(), ouvrir: (_) async => true);
      g.lireBientot(const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(g.etat!.email, 'pepper@gmail.com');
      g.dispose();
    });
  });

  group('Paramètres › Outils › Gmail', () {
    Future<ServiceGmail> afficher(WidgetTester t, Map<String, dynamic> reponse, {Widget Function(ServiceGmail)? page}) async {
      final s = Serveur()..reponse = reponse;
      final g = ServiceGmail(s.api(), ouvrir: (_) async => true);
      await t.pumpWidget(cadre(page?.call(g) ?? PanneauGmail(service: g)));
      await t.runAsync(() => g.actualiser());
      await t.pumpAndSettle();
      return g;
    }

    testWidgets('Outils : Gmail, son statut, ouverture', (t) async {
      OutilJarvis? ouvert;
      final g = await afficher(t, etat('connecte', email: 'pepper@gmail.com'),
          page: (g) => PanneauOutils(gmail: g, surChoix: (o) => ouvert = o));
      expect(find.text('Gmail'), findsOneWidget);
      expect(find.text('Connecté'), findsOneWidget);
      // Agenda (K1-14) : entrée prévue, aucun calendrier raccordé.
      expect(find.text('Agenda'), findsOneWidget);
      await t.tap(find.text('Gmail'));
      expect(ouvert, OutilJarvis.gmail);
      g.etat = const EtatGmail(statut: StatutGmail.nonConnecte);
      g.notifyListeners();
      await t.pump();
      expect(find.text('Déconnecté'), findsOneWidget);           // même état que la page Gmail
      await t.pumpWidget(const SizedBox());
      g.dispose();
    });

    testWidgets('déconnecté : invitation courte, aucun champ de mot de passe', (t) async {
      final g = await afficher(t, etat('non_connecte'));
      expect(find.text('Déconnecté'), findsOneWidget);
      expect(find.text('Connectez le compte Google que vous souhaitez utiliser avec JARVIS.'), findsOneWidget);
      expect(find.text('Choisir un compte Google'), findsOneWidget);
      expect(find.text('Connexion sécurisée via Google.'), findsOneWidget);
      expect(find.text('AUTORISATIONS'), findsNothing);           // plus de long encadré
      expect(find.byType(TextField), findsNothing);
      await t.pumpWidget(const SizedBox());
      g.dispose();
    });

    testWidgets('connecté : compte, lecture seule, « Gérer la connexion » regroupe les actions', (t) async {
      final g = await afficher(t, etat('connecte', email: 'pepper@gmail.com'));
      expect(find.text('Connecté'), findsOneWidget);
      expect(find.text('pepper@gmail.com'), findsOneWidget);
      expect(find.text('Lecture seule'), findsOneWidget);
      expect(find.text('Changer de compte'), findsNothing);       // pas affiché en permanence
      expect(find.text('Déconnecter Gmail'), findsNothing);
      await t.tap(find.text('Gérer la connexion'));
      await t.pumpAndSettle();
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

    testWidgets('réouverture : état connu affiché aussitôt, sans chargement', (t) async {
      final g = await afficher(t, etat('connecte', email: 'pepper@gmail.com'));
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(cadre(PanneauGmail(service: g)));       // première image, sans attendre
      expect(find.text('pepper@gmail.com'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.pumpWidget(const SizedBox());
      g.dispose();
    });

    testWidgets('premier affichage sans état : neutre et discret, jamais « Connecté »', (t) async {
      final g = ServiceGmail(Serveur().api(), ouvrir: (_) async => true);
      await t.pumpWidget(cadre(PanneauGmail(service: g)));
      expect(find.text('Vérification…'), findsOneWidget);
      expect(find.text('Connecté'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      g.dispose();
    });

    testWidgets('à renouveler : message et reconnexion', (t) async {
      final g = await afficher(t, etat('a_renouveler', email: 'pepper@gmail.com'));
      expect(find.text('À reconnecter'), findsOneWidget);
      expect(find.text('L’autorisation a expiré ou a été retirée chez Google.'), findsOneWidget);
      expect(find.text('Reconnecter Gmail'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      g.dispose();
    });

    testWidgets('connexion en cours chez Google', (t) async {
      final g = await afficher(t, etat('non_connecte'));
      await t.runAsync(() => g.connecter());
      await t.pump();
      expect(find.text('Connexion en cours'), findsOneWidget);
      expect(find.textContaining('Terminez la connexion chez Google'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pump();
      expect(g.enAttente, isFalse);
      await t.pumpWidget(const SizedBox());
      g.dispose();
    });

    testWidgets('serveur non configuré et sans compte JARVIS', (t) async {
      final g = await afficher(t, etat('non_connecte', configure: false));
      expect(find.textContaining('pas encore disponible sur ce serveur'), findsOneWidget);
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
      // Demandes indirectes (phase 1 Gmail) : comprises par le serveur, jamais
      // interceptées par le moteur local.
      for (final p in ['Ils m’ont répondu ?', 'Est-ce que mon école m’a répondu ?', 'Le professeur m’a répondu ?',
                       'J’ai reçu quelque chose d’important cette semaine ?', 'Celui de chimie.',
                       'Tu peux retrouver ce mail où on me disait que mon rendez-vous avait changé ?',
                       'Retrouve le message d’hier.']) {
        expect(await local.repondreLocalement(d(p), avecIA: true), isNull, reason: p);
      }
      final heure = await local.repondreLocalement(d('Quelle heure est-il ?'), avecIA: true);
      expect(heure, isNotNull);                                                  // commande locale gardée
    });

    test('K1-16 : « je lui réponds quoi ? » sans conversation collée va à l’IA (cartes)', () async {
      final local = MoteurConversationLocal();
      DemandeJarvis d(String t) => DemandeJarvis(
        texte: t, intention: const DetecteurIntention().detecter(t, conversationConnue: false));
      const q = 'Ma voisine m’a écrit : tu peux arroser mes plantes ? Je lui réponds quoi ?';
      expect(await local.repondreLocalement(d(q), avecIA: true), isNull);
      // Sans IA (sans compte) : on demande toujours de coller la conversation.
      expect((await local.repondreLocalement(d(q)))!.texte, MoteurConversationLocal.demandeConversation);
    });
  });
}
