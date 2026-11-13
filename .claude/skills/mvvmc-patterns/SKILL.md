---
name: mvvmc-patterns
description: Minimal, correct examples of every layer of the SnapLedger Flutter app (MVVMC with Provider + ChangeNotifier) - immutable Model with fromJson/toJson and money as Decimal from a string, Repository interface + ApiClient implementation with ProblemDetail mapped to a typed ApiFailure, ViewModel with a sealed state and no Flutter UI imports, Controller owning text fields and navigation intents, Page wired with Provider, context.select and AppLocalizations, AuthInterceptor with single-flight refresh and session wipe, GoRouter redirect from the session, and tests (ViewModel with a fake repository, interceptor concurrency with a fake HTTP adapter). Load when writing, planning or reviewing any code under app/, or when deciding "which layer does this belong to?".
---

# SnapLedger app patterns

Rules live in `app/CLAUDE.md`; this skill shows **how** to follow them. The examples build the
**Profile** screen (`GET /users/me`, `PATCH /users/me`) plus the session plumbing in `core/`.
They are deliberately minimal. When real code exists, **the code wins**: follow the sibling
screen and report any divergence from this skill so it gets updated.

Each example says which pub packages it needs. Packages are added to `pubspec.yaml` only in the
change that first uses them (`app/CLAUDE.md` > Stack). Comments follow the root rule (short
English line, `PT:` line, `Notes:` link); most are omitted here to keep the examples short.

| Package | First needed by |
|---|---|
| `provider` | Page, app composition root |
| `go_router` | Router, `GoRouterNavigator` |
| `dio` | `ApiClient`, `AuthInterceptor`, repository and interceptor tests |
| `flutter_secure_storage` | `DeviceSecureStore` |
| `flutter_localizations` (SDK) + `intl` | Page (`AppLocalizations`), formatting |
| `decimal` | Any model with money |

## Where does it go?

| I need to... | Layer | File |
|---|---|---|
| Parse or build a JSON payload | Model | `features/profile/_shared/data/models/user_model.dart` |
| Call an endpoint | Repository | `features/profile/_shared/data/repositories/user_repository.dart` |
| Hold loading/data/failure state, call repositories | ViewModel | `features/profile/overview/application/viewmodel/profile_view_model.dart` |
| Own text fields, focus, form key; decide where to navigate | Controller | `features/profile/overview/application/controller/profile_controller.dart` |
| Draw the screen | Page / widgets | `features/profile/overview/presentation/page/profile_page.dart` |
| Attach tokens, refresh, wipe the session | `core/api/`, `core/session/` | `auth_interceptor.dart`, `session_notifier.dart` |
| Decide which screen a session may see | `core/router/` | `app_router.dart` |
| Turn a failure into text | `core/l10n/` | `failure_messages.dart` |

## 1. Model

No package (plus `decimal` for money). Immutable, explicit casts (`strict-casts` is on).

```dart
// user_model.dart
import 'package:flutter/foundation.dart';

@immutable
class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.currency,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, Object?> json) => UserModel(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    currency: json['currency'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String name;
  final String email;
  final String currency;
  final DateTime createdAt;

  UserModel copyWith({String? name, String? currency}) => UserModel(
    id: id,
    name: name ?? this.name,
    email: email,
    currency: currency ?? this.currency,
    createdAt: createdAt,
  );
}

// update_profile_request.dart: absent and null both mean "unchanged" (contract), so nulls are omitted.
class UpdateProfileRequest {
  const UpdateProfileRequest({this.name, this.currency});

  final String? name;
  final String? currency;

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    if (currency != null) 'currency': currency,
  };
}
```

**Money** (needs `decimal`): the contract sends `"42.90"`, a string, because a binary `double`
cannot hold most cents exactly. Parse it, never `double.parse` it, and write it back with two
places. Hook rule D5 rejects `double`/`num` money fields.

```dart
// inside ExpenseModel.fromJson / ExpenseRequest.toJson
amount: Decimal.parse(json['amount'] as String),
'amount': amount.toStringAsFixed(2),
```

## 2. ApiClient and typed failures (`core/api/`)

Needs `dio`. The only place that knows Dio's exceptions; repositories receive `ApiFailure`.

