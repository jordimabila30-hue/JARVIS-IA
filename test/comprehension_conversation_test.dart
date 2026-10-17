// Moteur de compréhension conversationnelle (phase 1), côté Flutter :
// la consigne d'une pièce jointe enregistrée part au serveur sans être
// réinsérée, l'accord de l'utilisateur est demandé dans le fil avant tout
// envoi à l'IA, les suivis d'un chat WhatsApp vont au serveur, un nouvel
// essai ne duplique rien. Serveur simulé (MockClient), aucun réseau.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/piece_jointe_whatsapp.dart';
import 'package:ia_jarvis/models/importation/reference_whatsapp.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/conversation/consentement_analyse.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_hybride.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_ia.dart';
import 'package:ia_jarvis/services/conversations/correspondance_conversations.dart';
import 'package:ia_jarvis/services/conversations/depot_conversations.dart';
import 'package:ia_jarvis/services/importation/pieces_jointes_serveur.dart';
import 'package:ia_jarvis/services/importation/selection_whatsapp.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/widgets/conversation/carte_jarvis.dart';

import 'outils/conversations_whatsapp.dart';

const _conv = '33333333-3333-4333-8333-333333333333';

String _evenement(String type, Map<String, Object?> donnees) =>
    'event: $type\ndata: ${jsonEncode(donnees)}\n\n';

http.Response _sse(List<String> fragments, {String message = 'r1'}) =>
    http.Response.bytes(
      utf8.encode(
        [
          _evenement('meta', {
            'conversation_id': _conv,
            'message_id': message,
            'quota': {},
          }),
          for (final f in fragments) _evenement('delta', {'text': f}),
          _evenement('done', {'message_id': message}),
        ].join(),
      ),
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );

http.Response _json(int statut, Object corps) => http.Response.bytes(
  utf8.encode(jsonEncode(corps)),
  statut,
  headers: {'content-type': 'application/json'},
);

/// Serveur JARVIS simulé : le chat a des conversations WhatsApp jointes,
/// donc sans `whatsapp_analysis` il refuse (409) comme le vrai serveur.
class _Serveur {
  final corps = <Map<String, dynamic>>[];
  bool groqEnPanne = false;

