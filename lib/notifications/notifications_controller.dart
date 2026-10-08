import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api.dart';
import '../debug_tools.dart' show buildNotificationPayload;
import '../notification_feed.dart';
import '../notification_model.dart';
import '../notification_push.dart';
import '../notification_store.dart';
import '../push_wait_result.dart';

/// 通知列表分页大小（列表请求 limit）。
const int kNotificationsPageSize = 50;

/// 发通知固定来源：后端 source 必填且不能为空，界面上不露出（先例与 Web 一致取 admin）。
const String kNotificationsComposeSource = 'admin';

/// 鉴权失败处理：返回是否已处理（已触发登出）。需要 UI 上下文，由页面注入。
typedef AuthErrorHandler = Future<bool> Function(Object e);

/// 失败提示（SnackBar）。由页面注入。
typedef ToastFn = void Function(String msg, {required bool ok});

/// 确认弹窗：返回用户是否点确认。由页面注入。
typedef ConfirmAction = Future<bool> Function(String title, String message);

/// 通知页所需的后端操作；生产用 [HttpNotificationsApi]，测试注入假实现。
abstract class NotificationsApi {
  Future<List<NotificationType>> types();

  Future<Map<String, dynamic>> list({
    required int limit,
    int? before,
    required bool unreadOnly,
    required String level,
    required String source,
    required String type,
  });

  Future<void> markRead(int id);

  Future<void> markAllRead();

  Future<void> delete(int id);

  Future<ApiCallResult> create(Map<String, dynamic> payload);
}

/// [NotificationsApi] 的生产实现：原样转发到 [Api]。
class HttpNotificationsApi implements NotificationsApi {
  const HttpNotificationsApi();

  @override
  Future<List<NotificationType>> types() => Api.notificationTypes();

  @override
  Future<Map<String, dynamic>> list({
    required int limit,
    int? before,
    required bool unreadOnly,
    required String level,
    required String source,
    required String type,
  }) =>
      Api.notifications(
        limit: limit,
        before: before,
        unreadOnly: unreadOnly,
        level: level,
        source: source,
        type: type,
      );

  @override
  Future<void> markRead(int id) => Api.notificationRead(id);

  @override
  Future<void> markAllRead() async {
    await Api.notificationReadAll();
  }

  @override
  Future<void> delete(int id) => Api.notificationDelete(id);

  @override
  Future<ApiCallResult> create(Map<String, dynamic> payload) =>
      Api.createNotification(payload);
}

Future<bool> _defaultAuthError(Object e) async => false;

void _defaultToast(String msg, {required bool ok}) {}

Future<bool> _defaultConfirm(String title, String message) async => false;

Future<void> _defaultSyncUnread(int value) => NotificationStore.setUnread(value);

int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

/// 从列表响应取通知条目。
List<NotificationItem> notificationsItemsOf(Map<String, dynamic> data) {
  final raw = data['items'];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((m) => NotificationItem.fromJson(Map<String, dynamic>.from(m)))
      .toList();
}

/// 通知页状态与业务逻辑（原 `_NotificationsPageState` 的字段与方法）。
///
/// 只依赖可注入的后端操作与回调，不碰 UI；页面用 `ListenableBuilder` 监听重建。
class NotificationsController extends ChangeNotifier {
  NotificationsController({
    NotificationsApi? api,
    AuthErrorHandler? onAuthError,
    ToastFn? onToast,
    ConfirmAction? confirm,
    Future<void> Function(int value)? syncUnread,
    int Function()? nowMs,
    PushWaitController? pushWait,
  })  : _api = api ?? const HttpNotificationsApi(),
        _onAuthError = onAuthError ?? _defaultAuthError,
        _onToast = onToast ?? _defaultToast,
        _confirm = confirm ?? _defaultConfirm,
        _syncUnread = syncUnread ?? _defaultSyncUnread,
        _nowMs = nowMs ?? _defaultNowMs,
        pushWait = pushWait ?? PushWaitController();

  final NotificationsApi _api;
  final AuthErrorHandler _onAuthError;
  final ToastFn _onToast;
  final ConfirmAction _confirm;
  final Future<void> Function(int value) _syncUnread;
  final int Function() _nowMs;

