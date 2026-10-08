import 'package:flutter/material.dart';

import '../theme.dart';
import 'files_controller.dart';

/// 文件区顶部栏：标题、上级 / 面包屑、动作按钮与刷新。
class FilesHeader extends StatelessWidget {
  const FilesHeader({
    super.key,
    required this.controller,
    required this.onMkdir,
    required this.onPickFiles,
    required this.onOpenShares,
  });

  final FilesController controller;
  final VoidCallback onMkdir;
  final VoidCallback onPickFiles;
  final VoidCallback onOpenShares;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final path = controller.path;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              Text(
                '文件',
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
          const SizedBox(height: 10),
          Row(
            children: [
              InkWell(
                onTap: path.isEmpty ? null : controller.goParent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_upward,
                        size: 14,
                        color: path.isEmpty ? c.border : c.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '上级',
                        style: TextStyle(
                          fontSize: 12,
                          color: path.isEmpty ? c.muted : c.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _Crumbs(controller: controller)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _actionBtn(c, Icons.create_new_folder_outlined, '新建文件夹', onMkdir),
                    _actionBtn(c, Icons.upload_file_outlined, '选择文件', onPickFiles),
                    _actionBtn(c, Icons.link_outlined, '临时链接', onOpenShares),
                  ],
                ),
              ),
              IconButton(
                onPressed: controller.loading ? null : () => controller.load(path),
                tooltip: '刷新',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.refresh, size: 20, color: c.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    AppColors c,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: c.accent),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, color: c.fg)),
          ],
        ),
      ),
    );
  }
}

/// 面包屑：根目录 + 逐级路径，横向滚动、右对齐。
class _Crumbs extends StatelessWidget {
  const _Crumbs({required this.controller});

  final FilesController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final path = controller.path;
    final crumbs = controller.crumbs;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          InkWell(
            onTap: path.isEmpty ? null : () => controller.load(FilesController.root),
            child: Text(
              '根目录',
              style: TextStyle(fontSize: 12, color: path.isEmpty ? c.fg : c.muted),
            ),
          ),
          for (final crumb in crumbs) ...[
            Text('/', style: TextStyle(fontSize: 12, color: c.muted)),
            InkWell(
              onTap: crumb.path == path ? null : () => controller.load(crumb.path),
              child: Text(
                crumb.name,
                style: TextStyle(
                  fontSize: 12,
                  color: crumb.path == path ? c.fg : c.muted,
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
