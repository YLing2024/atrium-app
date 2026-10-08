import 'package:flutter/material.dart';

import '../debug_tools.dart';
import '../theme.dart';
import 'debug_common.dart';

/// 「发一条测试通知」表单：级别 / 标题 / 正文 + 发送按钮。
class DebugSendForm extends StatelessWidget {
  const DebugSendForm({
    super.key,
    required this.title,
    required this.body,
    required this.level,
    required this.sending,
    required this.onLevelChanged,
    required this.onSend,
  });

  /// 标题输入控制器。
  final TextEditingController title;

  /// 正文输入控制器。
  final TextEditingController body;

  /// 当前通知级别（value 与后端一一对应）。
  final String level;

  /// 发送中：禁用输入与按钮。
  final bool sending;

  final ValueChanged<String> onLevelChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        debugFieldLabel(c, '级别'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: level,
          isExpanded: true,
          dropdownColor: c.surface,
          style: TextStyle(color: c.fg, fontSize: 13),
          decoration: debugInputDecoration(c),
          items: [
            for (final l in kDebugNotificationLevels)
              DropdownMenuItem(value: l.value, child: Text(l.label)),
          ],
          onChanged: sending ? null : (v) => onLevelChanged(v ?? 'normal'),
        ),
        const SizedBox(height: 12),
        debugFieldLabel(c, '标题'),
        const SizedBox(height: 6),
        TextField(
          controller: title,
          maxLength: 80,
          enabled: !sending,
          style: TextStyle(color: c.fg, fontSize: 13),
          decoration: debugInputDecoration(c).copyWith(
            counterText: '',
            hintText: '标题，≤ 80 字',
            hintStyle: TextStyle(color: c.muted, fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        debugFieldLabel(c, '正文'),
        const SizedBox(height: 6),
        TextField(
          controller: body,
          maxLines: 3,
          enabled: !sending,
          style: TextStyle(color: c.fg, fontSize: 13),
          decoration: debugInputDecoration(c).copyWith(
            hintText: '纯文本，可留空',
            hintStyle: TextStyle(color: c.muted, fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '来源固定为 $kDebugNotificationSource',
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: sending ? null : onSend,
            child: Text(sending ? '发送中…' : '发送测试通知'),
          ),
        ),
      ],
    );
  }
}
