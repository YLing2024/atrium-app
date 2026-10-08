/// 博客管理页的纯逻辑（无副作用、脱离 Flutter 可单测）。
///
/// 原为 `blog_page.dart` 里的内联实现，语义与实现逐行保持不变。
library;

/// 把接口返回的原始列表规整为 `Map<String, dynamic>` 列表，丢弃坏结构。
List<Map<String, dynamic>> parseItems(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}

/// 标签输入：按中英文逗号切分、去空白、丢弃空项。
List<String> parseTags(String raw) => raw
    .split(RegExp(r'[,，]'))
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toList();

/// 标题校验：空 / 纯空白不通过。返回错误文案，通过返回 null。
String? validatePostTitle(String raw) =>
    raw.trim().isEmpty ? '标题不能为空' : null;

/// 合集名称校验：空 / 纯空白不通过。
String? validateCollectionName(String raw) =>
    raw.trim().isEmpty ? '合集名称不能为空' : null;

/// 文章提交体（新建 / 更新共用）。
Map<String, dynamic> buildPostBody({
  required String title,
  required List<String> tags,
  required String excerpt,
  required String content,
  required bool published,
  required int? collectionId,
}) =>
    {
      'title': title,
      'tags': tags,
      'excerpt': excerpt,
      'content': content,
      'published': published,
      'collection_id': collectionId,
    };

/// 合集提交体（新建 / 更新共用）。
Map<String, dynamic> buildCollectionBody({
  required String name,
  required String description,
}) =>
    {'name': name, 'description': description};

/// 草稿本地存储 key：新建用 `blog_draft_new`，编辑用文章数字 id。
String draftKeyFor({required bool isNew, Object? id}) =>
    'blog_draft_${isNew ? 'new' : id}';
