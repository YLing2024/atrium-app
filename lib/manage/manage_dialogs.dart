import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../login_page.dart';
import '../theme.dart';
import 'manage_controller.dart';
import 'manage_format.dart';

/// 弹窗内的带标签输入框（生成 / 编辑令牌共用）。
class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.label,
    required this.controller,
    this.maxLength,
    this.hint,
    this.number = false,
  });

  final String label;
  final TextEditingController controller;
  final int? maxLength;
  final String? hint;
  final bool number;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: c.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLength: maxLength,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: c.fg, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: hint,
            hintStyle: TextStyle(color: c.muted, fontSize: 13),
            filled: true,
            fillColor: c.surface2,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: c.border),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}

/// 删除设备确认弹窗。
Future<void> showDeleteSessionDialog(
  BuildContext context,
  ManageController controller,
  Map<String, dynamic> s,
) {
  final isCurrent = s['isCurrent'] == true;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.c.surface,
      title: Text('删除设备', style: TextStyle(color: ctx.c.fg, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '删除设备「${(s['deviceName'] ?? '').toString().isEmpty ? '未命名设备' : s['deviceName']}」并撤销其登录凭证？',
            style: TextStyle(color: ctx.c.fg, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            isCurrent
                ? '该设备将立即退出，必须重新认证才能进入管理后台。'
                : '该设备将立即失效，必须重新 TOTP 认证后才能进入管理后台。',
            style: TextStyle(color: ctx.c.muted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('取消', style: TextStyle(color: ctx.c.muted, fontSize: 13)),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            await controller.confirmDeleteSession(s);
          },
          child: Text('删除', style: TextStyle(color: ctx.c.danger, fontSize: 13)),
        ),
      ],
    ),
  );
}

/// 生成接口令牌弹窗；成功后展示一次性明文。
Future<void> showCreateTokenDialog(
  BuildContext context,
  ManageController controller,
) async {
  final nameCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final customCtrl = TextEditingController();
  var days = '30';
  var creating = false;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> submit() async {
          final nameErr = validateTokenName(nameCtrl.text);
          if (nameErr != null) {
            setDialogState(() => error = nameErr);
            return;
          }
          final raw = days == 'custom' ? customCtrl.text : days;
          final n = parseExpiryDays(raw);
          if (n == null) {
            setDialogState(() => error = '有效期需为 1~365 天的整数');
            return;
          }
          setDialogState(() {
            creating = true;
            error = null;
          });
          try {
            final data = await controller.createToken(
              name: nameCtrl.text.trim(),
              note: noteCtrl.text.trim(),
              expiresInDays: n,
            );
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            await controller.loadTokens();
            if (!context.mounted) return;
            await showCreatedTokenDialog(context, (data['token'] ?? '').toString());
          } catch (e) {
            if (!ctx.mounted) return;
            final handled = await handleAuthError(ctx, e);
            setDialogState(() {
              creating = false;
              error = handled ? null : e.toString();
            });
          }
        }

        return AlertDialog(
          backgroundColor: ctx.c.surface,
          title: Text('生成接口令牌', style: TextStyle(color: ctx.c.fg, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialogField(
                  label: '令牌名称',
                  controller: nameCtrl,
                  maxLength: 64,
                  hint: '如：行情脚本',
                ),
                const SizedBox(height: 12),
                _DialogField(
                  label: '备注（选填）',
                  controller: noteCtrl,
                  maxLength: 200,
                  hint: '用途说明',
                ),
                const SizedBox(height: 12),
                Text(
                  '有效期',
                  style: TextStyle(
                    color: ctx.c.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: days,
                  isExpanded: true,
                  dropdownColor: ctx.c.surface,
                  style: TextStyle(color: ctx.c.fg, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: ctx.c.surface2,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: ctx.c.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: '7', child: Text('7 天')),
                    DropdownMenuItem(value: '30', child: Text('30 天')),
                    DropdownMenuItem(value: '90', child: Text('90 天')),
                    DropdownMenuItem(value: 'custom', child: Text('自定义天数')),
                  ],
                  onChanged: (v) => setDialogState(() => days = v ?? '30'),
                ),
                if (days == 'custom') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: customCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: ctx.c.fg, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '1~365',
                      hintStyle: TextStyle(color: ctx.c.muted, fontSize: 13),
                      filled: true,
                      fillColor: ctx.c.surface2,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: ctx.c.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(color: ctx.c.danger, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: creating ? null : () => Navigator.of(ctx).pop(),
              child: Text('取消', style: TextStyle(color: ctx.c.muted, fontSize: 13)),
            ),
            TextButton(
              onPressed: creating ? null : submit,
              child: Text(
                creating ? '生成中…' : '生成',
                style: TextStyle(color: ctx.c.accent, fontSize: 13),
              ),
            ),
          ],
        );
      },
    ),
  );
  nameCtrl.dispose();
  noteCtrl.dispose();
  customCtrl.dispose();
}

