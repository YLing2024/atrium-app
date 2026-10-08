import 'package:flutter/material.dart';

import '../theme.dart';

/// 管理页区块标题：左侧标题 + 右侧动作，与首页其它页一致。
class ManageSectionHeader extends StatelessWidget {
  const ManageSectionHeader({
    super.key,
    required this.title,
    required this.action,
  });

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.fg,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const Spacer(),
        action,
      ],
    );
  }
}

/// 错误提示条。
Widget manageErrorBanner(AppColors c, String msg) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
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
            msg,
            style: TextStyle(color: c.danger, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

/// 空状态提示条。
Widget manageEmptyBanner(AppColors c, String text) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 32),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: c.surface,
      border: Border.all(color: c.border),
    ),
    child: Text(text, style: TextStyle(color: c.muted, fontSize: 13)),
  );
}

/// 保活状态行：可选状态点 + 值。
Widget manageStatusRow(AppColors c, String label, String value, {bool? dot}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
        const Spacer(),
        if (dot != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dot ? c.ok : c.danger,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(value, style: TextStyle(color: c.fg, fontSize: 12)),
      ],
    ),
  );
}

/// 窄屏卡片里的 `标签 值` 单行，超长省略。
Widget manageKvLine(AppColors c, String label, String value) {
  return RichText(
    text: TextSpan(
      style: TextStyle(color: c.muted, fontSize: 12),
      children: [
        TextSpan(text: '$label '),
        TextSpan(
          text: value,
          style: TextStyle(color: c.fg, fontSize: 12),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// 表格头：列标签，末列窄、其余均分，首列左对齐其余右对齐。
Widget manageTableHeader(AppColors c, List<String> cols) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: c.surface2,
      border: Border.all(color: c.border),
    ),
    child: Row(
      children: [
        for (final (i, label) in cols.indexed)
          Expanded(
            flex: i == cols.length - 1 ? 1 : 2,
            child: Text(
              label,
              textAlign: i == 0 ? TextAlign.left : TextAlign.right,
              style: TextStyle(
                color: c.muted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
      ],
    ),
  );
}
