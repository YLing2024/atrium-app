part of '../api.dart';

/* ============ 通知中心 ============ */

/// GET /api/admin/notifications?limit=&before=&unread=1&level=&source=&type=
/// → { items: [{id, ts, level, source, type, title, body, link, readAt}], unread, total }
/// ts / readAt 为 epoch 秒；before 传列表最后一条的 id（按 id 倒序翻页）。
/// type 为通知类别（服务端定义），与 unread / level / source 可叠加。
Future<Map<String, dynamic>> notificationsApiList({
  int limit = 50,
  int? before,
  bool unreadOnly = false,
  String? level,
  String? source,
  String? type,
}) async {
  final query = <String, String>{'limit': '$limit'};
  if (before != null) query['before'] = '$before';
  if (unreadOnly) query['unread'] = '1';
  if (level != null && level.isNotEmpty) query['level'] = level;
  if (source != null && source.isNotEmpty) query['source'] = source;
  if (type != null && type.isNotEmpty) query['type'] = type;
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/notifications', query));
  return Api._decode(res);
}

/// GET /api/admin/notifications/types
/// → { types: [{ key, label, description, defaultLevel, sort, enabled, count, unread }] }
///
/// 类别由服务端定义，客户端**不内置任何清单**；服务端新增类别无需发版。
Future<List<NotificationType>> notificationsApiTypes() async {
  final res = await Api._get(
    Api._uri(kApiBase, '/api/admin/notifications/types'),
  );
  final data = Api._decode(res);
  final raw = data['types'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => NotificationType.fromJson(Map<String, dynamic>.from(m)))
      .toList();
}

/// POST /api/admin/notifications/{id}/read -> { ok: true }
Future<void> notificationsApiRead(int id) async {
  final res = await Api._post(Api._uri(kApiBase, '/api/admin/notifications/$id/read'));
  Api._decode(res);
}

/// POST /api/admin/notifications/read-all -> { ok: true, count: N }
Future<int> notificationsApiReadAll() async {
  final res = await Api._post(Api._uri(kApiBase, '/api/admin/notifications/read-all'));
  final data = Api._decode(res);
  final count = data['count'];
  return count is num ? count.toInt() : 0;
}

/// DELETE /api/admin/notifications/{id} -> { ok: true }
Future<void> notificationsApiDelete(int id) async {
  final res = await Api._delete(Api._uri(kApiBase, '/api/admin/notifications/$id'));
  Api._decode(res);
}

/// POST /api/admin/notifications
///   { level, source, title, body?, link?, dedupKey? } -> 201 { id, ts }
///
/// 调试页发测试通知用。为展示「最近一次调用的状态码与响应体」，这里不抛异常，
/// 原样返回 [ApiCallResult]；401 仍触发全局登出（与其它请求一致）。
Future<ApiCallResult> notificationsApiCreate(
  Map<String, dynamic> payload,
) async {
  final res = await Api._post(
    Api._uri(kApiBase, '/api/admin/notifications'),
    body: jsonEncode(payload),
  );
  return ApiCallResult(status: res.statusCode, body: utf8.decode(res.bodyBytes));
}
