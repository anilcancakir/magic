import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../database/eloquent/model.dart';
import '../../facades/event.dart';
import '../../facades/http.dart';
import '../../facades/log.dart';
import '../../facades/vault.dart';
import '../../support/same_value.dart';
import '../authenticatable.dart';
import '../contracts/guard.dart';
import '../events/auth_events.dart';

/// Base Guard.
///
/// Provides common functionality for all guards:
/// - User state and caching
/// - Token management (with optional refresh token)
/// - Session restoration with cache-first strategy
///
/// ## Cache Strategy
///
/// On restore:
/// 1. Load user from cache (instant)
/// 2. Sync from API in background (fresh data)
///
/// ## Extending
///
/// ```dart
/// class MyGuard extends BaseGuard {
///   MyGuard() : super(
///     userEndpoint: '/api/me',
///     userFactory: (data) => User.fromMap(data),
///   );
///
///   @override
///   Future<void> login(Map<String, dynamic> data, Authenticatable user) async {
///     await startSession(user, token: data['token'] as String?);
///   }
/// }
/// ```
abstract class BaseGuard implements Guard {
  Authenticatable? _user;
  String? _cachedToken;

  /// The token of the last session whose writes all landed (or that a
  /// restore loaded), which a failed sign-in falls back to: [_cachedToken]
  /// may meanwhile hold the token of another sign-in still in flight.
  String? _committedToken;

  /// Moves, synchronously and before any await, whenever a session opens
  /// ([startSession]), ends ([logout], [clearTokens]) or is swapped for the
  /// one on disk ([loadTokenToCache] reading a different token). An in-flight
  /// boot sync or token refresh compares it against the value it captured,
  /// which [stateNotifier] cannot do alone: it bumps only once the user is
  /// set or cleared, after the Vault awaits. A refresh rotates the token
  /// inside one session and does not move it.
  int _sessionEpoch = 0;

  /// Auth state notifier.
  ///
  /// Bumped on every auth state change (setUser, logout, restore).
  /// Allows UI to reactively rebuild when auth state transitions.
  @override
  final ValueNotifier<int> stateNotifier = ValueNotifier<int>(0);

  /// Vault keys.
  final String tokenKey;
  final String? refreshTokenKey;
  final String userCacheKey;

  /// API endpoint to fetch user data.
  final String? userEndpoint;

  /// API endpoint to refresh access token.
  final String? refreshEndpoint;

  /// Factory to create user from API response.
  final Authenticatable Function(Map<String, dynamic>)? userFactory;

  BaseGuard({
    this.tokenKey = 'auth_token',
    this.refreshTokenKey,
    this.userCacheKey = 'auth_user',
    this.userEndpoint,
    this.refreshEndpoint,
    this.userFactory,
  });

  // ---------------------------------------------------------------------------
  // User State
  // ---------------------------------------------------------------------------

  @override
  bool check() => _user != null;

  @override
  bool get guest => !check();

  @override
  T? user<T extends Model>() => _user as T?;

  @override
  dynamic id() => _user?.authIdentifier;

  @override
  @override
  void setUser(Authenticatable user) {
    _user = user;
    stateNotifier.value++;
  }

  // ---------------------------------------------------------------------------
  // Token Management
  // ---------------------------------------------------------------------------

  @override
  Future<bool> hasToken() async {
    final token = await Vault.get(tokenKey);
    return token != null && token.isNotEmpty;
  }

  @override
  Future<String?> getToken() => Vault.get(tokenKey);

  /// Cached token for sync access.
  String? get cachedToken => _cachedToken;

  /// The session [_sessionEpoch] names, for `AuthInterceptor` to tell a
  /// refreshed token of the session a request was refused under from another
  /// session's token. Only equality between two reads means anything.
  @internal
  int get sessionEpoch => _sessionEpoch;

