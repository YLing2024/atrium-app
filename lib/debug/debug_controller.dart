import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../debug_tools.dart';
import '../notification_push.dart';
import '../notification_store.dart';
import '../push_wait_result.dart';

/// 鉴权失败处理：返回是否已处理（已触发登出）。需要 UI 上下文，由页面注入。
typedef DebugAuthErrorHandler = Future<bool> Function(Object e);

/// 失败提示（SnackBar）。由页面注入。
typedef DebugToastFn = void Function(String msg, {required bool ok});

/// 发测试通知的可注入入口；生产原样转发到 [Api]。
typedef DebugCreateNotification =
    Future<ApiCallResult> Function(Map<String, dynamic> payload);

/// 拉取列表的可注入入口（仅用于校正未读数）。
typedef DebugNotificationsFetch =
    Future<Map<String, dynamic>> Function({required int limit});

/// 复制文本的可注入入口（默认写系统剪贴板）。
typedef DebugClipboardWriter = Future<void> Function(String text);

Future<bool> _defaultAuthError(Object e) async => false;

void _defaultToast(String msg, {required bool ok}) {}

Future<ApiCallResult> _defaultCreate(Map<String, dynamic> payload) =>
    Api.createNotification(payload);

Future<Map<String, dynamic>> _defaultNotifications({required int limit}) =>
    Api.notifications(limit: limit);

Future<void> _defaultClipboardWrite(String text) =>
    Clipboard.setData(ClipboardData(text: text));

int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

/// 最近一次调用的结果（本页发出的测试通知）。
class DebugCallResult {
  const DebugCallResult({
    required this.status,
    required this.body,
    required this.at,
  });

  /// HTTP 状态码；0 表示未发出请求（如本地校验失败）
  final int status;
  final String body;

  /// 发生时间（epoch 秒）
  final int at;
}

/// 「通知调试」面板状态与业务逻辑（原 `_NotificationDebugPanelState` 的字段与方法）。
///
/// 只依赖可注入的后端操作与回调，不碰 UI；页面用 `ListenableBuilder` 监听重建。
class NotificationDebugController extends ChangeNotifier {
  NotificationDebugController({
    DebugCreateNotification? createNotification,
    DebugNotificationsFetch? notifications,
    Future<void> Function()? syncFromService,
    Future<void> Function(int value)? setUnread,
    void Function()? requestReload,
    DebugClipboardWriter? copyToClipboard,
    DebugAuthErrorHandler? onAuthError,
    DebugToastFn? onToast,
    int Function()? nowMs,
    PushWaitController? pushWait,
  })  : _createNotification = createNotification ?? _defaultCreate,
        _notifications = notifications ?? _defaultNotifications,
        _syncFromService = syncFromService ?? NotificationStore.syncFromService,
        _setUnread = setUnread ?? NotificationStore.setUnread,
        _requestReload = requestReload ?? NotificationStore.requestReload,
        _copyToClipboard = copyToClipboard ?? _defaultClipboardWrite,
        _onAuthError = onAuthError ?? _defaultAuthError,
        _onToast = onToast ?? _defaultToast,
        _nowMs = nowMs ?? _defaultNowMs,
        pushWait = pushWait ?? PushWaitController();

  final DebugCreateNotification _createNotification;
  final DebugNotificationsFetch _notifications;
  final Future<void> Function() _syncFromService;
  final Future<void> Function(int value) _setUnread;
  final void Function() _requestReload;
  final DebugClipboardWriter _copyToClipboard;
  final DebugAuthErrorHandler _onAuthError;
  final DebugToastFn _onToast;
  final int Function() _nowMs;

  /// 发通知后的推送等待控制器（页面用 [PushWaitResult] 呈现）。
  final PushWaitController pushWait;

  bool _disposed = false;

  String level = 'normal';
  bool sending = false;
  bool copied = false;
  bool repulled = false;
  DebugCallResult? result;

  int _nowSeconds() => _nowMs() ~/ 1000;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 恢复服务状态 + 向服务端校正未读数（下拉刷新 / Tab 切入）。
  Future<void> sync() async {
    await _syncFromService();
    await refreshUnread();
  }

  Future<void> refreshUnread() async {
    try {
      final data = await _notifications(limit: 1);
      final unread = data['unread'];
      if (unread is num) await _setUnread(unread.toInt());
    } catch (e) {
      // 实时状态以服务推送为准，校正失败不打断页面；401 仍走全局登出
      if (_disposed) return;
      await _onAuthError(e);
    }
  }

  /// 发送测试通知；返回是否发送成功（成功由页面负责清空表单）。
  ///
  /// 铁律：禁止乐观更新。只清空表单并等待服务器 SSE 推送，
  /// 列表与未读徽标都不在此处本地 +1（那是连通性检测的对象）。
  Future<bool> send({required String titleText, required String body}) async {
    final title = titleText.trim();
    if (title.isEmpty) {
      result = DebugCallResult(status: 0, body: '标题不能为空', at: _nowSeconds());
      _notify();
      return false;
    }
    final startedAt = _nowMs();
    sending = true;
    repulled = false;
    _notify();
    final payload = buildNotificationPayload(
      level: level,
      title: title,
      body: body,
    );
    try {
      final r = await _createNotification(payload);
      if (_disposed) return false;
      sending = false;
      result = DebugCallResult(status: r.status, body: r.body, at: _nowSeconds());
      _notify();
      if (r.ok) {
        pushWait.begin(
          PushTarget(id: r.id, title: title, source: kDebugNotificationSource),
          startedAtMillis: startedAt,
        );
        return true;
      }
      _onToast('发送失败：HTTP ${r.status}', ok: false);
      return false;
    } catch (e) {
      if (_disposed) return false;
      sending = false;
      result = DebugCallResult(status: 0, body: e.toString(), at: _nowSeconds());
      _notify();
      _onToast('发送失败', ok: false);
      return false;
    }
  }

  /// 等待超时后的显式动作：重新拉取列表（用户主动触发，允许更新徽标）。
  Future<void> repull() async {
    repulled = true;
    _notify();
    _requestReload();
    await refreshUnread();
  }

  Future<void> copyExample() async {
    try {
      await _copyToClipboard(notificationExampleJson());
      if (_disposed) return;
      copied = true;
      _notify();
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (_disposed) return;
        copied = false;
        _notify();
      });
    } catch (_) {
      // 复制失败静默降级：示例为可选中文本，可长按手动复制
    }
  }

  void setLevel(String value) {
    level = value;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    pushWait.dispose();
    super.dispose();
  }
}
