import 'package:flutter/foundation.dart';

import '../../models/conversations/apercu_conversation.dart';
import '../../models/conversations/source_conversation.dart';

/// Ce qu'une messagerie fournit au menu latéral : ses conversations et le
/// moyen d'en ouvrir une. Une implémentation par source (JARVIS
/// aujourd'hui ; WhatsApp, Gmail… avec leurs futurs modules). Prévient ses
/// écouteurs quand sa liste change.
abstract class FournisseurConversations implements Listenable {
  SourceConversation get source;

  /// Conversations connues, dans n'importe quel ordre (le tri et les
  /// épingles sont faits par `ConversationsMulticanal`).
  List<ApercuConversation> get conversations;

  /// Ouvre la conversation dans l'accueil. Faux si elle n'est pas (ou plus)
  /// disponible.
  bool ouvrir(String id);

  /// Supprime la conversation des données locales de JARVIS (jamais sur la
  /// plateforme d'origine : aucun appel à une API externe). Faux si elle
  /// est inconnue ou si la source ne garde rien.
  bool supprimer(String id);
}

/// Messagerie pas encore intégrée : aucune conversation, rien à ouvrir. Ne
/// prétend jamais être connectée.
class FournisseurNonIntegre extends ChangeNotifier
    implements FournisseurConversations {
  FournisseurNonIntegre(this.source);

  @override
  final SourceConversation source;

  @override
  List<ApercuConversation> get conversations => const [];

  @override
  bool ouvrir(String id) => false;

  @override
  bool supprimer(String id) => false;
}
