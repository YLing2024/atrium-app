import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// 用系统浏览器打开链接，失败给出提示（列表、编辑器预览链接共用）。
Future<void> launchExternal(BuildContext context, String url) async {
  try {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) _snackError(context, '无法打开链接');
  } catch (_) {
    if (context.mounted) _snackError(context, '无法打开链接');
  }
}

void _snackError(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: TextStyle(color: context.c.danger)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// 失败提示（列表删除等操作复用）：红字浮动 SnackBar。
void showBlogErrorToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: TextStyle(color: context.c.danger)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// 确认弹窗：返回用户是否点「确定」。
Future<bool> showBlogConfirm(
  BuildContext context,
  String title,
  String message,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(message, style: const TextStyle(fontSize: 13, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 只读标识展示（文章 ID / 合集 ID）：public_id 是 19 位字符串，严禁转数字。
Widget blogReadonlyValue(AppColors c, String value, String hint) {
  final v = value.trim();
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    decoration: BoxDecoration(
      color: c.surface2,
      border: Border.all(color: c.border),
    ),
    child: Text(
      v.isEmpty ? hint : v,
      style: TextStyle(
        color: v.isEmpty ? c.muted : c.fg,
        fontSize: 13,
        fontFamily: v.isEmpty ? null : 'monospace',
      ),
    ),
  );
}
