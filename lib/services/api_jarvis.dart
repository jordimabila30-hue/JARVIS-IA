import '../models/capture_jointe.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/importation/propositions_reponse.dart';
import '../models/integrations/etat_gmail.dart';
import '../models/importation/reference_whatsapp.dart';
import '../models/utilisation/utilisation.dart';
import '../utils/format_utilisation.dart';
import 'flux_sse.dart';

/// Compte tel que le backend JARVIS (FastAPI) le reconnaît, d'après le
/// jeton Supabase qu'il a vérifié (`GET /me`).
class CompteServeur {
  const CompteServeur({required this.identifiant, this.email});

  final String identifiant;
  final String? email;
}

/// Réponse complète du chat, reconstituée à partir du flux SSE.
class ReponseChat {
  const ReponseChat({
    required this.texte,
    required this.conversation,
    this.message,
    this.references = ReferencesReponse.vide,
  });

  /// Messages WhatsApp sur lesquels s'appuie la réponse, vérifiés par le
  /// serveur (événement `references`, avant `done`).
  final ReferencesReponse references;

  final String texte;

  /// Identifiant (UUID) de la conversation côté serveur.
  final String conversation;

  /// Identifiant (UUID) de la réponse enregistrée par le serveur.
  final String? message;
}

/// Résultat d'un appel au backend.
sealed class ResultatApi<T> {
  const ResultatApi();
}

final class SuccesApi<T> extends ResultatApi<T> {
  const SuccesApi(this.valeur);
  final T valeur;
}

final class EchecApi<T> extends ResultatApi<T> {
  const EchecApi(this.type, {this.detail});
  final ErreurApi type;

  /// Raison donnée par le serveur (« Token invalide »…), pour le
  /// diagnostic ; jamais de jeton ici.
  final String? detail;
}

enum ErreurApi {
  /// Réponse arrêtée par l'utilisateur (interruption vocale).
  annulee('Réponse arrêtée.'),

  /// Capture refusée avant tout appel (offre sans lecture d'image, image
  /// invalide) ; [EchecApi.detail] : le message du serveur.
  imageRefusee('L’image n’a pas pu être envoyée à JARVIS.'),

  /// Aucune session : aucun jeton à présenter.
  nonConnecte('Connectez-vous pour joindre le serveur JARVIS.'),

  /// Jeton refusé par le serveur (401).
  jetonRefuse('Le serveur JARVIS a refusé la session. Reconnectez-vous.'),

  /// Jeton expiré et renouvellement impossible : nouvelle connexion.
  sessionExpiree('Votre session a expiré. Reconnectez-vous.'),

  /// Serveur injoignable (arrêté, mauvaise adresse, réseau).
  injoignable('Le serveur JARVIS est injoignable.'),

  /// Réponse inattendue.
  serveur('Le serveur JARVIS a répondu de façon inattendue.'),

  /// Serveur temporairement indisponible (503 : base de données ou
  /// service d'authentification).
  indisponible(
    'Le serveur JARVIS est temporairement indisponible. Réessayez dans un '
    'instant.',
  ),

  /// Pas de réponse dans les délais (connexion ou génération).
  delaiDepasse(
    'Le serveur JARVIS met trop de temps à répondre. Réessayez dans un '
    'instant.',
  ),

  /// Limite JARVIS atteinte (429 : jour ou session, messages ou tokens) ;
  /// [EchecApi.detail] : message complet (limite et réinitialisation). Une
  /// limite du fournisseur IA est distincte : [iaIndisponible].
  quotaAtteint(
    'Vous avez atteint votre limite d’utilisation de l’IA.',
  ),

  /// Le fournisseur d'IA (GroqCloud) a échoué ; [EchecApi.detail] : le
  /// message du serveur, déjà rédigé pour l'utilisateur.
  iaIndisponible(
    'Le moteur IA est momentanément indisponible. Réessayez dans un instant.',
  ),

  /// Le flux s'est arrêté avant la fin de la réponse.
  fluxInterrompu(
    'La réponse a été interrompue avant la fin. Renvoyez votre message pour '
    'réessayer.',
  ),

  /// Flux terminé sans aucun texte.
  reponseVide('Le moteur IA n’a renvoyé aucune réponse. Réessayez.'),

  /// Conversation inconnue du serveur (404).
  conversationIntrouvable(
    'Cette conversation n’existe plus sur le serveur JARVIS.',
  ),

  /// Message refusé avant l'envoi (limite du serveur).
  messageTropLong('Ce message est trop long : 8 000 caractères au maximum.'),

  /// Pièce jointe WhatsApp refusée (données invalides, identifiant déjà
  /// utilisé pour un autre contenu).
  pieceJointeRefusee(
    'Le serveur JARVIS a refusé cette pièce jointe. Rejoignez la '
    'conversation pour réessayer.',
  ),

