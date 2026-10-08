import 'package:flutter/material.dart';

import '../login_page.dart';
import '../theme.dart';
import 'blog_widgets.dart';
import 'collection_editor_controller.dart';

/// 合集编辑器：名称 + 描述，新建 / 编辑。
class CollectionEditor extends StatefulWidget {
  const CollectionEditor({
    super.key,
    required this.collection,
    required this.onBack,
    required this.onSaved,
    this.controller,
  });

  final Map<String, dynamic>? collection;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  /// 可注入控制器（测试用）；为空时按 [collection] 自行创建。
  final CollectionEditorController? controller;

  @override
  State<CollectionEditor> createState() => _CollectionEditorState();
}

class _CollectionEditorState extends State<CollectionEditor> {
  late final CollectionEditorController _c;

  @override
  void initState() {
    super.initState();
    _c = widget.controller ??
        CollectionEditorController(
          collection: widget.collection,
          onSaved: widget.onSaved,
          onAuthError: (e) => handleAuthError(context, e),
        );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              InkWell(
                onTap: _c.saving ? null : widget.onBack,
                child: Row(
                  children: [
                    Icon(Icons.arrow_back, size: 18, color: c.accent),
                    const SizedBox(width: 4),
                    Text(
                      '返回',
                      style: TextStyle(color: c.accent, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _c.isNew ? '新建合集' : '编辑合集',
                style: TextStyle(
                  color: c.fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '名称 *',
            style: TextStyle(
              color: c.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _c.name,
            autofocus: _c.isNew,
            decoration: const InputDecoration(hintText: '合集名称'),
          ),
          const SizedBox(height: 12),
          Text(
            '合集 ID',
            style: TextStyle(
              color: c.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          blogReadonlyValue(
            c,
            widget.collection?['public_id']?.toString() ?? '',
            '保存后自动生成',
          ),
          const SizedBox(height: 12),
          Text(
            '描述',
            style: TextStyle(
              color: c.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _c.desc,
            maxLines: 3,
            decoration: const InputDecoration(hintText: '合集简介（列表页展示）'),
          ),
          if (_c.error != null) ...[
            const SizedBox(height: 10),
            Text(_c.error!, style: TextStyle(color: c.danger, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _c.saving ? null : widget.onBack,
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                onPressed: _c.saving ? null : _c.submit,
                child: _c.saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
