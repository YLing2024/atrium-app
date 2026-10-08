import 'package:flutter/material.dart';

import '../theme.dart';

/// 通知页页头：标题 + 未读徽标 + 发通知开关 + 全部已读。
class NotificationsHeader extends StatelessWidget {
  const NotificationsHeader({
    super.key,
    required this.unread,
    required this.markingAll,
    required this.composeOpen,
    required this.onToggleCompose,
    required this.onReadAll,
  });

  final int unread;
  final bool markingAll;
  final bool composeOpen;
  final VoidCallback onToggleCompose;
  final VoidCallback onReadAll;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Text(
            '通知',
            style: TextStyle(
              color: c.fg,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.accentSoft,
                border: Border.all(color: c.accentBorder),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '未读 $unread',
                style: TextStyle(color: c.accent, fontSize: 11),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: onToggleCompose,
            child: Text(
              composeOpen ? '收起' : '发通知',
              style: TextStyle(color: c.accent, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: (unread == 0 || markingAll) ? null : onReadAll,
            child: Text(
              markingAll ? '处理中…' : '全部已读',
              style: TextStyle(color: c.accent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
