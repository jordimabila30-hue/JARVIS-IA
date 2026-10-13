import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Conversation JARVIS enregistrée sur le serveur (table `conversations`).
class ConversationServeur {
  const ConversationServeur({
    required this.id,
    required this.titre,
    required this.derniereActivite,
    this.apercu = '',
  });

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
  const PageMessages(this.messages, {this.plusAnciens = false});

  final List<MessageServeur> messages;

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
            .select('id, title, last_message_at, messages(content, created_at)')
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
    return PageMessages([
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

  static bool _jetonExpire(PostgrestException e) =>
      e.code == 'PGRST301' ||
      e.code == 'PGRST303' ||
      e.message.toLowerCase().contains('jwt expired');

  static DateTime _date(Object? brut) =>
      (DateTime.tryParse('$brut') ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toLocal();
}
