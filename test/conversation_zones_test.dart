// Conversation écrite : zones (fil / PIM / barre), défilement invisible,
// clavier mobile, heures des messages, formulations neutres.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/pages/conversation_page.dart';
import 'package:ia_jarvis/services/conversation/analyse_conversation.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/detecteur_conversation.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';
import 'package:ia_jarvis/services/microphone_service.dart';
import 'package:ia_jarvis/services/niveau_micro.dart';
import 'package:ia_jarvis/services/peripheriques_audio.dart';
import 'package:ia_jarvis/services/speech_recognition_service.dart';
import 'package:ia_jarvis/services/tts_service.dart';
import 'package:ia_jarvis/services/voice_session.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/gabarit_jarvis.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/utils/local_date_time.dart';
import 'package:ia_jarvis/widgets/conversation/bulle_utilisateur.dart';
import 'package:ia_jarvis/widgets/conversation/carte_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/heure_message.dart';
import 'package:ia_jarvis/widgets/conversation/reponse_proposee.dart';
import 'package:ia_jarvis/widgets/conversation/signature_jarvis.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

class _Tts implements TtsService {
  @override
  String? voiceChoisie;
  @override
  Future<void> initialiser() async {}
  @override
  Future<void> appliquer(VoiceSettings reglages) async {}
  @override
  Future<List<VoixDisponible>> voixDisponibles({
    bool rafraichir = false,
  }) async => const [];
  @override
  Future<ResultatParole> parler(
    String texte, {
    void Function(int debut, int fin)? surMot,
    void Function()? surDebut,
  }) async => ResultatParole.lue;
  @override
  Future<void> arreter() async {}
}

class _Micros implements PeripheriquesAudio {
  @override
  bool get choixPossible => false;
  @override
  Future<List<MicroDisponible>> lister() async => const [];
  @override
  Future<bool> autoriser() async => false;
}

class _Micro implements MicrophoneService {
  @override
  Future<AccesMicro> demanderAcces() async => AccesMicro.autorise;
  @override
  Future<void> ouvrirReglages() async {}
}

class _Reco implements SpeechRecognitionService {
  @override
  Future<ErreurReconnaissance?> initialiser() async => null;
  @override
  Future<void> ecouter({
    required void Function(String phrase) surPhrase,
    required void Function(ErreurReconnaissance erreur) surErreur,
    required void Function() surFinSansResultat,
    void Function(String texte)? surPartiel,
    void Function(double amplitude)? surNiveau,
  }) async {}
  @override
  Future<void> annuler() async {}
}

class _Niveau implements NiveauMicro {
  @override
  Future<bool> demarrer(
    void Function(double niveau) surNiveau, {
    void Function(double graves, double mediums, double aigus)? surBandes,
    String? microphoneId,
  }) async => false;
  @override
  Future<void> arreter() async {}
}

/// Moteur qui garde les demandes reçues.
class _MoteurEspion extends MoteurConversationLocal {
  final demandes = <DemandeJarvis>[];

  @override
  Future<ReponseJarvis> repondre(DemandeJarvis demande) {
    demandes.add(demande);
    return super.repondre(demande);
  }
}

const _sarah =
    'Sarah : Tu aurais pu me prévenir.\n'
    'Moi : Désolé, j’étais occupé.\n'
    'Sarah : Ce n’est pas la première fois.';

final _longue = List.generate(
  30,
  (i) => i.isEven ? 'Sarah : Message $i.' : 'Moi : Réponse $i.',
).join('\n');

late PimController _pim;
late ConversationSession _conversation;

/// Horloge des messages : une minute de plus à chaque message, à partir
/// de 13:08.
DateTime Function() _horlogeDepuis(DateTime debut) {
  var n = 0;
  return () => debut.add(Duration(minutes: n++));
}

Widget _page({
  Duration reflexion = const Duration(milliseconds: 300),
  DateTime Function()? horloge,
}) {
  final tts = _Tts();
  _pim = PimController();
  _conversation = ConversationSession(
    delaiReflexion: reflexion,
    horloge: horloge,
  );
  return MaterialApp(
    theme: themeJarvis(),
    home: AccueilPage(
      session: VoiceSession(
        micro: _Micro(),
        reconnaissance: _Reco(),
        voix: tts,
        niveau: _Niveau(),
        reglages: VoiceSettingsService(
          tts: tts,
          stockage: StockageMemoire(),
          peripheriques: _Micros(),
        ),
      ),
      pim: _pim,
      conversation: _conversation,
    ),
  );
}

