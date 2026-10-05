import 'dart:convert';

import 'package:dartvex_auth_better/dartvex_auth_better.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('BetterAuthClient.changePassword', () {
    for (final baseUrl in [
      'https://example.convex.cloud',
      'https://example.convex.site/',
    ]) {
      test(
        'uses session bearer authentication and keeps sessions ($baseUrl)',
        () async {
          final client = BetterAuthClient(
            baseUrl: baseUrl,
            httpClient: MockClient((request) async {
              expect(
                request.url.toString(),
                'https://example.convex.site/api/auth/change-password',
              );
              expect(request.method, 'POST');
              expect(request.headers['Authorization'], 'Bearer session-token');
              expect(request.headers['Content-Type'], 'application/json');
              expect(jsonDecode(request.body), {
                'currentPassword': 'OldPass123',
                'newPassword': 'NewPass123',
                'revokeOtherSessions': false,
              });
              return http.Response(
                '{"token":null,"user":{"id":"user-1"}}',
                200,
              );
            }),
          );
          expect(
            await client.changePassword(
              sessionToken: 'session-token',
              currentPassword: 'OldPass123',
              newPassword: 'NewPass123',
            ),
            isNull,
          );
        },
      );
    }

    test('returns the replacement token when revoking sessions', () async {
      final client = BetterAuthClient(
        baseUrl: 'https://example.convex.site',
        httpClient: MockClient((request) async {
          expect(
            (jsonDecode(request.body) as Map)['revokeOtherSessions'],
            true,
          );
          return http.Response('{"token":"replacement-token","user":{}}', 200);
        }),
      );
      expect(
        await client.changePassword(
          sessionToken: 'session-token',
          currentPassword: 'OldPass123',
          newPassword: 'NewPass123',
          revokeOtherSessions: true,
        ),
        'replacement-token',
      );
    });

    for (final status in [200, 400, 401]) {
      test('surfaces Better Auth errors with status $status', () async {
        final client = BetterAuthClient(
          baseUrl: 'https://example.convex.site',
          httpClient: MockClient(
            (_) async => http.Response(
              '{"code":"INVALID_PASSWORD","message":"Invalid password"}',
              status,
            ),
          ),
        );
        await expectLater(
          client.changePassword(
            sessionToken: 'session-token',
            currentPassword: 'wrong',
            newPassword: 'NewPass123',
          ),
          throwsA(
            isA<BetterAuthException>().having(
              (e) => e.message,
              'message',
              contains('Invalid password'),
            ),
          ),
        );
      });
    }

    for (final body in ['<html>Server error</html>', '[]']) {
      test('rejects malformed successful responses: $body', () async {
        final client = BetterAuthClient(
          baseUrl: 'https://example.convex.site',
          httpClient: MockClient((_) async => http.Response(body, 200)),
        );
        await expectLater(
          client.changePassword(
            sessionToken: 'session-token',
            currentPassword: 'OldPass123',
            newPassword: 'NewPass123',
          ),
          throwsA(isA<BetterAuthException>()),
        );
      });
    }

    test(
      'rejects revocation responses missing the replacement token',
      () async {
        final client = BetterAuthClient(
          baseUrl: 'https://example.convex.site',
          httpClient: MockClient(
            (_) async => http.Response('{"token":null,"user":{}}', 200),
          ),
        );
        await expectLater(
          client.changePassword(
            sessionToken: 'session-token',
            currentPassword: 'OldPass123',
            newPassword: 'NewPass123',
            revokeOtherSessions: true,
          ),
          throwsA(isA<BetterAuthException>()),
        );
      },
    );
  });
}
