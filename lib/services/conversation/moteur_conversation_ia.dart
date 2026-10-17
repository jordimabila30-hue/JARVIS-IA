import 'package:flutter/foundation.dart';

import '../api_jarvis.dart';
import '../conversations/correspondance_conversations.dart';
import 'moteur_conversation.dart';

/// Réponses de l'IA du serveur JARVIS (FastAPI → GroqCloud), pour le chat
/// écrit comme pour le vocal.
///
/// Le serveur garde l'historique de chaque conversation (UUID) : seul le
/// nouveau message part, jamais l'historique du fil (pas de doublon dans
/// le contexte du modèle). Chaque conversation du fil (identifiant local,
/// [DemandeJarvis.idConversation]) est rattachée à sa conversation
/// serveur : la première question en crée une, les suivantes la
/// reprennent, une nouvelle conversation du fil en obtient une autre.
///
/// Seul le texte écrit ou dit à JARVIS est envoyé : jamais une
/// conversation collée (le moteur hybride la garde sur l'appareil), ni les
/// messages d'une conversation WhatsApp importée. Ceux-ci sont déjà sur le
/// serveur : c'est lui qui en joint les extraits utiles à la question
/// (moteur de compréhension conversationnelle), seulement si
/// l'utilisateur l'a accepté ([analyseWhatsApp]).
class MoteurConversationIA {
  MoteurConversationIA(
    this._api, {
    CorrespondanceConversations? correspondance,
    this.avantEnvoi,
    this.analyseWhatsApp,
  }) : correspondance = correspondance ?? CorrespondanceConversations();

  /// Réponse de l'utilisateur sur l'envoi de ses conversations WhatsApp
  /// jointes au fournisseur IA ('allowed', 'declined', null : jamais
  /// demandé), lue à chaque question.
  final String? Function()? analyseWhatsApp;

  /// Explication affichée (et dite) quand l'accord est demandé.
  static const demandeAccord =
      'Pour analyser cette conversation WhatsApp, j’ai besoin de votre '
      'accord : les extraits utiles des messages (auteurs, dates, textes) '
      'seront envoyés à GroqCloud, le service d’intelligence artificielle '
      'externe de JARVIS, à chaque question qui porte sur elle. Jamais de '
      'fichiers ni de médias. Sans accord, elle reste enregistrée et '
      'consultable, sans analyse. Vous pourrez changer d’avis dans les '
      'Paramètres.';

  /// Attendu avant chaque question à l'IA (conversation locale) : les
  /// échanges locaux de la conversation sont enregistrés d'abord, pour
  /// que tout reste dans la même conversation serveur, dans l'ordre.
  final Future<void> Function(String idLocal)? avantEnvoi;

  final ApiJarvis _api;

  /// Identifiant local → identifiant serveur (partagé avec la
  /// synchronisation des conversations).
  final CorrespondanceConversations correspondance;

  /// Conversation serveur rattachée à la conversation locale [idLocal].
  String? idServeur(String idLocal) => correspondance.serveur(idLocal);

  /// Les fragments de la réponse sont transmis dès leur arrivée
  /// ([DemandeJarvis.surFragment]) : affichage progressif, jamais
  /// d'attente de la fin de la génération. Si le flux s'arrête après le
  /// début du texte, le texte reçu est gardé et signalé comme interrompu
  /// ([ReponseJarvis.incident]), jamais présenté comme complet.
  Future<ReponseJarvis> repondre(DemandeJarvis demande) async {
    final local = demande.idConversation;
    if (local != null) await avantEnvoi?.call(local);
    final recu = StringBuffer();
    String? idReponse;
    Future<ResultatApi<ReponseChat>> envoyer() => _api.discuter(
      demande.texte,
      conversation: local == null ? null : correspondance.serveur(local),
      repondreA: demande.repondreA,
      analyseWhatsApp: analyseWhatsApp?.call(),
      tonPropose: demande.tonPropose,
      propositionsMessage: demande.propositionsMessage,
      longueurPropose: demande.longueurPropose,
      // Dès l'événement `meta` : même si la génération échoue ensuite,
      // ou si le fil a changé entre-temps, la conversation locale garde
      // sa conversation serveur.
      surConversation: (id) {
        if (local != null) correspondance.associer(local, id);
      },
      surMessage: (id) => idReponse = id,
      surFragment: (f) {
        recu.write(f);
        demande.surFragment?.call(f);
      },
      surPreparation: demande.surPreparation,
    );
    var r = await envoyer();
    if (r case EchecApi(
      type: ErreurApi.conversationIntrouvable,
    ) when local != null && demande.repondreA == null) {
      // Conversation effacée côté serveur : refusée avant toute
      // génération (rien d'enregistré), on en recommence une seule fois.
      correspondance.oublier(local);
      r = await envoyer();
    }
    switch (r) {
      case SuccesApi(:final valeur):
        return ReponseJarvis(
          texteSimple(valeur.texte),
          idServeur: valeur.message ?? idReponse,
          references: valeur.references,
        );
      case EchecApi(type: ErreurApi.consentementRequis):
        // Rien n'est parti vers l'IA : JARVIS demande l'accord dans le fil.
        return const ReponseJarvis(
          demandeAccord,
          erreur: true,
          accordRequis: true,
        );
      case EchecApi(:final type, :final detail):
        debugPrint(
          '[JARVIS IA] échec : ${type.name}${detail == null ? '' : ' ($detail)'}',
        );
        final partiel = texteSimple(recu.toString());
        if (partiel.isNotEmpty) {
          // Le serveur enregistre le texte déjà généré sous l'identifiant
          // annoncé par `meta` : la réponse partielle y est rattachée (une
          // actualisation ne l'affichera pas en double).
          return ReponseJarvis(
            partiel,
            erreur: true,
            idServeur: idReponse,
            incident: messageInterruption(type, detail),
          );
        }
        return ReponseJarvis(messageErreur(type, detail), erreur: true);
    }
  }

