import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'client.dart';
import 'exceptions.dart';
import 'logging.dart';
import 'transport/http_factory.dart';
import 'upload_operation.dart';

/// Describes an upload endpoint and its per-request authorization.
class ConvexUploadRequest {
  /// Creates an upload request, using POST unless [method] is specified.
  ConvexUploadRequest({
    required this.url,
    this.method = 'POST',
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers);

  /// Absolute HTTP or HTTPS endpoint that receives the file bytes.
  final Uri url;

  /// HTTP method accepted by the endpoint, for example POST or PUT.
  final String method;

  /// Additional headers, such as a short-lived bearer credential.
  ///
  /// The upload's content type is set separately by [ConvexStorage.uploadTo].
  final Map<String, String> headers;
}

/// Helper for uploading and downloading files via Convex storage.
///
/// Convex file storage works in two steps:
/// 1. Call a mutation to get a signed upload URL
/// 2. POST file bytes to that URL
///
/// ```dart
/// final storage = ConvexStorage(client);
/// final storageId = await storage.uploadFile(
///   uploadUrlAction: 'files:generateUploadUrl',
///   bytes: fileBytes,
///   filename: 'photo.jpg',
///   contentType: 'image/jpeg',
/// );
/// ```
class ConvexStorage {
  /// Creates a [ConvexStorage] helper backed by the given [caller].
  ///
  /// An optional [httpClient] can be provided for testing or custom
  /// configuration. If omitted, a default [http.Client] is used.
  ConvexStorage(this.caller, {http.Client? httpClient})
      : _httpClient = httpClient;

  /// The function caller used to invoke Convex mutations and queries.
  final ConvexFunctionCaller caller;
  final http.Client? _httpClient;

  /// Upload a file to Convex storage.
  ///
  /// 1. Calls [uploadUrlAction] (a Convex mutation) to get a signed upload URL.
  /// 2. POSTs [bytes] to that URL with the given [contentType].
  /// 3. Returns the `storageId` from the response.
  ///
  /// Throws [ConvexFileUploadException] if the upload HTTP request fails.
  Future<String> uploadFile({
    required String uploadUrlAction,
    required Uint8List bytes,
    required String filename,
    required String contentType,
    Map<String, dynamic>? uploadUrlArgs,
  }) async {
    _log(
      DartvexLogLevel.debug,
      'Starting file upload',
      data: <String, Object?>{
        'uploadUrlAction': uploadUrlAction,
        'filename': filename,
        'contentType': contentType,
        'sizeBytes': bytes.length,
      },
    );
    return uploadTo<String>(
      bytes: bytes,
      contentType: contentType,
      resolveRequest: () async {
        final uploadUrl = await caller.mutate(
          uploadUrlAction,
          uploadUrlArgs ?? const <String, dynamic>{},
        );
        return ConvexUploadRequest(
          url: _parseUploadUri(uploadUrlAction, uploadUrl),
        );
      },
      decodeResponse: _decodeUploadResponse,
    );
  }

  /// Creates a complete client upload operation without starting it.
  ///
  /// [readBytes] prepares the payload once; successful preparation is cached.
  /// [resolveRequest] can call a generated mutation executor to get credentials,
  /// which are reused across attempts and manual retries until [retry] returns
  /// [ConvexUploadRetry.renewCredentials]. [decodeResponse] completes a
  /// successful HTTP response and can call an application finalization mutation.
  ///
  /// [retry] decides which failures may be repeated safely. The default stops
  /// on every failure. [maxAttempts] bounds attempts per [ConvexUpload.run].
  /// [timeout] limits byte preparation and each authorized transfer separately.
  /// The operation exposes state and progress and owns cancellation. Dispose it
  /// when its UI owner is removed.
  ConvexUpload<T> createUpload<T>({
    required FutureOr<Uint8List> Function() readBytes,
    required String contentType,
    required FutureOr<ConvexUploadRequest> Function() resolveRequest,
    required FutureOr<T> Function(http.Response response) decodeResponse,
    ConvexUploadRetry Function(Object error, int attempt)? retry,
    int maxAttempts = 2,
    Duration? timeout,
  }) =>
      ConvexUpload<T>.internal(
        storage: this,
        readBytes: readBytes,
        contentType: contentType,
        resolveRequest: resolveRequest,
        decodeResponse: decodeResponse,
        retry: retry,
        maxAttempts: maxAttempts,
        timeout: timeout,
      );

