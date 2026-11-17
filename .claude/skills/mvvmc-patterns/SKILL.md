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

| Package | First needed by | In `pubspec.yaml` |
|---|---|---|
| `provider` | Page, app composition root | yes |
| `go_router` | Router, `GoRouterNavigator` | not yet |
| `dio` | `ApiClient`, `AuthInterceptor`, repository and interceptor tests | yes |
| `flutter_secure_storage` | `DeviceSecureStore` | yes |
| `flutter_localizations` (SDK) + `intl` | Page (`AppLocalizations`), `failure_messages.dart`, formatting | yes |
| `decimal` | Any model with money | not yet |
| `fake_async` (dev, pinned by `flutter_test`) | Tests with timers (`SessionNotifier.signOut` timeout) | yes |

The `core/` code of sections 2 and 7 **exists** (`app/lib/core/`); the snippets below are
condensed from it. When they disagree, the code and
[`docs/code-notes/app-core.md`](../../../docs/code-notes/app-core.md) win.

## Where does it go?

| I need to... | Layer | File |
|---|---|---|
| Parse or build a JSON payload | Model | `features/profile/_shared/data/models/user_model.dart` |
| Call an endpoint | Repository | `features/profile/_shared/data/repositories/user_repository.dart` |
| Hold loading/data/failure state, call repositories | ViewModel | `features/profile/overview/application/viewmodel/profile_view_model.dart` |
| Own text fields, focus, form key; decide where to navigate | Controller | `features/profile/overview/application/controller/profile_controller.dart` |
| Draw the screen | Page / widgets | `features/profile/overview/presentation/page/profile_page.dart` |
| Attach tokens, retry once after a refresh | `core/api/` | `auth_interceptor.dart` |
| Exchange the refresh token (single flight) | `core/api/` behind `core/session/session_refresher.dart` | `api_session_refresher.dart` |
| Build a `Dio` (D8 keeps `dio` out of `lib/app/`) | `core/api/` | `api_stack.dart` |
| Parse a `TokenResponse` (core needs it for refresh) | `core/api/` | `token_response.dart` |
| Hold the session state, wipe it | `core/session/` | `session_notifier.dart`, `token_store.dart` |
| Decide which screen a session may see | `core/router/` | `redirect.dart` (`redirectFor`), `app_router.dart` (`buildRouter`) |
| List the routes and pages, the tab shell | `app/` (references feature pages) | `app_routes.dart` |
| Validate input like the contract, for 2+ screens | `features/<f>/_shared/validation/` | `auth_validators.dart` (pure Dart, returns an error enum the View localizes) |
| A View helper shared by 2+ screens of one feature | `features/<f>/_shared/presentation/` | `auth_field_error_text.dart` (error enum → localized text) |
| A widget reused by several features, no business logic | `core/design/widgets/` | `app_text_field.dart`, `password_field.dart`, `busy_button.dart`, `form_error_banner.dart`, `centered_form_scaffold.dart`, `brand_header.dart`, `prompt_link_row.dart` |
| Form field whose error must vanish on edit (client + server), re-checked on submit | `AppTextField` / `PasswordField` (`ClearsErrorOnEdit`); never a raw `TextFormField` | `core/design/widgets/clears_error_on_edit.dart` |
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
  methodNotAllowed('method-not-allowed'),
  notAcceptable('not-acceptable'),
  emailAlreadyRegistered('email-already-registered'),
  categoryNameTaken('category-name-taken'),
  categoryInUse('category-in-use'),
  unsupportedMediaType('unsupported-media-type'),
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

  // Accepts the raw String body (see ApiClient) or a decoded map.
  factory ProblemFailure.fromResponse(int status, Object? rawBody) {
    final body = decodeJsonObject(rawBody); // json_body.dart: Map or null, never throws
    if (body == null) {
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

// api_client.dart (getJson, postJson, postNoContent today; patchJson/putJson/delete on first use)
final class ApiClient {
  const ApiClient(this._dio);

  final Dio _dio;

  Future<Map<String, Object?>> getJson(String path, {Map<String, Object?>? query}) =>
      _jsonObject(() => _dio.get<String>(path, queryParameters: query));

  // `<String>` keeps Dio from decoding: we decode, so a malformed body keeps its status.
  Future<Map<String, Object?>> _jsonObject(Future<Response<String>> Function() call) async {
    final response = await _send(call);
    final body = decodeJsonObject(response.data);
    // A 2xx without the promised JSON object fails loudly; never `?? const {}`.
    if (body == null) {
      throw ProblemFailure(status: response.statusCode ?? 0, type: ProblemType.unknown);
    }
    return body;
  }

  Future<Response<String>> _send(Future<Response<String>> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      final response = error.response;
      if (response == null) throw const NetworkFailure();
      throw ProblemFailure.fromResponse(response.statusCode ?? 0, response.data);
    }
  }
}
```

Every `Dio` is built by the factory functions in `core/api/api_stack.dart` (`apiBaseOptions`,
`buildSessionRefresher`, `buildApiClient`), never in `lib/app/` (hook D8). Base URL
`'${config.apiBaseUrl}/api/v1'`, connect 10 s / receive 20 s, `Accept: application/json,
application/problem+json`, `followRedirects: false` (a `3xx` becomes a `ProblemFailure`; a
redirect must never carry the token elsewhere), and **no `LogInterceptor`**. Dio forces JSON decoding for any type
argument other than `String` (and then a broken body throws without a response, looking like a
network error), so the stack always asks for `<String>` and decodes with `decodeJsonObject`.
Repository tests build `ApiClient(Dio(apiBaseOptions(config))..httpClientAdapter = fake)`.

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

Details learned in the auth screens: a state's `failure` field is typed `Exception` when the
ViewModel can also meet a `SecureStoreException` (login, register); a form that ends with the router
leaving the screen has a `Succeeded` state (further submits are ignored, the button stays busy); and a
form ViewModel has `clearFailure()` (Failed → Idle only; a no-op in any other state) that the
Controller calls from `onFieldEdited()` so a stale error disappears when the user edits a field.
Calling `load()`/`start()` from `initState` must not notify during build: skip the emit when the
state does not change.

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
    // validate() only shows the messages; the pure rule decides, so a plain test (no Form,
    // currentState null) still blocks. Such tests call TestWidgetsFlutterBinding.ensureInitialized()
    // because GlobalKey.currentState needs a binding. Real sibling: login_controller.dart.
    formKey.currentState?.validate();
    if (validateName(nameField.text) != null) return;
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

  // `context.read()` infers UserRepository from the parameter: the page never imports the
  // repository file (D1). The real sibling is features/auth/login/presentation/page/login_page.dart.
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => ProfileViewModel(context.read()),
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
        ProfileFailed(:final failure) => Center(child: Text(failureMessage(l10n, failure)!)),
        ProfileLoaded(:final saving, :final saveFailure) => Form(
          key: _controller.formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _controller.nameField,
                decoration: InputDecoration(
                  labelText: l10n.profileNameLabel,
                  errorText: fieldErrorMessage(l10n, saveFailure, 'name'),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? l10n.validationRequired : null,
              ),
              if (failureMessage(l10n, saveFailure, knownFields: {'name'}) case final message?)
                Text(message),
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

// core/l10n/failure_messages.dart (exists): server text is never shown.
// Null for no failure, or for a validation-error whose fields are all on the form (knownFields).
String? failureMessage(AppLocalizations l10n, Object? failure, {Set<String> knownFields = const {}}) =>
    switch (failure) {
      null => null,
      NetworkFailure() => l10n.errorNetwork,
      ProblemFailure(type: ProblemType.validationError, :final fieldErrors)
          when fieldErrors.isNotEmpty && fieldErrors.every(knownFields.contains) => null,
      ProblemFailure(type: ProblemType.validationError) => l10n.errorValidation,
      // A taken email goes under the email field (fieldErrorMessage) when the form has one.
      ProblemFailure(type: ProblemType.emailAlreadyRegistered) when knownFields.contains('email') => null,
      ProblemFailure(type: ProblemType.invalidCredentials) => l10n.errorInvalidCredentials,
      ProblemFailure(type: ProblemType.emailAlreadyRegistered) => l10n.errorEmailTaken,
      ProblemFailure(type: ProblemType.unauthorized) => l10n.errorUnauthorized,
      ProblemFailure(type: ProblemType.internalError, :final errorId?) =>
        l10n.errorUnexpectedWithId(errorId),
      SecureStoreException() => l10n.errorStorage,
      _ => l10n.errorUnexpected,
    };

// validationFieldInvalid under each field the server rejected, errorEmailTaken under 'email', else null.
String? fieldErrorMessage(AppLocalizations l10n, Object? failure, String field) => ...;
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
in memory only (a cold start refreshes once). The lifecycle is
[ADR 0011](../../../docs/decisions/0011-app-session-lifecycle.md). Build order in `lib/app/`:
`DeviceSecureStore` → `TokenStore` → `buildSessionRefresher` → `SessionNotifier` →
`buildApiClient` (the refresher never needs the session, so there is no cycle).

```dart
// core/storage/secure_store.dart (condensed): pure Dart, no plugin import, so TokenStore,
// SessionNotifier and failure_messages never pull flutter_secure_storage.
final class SecureStoreException implements Exception { ... } // operation only, never the value

abstract interface class SecureStore {
  Future<String?> read(String key); // null if absent/unreadable; SecureStoreException if transient
  Future<void> write(String key, String value); // SecureStoreException on failure
  Future<void> delete(String key); // SecureStoreException on failure
}

// core/storage/device_secure_store.dart (condensed): the only flutter_secure_storage import.
final class DeviceSecureStore implements SecureStore {
  // iOS: first_unlock_this_device (no iCloud/backup copy). Android: 11.x defaults
  // (Keystore-wrapped AES-GCM, resetOnError: true).
  const DeviceSecureStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
      );
  // read: PlatformException -25308 (keychain locked) -> SecureStoreException; any other
  // PlatformException -> delete the entry, return null. write/delete -> SecureStoreException.
}