```dart
// api_failure.dart
enum ProblemType {
  validationError('validation-error'),
  unauthorized('unauthorized'),
  invalidCredentials('invalid-credentials'),
  invalidRefreshToken('invalid-refresh-token'),
  forbidden('forbidden'),
  defaultCategoryReadOnly('default-category-read-only'),
  notFound('not-found'),
  emailAlreadyRegistered('email-already-registered'),
  categoryNameTaken('category-name-taken'),
  categoryInUse('category-in-use'),
  internalError('internal-error'),
  // about:blank or a slug this app version does not know: branch on status.
  unknown('');

  const ProblemType(this.slug);

  final String slug;

  static const _prefix = 'urn:snapledger:problem:';

  static ProblemType fromType(Object? type) {
    if (type is! String || !type.startsWith(_prefix)) return unknown;
    final slug = type.substring(_prefix.length);
    return values.firstWhere((p) => p != unknown && p.slug == slug, orElse: () => unknown);
  }
}

sealed class ApiFailure implements Exception {
  const ApiFailure();
}

/// No response at all: offline, DNS, timeout.
final class NetworkFailure extends ApiFailure {
  const NetworkFailure();
}

/// The API answered with a non-2xx ProblemDetail (or an unexpected body).
final class ProblemFailure extends ApiFailure {
  const ProblemFailure({
    required this.status,
    required this.type,
    this.fieldErrors = const [],
    this.errorId,
  });

  factory ProblemFailure.fromResponse(int status, Object? body) {
    if (body is! Map<String, Object?>) {
      return ProblemFailure(status: status, type: ProblemType.unknown);
    }
    final errors = body['errors'];
    return ProblemFailure(
      status: status,
      type: ProblemType.fromType(body['type']),
      fieldErrors: [
        if (errors is List<Object?>)
          for (final e in errors)
            if (e is Map<String, Object?> && e['field'] is String) e['field']! as String,
      ],
      errorId: body['errorId'] is String ? body['errorId']! as String : null,
    );
  }

  final int status;
  final ProblemType type;
  // Field names only: the message text comes from l10n, never from the server.
  final List<String> fieldErrors;
  final String? errorId;
}

// api_client.dart
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<Map<String, Object?>> getJson(String path) =>
      _send(() => _dio.get<Map<String, Object?>>(path));

  Future<Map<String, Object?>> patchJson(String path, Map<String, Object?> body) =>
      _send(() => _dio.patch<Map<String, Object?>>(path, data: body));

  Future<Map<String, Object?>> _send(
    Future<Response<Map<String, Object?>>> Function() call,
  ) async {
    try {
      final response = await call();
      return response.data ?? const {};
    } on DioException catch (e) {
      final response = e.response;
      if (response == null) throw const NetworkFailure();
      throw ProblemFailure.fromResponse(response.statusCode ?? 0, response.data);
    }
  }
}
```

The `Dio` behind it is built once in `lib/app/` with
`BaseOptions(baseUrl: '${config.apiBaseUrl}/api/v1', connectTimeout: ..., receiveTimeout: ...)`.
Dio decodes `application/problem+json` like JSON (`+json` suffix), so `response.data` is a map.

## 3. Repository

Needs nothing beyond `ApiClient`. Interface typed for fakes; implementation knows the paths.

```dart
// user_repository.dart
abstract interface class UserRepository {
  Future<UserModel> fetchCurrent();
  Future<UserModel> update(UpdateProfileRequest request);
}

final class ApiUserRepository implements UserRepository {
  const ApiUserRepository(this._api);

  final ApiClient _api;

  @override
  Future<UserModel> fetchCurrent() async => UserModel.fromJson(await _api.getJson('/users/me'));

  @override
  Future<UserModel> update(UpdateProfileRequest request) async =>
      UserModel.fromJson(await _api.patchJson('/users/me', request.toJson()));
}
```

## 4. ViewModel

Only `package:flutter/foundation.dart` (hook rule D2). State is a sealed, immutable value; a
failure is a typed `ApiFailure`, never a message.

