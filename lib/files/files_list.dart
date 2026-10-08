import 'package:flutter/material.dart';

import '../theme.dart';
import 'files_controller.dart';

/// 文件列表：排序表头 + 列表 / 加载态 / 错误态 / 空态 + 行与行内菜单。
class FilesList extends StatelessWidget {
  const FilesList({
    super.key,
    required this.controller,
    required this.onDownload,
    required this.onShare,
    required this.onRename,
    required this.onDelete,
  });

  final FilesController controller;
  final void Function(FsEntry entry) onDownload;
  final void Function(FsEntry entry) onShare;
  final void Function(FsEntry entry) onRename;
  final void Function(FsEntry entry) onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          _buildSortHeader(context, c),
          const Divider(height: 1),
          Expanded(child: _buildList(c)),
        ],
      ),
    );
  }

  Widget _buildSortHeader(BuildContext context, AppColors c) {
    final sortKey = controller.sortKey;
    final sortDir = controller.sortDir;
    Widget col(String key, String label, {double? width, TextAlign align = TextAlign.left}) {
      final active = sortKey == key;
      final arrow = active ? (sortDir > 0 ? ' ↑' : ' ↓') : '';
      final child = Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          '$label$arrow',
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: active ? c.accent : c.muted,
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      );
      final tap = InkWell(onTap: () => controller.toggleSort(key), child: child);
      return width == null ? Expanded(child: tap) : SizedBox(width: width, child: tap);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const SizedBox(width: 25),
          col('name', '名称'),
          col('size', '大小', width: 64, align: TextAlign.right),
          col('time', '修改时间', width: 96, align: TextAlign.right),
          const SizedBox(width: 34),
        ],
      ),
    );
  }

  Widget _buildList(AppColors c) {
    final loading = controller.loading;
    final entries = controller.entries;
    final error = controller.error;
    if (loading && entries.isEmpty) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(color: c.accent, strokeWidth: 2),
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.danger, fontSize: 13),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => controller.load(controller.path),
                child: Text(
                  '重试',
                  style: TextStyle(color: c.accent, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (entries.isEmpty) {
      return Center(
        child: Text(
          '空目录',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
      );
    }
    final shown = controller.shown;
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: shown.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
      itemBuilder: (_, i) => _row(c, shown[i]),
    );
  }

  Widget _row(AppColors c, FsEntry e) {
    return InkWell(
      onTap: e.isDir ? () => controller.enter(e) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Icon(
              e.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
              size: 17,
              color: e.isDir ? c.accent : c.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                e.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.fg, fontSize: 13),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                e.isDir ? '—' : formatSize(e.size),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.muted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            SizedBox(
              width: 96,
              child: Text(
                formatTime(e.mtime),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.muted,
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            SizedBox(width: 34, child: _rowMenu(c, e)),
          ],
        ),
      ),
    );
  }

  Widget _rowMenu(AppColors c, FsEntry e) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert, size: 18, color: c.muted),
      color: c.surface,
      tooltip: '',
      onSelected: (v) {
        if (v == 'download') {
          onDownload(e);
        } else if (v == 'share') {
          onShare(e);
        } else if (v == 'rename') {
          onRename(e);
        } else if (v == 'delete') {
          onDelete(e);
        }
      },
      itemBuilder: (_) => [
        if (!e.isDir)
          const PopupMenuItem(
            value: 'download',
            height: 40,
            child: Text('下载', style: TextStyle(fontSize: 13)),
          ),
        if (!e.isDir)
          const PopupMenuItem(
            value: 'share',
            height: 40,
            child: Text('链接', style: TextStyle(fontSize: 13)),
          ),
        const PopupMenuItem(
          value: 'rename',
          height: 40,
          child: Text('重命名', style: TextStyle(fontSize: 13)),
        ),
        const PopupMenuItem(
          value: 'delete',
          height: 40,
          child: Text('删除', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}
