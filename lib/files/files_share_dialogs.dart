import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import 'files_share_common.dart';

/* ---------------- 创建：预设有效期 + 自定义时刻 ---------------- */

class ShareCreateDialog extends StatefulWidget {
  const ShareCreateDialog({super.key, required this.path, required this.name});

  /// 文件区相对路径（提交给后端）
  final String path;

  /// 展示用文件名
  final String name;

  @override
  State<ShareCreateDialog> createState() => _ShareCreateDialogState();
}

class _ShareCreateDialogState extends State<ShareCreateDialog> {
  String _preset = '24h';
  DateTime? _customAt;
  final TextEditingController _noteCtrl = TextEditingController();
  bool _busy = false;
  bool _copied = false;
  String _error = '';
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _customAt = DateTime.now().add(const Duration(hours: 24));
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCustom() async {
    final at = _customAt ?? DateTime.now().add(const Duration(hours: 24));
    final picked = await pickShareMoment(context, initial: at);
    if (picked == null || !mounted) return;
    setState(() {
      _customAt = picked;
      _error = '';
    });
  }

  Future<void> _submit() async {
    if (_busy || _result != null) return;
    setState(() => _error = '');
    int? ttlHours;
    int? expiresAt;
    if (_preset == 'forever') {
      expiresAt = 0;
    } else if (_preset == 'custom') {
      final at = _customAt;
      if (at == null) {
        setState(() => _error = '请选择过期时间');
        return;
      }
      if (!at.isAfter(DateTime.now())) {
        setState(() => _error = '过期时间须晚于当前时间');
        return;
      }
      expiresAt = at.millisecondsSinceEpoch;
    } else {
      ttlHours = kSharePresets.firstWhere((p) => p.key == _preset).hours;
    }
    setState(() => _busy = true);
    try {
      final rec = await Api.fileShareCreate(
        path: widget.path,
        ttlHours: ttlHours,
        expiresAt: expiresAt,
        note: _noteCtrl.text,
      );
      if (!mounted) return;
      final url = (rec['url'] ?? '').toString();
      setState(() {
        _busy = false;
        if (url.isEmpty) {
          _error = '创建成功，但未返回链接';
        } else {
          _result = rec;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = shareMsgOf(e);
      });
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制链接')),
    );
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return shareDialogFrame(c, [
      Text(
        '创建临时链接',
        style: TextStyle(color: c.fg, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        widget.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c.muted, fontSize: 12),
      ),
      const SizedBox(height: 14),
      if (_result != null) ..._resultView(c, _result!) else ..._formView(c),
    ]);
  }

  List<Widget> _formView(AppColors c) {
    return [
      shareFieldLabel(c, '有效期'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in kSharePresets)
            shareChip(
              c,
              label: p.label,
              selected: _preset == p.key,
              onTap: _busy ? null : () => setState(() => _preset = p.key),
            ),
        ],
      ),
      if (_preset == 'custom') ...[
        const SizedBox(height: 12),
        shareFieldLabel(c, '过期时间'),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _customAt == null
                    ? '未选择'
                    : shareFmtTime(_customAt!.millisecondsSinceEpoch),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.fg, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _pickCustom,
              child: const Text('选择时间', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ],
      const SizedBox(height: 8),
      Text(
        _preset == 'forever'
            ? '永久有效，不会自动过期，只能手动撤销。'
            : '到期后链接自动失效。',
        style: TextStyle(color: c.muted, fontSize: 11.5),
      ),
      const SizedBox(height: 12),
      shareFieldLabel(c, '备注'),
      const SizedBox(height: 6),
      TextField(
        controller: _noteCtrl,
        enabled: !_busy,
        maxLength: 80,
        style: TextStyle(color: c.fg, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: '选填',
          hintStyle: TextStyle(color: c.muted, fontSize: 13),
          counterStyle: TextStyle(color: c.muted, fontSize: 10),
        ),
      ),
      if (_error.isNotEmpty) ...[
        Text(_error, style: TextStyle(color: c.danger, fontSize: 12)),
      ],
      const SizedBox(height: 14),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text('取消', style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(
              _busy ? '创建中…' : '创建链接',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _resultView(AppColors c, Map<String, dynamic> rec) {
    final url = (rec['url'] ?? '').toString();
    final expiresAt = shareExpiresMs(rec);
    return [
      shareFieldLabel(c, '链接'),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(
          url,
          style: TextStyle(color: c.fg, fontSize: 12, fontFamily: 'monospace'),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        (expiresAt != null && expiresAt == 0)
            ? '永久有效，不会自动过期，只能手动撤销。'
            : '有效期至 ${shareFmtTime(expiresAt ?? 0)}',
        style: TextStyle(color: c.muted, fontSize: 11.5),
      ),
      const SizedBox(height: 14),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('完成', style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: () => _copy(url),
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(
              _copied ? '已复制' : '复制链接',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    ];
  }
}

/* ---------------- 改期：改过期时刻本身（转永久 = expiresAt 0） ---------------- */

class ShareScheduleDialog extends StatefulWidget {
  const ShareScheduleDialog({super.key, required this.share});

  final Map<String, dynamic> share;

  @override
  State<ShareScheduleDialog> createState() => _ShareScheduleDialogState();
}

class _ShareScheduleDialogState extends State<ShareScheduleDialog> {
  late final bool _permanentAtOpen;
  String _mode = 'finite'; // finite / permanent
  DateTime? _at;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _permanentAtOpen = isPermanentShare(widget.share);
    _mode = _permanentAtOpen ? 'permanent' : 'finite';
    final cur = shareExpiresMs(widget.share);
    _at = (cur != null && cur > 0)
        ? DateTime.fromMillisecondsSinceEpoch(cur)
        : null;
  }

  Future<void> _pick() async {
    final at = _at ?? DateTime.now().add(const Duration(hours: 24));
    final picked = await pickShareMoment(context, initial: at);
    if (picked == null || !mounted) return;
    setState(() {
      _at = picked;
      _error = '';
    });
  }

  String _hint() {
    if (_mode == 'permanent') {
      return _permanentAtOpen
          ? '当前为永久有效，不会自动过期。'
          : '转为永久后不再自动过期，需手动撤销；之后可随时再指定过期时间。';
    }
    final at = _at;
    if (at == null) {
      return _permanentAtOpen ? '当前为永久有效：选择过期时间即转为限时。' : '';
    }
    final diff = at.difference(DateTime.now()).inMilliseconds;
    if (diff <= 0) return '该时刻已过去，请选择未来时间';
    final tip = '距现在约 ${humanDuration(diff)}';
    final cur = shareExpiresMs(widget.share) ?? 0;
    if (!_permanentAtOpen && cur > 0 && at.millisecondsSinceEpoch < cur) {
      return '$tip（比当前到期时间早，将缩短有效期）';
    }
    return tip;
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _error = '');
    if (_mode == 'permanent') {
      final ok = await confirmDialog(
        context,
        '转为永久',
        '转为永久有效后不再自动过期，只能手动撤销。确认？',
        '转为永久',
      );
      if (!ok || !mounted) return;
      await _submitBody(0);
      return;
    }
    final at = _at;
    if (at == null) {
      setState(() => _error = '请选择过期时间');
      return;
    }
    final ms = at.millisecondsSinceEpoch;
    if (!at.isAfter(DateTime.now())) {
      setState(() => _error = '过期时间须晚于当前时间');
      return;
    }
    final cur = shareExpiresMs(widget.share) ?? 0;
    if (!_permanentAtOpen && cur > 0 && ms < cur) {
      final ok = await confirmDialog(
        context,
        '缩短有效期',
        '新的过期时间早于当前，将缩短有效期。确认？',
        '确定',
      );
      if (!ok || !mounted) return;
    }
    await _submitBody(ms);
  }

  Future<void> _submitBody(int expiresAt) async {
    setState(() => _busy = true);
    try {
      final rec = await Api.fileShareUpdate(
        shareIdOf(widget.share),
        expiresAt: expiresAt,
      );
      if (!mounted) return;
      Navigator.of(context).pop(rec);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = shareMsgOf(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return shareDialogFrame(c, [
      Text(
        '改期',
        style: TextStyle(color: c.fg, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        shareDisplayName(widget.share),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c.muted, fontSize: 12),
      ),
      const SizedBox(height: 14),
      if (!_permanentAtOpen) ...[
        shareFieldLabel(c, '方式'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            shareChip(
              c,
              label: '指定时刻',
              selected: _mode == 'finite',
              onTap: _busy ? null : () => setState(() => _mode = 'finite'),
            ),
            shareChip(
              c,
              label: '转为永久',
              selected: _mode == 'permanent',
              onTap: _busy ? null : () => setState(() => _mode = 'permanent'),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      if (_mode == 'finite') ...[
        shareFieldLabel(c, '过期时间'),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _at == null
                    ? '未选择'
                    : shareFmtTime(_at!.millisecondsSinceEpoch),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.fg, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _pick,
              child: const Text('选择时间', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ],
      if (_hint().isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(_hint(), style: TextStyle(color: c.muted, fontSize: 11.5)),
      ],
      if (_error.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(_error, style: TextStyle(color: c.danger, fontSize: 12)),
      ],
      const SizedBox(height: 14),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text('取消', style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(
              _busy ? '提交中…' : '确定',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    ]);
  }
}
