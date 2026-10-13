import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
  });

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

  /// Quota quotidien atteint (429) ; [EchecApi.detail] : quand il se
  /// renouvelle.
  quotaAtteint(
    'Vous avez atteint votre limite quotidienne d’utilisation de l’IA.',
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
  messageTropLong('Ce message est trop long : 8 000 caractères au maximum.');

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
  }) : _client = client ?? http.Client();

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
  /// `meta`, même si la génération échoue ensuite. Chaque fragment de
  /// texte est donné à [surFragment] (affichage progressif, plus tard).
  ///
  /// Une réponse interrompue ou vide est un échec : jamais un texte
  /// partiel présenté comme complet. Aucun réessai, sauf un jeton expiré
  /// (refusé avant toute génération, donc sans doublon).
  Future<ResultatApi<ReponseChat>> discuter(
    String message, {
    String? conversation,
    void Function(String conversation)? surConversation,
    void Function(String fragment)? surFragment,
  }) {
    if (message.length > longueurMaxMessage) {
      return Future.value(const EchecApi(ErreurApi.messageTropLong));
    }
    return _authentifie(
      (j) => _chat(j, message, conversation, surConversation, surFragment),
    );
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
    var r = await appel(j);
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
    void Function(String fragment)? surFragment,
  ) async {
    _Reponse<ReponseChat> echec(ErreurApi e, [String? detail]) =>
        _Resultat(EchecApi(e, detail: detail));

    // Délai dépassé : la requête est abandonnée (connexion fermée).
    final abandon = Completer<void>();
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
          });
    final http.StreamedResponse r;
    try {
      r = await _client.send(requete).timeout(delaiChat);
    } on TimeoutException {
      abandon.complete();
      return echec(ErreurApi.delaiDepasse);
    } catch (_) {
      return echec(ErreurApi.injoignable);
    }

    if (r.statusCode != 200) {
      String corps;
      try {
        corps = await r.stream.bytesToString().timeout(delai);
      } catch (_) {
        corps = '';
      }
      return switch (r.statusCode) {
        401 || 403 => _Refus(_detail(corps), j),
        404 => echec(ErreurApi.conversationIntrouvable),
        429 => echec(ErreurApi.quotaAtteint, _quota(corps)),
        422 => echec(ErreurApi.messageTropLong),
        503 => echec(ErreurApi.indisponible, _detail(corps)),
        _ => echec(ErreurApi.serveur, 'HTTP ${r.statusCode}'),
      };
    }

    String? idConversation;
    final texte = StringBuffer();
    // Issue connue (`done` ou `error`) : le flux est tout de même lu
    // jusqu'à sa fermeture par le serveur (pas de connexion coupée net).
    _Reponse<ReponseChat>? fin;
    try {
      await for (final e in decoderSse(r.stream.timeout(delaiInactivite))) {
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
      return fin ?? echec(ErreurApi.fluxInterrompu);
    }
    // Fin du flux sans `done` : réponse incomplète.
    return fin ?? echec(ErreurApi.fluxInterrompu);
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

  /// « Elle se renouvelle dans 3 h. » : lu dans le refus 429 du serveur
  /// (secondes avant minuit UTC).
  static String? _quota(String corps) {
    try {
      final d = (jsonDecode(corps) as Map<String, dynamic>)['detail'];
      final quota = d is Map<String, dynamic> ? d['quota'] : null;
      final reste = quota is Map<String, dynamic> ? quota['resets_in'] : null;
      if (reste is! int) return null;
      final delai = reste < 3600
          ? '${(reste / 60).ceil()} min'
          : '${(reste / 3600).ceil()} h';
      return 'Elle se renouvelle dans $delai.';
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

  void fermer() => _client.close();
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
