import 'package:flutter_test/flutter_test.dart';

import 'package:home_admin/api.dart';
import 'package:home_admin/debug/debug_controller.dart';
import 'package:home_admin/debug_tools.dart';
import 'package:home_admin/notification_store.dart';

NotificationDebugController controller({
  Future<ApiCallResult> Function(Map<String, dynamic>)? create,
  Future<Map<String, dynamic>> Function({required int limit})? notifications,
  List<int>? synced,
  List<String>? toasts,
  void Function()? requestReload,
  Future<bool> Function(Object)? onAuthError,
  Future<void> Function(String)? copy,
}) {
  return NotificationDebugController(
    createNotification: create,
    notifications: notifications,
    setUnread: (v) async => synced?.add(v),
    requestReload: requestReload,
    onAuthError: onAuthError,
    copyToClipboard: copy,
    onToast: (msg, {required ok}) => toasts?.add('$msg|$ok'),
  );
}

void main() {
  setUp(() {
    NotificationStore.recentPushes.clear();
    NotificationStore.incoming.value = null;
  });

  group('发送测试通知', () {
    test('标题为空：本地校验失败，不发请求', () async {
      final calls = <Map<String, dynamic>>[];
      final c = controller(
        create: (p) async {
          calls.add(p);
          return const ApiCallResult(status: 201, body: '{"id":1}');
        },
      );
      addTearDown(c.dispose);

      final ok = await c.send(titleText: '   ', body: '正文');

      expect(ok, isFalse);
      expect(calls, isEmpty);
      expect(c.result?.status, 0);
      expect(c.result?.body, '标题不能为空');
      expect(c.sending, isFalse);
    });

    test('成功：下发构造后的请求体、记录结果并返回 true', () async {
      final calls = <Map<String, dynamic>>[];
      final c = controller(
        create: (p) async {
          calls.add(p);
          return const ApiCallResult(status: 201, body: '{"id":7}');
        },
      );
      addTearDown(c.dispose);

      final ok = await c.send(titleText: '  测试通知  ', body: '');

      expect(ok, isTrue);
      expect(calls.single, {
        'level': 'normal',
        'source': kDebugNotificationSource,
        'title': '测试通知',
      });
      expect(c.result?.status, 201);
      expect(c.result?.body, '{"id":7}');
      expect(c.sending, isFalse);
    });

    test('级别随 setLevel 生效', () async {
      final calls = <Map<String, dynamic>>[];
      final c = controller(
        create: (p) async {
          calls.add(p);
          return const ApiCallResult(status: 201, body: '{"id":1}');
        },
      );
      addTearDown(c.dispose);

      c.setLevel('urgent');
      expect(c.level, 'urgent');
      await c.send(titleText: 't', body: 'b');
      expect(calls.single['level'], 'urgent');
    });

    test('HTTP 失败：记录结果并提示状态码', () async {
      final toasts = <String>[];
      final c = controller(
        create: (p) async => const ApiCallResult(status: 500, body: 'oops'),
        toasts: toasts,
      );
      addTearDown(c.dispose);

      final ok = await c.send(titleText: 't', body: '');

      expect(ok, isFalse);
      expect(c.result?.status, 500);
      expect(c.result?.body, 'oops');
      expect(toasts, ['发送失败：HTTP 500|false']);
    });

    test('异常：记录异常文本并提示发送失败', () async {
      final toasts = <String>[];
      final c = controller(
        create: (p) async => throw Exception('boom'),
        toasts: toasts,
      );
      addTearDown(c.dispose);

      final ok = await c.send(titleText: 't', body: '');

      expect(ok, isFalse);
      expect(c.result?.status, 0);
      expect(c.result?.body, 'Exception: boom');
      expect(toasts, ['发送失败|false']);
    });
  });

  group('未读校正', () {
    test('成功：按服务端未读调用 setUnread', () async {
      final synced = <int>[];
      final c = controller(
        notifications: ({required limit}) async => {'unread': 5},
        synced: synced,
      );
      addTearDown(c.dispose);

      await c.refreshUnread();

      expect(synced, [5]);
    });

    test('非数值未读：不下发', () async {
      final synced = <int>[];
      final c = controller(
        notifications: ({required limit}) async => {'unread': 'x'},
        synced: synced,
      );
      addTearDown(c.dispose);

      await c.refreshUnread();

      expect(synced, isEmpty);
    });

    test('失败：交给鉴权处理，不抛出', () async {
      var authCalls = 0;
      final c = controller(
        notifications: ({required limit}) async => throw Exception('401'),
        onAuthError: (e) async {
          authCalls++;
          return true;
        },
      );
      addTearDown(c.dispose);

      await c.refreshUnread();

      expect(authCalls, 1);
    });
  });

  group('超时重拉', () {
    test('置 repulled、请求重拉并刷新未读', () async {
      var reloads = 0;
      final synced = <int>[];
      final c = controller(
        requestReload: () => reloads++,
        notifications: ({required limit}) async => {'unread': 2},
        synced: synced,
      );
      addTearDown(c.dispose);

      await c.repull();

      expect(c.repulled, isTrue);
      expect(reloads, 1);
      expect(synced, [2]);
    });
  });

  group('复制示例', () {
    test('复制成功后在 1.5s 内标记已复制并自动复位', () async {
      String? written;
      final c = controller(
        copy: (t) async => written = t,
      );
      addTearDown(c.dispose);

      await c.copyExample();

      expect(written, notificationExampleJson());
      expect(c.copied, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(c.copied, isFalse);
    });
  });
}
