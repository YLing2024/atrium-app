// 标准 OAuth2.1 / OIDC PKCE 登录（公开客户端，无 client_secret）。
//
// 流程（RFC 7636）：
//   1. 生成 code_verifier / code_challenge(S256) / state；
//   2. 系统浏览器打开认证中心 /authorize；
//   3. App 内起一个只监听 127.0.0.1:53682 的临时 HTTP server 收 ?code=&state=，
//      校验 state 一致后回一个「可以关闭此页」的页面并关掉 server；
//   4. 用 code + code_verifier 调 /token（不带 secret）换 access/refresh/id token；
//   5. token 存系统安全存储（Android Keystore / iOS Keychain）。
//
// 之后的 API 调用统一在 lib/api.dart 带 `Authorization: Bearer`，401 时调用
// [Auth.refresh] 静默续期并重试一次；登出走 [Auth.logout]（先清存储，再 best-effort 调 /revoke）。
//
// 并发纪律：认证中心的 refresh_token 是**一次性**的（重放会作废整条链），
// 因此全 App 只允许主 isolate 调 [refresh]；前台服务 isolate 遇到 401 只上报，
// 由主 isolate 续期后重启服务（见 lib/main.dart 与 lib/notification_service.dart）。
//
// 双模式：服务端 `AUTH_MODE=builtin` 时走 [loginWithCode]（6 位动态码，token 12h、
// 无 refresh），`sso` 时走 [login]（PKCE + refresh）。模式由 lib/auth_mode.dart
// 探测，探测失败一律按 sso（绝不改动现有 PKCE 行为）。
//
// 本文件是库根：实现按职责拆到 lib/auth/ 下的 part 文件（模型 / 存储 / PKCE /
// builtin / HTTP），[Auth] 只保留公开门面与登录态状态，调用点与签名均不变。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'pkce.dart';

part 'auth/auth_models.dart';
part 'auth/auth_storage.dart';
part 'auth/auth_pkce.dart';
part 'auth/auth_builtin.dart';
part 'auth/auth_http.dart';

/// 公开客户端 id（非机密信息，仍按约定用 --dart-define 注入，默认值即注册值）。
const String kOAuthClientId = String.fromEnvironment(
  'OAUTH_CLIENT_ID',
  defaultValue: 'home-admin',
);

/// 认证中心基址。构建时必须 `--dart-define=AUTH_BASE=https://auth.<域名>`，
/// 否则回退到占位域、登录不可用。
const String kAuthBase = String.fromEnvironment(
  'AUTH_BASE',
  defaultValue: 'https://auth.example.com',
);

/// 回环回调端口：认证中心只允许 https 或 localhost，不支持自定义 scheme；
/// 且 redirect_uri 精确匹配注册值（不许通配），故端口必须固定。
const int kLoopbackPort = 53682;

/// 注册到认证中心的回调地址，必须与客户端注册值完全一致。
const String kRedirectUri = 'http://127.0.0.1:$kLoopbackPort/callback';

/// 请求的 scope：必须含 `openid`。
const String kOAuthScope = 'openid profile';

/// 网络请求超时（换令牌 / 续期）。
const Duration _kHttpTimeout = Duration(seconds: 20);

/// 吊销请求超时（best-effort，短一点，别拖住登出）。
const Duration _kRevokeTimeout = Duration(seconds: 5);

/// PKCE 登录等待回调的总超时。
const Duration _kLoginTimeout = Duration(minutes: 5);

/// 安全存储读写超时：超过即视为不可用。
///
/// 某些设备上 KeyStore 异常会让 method channel 永久不返回（表现为启动挂住、
/// 连 `shared_prefs` 都不落盘），所以读写都必须有上限，超时按「不可用」降级。
const Duration kStorageTimeout = Duration(seconds: 5);

/// builtin 令牌有效期：服务端 12 小时有效、无 refresh，本地按签发时间 + 该时长
/// 提前判定过期（过期即回动态码登录页）。
const Duration kBuiltinTokenTtl = Duration(hours: 12);

/// 令牌与登录态的唯一入口。
class Auth {
  Auth._();

  /// 安全存储是否可用（读取/写入超时或抛错即置 false）。
  ///
  /// 不可用时仍保留**内存态**：本次会话可以正常登录与调用 API，只是**不会
  /// 持久保存**，UI 据此明确告知用户，不静默假装成功。
  static final ValueNotifier<bool> storageAvailable = ValueNotifier<bool>(true);