  /// Pièce jointe au-delà des limites du serveur.
  pieceJointeTropVolumineuse(
    'Cette pièce jointe est trop volumineuse : sélectionnez moins de '
    'messages.',
  ),

  /// Pièce jointe inconnue du serveur (supprimée, autre compte).
  pieceJointeIntrouvable('Cette pièce jointe n’existe plus sur le serveur.'),

  /// Le chat a des conversations WhatsApp jointes : le serveur attend
  /// l'accord de l'utilisateur avant d'en envoyer des extraits à l'IA
  /// (409, refusé avant tout appel au fournisseur).
  consentementRequis(
    'Pour analyser les conversations WhatsApp jointes, j’ai besoin de votre '
    'accord.',
  ),

  /// Consigne d'une pièce jointe inconnue du serveur (supprimée).
  consigneIntrouvable('Cette consigne n’existe plus sur le serveur.');

  const ErreurApi(this.message);
  final String message;
}

/// Client du backend FastAPI de JARVIS : santé du serveur, vérification
/// du compte (le jeton Supabase est accepté et désigne le bon utilisateur)
/// et chat en streaming ([discuter]).
///
/// Ne garde aucun jeton : il le demande à chaque appel ([jeton]), déjà
/// renouvelé s'il expirait.
class ApiJarvis {
  ApiJarvis({
    required this.adresse,
    required this.jeton,
    this.renouveler,
    http.Client? client,
    this.delai = const Duration(seconds: 10),
    this.delaiChat = const Duration(seconds: 30),
    this.delaiInactivite = const Duration(seconds: 30),
    this.veille,
    this.delaiReveil = const Duration(seconds: 75),
  }) : _client = client ?? http.Client();

  /// Serveur hébergé qui s'endort (Render Free : après ~15 min sans
  /// requête) : après ce silence, chaque appel protégé attend d'abord son
  /// réveil ([reveiller]). Null (serveur local, tests) : jamais d'attente.
  final Duration? veille;

  /// Attente maximale du réveil d'un serveur endormi.
  final Duration delaiReveil;

  /// Vrai pendant un réveil qui dure (au-delà d'une seconde et demie) :
  /// l'application affiche « Connexion au serveur JARVIS… ».
  final reveilEnCours = ValueNotifier<bool>(false);

  DateTime? _dernierContact;
  Future<ErreurApi?>? _reveil;

  void _vu() => _dernierContact = DateTime.now();

  /// Réveille le serveur hébergé s'il a pu s'endormir (`GET /health`, délai
  /// long, une seule requête partagée par les appels simultanés). Rien
  /// n'est envoyé au chat avant : jamais de message parti deux fois.
  /// Null : serveur joignable ; sinon l'erreur à présenter.
  Future<ErreurApi?> reveiller() {
    final veille = this.veille;
    final contact = _dernierContact;
    if (veille == null ||
        (contact != null && DateTime.now().difference(contact) < veille)) {
      return Future.value();
    }
    return _reveil ??= _attendreReveil().whenComplete(() => _reveil = null);
  }

  Future<ErreurApi?> _attendreReveil() async {
    final lent = Timer(
      const Duration(milliseconds: 1500),
      () => reveilEnCours.value = true,
    );
    try {
      final r = await _client.get(_route('health')).timeout(delaiReveil);
      _vu();
      return r.statusCode == 200 ? null : ErreurApi.indisponible;
    } on TimeoutException {
      return ErreurApi.delaiDepasse;
    } catch (e) {
      debugPrint('[JARVIS API] réveil impossible : ${_resume(e)}');
      return ErreurApi.injoignable;
    } finally {
      lent.cancel();
      reveilEnCours.value = false;
    }
  }

  /// Longueur maximale d'un message accepté par le serveur.
  static const longueurMaxMessage = 8000;

  final Uri adresse;
  final Future<String?> Function() jeton;

  /// Renouvelle le jeton quand le serveur le juge expiré (null : la
  /// session ne peut plus être renouvelée).
  final Future<String?> Function()? renouveler;
  final Duration delai;

  /// Attente maximale des en-têtes du chat (le serveur vérifie le jeton,
  /// le quota et prépare la conversation avant d'ouvrir le flux).
  final Duration delaiChat;

  /// Silence maximal entre deux paquets du flux.
  final Duration delaiInactivite;
  final http.Client _client;

  Uri _route(String chemin) {
    final base = adresse.path.endsWith('/') ? adresse.path : '${adresse.path}/';
    return adresse.replace(path: '$base$chemin');
  }

