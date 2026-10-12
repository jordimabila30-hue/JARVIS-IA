import 'package:flutter/foundation.dart';

import '../../models/importation/conversation_whatsapp.dart';

/// Conversation lue en attente du filtrage (étape 3) : en mémoire
/// seulement, jamais écrite sur le disque ni envoyée ailleurs. Elle reste
/// disponible même si le fichier partagé ne l'est plus.
class ImportEnCours {
  const ImportEnCours({required this.conversation, this.moi});

  final ConversationWhatsApp conversation;

  /// Nom de l'utilisateur parmi les participants (null : pas encore dit).
  final String? moi;

  ImportEnCours avecMoi(String nom) =>
      ImportEnCours(conversation: conversation, moi: nom);
}

/// L'import WhatsApp en cours (un à la fois) ; vidé à la fermeture de la
/// page d'import tant que rien n'est enregistré.
final importWhatsAppEnCours = ValueNotifier<ImportEnCours?>(null);
