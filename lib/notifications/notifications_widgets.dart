import 'package:flutter/material.dart';

import '../theme.dart';

/// 筛选分段按钮（全部 / 未读）。
Widget notificationsSegment(
  AppColors c,
  String label,
  bool selected,
  VoidCallback onTap,
) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? c.accentSoft : Colors.transparent,
        border: Border.all(color: selected ? c.accentBorder : c.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? c.accent : c.muted,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ),
  );
}

/// 筛选下拉（级别 / 来源）。
Widget notificationsDropdown(
  AppColors c, {
  required String value,
  required List<(String, String)> items,
  required ValueChanged<String> onChanged,
  double width = 120,
}) {
  return Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      border: Border.all(color: c.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        isDense: true,
        dropdownColor: c.surface,
        style: TextStyle(color: c.fg, fontSize: 13),
        icon: Icon(Icons.arrow_drop_down, size: 18, color: c.muted),
        items: [
          for (final (v, label) in items)
            DropdownMenuItem(
              value: v,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => onChanged(v ?? ''),
      ),
    ),
  );
}

/// 内联提示条（发通知失败等）。
Widget notificationsBanner(AppColors c, String msg, {required bool ok}) {
  final color = ok ? c.ok : c.danger;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: c.surface,
      border: Border.all(color: c.border),
    ),
    child: Text(msg, style: TextStyle(color: color, fontSize: 13)),
  );
}

/// 表单字段标签。
Widget notificationsFieldLabel(AppColors c, String text) {
  return Text(
    text,
    style: TextStyle(
      color: c.muted,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
  );
}

/// 表单输入框装饰。
InputDecoration notificationsInputDecoration(AppColors c) {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: c.surface2,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: OutlineInputBorder(
      borderSide: BorderSide(color: c.border),
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

/// 列表错误条（带「重试」）。
Widget notificationsErrorBanner(
  AppColors c,
  String msg, {
  required VoidCallback onRetry,
}) {
  return Container(
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
          child: Text(msg, style: TextStyle(color: c.danger, fontSize: 13)),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text('重试', style: TextStyle(color: c.accent, fontSize: 13)),
        ),
      ],
    ),
  );
}