```dart
// profile_view_model.dart
import 'package:flutter/foundation.dart';

sealed class ProfileState {
  const ProfileState();
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

final class ProfileLoaded extends ProfileState {
  const ProfileLoaded(this.user, {this.saving = false, this.saveFailure});

  final UserModel user;
  final bool saving;
  final ApiFailure? saveFailure;
}

final class ProfileFailed extends ProfileState {
  const ProfileFailed(this.failure);

  final ApiFailure failure;
}

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel(this._users);

  final UserRepository _users;
  ProfileState _state = const ProfileLoading();
  bool _disposed = false;

  ProfileState get state => _state;

  Future<void> load() async {
    _emit(const ProfileLoading());
    try {
      _emit(ProfileLoaded(await _users.fetchCurrent()));
    } on ApiFailure catch (failure) {
      _emit(ProfileFailed(failure));
    }
  }

  /// Returns whether the name was saved, so the Controller can react.
  Future<bool> rename(String name) async {
    final current = _state;
    if (current is! ProfileLoaded || current.saving) return false;
    _emit(ProfileLoaded(current.user, saving: true));
    try {
      _emit(ProfileLoaded(await _users.update(UpdateProfileRequest(name: name.trim()))));
      return true;
    } on ApiFailure catch (failure) {
      _emit(ProfileLoaded(current.user, saveFailure: failure));
      return false;
    }
  }

  // An answer that arrives after the screen closed must not notify a disposed notifier.
  void _emit(ProfileState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
```

## 5. Controller

`package:flutter/widgets.dart` is allowed here (text controllers, form keys). Navigation goes
through `AppNavigator`, an interface tests can fake.

```dart
// core/router/app_navigator.dart (needs go_router for the implementation)
enum AppRoute {
  splash('/splash'),
  login('/login'),
  register('/register'),
  summary('/summary'),
  expenses('/expenses'),
  profile('/profile'),
  categories('/profile/categories');

  const AppRoute(this.path);

  final String path;
}

abstract interface class AppNavigator {
  void goTo(AppRoute route);
  void push(AppRoute route);
}

final class GoRouterNavigator implements AppNavigator {
  const GoRouterNavigator(this._router);

  final GoRouter _router;

  @override
  void goTo(AppRoute route) => _router.go(route.path);

  @override
  void push(AppRoute route) => unawaited(_router.push<void>(route.path));
}

// profile_controller.dart
import 'package:flutter/widgets.dart';

class ProfileController {
  // Private named parameters (Dart 3.12+): callers write `viewModel:` and `navigator:`.
  ProfileController({required this._viewModel, required this._navigator});

  final ProfileViewModel _viewModel;
  final AppNavigator _navigator;
  final TextEditingController nameField = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  Future<void> start() async {
    await _viewModel.load();
    final state = _viewModel.state;
    if (state is ProfileLoaded) nameField.text = state.user.name;
  }

  Future<void> onSave() async {
    // No Form in a plain unit test: currentState is null there and validation is skipped.
    if (formKey.currentState?.validate() == false) return;
    await _viewModel.rename(nameField.text);
  }

  void onCategoriesTapped() => _navigator.push(AppRoute.categories);

  void dispose() => nameField.dispose();
}
```

## 6. Page

Needs `provider` and the generated `AppLocalizations` (`flutter_localizations`, `intl`,
`flutter: generate: true` and an `l10n.yaml` with `arb-dir: lib/l10n`,
`output-dir: lib/l10n/gen`, `nullable-getter: false`).

```dart
// profile_page.dart
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => ProfileViewModel(context.read<UserRepository>()),
    child: const _ProfileView(),
  );
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  late final ProfileController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ProfileController(
      viewModel: context.read<ProfileViewModel>(),
      navigator: context.read<AppNavigator>(),
    );
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.select((ProfileViewModel vm) => vm.state);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: switch (state) {
        ProfileLoading() => const Center(child: CircularProgressIndicator()),
        ProfileFailed(:final failure) => Center(child: Text(failureMessage(l10n, failure))),
        ProfileLoaded(:final saving, :final saveFailure) => Form(
          key: _controller.formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _controller.nameField,
                decoration: InputDecoration(labelText: l10n.profileNameLabel),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? l10n.validationRequired : null,
              ),
              if (saveFailure != null) Text(failureMessage(l10n, saveFailure)),
              FilledButton(
                onPressed: saving ? null : _controller.onSave,
                child: Text(l10n.profileSave),
              ),
              TextButton(
                onPressed: _controller.onCategoriesTapped,
                child: Text(l10n.profileCategories),
              ),
            ],
          ),
        ),
      },
    );
  }
}

// core/l10n/failure_messages.dart: server text is never shown.
String failureMessage(AppLocalizations l10n, ApiFailure failure) => switch (failure) {
  NetworkFailure() => l10n.errorNetwork,
  ProblemFailure(type: ProblemType.validationError) => l10n.errorValidation,
  ProblemFailure(type: ProblemType.notFound) => l10n.errorNotFound,
  ProblemFailure(:final errorId?) => l10n.errorUnexpectedWithId(errorId),
  ProblemFailure() => l10n.errorUnexpected,
};
```

