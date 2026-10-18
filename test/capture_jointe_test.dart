import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/capture_jointe.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';

/// Moteur espion : garde chaque demande, répond comme l'IA (fragments).
class _Moteur implements MoteurConversation {
  final demandes = <DemandeJarvis>[];

  @override
  Future<ReponseJarvis> repondre(DemandeJarvis demande) async {
    demandes.add(demande);
    demande.surFragment?.call('Une page Wikipédia.');
    return const ReponseJarvis('Une page Wikipédia.');
  }

  @override
  void reinitialiser() {}

  @override
  Object? capturerContexte() => null;

  @override
  void restaurerContexte(Object? contexte) {}

  @override
  Future<String> proposerReponse(ConversationExterne c, TonReponse t) async =>
      '';
}

void main() {
  // Image FICTIVE : quelques octets, jamais une capture réelle.
  final image = ImageAEnvoyer('image/png', Uint8List.fromList([1, 2, 3]));
  const capture = CaptureJointe(chemin: '/cache/captures_touch/capture_x.png');

  test('la capture part avec CE message seulement, jusqu’au moteur IA', () async {
    final moteur = _Moteur();
    final session = ConversationSession(
      moteur: moteur,
      delaiReflexion: Duration.zero,
    );
    addTearDown(session.dispose);

    await session.envoyerAvecCapture('Que vois-tu ?', capture, image);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(moteur.demandes, hasLength(1));
    expect(identical(moteur.demandes.single.image, image), isTrue);
    // La demande recopiée pour l'écriture progressive garde l'image.
    expect(
      identical(moteur.demandes.single.avecFragments((_) {}).image, image),
      isTrue,
    );
    final question = session.messages.first;
    expect(question.texte, 'Que vois-tu ?');
    expect(question.capture?.chemin, capture.chemin);

    // Question suivante : plus d'image envoyée par l'appareil.
    await session.envoyer('Et la deuxième ligne ?');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(moteur.demandes.last.image, isNull);
  });

  test('texte vide : rien n’est envoyé', () async {
    final moteur = _Moteur();
    final session = ConversationSession(moteur: moteur);
    addTearDown(session.dispose);
    await session.envoyerAvecCapture('   ', capture, image);
    expect(moteur.demandes, isEmpty);
    expect(session.messages, isEmpty);
  });
}