  /// Explication affichée sous une réponse interrompue en cours de route.
  static String messageInterruption(ErreurApi type, String? detail) =>
      switch (type) {
        ErreurApi.iaIndisponible =>
          'Réponse interrompue : ${detail ?? type.message}',
        ErreurApi.delaiDepasse =>
          'Réponse interrompue : le serveur JARVIS a cessé de répondre. '
              'Renvoyez votre message pour obtenir la suite.',
        _ =>
          'Réponse interrompue avant la fin (connexion perdue). Renvoyez '
              'votre message pour obtenir la réponse complète.',
      };

  /// Le modèle répond parfois en Markdown (« **Lima** ») alors que le fil
  /// affiche du texte simple et que la réponse peut être lue à voix
  /// haute : gras, italique, code et titres perdent leurs symboles (les
  /// listes « - » restent lisibles telles quelles).
  static String texteSimple(String texte) => texte
      .replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m.group(2)!)
      .replaceAllMapped(
        RegExp(r'(?<![\w*])\*(?!\s)([^*\n]+?)\*(?!\w)'),
        (m) => m.group(1)!,
      )
      .replaceAllMapped(RegExp(r'`([^`\n]+)`'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .trim();

  /// [texteSimple] d'un texte encore en réception : en plus, une syntaxe
  /// Markdown pas encore refermée (« **Lim », « `cod », « ## » en début de
  /// ligne) est masquée au lieu d'apparaître puis de disparaître. Le
  /// texte affiché ne change donc pas de forme quand la suite arrive : il
  /// se prolonge seulement.
  static String texteSimpleProvisoire(String brut) {
    var t = texteSimple(brut);
    // Gras ouvert : seul le symbole est masqué, le texte reste visible.
    for (final marque in const ['**', '__']) {
      if (marque.allMatches(t).length.isOdd) {
        final i = t.lastIndexOf(marque);
        t = t.substring(0, i) + t.substring(i + marque.length);
      }
    }
    final debutLigne = t.lastIndexOf('\n') + 1;
    var ligne = t.substring(debutLigne);
    // Code ou italique ouvert sur la dernière ligne : symbole masqué.
    final code = RegExp(r'(?<!`)`(?!`)').allMatches(ligne).toList();
    if (code.length.isOdd) {
      final i = code.last.start;
      ligne = ligne.substring(0, i) + ligne.substring(i + 1);
    }
    final italique = RegExp(r'(?<![\w*])\*(?=[^\s*])').allMatches(ligne);
    for (final m in italique.toList().reversed) {
      if (!ligne.substring(m.end).contains('*')) {
        ligne = ligne.substring(0, m.start) + ligne.substring(m.end);
      }
      break;
    }
    // Symbole isolé en toute fin (« ## » d'un titre pas encore écrit,
    // « * ») : peut-être le début d'une marque.
    ligne = ligne.replaceFirstMapped(
      RegExp(r'(^|\s)[*_`#]+$'),
      (m) => m.group(1)!,
    );
    return (t.substring(0, debutLigne) + ligne).trimRight();
  }

  /// Explication affichée (et dite en vocal) à la place d'une réponse.
  static String messageErreur(ErreurApi type, String? detail) => switch (type) {
    ErreurApi.nonConnecte =>
      'Connectez-vous à votre compte pour que je puisse répondre à cette '
          'question. L’heure, les calculs et les autres commandes locales '
          'restent disponibles.',
    ErreurApi.injoignable =>
      'Je n’arrive pas à joindre le serveur JARVIS. Vérifiez votre '
          'connexion Internet, ou que le serveur est bien démarré. Les '
          'commandes locales (heure, calculs…) restent disponibles.',
    ErreurApi.iaIndisponible => detail ?? type.message,
    // Message complet du serveur (type de limite + sa réinitialisation).
    ErreurApi.quotaAtteint => detail ?? type.message,
    _ => type.message,
  };
}
