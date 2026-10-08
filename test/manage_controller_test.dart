import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_admin/manage/manage_controller.dart';
import 'package:home_admin/manage/manage_format.dart';

/// 无网络、无设备的假后端：记录调用并可控地完成 / 失败。
class _FakeManageApi implements ManageApi {
  List<Map<String, dynamic>> sessionsResult = [];
  Object? sessionsError;
  final List<String> renames = [];
  Completer<void>? renameGate;
  Object? renameError;
  final List<String> deletes = [];
  Object? deleteError;

  List<Map<String, dynamic>> tokensResult = [];
  Object? tokensError;
  final List<Map<String, dynamic>> creates = [];
  Map<String, dynamic> createResult = const {};
  Object? createError;
  final List<String> updates = [];
  Object? updateError;
  final List<String> tokenDeletes = [];
  Object? tokenDeleteError;

  @override
  Future<List<Map<String, dynamic>>> sessions() async {
    if (sessionsError != null) throw sessionsError!;
    return sessionsResult;
  }

  @override
  Future<void> sessionRename(String id, String deviceName) async {
    renames.add('$id|$deviceName');
    final gate = renameGate;
    if (gate != null) await gate.future;
    if (renameError != null) throw renameError!;
  }

  @override
  Future<void> sessionDelete(String id) async {
    deletes.add(id);
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<List<Map<String, dynamic>>> apiTokens() async {
    if (tokensError != null) throw tokensError!;
    return tokensResult;
  }

  @override
  Future<Map<String, dynamic>> apiTokenCreate({
    required String name,
    required String note,
    required int expiresInDays,
  }) async {
    creates.add({'name': name, 'note': note, 'expiresInDays': expiresInDays});
    if (createError != null) throw createError!;
    return createResult;
  }

  @override
  Future<void> apiTokenUpdate(String id, Map<String, dynamic> patch) async {
    updates.add('$id|$patch');
    if (updateError != null) throw updateError!;
  }

  @override
  Future<void> apiTokenDelete(String id) async {
    tokenDeletes.add(id);
    if (tokenDeleteError != null) throw tokenDeleteError!;
  }
}

ManageController _controller(
  _FakeManageApi api, {
  Future<bool> Function(Object e)? onAuthError,
  Future<void> Function()? forceLogout,
  Future<bool> Function()? isIgnoringBattery,
  Future<bool> Function()? restartService,
  Future<void> Function()? requestBatteryOptimization,
  Future<void> Function()? syncStore,
}) =>
    ManageController(
      api: api,
      onAuthError: onAuthError,
      forceLogout: forceLogout,
      isIgnoringBattery: isIgnoringBattery,
      restartService: restartService,
      requestBatteryOptimization: requestBatteryOptimization,
      syncStore: syncStore ?? () async {},
    );

void main() {
  group('格式化', () {
    test('fmtTime：未知返回破折号，已知按 yyyy-MM-dd HH:mm', () {
      expect(fmtTime(null), '—');
      expect(fmtTime(0), '—');
      final ms = DateTime(2024, 1, 2, 3, 4).millisecondsSinceEpoch;
      expect(fmtTime(ms), '2024-01-02 03:04');
    });

    test('fmtDate：未知返回破折号，已知按 yyyy-MM-dd', () {
      expect(fmtDate(null), '—');
      expect(fmtDate(0), '—');
      final ms = DateTime(2024, 12, 31).millisecondsSinceEpoch;
      expect(fmtDate(ms), '2024-12-31');
    });

    test('relativeTime：分档与边界', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final base = now.millisecondsSinceEpoch;
      expect(relativeTime(null, now: now), '—');
      expect(relativeTime(base - 59 * 1000, now: now), '刚刚');
      expect(relativeTime(base - 60 * 1000, now: now), '1 分钟前');
      expect(relativeTime(base - 59 * 60 * 1000, now: now), '59 分钟前');
      expect(relativeTime(base - 60 * 60 * 1000, now: now), '1 小时前');
      expect(relativeTime(base - 23 * 3600 * 1000, now: now), '23 小时前');
      expect(relativeTime(base - 24 * 3600 * 1000, now: now), '1 天前');
      expect(relativeTime(base - 3 * 86400 * 1000, now: now), '3 天前');
    });

    test('remainingDays：已过期 / 未知为 0，未到期取整天', () {
      final now = DateTime(2026, 1, 1, 0, 0, 0);
      final base = now.millisecondsSinceEpoch;
      expect(remainingDays(null, now: now), 0);
      expect(remainingDays(0, now: now), 0);
      expect(remainingDays(base - 1000, now: now), 0);
      expect(remainingDays(base + 5 * 86400 * 1000, now: now), 5);
      expect(remainingDays(base + 5 * 86400 * 1000 + 1000, now: now), 5);
    });

    test('validateTokenName：空 / 空白不通过', () {
      expect(validateTokenName(''), '令牌名称不能为空');
      expect(validateTokenName('   '), '令牌名称不能为空');
      expect(validateTokenName('  行情脚本 '), isNull);
    });

    test('parseExpiryDays：仅接受 1~365 的整数', () {
      expect(parseExpiryDays('1'), 1);
      expect(parseExpiryDays(' 365 '), 365);
      expect(parseExpiryDays('0'), isNull);
      expect(parseExpiryDays('366'), isNull);
      expect(parseExpiryDays('abc'), isNull);
      expect(parseExpiryDays(''), isNull);
    });
  });

