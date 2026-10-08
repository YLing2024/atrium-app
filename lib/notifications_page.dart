import 'package:flutter/material.dart';

import 'login_page.dart';
import 'notification_detail_page.dart';
import 'notification_model.dart';
import 'notification_store.dart';
import 'notifications/notifications_compose.dart';
import 'notifications/notifications_controller.dart';
import 'notifications/notifications_filter_bar.dart';
import 'notifications/notifications_header.dart';
import 'notifications/notifications_list.dart';
import 'theme.dart';

/// 通知页：发通知（页头内联表单）+ 列表 + 筛选 + 单条已读/删除 + 全部已读。
///
/// 数据源：`GET /api/admin/notifications`（ts / readAt 均为 epoch 秒）。
/// 服务器 SSE 实时推送的新通知经 [NotificationStore.incoming] 置顶。
///
/// 铁律：本页发出通知后**禁止乐观更新** —— 不本地插入、不刷未读，只显示
/// 「已提交到服务器，等待推送…」，以 [PushWaitResult] 呈现收到 / 超时。
///
/// 状态与逻辑都在 [NotificationsController]，这里只负责组合、生命周期与弹窗。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.active = true});

  /// 是否为当前可见 Tab；由不可见变为可见时刷新一次。
  final bool active;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final NotificationsController _c;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _bodyText = TextEditingController();
  final TextEditingController _link = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c = NotificationsController(
      onAuthError: (e) => handleAuthError(context, e),
      onToast: (msg, {required ok}) => showAppToast(context, msg, ok: ok),
      confirm: _confirm,
    );
    _scroll.addListener(_onScroll);
    NotificationStore.incoming.addListener(_onIncoming);
    NotificationStore.reloadTick.addListener(_onReloadRequest);
    _c.loadTypes();
    _c.load();
  }

  @override
  void didUpdateWidget(covariant NotificationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从其它 Tab 切回本页：静默刷新，保留列表避免闪烁
    if (widget.active && !oldWidget.active) {
      _c.loadTypes();
      _c.load(silent: _c.feed.items.isNotEmpty);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    NotificationStore.incoming.removeListener(_onIncoming);
    NotificationStore.reloadTick.removeListener(_onReloadRequest);
    _c.dispose();
    _title.dispose();
    _bodyText.dispose();
    _link.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _c.loadMore();
    }
  }

  /// 服务器推送：唯一的新增入口（发送方不做本地插入）。
  void _onIncoming() {
    final item = NotificationStore.incoming.value;
    if (item == null || !mounted) return;
    _c.applyIncoming(item);
  }

  /// 调试页 / 其它发送方超时后请求「重新拉取列表」。
  void _onReloadRequest() {
    if (!mounted) return;
    _c.load(silent: _c.feed.items.isNotEmpty);
  }

  /// 点条目 → 详情页（顶部返回）。点开**不自动标记已读**：已读由详情页内的
  /// 独立按钮触发，避免误触丢失未读状态。
  Future<void> _openDetail(NotificationItem item) async {
    final action = await Navigator.of(context).push<NotificationDetailAction>(
      MaterialPageRoute(
        builder: (_) => NotificationDetailPage(
          item: item,
          types: _c.types,
          onMarkRead: _c.markRead,
          onDelete: _c.deleteFromDetail,
        ),
      ),
    );
    if (!mounted || action == null) return;
    setState(() {});
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.c.surface,
        title: Text(title, style: TextStyle(color: ctx.c.fg, fontSize: 16)),
        content: Text(message, style: TextStyle(color: ctx.c.fg, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '取消',
              style: TextStyle(color: ctx.c.muted, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '删除',
              style: TextStyle(color: ctx.c.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _send() async {
    final ok = await _c.sendNotification(
      titleText: _title.text,
      bodyText: _bodyText.text,
      linkText: _link.text,
    );
    if (!ok) return;
    _title.clear();
    _bodyText.clear();
    _link.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => RefreshIndicator(
        color: c.accent,
        onRefresh: () async {
          // 类别清单可能被后台新增/改名/停用，随下拉刷新一起重拉
          await _c.loadTypes();
          await _c.load(silent: _c.feed.items.isNotEmpty);
        },
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: NotificationsHeader(
                unread: _c.feed.unread,
                markingAll: _c.markingAll,
                composeOpen: _c.composeOpen,
                onToggleCompose: _c.toggleCompose,
                onReadAll: _c.readAll,
              ),
            ),
            if (_c.composeOpen)
              SliverToBoxAdapter(
                child: NotificationsCompose(
                  controller: _c,
                  titleController: _title,
                  bodyController: _bodyText,
                  linkController: _link,
                  onSend: _send,
                  onRepull: _c.repull,
                ),
              ),
            const SliverToBoxAdapter(child: Divider(height: 1)),
            SliverToBoxAdapter(
              child: NotificationsFilterBar(
                types: _c.types,
                unreadOnly: _c.unreadOnly,
                typeFilter: _c.typeFilter,
                levelFilter: _c.levelFilter,
                sourceFilter: _c.sourceFilter,
                sources: _c.sources,
                onUnreadOnly: _c.setUnreadOnly,
                onTypeFilter: _c.setTypeFilter,
                onLevelFilter: _c.setLevelFilter,
                onSourceFilter: _c.setSourceFilter,
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1)),
            ...buildNotificationsBodySlivers(
              context,
              controller: _c,
              onRetry: _c.load,
              onOpenDetail: _openDetail,
              onDelete: _c.delete,
            ),
          ],
        ),
      ),
    );
  }
}
