import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'exceptions.dart';
import 'storage.dart';

/// Lifecycle of a client upload operation.
enum ConvexUploadStatus {
  /// Waiting for the first run.
  queued,

  /// Preparing bytes, authorizing, transferring, or completing the upload.
  uploading,

  /// The response was decoded successfully.
  succeeded,

  /// The run failed; calling [ConvexUpload.run] retries it.
  failed,

  /// The operation was canceled and cannot be restarted.
  canceled,
}

/// Application policy for a failed upload attempt.
enum ConvexUploadRetry {
  /// Surface the failure and wait for an explicit retry.
  stop,

  /// Repeat the attempt with the existing credentials.
  retry,

  /// Discard the credentials and resolve a new request before retrying.
  renewCredentials,
}

/// Immutable state exposed by an upload operation.
class ConvexUploadSnapshot<T> {
  /// Creates a snapshot, initially queued with no progress or result.
  const ConvexUploadSnapshot({
    this.status = ConvexUploadStatus.queued,
    this.bytesSent = 0,
    this.totalBytes = 0,
    this.attempt = 0,
    this.result,
    this.error,
  });

  /// Current lifecycle state.
  final ConvexUploadStatus status;

  /// Bytes handed to the HTTP client in the current attempt.
  ///
  /// This measures client transfer progress, not server acknowledgement.
  final int bytesSent;

  /// Payload size, or zero before bytes are prepared.
  final int totalBytes;

  /// One-based attempt number in the current run, or zero before starting.
  final int attempt;

  /// Decoded result when [status] is [ConvexUploadStatus.succeeded].
  final T? result;

  /// Failure or cancellation reason, otherwise null.
  final Object? error;

  /// Transfer fraction, or null while the payload size is unknown.
  ///
  /// A value of one does not imply server-side completion. Check [status].
  double? get progress => totalBytes == 0 ? null : bytesSent / totalBytes;
}

