import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pièce jointe WhatsApp enregistrée (table `conversation_contexts`) :
/// métadonnées seulement ; ses messages sont lus à la demande.
class ContexteServeur {
  const ContexteServeur({
    required this.id,
    required this.consigne,
    required this.contact,
    required this.nombre,
    required this.creeLe,
    this.participants = const [],
    this.moi,
    this.groupe = false,
    this.datesIncertaines = false,
    this.debut,
    this.fin,
  });

  final String id;

  /// UUID du message de consigne (null : consigne supprimée).
  final String? consigne;
  final String contact;

  /// Nombre réel de messages enregistrés.
  final int nombre;
  final DateTime creeLe;
  final List<String> participants;
  final String? moi;
  final bool groupe;
  final bool datesIncertaines;

  /// Période des messages : heure locale de l'export, sans fuseau.
  final DateTime? debut;
  final DateTime? fin;

  /// Colonnes lues (et nombre de messages calculé par PostgREST).
  static const colonnes =
      'id, message_id, contact_name, participants, current_user_name, '
      'is_group, dates_uncertain, period_start, period_end, created_at, '
      'context_messages(count)';

  static ContexteServeur depuis(Map<String, dynamic> l) => ContexteServeur(
    id: l['id'] as String,
    consigne: l['message_id'] as String?,
    contact: (l['contact_name'] as String?)?.trim() ?? '',
    nombre: switch (l['context_messages']) {
      [final Map<String, dynamic> c, ...] => (c['count'] as num?)?.toInt() ?? 0,
      _ => 0,
    },
    creeLe: DepotConversationsSupabase._date(l['created_at']),
    participants: [
      for (final p in (l['participants'] as List?) ?? const []) '$p',
    ],
    moi: l['current_user_name'] as String?,
    groupe: l['is_group'] == true,
    datesIncertaines: l['dates_uncertain'] == true,
    debut: DateTime.tryParse('${l['period_start']}'),
    fin: DateTime.tryParse('${l['period_end']}'),
  );
}

/// Conversation JARVIS enregistrée sur le serveur (table `conversations`).
class ConversationServeur {
  const ConversationServeur({
    required this.id,
    required this.titre,
    required this.derniereActivite,
    this.apercu = '',
    this.contextes = const [],
  });

  /// Pièces jointes WhatsApp de la conversation, de la plus ancienne à la
  /// plus récente. Au moins une : la conversation est classée sous
  /// WhatsApp (son titre est déjà le nom du contact).
  final List<ContexteServeur> contextes;

  /// UUID serveur : la référence stable de la conversation.
  final String id;

  /// Titre enregistré par le serveur (début de la première question).
  final String titre;

  /// `last_message_at`, en heure locale.
  final DateTime derniereActivite;

  /// Début du dernier message.
  final String apercu;
}

/// Message enregistré par le serveur (table `messages`).
class MessageServeur {
  const MessageServeur({
    required this.id,
    required this.role,
    required this.contenu,
    required this.date,
  });

  final String id;

  /// `user`, `assistant` ou `system`.
  final String role;
  final String contenu;

  /// `created_at`, en heure locale.
  final DateTime date;
}

/// Une page de messages, du plus ancien au plus récent.
class PageMessages {
  const PageMessages(
    this.messages, {
    this.plusAnciens = false,
    this.contextes = const [],
  });

  final List<MessageServeur> messages;

  /// Pièces jointes WhatsApp de la conversation (première page seulement).
  final List<ContexteServeur> contextes;

  /// Vrai s'il reste des messages plus anciens à charger.
  final bool plusAnciens;
}

enum ErreurSynchro {
  horsLigne('Connexion impossible : vérifiez votre accès à Internet.'),
  sessionExpiree('Votre session a expiré. Reconnectez-vous.'),
  introuvable('Cette conversation n’existe plus sur le serveur.'),
  serveur('Le serveur des conversations a répondu de façon inattendue.');