// core/session/token_store.dart (condensed)
final class TokenStore {
  TokenStore(this._secure);

  static const refreshTokenKey = 'refresh_token';

  final SecureStore _secure;
  String? _accessToken;
  int _epoch = 0; // moved by every clear() and save(); a refresh started before must not save
  bool _deletePending = false; // a clear() whose keychain delete failed

  String? get accessToken => _accessToken;
  int get epoch => _epoch;

  // While a delete is pending: retry it and return null, so a cleared token is never read back.
  Future<String?> readRefreshToken() async { ... }

  // Sign-in = new session: moves the epoch, then persists first (after a rotation the previous
  // refresh token is already dead on the server), then exposes the access token.
  Future<void> save({required String accessToken, required String refreshToken}) async {
    _epoch++;
    await _write(refreshToken); // a successful write also clears _deletePending
    _accessToken = accessToken;
  }

  // Used by the refresher: saves only if the epoch did not move since it was read (checked before
  // and after the write; if it moved during the write, deletes what was written, unless a later
  // write, a newer sign-in, started after it).
  Future<bool> saveIfEpoch(int epoch, {required String accessToken, required String refreshToken});

  Future<void> clear() async {
    _epoch++;
    _accessToken = null;
    await _deleteStored(); // on SecureStoreException: _deletePending = true, rethrow
  }
}