  /// Store token (and optional refresh token).
  ///
  /// The in-memory token moves BEFORE the Vault writes, not after them. A
  /// boot sync still in the air judges a 401 by whether the token it was sent
  /// with is still the one held, and with the writes first a 401 about the
  /// old token landing between them read as a verdict on the current session:
  /// its logout deleted the token just written. A sign-in goes through
  /// [startSession] instead.
  ///
  /// Marks a new session, as [startSession] does: a token stored from outside
  /// is taken to be a sign-in, so a refresh or a boot sync in the air is
  /// discarded rather than written over it, and a stored refresh token is
  /// deleted unless [refreshToken] replaces it. A guard that rotates its own
  /// token through this pays that: its in-flight boot sync is discarded and
  /// the interceptor hands the refused request back instead of retrying it.
  /// [refreshToken]'s rotation path, which keeps the session, is the one that
  /// keeps both.
  Future<void> storeToken(String token, [String? refreshToken]) =>
      _holdThenPersist(
        token,
        refreshToken,
        epoch: ++_sessionEpoch,
        newSession: true,
      );

  /// Open a session: mark it opened and move the in-memory token, persist
  /// [token] and its [refreshToken] (deleting the stored one of each that is
  /// not given), then set [user] and cache it, unless a newer sign-in or a
  /// sign-out began in the meantime.
  ///
  /// Everything an in-flight boot sync reads moves before the first await.
  /// The sync ignores its answer once [_sessionEpoch] has moved, so neither of
  /// the two windows a sign-in used to open is reachable: with the user set a
  /// few awaits after the token, a late 200 applied the PREVIOUS account
  /// against the NEW token (0.0.17), and with the Vault writes ahead of the
  /// in-memory token, a late 401 logged out and deleted the token the sign-in
  /// had just written (0.0.18). Use this from [login] rather than
  /// [storeToken] followed by [setUser].
  ///
  /// Dispatches [AuthLogin] last, and awaits its listeners (a throwing one is
  /// logged by the dispatcher, never rethrown here), so a listener doing slow
  /// work should not await it. Not dispatched when the session ended or was
  /// replaced while the user was being cached, nor when a logout that was
  /// already mid-[clearTokens] when this login began finishes and clears
  /// [_user] before this check runs.
  @protected
  Future<void> startSession(
    Authenticatable user, {
    String? token,
    String? refreshToken,
  }) async {
    final epoch = ++_sessionEpoch;

    await _holdThenPersist(token, refreshToken, epoch: epoch, newSession: true);

    // A newer sign-in or a sign-out began during the writes, and the user is
    // theirs to set.
    if (_sessionEpoch != epoch) return;

    setUser(user);

    await cacheUser(user);

    // The cache write is an await, and a sign-out or another sign-in can begin
    // inside it. Neither should hear `AuthLogin` for this session after it has
    // ended, and a sign-out that cleared the cache before this write landed
    // would find the user back on disk. The same guard as the boot sync's.
    //
    // The epoch alone misses one case: a [logout] already inside its own
    // Vault deletes when this sign-in began. It bumped the epoch before this
    // login did, so this login's epoch is still the newest, but its
    // `_user = null` (see [logout]) can still land between `setUser` above
    // and this check, after the cached-user write yields. Comparing identity
    // catches that: a session this login no longer owns, even with a
    // matching epoch, no longer holds the user it just set.
    if (_sessionEpoch != epoch || !identical(_user, user)) {
      if (cachedToken == null) await clearUserCache();

      return;
    }

    await Event.dispatch(AuthLogin(user));
  }

