import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api.dart';
import '../notification_service.dart';
import '../notification_store.dart';

/// 管理页所需的后端操作；生产用 [HttpManageApi]，测试注入假实现。
abstract class ManageApi {
  Future<List<Map<String, dynamic>>> sessions();

  Future<void> sessionRename(String id, String deviceName);

  Future<void> sessionDelete(String id);

  Future<List<Map<String, dynamic>>> apiTokens();

  Future<Map<String, dynamic>> apiTokenCreate({
    required String name,
    required String note,
    required int expiresInDays,
  });

  Future<void> apiTokenUpdate(String id, Map<String, dynamic> patch);

  Future<void> apiTokenDelete(String id);
}

/// [ManageApi] 的生产实现：原样转发到 [Api]。
class HttpManageApi implements ManageApi {
  const HttpManageApi();

  @override
  Future<List<Map<String, dynamic>>> sessions() => Api.sessions();

  @override
  Future<void> sessionRename(String id, String deviceName) =>
      Api.sessionRename(id, deviceName);

  @override
  Future<void> sessionDelete(String id) => Api.sessionDelete(id);

  @override
  Future<List<Map<String, dynamic>>> apiTokens() => Api.apiTokens();

  @override
  Future<Map<String, dynamic>> apiTokenCreate({
    required String name,
    required String note,
    required int expiresInDays,
  }) =>
      Api.apiTokenCreate(
        name: name,
        note: note,
        expiresInDays: expiresInDays,
      );

  @override
  Future<void> apiTokenUpdate(String id, Map<String, dynamic> patch) =>
      Api.apiTokenUpdate(id, patch);

  @override
  Future<void> apiTokenDelete(String id) => Api.apiTokenDelete(id);
}

/// 电池优化状态读取（可注入，测试不触设备）。
typedef BatteryStatusReader = Future<bool> Function();

/// 重启通知服务（可注入）。
typedef ServiceRestarter = Future<bool> Function();

/// 无返回值的前台服务动作（申请忽略电池优化）。
typedef ServiceAction = Future<void> Function();

/// 从服务侧同步通知状态（可注入）。
typedef StoreSyncer = Future<void> Function();

/// 鉴权失败处理：返回是否已处理（已触发登出）。需要 UI 上下文，由页面注入。
typedef AuthErrorHandler = Future<bool> Function(Object e);

/// 强制登出回调：删除当前设备时触发。由页面注入。
typedef ForceLogout = Future<void> Function();

Future<bool> _defaultIsIgnoringBattery() =>
    NotificationService.isIgnoringBatteryOptimizations();

Future<bool> _defaultRestartService() => NotificationService.restart();

Future<void> _defaultRequestBattery() =>
    NotificationService.requestIgnoreBatteryOptimization();

Future<bool> _defaultAuthError(Object e) async => false;

Future<void> _defaultForceLogout() async {}

/// 管理 Tab 状态与业务逻辑：设备会话 + 接口令牌 + 通知保活。
///
/// 只依赖可注入的后端操作与回调，不碰 UI；页面用 `ListenableBuilder` 监听重建。
class ManageController extends ChangeNotifier {
  ManageController({
    ManageApi? api,
    BatteryStatusReader? isIgnoringBattery,
    ServiceRestarter? restartService,
    ServiceAction? requestBatteryOptimization,
    StoreSyncer? syncStore,
    AuthErrorHandler? onAuthError,
    ForceLogout? forceLogout,
  })  : _api = api ?? const HttpManageApi(),
        _isIgnoringBattery = isIgnoringBattery ?? _defaultIsIgnoringBattery,
        _restartService = restartService ?? _defaultRestartService,
        _requestBattery = requestBatteryOptimization ?? _defaultRequestBattery,
        _syncStore = syncStore ?? NotificationStore.syncFromService,
        _onAuthError = onAuthError ?? _defaultAuthError,
        _forceLogout = forceLogout ?? _defaultForceLogout;

  final ManageApi _api;
  final BatteryStatusReader _isIgnoringBattery;
  final ServiceRestarter _restartService;
  final ServiceAction _requestBattery;
  final StoreSyncer _syncStore;
  final AuthErrorHandler _onAuthError;
  final ForceLogout _forceLogout;

  bool _disposed = false;

  /* ===== 设备会话 ===== */
  List<Map<String, dynamic>> sessions = [];
  bool loadingSessions = true;
  String? sessionsError;
  String? editingId; // 正在重命名的会话 id
  String? editError;
  bool editSaving = false;
  bool renameInFlight = false;

