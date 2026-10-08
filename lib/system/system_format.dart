/// 系统监控页的纯格式化函数（无副作用、脱离 Flutter 可单测）。
///
/// 原为 `system_page.dart` 里的私有方法，语义与实现逐行保持不变。
library;

String fmtBytes(num? b) {
  if (b == null) return '—';
  final v = b.toDouble();
  if (v >= 1024 * 1024 * 1024 * 1024) {
    return '${(v / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
  }
  if (v >= 1024 * 1024 * 1024) {
    return '${(v / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (v >= 1024 * 1024) {
    return '${(v / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (v >= 1024) return '${(v / 1024).toStringAsFixed(1)} KB';
  return '${v.toStringAsFixed(1)} B';
}

String fmtMB(num? mb) {
  if (mb == null) return '—';
  final v = mb.toDouble();
  return v == v.roundToDouble() ? '${v.toInt()} MB' : '${v.toStringAsFixed(1)} MB';
}

String fmtRate(num? r) {
  if (r == null) return '—';
  return '${fmtBytes(r)}/s';
}

String fmtUptime(num? sec) {
  if (sec == null) return '刚刚';
  final s = sec.toInt();
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final parts = <String>[
    if (d > 0) '$d 天',
    if (h > 0) '$h 小时',
    if (m > 0) '$m 分钟',
  ];
  return parts.isEmpty ? '刚刚' : parts.join(' ');
}

String fmtLoad(dynamic load) {
  if (load is List) {
    return load
        .whereType<num>()
        .map((x) => x.toStringAsFixed(2))
        .join(' / ');
  }
  if (load is String) return load;
  return '—';
}

double pctOf(dynamic v) => v is num ? v.toDouble() : 0.0;

num numOr(dynamic v) => v is num ? v : 0;

String fmtClock(DateTime t) {
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(t.hour)}:${p2(t.minute)}:${p2(t.second)}';
}
