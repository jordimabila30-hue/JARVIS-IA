import 'dart:convert';

import '../../utils/identifiant.dart';
import '../api_jarvis.dart';
import '../conversations/depot_conversations.dart';

/// Phase 5 : actualisation manuelle d'un contexte WhatsApp.
///
/// L'utilisateur copie la suite de sa conversation sur WhatsApp (réponse
/// reçue, message qu'il a envoyé) et la colle dans JARVIS, sans
/// réimporter l'export. Le serveur l'ajoute à la suite du contexte avec sa
/// provenance (« ajouté à la main » : fourni par l'utilisateur, jamais une
/// réception vérifiée). Aucun appel à l'IA : la question suivante en tient
/// compte.
enum SensMessage {
  recu('Reçu', 'received'),
  envoye('Envoyé', 'sent');

  const SensMessage(this.libelle, this.api);
  final String libelle;
  final String api;
}

/// Une entrée du volet, avant confirmation.
class EntreeActualisation {
  EntreeActualisation({
    String? id,
    this.sens = SensMessage.recu,
    this.auteur,
    this.texte = '',
    this.date,
    this.dateBrute = '',
  }) : id = id ?? nouvelUuid();

  /// Choisi une fois par l'appareil : un réessai ne duplique rien.
  final String id;
  SensMessage sens;

  /// Reçu : participant choisi (obligatoire dans un groupe). Envoyé :
  /// ignoré (toujours l'utilisateur confirmé).
  String? auteur;
  String texte;

  /// Heure locale du message, si l'utilisateur la connaît (jamais
  /// inventée, jamais la date d'ajout).
  DateTime? date;
  String dateBrute;

  Map<String, Object?> versJson() => {
    'id': id,
    'direction': sens.api,
    'content': texte.trim(),
    if (sens == SensMessage.recu && auteur != null) 'author': auteur,
    if (date case final d?) 'sent_at': _iso(d),
    'sent_at_raw': dateBrute,
  };

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_deux(d.month)}-${_deux(d.day)}'
      'T${_deux(d.hour)}:${_deux(d.minute)}:00';
  static String _deux(int n) => n.toString().padLeft(2, '0');
}

/// Message déjà ajouté à la main (consultation, correction, suppression).
class MessageAjoute {
  const MessageAjoute({
    required this.id,
    required this.ordre,
    required this.sens,
    required this.auteur,
    required this.texte,
    this.date,
    this.corrige = false,
    this.ajouteLe,
  });

  /// Moment de l'ajout dans JARVIS (place de la bulle dans le fil), jamais
  /// la date du message.
  final DateTime? ajouteLe;

  MessageAjoute avecTexte(String nouveau) => MessageAjoute(
    id: id,
    ordre: ordre,
    sens: sens,
    auteur: auteur,
    texte: nouveau,
    date: date,
    corrige: true,
    ajouteLe: ajouteLe,
  );

  final String id;
  final int ordre;
  final SensMessage sens;
  final String auteur;
  final String texte;
  final DateTime? date;
  final bool corrige;

  static MessageAjoute? depuisJson(Object? j) {
    if (j case {
      'id': final String id,
      'message_order': final num ordre,
      'origin': final String origine,
      'author': final String auteur,
      'content': final String texte,
    } when origine != 'export') {
      final date = (j as Map)['sent_at'];
      final ajoute = j['created_at'];
      return MessageAjoute(
        ajouteLe: ajoute is String
            ? DateTime.tryParse(ajoute)?.toLocal()
            : null,
        id: id,
        ordre: ordre.toInt(),
        sens: origine == 'manual_sent' ? SensMessage.envoye : SensMessage.recu,
        auteur: auteur,
        texte: texte,
        date: date is String ? DateTime.tryParse(date) : null,
        corrige: j['edited_at'] != null,
      );
    }
    return null;
  }
}

/// Bulle du fil JARVIS (phase 5.1) : un message WhatsApp collé par
/// l'utilisateur, avec son contexte. Jamais un message adressé à JARVIS ni
/// une réponse de l'IA ; jamais envoyé au moteur comme historique du chat.
class AjoutDansLeFil {
  const AjoutDansLeFil({
    required this.contexte,
    required this.contact,
    required this.message,
  });

  final String contexte;
  final String contact;
  final MessageAjoute message;

  AjoutDansLeFil avecMessage(MessageAjoute m) =>
      AjoutDansLeFil(contexte: contexte, contact: contact, message: m);
}

/// Doublon possible signalé par le serveur (rien n'est écrit sans
/// confirmation).
class Correspondance {
  const Correspondance({
    required this.index,
    required this.declaration,
    required this.texte,
  });

  /// Rang de l'entrée concernée dans le volet.
  final int index;

  /// Proposition JARVIS déjà déclarée envoyée (phase 4) ; sinon message
  /// identique déjà présent dans la conversation.
  final bool declaration;
  final String texte;
}