/// A retryable upload with cached bytes, credentials, and observable state.
///
/// Create with [ConvexStorage.createUpload]. Concurrent [run] calls share one
/// future. Successful operations return their cached result; failed runs retain
/// bytes and credentials for an explicit retry. Automatic retries occur only
/// when the application's policy allows them. Cancellation is terminal.
class ConvexUpload<T> {
  /// Internal constructor used by [ConvexStorage.createUpload].
  @internal
  ConvexUpload.internal({
    required ConvexStorage storage,
    required FutureOr<Uint8List> Function() readBytes,
    required String contentType,
    required FutureOr<ConvexUploadRequest> Function() resolveRequest,
    required FutureOr<T> Function(http.Response response) decodeResponse,
    ConvexUploadRetry Function(Object error, int attempt)? retry,
    int maxAttempts = 2,
    Duration? timeout,
  })  : _storage = storage,
        _readBytes = readBytes,
        _contentType = contentType,
        _resolveRequest = resolveRequest,
        _decodeResponse = decodeResponse,
        _retry = retry,
        _maxAttempts = maxAttempts,
        _timeout = timeout {
    if (maxAttempts < 1) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'Must be positive');
    }
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
  }

  final ConvexStorage _storage;
  final FutureOr<Uint8List> Function() _readBytes;
  final String _contentType;
  final FutureOr<ConvexUploadRequest> Function() _resolveRequest;
  final FutureOr<T> Function(http.Response response) _decodeResponse;
  final ConvexUploadRetry Function(Object error, int attempt)? _retry;
  final int _maxAttempts;
  final Duration? _timeout;
  final _states = StreamController<ConvexUploadSnapshot<T>>.broadcast();
  final _abort = Completer<void>();
  ConvexUploadSnapshot<T> _snapshot = ConvexUploadSnapshot<T>();
  Future<T>? _running;
  Uint8List? _bytes;
  ConvexUploadRequest? _request;
  var _disposed = false;
  var _generation = 0;

  /// Latest state, including updates made before a listener subscribed.
  ConvexUploadSnapshot<T> get snapshot => _snapshot;

  /// State changes; read [snapshot] for the initial state.
  Stream<ConvexUploadSnapshot<T>> get snapshots => _states.stream;

  /// Starts or retries the upload.
  ///
  /// [ConvexStorage.createUpload]'s retry policy controls automatic attempts.
  /// Failed runs throw their original error and also publish a failed snapshot.
  Future<T> run() {
    if (_disposed) return Future.error(StateError('Upload is disposed'));
    if (_abort.isCompleted) {
      return Future.error(const ConvexFileUploadCancelledException());
    }
    if (_snapshot.status == ConvexUploadStatus.succeeded) {
      return Future.value(_snapshot.result as T);
    }
    final running = _running;
    if (running != null) return running;
    // Publish the future before callbacks can reenter run().
    final completion = Completer<T>();
    _running = completion.future;
    unawaited(_execute().then((value) {
      _running = null;
      completion.complete(value);
    }, onError: (Object error, StackTrace stack) {
      _running = null;
      completion.completeError(error, stack);
    }));
    return completion.future;
  }

  Future<T> _execute() async {
    try {
      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        _checkCanceled();
        _emit(ConvexUploadSnapshot<T>(
          status: ConvexUploadStatus.uploading,
          totalBytes: _bytes?.length ?? 0,
          attempt: attempt,
        ));
        final generation = ++_generation;
        try {
          _bytes ??= await _prepareBytes();
          _checkCanceled();
          final result = await _storage.uploadTo<T>(
            bytes: _bytes!,
            contentType: _contentType,
            resolveRequest: () async {
              final request = _request ?? await _resolveRequest();
              if (generation != _generation) {
                throw StateError('Upload attempt is no longer active');
              }
              return _request ??= request;
            },
            decodeResponse: _decodeResponse,
            timeout: _timeout,
            abortTrigger: _abort.future,
            onProgress: (sent, total) {
              if (generation == _generation) {
                _emit(ConvexUploadSnapshot<T>(
                  status: ConvexUploadStatus.uploading,
                  bytesSent: sent,
                  totalBytes: total,
                  attempt: attempt,
                ));
              }
            },
          );
          _checkCanceled();
          _emit(ConvexUploadSnapshot<T>(
            status: ConvexUploadStatus.succeeded,
            bytesSent: _bytes!.length,
            totalBytes: _bytes!.length,
            attempt: attempt,
            result: result,
          ));
          return result;
        } on Object catch (error, stack) {
          _checkCanceled();
          final decision =
              _retry?.call(error, attempt) ?? ConvexUploadRetry.stop;
          _checkCanceled();
          if (decision == ConvexUploadRetry.renewCredentials) _request = null;
          if (decision == ConvexUploadRetry.stop || attempt == _maxAttempts) {
            Error.throwWithStackTrace(error, stack);
          }
        } finally {
          _generation++;
        }
      }
      throw StateError('Upload attempts exhausted');
    } on Object catch (error) {
      if (!_abort.isCompleted) {
        _emit(ConvexUploadSnapshot<T>(
          status: ConvexUploadStatus.failed,
          bytesSent: _snapshot.bytesSent,
          totalBytes: _snapshot.totalBytes,
          attempt: _snapshot.attempt,
          error: error,
        ));
      }
      rethrow;
    }
  }

  Future<Uint8List> _prepareBytes() {
    final preparation = Future.any<Uint8List>([
      Future.sync(_readBytes),
      _abort.future.then<Uint8List>(
        (_) => throw const ConvexFileUploadCancelledException(),
      ),
    ]);
    final timeout = _timeout;
    return timeout == null ? preparation : preparation.timeout(timeout);
  }

  void _checkCanceled() {
    if (_abort.isCompleted) {
      throw const ConvexFileUploadCancelledException();
    }
  }

  void _emit(ConvexUploadSnapshot<T> state) {
    if (_disposed || _abort.isCompleted) return;
    _snapshot = state;
    _states.add(state);
  }

  /// Cancels queued or active work. This operation cannot be restarted.
  ///
  /// Backend work already started cannot be undone. Successful and failed
  /// operations are left unchanged.
  void cancel() {
    if (_disposed ||
        _abort.isCompleted ||
        _snapshot.status == ConvexUploadStatus.succeeded ||
        _snapshot.status == ConvexUploadStatus.failed) {
      return;
    }
    _snapshot = ConvexUploadSnapshot<T>(
      status: ConvexUploadStatus.canceled,
      bytesSent: _snapshot.bytesSent,
      totalBytes: _snapshot.totalBytes,
      attempt: _snapshot.attempt,
      error: const ConvexFileUploadCancelledException(),
    );
    _states.add(_snapshot);
    _abort.complete();
  }

  /// Cancels active work and closes the state stream.
  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    unawaited(_states.close());
  }
}
