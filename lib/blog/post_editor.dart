import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../api.dart';
import '../login_page.dart';
import '../theme.dart';
import 'blog_widgets.dart';
import 'post_editor_controller.dart';

/// 文章编辑器：Markdown 编辑 + 预览、插图、草稿自动保存。
class PostEditor extends StatefulWidget {
  const PostEditor({
    super.key,
    required this.post,
    required this.collections,
    required this.onBack,
    required this.onSaved,
    this.controller,
  });

  final Map<String, dynamic>? post;
  final List<Map<String, dynamic>> collections;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  /// 可注入控制器（测试用）；为空时按 [post] / [collections] 自行创建。
  final PostEditorController? controller;

  @override
  State<PostEditor> createState() => _PostEditorState();
}

class _PostEditorState extends State<PostEditor> {
  late final PostEditorController _c;

  @override
  void initState() {
    super.initState();
    _c = widget.controller ??
        PostEditorController(
          post: widget.post,
          collections: widget.collections,
          onSaved: widget.onSaved,
          onAuthError: (e) => handleAuthError(context, e),
        );
    _c.init();
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
                      '返回列表',
                      style: TextStyle(color: c.accent, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _c.isNew ? '新建文章' : '编辑文章',
                style: TextStyle(
                  color: c.fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 80),
            ],
          ),
          const SizedBox(height: 16),
          _field(c, '标题 *', TextField(
            controller: _c.title,
            autofocus: _c.isNew,
            onChanged: (_) => _c.markChanged(),
            decoration: const InputDecoration(hintText: '文章标题'),
          )),
          const SizedBox(height: 12),
          _field(c, '文章 ID', blogReadonlyValue(
            c,
            widget.post?['public_id']?.toString() ?? '',
            '保存后自动生成',
          )),
          const SizedBox(height: 12),
          _field(c, '标签', TextField(
            controller: _c.tags,
            onChanged: (_) => _c.markChanged(),
            decoration: const InputDecoration(hintText: '逗号分隔，如：前端, 生活'),
          )),
          const SizedBox(height: 12),
          _field(c, '摘要', TextField(
            controller: _c.excerpt,
            maxLines: 2,
            onChanged: (_) => _c.markChanged(),
            decoration: const InputDecoration(hintText: '列表页显示的摘要'),
          )),
          const SizedBox(height: 12),
          _field(c, '所属合集', InputDecorator(
            decoration: const InputDecoration(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: _c.collectionId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('无合集'),
                  ),
                  ...widget.collections.map(
                    (col) => DropdownMenuItem<int?>(
                      value: col['id'] as int,
                      child: Text(
                        (col['name'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: _c.setCollectionId,
              ),
            ),
          )),
          const SizedBox(height: 16),
          Row(
            children: [
              _toolBtn(c, '插图', _c.insertImage, icon: Icons.image_outlined),
              const SizedBox(width: 8),
              if (_c.notice != null)
                Expanded(
                  child: Text(
                    _c.notice!,
                    style: TextStyle(color: c.accent, fontSize: 12),
                  ),
                ),
              const Spacer(),
              _toolBtn(
                c,
                _c.preview ? '编辑' : '预览',
                _c.togglePreview,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_c.preview)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.border),
              ),
              child: MarkdownBody(
                data: _c.content.text,
                selectable: true,
                softLineBreak: true,
                // 相对路径图片（/api/blog/uploads/xxx.png）拼上 API 基址再加载
                sizedImageBuilder: (config) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Image.network(
                    Api.absoluteUrl(config.uri.toString()),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Text(
                      config.alt == null || config.alt!.isEmpty
                          ? '图片加载失败'
                          : config.alt!,
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ),
                ),
                onTapLink: (text, href, title) {
                  if (href != null && href.isNotEmpty) {
                    launchExternal(context, Api.absoluteUrl(href));
                  }
                },
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(color: c.fg, fontSize: 15, height: 1.7),
                  code: TextStyle(
                    color: c.accent,
                    fontSize: 13,
                    backgroundColor: c.codeBg,
                    fontFamily: 'monospace',
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: c.codeBg,
                    border: Border.all(color: c.border),
                  ),
                  codeblockPadding: const EdgeInsets.all(10),
                  // 长表格横向滚动，不撑破窄屏布局
                  tableColumnWidth: const IntrinsicColumnWidth(),
                  tableBorder: TableBorder.all(color: c.border),
                  tableHead: TextStyle(
                    color: c.fg,
                    fontWeight: FontWeight.w600,
                  ),
                  h1: TextStyle(
                    color: c.fg,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                  h2: TextStyle(
                    color: c.fg,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  h3: TextStyle(
                    color: c.fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  a: TextStyle(
                    color: c.accent,
                    decoration: TextDecoration.underline,
                  ),
                  listBullet: TextStyle(color: c.muted, fontSize: 15),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(left: BorderSide(color: c.accentBorder, width: 3)),
                  ),
                  blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                ),
              ),
            )
          else
            TextField(
              controller: _c.content,
              minLines: 10,
              maxLines: 16,
              onChanged: (_) => _c.markChanged(),
              style: TextStyle(
                color: c.fg,
                fontSize: 13,
                fontFamily: 'monospace',
                height: 1.6,
              ),
              decoration: const InputDecoration(
                hintText: '支持 Markdown 语法',
                alignLabelWithHint: true,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _c.published,
                onChanged: _c.saving
                    ? null
                    : (v) => _c.setPublished(v ?? false),
                activeColor: c.accent,
              ),
              Expanded(
                child: Text(
                  '发布状态（勾选为已发布，否则保存为草稿）',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
            ],
          ),
          if (_c.error != null) ...[
            const SizedBox(height: 6),
            Text(_c.error!, style: TextStyle(color: c.danger, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _c.saving ? null : widget.onBack,
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _c.saving ? null : () => _c.submit(_c.published),
                child: _c.saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                onPressed: _c.saving ? null : () => _c.submit(true),
                child: const Text('发布'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(AppColors c, String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: c.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _toolBtn(AppColors c, String label, VoidCallback onTap, {IconData? icon}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: c.muted),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
