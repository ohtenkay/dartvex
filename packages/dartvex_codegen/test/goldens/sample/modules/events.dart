// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_element, unused_import, unused_local_variable

import '../runtime.dart';
import '../schema.dart';

import 'package:dartvex/dartvex.dart';

class EventsApi {
  const EventsApi(this._client);

  final ConvexFunctionCaller _client;

  Future<Object> dispatch([
    Map<String, dynamic> args = const <String, dynamic>{},
    OptimisticUpdate? optimisticUpdate,
  ]) async {
    final raw$ = await _client.mutate(
      'events:dispatch',
      args,
      optimisticUpdate,
    );
    return expectCommitTs(raw$, label: 'DispatchResult');
  }

  ConvexMutationReference<Map<String, dynamic>, Object> get dispatchMutation =>
      dispatchMutationReference;

  Future<FieldResult> field() async {
    final raw$ = await _client.query('events:field', const <String, dynamic>{});
    return _decodeFieldResult(raw$);
  }

  TypedConvexSubscription<FieldResult> fieldSubscribe() {
    final subscription$ = _client.subscribe(
      'events:field',
      const <String, dynamic>{},
    );
    return TypedConvexSubscription<FieldResult>(
      subscription$,
      subscription$.stream.map(
        (event$) => typedQueryResult<FieldResult>(
          event$,
          (raw$) => _decodeFieldResult(raw$),
          'events:field',
        ),
      ),
    );
  }

  ConvexQueryReference<NoArgs, FieldResult> get fieldQuery =>
      fieldQueryReference;

  Future<LabelsResult> labels() async {
    final raw$ = await _client.query(
      'events:labels',
      const <String, dynamic>{},
    );
    return _decodeLabelsResult(raw$);
  }

  TypedConvexSubscription<LabelsResult> labelsSubscribe() {
    final subscription$ = _client.subscribe(
      'events:labels',
      const <String, dynamic>{},
    );
    return TypedConvexSubscription<LabelsResult>(
      subscription$,
      subscription$.stream.map(
        (event$) => typedQueryResult<LabelsResult>(
          event$,
          (raw$) => _decodeLabelsResult(raw$),
          'events:labels',
        ),
      ),
    );
  }

  ConvexQueryReference<NoArgs, LabelsResult> get labelsQuery =>
      labelsQueryReference;

  Future<LatestResult> latest({
    required Map<String, double> scores,
    Optional<Map<String, String>> labels = const Optional.absent(),
  }) async {
    final raw$ = await _client.query(
      'events:latest',
      _encodeLatestArgs((scores: scores, labels: labels)),
    );
    return _decodeLatestResult(raw$);
  }

  TypedConvexSubscription<LatestResult> latestSubscribe({
    required Map<String, double> scores,
    Optional<Map<String, String>> labels = const Optional.absent(),
  }) {
    final subscription$ = _client.subscribe(
      'events:latest',
      _encodeLatestArgs((scores: scores, labels: labels)),
    );
    return TypedConvexSubscription<LatestResult>(
      subscription$,
      subscription$.stream.map(
        (event$) => typedQueryResult<LatestResult>(
          event$,
          (raw$) => _decodeLatestResult(raw$),
          'events:latest',
        ),
      ),
    );
  }

  ConvexQueryReference<LatestArgs, LatestResult> get latestQuery =>
      latestQueryReference;

  Future<Null> resize({
    required ResizeArgsWidth width,
    Optional<Object> at = const Optional.absent(),
    OptimisticUpdate? optimisticUpdate,
  }) async {
    await _client.mutate(
      'events:resize',
      _encodeResizeArgs((width: width, at: at)),
      optimisticUpdate,
    );
    return null;
  }

  ConvexMutationReference<ResizeArgs, void> get resizeMutation =>
      resizeMutationReference;
}

enum ChoiceValue {
  aValue('a'),
  bValue('b');

  const ChoiceValue(this.value);
  final Object? value;

  static ChoiceValue fromJson(dynamic raw) {
    switch (raw) {
      case 'a':
        return ChoiceValue.aValue;
      case 'b':
        return ChoiceValue.bValue;
      default:
        throw FormatException('Expected one of a, b for ChoiceValue');
    }
  }
}

