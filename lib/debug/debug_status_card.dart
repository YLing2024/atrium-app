import 'package:flutter/material.dart';

import '../debug_tools.dart';
import '../notification_model.dart';
import '../notification_store.dart';
import '../theme.dart';

/// 「实时状态」卡片：前台服务 / SSE 连接 / 最近事件 / 未读通知。
///
/// 状态来自 [NotificationStore]（notification_service.dart 的同源状态），
/// 不另起 SSE 连接；[now] 为当前 epoch 秒，仅用于相对时间与心跳判定。
class DebugStatusCard extends StatelessWidget {
  const DebugStatusCard({super.key, required this.now});

  final int now;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: NotificationStore.running,
        builder: (context, running, _) => ValueListenableBuilder<int>(
          valueListenable: NotificationStore.lastHeartbeat,
          builder: (context, heartbeat, _) => ValueListenableBuilder<int>(
            valueListenable: NotificationStore.unread,
            builder: (context, unread, _) {
              final conn = notificationConnectionLabel(
                running: running,
                lastHeartbeatEpochSeconds: heartbeat,
                nowEpochSeconds: now,
              );
              final connColor = conn == '已连接'
                  ? c.ok
                  : (conn == '重连中' ? c.warn : c.danger);
              return Column(
                children: [
                  _statusRow(
                    c,
                    '前台服务',
                    running ? '运行中' : '未运行',
                    dot: running ? c.ok : c.danger,
                  ),
                  _statusRow(c, 'SSE 连接', conn, dot: connColor),
                  _statusRow(
                    c,
                    '最近事件/心跳',
                    formatNotificationTime(heartbeat),
                  ),
                  _statusRow(c, '未读通知', '$unread'),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _statusRow(AppColors c, String label, String value, {Color? dot}) {
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
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
            ),
            const SizedBox(width: 6),
          ],
          Text(value, style: TextStyle(color: c.fg, fontSize: 12)),
        ],
      ),
    );
  }
}
