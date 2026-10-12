// Authentification : connexion, inscription, mot de passe oublié (sans
// serveur), validations locales, responsive, architecture et accès de
// développement.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/main.dart';
import 'package:ia_jarvis/models/authentification/resultat_auth.dart';
import 'package:ia_jarvis/models/authentification/utilisateur_auth.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/pages/authentification/authentification_page.dart';
import 'package:ia_jarvis/pages/authentification/connexion_page.dart';
import 'package:ia_jarvis/pages/authentification/inscription_page.dart';
import 'package:ia_jarvis/pages/authentification/mot_de_passe_oublie_page.dart';
import 'package:ia_jarvis/services/authentification/auth_repository.dart';
import 'package:ia_jarvis/services/authentification/auth_service.dart';
import 'package:ia_jarvis/services/authentification/config_auth.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/authentification/bouton_auth.dart';
import 'package:ia_jarvis/widgets/authentification/conteneur_auth.dart';
import 'package:ia_jarvis/widgets/authentification/entete_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dépôt de test : enregistre les appels. Par défaut il se comporte comme
/// l'application actuelle (aucun serveur) ; [attente] retient la réponse
/// (chargement), [reponse] remplace l'échec (futur serveur).
class _Depot implements AuthRepository {
  final appels = <String>[];
  Completer<void>? attente;
  ResultatAuth<UtilisateurAuth>? reponse;
  static const _nonConfigure = AuthRepositoryNonConfigure();

  Future<void> _patienter() async {
    if (attente case final a?) await a.future;
  }

  @override
  Future<ResultatAuth<UtilisateurAuth>> connecter({
    required String email,
    required String motDePasse,
  }) async {
    appels.add('connecter:$email');
    await _patienter();
    return reponse ??
        await _nonConfigure.connecter(email: email, motDePasse: motDePasse);
  }

  @override
  Future<ResultatAuth<UtilisateurAuth>> inscrire(
    DemandeInscription demande,
  ) async {
    appels.add('inscrire:${demande.nom}:${demande.email}');
    await _patienter();
    return reponse ?? await _nonConfigure.inscrire(demande);
  }

  @override
  Future<ResultatAuth<void>> demanderRecuperation(String email) async {
    appels.add('recuperation:$email');
    await _patienter();
    return _nonConfigure.demanderRecuperation(email);
  }

  @override
  Future<ResultatAuth<void>> deconnecter() => _nonConfigure.deconnecter();

  @override
  Future<ResultatAuth<UtilisateurAuth?>> verifierSession() =>
      _nonConfigure.verifierSession();

  @override
  Future<ResultatAuth<UtilisateurAuth?>> restaurerSession() =>
      _nonConfigure.restaurerSession();
}

late _Depot _depot;
late AuthService _service;
final _connectes = <UtilisateurAuth>[];
var _accesDev = 0;

