import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

class _User extends Model with Authenticatable {
  @override
  String get table => 'users';

  @override
  String get resource => 'users';
}

/// A vault whose write of the refresh token waits for [gate].
class _HeldRefreshVault extends FakeVaultService {
  _HeldRefreshVault(this.gate);

  final Completer<void> gate;

  /// Completes when the refresh-token write has started and is waiting.
  final Completer<void> refreshWriteStarted = Completer<void>();

  @override
  Future<void> put(String key, String value) async {
    if (key == 'refresh_token') {
      refreshWriteStarted.complete();
      await gate.future;
    }

    return super.put(key, value);
  }
}

/// The refresh endpoint's answer, rotating the access token.
final MagicResponse _rotated = MagicResponse(
  data: <String, dynamic>{'token': 'rotated-token'},
  statusCode: 200,
);

/// A guard with a refresh endpoint, so [BaseGuard.refreshToken] runs for real.
class _RefreshingGuard extends BaseGuard {
  _RefreshingGuard({super.userFactory})
    : super(refreshEndpoint: '/refresh', refreshTokenKey: 'refresh_token');

  @override
  Future<void> login(Map<String, dynamic> data, Authenticatable user) =>
      startSession(
        user,
        token: data['token'] as String?,
        refreshToken: data['refresh_token'] as String?,
      );
}

/// A vault whose writes and deletes land one at a time, in the order they
/// were issued, as `MagicVaultService`'s do, and which holds the write of
/// [holdValue]
/// until [release] completes, and the answer of a read of [holdReadKey]
/// until [readRelease] completes.
class _SerialHoldingVault extends FakeVaultService {
  /// The key whose read answers late with the value it read at once, or
  /// null to hold no read.
  String? holdReadKey;

  /// Completes when the held read has taken its value and is waiting.
  final Completer<void> readTaken = Completer<void>();

  /// Lets the held read answer.
  final Completer<void> readRelease = Completer<void>();

  /// Reads take their place in the order too, as `MagicVaultService._run`
  /// gives them; a held read gives its place up once it has its value.
  @override
  Future<String?> get(String key) async {
    final value = await _inOrder(() => super.get(key));

    if (key == holdReadKey && !readTaken.isCompleted) {
      readTaken.complete();
      await readRelease.future;
    }

    return value;
  }

  /// The value whose write is held, or null to hold nothing.
  String? holdValue;

  /// Completes when the held write has started and is waiting.
  final Completer<void> holdStarted = Completer<void>();

  /// Opens the gate the held write is waiting on.
  final Completer<void> release = Completer<void>();

  Future<void> _tail = Future<void>.value();

  /// The value whose write fails as a locked keychain's does, or null.
  String? refuseValue;

  /// The key whose delete waits for [removeRelease], or null.
  String? holdRemoveKey;

  /// Lets the held delete run.
  final Completer<void> removeRelease = Completer<void>();

  @override
  Future<void> put(String key, String value) => _inOrder(() async {
    if (value == holdValue) {
      holdStarted.complete();
      await release.future;
    }
    if (value == refuseValue) throw MagicVaultException('keychain locked');

    await super.put(key, value);
  });

  @override
  Future<void> remove(String key) => _inOrder(() async {
    if (key == holdRemoveKey) await removeRelease.future;

    await super.remove(key);
  });

  /// Runs [operation] after every one issued before it. A failure reaches
  /// the caller and does not stop the ones issued after it.
  Future<T> _inOrder<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _) {});

    return result;
  }
}

/// A 401 carrying whatever headers the request actually went out with.
MagicError _unauthorized(Map<String, dynamic> headers) => MagicError(
  request: MagicRequest(url: '/notifications', method: 'GET', headers: headers),
  response: MagicResponse(data: null, statusCode: 401),
);

