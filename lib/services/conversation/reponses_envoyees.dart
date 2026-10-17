import '../../models/importation/propositions_reponse.dart';
import '../api_jarvis.dart';

/// Phase 4 : réponses que l'utilisateur DÉCLARE avoir envoyées (appui long
/// sur une proposition). Enregistrées par le serveur avec la réponse de
/// JARVIS qui porte les propositions (`messages.attachments`), jamais comme
/// des messages WhatsApp originaux ; rien n'est envoyé à WhatsApp.
abstract class ServiceReponsesEnvoyees {
  /// Déclare ([envoyee] vrai) ou annule. Succès : date confirmée par le
  /// serveur (null après une annulation).
  Future<ResultatApi<DateTime?>> statut({
    required String conversation,
    required String message,
    required String proposition,
    required bool envoyee,
  });

  /// « Reprendre » une génération de propositions incomplète : le serveur
  /// ne complète que les combinaisons manquantes, dans le même ensemble.
  Future<ResultatApi<PropositionsReponse?>> completer({
    required String conversation,
    required String message,
  });
}

class ReponsesEnvoyeesApi implements ServiceReponsesEnvoyees {
  const ReponsesEnvoyeesApi(this.api);

  final ApiJarvis api;

  @override
  Future<ResultatApi<DateTime?>> statut({
    required String conversation,
    required String message,
    required String proposition,
    required bool envoyee,
  }) => api.statutEnvoyee(
    conversation: conversation,
    message: message,
    proposition: proposition,
    envoyee: envoyee,
  );

  @override
  Future<ResultatApi<PropositionsReponse?>> completer({
    required String conversation,
    required String message,
  }) => api.completerPropositions(conversation: conversation, message: message);
}
