import 'package:flutter/material.dart';

import '../notification_model.dart';
import '../push_wait_result.dart';
import '../theme.dart';
import 'notifications_controller.dart';
import 'notifications_widgets.dart';

/// 页头内联的发通知表单：级别 / 标题 / 正文 / 链接 + 推送等待结果。
class NotificationsCompose extends StatelessWidget {
  const NotificationsCompose({
    super.key,
    required this.controller,
    required this.titleController,
    required this.bodyController,
    required this.linkController,
    required this.onSend,
    required this.onRepull,
  });

  final NotificationsController controller;
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final TextEditingController linkController;
  final VoidCallback onSend;
  final VoidCallback onRepull;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          notificationsFieldLabel(c, '级别'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: controller.level,
            isExpanded: true,
            dropdownColor: c.surface,
            style: TextStyle(color: c.fg, fontSize: 13),
            decoration: notificationsInputDecoration(c),
            items: [
              for (final (value, label) in kNotificationLevelOptions)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: controller.sending
                ? null
                : (v) => controller.setLevel(v ?? 'normal'),
          ),
          const SizedBox(height: 12),
          notificationsFieldLabel(c, '标题'),
          const SizedBox(height: 6),
          TextField(
            controller: titleController,
            maxLength: 80,
            enabled: !controller.sending,
            style: TextStyle(color: c.fg, fontSize: 13),
            decoration: notificationsInputDecoration(c).copyWith(
              counterText: '',
              hintText: '给你自己看的通知，≤ 80 字',
              hintStyle: TextStyle(color: c.muted, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          notificationsFieldLabel(c, '正文（选填，纯文本）'),
          const SizedBox(height: 6),
          TextField(
            controller: bodyController,
            maxLines: 3,
            enabled: !controller.sending,
            style: TextStyle(color: c.fg, fontSize: 13),
            decoration: notificationsInputDecoration(c).copyWith(
              hintText: '可留空',
              hintStyle: TextStyle(color: c.muted, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          notificationsFieldLabel(c, '链接（选填）'),
          const SizedBox(height: 6),
          TextField(
            controller: linkController,
            enabled: !controller.sending,
            keyboardType: TextInputType.url,
            style: TextStyle(color: c.fg, fontSize: 13),
            decoration: notificationsInputDecoration(c).copyWith(
              hintText: 'https://…',
              hintStyle: TextStyle(color: c.muted, fontSize: 13),
            ),
          ),
          if (controller.composeError != null) ...[
            const SizedBox(height: 10),
            notificationsBanner(c, controller.composeError!, ok: false),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: controller.sending ? null : onSend,
              child: Text(controller.sending ? '发送中…' : '发送'),
            ),
          ),
          ListenableBuilder(
            listenable: controller.pushWait,
            builder: (context, _) => PushWaitResult(
              state: controller.pushWait.state,
              onRepull: onRepull,
              repulled: controller.repulled,
            ),
          ),
        ],
      ),
    );
  }
}
