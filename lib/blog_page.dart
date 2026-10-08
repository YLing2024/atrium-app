import 'dart:async';

import 'package:flutter/material.dart';

import 'blog/blog_controller.dart';
import 'blog/blog_post_list.dart';
import 'blog/blog_widgets.dart';
import 'blog/collection_editor.dart';
import 'blog/post_editor.dart';
import 'login_page.dart';

/// 博客管理页（对齐 Web 端 BlogAdmin）：
/// 文章/合集双视图 CRUD、Markdown 编辑+预览、插图、草稿自动保存
///
/// 状态与逻辑都在 [BlogController]，这里只负责组合、生命周期与弹窗入口。
class BlogPage extends StatefulWidget {
  const BlogPage({super.key});

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> {
  late final BlogController _c;

  @override
  void initState() {
    super.initState();
    _c = BlogController(
      onAuthError: (e) => handleAuthError(context, e),
      confirm: (title, message) => showBlogConfirm(context, title, message),
      openExternal: (url) => launchExternal(context, url),
      onError: (msg) => showBlogErrorToast(context, msg),
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
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        if (_c.editingCollection != null) {
          return CollectionEditor(
            collection: _c.editingCollection is Map
                ? _c.editingCollection as Map<String, dynamic>
                : null,
            onBack: _c.closeCollectionEditor,
            onSaved: () {
              _c.closeCollectionEditor();
              unawaited(_c.reloadAll());
            },
          );
        }
        if (_c.editing != null) {
          final post = _c.editing is Map
              ? _c.editing as Map<String, dynamic>
              : null;
          return PostEditor(
            post: post,
            collections: _c.collections,
            onBack: _c.closeEditor,
            onSaved: () {
              _c.closeEditor();
              unawaited(_c.reloadAll());
            },
          );
        }
        return BlogListView(controller: _c);
      },
    );
  }
}
