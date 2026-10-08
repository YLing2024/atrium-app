import 'dart:async';

import 'package:flutter/material.dart';

import 'files/files_controller.dart';
import 'files/files_header.dart';
import 'files/files_list.dart';
import 'files/files_share_dialogs.dart';
import 'files/files_share_manage.dart';
import 'files/files_uploads.dart';
import 'theme.dart';

/// 文件区：目录浏览 / 上传（带进度）/ 新建文件夹 / 重命名 / 删除 / 下载。
/// 路径均为相对文件区根目录的相对路径，根目录为 ''，越界由后端拦截。
/// 行为对齐 Web 端 Files.jsx（移动端不做拖拽上传）。
/// 页面骨架：状态与逻辑都在 [FilesController]，这里只负责组合与弹窗。
class FilesPage extends StatefulWidget {
  const FilesPage({super.key, this.active = true});

  /// 是否处于可见 Tab（首次可见才请求，对齐 Web 懒加载）
  final bool active;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  final FilesController _c = FilesController();
  final TextEditingController _dialogCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _c.loadOnce();
    });
  }

  @override
  void didUpdateWidget(covariant FilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _c.loadOnce();
  }

  @override
  void dispose() {
    _dialogCtrl.dispose();
    _c.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _pickFiles() {
    unawaited(
      _c.pickFiles().then((msg) {
        if (msg != null) _snack('选择文件失败：$msg');
      }),
    );
  }

  void _download(FsEntry e) {
    unawaited(
      _c.download(e).then((msg) {
        if (msg != null) _snack(msg);
      }),
    );
  }

  void _openMkdir() {
    _dialogCtrl.text = '';
    _c.openMkdir();
  }

  void _openRename(FsEntry e) {
    _dialogCtrl.text = e.name;
    _dialogCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: e.name.length,
    );
    _c.openRename(e);
  }

  void _openDelete(FsEntry e) {
    _c.openDelete(e);
  }

  void _submitDialog() {
    unawaited(_c.submitDialog(_dialogCtrl.text));
  }

  void _openShareCreate(FsEntry e) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => ShareCreateDialog(path: _c.targetOf(e), name: e.name),
      ),
    );
  }

  void _openShares() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const ShareManageSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Stack(
        children: [
          Column(
            children: [
              FilesHeader(
                controller: _c,
                onMkdir: _openMkdir,
                onPickFiles: _pickFiles,
                onOpenShares: _openShares,
              ),
              if (_c.uploads.isNotEmpty) FilesUploads(controller: _c),
              Expanded(
                child: FilesList(
                  controller: _c,
                  onDownload: _download,
                  onShare: _openShareCreate,
                  onRename: _openRename,
                  onDelete: _openDelete,
                ),
              ),
            ],
          ),
          if (_c.dialogType != null) _buildDialog(c),
        ],
      ),
    );
  }

  Widget _buildDialog(AppColors c) {
    final isDelete = _c.dialogType == 'delete';
    return Positioned.fill(
      child: GestureDetector(
        onTap: () {
          if (!_c.dialogBusy) _c.closeDialog();
        },
        child: Container(
          color: c.overlay,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _c.dialogTitle,
                    style: TextStyle(
                      color: c.fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isDelete)
                    Text(
                      '确定删除「${_c.dialogValue}」？'
                      '${_c.dialogIsDir ? '该目录及其全部内容都会被删除，' : ''}'
                      '此操作不可撤销。',
                      style: TextStyle(color: c.muted, fontSize: 13, height: 1.6),
                    )
                  else
                    TextField(
                      controller: _dialogCtrl,
                      autofocus: true,
                      style: TextStyle(color: c.fg, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _c.dialogType == 'mkdir' ? '文件夹名称' : '新名称',
                        hintStyle: TextStyle(color: c.muted, fontSize: 13),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submitDialog(),
                    ),
                  if (_c.dialogError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _c.dialogError,
                      style: TextStyle(color: c.danger, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _c.dialogBusy ? null : _c.closeDialog,
                        child: Text(
                          '取消',
                          style: TextStyle(color: c.muted, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _dialogCtrl,
                        builder: (context, value, _) => FilledButton(
                          onPressed: (_c.dialogBusy ||
                                  (!isDelete && value.text.trim().isEmpty))
                              ? null
                              : _submitDialog,
                          style: FilledButton.styleFrom(
                            backgroundColor: c.accent,
                            foregroundColor: c.bg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Text(
                            _c.dialogBusy ? '处理中…' : (isDelete ? '删除' : '确定'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
