import 'package:flutter_test/flutter_test.dart';

import 'package:home_admin/notification_store.dart';
import 'package:home_admin/notifications/notifications_controller.dart';

import 'notifications_test_support.dart';

void main() {
  setUp(() {
    NotificationStore.recentPushes.clear();
    NotificationStore.incoming.value = null;
  });

  group('notificationsItemsOf', () {
    test('非 List / 坏项容错，正常项解析', () {
      expect(notificationsItemsOf(const {'items': 3}), isEmpty);
      final list = notificationsItemsOf({
        'items': [
          {'id': 1, 'ts': 2, 'level': 'urgent', 'source': 's', 'title': 'a'},
          'bad',
        ],
      });
      expect(list, hasLength(1));
      expect(list.single.id, 1);
      expect(list.single.level, 'urgent');
    });
  });

  group('加载', () {
    test('初始状态：加载中、无错误、空列表', () {
      final c = notificationsController(FakeNotificationsApi());
      addTearDown(c.dispose);
      expect(c.loading, isTrue);
      expect(c.error, isNull);
      expect(c.feed.items, isEmpty);
      expect(c.types, isEmpty);
    });

    test('加载成功：写入列表、按服务端未读校正并同步未读', () async {
      final synced = <int>[];
      final api = FakeNotificationsApi()
        ..listResult = {
          'items': [
            {'id': 1, 'ts': 2, 'level': 'normal', 'source': 'a', 'title': 'x'},
            {
              'id': 2,
              'ts': 3,
              'level': 'normal',
              'source': 'b',
              'title': 'y',
              'readAt': 9,
            },
          ],
          'unread': 1,
        };
      final c = notificationsController(api, synced: synced);
      addTearDown(c.dispose);
      await c.load();
      expect(c.feed.items, hasLength(2));
      expect(c.feed.unread, 1);
      expect(c.loading, isFalse);
      expect(c.error, isNull);
      expect(c.sources, {'a', 'b'});
      expect(synced, [1]);
      expect(api.listCalls.single, {
        'limit': kNotificationsPageSize,
        'before': null,
        'unreadOnly': false,
        'level': '',
        'source': '',
        'type': '',
      });
    });

    test('加载失败：记录错误并结束加载', () async {
      final api = FakeNotificationsApi()..listError = Exception('读取失败');
      final c = notificationsController(api);
      addTearDown(c.dispose);
      await c.load();
      expect(c.error, 'Exception: 读取失败');
      expect(c.loading, isFalse);
    });

    test('鉴权失败且已处理：不记录错误、保持加载态', () async {
      final api = FakeNotificationsApi()..listError = Exception('401');
      final c = notificationsController(api, onAuthError: (e) async => true);
      addTearDown(c.dispose);
      await c.load();
      expect(c.error, isNull);
      expect(c.loading, isTrue);
    });

    test('静默加载不进入 loading 态', () async {
      final api = FakeNotificationsApi()..listResult = {'items': []};
      final c = notificationsController(api);
      addTearDown(c.dispose);
      c.loading = false;
      await c.load(silent: true);
      expect(c.loading, isFalse);
    });
  });

  group('分页', () {
    test('loadMore：无列表 / 无更多时不发请求', () async {
      final api = FakeNotificationsApi();
      final c = notificationsController(api);
      addTearDown(c.dispose);
      c.loading = false;
      await c.loadMore();
      expect(api.listCalls, isEmpty);

      c.feed.replaceAll([], 0);
      c.feed.hasMore = false;
      await c.loadMore();
      expect(api.listCalls, isEmpty);
    });

    test('loadMore：传 before=最后一条 id 并追加去重', () async {
      final api = FakeNotificationsApi()
        ..listResult = {
          'items': [
            {'id': 49, 'ts': 2, 'level': 'normal', 'source': 's', 'title': 'old'},
          ],
        };
      final c = notificationsController(api);
      addTearDown(c.dispose);
      c.loading = false;
      c.feed.replaceAll(
        List.generate(
          kNotificationsPageSize,
          (i) => notificationItem(100 - i, title: 'n$i'),
        ),
        0,
      );
      expect(c.feed.hasMore, isTrue);
      await c.loadMore();
      expect(api.listCalls.single['before'], 100 - (kNotificationsPageSize - 1));
      expect(c.feed.items.last.id, 49);
    });
  });

  group('筛选', () {
    test('值未变化不发请求；变化后按新条件重载', () async {
      final api = FakeNotificationsApi()..listResult = {'items': []};
      final c = notificationsController(api);
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);

      c.setUnreadOnly(false);
      c.setLevelFilter('');
      expect(api.listCalls, isEmpty);
      expect(notifications, 0);

      c.setUnreadOnly(true);
      c.setLevelFilter('urgent');
      c.setSourceFilter('src');
      c.setTypeFilter('watchdog');
      await pumpEventQueue();
      expect(api.listCalls, hasLength(4));
      expect(api.listCalls.last['unreadOnly'], isTrue);
      expect(api.listCalls.last['level'], 'urgent');
      expect(api.listCalls.last['source'], 'src');
      expect(api.listCalls.last['type'], 'watchdog');
    });

    test('matchesFilter 叠加 unread / level / source / type', () {
      final c = notificationsController(FakeNotificationsApi());
      addTearDown(c.dispose);
      final item = notificationItem(
        1,
        level: 'urgent',
        source: 'src',
        type: 'watchdog',
      );
      expect(c.matchesFilter(item), isTrue);

      c.unreadOnly = true;
      expect(c.matchesFilter(item), isTrue, reason: '未读条目在未读筛选下保留');
      final read = notificationItem(
        2,
        level: 'urgent',
        source: 'src',
        type: 'watchdog',
        readAt: 5,
      );
      expect(c.matchesFilter(read), isFalse, reason: '已读条目被未读筛选剔除');
      c.unreadOnly = false;
      c.levelFilter = 'normal';
      expect(c.matchesFilter(item), isFalse);
      c.levelFilter = '';
      c.sourceFilter = 'other';
      expect(c.matchesFilter(item), isFalse);
      c.sourceFilter = '';
      c.typeFilter = 'other';
      expect(c.matchesFilter(item), isFalse);
    });
  });

  group('类别清单', () {
    test('加载成功：写入类别；选中项失效则回落全部', () async {
      final api = FakeNotificationsApi()
        ..typesResult = [notificationType('watchdog', label: '看门狗')];
      final c = notificationsController(api);
      addTearDown(c.dispose);
      c.typeFilter = 'gone';
      await c.loadTypes();
      expect(c.types.single.key, 'watchdog');
      expect(c.typeFilter, '');
    });

    test('选中项仍有效则保留', () async {
      final api = FakeNotificationsApi()
        ..typesResult = [notificationType('watchdog')];
      final c = notificationsController(api);
      addTearDown(c.dispose);
      c.typeFilter = 'watchdog';
      await c.loadTypes();
      expect(c.typeFilter, 'watchdog');
    });

    test('加载失败：类别置空、筛选回落，并交给鉴权处理', () async {
      var authCalls = 0;
      final api = FakeNotificationsApi()..typesError = Exception('fail');
      final c = notificationsController(
        api,
        onAuthError: (e) async {
          authCalls += 1;
          return false;
        },
      );
      addTearDown(c.dispose);
      c.typeFilter = 'watchdog';
      await c.loadTypes();
      expect(c.types, isEmpty);
      expect(c.typeFilter, '');
      expect(authCalls, 1);
    });
  });

  group('推送', () {
    test('匹配筛选的推送置顶并累加未读', () {
      final c = notificationsController(FakeNotificationsApi());
      addTearDown(c.dispose);
      c.applyIncoming(notificationItem(1, title: 'a'));
      expect(c.feed.items.single.id, 1);
      expect(c.feed.unread, 1);
      expect(c.sources, {'admin'});
    });

    test('不匹配筛选的推送不入列表，但来源仍被记录', () {
      final c = notificationsController(FakeNotificationsApi());
      addTearDown(c.dispose);
      c.unreadOnly = true;
      c.applyIncoming(notificationItem(1, readAt: 5, source: 's'));
      expect(c.feed.items, isEmpty);
      expect(c.feed.unread, 0);
      expect(c.sources, {'s'});
    });

    test('同 id 推送去重替换，不重复计未读', () {
      final c = notificationsController(FakeNotificationsApi());
      addTearDown(c.dispose);
      c.applyIncoming(notificationItem(1, title: 'a'));
      c.applyIncoming(notificationItem(1, title: 'b'));
      expect(c.feed.items.single.title, 'b');
      expect(c.feed.unread, 1);
    });
  });
}
