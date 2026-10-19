import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation.dart';

/// Moteur espion : la première réponse « se génère » jusqu'à son annulation.
class _Moteur implements MoteurConversation {
  final demandes = <DemandeJarvis>[];

  @override
  Future<ReponseJarvis> repondre(DemandeJarvis demande) async {
    demandes.add(demande);
    if (demandes.length == 1) {
      demande.surFragment?.call('Un moteur électrique transforme l’énergie. ');
      await demande.annulation; // l'utilisateur interrompt
      return const ReponseJarvis(
        'Un moteur électrique transforme l’énergie.',
        erreur: true,
        incident: 'Interrompue par vous.',
      );
    }
    return const ReponseJarvis('Le rotor est la partie qui tourne.');
  }

  @override
  void reinitialiser() {}
  @override
  Object? capturerContexte() => null;
  @override
  void restaurerContexte(Object? contexte) {}
  @override
  Future<String> proposerReponse(ConversationExterne c, TonReponse t) async => '';
}

void main() {
  test('interruption : génération arrêtée, « entendu » transmis UNE fois, '
      'même conversation', () async {
    final moteur = _Moteur();
    final session = ConversationSession(moteur: moteur, delaiReflexion: Duration.zero);
    addTearDown(session.dispose);
    final fragments = <String>[];

    final premiere = session.repondreVocal(
      'Explique le moteur électrique',
      surFragment: fragments.add,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fragments, isNotEmpty);
    final conversation = session.idCourant;

    session.interrompreReponseVocale('Un moteur électrique transforme l’énergie.');
    final r1 = await premiere;
    expect(r1!.interrompue, isTrue);

    final r2 = await session.repondreVocal('Attends, c’est quoi le rotor ?');
    expect(r2!.texte, 'Le rotor est la partie qui tourne.');
    expect(moteur.demandes, hasLength(2)); // aucun appel en double
    expect(moteur.demandes.first.annulation, isNotNull);
    expect(moteur.demandes[1].entendu, 'Un moteur électrique transforme l’énergie.');
    expect(session.idCourant, conversation); // une seule conversation

    await session.repondreVocal('Merci');
    expect(moteur.demandes.last.entendu, isNull); // transmis une seule fois
    // Historique : question, réponse interrompue, nouvelle question, réponse…
    final jarvis = session.messages.where((m) => m.deJarvis).toList();
    expect(jarvis.first.incident, 'Interrompue par vous.');
  });
}