Future<void> _images(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _taille(WidgetTester tester, Size s) async {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Écrit dans la barre puis envoie (Entrée), comme l'utilisateur.
Future<void> _envoyer(WidgetTester tester, String texte) async {
  await tester.enterText(find.byType(EditableText), texte);
  await _images(tester, 5);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await _images(tester, 45);
}

/// Conversation déjà longue : discussion, conversation collée, ton choisi.
Future<void> _remplir(WidgetTester tester) async {
  await _envoyer(tester, 'Bonjour JARVIS');
  await _envoyer(tester, _longue);
  await _envoyer(tester, 'Comment fonctionne une batterie ?');
  await _envoyer(tester, '$_sarah\n\nTu peux me dire quoi répondre ?');
  await tester.tap(find.text('Direct'));
  await _images(tester, 30);
}

Rect _fil(WidgetTester tester) =>
    tester.getRect(find.byKey(ConversationPage.cleFil));

Rect _zonePim(WidgetTester tester) {
  final page = tester.widget<ConversationPage>(find.byType(ConversationPage));
  return tester.getRect(find.byKey(page.cleZonePim!));
}

Rect _barre(WidgetTester tester) =>
    tester.getRect(find.byType(LigneDeCommande));

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(ConversationPage.cleFil),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

/// Séparation complète : fil, écart de sécurité, zone PIM (hauteur
/// maximale des particules au-dessus de la barre), barre.
void _verifierZones(
  WidgetTester tester, {
  String contexte = '',
  bool complete = true,
}) {
  final fil = _fil(tester);
  final zone = _zonePim(tester);
  final barre = _barre(tester);
  expect(fil.height, greaterThanOrEqualTo(0), reason: contexte);
  expect(
    fil.bottom,
    lessThan(zone.top),
    reason: 'fil au-dessus de la zone PIM $contexte',
  );
  expect(
    zone.bottom,
    closeTo(barre.top, 0.5),
    reason: 'zone PIM juste au-dessus de la barre $contexte',
  );
  final reserve = MesuresConversation.zonePimDe(_gabarit(tester));
  expect(
    zone.height,
    complete ? closeTo(reserve, 0.5) : lessThanOrEqualTo(reserve),
    reason: 'zone PIM complète $contexte',
  );
}

GabaritJarvis _gabarit(WidgetTester tester) =>
    GabaritJarvis.de(tester.view.physicalSize / tester.view.devicePixelRatio);

/// Ligne la plus haute où le moteur PIM dessine réellement, dans le repère
/// de l'écran.
Future<double> _hautPimDessine(WidgetTester tester) async {
  final objet = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(PimParticle),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  var haut = double.infinity;
  await tester.runAsync(() async {
    final image = await objet.toImage();
    final octets = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    for (var y = 0; y < image.height && haut.isInfinite; y++) {
      for (var x = 0; x < image.width; x++) {
        if (octets.getUint8((y * image.width + x) * 4 + 3) > 12) {
          haut = y.toDouble();
          break;
        }
      }
    }
  });
  return haut + tester.getTopLeft(find.byType(PimParticle)).dy;
}

void main() {
  group('Zones fil / PIM / barre', () {
    testWidgets('TEST 1 : aucune barre de défilement visible', (tester) async {
      await _taille(tester, const Size(1366, 768));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _remplir(tester);
      // Même au survol et pendant le défilement.
      final souris = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(souris.hover(_fil(tester).center));
      await tester.sendEventToBinding(souris.scroll(const Offset(0, -200)));
      await _images(tester, 10);
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(RawScrollbar), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.all());

    testWidgets('TEST 2 : molette, trackpad et doigt font défiler le fil', (
      tester,
    ) async {
      await _taille(tester, const Size(1366, 768));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _remplir(tester);
      final position = _position(tester);
      expect(position.pixels, 0);
      expect(position.maxScrollExtent, greaterThan(500));

      // Molette (liste inversée : vers le haut = relire l'historique).
      final souris = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(souris.hover(_fil(tester).center));
      await tester.sendEventToBinding(souris.scroll(const Offset(0, -300)));
      await _images(tester, 20);
      expect(position.pixels, greaterThan(100));
      await tester.sendEventToBinding(souris.scroll(const Offset(0, 300)));
      await _images(tester, 20);
      expect(position.pixels, lessThan(5));

      // Trackpad.
      await tester.drag(
        find.byKey(ConversationPage.cleFil),
        const Offset(0, 250),
        kind: PointerDeviceKind.trackpad,
      );
      await _images(tester, 40);
      expect(position.pixels, greaterThan(100));

      // Doigt.
      final avant = position.pixels;
      await tester.drag(
        find.byKey(ConversationPage.cleFil),
        const Offset(0, 300),
      );
      await _images(tester, 40);
      expect(position.pixels, greaterThan(avant + 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('TEST 3-6 : messages dans le fil, PIM autour de la barre', (
      tester,
    ) async {
      await _taille(tester, const Size(1366, 768));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _remplir(tester);
      await _images(tester, 120);
      _verifierZones(tester);

      final fil = _fil(tester);
      // Le fil découpe ses messages : rien n'est dessiné hors de sa
      // fenêtre (viewport rogné).
      final viewport = tester.renderObject<RenderViewport>(
        find.descendant(
          of: find.byKey(ConversationPage.cleFil),
          matching: find.byType(Viewport),
        ),
      );
      expect(viewport.clipBehavior, isNot(Clip.none));
      expect(tester.getRect(find.byType(Viewport)).bottom, fil.bottom);
      // Au repos, le dernier message s'arrête avant le bas du fil (marge).
      final dernier = tester.getRect(find.byType(CarteJarvis).first);
      expect(dernier.bottom, lessThanOrEqualTo(fil.bottom - 8));

      // Les particules entourent la barre (au-dessus et en dessous) sans
      // monter jusqu'au fil.
      expect(_pim.mode, ParticlePimMode.inputCalm);
      final barre = _barre(tester);
      expect(
        barre.top - fil.bottom,
        greaterThanOrEqualTo(MesuresConversation.zonePimDe(_gabarit(tester))),
      );

      // Ordre des calques : les particules sont dessinées derrière
      // l'interface (fil et barre), et ignorent les touches.
      final pile = tester.widget<Stack>(
        find
            .ancestor(
              of: find.byType(PimParticle),
              matching: find.byType(Stack),
            )
            .first,
      );
      final calque = (pile.children.first as Positioned).child;
      expect(calque, isA<PimParticle>());
      expect(
        find.descendant(
          of: find.byType(PimParticle),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
      // La barre reste utilisable : texte, « + », bouton vocal.
      expect(find.byTooltip('Ouvrir le chat vocal'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'Encore une');
      await _images(tester, 5);
      expect(find.text('Encore une'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('impulsion d’envoi : les particules restent sous le fil', (
      tester,
    ) async {
      await _taille(tester, const Size(429, 599));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _remplir(tester);
      await tester.enterText(find.byType(EditableText), 'Merci');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        _verifierZones(tester, contexte: 'image $i');
      }
    });
  });

  group('Heures des messages', () {
    test('format HH:mm', () {
      expect(heureCourte(DateTime(2026, 10, 7, 13, 8)), '13:08');
      expect(heureCourte(DateTime(2026, 10, 7, 9, 5)), '09:05');
      expect(heureCourte(DateTime(2026, 10, 7, 21, 39)), '21:39');
      expect(heureCourte(DateTime(2026, 10, 7)), '00:00');
    });

    test('TEST 9 : le modèle garde l’heure de création', () async {
      final debut = DateTime(2026, 10, 7, 16, 27);
      final s = ConversationSession(
        delaiReflexion: Duration.zero,
        horloge: _horlogeDepuis(debut),
      );
      await s.envoyer('Bonjour JARVIS');
      expect(s.messages[0].heure, debut);
      expect(s.messages[1].heure, debut.add(const Duration(minutes: 1)));
      // Choisir un ton ne change pas l'heure de la réponse.
      await s.envoyer('$_sarah\n\nTu peux me dire quoi répondre ?');
      final r = s.messages.last;
      await s.choisirTon(r.id, TonReponse.poli);
      expect(s.messages.last.heure, r.heure);
    });

    test('heure réelle par défaut', () async {
      final avant = DateTime.now();
      final s = ConversationSession(delaiReflexion: Duration.zero);
      await s.envoyer('Bonjour');
      final apres = DateTime.now();
      for (final m in s.messages) {
        expect(m.heure.isBefore(avant), isFalse);
        expect(m.heure.isAfter(apres), isFalse);
      }
    });

    testWidgets('TEST 7-8 : heure sous la bulle et sous la carte JARVIS', (
      tester,
    ) async {
      await _taille(tester, const Size(390, 844));
      await tester.pumpWidget(
        _page(horloge: _horlogeDepuis(DateTime(2026, 10, 7, 13, 8))),
      );
      await _images(tester, 10);
      await _envoyer(tester, 'Bonjour JARVIS');

      final bulle = find.byType(BulleUtilisateur);
      final carte = find.byType(CarteJarvis);
      final hUtil = find.descendant(of: bulle, matching: find.text('13:08'));
      final hJarvis = find.descendant(of: carte, matching: find.text('13:09'));
      expect(hUtil, findsOneWidget);
      expect(hJarvis, findsOneWidget);
      expect(find.byType(HeureMessage), findsNWidgets(2));

      // En bas à droite de la bulle et de la carte.
      final rb = tester.getRect(
        find.descendant(of: bulle, matching: find.byType(Container)).first,
      );
      final rh = tester.getRect(hUtil);
      expect(rh.bottom, closeTo(rb.bottom - 8, 2));
      expect(rh.right, closeTo(rb.right - 14, 2));
      final rc = tester.getRect(
        find.descendant(of: carte, matching: find.byType(Container)).first,
      );
      final rj = tester.getRect(hJarvis);
      expect(rj.bottom, closeTo(rc.bottom - 10, 2));
      expect(rj.right, closeTo(rc.right - 16, 2));
      // Discrète : petite et peu contrastée.
      final style = tester.widget<Text>(hUtil).style!;
      expect(style.fontSize, lessThanOrEqualTo(11));
      expect(style.color, HeureMessage.couleur);
      expect(tester.takeException(), isNull);
    });
  });

  group('Clavier mobile', () {
    const formats = {
      '390x844': Size(390, 844),
      '412x915': Size(412, 915),
      '360x800': Size(360, 800),
      '429x599': Size(429, 599),
    };
    for (final f in formats.entries) {
      testWidgets('TEST 10-13 ${f.key} : clavier fermé, partiel, ouvert, '
          'transitions', (tester) async {
        final ecran = f.value;
        await _taille(tester, ecran);
        await tester.pumpWidget(_page());
        await _images(tester, 10);
        await _remplir(tester);
        await _images(tester, 90);
        _verifierZones(tester, contexte: 'clavier fermé');

        final clavier = ecran.height * 0.42;
        await tester.tap(find.byType(EditableText));
        // Montée progressive (vérifiée à chaque image), pause à mi-course,
        // puis descente.
        Future<void> animer(double de, double a, String nom) async {
          for (var i = 1; i <= 18; i++) {
            final t = Curves.easeOutCubic.transform(i / 18);
            tester.view.viewInsets = FakeViewPadding(bottom: de + (a - de) * t);
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.takeException(), isNull, reason: '$nom image $i');
            _verifierZones(tester, contexte: '$nom image $i');
          }
        }

        await animer(0, clavier * 0.5, 'montée');
        await _images(tester, 30);
        _verifierZones(tester, contexte: 'clavier partiel');
        await animer(clavier * 0.5, clavier, 'fin de montée');
        await _images(tester, 30);
        _verifierZones(tester, contexte: 'clavier ouvert');

        // Barre juste au-dessus du clavier, fil toujours lisible.
        final barre = _barre(tester);
        expect(barre.bottom, lessThanOrEqualTo(ecran.height - clavier));
        expect(_fil(tester).height, greaterThan(90));
        expect(find.byType(ReponseProposee), findsOneWidget);

        await animer(clavier, 0, 'descente');
        await _images(tester, 30);
        _verifierZones(tester, contexte: 'clavier refermé');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('très petite hauteur : aucun débordement', (tester) async {
      await _taille(tester, const Size(360, 640));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _remplir(tester);
      await tester.tap(find.byType(EditableText));
      for (final bas in [200.0, 300.0, 360.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: bas);
        await _images(tester, 20);
        expect(tester.takeException(), isNull, reason: 'clavier $bas');
        _verifierZones(tester, contexte: 'clavier $bas', complete: false);
      }
    });
  });

  group('Défilement', () {
    testWidgets('TEST 14-16 : longue conversation, haut puis bas du fil', (
      tester,
    ) async {
      await _taille(tester, const Size(390, 844));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _remplir(tester);
      for (var i = 0; i < 6; i++) {
        await _envoyer(tester, 'Question $i ?');
      }
      final position = _position(tester);
      // Haut du fil : le premier message est visible, sous le logo.
      await tester.fling(
        find.byKey(ConversationPage.cleFil),
        const Offset(0, 4000),
        4000,
      );
      await _images(tester, 120);
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
      final premier = tester.getRect(find.text('Bonjour JARVIS'));
      final fil = _fil(tester);
      expect(premier.top, greaterThan(fil.top));
      expect(premier.bottom, lessThan(fil.bottom));
      // Bas du fil.
      await tester.fling(
        find.byKey(ConversationPage.cleFil),
        const Offset(0, -4000),
        4000,
      );
      await _images(tester, 120);
      expect(position.pixels, 0);
      expect(find.text('Question 5 ?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TEST 17 : près du bas, la nouvelle réponse est montrée', (
      tester,
    ) async {
      await _taille(tester, const Size(390, 844));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _remplir(tester);
      final position = _position(tester);
      // Un peu remonté, mais encore près du bas.
      position.jumpTo(60);
      await _images(tester, 2);
      await _envoyer(tester, 'Merci beaucoup');
      await _images(tester, 30);
      expect(position.pixels, 0);
      final reponse = tester.getRect(find.byType(CarteJarvis).first);
      expect(reponse.bottom, lessThanOrEqualTo(_fil(tester).bottom));
    });

    testWidgets('TEST 18 : remonté dans l’historique, la position est '
        'conservée', (tester) async {
      await _taille(tester, const Size(390, 844));
      await tester.pumpWidget(_page(reflexion: const Duration(seconds: 2)));
      await _images(tester, 10);
      await _envoyer(tester, 'Bonjour JARVIS');
      await _images(tester, 90);
      await _envoyer(tester, _longue);
      await _images(tester, 90);
      await _envoyer(tester, 'Comment fonctionne une batterie ?');
      await _images(tester, 90);

      // Nouvelle question, puis l'utilisateur remonte pendant que JARVIS
      // réfléchit.
      await tester.enterText(find.byType(EditableText), 'Et le soleil ?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _images(tester, 30);
      final position = _position(tester);
      // Haut du fil : la hauteur totale n'est connue exactement qu'une fois
      // les messages construits ; on attend que la position soit stable.
      for (var i = 0; i < 4; i++) {
        position.jumpTo(position.maxScrollExtent);
        await _images(tester, 15);
      }
      final repere = find.text('Bonjour JARVIS');
      final avant = tester.getRect(repere);
      final decalage = position.pixels;
      expect(decalage, greaterThan(ConversationPage.seuilBas));

      // La réponse arrive : pas de saut vers le bas.
      await _images(tester, 200);
      expect(_conversation.enReflexion, isFalse);
      expect(find.byType(CarteJarvis, skipOffstage: false), findsWidgets);
      expect(position.pixels, greaterThan(ConversationPage.seuilBas));
      expect(tester.getRect(repere).top, closeTo(avant.top, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('message de l’utilisateur : le fil redescend toujours', (
      tester,
    ) async {
      await _taille(tester, const Size(390, 844));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _remplir(tester);
      final position = _position(tester);
      position.jumpTo(position.maxScrollExtent);
      await _images(tester, 5);
      await _envoyer(tester, 'Nouvelle question ?');
      await _images(tester, 30);
      expect(position.pixels, 0);
      expect(find.text('Nouvelle question ?'), findsOneWidget);
    });
  });

  group('Formats', () {
    testWidgets('TEST 19 : Windows grand écran', (tester) async {
      await _taille(tester, const Size(1920, 1080));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _remplir(tester);
      await _images(tester, 90);
      _verifierZones(tester);
      final fil = _fil(tester);
      expect(
        fil.width,
        lessThanOrEqualTo(
          GabaritJarvis.de(const Size(1920, 1080)).largeurSaisie + 0.5,
        ),
      );
      expect(fil.center.dx, closeTo(960, 1));
      expect(find.byType(Scrollbar), findsNothing);
      // Redimensionnement de la fenêtre : moyenne, puis étroite.
      for (final s in const [Size(1100, 700), Size(700, 760), Size(429, 599)]) {
        await _taille(tester, s);
        await _images(tester, 40);
        expect(tester.takeException(), isNull, reason: '$s');
        _verifierZones(tester, contexte: '$s');
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    for (final s in const [
      Size(1366, 768),
      Size(820, 1180),
      Size(429, 599),
      Size(390, 844),
    ]) {
      testWidgets('TEST 20 : $s, zones séparées', (tester) async {
        await _taille(tester, s);
        await tester.pumpWidget(_page());
        await _images(tester, 10);
        await _remplir(tester);
        await _images(tester, 90);
        _verifierZones(tester);
        // Écart fil / particules proportionné : jamais énorme.
        final m = _zonePim(tester).top - _fil(tester).bottom;
        expect(m, inInclusiveRange(3, 7));
        expect(
          _zonePim(tester).height,
          lessThanOrEqualTo(MesuresConversation.zonePimDe(_gabarit(tester))),
        );
        // Séparation compacte : du dernier message à la barre, 65 px sur
        // téléphone et 74 px sur ordinateur (contre 105 à 118 px avant).
        final dernier = tester.getRect(find.byType(CarteJarvis).first);
        expect(_barre(tester).top - dernier.bottom, lessThanOrEqualTo(58));
        // Au repos, toujours un petit espace entre la carte et les
        // particules.
        await _images(tester, 60);
        expect(await _hautPimDessine(tester), greaterThan(dernier.bottom + 6));
        // La signature reste petite et dans la carte.
        final sig = tester.getRect(find.byType(SignatureJarvis).first);
        expect(sig.height, lessThanOrEqualTo(14));
        expect(sig.width, lessThan(120));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Non-régression', () {
    testWidgets('TEST 21 : PIM revient en sphère après la conversation', (
      tester,
    ) async {
      await _taille(tester, const Size(1366, 768));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _envoyer(tester, 'Bonjour JARVIS');
      await _images(tester, 60);
      await tester.tap(find.byTooltip('Nouvelle conversation'));
      await _images(tester, 300);
      expect(_pim.mode, isIn([ParticlePimMode.idle, ParticlePimMode.cube]));
      // La sphère n'est plus bornée par la zone de conversation.
      expect(_pim.etalement.maximum, lessThan(1.4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('TEST 22 : mode vocal depuis une conversation, puis retour', (
      tester,
    ) async {
      await _taille(tester, const Size(1366, 768));
      await tester.pumpWidget(_page());
      await _images(tester, 10);
      await _envoyer(tester, 'Bonjour JARVIS');
      await tester.tap(find.byTooltip('Ouvrir le chat vocal'));
      await _images(tester, 90);
      expect(find.byType(ConversationPage), findsNothing);
      expect(_pim.etatVocal, isNotNull);
      await tester.tap(find.text('Quitter le mode vocal'));
      await _images(tester, 120);
      expect(_pim.etatVocal, isNull);
      expect(find.byType(ConversationPage), findsOneWidget);
      expect(find.byType(BulleUtilisateur), findsOneWidget);
      await _images(tester, 60);
      _verifierZones(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Formulations neutres', () {
    const detecteur = DetecteurConversation();
    AnalyseConversation lire(String texte) =>
        AnalyseConversation(detecteur.analyser(texte).conversation!);

    // Formes accordées qui trahiraient un genre deviné.
    const accords = [
      'mise de côté',
      'mis de côté',
      'prise en',
      'pris en',
      'dérangée',
      'dérangé.',
      'quand il ',
      'quand elle ',
      'qu’il attend',
      'qu’elle attend',
      'il ou elle',
    ];

    String toutLeTexte(AnalyseConversation a) => [
      a.lectureCourte,
      a.avantReponse,
      a.resume,
      a.comprehension,
      a.analyser('Tu trouves que j’ai mal répondu ?'),
      a.analyser('Qu’est-ce qu’elle veut dire ?'),
      a.analyser('Il est fâché ?'),
    ].join('\n');

    test('le nom de la conversation est utilisé tel quel', () {
      for (final nom in ['Sarah', 'Léo', 'Clean Girl', 'Andrea']) {
        final a = lire(
          '$nom : Tu aurais pu me prévenir.\n'
          'Moi : Désolé, j’étais occupé.\n'
          '$nom : Ce n’est pas la première fois.',
        );
        final texte = toutLeTexte(a);
        expect(texte, contains(nom));
        for (final f in accords) {
          expect(texte.toLowerCase(), isNot(contains(f)), reason: '$nom : $f');
        }
      }
    });

    test('sans nom : « la personne », « ton interlocuteur »', () {
      final a = lire(
        'Elle : Tu aurais pu me prévenir.\n'
        'Moi : Désolé.\n'
        'Elle : Ce n’est pas la première fois.',
      );
      final texte = toutLeTexte(a);
      expect(texte, contains('La personne'));
      expect(a.lectureCourte, contains('ton interlocuteur'));
      expect(texte, isNot(contains('Elle te')));
      for (final f in accords) {
        expect(texte.toLowerCase(), isNot(contains(f)), reason: f);
      }
    });

    test('réponses proposées sans accord deviné', () async {
      final moteur = MoteurConversationLocal();
      final c = detecteur.analyser(_sarah).conversation!;
      for (final ton in TonReponse.values) {
        final r = await moteur.proposerReponse(c, ton);
        expect(r, isNot(contains('dérangée')));
      }
    });
  });

  group('Architecture remplaçable', () {
    test('le moteur reçoit le texte réel et l’historique', () async {
      final moteur = _MoteurEspion();
      final s = ConversationSession(
        moteur: moteur,
        delaiReflexion: Duration.zero,
      );
      await s.envoyer('Bonjour JARVIS');
      await s.envoyer('$_sarah\n\nTu peux me dire quoi répondre ?');
      final d = moteur.demandes.last;
      expect(d.texteComplet, '$_sarah\n\nTu peux me dire quoi répondre ?');
      expect(d.texte, 'Tu peux me dire quoi répondre ?');
      expect(d.historique, hasLength(2));
      expect(d.historique.first.texte, 'Bonjour JARVIS');
      expect(moteur.demandes.first.historique, isEmpty);
    });
  });

  group('Fermeture rapide du clavier : particules derrière les cartes', () {
    for (final ecran in const [
      Size(390, 844),
      Size(412, 915),
      Size(360, 800),
      Size(429, 599),
      Size(1366, 768),
    ]) {
      testWidgets('$ecran', (tester) async {
        await _taille(tester, ecran);
        await tester.pumpWidget(_page());
        await _images(tester, 10);
        await _remplir(tester);
        await _images(tester, 90);
        await tester.tap(find.byType(EditableText));
        final k = ecran.height * 0.42;
        var inertie = 0.0;
        for (final (de, a, n) in [
          (0.0, k, 15),
          (k, 0.0, 15),
          (0.0, k, 15),
          (k, 0.0, 6),
          (0.0, k, 15),
          (k, 0.0, 1),
        ]) {
          for (var i = 1; i <= n + 20; i++) {
            if (i <= n) {
              final t = Curves.easeInOutCubic.transform(i / n);
              tester.view.viewInsets = FakeViewPadding(
                bottom: de + (a - de) * t,
              );
            }
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.takeException(), isNull);
            _verifierZones(tester, contexte: '$de→$a ($n) image $i');
            final haut = await _hautPimDessine(tester);
            inertie = math.max(inertie, _zonePim(tester).top - haut);
          }
        }
        // Le moteur garde son inertie : pendant la descente, les particules
        // passent derrière les cartes (calque PIM sous le fil), puis
        // retrouvent leur place sous le dernier message.
        expect(inertie, greaterThan(20));
        expect(find.byType(ReponseProposee), findsOneWidget);
        await _images(tester, 60);
        final dernier = tester.getRect(find.byType(CarteJarvis).first);
        expect(await _hautPimDessine(tester), greaterThan(dernier.bottom));
      });
    }
  });

  group('Signature JARVIS', () {
    testWidgets('même signature pour toutes les réponses de JARVIS', (
      tester,
    ) async {
      await _taille(tester, const Size(1366, 768));
      await tester.pumpWidget(_page(reflexion: const Duration(seconds: 1)));
      await _images(tester, 10);

      /// La réponse la plus récente porte la signature, une seule fois.
      void signee(String nature) {
        final carte = find.byType(CarteJarvis).first;
        expect(
          find.descendant(of: carte, matching: find.byType(SignatureJarvis)),
          findsOneWidget,
          reason: nature,
        );
        expect(
          find.descendant(of: carte, matching: find.text('JARVIS')),
          findsOneWidget,
          reason: nature,
        );
      }

      // Pendant la réflexion aussi.
      await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _images(tester, 10);
      expect(
        find.descendant(
          of: find.byType(ReflexionJarvis),
          matching: find.byType(SignatureJarvis),
        ),
        findsOneWidget,
      );
      await _images(tester, 80);
      signee('réponse normale');
      await _envoyer(tester, _sarah);
      await _images(tester, 60);
      signee('lecture d’une conversation');
      await tester.tap(find.text('Résumer'));
      await _images(tester, 90);
      expect(find.textContaining('En bref'), findsOneWidget);
      signee('résumé');
      await _envoyer(tester, 'Elle est fâchée ?');
      await _images(tester, 60);
      signee('question sur la conversation');
      await _envoyer(tester, 'Tu peux me dire quoi répondre ?');
      await _images(tester, 60);
      await tester.tap(find.text('Poli'));
      await _images(tester, 30);
      expect(find.byType(ReponseProposee), findsOneWidget);
      signee('proposition de réponse');
      expect(tester.takeException(), isNull);
    });

    for (final s in const [
      Size(1920, 1080),
      Size(1366, 768),
      Size(820, 1180),
      Size(429, 599),
      Size(390, 844),
    ]) {
      testWidgets('$s : point et JARVIS alignés, petit et fin', (tester) async {
        await _taille(tester, s);
        await tester.pumpWidget(_page());
        await _images(tester, 10);
        await _envoyer(tester, 'Bonjour JARVIS');
        final sig = find.byType(SignatureJarvis).first;
        final perle = tester.getRect(
          find.descendant(of: sig, matching: find.byType(CustomPaint)).first,
        );
        final mot = tester.getRect(
          find.descendant(of: sig, matching: find.text('JARVIS')),
        );
        final carte = tester.getRect(find.byType(CarteJarvis).first);
        final contenu = tester.getRect(
          find
              .descendant(
                of: find.byType(CarteJarvis).first,
                matching: find.textContaining('Bonjour'),
              )
              .first,
        );
        // Point à gauche, centré verticalement sur le mot.
        expect(perle.right, lessThan(mot.left));
        expect(perle.center.dy, closeTo(mot.center.dy, 1));
        // Aligné sur le texte de la carte, à l'intérieur de la carte.
        expect(perle.left, closeTo(contenu.left, 0.5));
        expect(
          carte.contains(mot.topLeft) && carte.contains(mot.bottomRight),
          isTrue,
        );
        expect(contenu.top - mot.bottom, inInclusiveRange(6, 14));

        final style = tester
            .widget<Text>(
              find.descendant(of: sig, matching: find.text('JARVIS')),
            )
            .style!;
        expect(style.fontFamily, policeAffichage);
        expect(style.fontSize, lessThanOrEqualTo(10.5));
        expect(style.letterSpacing, greaterThanOrEqualTo(3));
        expect(style.fontWeight, FontWeight.w300);
        expect(perle.height, lessThanOrEqualTo(13));
        expect(mot.height, lessThan(14));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
