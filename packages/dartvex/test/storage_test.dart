import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvex/dartvex.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';

/// Minimal fake that implements [ConvexFunctionCaller] for unit tests.
class _FakeCaller implements ConvexFunctionCaller {
  final Map<String, dynamic Function(Map<String, dynamic>)> mutations =
      <String, dynamic Function(Map<String, dynamic>)>{};
  final Map<String, dynamic Function(Map<String, dynamic>)> queries =
      <String, dynamic Function(Map<String, dynamic>)>{};
  final Map<String, dynamic Function(Map<String, dynamic>)> actions =
      <String, dynamic Function(Map<String, dynamic>)>{};

  @override
  Future<dynamic> mutate(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) async {
    return mutations[name]!(args);
  }

  @override
  Future<dynamic> query(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) async {
    return queries[name]!(args);
  }

  @override
  Future<T> queryOnce<T>(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) async {
    final result = await query(name, args);
    return result as T;
  }

  @override
  ConvexSubscription subscribe(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) {
    throw UnimplementedError();
  }

  @override
  ConvexPaginatedQuery paginatedQuery(
    String name,
    Map<String, dynamic> args, {
    int pageSize = 20,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> action(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) async {
    return actions[name]!(args);
  }
}

class _UploadClient extends http.BaseClient {
  _UploadClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);

  @override
  void close() => closed = true;
}

void main() {
  group('ConvexStorage', () {
    test('uploadFile returns storageId on success', () async {
      final caller = _FakeCaller()
        ..mutations['files:generateUploadUrl'] =
            (_) => 'https://upload.convex.cloud/abc123';

      final mockHttp = http_testing.MockClient((request) async {
        expect(request.url.toString(), 'https://upload.convex.cloud/abc123');
        expect(request.headers['Content-Type'], 'image/jpeg');
        return http.Response(
          jsonEncode({'storageId': 'kg2abc123'}),
          200,
        );
      });

      final storage = ConvexStorage(caller, httpClient: mockHttp);
      final storageId = await storage.uploadFile(
        uploadUrlAction: 'files:generateUploadUrl',
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'photo.jpg',
        contentType: 'image/jpeg',
      );

      expect(storageId, 'kg2abc123');
    });

    test('uploadFile passes uploadUrlArgs to mutation', () async {
      Map<String, dynamic>? capturedArgs;
      final caller = _FakeCaller()
        ..mutations['files:generateUploadUrl'] = (args) {
          capturedArgs = args;
          return 'https://upload.convex.cloud/abc123';
        };

      final mockHttp = http_testing.MockClient((_) async {
        return http.Response(jsonEncode({'storageId': 'id1'}), 200);
      });

      final storage = ConvexStorage(caller, httpClient: mockHttp);
      await storage.uploadFile(
        uploadUrlAction: 'files:generateUploadUrl',
        bytes: Uint8List(0),
        filename: 'f.txt',
        contentType: 'text/plain',
        uploadUrlArgs: {'bucket': 'docs'},
      );

      expect(capturedArgs, {'bucket': 'docs'});
    });

    test('uploadFile throws ConvexFileUploadException on non-200', () async {
      final caller = _FakeCaller()
        ..mutations['files:generateUploadUrl'] =
            (_) => 'https://upload.convex.cloud/abc';

      final mockHttp = http_testing.MockClient((_) async {
        return http.Response('File too large', 413);
      });

      final storage = ConvexStorage(caller, httpClient: mockHttp);
      expect(
        () => storage.uploadFile(
          uploadUrlAction: 'files:generateUploadUrl',
          bytes: Uint8List(0),
          filename: 'big.bin',
          contentType: 'application/octet-stream',
        ),
        throwsA(
          isA<ConvexFileUploadException>()
              .having((e) => e.statusCode, 'statusCode', 413)
              .having((e) => e.body, 'body', 'File too large'),
        ),
      );
    });

    test('uploadFile throws typed exception when resolver returns non-string',
        () async {
      final caller = _FakeCaller()
        ..mutations['files:generateUploadUrl'] = (_) => <String, dynamic>{
              'url': 'https://upload.convex.cloud/abc',
            };

      final storage = ConvexStorage(
        caller,
        httpClient: http_testing.MockClient((_) async {
          fail('HTTP upload should not start for an invalid resolver result');
        }),
      );

      await expectLater(
        () => storage.uploadFile(
          uploadUrlAction: 'files:generateUploadUrl',
          bytes: Uint8List(0),
          filename: 'photo.jpg',
          contentType: 'image/jpeg',
        ),
        throwsA(
          isA<ConvexStorageException>().having(
            (error) => error.message,
            'message',
            contains('must return a non-empty string'),
          ),
        ),
      );
    });

    test('uploadFile throws typed exception when resolver URL is invalid',
        () async {
      final caller = _FakeCaller()
        ..mutations['files:generateUploadUrl'] =
            (_) => 'https://upload.convex.cloud/abc';

      for (final uploadUrl in <String>[
        'ftp://upload.convex.cloud/abc',
        'https:///missing-host',
      ]) {
        caller.mutations['files:generateUploadUrl'] = (_) => uploadUrl;
        final storage = ConvexStorage(
          caller,
          httpClient: http_testing.MockClient((_) async {
            fail('HTTP upload should not start for $uploadUrl');
          }),
        );

        await expectLater(
          () => storage.uploadFile(
            uploadUrlAction: 'files:generateUploadUrl',
            bytes: Uint8List(0),
            filename: 'photo.jpg',
            contentType: 'image/jpeg',
          ),
          throwsA(isA<ConvexStorageException>()),
        );
      }
    });

    test('uploadFile throws typed exception on malformed success body',
        () async {
      final caller = _FakeCaller()
        ..mutations['files:generateUploadUrl'] =
            (_) => 'https://upload.convex.cloud/abc';

      for (final body in <String>[
        '',
        jsonEncode(<String>[]),
        jsonEncode(<String, dynamic>{}),
        jsonEncode(<String, dynamic>{'storageId': 42}),
        jsonEncode(<String, dynamic>{'storageId': ''}),
      ]) {
        final storage = ConvexStorage(
          caller,
          httpClient: http_testing.MockClient((_) async {
            return http.Response(body, 200);
          }),
        );

        await expectLater(
          () => storage.uploadFile(
            uploadUrlAction: 'files:generateUploadUrl',
            bytes: Uint8List(0),
            filename: 'photo.jpg',
            contentType: 'image/jpeg',
          ),
          throwsA(
            isA<ConvexFileUploadException>().having(
              (error) => error.statusCode,
              'statusCode',
              200,
            ),
          ),
        );
      }
    });

    group('uploadTo', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      ConvexUploadRequest target() => ConvexUploadRequest(
            url: Uri.parse('https://example.com/images'),
            method: 'PUT',
            headers: {'Authorization': 'Bearer ticket'},
          );

      test('resolves a typed request and decodes a custom 201 response',
          () async {
        var resolutions = 0;
        final client = http_testing.MockClient((request) async {
          expect(request.url, Uri.parse('https://example.com/images'));
          expect(request.method, 'PUT');
          expect(request.headers['Authorization'], 'Bearer ticket');
          expect(request.headers['Content-Type'], 'image/jpeg');
          expect(request.bodyBytes, bytes);
          return http.Response('{"photoId":"photo1"}', 201);
        });
        final result = await ConvexStorage(_FakeCaller(), httpClient: client)
            .uploadTo<String>(
          bytes: bytes,
          contentType: 'image/jpeg',
          resolveRequest: () async {
            resolutions++;
            return target();
          },
          decodeResponse: (response) async => (jsonDecode(response.body)
              as Map<String, dynamic>)['photoId'] as String,
        );
        expect(result, 'photo1');
        expect(resolutions, 1);
      });

      test('returns typed HTTP failures without decoding or retrying',
          () async {
        var requests = 0;
        final storage = ConvexStorage(
          _FakeCaller(),
          httpClient: http_testing.MockClient((_) async {
            requests++;
            return http.Response('Upload expired', 410);
          }),
        );
        await expectLater(
          storage.uploadTo<void>(
            bytes: bytes,
            contentType: 'image/jpeg',
            resolveRequest: target,
            decodeResponse: (_) => fail('Must not decode an HTTP failure'),
          ),
          throwsA(isA<ConvexFileUploadException>()
              .having((error) => error.statusCode, 'statusCode', 410)
              .having((error) => error.body, 'body', 'Upload expired')),
        );
        expect(requests, 1);
      });

      test('rejects invalid endpoints before sending bytes', () async {
        final storage = ConvexStorage(
          _FakeCaller(),
          httpClient: http_testing.MockClient(
            (_) async => fail('Must not send bytes to an invalid endpoint'),
          ),
        );
        for (final url in ['ftp://example.com/file', '/relative']) {
          await expectLater(
            storage.uploadTo<void>(
              bytes: bytes,
              contentType: 'image/jpeg',
              resolveRequest: () => ConvexUploadRequest(url: Uri.parse(url)),
              decodeResponse: (_) {},
            ),
            throwsA(isA<ConvexStorageException>()),
          );
        }
      });

      test('preserves callback failures', () async {
        final failure = StateError('Application failure');
        final storage = ConvexStorage(
          _FakeCaller(),
          httpClient: http_testing.MockClient(
            (_) async => http.Response('ok', 200),
          ),
        );
        await expectLater(
          storage.uploadTo<void>(
            bytes: bytes,
            contentType: 'image/jpeg',
            resolveRequest: () => throw failure,
            decodeResponse: (_) {},
          ),
          throwsA(same(failure)),
        );
        await expectLater(
          storage.uploadTo<void>(
            bytes: bytes,
            contentType: 'image/jpeg',
            resolveRequest: target,
            decodeResponse: (_) => throw failure,
          ),
          throwsA(same(failure)),
        );
      });

      test('cancels while credentials are resolving without sending bytes',
          () async {
        final credentials = Completer<ConvexUploadRequest>();
        final cancel = Completer<void>();
        final storage = ConvexStorage(
          _FakeCaller(),
          httpClient: http_testing.MockClient(
            (_) async => fail('Canceled upload must not send bytes'),
          ),
        );
        final operation = storage.uploadTo<void>(
          bytes: bytes,
          contentType: 'image/jpeg',
          resolveRequest: () => credentials.future,
          decodeResponse: (_) {},
          abortTrigger: cancel.future,
        );
        final assertion = expectLater(
          operation,
          throwsA(isA<ConvexFileUploadCancelledException>()),
        );
        cancel.complete();
        await assertion;
        credentials.complete(target());
        await Future<void>.delayed(Duration.zero);
      });

      test('aborts an active transfer on cancellation', () async {
        final started = Completer<void>();
        final aborted = Completer<void>();
        final cancel = Completer<void>();
        final client = _UploadClient((request) async {
          started.complete();
          await (request as http.Abortable).abortTrigger;
          aborted.complete();
          throw http.RequestAbortedException(request.url);
        });
        final operation =
            ConvexStorage(_FakeCaller(), httpClient: client).uploadTo<void>(
          bytes: bytes,
          contentType: 'image/jpeg',
          resolveRequest: target,
          decodeResponse: (_) => fail('Canceled response must not be decoded'),
          abortTrigger: cancel.future,
        );
        final assertion = expectLater(
          operation,
          throwsA(isA<ConvexFileUploadCancelledException>()),
        );
        await started.future;
        cancel.complete();
        await assertion;
        await aborted.future;
        expect(client.closed, isFalse,
            reason: 'Injected clients are caller-owned');
      });

      test('times out credential resolution without a late upload', () async {
        final credentials = Completer<ConvexUploadRequest>();
        await expectLater(
          ConvexStorage(
            _FakeCaller(),
            httpClient: http_testing.MockClient(
              (_) async => fail('Timed-out upload must not send bytes'),
            ),
          ).uploadTo<void>(
            bytes: bytes,
            contentType: 'image/jpeg',
            resolveRequest: () => credentials.future,
            decodeResponse: (_) {},
            timeout: const Duration(milliseconds: 10),
          ),
          throwsA(isA<TimeoutException>()),
        );
        credentials.complete(target());
        await Future<void>.delayed(Duration.zero);
      });

      test('timeout aborts the transfer and closes an owned client', () async {
        final aborted = Completer<void>();
        final client = _UploadClient((request) async {
          await (request as http.Abortable).abortTrigger;
          aborted.complete();
          throw http.RequestAbortedException(request.url);
        });
        final previousFactory = defaultHttpClientFactory;
        defaultHttpClientFactory = () => client;
        addTearDown(() => defaultHttpClientFactory = previousFactory);
        await expectLater(
          ConvexStorage(_FakeCaller()).uploadTo<void>(
            bytes: bytes,
            contentType: 'image/jpeg',
            resolveRequest: target,
            decodeResponse: (_) {},
            timeout: const Duration(milliseconds: 10),
          ),
          throwsA(isA<TimeoutException>()),
        );
        await aborted.future;
        await Future<void>.delayed(Duration.zero);
        expect(client.closed, isTrue);
      });

      test('closes owned clients on success and leaves injected clients open',
          () async {
        _UploadClient createClient() => _UploadClient(
              (_) async => http.StreamedResponse(Stream.value([1]), 200),
            );
        final injected = createClient();
        final owned = createClient();
        final previousFactory = defaultHttpClientFactory;
        defaultHttpClientFactory = () => owned;
        addTearDown(() => defaultHttpClientFactory = previousFactory);
        for (final storage in [
          ConvexStorage(_FakeCaller()),
          ConvexStorage(_FakeCaller(), httpClient: injected),
        ]) {
          await storage.uploadTo<int>(
            bytes: bytes,
            contentType: 'image/jpeg',
            resolveRequest: target,
            decodeResponse: (response) => response.bodyBytes.single,
          );
        }
        expect(owned.closed, isTrue);
        expect(injected.closed, isFalse);
      });
    });

    test('getFileUrl returns URL from query', () async {
      final caller = _FakeCaller()
        ..queries['files:getUrl'] = (args) {
          expect(args['storageId'], 'kg2abc123');
          return 'https://cdn.convex.cloud/file/kg2abc123';
        };

      final storage = ConvexStorage(caller);
      final url = await storage.getFileUrl(
        getUrlAction: 'files:getUrl',
        storageId: 'kg2abc123',
      );

      expect(url, 'https://cdn.convex.cloud/file/kg2abc123');
    });

    test('getFileUrl returns URL from action when requested', () async {
      final caller = _FakeCaller()
        ..actions['files:getUrl'] = (args) {
          expect(args['storageId'], 'kg2abc123');
          return 'https://cdn.convex.cloud/file/kg2abc123';
        };

      final storage = ConvexStorage(caller);
      final url = await storage.getFileUrl(
        getUrlAction: 'files:getUrl',
        storageId: 'kg2abc123',
        useAction: true,
      );

      expect(url, 'https://cdn.convex.cloud/file/kg2abc123');
    });

    test('getFileUrl throws ConvexStorageException when resolver returns null',
        () async {
      final caller = _FakeCaller()..queries['files:getUrl'] = (_) => null;

      final storage = ConvexStorage(caller);

      expect(
        () => storage.getFileUrl(
          getUrlAction: 'files:getUrl',
          storageId: 'missing',
        ),
        throwsA(
          isA<ConvexStorageException>().having(
            (error) => error.message,
            'message',
            contains('No URL returned for storageId missing'),
          ),
        ),
      );
    });
  });
}
