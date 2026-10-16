import '../../models/importation/conversation_whatsapp.dart';
import '../../models/importation/piece_jointe_whatsapp.dart';
import '../../models/importation/reference_whatsapp.dart';
import '../api_jarvis.dart';

/// Pièce jointe enregistrée par le serveur (réponse de l'enregistrement).
class PieceJointeEnregistree {
  const PieceJointeEnregistree({
    required this.conversation,
    required this.consigne,
    required this.contexte,
    required this.nombre,
    required this.dejaEnregistree,
    required this.conversationCreee,
  });

  /// UUID de la conversation JARVIS (reprise ou créée).
  final String conversation;
  final String consigne;
  final String contexte;
  final int nombre;

  /// Nouvel essai d'un envoi déjà enregistré (coupure réseau) : rien n'a
  /// été réinséré.
  final bool dejaEnregistree;
  final bool conversationCreee;
}

/// Une page de messages d'une pièce jointe : rangs [premier] à
/// `premier + messages.length - 1` (rangs contigus : la pièce jointe
/// numérote ses messages 0..n-1).
class PageWhatsApp {
  const PageWhatsApp({
    required this.premier,
    required this.messages,
    required this.suite,
  });

  final int premier;
  final List<MessageWhatsApp> messages;

  /// D'autres messages suivent.
  final bool suite;
}

/// Pièces jointes WhatsApp du compte, côté serveur (backend FastAPI) :
/// enregistrer (consigne + pièce jointe, une transaction), relire les
/// messages d'une pièce jointe (tous, ou une page autour d'un message),
/// la supprimer, relire les références des réponses. Rien ne passe par
/// l'IA.
abstract class ServicePiecesJointes {
  /// [conversation] : UUID serveur du chat existant, ou null (le serveur
  /// crée la conversation, au nom du contact).
  Future<ResultatApi<PieceJointeEnregistree>> enregistrer({
    required PieceJointeWhatsApp piece,
    required String consigne,
    String? conversation,
  });

  /// Tous les messages de la pièce jointe [idContexte], dans l'ordre (lus
  /// par pages).
  Future<ResultatApi<List<MessageWhatsApp>>> messages(String idContexte);

  Future<ResultatApi<void>> supprimer(String idContexte);

  /// Messages de rang [apres] + 1 à [apres] + [limite] (ordre original).
  Future<ResultatApi<PageWhatsApp>> page(
    String idContexte, {
    required int apres,
    required int limite,
  });

  /// Références vérifiées des réponses de JARVIS du chat [conversation]
  /// (UUID serveur), par UUID de réponse.
  Future<ResultatApi<Map<String, ReferencesReponse>>> references(
    String conversation,
  );
}

/// [ServicePiecesJointes] par l'API JARVIS (jeton de la session).
class PiecesJointesApi implements ServicePiecesJointes {
  PiecesJointesApi(this.api, {this.taillePage = 500});

  final ApiJarvis api;
  final int taillePage;

  @override
  Future<ResultatApi<PieceJointeEnregistree>> enregistrer({
    required PieceJointeWhatsApp piece,
    required String consigne,
    String? conversation,
  }) async {
    final r = await api.enregistrerContexte(
      corps(piece: piece, consigne: consigne, conversation: conversation),
    );
    switch (r) {
      case EchecApi(:final type, :final detail):
        return EchecApi(type, detail: detail);
      case SuccesApi(:final valeur):
        try {
          return SuccesApi(
            PieceJointeEnregistree(
              conversation: valeur['conversation_id'] as String,
              consigne: valeur['message_id'] as String,
              contexte: valeur['context_id'] as String,
              nombre: (valeur['messages_count'] as num).toInt(),
              dejaEnregistree: valeur['already_saved'] == true,
              conversationCreee: valeur['conversation_created'] == true,
            ),
          );
        } catch (_) {
          return const EchecApi(ErreurApi.serveur, detail: 'réponse illisible');
        }
    }
  }

  @override
  Future<ResultatApi<List<MessageWhatsApp>>> messages(String idContexte) async {
    final lus = <MessageWhatsApp>[];
    var apres = -1;
    // Borne de sécurité : jamais de boucle sans fin sur une réponse
    // inattendue (limite serveur : quelques milliers de messages).
    for (var page = 0; page < 1000; page++) {
      final r = await api.pageMessagesContexte(
        idContexte,
        apres: apres,
        limite: taillePage,
      );
      switch (r) {
        case EchecApi(:final type, :final detail):
          return EchecApi(type, detail: detail);
        case SuccesApi(:final valeur):
          try {
            for (final m in valeur['messages'] as List) {
              lus.add(versMessage(m as Map<String, dynamic>));
            }
            final suite = valeur['next_after'];
            if (suite is! num) return SuccesApi(lus);
            apres = suite.toInt();
          } catch (_) {
            return const EchecApi(ErreurApi.serveur, detail: 'page illisible');
          }
      }
    }
    return const EchecApi(ErreurApi.serveur, detail: 'pages sans fin');
  }

