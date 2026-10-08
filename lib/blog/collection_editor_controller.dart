import 'package:flutter/widgets.dart';

import 'blog_controller.dart';
import 'blog_format.dart';

Future<bool> _defaultAuthError(Object e) async => false;

/// 合集编辑器状态与逻辑：名称校验、新建 / 更新提交。
///
/// 原为 `_CollectionEditorState` 的字段与方法；依赖通过构造函数注入。
class CollectionEditorController extends ChangeNotifier {
  CollectionEditorController({
    required this.collection,
    required VoidCallback onSaved,
    BlogApi? api,
    AuthErrorHandler? onAuthError,
  })  : _api = api ?? const HttpBlogApi(),
        _onAuthError = onAuthError ?? _defaultAuthError,
        _onSaved = onSaved {
    name = TextEditingController(text: collection?['name']?.toString() ?? '');
    desc = TextEditingController(
      text: collection?['description']?.toString() ?? '',
    );
  }

  final Map<String, dynamic>? collection;

  final BlogApi _api;
  final AuthErrorHandler _onAuthError;
  final VoidCallback _onSaved;

  late final TextEditingController name;
  late final TextEditingController desc;

  bool saving = false;
  String? error;
  bool _disposed = false;

  bool get isNew => collection == null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> submit() async {
    final nameText = name.text.trim();
    final nameError = validateCollectionName(name.text);
    if (nameError != null) {
      error = nameError;
      _notify();
      return;
    }
    final body = buildCollectionBody(
      name: nameText,
      description: desc.text.trim(),
    );
    saving = true;
    error = null;
    _notify();
    try {
      if (isNew) {
        await _api.createCollection(body);
      } else {
        await _api.updateCollection(collection!['id'] as int, body);
      }
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

  @override
  void dispose() {
    _disposed = true;
    name.dispose();
    desc.dispose();
    super.dispose();
  }
}
