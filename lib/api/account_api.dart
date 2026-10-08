part of '../api.dart';

/// GET /api/admin/sessions -> { sessions: [{ id, deviceName, ip, isLocal,
///   location, userAgent, createdAt, lastSeenAt, expiresAt(秒), isCurrent }] }
Future<List<Map<String, dynamic>>> accountSessions() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/sessions'));
  final data = Api._decode(res);
  final list = data['sessions'];
  return (list is List)
      ? list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : [];
}

/// PUT /api/admin/sessions/{id}/name { deviceName }
Future<void> accountSessionRename(String id, String deviceName) async {
  final res = await Api._put(
    Api._uri(kApiBase, '/api/admin/sessions/${Uri.encodeComponent(id)}/name'),
    body: jsonEncode({'deviceName': deviceName}),
  );
  Api._decode(res);
}

/// DELETE /api/admin/sessions/{id}
Future<void> accountSessionDelete(String id) async {
  final res = await Api._delete(
    Api._uri(kApiBase, '/api/admin/sessions/${Uri.encodeComponent(id)}'),
  );
  Api._decode(res);
}

/* ============ 接口令牌管理（与登录设备隔离） ============ */

/// GET /api/admin/api-tokens -> { tokens: [{ id, name, note, createdAt,
///   expiresAt, lastUsedAt }] }（绝不含 token 明文）
Future<List<Map<String, dynamic>>> accountApiTokens() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/api-tokens'));
  final data = Api._decode(res);
  final list = data['tokens'];
  return (list is List)
      ? list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : [];
}

/// POST /api/admin/api-tokens { name, note, expiresInDays } -> { id, token, meta }
/// token 明文仅此一次返回
Future<Map<String, dynamic>> accountApiTokenCreate({
  required String name,
  String note = '',
  required int expiresInDays,
}) async {
  final res = await Api._post(
    Api._uri(kApiBase, '/api/admin/api-tokens'),
    body: jsonEncode({'name': name, 'note': note, 'expiresInDays': expiresInDays}),
  );
  return Api._decode(res);
}

/// PATCH /api/admin/api-tokens/{id}，可选 { name, note, expiresInDays }
Future<void> accountApiTokenUpdate(String id, Map<String, dynamic> patch) async {
  final res = await Api._patch(
    Api._uri(kApiBase, '/api/admin/api-tokens/${Uri.encodeComponent(id)}'),
    body: jsonEncode(patch),
  );
  Api._decode(res);
}

/// DELETE /api/admin/api-tokens/{id}（吊销，立即失效）
Future<void> accountApiTokenDelete(String id) async {
  final res = await Api._delete(
    Api._uri(kApiBase, '/api/admin/api-tokens/${Uri.encodeComponent(id)}'),
  );
  Api._decode(res);
}

/* ============ 服务器终端（ttyd + tmux，对齐 Web Terminal.jsx） ============ */

/// POST /api/admin/term/unlock { password } -> { ticket, expiresIn }
/// 注意：口令错误时服务端返回 401，这里不能走 _decode 的「登录过期」回调，
/// 否则输错口令会被全局登出；429 时 ApiException.retryAfter 为锁定剩余秒数。
Future<Map<String, dynamic>> accountTermUnlock(String password) async {
  // 口令错误与登录过期同为 401：这里不走 _authed 的续期/登出，避免误登出。
  // 但先确保 access 未过期，免得把「会话过期」误报成「口令不正确」。
  await Auth.ensureValidAccessToken();
  final res = await http.post(
    Api._uri(kApiBase, '/api/admin/term/unlock'),
    headers: Api._headers(),
    body: jsonEncode({'password': password}),
  );
  Map<String, dynamic> data;
  try {
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    data = (decoded is Map) ? Map<String, dynamic>.from(decoded) : {};
  } catch (_) {
    data = {};
  }
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw ApiException(
      (data['error'] as String?) ?? 'HTTP ${res.statusCode}',
      code: res.statusCode,
      retryAfter: data['retryAfter'] is num
          ? (data['retryAfter'] as num).toInt()
          : null,
    );
  }
  return data;
}

/// GET /api/admin/term/sessions -> { sessions: [{ name, attached, activity }] }
Future<List<Map<String, dynamic>>> accountTermSessions() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/term/sessions'));
  final data = Api._decode(res);
  final list = data['sessions'];
  return (list is List)
      ? list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : [];
}

/// DELETE /api/admin/term/sessions/{name}（关闭单个会话，关标签时调用）
Future<void> accountTermCloseSession(String name) async {
  final res = await Api._delete(
    Api._uri(kApiBase, '/api/admin/term/sessions/${Uri.encodeComponent(name)}'),
  );
  Api._decode(res);
}

/// POST /api/admin/term/sessions/close { names }（批量关闭，锁定/离开时调用）
Future<void> accountTermCloseSessions(List<String> names) async {
  final res = await Api._post(
    Api._uri(kApiBase, '/api/admin/term/sessions/close'),
    body: jsonEncode({'names': names}),
  );
  Api._decode(res);
}

/// 终端 WebView 地址：两个 arg 按 ttyd --url-arg 顺序传给服务端 wrapper
/// （$1=会话名，$2=票据）。鉴权不再走 URL token，改由 WebView 首帧带
/// [webviewHeaders] 的 Authorization: Bearer（网关校验）。
String accountTermUrl(String name, String ticket) =>
    Uri.parse('$kApiBase/term/').replace(queryParameters: {
      'arg': [name, ticket],
    }).toString();