  /// Move the in-memory token to [token], then persist it and [refreshToken]
  /// for the session [epoch] names.
  ///
  /// A sign-in ([newSession]) keeps nothing of the previous session: the
  /// stored refresh token is deleted first, then [token] is written (or the
  /// stored access token deleted when it is null), and [refreshToken] goes
  /// last, so no step can leave the new access token beside the previous
  /// account's refresh token. A refresh that answers no new refresh token
  /// keeps the stored one.
  ///
  /// A sign-in that a sign-out or a newer sign-in overtakes during its
  /// refresh-token delete stops there: its access-token write would land
  /// after theirs and put a token back on disk that they had removed.
  ///
  /// When a step throws ([MagicVaultException] on a locked keychain or a
  /// missing entitlement), the in-memory token goes back to what it was (for
  /// a sign-in, the token of the last session whose writes all landed), as
  /// long as the session has not changed since, and the failure propagates:
  /// a token whose session could not be stored must not ride on later
  /// requests. The Vault keeps whatever steps did land, so after a failure
  /// past the first one the previous token stays in memory while its stored
  /// refresh token is already gone, and the new access token may be on disk.
  ///
  /// A refresh's failed refresh-token write does NOT move it back. By then
  /// the new access token is on disk, and the server has already rotated the
  /// old one away, so reverting would sign requests with a token nobody
  /// accepts while the Vault holds the one that works.
  ///
  /// The refresh token is written only while the session is still [epoch]: a
  /// session opened during the access-token write may have no refresh token
  /// of its own, and must not inherit this one.
  Future<void> _holdThenPersist(
    String? token,
    String? refreshToken, {
    required int epoch,
    bool newSession = false,
  }) async {
    // A sign-in falls back to the last committed session's token, never to
    // one another sign-in still in flight was holding when this one began.
    final previous = newSession ? _committedToken : _cachedToken;
    _cachedToken = token;
    var revertible = true;

    try {
      if (newSession && refreshTokenKey != null) {
        await Vault.delete(refreshTokenKey!);

        // A sign-out or a newer sign-in queued its own writes during the
        // delete; this one's access-token write would land after them.
        if (_sessionEpoch != epoch) return;
      }

      if (token == null) {
        await Vault.delete(tokenKey);
      } else {
        await Vault.put(tokenKey, token);
      }

      revertible = newSession;
      if (_sessionEpoch != epoch) return;
      if (!newSession) _committedToken = token;

      if (refreshToken != null && refreshTokenKey != null) {
        await Vault.put(refreshTokenKey!, refreshToken);
      }

      if (_sessionEpoch == epoch) _committedToken = token;
    } catch (_) {
      if (revertible && _sessionEpoch == epoch && _cachedToken == token) {
        _cachedToken = previous;
      }

      rethrow;
    }
  }

  /// Get refresh token.
  Future<String?> getRefreshToken() async {
    if (refreshTokenKey == null) return null;
    return Vault.get(refreshTokenKey!);
  }

  /// Load token into cache.
  ///
  /// A token other than the one held is another session (another account's,
  /// or none), so [_sessionEpoch] moves with it. The same token is the same
  /// session: `Auth.restore()` after a profile save must not discard a
  /// refresh in the air that the server has already rotated to.
  ///
  /// When the session changed (a sign-in, a sign-out) or the in-memory token
  /// moved (a refresh) while the read was in the air, memory is newer than
  /// what the read saw, so nothing changes: putting the read back would undo
  /// a refresh the server already rotated.
  Future<void> loadTokenToCache() async {
    await _loadTokenToCache();
  }

  /// [loadTokenToCache], answering false when the session changed while the
  /// read was in the air, so [restore] stops rather than apply what it reads
  /// next to a session that is no longer the one it began under.
  Future<bool> _loadTokenToCache() async {
    final held = _cachedToken;
    final epoch = _sessionEpoch;
    final token = await Vault.get(tokenKey);

    if (_sessionEpoch != epoch) return false;
    if (_cachedToken != held) return true;

    if (token != held) _sessionEpoch++;
    _cachedToken = token;
    _committedToken = token;

    return true;
  }