// core/session/session_notifier.dart (foundation only)
enum SessionStatus { unknown, signedOut, signedIn }

class SessionNotifier extends ChangeNotifier {
  SessionNotifier({required this._tokens, required this._refresher});
  static const revokeTimeout = Duration(seconds: 5); // ADR 0011

  // status (unknown / signedOut / signedIn) + restoreFailed

  // Cold start = one refresh, shared by concurrent calls (single future).
  Future<void> restore() => _restoring ??= _restore().whenComplete(() => _restoring = null);

  Future<void> _restore() async {
    if (_status != SessionStatus.unknown) return;
    _update(SessionStatus.unknown, restoreFailed: false);
    final outcome = await _refresher.refresh();
    if (_status != SessionStatus.unknown) return; // a sign-in or wipe meanwhile already decided
    switch (outcome) {
      case Refreshed():
        _update(SessionStatus.signedIn);
      case SessionEnded():
        _update(SessionStatus.signedOut);
      case TemporaryFailure():
        _update(SessionStatus.unknown, restoreFailed: true); // token kept, user may retry
    }
  }

  // Persists first; throws SecureStoreException if it could not save (LoginViewModel shows errorStorage).
  Future<void> signIn(TokenResponse tokens) async { ... }

  // Never throws: memory is cleared even if the keychain delete fails.
  Future<void> wipe() async { ... }

