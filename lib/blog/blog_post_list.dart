import 'package:flutter/material.dart';

import '../theme.dart';
import 'blog_controller.dart';

/// 博客列表视图：标题栏 + 文章 / 合集双 Tab + 列表 / 加载态 / 错误态。
class BlogListView extends StatelessWidget {
  const BlogListView({super.key, required this.controller});

  final BlogController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final error = controller.error;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '博客管理',
                    style: TextStyle(
                      color: c.fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _tabBtn(c, '文章', 'posts'),
                      const SizedBox(width: 18),
                      _tabBtn(c, '合集', 'collections'),
                    ],
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: controller.loading ? null : controller.startCreate,
              child: Text(controller.view == 'posts' ? '＋ 新建文章' : '＋ 新建合集'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: c.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: TextStyle(color: c.danger, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (controller.loading)
          const Padding(
            padding: EdgeInsets.only(top: 100),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (controller.view == 'posts')
          _postsList(c)
        else
          _collectionsList(c),
      ],
    );
  }

  Widget _tabBtn(AppColors c, String label, String view) {
    final active = controller.view == view;
    return InkWell(
      onTap: () => controller.setView(view),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? c.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? c.accent : c.muted,
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  /* ============ 文章列表 ============ */

  Widget _postsList(AppColors c) {
    if (controller.posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(
          child: Text(
            '暂无文章，点击右上角「新建文章」开始创作',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final p in controller.posts) _postRow(c, p),
      ],
    );
  }

  Widget _postRow(AppColors c, Map<String, dynamic> p) {
    final title = (p['title'] ?? '-').toString();
    final published = p['published'] == true;
    final tags = p['tags'] is List ? p['tags'] as List : const [];
    final updated = (p['updated_at'] ?? p['created_at'] ?? '').toString();
    final collection = p['collection'] is Map
        ? (p['collection'] as Map)['name']?.toString()
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => controller.openPost(p),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: c.accentBorder,
                          ),
                        ),
                      ),
                      if (collection != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(color: c.accentBorder),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '合集：$collection',
                            style: TextStyle(color: c.accent, fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: published ? c.ok : c.border,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    published ? '已发布' : '草稿',
                    style: TextStyle(
                      color: published ? c.ok : c.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (tags.isNotEmpty) ...[
              // 不换行，超宽时横向滚动（对齐 Web blog-tags: flex-wrap: nowrap）
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: tags
                      .whereType<String>()
                      .map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              border: Border.all(color: c.border),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              t,
                              style: TextStyle(color: c.muted, fontSize: 11),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    updated,
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
                ),
                _linkBtn(c, '编辑', () => controller.openPostEditor(p)),
                const SizedBox(width: 14),
                _linkBtn(c, '删除', () => controller.deletePost(p), danger: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /* ============ 合集列表 ============ */

  Widget _collectionsList(AppColors c) {
    if (controller.collections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(
          child: Text(
            '暂无合集，点击右上角「新建合集」开始创建',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final col in controller.collections) _collectionRow(c, col),
      ],
    );
  }

  Widget _collectionRow(AppColors c, Map<String, dynamic> col) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => controller.openCollection(col),
            child: Text(
              (col['name'] ?? '-').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.fg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: c.accentBorder,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (col['description'] ?? '—').toString(),
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${col['post_count'] ?? 0} 篇文章',
                  style: TextStyle(color: c.muted, fontSize: 11),
                ),
              ),
              _linkBtn(c, '编辑', () => controller.openCollectionEditor(col)),
              const SizedBox(width: 14),
              _linkBtn(c, '删除', () => controller.deleteCollection(col), danger: true),
            ],
          ),
        ],
      ),
    );
  }

  /* ============ 通用 ============ */

  Widget _linkBtn(AppColors c, String label, VoidCallback onTap, {bool danger = false}) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: danger ? c.danger : c.accent,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
