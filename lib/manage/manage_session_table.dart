import 'package:flutter/material.dart';

import '../theme.dart';
import 'manage_controller.dart';
import 'manage_format.dart';
import 'manage_widgets.dart';

/// 设备会话表：宽屏表格、窄屏卡片；支持行内重命名（失焦即保存）。
class ManageSessionTable extends StatefulWidget {
  const ManageSessionTable({
    super.key,
    required this.controller,
    required this.onDelete,
  });

  final ManageController controller;
  final void Function(Map<String, dynamic> session) onDelete;

  @override
  State<ManageSessionTable> createState() => _ManageSessionTableState();
}

class _ManageSessionTableState extends State<ManageSessionTable> {
  final TextEditingController _editNameCtrl = TextEditingController();
  final FocusNode _editFocus = FocusNode();

  @override
  void dispose() {
    _editNameCtrl.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _startRename(Map<String, dynamic> s) {
    _editNameCtrl.text = (s['deviceName'] ?? '').toString();
    widget.controller.startRename(s['id'].toString());
  }

  Future<void> _saveRename(Map<String, dynamic> s) =>
      widget.controller.saveRename(s, _editNameCtrl.text);

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
                  ['设备', '设备 IP', '登录时间', '最近活跃', '凭证过期', '操作'],
                ),
                for (final s in widget.controller.sessions) _sessionRow(c, s, wide),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final s in widget.controller.sessions) ...[
              _sessionRow(c, s, wide),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _sessionRow(AppColors c, Map<String, dynamic> s, bool wide) {
    final controller = widget.controller;
    final id = s['id'].toString();
    final editing = controller.editingId == id;
    final expiresAt =
        (s['expiresAt'] is num) ? (s['expiresAt'] as num).toInt() * 1000 : null;

    final deviceCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (editing)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _editNameCtrl,
                focusNode: _editFocus,
                maxLength: 64,
                enabled: !controller.editSaving,
                autofocus: true,
                style: TextStyle(color: c.fg, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: '设备名称',
                  hintStyle: TextStyle(color: c.muted, fontSize: 13),
                  filled: true,
                  fillColor: c.surface2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: c.accentBorder),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: c.accentBorder),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: c.accent),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onSubmitted: (_) => _saveRename(s),
                onTapOutside: (_) {
                  // 失焦自动保存（对齐 Web 编辑态：无「取消」，失焦即保存）
                  _saveRename(s);
                },
              ),
              if (controller.editError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    controller.editError!,
                    style: TextStyle(color: c.danger, fontSize: 11),
                  ),
                ),
            ],
          )
        else
          Row(
            children: [
              Flexible(
                child: Text(
                  (s['deviceName'] ?? '').toString().isEmpty
                      ? '未命名设备'
                      : (s['deviceName'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _startRename(s),
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.edit_outlined, size: 13, color: c.muted),
                ),
              ),
              if (s['isCurrent'] == true) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.accentBorder),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '当前设备',
                    style: TextStyle(color: c.accent, fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
        if ((s['userAgent'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              (s['userAgent'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.muted, fontSize: 11),
            ),
          ),
      ],
    );

    if (wide) {
      final cells = [
        deviceCol,
        Text(
          (s['ip'] ?? '').toString().isEmpty ? '—' : (s['ip'] ?? '').toString(),
          textAlign: TextAlign.right,
          style: TextStyle(
            color: c.fg,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          fmtTime(s['createdAt'] is num ? (s['createdAt'] as num) : null),
          textAlign: TextAlign.right,
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        Text(
          relativeTime(s['lastSeenAt'] is num ? (s['lastSeenAt'] as num) : null),
          textAlign: TextAlign.right,
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        Text(
          fmtTime(expiresAt),
          textAlign: TextAlign.right,
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        editing
            ? TextButton(
                onPressed: controller.editSaving ? null : () => _saveRename(s),
                child: Text(
                  controller.editSaving ? '保存中…' : '保存',
                  style: TextStyle(color: c.accent, fontSize: 12),
                ),
              )
            : TextButton(
                onPressed: () => widget.onDelete(s),
                child: Text('删除', style: TextStyle(color: c.danger, fontSize: 12)),
              ),
      ];
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
        ),
        child: Row(
          children: [
            for (final (i, cell) in cells.indexed)
              Expanded(
                flex: i == cells.length - 1 ? 1 : 2,
                child: i == 0 ? cell : Align(alignment: Alignment.centerRight, child: cell),
              ),
          ],
        ),
      );
    }

    // 窄屏卡片式布局
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          deviceCol,
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: manageKvLine(c, 'IP', (s['ip'] ?? '—').toString()),
              ),
              Expanded(
                child: manageKvLine(
                  c,
                  '登录',
                  fmtTime(s['createdAt'] is num ? (s['createdAt'] as num) : null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: manageKvLine(
                  c,
                  '活跃',
                  relativeTime(s['lastSeenAt'] is num ? (s['lastSeenAt'] as num) : null),
                ),
              ),
              Expanded(
                child: manageKvLine(c, '过期', fmtTime(expiresAt)),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: editing
                ? TextButton(
                    onPressed: controller.editSaving ? null : () => _saveRename(s),
                    child: Text(
                      controller.editSaving ? '保存中…' : '保存',
                      style: TextStyle(color: c.accent, fontSize: 12),
                    ),
                  )
                : TextButton(
                    onPressed: () => widget.onDelete(s),
                    child: Text('删除', style: TextStyle(color: c.danger, fontSize: 12)),
                  ),
          ),
        ],
      ),
    );
  }
}