sealed class ResultatAjout {
  const ResultatAjout();
}

final class AjoutReussi extends ResultatAjout {
  const AjoutReussi(this.messages);
  final List<MessageAjoute> messages;
}

final class DoublonsPossibles extends ResultatAjout {
  const DoublonsPossibles(this.items);
  final List<Correspondance> items;
}

final class EchecAjout extends ResultatAjout {
  const EchecAjout(this.message);
  final String message;
}

abstract class ServiceActualisationWhatsApp {
  /// Pièces jointes WhatsApp du compte (volet ouvert hors d'un chat
  /// WhatsApp).
  Future<ResultatApi<List<ContexteServeur>>> contextes();

  Future<ResultatAjout> ajouter(
    String contexte,
    List<EntreeActualisation> entrees, {
    bool confirmer = false,
  });

  Future<ResultatApi<List<MessageAjoute>>> ajoutes(String contexte);

  Future<ResultatApi<void>> modifier(
    String contexte,
    String message, {
    String? texte,
    String? auteur,
  });

  Future<ResultatApi<void>> supprimer(String contexte, String message);
}

class ActualisationWhatsAppApi implements ServiceActualisationWhatsApp {
  const ActualisationWhatsAppApi(this.api);

  final ApiJarvis api;

  @override
  Future<ResultatApi<List<ContexteServeur>>> contextes() async {
    final r = await api.contextesWhatsApp();
    switch (r) {
      case EchecApi(:final type, :final detail):
        return EchecApi(type, detail: detail);
      case SuccesApi(:final valeur):
        return SuccesApi([
          for (final l in (valeur['items'] as List? ?? const []))
            if (l is Map<String, dynamic>)
              ContexteServeur.depuis({
                ...l,
                'context_messages': [
                  {'count': l['messages_count'] ?? 0},
                ],
              }),
        ]);
    }
  }

  @override
  Future<ResultatAjout> ajouter(
    String contexte,
    List<EntreeActualisation> entrees, {
    bool confirmer = false,
  }) async {
    final r = await api.ajouterMessagesContexte(contexte, {
      'messages': [for (final e in entrees) e.versJson()],
      'confirm_duplicates': confirmer,
    });
    switch (r) {
      case SuccesApi(:final valeur):
        return AjoutReussi([
          for (final m in (valeur['messages'] as List? ?? const []))
            ?MessageAjoute.depuisJson(m),
        ]);
      case EchecApi(:final type, :final detail):
        final corps = _corps(detail);
        if (corps case {'code': 'correspondances', 'items': final List items}) {
          return DoublonsPossibles([
            for (final i in items)
              if (i case {'index': final num index, 'type': final String t})
                Correspondance(
                  index: index.toInt(),
                  declaration: t == 'declaration',
                  texte: '${i['texte'] ?? ''}',
                ),
          ]);
        }
        if (corps case {'message': final String message}) {
          return EchecAjout(message);
        }
        return EchecAjout(switch (type) {
          ErreurApi.pieceJointeIntrouvable =>
            'Cette conversation WhatsApp n’existe plus.',
          ErreurApi.nonConnecte => 'Connectez-vous pour actualiser.',
          ErreurApi.injoignable ||
          ErreurApi.delaiDepasse => 'Serveur JARVIS injoignable. Réessayez.',
          _ => 'L’ajout n’a pas pu être enregistré. Réessayez.',
        });
    }
  }

  @override
  Future<ResultatApi<List<MessageAjoute>>> ajoutes(String contexte) async {
    final r = await api.messagesAjoutes(contexte);
    switch (r) {
      case EchecApi(:final type, :final detail):
        return EchecApi(type, detail: detail);
      case SuccesApi(:final valeur):
        return SuccesApi([
          for (final m in (valeur['messages'] as List? ?? const []))
            ?MessageAjoute.depuisJson(m),
        ]);
    }
  }

  @override
  Future<ResultatApi<void>> modifier(
    String contexte,
    String message, {
    String? texte,
    String? auteur,
  }) async {
    final r = await api.modifierMessageContexte(contexte, message, {
      'content': ?texte,
      'author': ?auteur,
    });
    return switch (r) {
      SuccesApi() => const SuccesApi(null),
      EchecApi(:final type, :final detail) => EchecApi(type, detail: detail),
    };
  }

  @override
  Future<ResultatApi<void>> supprimer(String contexte, String message) async {
    final r = await api.supprimerMessageContexte(contexte, message);
    return switch (r) {
      SuccesApi() => const SuccesApi(null),
      EchecApi(:final type, :final detail) => EchecApi(type, detail: detail),
    };
  }

  static Map<String, dynamic>? _corps(String? detail) {
    if (detail == null || !detail.startsWith('{')) return null;
    try {
      final d = (jsonDecode(detail) as Map<String, dynamic>)['detail'];
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }
}
