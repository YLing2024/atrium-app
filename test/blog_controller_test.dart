import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_admin/api.dart';
import 'package:home_admin/blog/blog_controller.dart';
import 'package:home_admin/blog/blog_format.dart';
import 'package:home_admin/blog/collection_editor_controller.dart';
import 'package:home_admin/blog/post_editor_controller.dart';

/// 无网络、无设备的假后端：记录调用并可控地完成 / 失败。
class _FakeBlogApi implements BlogApi {
  List<Map<String, dynamic>> postsResult = [];
  List<Map<String, dynamic>> collectionsResult = [];
  Object? postsError;
  Object? collectionsError;
  int postsCalls = 0;
  int collectionsCalls = 0;

  final List<int> deletedPosts = [];
  Object? deletePostError;
  final List<int> deletedCollections = [];
  Object? deleteCollectionError;

  final List<int> previewIds = [];
  Map<String, dynamic> previewResult = const {};
  Object? previewError;

  final List<Map<String, dynamic>> createdPosts = [];
  final List<String> updatedPosts = [];
  Object? createPostError;

  final List<Map<String, dynamic>> createdCollections = [];
  final List<String> updatedCollections = [];
  Object? createCollectionError;

  @override
  Future<List<Map<String, dynamic>>> posts() async {
    postsCalls += 1;
    if (postsError != null) throw postsError!;
    return postsResult;
  }

  @override
  Future<List<Map<String, dynamic>>> collections() async {
    collectionsCalls += 1;
    if (collectionsError != null) throw collectionsError!;
    return collectionsResult;
  }

  @override
  Future<void> deletePost(int id) async {
    deletedPosts.add(id);
    if (deletePostError != null) throw deletePostError!;
  }

  @override
  Future<void> deleteCollection(int id) async {
    deletedCollections.add(id);
    if (deleteCollectionError != null) throw deleteCollectionError!;
  }

  @override
  Future<Map<String, dynamic>> postPreviewLink(int id) async {
    previewIds.add(id);
    if (previewError != null) throw previewError!;
    return previewResult;
  }

  @override
  Future<void> createPost(Map<String, dynamic> body) async {
    createdPosts.add(body);
    if (createPostError != null) throw createPostError!;
  }

  @override
  Future<void> updatePost(int id, Map<String, dynamic> body) async {
    updatedPosts.add('$id|$body');
  }

  @override
  Future<void> createCollection(Map<String, dynamic> body) async {
    createdCollections.add(body);
    if (createCollectionError != null) throw createCollectionError!;
  }

  @override
  Future<void> updateCollection(int id, Map<String, dynamic> body) async {
    updatedCollections.add('$id|$body');
  }
}

/// 内存草稿存储：不触 SharedPreferences。
class _FakeDraftStore implements DraftStore {
  final Map<String, String> values = {};
  final List<String> writes = [];
  final List<String> removes = [];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    writes.add(key);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
    removes.add(key);
  }
}

BlogController _controller(
  _FakeBlogApi api, {
  Future<bool> Function(String title, String message)? confirm,
  Future<void> Function(String url)? openExternal,
  void Function(String msg)? onError,
  Future<bool> Function(Object e)? onAuthError,
}) =>
    BlogController(
      api: api,
      confirm: confirm,
      openExternal: openExternal,
      onError: onError,
      onAuthError: onAuthError,
    );

PostEditorController _editor({
  Map<String, dynamic>? post,
  List<Map<String, dynamic>> collections = const [],
  BlogApi? api,
  DraftStore? drafts,
  ImagePickerFn? pickImage,
  UploadImageFn? uploadImage,
  Future<bool> Function(Object e)? onAuthError,
  void Function()? onSaved,
}) =>
    PostEditorController(
      post: post,
      collections: collections,
      onSaved: onSaved ?? () {},
      api: api,
      drafts: drafts,
      pickImage: pickImage,
      uploadImage: uploadImage,
      onAuthError: onAuthError,
    );

