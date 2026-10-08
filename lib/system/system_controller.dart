import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api.dart';
import '../trend_granularity.dart';

/// 一次 SSE 订阅的可取消句柄；默认实现包装 [Api.systemStream]。
class SystemStreamBinding {
  const SystemStreamBinding(this.cancel);

  final Future<void> Function() cancel;
}

/// 建立 SSE 连接的可注入入口（便于单测替换，不触网）。
typedef SystemStreamStarter = SystemStreamBinding Function({
  required void Function(Map<String, dynamic> snapshot) onSnapshot,
  void Function(String? error)? onError,
  void Function()? onDone,
});

/// 拉取聚合指标的可注入入口（便于单测替换，不触网）。
typedef SystemMetricsFetcher = Future<SystemMetrics> Function({
  required String range,
  required String step,
});

SystemStreamBinding _startApiStream({
  required void Function(Map<String, dynamic> snapshot) onSnapshot,
  void Function(String? error)? onError,
  void Function()? onDone,
}) {
  final handle = Api.systemStream(
    onSnapshot: onSnapshot,
    onError: onError,
    onDone: onDone,
  );
  return SystemStreamBinding(handle.cancel);
}

/// 系统监控页状态与逻辑（原 `_SystemPageState` 的字段与方法）。
///
/// 「秒」档沿用 SSE 实时快照；非秒档走聚合接口并按档位间隔轮询，逻辑与
/// 原实现逐行一致。依赖通过构造函数注入，便于用假实现单测。
class SystemController extends ChangeNotifier {
  SystemController({
    SystemStreamStarter streamStarter = _startApiStream,
    SystemMetricsFetcher? metricsFetcher,
  })  : _streamStarter = streamStarter,
        _metricsFetcher = metricsFetcher ?? Api.systemMetrics;

  final SystemStreamStarter _streamStarter;
  final SystemMetricsFetcher _metricsFetcher;

  bool _active = false;
  bool _disposed = false;

  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _processes = [];
  List<Map<String, dynamic>> _services = [];
  double? _totalCpu; // 全部进程 CPU 合计（SSE services.total_cpu）
  String? _error;
  DateTime? _updated; // 最近一次快照时间（对齐 Web「更新于」）
  String _procSort = 'mem';

  // 趋势粒度：App 会话内记忆，退出 App 回默认「秒」（对齐 Web sessionStorage）
  TrendGranularity _granularity = TrendGranularity.sec;
  List<Map<String, dynamic>> _granPoints = []; // 非秒档最近一帧（失败保留）
  int? _granRecordedMinutes; // 非秒档 meta.recordedSeconds 的分钟数（空态文案）
  final Map<TrendGranularity, List<Map<String, dynamic>>> _granCache = {};
  final Map<TrendGranularity, int> _granMetaMinutes = {};
  Timer? _granTimer;

  SystemStreamBinding? _stream;
  Timer? _retryTimer;

  Map<String, dynamic>? get data => _data;
  List<Map<String, dynamic>> get history => _history;
  List<Map<String, dynamic>> get processes => _processes;
  List<Map<String, dynamic>> get services => _services;
  double? get totalCpu => _totalCpu;
  String? get error => _error;
  DateTime? get updated => _updated;
  String get procSort => _procSort;
  TrendGranularity get granularity => _granularity;
  List<Map<String, dynamic>> get granPoints => _granPoints;
  int? get granRecordedMinutes => _granRecordedMinutes;

  /// 是否处于可见 Tab：激活才建连，切走立即断开（对齐 Web System.jsx）。
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (active) {
      _connect(); // 切回系统 Tab：重新建连
      _syncGranularityPolling();
    } else {
      _disconnect(); // 切走：立即断开，零残留
      _syncGranularityPolling(); // 同时停掉非秒档轮询
    }
  }

  /// 手动刷新：重连 SSE 立即拉取最新快照；非秒档同时重拉聚合数据。
  Future<void> reconnect() async {
    _connect();
    _syncGranularityPolling();
  }

  /// 切换进程排序键（原 `_sortBtn` 的 setState）。
  void setProcSort(String key) {
    if (_procSort == key) return;
    _procSort = key;
    notifyListeners();
  }

  /// 切档：立即改档并按新档取数（秒档无轮询，用 SSE）。
  void selectGranularity(TrendGranularity g) {
    if (g == _granularity) return;
    _granularity = g;
    _syncGranularityPolling();
    notifyListeners();
  }

  void _disconnect() {
    _retryTimer?.cancel();
    _retryTimer = null;
    final stream = _stream;
    _stream = null;
    if (stream != null) unawaited(stream.cancel());
  }

  void _connect() {
    _disconnect();
    _stream = _streamStarter(
      onSnapshot: applySnapshot,
      onError: (err) {
        if (_disposed) return;
        _error = '连接已断开，正在重连…';
        notifyListeners();
      },
      onDone: _scheduleReconnect,
    );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    // 连接断开（或流结束）且 Tab 仍激活：5s 后自动重试
    if (!_active) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), () {
      if (!_disposed && _active) _connect();
    });
  }

  /// 应用一条 SSE 快照（原 `_onSnapshot`）。
  void applySnapshot(Map<String, dynamic> snapshot) {
    if (_disposed) return;
    final system = snapshot['system'];
    final hist = snapshot['history'];
    final servicesRaw = snapshot['services'];
    final services = servicesRaw is Map ? servicesRaw : <String, dynamic>{};
    _data = (system is Map) ? Map<String, dynamic>.from(system) : null;
    _history = (hist is List)
        ? hist.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : [];
    final s = services['services'];
    final p = services['processes'];
    _services = (s is List)
        ? s.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : [];
    _processes = (p is List)
        ? p.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : [];
    _totalCpu = services['total_cpu'] is num
        ? (services['total_cpu'] as num).toDouble()
        : null;
    _updated = DateTime.now();
    _error = null;
    notifyListeners();
  }

  /// 按当前档位重设取数：秒档停轮询；非秒档先渲染该档缓存再立即拉一次，
  /// 之后按档位间隔轮询（30s / 300s / 1800s）。切走 Tab 时不请求。
  void _syncGranularityPolling() {
    _granTimer?.cancel();
    _granTimer = null;
    final query = trendQueryOf(_granularity);
    if (!_active || query == null) return;
    final cached = _granCache[_granularity];
    if (cached != null) {
      // 切回已取过的档位：先渲染缓存，避免闪空（R4）
      _granPoints = cached;
      final minutes = _granMetaMinutes[_granularity];
      if (minutes != null) _granRecordedMinutes = minutes;
    }
    unawaited(_loadGranularity());
    _granTimer = Timer.periodic(
      query.refresh,
      (_) => unawaited(_loadGranularity()),
    );
  }

  /// 非秒档拉取聚合点。失败保留上一帧，不弹错、不阻断页面（R4 / R11）。
  Future<void> _loadGranularity() async {
    final g = _granularity;
    final query = trendQueryOf(g);
    if (query == null) return;
    try {
      final metrics = await _metricsFetcher(
        range: query.range,
        step: query.step,
      );
      if (_disposed || _granularity != g) return;
      _granPoints = metrics.points;
      _granCache[g] = metrics.points;
      final minutes = trendRecordedMinutes(metrics.recordedSeconds);
      if (minutes != null) {
        _granRecordedMinutes = minutes;
        _granMetaMinutes[g] = minutes;
      }
      notifyListeners();
    } catch (_) {
      // 保留上一帧，静默等下次刷新
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _disconnect();
    _granTimer?.cancel();
    _granTimer = null;
    super.dispose();
  }
}