  const ErreurSynchro(this.message);
  final String message;
}

class EchecSynchro implements Exception {
  const EchecSynchro(this.type, {this.detail});

  final ErreurSynchro type;

  /// Pour le diagnostic (jamais de jeton ni de contenu de message).
  final String? detail;

  @override
  String toString() =>
      'EchecSynchro(${type.name}${detail == null ? '' : ', $detail'})';
}

/// Conversations JARVIS enregistrées, lues avec les droits de
/// l'utilisateur connecté.
///
/// Flutter ne fait que lire et supprimer : les messages sont enregistrés
/// par le backend (FastAPI) à chaque échange avec l'IA, jamais une
/// seconde fois par l'application.
abstract class DepotConversations {
  /// Compte dont les données sont lues (null : personne de connecté).
  String? get utilisateur;

  /// Conversations non archivées, la plus récemment active d'abord, vides
  /// comprises (génération échouée) : elles peuvent être supprimées.
  Future<List<ConversationServeur>> lister({int limite = 100});

  /// Derniers messages de la conversation [id] (ou ceux d'avant [avant]).
  /// [ErreurSynchro.introuvable] si elle n'existe pas (ou plus).
  Future<PageMessages> messages(String id, {DateTime? avant, int limite = 50});

  /// Supprime la conversation et, par cascade, ses messages. Une
  /// conversation déjà supprimée ailleurs : [ErreurSynchro.introuvable].
  Future<void> supprimer(String id);
}

/// [DepotConversations] par l'API Supabase (PostgREST) avec la session de
/// l'utilisateur : les règles RLS du projet s'appliquent (chacun ne voit
/// et ne supprime que ses propres conversations). Aucune clé
/// administrative ici.
class DepotConversationsSupabase implements DepotConversations {
  DepotConversationsSupabase(
    this._client, {
    required this.jeton,
    this.renouveler,
    this.delai = const Duration(seconds: 15),
  });

  final SupabaseClient _client;

  /// Jeton valide de la session (déjà renouvelé s'il allait expirer,
  /// d'après l'horloge fiable de `HorlogeJetons`) ; null : déconnecté.
  final Future<String?> Function() jeton;

  /// Renouvellement quand le serveur juge le jeton expiré.
  final Future<String?> Function()? renouveler;
  final Duration delai;

  @override
  String? get utilisateur => _client.auth.currentUser?.id;

  @override
  Future<List<ConversationServeur>> lister({int limite = 100}) =>
      _executer((uid) async {
        final lignes = await _client
            .from('conversations')
            .select(
              'id, title, last_message_at, messages(content, created_at), '
              'conversation_contexts(${ContexteServeur.colonnes})',
            )
            .eq('user_id', uid)
            .eq('archived', false)
            .order('last_message_at', ascending: false)
            .order('created_at', referencedTable: 'messages', ascending: false)
            .limit(1, referencedTable: 'messages')
            .limit(limite)
            .timeout(delai);
        return [
          for (final l in lignes)
            ConversationServeur(
              id: l['id'] as String,
              titre: (l['title'] as String?)?.trim() ?? '',
              derniereActivite: _date(l['last_message_at']),
              apercu: switch (l['messages']) {
                [final Map<String, dynamic> dernier, ...] =>
                  dernier['content'] as String? ?? '',
                _ => '',
              },
              contextes: _contextes(l['conversation_contexts']),
            ),
        ];
      });