sealed class FieldResult {
  const FieldResult();
}

final class Choice extends FieldResult {
  const Choice({required this.value});

  final ChoiceValue value;

  /// Returns a copy with the given fields replaced. Nullable fields take
  /// an [Optional], so `Optional.of(null)` clears them.
  Choice copyWith({ChoiceValue? value}) => Choice(value: value ?? this.value);
}

final class Text extends FieldResult {
  const Text({required this.value});

  final String value;

  /// Returns a copy with the given fields replaced. Nullable fields take
  /// an [Optional], so `Optional.of(null)` clears them.
  Text copyWith({String? value}) => Text(value: value ?? this.value);
}

Map<String, dynamic> _encodeFieldResult(FieldResult value) {
  switch (value) {
    case Choice(value: final value):
      return <String, dynamic>{'kind': 'choice', 'value': value.value};
    case Text(value: final value):
      return <String, dynamic>{'kind': 'text', 'value': value};
  }
}

FieldResult _decodeFieldResult(dynamic raw) {
  final map = expectMap(raw, label: 'FieldResult');
  if (!map.containsKey('kind')) {
    throw FormatException('Missing discriminator "kind" for FieldResult');
  }
  final discriminator = expectString(map['kind'], label: 'FieldResultKind');
  switch (discriminator) {
    case 'choice':
      if (!map.containsKey('value')) {
        throw FormatException('Missing required field "value" for Choice');
      }
      return Choice(value: ChoiceValue.fromJson(map['value']));
    case 'text':
      if (!map.containsKey('value')) {
        throw FormatException('Missing required field "value" for Text');
      }
      return Text(value: expectString(map['value'], label: 'TextValue'));
    default:
      throw FormatException(
        'Unknown FieldResult discriminator: $discriminator',
      );
  }
}

typedef LabelsResult2Value2 = ({double count});

Map<String, dynamic> _encodeLabelsResult2Value2(LabelsResult2Value2 value$) {
  final (count: count) = value$;
  return <String, dynamic>{'count': count};
}

LabelsResult2Value2 _decodeLabelsResult2Value2(dynamic raw) {
  final map = expectMap(raw, label: 'LabelsResult2Value2');
  if (!map.containsKey('count')) {
    throw FormatException(
      'Missing required field "count" for LabelsResult2Value2',
    );
  }
  return (count: expectDouble(map['count'], label: 'LabelsResult2Value2Count'));
}

sealed class LabelsResult {
  const LabelsResult();
}

class LabelsResult1Value extends LabelsResult {
  const LabelsResult1Value(this.value);
  final String value;
}

class LabelsResult2Value extends LabelsResult {
  const LabelsResult2Value(this.value);
  final Map<String, LabelsResult2Value2> value;
}

dynamic _encodeLabelsResult(LabelsResult value) {
  switch (value) {
    case LabelsResult1Value(value: final inner):
      return inner;
    case LabelsResult2Value(value: final inner):
      return inner.map(
        (key, value) => MapEntry(key, _encodeLabelsResult2Value2(value)),
      );
  }
}

LabelsResult _decodeLabelsResult(dynamic raw) {
  final errors = <String>[];
  try {
    return LabelsResult1Value(expectString(raw, label: 'LabelsResult1'));
  } catch (e) {
    errors.add('LabelsResult1Value: $e');
  }
  try {
    return LabelsResult2Value(
      expectMap(
        raw,
        label: 'LabelsResult2',
      ).map((key, value) => MapEntry(key, _decodeLabelsResult2Value2(value))),
    );
  } catch (e) {
    errors.add('LabelsResult2Value: $e');
  }
  throw FormatException(
    'Expected LabelsResult but received ${describeType(raw)}.\n'
    'Tried: ${errors.join(", ")}',
  );
}

typedef LatestResult = ({
  EventsId systemId,
  double systemCreationTime,
  String id,
  double creationTime,
  Object ts,
  String callback,
  dynamic payload,
  SystemStorageId fileId,
  StorageId storageId,
  String toStringValue,
});