  /// Clear all tokens.
  ///
  /// Both deletes are attempted even when the first one fails, and the first
  /// failure is rethrown once both have been tried. A vault delete throws
  /// [MagicVaultException] on a platform error (a locked keychain, a lost
  /// entitlement), and stopping at the first would leave the refresh token
  /// behind, which is a live session on the next launch.
  ///
  /// Ends the session, so [_sessionEpoch] moves before the first await, and a
  /// refresh in the air does not put its token back.
  Future<void> clearTokens() async {
    _sessionEpoch++;

    Object? failure;
    StackTrace? failureStack;

    try {
      await Vault.delete(tokenKey);
    } catch (e, stack) {
      failure = e;
      failureStack = stack;
    }
    _cachedToken = null;
    _committedToken = null;

    if (refreshTokenKey != null) {
      try {
        await Vault.delete(refreshTokenKey!);
      } catch (e, stack) {
        failure ??= e;
        failureStack ??= stack;
      }
    }

    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  // ---------------------------------------------------------------------------
  // User Caching
  // ---------------------------------------------------------------------------

  /// Cache user data to Vault.
  Future<void> cacheUser(Authenticatable user) async {
    try {
      final data = user.toMap();
      await Vault.put(userCacheKey, jsonEncode(data));
    } catch (e) {
      Log.warning('Auth: Failed to cache user: $e');
    }
  }

  /// Load user from cache.
  Future<Authenticatable?> loadCachedUser() async {
    if (userFactory == null) return null;

    try {
      final cached = await Vault.get(userCacheKey);
      if (cached == null || cached.isEmpty) return null;

      final data = jsonDecode(cached) as Map<String, dynamic>;
      return userFactory!(data);
    } catch (e) {
      Log.warning('Auth: Failed to load cached user: $e');
      return null;
    }
  }

  /// Clear cached user.
  Future<void> clearUserCache() async {
    await Vault.delete(userCacheKey);
  }

  // ---------------------------------------------------------------------------
  // Token Refresh
  // ---------------------------------------------------------------------------

  /// Trade the stored refresh token for a new access token.
  ///
  /// The answer belongs to the session the request was sent for. When a
  /// sign-in, a sign-out or a restore of another token moved [_sessionEpoch]
  /// while the request was in the air, the new token is discarded and this
  /// returns false: storing it would hand the session now held the previous
  /// account's token. The same holds for a change during the access-token
  /// write, which also skips the refresh-token write.
  @override
  Future<bool> refreshToken() async {
    if (refreshEndpoint == null || refreshTokenKey == null) {
      return false;
    }

    final epoch = _sessionEpoch;
    final refreshTokenValue = await getRefreshToken();
    if (refreshTokenValue == null) {
      Log.warning('Auth: No refresh token available');
      return false;
    }

    try {
      final response = await Http.post(
        refreshEndpoint!,
        data: {'refresh_token': refreshTokenValue},
      );

      if (!response.successful) {
        Log.warning('Auth: Token refresh failed');
        return false;
      }

      // Extract new tokens from response
      final data = response.data;
      final newToken =
          data?['token'] ??
          data?['access_token'] ??
          data?['data']?['token'] ??
          data?['data']?['access_token'];
      final newRefreshToken =
          data?['refresh_token'] ?? data?['data']?['refresh_token'];

      if (newToken is! String) return false;

      if (_sessionEpoch != epoch) {
        Log.debug('Auth: refresh answered for an ended session; discarded');

        return false;
      }

      await _holdThenPersist(
        newToken,
        newRefreshToken as String?,
        epoch: epoch,
      );
      if (_sessionEpoch != epoch) return false;

      Log.info('Auth: Token refreshed');

      return true;
    } catch (e) {
      Log.error('Auth: Token refresh error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  /// End the session.
  ///
  /// Every step is attempted, whatever the earlier ones did, and the first
  /// failure is rethrown at the end. Vault deletes throw on a platform error,
  /// and running these in sequence without that meant a locked keychain on the
  /// first delete left the cached user on disk, left the user in memory, and
  /// never bumped [stateNotifier], so the app went on rendering a signed-in
  /// session while the caller was told the logout had failed.
  ///
  /// The in-memory clear is last and unconditional on purpose: it is the part
  /// that cannot fail, so it is the part that must not be skipped. The throw
  /// still reaches the caller, because a logout that could not remove a
  /// credential is not a logout, and only the caller can decide what to say
  /// about it.
  ///
  /// [_sessionEpoch] moves first, before any await, so a boot sync answering
  /// while the deletes run is not applied to a session that is ending.
  ///
  /// [AuthLogout] means "the in-memory session ended", not "the credentials
  /// are gone": it follows the notifier bump even when a delete failed, so
  /// listeners never disagree with [stateNotifier], and it goes out before the
  /// rethrow. A listener releasing server-side state still has to gate on
  /// [hasToken]. It carries the user held when the logout began (Laravel's
  /// `SessionGuard::logout` takes it at entry the same way), which is null for
  /// a guest, and a guest logout still dispatches.
  @override
  Future<void> logout() async {
    _sessionEpoch++;
    final previous = _user;

    Object? failure;
    StackTrace? failureStack;

    try {
      await clearTokens();
    } catch (e, stack) {
      failure = e;
      failureStack = stack;
    }

    try {
      await clearUserCache();
    } catch (e, stack) {
      failure ??= e;
      failureStack ??= stack;
    }

    _user = null;
    stateNotifier.value++;

    await Event.dispatch(AuthLogout(previous));

    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  @override
  Future<void> restore() async {
    Log.debug(
      'Auth: Restoring session (tokenKey=$tokenKey, hasFactory=${userFactory != null})',
    );
    // A sign-in or a sign-out that begins during either read owns the
    // session from then on, and what the reads saw belongs to the one before
    // it, so the restore stops there. The token read's own move of the epoch
    // (it loaded another token) is the session this restore continues under.
    // A refresh moves the token without changing the session, so a token
    // read that yielded to one still restores.
    if (!await _loadTokenToCache()) return;

    if (cachedToken == null) {
      Log.debug('Auth: No token found in storage');
      return;
    }

    Log.debug('Auth: Token loaded from storage');

    // 1. Load from cache first (instant)
    final epoch = _sessionEpoch;
    final cachedUser = await loadCachedUser();
    if (_sessionEpoch != epoch) return;

    if (cachedUser != null) {
      setUser(cachedUser);
      Log.debug('Auth: Cached user restored');
    } else {
      Log.debug('Auth: No cached user found');
    }

    // 2. Sync from API (fresh data).
    //
    // Awaited only when the cache had nothing to show. `AuthServiceProvider`
    // awaits `restore()`, which holds `Magic.init()`, which holds `runApp`, so
    // anything awaited here is time the user spends looking at a blank window.
    // Against a backend that accepts the connection and then says nothing (a
    // captive portal, a dead mobile link) that is the whole client timeout: on
    // an app configured for 120s it measured as roughly two minutes of white
    // screen on a cold start, with the console stopping dead on the line above.
    //
    // With a cached user already set the screen can render now and correct
    // itself when the sync lands, which is what this class has documented as
    // its cache strategy from the start ("2. Sync from API in background").
    // Without one there is nothing to render and no honest way to route, so the
    // API is the only answer and waiting for it is the point.
    if (cachedUser != null) {
      unawaited(_syncUserFromApi());

      return;
    }

    await _syncUserFromApi();
  }

  /// Sync user data from API.
  ///
  /// [restore] fires this unawaited when the cache had a user, so the session
  /// can change while it is in the air, and two kinds of change need two
  /// different answers.
  ///
  /// A sign-in or a sign-out makes the answer about a session that no longer
  /// exists, so nothing of it is applied. Either is seen from its first line,
  /// through [_sessionEpoch], and a [setUser] from anywhere else through
  /// [stateNotifier]. A 401 used to run [logout], whose [clearTokens] deleted
  /// the token the sign-in had just stored, and a 200 used to put the
  /// previous account back in memory and on disk.
  ///
  /// A token rotation (a refresh, which bumps nothing) keeps the account, so
  /// a 200 is still applied: the interceptor's own refresh-and-retry of this
  /// very request lands here as a 200 under a new token, and on a cold start
  /// with no cached user that 200 is the only thing that can sign the user
  /// in. A 401 or 403 under a rotated token is about the token it replaced,
  /// so it ends nothing by itself: the sync is re-checked once under the
  /// current token ([afterRotation]), and that answer decides. Keeping the
  /// session on the first refusal alone left a viewer holding a token the
  /// server had just refused, when the interceptor's own refresh-and-retry of
  /// this request was the thing refused.
  ///
  /// An applied 200 dispatches [AuthRestored] with `changed` false when the
  /// answer serializes the same as the user held before it, so a listener
  /// that remounts or refetches on it can skip a sync that only confirmed the
  /// cache.
  Future<void> _syncUserFromApi({bool afterRotation = false}) async {
    if (userEndpoint == null || userFactory == null) {
      Log.debug(
        'Auth: Skipping API sync '
        '(endpoint=${userEndpoint ?? 'null'}, hasFactory=${userFactory != null})',
      );
      return;
    }

    final sentToken = cachedToken;
    final sentSession = stateNotifier.value;
    final sentEpoch = _sessionEpoch;

    try {
      final response = await Http.get(userEndpoint!);

      if (_sessionEpoch != sentEpoch || stateNotifier.value != sentSession) {
        Log.debug(
          'Auth: user sync answered for a session that has since changed; '
          'ignoring it',
        );

        return;
      }

      if (!response.successful) {
        // Only the server may end a session. A transport failure (a timeout, a
        // DNS miss, a dead mobile link) reaches here as statusCode 0, because
        // `DioNetworkDriver._handleError` has no response to report: that is
        // "nobody answered", not "your token is bad". Logging out on it threw
        // away a valid session because the phone went through a tunnel, and
        // said "Token invalid" about a server that never spoke.
        if (response.statusCode == 401 || response.statusCode == 403) {
          if (cachedToken != sentToken && !afterRotation) {
            Log.debug(
              'Auth: user sync refused a token the guard has since replaced; '
              're-checking under the current one',
            );

            return await _syncUserFromApi(afterRotation: true);
          }

          Log.warning('Auth: Token rejected by the server, logging out');
          await logout();

          return;
        }

        Log.warning(
          'Auth: user sync failed (status ${response.statusCode}); '
          'keeping the cached session',
        );

        return;
      }

      final userData = extractUserData(response.data);
      if (userData != null) {
        final user = userFactory!(userData);

        // Judged before [setUser] replaces the held user. The session checks
        // above passed, so [_user] is still the one this sync was sent for.
        final held = _user;
        final changed = held == null || !sameValue(held.toMap(), user.toMap());

        setUser(user);
        await cacheUser(user);

        // The cache write is an await, and a sign-in or sign-out can begin
        // inside it. Neither should hear `AuthRestored` for the session this
        // answer was about, and a sign-out that cleared the cache before this
        // write landed would find the user back on disk.
        if (_sessionEpoch != sentEpoch) {
          if (cachedToken == null) await clearUserCache();

          return;
        }

        Log.info('Auth: User synced from API');

        // Dispatch updated event
        await Event.dispatch(AuthRestored(user, changed: changed));
      }
    } catch (e) {
      Log.error('Auth: Sync failed: $e');
      // Keep cached user if sync fails
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Extract user data from API response.
  ///
  /// Supports common Laravel response formats:
  /// - `{ "data": { "user": {...} } }`
  /// - `{ "data": {...} }`
  /// - `{ "user": {...} }`
  /// - `{ "id": ... }` (root level)
  Map<String, dynamic>? extractUserData(Map<String, dynamic>? data) {
    if (data == null) return null;

    // Try: data.user
    if (data['data'] is Map && data['data']['user'] is Map) {
      return data['data']['user'] as Map<String, dynamic>;
    }
    // Try: data (with id)
    if (data['data'] is Map && data['data']['id'] != null) {
      return data['data'] as Map<String, dynamic>;
    }
    // Try: user
    if (data['user'] is Map) {
      return data['user'] as Map<String, dynamic>;
    }
    // Try: root level
    if (data['id'] != null) {
      return data;
    }
    return null;
  }
}