Future<void> _monter(
  WidgetTester tester, {
  Size taille = const Size(390, 844),
  bool acces = true,
  EcranAuth ecran = EcranAuth.connexion,
}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _depot = _Depot();
  _service = AuthService(_depot);
  _connectes.clear();
  _accesDev = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: themeJarvis(),
      home: AuthentificationPage(
        service: _service,
        ecranInitial: ecran,
        surConnecte: _connectes.add,
        surAccesDeveloppement: acces ? () => _accesDev++ : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _champ(String libelle) => find.descendant(
  of: find
      .ancestor(of: find.text(libelle), matching: find.byType(Column))
      .first,
  matching: find.byType(EditableText),
);

Future<void> _saisir(WidgetTester tester, String libelle, String texte) =>
    tester.enterText(_champ(libelle), texte);

Future<void> _appuyer(WidgetTester tester, String libelle) async {
  final f = find.widgetWithText(BoutonAuth, libelle);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _lien(WidgetTester tester, String libelle) async {
  final f = find.widgetWithText(TextButton, libelle);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

bool _masque(WidgetTester tester, String libelle) =>
    tester.widget<EditableText>(_champ(libelle)).obscureText;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Connexion', () {
    testWidgets('1. formulaire : en-tête, deux champs, liens, bouton', (
      tester,
    ) async {
      await _monter(tester);
      expect(find.byType(ConnexionPage), findsOneWidget);
      expect(find.byType(LogoAuth), findsOneWidget);
      expect(find.text('JARVIS'), findsOneWidget);
      expect(find.text('Heureux de vous revoir'), findsOneWidget);
      expect(find.text('Adresse e-mail'), findsOneWidget);
      expect(find.text('Mot de passe'), findsOneWidget);
      expect(find.text('Mot de passe oublié ?'), findsOneWidget);
      expect(find.widgetWithText(BoutonAuth, 'Se connecter'), findsOneWidget);
      expect(find.text('Créer un compte'), findsOneWidget);
    });

    testWidgets('2. champs vides : erreurs, aucune requête', (tester) async {
      await _monter(tester);
      await _appuyer(tester, 'Se connecter');
      expect(find.text('Saisissez votre adresse e-mail.'), findsOneWidget);
      expect(find.text('Saisissez votre mot de passe.'), findsOneWidget);
      expect(_depot.appels, isEmpty);
    });

    testWidgets('3. adresse e-mail invalide, puis corrigée (espaces retirés)', (
      tester,
    ) async {
      await _monter(tester);
      await _saisir(tester, 'Adresse e-mail', 'jordi@exemple');
      await _saisir(tester, 'Mot de passe', 'secret');
      await _appuyer(tester, 'Se connecter');
      expect(find.text('Adresse e-mail invalide.'), findsOneWidget);
      expect(_depot.appels, isEmpty);
      // Correction : l'erreur disparaît pendant la saisie.
      await _saisir(tester, 'Adresse e-mail', '  jordi@exemple.com ');
      await tester.pump();
      expect(find.text('Adresse e-mail invalide.'), findsNothing);
      await _appuyer(tester, 'Se connecter');
      expect(_depot.appels, ['connecter:jordi@exemple.com']);
    });

    testWidgets('4. afficher puis masquer le mot de passe', (tester) async {
      await _monter(tester);
      expect(_masque(tester, 'Mot de passe'), isTrue);
      await tester.tap(find.byTooltip('Afficher le mot de passe'));
      await tester.pump();
      expect(_masque(tester, 'Mot de passe'), isFalse);
      await tester.tap(find.byTooltip('Masquer le mot de passe'));
      await tester.pump();
      expect(_masque(tester, 'Mot de passe'), isTrue);
    });

    testWidgets('5-6. vers l’inscription et vers la récupération', (
      tester,
    ) async {
      await _monter(tester);
      await _lien(tester, 'Créer un compte');
      expect(find.byType(InscriptionPage), findsOneWidget);
      await _lien(tester, 'Connexion');
      expect(find.byType(ConnexionPage), findsOneWidget);
      await _lien(tester, 'Mot de passe oublié ?');
      expect(find.byType(MotDePasseOubliePage), findsOneWidget);
    });

    testWidgets('7. aucune fausse authentification : message clair, '
        'aucun utilisateur', (tester) async {
      await _monter(tester);
      await _saisir(tester, 'Adresse e-mail', 'jordi@exemple.com');
      await _saisir(tester, 'Mot de passe', 'secret');
      await _appuyer(tester, 'Se connecter');
      expect(find.text(ConnexionPage.nonDisponible), findsOneWidget);
      expect(_connectes, isEmpty);
      expect(_service.connecte, isFalse);
      expect(_service.utilisateur, isNull);
      expect(find.byType(ConnexionPage), findsOneWidget);
      // Nouvel envoi invalide : l'ancien message ne reste pas affiché.
      await _saisir(tester, 'Adresse e-mail', 'invalide');
      await _appuyer(tester, 'Se connecter');
      expect(find.text('Adresse e-mail invalide.'), findsOneWidget);
      expect(find.text(ConnexionPage.nonDisponible), findsNothing);
    });

    testWidgets('clavier : Entrée passe au mot de passe puis envoie', (
      tester,
    ) async {
      await _monter(tester);
      await tester.tap(_champ('Adresse e-mail'));
      await tester.enterText(_champ('Adresse e-mail'), 'jordi@exemple.com');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(
        tester.widget<EditableText>(_champ('Mot de passe')).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(_champ('Mot de passe'), 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_depot.appels, hasLength(1));
    });

    testWidgets('chargement : bouton occupé, pas de double envoi', (
      tester,
    ) async {
      await _monter(tester);
      _depot.attente = Completer<void>();
      await _saisir(tester, 'Adresse e-mail', 'jordi@exemple.com');
      await _saisir(tester, 'Mot de passe', 'secret');
      await tester.tap(find.widgetWithText(BoutonAuth, 'Se connecter'));
      await tester.pump();
      expect(_service.enCours, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Entrée pendant le chargement : ignorée.
      await tester.tap(_champ('Mot de passe'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(_depot.appels, hasLength(1));
      _depot.attente!.complete();
      await tester.pumpAndSettle();
      expect(_service.enCours, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('futur serveur : seul un succès réel ouvre JARVIS', (
      tester,
    ) async {
      await _monter(tester);
      const u = UtilisateurAuth(identifiant: '1', email: 'jordi@exemple.com');
      _depot.reponse = const SuccesAuth(u);
      await _saisir(tester, 'Adresse e-mail', 'jordi@exemple.com');
      await _saisir(tester, 'Mot de passe', 'secret');
      await _appuyer(tester, 'Se connecter');
      expect(_connectes, [u]);
      expect(_service.utilisateur, u);
    });

    testWidgets('erreur du serveur : bandeau d’erreur', (tester) async {
      await _monter(tester);
      _depot.reponse = const EchecAuth(
        ErreurAuth(TypeErreurAuth.identifiantsInvalides),
      );
      await _saisir(tester, 'Adresse e-mail', 'jordi@exemple.com');
      await _saisir(tester, 'Mot de passe', 'faux');
      await _appuyer(tester, 'Se connecter');
      expect(
        find.text('Adresse e-mail ou mot de passe incorrect.'),
        findsOneWidget,
      );
      expect(_connectes, isEmpty);
    });
  });

  group('Inscription', () {
    testWidgets('8. en-tête et quatre champs', (tester) async {
      await _monter(tester, ecran: EcranAuth.inscription);
      expect(find.text('Rejoindre JARVIS'), findsOneWidget);
      expect(find.text('Créez votre espace personnel'), findsOneWidget);
      for (final l in [
        'Nom ou pseudonyme',
        'Adresse e-mail',
        'Mot de passe',
        'Confirmer le mot de passe',
      ]) {
        expect(find.text(l), findsOneWidget);
      }
      expect(find.byType(EditableText), findsNWidgets(4));
      expect(
        find.widgetWithText(BoutonAuth, 'Créer mon compte'),
        findsOneWidget,
      );
      expect(find.text('Déjà un compte ?'), findsOneWidget);
    });

    testWidgets('9-11. e-mail, longueur, mots de passe différents : erreurs '
        'sous les champs', (tester) async {
      await _monter(tester, ecran: EcranAuth.inscription);
      await _appuyer(tester, 'Créer mon compte');
      expect(find.text('Saisissez un nom ou un pseudonyme.'), findsOneWidget);
      expect(find.text('Saisissez votre adresse e-mail.'), findsOneWidget);
      expect(find.text('Choisissez un mot de passe.'), findsOneWidget);
      expect(find.text('Confirmez votre mot de passe.'), findsOneWidget);

      await _saisir(tester, 'Nom ou pseudonyme', '   ');
      await _saisir(tester, 'Adresse e-mail', 'pas une adresse');
      await _saisir(tester, 'Mot de passe', 'court');
      await _saisir(tester, 'Confirmer le mot de passe', 'autre');
      await _appuyer(tester, 'Créer mon compte');
      expect(find.text('Saisissez un nom ou un pseudonyme.'), findsOneWidget);
      expect(find.text('Adresse e-mail invalide.'), findsOneWidget);
      expect(find.text('Au moins 8 caractères.'), findsOneWidget);
      expect(
        find.text('Les mots de passe ne correspondent pas.'),
        findsOneWidget,
      );
      expect(_depot.appels, isEmpty);

      // Tout est corrigé : nom et e-mail nettoyés, mot de passe intact.
      await _saisir(tester, 'Nom ou pseudonyme', '  Jordi   M ');
      await _saisir(tester, 'Adresse e-mail', ' jordi@exemple.com ');
      await _saisir(tester, 'Mot de passe', 'motdepasse1');
      await _saisir(tester, 'Confirmer le mot de passe', 'motdepasse1');
      await _appuyer(tester, 'Créer mon compte');
      expect(_depot.appels, ['inscrire:Jordi M:jordi@exemple.com']);
    });

    testWidgets('afficher les mots de passe', (tester) async {
      await _monter(tester, ecran: EcranAuth.inscription);
      expect(find.byTooltip('Afficher le mot de passe'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Afficher le mot de passe').first);
      await tester.pump();
      expect(_masque(tester, 'Mot de passe'), isFalse);
      expect(_masque(tester, 'Confirmer le mot de passe'), isTrue);
    });

    testWidgets('12. retour à la connexion, saisies conservées', (
      tester,
    ) async {
      await _monter(tester);
      await _saisir(tester, 'Adresse e-mail', 'jordi@exemple.com');
      await _lien(tester, 'Créer un compte');
      // L'adresse suit d'une page à l'autre.
      expect(find.text('jordi@exemple.com'), findsOneWidget);
      await _saisir(tester, 'Nom ou pseudonyme', 'Jordi');
      await _lien(tester, 'Connexion');
      expect(find.byType(ConnexionPage), findsOneWidget);
      await _lien(tester, 'Créer un compte');
      expect(find.text('Jordi'), findsOneWidget);
    });

    testWidgets('13. aucun compte fictif créé', (tester) async {
      await _monter(tester, ecran: EcranAuth.inscription);
      await _saisir(tester, 'Nom ou pseudonyme', 'Jordi');
      await _saisir(tester, 'Adresse e-mail', 'jordi@exemple.com');
      await _saisir(tester, 'Mot de passe', 'motdepasse1');
      await _saisir(tester, 'Confirmer le mot de passe', 'motdepasse1');
      await _appuyer(tester, 'Créer mon compte');
      expect(find.text(InscriptionPage.nonDisponible), findsOneWidget);
      expect(_connectes, isEmpty);
      expect(_service.utilisateur, isNull);
    });
  });

  group('Mot de passe oublié', () {
    testWidgets('14. validation de l’adresse e-mail', (tester) async {
      await _monter(tester, ecran: EcranAuth.recuperation);
      expect(find.text('Mot de passe oublié ?'), findsOneWidget);
      expect(find.byType(LogoAuth), findsOneWidget);
      await _appuyer(tester, 'Envoyer le lien');
      expect(find.text('Saisissez votre adresse e-mail.'), findsOneWidget);
      await _saisir(tester, 'Adresse e-mail', 'jordi@');
      await _appuyer(tester, 'Envoyer le lien');
      expect(find.text('Adresse e-mail invalide.'), findsOneWidget);
      expect(_depot.appels, isEmpty);
    });

    testWidgets('15. retour à la connexion (lien et bouton Retour)', (
      tester,
    ) async {
      await _monter(tester, ecran: EcranAuth.recuperation);
      await _lien(tester, 'Retour à la connexion');
      expect(find.byType(ConnexionPage), findsOneWidget);
      await _lien(tester, 'Mot de passe oublié ?');
      // Retour système (Android, navigateur) : revient à la connexion.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ConnexionPage), findsOneWidget);
    });

    testWidgets('16. aucun faux « e-mail envoyé »', (tester) async {
      await _monter(tester, ecran: EcranAuth.recuperation);
      await _saisir(tester, 'Adresse e-mail', 'jordi@exemple.com');
      await _appuyer(tester, 'Envoyer le lien');
      expect(_depot.appels, ['recuperation:jordi@exemple.com']);
      expect(find.text(MotDePasseOubliePage.nonDisponible), findsOneWidget);
      expect(find.text(MotDePasseOubliePage.demandeTransmise), findsNothing);
    });
  });

  group('Responsive', () {
    for (final (taille, nom) in const [
      (Size(320, 568), '17. petit téléphone'),
      (Size(430, 932), '18. grand téléphone'),
      (Size(820, 1180), '19. tablette'),
      (Size(1366, 768), '20. ordinateur'),
      (Size(1920, 1080), 'grand écran'),
      (Size(500, 400), 'petite fenêtre'),
    ]) {
      testWidgets('$nom : trois pages sans débordement, largeur bornée', (
        tester,
      ) async {
        for (final e in EcranAuth.values) {
          await _monter(tester, taille: taille, ecran: e);
          expect(tester.takeException(), isNull);
          final formulaire = tester.getRect(
            find.descendant(
              of: find.byType(ConteneurAuth),
              matching: find.byType(Form),
            ),
          );
          expect(formulaire.width, lessThanOrEqualTo(ConteneurAuth.largeurMax));
          expect(formulaire.left, greaterThanOrEqualTo(0));
          expect(formulaire.right, lessThanOrEqualTo(taille.width));
          // Centré horizontalement.
          expect(formulaire.center.dx, closeTo(taille.width / 2, 1));
          // Boutons confortables.
          expect(
            tester.getSize(find.byType(BoutonAuth)).height,
            greaterThanOrEqualTo(48),
          );
          // En plus d'erreurs partout.
          final bouton = find.byType(BoutonAuth);
          await tester.ensureVisible(bouton);
          await tester.tap(bouton);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('21. clavier ouvert : défilement, champ actif visible', (
      tester,
    ) async {
      await _monter(tester, ecran: EcranAuth.inscription);
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final champ = _champ('Confirmer le mot de passe');
      await tester.ensureVisible(champ);
      await tester.tap(champ);
      await tester.pumpAndSettle();
      final r = tester.getRect(champ);
      expect(r.bottom, lessThanOrEqualTo(844 - 340));
      expect(r.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('Architecture', () {
    String source(String chemin) => File(chemin).readAsStringSync();

    testWidgets('23. les pages ne dépendent d’aucune API concrète', (
      tester,
    ) async {
      final pages = Directory(
        'lib/pages/authentification',
      ).listSync().whereType<File>().map((f) => f.readAsStringSync());
      for (final s in pages) {
        for (final interdit in [
          'package:http',
          'dart:io',
          'HttpClient',
          'Uri.parse',
          'http://',
          'https://',
          'SharedPreferences',
          'AuthRepositoryNonConfigure',
          'StockageSession',
        ]) {
          expect(s.contains(interdit), isFalse, reason: interdit);
        }
      }
    });

    test('24. le service accepte n’importe quel dépôt ; un seul endroit '
        'choisit l’implémentation', () async {
      final depot = _Depot()
        ..reponse = const SuccesAuth(
          UtilisateurAuth(identifiant: 'x', email: 'a@b.co'),
        );
      final service = AuthService(depot);
      final r = await service.connecter(email: 'a@b.co', motDePasse: 'p');
      expect(r, isA<SuccesAuth<UtilisateurAuth>>());
      expect(service.connecte, isTrue);
      await service.deconnecter();
      expect(service.connecte, isFalse);
      expect(
        const ConfigAuth().creerRepository(),
        isA<AuthRepositoryNonConfigure>(),
      );
      expect(
        RegExp('creerRepository').allMatches(source('lib/main.dart')).length,
        1,
      );
    });

    test('aucun serveur : aucune session, échecs « non configuré »', () async {
      final service = AuthService(const AuthRepositoryNonConfigure());
      expect(await service.restaurerSession(), isNull);
      final r = await service.demanderRecuperation('a@b.co');
      expect((r as EchecAuth).erreur.type, TypeErreurAuth.serveurNonConfigure);
      expect(service.connecte, isFalse);
    });

    test('double envoi refusé par le service', () async {
      final depot = _Depot()..attente = Completer<void>();
      final service = AuthService(depot);
      final premier = service.connecter(email: 'a@b.co', motDePasse: 'p');
      final second = await service.connecter(email: 'a@b.co', motDePasse: 'p');
      expect(
        (second as EchecAuth).erreur.type,
        TypeErreurAuth.operationEnCours,
      );
      depot.attente!.complete();
      await premier;
      expect(depot.appels, hasLength(1));
    });

    testWidgets('25. accès de développement isolé : absent si désactivé', (
      tester,
    ) async {
      await _monter(tester, acces: false);
      expect(find.text(BoutonAccesDeveloppement.libelle), findsNothing);
      await _monter(tester);
      expect(find.text(BoutonAccesDeveloppement.libelle), findsOneWidget);
      expect(find.textContaining('Mode développement'), findsOneWidget);
      // Désactivé par défaut hors configuration de compilation.
      expect(const ConfigAuth().accesDeveloppement, isFalse);
      final b = find.text(BoutonAccesDeveloppement.libelle);
      await tester.ensureVisible(b);
      await tester.tap(b);
      await tester.pumpAndSettle();
      expect(_accesDev, 1);
      // Aucun utilisateur, aucune session.
      expect(_connectes, isEmpty);
      expect(_service.connecte, isFalse);
    });

    testWidgets('26. aucun mot de passe stocké sur l’appareil', (tester) async {
      await _monter(tester);
      await _saisir(tester, 'Adresse e-mail', 'jordi@exemple.com');
      await _saisir(tester, 'Mot de passe', 'secret');
      await _appuyer(tester, 'Se connecter');
      await _lien(tester, 'Créer un compte');
      await _saisir(tester, 'Nom ou pseudonyme', 'Jordi');
      await _saisir(tester, 'Mot de passe', 'motdepasse1');
      await _saisir(tester, 'Confirmer le mot de passe', 'motdepasse1');
      await _appuyer(tester, 'Créer mon compte');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      for (final f in [
        'lib/services/authentification/auth_service.dart',
        'lib/widgets/authentification/brouillon_auth.dart',
      ]) {
        expect(source(f).contains('SharedPreferences'), isFalse);
      }
    });

    testWidgets('27-28. parcours complet : lancement → connexion → accès de '
        'développement → accueil existant', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const JarvisApp(config: ConfigAuth(accesDeveloppement: true)),
      );
      // Écran de lancement (3,2 s) puis fondu (0,7 s).
      for (var i = 0; i < 280; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(ConnexionPage), findsOneWidget);
      expect(find.byType(AccueilPage), findsNothing);
      await tester.tap(find.text(BoutonAccesDeveloppement.libelle));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(AccueilPage), findsOneWidget);
      expect(find.byType(AuthentificationPage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('production : pas d’accès de développement', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const JarvisApp(config: ConfigAuth()));
      for (var i = 0; i < 280; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(ConnexionPage), findsOneWidget);
      expect(find.text(BoutonAccesDeveloppement.libelle), findsNothing);
    });
  });
}
