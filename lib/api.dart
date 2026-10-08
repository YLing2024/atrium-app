import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth.dart';
import 'notification_model.dart';

part 'api/system_api.dart';
part 'api/account_api.dart';
part 'api/files_api.dart';
part 'api/blog_api.dart';
part 'api/notifications_api.dart';
part 'api/totp_api.dart';

// 构建时必须带 --dart-define 注入真实地址，否则将回退到占位域、连不上后端：
//   flutter build apk --release --dart-define=API_BASE=... --dart-define=AUTH_BASE=...

/// 管理后台 API 基址（网关注入 X-Auth-User；客户端统一带 Authorization: Bearer）。
const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://api.example.com',
);

class ApiException implements Exception {
  final String message;
  final int? code;
  final String? errorCode;
  final int? retryAfter;

  ApiException(this.message, {this.code, this.errorCode, this.retryAfter});

  bool get isAuth => code == 401;

  @override
  String toString() => message;
}

/// 原始 HTTP 调用结果：调试页展示「最近一次请求的状态码与响应体」用。
///
/// 与 [ApiException] 不同，这类调用**不抛异常**：无论 2xx 还是 4xx/5xx 都原样
/// 返回，方便把真实状态码与响应体摆到调试界面上排查。
class ApiCallResult {
  const ApiCallResult({required this.status, required this.body});

  final int status;
  final String body;

  bool get ok => status >= 200 && status < 300;