  /// 发通知后的推送等待控制器（页面用 [PushWaitResult] 呈现）。
  final PushWaitController pushWait;

  /// 列表内存状态；唯一新增入口是服务器推送与主动拉取。
  final NotificationFeed feed = NotificationFeed(pageSize: kNotificationsPageSize);

  bool _disposed = false;

  bool loading = true;
  bool loadingMore = false;
  bool markingAll = false;
  String? error;

  /* ===== 筛选 ===== */
  bool unreadOnly = false;
  String levelFilter = '';
  String sourceFilter = '';

  /// 通知类别键（服务端定义），空串为「全部」；列表请求带 `type=<key>`。
  String typeFilter = '';

  /// 服务端返回的类别（含停用，用于显示历史通知类别名）；接口失败时为空。
  List<NotificationType> types = const [];
  final Set<String> sources = {};

  /* ===== 发通知（页头内联表单） ===== */
  String level = 'normal';
  bool composeOpen = false;
  bool sending = false;
  bool repulled = false;
  String? composeError;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 拉取服务端定义的类别清单（进通知页 / 切回本页时）。
  ///
  /// 接口失败 → 类别置空、筛选回落「全部」，**不阻塞通知列表**（列表仍照常加载）。
  Future<void> loadTypes() async {
    try {
      final list = await _api.types();
      if (_disposed) return;
      types = list;
      // 选中的类别在新清单里不存在 / 已停用 → 回落「全部」
      final stillValid = list.any((t) => t.key == typeFilter && t.enabled);
      if (!stillValid) typeFilter = '';
      _notify();
    } catch (e) {
      if (_disposed) return;
      types = const [];
      typeFilter = '';
      _notify();
      await _onAuthError(e);
    }
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      loading = true;
      error = null;
      _notify();
    }
    try {
      final data = await _api.list(
        limit: kNotificationsPageSize,
        unreadOnly: unreadOnly,
        level: levelFilter,
        source: sourceFilter,
        type: typeFilter,
      );
      final list = notificationsItemsOf(data);
      final unread = data['unread'];
      if (_disposed) return;
      _addSources(list);
      feed.replaceAll(list, unread is num ? unread.toInt() : null);
      loading = false;
      error = null;
      _notify();
      await _syncUnread(feed.unread);
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        error = e.toString();
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (loadingMore || loading || !feed.hasMore || feed.items.isEmpty) {
      return;
    }
    loadingMore = true;
    _notify();
    try {
      final data = await _api.list(
        limit: kNotificationsPageSize,
        before: feed.items.last.id,
        unreadOnly: unreadOnly,
        level: levelFilter,
        source: sourceFilter,
        type: typeFilter,
      );
      final list = notificationsItemsOf(data);
      if (_disposed) return;
      feed.appendOlder(list);
      loadingMore = false;
      _notify();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        loadingMore = false;
        _notify();
        _onToast('加载更多失败', ok: false);
      }
    }
  }

  void _addSources(Iterable<NotificationItem> items) {
    for (final item in items) {
      if (item.source.isNotEmpty) sources.add(item.source);
    }
  }

  bool matchesFilter(NotificationItem item) {
    if (unreadOnly && !item.isUnread) return false;
    if (levelFilter.isNotEmpty && item.level != levelFilter) return false;
    if (sourceFilter.isNotEmpty && item.source != sourceFilter) return false;
    if (typeFilter.isNotEmpty && item.category != typeFilter) return false;
    return true;
  }

  /// 服务器推送：唯一的新增入口（发送方不做本地插入）。
  void applyIncoming(NotificationItem item) {
    _addSources([item]);
    // 对齐 Web：不匹配当前筛选的推送不插入列表（未读徽标仍由服务状态更新）。
    if (!matchesFilter(item)) return;
    feed.applyPush(item);
    _notify();
  }

  /* ============ 筛选切换 ============ */

  void setUnreadOnly(bool value) {
    if (unreadOnly == value) return;
    unreadOnly = value;
    _notify();
    unawaited(load());
  }

  void setLevelFilter(String value) {
    if (levelFilter == value) return;
    levelFilter = value;
    _notify();
    unawaited(load());
  }

  void setSourceFilter(String value) {
    if (sourceFilter == value) return;
    sourceFilter = value;
    _notify();
    unawaited(load());
  }

  void setTypeFilter(String value) {
    if (typeFilter == value) return;
    typeFilter = value;
    _notify();
    unawaited(load());
  }

  /* ============ 点条目进详情页的回调 ============ */

  /// 详情页「标记已读」：服务端成功后就地更新列表并同步未读；返回是否成功。
  Future<bool> markRead(NotificationItem item) async {
    if (!item.isUnread) return true;
    try {
      await _api.markRead(item.id);
      if (_disposed) return true;
      feed.markRead(item.id, _nowMs() ~/ 1000);
      _notify();
      await _syncUnread(feed.unread);
      return true;
    } catch (e) {
      if (!_disposed) await _onAuthError(e);
      return false;
    }
  }

  /// 详情页「删除」：服务端成功后从列表移除并同步未读；返回是否成功。
  Future<bool> deleteFromDetail(NotificationItem item) async {
    try {
      await _api.delete(item.id);
      if (_disposed) return true;
      final removed = feed.remove(item.id);
      if (removed != null) _notify();
      await _syncUnread(feed.unread);
      return true;
    } catch (e) {
      if (!_disposed) await _onAuthError(e);
      return false;
    }
  }

  Future<void> readAll() async {
    if (feed.unread == 0 || markingAll) return;
    markingAll = true;
    _notify();
    try {
      await _api.markAllRead();
      if (_disposed) return;
      feed.markAllRead(_nowMs() ~/ 1000);
      markingAll = false;
      _notify();
      await _syncUnread(0);
    } catch (e) {
      if (_disposed) return;
      markingAll = false;
      _notify();
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) _onToast('操作失败', ok: false);
    }
  }

  /* ============ 单条删除（二次确认） ============ */

  Future<void> delete(NotificationItem item) async {
    final confirmed = await _confirm('删除通知', '删除这条通知？删除后不可恢复。');
    if (!confirmed || _disposed) return;
    try {
      await _api.delete(item.id);
      if (_disposed) return;
      final removed = feed.remove(item.id);
      if (removed != null) _notify();
      await _syncUnread(feed.unread);
      if (!_disposed) _onToast('已删除', ok: true);
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) _onToast('删除失败', ok: false);
    }
  }

  /* ============ 发通知 ============ */

  void toggleCompose() {
    composeOpen = !composeOpen;
    _notify();
  }

  void setLevel(String value) {
    level = value;
    _notify();
  }

  /// 发送通知；返回 POST 是否成功（成功由页面负责清空输入框）。
  ///
  /// 铁律：禁止乐观更新。不插入列表、不刷未读，只等服务器 SSE 推送。
  Future<bool> sendNotification({
    required String titleText,
    required String bodyText,
    required String linkText,
  }) async {
    final title = titleText.trim();
    if (title.isEmpty) {
      composeError = '标题不能为空';
      _notify();
      return false;
    }
    final payload = buildNotificationPayload(
      level: level,
      title: title,
      source: kNotificationsComposeSource,
      body: bodyText,
      link: linkText,
    );
    final startedAt = _nowMs();
    sending = true;
    composeError = null;
    repulled = false;
    _notify();
    try {
      final r = await _api.create(payload);
      if (_disposed) return false;
      sending = false;
      _notify();
      if (!r.ok) {
        composeError = '发送失败：HTTP ${r.status}';
        _notify();
        return false;
      }
      pushWait.begin(
        PushTarget(id: r.id, title: title, source: kNotificationsComposeSource),
        startedAtMillis: startedAt,
      );
      return true;
    } catch (e) {
      if (_disposed) return false;
      sending = false;
      composeError = e.toString();
      _notify();
      await _onAuthError(e);
      return false;
    }
  }

  /// 等待超时后的显式动作：重新拉取列表（用户主动触发，允许更新未读）。
  Future<void> repull() async {
    repulled = true;
    _notify();
    await load(silent: feed.items.isNotEmpty);
  }

  @override
  void dispose() {
    _disposed = true;
    pushWait.dispose();
    super.dispose();
  }
}