  @override
  Future<PageMessages> messages(
    String id, {
    DateTime? avant,
    int limite = 50,
  }) => _executer((uid) async {
    var requete = _client
        .from('messages')
        .select('id, role, content, created_at')
        .eq('conversation_id', id)
        .eq('user_id', uid);
    if (avant != null) {
      requete = requete.lt('created_at', avant.toUtc().toIso8601String());
    }
    final lignes = await requete
        .order('created_at', ascending: false)
        .limit(limite + 1)
        .timeout(delai);
    if (lignes.isEmpty && avant == null) {
      // Aucun message : la conversation a-t-elle été supprimée ailleurs ?
      final existe = await _client
          .from('conversations')
          .select('id')
          .eq('id', id)
          .eq('user_id', uid)
          .maybeSingle()
          .timeout(delai);
      if (existe == null) throw const EchecSynchro(ErreurSynchro.introuvable);
    }
    final page = lignes.take(limite).toList().reversed;
    // Pièces jointes WhatsApp : métadonnées seulement, avec la dernière
    // page (les messages WhatsApp sont lus à la demande).
    final contextes = avant != null
        ? const <ContexteServeur>[]
        : _contextes(
            await _client
                .from('conversation_contexts')
                .select(ContexteServeur.colonnes)
                .eq('conversation_id', id)
                .eq('user_id', uid)
                .timeout(delai),
          );
    return PageMessages(contextes: contextes, [
      for (final l in page)
        MessageServeur(
          id: l['id'] as String,
          role: '${l['role']}',
          contenu: l['content'] as String? ?? '',
          date: _date(l['created_at']),
        ),
    ], plusAnciens: lignes.length > limite);
  });

  @override
  Future<void> supprimer(String id) => _executer((uid) async {
    final supprimees = await _client
        .from('conversations')
        .delete()
        .eq('id', id)
        .eq('user_id', uid)
        .select('id')
        .timeout(delai);
    if (supprimees.isEmpty) {
      throw const EchecSynchro(ErreurSynchro.introuvable);
    }
  });

  /// Jeton frais avant l'appel ; jeton jugé expiré par le serveur :
  /// renouvelé, puis un seul nouvel essai. Erreurs traduites en
  /// [EchecSynchro].
  Future<T> _executer<T>(Future<T> Function(String uid) appel) async {
    Future<T> essai() async {
      final j = await jeton();
      final uid = utilisateur;
      if (j == null || uid == null) {
        throw const EchecSynchro(ErreurSynchro.sessionExpiree);
      }
      return appel(uid);
    }

    try {
      try {
        return await essai();
      } on PostgrestException catch (e) {
        final renouveler = this.renouveler;
        if (!_jetonExpire(e) || renouveler == null) rethrow;
        if (await renouveler() == null) {
          throw const EchecSynchro(ErreurSynchro.sessionExpiree);
        }
        return await essai();
      }
    } on EchecSynchro {
      rethrow;
    } on PostgrestException catch (e) {
      throw EchecSynchro(
        _jetonExpire(e) || e.code == '401'
            ? ErreurSynchro.sessionExpiree
            : ErreurSynchro.serveur,
        detail: e.code,
      );
    } on AuthException catch (e) {
      throw EchecSynchro(ErreurSynchro.sessionExpiree, detail: e.statusCode);
    } on TimeoutException {
      throw const EchecSynchro(ErreurSynchro.horsLigne, detail: 'délai');
    } on http.ClientException {
      throw const EchecSynchro(ErreurSynchro.horsLigne);
    } catch (e) {
      // SocketException (hors Web), sans importer dart:io.
      final reseau = '${e.runtimeType}'.contains('Socket');
      throw EchecSynchro(
        reseau ? ErreurSynchro.horsLigne : ErreurSynchro.serveur,
        detail: '${e.runtimeType}',
      );
    }
  }

  static List<ContexteServeur> _contextes(Object? brut) {
    final liste = [
      for (final l in (brut as List?) ?? const [])
        ContexteServeur.depuis(l as Map<String, dynamic>),
    ];
    liste.sort((a, b) => a.creeLe.compareTo(b.creeLe));
    return liste;
  }

  static bool _jetonExpire(PostgrestException e) =>
      e.code == 'PGRST301' ||
      e.code == 'PGRST303' ||
      e.message.toLowerCase().contains('jwt expired');

  static DateTime _date(Object? brut) =>
      (DateTime.tryParse('$brut') ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toLocal();
}
