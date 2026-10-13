import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Compte tel que le backend JARVIS (FastAPI) le reconnaît, d'après le
/// jeton Supabase qu'il a vérifié (`GET /me`).
class CompteServeur {
  const CompteServeur({required this.identifiant, this.email});

  final String identifiant;
  final String? email;
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
  serveur('Le serveur JARVIS a répondu de façon inattendue.');

  const ErreurApi(this.message);
  final String message;
}

/// Client du backend FastAPI de JARVIS. Pour l'instant : santé du serveur
/// et vérification du compte (le jeton Supabase est accepté et désigne le
/// bon utilisateur). Le chat (streaming) viendra plus tard.
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
  }) : _client = client ?? http.Client();

  final Uri adresse;
  final Future<String?> Function() jeton;

  /// Renouvelle le jeton quand le serveur le juge expiré (null : la
  /// session ne peut plus être renouvelée).
  final Future<String?> Function()? renouveler;
  final Duration delai;
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
  /// signature du jeton et renvoie l'utilisateur qu'il y lit. Seule
  /// l'horloge du serveur décide si le jeton est expiré ; dans ce cas, le
  /// jeton est renouvelé (Supabase) et l'appel refait une seule fois.
  Future<ResultatApi<CompteServeur>> moi() async {
    final j = await jeton();
    if (j == null) return const EchecApi(ErreurApi.nonConnecte);
    var r = await _getMoi(j);
    final renouveler = this.renouveler;
    if (r is _Refus && r.detail == 'Token expiré' && renouveler != null) {
      final neuf = await renouveler();
      if (neuf == null) return const EchecApi(ErreurApi.sessionExpiree);
      r = await _getMoi(neuf);
    }
    return switch (r) {
      _Refus(:final detail, :final jeton) => EchecApi(
        ErreurApi.jetonRefuse,
        detail: _raison(detail, jeton),
      ),
      _Resultat(:final resultat) => resultat,
    };
  }

  Future<_Reponse> _getMoi(String j) async {
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

sealed class _Reponse {
  const _Reponse();
}

final class _Refus extends _Reponse {
  const _Refus(this.detail, this.jeton);
  final String? detail;
  final String jeton;
}

final class _Resultat extends _Reponse {
  const _Resultat(this.resultat);
  final ResultatApi<CompteServeur> resultat;
}