  /// 当前 access_token（内存缓存，空串表示无）。
  static String get accessToken => _tokens?.accessToken ?? '';

  /// 是否持有可用登录态：有 access，或有 refresh 可续期。
  ///
  /// builtin 无 refresh：令牌过期即视为无登录态（回动态码页）；sso 语义不变。
  static bool get hasSession {
    final t = _tokens;
    if (t == null) return false;
    if (t.builtin) return t.accessToken.isNotEmpty && !t.isExpired;
    return t.accessToken.isNotEmpty || (t.refreshToken?.isNotEmpty ?? false);
  }

  /// 当前是否 builtin（自带动态码）登录态。
  static bool get isBuiltinSession => _tokens?.builtin ?? false;

  /// 启动时从系统安全存储恢复令牌（前台服务 isolate 也会各自调用一次）。
  static Future<void> init() async {
    _tokens = await _read();
  }

  /// 若 access 已过期但有 refresh，则静默续期；返回是否持有可用 access。
  ///
  /// 主 isolate 启动时调用，避免「refresh 还在但 access 过期」被当成未登录。
  /// builtin 无 refresh：过期即返回 false（由调用方登出回动态码页）。
  static Future<bool> ensureValidAccessToken() async {
    final t = _tokens;
    if (t != null && t.accessToken.isNotEmpty && !t.isExpired) return true;
    if (t != null && t.builtin) return false;
    if (t != null && (t.refreshToken?.isNotEmpty ?? false)) {
      return refresh();
    }
    return t != null && t.accessToken.isNotEmpty;
  }

  /// 清空内存与安全存储中的令牌（安全存储失败不抛出：内存已清即已登出）。
  static Future<void> clear() async {
    _tokens = null;
    try {
      await Future.wait([
        _storage.delete(key: _kAccess),
        _storage.delete(key: _kRefresh),
        _storage.delete(key: _kId),
        _storage.delete(key: _kExpiry),
        _storage.delete(key: _kBuiltinAccess),
        _storage.delete(key: _kBuiltinIssuedAt),
      ]).timeout(kStorageTimeout);
    } catch (e) {
      _markStorageUnavailable(e);
    }
  }

  /* ============ 登录（PKCE） ============ */

  /// 走完整的 PKCE 登录：系统浏览器 → 回环回调 → 换令牌 → 存安全存储。
  /// 失败抛 [AuthException]（state 不一致 / 用户取消 / 超时 / 换令牌失败）。
  static Future<void> login() => _pkceLogin();

  /* ============ 登录（builtin：自带 6 位动态码） ============ */

  /// builtin 登录：`POST ${kApiBase}/api/admin/login {code}` → `200 {token}`。
  ///
  /// token 12h 有效、无 refresh；失败抛 [BuiltinLoginException]（401 验证码错误 /
  /// 403 需先绑定验证器 / 429 失败过多）。`client` / `baseUrl` 仅供测试注入。
  static Future<void> loginWithCode(
    String code, {
    http.Client? client,
    String? baseUrl,
  }) => _builtinLoginWithCode(code, client: client, baseUrl: baseUrl);

  /// 首次绑定验证器：`GET ${kApiBase}/api/admin/totp/setup`（免鉴权，已绑定则 409）。
  /// 返回 otpauth URI（兼容 `otpauthUri` / 老版 `uri` / 只有 `secret`）。
  static Future<String> fetchTotpSetup({
    http.Client? client,
    String? baseUrl,
  }) => _builtinFetchTotpSetup(client: client, baseUrl: baseUrl);

  /* ============ 续期 / 登出 ============ */

  /// 用 refresh_token 静默续期（grant_type=refresh_token，仍不带 secret）。
  /// 单飞：并发 401 只触发一次续期。成功返回 true。
  static Future<bool> refresh() {
    final existing = _refreshing;
    if (existing != null) return existing;
    final f = _doRefresh().whenComplete(() => _refreshing = null);
    _refreshing = f;
    return f;
  }

  /// 登出：先清空安全存储（同步语义，立刻不可用），再 best-effort 后台调吊销接口。
  /// sso → 认证中心 `/revoke`；builtin → `POST /api/admin/logout`（幂等）。
  /// 不做任何「静默登出后还能用」的缓存。
  static Future<void> logout() async {
    final current = _tokens ?? await _read();
    await clear();
    if (current?.builtin ?? false) {
      unawaited(_builtinLogout(current!.accessToken));
    } else {
      unawaited(_revokeAll(current));
    }
  }
}