  group('设备会话', () {
    test('初始状态：两端都在加载中', () {
      final c = _controller(_FakeManageApi());
      expect(c.loadingSessions, isTrue);
      expect(c.loadingTokens, isTrue);
      expect(c.sessions, isEmpty);
      expect(c.ignoringBattery, isFalse);
    });

    test('加载成功：写入列表并结束加载', () async {
      final api = _FakeManageApi()
        ..sessionsResult = [
          {'id': 1, 'deviceName': '手机', 'isCurrent': true},
        ];
      final c = _controller(api);
      await c.loadSessions();
      expect(c.sessions.single['deviceName'], '手机');
      expect(c.loadingSessions, isFalse);
      expect(c.sessionsError, isNull);
    });

    test('加载失败：记录错误并结束加载', () async {
      final api = _FakeManageApi()..sessionsError = Exception('读取失败');
      final c = _controller(api);
      await c.loadSessions();
      expect(c.sessionsError, 'Exception: 读取失败');
      expect(c.loadingSessions, isFalse);
    });

    test('鉴权失败且已处理：不记录错误、保持加载态', () async {
      final api = _FakeManageApi()..sessionsError = Exception('401');
      final c = _controller(api, onAuthError: (e) async => true);
      await c.loadSessions();
      expect(c.sessionsError, isNull);
      expect(c.loadingSessions, isTrue);
    });

    test('重命名：空名称报错且不发请求', () async {
      final api = _FakeManageApi();
      final c = _controller(api);
      c.startRename('1');
      await c.saveRename({'id': 1, 'deviceName': '手机'}, '   ');
      expect(c.editError, '设备名称不能为空');
      expect(c.editingId, '1');
      expect(api.renames, isEmpty);
    });

    test('重命名：未改动直接退出编辑态，不发请求', () async {
      final api = _FakeManageApi();
      final c = _controller(api);
      c.startRename('1');
      await c.saveRename({'id': 1, 'deviceName': '手机'}, '手机');
      expect(c.editingId, isNull);
      expect(api.renames, isEmpty);
    });

    test('重命名成功：更新列表并退出编辑态', () async {
      final api = _FakeManageApi()
        ..sessionsResult = [
          {'id': 1, 'deviceName': '旧名'},
          {'id': 2, 'deviceName': '其它'},
        ];
      final c = _controller(api);
      await c.loadSessions();
      c.startRename('1');
      await c.saveRename(c.sessions.first, '新名');
      expect(api.renames, ['1|新名']);
      expect(c.sessions.first['deviceName'], '新名');
      expect(c.sessions[1]['deviceName'], '其它');
      expect(c.editingId, isNull);
      expect(c.editSaving, isFalse);
    });

    test('重命名失败：保留编辑态并展示错误', () async {
      final api = _FakeManageApi()
        ..sessionsResult = [
          {'id': 1, 'deviceName': '旧名'},
        ]
        ..renameError = Exception('写入失败');
      final c = _controller(api);
      await c.loadSessions();
      c.startRename('1');
      await c.saveRename(c.sessions.first, '新名');
      expect(c.editError, 'Exception: 写入失败');
      expect(c.editingId, '1', reason: '失败保留编辑态');
      expect(c.editSaving, isFalse);
    });

    test('重命名去重：进行中再次保存不重复发请求', () async {
      final api = _FakeManageApi()
        ..renameGate = Completer<void>()
        ..sessionsResult = [
          {'id': 1, 'deviceName': '旧名'},
        ];
      final c = _controller(api);
      await c.loadSessions();
      c.startRename('1');
      final first = c.saveRename(c.sessions.first, '新名');
      await pumpEventQueue();
      expect(c.renameInFlight, isTrue);
      await c.saveRename(c.sessions.first, '新名2');
      expect(api.renames, ['1|新名']);
      api.renameGate!.complete();
      await first;
      expect(c.editingId, isNull);
    });

    test('删除非当前设备：从列表移除', () async {
      final api = _FakeManageApi()
        ..sessionsResult = [
          {'id': 1, 'deviceName': '手机'},
          {'id': 2, 'deviceName': '平板'},
        ];
      final c = _controller(api);
      await c.loadSessions();
      await c.confirmDeleteSession(c.sessions.first);
      expect(api.deletes, ['1']);
      expect(c.sessions.single['id'], 2);
    });

    test('删除当前设备：撤销凭证并登出，不改列表', () async {
      final api = _FakeManageApi()
        ..sessionsResult = [
          {'id': 1, 'deviceName': '本机', 'isCurrent': true},
        ];
      var loggedOut = 0;
      final c = _controller(api, forceLogout: () async => loggedOut++);
      await c.loadSessions();
      await c.confirmDeleteSession(c.sessions.first);
      expect(loggedOut, 1);
      expect(c.sessions, hasLength(1), reason: '登出前不改列表');
    });
  });

