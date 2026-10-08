part of '../auth.dart';

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// builtin（自带动态码）登录失败。[statusCode] / [errorCode] / [retryAfter]
/// 对应服务端契约：401 验证码错误、403 `totp_setup_required`（需先绑定验证器）、
/// 429 失败过多（[retryAfter] 为剩余秒数）。
class BuiltinLoginException implements Exception {
  const BuiltinLoginException(
    this.message, {
    this.statusCode,
    this.errorCode,
    this.retryAfter,
  });

  final String message;
  final int? statusCode;
  final String? errorCode;
  final int? retryAfter;

  /// 服务端要求先绑定验证器（首次使用）。
  bool get setupRequired =>
      statusCode == 403 && errorCode == 'totp_setup_required';

  @override
  String toString() => message;
}

/// 一份令牌集（access / refresh / id + 过期时刻）。
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    this.expiresAt,
    this.builtin = false,
  });

  final String accessToken;
  final String? refreshToken;
  final String? idToken;

  /// access_token 的绝对过期时刻（expires_in 换算；未知为 null）。
  final DateTime? expiresAt;

  /// 是否 builtin（自带动态码）令牌：12h 有效、无 refresh_token。
  final bool builtin;

  /// 是否已过期（留 60s 提前量，避免边界上刚发出就过期）。
  bool get isExpired {
    final e = expiresAt;
    if (e == null) return false;
    return DateTime.now().isAfter(e.subtract(const Duration(seconds: 60)));
  }
}
