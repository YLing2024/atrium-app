import 'package:flutter/material.dart';

import '../theme.dart';
import 'manage_controller.dart';
import 'manage_format.dart';
import 'manage_widgets.dart';

/// 接口令牌表：宽屏表格、窄屏卡片；每行提供编辑 / 吊销。
class ManageTokenTable extends StatelessWidget {
  const ManageTokenTable({
    super.key,
    required this.controller,
    required this.onEdit,
    required this.onRevoke,
  });

  final ManageController controller;
  final void Function(Map<String, dynamic> token) onEdit;
  final void Function(Map<String, dynamic> token) onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        if (wide) {
          return Container(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                manageTableHeader(
                  c,
                  ['名称', '备注', '创建时间', '过期时间', '最近使用', '操作'],
                ),
                for (final t in controller.tokens) _tokenRow(c, t, wide),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final t in controller.tokens) ...[
              _tokenRow(c, t, wide),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _tokenRow(AppColors c, Map<String, dynamic> t, bool wide) {
    final expiresAt = t['expiresAt'] is num ? (t['expiresAt'] as num).toInt() : null;
    final expired = expiresAt != null &&
        expiresAt > 0 &&
        expiresAt <= DateTime.now().millisecondsSinceEpoch;
    final lastUsed = t['lastUsedAt'] is num ? (t['lastUsedAt'] as num).toInt() : null;

    final nameCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (t['name'] ?? '').toString(),
          style: TextStyle(
            color: c.fg,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        if ((t['note'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              (t['note'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.muted, fontSize: 11),
            ),
          ),
      ],
    );

    final expiryCol = expired
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: c.danger),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '已过期',
              style: TextStyle(color: c.danger, fontSize: 10),
            ),
          )
        : Text(
            '${fmtDate(expiresAt?.toDouble())} · 剩余 ${remainingDays(expiresAt?.toDouble())} 天',
            textAlign: TextAlign.right,
            style: TextStyle(color: c.fg, fontSize: 12),
          );

    final lastUsedCol = lastUsed == null || lastUsed == 0
        ? Text('从未使用', style: TextStyle(color: c.muted, fontSize: 12))
        : Text(
            fmtTime(lastUsed.toDouble()),
            textAlign: TextAlign.right,
            style: TextStyle(color: c.muted, fontSize: 12),
          );

    final opsCol = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => onEdit(t),
          child: Text('编辑', style: TextStyle(color: c.accent, fontSize: 12)),
        ),
        TextButton(
          onPressed: () => onRevoke(t),
          child: Text('吊销', style: TextStyle(color: c.danger, fontSize: 12)),
        ),
      ],
    );

    if (wide) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(flex: 2, child: nameCol),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  (t['note'] ?? '').toString().isEmpty ? '—' : (t['note'] ?? '').toString(),
                  textAlign: TextAlign.right,
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  fmtDate(t['createdAt'] is num ? (t['createdAt'] as num) : null),
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(alignment: Alignment.centerRight, child: expiryCol),
            ),
            Expanded(
              flex: 1,
              child: Align(alignment: Alignment.centerRight, child: lastUsedCol),
            ),
            Expanded(
              flex: 1,
              child: Align(alignment: Alignment.centerRight, child: opsCol),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          nameCol,
          const SizedBox(height: 8),
          manageKvLine(
            c,
            '创建',
            fmtDate(t['createdAt'] is num ? (t['createdAt'] as num) : null),
          ),
          const SizedBox(height: 4),
          manageKvLine(
            c,
            '过期',
            expired
                ? '已过期'
                : '${fmtDate(expiresAt?.toDouble())} · 剩余 ${remainingDays(expiresAt?.toDouble())} 天',
          ),
          const SizedBox(height: 4),
          manageKvLine(
            c,
            '使用',
            lastUsed == null || lastUsed == 0 ? '从未使用' : fmtTime(lastUsed.toDouble()),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: opsCol,
          ),
        ],
      ),
    );
  }
}