`lib/l10n/app_en.arb` (excerpt):

```json
{
  "profileTitle": "Profile",
  "profileNameLabel": "Name",
  "profileSave": "Save",
  "errorUnexpectedWithId": "Something went wrong. Error code: {errorId}",
  "@errorUnexpectedWithId": { "placeholders": { "errorId": { "type": "String" } } }
}
```

## 7. Session, secure storage and AuthInterceptor

Needs `flutter_secure_storage` and `dio`. The refresh token is persisted; the access token lives
in memory only (a cold start refreshes once).

```dart
// core/storage/secure_store.dart
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class DeviceSecureStore implements SecureStore {
  // Keychain item readable only on this device after the first unlock (no iCloud/backup copy).
  // Android options depend on the package version: choose them when the package is added.
  const DeviceSecureStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

// core/session/token_store.dart
class TokenStore {
  TokenStore(this._secure);

  static const _refreshKey = 'refresh_token';

  final SecureStore _secure;
  String? _accessToken;

  String? get accessToken => _accessToken;

  Future<String?> readRefreshToken() => _secure.read(_refreshKey);

  // Persist first: after a rotation the previous refresh token is already dead on the server.
  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _secure.write(_refreshKey, refreshToken);
    _accessToken = accessToken;
  }

  Future<void> clear() async {
    _accessToken = null;
    await _secure.delete(_refreshKey);
  }
}

// core/session/session_notifier.dart (foundation only)
enum SessionStatus { unknown, signedOut, signedIn }

class SessionNotifier extends ChangeNotifier {
  SessionNotifier(this._tokens);

  final TokenStore _tokens;
  SessionStatus _status = SessionStatus.unknown;

  SessionStatus get status => _status;

  Future<void> restore() async => _set(
    await _tokens.readRefreshToken() == null ? SessionStatus.signedOut : SessionStatus.signedIn,
  );

  Future<void> signIn({required String accessToken, required String refreshToken}) async {
    await _tokens.save(accessToken: accessToken, refreshToken: refreshToken);
    _set(SessionStatus.signedIn);
  }

  Future<void> wipe() async {
    await _tokens.clear();
    _set(SessionStatus.signedOut);
  }

  void _set(SessionStatus next) {
    if (next == _status) return;
    _status = next;
    notifyListeners();
  }
}

// core/api/auth_interceptor.dart
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this._dio,
    required this._refreshDio,
    required this._tokens,
    required this._session,
  });

  static const _retriedKey = 'snapledger.retried';
  static const _sentTokenKey = 'snapledger.sentToken';

  final Dio _dio; // the Dio this interceptor is attached to, used for the single retry
  final Dio _refreshDio; // same base URL, WITHOUT this interceptor (no recursion)
  final TokenStore _tokens;
  final SessionNotifier _session;
  Future<String?>? _refreshing;

  static bool _isAuthPath(RequestOptions options) => options.path.startsWith('/auth/');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokens.accessToken;
    if (token != null && !_isAuthPath(options)) {
      options.headers['Authorization'] = 'Bearer $token';
      options.extra[_sentTokenKey] = token;
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final response = err.response;
    final unauthorized = response != null &&
        response.statusCode == 401 &&
        ProblemFailure.fromResponse(401, response.data).type == ProblemType.unauthorized;
    if (!unauthorized || _isAuthPath(request)) {
      handler.next(err); // invalid-credentials and every other error are final
      return;
    }
    if (request.extra[_retriedKey] == true) {
      await _session.wipe(); // a fresh token was rejected too: the session is gone
      handler.next(err);
      return;
    }
    // Another request already refreshed while this one was in flight: just retry.
    final current = _tokens.accessToken;
    final token = current != null && current != request.extra[_sentTokenKey]
        ? current
        : await _refreshOnce();
    if (token == null) {
      handler.next(err);
      return;
    }
    try {
      handler.resolve(
        await _dio.fetch<Object?>(request.copyWith(extra: {...request.extra, _retriedKey: true})),
      );
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  // Single flight: every 401 that arrives while a refresh runs awaits the same future.
  Future<String?> _refreshOnce() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<String?> _refresh() async {
    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken == null) {
      await _session.wipe();
      return null;
    }
    try {
      final response = await _refreshDio.post<Map<String, Object?>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = response.data!;
      final accessToken = body['accessToken'] as String;
      await _tokens.save(accessToken: accessToken, refreshToken: body['refreshToken'] as String);
      return accessToken;
    } on DioException catch (e) {
      final response = e.response;
      final rejected = response != null &&
          ProblemFailure.fromResponse(response.statusCode ?? 0, response.data).type ==
              ProblemType.invalidRefreshToken;
      // Only a rejected refresh token ends the session; a 500 or no network may be temporary.
      if (rejected) await _session.wipe();
      return null;
    }
  }
}
```

