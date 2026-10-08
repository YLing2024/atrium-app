import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import 'files_share_common.dart';
import 'files_share_dialogs.dart';

/* ---------------- 管理面板：列表 / 复制 / 改期 / 撤销 / 删除 ---------------- */

class ShareManageSheet extends StatefulWidget {
  const ShareManageSheet({super.key});

  @override
  State<ShareManageSheet> createState() => _ShareManageSheetState();
}

class _ShareManageSheetState extends State<ShareManageSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _error = '';
  String _busyId = '';
  String _copiedId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final list = await Api.fileShares();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = shareMsgOf(e);
        _items = [];
        _loading = false;
      });
    }
  }

  void _apply(Map<String, dynamic> rec) {
    final id = rec['id'];
    if (id == null) return;
    setState(() {
      _items = [
        for (final s in _items) s['id'] == id ? rec : s,
      ];
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _copy(Map<String, dynamic> s) async {
    final url = (s['url'] ?? '').toString();
    if (url.isEmpty) {
      _snack('该记录没有链接');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    final id = shareIdOf(s);
    setState(() => _copiedId = id);
    _snack('已复制链接');
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _copiedId == id) setState(() => _copiedId = '');
    });
  }

  Future<void> _edit(Map<String, dynamic> s) async {
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ShareScheduleDialog(share: s),
    );
    if (updated == null || !mounted) return;
    _apply(updated);
  }

  Future<void> _revoke(Map<String, dynamic> s) async {
    final ok = await confirmDialog(
      context,
      '撤销链接',
      '撤销「${shareDisplayName(s)}」的临时链接？撤销后不可恢复。',
      '撤销',
    );
    if (!ok || !mounted) return;
    setState(() => _busyId = shareIdOf(s));
    try {
      final rec = await Api.fileShareUpdate(shareIdOf(s), revoked: true);
      if (!mounted) return;
      _apply(rec);
    } catch (e) {
      _snack(shareMsgOf(e));
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  Future<void> _remove(Map<String, dynamic> s) async {
    final ok = await confirmDialog(
      context,
      '删除记录',
      '删除「${shareDisplayName(s)}」的链接记录？磁盘文件不受影响。',
      '删除',
    );
    if (!ok || !mounted) return;
    final id = shareIdOf(s);
    setState(() => _busyId = id);
    try {
      await Api.fileShareDelete(id);
      if (!mounted) return;
      setState(() => _items = _items.where((x) => x['id'] != s['id']).toList());
    } catch (e) {
      _snack(shareMsgOf(e));
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '临时链接',
                style: TextStyle(
                  color: c.fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _loading ? null : _load,
                child: Text('刷新', style: TextStyle(color: c.accent, fontSize: 12)),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
                tooltip: '关闭',
                icon: Icon(Icons.close, size: 18, color: c.muted),
              ),
            ],
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_error, style: TextStyle(color: c.danger, fontSize: 12)),
          ],
          const SizedBox(height: 6),
          Flexible(child: _buildBody(c)),
        ],
      ),
    );
  }

  Widget _buildBody(AppColors c) {
    if (_loading && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: c.accent,
      backgroundColor: c.surface,
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 48),
                Center(
                  child: Text(
                    '暂无临时链接',
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _items.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
              itemBuilder: (_, i) => _item(c, _items[i]),
            ),
    );
  }

  Widget _item(AppColors c, Map<String, dynamic> s) {
    final id = shareIdOf(s);
    final status = (s['status'] ?? '').toString();
    final meta = shareStatusMeta(c, status);
    final name = shareDisplayName(s);
    final relPath = (s['relPath'] ?? '').toString();
    final note = (s['note'] ?? '').toString();
    final downloads = s['downloads'];
    final count = downloads is num ? downloads.toInt() : 0;
    final created = s['createdAt'];
    final createdMs = created is num ? created.toInt() : 0;
    final fileExists = s['fileExists'] != false;
    final busy = _busyId == id;
    final copied = _copiedId == id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.fg, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: meta.color,
                ),
              ),
              const SizedBox(width: 5),
              Text(meta.text, style: TextStyle(color: meta.color, fontSize: 11.5)),
            ],
          ),
          if (relPath.isNotEmpty && relPath != name) ...[
            const SizedBox(height: 2),
            Text(
              relPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.muted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '有效期 ${shareExpiryText(s)} · 下载 $count 次 · 创建 ${shareFmtTime(createdMs)}',
            style: TextStyle(color: c.muted, fontSize: 11),
          ),
          if (!fileExists) ...[
            const SizedBox(height: 2),
            Text('文件已删除', style: TextStyle(color: c.danger, fontSize: 11)),
          ],
          if (note.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '备注 $note',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 2),
          Wrap(
            spacing: 2,
            runSpacing: 0,
            children: [
              _op(
                c,
                copied ? '已复制' : '复制链接',
                onTap: () => _copy(s),
              ),
              if (status == 'active')
                _op(c, '改期', onTap: busy ? null : () => _edit(s)),
              if (status == 'active')
                _op(c, '撤销', danger: true, onTap: busy ? null : () => _revoke(s)),
              _op(c, '删除记录', danger: true, onTap: busy ? null : () => _remove(s)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _op(
    AppColors c,
    String label, {
    bool danger = false,
    VoidCallback? onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: danger ? c.danger : c.accent,
      ),
      child: Text(label, style: const TextStyle(fontSize: 11.5)),
    );
  }
}
