import 'package:flutter_test/flutter_test.dart';

import 'package:home_admin/api.dart';
import 'package:home_admin/notification_store.dart';
import 'package:home_admin/notifications/notifications_controller.dart';

import 'notifications_test_support.dart';

void main() {
  setUp(() {
    NotificationStore.recentPushes.clear();
    NotificationStore.incoming.value = null;
  });

  group('详情页动作', () {
    test('markRead：成功后本地已读并同步未读', () async {
      final synced = <int>[];
      final api = FakeNotificationsApi();
      final c = notificationsController(api, synced: synced);
      addTearDown(c.dispose);
      c.applyIncoming(notificationItem(1));
      final ok = await c.markRead(c.feed.items.single);
      expect(ok, isTrue);
      expect(api.readIds, [1]);
      expect(c.feed.items.single.isUnread, isFalse);
      expect(c.feed.unread, 0);
      expect(synced.last, 0);
    });

    test('markRead：已读条目直接成功且不发请求', () async {
      final api = FakeNotificationsApi();
      final c = notificationsController(api);
      addTearDown(c.dispose);
      final ok = await c.markRead(notificationItem(1, readAt: 9));
      expect(ok, isTrue);
      expect(api.readIds, isEmpty);
    });

    test('markRead 失败：交给鉴权处理并返回 false', () async {
      var authCalls = 0;
      final api = FakeNotificationsApi()..readError = Exception('boom');
      final c = notificationsController(
        api,
        onAuthError: (e) async {
          authCalls += 1;
          return false;
        },
      );
      addTearDown(c.dispose);
      c.applyIncoming(notificationItem(1));
      final ok = await c.markRead(c.feed.items.single);
      expect(ok, isFalse);
      expect(authCalls, 1);
      expect(c.feed.items.single.isUnread, isTrue);
    });

    test('deleteFromDetail：成功后移除并同步未读', () async {
      final synced = <int>[];
      final api = FakeNotificationsApi();
      final c = notificationsController(api, synced: synced);
      addTearDown(c.dispose);
      c.applyIncoming(notificationItem(1));
      final ok = await c.deleteFromDetail(c.feed.items.single);
      expect(ok, isTrue);
      expect(api.deleteIds, [1]);
      expect(c.feed.items, isEmpty);
      expect(synced.last, 0);
    });

    test('deleteFromDetail 失败：返回 false', () async {
      final api = FakeNotificationsApi()..deleteError = Exception('boom');
      final c = notificationsController(api);
      addTearDown(c.dispose);
      c.applyIncoming(notificationItem(1));
      final ok = await c.deleteFromDetail(c.feed.items.single);
      expect(ok, isFalse);
    });
  });

  group('全部已读', () {
    test('成功：全部置读并同步 0', () async {
      final synced = <int>[];
      final api = FakeNotificationsApi();
      final c = notificationsController(api, synced: synced);
      addTearDown(c.dispose);
      c.applyIncoming(notificationItem(1));
      c.applyIncoming(notificationItem(2));
      await c.readAll();
      expect(api.readAllCount, 1);
      expect(c.feed.unread, 0);
      expect(c.feed.items.every((x) => !x.isUnread), isTrue);
      expect(synced.last, 0);
    });

    test('无未读或进行中：不发请求', () async {
      final api = FakeNotificationsApi();
      final c = notificationsController(api);
      addTearDown(c.dispose);
      await c.readAll();
      expect(api.readAllCount, 0);

      c.applyIncoming(notificationItem(1));
      c.markingAll = true;
      await c.readAll();
      expect(api.readAllCount, 0);
    });

    test('失败：提示操作失败', () async {
      final toasts = <String>[];
      final api = FakeNotificationsApi()..readAllError = Exception('boom');
      final c = notificationsController(
        api,
        onToast: (msg, {required ok}) => toasts.add('$msg|$ok'),
      );
      addTearDown(c.dispose);
      c.applyIncoming(notificationItem(1));
      await c.readAll();
      expect(toasts, ['操作失败|false']);
      expect(c.markingAll, isFalse);
    });
  });

  group('单条删除（二次确认）', () {
    test('取消确认：不发请求', () async {
      final api = FakeNotificationsApi();
      final c = notificationsController(api, confirm: (t, m) async => false);
      addTearDown(c.dispose);
      await c.delete(notificationItem(1));
      expect(api.deleteIds, isEmpty);
    });

    test('确认成功：删除并提示已删除', () async {
      final toasts = <String>[];
      final api = FakeNotificationsApi();
      final c = notificationsController(
        api,
        confirm: (t, m) async => true,
        onToast: (msg, {required ok}) => toasts.add('$msg|$ok'),
      );
      addTearDown(c.dispose);
      c.applyIncoming(notificationItem(1));
      await c.delete(c.feed.items.single);
      expect(api.deleteIds, [1]);
      expect(c.feed.items, isEmpty);
      expect(toasts, ['已删除|true']);
    });

    test('失败：提示删除失败', () async {
      final toasts = <String>[];
      final api = FakeNotificationsApi()..deleteError = Exception('boom');
      final c = notificationsController(
        api,
        confirm: (t, m) async => true,
        onToast: (msg, {required ok}) => toasts.add('$msg|$ok'),
      );
      addTearDown(c.dispose);
      await c.delete(notificationItem(1));
      expect(toasts, ['删除失败|false']);
    });
  });

  group('发通知', () {
    test('标题为空：报错且不发请求', () async {
      final api = FakeNotificationsApi();
      final c = notificationsController(api);
      addTearDown(c.dispose);
      final ok = await c.sendNotification(
        titleText: '   ',
        bodyText: '',
        linkText: '',
      );
      expect(ok, isFalse);
      expect(c.composeError, '标题不能为空');
      expect(api.createCalls, isEmpty);
    });

    test('成功：payload 取 admin 来源、标题 trim；进入等待推送', () async {
      final api = FakeNotificationsApi()
        ..createResult = const ApiCallResult(status: 201, body: '{"id":7}');
      final c = notificationsController(api);
      addTearDown(c.dispose);
      c.setLevel('urgent');
      final ok = await c.sendNotification(
        titleText: '  hi  ',
        bodyText: ' body ',
        linkText: '',
      );
      expect(ok, isTrue);
      expect(c.sending, isFalse);
      expect(c.composeError, isNull);
      expect(api.createCalls.single, {
        'level': 'urgent',
        'source': kNotificationsComposeSource,
        'title': 'hi',
        'body': 'body',
      });
      expect(c.pushWait.state?.isWaiting, isTrue);
      expect(c.repulled, isFalse);
    });

    test('HTTP 非 2xx：提示状态码并返回 false', () async {
      final api = FakeNotificationsApi()
        ..createResult = const ApiCallResult(status: 500, body: '');
      final c = notificationsController(api);
      addTearDown(c.dispose);
      final ok = await c.sendNotification(
        titleText: 'hi',
        bodyText: '',
        linkText: '',
      );
      expect(ok, isFalse);
      expect(c.composeError, '发送失败：HTTP 500');
      expect(c.sending, isFalse);
    });

    test('异常：记录错误并交给鉴权处理', () async {
      var authCalls = 0;
      final api = FakeNotificationsApi()..createError = Exception('boom');
      final c = notificationsController(
        api,
        onAuthError: (e) async {
          authCalls += 1;
          return false;
        },
      );
      addTearDown(c.dispose);
      final ok = await c.sendNotification(
        titleText: 'hi',
        bodyText: '',
        linkText: '',
      );
      expect(ok, isFalse);
      expect(c.composeError, 'Exception: boom');
      expect(authCalls, 1);
    });
  });

  group('组装与重拉', () {
    test('toggleCompose / setLevel 通知并改状态', () {
      final c = notificationsController(FakeNotificationsApi());
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);
      c.toggleCompose();
      expect(c.composeOpen, isTrue);
      c.setLevel('digest');
      expect(c.level, 'digest');
      expect(notifications, 2);
    });

    test('repull：置标记并静默拉取列表', () async {
      final api = FakeNotificationsApi()
        ..listResult = {
          'items': [
            {'id': 1, 'ts': 2, 'level': 'normal', 'source': 's', 'title': 'x'},
          ],
        };
      final c = notificationsController(api);
      addTearDown(c.dispose);
      await c.load();
      api.listCalls.clear();
      await c.repull();
      expect(c.repulled, isTrue);
      expect(api.listCalls.single['before'], isNull);
    });
  });
}
