part of '../api.dart';

/// GET /api/admin/system
Future<Map<String, dynamic>> systemApiSystem() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/system'));
  return Api._decode(res);
}

/// GET /api/admin/system/history -> 采样点数组（服务端直接返回 JSON 数组）
Future<List<dynamic>> systemApiHistory() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/system/history'));
  return Api._decodeList(res);
}

/// GET /api/admin/system/metrics?range=&step= -> { points, meta }
///
/// 趋势聚合：`range` ∈ 1h|6h|1d|7d|30d，`step` ∈ 1m|5m|1h|1d（对齐 admin-web）。
/// 后端对未知参数回退 `range=1d&step=1m` 并返回 200；无数据返回 `points: []`
/// + 完整 `meta`，绝不 500。鉴权 / 401 续期沿用 [_authed] 统一链路。
Future<SystemMetrics> systemApiMetrics({
  required String range,
  required String step,
}) async {
  final res = await Api._get(
    Api._uri(kApiBase, '/api/admin/system/metrics', {'range': range, 'step': step}),
  );
  return SystemMetrics.fromJson(Api._decode(res));
}

/// GET /api/admin/services -> { services, processes }
Future<Map<String, dynamic>> systemApiServices() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/services'));
  return Api._decode(res);
}

/// GET /api/admin/versions -> { list }
Future<List<dynamic>> systemApiVersions() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/versions'));
  final data = Api._decode(res);
  final list = data['list'];
  return list is List ? list : [];
}

/// GET /api/admin/history -> { sessions: [{ id, title, time, message_count }] }
Future<Map<String, dynamic>> systemApiHistorySessions() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/history'));
  return Api._decode(res);
}

/// GET /api/admin/history/{id} -> { session: { id, title }, messages: [{ role, content, ts }] }
Future<Map<String, dynamic>> systemApiHistoryMessages(String id) async {
  final res = await Api._get(
    Api._uri(kApiBase, '/api/admin/history/${Uri.encodeComponent(id)}'),
  );
  return Api._decode(res);
}

/// 建立 /api/admin/system/stream 长连接。服务端每 ~1s 推一条
/// `event: snapshot / data: {system, services, history}`。
/// 返回句柄，调用 cancel() 即断开（对齐 Web：Tab 激活才连、切走断开）。
SystemStreamHandle systemApiStream({
  required void Function(Map<String, dynamic> snapshot) onSnapshot,
  void Function(String? error)? onError,
  void Function()? onDone,
}) {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => false;
  final handle = SystemStreamHandle._(client);
  handle._run(onSnapshot, onError, onDone);
  return handle;
}

/// SSE 长连接句柄：cancel() 断开流并释放连接
class SystemStreamHandle {
  SystemStreamHandle._(this._client);

  final HttpClient _client;
  HttpClientRequest? _request;
  bool _cancelled = false;
  bool _done = false;

  /// 建立连接并带上当前 Bearer；401 时先续期一次再重连。
  Future<HttpClientResponse> _open() async {
    final req = await _client.getUrl(Api._uri(kApiBase, '/api/admin/system/stream'));
    _request = req;
    final token = Auth.accessToken;
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    return req.close();
  }

  Future<void> _run(
    void Function(Map<String, dynamic> snapshot) onSnapshot,
    void Function(String? error)? onError,
    void Function()? onDone,
  ) async {
    try {
      var res = await _open();
      if (_cancelled) {
        _client.close(force: true);
        return;
      }
      if (res.statusCode == 401 && await Auth.refresh()) {
        if (_cancelled) {
          _client.close(force: true);
          return;
        }
        res = await _open();
        if (_cancelled) {
          _client.close(force: true);
          return;
        }
      }
      if (res.statusCode != 200) {
        if (!_cancelled) onError?.call(Api._errorOfStatus(res.statusCode));
        if (!_cancelled) onDone?.call();
        _done = true;
        _client.close(force: true);
        return;
      }
      // 按 \n\n 分帧解析 SSE
      final transformer = _SseTransformer();
      final subscription = res
          .transform(utf8.decoder)
          .transform(transformer)
          .listen(
            (frame) {
              if (_cancelled) return;
              final snapshot = Api._parseSseFrame(frame);
              if (snapshot != null) onSnapshot(snapshot);
            },
            onError: (Object e) {
              if (_cancelled) return;
              onError?.call(e.toString());
            },
            onDone: () {
              if (_cancelled) return;
              onDone?.call();
            },
            cancelOnError: true,
          );
      await subscription.asFuture<void>().catchError((_) {});
    } catch (e) {
      if (!_cancelled) {
        onError?.call(e.toString());
        onDone?.call();
      }
    } finally {
      _done = true;
      _client.close(force: true);
    }
  }

  /// 主动断开连接
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _request?.abort();
    _client.close(force: true);
  }

  bool get isDone => _done;
}

/// 将字节流按 SSE 帧（\n\n 分隔）切分
class _SseTransformer extends StreamTransformerBase<String, String> {
  @override
  Stream<String> bind(Stream<String> stream) async* {
    var buf = '';
    await for (final chunk in stream) {
      buf += chunk;
      int idx;
      while ((idx = buf.indexOf('\n\n')) != -1) {
        final frame = buf.substring(0, idx);
        buf = buf.substring(idx + 2);
        if (frame.trim().isNotEmpty) yield frame;
      }
    }
  }
}
