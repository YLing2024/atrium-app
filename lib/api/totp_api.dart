part of '../api.dart';

/* ============ TOTP 重置（admin-server 代理到认证中心） ============ */

/// POST /api/admin/totp/reset -> { secret, otpauthUri, expiresIn }
Future<Map<String, dynamic>> totpApiReset() async {
  final res = await Api._post(Api._uri(kApiBase, '/api/admin/totp/reset'));
  return Api._decode(res);
}

/// POST /api/admin/totp/confirm { code }
Future<void> totpApiResetConfirm(String code) async {
  final res = await Api._post(
    Api._uri(kApiBase, '/api/admin/totp/confirm'),
    body: jsonEncode({'code': code}),
  );
  Api._decode(res);
}
