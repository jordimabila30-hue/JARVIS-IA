import '../../models/message_conversation.dart';
import 'moteur_conversation.dart';
import 'moteur_conversation_ia.dart';

/// Moteur de JARVIS une fois le serveur branché : d'abord les règles
/// locales, sinon l'IA du serveur.
///
/// ConversationSession → [MoteurConversationHybride]
///   → [MoteurConversationLocal] : conversation collée (analysée sur
///     l'appareil, jamais envoyée), heure, date, calcul, prénom, notions,
///     « au revoir »… instantané, sans réseau ni quota ;
///   → sinon [MoteurConversationIA] → ApiJarvis → FastAPI → GroqCloud.
///
/// Le même moteur sert l'écrit et le vocal (une seule conversation, un
/// seul contexte) ; une erreur du serveur devient un message clair, et
/// les commandes locales restent disponibles hors connexion.
class MoteurConversationHybride implements MoteurConversation {
  MoteurConversationHybride({
    required MoteurConversationIA ia,
    MoteurConversationLocal? local,
  }) : _ia = ia,
       _local = local ?? MoteurConversationLocal();

  final MoteurConversationIA _ia;
  final MoteurConversationLocal _local;

  // Change quand le fil change (nouvelle conversation, reprise) : une
  // réponse de l'IA arrivée après ne touche pas le contexte du nouveau fil.
  int _fil = 0;

  @override
  Future<ReponseJarvis> repondre(DemandeJarvis demande) async {
    final fil = _fil;
    final locale = await _local.repondreLocalement(demande, avecIA: true);
    if (locale != null) return locale;
    final r = await _ia.repondre(demande);
    if (!r.erreur && fil == _fil) _local.retenirReponseDistante(r.texte);
    return r;
  }

  // Le contexte local (prénom, notion en cours…) suit chaque conversation
  // du fil ; celui de l'IA est gardé par le serveur.

  @override
  void reinitialiser() {
    _fil++;
    _local.reinitialiser();
  }

  @override
  Object? capturerContexte() => _local.capturerContexte();

  @override
  void restaurerContexte(Object? contexte) {
    _fil++;
    _local.restaurerContexte(contexte);
  }

  /// Réponse proposée à une conversation collée : locale (la conversation
  /// ne quitte pas l'appareil).
  @override
  Future<String> proposerReponse(
    ConversationExterne conversation,
    TonReponse ton,
  ) => _local.proposerReponse(conversation, ton);
}
