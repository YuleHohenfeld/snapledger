import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:snapledger/app/app_routes.dart';
import 'package:snapledger/core/api/api_client.dart';
import 'package:snapledger/core/api/api_stack.dart';
import 'package:snapledger/core/config/app_config.dart';
import 'package:snapledger/core/router/app_navigator.dart';
import 'package:snapledger/core/router/app_router.dart';
import 'package:snapledger/core/router/go_router_navigator.dart';
import 'package:snapledger/core/session/session_notifier.dart';
import 'package:snapledger/core/session/session_refresher.dart';
import 'package:snapledger/core/session/token_store.dart';
import 'package:snapledger/core/storage/device_secure_store.dart';
import 'package:snapledger/core/storage/secure_store.dart';
import 'package:snapledger/features/auth/_shared/data/repositories/auth_repository.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';

/// Every app-wide object, created once and in dependency order; [secureStore] replaces the keychain in tests.
/// PT: Todo objeto do app inteiro, criado uma vez e na ordem das dependências; [secureStore] troca o keychain nos testes.
/// Notes: docs/code-notes/app-core.md#composition-root
List<SingleChildWidget> buildAppProviders(AppConfig config, {SecureStore? secureStore}) => [
  Provider<AppConfig>.value(value: config),
  Provider<SecureStore>(create: (_) => secureStore ?? const DeviceSecureStore()),
  Provider<TokenStore>(create: (context) => TokenStore(context.read())),
  Provider<SessionRefresher>(
    create: (context) => buildSessionRefresher(config, context.read<TokenStore>()),
  ),
  ChangeNotifierProvider<SessionNotifier>(
    create: (context) => SessionNotifier(tokens: context.read(), refresher: context.read()),
  ),
  Provider<ApiClient>(
    create: (context) => buildApiClient(
      config,
      tokens: context.read(),
      refresher: context.read(),
      session: context.read(),
    ),
  ),
  // The router is built here, once, never in a build method (it would reset navigation on rebuild).
  // PT: O router é montado aqui, uma vez, nunca num build (isso zeraria a navegação a cada rebuild).
  Provider<GoRouter>(
    create: (context) => buildRouter(context.read<SessionNotifier>(), appRoutes),
    dispose: (_, router) => router.dispose(),
  ),
  Provider<AppNavigator>(create: (context) => GoRouterNavigator(context.read())),
  Provider<AuthRepository>(create: (context) => ApiAuthRepository(context.read())),
  Provider<UserRepository>(create: (context) => ApiUserRepository(context.read())),
];
