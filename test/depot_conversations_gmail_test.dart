// Classement Gmail des conversations enregistrées : la requête sur la marque
// d'origine (`messages.attachments`, jsonb) doit partir en JSON. Une List
// passée à `contains` devenait un tableau Postgres (`cs.{…}`), refusé par
// PostgREST : l'erreur était avalée et aucun chat n'était classé sous Gmail
// (constaté sur S10+, 2026-10-21).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ia_jarvis/services/conversations/depot_conversations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'https://projet-test.supabase.co';
const _id = '7a1f5c2e-0000-4000-8000-000000000001';

String _jwt() {
  String b64(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final iat = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${b64({'alg': 'ES256'})}.'
      '${b64({'sub': _id, 'iat': iat, 'exp': iat + 3600})}.signature';
}

http.Response _json(Object corps, [int code = 200]) => http.Response(
  jsonEncode(corps),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('un chat dont une réponse a lu des e-mails est classé Gmail', () async {
    final client = SupabaseClient(
      _url,
      'sb_publishable_test',
      httpClient: MockClient((r) async {
        // Comme une vraie réponse HTTP : liée à sa requête (lue par
        // PostgREST).
        final rep = repondre(r);
        return http.Response.bytes(
          rep.bodyBytes,
          rep.statusCode,
          headers: rep.headers,
          request: r,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'ada@exemple.com',
      password: 'motdepasse1',
    );

    final depot = DepotConversationsSupabase(
      client,
      jeton: () async => client.auth.currentSession?.accessToken,
    );
    final liste = await depot.lister();

    expect(filtre, 'cs.[{"type":"origine","source":"gmail"}]');
    expect(
      {for (final c in liste) c.id: c.mail},
      {'c-mail': true, 'c-jarvis': false},
    );
  });
}

String? filtre;

http.Response repondre(http.Request r) {
  switch (r.url.path) {
    case '/auth/v1/token':
      return _json({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'jeton-renouvellement',
        'user': {
          'id': _id,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'ada@exemple.com',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-10-13T10:00:00Z',
        },
      });
    case '/rest/v1/conversations':
      return _json([
        for (final id in ['c-mail', 'c-jarvis'])
          {
            'id': id,
            'title': id,
            'last_message_at': '2026-10-21T04:42:16Z',
            'messages': [
              {'content': '…', 'created_at': '2026-10-21T04:42:16Z'},
            ],
            'conversation_contexts': <Object>[],
          },
      ]);
    case '/rest/v1/messages':
      filtre = r.url.queryParameters['attachments'];
      // Comme PostgREST : un tableau Postgres sur une colonne jsonb
      // est refusé.
      if (filtre != 'cs.[{"type":"origine","source":"gmail"}]') {
        return _json({'message': 'invalid input syntax'}, 400);
      }
      return _json([
        {'conversation_id': 'c-mail'},
      ]);
  }
  return _json({'message': 'inattendu'}, 404);
}
