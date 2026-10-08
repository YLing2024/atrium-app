import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';

/// 目录条目（对齐后端 files 路由返回结构）。
class FsEntry {
  const FsEntry(this.name, this.isDir, this.size, this.mtime);

  final String name;
  final bool isDir;
  final int size;
  final int mtime; // 毫秒时间戳，0 表示未知
}

/// 上传任务：串行执行，可取消 / 重试，带进度。
class UploadTask {
  UploadTask({
    required this.id,
    required this.file,
    required this.name,
    required this.size,
    required this.dir,
  });

  final String id;
  final File file;
  final String name;
  final int size;
  final String dir; // 目标目录（相对路径）

  String status = 'waiting'; // waiting / uploading / done / error
  int loaded = 0;
  double percent = 0;
  double speed = 0; // B/s
  double eta = 0; // s
  String error = '';
  bool canceled = false;
  Completer<void>? abort;
}

/* ============ 纯逻辑：路径 / 排序 / 格式化（可单测） ============ */

/// 相对路径拼接：根目录（''）下直接返回名称，否则 `dir/name`。
String joinPath(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

/// 上一级目录；根目录返回自身（''）。
String parentPath(String path) {
  if (path.isEmpty) return '';
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// 面包屑：逐级累积路径；根目录返回空。
List<({String name, String path})> crumbsOf(String path) {
  if (path.isEmpty) return const [];
  final out = <({String name, String path})>[];
  var cur = '';
  for (final part in path.split('/')) {
    cur = cur.isEmpty ? part : '$cur/$part';
    out.add((name: part, path: cur));
  }
  return out;
}

/// 排序：目录恒在前，再按 sortKey（name / size / time）与 sortDir（1 / -1）。
List<FsEntry> sortedEntries(List<FsEntry> entries, String sortKey, int sortDir) {
  final list = [...entries];
  list.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1; // 目录恒在前
    int r;
    if (sortKey == 'size') {
      r = a.size.compareTo(b.size);
    } else if (sortKey == 'time') {
      r = a.mtime.compareTo(b.mtime);
    } else {
      r = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    return r * sortDir;
  });
  return list;
}

/// 人类可读体积：B / KB / MB / GB / TB。
String formatSize(int n) {
  if (n < 1024) return '$n B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = n / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${units[i]}';
}

/// 毫秒时间戳 → `yyyy-MM-dd HH:mm`；未知（<=0）返回破折号。
String formatTime(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p2(d.month)}-${p2(d.day)} ${p2(d.hour)}:${p2(d.minute)}';
}

/// 秒 → 「x 秒 / x 分 x 秒」；非有限或 <=0 返回空串。
String formatDuration(double sec) {
  if (!sec.isFinite || sec <= 0) return '';
  if (sec < 60) return '${sec.ceil()} 秒';
  return '${sec ~/ 60} 分 ${(sec % 60).ceil()} 秒';
}

/// 统一错误取文案：ApiException 取 message，其余 toString。
String messageOf(Object e) => e is ApiException ? e.message : e.toString();

/* ============ 后端操作抽象（测试可注入假实现） ============ */

/// 文件区所需的后端操作；生产用 [HttpFilesApi]，测试注入假实现。
abstract class FilesApi {
  Future<Map<String, dynamic>> list(String path);

  Future<void> mkdir(String dir, String name);

  Future<void> rename(String path, String name);

  Future<void> delete(String path);

  Future<Map<String, dynamic>> upload(
    File file,
    String filename,
    String dir, {
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  });

  String downloadUrl(String path);
}

/// [FilesApi] 的生产实现：原样转发到 [Api]。
class HttpFilesApi implements FilesApi {
  const HttpFilesApi();

  @override
  Future<Map<String, dynamic>> list(String path) => Api.fileList(path);

  @override
  Future<void> mkdir(String dir, String name) => Api.fileMkdir(dir, name);

  @override
  Future<void> rename(String path, String name) => Api.fileRename(path, name);

  @override
  Future<void> delete(String path) => Api.fileDelete(path);

