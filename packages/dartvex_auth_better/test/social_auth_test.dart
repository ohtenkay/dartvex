import 'dart:convert';

import 'package:dartvex_auth_better/dartvex_auth_better.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('native social token uses the existing session and JWT exchange',
      () async {
    final requests = <http.Request>[];
    final client = BetterAuthClient(
      baseUrl: 'https://app.convex.cloud',
      httpClient: MockClient((request) async {
        requests.add(request);
        expect(request.url.host, 'app.convex.site');
        if (request.url.path == '/api/auth/sign-in/social') {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {
            'provider': 'google',
            'idToken': {'token': 'google-id-token'},
          });
          return http.Response(
              jsonEncode({
                'token': 'session-token',
                'user': {'id': 'user', 'email': 'user@example.com'},
              }),
              200);
        }
        expect(request.url.path, '/api/auth/convex/token');
        expect(request.headers['Authorization'], 'Bearer session-token');
        return http.Response('{"token":"convex-jwt"}', 200);
      }),
    );
    final session = await client.signInSocial(
        provider: 'google', idToken: 'google-id-token');
    expect(session.token, 'convex-jwt');
    expect(session.sessionToken, 'session-token');
    expect(session.userId, 'user');
    expect(session.email, 'user@example.com');
    expect(requests, hasLength(2));
  });

  test('rejected or malformed social login cannot become a session', () async {
    for (final response in [
      http.Response('{"message":"Invalid ID token"}', 401),
      http.Response('{}', 200),
      http.Response('not-json', 200),
      http.Response('[]', 200),
      http.Response(
          '{"code":"INVALID_TOKEN","message":"Invalid ID token"}', 200),
    ]) {
      final client = BetterAuthClient(
        baseUrl: 'https://auth.example.com',
        httpClient: MockClient((_) async => response),
      );
      await expectLater(
          client.signInSocial(provider: 'google', idToken: 'invalid'),
          throwsA(isA<BetterAuthException>()));
    }
  });

  test(
      'account status authenticates both requests and detects linked passwords',
      () async {
    for (final providers in [
      ['google'],
      ['google', 'credential']
    ]) {
      final client = BetterAuthClient(
        baseUrl: 'https://app.convex.cloud',
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.host, 'app.convex.site');
          expect(request.headers['Authorization'], 'Bearer session');
          if (request.url.path == '/api/auth/get-session') {
            return http.Response('{"user":{"emailVerified":true}}', 200);
          }
          expect(request.url.path, '/api/auth/list-accounts');
          return http.Response(
              jsonEncode(providers.map((id) => {'providerId': id}).toList()),
              200);
        }),
      );
      final status = await client.getAccountStatus(sessionToken: 'session');
      expect(status.emailVerified, isTrue);
      expect(status.hasPassword, providers.contains('credential'));
    }
  });

  test('account status preserves expired and transient failures', () async {
    for (final status in [401, 503]) {
      final client = BetterAuthClient(
        baseUrl: 'https://auth.example.com',
        httpClient: MockClient((_) async => http.Response('{}', status)),
      );
      await expectLater(
          client.getAccountStatus(sessionToken: 'session'),
          throwsA(isA<BetterAuthException>()
              .having((e) => e.retryable, 'retryable', status >= 500)));
    }
  });

  test('malformed account responses fail with typed errors', () async {
    for (final bodies in [
      ('null', '[]'),
      ('{"user":{"emailVerified":"true"}}', '[]'),
      ('{"user":{"emailVerified":true}}', '{}'),
      ('{"user":{"emailVerified":true}}', '[null]'),
      ('{"user":{"emailVerified":true}}', '[{"providerId":1}]'),
      ('{"user":{"emailVerified":true}}', 'not-json'),
    ]) {
      final client = BetterAuthClient(
        baseUrl: 'https://auth.example.com',
        httpClient: MockClient((request) async => http.Response(
              request.url.path.endsWith('/get-session') ? bodies.$1 : bodies.$2,
              200,
            )),
      );
      await expectLater(client.getAccountStatus(sessionToken: 'session'),
          throwsA(isA<BetterAuthException>()));
    }
  });
}
