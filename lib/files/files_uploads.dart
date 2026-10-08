import 'package:flutter/material.dart';

import '../theme.dart';
import 'files_controller.dart';

/// 上传面板：标题 / 计数、清除已完成、与每行的进度 / 取消 / 重试。
class FilesUploads extends StatelessWidget {
  const FilesUploads({super.key, required this.controller});

  final FilesController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final uploads = controller.uploads;
    final active = uploads
        .where((u) => u.status == 'uploading' || u.status == 'waiting')
        .length;
    final failed = uploads.where((u) => u.status == 'error').length;
    final head = active > 0 ? '上传中 · 剩余 $active' : '上传完成';
    final shown = uploads.length > 6 ? 6 : uploads.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$head${failed > 0 ? ' · 失败 $failed' : ''}',
                    style: TextStyle(color: c.fg, fontSize: 12),
                  ),
                ),
                InkWell(
                  onTap: controller.clearFinished,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      '清除已完成',
                      style: TextStyle(color: c.muted, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: shown,
              itemBuilder: (_, i) => _uploadRow(c, uploads[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadRow(AppColors c, UploadTask u) {
    final error = u.status == 'error';
    final bar = u.status == 'done'
        ? 1.0
        : u.status == 'waiting'
            ? 0.0
            : (u.percent / 100).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  u.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.fg, fontSize: 12),
                ),
              ),
              if (error)
                _linkBtn(c, '重试', c.accent, () => controller.retryUpload(u))
              else if (u.status == 'uploading' || u.status == 'waiting')
                _linkBtn(c, '取消', c.muted, () => controller.cancelUpload(u))
              else
                const SizedBox(width: 4),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _uploadMeta(u),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: error ? c.danger : c.muted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: bar,
              minHeight: 3,
              backgroundColor: c.surface2,
              valueColor: AlwaysStoppedAnimation<Color>(
                error ? c.danger : c.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 上传行状态文案：进度只反映 HTTP 段，落盘那几秒停在 99% 需明确提示。
String _uploadMeta(UploadTask u) {
  if (u.status == 'error') return u.error.isEmpty ? '失败' : u.error;
  if (u.status == 'done') return '${formatSize(u.size)} · 完成';
  if (u.status == 'waiting') return '${formatSize(u.size)} · 等待中';
  if (u.percent >= 99) return '${formatSize(u.size)} · 写入服务器…';
  final parts = <String>[
    '${formatSize(u.loaded)} / ${formatSize(u.size)}',
    '${u.percent.toStringAsFixed(0)}%',
  ];
  if (u.speed > 0) parts.add('${formatSize(u.speed.round())}/s');
  if (u.eta > 0) parts.add('剩余 ${formatDuration(u.eta)}');
  return parts.join(' · ');
}

Widget _linkBtn(AppColors c, String label, Color color, VoidCallback onTap) {
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    ),
  );
}
