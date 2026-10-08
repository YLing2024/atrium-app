import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/* ============ 临时链接：预设 / 文案 / 状态色（创建与管理共用） ============ */

/// 预设有效期：hours 为 0 表示永久，为 null 表示自定义时刻
const List<({String key, String label, int? hours})> kSharePresets = [
  (key: '1h', label: '1 小时', hours: 1),
  (key: '24h', label: '24 小时', hours: 24),
  (key: '7d', label: '7 天', hours: 168),
  (key: '30d', label: '30 天', hours: 720),
  (key: 'forever', label: '永久', hours: 0),
  (key: 'custom', label: '自定义', hours: null),
];

String _pad2(int n) => n.toString().padLeft(2, '0');

String shareFmtTime(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${_pad2(d.month)}-${_pad2(d.day)} '
      '${_pad2(d.hour)}:${_pad2(d.minute)}';
}

/// 毫秒时长 → 「x 天 x 小时 / x 小时 x 分 / x 分」
String humanDuration(int ms) {
  final min = ms ~/ 60000;
  final days = min ~/ 1440;
  final hours = (min % 1440) ~/ 60;
  final mins = min % 60;
  if (days > 0) return '$days 天 $hours 小时';
  if (hours > 0) return '$hours 小时 $mins 分';
  return '${mins < 1 ? 1 : mins} 分';
}

int? shareExpiresMs(Map<String, dynamic> s) {
  final e = s['expiresAt'];
  return e is num ? e.toInt() : null;
}

bool isPermanentShare(Map<String, dynamic> s) {
  final e = shareExpiresMs(s);
  return e != null && e == 0;
}

String shareIdOf(Map<String, dynamic> s) => (s['id'] ?? '').toString();

String shareDisplayName(Map<String, dynamic> s) {
  final rel = (s['relPath'] ?? '').toString();
  if (rel.isEmpty) return shareIdOf(s);
  final i = rel.lastIndexOf('/');
  return i < 0 ? rel : rel.substring(i + 1);
}

/// 列表里的有效期文案：永久 / 剩余 x / 已过期 / 已撤销
String shareExpiryText(Map<String, dynamic> s) {
  if ((s['status'] ?? '').toString() == 'revoked') return '已撤销';
  if (isPermanentShare(s)) return '永久';
  final remaining = s['remainingMs'];
  if (remaining is num && remaining > 0) {
    return '剩余 ${humanDuration(remaining.toInt())}';
  }
  return '已过期';
}

({String text, Color color}) shareStatusMeta(AppColors c, String status) {
  switch (status) {
    case 'active':
      return (text: '有效', color: c.ok);
    case 'expired':
      return (text: '已过期', color: c.warn);
    case 'revoked':
      return (text: '已撤销', color: c.danger);
    default:
      return (text: status.isEmpty ? '未知' : status, color: c.muted);
  }
}

String shareMsgOf(Object e) => e is ApiException ? e.message : e.toString();

/// 二次确认弹窗；确认返回 true，取消 / 关闭返回 false
Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String message,
  String confirmLabel,
) async {
  final c = context.c;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: c.border),
      ),
      title: Text(
        title,
        style: TextStyle(color: c.fg, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      content: Text(
        message,
        style: TextStyle(color: c.muted, fontSize: 13, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('取消', style: TextStyle(color: c.muted, fontSize: 13)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: c.bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Text(confirmLabel, style: const TextStyle(fontSize: 13)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 弹窗外框：直角、发丝线、暖纸白 / 墨黑；窄屏不横向滚动
Widget shareDialogFrame(AppColors c, List<Widget> children) {
  return Dialog(
    backgroundColor: c.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: c.border),
    ),
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

Widget shareFieldLabel(AppColors c, String text) => Text(
      text,
      style: TextStyle(color: c.muted, fontSize: 11, letterSpacing: 1.2),
    );

Widget shareChip(
  AppColors c, {
  required String label,
  required bool selected,
  required VoidCallback? onTap,
}) {
  return ChoiceChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: onTap == null ? null : (_) => onTap(),
    labelStyle: TextStyle(
      fontSize: 12,
      color: selected ? c.accent : c.fg,
    ),
    selectedColor: c.accentSoft,
    backgroundColor: c.surface2,
    side: BorderSide(color: selected ? c.accentBorder : c.border),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
  );
}

/// 日期 + 时间选择（分钟精度）；返回本地时间，取消返回 null
Future<DateTime?> pickShareMoment(
  BuildContext context, {
  required DateTime initial,
}) async {
  final now = DateTime.now();
  final base = initial.isBefore(now) ? now : initial;
  final date = await showDatePicker(
    context: context,
    initialDate: base,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 10),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(base),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