  late final client = MockClient((r) async {
    final c = jsonDecode(r.body) as Map<String, dynamic>;
    corps.add(c);
    if (c['whatsapp_analysis'] == null) {
      return _json(409, {
        'detail': {'code': 'consentement_requis', 'message': '…'},
      });
    }
    if (groqEnPanne) {
      return http.Response.bytes(
        utf8.encode(
          _evenement('meta', {'conversation_id': _conv, 'message_id': 'x'}) +
              _evenement('error', {
                'code': 'llm_unavailable',
                'message': 'Le moteur IA est momentanément indisponible.',
              }),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    return _sse([
      'Vous parlez surtout du projet,',
      ' avec un ton détendu.',
    ], message: 'r${corps.length}');
  });

  ApiJarvis api() => ApiJarvis(
    adresse: Uri.parse('http://localhost:8000'),
    jeton: () async => 'jeton',
    client: client,
  );
}

class _Service implements ServicePiecesJointes {
  int enregistrements = 0;

  @override
  Future<ResultatApi<PieceJointeEnregistree>> enregistrer({
    required PieceJointeWhatsApp piece,
    required String consigne,
    String? conversation,
  }) async {
    enregistrements++;
    return SuccesApi(
      PieceJointeEnregistree(
        conversation: _conv,
        consigne: piece.idConsigne,
        contexte: piece.id,
        nombre: piece.nombre,
        dejaEnregistree: false,
        conversationCreee: conversation == null,
      ),
    );
  }

  @override
  Future<ResultatApi<List<MessageWhatsApp>>> messages(String id) async =>
      const SuccesApi([]);

  @override
  Future<ResultatApi<void>> supprimer(String id) async => const SuccesApi(null);

  /// Références que le serveur renverrait pour un chat restauré.
  Map<String, ReferencesReponse> refs = {};
  final demandesReferences = <String>[];

  @override
  Future<ResultatApi<PageWhatsApp>> page(
    String id, {
    required int apres,
    required int limite,
  }) async => SuccesApi(
    PageWhatsApp(premier: apres + 1, messages: const [], suite: false),
  );

  @override
  Future<ResultatApi<Map<String, ReferencesReponse>>> references(
    String conversation,
  ) async {
    demandesReferences.add(conversation);
    return SuccesApi(refs);
  }
}

class _Depot implements DepotConversations {
  _Depot(this.lignes, this.contextes);
  final List<MessageServeur> lignes;
  final List<ContexteServeur> contextes;

  @override
  String? get utilisateur => 'compte-1';

  @override
  Future<List<ConversationServeur>> lister({int limite = 100}) async => [];

  @override
  Future<PageMessages> messages(
    String id, {
    DateTime? avant,
    int limite = 50,
  }) async => PageMessages(List.of(lignes), contextes: contextes);

  @override
  Future<void> supprimer(String id) async {}
}

PieceJointeWhatsApp _piece() {
  final c = ConversationWhatsApp(
    titre: 'Pepper Potts',
    messages: [
      for (var i = 0; i < 6; i++)
        msg(
          i,
          DateTime(2026, 10, 12, 9, i),
          auteur: i.isEven ? 'Pepper Potts' : 'Tony Stark',
          texte: 'message $i',
        ),
    ],
    participants: const [
      ParticipantWhatsApp(nom: 'Pepper Potts', messages: 3),
      ParticipantWhatsApp(nom: 'Tony Stark', messages: 3),
    ],
    ordreDate: OrdreDate.jourMoisAnnee,
    dateIncertaine: false,
    lignesNonRattachees: const [],
    nombreLignesNonRattachees: 0,
    nomFichier: 'chat.txt',
  );
  return PieceJointeWhatsApp.depuis(
    conversation: c,
    choisis: (SelectionWhatsApp(c)..cocherVisibles(true)).resultat(),
    moi: 'Tony Stark',
  );
}

Future<void> _attendre() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late _Serveur serveur;
  late _Service service;
  late ConsentementAnalyse accord;
  late StockageMemoire stockage;

  // Comme dans l'accueil : une seule correspondance local ↔ serveur,
  // partagée par la session et le moteur IA.
  ConversationSession session({DepotConversations? depot}) {
    final correspondance = CorrespondanceConversations();
    return ConversationSession(
      delaiReflexion: Duration.zero,
      moteur: MoteurConversationHybride(
        ia: MoteurConversationIA(
          serveur.api(),
          correspondance: correspondance,
          analyseWhatsApp: () => accord.etat.valeurApi,
        ),
      ),
      piecesJointes: service,
      consentement: accord,
      depot: depot,
      correspondance: correspondance,
    );
  }

  setUp(() {
    serveur = _Serveur();
    service = _Service();
    stockage = StockageMemoire();
    accord = ConsentementAnalyse(stockage: stockage);
  });

  group('après une pièce jointe', () {
    test('aucun envoi à l’IA sans accord : JARVIS le demande dans le fil, '
        'rien n’est dupliqué', () async {
      final s = session();
      addTearDown(s.dispose);
      final p = _piece();
      await s.envoyerAvecPieceJointe('Résume cette discussion.', p);
      await _attendre();
      // Une seule requête, refusée par le serveur avant l'IA.
      expect(serveur.corps, hasLength(1));
      expect(serveur.corps.single['reply_to'], p.idConsigne);
      expect(serveur.corps.single.containsKey('whatsapp_analysis'), isFalse);
      expect(s.messages, hasLength(2));
      final demande = s.messages.last;
      expect(demande.texte, MoteurConversationIA.demandeAccord);
      expect(demande.choix, [
        ChoixJarvis.autoriserAnalyse,
        ChoixJarvis.refuserAnalyse,
      ]);
      expect(demande.enregistre, isFalse);
    });

    test('accord donné : la MÊME consigne est analysée (reply_to), '
        'réponse enregistrée, accord mémorisé', () async {
      final s = session();
      addTearDown(s.dispose);
      final p = _piece();
      await s.envoyerAvecPieceJointe('Résume cette discussion.', p);
      await _attendre();
      await s.choisir(s.messages.last.id, ChoixJarvis.autoriserAnalyse);
      await _attendre();
      expect(accord.etat, EtatConsentement.accorde);
      expect(stockage.valeur, 'accorde');
      final second = serveur.corps.last;
      expect(second['reply_to'], p.idConsigne);
      expect(second['whatsapp_analysis'], 'allowed');
      expect(second['message'], 'Résume cette discussion.');
      expect(service.enregistrements, 1);
      // Consigne une fois, la demande d'accord (boutons retirés), la réponse.
      expect(s.messages.where((m) => !m.deJarvis), hasLength(1));
      expect(s.messages[1].choix, isEmpty);
      expect(
        s.messages.last.texte,
        'Vous parlez surtout du projet, avec un ton détendu.',
      );
      expect(s.messages.last.enregistre, isTrue);
    });

    test('accord refusé : rien n’est envoyé, réponse locale honnête', () async {
      final s = session();
      addTearDown(s.dispose);
      await s.envoyerAvecPieceJointe('Résume.', _piece());
      await _attendre();
      await s.choisir(s.messages.last.id, ChoixJarvis.refuserAnalyse);
      await _attendre();
      expect(accord.etat, EtatConsentement.refuse);
      expect(serveur.corps, hasLength(1));
      expect(s.messages.last.texte, ConversationSession.refusAnalyse);
      expect(s.messages.last.enregistre, isFalse);
    });

    test('accord déjà donné : analyse directe, puis suivis dans le même '
        'chat (contexte WhatsApp, jamais « colle la conversation »)', () async {
      await accord.accorder();
      final s = session();
      addTearDown(s.dispose);
      await s.envoyerAvecPieceJointe('Analyse cette discussion.', _piece());
      await _attendre();
      expect(serveur.corps.single['whatsapp_analysis'], 'allowed');
      await s.envoyer('Résume cette conversation.');
      await _attendre();
      await s.envoyer('Et vers la fin, c’est toujours pareil ?');
      await _attendre();
      // Aucune réponse locale « Colle-moi la conversation » : tout part
      // au serveur, dans la même conversation, sans reply_to.
      expect(serveur.corps, hasLength(3));
      for (final c in serveur.corps.skip(1)) {
        expect(c['conversation_id'], _conv);
        expect(c.containsKey('reply_to'), isFalse);
        expect(c['whatsapp_analysis'], 'allowed');
      }
      expect(
        serveur.corps[2]['message'],
        'Et vers la fin, c’est toujours pareil ?',
      );
      expect(
        s.messages.where((m) => m.deJarvis).every((m) => m.enregistre),
        isTrue,
      );
      // Les commandes locales restent locales.
      await s.envoyer('Quelle heure est-il ?');
      await _attendre();
      expect(serveur.corps, hasLength(3));
    });

    test('erreur GroqCloud : message honnête, « Réessayer » sans nouvelle '
        'pièce jointe ni consigne dupliquée', () async {
      await accord.accorder();
      serveur.groqEnPanne = true;
      final s = session();
      addTearDown(s.dispose);
      final p = _piece();
      await s.envoyerAvecPieceJointe('Analyse.', p);
      await _attendre();
      final erreur = s.messages.last;
      expect(erreur.texte, contains('indisponible'));
      expect(erreur.choix, [ChoixJarvis.reessayer]);
      expect(erreur.enregistre, isFalse);
      serveur.groqEnPanne = false;
      await s.choisir(erreur.id, ChoixJarvis.reessayer);
      await _attendre();
      expect(serveur.corps.map((c) => c['reply_to']), [
        p.idConsigne,
        p.idConsigne,
      ]);
      expect(service.enregistrements, 1);
      expect(s.messages.where((m) => !m.deJarvis), hasLength(1));
      expect(s.messages.last.texte, contains('ton détendu'));
      // Un choix fait ne peut pas être refait.
      await s.choisir(erreur.id, ChoixJarvis.reessayer);
      await _attendre();
      expect(serveur.corps, hasLength(2));
    });
  });

  group('chat restauré depuis le serveur', () {
    test(
      'réponses enregistrées visibles, suivi avec le contexte WhatsApp',
      () async {
        await accord.accorder();
        final s = session(
          depot: _Depot(
            [
              MessageServeur(
                id: 'c1',
                role: 'user',
                contenu: 'Résume.',
                date: DateTime(2026, 10, 15, 10),
              ),
              MessageServeur(
                id: 'r0',
                role: 'assistant',
                contenu: 'Vous parlez du **projet** Mark 42.',
                date: DateTime(2026, 10, 15, 10, 1),
              ),
            ],
            [
              ContexteServeur(
                id: 'ctx',
                consigne: 'c1',
                contact: 'Pepper Potts',
                nombre: 6,
                creeLe: DateTime(2026, 10, 15, 10),
              ),
            ],
          ),
        );
        addTearDown(s.dispose);
        await s.ouvrirServeur(_conv);
        expect(s.messages.last.texte, 'Vous parlez du projet Mark 42.');
        expect(s.messages.first.pieceJointe, isNotNull);
        await s.envoyer('On en était où dans notre analyse ?');
        await _attendre();
        expect(serveur.corps.single['conversation_id'], _conv);
        expect(serveur.corps.single['whatsapp_analysis'], 'allowed');
      },
    );
  });

  test('chat JARVIS ordinaire : aucun accord demandé ni envoyé', () async {
    final ordinaire = MockClient((r) async {
      final c = jsonDecode(r.body) as Map<String, dynamic>;
      expect(c.containsKey('reply_to'), isFalse);
      return _sse(['Lima.']);
    });
    final s = ConversationSession(
      delaiReflexion: Duration.zero,
      moteur: MoteurConversationHybride(
        ia: MoteurConversationIA(
          ApiJarvis(
            adresse: Uri.parse('http://localhost:8000'),
            jeton: () async => 'jeton',
            client: ordinaire,
          ),
          analyseWhatsApp: () => null,
        ),
      ),
    );
    addTearDown(s.dispose);
    await s.envoyer('Quelle est la capitale du Pérou ?');
    await _attendre();
    expect(s.messages.last.texte, 'Lima.');
    expect(s.messages.last.choix, isEmpty);
  });

  test('accord : relu après redémarrage, par compte', () async {
    final memoire = StockageMemoire();
    await ConsentementAnalyse(stockage: memoire).accorder();
    final relu = ConsentementAnalyse(stockage: memoire);
    expect(relu.etat, EtatConsentement.inconnu);
    await relu.charger();
    expect(relu.etat, EtatConsentement.accorde);
    expect(relu.etat.valeurApi, 'allowed');
    await relu.refuser();
    expect(memoire.valeur, 'refuse');
  });

  for (final largeur in [320.0, 390.0, 1366.0]) {
    testWidgets('carte de demande d’accord : boutons, aucun débordement '
        '($largeur px)', (tester) async {
      tester.view.physicalSize = Size(largeur, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final choisis = <ChoixJarvis>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CarteJarvis(
                message: MessageConversation(
                  id: 1,
                  auteur: AuteurMessage.jarvis,
                  heure: DateTime(2026, 10, 15, 10),
                  texte: MoteurConversationIA.demandeAccord,
                  choix: const [
                    ChoixJarvis.autoriserAnalyse,
                    ChoixJarvis.refuserAnalyse,
                  ],
                ),
                surTon: (_) {},
                surAction: (_) {},
                surChoix: choisis.add,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Autoriser l’analyse'), findsOneWidget);
      expect(find.text('Pas maintenant'), findsOneWidget);
      await tester.tap(find.text('Autoriser l’analyse'));
      expect(choisis, [ChoixJarvis.autoriserAnalyse]);
      expect(tester.takeException(), isNull);
    });
  }
}
