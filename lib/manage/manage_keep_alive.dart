import 'package:flutter/material.dart';

import '../notification_model.dart';
import '../notification_store.dart';
import '../theme.dart';
import 'manage_controller.dart';
import 'manage_widgets.dart';

/// 通知保活状态卡：诚实展示服务状态与补救手段（对齐需求「管理页保活状态卡」）。
class ManageKeepAliveSection extends StatelessWidget {
  const ManageKeepAliveSection({
    super.key,
    required this.controller,
    required this.onRestart,
    required this.onRequestBattery,
  });

  final ManageController controller;
  final VoidCallback onRestart;
  final VoidCallback onRequestBattery;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManageSectionHeader(
          title: '通知保活',
          action: TextButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('重启通知服务'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '保持与服务器的通知长连接，收到新通知时以系统通知提醒。',
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Container(
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
                builder: (context, unread, _) => Column(
                  children: [
                    manageStatusRow(
                      c,
                      '服务状态',
                      running ? '运行中' : '未运行',
                      dot: running,
                    ),
                    manageStatusRow(
                      c,
                      '最后心跳',
                      heartbeat > 0
                          ? formatNotificationTime(heartbeat)
                          : '从未',
                    ),
                    manageStatusRow(c, '未读通知', '$unread'),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: controller.ignoringBattery ? null : onRequestBattery,
          icon: Icon(
            controller.ignoringBattery ? Icons.check : Icons.battery_saver,
            size: 16,
          ),
          label: Text(
            controller.ignoringBattery ? '已忽略电池优化' : '申请忽略电池优化',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '若厂商系统仍自动结束后台，请在系统设置中允许本应用自启动与后台运行。',
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
      ],
    );
  }
}
