import 'package:go_router/go_router.dart';
import 'package:snapledger/app/home_shell.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/features/auth/login/presentation/page/login_page.dart';
import 'package:snapledger/features/auth/password_reset/presentation/page/password_reset_page.dart';
import 'package:snapledger/features/auth/register/presentation/page/register_page.dart';
import 'package:snapledger/features/auth/splash/presentation/page/splash_page.dart';
import 'package:snapledger/features/auth/verify_email/presentation/page/verify_email_page.dart';
import 'package:snapledger/features/categories/manage/presentation/page/category_manage_page.dart';
import 'package:snapledger/features/expenses/form/presentation/page/expense_form_page.dart';
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
            routes: [
              // Relative paths: AppRoute.expenseNew ('/expenses/new') and AppRoute.expenseEditPattern
              // ('/expenses/:id') under the list, so a deep link still has the list below it to pop to.
              // 'new' comes first: ':id' would also match it.
              // PT: Caminhos relativos: AppRoute.expenseNew e AppRoute.expenseEditPattern sob a lista, então um
              // PT: deep link ainda tem a lista embaixo para voltar. 'new' vem primeiro: ':id' também o casaria.
              // Notes: docs/code-notes/app-expenses.md#routes
              GoRoute(path: 'new', builder: (context, state) => const ExpenseFormPage()),
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    ExpenseFormPage(expenseId: state.pathParameters['id']),
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: AppRoute.profile.path,
            builder: (context, state) => const ProfilePage(),
            routes: [
              // Relative path: it is AppRoute.categories ('/profile/categories') under the profile.
              // PT: Caminho relativo: é o AppRoute.categories ('/profile/categories') sob o perfil.
              GoRoute(path: 'categories', builder: (context, state) => const CategoryManagePage()),
            ],
          ),
        ],
      ),
    ],
  ),
];
