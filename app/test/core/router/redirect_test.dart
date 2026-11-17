import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/router/redirect.dart';
import 'package:snapledger/core/session/session_notifier.dart';

void main() {
  String? redirect(SessionStatus status, String location) =>
      redirectFor(status, Uri.parse(location));

  group('unknown session', () {
    test('stays on the splash', () {
      expect(redirect(SessionStatus.unknown, '/splash'), isNull);
      expect(redirect(SessionStatus.unknown, '/splash?from=/expenses'), isNull);
    });

    test('everything else goes to the splash', () {
      expect(redirect(SessionStatus.unknown, '/login'), '/splash');
      expect(redirect(SessionStatus.unknown, '/register'), '/splash');
      expect(redirect(SessionStatus.unknown, '/nowhere'), '/splash');
    });

    test('a tab path is remembered as from', () {
      expect(redirect(SessionStatus.unknown, '/expenses'), '/splash?from=%2Fexpenses');
      expect(redirect(SessionStatus.unknown, '/profile'), '/splash?from=%2Fprofile');
    });

    test('a tab sub-path is not remembered', () {
      expect(redirect(SessionStatus.unknown, '/profile/categories'), '/splash');
    });
  });

  group('signed out', () {
    test('stays on login and register', () {
      expect(redirect(SessionStatus.signedOut, '/login'), isNull);
      expect(redirect(SessionStatus.signedOut, '/register'), isNull);
      expect(redirect(SessionStatus.signedOut, '/login?from=/expenses'), isNull);
    });

    test('the splash goes to login', () {
      expect(redirect(SessionStatus.signedOut, '/splash'), '/login');
    });

    test('the splash keeps an allowlisted from', () {
      expect(
        redirect(SessionStatus.signedOut, '/splash?from=/expenses'),
        '/login?from=%2Fexpenses',
      );
    });

    test('the splash drops a from that is not allowlisted', () {
      expect(redirect(SessionStatus.signedOut, '/splash?from=//evil.test'), '/login');
    });

    test('a tab goes to login remembering where it was', () {
      expect(redirect(SessionStatus.signedOut, '/summary'), '/login?from=%2Fsummary');
      expect(redirect(SessionStatus.signedOut, '/expenses'), '/login?from=%2Fexpenses');
      expect(redirect(SessionStatus.signedOut, '/profile'), '/login?from=%2Fprofile');
    });

    test('an unknown path goes to login without from', () {
      expect(redirect(SessionStatus.signedOut, '/nowhere'), '/login');
      expect(redirect(SessionStatus.signedOut, '/profile/categories'), '/login');
    });
  });

  group('signed in', () {
    test('tabs stay', () {
      for (final path in ['/summary', '/expenses', '/profile', '/profile/categories']) {
        expect(redirect(SessionStatus.signedIn, path), isNull, reason: path);
      }
    });

    test('auth screens and the splash go to the summary', () {
      for (final path in ['/login', '/register', '/splash']) {
        expect(redirect(SessionStatus.signedIn, path), '/summary', reason: path);
      }
    });

    test('an allowlisted from is honoured', () {
      expect(redirect(SessionStatus.signedIn, '/login?from=/expenses'), '/expenses');
      expect(redirect(SessionStatus.signedIn, '/splash?from=%2Fprofile'), '/profile');
      expect(redirect(SessionStatus.signedIn, '/register?from=/summary'), '/summary');
    });

    test('an unknown path goes to the summary', () {
      expect(redirect(SessionStatus.signedIn, '/nowhere'), '/summary');
    });
  });

  group('password reset and email verification', () {
    test('forgot password: allowed signed out, summary when signed in, splash while unknown', () {
      expect(redirect(SessionStatus.signedOut, '/forgot-password'), isNull);
      expect(redirect(SessionStatus.signedIn, '/forgot-password'), '/summary');
      expect(redirect(SessionStatus.unknown, '/forgot-password'), '/splash');
    });

    test('verify email: allowed only when signed in', () {
      expect(redirect(SessionStatus.signedIn, '/verify-email'), isNull);
      expect(redirect(SessionStatus.signedOut, '/verify-email'), '/login');
      expect(redirect(SessionStatus.unknown, '/verify-email'), '/splash');
    });

    test('a pending verification pins a signed in user to the verify email screen', () {
      String? pinned(String location) =>
          redirectFor(SessionStatus.signedIn, Uri.parse(location), pendingVerification: true);

      expect(pinned('/verify-email'), isNull);
      expect(pinned('/summary'), '/verify-email');
      expect(pinned('/register'), '/verify-email');
      expect(pinned('/login?from=/expenses'), '/verify-email');
    });

    test('a pending verification does not affect a signed out or unknown session', () {
      expect(
        redirectFor(SessionStatus.signedOut, Uri.parse('/login'), pendingVerification: true),
        isNull,
      );
      expect(
        redirectFor(SessionStatus.unknown, Uri.parse('/splash'), pendingVerification: true),
        isNull,
      );
    });

    test('verify email and forgot password are never valid from targets', () {
      expect(allowedFrom('/verify-email'), isNull);
      expect(allowedFrom('/forgot-password'), isNull);
    });
  });

  group('the from allowlist', () {
    test('accepts only the three tab roots', () {
      expect(allowedFrom('/summary'), '/summary');
      expect(allowedFrom('/expenses'), '/expenses');
      expect(allowedFrom('/profile'), '/profile');
    });

    for (final raw in <String?>[
      null,
      '',
      'summary',
      'https://evil.test/summary',
      'http://evil.test',
      '//evil.test/summary',
      '//summary',
      r'/\evil.test',
      'javascript:alert(1)',
      '/login',
      '/register',
      '/splash',
      '/profile/categories',
      '/summary?x=1',
      '/summary#top',
      '/summary/../login',
      '/unknown',
    ]) {
      test('rejects ${raw == null ? 'null' : "'$raw'"}', () {
        expect(allowedFrom(raw), isNull);
      });
    }

    test('a rejected from sends a signed-in user to the summary', () {
      expect(redirect(SessionStatus.signedIn, '/login?from=https://evil.test'), '/summary');
      expect(redirect(SessionStatus.signedIn, '/login?from=//evil.test'), '/summary');
      expect(redirect(SessionStatus.signedIn, '/login?from=/login'), '/summary');
    });
  });
}