Map<String, dynamic> _encodeLatestResult(LatestResult value$) {
  final (
    systemId: systemId,
    systemCreationTime: systemCreationTime,
    id: id,
    creationTime: creationTime,
    ts: ts,
    callback: callback,
    payload: payload,
    fileId: fileId,
    storageId: storageId,
    toStringValue: toStringValue,
  ) = value$;
  return <String, dynamic>{
    '_id': systemId.value,
    '_creationTime': systemCreationTime,
    'id': id,
    'creationTime': creationTime,
    'ts': ts,
    'callback': callback,
    'payload': payload,
    'fileId': fileId.value,
    'storageId': storageId.value,
    'toString': toStringValue,
  };
}

LatestResult _decodeLatestResult(dynamic raw) {
  final map = expectMap(raw, label: 'LatestResult');
  if (!map.containsKey('_id')) {
    throw FormatException('Missing required field "_id" for LatestResult');
  }
  if (!map.containsKey('_creationTime')) {
    throw FormatException(
      'Missing required field "_creationTime" for LatestResult',
    );
  }
  if (!map.containsKey('id')) {
    throw FormatException('Missing required field "id" for LatestResult');
  }
  if (!map.containsKey('creationTime')) {
    throw FormatException(
      'Missing required field "creationTime" for LatestResult',
    );
  }
  if (!map.containsKey('ts')) {
    throw FormatException('Missing required field "ts" for LatestResult');
  }
  if (!map.containsKey('callback')) {
    throw FormatException('Missing required field "callback" for LatestResult');
  }
  if (!map.containsKey('payload')) {
    throw FormatException('Missing required field "payload" for LatestResult');
  }
  if (!map.containsKey('fileId')) {
    throw FormatException('Missing required field "fileId" for LatestResult');
  }
  if (!map.containsKey('storageId')) {
    throw FormatException(
      'Missing required field "storageId" for LatestResult',
    );
  }
  if (!map.containsKey('toString')) {
    throw FormatException('Missing required field "toString" for LatestResult');
  }
  return (
    systemId: EventsId(expectString(map['_id'], label: 'LatestResultSystemId')),
    systemCreationTime: expectDouble(
      map['_creationTime'],
      label: 'LatestResultSystemCreationTime',
    ),
    id: expectString(map['id'], label: 'LatestResultId'),
    creationTime: expectDouble(
      map['creationTime'],
      label: 'LatestResultCreationTime',
    ),
    ts: expectCommitTs(map['ts'], label: 'LatestResultTs'),
    callback: expectString(map['callback'], label: 'LatestResultCallback'),
    payload: map['payload'],
    fileId: SystemStorageId(
      expectString(map['fileId'], label: 'LatestResultFileId'),
    ),
    storageId: StorageId(
      expectString(map['storageId'], label: 'LatestResultStorageId'),
    ),
    toStringValue: expectString(map['toString'], label: 'LatestResultToString'),
  );
}

typedef LatestArgs = ({
  Map<String, double> scores,
  Optional<Map<String, String>> labels,
});

Map<String, dynamic> _encodeLatestArgs(LatestArgs value$) {
  final (scores: scores, labels: labels) = value$;
  return <String, dynamic>{
    'scores': scores.map((key, value) => MapEntry(key, value)),
    if (labels.isDefined)
      'labels': labels.value.map((key, value) => MapEntry(key, value)),
  };
}

LatestArgs _decodeLatestArgs(dynamic raw) {
  final map = expectMap(raw, label: 'LatestArgs');
  if (!map.containsKey('scores')) {
    throw FormatException('Missing required field "scores" for LatestArgs');
  }
  return (
    scores: expectMap(map['scores'], label: 'LatestArgsScores').map(
      (key, value) =>
          MapEntry(key, expectDouble(value, label: 'LatestArgsScoresValue')),
    ),
    labels: map.containsKey('labels')
        ? Optional.of(
            expectMap(map['labels'], label: 'LatestArgsLabels').map(
              (key, value) => MapEntry(
                key,
                expectString(value, label: 'LatestArgsLabelsValue'),
              ),
            ),
          )
        : const Optional.absent(),
  );
}

sealed class ResizeArgsWidth {
  const ResizeArgsWidth();
}

