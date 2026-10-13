import 'package:flutter/foundation.dart';

import '../api_jarvis.dart';
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
/// conversation collée ou importée (le moteur hybride les garde sur
/// l'appareil).
class MoteurConversationIA {
  MoteurConversationIA(this._api);

  final ApiJarvis _api;

  /// Identifiant local → identifiant serveur.
  final _serveur = <String, String>{};

  /// Conversation serveur rattachée à la conversation locale [idLocal].
  String? idServeur(String idLocal) => _serveur[idLocal];

  Future<ReponseJarvis> repondre(DemandeJarvis demande) async {
    final local = demande.idConversation;
    var r = await _envoyer(demande.texte, local);
    if (r case EchecApi(
      type: ErreurApi.conversationIntrouvable,
    ) when local != null) {
      // Conversation effacée côté serveur : refusée avant toute
      // génération (rien d'enregistré), on en recommence une seule fois.
      _serveur.remove(local);
      r = await _envoyer(demande.texte, local);
    }
    switch (r) {
      case SuccesApi(:final valeur):
        return ReponseJarvis(texteSimple(valeur.texte));
      case EchecApi(:final type, :final detail):
        debugPrint(
          '[JARVIS IA] échec : ${type.name}${detail == null ? '' : ' ($detail)'}',
        );
        return ReponseJarvis(messageErreur(type, detail), erreur: true);
    }
  }

  Future<ResultatApi<ReponseChat>> _envoyer(String texte, String? local) =>
      _api.discuter(
        texte,
        conversation: local == null ? null : _serveur[local],
        // Dès l'événement `meta` : même si la génération échoue ensuite,
        // ou si le fil a changé entre-temps, la conversation locale garde
        // sa conversation serveur.
        surConversation: (id) {
          if (local != null) _serveur[local] = id;
        },
      );

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
    ErreurApi.quotaAtteint =>
      detail == null ? type.message : '${type.message} $detail',
    _ => type.message,
  };
}