  @override
  Future<ResultatApi<PageWhatsApp>> page(
    String idContexte, {
    required int apres,
    required int limite,
  }) async {
    final r = await api.pageMessagesContexte(
      idContexte,
      apres: apres,
      limite: limite,
    );
    switch (r) {
      case EchecApi(:final type, :final detail):
        return EchecApi(type, detail: detail);
      case SuccesApi(:final valeur):
        try {
          final lignes = valeur['messages'] as List;
          final premier = lignes.isEmpty
              ? apres + 1
              : ((lignes.first as Map)['message_order'] as num).toInt();
          return SuccesApi(
            PageWhatsApp(
              premier: premier,
              messages: [
                for (final m in lignes) versMessage(m as Map<String, dynamic>),
              ],
              suite: valeur['next_after'] is num,
            ),
          );
        } catch (_) {
          return const EchecApi(ErreurApi.serveur, detail: 'page illisible');
        }
    }
  }

  @override
  Future<ResultatApi<Map<String, ReferencesReponse>>> references(
    String conversation,
  ) => api.referencesConversation(conversation);

  @override
  Future<ResultatApi<void>> supprimer(String idContexte) async {
    final r = await api.supprimerContexte(idContexte);
    return switch (r) {
      EchecApi(:final type, :final detail) => EchecApi(type, detail: detail),
      SuccesApi() => const SuccesApi(null),
    };
  }

  // --- Format d'échange (docs/backend/CONTEXTES_WHATSAPP.md) --------------

  static const _types = {
    TypeMessageWhatsApp.texte: 'text',
    TypeMessageWhatsApp.media: 'media',
    TypeMessageWhatsApp.supprime: 'deleted',
    TypeMessageWhatsApp.systeme: 'system',
  };

  /// Corps de l'enregistrement : la consigne, les identifiants choisis par
  /// l'appareil et UNIQUEMENT les messages sélectionnés (texte et
  /// métadonnées ; jamais un fichier ni un média).
  static Map<String, dynamic> corps({
    required PieceJointeWhatsApp piece,
    required String consigne,
    String? conversation,
  }) => {
    'context_id': piece.id,
    'message_id': piece.idConsigne,
    'conversation_id': conversation,
    'instruction': consigne,
    'context': {
      'source': piece.source.name,
      'contact_name': piece.titre,
      'is_group': piece.groupe,
      'current_user_name': piece.moi.isEmpty ? null : piece.moi,
      'participants': piece.participants,
      'dates_uncertain': piece.dateIncertaine,
      if (piece.conversationSource.isNotEmpty)
        'source_fingerprint': piece.conversationSource,
    },
    'messages': [
      for (var i = 0; i < piece.messages.length; i++)
        _versJson(piece.messages[i], i),
    ],
  };

  static Map<String, dynamic> _versJson(MessageWhatsApp m, int rang) => {
    'message_order': rang,
    'source_order': m.ordre,
    'author': m.auteur,
    'content': m.texte,
    'kind': _types[m.type],
    'media_type': m.typeMedia?.name,
    // Heure locale de l'export, sans fuseau (aucune précision inventée).
    'sent_at': m.date == null ? null : _dateLocale(m.date!),
    'sent_at_raw': m.dateBrute.length > 100
        ? m.dateBrute.substring(0, 100)
        : m.dateBrute,
  };

  static String _dateLocale(DateTime d) {
    String deux(int v) => v.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${deux(d.month)}-'
        '${deux(d.day)}T${deux(d.hour)}:${deux(d.minute)}:${deux(d.second)}';
  }

  /// Message relu du serveur ; `ordre` reprend le rang d'origine.
  static MessageWhatsApp versMessage(Map<String, dynamic> j) {
    final type = _types.entries
        .firstWhere(
          (e) => e.value == j['kind'],
          orElse: () => const MapEntry(TypeMessageWhatsApp.texte, 'text'),
        )
        .key;
    final media = j['media_type'] as String?;
    final date = j['sent_at'] as String?;
    return MessageWhatsApp(
      ordre: ((j['source_order'] ?? j['message_order']) as num).toInt(),
      auteur: j['author'] as String?,
      // Lue telle quelle : heure locale, sans conversion de fuseau.
      date: date == null ? null : DateTime.tryParse(date.replaceAll('Z', '')),
      dateBrute: j['sent_at_raw'] as String? ?? '',
      texte: j['content'] as String? ?? '',
      type: type,
      ajoute: j['origin'] is String && j['origin'] != 'export',
      typeMedia: media == null
          ? null
          : TypeMediaWhatsApp.values.firstWhere(
              (t) => t.name == media,
              orElse: () => TypeMediaWhatsApp.inconnu,
            ),
    );
  }
}
