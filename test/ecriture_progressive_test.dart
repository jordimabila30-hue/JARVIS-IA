// Phase 4 : écriture progressive des réponses de JARVIS.
//
// Le moteur d'écriture est piloté avec des durées exactes ; le serveur est
// simulé par un flux SSE réel, envoyé fragment par fragment (aucun appel
// réseau, aucun quota GroqCloud consommé).

// Libération vérifiée par `hasListeners` (protégé, lu ici volontairement).
// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/pages/conversation_page.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_hybride.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_ia.dart';
import 'package:ia_jarvis/services/conversations/depot_conversations.dart';
import 'package:ia_jarvis/services/conversations/synchro_echanges_locaux.dart';
import 'package:ia_jarvis/services/ecriture/ecriture_progressive.dart';
import 'package:ia_jarvis/services/ecriture/texte_en_direct.dart';
import 'package:ia_jarvis/theme/gabarit_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/carte_jarvis.dart';
import 'package:ia_jarvis/widgets/ecriture/texte_progressif.dart';

const _image = Duration(milliseconds: 16);
const _uuid = '11111111-1111-4111-8111-111111111111';

/// Fait tourner l'écriture image par image ; renvoie le temps écoulé
/// jusqu'à ce qu'elle ait rattrapé le texte reçu (ou [max]).
Duration _animer(
  EcritureProgressive e, {
  Duration max = const Duration(seconds: 30),
  void Function(String visible)? surImage,
}) {
  var t = Duration.zero;
  while (e.enMouvement && t < max) {
    e.avancer(_image);
    t += _image;
    surImage?.call(e.visible);
  }
  return t;
}

/// Toutes les frontières de graphème du texte.
Set<int> _frontieres(String texte) {
  final r = <int>{0};
  var i = 0;
  for (final c in texte.characters) {
    i += c.length;
    r.add(i);
  }
  return r;
}

String _evenement(String type, Map<String, Object?> donnees) =>
    'event: $type\ndata: ${jsonEncode(donnees)}\n\n';

/// Serveur dont on envoie le flux SSE à la main, événement par événement :
/// réponse plus rapide ou plus lente que l'animation, coupure en plein
/// flux…
class _ServeurPilote {
  final requetes = <http.BaseRequest>[];
  StreamController<List<int>>? _flux;

  /// Réponse non SSE (refus, quota…) au lieu d'un flux.
  http.StreamedResponse Function()? refus;

  late final client = MockClient.streaming((r, _) async {
    requetes.add(r);
    final refus = this.refus;
    if (refus != null) return refus();
    final f = _flux = StreamController<List<int>>();
    return http.StreamedResponse(
      f.stream,
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );
  });

  ApiJarvis api() => ApiJarvis(
    adresse: Uri.parse('http://localhost:8000'),
    jeton: () async => 'jeton-acces',
    client: client,
  );

  bool get ouvert => _flux != null;

  void _envoyer(String type, Map<String, Object?> d) =>
      _flux!.add(utf8.encode(_evenement(type, d)));

  void meta() => _envoyer('meta', {
    'conversation_id': _uuid,
    'message_id': 'r1',
    'quota': {},
  });
  void delta(String texte) => _envoyer('delta', {'text': texte});
  void done() =>
      _envoyer('done', {'message_id': 'r1', 'usage': {}, 'quota': {}});
  void erreur(String message) => _envoyer('error', {'message': message});
  Future<void> fermer() async {
    final f = _flux!;
    _flux = null;
    await f.close();
  }
}

