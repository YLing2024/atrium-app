part of '../api.dart';

/// GET /api/blog/admin/posts -> { list }
Future<List<dynamic>> blogApiPosts() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/blog/admin/posts'));
  final data = Api._decode(res);
  final list = data['list'];
  return list is List ? list : [];
}

/// POST /api/blog/admin/posts
Future<Map<String, dynamic>> blogApiCreatePost(Map<String, dynamic> body) async {
  final res = await Api._post(
    Api._uri(kApiBase, '/api/blog/admin/posts'),
    body: jsonEncode(body),
  );
  return Api._decode(res);
}

/// PUT /api/blog/admin/posts/{id}
Future<Map<String, dynamic>> blogApiUpdatePost(int id, Map<String, dynamic> body) async {
  final res = await Api._put(
    Api._uri(kApiBase, '/api/blog/admin/posts/$id'),
    body: jsonEncode(body),
  );
  return Api._decode(res);
}

/// DELETE /api/blog/admin/posts/{id}
Future<void> blogApiDeletePost(int id) async {
  final res = await Api._delete(Api._uri(kApiBase, '/api/blog/admin/posts/$id'));
  Api._decode(res);
}

/// GET /api/blog/admin/posts/{id}/preview-link -> { published, url }
/// 已发布回公开地址；草稿附短时效预览令牌（url 为服务端返回的相对路径）。
Future<Map<String, dynamic>> blogApiPostPreviewLink(int id) async {
  final res = await Api._get(
    Api._uri(kApiBase, '/api/blog/admin/posts/$id/preview-link'),
  );
  return Api._decode(res);
}

/// GET /api/blog/admin/collections -> { list }
Future<List<dynamic>> blogApiCollections() async {
  final res = await Api._get(Api._uri(kApiBase, '/api/blog/admin/collections'));
  final data = Api._decode(res);
  final list = data['list'];
  return list is List ? list : [];
}

/// POST /api/blog/admin/collections
Future<Map<String, dynamic>> blogApiCreateCollection(Map<String, dynamic> body) async {
  final res = await Api._post(
    Api._uri(kApiBase, '/api/blog/admin/collections'),
    body: jsonEncode(body),
  );
  return Api._decode(res);
}

/// PUT /api/blog/admin/collections/{id}
Future<Map<String, dynamic>> blogApiUpdateCollection(
  int id,
  Map<String, dynamic> body,
) async {
  final res = await Api._put(
    Api._uri(kApiBase, '/api/blog/admin/collections/$id'),
    body: jsonEncode(body),
  );
  return Api._decode(res);
}

/// DELETE /api/blog/admin/collections/{id}
Future<void> blogApiDeleteCollection(int id) async {
  final res = await Api._delete(Api._uri(kApiBase, '/api/blog/admin/collections/$id'));
  Api._decode(res);
}

/// POST /api/blog/admin/upload（multipart 字段名 image）-> { url }
Future<String> blogApiUploadImage(File file, String filename) async {
  final res = await Api._sendMultipart(
    (headers) async => http.MultipartRequest(
      'POST',
      Api._uri(kApiBase, '/api/blog/admin/upload'),
    )
      ..headers.addAll(headers)
      ..files.add(
        await http.MultipartFile.fromPath('image', file.path, filename: filename),
      ),
    timeout: const Duration(seconds: 60),
  );
  final data = Api._decode(res);
  final url = data['url'];
  if (url is! String || url.isEmpty) {
    throw ApiException('图片上传失败：未返回 URL');
  }
  return url;
}
