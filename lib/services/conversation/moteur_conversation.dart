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
    this.idConversation,
    this.surFragment,
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

  /// Identifiant local de la conversation du fil ([ConversationSession
  /// .idCourant]) : un moteur d'IA y rattache sa conversation serveur.
  final String? idConversation;

  /// Reçoit chaque fragment de la réponse dès son arrivée (flux de l'IA),
  /// pour l'affichage progressif. Un moteur qui produit sa réponse d'un
  /// coup (règles locales) ne l'appelle pas.
  final void Function(String fragment)? surFragment;

  /// La même demande, dont les fragments de réponse vont à [surFragment].
  DemandeJarvis avecFragments(void Function(String fragment) surFragment) =>
      DemandeJarvis(
        texte: texte,
        intention: intention,
        texteComplet: texteComplet,
        historique: historique,
        conversation: conversation,
        conversationNouvelle: conversationNouvelle,
        vocale: vocale,
        idConversation: idConversation,
        surFragment: surFragment,
      );
}

/// Réponse de JARVIS dans le fil.
class ReponseJarvis {
  const ReponseJarvis(
    this.texte, {
    this.choixTon = false,
    this.actions = const [],
    this.terminerSession = false,
    this.erreur = false,
    this.idServeur,
    this.incident,
  });

  final String texte;

  /// Afficher « Quel ton ? » puis une réponse proposée.
  final bool choixTon;

  /// Raccourcis discrets, seulement quand ils sont utiles.
  final List<ActionRapide> actions;

  /// « Au revoir JARVIS » : le chat vocal se termine.
  final bool terminerSession;

  /// Pas une réponse : explication d'un échec (serveur injoignable, quota
  /// atteint…). Le message de l'utilisateur reste dans le fil, à renvoyer.
  final bool erreur;

  /// Réponse de l'IA enregistrée par le serveur : UUID de sa ligne. Null
  /// pour une réponse locale (qui reste sur l'appareil).
  final String? idServeur;

  /// Réponse interrompue après le début de la réception : [texte] est le
  /// texte reçu (partiel), [incident] l'explication de l'arrêt. Toujours
  /// avec [erreur].
  final String? incident;

  /// Texte partiel d'une réponse interrompue.
  bool get interrompue => incident != null;
}

/// Cerveau de la conversation, écrite comme vocale (une seule conversation,
/// un seul contexte) : [MoteurConversationLocal] (règles locales seules) ou
/// [MoteurConversationHybride] (règles locales, sinon l'IA du serveur).
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
    final locale = await repondreLocalement(demande);
    if (locale != null) return locale;
    // Vocal : la réponse « pas encore disponible » du mode vocal.
    if (demande.vocale) {
      final r = await _commandes.traiter(demande.texte);
      return ReponseJarvis(r.texte, terminerSession: r.terminerSession);
    }
    return const ReponseJarvis(inconnue);
  }

  /// Réponse locale si la demande en a une, sinon null : conversation
  /// collée (analysée sur l'appareil, jamais envoyée), commande reconnue
  /// (heure, calcul, prénom, notion…).
  ///
  /// [avecIA] : une IA prend le relais si rien ne correspond (voir
  /// [VoiceCommandService.reponseLocale]).
  Future<ReponseJarvis?> repondreLocalement(
    DemandeJarvis demande, {
    bool avecIA = false,
  }) async {
    final c = demande.conversation;
    // Sans conversation connue, « résume la Révolution française » est une
    // vraie question pour l'IA ; « résume cette conversation » attend
    // toujours qu'on la colle.
    final sansConversation = !avecIA || _parleDUneConversation(demande.texte)
        ? const ReponseJarvis(demandeConversation)
        : null;
    switch (demande.intention) {
      case IntentionMessage.reponse:
        if (c == null) return sansConversation;
        return ReponseJarvis(
          AnalyseConversation(c).avantReponse,
          choixTon: true,
        );
      case IntentionMessage.resume:
        if (c == null) return sansConversation;
        return ReponseJarvis(AnalyseConversation(c).resume);
      case IntentionMessage.comprendre:
        if (c == null) return sansConversation;
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
    final r = _commandes.reponseLocale(demande.texte, avecIA: avecIA);
    if (r == null) return null;
    // « Au revoir » ne termine que le chat vocal.
    return ReponseJarvis(
      r.texte,
      terminerSession: demande.vocale && r.terminerSession,
    );
  }

  static const _motsConversation = [
    'conversation',
    'discussion',
    'message',
    'messages',
    'echange',
    'sms',
    'texto',
    'mail',
    'whatsapp',
    'messenger',
    'instagram',
    'lui',
    'leur',
  ];

  /// « Résume cette conversation », « que lui répondre ? », « que
  /// répondre ? » : la demande porte sur une conversation à coller.
  static bool _parleDUneConversation(String texte) {
    final t = DetecteurIntention.normaliser(texte);
    final encadre = ' $t ';
    return t.split(' ').length <= 3 ||
        _motsConversation.any((m) => encadre.contains(' $m '));
  }

  /// Réponse donnée par l'IA : retenue dans le contexte local (« répète »).
  void retenirReponseDistante(String texte) =>
      _commandes.retenirReponseDistante(texte);

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
