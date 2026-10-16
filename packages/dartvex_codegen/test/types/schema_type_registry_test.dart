import 'package:dartvex_codegen/dartvex_codegen.dart';
import 'package:test/test.dart';

void main() {
  const category = ConvexUnionType(<ConvexType>[
    ConvexObjectType(<String, ConvexField>{
      'kind': ConvexField(
        fieldType: ConvexLiteralType('beer'),
        optional: false,
      ),
    }),
    ConvexObjectType(<String, ConvexField>{
      'kind': ConvexField(
        fieldType: ConvexLiteralType('wine'),
        optional: false,
      ),
    }),
  ]);
  const reorderedCategory = ConvexUnionType(<ConvexType>[
    ConvexObjectType(<String, ConvexField>{
      'kind': ConvexField(
        fieldType: ConvexLiteralType('wine'),
        optional: false,
      ),
    }),
    ConvexObjectType(<String, ConvexField>{
      'kind': ConvexField(
        fieldType: ConvexLiteralType('beer'),
        optional: false,
      ),
    }),
  ]);

  test('reuses identical field unions across nesting levels', () {
    final registry = SchemaTypeRegistry.fromSchema(
      const SchemaSpec(
        tables: <SchemaTableSpec>[
          SchemaTableSpec(
            name: 'drinks',
            documentType: ConvexObjectType(<String, ConvexField>{
              'category': ConvexField(fieldType: category, optional: false),
            }),
          ),
          SchemaTableSpec(
            name: 'profiles',
            documentType: ConvexObjectType(<String, ConvexField>{
              'preferences': ConvexField(
                fieldType: ConvexObjectType(<String, ConvexField>{
                  'category': ConvexField(
                    fieldType: reorderedCategory,
                    optional: false,
                  ),
                }),
                optional: false,
              ),
            }),
          ),
        ],
      ),
      discriminator: 'kind',
    );

    expect(registry.types, hasLength(3));
    final categoryType = registry.types.singleWhere((type) => !type.isDocument);
    expect(categoryType.name, 'Category');
    expect(
      categoryType.paths,
      containsAll(<String>['drinks.category', 'profiles.preferences.category']),
    );
  });

  test('discovers nullable discriminated unions', () {
    const nullableReordered = ConvexUnionType(<ConvexType>[
      ConvexNullType(),
      ConvexObjectType(<String, ConvexField>{
        'kind': ConvexField(
          fieldType: ConvexLiteralType('wine'),
          optional: false,
        ),
      }),
      ConvexObjectType(<String, ConvexField>{
        'kind': ConvexField(
          fieldType: ConvexLiteralType('beer'),
          optional: false,
        ),
      }),
    ]);
    final registry = SchemaTypeRegistry.fromSchema(
      const SchemaSpec(
        tables: <SchemaTableSpec>[
          SchemaTableSpec(
            name: 'drinks',
            documentType: ConvexObjectType(<String, ConvexField>{
              'category': ConvexField(
                fieldType: nullableReordered,
                optional: false,
              ),
            }),
          ),
        ],
      ),
      discriminator: 'kind',
    );

    expect(
      registry.types.singleWhere((type) => !type.isDocument).name,
      'Category',
    );
    expect(
      registry.resolve(nullableReordered, fieldName: 'status')?.name,
      'Category',
    );
  });

  test('shares differently named fields and resolves every alias', () {
    final registry = SchemaTypeRegistry.fromSchema(
      const SchemaSpec(
        tables: [
          SchemaTableSpec(
            name: 'matches',
            documentType: ConvexObjectType({
              'slotA': ConvexField(fieldType: category, optional: false),
              'slotB': ConvexField(
                fieldType: reorderedCategory,
                optional: false,
              ),
              'history': ConvexField(
                fieldType: ConvexArrayType(
                  ConvexObjectType({
                    'previousSlot': ConvexField(
                      fieldType: category,
                      optional: false,
                    ),
                    'slotB': ConvexField(fieldType: category, optional: false),
                  }),
                ),
                optional: false,
              ),
            }),
          ),
        ],
      ),
      discriminator: 'kind',
    );
    final shared = registry.types.singleWhere((type) => !type.isDocument);
    expect(shared.name, 'SlotA');
    expect(shared.paths, [
      'matches.slotA',
      'matches.slotB',
      'matches.history[].previousSlot',
      'matches.history[].slotB',
    ]);
    for (final name in ['slotA', 'slotB', 'previousSlot', 'endpointSlot']) {
      expect(
        registry.resolve(reorderedCategory, fieldName: name),
        same(shared),
      );
    }
    expect(registry.resolve(category), same(shared));
  });

  test('reuses identical nullable unions under different field names', () {
    final nullable = ConvexUnionType([
      ...category.value,
      const ConvexNullType(),
    ]);
    final registry = SchemaTypeRegistry.fromSchema(
      SchemaSpec(
        tables: [
          SchemaTableSpec(
            name: 'matches',
            documentType: ConvexObjectType({
              'slotA': ConvexField(fieldType: nullable, optional: false),
              'slotB': ConvexField(fieldType: nullable, optional: true),
            }),
          ),
        ],
      ),
      discriminator: 'kind',
    );
    expect(registry.types.where((type) => !type.isDocument), hasLength(1));
    expect(registry.resolve(nullable, fieldName: 'slotB')?.name, 'SlotA');
  });

  test('still rejects incompatible unions claiming the same subclasses', () {
    final changed = ConvexUnionType([
      for (final member in category.value.cast<ConvexObjectType>())
        ConvexObjectType({
          ...member.value,
          'extra': const ConvexField(
            fieldType: ConvexStringType(),
            optional: false,
          ),
        }),
    ]);
    expect(
      () => SchemaTypeRegistry.fromSchema(
        SchemaSpec(
          tables: [
            SchemaTableSpec(
              name: 'matches',
              documentType: ConvexObjectType({
                'slotA': const ConvexField(
                  fieldType: category,
                  optional: false,
                ),
                'slotB': ConvexField(fieldType: changed, optional: false),
              }),
            ),
          ],
        ),
        discriminator: 'kind',
      ),
      throwsA(
        isA<SchemaTypeRegistryException>().having(
          (error) => error.message,
          'message',
          contains('Generated subtype "Beer"'),
        ),
      ),
    );
  });

  test('rejects incompatible definitions of a reused field alias', () {
    const other = ConvexUnionType([
      ConvexObjectType({
        'kind': ConvexField(
          fieldType: ConvexLiteralType('food'),
          optional: false,
        ),
      }),
      ConvexObjectType({
        'kind': ConvexField(
          fieldType: ConvexLiteralType('other'),
          optional: false,
        ),
      }),
    ]);
    expect(
      () => SchemaTypeRegistry.fromSchema(
        const SchemaSpec(
          tables: [
            SchemaTableSpec(
              name: 'matches',
              documentType: ConvexObjectType({
                'slotA': ConvexField(fieldType: category, optional: false),
                'slotB': ConvexField(fieldType: category, optional: false),
              }),
            ),
            SchemaTableSpec(
              name: 'history',
              documentType: ConvexObjectType({
                'slotB': ConvexField(fieldType: other, optional: false),
              }),
            ),
          ],
        ),
        discriminator: 'kind',
      ),
      throwsA(
        isA<SchemaTypeRegistryException>().having(
          (error) => error.message,
          'message',
          contains('Schema field "slotB"'),
        ),
      ),
    );
  });

  test('rejects different unions using the same schema field name', () {
    const otherCategory = ConvexUnionType(<ConvexType>[
      ConvexObjectType(<String, ConvexField>{
        'kind': ConvexField(
          fieldType: ConvexLiteralType('food'),
          optional: false,
        ),
      }),
      ConvexObjectType(<String, ConvexField>{
        'kind': ConvexField(
          fieldType: ConvexLiteralType('other'),
          optional: false,
        ),
      }),
    ]);

    expect(
      () => SchemaTypeRegistry.fromSchema(
        const SchemaSpec(
          tables: <SchemaTableSpec>[
            SchemaTableSpec(
              name: 'drinks',
              documentType: ConvexObjectType(<String, ConvexField>{
                'category': ConvexField(fieldType: category, optional: false),
              }),
            ),
            SchemaTableSpec(
              name: 'meals',
              documentType: ConvexObjectType(<String, ConvexField>{
                'category': ConvexField(
                  fieldType: otherCategory,
                  optional: false,
                ),
              }),
            ),
          ],
        ),
        discriminator: 'kind',
      ),
      throwsA(isA<SchemaTypeRegistryException>()),
    );
  });
}
