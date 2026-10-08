import 'package:flutter/material.dart';

import '../debug_tools.dart';
import '../theme.dart';
import 'debug_common.dart';

/// 「接口说明」：接口地址、字段表、可复制的请求体示例、鉴权说明。
class DebugApiSection extends StatelessWidget {
  const DebugApiSection({
    super.key,
    required this.copied,
    required this.onCopy,
  });

  /// 是否刚复制过（1.5s 内显示「已复制」）。
  final bool copied;

  final VoidCallback onCopy;

  static const List<(String, String, String)> _fields = [
    ('level', '是', 'urgent / normal / digest'),
    ('source', '是', '来源标识，调试固定 $kDebugNotificationSource'),
    ('title', '是', '标题，≤ 80 字'),
    ('body', '否', '正文，纯文本'),
    ('link', '否', '跳转链接'),
    ('dedupKey', '否', '去重键，10 分钟内相同键只保留一条'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            debugBlockTitle(c, '接口说明'),
            const Spacer(),
            TextButton.icon(
              onPressed: onCopy,
              icon: Icon(
                copied ? Icons.check : Icons.copy,
                size: 16,
                color: c.accent,
              ),
              label: Text(
                copied ? '已复制' : '复制',
                style: TextStyle(color: c.accent, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        debugCodeBox(
          c,
          'POST ${notificationEndpoint()}',
          color: c.accent,
        ),
        const SizedBox(height: 12),
        _fieldTable(c),
        const SizedBox(height: 14),
        debugFieldLabel(c, '请求体示例'),
        const SizedBox(height: 6),
        debugCodeBox(c, notificationExampleJson(), color: c.fg),
        const SizedBox(height: 8),
        Text(
          '鉴权：登录会话，或可在「管理」页生成的可写接口令牌。',
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _fieldTable(AppColors c) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: c.border)),
      child: Column(
        children: [
          for (final (i, f) in _fields.indexed) ...[
            if (i > 0) Container(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(
                      f.$1,
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text(
                      f.$2,
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      f.$3,
                      style: TextStyle(color: c.fg, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
