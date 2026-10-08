import 'package:home_admin/api.dart';
import 'package:home_admin/notification_model.dart';
import 'package:home_admin/notifications/notifications_controller.dart';

/// 无网络、无设备的假后端：记录调用并可控地完成 / 失败。
class FakeNotificationsApi implements NotificationsApi {
  List<NotificationType> typesResult = const [];
  Object? typesError;

  Map<String, dynamic> listResult = const {};
  Object? listError;
  final List<Map<String, dynamic>> listCalls = [];

  final List<int> readIds = [];
  Object? readError;

  int readAllCount = 0;
  Object? readAllError;

  final List<int> deleteIds = [];
  Object? deleteError;

  ApiCallResult createResult = const ApiCallResult(status: 201, body: '{}');
  Object? createError;
  final List<Map<String, dynamic>> createCalls = [];

  @override
  Future<List<NotificationType>> types() async {
    if (typesError != null) throw typesError!;
    return typesResult;
  }

  @override
  Future<Map<String, dynamic>> list({
    required int limit,
    int? before,
    required bool unreadOnly,
    required String level,
    required String source,
    required String type,
  }) async {
    listCalls.add({
      'limit': limit,
      'before': before,
      'unreadOnly': unreadOnly,
      'level': level,
      'source': source,
      'type': type,
    });
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<void> markRead(int id) async {
    readIds.add(id);
    if (readError != null) throw readError!;
  }

  @override
  Future<void> markAllRead() async {
    readAllCount += 1;
    if (readAllError != null) throw readAllError!;
  }

  @override
  Future<void> delete(int id) async {
    deleteIds.add(id);
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<ApiCallResult> create(Map<String, dynamic> payload) async {
    createCalls.add(payload);
    if (createError != null) throw createError!;
    return createResult;
  }
}

NotificationItem notificationItem(
  int id, {
  String level = 'normal',
  String source = 'admin',
  String title = 't',
  String type = '',
  int? readAt,
  String? body,
}) =>
    NotificationItem(
      id: id,
      ts: 1000,
      level: level,
      source: source,
      title: title,
      type: type,
      body: body,
      readAt: readAt,
    );

NotificationType notificationType(
  String key, {
  String label = 'L',
  bool enabled = true,
}) =>
    NotificationType(key: key, label: label, enabled: enabled);

NotificationsController notificationsController(
  FakeNotificationsApi api, {
  Future<bool> Function(Object e)? onAuthError,
  void Function(String msg, {required bool ok})? onToast,
  Future<bool> Function(String title, String message)? confirm,
  List<int>? synced,
  int Function()? nowMs,
}) =>
    NotificationsController(
      api: api,
      onAuthError: onAuthError,
      onToast: onToast,
      confirm: confirm,
      syncUnread: (v) async => synced?.add(v),
      nowMs: nowMs ?? () => 1000 * 1000,
    );
