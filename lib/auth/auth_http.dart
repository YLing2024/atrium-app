part of '../auth.dart';

/* ============ 续期 / 登出 ============ */

Future<bool> _doRefresh() async {
  final current = _tokens ?? await _read();
  final rt = current?.refreshToken;
  if (rt == null || rt.isEmpty) return false;
  try {
    final res = await http
        .post(
          Uri.parse('$kAuthBase/token'),
          headers: _formHeaders,
          body: {
            'grant_type': 'refresh_token',
            'refresh_token': rt,
            'client_id': kOAuthClientId,
          },
        )
        .timeout(_kHttpTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) return false;
    final data = _json(res);
    final access = data['access_token'];
    if (access is! String || access.isEmpty) return false;
    final tokens = AuthTokens(
      accessToken: access,
      refreshToken: (data['refresh_token'] as String?) ?? rt,
      idToken: (data['id_token'] as String?) ?? current?.idToken,
      expiresAt: _expiryOf(data['expires_in']),
    );
    await _persist(tokens);
    return true;
  } catch (_) {
    return false;
  }
}

/// builtin 登出（best-effort，失败不阻断登出）：带 Bearer 让服务端作废 token。
Future<void> _builtinLogout(
  String token, {
  http.Client? client,
  String? baseUrl,
}) async {
  if (token.isEmpty) return;
  try {
    final uri = Uri.parse('${_apiBase(baseUrl)}/api/admin/logout');
    final send = client?.post ?? http.post;
    await send(
      uri,
      headers: {..._jsonHeaders, 'Authorization': 'Bearer $token'},
    ).timeout(_kRevokeTimeout);
  } catch (_) {
    /* 登出接口失败不阻断登出：本地令牌已清，无法再用 */
  }
}

Future<void> _revokeAll(AuthTokens? tokens) async {
  final refresh = tokens?.refreshToken;
  final access = tokens?.accessToken;
  if (refresh != null && refresh.isNotEmpty) {
    await _revoke(refresh);
  }
  if (access != null && access.isNotEmpty) {
    await _revoke(access);
  }
}

Future<void> _revoke(String token) async {
  try {
    await http
        .post(
          Uri.parse('$kAuthBase/revoke'),
          headers: _formHeaders,
          body: {'token': token, 'client_id': kOAuthClientId},
        )
        .timeout(_kRevokeTimeout);
  } catch (_) {
    /* 吊销失败不阻断登出：本地令牌已清，无法再用 */
  }
}

/* ============ HTTP 小工具 ============ */

const Map<String, String> _formHeaders = {
  'Content-Type': 'application/x-www-form-urlencoded',
  'Accept': 'application/json',
};

/// POST 表单，2xx 返回 JSON（失败抛 [AuthException]，带服务端 error_description）。
Future<Map<String, dynamic>> _postForm(
  Uri uri,
  Map<String, String> body,
) async {
  http.Response res;
  try {
    res = await http
        .post(uri, headers: _formHeaders, body: body)
        .timeout(_kHttpTimeout);
  } catch (e) {
    throw AuthException('网络异常：$e');
  }
  final data = _json(res);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    final desc =
        data['error_description'] ??
        data['error'] ??
        'HTTP ${res.statusCode}';
    throw AuthException('认证中心返回错误：$desc');
  }
  return data;
}

Map<String, dynamic> _json(http.Response res) {
  try {
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  } catch (_) {
    return {};
  }
}

/// builtin REST 请求头（JSON）。
const Map<String, String> _jsonHeaders = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
};

/// 解析 JSON 对象响应（非对象 / 解析失败返回空 Map）。
Map<String, dynamic> _decodeJson(http.Response res) {
  try {
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  } catch (_) {
    return {};
  }
}

int? _retryAfterOf(Map<String, dynamic> data) {
  final v = data['retryAfter'];
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// API 基址（测试可注入 [baseUrl]），去掉结尾多余斜杠。
String _apiBase(String? baseUrl) {
  final b = (baseUrl ?? kApiBase).trim();
  return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
}

DateTime? _expiryOf(dynamic expiresIn) {
  int? seconds;
  if (expiresIn is num) {
    seconds = expiresIn.toInt();
  } else if (expiresIn is String) {
    seconds = int.tryParse(expiresIn);
  }
  if (seconds == null) return null;
  return DateTime.now().add(Duration(seconds: seconds));
}