  // core/ cannot import the auth repository, so the logout call is passed in.
  Future<void> signOut({required Future<void> Function(String refreshToken) revoke}) async {
    try {
      final refreshToken = await _tokens.readRefreshToken();
      if (refreshToken != null) await revoke(refreshToken).timeout(revokeTimeout);
    } on Exception {
      // best effort
    } finally {
      await wipe(); // regardless of the server
    }
  }
}

// core/session/session_refresher.dart: what the session and the interceptor depend on.
abstract interface class SessionRefresher {
  Future<RefreshOutcome> refresh(); // never throws; on SessionEnded the tokens are already cleared
}

sealed class RefreshOutcome { const RefreshOutcome(); }
final class Refreshed extends RefreshOutcome { const Refreshed(this.accessToken); final String accessToken; } // toString masks it
final class SessionEnded extends RefreshOutcome { const SessionEnded(); }
final class TemporaryFailure extends RefreshOutcome { const TemporaryFailure(); }

// core/api/api_session_refresher.dart (condensed)
final class ApiSessionRefresher implements SessionRefresher {
  ApiSessionRefresher({required this._refreshDio, required this._tokens}); // Dio WITHOUT the interceptor

  Future<RefreshOutcome>? _inFlight;

  // Single flight: every caller during a refresh awaits the same future.
  @override
  Future<RefreshOutcome> refresh() => _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  // _refresh(): epoch = tokens.epoch; read the stored token (SecureStoreException -> TemporaryFailure);
  // none -> _endSession(epoch); POST /auth/refresh with <String>;
  // 401 invalid-refresh-token -> _endSession(epoch);
  // any other DioException, malformed body, FormatException, storage failure -> TemporaryFailure;
  // 200 -> tokens.saveIfEpoch(epoch, ...) -> Refreshed(accessToken), or TemporaryFailure if refused.
  // _endSession(epoch): epoch moved (newer wipe or sign-in) -> TemporaryFailure, touch nothing;
  // else tokens.clear() (a failed delete stays pending) -> SessionEnded.
}