  /// 解析响应体 JSON（非对象或解析失败返回 null）。
  Map<String, dynamic>? get json {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// 创建通知返回的 id（`201 { id, ts }`）；无则 null。
  int? get id {
    final v = json?['id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// 系统趋势聚合结果（`GET /api/admin/system/metrics`）。
///
/// `points` 与 `/api/admin/system/history` 同构（字段名与单位一致，图表映射通用）；
/// `meta.recordedSeconds` 供「数据积累中（已记录 N 分钟）」空态使用。
class SystemMetrics {
  const SystemMetrics({required this.points, required this.meta});

  static const SystemMetrics empty = SystemMetrics(points: [], meta: {});

  final List<Map<String, dynamic>> points;
  final Map<String, dynamic> meta;

  /// 解析响应体：`points` 非数组 / 坏结构一律按空处理，不抛异常。
  factory SystemMetrics.fromJson(Map<String, dynamic> data) {
    final rawPoints = data['points'];
    final rawMeta = data['meta'];
    return SystemMetrics(
      points: rawPoints is List
          ? rawPoints
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
          : const [],
      meta: rawMeta is Map ? Map<String, dynamic>.from(rawMeta) : const {},
    );
  }

  /// `meta.recordedSeconds`（服务端为数字）；缺失 / 非数字 → null。
  int? get recordedSeconds {
    final v = meta['recordedSeconds'];
    return v is num ? v.toInt() : null;
  }
}

/// REST API 封装：系统监控 / 上传下载 / TOTP 重置 / 博客管理 / 通知。
///
/// 鉴权：登录态由 [Auth]（PKCE + 系统安全存储）持有，这里统一在
/// [_headers] 注入 `Authorization: Bearer`；[_authed] 在 401 时用
/// refresh_token 静默续期并重试一次，续期失败才触发全局登出。
///
/// 公共方法名与签名保持不变；每个方法都是对 `lib/api/` 下同名顶层函数的一行转发，
/// 私有辅助逻辑仍集中在本类。
class Api {
  Api._();

  /// 业务请求头：JSON 内容类型 + Bearer（无登录态时不带 Authorization）。
  static Map<String, String> _headers({bool json = true}) => {
    if (json) 'Content-Type': 'application/json',
    if (Auth.accessToken.isNotEmpty) 'Authorization': 'Bearer ${Auth.accessToken}',
  };

  /// WebView 首帧请求头（终端等无法用 http 包直达的场景）。
  static Map<String, String> webviewHeaders() => {
    if (Auth.accessToken.isNotEmpty) 'Authorization': 'Bearer ${Auth.accessToken}',
  };

  static Uri _uri(String base, String path, [Map<String, String>? query]) =>
      Uri.parse('$base$path').replace(queryParameters: query);

  /// 鉴权失效回调（401 且续期失败），由 main 注册为全局登出
  static Future<void> Function()? onAuthRequired;

  static void _notifyAuthRequired() {
    final cb = onAuthRequired;
    if (cb != null) unawaited(cb());
  }

  /* ============ 统一鉴权请求 ============ */

  /// 自动带 Bearer；401 时先用 refresh_token 续期，再原样重试一次；
  /// 仍 401 则触发全局登出（不回退到旧的 /api/admin/login）。
  static Future<http.Response> _authed(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var res = await send(_headers());
    if (res.statusCode == 401 && await Auth.refresh()) {
      res = await send(_headers());
    }
    if (res.statusCode == 401) _notifyAuthRequired();
    return res;
  }

  static Future<http.Response> _get(Uri uri) =>
      _authed((h) => http.get(uri, headers: h));

  static Future<http.Response> _post(Uri uri, {Object? body}) =>
      _authed((h) => http.post(uri, headers: h, body: body));

  static Future<http.Response> _put(Uri uri, {Object? body}) =>
      _authed((h) => http.put(uri, headers: h, body: body));

  static Future<http.Response> _patch(Uri uri, {Object? body}) =>
      _authed((h) => http.patch(uri, headers: h, body: body));

  static Future<http.Response> _delete(Uri uri) =>
      _authed((h) => http.delete(uri, headers: h));

  /// multipart 请求同样走鉴权与 401 续期重试；[build] 需可重复调用以重建文件流。
  static Future<http.Response> _sendMultipart(
    Future<http.MultipartRequest> Function(Map<String, String> headers) build, {
    Duration? timeout,
  }) async {
    Future<http.Response> send() async {
      final req = await build(_headers(json: false));
      var streamed = req.send();
      if (timeout != null) streamed = streamed.timeout(timeout);
      return http.Response.fromStream(await streamed);
    }

    var res = await send();
    if (res.statusCode == 401 && await Auth.refresh()) {
      res = await send();
    }
    if (res.statusCode == 401) _notifyAuthRequired();
    return res;
  }

  /* ============ 系统监控 ============ */

  /// GET /api/admin/system
  static Future<Map<String, dynamic>> system() => systemApiSystem();

  /// GET /api/admin/system/history -> 采样点数组（服务端直接返回 JSON 数组）
  static Future<List<dynamic>> systemHistory() => systemApiHistory();

  /// GET /api/admin/system/metrics?range=&step= -> { points, meta }
  ///
  /// 趋势聚合：`range` ∈ 1h|6h|1d|7d|30d，`step` ∈ 1m|5m|1h|1d（对齐 admin-web）。
  /// 后端对未知参数回退 `range=1d&step=1m` 并返回 200；无数据返回 `points: []`
  /// + 完整 `meta`，绝不 500。鉴权 / 401 续期沿用 [_authed] 统一链路。
  static Future<SystemMetrics> systemMetrics({
    required String range,
    required String step,
  }) => systemApiMetrics(range: range, step: step);

  /// GET /api/admin/services -> { services, processes }
  static Future<Map<String, dynamic>> services() => systemApiServices();

  /// GET /api/admin/versions -> { list }
  static Future<List<dynamic>> versions() => systemApiVersions();

  /* ============ 历史会话浏览（只读） ============ */

  /// GET /api/admin/history -> { sessions: [{ id, title, time, message_count }] }
  static Future<Map<String, dynamic>> historySessions() =>
      systemApiHistorySessions();

  /// GET /api/admin/history/{id} -> { session: { id, title }, messages: [{ role, content, ts }] }
  static Future<Map<String, dynamic>> historyMessages(String id) =>
      systemApiHistoryMessages(id);

  /* ============ 设备会话管理（认证中心转发） ============ */

  /// GET /api/admin/sessions -> { sessions: [{ id, deviceName, ip, isLocal,
  ///   location, userAgent, createdAt, lastSeenAt, expiresAt(秒), isCurrent }] }
  static Future<List<Map<String, dynamic>>> sessions() => accountSessions();

  /// PUT /api/admin/sessions/{id}/name { deviceName }
  static Future<void> sessionRename(String id, String deviceName) =>
      accountSessionRename(id, deviceName);

  /// DELETE /api/admin/sessions/{id}
  static Future<void> sessionDelete(String id) => accountSessionDelete(id);

  /* ============ 接口令牌管理（与登录设备隔离） ============ */

  /// GET /api/admin/api-tokens -> { tokens: [{ id, name, note, createdAt,
  ///   expiresAt, lastUsedAt }] }（绝不含 token 明文）
  static Future<List<Map<String, dynamic>>> apiTokens() => accountApiTokens();

  /// POST /api/admin/api-tokens { name, note, expiresInDays } -> { id, token, meta }
  /// token 明文仅此一次返回
  static Future<Map<String, dynamic>> apiTokenCreate({
    required String name,
    String note = '',
    required int expiresInDays,
  }) =>
      accountApiTokenCreate(
          name: name, note: note, expiresInDays: expiresInDays);

  /// PATCH /api/admin/api-tokens/{id}，可选 { name, note, expiresInDays }
  static Future<void> apiTokenUpdate(String id, Map<String, dynamic> patch) =>
      accountApiTokenUpdate(id, patch);

  /// DELETE /api/admin/api-tokens/{id}（吊销，立即失效）
  static Future<void> apiTokenDelete(String id) => accountApiTokenDelete(id);

  /* ============ 服务器终端（ttyd + tmux，对齐 Web Terminal.jsx） ============ */

  /// POST /api/admin/term/unlock { password } -> { ticket, expiresIn }
  /// 注意：口令错误时服务端返回 401，这里不能走 _decode 的「登录过期」回调，
  /// 否则输错口令会被全局登出；429 时 ApiException.retryAfter 为锁定剩余秒数。
  static Future<Map<String, dynamic>> termUnlock(String password) =>
      accountTermUnlock(password);

  /// GET /api/admin/term/sessions -> { sessions: [{ name, attached, activity }] }
  static Future<List<Map<String, dynamic>>> termSessions() =>
      accountTermSessions();

  /// DELETE /api/admin/term/sessions/{name}（关闭单个会话，关标签时调用）
  static Future<void> termCloseSession(String name) =>
      accountTermCloseSession(name);

  /// POST /api/admin/term/sessions/close { names }（批量关闭，锁定/离开时调用）
  static Future<void> termCloseSessions(List<String> names) =>
      accountTermCloseSessions(names);

  /// 终端 WebView 地址：两个 arg 按 ttyd --url-arg 顺序传给服务端 wrapper
  /// （$1=会话名，$2=票据）。鉴权不再走 URL token，改由 WebView 首帧带
  /// [webviewHeaders] 的 Authorization: Bearer（网关校验）。
  static String termUrl(String name, String ticket) =>
      accountTermUrl(name, ticket);

  /* ============ 上传 / 下载 ============ */

  /// POST /api/admin/upload（multipart 字段名 file）-> {path}
  static Future<String> upload(File file, String filename) =>
      filesUpload(file, filename);

  /// GET /api/admin/download?path= -> 文件字节（App 内带 Bearer 取回）
  static Future<Uint8List> download(String path) => filesDownload(path);

  /// 文件下载 URL：交给**系统浏览器**打开（鉴权由浏览器携带的网关会话 cookie 完成）。
  /// 不再把 App 的 Bearer 拼进 URL，令牌不落 URL / 浏览器历史。
  /// App 内需要带 Bearer 直接取字节时用 [download]。
  static String fileDownloadUrl(String path) => filesDownloadUrl(path);

  /// 把服务端返回的相对路径（图片 / 预览链接）拼成绝对地址；
  /// 已是 http(s)、data 等带 scheme 的地址原样返回。
  static String absoluteUrl(String path) => filesAbsoluteUrl(path);

  /* ============ 文件区（对齐 Web Files.jsx / admin-server 文件路由） ============ */

  /// GET /api/admin/files?path= -> { path, parent, entries: [{name, type, size, mtime}] }
  /// path 为相对文件区根目录的路径，根目录为 ''（越界由后端拦截）。
  /// _uri 的 queryParameters 走 Uri.encodeQueryComponent，`lost+found` 等名称编码正确。
  static Future<Map<String, dynamic>> fileList(String path) => filesList(path);

  /// POST /api/admin/files/mkdir { path, name }
  static Future<void> fileMkdir(String dir, String name) =>
      filesMkdir(dir, name);

  /// POST /api/admin/files/rename { path, name }
  static Future<void> fileRename(String path, String name) =>
      filesRename(path, name);

  /// DELETE /api/admin/files?path=（目录递归删除）
  static Future<void> fileDelete(String path) => filesDelete(path);

  /// POST /api/admin/files/upload?path=（multipart 字段名 file，上限 500MB）
  /// onProgress 回调已发送字节数（HTTP 段），落盘耗时可配合 99% 文案；
  /// abortTrigger 完成即中断上传（取消按钮）；重名后端自动加 -2。
  static Future<Map<String, dynamic>> fileUpload(
    File file,
    String filename,
    String dir, {
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) =>
      filesFileUpload(file, filename, dir,
          onProgress: onProgress, abortTrigger: abortTrigger);

  /* ============ 文件区 · 临时链接（限时分享，对齐 Web FileShare.jsx） ============ */
  // 语义对齐后端 /api/admin/files/shares：expiresAt === 0 为永久有效哨兵；
  // 分享链接一律使用后端返回的 url 字段，不拼域名。

  /// GET /api/admin/files/shares -> { shares: [...] }
  /// 列表接口正常返回 { shares }，这里兼容裸数组（双保险）。
  static Future<List<Map<String, dynamic>>> fileShares() => filesShares();

  /// POST /api/admin/files/shares { path, ttlHours? | expiresAt?, note? } -> 记录（含 url）
  /// ttlHours 与 expiresAt 二选一：expiresAt 为绝对 epoch 毫秒（0 = 永久），
  /// 都不给时后端默认 24 小时。
  static Future<Map<String, dynamic>> fileShareCreate({
    required String path,
    int? ttlHours,
    int? expiresAt,
    String? note,
  }) =>
      filesShareCreate(
          path: path, ttlHours: ttlHours, expiresAt: expiresAt, note: note);

  /// PATCH /api/admin/files/shares/{id} { expiresAt?, note?, revoked? } -> 记录
  /// expiresAt: 0 转永久；>0 改为该绝对到期时刻；revoked: true 撤销（不可逆）。
  static Future<Map<String, dynamic>> fileShareUpdate(
    String id, {
    int? expiresAt,
    String? note,
    bool? revoked,
  }) => filesShareUpdate(id, expiresAt: expiresAt, note: note, revoked: revoked);

  /// DELETE /api/admin/files/shares/{id}（仅删记录，不动磁盘文件）
  static Future<void> fileShareDelete(String id) => filesShareDelete(id);

  /// 后端直接返回记录；兼容被包一层 share 的写法（双保险）。
  static Map<String, dynamic> _shareRecord(Map<String, dynamic> data) {
    final rec = data['share'];
    return rec is Map ? Map<String, dynamic>.from(rec) : data;
  }

  /* ============ TOTP 重置（admin-server 代理到认证中心） ============ */

  /// POST /api/admin/totp/reset -> { secret, otpauthUri, expiresIn }
  static Future<Map<String, dynamic>> totpReset() => totpApiReset();

  /// POST /api/admin/totp/confirm { code }
  static Future<void> totpResetConfirm(String code) => totpApiResetConfirm(code);

  /* ============ 博客管理 ============ */

  /// GET /api/blog/admin/posts -> { list }
  static Future<List<dynamic>> blogPosts() => blogApiPosts();

  /// POST /api/blog/admin/posts
  static Future<Map<String, dynamic>> blogCreatePost(
    Map<String, dynamic> body,
  ) => blogApiCreatePost(body);

  /// PUT /api/blog/admin/posts/{id}
  static Future<Map<String, dynamic>> blogUpdatePost(
    int id,
    Map<String, dynamic> body,
  ) => blogApiUpdatePost(id, body);

  /// DELETE /api/blog/admin/posts/{id}
  static Future<void> blogDeletePost(int id) => blogApiDeletePost(id);

  /// GET /api/blog/admin/posts/{id}/preview-link -> { published, url }
  /// 已发布回公开地址；草稿附短时效预览令牌（url 为服务端返回的相对路径）。
  static Future<Map<String, dynamic>> blogPostPreviewLink(int id) =>
      blogApiPostPreviewLink(id);

  /// GET /api/blog/admin/collections -> { list }
  static Future<List<dynamic>> blogCollections() => blogApiCollections();

  /// POST /api/blog/admin/collections
  static Future<Map<String, dynamic>> blogCreateCollection(
    Map<String, dynamic> body,
  ) => blogApiCreateCollection(body);

  /// PUT /api/blog/admin/collections/{id}
  static Future<Map<String, dynamic>> blogUpdateCollection(
    int id,
    Map<String, dynamic> body,
  ) => blogApiUpdateCollection(id, body);

  /// DELETE /api/blog/admin/collections/{id}
  static Future<void> blogDeleteCollection(int id) =>
      blogApiDeleteCollection(id);

  /// POST /api/blog/admin/upload（multipart 字段名 image）-> { url }
  static Future<String> blogUploadImage(File file, String filename) =>
      blogApiUploadImage(file, filename);

  /* ============ 通知中心 ============ */

  /// GET /api/admin/notifications?limit=&before=&unread=1&level=&source=&type=
  /// → { items: [{id, ts, level, source, type, title, body, link, readAt}], unread, total }
  /// ts / readAt 为 epoch 秒；before 传列表最后一条的 id（按 id 倒序翻页）。
  /// type 为通知类别（服务端定义），与 unread / level / source 可叠加。
  static Future<Map<String, dynamic>> notifications({
    int limit = 50,
    int? before,
    bool unreadOnly = false,
    String? level,
    String? source,
    String? type,
  }) =>
      notificationsApiList(
          limit: limit, before: before, unreadOnly: unreadOnly,
          level: level, source: source, type: type);

  /// GET /api/admin/notifications/types
  /// → { types: [{ key, label, description, defaultLevel, sort, enabled, count, unread }] }
  ///
  /// 类别由服务端定义，客户端**不内置任何清单**；服务端新增类别无需发版。
  static Future<List<NotificationType>> notificationTypes() =>
      notificationsApiTypes();

  /// POST /api/admin/notifications/{id}/read -> { ok: true }
  static Future<void> notificationRead(int id) => notificationsApiRead(id);

  /// POST /api/admin/notifications/read-all -> { ok: true, count: N }
  static Future<int> notificationReadAll() => notificationsApiReadAll();

  /// DELETE /api/admin/notifications/{id} -> { ok: true }
  static Future<void> notificationDelete(int id) => notificationsApiDelete(id);

  /// POST /api/admin/notifications
  ///   { level, source, title, body?, link?, dedupKey? } -> 201 { id, ts }
  ///
  /// 调试页发测试通知用。为展示「最近一次调用的状态码与响应体」，这里不抛异常，
  /// 原样返回 [ApiCallResult]；401 仍触发全局登出（与其它请求一致）。
  static Future<ApiCallResult> createNotification(
    Map<String, dynamic> payload,
  ) => notificationsApiCreate(payload);

  /* ============ SSE 实时流 ============ */

  /// 建立 /api/admin/system/stream 长连接。服务端每 ~1s 推一条
  /// `event: snapshot / data: {system, services, history}`。
  /// 返回句柄，调用 cancel() 即断开（对齐 Web：Tab 激活才连、切走断开）。
  static SystemStreamHandle systemStream({
    required void Function(Map<String, dynamic> snapshot) onSnapshot,
    void Function(String? error)? onError,
    void Function()? onDone,
  }) =>
      systemApiStream(
          onSnapshot: onSnapshot, onError: onError, onDone: onDone);

  /* ============ 通用 ============ */

  static String _errorOfStatus(int code) {
    if (code == 401) {
      _notifyAuthRequired();
      return '未登录或登录已过期';
    }
    return 'SSE HTTP $code';
  }

  /// 解析单条 SSE 帧（event:/data: 行），非 snapshot 返回 null
  static Map<String, dynamic>? _parseSseFrame(String frame) {
    String? event;
    String? data;
    for (final line in frame.split('\n')) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data = line.substring(5).trim();
      }
    }
    if (event != 'snapshot' || data == null) return null;
    try {
      final decoded = jsonDecode(data);
      return (decoded is Map) ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// 解析数组响应（服务端直接返回 JSON 数组，如 system/history）
  static List<dynamic> _decodeList(http.Response res) {
    if (res.statusCode == 401) {
      throw ApiException('未登录或登录已过期', code: 401);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(_errorOf(res), code: res.statusCode);
    }
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  /// 解析「对象包裹的数组字段」或「裸数组」两种响应（分享列表双保险）
  static List<dynamic> _decodeListOr(http.Response res, String key) {
    if (res.statusCode == 401) {
      throw ApiException('未登录或登录已过期', code: 401);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(_errorOf(res), code: res.statusCode);
    }
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is List) return decoded;
      if (decoded is Map && decoded[key] is List) return decoded[key] as List;
    } catch (_) {}
    return const [];
  }

  /// 401 已由 [_authed] 处理（续期失败才走到这里）：这里只把 401 转成 ApiException，
  /// 不再重复触发全局登出。
  static Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode == 401) {
      throw ApiException('未登录或登录已过期', code: 401);
    }
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      data = (decoded is Map) ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      data = {};
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = (data['error'] as String?) ??
          (data['message'] as String?) ??
          'HTTP ${res.statusCode}';
      throw ApiException(
        message,
        code: res.statusCode,
        errorCode: data['code'] as String?,
        retryAfter: data['retryAfter'] is num
            ? (data['retryAfter'] as num).toInt()
            : null,
      );
    }
    return data;
  }

  static String _errorOf(http.Response res) {
    if (res.statusCode == 401) return '未登录或登录已过期';
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) {
        return (decoded['error'] as String?) ??
            (decoded['message'] as String?) ??
            'HTTP ${res.statusCode}';
      }
    } catch (_) {}
    return 'HTTP ${res.statusCode}';
  }
}