  group('接口令牌', () {
    test('加载成功 / 失败', () async {
      final ok = _FakeManageApi()
        ..tokensResult = [
          {'id': 1, 'name': '脚本'},
        ];
      final c1 = _controller(ok);
      await c1.loadTokens();
      expect(c1.tokens.single['name'], '脚本');
      expect(c1.loadingTokens, isFalse);

      final bad = _FakeManageApi()..tokensError = Exception('读取失败');
      final c2 = _controller(bad);
      await c2.loadTokens();
      expect(c2.tokensError, 'Exception: 读取失败');
      expect(c2.loadingTokens, isFalse);
    });

    test('createToken：参数原样透传并返回原始数据', () async {
      final api = _FakeManageApi()..createResult = {'token': 'raw-token'};
      final c = _controller(api);
      final data = await c.createToken(
        name: '行情脚本',
        note: '备注',
        expiresInDays: 30,
      );
      expect(data['token'], 'raw-token');
      expect(api.creates.single, {
        'name': '行情脚本',
        'note': '备注',
        'expiresInDays': 30,
      });
    });

    test('updateToken：透传 id 与 patch', () async {
      final api = _FakeManageApi();
      final c = _controller(api);
      await c.updateToken('7', {'name': '新名'});
      expect(api.updates, ['7|{name: 新名}']);
    });

    test('吊销成功移除；失败记录错误', () async {
      final api = _FakeManageApi()
        ..tokensResult = [
          {'id': 1, 'name': 'A'},
          {'id': 2, 'name': 'B'},
        ];
      final c = _controller(api);
      await c.loadTokens();
      await c.deleteToken(c.tokens.first);
      expect(api.tokenDeletes, ['1']);
      expect(c.tokens.single['id'], 2);

      final bad = _FakeManageApi()
        ..tokensResult = [
          {'id': 1, 'name': 'A'},
        ]
        ..tokenDeleteError = Exception('吊销失败');
      final c2 = _controller(bad);
      await c2.loadTokens();
      await c2.deleteToken(c2.tokens.first);
      expect(c2.tokens, hasLength(1));
      expect(c2.tokensError, 'Exception: 吊销失败');
    });
  });

  group('通知保活', () {
    test('读取与申请忽略电池优化', () async {
      var ignoring = false;
      var requested = 0;
      final c = _controller(
        _FakeManageApi(),
        isIgnoringBattery: () async => ignoring,
        requestBatteryOptimization: () async {
          requested++;
          ignoring = true;
        },
      );
      await c.loadBatteryStatus();
      expect(c.ignoringBattery, isFalse);
      await c.requestBatteryOptimization();
      expect(requested, 1);
      expect(c.ignoringBattery, isTrue);
    });

    test('restartNotificationService：透传结果', () async {
      final c = _controller(_FakeManageApi(), restartService: () async => true);
      expect(await c.restartNotificationService(), isTrue);
    });
  });

  group('刷新', () {
    test('refresh 同时重载会话与令牌，并同步通知状态', () async {
      final api = _FakeManageApi()
        ..sessionsResult = [
          {'id': 1, 'deviceName': '手机'},
        ]
        ..tokensResult = [
          {'id': 1, 'name': '脚本'},
        ];
      var synced = 0;
      final c = _controller(api, syncStore: () async => synced++);
      await c.refresh();
      expect(synced, 1);
      expect(c.sessions, hasLength(1));
      expect(c.tokens, hasLength(1));
    });
  });
}
