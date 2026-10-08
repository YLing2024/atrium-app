import 'package:flutter/material.dart';

import '../theme.dart';

/// 工具选择项（当前只有一项，横向排列以便窄屏）。
class DebugToolChip extends StatelessWidget {
  const DebugToolChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
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
}

/// 面板内的小节标题。
Widget debugBlockTitle(AppColors c, String text) {
  return Text(
    text,
    style: TextStyle(
      color: c.fg,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    ),
  );
}

/// 表单字段标签。
Widget debugFieldLabel(AppColors c, String text) {
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

/// 等宽代码块（可选中）。
Widget debugCodeBox(AppColors c, String text, {required Color color}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: c.codeBg,
      border: Border.all(color: c.border),
    ),
    child: SelectableText(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontFamily: 'monospace',
        height: 1.5,
      ),
    ),
  );
}

InputDecoration debugInputDecoration(AppColors c) {
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
