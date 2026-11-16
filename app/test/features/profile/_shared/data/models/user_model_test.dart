import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/features/profile/_shared/data/models/user_model.dart';

import '../../../../../support/json_fixtures.dart';

Matcher _formatErrorNaming(String field, {required List<String> without}) => isA<FormatException>()
    .having((e) => e.message, 'message', contains(field))
    .having(
      (e) => without.every((secret) => !e.toString().contains(secret)),
      'hides the values',
      isTrue,
    );

void main() {
  group('UserModel', () {
    test('parses the contract UserResponse', () {
      final user = UserModel.fromJson(fakeUserJson());

      expect(user.id, '6f1c2a4e-8b0d-4c39-9a51-2f7e0d3b9c11');
      expect(user.name, 'Ana Souza');
      expect(user.email, 'ana@example.com');
      expect(user.currency, 'BRL');
      expect(user.createdAt, DateTime.utc(2026, 11, 10, 14, 3, 22));
      expect(user.createdAt.isUtc, isTrue);
    });

    test('accepts fractional seconds and ignores unknown fields', () {
      final user = UserModel.fromJson({
        ...fakeUserJson(),
        'createdAt': '2026-11-10T14:03:22.123456Z',
        'extra': true,
      });

      expect(user.createdAt.microsecond, 456);
    });

    for (final field in ['id', 'name', 'email', 'currency', 'createdAt']) {
      test('a missing $field fails loudly, naming the field', () {
        final json = fakeUserJson()..remove(field);

        expect(() => UserModel.fromJson(json), throwsA(_formatErrorNaming(field, without: [])));
      });
    }

    test('a wrong type or bad timestamp names the field, never the value', () {
      expect(
        () => UserModel.fromJson({...fakeUserJson(), 'email': 42}),
        throwsA(_formatErrorNaming('email', without: ['42'])),
      );
      expect(
        () => UserModel.fromJson({...fakeUserJson(), 'createdAt': 'not-a-date-ana@example.com'}),
        throwsA(_formatErrorNaming('createdAt', without: ['ana@example.com', 'not-a-date'])),
      );
    });

    test('toString shows the id but never the name or the email', () {
      final text = UserModel.fromJson(fakeUserJson()).toString();

      expect(text, contains('6f1c2a4e-8b0d-4c39-9a51-2f7e0d3b9c11'));
      expect(text, isNot(contains('Ana')));
      expect(text, isNot(contains('ana@example.com')));
    });

    test('compares by value', () {
      expect(UserModel.fromJson(fakeUserJson()), UserModel.fromJson(fakeUserJson()));
      expect(
        UserModel.fromJson(fakeUserJson()),
        isNot(UserModel.fromJson({...fakeUserJson(), 'name': 'Bia'})),
      );
    });
  });
}
