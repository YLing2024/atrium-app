import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import 'blog_controller.dart';
import 'blog_format.dart';

/// 草稿读写抽象；生产用 [PrefsDraftStore]（SharedPreferences），测试注入内存实现。
abstract class DraftStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);
}

/// [DraftStore] 的生产实现：原样转发到 [SharedPreferences]。
class PrefsDraftStore implements DraftStore {
  const PrefsDraftStore();

  Future<SharedPreferences> get _sp => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _sp).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await _sp).setString(key, value);

  @override
  Future<void> remove(String key) async => (await _sp).remove(key);
}

/// 图库选中结果（路径 + 文件名），对齐 XFile。
class PickedImage {
  const PickedImage(this.path, this.name);

  final String path;
  final String name;
}

/// 唤起图库选图的可注入入口（测试不触设备）。
typedef ImagePickerFn = Future<PickedImage?> Function();

/// 上传插图的可注入入口（测试不触网）。
typedef UploadImageFn = Future<String> Function(File file, String filename);

Future<PickedImage?> _defaultPickImage() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  return PickedImage(picked.path, picked.name);
}

Future<String> _defaultUploadImage(File file, String filename) =>
    Api.blogUploadImage(file, filename);

Future<bool> _defaultAuthError(Object e) async => false;

/// 文章编辑器状态与逻辑：草稿自动保存 / 恢复、提交、插图、预览切换。
///
/// 原为 `_PostEditorState` 的字段与方法；依赖通过构造函数注入，便于单测。
class PostEditorController extends ChangeNotifier {
  PostEditorController({
    required this.post,
    required this.collections,
    required VoidCallback onSaved,
    BlogApi? api,
    DraftStore? drafts,
    ImagePickerFn? pickImage,
    UploadImageFn? uploadImage,
    AuthErrorHandler? onAuthError,
  })  : _api = api ?? const HttpBlogApi(),
        _drafts = drafts ?? const PrefsDraftStore(),
        _pickImage = pickImage ?? _defaultPickImage,
        _uploadImage = uploadImage ?? _defaultUploadImage,
        _onAuthError = onAuthError ?? _defaultAuthError,
        _onSaved = onSaved {
    title = TextEditingController(text: post?['title']?.toString() ?? '');
    tags = TextEditingController(
      text: (post?['tags'] as List?)?.join(', ') ?? '',
    );
    excerpt = TextEditingController(text: post?['excerpt']?.toString() ?? '');
    content = TextEditingController(text: post?['content']?.toString() ?? '');
    final col = post?['collection'];
    collectionId = col is Map ? col['id'] as int? : null;
    published = post?['published'] == true;
  }

  final Map<String, dynamic>? post;
  final List<Map<String, dynamic>> collections;

  final BlogApi _api;
  final DraftStore _drafts;
  final ImagePickerFn _pickImage;
  final UploadImageFn _uploadImage;
  final AuthErrorHandler _onAuthError;
  final VoidCallback _onSaved;

  late final TextEditingController title;
  late final TextEditingController tags;
  late final TextEditingController excerpt;
  late final TextEditingController content;

  int? collectionId;
  bool published = false;
  bool preview = false;
  bool saving = false;
  String? error;
  String? notice;

  Timer? _draftTimer;
  Timer? _noticeTimer;
  bool _userEdited = false; // 打开编辑器后用户是否已输入（对齐 Web：恢复不覆盖已输入内容）
  bool _disposed = false;

  bool get isNew => post == null;
  String get draftKey => draftKeyFor(isNew: isNew, id: post?['id']);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 视图创建后调用：异步恢复未保存草稿。
  void init() {
    unawaited(restoreDraft());
  }

  // 防抖自动保存（独立于恢复：随输入触发，恢复只在 init 执行一次）
  void markChanged() {
    _userEdited = true;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 1500), saveDraft);
  }

  Future<void> restoreDraft() async {
    final raw = await _drafts.read(draftKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (_disposed) return;
      // 读取草稿期间用户可能已开始输入（SharedPreferences 首次加载有延迟）：
      // 已有输入则放弃恢复，避免旧草稿覆盖输入内容
      if (_userEdited) return;
      title.text = saved['title']?.toString() ?? title.text;
      tags.text = saved['tags']?.toString() ?? tags.text;
      excerpt.text = saved['excerpt']?.toString() ?? excerpt.text;
      content.text = saved['content']?.toString() ?? content.text;
      collectionId = saved['collection_id'];
      published = saved['published'] == true;
      notice = '已恢复未保存的草稿';
      _notify();
      _noticeTimer = Timer(const Duration(milliseconds: 3000), () {
        if (_disposed) return;
        notice = null;
        _notify();
      });
    } catch (_) {
      // 损坏的草稿 JSON 静默忽略
    }
  }

  Future<void> saveDraft() async {
    // 先同步快照字段值再异步等待，dispose 时保存不会读到已释放的控制器
    final data = jsonEncode({
      'title': title.text,
      'tags': tags.text,
      'excerpt': excerpt.text,
      'content': content.text,
      'collection_id': collectionId,
      'published': published,
    });
    await _drafts.write(draftKey, data);
  }

  Future<void> clearDraft() async {
    _draftTimer?.cancel();
    await _drafts.remove(draftKey);
  }

  Future<void> submit(bool publish) async {
    final titleText = title.text.trim();
    final titleError = validatePostTitle(title.text);
    if (titleError != null) {
      error = titleError;
      _notify();
      return;
    }
    final body = buildPostBody(
      title: titleText,
      tags: parseTags(tags.text),
      excerpt: excerpt.text.trim(),
      content: content.text,
      published: publish,
      collectionId: collectionId,
    );
    saving = true;
    error = null;
    _notify();
    try {
      if (isNew) {
        await _api.createPost(body);
      } else {
        await _api.updatePost(post!['id'] as int, body);
      }
      await clearDraft();
      if (_disposed) return;
      _onSaved();
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        error = e.toString();
        _notify();
      }
    } finally {
      if (!_disposed) {
        saving = false;
        _notify();
      }
    }
  }

  Future<void> insertImage() async {
    try {
      final picked = await _pickImage();
      if (picked == null) return;
      final url = await _uploadImage(File(picked.path), picked.name);
      if (_disposed) return;
      // 存相对路径，换域名也正确；预览与公开页各自拼上基址（对齐 Web）
      final mdText = '![]($url)';
      final sel = content.selection;
      final start = sel.isValid ? sel.start : content.text.length;
      final end = sel.isValid ? sel.end : content.text.length;
      final next = content.text.replaceRange(start, end, mdText);
      content.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + mdText.length),
      );
      notice = '图片已插入';
      _notify();
      _noticeTimer?.cancel();
      _noticeTimer = Timer(const Duration(milliseconds: 2500), () {
        if (_disposed) return;
        notice = null;
        _notify();
      });
    } catch (e) {
      if (_disposed) return;
      final handled = await _onAuthError(e);
      if (!handled && !_disposed) {
        error = '图片上传失败: ${e.toString()}';
        _notify();
      }
    }
  }

  void togglePreview() {
    preview = !preview;
    _notify();
  }

  void setCollectionId(int? v) {
    collectionId = v;
    _notify();
    markChanged();
  }

  void setPublished(bool v) {
    published = v;
    _notify();
    markChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    _draftTimer?.cancel();
    _noticeTimer?.cancel();
    unawaited(saveDraft());
    title.dispose();
    tags.dispose();
    excerpt.dispose();
    content.dispose();
    super.dispose();
  }
}
