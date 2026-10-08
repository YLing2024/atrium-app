import 'dart:async';

import 'package:flutter/material.dart';

import 'login_page.dart';
import 'manage/manage_controller.dart';
import 'manage/manage_dialogs.dart';
import 'manage/manage_keep_alive.dart';
import 'manage/manage_session_table.dart';
import 'manage/manage_token_table.dart';
import 'manage/manage_widgets.dart';
import 'theme.dart';

/// 管理 Tab：设备会话管理 + 接口令牌管理（对齐 Web Manage.jsx）。
///
/// 状态与逻辑都在 [ManageController]，这里只负责组合、生命周期与弹窗入口。
class ManagePage extends StatefulWidget {
  const ManagePage({super.key});

  @override
  State<ManagePage> createState() => _ManagePageState();
}

class _ManagePageState extends State<ManagePage> {
  late final ManageController _c;

  @override
  void initState() {
    super.initState();
    _c = ManageController(
      onAuthError: (e) => handleAuthError(context, e),
      forceLogout: forceLogout,
    );
    _c.init();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _restartNotificationService() {
    unawaited(
      _c.restartNotificationService().then((ok) {
        if (!mounted) return;
        showAppToast(context, ok ? '通知服务已重启' : '通知服务启动失败', ok: ok);
      }),
    );
  }

  void _askDeleteSession(Map<String, dynamic> s) {
    unawaited(showDeleteSessionDialog(context, _c, s));
  }

  void _openCreate() {
    unawaited(showCreateTokenDialog(context, _c));
  }

  void _openEdit(Map<String, dynamic> t) {
    unawaited(showEditTokenDialog(context, _c, t));
  }

  void _askRevoke(Map<String, dynamic> t) {
    unawaited(showRevokeTokenDialog(context, _c, t));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => RefreshIndicator(
        color: c.accent,
        onRefresh: _c.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                const Spacer(),
                Text(
                  '管理',
                  style: TextStyle(
                    color: c.fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            ManageKeepAliveSection(
              controller: _c,
              onRestart: _restartNotificationService,
              onRequestBattery: _c.requestBatteryOptimization,
            ),
            const SizedBox(height: 28),
            Container(height: 1, color: c.border),
            const SizedBox(height: 28),
            ManageSectionHeader(
              title: '设备管理',
              action: TextButton.icon(
                onPressed: _c.loadingSessions ? null : _c.loadSessions,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(_c.loadingSessions ? '刷新中…' : '刷新'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '删除设备会撤销其登录凭证，该设备必须重新认证才能进入管理后台。',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (_c.sessionsError != null) manageErrorBanner(c, _c.sessionsError!),
            if (_c.loadingSessions)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_c.sessions.isEmpty)
              manageEmptyBanner(c, '暂无已登录设备')
            else
              ManageSessionTable(controller: _c, onDelete: _askDeleteSession),
            const SizedBox(height: 28),
            Container(height: 1, color: c.border),
            const SizedBox(height: 28),
            ManageSectionHeader(
              title: '接口令牌',
              action: TextButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('生成令牌'),
              ),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                style: TextStyle(color: c.muted, fontSize: 12),
                children: [
                  const TextSpan(text: '接口令牌用于第三方工具调用 Admin 接口。调用时在请求头携带 '),
                  TextSpan(
                    text: 'Authorization: Bearer <令牌>',
                    style: TextStyle(
                      color: c.accent,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  const TextSpan(
                    text: ' 即可。令牌与登录设备相互独立，不占用设备登录。请妥善保管令牌，泄露可随时吊销。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_c.tokensError != null) manageErrorBanner(c, _c.tokensError!),
            if (_c.loadingTokens)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_c.tokens.isEmpty)
              manageEmptyBanner(c, '暂无接口令牌')
            else
              ManageTokenTable(controller: _c, onEdit: _openEdit, onRevoke: _askRevoke),
          ],
        ),
      ),
    );
  }
}