void main() {
  group('纯逻辑：解析 / 校验 / 构造', () {
    test('parseItems：只保留 Map，忽略坏结构', () {
      expect(parseItems(null), isEmpty);
      expect(parseItems('x'), isEmpty);
      expect(parseItems([1, 'a', {'id': 1}, {'id': 2}]).map((m) => m['id']), [1, 2]);
    });

    test('parseTags：中英文逗号切分、去空白、丢空项', () {
      expect(parseTags(''), isEmpty);
      expect(parseTags(' a , b，c ,, '), ['a', 'b', 'c']);
    });

    test('校验：空 / 纯空白不通过', () {
      expect(validatePostTitle(''), '标题不能为空');
      expect(validatePostTitle('   '), '标题不能为空');
      expect(validatePostTitle(' 你好 '), isNull);
      expect(validateCollectionName(''), '合集名称不能为空');
      expect(validateCollectionName('  '), '合集名称不能为空');
      expect(validateCollectionName('随笔'), isNull);
    });

    test('buildPostBody / buildCollectionBody：字段与顺序', () {
      expect(
        buildPostBody(
          title: 'T',
          tags: ['a'],
          excerpt: 'E',
          content: 'C',
          published: true,
          collectionId: 3,
        ),
        {
          'title': 'T',
          'tags': ['a'],
          'excerpt': 'E',
          'content': 'C',
          'published': true,
          'collection_id': 3,
        },
      );
      expect(buildCollectionBody(name: 'N', description: 'D'), {
        'name': 'N',
        'description': 'D',
      });
    });

    test('draftKeyFor：新建用 new，编辑用数字 id', () {
      expect(draftKeyFor(isNew: true, id: null), 'blog_draft_new');
      expect(draftKeyFor(isNew: false, id: 7), 'blog_draft_7');
    });
  });

  group('BlogController：加载', () {
    test('初始状态：文章视图、加载中、列表为空', () {
      final c = _controller(_FakeBlogApi());
      expect(c.view, 'posts');
      expect(c.loading, isTrue);
      expect(c.posts, isEmpty);
      expect(c.collections, isEmpty);
      expect(c.error, isNull);
      expect(c.editing, isNull);
      c.dispose();
    });

    test('加载成功：写入文章与合集、结束加载、清错误', () async {
      final api = _FakeBlogApi()
        ..postsResult = [
          {'id': 1, 'title': 'A'},
        ]
        ..collectionsResult = [
          {'id': 2, 'name': 'C'},
        ];
      final c = _controller(api);
      await c.load();
      expect(c.posts.single['title'], 'A');
      expect(c.collections.single['name'], 'C');
      expect(c.loading, isFalse);
      expect(c.error, isNull);
      c.dispose();
    });

    test('合集加载失败不阻塞文章列表', () async {
      final api = _FakeBlogApi()
        ..postsResult = [
          {'id': 1, 'title': 'A'},
        ]
        ..collectionsError = Exception('合集挂了');
      final c = _controller(api);
      await c.load();
      expect(c.posts, hasLength(1));
      expect(c.collections, isEmpty);
      expect(c.loading, isFalse);
      expect(c.error, isNull);
      c.dispose();
    });

    test('加载失败：记录错误并结束加载', () async {
      final api = _FakeBlogApi()..postsError = Exception('读取失败');
      final c = _controller(api);
      await c.load();
      expect(c.error, 'Exception: 读取失败');
      expect(c.loading, isFalse);
      c.dispose();
    });

    test('鉴权失败且已处理：不记错误、保持加载态', () async {
      final api = _FakeBlogApi()..postsError = Exception('401');
      final c = _controller(api, onAuthError: (e) async => true);
      await c.load();
      expect(c.error, isNull);
      expect(c.loading, isTrue);
      c.dispose();
    });

    test('reloadAll：刷新列表、保留 loading 终态语义', () async {
      final api = _FakeBlogApi()..postsResult = [
        {'id': 1, 'title': 'A'},
      ];
      final c = _controller(api);
      await c.reloadAll();
      expect(c.posts, hasLength(1));
      expect(c.error, isNull);

      api.postsError = Exception('刷新失败');
      await c.reloadAll();
      expect(c.error, 'Exception: 刷新失败');
      c.dispose();
    });
  });

  group('BlogController：视图与编辑器路由', () {
    test('切 Tab 与新建入口按当前视图分流', () {
      final c = _controller(_FakeBlogApi());
      c.setView('collections');
      expect(c.view, 'collections');
      c.startCreate();
      expect(c.editingCollection, 'new');
      expect(c.editing, isNull);

      c.setView('posts');
      c.startCreate();
      expect(c.editing, 'new');
      c.dispose();
    });

    test('打开 / 关闭文章与合集编辑器', () {
      final c = _controller(_FakeBlogApi());
      final post = {'id': 1, 'title': 'A'};
      final col = {'id': 2, 'name': 'C'};
      c.openPostEditor(post);
      expect(c.editing, post);
      c.closeEditor();
      expect(c.editing, isNull);

      c.openCollectionEditor(col);
      expect(c.editingCollection, col);
      c.closeCollectionEditor();
      expect(c.editingCollection, isNull);
      c.dispose();
    });
  });

  group('BlogController：删除', () {
    test('删除文章：取消不发请求', () async {
      final api = _FakeBlogApi();
      final c = _controller(api, confirm: (t, m) async => false);
      await c.deletePost({'id': 5, 'title': 'A'});
      expect(api.deletedPosts, isEmpty);
      c.dispose();
    });

    test('删除文章：确认后删除并刷新', () async {
      final api = _FakeBlogApi()..postsResult = [
        {'id': 5, 'title': 'A'},
      ];
      final prompts = <String>[];
      final c = _controller(
        api,
        confirm: (t, m) async {
          prompts.add('$t|$m');
          return true;
        },
      );
      await c.deletePost({'id': 5, 'title': 'A'});
      expect(api.deletedPosts, [5]);
      expect(prompts.single, '删除文章|确定删除「A」？此操作不可恢复。');
      expect(api.postsCalls, 1, reason: '删除成功后 reloadAll 再取一次');
      c.dispose();
    });

    test('删除文章失败：提示错误', () async {
      final api = _FakeBlogApi()..deletePostError = Exception('删除失败');
      final toasts = <String>[];
      final c = _controller(
        api,
        confirm: (t, m) async => true,
        onError: toasts.add,
      );
      await c.deletePost({'id': 5, 'title': 'A'});
      expect(toasts, ['Exception: 删除失败']);
      c.dispose();
    });

    test('删除合集：两次确认，任一取消都不删除', () async {
      final api = _FakeBlogApi();
      final answers = <bool>[false];
      final prompts = <String>[];
      final c = _controller(
        api,
        confirm: (t, m) async {
          prompts.add('$t|$m');
          return answers.removeAt(0);
        },
      );
      await c.deleteCollection({'id': 9, 'name': 'C'});
      expect(api.deletedCollections, isEmpty);
      expect(prompts, hasLength(1), reason: '第一次取消不再弹第二次');

      answers.add(true);
      answers.add(false);
      await c.deleteCollection({'id': 9, 'name': 'C'});
      expect(api.deletedCollections, isEmpty);
      expect(prompts, hasLength(3));
      c.dispose();
    });

    test('删除合集：两次确认后删除并刷新', () async {
      final api = _FakeBlogApi();
      final prompts = <String>[];
      final c = _controller(
        api,
        confirm: (t, m) async {
          prompts.add('$t|$m');
          return true;
        },
      );
      await c.deleteCollection({'id': 9, 'name': 'C'});
      expect(api.deletedCollections, [9]);
      expect(prompts, [
        '删除合集|确定删除合集「C」？',
        '再次确认|再次确认：删除合集「C」将解除该合集下所有文章的关联，此操作不可恢复。',
      ]);
      c.dispose();
    });
  });

  group('BlogController：打开文章 / 合集', () {
    test('已发布且有 key：直接打开公开地址', () async {
      final opens = <String>[];
      final c = _controller(_FakeBlogApi(), openExternal: (u) async => opens.add(u));
      await c.openPost({'published': true, 'public_id': 'abc'});
      expect(opens, [Api.absoluteUrl('/blog/abc')]);
      c.dispose();
    });

    test('已发布但 key 为空：不打开', () async {
      final opens = <String>[];
      final c = _controller(_FakeBlogApi(), openExternal: (u) async => opens.add(u));
      await c.openPost({'published': true});
      expect(opens, isEmpty);
      c.dispose();
    });

    test('草稿：取预览链接再打开', () async {
      final api = _FakeBlogApi()..previewResult = {'url': '/blog/preview/xyz'};
      final opens = <String>[];
      final c = _controller(api, openExternal: (u) async => opens.add(u));
      await c.openPost({'published': false, 'id': 3});
      expect(api.previewIds, [3]);
      expect(opens, [Api.absoluteUrl('/blog/preview/xyz')]);
      c.dispose();
    });

    test('草稿 id 非 int / 链接为空：不打开', () async {
      final api = _FakeBlogApi()..previewResult = {'url': '  '};
      final opens = <String>[];
      final c = _controller(api, openExternal: (u) async => opens.add(u));
      await c.openPost({'published': false, 'id': '3'});
      await c.openPost({'published': false, 'id': 3});
      expect(api.previewIds, [3], reason: '非 int id 不请求预览链接');
      expect(opens, isEmpty);
      c.dispose();
    });

    test('打开失败：提示错误', () async {
      final api = _FakeBlogApi()..previewError = Exception('boom');
      final toasts = <String>[];
      final c = _controller(
        _FakeBlogApi(),
        onError: toasts.add,
      );
      await c.openPost({'published': false, 'id': 1});
      expect(toasts, isEmpty);
      c.dispose();

      final c2 = _controller(api, onError: toasts.add);
      await c2.openPost({'published': false, 'id': 1});
      expect(toasts, ['打开文章失败：Exception: boom']);
      c2.dispose();
    });

    test('合集：有 key 打开，无 key 不打开', () async {
      final opens = <String>[];
      final c = _controller(_FakeBlogApi(), openExternal: (u) async => opens.add(u));
      await c.openCollection({'public_id': 'c1'});
      await c.openCollection({'name': '无 key'});
      expect(opens, [Api.absoluteUrl('/blog/collections/c1')]);
      c.dispose();
    });
  });

  group('PostEditorController：初始化与草稿', () {
    test('编辑：从 post 初始化字段与草稿 key', () {
      final c = _editor(
        post: {
          'id': 7,
          'title': 'T',
          'tags': ['a', 'b'],
          'excerpt': 'E',
          'content': 'C',
          'collection': {'id': 9},
          'published': true,
        },
        drafts: _FakeDraftStore(),
      );
      expect(c.isNew, isFalse);
      expect(c.draftKey, 'blog_draft_7');
      expect(c.title.text, 'T');
      expect(c.tags.text, 'a, b');
      expect(c.excerpt.text, 'E');
      expect(c.content.text, 'C');
      expect(c.collectionId, 9);
      expect(c.published, isTrue);
      c.dispose();
    });

    test('新建：isNew 与默认草稿 key', () {
      final c = _editor(drafts: _FakeDraftStore());
      expect(c.isNew, isTrue);
      expect(c.draftKey, 'blog_draft_new');
      c.dispose();
    });

    test('恢复草稿：写回字段并提示', () async {
      final store = _FakeDraftStore()
        ..values['blog_draft_7'] = jsonEncode({
          'title': '草稿标题',
          'tags': 'x, y',
          'excerpt': '草稿摘要',
          'content': '草稿正文',
          'collection_id': 4,
          'published': true,
        });
      final c = _editor(post: {'id': 7}, drafts: store);
      await c.restoreDraft();
      expect(c.title.text, '草稿标题');
      expect(c.tags.text, 'x, y');
      expect(c.excerpt.text, '草稿摘要');
      expect(c.content.text, '草稿正文');
      expect(c.collectionId, 4);
      expect(c.published, isTrue);
      expect(c.notice, '已恢复未保存的草稿');
      c.dispose();
    });

    test('恢复草稿：用户已输入则不覆盖', () async {
      final store = _FakeDraftStore()
        ..values['blog_draft_new'] = jsonEncode({'title': '旧草稿'});
      final c = _editor(drafts: store);
      c.title.text = '新输入';
      c.markChanged();
      await c.restoreDraft();
      expect(c.title.text, '新输入');
      c.dispose();
    });

    test('恢复草稿：损坏 JSON 静默忽略', () async {
      final store = _FakeDraftStore()..values['blog_draft_new'] = '{not json';
      final c = _editor(drafts: store);
      await c.restoreDraft();
      expect(c.title.text, '');
      expect(c.notice, isNull);
      c.dispose();
    });

    test('saveDraft / clearDraft 使用同一 key', () async {
      final store = _FakeDraftStore();
      final c = _editor(drafts: store);
      c.title.text = 'A';
      c.tags.text = 'x';
      await c.saveDraft();
      expect(store.writes, ['blog_draft_new']);
      final saved = jsonDecode(store.values['blog_draft_new']!) as Map;
      expect(saved['title'], 'A');
      expect(saved['tags'], 'x');
      await c.clearDraft();
      expect(store.removes, ['blog_draft_new']);
      c.dispose();
    });
  });

  group('PostEditorController：提交', () {
    test('空标题：报错且不发请求', () async {
      final api = _FakeBlogApi();
      final c = _editor(api: api, drafts: _FakeDraftStore());
      await c.submit(false);
      expect(c.error, '标题不能为空');
      expect(api.createdPosts, isEmpty);
      expect(c.saving, isFalse);
      c.dispose();
    });

    test('新建：提交 createPost 并清草稿、回调 onSaved', () async {
      final api = _FakeBlogApi();
      final store = _FakeDraftStore();
      var saved = 0;
      final c = _editor(
        api: api,
        drafts: store,
        onSaved: () => saved++,
      );
      c.title.text = ' 标题 ';
      c.tags.text = 'a, b，c';
      c.excerpt.text = ' 摘要 ';
      c.content.text = '正文';
      await c.submit(true);
      expect(api.createdPosts.single, {
        'title': '标题',
        'tags': ['a', 'b', 'c'],
        'excerpt': '摘要',
        'content': '正文',
        'published': true,
        'collection_id': null,
      });
      expect(store.removes, ['blog_draft_new']);
      expect(saved, 1);
      expect(c.saving, isFalse);
      c.dispose();
    });

    test('编辑：提交 updatePost 并透传 id', () async {
      final api = _FakeBlogApi();
      final c = _editor(
        post: {'id': 7, 'title': '旧'},
        api: api,
        drafts: _FakeDraftStore(),
      );
      c.title.text = '新';
      await c.submit(false);
      expect(api.updatedPosts.single, startsWith('7|'));
      expect(api.createdPosts, isEmpty);
      c.dispose();
    });

    test('提交失败：记录错误并复位 saving', () async {
      final api = _FakeBlogApi()..createPostError = Exception('写入失败');
      final c = _editor(api: api, drafts: _FakeDraftStore());
      c.title.text = 'T';
      await c.submit(false);
      expect(c.error, 'Exception: 写入失败');
      expect(c.saving, isFalse);
      c.dispose();
    });
  });

  group('PostEditorController：插图与开关', () {
    test('插图：选图成功后追加 Markdown 并提示', () async {
      final c = _editor(
        drafts: _FakeDraftStore(),
        pickImage: () async => const PickedImage('/tmp/a.png', 'a.png'),
        uploadImage: (file, name) async => '/api/blog/uploads/a.png',
      );
      c.content.text = '';
      await c.insertImage();
      expect(c.content.text, '![](/api/blog/uploads/a.png)');
      expect(c.notice, '图片已插入');
      c.dispose();
    });

    test('插图：取消选择不插入', () async {
      var uploaded = 0;
      final c = _editor(
        drafts: _FakeDraftStore(),
        pickImage: () async => null,
        uploadImage: (file, name) async {
          uploaded++;
          return 'x';
        },
      );
      await c.insertImage();
      expect(uploaded, 0);
      expect(c.content.text, '');
      c.dispose();
    });

    test('插图：上传失败记录错误', () async {
      final c = _editor(
        drafts: _FakeDraftStore(),
        pickImage: () async => const PickedImage('/tmp/a.png', 'a.png'),
        uploadImage: (file, name) async => throw Exception('上传失败'),
      );
      await c.insertImage();
      expect(c.error, '图片上传失败: Exception: 上传失败');
      c.dispose();
    });

    test('预览 / 合集 / 发布开关', () {
      final c = _editor(drafts: _FakeDraftStore());
      expect(c.preview, isFalse);
      c.togglePreview();
      expect(c.preview, isTrue);
      c.setCollectionId(5);
      expect(c.collectionId, 5);
      c.setPublished(true);
      expect(c.published, isTrue);
      c.dispose();
    });
  });

  group('CollectionEditorController', () {
    test('空名称：报错且不发请求', () async {
      final api = _FakeBlogApi();
      final c = CollectionEditorController(collection: null, onSaved: () {}, api: api);
      await c.submit();
      expect(c.error, '合集名称不能为空');
      expect(api.createdCollections, isEmpty);
      c.dispose();
    });

    test('新建成功：提交并回调', () async {
      final api = _FakeBlogApi();
      var saved = 0;
      final c = CollectionEditorController(
        collection: null,
        onSaved: () => saved++,
        api: api,
      );
      c.name.text = ' 随笔 ';
      c.desc.text = ' 描述 ';
      await c.submit();
      expect(api.createdCollections.single, {'name': '随笔', 'description': '描述'});
      expect(saved, 1);
      expect(c.saving, isFalse);
      c.dispose();
    });

    test('编辑：提交 updateCollection 并透传 id', () async {
      final api = _FakeBlogApi();
      final c = CollectionEditorController(
        collection: {'id': 7, 'name': '旧'},
        onSaved: () {},
        api: api,
      );
      c.name.text = '新';
      await c.submit();
      expect(api.updatedCollections.single, startsWith('7|'));
      c.dispose();
    });

    test('提交失败：记录错误', () async {
      final api = _FakeBlogApi()..createCollectionError = Exception('写入失败');
      final c = CollectionEditorController(collection: null, onSaved: () {}, api: api);
      c.name.text = 'N';
      await c.submit();
      expect(c.error, 'Exception: 写入失败');
      expect(c.saving, isFalse);
      c.dispose();
    });
  });
}