  @override
  Future<Map<String, dynamic>> upload(
    File file,
    String filename,
    String dir, {
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) =>
      Api.fileUpload(
        file,
        filename,
        dir,
        onProgress: onProgress,
        abortTrigger: abortTrigger,
      );

  @override
  String downloadUrl(String path) => Api.fileDownloadUrl(path);
}

/* ============ 控制器：目录导航 / 上传 / 弹窗动作 ============ */

/// 文件区状态与业务逻辑：目录导航、条目列表、排序、上传队列、分享入口。
///
/// 只依赖 [FilesApi] 与 Flutter foundation（[ChangeNotifier]），不碰 UI；
/// 页面用 `ListenableBuilder` 监听并重建。
class FilesController extends ChangeNotifier {
  FilesController({FilesApi? api}) : _api = api ?? const HttpFilesApi();

  final FilesApi _api;

  /// 文件区根目录。
  static const String root = '';

  String path = root;
  List<FsEntry> entries = [];
  bool loading = false;
  bool loadedOnce = false;
  String? error;

  String sortKey = 'name'; // name / size / time
  int sortDir = 1;

  final List<UploadTask> uploads = [];
  final List<UploadTask> _queue = [];
  bool _pumping = false;
  bool _disposed = false;

  // 弹窗状态机：mkdir / rename / delete 三种
  String? dialogType;
  String dialogTitle = '';
  String dialogValue = '';
  String dialogTarget = '';
  bool dialogIsDir = false;
  bool dialogBusy = false;
  String dialogError = '';

  /// 按当前排序展示的条目。
  List<FsEntry> get shown => sortedEntries(entries, sortKey, sortDir);

  /// 当前路径的面包屑。
  List<({String name, String path})> get crumbs => crumbsOf(path);

  /// 相对文件区根目录的完整目标路径。
  String targetOf(FsEntry e) => joinPath(path, e.name);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /* ---- 数据加载 ---- */

  /// 首次可见时懒加载根目录（只生效一次）。
  void loadOnce() {
    if (loadedOnce) return;
    loadedOnce = true;
    unawaited(load(root));
  }

