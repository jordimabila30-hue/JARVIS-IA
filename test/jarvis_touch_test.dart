import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/jarvis_touch_service.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/widgets/parametres/pages_jarvis_touch.dart';
import 'package:ia_jarvis/widgets/parametres/panneau_general.dart';

/// Module natif simulé : autorisation et bulle pilotées par le test.
class _FausseBulle implements PlateformeJarvisTouch {
  bool autorise = false;
  bool affichee = false;
  bool echoue = false;
  int demandes = 0;

  @override
  Future<bool> autorisationAccordee() async => autorise;

  @override
  Future<void> demanderAutorisation() async => demandes++;

  @override
  Future<bool> demarrer() async {
    if (echoue) throw PlatformException(code: 'echec', message: 'Raté.');
    affichee = true;
    return true;
  }

  @override
  Future<void> arreter() async => affichee = false;

  @override
  Future<bool> estActif() async => affichee;

  bool captureSansAutorisation = false;
  int reglagesCapture = 0;

  @override
  Future<CaptureEcranTouch> etatCapture() async => CaptureEcranTouch(
    sansAutorisationPossible: true,
    sansAutorisation: captureSansAutorisation,
  );

  @override
  Future<void> ouvrirReglagesCapture() async => reglagesCapture++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FausseBulle bulle;
  late StockageMemoire stockage;
  JarvisTouchService service({bool disponible = true}) => JarvisTouchService(
    plateforme: bulle,
    stockage: stockage,
    disponible: disponible,
  );

  setUp(() {
    bulle = _FausseBulle();
    stockage = StockageMemoire();
  });

  test('désactivé par défaut', () async {
    final s = service();
    await s.restaurer();
    expect(s.etat, EtatJarvisTouch.desactive);
    expect(bulle.affichee, isFalse);
  });

  test('autorisé : la bulle démarre et le choix est enregistré', () async {
    bulle.autorise = true;
    final s = service();
    await s.activer();
    expect(s.actif, isTrue);
    expect(bulle.affichee, isTrue);
    expect(stockage.valeur, 'oui');

    await s.desactiver();
    expect(s.etat, EtatJarvisTouch.desactive);
    expect(bulle.affichee, isFalse);
    expect(stockage.valeur, 'non');
  });

  test('sans autorisation : demande, puis démarrage au retour', () async {
    final s = service();
    await s.activer();
    expect(bulle.demandes, 1);
    expect(s.etat, EtatJarvisTouch.attenteAutorisation);
    expect(s.actif, isFalse);

    bulle.autorise = true;
    await s.synchroniser();
    expect(s.actif, isTrue);
    expect(bulle.affichee, isTrue);
  });

  test('autorisation refusée : reste désactivé avec une explication', () async {
    final s = service();
    await s.activer();
    await s.synchroniser();
    expect(s.etat, EtatJarvisTouch.desactive);
    expect(s.message, JarvisTouchService.refus);
    expect(bulle.affichee, isFalse);
  });

  test('échec du service : jamais affiché « actif »', () async {
    bulle
      ..autorise = true
      ..echoue = true;
    final s = service();
    await s.activer();
    expect(s.actif, isFalse);
    expect(s.message, 'Raté.');
    expect(stockage.valeur, 'non');
  });

  test(
    'relancé au démarrage si activé, coupé si autorisation retirée',
    () async {
      bulle.autorise = true;
      stockage.valeur = 'oui';
      final s = service();
      await s.restaurer();
      expect(s.actif, isTrue);

      bulle.autorise = false;
      await s.synchroniser();
      expect(s.actif, isFalse);
      expect(bulle.affichee, isFalse);
      expect(s.message, isNotNull);
    },
  );

  testWidgets('Général : une entrée JARVIS Touch, page dédiée avec interrupteur', (
    tester,
  ) async {
    PageGenerale? ouverte;
    Future<void> monter(JarvisTouchService s, {PageGenerale? page}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PanneauGeneral(
                  touch: s,
                  page: page,
                  surPage: (p) => ouverte = p,
                ),
              ),
            ),
          ),
        );
    final s = service();
    await monter(s);
    expect(find.text('JARVIS Touch'), findsOneWidget);
    expect(find.text('Assistant flottant'), findsOneWidget);
    // Général n'est plus chargé : ni interrupteur ni réglages de capture.
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Capture d’écran'), findsNothing);
    await tester.tap(find.text('JARVIS Touch'));
    expect(ouverte, PageGenerale.touch);

    await monter(s, page: PageGenerale.touch);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('Capture d’écran'), findsOneWidget);
    expect(find.text('Personnalisation'), findsOneWidget);
    await tester.tap(find.text('Capture d’écran'));
    expect(ouverte, PageGenerale.capture);

    await monter(service(disponible: false));
    expect(find.text('JARVIS Touch'), findsNothing);
    expect(find.text('Version'), findsOneWidget);
  });

  testWidgets('Capture d’écran : état réel, jamais « Autorisé » à tort', (
    tester,
  ) async {
    final s = service();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PanneauGeneral(touch: s, page: PageGenerale.capture),
          ),
        ),
      ),
    );
    expect(find.text('…'), findsOneWidget);

    await tester.runAsync(s.synchroniser);
    await tester.pump();
    expect(find.text('Non autorisé'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);   // aucun faux interrupteur

    await tester.tap(find.text('Gérer l’autorisation'));
    await tester.pump();
    expect(bulle.reglagesCapture, 1);

    bulle.captureSansAutorisation = true;
    await tester.runAsync(s.synchroniser);
    await tester.pump();
    expect(find.text('Autorisé'), findsOneWidget);
  });
}