/// 展示一次性令牌明文与 curl 示例。
Future<void> showCreatedTokenDialog(BuildContext context, String token) async {
  var copied = false;
  final curl =
      'curl -H "Authorization: Bearer $token" $kApiBase/api/admin/system';
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: ctx.c.surface,
        title: Text('接口令牌已生成', style: TextStyle(color: ctx.c.fg, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '令牌仅显示一次，关闭后无法再次查看，请立即保存。',
                style: TextStyle(color: ctx.c.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ctx.c.bg,
                  border: Border.all(color: ctx.c.border),
                ),
                child: SelectableText(
                  token,
                  style: TextStyle(
                    color: ctx.c.fg,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  if (!ctx.mounted) return;
                  setDialogState(() => copied = true);
                  Future.delayed(const Duration(milliseconds: 1500), () {
                    if (ctx.mounted) setDialogState(() => copied = false);
                  });
                },
                icon: Icon(copied ? Icons.check : Icons.copy, size: 16, color: ctx.c.accent),
                label: Text(
                  copied ? '已复制' : '复制令牌',
                  style: TextStyle(color: ctx.c.accent, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'curl 用法示例',
                style: TextStyle(
                  color: ctx.c.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ctx.c.bg,
                  border: Border.all(color: ctx.c.border),
                ),
                child: SelectableText(
                  curl,
                  style: TextStyle(
                    color: ctx.c.muted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('关闭', style: TextStyle(color: ctx.c.muted, fontSize: 13)),
          ),
        ],
      ),
    ),
  );
}

/// 编辑接口令牌弹窗：仅提交有改动的字段，可选重置有效期。
Future<void> showEditTokenDialog(
  BuildContext context,
  ManageController controller,
  Map<String, dynamic> t,
) async {
  final nameCtrl = TextEditingController(text: (t['name'] ?? '').toString());
  final noteCtrl = TextEditingController(text: (t['note'] ?? '').toString());
  final daysCtrl = TextEditingController();
  var saving = false;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> submit() async {
          final nameErr = validateTokenName(nameCtrl.text);
          if (nameErr != null) {
            setDialogState(() => error = nameErr);
            return;
          }
          final name = nameCtrl.text.trim();
          final patch = <String, dynamic>{};
          if (name != (t['name'] ?? '').toString()) patch['name'] = name;
          if (noteCtrl.text.trim() != (t['note'] ?? '').toString()) {
            patch['note'] = noteCtrl.text.trim();
          }
          final daysRaw = daysCtrl.text.trim();
          if (daysRaw.isNotEmpty) {
            final n = parseExpiryDays(daysRaw);
            if (n == null) {
              setDialogState(() => error = '有效期需为 1~365 天的整数');
              return;
            }
            patch['expiresInDays'] = n;
          }
          if (patch.isEmpty) {
            Navigator.of(ctx).pop(); // 无改动：直接关闭
            return;
          }
          setDialogState(() {
            saving = true;
            error = null;
          });
          try {
            await controller.updateToken(t['id'].toString(), patch);
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            await controller.loadTokens();
          } catch (e) {
            if (!ctx.mounted) return;
            final handled = await handleAuthError(ctx, e);
            setDialogState(() {
              saving = false;
              error = handled ? null : e.toString();
            });
          }
        }

        return AlertDialog(
          backgroundColor: ctx.c.surface,
          title: Text('编辑接口令牌', style: TextStyle(color: ctx.c.fg, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialogField(label: '令牌名称', controller: nameCtrl, maxLength: 64),
                const SizedBox(height: 12),
                _DialogField(label: '备注（选填）', controller: noteCtrl, maxLength: 200, hint: '用途说明'),
                const SizedBox(height: 12),
                _DialogField(
                  label: '重置有效期（选填）',
                  controller: daysCtrl,
                  hint: '留空则保持当前有效期',
                  number: true,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(color: ctx.c.danger, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: Text('取消', style: TextStyle(color: ctx.c.muted, fontSize: 13)),
            ),
            TextButton(
              onPressed: saving ? null : submit,
              child: Text(
                saving ? '保存中…' : '保存',
                style: TextStyle(color: ctx.c.accent, fontSize: 13),
              ),
            ),
          ],
        );
      },
    ),
  );
  nameCtrl.dispose();
  noteCtrl.dispose();
  daysCtrl.dispose();
}

/// 吊销令牌确认弹窗。
Future<void> showRevokeTokenDialog(
  BuildContext context,
  ManageController controller,
  Map<String, dynamic> t,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.c.surface,
      title: Text('吊销接口令牌', style: TextStyle(color: ctx.c.fg, fontSize: 16)),
      content: Text(
        '吊销令牌「${t['name']}」？吊销后立即失效，使用该令牌的工具将无法再调用接口。',
        style: TextStyle(color: ctx.c.fg, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('取消', style: TextStyle(color: ctx.c.muted, fontSize: 13)),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            await controller.deleteToken(t);
          },
          child: Text('吊销', style: TextStyle(color: ctx.c.danger, fontSize: 13)),
        ),
      ],
    ),
  );
}
