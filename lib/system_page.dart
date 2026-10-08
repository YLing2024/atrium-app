import 'package:flutter/material.dart';

import 'system/system_cards.dart';
import 'system/system_controller.dart';
import 'system/system_process_list.dart';
import 'system/system_format.dart';
import 'system/trend_chart.dart';
import 'theme.dart';
import 'trend_granularity.dart';

export 'system/trend_chart.dart';

/// 系统监控页：SSE 实时快照 + 趋势聚合。状态与逻辑都在 [SystemController]，
/// 这里只负责组合与生命周期（对齐 Web System.jsx）。
class SystemPage extends StatefulWidget {
  const SystemPage({super.key, this.active = true});

  /// 是否处于可见 Tab：SSE 仅在激活时建连，切走立即断开（对齐 Web System.jsx）
  final bool active;

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
  final SystemController _c = SystemController();

  @override
  void initState() {
    super.initState();
    _c.setActive(widget.active);
  }

  @override
  void didUpdateWidget(covariant SystemPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _c.setActive(widget.active);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final data = _c.data;
        return RefreshIndicator(
          onRefresh: () async => _c.reconnect(),
          color: c.accent,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  const Spacer(),
                  Text(
                    '系统监控',
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
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.center,
                child: Text(
                  _c.updated == null
                      ? '更新于 --'
                      : '更新于 ${fmtClock(_c.updated!)}',
                  style: TextStyle(color: c.muted, fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),
              if (_c.error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: c.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _c.error!,
                          style: TextStyle(color: c.danger, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              if (data == null)
                const Padding(
                  padding: EdgeInsets.only(top: 140),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                SystemMetricGrid(data: data),
                const SizedBox(height: 12),
                SystemDiskSection(data: data),
                if (_c.processes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SystemProcessList(
                    processes: _c.processes,
                    services: _c.services,
                    totalCpu: _c.totalCpu,
                    procSort: _c.procSort,
                    onSort: _c.setProcSort,
                  ),
                ],
                const SizedBox(height: 12),
                SystemTrendBlock(
                  granularity: _c.granularity,
                  history: _c.granularity == TrendGranularity.sec
                      ? _c.history
                      : _c.granPoints,
                  recordedMinutes: _c.granRecordedMinutes,
                  onSelect: _c.selectGranularity,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
