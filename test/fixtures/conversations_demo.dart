// DONNÉES DE DÉMONSTRATION — tests uniquement. Jamais utilisées par
// l'application : aucune fausse conversation ni faux compte connecté
// n'apparaît dans JARVIS.

import 'package:flutter/foundation.dart';
import 'package:ia_jarvis/models/conversations/apercu_conversation.dart';
import 'package:ia_jarvis/models/conversations/source_conversation.dart';
import 'package:ia_jarvis/services/conversations/fournisseur_conversations.dart';

/// Messagerie de démonstration : une liste fixe, et le journal des
/// conversations ouvertes.
class FournisseurDemo extends ChangeNotifier
    implements FournisseurConversations {
  FournisseurDemo(this.source, this._conversations);

  @override
  final SourceConversation source;

  final List<ApercuConversation> _conversations;
  final ouvertes = <String>[];

  @override
  List<ApercuConversation> get conversations => _conversations;

  @override
  bool ouvrir(String id) {
    final c = _conversations.where((c) => c.id == id).firstOrNull;
    if (c == null || !c.disponible) return false;
    ouvertes.add(id);
    return true;
  }

  /// Données locales de démonstration seulement.
  @override
  bool supprimer(String id) {
    final avant = _conversations.length;
    _conversations.removeWhere((c) => c.id == id);
    if (_conversations.length == avant) return false;
    notifyListeners();
    return true;
  }

  void ajouter(ApercuConversation c) {
    _conversations.add(c);
    notifyListeners();
  }
}

/// Instant de référence des données de démonstration.
final referenceDemo = DateTime(2026, 10, 11, 18, 42);

ApercuConversation conversationDemo(
  SourceConversation source,
  String id,
  String titre,
  String apercu, {
  int minutesAvant = 0,
  bool disponible = true,
}) => ApercuConversation(
  source: source,
  id: id,
  titre: titre,
  apercu: apercu,
  derniereActivite: referenceDemo.subtract(Duration(minutes: minutesAvant)),
  disponible: disponible,
);

/// 40 conversations WhatsApp (de la plus récente à la plus ancienne :
/// « Contact 0 » … « Contact 39 »), dont Tony Stark en tête.
List<ApercuConversation> whatsappDemo() => [
  conversationDemo(
    SourceConversation.whatsapp,
    'wa-tony',
    'Tony Stark',
    'On se voit demain ?',
  ),
  for (var i = 1; i < 40; i++)
    conversationDemo(
      SourceConversation.whatsapp,
      'wa-$i',
      'Contact $i',
      'Message numéro $i',
      minutesAvant: i * 90,
    ),
];

List<ApercuConversation> gmailDemo() => [
  conversationDemo(
    SourceConversation.gmail,
    'gm-1',
    'Pepper Potts',
    'Réunion du conseil d’administration',
    minutesAvant: 30,
  ),
  conversationDemo(
    SourceConversation.gmail,
    'gm-2',
    'Équipe Stark Industries',
    'Rapport trimestriel',
    minutesAvant: 3000,
  ),
  // Même identifiant qu'une conversation WhatsApp : les épingles ne
  // doivent jamais se mélanger.
  conversationDemo(
    SourceConversation.gmail,
    'wa-tony',
    'Happy Hogan',
    'Voiture prête',
    minutesAvant: 9000,
  ),
];
