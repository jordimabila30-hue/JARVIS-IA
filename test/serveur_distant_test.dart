// Backend hébergé (Render) : choix de l'environnement et réveil du serveur
// endormi, sans message envoyé deux fois.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/authentification/config_auth.dart';

const _id = '7d3c2a1e-0000-4000-8000-000000000001';

http.Response _json(Object corps, [int code = 200]) => http.Response(
  jsonEncode(corps),
  code,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('ConfigAuth : choix du serveur', () {
    test('distant : le serveur hébergé, en HTTPS', () {
      const c = ConfigAuth(serveur: 'distant');
      expect(c.adresseApi.toString(), ConfigAuth.adresseHebergee);
      expect(c.adresseApi.scheme, 'https');
      expect(c.serveurDistant, isTrue);
    });

    test('local : le Docker de l\'ordinateur', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        const ConfigAuth().adresseApi.toString(),
        'http://localhost:8000',
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        const ConfigAuth(serveur: 'local').adresseApi.toString(),
        'http://10.0.2.2:8000',
      );
      expect(const ConfigAuth().serveurDistant, isFalse);
      debugDefaultTargetPlatformOverride = null;
    });

    test('JARVIS_API_URL l\'emporte sur l\'environnement', () {
      const c = ConfigAuth(
        adresseServeur: 'http://127.0.0.1:8000',
        serveur: 'distant',
      );
      expect(c.adresseApi.toString(), 'http://127.0.0.1:8000');
      expect(c.serveurDistant, isFalse);
    });

    test('valeur inconnue : erreur explicite, jamais une adresse devinée', () {
      expect(
        () => const ConfigAuth(serveur: 'render').adresseApi,
        throwsArgumentError,
      );
    });
  });

  group('ApiJarvis : réveil du serveur hébergé', () {
    test('serveur local (veille nulle) : aucune requête de réveil', () async {
      final chemins = <String>[];
      final api = ApiJarvis(
        adresse: Uri.parse('http://localhost:8000'),
        jeton: () async => 'j',
        client: MockClient((r) async {
          chemins.add(r.url.path);
          return _json({'id': _id});
        }),
      );
      await api.moi();
      expect(chemins, ['/me']);
    });

    test('réveil une seule fois, partagé, puis plus jusqu\'à la veille', () async {
      final chemins = <String>[];
      final api = ApiJarvis(
        adresse: Uri.parse(ConfigAuth.adresseHebergee),
        jeton: () async => 'j',
        veille: const Duration(minutes: 10),
        client: MockClient((r) async {
          chemins.add(r.url.path);
          return r.url.path == '/health'
              ? _json({'status': 'ok'})
              : _json({'id': _id});
        }),
      );
      await Future.wait([api.moi(), api.moi()]);
      await api.moi();
      expect(chemins.where((c) => c == '/health'), hasLength(1));
      expect(chemins.where((c) => c == '/me'), hasLength(3));
    });

    test('réveil lent : indicateur visible, puis effacé', () async {
      final health = Completer<http.Response>();
      final api = ApiJarvis(
        adresse: Uri.parse(ConfigAuth.adresseHebergee),
        jeton: () async => 'j',
        veille: const Duration(minutes: 10),
        client: MockClient((r) async {
          if (r.url.path == '/health') return health.future;
          return _json({'id': _id});
        }),
      );
      final appel = api.moi();
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      expect(api.reveilEnCours.value, isTrue);
      health.complete(_json({'status': 'ok'}));
      expect(await appel, isA<SuccesApi<CompteServeur>>());
      expect(api.reveilEnCours.value, isFalse);
    });

    test('réveil impossible : le chat n\'est jamais envoyé', () async {
      final chemins = <String>[];
      final api = ApiJarvis(
        adresse: Uri.parse(ConfigAuth.adresseHebergee),
        jeton: () async => 'j',
        veille: const Duration(minutes: 10),
        delaiReveil: const Duration(milliseconds: 50),
        client: MockClient((r) async {
          chemins.add(r.url.path);
          await Future<void>.delayed(const Duration(seconds: 1));
          return _json({'status': 'ok'});
        }),
      );
      final r = await api.discuter('Bonjour');
      expect((r as EchecApi).type, ErreurApi.delaiDepasse);
      expect(chemins, ['/health']);
      expect(api.reveilEnCours.value, isFalse);
    });

    test('réseau coupé pendant le réveil : injoignable, rien envoyé', () async {
      final chemins = <String>[];
      final api = ApiJarvis(
        adresse: Uri.parse(ConfigAuth.adresseHebergee),
        jeton: () async => 'j',
        veille: const Duration(minutes: 10),
        client: MockClient((r) async {
          chemins.add(r.url.path);
          throw http.ClientException('réseau coupé');
        }),
      );
      final r = await api.discuter('Bonjour');
      expect((r as EchecApi).type, ErreurApi.injoignable);
      expect(chemins, ['/health']);
    });
  });
}
