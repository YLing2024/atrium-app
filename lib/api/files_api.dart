part of '../api.dart';

/* ============ 上传 / 下载 ============ */

/// POST /api/admin/upload（multipart 字段名 file）-> {path}
Future<String> filesUpload(File file, String filename) async {
  final res = await Api._sendMultipart(
    (headers) async => http.MultipartRequest(
      'POST',
      Api._uri(kApiBase, '/api/admin/upload'),
    )
      ..headers.addAll(headers)
      ..files.add(
        await http.MultipartFile.fromPath('file', file.path, filename: filename),
      ),
    timeout: const Duration(seconds: 120),
  );
  final data = Api._decode(res);
  final p = data['path'];
  if (p is! String || p.isEmpty) {
    throw ApiException('上传失败：未返回路径');
  }
  return p;
}

/// GET /api/admin/download?path= -> 文件字节（App 内带 Bearer 取回）
Future<Uint8List> filesDownload(String path) async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/download', {'path': path}));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw ApiException(Api._errorOf(res), code: res.statusCode);
  }
  return res.bodyBytes;
}

/// 文件下载 URL：交给**系统浏览器**打开（鉴权由浏览器携带的网关会话 cookie 完成）。
/// 不再把 App 的 Bearer 拼进 URL，令牌不落 URL / 浏览器历史。
/// App 内需要带 Bearer 直接取字节时用 [download]。
String filesDownloadUrl(String path) =>
    Api._uri(kApiBase, '/api/admin/files/download', {'path': path}).toString();

/// 把服务端返回的相对路径（图片 / 预览链接）拼成绝对地址；
/// 已是 http(s)、data 等带 scheme 的地址原样返回。
String filesAbsoluteUrl(String path) {
  final p = path.trim();
  if (p.isEmpty) return p;
  final uri = Uri.tryParse(p);
  if (uri != null && uri.hasScheme) return p;
  return p.startsWith('/') ? '$kApiBase$p' : '$kApiBase/$p';
}

/* ============ 文件区（对齐 Web Files.jsx / admin-server 文件路由） ============ */

/// GET /api/admin/files?path= -> { path, parent, entries: [{name, type, size, mtime}] }
/// path 为相对文件区根目录的路径，根目录为 ''（越界由后端拦截）。
/// _uri 的 queryParameters 走 Uri.encodeQueryComponent，`lost+found` 等名称编码正确。
Future<Map<String, dynamic>> filesList(String path) async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/files', {'path': path}));
  return Api._decode(res);
}

/// POST /api/admin/files/mkdir { path, name }
Future<void> filesMkdir(String dir, String name) async {
  final res = await Api._post(
    Api._uri(kApiBase, '/api/admin/files/mkdir'),
    body: jsonEncode({'path': dir, 'name': name}),
  );
  Api._decode(res);
}

/// POST /api/admin/files/rename { path, name }
Future<void> filesRename(String path, String name) async {
  final res = await Api._post(
    Api._uri(kApiBase, '/api/admin/files/rename'),
    body: jsonEncode({'path': path, 'name': name}),
  );
  Api._decode(res);
}

/// DELETE /api/admin/files?path=（目录递归删除）
Future<void> filesDelete(String path) async {
  final res = await Api._delete(Api._uri(kApiBase, '/api/admin/files', {'path': path}));
  Api._decode(res);
}

/// POST /api/admin/files/upload?path=（multipart 字段名 file，上限 500MB）
/// onProgress 回调已发送字节数（HTTP 段），落盘耗时可配合 99% 文案；
/// abortTrigger 完成即中断上传（取消按钮）；重名后端自动加 -2。
Future<Map<String, dynamic>> filesFileUpload(
  File file,
  String filename,
  String dir, {
  void Function(int sent, int total)? onProgress,
  Future<void>? abortTrigger,
}) async {
  final res = await Api._sendMultipart(
    (headers) async => _ProgressMultipartRequest(
      'POST',
      Api._uri(kApiBase, '/api/admin/files/upload', {'path': dir}),
      onProgress: onProgress,
    )
      ..headers.addAll(headers)
      ..abortTrigger = abortTrigger
      ..files.add(
        await http.MultipartFile.fromPath('file', file.path, filename: filename),
      ),
  );
  return Api._decode(res);
}

/* ============ 文件区 · 临时链接（限时分享，对齐 Web FileShare.jsx） ============ */
// 语义对齐后端 /api/admin/files/shares：expiresAt === 0 为永久有效哨兵；
// 分享链接一律使用后端返回的 url 字段，不拼域名。

/// GET /api/admin/files/shares -> { shares: [...] }
/// 列表接口正常返回 { shares }，这里兼容裸数组（双保险）。
Future<List<Map<String, dynamic>>> filesShares() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/admin/files/shares'));
  return Api._decodeListOr(res, 'shares')
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}

/// POST /api/admin/files/shares { path, ttlHours? | expiresAt?, note? } -> 记录（含 url）
/// ttlHours 与 expiresAt 二选一：expiresAt 为绝对 epoch 毫秒（0 = 永久），
/// 都不给时后端默认 24 小时。
Future<Map<String, dynamic>> filesShareCreate({
  required String path,
  int? ttlHours,
  int? expiresAt,
  String? note,
}) async {
  final body = <String, dynamic>{'path': path};
  if (expiresAt != null) {
    body['expiresAt'] = expiresAt;
  } else if (ttlHours != null) {
    body['ttlHours'] = ttlHours;
  }
  final n = note?.trim() ?? '';
  if (n.isNotEmpty) body['note'] = n;
  final res = await Api._post(
    Api._uri(kApiBase, '/api/admin/files/shares'),
    body: jsonEncode(body),
  );
  return Api._shareRecord(Api._decode(res));
}

/// PATCH /api/admin/files/shares/{id} { expiresAt?, note?, revoked? } -> 记录
/// expiresAt: 0 转永久；>0 改为该绝对到期时刻；revoked: true 撤销（不可逆）。
Future<Map<String, dynamic>> filesShareUpdate(
  String id, {
  int? expiresAt,
  String? note,
  bool? revoked,
}) async {
  final body = <String, dynamic>{};
  if (expiresAt != null) body['expiresAt'] = expiresAt;
  if (note != null) body['note'] = note;
  if (revoked != null) body['revoked'] = revoked;
  final res = await Api._patch(
    Api._uri(kApiBase, '/api/admin/files/shares/${Uri.encodeComponent(id)}'),
    body: jsonEncode(body),
  );
  return Api._shareRecord(Api._decode(res));
}

/// DELETE /api/admin/files/shares/{id}（仅删记录，不动磁盘文件）
Future<void> filesShareDelete(String id) async {
  final res = await Api._delete(
    Api._uri(kApiBase, '/api/admin/files/shares/${Uri.encodeComponent(id)}'),
  );
  Api._decode(res);
}

/// 带上传进度的 multipart 请求：finalize 时统计已发送字节，
/// 并支持通过 [abortTrigger] 中断（http Client 支持 Abortable）。
class _ProgressMultipartRequest extends http.MultipartRequest with http.Abortable {
  _ProgressMultipartRequest(super.method, super.url, {this.onProgress});

  final void Function(int sent, int total)? onProgress;

  @override
  Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    final total = contentLength;
    var sent = 0;
    final onP = onProgress;
    final base = super.finalize();
    if (onP == null) return base;
    return http.ByteStream(
      base.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            sent += data.length;
            onP(sent, total);
            sink.add(data);
          },
        ),
      ),
    );
  }
}
