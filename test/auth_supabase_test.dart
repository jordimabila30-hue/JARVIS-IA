// Authentification Supabase : traduction des réponses réelles de Supabase
// Auth et de la table public.users en résultats JARVIS. Aucun réseau : un
// faux serveur HTTP répond comme Supabase (mêmes chemins, mêmes formats).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/models/authentification/profil_compte.dart';
import 'package:ia_jarvis/models/authentification/resultat_auth.dart';
import 'package:ia_jarvis/models/authentification/utilisateur_auth.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/authentification/auth_repository.dart';
import 'package:ia_jarvis/services/authentification/auth_repository_supabase.dart';
import 'package:ia_jarvis/services/authentification/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'https://projet-test.supabase.co';
const _id = '7a1f5c2e-0000-4000-8000-000000000001';

Map<String, dynamic> _user({String email = 'ada@exemple.com', String? nom}) => {
  'id': _id,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': email,
  'app_metadata': <String, dynamic>{},
  'user_metadata': {'display_name': ?nom},
  'created_at': '2026-10-13T10:00:00Z',
};

/// Jeton de la forme d'un JWT Supabase (non signé : seul le serveur
/// vérifie la signature) ; [etiquette] permet de le reconnaître.
String _jwt(String etiquette, int expireDans) {
  String b64(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + expireDans;
  return '${b64({'alg': 'ES256'})}.'
      '${b64({'sub': _id, 'exp': exp, 'etiquette': etiquette})}.signature';
}

/// Étiquette d'un jeton émis par [_jwt].
String? _etiquette(String? jeton) {
  if (jeton == null) return null;
  final partie = base64Url.normalize(jeton.split('.')[1]);
  return (jsonDecode(utf8.decode(base64Url.decode(partie))) as Map)['etiquette']
      as String;
}

Map<String, dynamic> _session({
  String? nom,
  int expireDans = 3600,
  String etiquette = 'acces',
}) => {
  'access_token': _jwt(etiquette, expireDans),
  'token_type': 'bearer',
  'expires_in': expireDans,
  'refresh_token': 'jeton-renouvellement',
  'user': _user(nom: nom),
};

Map<String, dynamic> _ligne({String? nom = 'Ada'}) => {
  'id': _id,
  'email': 'ada@exemple.com',
  'display_name': nom,
  'avatar_url': null,
  'plan': 'free',
  'daily_message_limit': 30,
  'daily_token_limit': 50000,
  'created_at': '2026-10-13T10:00:00Z',
};

http.Response _json(Object corps, [int code = 200]) => http.Response(
  jsonEncode(corps),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _erreur(int code, String erreur) =>
    _json({'error_code': erreur, 'msg': 'message du serveur'}, code);

/// Faux Supabase : chaque requête est notée, la réponse vient de [repondre].
class _Serveur {
  _Serveur(this.repondre);

  http.Response Function(http.Request r) repondre;
  final requetes = <http.Request>[];

  late final client = MockClient((r) async {
    requetes.add(r);
    final rep = repondre(r);
    // Comme une vraie réponse HTTP : liée à sa requête.
    return http.Response.bytes(
      rep.bodyBytes,
      rep.statusCode,
      headers: rep.headers,
      request: r,
    );
  });

  Iterable<String> get chemins => requetes.map((r) => r.url.path);
}

void main() {
  late _Serveur serveur;
  late SupabaseClient client;
  late AuthRepositorySupabase depot;
  var cree = false;

  AuthRepositorySupabase creer(http.Response Function(http.Request) rep) {
    serveur = _Serveur(rep);
    client = SupabaseClient(
      _url,
      'sb_publishable_test',
      httpClient: serveur.client,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    cree = true;
    return depot = AuthRepositorySupabase(client);
  }

  tearDown(() async {
    if (!cree) return;
    cree = false;
    await depot.fermer();
    await client.dispose();
  });

  Future<void> seConnecter() async {
    final r = await depot.connecter(
      email: 'ada@exemple.com',
      motDePasse: 'motdepasse1',
    );
    expect(r, isA<SuccesAuth<UtilisateurAuth>>());
  }

  group('connexion', () {
    test('succès : utilisateur, jeton, clé publique seulement', () async {
      creer((r) => _json(_session(nom: 'Ada')));
      final r = await depot.connecter(
        email: 'ada@exemple.com',
        motDePasse: 'motdepasse1',
      );
      final u = (r as SuccesAuth<UtilisateurAuth>).valeur;
      expect(u.identifiant, _id);
      expect(u.email, 'ada@exemple.com');
      expect(u.nom, 'Ada');
      final requete = serveur.requetes.single;
      expect(requete.url.path, '/auth/v1/token');
      expect(requete.url.queryParameters['grant_type'], 'password');
      expect(requete.headers['apikey'], 'sb_publishable_test');
      expect(_etiquette(await depot.jetonAcces()), 'acces');
    });

    test('erreurs traduites (jamais le message brut du serveur)', () async {
      for (final (code, erreur, attendu) in const [
        (400, 'invalid_credentials', TypeErreurAuth.identifiantsInvalides),
        (400, 'email_not_confirmed', TypeErreurAuth.emailNonConfirme),
        (429, 'over_request_rate_limit', TypeErreurAuth.tropDeTentatives),
      ]) {
        creer((r) => _erreur(code, erreur));
        final r = await depot.connecter(email: 'a@b.fr', motDePasse: 'x');
        final e = (r as EchecAuth).erreur;
        expect(e.type, attendu, reason: erreur);
        expect(e.message, isNot(contains('message du serveur')));
        await depot.fermer();
        await client.dispose();
      }
      creer((r) => throw http.ClientException('hors ligne'));
    });

    test('serveur injoignable : erreur réseau', () async {
      creer((r) => throw http.ClientException('hors ligne'));
      final r = await depot.connecter(email: 'a@b.fr', motDePasse: 'x');
      expect((r as EchecAuth).erreur.type, TypeErreurAuth.reseau);
    });
  });

  group('inscription', () {
    test('nom transmis au déclencheur (display_name)', () async {
      creer((r) => _json(_session(nom: 'Ada Lovelace')));
      final r = await depot.inscrire(
        const DemandeInscription(
          nom: 'Ada Lovelace',
          email: 'ada@exemple.com',
          motDePasse: 'motdepasse1',
        ),
      );
      expect(r, isA<SuccesAuth<UtilisateurAuth>>());
      final corps = jsonDecode(serveur.requetes.single.body) as Map;
      expect(serveur.requetes.single.url.path, '/auth/v1/signup');
      expect(corps['data'], {'display_name': 'Ada Lovelace'});
      expect(corps['email'], 'ada@exemple.com');
    });

    test('confirmation e-mail exigée : compte créé, aucune session', () async {
      creer((r) => _json(_user()));
      final r = await depot.inscrire(
        const DemandeInscription(
          nom: 'Ada',
          email: 'ada@exemple.com',
          motDePasse: 'motdepasse1',
        ),
      );
      expect((r as EchecAuth).erreur.type, TypeErreurAuth.confirmationEnvoyee);
      expect(await depot.jetonAcces(), isNull);
    });

    test('adresse déjà inscrite (réponse masquée de Supabase)', () async {
      creer((r) => _json({..._user(), 'identities': <Object>[]}));
      final r = await depot.inscrire(
        const DemandeInscription(nom: 'Ada', email: 'a@b.fr', motDePasse: 'x'),
      );
      expect((r as EchecAuth).erreur.type, TypeErreurAuth.emailDejaUtilise);
    });

    test('mot de passe trop faible, adresse existante', () async {
      creer((r) => _erreur(422, 'weak_password'));
      var r = await depot.inscrire(
        const DemandeInscription(nom: 'A', email: 'a@b.fr', motDePasse: '1'),
      );
      expect((r as EchecAuth).erreur.type, TypeErreurAuth.motDePasseFaible);
      serveur.repondre = (r) => _erreur(422, 'user_already_exists');
      r = await depot.inscrire(
        const DemandeInscription(nom: 'A', email: 'a@b.fr', motDePasse: '1'),
      );
      expect((r as EchecAuth).erreur.type, TypeErreurAuth.emailDejaUtilise);
    });
  });

  group('session, profil, récupération', () {
    test('profil lu dans public.users (sa propre ligne)', () async {
      creer(
        (r) => r.url.path == '/rest/v1/users'
            ? _json([_ligne()])
            : _json(_session()),
      );
      await seConnecter();
      final r = await depot.lireProfil();
      final p = (r as SuccesAuth<ProfilCompte>).valeur;
      expect(p.nom, 'Ada');
      expect(p.offre, OffreCompte.gratuite);
      expect(p.limiteMessagesJour, 30);
      final lecture = serveur.requetes.last;
      expect(lecture.method, 'GET');
      expect(lecture.url.queryParameters['id'], 'eq.$_id');
      expect(
        _etiquette(lecture.headers['Authorization']!.substring(7)),
        'acces',
      );
    });

    test('profil absent : erreur claire, rien d’inventé', () async {
      creer(
        (r) => r.url.path == '/rest/v1/users' ? _json([]) : _json(_session()),
      );
      await seConnecter();
      final r = await depot.lireProfil();
      expect((r as EchecAuth).erreur.message, contains('introuvable'));
    });

    test('nom modifié : seule la colonne display_name', () async {
      creer(
        // PATCH … maybeSingle : PostgREST renvoie un objet (en-tête
        // application/vnd.pgrst.object+json).
        (r) => r.url.path == '/rest/v1/users'
            ? _json(_ligne(nom: 'Ada L.'))
            : _json(_session()),
      );
      await seConnecter();
      final r = await depot.modifierProfil(nom: 'Ada L.');
      expect((r as SuccesAuth<ProfilCompte>).valeur.nom, 'Ada L.');
      final maj = serveur.requetes.last;
      expect(maj.method, 'PATCH');
      expect(jsonDecode(maj.body), {'display_name': 'Ada L.'});
    });

    test('sans session : profil refusé, aucune requête', () async {
      creer((r) => _json(_session()));
      final r = await depot.lireProfil();
      expect((r as EchecAuth).erreur.type, TypeErreurAuth.sessionExpiree);
      expect(serveur.requetes, isEmpty);
    });

    test('restauration : rien à restaurer sans session', () async {
      creer((r) => _json(_session()));
      final r = await depot.restaurerSession();
      expect((r as SuccesAuth).valeur, isNull);
      expect(serveur.requetes, isEmpty);
    });

    test(
      'restauration : vérifiée par le serveur ; refusée → effacée',
      () async {
        creer(
          (r) => r.url.path == '/auth/v1/user'
              ? _json(_user(nom: 'Ada'))
              : _json(_session()),
        );
        await seConnecter();
        var r = await depot.restaurerSession();
        expect((r as SuccesAuth<UtilisateurAuth?>).valeur!.identifiant, _id);
        expect(serveur.chemins.last, '/auth/v1/user');
        // Session révoquée côté serveur.
        serveur.repondre = (r) => r.url.path == '/auth/v1/user'
            ? _erreur(403, 'session_not_found')
            : _json({});
        r = await depot.restaurerSession();
        expect((r as EchecAuth).erreur.type, TypeErreurAuth.sessionExpiree);
        expect(await depot.jetonAcces(), isNull);
      },
    );

    test(
      'restauration hors ligne : la session gardée reste utilisable',
      () async {
        creer((r) => _json(_session()));
        await seConnecter();
        serveur.repondre = (r) => throw http.ClientException('hors ligne');
        final r = await depot.restaurerSession();
        expect((r as SuccesAuth<UtilisateurAuth?>).valeur!.identifiant, _id);
      },
    );

    test('jeton bientôt expiré : renouvelé avant l’appel', () async {
      creer(
        (r) => r.url.queryParameters['grant_type'] == 'refresh_token'
            ? _json(_session(etiquette: 'neuf'))
            : _json(_session(expireDans: 20)),
      );
      await seConnecter();
      expect(_etiquette(await depot.jetonAcces()), 'neuf');
    });

    test('récupération du mot de passe : demande envoyée', () async {
      creer((r) => _json({}));
      final r = await depot.demanderRecuperation('ada@exemple.com');
      expect(r, isA<SuccesAuth<void>>());
      expect(serveur.requetes.single.url.path, '/auth/v1/recover');
    });

    test('déconnexion : session effacée, événement émis', () async {
      creer(
        (r) => r.url.path == '/auth/v1/logout'
            ? http.Response('', 204)
            : _json(_session()),
      );
      await seConnecter();
      final evenements = <UtilisateurAuth?>[];
      final abonnement = depot.changements.listen(evenements.add);
      final r = await depot.deconnecter();
      expect(r, isA<SuccesAuth<void>>());
      expect(await depot.jetonAcces(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(evenements.last, isNull);
      await abonnement.cancel();
    });
  });

  test('AuthService : profil chargé puis oublié à la déconnexion', () async {
    creer(
      (r) => switch (r.url.path) {
        '/rest/v1/users' => _json([_ligne()]),
        '/auth/v1/logout' => http.Response('', 204),
        _ => _json(_session(nom: 'Ada')),
      },
    );
    final service = AuthService(depot);
    await service.connecter(email: 'ada@exemple.com', motDePasse: 'secret12');
    expect(service.connecte, isTrue);
    await service.chargerProfil();
    expect(service.profil!.nom, 'Ada');
    expect(_etiquette(await service.jetonAcces()), 'acces');
    await service.deconnecter();
    expect(service.connecte, isFalse);
    expect(service.profil, isNull);
    service.dispose();
  });

  group('ApiJarvis (backend FastAPI)', () {
    test('GET /me avec le jeton : compte reconnu', () async {
      final requetes = <http.Request>[];
      final api = ApiJarvis(
        adresse: Uri.parse('http://localhost:8000'),
        jeton: () async => 'jeton-acces',
        client: MockClient((r) async {
          requetes.add(r);
          return _json({'id': _id, 'email': 'ada@exemple.com'});
        }),
      );
      final r = await api.moi();
      expect((r as SuccesApi<CompteServeur>).valeur.identifiant, _id);
      expect(requetes.single.url.toString(), 'http://localhost:8000/me');
      expect(requetes.single.headers['Authorization'], 'Bearer jeton-acces');
    });

    test('sans session, jeton refusé, serveur arrêté', () async {
      ApiJarvis api(String? jeton, http.Response Function() rep) => ApiJarvis(
        adresse: Uri.parse('http://10.0.2.2:8000'),
        jeton: () async => jeton,
        client: MockClient((r) async => rep()),
      );
      expect(
        (await api(null, () => _json({})).moi() as EchecApi).type,
        ErreurApi.nonConnecte,
      );
      expect(
        (await api('x', () => _json({'detail': 'x'}, 401)).moi() as EchecApi)
            .type,
        ErreurApi.jetonRefuse,
      );
      expect(
        (await api('x', () => throw http.ClientException('refusée')).moi()
                as EchecApi)
            .type,
        ErreurApi.injoignable,
      );
    });
  });
}
