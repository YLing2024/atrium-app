import 'package:flutter_test/flutter_test.dart';

import 'package:home_admin/api.dart';
import 'package:home_admin/system/system_controller.dart';
import 'package:home_admin/system/system_format.dart';
import 'package:home_admin/trend_granularity.dart';

void main() {
  group('system_format', () {
    test('fmtBytes 按 TB/GB/MB/KB/B 分级并保留一位小数', () {
      expect(fmtBytes(null), '—');
      expect(fmtBytes(0), '0.0 B');
      expect(fmtBytes(512), '512.0 B');
      expect(fmtBytes(1024), '1.0 KB');
      expect(fmtBytes(1024 * 1024), '1.0 MB');
      expect(fmtBytes(1024 * 1024 * 1024), '1.0 GB');
      expect(fmtBytes(1024 * 1024 * 1024 * 1024), '1.0 TB');
    });

    test('fmtMB 整数去小数、非整数保留一位', () {
      expect(fmtMB(null), '—');
      expect(fmtMB(256), '256 MB');
      expect(fmtMB(12.5), '12.5 MB');
    });

    test('fmtRate 追加 /s', () {
      expect(fmtRate(null), '—');
      expect(fmtRate(1024), '1.0 KB/s');
    });

    test('fmtUptime 组合天/小时/分钟，空则「刚刚」', () {
      expect(fmtUptime(null), '刚刚');
      expect(fmtUptime(0), '刚刚');
      expect(fmtUptime(59), '刚刚');
      expect(fmtUptime(60), '1 分钟');
      expect(fmtUptime(3600 + 120), '1 小时 2 分钟');
      expect(fmtUptime(86400 + 3600), '1 天 1 小时');
    });

    test('fmtLoad 支持数组 / 字符串 / 其它', () {
      expect(fmtLoad([1.0, 0.5, 0.25]), '1.00 / 0.50 / 0.25');
      expect(fmtLoad('1.2 3.4'), '1.2 3.4');
      expect(fmtLoad(null), '—');
    });

    test('pctOf / numOr 容错非数字', () {
      expect(pctOf(42), 42.0);
      expect(pctOf('x'), 0.0);
      expect(numOr(7), 7);
      expect(numOr(null), 0);
    });

    test('fmtClock 补零到 HH:mm:ss', () {
      expect(fmtClock(DateTime(2026, 1, 2, 3, 4, 5)), '03:04:05');
    });
  });

  group('SystemController', () {
    test('setActive(true) 建连，setActive(false) 断开', () {
      var started = 0;
      var cancelled = 0;
      final controller = SystemController(
        streamStarter: ({
          required void Function(Map<String, dynamic>) onSnapshot,
          void Function(String?)? onError,
          void Function()? onDone,
        }) {
          started++;
          return SystemStreamBinding(() async => cancelled++);
        },
      );
      addTearDown(controller.dispose);

      controller.setActive(true);
      expect(started, 1);
      controller.setActive(false);
      expect(cancelled, 1);
    });

    test('applySnapshot 解析 system/history/services 并清空错误', () {
      final controller = SystemController(
        streamStarter: ({
          required void Function(Map<String, dynamic>) onSnapshot,
          void Function(String?)? onError,
          void Function()? onDone,
        }) =>
            SystemStreamBinding(() async {}),
      );
      addTearDown(controller.dispose);

      controller.applySnapshot({
        'system': {'hostname': 'h1'},
        'history': [
          {'ts': 1, 'cpu': 2.0},
        ],
        'services': {
          'services': [
            {'pid': 10, 'status': 'up'},
          ],
          'processes': [
            {'pid': 10, 'name': 'p', 'mem_mb': 5, 'cpu': 1.0},
          ],
          'total_cpu': 1.5,
        },
      });

      expect(controller.data, {'hostname': 'h1'});
      expect(controller.history.length, 1);
      expect(controller.services.length, 1);
      expect(controller.processes.length, 1);
      expect(controller.totalCpu, 1.5);
      expect(controller.error, isNull);
      expect(controller.updated, isNotNull);
    });

    test('applySnapshot 坏结构回退为空，不抛异常', () {
      final controller = SystemController(
        streamStarter: ({
          required void Function(Map<String, dynamic>) onSnapshot,
          void Function(String?)? onError,
          void Function()? onDone,
        }) =>
            SystemStreamBinding(() async {}),
      );
      addTearDown(controller.dispose);

      controller.applySnapshot({'system': 'bad', 'history': 3});
      expect(controller.data, isNull);
      expect(controller.history, isEmpty);
      expect(controller.processes, isEmpty);
      expect(controller.totalCpu, isNull);
    });

    test('setProcSort 变化才通知，selectGranularity 去重', () {
      final controller = SystemController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setProcSort('mem');
      expect(notifications, 0);
      controller.setProcSort('cpu');
      expect(controller.procSort, 'cpu');
      expect(notifications, 1);

      controller.selectGranularity(TrendGranularity.sec);
      expect(notifications, 1);
      controller.selectGranularity(TrendGranularity.min);
      expect(controller.granularity, TrendGranularity.min);
      expect(notifications, 2);
    });

    test('非秒档拉取聚合点并缓存，切回渲染缓存（不请求实时流）', () async {
      final calls = <String>[];
      final controller = SystemController(
        streamStarter: ({
          required void Function(Map<String, dynamic>) onSnapshot,
          void Function(String?)? onError,
          void Function()? onDone,
        }) =>
            SystemStreamBinding(() async {}),
        metricsFetcher: ({required String range, required String step}) async {
          calls.add('$range/$step');
          return const SystemMetrics(
            points: [
              {'ts': 1, 'cpu': 2.0},
            ],
            meta: {'recordedSeconds': 720},
          );
        },
      );
      addTearDown(controller.dispose);

      controller.setActive(true);
      controller.selectGranularity(TrendGranularity.min);
      await Future<void>.delayed(Duration.zero);

      expect(calls, ['1d/1m']);
      expect(controller.granPoints.length, 1);
      expect(controller.granRecordedMinutes, 12);
    });
  });
}
