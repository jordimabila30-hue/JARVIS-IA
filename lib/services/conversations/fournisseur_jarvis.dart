import 'package:flutter/foundation.dart';

import '../../models/conversations/apercu_conversation.dart';
import '../../models/conversations/source_conversation.dart';
import '../../models/message_conversation.dart';
import '../conversation/conversation_session.dart';
import 'fournisseur_conversations.dart';

/// Conversations JARVIS réellement disponibles : celle de l'accueil et
/// celles mises de côté par « Nouvelle conversation » (en mémoire pour
/// l'instant). Les ouvrir passe par [ConversationSession.ouvrir].
class FournisseurJarvis extends ChangeNotifier
    implements FournisseurConversations {
  FournisseurJarvis(this._session) {
    _session.addListener(_surSession);
  }

  final ConversationSession _session;

  // Ne prévient le menu que si la liste a changé (pas à chaque réflexion).
  String _signature = '';

  void _surSession() {
    final s = [
      _session.idCourant,
      _session.messages.length,
      for (final a in _session.archives) a.id,
    ].join('|');
    if (s == _signature) return;
    _signature = s;
    notifyListeners();
  }

  @override
  SourceConversation get source => SourceConversation.jarvis;

  @override
  List<ApercuConversation> get conversations {
    final courante = _session.idCourant;
    return [
      if (courante != null && _session.messages.isNotEmpty)
        _apercu(courante, _session.messages, ouverte: true),
      for (final a in _session.archives) _apercu(a.id, a.messages),
    ];
  }

  @override
  bool ouvrir(String id) => _session.ouvrir(id);

  /// Retirée de la session (seul endroit où elle existe : en mémoire, pas
  /// encore enregistrée sur l'appareil).
  @override
  bool supprimer(String id) => _session.supprimer(id);

  ApercuConversation _apercu(
    String id,
    List<MessageConversation> messages, {
    bool ouverte = false,
  }) {
    final dernier = messages.last;
    return ApercuConversation(
      source: SourceConversation.jarvis,
      id: id,
      titre: titre(messages),
      apercu: _uneLigne(
        dernier.texte.trim().isNotEmpty
            ? dernier.texte
            : (dernier.conversation != null ? 'Conversation collée' : ''),
      ),
      derniereActivite: dernier.heure,
      ouverte: ouverte,
    );
  }

  /// Titre : début du premier message de l'utilisateur.
  static String titre(List<MessageConversation> messages) {
    for (final m in messages) {
      if (m.deJarvis) continue;
      if (m.texte.trim().isNotEmpty) return _uneLigne(m.texte);
      if (m.conversation != null) return 'Conversation collée';
    }
    return 'Conversation';
  }

  static String _uneLigne(String texte) =>
      texte.trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  void dispose() {
    _session.removeListener(_surSession);
    super.dispose();
  }
}
