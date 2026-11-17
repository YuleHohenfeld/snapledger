import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/features/auth/_shared/validation/auth_validators.dart';

void main() {
  group('validateName', () {
    test('accepts a normal name and ignores spaces at the ends', () {
      expect(validateName('Ana Souza'), isNull);
      expect(validateName('  Ana  '), isNull);
      expect(validateName('José Conceição'), isNull);
    });

    test('requires a value that is not only spaces', () {
      expect(validateName(null), AuthFieldError.required);
      expect(validateName(''), AuthFieldError.required);
      expect(validateName('   \t '), AuthFieldError.required);
    });

    test('counts code points: 80 emoji are accepted, 81 are too long', () {
      expect(validateName('😀' * 80), isNull);
      expect(validateName('😀' * 81), AuthFieldError.nameTooLong);
      expect(validateName('a' * 80), isNull);
      expect(validateName('a' * 81), AuthFieldError.nameTooLong);
    });

    test('accented letters count as one character each', () {
      expect(validateName('é' * 80), isNull);
      expect(validateName('é' * 81), AuthFieldError.nameTooLong);
    });

    test('the 80 limit is checked after trimming the ends', () {
      expect(validateName('  ${'a' * 80}  '), isNull);
    });

    test('rejects control and invisible formatting characters inside the name', () {
      for (final bad in [
        'Ana\nSouza', // line feed (Cc)
        'Ana\tSouza', // tab (Cc)
        'Ana${String.fromCharCode(0x00)}', // NUL (Cc)
        'An${String.fromCharCode(0x200B)}a', // zero-width space (Cf)
        'Ana${String.fromCharCode(0x202E)}Souza', // right-to-left override (Cf)
        'An${String.fromCharCode(0x00AD)}a', // soft hyphen (Cf)
        'An${String.fromCharCode(0xD800)}a', // lone surrogate (Cs)
      ]) {
        expect(validateName(bad), AuthFieldError.nameInvalidChars, reason: bad.runes.toString());
      }
    });
  });

  group('validateEmail', () {
    test('accepts a plain ASCII email, trimming only the ends', () {
      expect(validateEmail('ana@example.com'), isNull);
      expect(validateEmail('  ana@example.com  '), isNull);
      expect(validateEmail('Ana.Souza+tag@Example.COM'), isNull);
    });

    test('requires a value', () {
      expect(validateEmail(null), AuthFieldError.required);
      expect(validateEmail('   '), AuthFieldError.required);
    });

    test('rejects whitespace inside', () {
      expect(validateEmail('ana @example.com'), AuthFieldError.emailInvalid);
      expect(validateEmail('ana@exa\tmple.com'), AuthFieldError.emailInvalid);
    });

    test('rejects anything outside printable ASCII', () {
      expect(validateEmail('josé@example.com'), AuthFieldError.emailInvalid);
      expect(validateEmail('ana@exämple.com'), AuthFieldError.emailInvalid);
      expect(validateEmail('ana😀@example.com'), AuthFieldError.emailInvalid);
      expect(
        validateEmail('ana${String.fromCharCode(0x200B)}@example.com'),
        AuthFieldError.emailInvalid,
      );
    });

    test('needs exactly one @ with text on both sides', () {
      expect(validateEmail('ana.example.com'), AuthFieldError.emailInvalid);
      expect(validateEmail('@example.com'), AuthFieldError.emailInvalid);
      expect(validateEmail('ana@'), AuthFieldError.emailInvalid);
      expect(validateEmail('ana@@example.com'), AuthFieldError.emailInvalid);
      expect(validateEmail('a@b@example.com'), AuthFieldError.emailInvalid);
    });

    test('accepts 254 characters and rejects 255', () {
      const domain = '@example.com';
      expect(validateEmail('${'a' * (254 - domain.length)}$domain'), isNull);
      expect(validateEmail('${'a' * (255 - domain.length)}$domain'), AuthFieldError.emailTooLong);
    });
  });

  group('validateRegisterPassword', () {
    test('accepts 8 to 72 bytes', () {
      expect(validateRegisterPassword('a' * 8), isNull);
      expect(validateRegisterPassword('a' * 72), isNull);
    });

    test('requires a password that is not only spaces, and never trims it', () {
      expect(validateRegisterPassword(null), AuthFieldError.required);
      expect(validateRegisterPassword(''), AuthFieldError.required);
      expect(validateRegisterPassword('        '), AuthFieldError.required);
      // 6 letters + 2 spaces = 8 bytes: the spaces count.
      // PT: 6 letras + 2 espaços = 8 bytes: os espaços contam.
      expect(validateRegisterPassword(' abcdef '), isNull);
    });

    test('counts bytes, not characters: 4 accented letters are 8 bytes', () {
      expect(validateRegisterPassword('ééé'), AuthFieldError.passwordTooShort); // 6 bytes
      expect(validateRegisterPassword('éééé'), isNull); // 8 bytes
      expect(validateRegisterPassword('😀😀'), isNull); // 8 bytes, 2 characters
      expect(validateRegisterPassword('abcdefg'), AuthFieldError.passwordTooShort);
    });

    test('the 72-byte limit counts multi-byte characters', () {
      expect(validateRegisterPassword('a' * 73), AuthFieldError.passwordTooLong);
      expect(validateRegisterPassword('é' * 36), isNull); // 72 bytes
      expect(validateRegisterPassword('${'é' * 36}a'), AuthFieldError.passwordTooLong); // 73
      expect(validateRegisterPassword('😀' * 18), isNull); // 72 bytes
      expect(validateRegisterPassword('${'😀' * 18}a'), AuthFieldError.passwordTooLong);
    });
  });

  group('validateLoginPassword', () {
    test('has no minimum length', () {
      expect(validateLoginPassword('a'), isNull);
      expect(validateLoginPassword('é'), isNull);
    });

    test('requires a password that is not only spaces', () {
      expect(validateLoginPassword(null), AuthFieldError.required);
      expect(validateLoginPassword('  '), AuthFieldError.required);
    });

    test('rejects more than 72 bytes', () {
      expect(validateLoginPassword('a' * 72), isNull);
      expect(validateLoginPassword('é' * 36), isNull);
      expect(validateLoginPassword('${'é' * 36}a'), AuthFieldError.passwordTooLong);
      expect(validateLoginPassword('😀' * 19), AuthFieldError.passwordTooLong);
    });
  });

  group('validateCode', () {
    test('accepts exactly 6 ASCII digits, leading zeros included', () {
      expect(validateCode('042917'), isNull);
      expect(validateCode('000000'), isNull);
    });

    test('requires a value', () {
      expect(validateCode(null), AuthFieldError.required);
      expect(validateCode(''), AuthFieldError.required);
    });

    test('rejects 5 and 7 digits', () {
      expect(validateCode('12345'), AuthFieldError.codeInvalid);
      expect(validateCode('1234567'), AuthFieldError.codeInvalid);
    });

    test('rejects letters, spaces and symbols', () {
      for (final value in ['12345a', 'abcdef', '123 56', ' 12345', '12345 ', '12-456']) {
        expect(validateCode(value), AuthFieldError.codeInvalid, reason: value);
      }
    });

    test('rejects full-width and other non-ASCII digits', () {
      expect(validateCode('０４２９１７'), AuthFieldError.codeInvalid);
      expect(validateCode('٠٤٢٩١٧'), AuthFieldError.codeInvalid);
    });

    test('does not accept a trailing newline', () {
      expect(validateCode('042917\n'), AuthFieldError.codeInvalid);
    });
  });
}