  /// `GET /health/ready` : API, Redis et Supabase prêts.
  Future<bool> pret() async {
    try {
      final r = await _client.get(_route('health/ready')).timeout(delai);
      _vu();
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// `GET /me` avec le jeton de la session : le serveur vérifie la
  /// signature du jeton et renvoie l'utilisateur qu'il y lit.
  Future<ResultatApi<CompteServeur>> moi() => _authentifie(_getMoi);

  /// `POST /api/v1/chat/stream` : envoie [message] et attend la réponse
  /// complète de l'IA (flux SSE `meta` → `delta`… → `done`, ou `error`).
  ///
  /// Seul le nouveau message part : l'historique est gardé par le serveur,
  /// dans la conversation [conversation] (UUID ; null : le serveur en crée
  /// une). Son identifiant est donné à [surConversation] dès l'événement
  /// `meta`, même si la génération échoue ensuite, avec celui de la future
  /// réponse ([surMessage] : le serveur l'enregistre même interrompue).
  /// Chaque fragment de texte est donné à [surFragment] dès son arrivée
  /// (affichage progressif).
  ///
  /// Une réponse interrompue ou vide est un échec : jamais un texte
  /// partiel présenté comme complet. Aucun réessai, sauf un jeton expiré
  /// (refusé avant toute génération, donc sans doublon).
  ///
  /// [repondreA] : UUID d'une consigne déjà enregistrée avec sa pièce
  /// jointe WhatsApp (elle n'est pas réinsérée). [analyseWhatsApp] :
  /// réponse de l'utilisateur sur l'envoi des messages WhatsApp joints au
  /// fournisseur IA ('allowed', 'declined', null : jamais demandé).
  /// [tonPropose] : ton affiché dans les dernières propositions de réponse
  /// (« pourquoi la deuxième ? » vise ce ton).
  Future<ResultatApi<ReponseChat>> discuter(
    String message, {
    String? conversation,
    String? repondreA,
    String? analyseWhatsApp,
    String? tonPropose,
    String? propositionsMessage,
    String? longueurPropose,
    ImageAEnvoyer? image,
    bool oral = false,
    Future<void>? annulation,
    String? entendu,
    void Function(String conversation)? surConversation,
    void Function(String message)? surMessage,
    void Function(String fragment)? surFragment,
    void Function()? surPreparation,
  }) {
    if (message.length > longueurMaxMessage) {
      return Future.value(const EchecApi(ErreurApi.messageTropLong));
    }
    return _consommer(
      () => _authentifie(
      (j) => _chat(
        j,
        message,
        conversation,
        surConversation,
        surMessage,
        surFragment,
        repondreA: repondreA,
        analyseWhatsApp: analyseWhatsApp,
        tonPropose: tonPropose,
        propositionsMessage: propositionsMessage,
        longueurPropose: longueurPropose,
        image: image,
        oral: oral,
        annulation: annulation,
        entendu: entendu,
        surPreparation: surPreparation,
      ),
      ),
    );
  }

  /// Appelé après chaque opération IA qui a pu consommer le quota (réponse
  /// terminée, interrompue ou refusée, « Reprendre ») : l'application
  /// actualise alors l'utilisation (`/me/quota`). Jamais pendant un flux.
  void Function()? surConsommation;

  Future<ResultatApi<T>> _consommer<T>(Future<ResultatApi<T>> Function() appel) async {
    try {
      return await appel();
    } finally {
      surConsommation?.call();
    }
  }

  /// `GET /me/quota` : utilisation du compte calculée par le serveur
  /// (offre Supabase, consommation du jour et de la session). Lecture
  /// seule : n'appelle jamais l'IA, n'ouvre aucune session.
  Future<ResultatApi<Utilisation>> utilisation() async {
    final r = await _authentifie((j) => _json('GET', 'me/quota', j));
    switch (r) {
      case EchecApi(:final type, :final detail):
        return EchecApi(type, detail: detail);
      case SuccesApi(:final valeur):
        try {
          return SuccesApi(Utilisation.depuisJson(valeur));
        } on FormatException {
          return const EchecApi(ErreurApi.serveur, detail: 'réponse /me/quota illisible');
        }
    }
  }

  /// `POST /api/v1/conversations/local-exchanges` : enregistre un échange
  /// traité localement (heure, calcul…) dans la conversation [conversation]
  /// du compte (null : le serveur en crée une). Rien n'est généré par le
  /// serveur, aucun quota n'est consommé. Renvoie l'UUID de la
  /// conversation.
  ///
  /// [idQuestion] et [idReponse] (UUID choisis par l'appareil) rendent
  /// l'envoi sans risque de doublon : renvoyé après une coupure, il n'est
  /// pas réinséré.
  Future<ResultatApi<String>> enregistrerEchangeLocal({
    required String idQuestion,
    required String idReponse,
    required String question,
    required String reponse,
    String? conversation,
    DateTime? questionA,
    DateTime? reponseA,
  }) => _authentifie((j) async {
    _Reponse<String> echec(ErreurApi e, [String? detail]) =>
        _Resultat(EchecApi(e, detail: detail));
    final http.Response r;
    try {
      r = await _client
          .post(
            _route('api/v1/conversations/local-exchanges'),
            headers: {
              'Authorization': 'Bearer $j',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'question_id': idQuestion,
              'answer_id': idReponse,
              'conversation_id': conversation,
              'question': question,
              'answer': reponse,
              'question_at': questionA?.toUtc().toIso8601String(),
              'answer_at': reponseA?.toUtc().toIso8601String(),
            }),
          )
          .timeout(delai);
    } on TimeoutException {
      return echec(ErreurApi.delaiDepasse);
    } catch (_) {
      return echec(ErreurApi.injoignable);
    }
    switch (r.statusCode) {
      case 200 || 201:
        try {
          final id = (jsonDecode(r.body) as Map)['conversation_id'];
          if (id is String) return _Resultat(SuccesApi(id));
        } catch (_) {}
        return echec(ErreurApi.serveur, 'réponse illisible');
      case 401 || 403:
        return _Refus(_detail(r.body), j);
      case 404:
        return echec(ErreurApi.conversationIntrouvable);
      case 422:
        return echec(ErreurApi.messageTropLong);
      case 503:
        return echec(ErreurApi.indisponible, _detail(r.body));
      default:
        return echec(ErreurApi.serveur, 'HTTP ${r.statusCode}');
    }
  });

  // --- Contextes WhatsApp (pièces jointes) -------------------------------
  // Stockage seulement : aucune de ces routes ne passe par l'IA.

  /// `POST /api/v1/conversations/contexts` : consigne + pièce jointe, en
  /// une transaction côté serveur. [corps] porte les identifiants choisis
  /// par l'appareil : un nouvel essai ne crée jamais de doublon.
  Future<ResultatApi<Map<String, dynamic>>> enregistrerContexte(
    Map<String, dynamic> corps, {
    Duration delaiEnregistrement = const Duration(seconds: 45),
  }) => _authentifie(
    (j) => _json(
      'POST',
      'api/v1/conversations/contexts',
      j,
      corps: corps,
      delaiAppel: delaiEnregistrement,
    ),
  );

  /// `GET /api/v1/contexts/{id}/messages` : une page, ordre original.
  Future<ResultatApi<Map<String, dynamic>>> pageMessagesContexte(
    String id, {
    int apres = -1,
    int limite = 500,
  }) => _authentifie(
    (j) => _json(
      'GET',
      'api/v1/contexts/$id/messages',
      j,
      requete: {'after': '$apres', 'limit': '$limite'},
    ),
  );

  /// `GET /api/v1/conversations/{id}/references` : références vérifiées
  /// des réponses de JARVIS de ce chat (relues dans Supabase), par UUID
  /// de réponse.
  Future<ResultatApi<Map<String, ReferencesReponse>>> referencesConversation(
    String conversation,
  ) async {
    final r = await _authentifie(
      (j) => _json('GET', 'api/v1/conversations/$conversation/references', j),
    );
    switch (r) {
      case EchecApi(:final type, :final detail):
        return EchecApi(type, detail: detail);
      case SuccesApi(:final valeur):
        try {
          return SuccesApi({
            for (final e in valeur['items'] as List)
              if (e case {'message_id': final String id})
                id: ReferencesReponse(
                  ReferenceWhatsApp.listeDepuisJson(e['references']),
                  note: e['note'] as String?,
                  propositions: PropositionsReponse.depuisJson(
                    e['propositions'],
                  ),
                ),
          });
        } catch (_) {
          return const EchecApi(
            ErreurApi.serveur,
            detail: 'références illisibles',
          );
        }
    }
  }

  /// Phase 4 : `PUT` (déclarer) ou `DELETE` (annuler)
  /// `/api/v1/conversations/{c}/messages/{m}/propositions/{p}/envoyee`.
  /// Succès : date de la déclaration confirmée par le serveur (null :
  /// annulée). Idempotent côté serveur (aucun doublon).
  Future<ResultatApi<DateTime?>> statutEnvoyee({
    required String conversation,
    required String message,
    required String proposition,
    required bool envoyee,
  }) async {
    final r = await _authentifie(
      (j) => _json(
        envoyee ? 'PUT' : 'DELETE',
        'api/v1/conversations/$conversation/messages/$message/propositions/'
        '$proposition/envoyee',
        j,
      ),
    );
    switch (r) {
      case EchecApi(:final type, :final detail):
        return EchecApi(type, detail: detail);
      case SuccesApi(:final valeur):
        final date = valeur['declared_at'];
        if (valeur['envoyee'] == true && date is String) {
          return SuccesApi(DateTime.tryParse(date)?.toLocal());
        }
        if (valeur['envoyee'] == false) return const SuccesApi(null);
        return const EchecApi(ErreurApi.serveur, detail: 'statut illisible');
    }
  }

  /// `POST /api/v1/conversations/{c}/messages/{m}/propositions/completer` :
  /// complète une génération incomplète (seulement ce qui manque, même
  /// ensemble). Peut attendre la limite du fournisseur : délai long.
  Future<ResultatApi<PropositionsReponse?>> completerPropositions({
    required String conversation,
    required String message,
  }) async {
    final r = await _authentifie(
      (j) => _json(
        'POST',
        'api/v1/conversations/$conversation/messages/$message/propositions/'
        'completer',
        j,
        delaiAppel: const Duration(minutes: 2),
      ),
    );
    surConsommation?.call();   // lots de propositions : quota consommé
    switch (r) {
      case EchecApi(:final type, :final detail):
        return EchecApi(type, detail: detail);
      case SuccesApi(:final valeur):
        return SuccesApi(PropositionsReponse.depuisJson(valeur['propositions']));
    }
  }

  // --- Phase 5 : actualisation manuelle d'un contexte WhatsApp ----------

  /// `GET /api/v1/contexts` : toutes les pièces jointes du compte.
  Future<ResultatApi<Map<String, dynamic>>> contextesWhatsApp() =>
      _authentifie((j) => _json('GET', 'api/v1/contexts', j));

  /// `POST /api/v1/contexts/{id}/messages` : messages collés (reçus /
  /// envoyés), atomique et idempotent. Échec 409 : [EchecApi.detail] porte
  /// le corps (`correspondances`).
  Future<ResultatApi<Map<String, dynamic>>> ajouterMessagesContexte(
    String contexte,
    Map<String, dynamic> corps,
  ) => _authentifie(
    (j) => _json('POST', 'api/v1/contexts/$contexte/messages', j, corps: corps),
  );

  /// `GET /api/v1/contexts/{id}/messages?manual=true` : les ajouts seulement.
  Future<ResultatApi<Map<String, dynamic>>> messagesAjoutes(String contexte) =>
      _authentifie(
        (j) => _json(
          'GET',
          'api/v1/contexts/$contexte/messages',
          j,
          requete: {'after': '-1', 'limit': '200', 'manual': 'true'},
        ),
      );

  /// `PATCH` / `DELETE /api/v1/contexts/{id}/messages/{message}` : corrige
  /// ou supprime un message AJOUTÉ (jamais un message importé).
  Future<ResultatApi<Map<String, dynamic>>> modifierMessageContexte(
    String contexte,
    String message,
    Map<String, dynamic> corps,
  ) => _authentifie(
    (j) => _json(
      'PATCH',
      'api/v1/contexts/$contexte/messages/$message',
      j,
      corps: corps,
    ),
  );

  Future<ResultatApi<Map<String, dynamic>>> supprimerMessageContexte(
    String contexte,
    String message,
  ) => _authentifie(
    (j) => _json('DELETE', 'api/v1/contexts/$contexte/messages/$message', j),
  );

  /// `DELETE /api/v1/contexts/{id}` : la pièce jointe et ses messages.
  Future<ResultatApi<Map<String, dynamic>>> supprimerContexte(String id) =>
      _authentifie((j) => _json('DELETE', 'api/v1/contexts/$id', j));

  // --- Gmail (ODO phase 2, lecture seule) -------------------------------------
  // Les jetons Google restent sur le serveur : l'application ne reçoit que
  // l'état et l'URL de la page Google à ouvrir dans le navigateur.

  /// `GET /api/v1/integrations/gmail`.
  Future<ResultatApi<EtatGmail>> etatGmail() async {
    final r = await _authentifie((j) => _json('GET', 'api/v1/integrations/gmail', j));
    return switch (r) {
      SuccesApi(:final valeur) => SuccesApi(EtatGmail.depuisJson(valeur)),
      EchecApi(:final type, :final detail) => EchecApi(type, detail: detail),
    };
  }

  /// `POST /api/v1/integrations/gmail/connexion` : URL de Google (choix du
  /// compte et consentement), à ouvrir dans le navigateur du système.
  Future<ResultatApi<String>> urlConnexionGmail(String plateforme) async {
    final r = await _authentifie(
      (j) => _json('POST', 'api/v1/integrations/gmail/connexion', j, corps: {'plateforme': plateforme}),
    );
    return switch (r) {
      SuccesApi(:final valeur) when valeur['url'] is String => SuccesApi(valeur['url'] as String),
      SuccesApi() => const EchecApi(ErreurApi.serveur, detail: 'URL Google absente'),
      EchecApi(:final type, :final detail) => EchecApi(type, detail: detail),
    };
  }

  /// `DELETE /api/v1/integrations/gmail` : accès coupé, autorisation
  /// révoquée chez Google (la boîte Gmail n'est jamais touchée).
  Future<ResultatApi<Map<String, dynamic>>> deconnecterGmail() =>
      _authentifie((j) => _json('DELETE', 'api/v1/integrations/gmail', j));

  Future<_Reponse<Map<String, dynamic>>> _json(
    String methode,
    String chemin,
    String j, {
    Map<String, dynamic>? corps,
    Map<String, String>? requete,
    Duration? delaiAppel,
  }) async {
    _Reponse<Map<String, dynamic>> echec(ErreurApi e, [String? detail]) =>
        _Resultat(EchecApi(e, detail: detail));
    final http.Response r;
    try {
      final adresse = _route(chemin).replace(queryParameters: requete);
      final demande = http.Request(methode, adresse)
        ..headers.addAll({
          'Authorization': 'Bearer $j',
          if (corps != null) 'Content-Type': 'application/json',
        });
      if (corps != null) demande.body = jsonEncode(corps);
      r = await http.Response.fromStream(
        await _client.send(demande),
      ).timeout(delaiAppel ?? delai);
    } on TimeoutException {
      return echec(ErreurApi.delaiDepasse);
    } catch (_) {
      return echec(ErreurApi.injoignable);
    }
    switch (r.statusCode) {
      case 200 || 201:
        try {
          return _Resultat(
            SuccesApi(
              jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>,
            ),
          );
        } catch (_) {
          return echec(ErreurApi.serveur, 'réponse illisible');
        }
      case 204:
        return _Resultat(const SuccesApi(<String, dynamic>{}));
      case 401 || 403:
        return _Refus(_detail(r.body), j);
      case 404:
        return echec(
          chemin.startsWith('api/v1/contexts')
              ? ErreurApi.pieceJointeIntrouvable
              : ErreurApi.conversationIntrouvable,
        );
      case 409 || 422:
        // Phase 5 (ajouts manuels) : le corps porte les doublons possibles
        // ou la raison du refus (auteur invalide, message importé).
        return echec(
          ErreurApi.pieceJointeRefusee,
          chemin.contains('/messages')
              ? utf8.decode(r.bodyBytes)
              : 'HTTP ${r.statusCode}',
        );
      case 413:
        return echec(ErreurApi.pieceJointeTropVolumineuse);
      case 429:
        return echec(ErreurApi.quotaAtteint, messageLimite(utf8.decode(r.bodyBytes)));
      case 503:
        return echec(ErreurApi.indisponible, _detail(r.body));
      default:
        return echec(ErreurApi.serveur, 'HTTP ${r.statusCode}');
    }
  }

  /// Appel protégé : seule l'horloge du serveur décide si le jeton est
  /// expiré ; dans ce cas, le jeton est renouvelé (Supabase) et l'appel
  /// refait une seule fois. Renouvellement impossible : session expirée
  /// (l'application ramène alors à la connexion).
  Future<ResultatApi<T>> _authentifie<T>(
    Future<_Reponse<T>> Function(String jeton) appel,
  ) async {
    final j = await jeton();
    if (j == null) return EchecApi<T>(ErreurApi.nonConnecte);
    final reveil = await reveiller();
    if (reveil != null) return EchecApi<T>(reveil, detail: 'réveil du serveur');
    var r = await appel(j);
    // Le serveur a répondu (même par un refus) : il est éveillé.
    final repondu = switch (r) {
      _Resultat<T>(
        resultat: EchecApi<T>(
          type: ErreurApi.injoignable || ErreurApi.delaiDepasse,
        ),
      ) =>
        false,
      _ => true,
    };
    if (repondu) _vu();
    final renouveler = this.renouveler;
    if (r is _Refus<T> && r.detail == 'Token expiré' && renouveler != null) {
      final neuf = await renouveler();
      if (neuf == null) return EchecApi<T>(ErreurApi.sessionExpiree);
      r = await appel(neuf);
    }
    return switch (r) {
      _Refus<T>(:final detail, :final jeton) => EchecApi<T>(
        ErreurApi.jetonRefuse,
        detail: _raison(detail, jeton),
      ),
      _Resultat<T>(:final resultat) => resultat,
    };
  }

  Future<_Reponse<CompteServeur>> _getMoi(String j) async {
    final http.Response r;
    try {
      r = await _client
          .get(_route('me'), headers: {'Authorization': 'Bearer $j'})
          .timeout(delai);
    } catch (_) {
      return const _Resultat(EchecApi(ErreurApi.injoignable));
    }
    if (r.statusCode == 401 || r.statusCode == 403) {
      return _Refus(_detail(r.body), j);
    }
    if (r.statusCode != 200) {
      return const _Resultat(EchecApi(ErreurApi.serveur));
    }
    try {
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      return _Resultat(
        SuccesApi(
          CompteServeur(
            identifiant: '${json['id']}',
            email: json['email'] as String?,
          ),
        ),
      );
    } catch (_) {
      return const _Resultat(EchecApi(ErreurApi.serveur));
    }
  }

  Future<_Reponse<ReponseChat>> _chat(
    String j,
    String message,
    String? conversation,
    void Function(String conversation)? surConversation,
    void Function(String message)? surMessage,
    void Function(String fragment)? surFragment, {
    String? repondreA,
    String? analyseWhatsApp,
    String? tonPropose,
    String? propositionsMessage,
    String? longueurPropose,
    ImageAEnvoyer? image,
    bool oral = false,
    Future<void>? annulation,
    String? entendu,
    void Function()? surPreparation,
  }) async {
    _Reponse<ReponseChat> echec(ErreurApi e, [String? detail]) =>
        _Resultat(EchecApi(e, detail: detail));

    // Délai dépassé ou arrêt demandé : la requête est abandonnée (connexion
    // fermée ; le serveur enregistre le texte déjà généré).
    final abandon = Completer<void>();
    var annulee = false;
    if (annulation != null) {
      unawaited(
        annulation.then((_) {
          annulee = true;
          if (!abandon.isCompleted) abandon.complete();
        }),
      );
    }
    final requete =
        http.AbortableRequest(
            'POST',
            _route('api/v1/chat/stream'),
            abortTrigger: abandon.future,
          )
          ..headers.addAll({
            'Authorization': 'Bearer $j',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode({
            'message': message,
            'conversation_id': conversation,
            'reply_to': ?repondreA,
            'whatsapp_analysis': ?analyseWhatsApp,
            'ton_propose': ?tonPropose,
            'propositions_message_id': ?propositionsMessage,
            'longueur_proposee': ?longueurPropose,
            if (oral) 'oral': true,
            if (entendu != null) 'interruption': {'entendu': entendu},
            // « hier », « cette semaine » : heure locale de l'appareil.
            'fuseau_minutes': DateTime.now().timeZoneOffset.inMinutes,
            if (image != null)
              'image': {
                'media_type': image.typeMedia,
                'data': base64Encode(image.octets),
              },
          });
    final http.StreamedResponse r;
    try {
      r = await _client.send(requete).timeout(delaiChat);
    } on TimeoutException {
      if (!abandon.isCompleted) abandon.complete();
      return echec(ErreurApi.delaiDepasse);
    } catch (e) {
      if (annulee) return echec(ErreurApi.annulee);
      return echec(ErreurApi.injoignable, _resume(e));
    }

    if (r.statusCode != 200) {
      String corps;
      try {
        corps = await r.stream.bytesToString().timeout(delai);
      } catch (_) {
        corps = '';
      }
      final code = _code(corps) ?? '';
      return switch (r.statusCode) {
        403 || 422 when code.startsWith('vision') || code.startsWith('image') =>
          echec(ErreurApi.imageRefusee, _messageDetail(corps)),
        401 || 403 => _Refus(_detail(corps), j),
        404 when _detail(corps) == 'Consigne introuvable' => echec(
          ErreurApi.consigneIntrouvable,
        ),
        404 => echec(ErreurApi.conversationIntrouvable),
        409 when _code(corps) == 'consentement_requis' => echec(
          ErreurApi.consentementRequis,
        ),
        429 => echec(ErreurApi.quotaAtteint, messageLimite(corps)),
        422 => echec(ErreurApi.messageTropLong),
        503 => echec(ErreurApi.indisponible, _detail(corps)),
        _ => echec(ErreurApi.serveur, 'HTTP ${r.statusCode}'),
      };
    }

    String? idConversation;
    final texte = StringBuffer();
    var references = ReferencesReponse.vide;
    PropositionsReponse? propositions;
    // Issue connue (`done` ou `error`) : le flux est tout de même lu
    // jusqu'à sa fermeture par le serveur (pas de connexion coupée net).
    _Reponse<ReponseChat>? fin;
    try {
      await for (final e in decoderSse(r.stream.timeout(delaiInactivite))) {
        if (annulee) break;
        if (fin != null) continue;
        final donnees = e.donnees.isEmpty
            ? const <String, dynamic>{}
            : jsonDecode(e.donnees) as Map<String, dynamic>;
        switch (e.type) {
          case 'meta':
            final id = donnees['conversation_id'];
            if (id is String && id.isNotEmpty) {
              idConversation = id;
              surConversation?.call(id);
            }
            final message = donnees['message_id'];
            if (message is String && message.isNotEmpty) {
              surMessage?.call(message);
            }
          case 'references':
            references = ReferencesReponse(
              ReferenceWhatsApp.listeDepuisJson(donnees['references']),
              note: donnees['note'] as String?,
            );
          case 'propositions':
            propositions = PropositionsReponse.depuisJson(donnees);
          case 'preparation':
            // Texte fini, propositions en préparation (lots) : la bulle
            // garde un indicateur vivant jusqu'à `propositions` / `done`.
            surPreparation?.call();
          case 'delta':
            final fragment = donnees['text'];
            if (fragment is String && fragment.isNotEmpty) {
              texte.write(fragment);
              surFragment?.call(fragment);
            }
          case 'done':
            final id = idConversation;
            fin = id == null
                ? echec(ErreurApi.serveur, 'flux sans meta')
                : texte.toString().trim().isEmpty
                ? echec(ErreurApi.reponseVide)
                : _Resultat(
                    SuccesApi(
                      ReponseChat(
                        texte: texte.toString(),
                        conversation: id,
                        message: donnees['message_id'] as String?,
                        references: references.avecPropositions(propositions),
                      ),
                    ),
                  );
          case 'error':
            final m = donnees['message'];
            fin = echec(ErreurApi.iaIndisponible, m is String ? m : null);
        }
      }
    } on TimeoutException {
      return fin ?? echec(ErreurApi.delaiDepasse);
    } on FormatException {
      return fin ?? echec(ErreurApi.serveur, 'flux illisible');
    } catch (_) {
      return fin ?? echec(annulee ? ErreurApi.annulee : ErreurApi.fluxInterrompu);
    }
    if (annulee) return fin ?? echec(ErreurApi.annulee);
    // Fin du flux sans `done` : réponse incomplète.
    return fin ?? echec(ErreurApi.fluxInterrompu);
  }

  /// Cause d'un échec réseau pour le journal : type et début du message
  /// (adresse, code système ; jamais d'en-tête ni de jeton).
  static String _resume(Object e) {
    final m = '$e'.replaceAll(RegExp(r'\s+'), ' ');
    return '${e.runtimeType}: ${m.length > 160 ? m.substring(0, 160) : m}';
  }

  static String? _raison(String? detail, String jeton) {
    final raison = [?detail, ?_algorithme(jeton)].join(' · ');
    return raison.isEmpty ? null : raison;
  }

  static String? _detail(String corps) {
    try {
      final d = (jsonDecode(corps) as Map<String, dynamic>)['detail'];
      return d is String ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// Message d'une erreur structurée (`{"detail": {"message": …}}`).
  static String? _messageDetail(String corps) {
    try {
      final d = (jsonDecode(corps) as Map<String, dynamic>)['detail'];
      return d is Map && d['message'] is String ? d['message'] as String : null;
    } catch (_) {
      return null;
    }
  }

  /// Code d'une erreur structurée (`{"detail": {"code": …}}`).
  static String? _code(String corps) {
    try {
      final d = (jsonDecode(corps) as Map<String, dynamic>)['detail'];
      final code = d is Map<String, dynamic> ? d['code'] : null;
      return code is String ? code : null;
    } catch (_) {
      return null;
    }
  }

  /// Message complet d'un refus 429 du serveur, selon la limite atteinte
  /// (`detail.kind`) et SA réinitialisation (`detail.resets_at` : fin de
  /// session pour une limite de session, remise à zéro quotidienne sinon).
  /// null : corps illisible (message générique).
  static String? messageLimite(String corps, {DateTime? maintenant}) {
    try {
      final d = (jsonDecode(corps) as Map<String, dynamic>)['detail'];
      if (d is! Map<String, dynamic>) return null;
      final quand = DateTime.tryParse(d['resets_at'] as String? ?? '');
      final reprise = quand == null
          ? ''
          : ' ${repriseLimite(quand, maintenant ?? DateTime.now())}';
      return switch (d['kind']) {
        'session_messages' =>
          'Vous avez atteint votre limite de messages pour cette session. '
              'Réessayez après sa réinitialisation.$reprise',
        'session_tokens' =>
          'Vous avez atteint votre limite de tokens pour cette session. '
              'Réessayez après sa réinitialisation.$reprise',
        'messages' => 'Votre limite quotidienne de messages est atteinte.$reprise',
        'tokens' => 'Votre limite quotidienne de tokens est atteinte.$reprise',
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  /// « signature ES256 (clé identifiée) » : lu dans l'en-tête du jeton,
  /// qui ne contient rien de secret (le jeton lui-même n'est jamais
  /// affiché).
  static String? _algorithme(String jeton) {
    try {
      final entete = base64Url.normalize(jeton.split('.').first);
      final h =
          jsonDecode(utf8.decode(base64Url.decode(entete)))
              as Map<String, dynamic>;
      final cle = h['kid'] is String
          ? 'clé ${(h['kid'] as String).substring(0, 6)}…'
          : 'sans clé';
      return 'signature ${h['alg']}, $cle';
    } catch (_) {
      return null;
    }
  }

  void fermer() {
    reveilEnCours.dispose();
    _client.close();
  }
}

sealed class _Reponse<T> {
  const _Reponse();
}

final class _Refus<T> extends _Reponse<T> {
  const _Refus(this.detail, this.jeton);
  final String? detail;
  final String jeton;
}

final class _Resultat<T> extends _Reponse<T> {
  const _Resultat(this.resultat);
  final ResultatApi<T> resultat;
}
