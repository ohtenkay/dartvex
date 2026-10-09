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
