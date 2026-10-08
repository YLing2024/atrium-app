import 'package:flutter/material.dart';

import '../notification_model.dart';
import '../notification_type_filter.dart';
import '../theme.dart';
import 'notifications_widgets.dart';

/// 通知筛选栏：全部 / 未读 + 类别 + 级别 + 来源。
class NotificationsFilterBar extends StatelessWidget {
  const NotificationsFilterBar({
    super.key,
    required this.types,
    required this.unreadOnly,
    required this.typeFilter,
    required this.levelFilter,
    required this.sourceFilter,
    required this.sources,
    required this.onUnreadOnly,
    required this.onTypeFilter,
    required this.onLevelFilter,
    required this.onSourceFilter,
  });

  final List<NotificationType> types;
  final bool unreadOnly;
  final String typeFilter;
  final String levelFilter;
  final String sourceFilter;
  final Set<String> sources;
  final ValueChanged<bool> onUnreadOnly;
  final ValueChanged<String> onTypeFilter;
  final ValueChanged<String> onLevelFilter;
  final ValueChanged<String> onSourceFilter;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          notificationsSegment(c, '全部', !unreadOnly, () => onUnreadOnly(false)),
          notificationsSegment(c, '未读', unreadOnly, () => onUnreadOnly(true)),
          NotificationTypeFilter(
            types: types,
            value: typeFilter,
            onChanged: onTypeFilter,
          ),
          notificationsDropdown(
            c,
            value: levelFilter,
            items: [('', '全部级别'), ...kNotificationLevelOptions],
            onChanged: onLevelFilter,
          ),
          notificationsDropdown(
            c,
            width: 140,
            value: sourceFilter,
            items: [('', '全部来源'), for (final s in sources) (s, s)],
            onChanged: onSourceFilter,
          ),
        ],
      ),
    );
  }
}
