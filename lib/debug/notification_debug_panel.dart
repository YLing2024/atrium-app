import 'dart:async';

import 'package:flutter/material.dart';

import '../login_page.dart';
import '../push_wait_result.dart';
import '../theme.dart';
import 'debug_api_section.dart';
import 'debug_common.dart';
import 'debug_controller.dart';
import 'debug_result_section.dart';
import 'debug_send_form.dart';
import 'debug_status_card.dart';

/// 通知调试面板：实时状态 / 发测试通知 / 接口说明 / 调用结果。
///
/// 状态与逻辑都在 [NotificationDebugController]，这里只负责组合与生命周期。
/// 实时状态**复用** NotificationStore（notification_service.dart 的同源状态），
/// 不另起 SSE 连接；未读数以服务端 `GET /api/admin/notifications` 下拉刷新校正。
class NotificationDebugPanel extends StatefulWidget {
  const NotificationDebugPanel({super.key, this.active = true});

  final bool active;

  @override
  State<NotificationDebugPanel> createState() => _NotificationDebugPanelState();
}

class _NotificationDebugPanelState extends State<NotificationDebugPanel> {
  late final NotificationDebugController _c;
  final TextEditingController _title = TextEditingController(text: '测试通知');
  final TextEditingController _body = TextEditingController(text: '来自 Admin 调试');
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _c = NotificationDebugController(
      onAuthError: (e) => handleAuthError(context, e),
      onToast: (msg, {required ok}) => showAppToast(context, msg, ok: ok),
    );
    _syncTicker();
    if (widget.active) unawaited(_c.sync());
  }

  @override
  void didUpdateWidget(covariant NotificationDebugPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) unawaited(_c.sync());
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _c.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// 仅在可见时每秒重绘，让「x 秒前」等相对时间保持准确
  void _syncTicker() {
    if (widget.active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!widget.active) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<void> _send() async {
    final ok = await _c.send(titleText: _title.text, body: _body.text);
    if (!ok) return;
    _title.clear();
    _body.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => RefreshIndicator(
        color: c.accent,
        onRefresh: _c.sync,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            debugBlockTitle(c, '实时状态'),
            const SizedBox(height: 10),
            DebugStatusCard(now: _now()),
            const SizedBox(height: 26),
            Container(height: 1, color: c.border),
            const SizedBox(height: 26),
            debugBlockTitle(c, '发一条测试通知'),
            const SizedBox(height: 10),
            DebugSendForm(
              title: _title,
              body: _body,
              level: _c.level,
              sending: _c.sending,
              onLevelChanged: _c.setLevel,
              onSend: _send,
            ),
            ListenableBuilder(
              listenable: _c.pushWait,
              builder: (context, _) => PushWaitResult(
                state: _c.pushWait.state,
                onRepull: _c.repull,
                repulled: _c.repulled,
              ),
            ),
            const SizedBox(height: 26),
            Container(height: 1, color: c.border),
            const SizedBox(height: 26),
            DebugApiSection(copied: _c.copied, onCopy: _c.copyExample),
            const SizedBox(height: 26),
            Container(height: 1, color: c.border),
            const SizedBox(height: 26),
            debugBlockTitle(c, '调用结果'),
            const SizedBox(height: 10),
            DebugResultSection(result: _c.result),
          ],
        ),
      ),
    );
  }
}
