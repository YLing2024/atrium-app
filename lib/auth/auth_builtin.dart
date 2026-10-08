part of '../auth.dart';

/* ============ 登录（builtin：自带 6 位动态码） ============ */

/// builtin 登录：`POST ${kApiBase}/api/admin/login {code}` → `200 {token}`。
///
/// token 12h 有效、无 refresh；失败抛 [BuiltinLoginException]（401 验证码错误 /
/// 403 需先绑定验证器 / 429 失败过多）。`client` / `baseUrl` 仅供测试注入。
Future<void> _builtinLoginWithCode(
  String code, {
  http.Client? client,
  String? baseUrl,
}) async {
  final uri = Uri.parse('${_apiBase(baseUrl)}/api/admin/login');
  http.Response res;
  try {
    final send = client?.post ?? http.post;
    res = await send(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({'code': code}),
    ).timeout(_kHttpTimeout);
  } catch (e) {
    throw BuiltinLoginException('网络异常：$e');
  }
  final data = _decodeJson(res);
  final token = data['token'];
  if (res.statusCode >= 200 &&
      res.statusCode < 300 &&
      token is String &&
      token.isNotEmpty) {
    await _persistBuiltin(token);
    return;
  }
  throw BuiltinLoginException(
    (data['error'] as String?) ?? 'HTTP ${res.statusCode}',
    statusCode: res.statusCode,
    errorCode: data['code'] as String?,
    retryAfter: _retryAfterOf(data),
  );
}

/// 首次绑定验证器：`GET ${kApiBase}/api/admin/totp/setup`（免鉴权，已绑定则 409）。
/// 返回 otpauth URI（兼容 `otpauthUri` / 老版 `uri` / 只有 `secret`）。
Future<String> _builtinFetchTotpSetup({
  http.Client? client,
  String? baseUrl,
}) async {
  final uri = Uri.parse('${_apiBase(baseUrl)}/api/admin/totp/setup');
  http.Response res;
  try {
    final send = client?.get ?? http.get;
    res = await send(uri, headers: _jsonHeaders).timeout(_kHttpTimeout);
  } catch (e) {
    throw BuiltinLoginException('网络异常：$e');
  }
  final data = _decodeJson(res);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw BuiltinLoginException(
      (data['error'] as String?) ?? 'HTTP ${res.statusCode}',
      statusCode: res.statusCode,
      errorCode: data['code'] as String?,
      retryAfter: _retryAfterOf(data),
    );
  }
  final uriField =
      (data['otpauthUri'] as String?) ?? (data['uri'] as String?);
  if (uriField != null && uriField.isNotEmpty) return uriField;
  final secret = data['secret'];
  if (secret is String && secret.isNotEmpty) {
    // 老版本只回裸 secret：拼一个最小可用的 otpauth URI（账户名仅作展示）。
    return 'otpauth://totp/Admin?secret=$secret&issuer=Admin';
  }
  throw const BuiltinLoginException('服务端未返回绑定信息');
}
