import 'dart:async';
import 'dart:typed_data';

import 'package:dartvex/dartvex.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late ConvexClient caller;
  setUp(() {
    caller = ConvexClient(
      'https://unused.convex.cloud',
      config: const ConvexClientConfig(connectImmediately: false),
    );
    addTearDown(caller.close);
  });

  ConvexStorage storage(Future<http.Response> Function(http.Request) handler) =>
      ConvexStorage(caller, httpClient: MockClient(handler));
  ConvexUploadRequest request([String token = 'first']) => ConvexUploadRequest(
        url: Uri.parse('https://example.com/images'),
        headers: {'Authorization': 'Bearer $token'},
      );
  final bytes = Uint8List(150000);

  test('coalesces runs, publishes progress, and caches successful completion',
      () async {
    var reads = 0;
    var resolutions = 0;
    var requests = 0;
    final response = Completer<http.Response>();
    final operation = storage((req) async {
      requests++;
      expect(req.bodyBytes, bytes);
      return response.future;
    }).createUpload<String>(
      readBytes: () {
        reads++;
        return bytes;
      },
      contentType: 'image/jpeg',
      resolveRequest: () {
        resolutions++;
        return request();
      },
      decodeResponse: (response) => response.body,
    );
    addTearDown(operation.dispose);
    expect(operation.snapshot.status, ConvexUploadStatus.queued);
    final states = <ConvexUploadSnapshot<String>>[];
    final subscription = operation.snapshots.listen(states.add);
    addTearDown(subscription.cancel);

    final first = operation.run();
    expect(operation.run(), same(first));
    await Future<void>.delayed(Duration.zero);
    expect(operation.snapshot.status, ConvexUploadStatus.uploading);
    expect(operation.snapshot.progress, 1);
    response.complete(http.Response('photo1', 200));
    expect(await first, 'photo1');
    expect(await operation.run(), 'photo1');
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    expect(resolutions, 1);
    expect(requests, 1);
    expect(operation.snapshot.result, 'photo1');
    expect(states.last.status, ConvexUploadStatus.succeeded);
    expect(
        states.any(
            (s) => s.progress != null && s.progress! > 0 && s.progress! < 1),
        isTrue);
  });

  test(
      'manual retries preserve bytes and credentials without automatic retries',
      () async {
    var reads = 0;
    var resolutions = 0;
    var requests = 0;
    final failure = StateError('Connection lost');
    final operation = storage((_) async {
      if (++requests == 1) throw failure;
      return http.Response('ok', 200);
    }).createUpload<String>(
      readBytes: () {
        reads++;
        return bytes;
      },
      contentType: 'image/jpeg',
      resolveRequest: () {
        resolutions++;
        return request();
      },
      decodeResponse: (response) => response.body,
    );
    addTearDown(operation.dispose);
    await expectLater(operation.run(), throwsA(same(failure)));
    expect(operation.snapshot.status, ConvexUploadStatus.failed);
    expect(operation.snapshot.error, same(failure));
    expect(requests, 1);
    expect(await operation.run(), 'ok');
    expect(reads, 1);
    expect(resolutions, 1);
    expect(operation.snapshot.error, isNull);
  });

  test('renews expired credentials while reusing the prepared payload',
      () async {
    var reads = 0;
    var resolutions = 0;
    final tokens = <String?>[];
    final operation = storage((req) async {
      tokens.add(req.headers['Authorization']);
      return http.Response('ok', tokens.length == 1 ? 410 : 200);
    }).createUpload<String>(
      readBytes: () {
        reads++;
        return bytes;
      },
      contentType: 'image/jpeg',
      resolveRequest: () => request('${++resolutions}'),
      decodeResponse: (response) => response.body,
      retry: (error, _) =>
          error is ConvexFileUploadException && error.statusCode == 410
              ? ConvexUploadRetry.renewCredentials
              : ConvexUploadRetry.stop,
    );
    addTearDown(operation.dispose);
    expect(await operation.run(), 'ok');
    expect(tokens, ['Bearer 1', 'Bearer 2']);
    expect(reads, 1);
    expect(operation.snapshot.attempt, 2);
  });

  test(
      'bounds retries and discards expired credentials even on the final attempt',
      () async {
    var resolutions = 0;
    var requests = 0;
    final operation =
        storage((_) async => http.Response('ok', ++requests <= 2 ? 410 : 200))
            .createUpload<void>(
      readBytes: () => bytes,
      contentType: 'image/jpeg',
      resolveRequest: () => request('${++resolutions}'),
      decodeResponse: (_) {},
      retry: (_, __) => ConvexUploadRetry.renewCredentials,
      maxAttempts: 2,
    );
    addTearDown(operation.dispose);
    await expectLater(
        operation.run(), throwsA(isA<ConvexFileUploadException>()));
    expect(requests, 2);
    expect(operation.snapshot.status, ConvexUploadStatus.failed);
    await operation.run();
    expect(resolutions, 3);
    expect(requests, 3);
  });

  test('retry policy can repeat an attempt without resolving new credentials',
      () async {
    var resolutions = 0;
    var requests = 0;
    final operation =
        storage((_) async => http.Response('ok', ++requests == 1 ? 503 : 200))
            .createUpload<void>(
      readBytes: () => bytes,
      contentType: 'image/jpeg',
      resolveRequest: () {
        resolutions++;
        return request();
      },
      decodeResponse: (_) {},
      retry: (_, __) => ConvexUploadRetry.retry,
    );
    addTearDown(operation.dispose);
    await operation.run();
    expect(requests, 2);
    expect(resolutions, 1);
  });

  test('canceling a queued operation prevents preparation and authorization',
      () async {
    final operation =
        storage((_) async => fail('Must not upload')).createUpload<void>(
      readBytes: () => fail('Must not prepare'),
      contentType: 'image/jpeg',
      resolveRequest: () => fail('Must not authorize'),
      decodeResponse: (_) {},
    );
    addTearDown(operation.dispose);
    operation.cancel();
    await expectLater(
      operation.run(),
      throwsA(isA<ConvexFileUploadCancelledException>()),
    );
    expect(operation.snapshot.status, ConvexUploadStatus.canceled);
  });

  test('canceling preparation prevents late bytes from starting a transfer',
      () async {
    final preparation = Completer<Uint8List>();
    final operation =
        storage((_) async => fail('Must not upload')).createUpload<void>(
      readBytes: () => preparation.future,
      contentType: 'image/jpeg',
      resolveRequest: () => fail('Must not authorize'),
      decodeResponse: (_) {},
    );
    addTearDown(operation.dispose);
    final assertion = expectLater(
      operation.run(),
      throwsA(isA<ConvexFileUploadCancelledException>()),
    );
    operation.cancel();
    await assertion;
    preparation.complete(bytes);
    await Future<void>.delayed(Duration.zero);
    expect(operation.snapshot.status, ConvexUploadStatus.canceled);
  });

  test('disposal cancels active work and ignores late progress and completion',
      () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final operation = storage((_) async {
      started.complete();
      return response.future;
    }).createUpload<void>(
      readBytes: () => bytes,
      contentType: 'image/jpeg',
      resolveRequest: request,
      decodeResponse: (_) => fail('Must not decode a canceled response'),
    );
    final assertion = expectLater(
      operation.run(),
      throwsA(isA<ConvexFileUploadCancelledException>()),
    );
    await started.future;
    operation.dispose();
    await assertion;
    response.complete(http.Response('ok', 200));
    await Future<void>.delayed(Duration.zero);
    expect(operation.snapshot.status, ConvexUploadStatus.canceled);
    await expectLater(operation.run(), throwsStateError);
    operation.dispose();
  });

  test('a timed-out authorization cannot populate the credential cache later',
      () async {
    final late = Completer<ConvexUploadRequest>();
    var resolutions = 0;
    final operation = storage((req) async {
      expect(req.headers['Authorization'], 'Bearer fresh');
      return http.Response('ok', 200);
    }).createUpload<void>(
      readBytes: () => bytes,
      contentType: 'image/jpeg',
      resolveRequest: () => ++resolutions == 1 ? late.future : request('fresh'),
      decodeResponse: (_) {},
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(operation.dispose);
    await expectLater(operation.run(), throwsA(isA<TimeoutException>()));
    expect(operation.snapshot.status, ConvexUploadStatus.failed);
    late.complete(request('obsolete'));
    await Future<void>.delayed(Duration.zero);
    await operation.run();
    expect(resolutions, 2);
    expect(operation.snapshot.status, ConvexUploadStatus.succeeded);
  });

  test('preparation failures can be retried without recreating the operation',
      () async {
    var reads = 0;
    final failure = StateError('File not yet readable');
    final operation =
        storage((_) async => http.Response('ok', 200)).createUpload<void>(
      readBytes: () {
        if (++reads == 1) throw failure;
        return bytes;
      },
      contentType: 'image/jpeg',
      resolveRequest: request,
      decodeResponse: (_) {},
    );
    addTearDown(operation.dispose);
    await expectLater(operation.run(), throwsA(same(failure)));
    await operation.run();
    expect(reads, 2);
  });

  test('waits for application finalization before marking success', () async {
    final finalization = Completer<String>();
    final decoding = Completer<void>();
    final operation =
        storage((_) async => http.Response('ok', 200)).createUpload<String>(
      readBytes: () => bytes,
      contentType: 'image/jpeg',
      resolveRequest: request,
      decodeResponse: (_) {
        decoding.complete();
        return finalization.future;
      },
    );
    addTearDown(operation.dispose);
    final result = operation.run();
    await decoding.future;
    expect(operation.snapshot.progress, 1);
    expect(operation.snapshot.status, ConvexUploadStatus.uploading);
    finalization.complete('attached');
    expect(await result, 'attached');
    expect(operation.snapshot.status, ConvexUploadStatus.succeeded);
  });
}