// core/api/auth_interceptor.dart (condensed)
final class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this._dio, // the Dio this interceptor is attached to, used for the single retry
    required this._apiBase, // Uri of `{API_BASE_URL}/api/v1`, passed by buildApiClient
    required this._tokens,
    required this._refresher,
    required this._session,
  });

  static const _retriedKey = 'snapledger.retried';
  static const _sentTokenKey = 'snapledger.sentToken';

  // Same scheme, host and port as the API base, path under /api/v1/, and not /api/v1/auth/*.
  // Checked on the final options.uri, so absolute URLs (foreign or the API's own /auth/*) count.
  bool _isProtected(Uri uri) { ... }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.remove('Authorization'); // also drops one a caller set
    options.extra.remove(_sentTokenKey);
    final token = _tokens.accessToken;
    if (token != null && _isProtected(options.uri)) {
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
    if (!unauthorized || !_isProtected(request.uri)) {
      handler.next(err); // invalid-credentials, foreign hosts and every other error are final
      return;
    }
    if (request.extra[_retriedKey] == true) {
      await _session.wipe(); // a fresh token was rejected too: the session is gone
      handler.next(err);
      return;
    }
    // A different token in memory: another request already refreshed; retry without refreshing.
    final current = _tokens.accessToken;
    if (current == null || current == request.extra[_sentTokenKey]) {
      switch (await _refresher.refresh()) { // shared single-flight future
        case Refreshed():
          break; // the retry's onRequest attaches the new token
        case SessionEnded():
          await _session.wipe(); // the refresher cleared the tokens: move the app to signed out
          handler.next(err);
          return;
        case TemporaryFailure():
          handler.next(err); // the original error; the session is kept
          return;
      }
    }
    try {
      final retry = request.copyWith(extra: {...request.extra, _retriedKey: true});
      handler.resolve(await _dio.fetch<String>(retry)); // <String>, like ApiClient
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
```

Alternative: Dio's `QueuedInterceptor` serializes every `onError`, which also gives one refresh,
but it queues unrelated errors behind it too. The shared future keeps other errors independent.

## 8. Router redirect

Needs `go_router`. The redirect reads only the session; `refreshListenable` re-runs it when the
session changes (a wipe sends the user to login from anywhere).

The route list references feature pages, so it lives in `lib/app/` (`core/` never imports
features); `redirectFor`, `AppRoute` and `AppNavigator` stay in `core/router/`.

```dart
// app/app_routes.dart: the ONLY place pages are tied to paths
final List<RouteBase> appRoutes = [
  GoRoute(path: AppRoute.splash.path, builder: (context, state) => const SplashPage()),
  GoRoute(path: AppRoute.login.path, builder: (context, state) => const LoginPage()),
  GoRoute(path: AppRoute.register.path, builder: (context, state) => const RegisterPage()),
  StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => HomeShell(shell: shell), // bottom navigation
    branches: [
      StatefulShellBranch(routes: [GoRoute(path: AppRoute.summary.path, builder: (c, s) => const SummaryPage())]),
      StatefulShellBranch(routes: [GoRoute(path: AppRoute.expenses.path, builder: (c, s) => const ExpenseListPage())]),
      StatefulShellBranch(routes: [GoRoute(path: AppRoute.profile.path, builder: (c, s) => const ProfilePage())]),
    ],
  ),
];

// core/router/app_router.dart: knows no page, receives the routes.
GoRouter buildRouter(SessionNotifier session, List<RouteBase> routes) => GoRouter(
  initialLocation: AppRoute.splash.path,
  refreshListenable: session,
  redirect: (context, state) => redirectFor(session.status, state.uri),
  routes: routes,
);

// core/router/redirect.dart: pure, so every session state and every `?from=` is unit tested.
// unknown -> /splash (keeps an allowlisted from); signedOut -> /login (keeps from for a tab);
// signedIn leaving auth/splash -> allowlisted from, else /summary. `allowedFrom` accepts only
// /summary, /expenses and /profile (no scheme, host, `//`, backslash, query, fragment).
String? redirectFor(SessionStatus status, Uri location) { ... }

// app/app_providers.dart: the GoRouter and the AppNavigator are Providers created ONCE
// (Provider<GoRouter>(create: ..., dispose: router.dispose)), never inside a build method.
```

## 9. Tests

Shared fakes and fixtures live in `test/support/` (`fake_http_adapter.dart`,
`in_memory_secure_store.dart`, `json_fixtures.dart`, `fake_auth_repository.dart`, `fake_user_repository.dart`,
`fake_navigator.dart`, `fake_session_refresher.dart` with `inMemorySession()`, and `pump_app.dart`:
`pumpApp(tester, page, providers: [...])` wraps a page in the l10n delegates under any list of
providers); a test file never keeps a private copy.
No mocking library: fakes are small classes. `test/` is not part of the package, so a `package:`
import cannot reach it: test files import `test/support/` **relatively**, after the `package:`
imports (`import '../../support/fake_http_adapter.dart';`). Hook rule D6 allows a relative import
in `test/` only when its target is under a `support/` folder and is not a `*_test.dart` file;
`lib/` stays `package:`-only. Timers (for example the 5 s logout timeout) are tested with
`fakeAsync` from `package:fake_async`, never with real delays.

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
  final List<RequestOptions> requests = []; // every request that reached the "network"

  int callsTo(String path) => requests.where((r) => r.path == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return _answer(options);
  }

  @override
  void close({bool force = false}) {}
}

// test/support/in_memory_secure_store.dart (condensed)
class InMemorySecureStore implements SecureStore {
  final Map<String, String> values = {};
  bool failRead = false, failWrite = false, failDelete = false; // throw SecureStoreException
  Future<void> Function()? beforeWrite, afterWrite; // interleave other work with a write
  // read / write / delete over `values`, honoring the flags and hooks
}

// test/support/json_fixtures.dart: jsonBody, textBody, problemBody(status, slug), fakeTokenJson(n)
ResponseBody jsonBody(int status, Object? body, {String type = 'application/json'}) =>
    textBody(status, jsonEncode(body), type: type);

// test/core/api/auth_interceptor_test.dart (condensed): the REAL stack over a fake network,
// built with the same factories as the app (api_stack.dart), only the adapter is fake.
// Imports: package: first, then '../../support/fake_http_adapter.dart' and the other support files.
Future<(TokenStore, SessionNotifier, ApiClient, FakeHttpAdapter)> signedInStack(
  Future<ResponseBody> Function(RequestOptions o) answer,
) async {
  final tokens = TokenStore(InMemorySecureStore());
  final config = AppConfig.parse('https://api.test', isRelease: true);
  final adapter = FakeHttpAdapter(answer);
  final refresher = buildSessionRefresher(config, tokens, adapter: adapter);
  final session = SessionNotifier(tokens: tokens, refresher: refresher);
  await session.signIn(TokenResponse.fromJson(fakeTokenJson(1)));
  final api = buildApiClient(config, tokens: tokens, refresher: refresher, session: session, adapter: adapter);
  return (tokens, session, api, adapter);
}

void main() {
  test('concurrent 401s trigger exactly one refresh and each request is retried once', () async {
    // A gate, not a delay: the refresh answers only after the three originals were sent.
    final threeSent = Completer<void>();
    late FakeHttpAdapter adapter;
    final (tokens, session, api, fake) = await signedInStack((o) async {
      if (o.path == '/auth/refresh') {
        await threeSent.future;
        return jsonBody(200, fakeTokenJson(2));
      }
      if (adapter.callsTo('/expenses') == 3 && !threeSent.isCompleted) threeSent.complete();
      return o.headers['Authorization'] == 'Bearer fake-access-2'
          ? jsonBody(200, {'ok': true})
          : problemBody(401, 'unauthorized');
    });
    adapter = fake;

    final results = await Future.wait([for (var i = 0; i < 3; i++) api.getJson('/expenses')]);

    expect(results, everyElement({'ok': true}));
    expect(adapter.callsTo('/auth/refresh'), 1);
    expect(await tokens.readRefreshToken(), 'fake-refresh-2');
  });
}
```

The real file also covers: `invalid-refresh-token` → wipe (memory and storage); retried request
`401` again → wipe and no third request; refresh `500` / other `4xx` / timeout / no network /
malformed `200` → session kept; `401` from `/auth/*` → no refresh; no `Authorization` on
`/auth/*` (one set by a caller is removed); absolute URLs: a foreign host, another scheme/port or a
path outside `/api/v1/` gets no token and its `401` never refreshes, the API's own absolute
`/api/v1/auth/login` gets none; older token → retry without refresh; wipe during an in-flight
refresh stays signed out (epoch); the rotated token is persisted before the retry; nothing printed
contains a token or a password (zone `print` capture). Next to it: `device_secure_store_test.dart`
answers the plugin's method channel with `PlatformException`s (locked keychain `-25308` → throws,
entry kept; other read error → entry deleted, null; write/delete → `SecureStoreException`).