/// Laisse passer les microtâches (requête, décodage du flux).
Future<void> _laisser([int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _attendreFlux(_ServeurPilote s) async {
  for (var i = 0; i < 200 && !s.ouvert; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(s.ouvert, isTrue, reason: 'la requête de chat est partie');
}

ConversationSession _session(_ServeurPilote s, {DepotConversations? depot}) =>
    ConversationSession(
      delaiReflexion: Duration.zero,
      depot: depot,
      moteur: MoteurConversationHybride(ia: MoteurConversationIA(s.api())),
    );

List<MessageConversation> _deJarvis(ConversationSession c) => [
  for (final m in c.messages)
    if (m.deJarvis) m,
];

/// Dépôt Supabase minimal : la conversation [_uuid] avec les lignes que le
/// backend y a enregistrées.
class _Depot implements DepotConversations {
  @override
  String? utilisateur = 'compte-a';
  final lignes = <MessageServeur>[];

  @override
  Future<List<ConversationServeur>> lister({int limite = 100}) async => [];

  @override
  Future<PageMessages> messages(
    String id, {
    DateTime? avant,
    int limite = 50,
  }) async => PageMessages([...lignes]);

  @override
  Future<void> supprimer(String id) async {}
}

const _question = 'Raconte-moi l’histoire de Lima en quelques lignes';

void main() {
  group('Moteur d’écriture (EcritureProgressive)', () {
    test('texte complet : révélé progressivement, puis terminé', () {
      const texte = '6 fois 7 égale 42.';
      final e = EcritureProgressive.complet(texte);
      expect(e.visible, '');
      expect(e.enMouvement, isTrue);
      expect(e.termine, isFalse);
      e.avancer(const Duration(milliseconds: 100));
      expect(e.visible, '6', reason: 'mot par mot');
      expect(texte.startsWith(e.visible), isTrue);
      expect(e.visible.length, lessThan(texte.length));
      final t = _animer(e);
      expect(e.visible, texte);
      expect(e.termine, isTrue);
      expect(e.finie.value, isTrue);
      // Court : 5 mots, moins d'une demi-seconde.
      expect(t, lessThan(const Duration(milliseconds: 600)));
      e.dispose();
    });

    test('rythme posé, mot par mot (≈ 12 mots/s) ; seules les très '
        'longues réponses accélèrent', () {
      Duration duree(int mots) {
        final e = EcritureProgressive.complet(
          List.filled(mots, 'mot').join(' '),
        );
        final vus = <String>{};
        final t = _animer(e, surImage: vus.add);
        expect(e.termine, isTrue);
        // Toujours des mots entiers.
        for (final v in vus) {
          expect(v.isEmpty || v.endsWith('mot'), isTrue, reason: '« $v »');
        }
        e.dispose();
        return t;
      }

      final court = duree(20);
      final moyen = duree(100);
      final long = duree(400);
      final tresLong = duree(1500);
      expect(court, lessThan(const Duration(seconds: 2)));
      expect(moyen, greaterThan(const Duration(seconds: 7)));
      expect(moyen, lessThan(const Duration(milliseconds: 9500)));
      // Plafonnées à environ 20 s.
      expect(long, lessThan(const Duration(seconds: 21)));
      expect(tresLong, lessThan(const Duration(seconds: 21)));
    });

    test('mises à jour groupées : au plus une par image et par mot', () {
      final e = EcritureProgressive.complet('mot ' * 1000);
      var notifications = 0;
      e.addListener(() => notifications++);
      final t = _animer(e);
      expect(e.termine, isTrue);
      expect(notifications, lessThanOrEqualTo(t.inMilliseconds ~/ 16 + 2));
      expect(notifications, lessThanOrEqualTo(1000));
      e.dispose();
    });

    test('fragments : ordre exact, révélés pendant que la suite arrive', () {
      final source = TexteEnDirect();
      final e = EcritureProgressive(source);
      source.ajouter('Lima est ');
      expect(e.enMouvement, isTrue);
      _animer(e);
      // Mots entiers seulement.
      expect(e.visible, 'Lima est');
      expect(e.termine, isFalse, reason: 'réception en cours');
      source.ajouter('la capitale ');
      e.avancer(_image);
      source.ajouter('du Pérou.');
      _animer(e);
      // « Pérou. » n'est pas encore suivi d'un espace : il peut encore
      // être complété, il attend.
      expect(e.visible, 'Lima est la capitale du');
      source.terminer();
      _animer(e);
      expect(e.visible, 'Lima est la capitale du Pérou.');
      expect(e.termine, isTrue);
      e.dispose();
      source.dispose();
    });

    test('réponse plus rapide que l’animation : réception finie, '
        'affichage encore en cours', () {
      final source = TexteEnDirect();
      final e = EcritureProgressive(source);
      final complet = 'Un texte assez long. ' * 20;
      for (final mot in complet.split(' ')) {
        source.ajouter('$mot ');
      }
      source.terminer(complet.trim());
      expect(source.etat, EtatReception.terminee);
      expect(e.visible, '');
      expect(e.termine, isFalse, reason: 'rien encore affiché');
      e.avancer(const Duration(milliseconds: 100));
      expect(e.termine, isFalse);
      expect(e.reception, EtatReception.terminee);
      _animer(e);
      expect(e.visible, complet.trim());
      expect(e.termine, isTrue);
      e.dispose();
    });

    test('réponse plus lente que l’animation : l’écriture attend la suite', () {
      final source = TexteEnDirect();
      final e = EcritureProgressive(source);
      source.ajouter('Bonjour, ');
      _animer(e);
      expect(e.enMouvement, isFalse, reason: 'tout le reçu est visible');
      expect(e.termine, isFalse, reason: 'la réception continue');
      var notifie = false;
      e.addListener(() => notifie = true);
      source.ajouter('voici la suite.');
      expect(notifie, isTrue, reason: 'le widget relance son animation');
      expect(e.enMouvement, isTrue);
      source.terminer();
      _animer(e);
      expect(e.visible, 'Bonjour, voici la suite.');
      e.dispose();
    });

    test('gros retard (IA bien plus rapide que l’écriture) : rattrapage '
        'progressif, écriture bornée', () {
      final source = TexteEnDirect();
      final e = EcritureProgressive(source);
      var t = Duration.zero;
      // Le serveur envoie 2 000 mots en 4 s (≈ 500 mots/s).
      var envoyes = 0;
      while (envoyes < 2000) {
        for (var k = 0; k < 8 && envoyes < 2000; k++, envoyes++) {
          source.ajouter('mot ');
        }
        e.avancer(_image);
        t += _image;
      }
      source.terminer();
      t += _animer(e);
      expect(e.termine, isTrue);
      expect(t, lessThan(const Duration(seconds: 23)));
      e.dispose();
      source.dispose();
    });

    test('réponse vide : terminée aussitôt, rien d’affiché', () {
      final e = EcritureProgressive.complet('');
      expect(e.visible, '');
      expect(e.enMouvement, isFalse);
      expect(e.termine, isTrue);
      e.dispose();
    });

    test('Unicode : accents combinants et emojis composés jamais coupés', () {
      const fragments = [
        'Bravo ',
        '👨‍',
        '👩‍👧',
        ' et e',
        '́te ',
        '🇫',
        '🇷 !',
      ];
      final complet = fragments.join();
      final frontieres = _frontieres(complet);
      final source = TexteEnDirect();
      final e = EcritureProgressive(source);
      final vus = <String>[];
      for (final f in fragments) {
        source.ajouter(f);
        _animer(e, surImage: vus.add);
      }
      source.terminer();
      _animer(e, surImage: vus.add);
      expect(e.visible, complet);
      for (final v in vus) {
        expect(complet.startsWith(v), isTrue);
        expect(frontieres, contains(v.length), reason: 'coupé : « $v »');
      }
      e.dispose();
      source.dispose();
    });

    test('Markdown inachevé : jamais de symboles qui apparaissent puis '
        'disparaissent', () {
      const fragments = [
        'La capitale est **Li',
        'ma**. Elle est ',
        'au `bord',
        '` de la mer.\n',
        '##',
        ' Climat\nIl y fait *doux',
        '* toute l’année.',
      ];
      final source = TexteEnDirect(
        nettoyer: MoteurConversationIA.texteSimpleProvisoire,
      );
      final e = EcritureProgressive(source);
      final vus = <String>[];
      for (final f in fragments) {
        source.ajouter(f);
        _animer(e, surImage: vus.add);
      }
      final finale = MoteurConversationIA.texteSimple(fragments.join());
      source.terminer(finale);
      _animer(e, surImage: vus.add);
      expect(
        finale,
        'La capitale est Lima. Elle est au bord de la mer.\nClimat\n'
        'Il y fait doux toute l’année.',
      );
      expect(e.visible, finale);
      for (final v in vus) {
        expect(v, isNot(contains('*')));
        expect(v, isNot(contains('`')));
        expect(v, isNot(contains('#')));
        // Le texte se prolonge seulement : jamais de changement de forme.
        expect(finale.startsWith(v), isTrue, reason: '« $v »');
      }
      e.dispose();
    });

    test('« Tout afficher » : le texte reçu apparaît aussitôt, la '
        'réception continue', () {
      final source = TexteEnDirect();
      final e = EcritureProgressive(source);
      source.ajouter('${'a' * 300} ');
      e.avancer(_image);
      expect(e.rattrapable.value, isTrue);
      e.toutAfficher();
      expect(e.visible, 'a' * 300);
      expect(e.rattrapable.value, isFalse);
      expect(e.termine, isFalse, reason: 'la réception continue');
      // Les fragments suivants s'affichent normalement.
      source.ajouter('suite du texte');
      expect(e.visible, 'a' * 300);
      e.avancer(const Duration(milliseconds: 200));
      expect(e.visible.length, greaterThan(300));
      source.terminer();
      _animer(e);
      expect(e.visible, '${'a' * 300} suite du texte');
      expect(e.termine, isTrue);
      e.dispose();
      source.dispose();
    });

    test('remplacer : la nouvelle proposition repart de zéro, sans '
        'mélange', () {
      final e = EcritureProgressive.complet('Avec plaisir, à ce soir !');
      e.avancer(const Duration(milliseconds: 100));
      expect(e.visible, isNotEmpty);
      final ancienne = TexteEnDirect();
      e.remplacer(ancienne);
      ancienne.ajouter('Je ne pourrai ');
      final suivante = TexteEnDirect();
      e.remplacer(suivante);
      expect(ancienne.hasListeners, isFalse);
      expect(e.visible, '');
      // L'ancienne continue d'arriver : sans effet.
      ancienne.ajouter('pas venir.');
      suivante.ajouter('Bonjour Madame,');
      suivante.terminer();
      final vus = <String>[];
      _animer(e, surImage: vus.add);
      expect(e.visible, 'Bonjour Madame,');
      for (final v in vus) {
        expect('Bonjour Madame,'.startsWith(v), isTrue);
      }
      e.remplacerPar('Salut !');
      expect(e.visible, '');
      _animer(e);
      expect(e.visible, 'Salut !');
      e.dispose();
      ancienne.dispose();
      suivante.dispose();
    });

    test('interruption : texte reçu gardé, jamais présenté comme complet', () {
      final source = TexteEnDirect();
      final e = EcritureProgressive(source);
      source.ajouter('Lima a été fondée en');
      source.interrompre();
      _animer(e);
      expect(e.visible, 'Lima a été fondée en');
      expect(e.reception, EtatReception.interrompue);
      expect(e.termine, isTrue);
      // Plus rien n'est accepté après la fin.
      source.ajouter(' 1535.');
      expect(source.texte, 'Lima a été fondée en');
      e.dispose();
      source.dispose();
    });

    test('animations réduites : texte affiché aussitôt', () {
      final source = TexteEnDirect();
      final e = EcritureProgressive(source)..immediat = true;
      source.ajouter('Tout de suite.');
      expect(e.visible, 'Tout de');
      source.terminer();
      expect(e.visible, 'Tout de suite.');
      expect(e.termine, isTrue);
      e.dispose();
      source.dispose();
    });

    test('libération : arreter() et dispose() lâchent la source', () {
      final source = TexteEnDirect();
      final e = EcritureProgressive(source);
      expect(source.hasListeners, isTrue);
      var notifications = 0;
      e.addListener(() => notifications++);
      e.arreter();
      expect(source.hasListeners, isFalse);
      source.ajouter('ignoré');
      e.avancer(const Duration(seconds: 1));
      expect(notifications, 0);
      expect(e.termine, isTrue);
      e.dispose();
      // Une source possédée est libérée avec l'écriture.
      final possedee = EcritureProgressive.complet('texte');
      possedee.dispose();
      expect(() => possedee.source.ajouter('après'), returnsNormally);
      source.dispose();
    });
  });

  group('Widget TexteProgressif', () {
    Widget app(Widget enfant, {bool reduit = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduit),
        child: Scaffold(body: enfant),
      ),
    );

    testWidgets('curseur pendant l’écriture, simple texte ensuite ; '
        'aucune animation restante', (tester) async {
      const texte = 'Bonjour, je suis JARVIS.';
      final e = EcritureProgressive.complet(texte);
      await tester.pumpWidget(
        app(TexteProgressif(ecriture: e, style: const TextStyle())),
      );
      expect(find.byKey(TexteProgressif.cleCurseur), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(texte), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text(texte), findsOneWidget);
      expect(find.byKey(TexteProgressif.cleCurseur), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      e.dispose();
    });

    testWidgets('fragments reçus en direct, ticker arrêté pendant '
        'l’attente', (tester) async {
      final source = TexteEnDirect();
      final e = EcritureProgressive(source);
      await tester.pumpWidget(
        app(TexteProgressif(ecriture: e, style: const TextStyle())),
      );
      source.ajouter('Première partie. ');
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(_image);
      }
      expect(e.enMouvement, isFalse);
      expect(find.byKey(TexteProgressif.cleCurseur), findsOneWidget);
      source.ajouter('Seconde partie.');
      source.terminer();
      await tester.pumpAndSettle();
      expect(find.text('Première partie. Seconde partie.'), findsOneWidget);
      e.dispose();
      source.dispose();
    });

    testWidgets('animations réduites : texte complet sans attendre', (
      tester,
    ) async {
      const texte = 'Réponse affichée immédiatement, sans animation.';
      final e = EcritureProgressive.complet(texte);
      await tester.pumpWidget(
        app(
          TexteProgressif(ecriture: e, style: const TextStyle()),
          reduit: true,
        ),
      );
      await tester.pump();
      expect(find.text(texte), findsOneWidget);
      e.dispose();
    });

    testWidgets('« Tout afficher » : proposé pour un long texte seulement', (
      tester,
    ) async {
      final long = EcritureProgressive.complet('Une longue réponse. ' * 30);
      await tester.pumpWidget(
        app(
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: TexteProgressif(
                    ecriture: long,
                    style: const TextStyle(),
                  ),
                ),
              ),
              ActionToutAfficher(ecriture: long),
            ],
          ),
        ),
      );
      await tester.pump(_image);
      await tester.pump(_image);
      expect(long.rattrapable.value, isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text(ActionToutAfficher.libelle));
      await tester.pump();
      expect(long.termine, isTrue);
      expect(find.text(('Une longue réponse. ' * 30)), findsOneWidget);
      long.dispose();

      final court = EcritureProgressive.complet('Il est 10 h 12.');
      expect(court.rattrapable.value, isFalse);
      court.avancer(_image);
      expect(court.rattrapable.value, isFalse);
      court.dispose();
    });

    testWidgets('widget retiré en pleine écriture : rien ne fuit, la '
        'progression est gardée', (tester) async {
      final e = EcritureProgressive.complet('Texte qui s’écrit. ' * 10);
      await tester.pumpWidget(
        app(TexteProgressif(ecriture: e, style: const TextStyle())),
      );
      await tester.pump(_image);
      await tester.pump(const Duration(milliseconds: 200));
      final avant = e.visible.length;
      expect(avant, greaterThan(0));
      await tester.pumpWidget(app(const SizedBox()));
      expect(e.hasListeners, isFalse);
      await tester.pump();
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'ticker arrêté',
      );
      // De retour à l'écran : reprend où elle en était.
      await tester.pumpWidget(
        app(TexteProgressif(ecriture: e, style: const TextStyle())),
      );
      expect(e.visible.length, avant);
      await tester.pumpAndSettle();
      expect(e.termine, isTrue);
      e.dispose();
    });
  });

  group('Conversation : réponses de l’IA reçues en direct', () {
    test('une seule bulle, construite au fil des fragments, finalisée une '
        'fois', () async {
      final s = _ServeurPilote();
      final c = _session(s);
      var notifications = 0;
      c.addListener(() => notifications++);
      final envoi = c.envoyer(_question);
      await _attendreFlux(s);
      expect(c.enReflexion, isTrue);
      expect(_deJarvis(c), isEmpty, reason: 'réflexion, pas encore de texte');
      s.meta();
      s.delta('Lima a été ');
      await _laisser();
      // Le texte n'attend pas la fin de la génération.
      expect(c.enReflexion, isFalse);
      final bulle = _deJarvis(c).single;
      expect(bulle.redaction, isTrue);
      expect(bulle.ecriture!.source.brut, 'Lima a été ');
      final notificationsBulle = notifications;
      s.delta('fondée en ');
      s.delta('1535.');
      await _laisser();
      expect(_deJarvis(c).single.id, bulle.id);
      expect(bulle.ecriture!.source.brut, 'Lima a été fondée en 1535.');
      // Les fragments ne reconstruisent pas la conversation.
      expect(notifications, notificationsBulle);
      s.done();
      await s.fermer();
      await envoi;
      final finale = _deJarvis(c).single;
      expect(finale.id, bulle.id, reason: 'même bulle');
      expect(finale.redaction, isFalse);
      expect(finale.texte, 'Lima a été fondée en 1535.');
      expect(finale.idServeur, 'r1');
      expect(finale.enregistre, isTrue);
      expect(finale.incident, isNull);
      expect(identical(finale.ecriture, bulle.ecriture), isTrue);
      expect(finale.ecriture!.reception, EtatReception.terminee);
      // Enregistrement terminé alors que l'affichage commence à peine.
      expect(finale.ecriture!.termine, isFalse);
      _animer(finale.ecriture!);
      expect(finale.ecriture!.visible, finale.texte);
      expect(c.messages.where((m) => !m.deJarvis).single.enregistre, isTrue);
      expect(s.requetes, hasLength(1));
      c.dispose();
    });

    test('coupure réseau en plein flux : texte reçu gardé, signalé '
        'interrompu, rattaché à sa ligne serveur', () async {
      final s = _ServeurPilote();
      final c = _session(s);
      final envoi = c.envoyer(_question);
      await _attendreFlux(s);
      s.meta();
      s.delta('Lima a été fondée ');
      await _laisser();
      // Connexion fermée sans `done`.
      await s.fermer();
      await envoi;
      final m = _deJarvis(c).single;
      expect(m.texte, 'Lima a été fondée');
      expect(m.incident, contains('interrompue'));
      expect(m.ecriture!.reception, EtatReception.interrompue);
      // Le serveur garde le texte déjà généré sous l'identifiant de `meta`.
      expect(m.idServeur, 'r1');
      expect(m.redaction, isFalse);
      c.dispose();
    });

    test(
      'erreur de l’IA en cours de réponse : texte partiel conservé',
      () async {
        final s = _ServeurPilote();
        final c = _session(s);
        final envoi = c.envoyer(_question);
        await _attendreFlux(s);
        s.meta();
        s.delta('Première phrase. ');
        s.erreur('Le moteur IA est momentanément indisponible.');
        await s.fermer();
        await envoi;
        final m = _deJarvis(c).single;
        expect(m.texte, 'Première phrase.');
        expect(m.incident, contains('momentanément indisponible'));
        expect(m.ecriture!.reception, EtatReception.interrompue);
        c.dispose();
      },
    );

    test('erreur avant tout texte (quota) : message clair, aucune bulle '
        'vide', () async {
      final s = _ServeurPilote()
        ..refus = () => http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'detail': {
                  'quota': {'resets_in': 7200},
                },
              }),
            ),
          ),
          429,
        );
      final c = _session(s);
      await c.envoyer(_question);
      final m = _deJarvis(c).single;
      expect(m.texte, contains('limite quotidienne'));
      expect(m.incident, isNull);
      expect(m.idServeur, isNull);
      expect(m.ecriture, isNotNull, reason: 'écrite comme les autres');
      c.dispose();
    });

    test('pas de doublon à l’actualisation, même après une coupure', () async {
      final s = _ServeurPilote();
      final depot = _Depot();
      final c = _session(s, depot: depot);
      final envoi = c.envoyer(_question);
      await _attendreFlux(s);
      s.meta();
      s.delta('Réponse partielle');
      await _laisser();
      await s.fermer();
      await envoi;
      // Le backend a enregistré la question et le texte partiel.
      final t = DateTime(2026, 10, 14, 10);
      depot.lignes.addAll([
        MessageServeur(id: 'q1', role: 'user', contenu: _question, date: t),
        MessageServeur(
          id: 'r1',
          role: 'assistant',
          contenu: 'Réponse partielle',
          date: t,
        ),
      ]);
      await c.rafraichir();
      expect(c.messages, hasLength(2));
      expect(_deJarvis(c).single.idServeur, 'r1');
      c.dispose();
    });

    test('changement de conversation en plein flux : le texte de A ne va '
        'jamais dans B', () async {
      final s = _ServeurPilote();
      final c = _session(s);
      final envoi = c.envoyer(_question);
      await _attendreFlux(s);
      final idA = c.idCourant!;
      s.meta();
      s.delta('Texte de A, ');
      await _laisser();
      final bulle = _deJarvis(c).single;
      // Nouvelle conversation B pendant la réception.
      c.effacer();
      expect(c.messages, isEmpty);
      s.delta('suite de A.');
      s.done();
      await s.fermer();
      await envoi;
      expect(c.messages, isEmpty, reason: 'B reste vide');
      final a = c.archives.singleWhere((x) => x.id == idA);
      final reponses = [
        for (final m in a.messages)
          if (m.deJarvis) m,
      ];
      expect(reponses, hasLength(1), reason: 'bulle finalisée, pas ajoutée');
      expect(reponses.single.id, bulle.id);
      expect(reponses.single.texte, 'Texte de A, suite de A.');
      // Rouverte : la réponse complète, une seule fois.
      expect(c.ouvrir(idA), isTrue);
      expect(_deJarvis(c).single.texte, 'Texte de A, suite de A.');
      c.dispose();
    });

    test('suppression de la conversation en plein flux : réponse perdue, '
        'écriture arrêtée', () async {
      final s = _ServeurPilote();
      final c = _session(s);
      final envoi = c.envoyer(_question);
      await _attendreFlux(s);
      s.meta();
      s.delta('Début ');
      await _laisser();
      final ecriture = _deJarvis(c).single.ecriture!;
      expect(c.supprimer(c.idCourant!), isTrue);
      expect(ecriture.source.hasListeners, isFalse);
      s.delta('fin.');
      s.done();
      await s.fermer();
      await envoi;
      expect(c.messages, isEmpty);
      expect(c.archives, isEmpty);
      c.dispose();
    });

    test('fermeture (déconnexion, page quittée) en plein flux : aucune '
        'erreur', () async {
      final s = _ServeurPilote();
      final c = _session(s);
      final envoi = c.envoyer(_question);
      await _attendreFlux(s);
      s.meta();
      s.delta('Début ');
      await _laisser();
      c.dispose();
      s.delta('suite');
      s.done();
      await s.fermer();
      await envoi;
    });

    test('mode vocal : la réponse est rendue une seule fois, entière, à la '
        'fin de la réception', () async {
      final s = _ServeurPilote();
      final c = _session(s);
      final vocale = c.repondreVocal(_question);
      await _attendreFlux(s);
      s.meta();
      s.delta('Lima est ');
      await _laisser();
      expect(_deJarvis(c).single.redaction, isTrue);
      var rendue = false;
      unawaited(vocale.then((_) => rendue = true));
      await _laisser();
      expect(rendue, isFalse, reason: 'jamais un fragment seul');
      s.delta('au Pérou.');
      s.done();
      await s.fermer();
      final r = await vocale;
      expect(r!.texte, 'Lima est au Pérou.');
      expect(_deJarvis(c).single.vocal, isTrue);
      c.dispose();
    });

    test('mode vocal interrompu : le texte reçu puis l’explication', () async {
      final s = _ServeurPilote();
      final c = _session(s);
      final vocale = c.repondreVocal(_question);
      await _attendreFlux(s);
      s.meta();
      s.delta('Lima est ');
      await _laisser();
      await s.fermer();
      final r = await vocale;
      expect(r!.texte, startsWith('Lima est Réponse interrompue'));
      c.dispose();
    });
  });

  group('Conversation : réponses locales', () {
    test('calcul local : aucun appel au serveur, réponse complète tout de '
        'suite, écrite progressivement, enregistrée une fois', () async {
      final s = _ServeurPilote();
      final c = _session(s);
      final echanges = <EchangeLocal>[];
      bool? termineAuMomentDeLEnregistrement;
      c.surEchangeLocal = (e) {
        echanges.add(e);
        termineAuMomentDeLEnregistrement = _deJarvis(c).last.ecriture?.termine;
      };
      await c.envoyer('Combien font 6 fois 7 ?');
      expect(s.requetes, isEmpty, reason: 'aucun appel à GroqCloud');
      final m = _deJarvis(c).single;
      expect(m.texte, contains('42'));
      expect(m.redaction, isFalse);
      expect(m.idServeur, isNotNull, reason: 'identifiant prévu, synchro');
      expect(echanges, hasLength(1));
      expect(echanges.single.reponse, m.texte);
      // L'enregistrement n'attend pas la fin de l'animation.
      expect(termineAuMomentDeLEnregistrement, isFalse);
      final e = m.ecriture!;
      expect(e.visible, '');
      _animer(e);
      expect(e.visible, m.texte);
      expect(e.termine, isTrue);
      c.dispose();
    });
  });

  group('Fil de conversation (écran)', () {
    testWidgets('la réponse s’écrit dans une seule carte, puis le curseur '
        'disparaît', (tester) async {
      final c = ConversationSession(delaiReflexion: Duration.zero);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (context, _) => ListView(
                children: [
                  for (final m in c.messages)
                    if (m.deJarvis)
                      CarteJarvis(
                        message: m,
                        surTon: (_) {},
                        surAction: (_) {},
                      ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => c.envoyer('Combien font 6 fois 7 ?'));
      await tester.pump();
      expect(find.byType(CarteJarvis), findsOneWidget);
      expect(find.byKey(TexteProgressif.cleCurseur), findsOneWidget);
      final texte = _deJarvis(c).single.texte;
      expect(find.text(texte), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(CarteJarvis), findsOneWidget);
      expect(find.text(texte), findsOneWidget);
      expect(find.byKey(TexteProgressif.cleCurseur), findsNothing);
      c.dispose();
    });

    Future<ConversationSession> filRempli(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ConversationSession(
        delaiReflexion: Duration.zero,
        moteur: _MoteurTexte(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ConversationPage(
                session: c,
                gabarit: GabaritJarvis.of(context),
                surPoserQuestion: () {},
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        c.envoyer('question $i');
        await tester.pump();
        await tester.pumpAndSettle();
      }
      return c;
    }

    testWidgets('près du bas : le fil suit le texte qui s’écrit', (
      tester,
    ) async {
      final c = await filRempli(tester);
      c.envoyer('longue');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // La carte qui s'écrit (liste inversée : pas forcément la dernière
      // de l'arbre).
      final carte = find.ancestor(
        of: find.byKey(TexteProgressif.cleCurseur),
        matching: find.byType(CarteJarvis),
      );
      expect(carte, findsOneWidget);
      final avant = tester.getRect(carte);
      for (var i = 0; i < 90; i++) {
        await tester.pump(_image);
      }
      final apres = tester.getRect(carte);
      expect(apres.height, greaterThan(avant.height), reason: 'elle grandit');
      // Ancrée en bas : la fin du texte reste visible au même endroit.
      expect((apres.bottom - avant.bottom).abs(), lessThan(1));
      await tester.pumpAndSettle();
      c.dispose();
    });

    testWidgets('l’utilisateur relit l’historique : rien ne bouge sous ses '
        'yeux pendant l’écriture', (tester) async {
      final c = await filRempli(tester);
      c.envoyer('longue');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // Remonte dans l'historique (liste inversée : glisser vers le bas).
      await tester.drag(
        find.byKey(ConversationPage.cleFil),
        const Offset(0, 300),
      );
      // L'élan du geste se termine.
      for (var i = 0; i < 40; i++) {
        await tester.pump(_image);
      }
      // La réponse est hors de la vue : son écriture attend.
      final ecriture = c.messages.last.ecriture!;
      expect(ecriture.suspendue, isTrue);
      expect(ecriture.termine, isFalse);
      // Repère : une ancienne réponse visible à l'écran.
      final anciennes = find.textContaining('Réponse à « question');
      Finder? repereVisible;
      for (var i = 0; i < anciennes.evaluate().length; i++) {
        final r = tester.getRect(anciennes.at(i));
        if (r.top > 40 && r.bottom < 600) {
          // Retrouvé par son texte (les indices changent avec le fil).
          repereVisible = find.text(tester.widget<Text>(anciennes.at(i)).data!);
        }
      }
      expect(repereVisible, isNotNull);
      final repere = repereVisible!;
      final avant = tester.getRect(repere).top;
      for (var i = 0; i < 60; i++) {
        await tester.pump(_image);
      }
      expect((tester.getRect(repere).top - avant).abs(), lessThan(1));
      expect(ecriture.termine, isFalse);
      // Retour en bas : l'écriture reprend où elle en était et se termine.
      await tester.drag(
        find.byKey(ConversationPage.cleFil),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
      expect(ecriture.suspendue, isFalse);
      expect(ecriture.termine, isTrue);
      expect(find.text(_MoteurTexte.reponse('longue')), findsOneWidget);
      c.dispose();
    });
  });
}

/// Moteur local de test : réponse courte, ou longue pour « longue ».
class _MoteurTexte implements MoteurConversation {
  static String reponse(String question) => question == 'longue'
      ? 'Voici une réponse détaillée qui prend plusieurs lignes. ' * 12
      : 'Réponse à « $question », sur deux lignes au moins pour occuper '
            'un peu de place dans le fil.';

  @override
  Future<ReponseJarvis> repondre(DemandeJarvis demande) async =>
      ReponseJarvis(reponse(demande.texte));

  @override
  void reinitialiser() {}

  @override
  Object? capturerContexte() => null;

  @override
  void restaurerContexte(Object? contexte) {}

  @override
  Future<String> proposerReponse(
    ConversationExterne conversation,
    TonReponse ton,
  ) async => '';
}