Alternative: Dio's `QueuedInterceptor` serializes every `onError`, which also gives one refresh,
but it queues unrelated errors behind it too. The shared future keeps other errors independent.

## 8. Router redirect

Needs `go_router`. The redirect reads only the session; `refreshListenable` re-runs it when the
session changes (a wipe sends the user to login from anywhere).

```dart
// core/router/app_router.dart
GoRouter buildRouter(SessionNotifier session) => GoRouter(
  initialLocation: AppRoute.summary.path,
  refreshListenable: session,
  redirect: (context, state) => redirectFor(session.status, state.matchedLocation),
  routes: [
    GoRoute(path: AppRoute.splash.path, builder: (_, _) => const SplashPage()),
    GoRoute(path: AppRoute.login.path, builder: (_, _) => const LoginPage()),
    GoRoute(path: AppRoute.register.path, builder: (_, _) => const RegisterPage()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomeShell(shell: shell), // bottom navigation
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: AppRoute.summary.path, builder: (_, _) => const SummaryPage())]),
        StatefulShellBranch(routes: [GoRoute(path: AppRoute.expenses.path, builder: (_, _) => const ExpenseListPage())]),
        StatefulShellBranch(routes: [GoRoute(path: AppRoute.profile.path, builder: (_, _) => const ProfilePage())]),
      ],
    ),
  ],
);

// A pure function, so every session state is unit tested without widgets.
String? redirectFor(SessionStatus status, String location) {
  final onAuth = location == AppRoute.login.path || location == AppRoute.register.path;
  return switch (status) {
    SessionStatus.unknown => location == AppRoute.splash.path ? null : AppRoute.splash.path,
    SessionStatus.signedOut => onAuth ? null : AppRoute.login.path,
    SessionStatus.signedIn =>
      onAuth || location == AppRoute.splash.path ? AppRoute.summary.path : null,
  };
}
```

## 9. Tests

Shared fakes live in `test/support/`. No mocking library: fakes are small classes.

**ViewModel with a fake repository** (plain `test`, no widgets):

```dart
// test/support/fake_user_repository.dart
class FakeUserRepository implements UserRepository {
  FakeUserRepository(this.user);

  UserModel user;
  ApiFailure? failure;

  @override
  Future<UserModel> fetchCurrent() async => failure == null ? user : throw failure!;

  @override
  Future<UserModel> update(UpdateProfileRequest request) async {
    if (failure != null) throw failure!;
    return user = user.copyWith(name: request.name);
  }
}

// test/features/profile/overview/application/viewmodel/profile_view_model_test.dart
void main() {
  final ana = UserModel(
    id: '6f1c2a4e-8b0d-4c39-9a51-2f7e0d3b9c11',
    name: 'Ana',
    email: 'ana@example.com',
    currency: 'BRL',
    createdAt: DateTime.utc(2026, 11, 10),
  );

  test('loads the current user', () async {
    final viewModel = ProfileViewModel(FakeUserRepository(ana));

    await viewModel.load();

    expect(viewModel.state, isA<ProfileLoaded>().having((s) => s.user.name, 'name', 'Ana'));
  });

  test('keeps the old user and exposes the failure when saving fails', () async {
    final repository = FakeUserRepository(ana);
    final viewModel = ProfileViewModel(repository);
    await viewModel.load();
    repository.failure = const ProblemFailure(status: 400, type: ProblemType.validationError);

    final saved = await viewModel.rename('  ');

    expect(saved, isFalse);
    expect(
      viewModel.state,
      isA<ProfileLoaded>()
          .having((s) => s.user.name, 'name', 'Ana')
          .having((s) => s.saveFailure, 'saveFailure', isA<ProblemFailure>()),
    );
  });
}
```