void main() {
  late FakeAuthManager auth;

  setUp(() {
    MagicApp.reset();
    Magic.flush();
    Log.fake();
    auth = Auth.fake(user: _User()..setRawAttributes({'id': 1}, sync: true));
  });

  test('a 401 on a request that carried no credential leaves the session alone', () async {
    // The failure this covers, measured in a browser against a consumer app:
    // the app opens a guest session on launch, and a DIFFERENT request that was
    // dispatched before that login returned went out with no `Authorization`
    // header at all. Its 401 arrived after the login had succeeded, and this
    // interceptor read it as "the session is invalid" and logged the brand new
    // session out. A 401 on a request that sent no credential says nothing
    // about the credential the guard now holds.
    await AuthInterceptor().onError(_unauthorized(const <String, dynamic>{}));

    auth.assertLoggedIn();
  });

  test('a 401 on a request that carried the token still ends the session', () async {
    // The other half, and the reason the check is on the header rather than on
    // a flag: a token the server actually rejected must still end the session,
    // because this app has no refresh endpoint to fall back on.
    await AuthInterceptor().onError(
      _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
    );

    auth.assertLoggedOut();
  });

  test('the header is matched whatever casing the request carried', () async {
    // Header names are case-insensitive on the wire, and Dio keeps the casing
    // of the FIRST insertion: a caller that passed `authorization` explicitly
    // still owns that key after `onRequest` writes `Authorization` into it, and
    // the error hands back the lowercase one. An exact-key lookup would read a
    // presented token as absent and keep a session the server just refused.
    await AuthInterceptor().onError(
      _unauthorized(<String, dynamic>{'authorization': 'Bearer a-token'}),
    );

    auth.assertLoggedOut();
  });

  test('the header the request is judged by is the configured one', () async {
    // `onRequest` writes whichever header `auth.token.header` names, so the
    // reader has to look for the same one or a consumer that renames it gets
    // the bug back with no test failing.
    Config.set('auth', <String, dynamic>{
      'token': <String, dynamic>{'header': 'X-Auth', 'prefix': 'Bearer'},
    });

    await AuthInterceptor().onError(
      _unauthorized(<String, dynamic>{'X-Auth': 'Bearer a-token'}),
    );

    auth.assertLoggedOut();
  });

  group('against a guard that holds a token', () {
    // `FakeAuthManager`'s guard is not a `BaseGuard`, so it has no token to
    // compare against. A real guard over a faked vault is the seam that does.
    late BaseGuard guard;

    setUp(() async {
      MagicApp.reset();
      Magic.flush();
      Log.fake();
      Vault.fake();
      Magic.singleton('auth', AuthManager.new);

      guard = Auth.guard() as BaseGuard;
      await guard.storeToken('fresh-token');
      guard.setUser(_User()..setRawAttributes({'id': 1}, sync: true));
    });

    test(
      'a 401 on a token the guard no longer holds keeps the session',
      () async {
        // The same race with a credential in it: a request dispatched with the
        // token restored at boot is refused, a sign-in stores a new token while
        // that refusal is in flight, and the late 401 is about the old token.
        // Ending the session on it ends one the server never judged. It is
        // not replayed with the new token either: a rotation and a different
        // account signing in look the same from here.
        final http = Http.fake();

        final result = await AuthInterceptor().onError(
          _unauthorized(<String, dynamic>{
            'Authorization': 'Bearer stale-token',
          }),
        );

        expect(result, isA<MagicError>());
        expect(guard.check(), isTrue);
        expect(guard.cachedToken, 'fresh-token');
        http.assertNothingSent();
      },
    );

    test('a 401 on a token after a sign-out is left alone', () async {
      // Nothing newer to replay with, and nothing left to end.
      final http = Http.fake();
      await guard.logout();

      final result = await AuthInterceptor().onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer fresh-token'}),
      );

      expect(result, isA<MagicError>());
      http.assertNothingSent();
    });

    test('a 401 on the token the guard holds still ends the session', () async {
      await AuthInterceptor().onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer fresh-token'}),
      );

      expect(guard.check(), isFalse);
      expect(guard.cachedToken, isNull);
    });
  });

  test('a retry after a refresh carries the new token exactly once', () async {
    // The retry reuses the refused request's own header map, which is a plain
    // copy of Dio's and so case-sensitive. A caller that sent `authorization`
    // left that key in place beside the `Authorization` the retry wrote, and
    // the retry went out carrying the refused token as well as the fresh one.
    MagicApp.reset();
    Magic.flush();
    Log.fake();
    Vault.fake();
    final http = Http.fake(
      (MagicRequest request) => request.url == '/refresh'
          ? _rotated
          : MagicResponse(data: <String, dynamic>{}, statusCode: 200),
    );
    Config.set('auth', <String, dynamic>{
      'defaults': <String, dynamic>{'guard': 'api'},
      'guards': <String, dynamic>{
        'api': <String, dynamic>{'driver': 'refreshing'},
      },
    });
    Magic.singleton('auth', AuthManager.new);
    Auth.manager
      ..extend('refreshing', (_) => _RefreshingGuard())
      ..forgetGuards();
    await (Auth.guard() as BaseGuard).storeToken('old-token', 'old-refresh');

    await AuthInterceptor().onError(
      _unauthorized(<String, dynamic>{'authorization': 'Bearer old-token'}),
    );

    final sent = http.recorded
        .singleWhere((entry) => entry.$1.url == '/notifications')
        .$1
        .headers
        .entries
        .where((entry) => entry.key.toLowerCase() == 'authorization')
        .map((entry) => entry.value)
        .toList();
    expect(sent, <String>['Bearer rotated-token']);
  });

  test(
    'a retry that yields nothing hands back the request as it was sent',
    () async {
      // The retry used to rewrite the refused request's own header map, so
      // the error returned when the retry failed advertised a token that
      // request never carried.
      MagicApp.reset();
      Magic.flush();
      Log.fake();
      Vault.fake();
      Http.fake(
        (MagicRequest request) =>
            request.url == '/refresh' ? _rotated : throw StateError('offline'),
      );
      Config.set('auth', <String, dynamic>{
        'defaults': <String, dynamic>{'guard': 'api'},
        'guards': <String, dynamic>{
          'api': <String, dynamic>{'driver': 'refreshing'},
        },
      });
      Magic.singleton('auth', AuthManager.new);
      Auth.manager
        ..extend('refreshing', (_) => _RefreshingGuard())
        ..forgetGuards();
      await (Auth.guard() as BaseGuard).storeToken('old-token', 'old-refresh');

      final result = await AuthInterceptor().onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer old-token'}),
      );

      expect(result, isA<MagicError>());
      expect(
        (result as MagicError).request!.headers['Authorization'],
        'Bearer old-token',
      );
      expect((Auth.guard() as BaseGuard).cachedToken, 'rotated-token');
    },
  );

  test(
    'a 401 on the old token during a sign-in keeps the token it wrote',
    () async {
      // `startSession` moves the in-memory token before its Vault writes. With
      // the writes first, a request that went out with the old token and was
      // refused while the refresh token was being written matched the token
      // the guard still held, ran the ladder, and its logout deleted the
      // access token the sign-in had just written.
      MagicApp.reset();
      Magic.flush();
      Log.fake();
      final refreshWrite = Completer<void>();
      final vault = _HeldRefreshVault(refreshWrite);
      Magic.app.setInstance('vault', vault);
      Config.set('auth', <String, dynamic>{
        'defaults': <String, dynamic>{'guard': 'api'},
        'guards': <String, dynamic>{
          'api': <String, dynamic>{'driver': 'with-refresh-key'},
        },
      });
      Magic.singleton('auth', AuthManager.new);
      Auth.manager
        ..extend(
          'with-refresh-key',
          (_) => BearerTokenGuard(refreshTokenKey: 'refresh_token'),
        )
        ..forgetGuards();
      final guard = Auth.guard() as BaseGuard;
      await guard.storeToken('old-token');

      final signingIn = guard.login({
        'token': 'new-token',
        'refresh_token': 'new-refresh',
      }, _User()..setRawAttributes({'id': 2}, sync: true));
      await vault.refreshWriteStarted.future;
      await AuthInterceptor().onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer old-token'}),
      );
      refreshWrite.complete();
      await signingIn;

      expect(guard.check(), isTrue);
      expect(await Vault.get('auth_token'), 'new-token');
    },
  );

  group('a refresh across a change of session', () {
    // A request refused under one session must never be replayed with another
    // session's token, and a refresh started under one session must never
    // store its token into another. Account A's 401 starts a refresh; account
    // B signs in, or the session ends, while it is in the air.
    late BaseGuard guard;
    late _SerialHoldingVault vault;
    late FakeNetworkDriver http;
    late MagicResponse refreshAnswer;
    late bool holdRefresh;
    late int refreshCount;
    late Completer<void> refreshArrived;
    late Completer<void> refreshRelease;

    setUp(() async {
      MagicApp.reset();
      Magic.flush();
      Log.fake();
      vault = _SerialHoldingVault();
      Magic.app.setInstance('vault', vault);
      refreshAnswer = MagicResponse(
        data: <String, dynamic>{
          'token': 'a2-token',
          'refresh_token': 'a2-refresh',
        },
        statusCode: 200,
      );
      holdRefresh = false;
      refreshCount = 0;
      refreshArrived = Completer<void>();
      refreshRelease = Completer<void>();
      http = Http.fake((MagicRequest request) async {
        if (request.url != '/refresh') {
          return MagicResponse(data: <String, dynamic>{}, statusCode: 200);
        }

        refreshCount++;
        if (!refreshArrived.isCompleted) refreshArrived.complete();
        if (holdRefresh) await refreshRelease.future;

        return refreshAnswer;
      });
      Config.set('auth', <String, dynamic>{
        'defaults': <String, dynamic>{'guard': 'api'},
        'guards': <String, dynamic>{
          'api': <String, dynamic>{'driver': 'refreshing'},
        },
      });
      Magic.singleton('auth', AuthManager.new);
      Auth.manager
        ..extend('refreshing', (_) => _RefreshingGuard())
        ..forgetGuards();
      guard = Auth.guard() as BaseGuard;

      await guard.login(<String, dynamic>{
        'token': 'a-token',
        'refresh_token': 'a-refresh',
      }, _User()..setRawAttributes({'id': 1}, sync: true));
    });

    /// Every credential the refused request was replayed with.
    List<Object?> replays() => http.recorded
        .where((entry) => entry.$1.url == '/notifications')
        .map((entry) => entry.$1.headers['Authorization'])
        .toList();

    Future<void> signInB() => guard.login(<String, dynamic>{
      'token': 'b-token',
      'refresh_token': 'b-refresh',
    }, _User()..setRawAttributes({'id': 2}, sync: true));

    test(
      'a refresh within one session still retries with the new token',
      () async {
        final result = await AuthInterceptor().onError(
          _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
        );

        expect(result, isA<MagicResponse>());
        expect(replays(), <Object?>['Bearer a2-token']);
        expect(guard.cachedToken, 'a2-token');
        expect(await Vault.get('auth_token'), 'a2-token');
        expect(await Vault.get('refresh_token'), 'a2-refresh');
      },
    );

    test('two 401s at once still refresh once', () async {
      holdRefresh = true;
      final interceptor = AuthInterceptor();

      final first = interceptor.onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
      );
      final second = interceptor.onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
      );
      await refreshArrived.future;
      refreshRelease.complete();
      await Future.wait<dynamic>([first, second]);

      expect(refreshCount, 1);
      expect(guard.cachedToken, 'a2-token');
    });

    test(
      'a sign-in during the refresh write is not replayed with its token',
      () async {
        // The refresh moves the in-memory token before its Vault write, and
        // the interceptor used to read the credential to retry with only
        // after the refresh returned: by then it was B's, and A's request
        // went out under B's token, answering B's screen with A's question.
        vault.holdValue = 'a2-token';

        final refusal = AuthInterceptor().onError(
          _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
        );
        await vault.holdStarted.future;
        final signingIn = signInB();
        vault.release.complete();
        final result = await refusal;
        await signingIn;

        expect(result, isA<MagicError>());
        expect(replays(), isEmpty);
        expect(guard.id(), 2);
        expect(guard.cachedToken, 'b-token');
        expect(await Vault.get('auth_token'), 'b-token');
        expect(await Vault.get('refresh_token'), 'b-refresh');
      },
    );

    test('a sign-in during the refresh request keeps its own token', () async {
      // The refresh stored whatever the endpoint answered, whoever had signed
      // in since it was sent: B was left holding A's token in memory and in
      // the Vault.
      holdRefresh = true;

      final refusal = AuthInterceptor().onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
      );
      await refreshArrived.future;
      await signInB();
      refreshRelease.complete();
      final result = await refusal;

      expect(guard.id(), 2);
      expect(guard.cachedToken, 'b-token');
      expect(await Vault.get('auth_token'), 'b-token');
      expect(await Vault.get('refresh_token'), 'b-refresh');
      expect(result, isA<MagicError>());
      expect(replays(), isEmpty);
    });

    test('a sign-out during the refresh request stays signed out', () async {
      holdRefresh = true;

      final refusal = AuthInterceptor().onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
      );
      await refreshArrived.future;
      await guard.logout();
      refreshRelease.complete();
      final result = await refusal;

      expect(guard.check(), isFalse);
      expect(guard.cachedToken, isNull);
      expect(await Vault.get('auth_token'), isNull);
      expect(await Vault.get('refresh_token'), isNull);
      expect(result, isA<MagicError>());
      expect(replays(), isEmpty);
    });

    test('a refused refresh does not end a session opened during it', () async {
      // A failed refresh logs out, and that logout used to land on whoever
      // held the guard by then.
      holdRefresh = true;
      refreshAnswer = MagicResponse(data: null, statusCode: 401);

      final refusal = AuthInterceptor().onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
      );
      await refreshArrived.future;
      await signInB();
      refreshRelease.complete();
      final result = await refusal;

      expect(result, isA<MagicError>());
      expect(guard.check(), isTrue);
      expect(guard.id(), 2);
      expect(guard.cachedToken, 'b-token');
    });

    test('a restore that loads another token discards the refresh', () async {
      // Another path stored B's token, and a restore picked it up while A's
      // refresh was in the air.
      holdRefresh = true;

      final refusal = AuthInterceptor().onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
      );
      await refreshArrived.future;
      await Vault.put('auth_token', 'b-token');
      await guard.restore();
      refreshRelease.complete();
      final result = await refusal;

      expect(result, isA<MagicError>());
      expect(replays(), isEmpty);
      expect(guard.cachedToken, 'b-token');
      expect(await Vault.get('auth_token'), 'b-token');
    });

    test('a restore of the same session lets the refresh land', () async {
      // `Auth.restore()` runs after a profile save or a team switch, on the
      // same token. Discarding a refresh for it would drop a token the
      // server has already rotated to.
      holdRefresh = true;

      final refusal = AuthInterceptor().onError(
        _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
      );
      await refreshArrived.future;
      await guard.restore();
      refreshRelease.complete();
      final result = await refusal;

      expect(result, isA<MagicResponse>());
      expect(replays(), <Object?>['Bearer a2-token']);
      expect(guard.cachedToken, 'a2-token');
    });

    test(
      'a restore that read the disk before the refresh wrote it lets it land',
      () async {
        // The restore's read answered with the pre-refresh token after the
        // refresh had already moved the in-memory one. Read as another
        // session, it put the stale token back and the refresh skipped its
        // refresh-token write, so the next 401 refreshed with a token the
        // server had rotated away and the account was logged out.
        holdRefresh = true;
        vault
          ..holdReadKey = 'auth_token'
          ..holdValue = 'a2-token';

        final refusal = AuthInterceptor().onError(
          _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
        );
        await refreshArrived.future;
        final restoring = guard.restore();
        await vault.readTaken.future;
        refreshRelease.complete();
        await vault.holdStarted.future;
        vault.readRelease.complete();
        await restoring;
        vault.release.complete();
        final result = await refusal;

        expect(await Vault.get('refresh_token'), 'a2-refresh');
        expect(guard.cachedToken, 'a2-token');
        expect(result, isA<MagicResponse>());
        expect(replays(), <Object?>['Bearer a2-token']);
      },
    );

    test(
      "a sign-in without a refresh token does not keep the previous one",
      () async {
        // B signing in over A with no refresh token of its own used to
        // inherit A's, and B's next 401 traded it for A's access token.
        await guard.login(<String, dynamic>{
          'token': 'b-token',
        }, _User()..setRawAttributes({'id': 2}, sync: true));

        expect(await Vault.get('refresh_token'), isNull);

        await AuthInterceptor().onError(
          _unauthorized(<String, dynamic>{'Authorization': 'Bearer b-token'}),
        );

        expect(refreshCount, 0);
        expect(guard.cachedToken, isNot('a2-token'));
      },
    );

    test(
      'a sign-in without a refresh token during the refresh write gets none',
      () async {
        vault.holdValue = 'a2-token';

        final refusal = AuthInterceptor().onError(
          _unauthorized(<String, dynamic>{'Authorization': 'Bearer a-token'}),
        );
        await vault.holdStarted.future;
        final signingIn = guard.login(<String, dynamic>{
          'token': 'b-token',
        }, _User()..setRawAttributes({'id': 2}, sync: true));
        vault.release.complete();
        await refusal;
        await signingIn;

        expect(guard.cachedToken, 'b-token');
        expect(await Vault.get('refresh_token'), isNull);
      },
    );

    test(
      'a sign-in that carries no token does not keep the previous one',
      () async {
        // A login whose data names the token under another key (`access_token`)
        // reaches `startSession` with none, and B went on sending A's token, in
        // memory and again after a restart.
        await guard.login(<String, dynamic>{
          'access_token': 'b-token',
        }, _User()..setRawAttributes({'id': 2}, sync: true));

        expect(guard.cachedToken, isNull);
        expect(await Vault.get('auth_token'), isNull);
        expect(await Vault.get('refresh_token'), isNull);
      },
    );

    test(
      'a sign-in through storeToken during the refresh request keeps its token',
      () async {
        // A custom guard whose login is `storeToken` then `setUser` opened no
        // new session, so A's refresh answer was written over B's tokens.
        holdRefresh = true;

        final refreshing = guard.refreshToken();
        await refreshArrived.future;
        await guard.storeToken('b-token', 'b-refresh');
        guard.setUser(_User()..setRawAttributes({'id': 2}, sync: true));
        refreshRelease.complete();

        expect(await refreshing, isFalse);
        expect(guard.cachedToken, 'b-token');
        expect(await Vault.get('auth_token'), 'b-token');
        expect(await Vault.get('refresh_token'), 'b-refresh');
      },
    );

    test(
      'a sign-in whose stale refresh-token delete fails keeps the old session',
      () async {
        // The delete ran after B's token was held and stored, so a locked
        // keychain failed the login with B's token in memory and on disk
        // under A's user.
        vault.throwOnRemove();

        await expectLater(
          guard.login(<String, dynamic>{
            'token': 'b-token',
          }, _User()..setRawAttributes({'id': 2}, sync: true)),
          throwsA(isA<MagicVaultException>()),
        );

        expect(guard.cachedToken, 'a-token');
        expect(guard.id(), 1);
        expect(await Vault.get('auth_token'), 'a-token');
        expect(await Vault.get('refresh_token'), 'a-refresh');
      },
    );

    test(
      'a restore that yields its token read to a sign-in stops there',
      () async {
        // The token read stepped aside for the sign-in, but the restore went
        // on to apply the cached user from disk over the one just signed in.
        final restoring = _RefreshingGuard(
          userFactory: (data) => _User()..setRawAttributes(data, sync: true),
        );
        await restoring.login(<String, dynamic>{
          'token': 'a-token',
          'refresh_token': 'a-refresh',
        }, _User()..setRawAttributes({'id': 1}, sync: true));
        vault.holdReadKey = 'auth_token';
        final userB = _User()..setRawAttributes({'id': 2}, sync: true);

        final restored = restoring.restore();
        await vault.readTaken.future;
        await restoring.login(<String, dynamic>{
          'token': 'b-token',
          'refresh_token': 'b-refresh',
        }, userB);
        vault.readRelease.complete();
        await restored;

        expect(identical(restoring.user(), userB), isTrue);
        expect(restoring.cachedToken, 'b-token');
      },
    );

    test(
      'a restore does not apply a cached user read before a sign-in',
      () async {
        // The cached-user read is an await too: A's user, read from disk
        // before B signed in, was set over B while B's token stayed.
        final restoring = _RefreshingGuard(
          userFactory: (data) => _User()..setRawAttributes(data, sync: true),
        );
        await restoring.login(<String, dynamic>{
          'token': 'a-token',
          'refresh_token': 'a-refresh',
        }, _User()..setRawAttributes({'id': 1}, sync: true));
        vault.holdReadKey = 'auth_user';

        final restored = restoring.restore();
        await vault.readTaken.future;
        await restoring.login(<String, dynamic>{
          'token': 'b-token',
          'refresh_token': 'b-refresh',
        }, _User()..setRawAttributes({'id': 2}, sync: true));
        vault.readRelease.complete();
        await restored;

        expect(restoring.id(), 2);
        expect(restoring.cachedToken, 'b-token');
      },
    );

    test(
      'an older sign-in does not write its refresh token into a newer one',
      () async {
        // C signs in with a refresh token, and B, with none, signs in while
        // C's access-token write is still landing. C's refresh-token write
        // came after B's delete and handed B C's refresh token.
        vault.holdValue = 'c-token';

        final signingInC = guard.login(<String, dynamic>{
          'token': 'c-token',
          'refresh_token': 'c-refresh',
        }, _User()..setRawAttributes({'id': 3}, sync: true));
        await vault.holdStarted.future;
        final signingInB = guard.login(<String, dynamic>{
          'token': 'b-token',
        }, _User()..setRawAttributes({'id': 2}, sync: true));
        vault.release.complete();
        await Future.wait<void>([signingInC, signingInB]);

        expect(guard.id(), 2);
        expect(guard.cachedToken, 'b-token');
        expect(await Vault.get('auth_token'), 'b-token');
        expect(await Vault.get('refresh_token'), isNull);
      },
    );

    test(
      'a sign-in deletes the old refresh token first and writes its own last',
      () async {
        // Written token first, refresh token second, a kill or a failure
        // between the two left B's access token beside A's refresh token.
        vault.reset();

        await guard.login(<String, dynamic>{
          'token': 'b-token',
          'refresh_token': 'b-refresh',
        }, _User()..setRawAttributes({'id': 2}, sync: true));

        expect(
          vault.recorded
              .where((op) => op.key != 'auth_user')
              .map((op) => '${op.operation} ${op.key}')
              .toList(),
          <String>[
            'remove refresh_token',
            'put auth_token',
            'put refresh_token',
          ],
        );
      },
    );

    test(
      'a sign-in whose refresh-token write fails keeps the old token in memory',
      () async {
        vault.refuseValue = 'b-refresh';

        await expectLater(
          guard.login(<String, dynamic>{
            'token': 'b-token',
            'refresh_token': 'b-refresh',
          }, _User()..setRawAttributes({'id': 2}, sync: true)),
          throwsA(isA<MagicVaultException>()),
        );

        expect(guard.cachedToken, 'a-token');
        expect(guard.id(), 1);
        expect(await Vault.get('auth_token'), 'a-token');
        expect(await Vault.get('refresh_token'), isNull);
      },
    );

    test(
      'a sign-in through storeToken drops a refresh token it lacks',
      () async {
        await guard.storeToken('b-token');

        expect(await Vault.get('refresh_token'), isNull);
      },
    );

    test(
      'a restore stops when a sign-out begins during its token read',
      () async {
        // The read answers before the sign-out's delete lands, memory has not
        // moved yet, and the restore used to apply the cached user anyway.
        final restoring = _RefreshingGuard(
          userFactory: (data) => _User()..setRawAttributes(data, sync: true),
        );
        await restoring.login(<String, dynamic>{
          'token': 'a-token',
          'refresh_token': 'a-refresh',
        }, _User()..setRawAttributes({'id': 1}, sync: true));
        vault
          ..holdReadKey = 'auth_token'
          ..holdRemoveKey = 'auth_token';
        final applied = <Object?>[];
        restoring.stateNotifier.addListener(() => applied.add(restoring.id()));

        final restored = restoring.restore();
        await vault.readTaken.future;
        final signingOut = restoring.logout();
        vault.readRelease.complete();
        await restored;
        vault.removeRelease.complete();
        await signingOut;

        expect(applied, isNot(contains(1)));
        expect(restoring.check(), isFalse);
        expect(restoring.cachedToken, isNull);
      },
    );

    test(
      'a sign-out during a sign-in leaves no access token on disk',
      () async {
        // The sign-out queued its token delete while the sign-in waited on
        // its refresh-token delete, and the sign-in's token write, queued
        // after it, put the token back: a later restore signed in again.
        vault.holdRemoveKey = 'refresh_token';

        final signingIn = guard.login(<String, dynamic>{
          'token': 'b-token',
          'refresh_token': 'b-refresh',
        }, _User()..setRawAttributes({'id': 2}, sync: true));
        final signingOut = guard.logout();
        vault.removeRelease.complete();
        await signingIn;
        await signingOut;

        expect(await Vault.get('auth_token'), isNull);
        expect(await Vault.get('refresh_token'), isNull);

        await guard.restore();

        expect(guard.cachedToken, isNull);
        expect(guard.check(), isFalse);
      },
    );

    test(
      'a failed sign-in over a pending one keeps the committed session',
      () async {
        // C is still writing when B starts, so B took C's uncommitted token
        // as the one to fall back to; C then stood down for B, B's write
        // failed, and A's user was left holding C's token.
        vault
          ..holdValue = 'c-token'
          ..refuseValue = 'b-token';

        final signingInC = guard.login(<String, dynamic>{
          'token': 'c-token',
          'refresh_token': 'c-refresh',
        }, _User()..setRawAttributes({'id': 3}, sync: true));
        await vault.holdStarted.future;
        final signingInB = guard.login(<String, dynamic>{
          'token': 'b-token',
          'refresh_token': 'b-refresh',
        }, _User()..setRawAttributes({'id': 2}, sync: true));
        vault.release.complete();
        await signingInC;
        await expectLater(signingInB, throwsA(isA<MagicVaultException>()));

        expect(guard.id(), 1);
        expect(guard.cachedToken, 'a-token');
        expect(await Vault.get('auth_token'), 'a-token');
      },
    );

    test(
      'a restore during a sign-in does not commit the old account',
      () async {
        // The sign-in deletes the refresh token before it writes its access
        // token, and a restore read queued in between read A's token, took
        // it for another session and set A's cached user; the sign-in then
        // stood down without an error.
        final restoring = _RefreshingGuard(
          userFactory: (data) => _User()..setRawAttributes(data, sync: true),
        );
        await restoring.login(<String, dynamic>{
          'token': 'a-token',
          'refresh_token': 'a-refresh',
        }, _User()..setRawAttributes({'id': 1}, sync: true));
        vault.holdRemoveKey = 'refresh_token';

        final signingIn = restoring.login(<String, dynamic>{
          'token': 'b-token',
          'refresh_token': 'b-refresh',
        }, _User()..setRawAttributes({'id': 2}, sync: true));
        final restored = restoring.restore();
        vault.removeRelease.complete();
        await Future.wait<void>([signingIn, restored]);

        expect(restoring.id(), 2);
        expect(restoring.cachedToken, 'b-token');
        expect(await Vault.get('auth_token'), 'b-token');
        expect(await Vault.get('auth_user'), contains('"id":2'));
      },
    );

    test(
      'a failed sign-in falls back to the token a refresh rotated to',
      () async {
        // The refresh's write landed after B began, so it never became the
        // committed token, and B's failure put back the token the server had
        // rotated away.
        vault
          ..holdValue = 'a2-token'
          ..refuseValue = 'b-token';

        final refreshing = guard.refreshToken();
        await vault.holdStarted.future;
        final signingIn = guard.login(<String, dynamic>{
          'token': 'b-token',
          'refresh_token': 'b-refresh',
        }, _User()..setRawAttributes({'id': 2}, sync: true));
        vault.release.complete();
        await refreshing;
        await expectLater(signingIn, throwsA(isA<MagicVaultException>()));

        expect(guard.id(), 1);
        expect(guard.cachedToken, 'a2-token');
        expect(await Vault.get('auth_token'), 'a2-token');
      },
    );

    test(
      'a sign-in that a running sign-out wins over leaves no token behind',
      () async {
        // The sign-out was already inside its token delete when the sign-in
        // began; the sign-out wins (see `auth_events_dispatch_test.dart`),
        // but the sign-in's token stayed committed and on disk, and a later
        // failed sign-in put it back under a guest.
        final plain = BearerTokenGuard();
        await plain.login(<String, dynamic>{
          'token': 'a-token',
        }, _User()..setRawAttributes({'id': 1}, sync: true));
        vault.holdRemoveKey = 'auth_token';

        final signingOut = plain.logout();
        final signingIn = plain.login(<String, dynamic>{
          'token': 's-token',
        }, _User()..setRawAttributes({'id': 2}, sync: true));
        vault.removeRelease.complete();
        await Future.wait<void>([signingOut, signingIn]);

        expect(plain.check(), isFalse);
        expect(plain.cachedToken, isNull);
        expect(await Vault.get('auth_token'), isNull);

        vault.refuseValue = 'x-token';
        await expectLater(
          plain.login(<String, dynamic>{
            'token': 'x-token',
          }, _User()..setRawAttributes({'id': 3}, sync: true)),
          throwsA(isA<MagicVaultException>()),
        );

        expect(plain.cachedToken, isNull);
      },
    );

    test(
      'a sign-in with a refresh token that a running sign-out wins over too',
      () async {
        // With a refresh token the writes interleave the other way: the
        // sign-out's `_user = null` lands before the sign-in's last write, so
        // the sign-in set its user after it and signed in with no token in
        // memory, every request going out without a header.
        vault.holdRemoveKey = 'auth_token';

        final signingOut = guard.logout();
        final signingIn = guard.login(<String, dynamic>{
          'token': 's-token',
          'refresh_token': 's-refresh',
        }, _User()..setRawAttributes({'id': 2}, sync: true));
        vault.removeRelease.complete();
        await Future.wait<void>([signingOut, signingIn]);

        expect(guard.check(), isFalse);
        expect(guard.cachedToken, isNull);
        expect(await Vault.get('auth_token'), isNull);
        expect(await Vault.get('refresh_token'), isNull);
        expect(await Vault.get('auth_user'), isNull);
      },
    );

    test(
      'a refresh that read a lost sign-in\'s refresh token stores nothing',
      () async {
        // The refresh started after the losing sign-in queued its refresh
        // token, read it, and found the session unchanged when it answered:
        // forgetting the sign-in's tokens did not end anything, so the
        // refreshed pair was written back after the sign-out.
        vault
          ..holdRemoveKey = 'auth_token'
          ..holdValue = 's-refresh';
        holdRefresh = true;
        refreshAnswer = MagicResponse(
          data: <String, dynamic>{
            'token': 's2-token',
            'refresh_token': 's2-refresh',
          },
          statusCode: 200,
        );

        final signingOut = guard.logout();
        final signingIn = guard.login(<String, dynamic>{
          'token': 's-token',
          'refresh_token': 's-refresh',
        }, _User()..setRawAttributes({'id': 2}, sync: true));
        vault.removeRelease.complete();
        await vault.holdStarted.future;
        final refreshing = guard.refreshToken();
        vault.release.complete();
        await Future.wait<void>([signingOut, signingIn]);
        await refreshArrived.future;
        refreshRelease.complete();
        await refreshing;

        expect(guard.check(), isFalse);
        expect(guard.cachedToken, isNull);
        expect(await Vault.get('auth_token'), isNull);
        expect(await Vault.get('refresh_token'), isNull);
      },
    );
  });
}