  /// Uploads bytes using an application-defined endpoint and response format.
  ///
  /// [resolveRequest] can call a generated mutation executor to obtain upload
  /// credentials. [decodeResponse] interprets a successful (2xx) HTTP response.
  /// Non-2xx responses throw [ConvexFileUploadException]; failures in either
  /// callback propagate unchanged.
  ///
  /// [timeout] covers request resolution, HTTP transfer, and response decoding.
  /// Expiry throws [TimeoutException] and aborts an active HTTP request.
  /// Completing [abortTrigger] cancels the operation with
  /// [ConvexFileUploadCancelledException]. It must complete without an error.
  /// Cancellation requires an abort-capable HTTP client to stop the transfer;
  /// callbacks and backend work already started cannot be undone.
  /// [onProgress] reports bytes handed to the HTTP client, not server receipt.
  ///
  /// Requests are sent once. Credential renewal and retry policy belong to the
  /// caller, which knows whether repeating an upload is safe.
  Future<T> uploadTo<T>({
    required Uint8List bytes,
    required String contentType,
    required FutureOr<ConvexUploadRequest> Function() resolveRequest,
    required FutureOr<T> Function(http.Response response) decodeResponse,
    Duration? timeout,
    Future<void>? abortTrigger,
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) async {
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
    final abort = Completer<void>();
    var finished = false;
    void cancel() {
      if (!finished && !abort.isCompleted) abort.complete();
    }

    if (abortTrigger != null) {
      unawaited(abortTrigger.then((_) => cancel()));
    }

    Future<T> transfer() async {
      final target = await resolveRequest();
      if (abort.isCompleted) {
        throw const ConvexFileUploadCancelledException();
      }
      if ((target.url.scheme != 'https' && target.url.scheme != 'http') ||
          target.url.host.isEmpty) {
        throw const ConvexStorageException(
          'Upload endpoint must be an absolute HTTP or HTTPS URL',
        );
      }
      final request = _ProgressUploadRequest(
        target.method,
        target.url,
        abortTrigger: abort.future,
        onProgress: onProgress,
      )
        ..headers.addAll(target.headers)
        ..headers['Content-Type'] = contentType
        ..bodyBytes = bytes;
      _log(
        DartvexLogLevel.debug,
        'Starting HTTP file upload',
        data: <String, Object?>{
          'method': target.method,
          'contentType': contentType,
          'sizeBytes': bytes.length,
        },
      );
      onProgress?.call(0, bytes.length);
      final client = _httpClient ?? createDefaultHttpClient();
      try {
        final response =
            await http.Response.fromStream(await client.send(request));
        if (abort.isCompleted) {
          throw const ConvexFileUploadCancelledException();
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          _log(
            DartvexLogLevel.error,
            'File upload failed',
            data: <String, Object?>{'statusCode': response.statusCode},
          );
          throw ConvexFileUploadException(response.statusCode, response.body);
        }
        final result = await decodeResponse(response);
        if (abort.isCompleted) {
          throw const ConvexFileUploadCancelledException();
        }
        _log(DartvexLogLevel.debug, 'File upload succeeded');
        return result;
      } on http.RequestAbortedException {
        throw const ConvexFileUploadCancelledException();
      } finally {
        if (_httpClient == null) client.close();
      }
    }

    try {
      final operation = Future.any<T>([
        transfer(),
        abort.future.then<T>(
          (_) => throw const ConvexFileUploadCancelledException(),
        ),
      ]);
      if (timeout == null) return await operation;
      return await operation.timeout(timeout, onTimeout: () {
        cancel();
        throw TimeoutException('File upload timed out', timeout);
      });
    } finally {
      finished = true;
    }
  }

  /// Get a download URL for a stored file.
  ///
  /// Calls [getUrlAction] with the given [storageId] and returns the signed
  /// download URL. By default this uses a Convex query; set [useAction] to
  /// true when the backend resolver is an action.
  Future<String> getFileUrl({
    required String getUrlAction,
    required String storageId,
    bool useAction = false,
  }) async {
    _log(
      DartvexLogLevel.debug,
      'Resolving file URL',
      data: <String, Object?>{
        'getUrlAction': getUrlAction,
        'storageId': storageId,
      },
    );
    final args = <String, dynamic>{'storageId': storageId};
    final url = useAction
        ? await caller.action(getUrlAction, args)
        : await caller.query(getUrlAction, args);
    _log(DartvexLogLevel.debug, 'Resolved file URL');
    if (url is String && url.isNotEmpty) {
      return url;
    }
    throw ConvexStorageException('No URL returned for storageId $storageId');
  }

  void _log(
    DartvexLogLevel level,
    String message, {
    Map<String, Object?>? data,
  }) {
    if (caller case final DartvexLogSource logSource) {
      emitDartvexLog(
        configuredLevel: logSource.logLevel,
        logger: logSource.logger,
        eventLevel: level,
        message: message,
        tag: 'storage',
        data: data,
      );
      return;
    }
  }

  Uri _parseUploadUri(String uploadUrlAction, Object? uploadUrl) {
    if (uploadUrl is! String || uploadUrl.isEmpty) {
      throw ConvexStorageException(
        'Upload URL resolver "$uploadUrlAction" must return a non-empty string',
      );
    }
    try {
      return Uri.parse(uploadUrl);
    } on FormatException catch (error) {
      throw ConvexStorageException(
        'Upload URL resolver "$uploadUrlAction" returned an invalid URL: '
        '${error.message}',
      );
    }
  }

  String _decodeUploadResponse(http.Response response) {
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw ConvexFileUploadException(
        response.statusCode,
        'Upload endpoint returned invalid JSON: ${response.body}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw ConvexFileUploadException(
        response.statusCode,
        'Upload endpoint returned a non-object JSON response',
      );
    }
    final storageId = decoded['storageId'];
    if (storageId is! String || storageId.isEmpty) {
      throw ConvexFileUploadException(
        response.statusCode,
        'Upload endpoint response is missing a non-empty string storageId',
      );
    }
    return storageId;
  }
}

class _ProgressUploadRequest extends http.Request implements http.Abortable {
  _ProgressUploadRequest(
    super.method,
    super.url, {
    this.abortTrigger,
    this.onProgress,
  });

  @override
  final Future<void>? abortTrigger;

  final void Function(int bytesSent, int totalBytes)? onProgress;

  @override
  http.ByteStream finalize() {
    var sent = 0;
    final total = contentLength;
    return http.ByteStream(super.finalize().expand(_chunks).map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent, total);
      return chunk;
    }));
  }

  Iterable<List<int>> _chunks(List<int> bytes) sync* {
    const chunkSize = 64 * 1024;
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      yield bytes is Uint8List
          ? Uint8List.sublistView(bytes, offset, end)
          : bytes.sublist(offset, end);
    }
  }
}