**Interceptor concurrency** with a fake `HttpClientAdapter` (needs `dio`). The token strings are
obviously fake: tests never contain a real token.

```dart
// test/support/fake_http_adapter.dart
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this._answer);

  final Future<ResponseBody> Function(RequestOptions options) _answer;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _answer(options);

  @override
  void close({bool force = false}) {}
}

// test/support/in_memory_secure_store.dart
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

ResponseBody jsonBody(int status, Map<String, Object?> body, {String type = 'application/json'}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [type],
    });

// test/core/api/auth_interceptor_test.dart
void main() {
  test('concurrent 401s trigger exactly one refresh and every request is retried once', () async {
    final tokens = TokenStore(InMemorySecureStore());
    await tokens.save(accessToken: 'fake-access-1', refreshToken: 'fake-refresh-1');
    final session = SessionNotifier(tokens);
    var refreshCalls = 0;
    final adapter = FakeHttpAdapter((options) async {
      if (options.path == '/auth/refresh') {
        refreshCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20)); // keep it in flight
        return jsonBody(200, {
          'accessToken': 'fake-access-2',
          'tokenType': 'Bearer',
          'expiresIn': 900,
          'refreshToken': 'fake-refresh-2',
          'refreshExpiresIn': 2592000,
        });
      }
      return options.headers['Authorization'] == 'Bearer fake-access-2'
          ? jsonBody(200, {'ok': true})
          : jsonBody(401, {'type': 'urn:snapledger:problem:unauthorized', 'status': 401},
              type: 'application/problem+json');
    });
    final options = BaseOptions(baseUrl: 'https://api.test/api/v1');
    final dio = Dio(options)..httpClientAdapter = adapter;
    final refreshDio = Dio(options)..httpClientAdapter = adapter;
    dio.interceptors.add(
      AuthInterceptor(dio: dio, refreshDio: refreshDio, tokens: tokens, session: session),
    );

    final responses = await Future.wait([for (var i = 0; i < 3; i++) dio.get<Object?>('/expenses')]);

    expect(refreshCalls, 1);
    expect(responses.map((r) => r.statusCode), everyElement(200));
    expect(await tokens.readRefreshToken(), 'fake-refresh-2');
  });

  test('wipes the session when the refresh token is rejected', () async {
    final tokens = TokenStore(InMemorySecureStore());
    await tokens.save(accessToken: 'fake-access-1', refreshToken: 'fake-refresh-1');
    final session = SessionNotifier(tokens);
    await session.restore();
    final adapter = FakeHttpAdapter((options) async => options.path == '/auth/refresh'
        ? jsonBody(401, {'type': 'urn:snapledger:problem:invalid-refresh-token', 'status': 401},
            type: 'application/problem+json')
        : jsonBody(401, {'type': 'urn:snapledger:problem:unauthorized', 'status': 401},
            type: 'application/problem+json'));
    final options = BaseOptions(baseUrl: 'https://api.test/api/v1');
    final dio = Dio(options)..httpClientAdapter = adapter;
    final refreshDio = Dio(options)..httpClientAdapter = adapter;
    dio.interceptors.add(
      AuthInterceptor(dio: dio, refreshDio: refreshDio, tokens: tokens, session: session),
    );

    await expectLater(dio.get<Object?>('/expenses'), throwsA(isA<DioException>()));

    expect(session.status, SessionStatus.signedOut);
    expect(await tokens.readRefreshToken(), isNull);
    expect(tokens.accessToken, isNull);
  });
}
```

Also required for the interceptor (same setup, different answers): refresh answers `500` →
session untouched; a `401` from `/auth/login` → no refresh call; the retried request answers
`401` again → wipe, and no third request.
