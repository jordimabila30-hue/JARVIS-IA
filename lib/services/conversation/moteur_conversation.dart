import '../../models/message_conversation.dart';
import '../voice_command_service.dart';
import 'analyse_conversation.dart';
import 'detecteur_intention.dart';
import 'reponses_tons.dart';

/// Ce que JARVIS reçoit pour répondre.
///
/// Le texte réel ([texteComplet]) et l'[historique] sont toujours
/// transmis : un moteur d'IA s'en servira directement. [intention] et
/// [conversation] ne sont qu'un pré-classement des détecteurs locaux
/// (temporaires), qu'un tel moteur est libre d'ignorer.
class DemandeJarvis {
  const DemandeJarvis({
    required this.texte,
    required this.intention,
    String? texteComplet,
    this.historique = const [],
    this.conversation,
    this.conversationNouvelle = false,
    this.vocale = false,
  }) : texteComplet = texteComplet ?? texte;

  /// Ce que l'utilisateur dit à JARVIS (sans la conversation collée).
  final String texte;

  /// Message tel qu'envoyé, conversation collée comprise.
  final String texteComplet;

  /// Messages du fil avant celui-ci, du plus ancien au plus récent.
  final List<MessageConversation> historique;

  /// Pré-classement local (discussion, réponse, résumé…).
  final IntentionMessage intention;

  /// Conversation concernée : collée dans ce message, ou la dernière de la
  /// discussion.
  final ConversationExterne? conversation;

  /// Vrai si la conversation vient d'être collée dans ce message.
  final bool conversationNouvelle;

  /// Phrase dite en mode vocal (réponse à prononcer).
  final bool vocale;
}

/// Réponse de JARVIS dans le fil.
class ReponseJarvis {
  const ReponseJarvis(
    this.texte, {
    this.choixTon = false,
    this.actions = const [],
    this.terminerSession = false,
  });

  final String texte;

  /// Afficher « Quel ton ? » puis une réponse proposée.
  final bool choixTon;

  /// Raccourcis discrets, seulement quand ils sont utiles.
  final List<ActionRapide> actions;

  /// « Au revoir JARVIS » : le chat vocal se termine.
  final bool terminerSession;
}

/// Cerveau de la conversation, écrite comme vocale (une seule conversation,
/// un seul contexte). Aujourd'hui [MoteurConversationLocal] (règles
/// locales) ; demain un service d'IA (API) qui implémentera la même
/// interface, sans toucher à l'écran.
abstract class MoteurConversation {
  Future<ReponseJarvis> repondre(DemandeJarvis demande);

  /// Nouvelle conversation : le contexte (prénom, sujet…) est oublié.
  void reinitialiser();

  /// Copie du contexte actuel, pour reprendre la conversation plus tard.
  Object? capturerContexte();

  /// Reprend un contexte capturé par [capturerContexte] (null : oubli).
  void restaurerContexte(Object? contexte);

  /// Réponse à envoyer à la [conversation], dans le [ton] choisi.
  Future<String> proposerReponse(
    ConversationExterne conversation,
    TonReponse ton,
  );
}

/// Prototype local : discussion normale par les règles du mode vocal
/// ([VoiceCommandService] : salutations, heure, calculs, notions), analyse
/// de conversations par heuristiques ([AnalyseConversation]).
///
/// Un seul [VoiceCommandService] pour l'écrit et le vocal : une information
/// donnée à l'oral (« je m'appelle Jordi ») est connue à l'écrit, et
/// inversement.
class MoteurConversationLocal implements MoteurConversation {
  MoteurConversationLocal({VoiceCommandService? commandes})
    : _commandes = commandes ?? VoiceCommandService();

  final VoiceCommandService _commandes;

  static const inconnue =
      'Je n’ai pas encore de réponse à cela : mon intelligence artificielle '
      'n’est pas encore branchée. Je peux déjà te donner l’heure, faire un '
      'calcul, t’expliquer une notion technique, ou t’aider avec une '
      'conversation : colle-la ici, par exemple « Sarah : … » puis « Moi : … ».';

  static const demandeConversation =
      'Colle-moi la conversation concernée, une ligne par message, par '
      'exemple :\nSarah : Tu viens ce soir ?\nMoi : Je ne sais pas encore.\n\n'
      'Je m’en occupe ensuite.';

  @override
  Future<ReponseJarvis> repondre(DemandeJarvis demande) async {
    final c = demande.conversation;
    switch (demande.intention) {
      case IntentionMessage.reponse:
        if (c == null) return const ReponseJarvis(demandeConversation);
        return ReponseJarvis(
          AnalyseConversation(c).avantReponse,
          choixTon: true,
        );
      case IntentionMessage.resume:
        if (c == null) return const ReponseJarvis(demandeConversation);
        return ReponseJarvis(AnalyseConversation(c).resume);
      case IntentionMessage.comprendre:
        if (c == null) return const ReponseJarvis(demandeConversation);
        return ReponseJarvis(AnalyseConversation(c).comprehension);
      case IntentionMessage.analyse:
        // Sans conversation, « je suis fâché » reste une discussion.
        if (c != null) {
          return ReponseJarvis(AnalyseConversation(c).analyser(demande.texte));
        }
      case IntentionMessage.discussion:
        // Conversation qui vient d'être collée, sans demande reconnue :
        // lecture courte et raccourcis discrets.
        if (c != null && demande.conversationNouvelle) {
          return ReponseJarvis(
            AnalyseConversation(c).lectureCourte,
            actions: ActionRapide.values,
          );
        }
    }
    // Vocal : la réponse complète du mode vocal (dont « Au revoir »).
    if (demande.vocale) {
      final r = await _commandes.traiter(demande.texte);
      return ReponseJarvis(r.texte, terminerSession: r.terminerSession);
    }
    return ReponseJarvis(_discussion(demande.texte));
  }

  String _discussion(String texte) {
    final r = _commandes.reponseLocale(texte);
    return r?.texte ?? inconnue;
  }

  @override
  void reinitialiser() => _commandes.contexte.reinitialiser();

  @override
  Object? capturerContexte() => _commandes.contexte.copie();

  @override
  void restaurerContexte(Object? contexte) {
    if (contexte is ContexteConversation) {
      _commandes.contexte.copierDe(contexte);
    } else {
      _commandes.contexte.reinitialiser();
    }
  }

  @override
  Future<String> proposerReponse(
    ConversationExterne conversation,
    TonReponse ton,
  ) async => reponseLocale(AnalyseConversation(conversation), ton);
}
