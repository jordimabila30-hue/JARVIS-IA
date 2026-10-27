import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/ouverture_messageries.dart';
import 'package:ia_jarvis/widgets/conversation/volet_aide_reponse.dart';
import 'package:ia_jarvis/widgets/feuille_ajout.dart';
import 'package:ia_jarvis/widgets/integrations/panneau_outils.dart';

void main() {
  group('K1-04/05/06 : ouvrir Instagram, Messenger, Mail', () {
    test(
      'Android, application installée : elle s’ouvre, pas le site',
      () async {
        final cibles = <String>[], sites = <Uri>[];
        final o = OuvertureMessageries(
          android: true,
          application: (c) async => (cibles..add(c)).isNotEmpty,
          navigateur: (s) async => (sites..add(s)).isNotEmpty,
        );
        expect(await o.ouvrir(Messagerie.instagram), isTrue);
        expect(cibles, ['com.instagram.android']);
        expect(sites, isEmpty);
      },
    );

    test('Android sans l’application : son site', () async {
      final sites = <Uri>[];
      final o = OuvertureMessageries(
        android: true,
        application: (_) async => false,
        navigateur: (s) async => (sites..add(s)).isNotEmpty,
      );
      await o.ouvrir(Messagerie.messenger);
      expect(sites.single.host, 'www.messenger.com');
    });

    test('Web / Windows : le site directement', () async {
      final cibles = <String>[], sites = <Uri>[];
      final o = OuvertureMessageries(
        android: false,
        application: (c) async => (cibles..add(c)).isNotEmpty,
        navigateur: (s) async => (sites..add(s)).isNotEmpty,
      );
      await o.ouvrir(Messagerie.mail);
      expect(cibles, isEmpty);
      expect(sites.single.host, 'mail.google.com');
      expect(Messagerie.mail.libelle, 'Gmail');
      expect(Messagerie.mail.cibleAndroid, 'com.google.android.gm');
    });

    testWidgets('la feuille renvoie le choix de la messagerie', (tester) async {
      ChoixAjout? choix;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  choix = await afficherFeuilleAjout(context),
              child: const Text('+'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      for (final t in ['Instagram', 'Messenger', 'Gmail']) {
        expect(find.text(t), findsOneWidget);
      }
      await tester.tap(find.text('Messenger'));
      await tester.pumpAndSettle();
      expect(choix, ChoixAjout.messenger);
      expect(choix!.messagerie, Messagerie.messenger);
    });
  });

  group('K1-16 : répondre à un message reçu hors WhatsApp', () {
    test('question : message cité, origine, intention, aucun envoi', () {
      const d = DemandeAideReponse(
        message: 'Tu viens samedi ?',
        origine: OrigineMessage.instagram,
        intention: 'non, je travaille',
      );
      expect(d.question, contains('reçu sur Instagram'));
      expect(d.question, contains('« Tu viens samedi ? »'));
      expect(
        d.question,
        contains('je voudrais lui dire ceci, non, je travaille.'),
      );
    });

    testWidgets('bouton actif seulement avec un message', (tester) async {
      DemandeAideReponse? d;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  d = await afficherVoletAideReponse(context),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      final bouton = find.widgetWithText(FilledButton, VoletAideReponse.action);
      expect(tester.widget<FilledButton>(bouton).onPressed, isNull);
      await tester.tap(find.text('SMS'));
      await tester.enterText(
        find.byKey(const Key('aide-message')),
        'On se voit demain ?',
      );
      await tester.pump();
      await tester.tap(bouton);
      await tester.pumpAndSettle();
      expect(d!.origine, OrigineMessage.sms);
      expect(d!.message, 'On se voit demain ?');
    });
  });

  testWidgets('K1-14 : Agenda dans les Outils, sans fournisseur', (
    tester,
  ) async {
    OutilJarvis? choisi;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PanneauOutils(gmail: null, surChoix: (o) => choisi = o),
        ),
      ),
    );
    expect(find.text('Agenda'), findsOneWidget);
    await tester.tap(find.text('Agenda'));
    expect(choisi, OutilJarvis.agenda);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: PanneauAgenda())),
      ),
    );
    expect(find.textContaining('Aucun calendrier'), findsOneWidget);
  });
}