  /* ===== 接口令牌 ===== */
  List<Map<String, dynamic>> tokens = [];
  bool loadingTokens = true;
  String? tokensError;

  /* ===== 通知保活 ===== */
  bool ignoringBattery = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 首次进入：并行加载会话 / 令牌、同步通知状态、读电池优化状态。
  void init() {
    unawaited(loadSessions());
    unawaited(loadTokens());
    unawaited(_syncStore());
    unawaited(loadBatteryStatus());
  }

  /// 下拉刷新：重新加载会话与令牌，并同步通知状态。
  Future<void> refresh() async {
    await Future.wait([loadSessions(), loadTokens(), _syncStore()]);
  }

  /* ============ 设备会话 ============ */

  Future<void> loadSessions() async {
    loadingSessions = true;
    sessionsError = null;
    _notify();
    try {
      final list = await _api.sessions();
      if (_disposed) return;
      sessions = list;
      loadingSessions = false;
      _notify();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        sessionsError = e.toString();
        loadingSessions = false;
        _notify();
      }
    }
  }

  void startRename(String id) {
    editingId = id;
    editError = null;
    _notify();
  }

  void cancelRename() {
    editingId = null;
    editError = null;
    _notify();
  }

  /// 保存设备重命名：[rawName] 为输入框原文。
  Future<void> saveRename(Map<String, dynamic> s, String rawName) async {
    final id = s['id'].toString();
    final name = rawName.trim();
    if (name.isEmpty) {
      editError = '设备名称不能为空';
      _notify();
      return;
    }
    if (name == (s['deviceName'] ?? '').toString()) {
      cancelRename(); // 未改动：直接退出编辑态，不发请求
      return;
    }
    if (renameInFlight) return; // 失焦与保存同帧触发时去重
    renameInFlight = true;
    editSaving = true;
    editError = null;
    _notify();
    try {
      await _api.sessionRename(id, name);
      if (_disposed) return;
      sessions = [
        for (final x in sessions)
          if (x['id'].toString() == id) {...x, 'deviceName': name} else x,
      ];
      editingId = null;
      editError = null;
      _notify();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        editError = e.toString();
        _notify();
      }
    } finally {
      renameInFlight = false;
      if (!_disposed) {
        editSaving = false;
        _notify();
      }
    }
  }

  /// 确认删除设备；删除当前设备时撤销自身凭证并登出。
  Future<void> confirmDeleteSession(Map<String, dynamic> s) async {
    final id = s['id'].toString();
    try {
      await _api.sessionDelete(id);
      if (_disposed) return;
      if (s['isCurrent'] == true) {
        // 删除当前设备：撤销自身凭证 → 立即退出登录
        await _forceLogout();
        return;
      }
      sessions = sessions.where((x) => x['id'].toString() != id).toList();
      _notify();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        sessionsError = e.toString();
        _notify();
      }
    }
  }

  /* ============ 接口令牌 ============ */

  Future<void> loadTokens() async {
    loadingTokens = true;
    tokensError = null;
    _notify();
    try {
      final list = await _api.apiTokens();
      if (_disposed) return;
      tokens = list;
      loadingTokens = false;
      _notify();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        tokensError = e.toString();
        loadingTokens = false;
        _notify();
      }
    }
  }

  /// 生成令牌；返回后端响应的原始数据（含一次性明文 `token`）。
  Future<Map<String, dynamic>> createToken({
    required String name,
    required String note,
    required int expiresInDays,
  }) =>
      _api.apiTokenCreate(
        name: name,
        note: note,
        expiresInDays: expiresInDays,
      );

  Future<void> updateToken(String id, Map<String, dynamic> patch) =>
      _api.apiTokenUpdate(id, patch);

  /// 吊销令牌并从列表移除。
  Future<void> deleteToken(Map<String, dynamic> t) async {
    final id = t['id'].toString();
    try {
      await _api.apiTokenDelete(id);
      if (_disposed) return;
      tokens = tokens.where((x) => x['id'].toString() != id).toList();
      _notify();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        tokensError = e.toString();
        _notify();
      }
    }
  }

  /* ============ 通知保活 ============ */

  Future<void> loadBatteryStatus() async {
    final ignoring = await _isIgnoringBattery();
    if (_disposed) return;
    ignoringBattery = ignoring;
    _notify();
  }

  Future<bool> restartNotificationService() => _restartService();

  Future<void> requestBatteryOptimization() async {
    await _requestBattery();
    await loadBatteryStatus();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
