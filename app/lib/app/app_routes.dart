import 'package:go_router/go_router.dart';
import 'package:snapledger/app/home_shell.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/auth/login/presentation/page/login_page.dart';
import 'package:snapledger/features/auth/password_reset/presentation/page/password_reset_page.dart';
import 'package:snapledger/features/auth/register/presentation/page/register_page.dart';
import 'package:snapledger/features/auth/splash/presentation/page/splash_page.dart';
import 'package:snapledger/features/auth/verify_email/presentation/page/verify_email_page.dart';
import 'package:snapledger/features/expenses/list/presentation/page/expense_list_page.dart';
import 'package:snapledger/features/profile/overview/presentation/page/profile_page.dart';
import 'package:snapledger/features/summary/overview/presentation/page/summary_page.dart';

/// The only place where pages are tied to paths (typed by [AppRoute]).
/// PT: O único lugar onde páginas são ligadas a caminhos (tipados pelo [AppRoute]).
/// Notes: docs/code-notes/app-core.md#composition-root
final List<RouteBase> appRoutes = [
  GoRoute(path: AppRoute.splash.path, builder: (context, state) => const SplashPage()),
  GoRoute(path: AppRoute.login.path, builder: (context, state) => const LoginPage()),
  GoRoute(path: AppRoute.register.path, builder: (context, state) => const RegisterPage()),
  GoRoute(
    path: AppRoute.passwordReset.path,
    builder: (context, state) => const PasswordResetPage(),
  ),
  // Top level (no bottom bar): after register the redirect lands here, and the profile pushes it.
  // PT: No nível raiz (sem barra inferior): após o cadastro o redirect cai aqui, e o perfil o empilha.
  // Notes: docs/code-notes/app-auth.md#pending-verification
  GoRoute(path: AppRoute.verifyEmail.path, builder: (context, state) => const VerifyEmailPage()),
  StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => HomeShell(shell: shell),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(path: AppRoute.summary.path, builder: (context, state) => const SummaryPage()),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: AppRoute.expenses.path,
            builder: (context, state) => const ExpenseListPage(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(path: AppRoute.profile.path, builder: (context, state) => const ProfilePage()),
        ],
      ),
    ],
  ),
];
