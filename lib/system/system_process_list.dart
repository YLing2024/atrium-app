import 'package:flutter/material.dart';

import '../theme.dart';
import 'system_cards.dart';
import 'system_format.dart';

/* ============ 进程排行 ============ */

/// 进程排行：按名称 / 内存 / CPU 排序，含合计行（对齐 Web 表格）。
class SystemProcessList extends StatelessWidget {
  const SystemProcessList({
    super.key,
    required this.processes,
    required this.services,
    required this.totalCpu,
    required this.procSort,
    required this.onSort,
  });

  final List<Map<String, dynamic>> processes;
  final List<Map<String, dynamic>> services;
  final double? totalCpu;

  /// 当前排序键：`name` / `cpu` / 其它按内存（默认 `mem`）。
  final String procSort;
  final ValueChanged<String> onSort;

  bool _serviceUp(dynamic pid) {
    for (final s in services) {
      if ('${s['pid']}' == '$pid') {
        return s['status'] != 'down';
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sorted = List<Map<String, dynamic>>.from(processes);
    if (procSort == 'name') {
      sorted.sort((a, b) =>
          (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    } else if (procSort == 'cpu') {
      sorted.sort((a, b) => (numOr(b['cpu'])).compareTo(numOr(a['cpu'])));
    } else {
      sorted.sort((a, b) => (numOr(b['mem_mb'])).compareTo(numOr(a['mem_mb'])));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const BlockTitle('进程排行'),
            const Spacer(),
            _sortBtn(c, '名称', 'name'),
            const SizedBox(width: 4),
            _sortBtn(c, '内存', 'mem'),
            const SizedBox(width: 4),
            _sortBtn(c, 'CPU', 'cpu'),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: c.surface2,
                  border: Border.all(color: c.border),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 8),
                    Expanded(child: SystemHeadLabel('进程')),
                    SizedBox(
                      width: 56,
                      child: SystemHeadLabel('PID', right: true),
                    ),
                    SizedBox(
                      width: 64,
                      child: SystemHeadLabel('内存', right: true),
                    ),
                    SizedBox(
                      width: 60,
                      child: SystemHeadLabel('CPU', right: true),
                    ),
                  ],
                ),
              ),
              for (final p in sorted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      StatusDot(up: _serviceUp(p['pid'])),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (p['name'] ?? '-').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.fg, fontSize: 12.5),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${p['pid']}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          fmtMB(numOr(p['mem_mb'])),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: c.fg,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          '${numOr(p['cpu']).toDouble().toStringAsFixed(1)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // 合计行（对齐 Web：合计（全部进程） + CPU 列）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
                ),
                child: Row(
                  children: [
                    const StatusDot(up: true),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '合计（全部进程）',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.fg,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text('', style: TextStyle(color: c.muted, fontSize: 12)),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text('', style: TextStyle(color: c.fg, fontSize: 12)),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        totalCpu == null ? '—' : '${totalCpu!.toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: c.fg,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sortBtn(AppColors c, String label, String key) {
    final active = procSort == key;
    return InkWell(
      onTap: () => onSort(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? c.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? c.accent : c.muted,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
