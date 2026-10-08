import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_admin/auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// auth 纯逻辑与门面回归：不触网、不依赖设备。
/// 覆盖令牌模型边界、builtin 错误映射、常量，以及 `_apiBase` / `_retryAfterOf`
/// 经由公开 API 的可观测行为。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // 清掉上一个用例可能留在内存里的令牌；测试环境无安全存储插件，
    // clear() 会把 storageAvailable 置 false，这里复位。
    await Auth.clear();
    Auth.storageAvailable.value = true;
  });

  http.Response jsonRes(String body, int status) => http.Response(
    body,
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  group('AuthTokens', () {
    test('isExpired：null 视为不过期', () {
      expect(const AuthTokens(accessToken: 'a').isExpired, isFalse);
    });

    test('isExpired：距过期 >60s 视为不过期', () {
      final t = AuthTokens(
        accessToken: 'a',
        expiresAt: DateTime.now().add(const Duration(seconds: 61)),
      );
      expect(t.isExpired, isFalse);
    });

    test('isExpired：进入 60s 提前量即判定过期', () {
      final t = AuthTokens(
        accessToken: 'a',
        expiresAt: DateTime.now().add(const Duration(seconds: 59)),
      );
      expect(t.isExpired, isTrue);
    });

    test('isExpired：已过期', () {
      final t = AuthTokens(
        accessToken: 'a',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 5)),
      );
      expect(t.isExpired, isTrue);
    });

    test('默认值：无 refresh/id、builtin=false、expiresAt=null', () {
      const t = AuthTokens(accessToken: 'a');
      expect(t.refreshToken, isNull);
      expect(t.idToken, isNull);
      expect(t.expiresAt, isNull);
      expect(t.builtin, isFalse);
    });
  });

  group('异常', () {
    test('AuthException.toString 返回 message', () {
      expect(const AuthException('boom').toString(), 'boom');
    });

    test('BuiltinLoginException.setupRequired 仅 403 + totp_setup_required', () {
      const hit = BuiltinLoginException(
        'x',
        statusCode: 403,
        errorCode: 'totp_setup_required',
      );
      expect(hit.setupRequired, isTrue);
      expect(hit.toString(), 'x');

      expect(
        const BuiltinLoginException(
          'x',
          statusCode: 403,
          errorCode: 'other',
        ).setupRequired,
        isFalse,
      );
      expect(
        const BuiltinLoginException(
          'x',
          statusCode: 401,
          errorCode: 'totp_setup_required',
        ).setupRequired,
        isFalse,
      );
      expect(const BuiltinLoginException('x').setupRequired, isFalse);
    });
  });

  group('公开常量', () {
    test('OAuth / builtin 常量与注册值一致', () {
      expect(kOAuthClientId, 'home-admin');
      expect(kOAuthScope, 'openid profile');
      expect(kLoopbackPort, 53682);
      expect(kRedirectUri, 'http://127.0.0.1:53682/callback');
      expect(kBuiltinTokenTtl, const Duration(hours: 12));
      expect(kStorageTimeout, const Duration(seconds: 5));
    });
  });

  group('hasSession 语义（经公开 API）', () {
    test('未登录时为 false', () {
      expect(Auth.accessToken, '');
      expect(Auth.hasSession, isFalse);
      expect(Auth.isBuiltinSession, isFalse);
    });

    test('builtin 登录成功后为 true，accessToken 可读', () async {
      await Auth.loginWithCode(
        '123456',
        client: MockClient((_) async => jsonRes('{"token":"tok-1"}', 200)),
        baseUrl: 'https://api.test',
      );
      expect(Auth.accessToken, 'tok-1');
      expect(Auth.isBuiltinSession, isTrue);
      expect(Auth.hasSession, isTrue);
      expect(await Auth.ensureValidAccessToken(), isTrue);
    });

    test('clear 后回到 false 且不抛出', () async {
      await Auth.loginWithCode(
        '123456',
        client: MockClient((_) async => jsonRes('{"token":"tok-1"}', 200)),
        baseUrl: 'https://api.test',
      );
      expect(Auth.hasSession, isTrue);
      await Auth.clear();
      expect(Auth.accessToken, '');
      expect(Auth.hasSession, isFalse);
    });
  });

  group('_apiBase 结尾斜杠归一（经公开 API 观测请求 URL）', () {
    test('loginWithCode 去掉 baseUrl 结尾斜杠', () async {
      late Uri seen;
      await Auth.loginWithCode(
        '123456',
        client: MockClient((req) async {
          seen = req.url;
          return jsonRes('{"token":"t"}', 200);
        }),
        baseUrl: 'https://api.test/',
      );
      expect(seen.toString(), 'https://api.test/api/admin/login');
    });

    test('fetchTotpSetup 路径与斜杠归一', () async {
      late Uri seen;
      final uri = await Auth.fetchTotpSetup(
        client: MockClient((req) async {
          seen = req.url;
          return jsonRes('{"secret":"S"}', 200);
        }),
        baseUrl: 'https://api.test/',
      );
      expect(seen.toString(), 'https://api.test/api/admin/totp/setup');
      expect(uri, contains('secret=S'));
    });
  });

  group('_retryAfterOf / 错误映射（经 loginWithCode 观测）', () {
    Future<BuiltinLoginException?> failure(Object body, int status) async {
      try {
        await Auth.loginWithCode(
          '123456',
          client: MockClient((_) async => jsonRes(jsonEncode(body), status)),
          baseUrl: 'https://api.test',
        );
        return null;
      } on BuiltinLoginException catch (e) {
        return e;
      }
    }

    test('retryAfter 兼容数字与字符串', () async {
      expect((await failure({'error': 'x', 'retryAfter': 7}, 429))!.retryAfter, 7);
      expect((await failure({'error': 'x', 'retryAfter': '9'}, 429))!.retryAfter, 9);
      expect((await failure({'error': 'x'}, 429))!.retryAfter, isNull);
      expect(
        (await failure({'error': 'x', 'retryAfter': 'nope'}, 429))!.retryAfter,
        isNull,
      );
    });

    test('非 2xx 带出 statusCode / errorCode / error 文案', () async {
      final e = (await failure(
        {'error': '验证码不正确', 'code': 'bad_code'},
        401,
      ))!;
      expect(e.statusCode, 401);
      expect(e.errorCode, 'bad_code');
      expect(e.message, '验证码不正确');

      final noError = (await failure({}, 500))!;
      expect(noError.message, 'HTTP 500');
      expect(noError.errorCode, isNull);
    });
  });
}
