import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api.dart';
import 'blog_format.dart';

/// 鉴权失败处理：返回是否已处理（已触发登出）。需要 UI 上下文，由页面注入。
typedef AuthErrorHandler = Future<bool> Function(Object e);

/// 确认弹窗：返回用户是否点「确定」。由页面注入。
typedef ConfirmAction = Future<bool> Function(String title, String message);

/// 用系统浏览器打开链接。由页面注入（失败提示在 UI 侧）。
typedef OpenExternal = Future<void> Function(String url);

/// 失败提示（SnackBar）。由页面注入。
typedef ErrorToast = void Function(String msg);

/// 博客区所需的后端操作；生产用 [HttpBlogApi]，测试注入假实现。
abstract class BlogApi {
  Future<List<Map<String, dynamic>>> posts();

  Future<List<Map<String, dynamic>>> collections();

  Future<void> deletePost(int id);

  Future<void> deleteCollection(int id);

  Future<Map<String, dynamic>> postPreviewLink(int id);

  Future<void> createPost(Map<String, dynamic> body);

  Future<void> updatePost(int id, Map<String, dynamic> body);

  Future<void> createCollection(Map<String, dynamic> body);

  Future<void> updateCollection(int id, Map<String, dynamic> body);
}

/// [BlogApi] 的生产实现：原样转发到 [Api]。
class HttpBlogApi implements BlogApi {
  const HttpBlogApi();

  @override
  Future<List<Map<String, dynamic>>> posts() async =>
      parseItems(await Api.blogPosts());

  @override
  Future<List<Map<String, dynamic>>> collections() async =>
      parseItems(await Api.blogCollections());

  @override
  Future<void> deletePost(int id) => Api.blogDeletePost(id);

  @override
  Future<void> deleteCollection(int id) => Api.blogDeleteCollection(id);

  @override
  Future<Map<String, dynamic>> postPreviewLink(int id) =>
      Api.blogPostPreviewLink(id);

  @override
  Future<void> createPost(Map<String, dynamic> body) =>
      Api.blogCreatePost(body);

  @override
  Future<void> updatePost(int id, Map<String, dynamic> body) =>
      Api.blogUpdatePost(id, body);

  @override
  Future<void> createCollection(Map<String, dynamic> body) =>
      Api.blogCreateCollection(body);

  @override
  Future<void> updateCollection(int id, Map<String, dynamic> body) =>
      Api.blogUpdateCollection(id, body);
}

Future<bool> _defaultAuthError(Object e) async => false;

Future<bool> _defaultConfirm(String title, String message) async => false;

Future<void> _defaultOpenExternal(String url) async {}

void _defaultError(String msg) {}

/// 博客列表状态与业务逻辑：文章 / 合集双视图、编辑器路由、删除与打开。
///
/// 只依赖可注入的后端操作与回调，不碰 UI；页面用 `ListenableBuilder` 监听重建。
class BlogController extends ChangeNotifier {
  BlogController({
    BlogApi? api,
    AuthErrorHandler? onAuthError,
    ConfirmAction? confirm,
    OpenExternal? openExternal,
    ErrorToast? onError,
  })  : _api = api ?? const HttpBlogApi(),
        _onAuthError = onAuthError ?? _defaultAuthError,
        _confirm = confirm ?? _defaultConfirm,
        _openExternal = openExternal ?? _defaultOpenExternal,
        _onError = onError ?? _defaultError;

  final BlogApi _api;
  final AuthErrorHandler _onAuthError;
  final ConfirmAction _confirm;
  final OpenExternal _openExternal;
  final ErrorToast _onError;

  bool _disposed = false;

  String view = 'posts'; // posts | collections
  List<Map<String, dynamic>> posts = [];
  List<Map<String, dynamic>> collections = [];
  bool loading = true;
  String? error;

  // 编辑器状态：null=列表，'new'=新建，Map=编辑
  Object? editing;
  Object? editingCollection;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 首次进入：拉取文章与合集。
  void init() {
    unawaited(load());
  }

  Future<void> load() async {
    loading = true;
    _notify();
    try {
      final list = await _api.posts();
      var cols = <Map<String, dynamic>>[];
      try {
        cols = await _api.collections();
      } catch (_) {
        // 合集加载失败不阻塞文章列表
      }
      if (_disposed) return;
      posts = list;
      collections = cols;
      loading = false;
      error = null;
      _notify();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        loading = false;
        error = e.toString();
        _notify();
      }
    }
  }

  Future<void> reloadAll() async {
    try {
      final list = await _api.posts();
      var cols = <Map<String, dynamic>>[];
      try {
        cols = await _api.collections();
      } catch (_) {}
      if (_disposed) return;
      posts = list;
      collections = cols;
      error = null;
      _notify();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        error = e.toString();
        _notify();
      }
    }
  }

  /* ============ 视图与编辑器路由 ============ */

  void setView(String v) {
    view = v;
    _notify();
  }

  /// 点「新建」：按当前视图进入对应编辑器。
  void startCreate() {
    if (view == 'posts') {
      editing = 'new';
    } else {
      editingCollection = 'new';
    }
    _notify();
  }

  void openPostEditor(Map<String, dynamic> p) {
    editing = p;
    _notify();
  }

  void openCollectionEditor(Map<String, dynamic> col) {
    editingCollection = col;
    _notify();
  }

  void closeEditor() {
    editing = null;
    _notify();
  }

  void closeCollectionEditor() {
    editingCollection = null;
    _notify();
  }

  /* ============ 删除 ============ */

  Future<void> deletePost(Map<String, dynamic> p) async {
    final ok = await _confirm(
      '删除文章',
      '确定删除「${p['title']}」？此操作不可恢复。',
    );
    if (!ok) return;
    try {
      await _api.deletePost(p['id'] as int);
      await reloadAll();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) _onError(e.toString());
    }
  }

  Future<void> deleteCollection(Map<String, dynamic> col) async {
    final ok1 = await _confirm(
      '删除合集',
      '确定删除合集「${col['name']}」？',
    );
    if (!ok1 || _disposed) return;
    final ok2 = await _confirm(
      '再次确认',
      '再次确认：删除合集「${col['name']}」将解除该合集下所有文章的关联，此操作不可恢复。',
    );
    if (!ok2) return;
    try {
      await _api.deleteCollection(col['id'] as int);
      await reloadAll();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) _onError(e.toString());
    }
  }

  /* ============ 打开文章 / 合集页 ============ */

  /// 标题即入口（对齐 Web BlogAdmin.openPost）：
  /// 已发布 → 公开地址；草稿 → 先取带预览令牌的链接再打开。
  /// 接口入参始终是数字 id，public_id 只用于拼 URL。
  Future<void> openPost(Map<String, dynamic> p) async {
    final key = (p['public_id'] ?? p['slug'] ?? '').toString().trim();
    final id = p['id'];
    try {
      if (p['published'] == true) {
        if (key.isEmpty) return;
        await _openExternal(Api.absoluteUrl('/blog/$key'));
        return;
      }
      if (id is! int) return;
      final data = await _api.postPreviewLink(id);
      final url = (data['url'] ?? '').toString().trim();
      if (url.isEmpty) return;
      await _openExternal(Api.absoluteUrl(url));
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) _onError('打开文章失败：${e.toString()}');
    }
  }

  Future<void> openCollection(Map<String, dynamic> col) async {
    final key = (col['public_id'] ?? col['slug'] ?? '').toString().trim();
    if (key.isEmpty) return;
    await _openExternal(Api.absoluteUrl('/blog/collections/$key'));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