class ResizeArgsWidth1Value extends ResizeArgsWidth {
  const ResizeArgsWidth1Value(this.value);
  final String value;
}

class ResizeArgsWidth2Value extends ResizeArgsWidth {
  const ResizeArgsWidth2Value(this.value);
  final String value;
}

class ResizeArgsWidth3Value extends ResizeArgsWidth {
  const ResizeArgsWidth3Value(this.value);
  final double value;
}

dynamic _encodeResizeArgsWidth(ResizeArgsWidth value) {
  switch (value) {
    case ResizeArgsWidth1Value(value: final inner):
      return inner;
    case ResizeArgsWidth2Value(value: final inner):
      return inner;
    case ResizeArgsWidth3Value(value: final inner):
      return inner;
  }
}

ResizeArgsWidth _decodeResizeArgsWidth(dynamic raw) {
  final errors = <String>[];
  try {
    return ResizeArgsWidth1Value(
      expectLiteral<String>(raw, 'auto', label: 'ResizeArgsWidth1'),
    );
  } catch (e) {
    errors.add('ResizeArgsWidth1Value: $e');
  }
  try {
    return ResizeArgsWidth2Value(
      expectLiteral<String>(raw, 'none', label: 'ResizeArgsWidth2'),
    );
  } catch (e) {
    errors.add('ResizeArgsWidth2Value: $e');
  }
  try {
    return ResizeArgsWidth3Value(expectDouble(raw, label: 'ResizeArgsWidth3'));
  } catch (e) {
    errors.add('ResizeArgsWidth3Value: $e');
  }
  throw FormatException(
    'Expected ResizeArgsWidth but received ${describeType(raw)}.\n'
    'Tried: ${errors.join(", ")}',
  );
}

typedef ResizeArgs = ({ResizeArgsWidth width, Optional<Object> at});

Map<String, dynamic> _encodeResizeArgs(ResizeArgs value$) {
  final (width: width, at: at) = value$;
  return <String, dynamic>{
    'width': _encodeResizeArgsWidth(width),
    if (at.isDefined) 'at': at.value,
  };
}

ResizeArgs _decodeResizeArgs(dynamic raw) {
  final map = expectMap(raw, label: 'ResizeArgs');
  if (!map.containsKey('width')) {
    throw FormatException('Missing required field "width" for ResizeArgs');
  }
  return (
    width: _decodeResizeArgsWidth(map['width']),
    at: map.containsKey('at')
        ? Optional.of(expectCommitTs(map['at'], label: 'ResizeArgsAt'))
        : const Optional.absent(),
  );
}

final ConvexMutationReference<Map<String, dynamic>, Object>
dispatchMutationReference = ConvexMutationReference(
  name: 'events:dispatch',
  encode: (args) => args,
  decode: (raw) => expectCommitTs(raw, label: 'DispatchResult'),
);

final ConvexQueryReference<NoArgs, FieldResult> fieldQueryReference =
    ConvexQueryReference(
      name: 'events:field',
      encode: (args) => const <String, dynamic>{},
      decodeArgs: (raw) => const NoArgs(),
      decode: (raw) => _decodeFieldResult(raw),
      encodeResult: (value) => _encodeFieldResult(value),
    );

final ConvexQueryReference<NoArgs, LabelsResult> labelsQueryReference =
    ConvexQueryReference(
      name: 'events:labels',
      encode: (args) => const <String, dynamic>{},
      decodeArgs: (raw) => const NoArgs(),
      decode: (raw) => _decodeLabelsResult(raw),
      encodeResult: (value) => _encodeLabelsResult(value),
    );

final ConvexQueryReference<LatestArgs, LatestResult> latestQueryReference =
    ConvexQueryReference(
      name: 'events:latest',
      encode: (args) => _encodeLatestArgs(args),
      decodeArgs: (raw) => _decodeLatestArgs(raw),
      decode: (raw) => _decodeLatestResult(raw),
      encodeResult: (value) => _encodeLatestResult(value),
    );

final ConvexMutationReference<ResizeArgs, void> resizeMutationReference =
    ConvexMutationReference(
      name: 'events:resize',
      encode: (args) => _encodeResizeArgs(args),
      decode: (raw) => null,
    );
