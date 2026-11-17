import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/features/auth/_shared/data/models/auth_response.dart';
import 'package:snapledger/features/auth/_shared/data/models/login_request.dart';
import 'package:snapledger/features/auth/_shared/data/models/password_reset_requests.dart';
import 'package:snapledger/features/auth/_shared/data/models/register_request.dart';

import '../../../../../support/json_fixtures.dart';

Matcher _formatErrorNaming(String field, {required List<String> without}) => isA<FormatException>()
    .having((e) => e.message, 'message', contains(field))
    .having(
      (e) => without.every((secret) => !e.toString().contains(secret)),
      'hides the values',
      isTrue,
    );

void main() {
  group('AuthResponse', () {
    test('parses user and tokens', () {
      final response = AuthResponse.fromJson(fakeAuthJson(3));

      expect(response.user.email, 'ana@example.com');
      expect(response.tokens.accessToken, 'fake-access-3');
      expect(response.tokens.refreshToken, 'fake-refresh-3');
    });

    test('a missing or malformed part fails loudly, naming it', () {
      expect(
        () => AuthResponse.fromJson({'tokens': fakeTokenJson(1)}),
        throwsA(_formatErrorNaming('user', without: [])),
      );
      expect(
        () => AuthResponse.fromJson({'user': fakeUserJson(), 'tokens': 'fake-access-1'}),
        throwsA(_formatErrorNaming('tokens', without: ['fake-access-1'])),
      );
      expect(
        () => AuthResponse.fromJson({
          'user': fakeUserJson(),
          'tokens': {...fakeTokenJson(1)}..remove('refreshToken'),
        }),
        throwsA(_formatErrorNaming('refreshToken', without: ['fake-access-1'])),
      );
    });

    test('toString shows neither tokens nor personal data', () {
      final text = AuthResponse.fromJson(fakeAuthJson(1)).toString();

      for (final secret in ['fake-access-1', 'fake-refresh-1', 'ana@example.com', 'Ana']) {
        expect(text, isNot(contains(secret)));
      }
    });
  });

  group('requests', () {
    test('LoginRequest sends email and password; toString hides both', () {
      const request = LoginRequest(email: 'ana@example.com', password: 'fake-password');

      expect(request.toJson(), {'email': 'ana@example.com', 'password': 'fake-password'});
      expect(request.toString(), isNot(contains('ana@example.com')));
      expect(request.toString(), isNot(contains('fake-password')));
    });

    test('RegisterRequest sends no currency; toString hides name, email and password', () {
      const request = RegisterRequest(
        name: 'Ana Souza',
        email: 'ana@example.com',
        password: 'fake-password',
      );

      expect(request.toJson(), {
        'name': 'Ana Souza',
        'email': 'ana@example.com',
        'password': 'fake-password',
      });
      for (final secret in ['Ana Souza', 'ana@example.com', 'fake-password']) {
        expect(request.toString(), isNot(contains(secret)));
      }
    });

    test('PasswordResetRequest sends the email; toString hides it', () {
      const request = PasswordResetRequest(email: 'ana@example.com');

      expect(request.toJson(), {'email': 'ana@example.com'});
      expect(request.toString(), isNot(contains('ana@example.com')));
    });

    test('PasswordResetConfirmRequest sends email, code and newPassword; toString hides all', () {
      const request = PasswordResetConfirmRequest(
        email: 'ana@example.com',
        code: '042917',
        newPassword: 'fake-new-password',
      );

      expect(request.toJson(), {
        'email': 'ana@example.com',
        'code': '042917',
        'newPassword': 'fake-new-password',
      });
      for (final secret in ['ana@example.com', '042917', 'fake-new-password']) {
        expect(request.toString(), isNot(contains(secret)));
      }
    });
  });
}
