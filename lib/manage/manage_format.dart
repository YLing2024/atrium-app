// 管理页纯格式化与校验：无 UI、无 IO，可直接单测。
//
// 时间入参统一为毫秒时间戳（令牌有效期由秒换算后再传入）；`now` 可注入，
// 便于对相对时间做确定性断言，生产默认取当前时刻。

String _p2(int n) => n.toString().padLeft(2, '0');

/// 毫秒时间戳 → `yyyy-MM-dd HH:mm`；未知（null / 0）返回破折号。
String fmtTime(num? ms) {
  if (ms == null || ms == 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  return '${d.year}-${_p2(d.month)}-${_p2(d.day)} ${_p2(d.hour)}:${_p2(d.minute)}';
}

/// 毫秒时间戳 → `yyyy-MM-dd`；未知（null / 0）返回破折号。
String fmtDate(num? ms) {
  if (ms == null || ms == 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  return '${d.year}-${_p2(d.month)}-${_p2(d.day)}';
}

/// 相对当前时刻：刚刚 / N 分钟前 / N 小时前 / N 天前；未知返回破折号。
String relativeTime(num? ms, {DateTime? now}) {
  if (ms == null || ms == 0) return '—';
  final base = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final diff = base - ms.toInt();
  if (diff < 60 * 1000) return '刚刚';
  if (diff < 3600 * 1000) return '${diff ~/ 60000} 分钟前';
  if (diff < 86400 * 1000) return '${diff ~/ 3600000} 小时前';
  return '${diff ~/ 86400000} 天前';
}

/// 距过期剩余天数；已过期 / 未知返回 0。
int remainingDays(num? expiresAt, {DateTime? now}) {
  if (expiresAt == null || expiresAt == 0) return 0;
  final base = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final diff = expiresAt.toInt() - base;
  return diff <= 0 ? 0 : diff ~/ 86400000;
}

/// 令牌名称非空校验；通过返回 null。
String? validateTokenName(String raw) =>
    raw.trim().isEmpty ? '令牌名称不能为空' : null;

/// 有效期天数解析：合法（1~365 的整数）返回天数，非法返回 null。
int? parseExpiryDays(String raw) {
  final n = int.tryParse(raw.trim());
  if (n == null || n < 1 || n > 365) return null;
  return n;
}