  Future<void> load(String p) async {
    loading = true;
    error = null;
    _notify();
    try {
      final data = await _api.list(p);
      if (_disposed) return;
      final raw = data['entries'];
      final list = <FsEntry>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final name = (e['name'] ?? '').toString();
          if (name.isEmpty) continue;
          list.add(
            FsEntry(
              name,
              (e['type'] ?? 'file') == 'dir',
              e['size'] is num ? (e['size'] as num).toInt() : 0,
              e['mtime'] is num ? (e['mtime'] as num).toInt() : 0,
            ),
          );
        }
      }
      entries = list;
      path = (data['path'] ?? p).toString();
      loading = false;
      _notify();
    } catch (e) {
      if (_disposed) return;
      error = messageOf(e);
      entries = [];
      loading = false;
      _notify();
    }
  }

  /* ---- 排序 ---- */

  void toggleSort(String key) {
    if (sortKey == key) {
      sortDir = -sortDir;
    } else {
      sortKey = key;
      sortDir = 1;
    }
    _notify();
  }

  /* ---- 目录导航 ---- */

  void enter(FsEntry e) {
    unawaited(load(joinPath(path, e.name)));
  }

  void goParent() {
    if (path.isEmpty) return;
    unawaited(load(parentPath(path)));
  }

  /* ---- 上传队列（串行，带进度） ---- */

  /// 唤起系统文件选择器；失败返回错误文案，取消返回 null。
  Future<String?> pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return null;
      enqueue(result.files);
      return null;
    } catch (e) {
      return messageOf(e);
    }
  }

  /// 把选中的文件插入队列表并入队执行。
  void enqueue(List<PlatformFile> picked) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final jobs = <UploadTask>[];
    var i = 0;
    for (final f in picked) {
      final p = f.path;
      if (p == null || p.isEmpty) continue;
      jobs.add(
        UploadTask(
          id: '$stamp-$i-${f.name}',
          file: File(p),
          name: f.name,
          size: f.size,
          dir: path,
        ),
      );
      i += 1;
    }
    if (jobs.isEmpty) return;
    uploads.insertAll(0, jobs);
    if (uploads.length > 40) uploads.removeRange(40, uploads.length);
    _notify();
    _queue.addAll(jobs.reversed);
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      if (job.canceled) continue;
      await _runUpload(job);
    }
    _pumping = false;
    if (!_disposed) await load(path); // 全部结束刷新当前目录
  }

  Future<void> _runUpload(UploadTask job) async {
    if (job.canceled || _disposed) return;
    final abort = Completer<void>();
    job.abort = abort;
    final t0 = DateTime.now();
    job.status = 'uploading';
    job.loaded = 0;
    job.percent = 0;
    job.error = '';
    _notify();
    try {
      await _api.upload(
        job.file,
        job.name,
        job.dir,
        onProgress: (sent, total) {
          if (_disposed || job.canceled) return;
          final elapsed = DateTime.now().difference(t0).inMilliseconds / 1000;
          final speed = elapsed > 0.3 ? sent / elapsed : 0.0;
          job.loaded = sent;
          job.percent = total > 0 ? sent / total * 100 : 0;
          job.speed = speed;
          job.eta = speed > 0 ? (total - sent) / speed : 0;
          _notify();
        },
        abortTrigger: abort.future,
      );
      if (_disposed || job.canceled) return;
      job.status = 'done';
      job.loaded = job.size;
      job.percent = 100;
      job.speed = 0;
      job.eta = 0;
      _notify();
    } catch (e) {
      if (_disposed || job.canceled) return;
      job.status = 'error';
      job.error = messageOf(e);
      _notify();
    }
  }

  void cancelUpload(UploadTask job) {
    job.canceled = true;
    job.abort?.complete();
    uploads.remove(job);
    _notify();
  }

  void retryUpload(UploadTask job) {
    if (job.status != 'error') return;
    job.status = 'waiting';
    job.loaded = 0;
    job.percent = 0;
    job.speed = 0;
    job.eta = 0;
    job.error = '';
    job.canceled = false;
    _queue.add(job);
    _notify();
    unawaited(_pump());
  }

  void clearFinished() {
    uploads.removeWhere((u) => u.status == 'done' || u.status == 'error');
    _notify();
  }

  /* ---- 下载（系统浏览器） ---- */

  /// 用系统浏览器打开下载链接；失败返回错误文案，成功返回 null。
  Future<String?> download(FsEntry e) async {
    try {
      // 系统浏览器打开下载地址：鉴权走浏览器侧的网关会话 cookie（对齐 Web），
      // 不把 App 的 Bearer 拼进 URL。App 内带 Bearer 取字节用 Api.download()。
      final ok = await launchUrl(
        Uri.parse(_api.downloadUrl(targetOf(e))),
        mode: LaunchMode.externalApplication,
      );
      return ok ? null : '无法打开下载链接';
    } catch (e) {
      return '下载失败：${messageOf(e)}';
    }
  }

  /* ---- 弹窗动作 ---- */

  void openMkdir() {
    dialogType = 'mkdir';
    dialogTitle = '新建文件夹';
    dialogValue = '';
    dialogTarget = path;
    dialogIsDir = false;
    dialogError = '';
    _notify();
  }

  void openRename(FsEntry e) {
    dialogType = 'rename';
    dialogTitle = '重命名';
    dialogValue = e.name;
    dialogTarget = targetOf(e);
    dialogIsDir = e.isDir;
    dialogError = '';
    _notify();
  }

  void openDelete(FsEntry e) {
    dialogType = 'delete';
    dialogTitle = '删除';
    dialogValue = e.name;
    dialogTarget = targetOf(e);
    dialogIsDir = e.isDir;
    dialogError = '';
    _notify();
  }

  void closeDialog() {
    dialogType = null;
    dialogError = '';
    dialogBusy = false;
    _notify();
  }

  /// 提交当前弹窗动作；[value] 为输入框原文本（delete 忽略）。
  Future<void> submitDialog(String value) async {
    final type = dialogType;
    if (type == null || dialogBusy) return;
    final v = value.trim();
    if (type != 'delete' && v.isEmpty) return;
    dialogBusy = true;
    dialogError = '';
    _notify();
    try {
      if (type == 'mkdir') {
        await _api.mkdir(dialogTarget, v);
      } else if (type == 'rename') {
        await _api.rename(dialogTarget, v);
      } else {
        await _api.delete(dialogTarget);
      }
      if (_disposed) return;
      dialogBusy = false;
      dialogType = null;
      _notify();
      await load(path);
    } catch (e) {
      if (_disposed) return;
      dialogBusy = false;
      dialogError = messageOf(e);
      _notify();
    }
  }
}
