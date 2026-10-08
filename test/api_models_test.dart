import 'package:flutter_test/flutter_test.dart';

import 'package:home_admin/api.dart';

void main() {
  group('kApiBase', () {
    test('未注入 --dart-define 时回退到 example.com 占位域', () {
      expect(kApiBase, 'https://api.example.com');
    });
  });

  group('ApiException', () {
    test('message / toString 与字段默认值', () {
      final e = ApiException('接口错误');
      expect(e.message, '接口错误');
      expect(e.toString(), '接口错误');
      expect(e.code, isNull);
      expect(e.errorCode, isNull);
      expect(e.retryAfter, isNull);
    });

    test('isAuth 仅在 code == 401 时为真', () {
      expect(ApiException('x', code: 401).isAuth, isTrue);
      expect(ApiException('x', code: 403).isAuth, isFalse);
      expect(ApiException('x').isAuth, isFalse);
    });

    test('保留 errorCode 与 retryAfter', () {
      final e = ApiException(
        '锁定',
        code: 429,
        errorCode: 'totp_locked',
        retryAfter: 30,
      );
      expect(e.code, 429);
      expect(e.errorCode, 'totp_locked');
      expect(e.retryAfter, 30);
    });
  });

  group('ApiCallResult', () {
    test('ok 覆盖 2xx 边界', () {
      expect(const ApiCallResult(status: 200, body: '').ok, isTrue);
      expect(const ApiCallResult(status: 204, body: '').ok, isTrue);
      expect(const ApiCallResult(status: 299, body: '').ok, isTrue);
      expect(const ApiCallResult(status: 199, body: '').ok, isFalse);
      expect(const ApiCallResult(status: 300, body: '').ok, isFalse);
      expect(const ApiCallResult(status: 201, body: '').ok, isTrue);
    });

    test('json 解析对象；非对象 / 坏 JSON 返回 null', () {
      expect(
        const ApiCallResult(status: 200, body: '{"id": 7}').json,
        {'id': 7},
      );
      expect(const ApiCallResult(status: 200, body: '[1,2]').json, isNull);
      expect(const ApiCallResult(status: 200, body: 'not json').json, isNull);
      expect(const ApiCallResult(status: 500, body: '').json, isNull);
    });

    test('id 兼容 int / num / 数字字符串；其余为 null', () {
      expect(const ApiCallResult(status: 201, body: '{"id": 7}').id, 7);
      expect(const ApiCallResult(status: 201, body: '{"id": 7.0}').id, 7);
      expect(const ApiCallResult(status: 201, body: '{"id": "42"}').id, 42);
      expect(const ApiCallResult(status: 201, body: '{"id": "x"}').id, isNull);
      expect(const ApiCallResult(status: 201, body: '{"ts": 1}').id, isNull);
      expect(const ApiCallResult(status: 201, body: '').id, isNull);
    });
  });

  group('SystemMetrics', () {
    test('empty 为无点无 meta 的常量', () {
      expect(SystemMetrics.empty.points, isEmpty);
      expect(SystemMetrics.empty.meta, isEmpty);
      expect(SystemMetrics.empty.recordedSeconds, isNull);
    });

    test('points 元素保留原始键值', () {
      final m = SystemMetrics.fromJson({
        'points': [
          {'ts': 1, 'cpu': 2.5},
        ],
      });
      expect(m.points.single, {'ts': 1, 'cpu': 2.5});
    });

    test('recordedSeconds：整数 / 小数取整 / 缺失 / 非数字', () {
      expect(
        SystemMetrics.fromJson(const {
          'meta': {'recordedSeconds': 3600},
        }).recordedSeconds,
        3600,
      );
      expect(
        SystemMetrics.fromJson(const {
          'meta': {'recordedSeconds': 3600.9},
        }).recordedSeconds,
        3600,
      );
      expect(
        SystemMetrics.fromJson(const {'meta': {}}).recordedSeconds,
        isNull,
      );
      expect(
        SystemMetrics.fromJson(const {
          'meta': {'recordedSeconds': 'x'},
        }).recordedSeconds,
        isNull,
      );
    });

    test('meta 非对象按空处理', () {
      expect(SystemMetrics.fromJson(const {'meta': 1}).meta, isEmpty);
    });
  });

  group('Api 纯地址与请求头', () {
    test('webviewHeaders 无登录态时为空', () {
      expect(Api.webviewHeaders(), isEmpty);
    });

    test('absoluteUrl 空串 / 纯空白返回自身（去空白后）', () {
      expect(Api.absoluteUrl(''), '');
      expect(Api.absoluteUrl('   '), '');
    });

    test('absoluteUrl 保留已带 scheme 的地址', () {
      expect(
        Api.absoluteUrl('https://cdn.example.com/a.png'),
        'https://cdn.example.com/a.png',
      );
      expect(Api.absoluteUrl('data:image/png;base64,AA'), 'data:image/png;base64,AA');
    });

    test('absoluteUrl 拼接相对路径（前导斜杠与裸相对名）', () {
      expect(Api.absoluteUrl('/blog/x'), '$kApiBase/blog/x');
      expect(Api.absoluteUrl('blog/x'), '$kApiBase/blog/x');
      expect(Api.absoluteUrl(' /blog/x '), '$kApiBase/blog/x');
    });

    test('fileDownloadUrl 使用 /api/admin/files/download 且 path 编码', () {
      final url = Api.fileDownloadUrl('/a b/c');
      expect(url, startsWith('$kApiBase/api/admin/files/download?path='));
      expect(url, contains(Uri.encodeQueryComponent('/a b/c')));
    });

    test('termUrl 依次携带会话名与票据（--url-arg 顺序）', () {
      final url = Api.termUrl('main', 'ticket-1');
      expect(url, startsWith('$kApiBase/term/?arg='));
      expect(url, contains(Uri.encodeQueryComponent('main')));
      expect(url, contains(Uri.encodeQueryComponent('ticket-1')));
    });
  });
}
