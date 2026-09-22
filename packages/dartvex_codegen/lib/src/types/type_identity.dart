import 'dart:convert';

import '../spec/function_spec.dart';

/// Returns a deterministic structural identity for a Convex type.
String convexTypeIdentity(ConvexType type) => jsonEncode(_canonicalType(type));

Object? _canonicalType(ConvexType type) {
  return switch (type) {
    ConvexAnyType() => const <String, Object?>{'type': 'any'},
    ConvexBooleanType() => const <String, Object?>{'type': 'boolean'},
    ConvexStringType() => const <String, Object?>{'type': 'string'},
    ConvexNumberType() => const <String, Object?>{'type': 'number'},
    ConvexNullType() => const <String, Object?>{'type': 'null'},
    ConvexBigIntType() => const <String, Object?>{'type': 'bigint'},
    ConvexBytesType() => const <String, Object?>{'type': 'bytes'},
    ConvexLiteralType(:final value) => <String, Object?>{
      'type': 'literal',
      'value': _canonicalValue(value),
    },
    ConvexIdType(:final tableName) => <String, Object?>{
      'type': 'id',
      'tableName': tableName,
    },
    ConvexArrayType(:final value) => <String, Object?>{
      'type': 'array',
      'value': _canonicalType(value),
    },
    ConvexRecordType(:final keys, :final values) => <String, Object?>{
      'type': 'record',
      'keys': _canonicalType(keys),
      'values': _canonicalField(values),
    },
    ConvexObjectType(:final value) => <String, Object?>{
      'type': 'object',
      'value': <String, Object?>{
        for (final key in value.keys.toList()..sort())
          key: _canonicalField(value[key]!),
      },
    },
    ConvexUnionType(:final value) => <String, Object?>{
      'type': 'union',
      'value': _canonicalUnionMembers(value),
    },
  };
}

List<Object?> _canonicalUnionMembers(List<ConvexType> members) {
  final canonical = members.map(_canonicalType).toList();
  canonical.sort(
    (left, right) => jsonEncode(left).compareTo(jsonEncode(right)),
  );
  return canonical;
}

Object _canonicalField(ConvexField field) => <String, Object?>{
  'fieldType': _canonicalType(field.fieldType),
  'optional': field.optional,
};

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final map = value.cast<String, dynamic>();
    return <String, Object?>{
      for (final key in map.keys.toList()..sort())
        key: _canonicalValue(map[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  return value;
}
