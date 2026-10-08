part of '../auth.dart';

/* ============ 登录（PKCE） ============ */

/// 走完整的 PKCE 登录：系统浏览器 → 回环回调 → 换令牌 → 存安全存储。
/// 失败抛 [AuthException]（state 不一致 / 用户取消 / 超时 / 换令牌失败）。
Future<void> _pkceLogin() async {
  final verifier = generateCodeVerifier();
  final challenge = codeChallengeS256(verifier);
  final state = generateState();

  HttpServer server;
  try {
    server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      kLoopbackPort,
    );
  } on SocketException catch (e) {
    throw AuthException('无法监听本地回调端口 $kLoopbackPort：${e.message}');
  }

  try {
    final authorizeUri = Uri.parse('$kAuthBase/authorize').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': kOAuthClientId,
        'redirect_uri': kRedirectUri,
        'scope': kOAuthScope,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    );
    final code = await _awaitCallback(server, state, authorizeUri);
    await _exchangeCode(code, verifier);
  } finally {
    await server.close(force: true);
  }
}

/// 在临时 server 上等待回调：校验 state → 取 code；错误写回浏览器页面。
Future<String> _awaitCallback(
  HttpServer server,
  String expectedState,
  Uri authorizeUri,
) async {
  final completer = Completer<String>();
  late StreamSubscription<HttpRequest> sub;

  sub = server.listen((req) async {
    if (req.uri.path != '/callback') {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final q = req.uri.queryParameters;
    String? code;
    String? error;
    if (!verifyState(expectedState, q['state'])) {
      // state 不一致：可能是 CSRF / 授权码注入，直接拒绝
      error = 'state 校验失败，请重试';
    } else if ((q['error'] ?? '').isNotEmpty) {
      final desc = q['error_description'];
      error =
          '登录被拒绝：${q['error']}${desc == null || desc.isEmpty ? '' : '（$desc）'}';
    } else if ((q['code'] ?? '').isEmpty) {
      error = '回调缺少授权码';
    } else {
      code = q['code'];
    }
    await _writeCallbackPage(req.response, ok: error == null);
    if (!completer.isCompleted) {
      if (error != null) {
        completer.completeError(AuthException(error));
      } else {
        completer.complete(code);
      }
    }
  });

  try {
    final launched = await launchUrl(
      authorizeUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) throw const AuthException('无法打开系统浏览器，请检查默认浏览器设置');
    return await completer.future.timeout(
      _kLoginTimeout,
      onTimeout: () => throw const AuthException('登录超时，请重试'),
    );
  } finally {
    await sub.cancel();
  }
}

/// 用授权码换令牌（不带 client_secret）。
Future<void> _exchangeCode(String code, String verifier) async {
  final data = await _postForm(Uri.parse('$kAuthBase/token'), {
    'grant_type': 'authorization_code',
    'code': code,
    'redirect_uri': kRedirectUri,
    'client_id': kOAuthClientId,
    'code_verifier': verifier,
  });
  final access = data['access_token'];
  if (access is! String || access.isEmpty) {
    throw const AuthException('换取令牌失败：未返回 access_token');
  }
  final tokens = AuthTokens(
    accessToken: access,
    refreshToken: data['refresh_token'] as String?,
    idToken: data['id_token'] as String?,
    expiresAt: _expiryOf(data['expires_in']),
  );
  await _persist(tokens);
}

/// 回调页：纯静态、无外部资源，读完即可关闭。
Future<void> _writeCallbackPage(
  HttpResponse res, {
  required bool ok,
}) async {
  res.statusCode = ok ? HttpStatus.ok : HttpStatus.badRequest;
  res.headers.contentType = ContentType.html;
  final title = ok ? '登录完成' : '登录失败';
  final body = ok ? '登录完成，可以关闭此页回到 App。' : '登录未完成，请回到 App 重试。';
  res.write(
    '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<title>$title</title></head>'
    '<body style="font-family:sans-serif;text-align:center;padding:80px 24px;color:#171512">'
    '<p style="font-size:16px">$body</p></body></html>',
  );
  await res.close();
}
