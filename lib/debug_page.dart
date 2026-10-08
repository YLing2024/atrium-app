import 'package:flutter/material.dart';

import 'debug/debug_common.dart';
import 'debug/notification_debug_panel.dart';
import 'theme.dart';

export 'debug/notification_debug_panel.dart' show NotificationDebugPanel;

/// 调试页：工具容器（工具列表 + 工具面板）。
///
/// 当前只有一项工具「通知调试」；其余留空，不造占位工具（对齐 Web 端 Debug.jsx）。
class DebugPage extends StatefulWidget {
  const DebugPage({super.key, this.active = true});

  /// 是否为当前可见 Tab；仅可见时刷新状态并驱动相对时间重绘。
  final bool active;

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  static const List<String> _tools = ['通知调试'];
  int _tool = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              const Spacer(),
              Text(
                '调试',
                style: TextStyle(
                  color: c.fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              for (var i = 0; i < _tools.length; i++)
                DebugToolChip(
                  label: _tools[i],
                  selected: i == _tool,
                  onTap: () => setState(() => _tool = i),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: IndexedStack(
            index: _tool,
            children: [
              NotificationDebugPanel(active: widget.active),
            ],
          ),
        ),
      ],
    );
  }
}
