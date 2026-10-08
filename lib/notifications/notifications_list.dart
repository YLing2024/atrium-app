import 'package:flutter/material.dart';

import '../notification_model.dart';
import '../notification_summary.dart';
import '../theme.dart';
import 'notifications_controller.dart';
import 'notifications_widgets.dart';

/// 通知列表主体 slivers：加载中 / 错误 / 空态 / 列表 + 底部。
List<Widget> buildNotificationsBodySlivers(
  BuildContext context, {
  required NotificationsController controller,
  required VoidCallback onRetry,
  required void Function(NotificationItem item) onOpenDetail,
  required void Function(NotificationItem item) onDelete,
}) {
  final c = context.c;
  if (controller.loading && controller.feed.items.isEmpty) {
    return const [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    ];
  }
  if (controller.error != null && controller.feed.items.isEmpty) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: notificationsErrorBanner(
            c,
            controller.error!,
            onRetry: onRetry,
          ),
        ),
      ),
    ];
  }
  if (controller.feed.items.isEmpty) {
    return [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                controller.unreadOnly ||
                        controller.levelFilter.isNotEmpty ||
                        controller.sourceFilter.isNotEmpty ||
                        controller.typeFilter.isNotEmpty
                    ? '没有符合条件的通知'
                    : '暂无通知',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.fg, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                '新的系统通知会出现在这里。',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ];
  }
  return [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      sliver: SliverList.builder(
        itemCount: controller.feed.items.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: NotificationsItemTile(
            item: controller.feed.items[i],
            types: controller.types,
            onOpen: onOpenDetail,
            onDelete: onDelete,
          ),
        ),
      ),
    ),
    SliverToBoxAdapter(child: notificationsFooter(context, controller)),
  ];
}

/// 列表底部：加载更多 / 占位 / 「没有更多了」。
Widget notificationsFooter(
  BuildContext context,
  NotificationsController controller,
) {
  final c = context.c;
  if (controller.loadingMore) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
  if (controller.feed.hasMore) {
    return const SizedBox(height: 18);
  }
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(
      '没有更多了',
      textAlign: TextAlign.center,
      style: TextStyle(color: c.muted, fontSize: 12),
    ),
  );
}

/// 单条通知卡片。
class NotificationsItemTile extends StatelessWidget {
  const NotificationsItemTile({
    super.key,
    required this.item,
    required this.types,
    required this.onOpen,
    required this.onDelete,
  });

  final NotificationItem item;
  final List<NotificationType> types;
  final void Function(NotificationItem item) onOpen;
  final void Function(NotificationItem item) onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final urgent = item.isUrgent;
    final body = item.body ?? '';
    return InkWell(
      onTap: () => onOpen(item),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: urgent ? c.accentBorder : c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: urgent ? c.accentBorder : c.border,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    notificationLevelLabel(item.level),
                    style: TextStyle(
                      color: urgent ? c.accent : c.muted,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notificationTypeLabel(item.category, types),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatNotificationTime(item.ts),
                  style: TextStyle(color: c.muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.isUnread)
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: 7),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.accent,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    item.title.isEmpty ? '(无标题)' : item.title,
                    style: TextStyle(
                      color: c.fg,
                      fontSize: 13,
                      fontWeight: item.isUnread
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (item.link != null && item.link!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 1),
                    child: Icon(Icons.open_in_new, size: 14, color: c.muted),
                  ),
                IconButton(
                  onPressed: () => onDelete(item),
                  tooltip: '删除',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 24,
                  ),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline, size: 16, color: c.muted),
                ),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              NotificationBodySummary(
                body,
                style: TextStyle(color: c.muted, fontSize: 12, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
