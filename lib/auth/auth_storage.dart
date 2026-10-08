part of '../auth.dart';

const FlutterSecureStorage _storage = FlutterSecureStorage();

const String _kAccess = 'oauth.access_token';
const String _kRefresh = 'oauth.refresh_token';
const String _kId = 'oauth.id_token';
const String _kExpiry = 'oauth.expires_at';

// builtin（自带动态码）令牌独立 key：与 oauth 并存也不会互相串味。
const String _kBuiltinAccess = 'builtin.access_token';
const String _kBuiltinIssuedAt = 'builtin.issued_at';

AuthTokens? _tokens;
Future<bool>? _refreshing;

void _markStorageUnavailable(Object e) {
  if (Auth.storageAvailable.value) {
    debugPrint('安全存储不可用，本次会话改用内存态（不持久保存）: $e');
  }
  Auth.storageAvailable.value = false;
}

/* ============ 存储 ============ */

Future<AuthTokens?> _read() async {
  try {
    return await _readFromStorage().timeout(kStorageTimeout);
  } catch (e) {
    // 安全存储不可用（如 KeyStore 异常、超时）时按未登录处理，不抛给调用方
    _markStorageUnavailable(e);
    return null;
  }
}

Future<AuthTokens?> _readFromStorage() async {
  final access = await _storage.read(key: _kAccess) ?? '';
  final refresh = await _storage.read(key: _kRefresh);
  if (access.isEmpty && (refresh == null || refresh.isEmpty)) {
    return _readBuiltinFromStorage();
  }
  final id = await _storage.read(key: _kId);
  final expRaw = await _storage.read(key: _kExpiry);
  final expMs = expRaw == null ? null : int.tryParse(expRaw);
  return AuthTokens(
    accessToken: access,
    refreshToken: refresh,
    idToken: id,
    expiresAt: expMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expMs),
  );
}

/// builtin 令牌：由签发时间 + [kBuiltinTokenTtl] 换算过期时刻（无 refresh）。
Future<AuthTokens?> _readBuiltinFromStorage() async {
  final token = await _storage.read(key: _kBuiltinAccess) ?? '';
  if (token.isEmpty) return null;
  final issuedRaw = await _storage.read(key: _kBuiltinIssuedAt);
  final issuedMs = issuedRaw == null ? null : int.tryParse(issuedRaw);
  return AuthTokens(
    accessToken: token,
    builtin: true,
    expiresAt: issuedMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(issuedMs).add(kBuiltinTokenTtl),
  );
}

/// 先落内存，再尽力写安全存储：写入失败/超时只标记「不持久保存」，不抛出，
/// 保证本次会话（登录、API）仍可用。
Future<void> _persist(AuthTokens t) async {
  _tokens = t;
  try {
    await _writeToStorage(t).timeout(kStorageTimeout);
  } catch (e) {
    _markStorageUnavailable(e);
  }
}

/// builtin 登录成功：记签发时间，12h 后本地判定过期（不做 refresh）。
Future<void> _persistBuiltin(String token) async {
  final issuedAt = DateTime.now();
  _tokens = AuthTokens(
    accessToken: token,
    builtin: true,
    expiresAt: issuedAt.add(kBuiltinTokenTtl),
  );
  try {
    await _writeBuiltinToStorage(token, issuedAt).timeout(kStorageTimeout);
  } catch (e) {
    _markStorageUnavailable(e);
  }
}

Future<void> _writeToStorage(AuthTokens t) async {
  await _storage.write(key: _kAccess, value: t.accessToken);
  final exp = t.expiresAt;
  if (exp == null) {
    await _storage.delete(key: _kExpiry);
  } else {
    await _storage.write(
      key: _kExpiry,
      value: exp.millisecondsSinceEpoch.toString(),
    );
  }
  await _writeOrDelete(_kRefresh, t.refreshToken);
  await _writeOrDelete(_kId, t.idToken);
  // 切到 sso 后清掉 builtin 残留，避免下次启动读串
  await _storage.delete(key: _kBuiltinAccess);
  await _storage.delete(key: _kBuiltinIssuedAt);
}

Future<void> _writeBuiltinToStorage(
  String token,
  DateTime issuedAt,
) async {
  await _storage.write(key: _kBuiltinAccess, value: token);
  await _storage.write(
    key: _kBuiltinIssuedAt,
    value: issuedAt.millisecondsSinceEpoch.toString(),
  );
  // 切到 builtin 后清掉 oauth 残留
  await _storage.delete(key: _kAccess);
  await _storage.delete(key: _kRefresh);
  await _storage.delete(key: _kId);
  await _storage.delete(key: _kExpiry);
}

Future<void> _writeOrDelete(String key, String? value) async {
  if (value == null || value.isEmpty) {
    await _storage.delete(key: key);
  } else {
    await _storage.write(key: key, value: value);
  }
}
