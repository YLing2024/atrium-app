import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_admin/api.dart';
import 'package:home_admin/files/files_controller.dart';

/// 无网络、无设备的假后端：记录调用并可控地完成 / 失败。
class _FakeFilesApi implements FilesApi {
  final List<String> listed = [];
  final List<String> mkdirs = [];
  final List<String> renames = [];
  final List<String> deletes = [];
  final List<String> uploads = [];

  Map<String, dynamic> listResult = {'path': '', 'entries': <dynamic>[]};
  Object? listError;
  Object? mkdirError;
  Object? uploadError;
  Completer<void>? uploadGate;

  @override
  Future<Map<String, dynamic>> list(String path) async {
    listed.add(path);
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<void> mkdir(String dir, String name) async {
    mkdirs.add('$dir|$name');
    if (mkdirError != null) throw mkdirError!;
  }

  @override
  Future<void> rename(String path, String name) async {
    renames.add('$path|$name');
  }

  @override
  Future<void> delete(String path) async {
    deletes.add(path);
  }

  @override
  Future<Map<String, dynamic>> upload(
    File file,
    String filename,
    String dir, {
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    uploads.add(joinPath(dir, filename));
    onProgress?.call(50, 100);
    final gate = uploadGate;
    if (gate != null) await gate.future;
    if (uploadError != null) throw uploadError!;
    return {'path': joinPath(dir, filename)};
  }

  @override
  String downloadUrl(String path) => 'https://example.com/download?path=$path';
}

PlatformFile _pick(String name, {String? path, int size = 100}) =>
    PlatformFile(name: name, size: size, path: path);

void main() {
  group('路径拼接与上一级导航', () {
    test('joinPath：根目录直接拼名，子目录用斜杠连接', () {
      expect(joinPath('', 'a.txt'), 'a.txt');
      expect(joinPath('docs', 'a.txt'), 'docs/a.txt');
      expect(joinPath('docs/2026', 'a.txt'), 'docs/2026/a.txt');
    });

    test('joinPath：中文与特殊字符原样保留', () {
      expect(joinPath('文档', '报告.pdf'), '文档/报告.pdf');
      expect(joinPath('a b', 'c#d?e'), 'a b/c#d?e');
      expect(joinPath('lost+found', 'f'), 'lost+found/f');
    });

    test('parentPath：根目录与一级目录都回到根', () {
      expect(parentPath(''), '');
      expect(parentPath('a'), '');
      expect(parentPath('a/b'), 'a');
      expect(parentPath('a/b/c'), 'a/b');
      expect(parentPath('文档/报告'), '文档');
    });

    test('crumbsOf：逐级累积路径', () {
      expect(crumbsOf(''), isEmpty);
      expect(crumbsOf('a'), [(name: 'a', path: 'a')]);
      expect(crumbsOf('a/b/c'), [
        (name: 'a', path: 'a'),
        (name: 'b', path: 'a/b'),
        (name: 'c', path: 'a/b/c'),
      ]);
    });
  });

  group('排序', () {
    final entries = [
      const FsEntry('bdir', true, 20, 2),
      const FsEntry('adir', true, 10, 1),
      const FsEntry('c.txt', false, 300, 30),
      const FsEntry('a.txt', false, 100, 10),
      const FsEntry('b.txt', false, 200, 20),
    ];

    test('名称升序：目录恒在前，再按名称', () {
      final out = sortedEntries(entries, 'name', 1);
      expect(out.map((e) => e.name).toList(), [
        'adir',
        'bdir',
        'a.txt',
        'b.txt',
        'c.txt',
      ]);
    });

    test('名称降序：目录仍在最前', () {
      final out = sortedEntries(entries, 'name', -1);
      expect(out.map((e) => e.name).toList(), [
        'bdir',
        'adir',
        'c.txt',
        'b.txt',
        'a.txt',
      ]);
    });

    test('大小升 / 降序', () {
      expect(
        sortedEntries(entries, 'size', 1).map((e) => e.name).toList(),
        ['adir', 'bdir', 'a.txt', 'b.txt', 'c.txt'],
      );
      expect(
        sortedEntries(entries, 'size', -1).map((e) => e.name).toList(),
        ['bdir', 'adir', 'c.txt', 'b.txt', 'a.txt'],
      );
    });

    test('时间升 / 降序', () {
      expect(
        sortedEntries(entries, 'time', 1).map((e) => e.name).toList(),
        ['adir', 'bdir', 'a.txt', 'b.txt', 'c.txt'],
      );
      expect(
        sortedEntries(entries, 'time', -1).map((e) => e.name).toList(),
        ['bdir', 'adir', 'c.txt', 'b.txt', 'a.txt'],
      );
    });

    test('toggleSort：同键翻转方向，换键重置升序', () {
      final c = FilesController(api: _FakeFilesApi());
      expect(c.sortKey, 'name');
      expect(c.sortDir, 1);
      c.toggleSort('name');
      expect(c.sortKey, 'name');
      expect(c.sortDir, -1);
      c.toggleSort('size');
      expect(c.sortKey, 'size');
      expect(c.sortDir, 1);
      c.toggleSort('size');
      expect(c.sortDir, -1);
    });
  });

  group('数据加载', () {
    test('解析条目、忽略坏结构、采纳服务端返回路径', () async {
      final api = _FakeFilesApi()
        ..listResult = {
          'path': 'docs',
          'entries': [
            {'name': 'a.txt', 'type': 'file', 'size': 10, 'mtime': 5},
            {'name': 'sub', 'type': 'dir'},
            {'name': '', 'type': 'file'},
            {'name': 'b.txt', 'type': 'file', 'size': 'x', 'mtime': null},
          ],
        };
      final c = FilesController(api: api);
      await c.load('docs');
      expect(c.path, 'docs');
      expect(c.loading, isFalse);
      expect(c.error, isNull);
      expect(c.entries.map((e) => e.name).toList(), ['a.txt', 'sub', 'b.txt']);
      expect(c.entries[1].isDir, isTrue);
      expect(c.entries[1].size, 0);
      expect(c.entries[2].size, 0);
      expect(c.entries[2].mtime, 0);
    });

    test('加载失败：置错误并清空条目', () async {
      final api = _FakeFilesApi()..listError = ApiException('目录不可读');
      final c = FilesController(api: api);
      await c.load('');
      expect(c.error, '目录不可读');
      expect(c.entries, isEmpty);
      expect(c.loading, isFalse);
    });

    test('enter：切换到子目录并刷新条目（跨目录清空旧列表）', () async {
      final api = _FakeFilesApi()
        ..listResult = {
          'path': 'docs',
          'entries': [
            {'name': 'sub', 'type': 'dir'},
          ],
        };
      final c = FilesController(api: api);
      await c.load('docs');
      expect(c.entries.single.name, 'sub');
      api.listResult = {
        'path': 'docs/sub',
        'entries': [
          {'name': 'deep.txt', 'type': 'file'},
        ],
      };
      c.enter(c.entries.single);
      await pumpEventQueue();
      expect(api.listed.last, 'docs/sub');
      expect(c.entries.single.name, 'deep.txt');
    });

    test('targetOf：根目录与子目录都拼出完整相对路径', () async {
      final api = _FakeFilesApi()..listResult = {'path': 'docs', 'entries': <dynamic>[]};
      final c = FilesController(api: api);
      await c.load('docs');
      expect(c.targetOf(const FsEntry('a.txt', false, 0, 0)), 'docs/a.txt');
    });
  });

  group('上传队列状态流转', () {
    test('上传中（带进度）→ 完成', () async {
      final api = _FakeFilesApi()..uploadGate = Completer<void>();
      final c = FilesController(api: api);
      c.enqueue([_pick('a.txt', path: '/tmp/a.txt')]);
      await pumpEventQueue();
      expect(c.uploads.single.status, 'uploading');
      expect(c.uploads.single.percent, 50);
      expect(c.uploads.single.loaded, 50);
      api.uploadGate!.complete();
      await pumpEventQueue();
      expect(c.uploads.single.status, 'done');
      expect(c.uploads.single.percent, 100);
      expect(api.uploads, ['a.txt']);
    });

    test('串行：前一个未完成时，后一个保持等待', () async {
      final api = _FakeFilesApi()..uploadGate = Completer<void>();
      final c = FilesController(api: api);
      c.enqueue([_pick('a.txt', path: '/tmp/a.txt')]);
      await pumpEventQueue();
      c.enqueue([_pick('b.txt', path: '/tmp/b.txt')]);
      // 新任务插到面板最前，且因串行仍在等待
      expect(c.uploads.first.name, 'b.txt');
      expect(c.uploads.first.status, 'waiting');
      expect(c.uploads.last.status, 'uploading');
      api.uploadGate!.complete();
      await pumpEventQueue();
      expect(c.uploads.every((u) => u.status == 'done'), isTrue);
    });

    test('失败 → 重试 → 成功', () async {
      final api = _FakeFilesApi()..uploadError = ApiException('写入失败');
      final c = FilesController(api: api);
      c.enqueue([_pick('a.txt', path: '/tmp/a.txt')]);
      await pumpEventQueue();
      expect(c.uploads.single.status, 'error');
      expect(c.uploads.single.error, '写入失败');

      api.uploadError = null;
      c.retryUpload(c.uploads.single);
      await pumpEventQueue();
      expect(c.uploads.single.status, 'done');
      expect(api.uploads.length, 2);
    });

    test('取消：移出面板并标记 canceled', () async {
      final api = _FakeFilesApi()..uploadGate = Completer<void>();
      final c = FilesController(api: api);
      c.enqueue([_pick('a.txt', path: '/tmp/a.txt')]);
      await pumpEventQueue();
      final job = c.uploads.single;
      c.cancelUpload(job);
      expect(c.uploads, isEmpty);
      expect(job.canceled, isTrue);
      api.uploadGate!.complete();
      await pumpEventQueue();
    });

    test('清除已完成：只移除 done / error', () async {
      final api = _FakeFilesApi();
      final c = FilesController(api: api);
      c.enqueue([_pick('a.txt', path: '/tmp/a.txt')]);
      await pumpEventQueue();
      expect(c.uploads.single.status, 'done');
      c.clearFinished();
      expect(c.uploads, isEmpty);
    });

    test('无路径的文件被跳过', () async {
      final api = _FakeFilesApi();
      final c = FilesController(api: api);
      c.enqueue([_pick('a.txt'), _pick('b.txt', path: '/tmp/b.txt')]);
      expect(c.uploads.length, 1);
      expect(c.uploads.single.name, 'b.txt');
      await pumpEventQueue();
    });
  });

  group('弹窗动作', () {
    test('mkdir：打开 / 提交 / 关闭', () async {
      final api = _FakeFilesApi()..listResult = {'path': 'docs', 'entries': <dynamic>[]};
      final c = FilesController(api: api);
      await c.load('docs');
      c.openMkdir();
      expect(c.dialogType, 'mkdir');
      expect(c.dialogTitle, '新建文件夹');
      expect(c.dialogTarget, 'docs');
      await c.submitDialog('新文件夹');
      expect(api.mkdirs, ['docs|新文件夹']);
      expect(c.dialogType, isNull);
      expect(c.dialogBusy, isFalse);
    });

    test('rename / delete：目标路径与目录标记正确', () async {
      final api = _FakeFilesApi()..listResult = {'path': 'docs', 'entries': <dynamic>[]};
      final c = FilesController(api: api);
      await c.load('docs');

      c.openRename(const FsEntry('a.txt', false, 0, 0));
      expect(c.dialogType, 'rename');
      expect(c.dialogValue, 'a.txt');
      expect(c.dialogTarget, 'docs/a.txt');
      expect(c.dialogIsDir, isFalse);

      c.openDelete(const FsEntry('sub', true, 0, 0));
      expect(c.dialogType, 'delete');
      expect(c.dialogTarget, 'docs/sub');
      expect(c.dialogIsDir, isTrue);

      await c.submitDialog('sub');
      expect(api.deletes, ['docs/sub']);
      expect(c.dialogType, isNull);
    });

    test('提交失败：保留弹窗并展示错误', () async {
      final api = _FakeFilesApi()
        ..listResult = {'path': '', 'entries': <dynamic>[]}
        ..mkdirError = ApiException('同名目录已存在');
      final c = FilesController(api: api);
      await c.load('');
      c.openMkdir();
      await c.submitDialog('   ');
      expect(c.dialogType, 'mkdir', reason: '空名称不提交');
      await c.submitDialog('bad');
      expect(api.mkdirs, ['|bad']);
      expect(c.dialogType, 'mkdir', reason: '失败保留弹窗');
      expect(c.dialogError, '同名目录已存在');
      expect(c.dialogBusy, isFalse);
    });

    test('closeDialog：清空错误与忙碌标记', () async {
      final c = FilesController(api: _FakeFilesApi());
      c.openMkdir();
      c.closeDialog();
      expect(c.dialogType, isNull);
      expect(c.dialogError, '');
      expect(c.dialogBusy, isFalse);
    });
  });

  group('格式化', () {
    test('formatSize', () {
      expect(formatSize(0), '0 B');
      expect(formatSize(1023), '1023 B');
      expect(formatSize(1024), '1.0 KB');
      expect(formatSize(1024 * 1024), '1.0 MB');
      expect(formatSize(1024 * 1024 * 1024), '1.0 GB');
      expect(formatSize(100 * 1024), '100 KB');
    });

    test('formatTime：未知时间戳返回破折号', () {
      expect(formatTime(0), '—');
      final ms = DateTime(2024, 1, 2, 3, 4).millisecondsSinceEpoch;
      expect(formatTime(ms), '2024-01-02 03:04');
    });

    test('formatDuration', () {
      expect(formatDuration(0), '');
      expect(formatDuration(double.nan), '');
      expect(formatDuration(5.2), '6 秒');
      expect(formatDuration(61.5), '1 分 2 秒');
    });

    test('messageOf：ApiException 取 message', () {
      expect(messageOf(ApiException('接口错误')), '接口错误');
      expect(messageOf(Exception('x')), 'Exception: x');
    });
  });
}
