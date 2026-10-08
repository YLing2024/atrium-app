import 'package:flutter/material.dart';

import '../theme.dart';
import 'system_format.dart';

/* ============ 指标卡片 ============ */

/// 指标区：CPU / 内存 / Swap / PSI / 系统 / 网络 / 磁盘 I/O。
/// 宽屏两列，窄屏单列（对齐 Web 网格断点）。
class SystemMetricGrid extends StatelessWidget {
  const SystemMetricGrid({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cpu = data['cpu'] is Map ? data['cpu'] as Map : const {};
    final mem = data['memory'] is Map ? data['memory'] as Map : const {};
    final net = data['network'] is Map ? data['network'] as Map : const {};
    final io = data['disk_io'] is Map ? data['disk_io'] as Map : const {};
    final procs = data['processes'] is Map ? data['processes'] as Map : const {};
    final cpuUsage = pctOf(cpu['usage_percent']);
    final memPercent = pctOf(mem['percent']);

    final cpuCard = PanelCard(
      title: 'CPU',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${cpuUsage.toStringAsFixed(1)}%',
            style: TextStyle(
              color: c.fg,
              fontSize: 38,
              fontWeight: FontWeight.w200,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          MetricBar(percent: cpuUsage),
          _CoreGrid(raw: cpu['per_core']),
          const SizedBox(height: 10),
          SystemKv('型号', (cpu['model'] ?? '-').toString()),
          SystemKv('核心数', (cpu['cores'] ?? '-').toString()),
          SystemKv(
            '进程',
            '${numOr(procs['running'])} / ${numOr(procs['total'])}',
          ),
          SystemKv('负载 (1/5/15m)', fmtLoad(cpu['loadavg'])),
        ],
      ),
    );

    final memCard = PanelCard(
      title: '内存',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${memPercent.toStringAsFixed(1)}%',
            style: TextStyle(
              color: c.fg,
              fontSize: 38,
              fontWeight: FontWeight.w200,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          MetricBar(percent: memPercent),
          const SizedBox(height: 10),
          SystemKv('已用（不含缓存）', fmtBytes(numOr(mem['used']))),
          SystemKv(
            '可用',
            mem['available'] == null ? '—' : fmtBytes(numOr(mem['available'])),
          ),
          SystemKv(
            '其中缓存（可回收）',
            mem['buffCache'] == null ? '—' : fmtBytes(numOr(mem['buffCache'])),
          ),
          SystemKv(
            '剩余 / 总计',
            '${fmtBytes(numOr(mem['free']))} / ${fmtBytes(numOr(mem['total']))}',
          ),
        ],
      ),
    );

    // Swap 卡（对齐 Web）：无 swap 时显示 0% + 备注
    final swapTotal = numOr(mem['swapTotal']);
    final hasSwap = swapTotal > 0;
    final zram =
        mem['zram'] is Map ? Map<String, dynamic>.from(mem['zram'] as Map) : null;
    final swapPercent = pctOf(mem['swapPercent']);
    final swapCard = PanelCard(
      title: 'Swap',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasSwap ? '${swapPercent.toStringAsFixed(1)}%' : '0%',
            style: TextStyle(
              color: hasSwap ? c.fg : c.muted,
              fontSize: 38,
              fontWeight: FontWeight.w200,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          MetricBar(percent: hasSwap ? swapPercent : 0),
          const SizedBox(height: 10),
          if (hasSwap) ...[
            SystemKv('已用', fmtBytes(numOr(mem['swapUsed']))),
            SystemKv(
              '剩余 / 总计',
              '${fmtBytes(numOr(mem['swapFree']))} / ${fmtBytes(numOr(mem['swapTotal']))}',
            ),
            SystemKv(
              zram == null ? 'zram' : 'zram (${zram['algorithm'] ?? 'lz4'})',
              zram == null
                  ? '无'
                  : '${fmtBytes(numOr(zram['used']))} / ${fmtBytes(numOr(zram['total']))}',
            ),
          ] else ...[
            const SystemKv('zram', '无'),
            const SystemKv('备注', '本机未配置 swap'),
          ],
        ],
      ),
    );

    // PSI 压力卡（对齐 Web）：some/full avg10，压力越大越警示
    final psi = data['psi'] is Map ? data['psi'] as Map : const {};
    final psiCard = PanelCard(
      title: 'PSI 压力',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PsiRow('内存 (memory)', psi['memory']),
          _PsiRow('CPU', psi['cpu']),
          _PsiRow('I/O', psi['io']),
          const SystemKv('说明', 'avg10 压力 · some/full'),
        ],
      ),
    );

    final sysCard = PanelCard(
      title: '系统',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SystemKv('主机名', (data['hostname'] ?? '-').toString()),
          SystemKv('操作系统', (data['os'] ?? '-').toString()),
          SystemKv(
            '运行时长',
            fmtUptime(data['uptime'] is num ? data['uptime'] as num : null),
          ),
        ],
      ),
    );

    final netCard = PanelCard(
      title: '网络',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SystemKv(
            '↓ 下载',
            fmtRate(net['rx_rate'] is num ? net['rx_rate'] as num : null),
            amber: true,
          ),
          SystemKv(
            '↑ 上传',
            fmtRate(net['tx_rate'] is num ? net['tx_rate'] as num : null),
          ),
          SystemKv('累计下载', fmtBytes(numOr(net['rx_bytes']))),
          SystemKv('累计上传', fmtBytes(numOr(net['tx_bytes']))),
        ],
      ),
    );

    final ioCard = PanelCard(
      title: '磁盘 I/O',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SystemRateStat(
                  '读',
                  fmtRate(io['read_rate'] is num ? io['read_rate'] as num : null),
                  amber: true,
                ),
              ),
              const SystemVDivider(),
              Expanded(
                child: SystemRateStat(
                  '写',
                  fmtRate(io['write_rate'] is num ? io['write_rate'] as num : null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SystemRateStat('累计读', fmtBytes(numOr(io['read_bytes'])))),
              const SystemVDivider(),
              Expanded(child: SystemRateStat('累计写', fmtBytes(numOr(io['write_bytes'])))),
            ],
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: [
              cpuCard,
              const SizedBox(height: 12),
              memCard,
              const SizedBox(height: 12),
              swapCard,
              const SizedBox(height: 12),
              psiCard,
              const SizedBox(height: 12),
              sysCard,
              const SizedBox(height: 12),
              netCard,
              const SizedBox(height: 12),
              ioCard,
            ],
          );
        }
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cpuCard),
                const SizedBox(width: 12),
                Expanded(child: memCard),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: swapCard),
                const SizedBox(width: 12),
                Expanded(child: psiCard),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: sysCard),
                const SizedBox(width: 12),
                Expanded(child: netCard),
              ],
            ),
            const SizedBox(height: 12),
            ioCard,
          ],
        );
      },
    );
  }
}

/// 每核负载网格（对齐 Web CoreGrid）：per_core 缺失或空数组时整块不渲染，
/// 窄屏按可用宽度自动换列，不产生横向滚动。
class _CoreGrid extends StatelessWidget {
  const _CoreGrid({required this.raw});

  final dynamic raw;

  @override
  Widget build(BuildContext context) {
    final cores =
        raw is List ? raw.whereType<Map>().toList(growable: false) : const [];
    if (cores.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final width = constraints.maxWidth;
          final cols = width < 300 ? 2 : (width < 460 ? 3 : 4);
          final itemW = (width - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < cores.length; i++)
                SizedBox(
                  width: itemW,
                  child: _CoreCell(raw: cores[i], index: i),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CoreCell extends StatelessWidget {
  const _CoreCell({required this.raw, required this.index});

  final dynamic raw;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final core = raw is Map ? raw : const {};
    final id = core['id'] ?? index;
    final percent = pctOf(core['usage_percent']).clamp(0.0, 100.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '#$id',
              style: TextStyle(
                color: c.muted,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Text(
              '${percent.toStringAsFixed(1)}%',
              style: TextStyle(
                color: c.fg,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        // 颜色分级复用 MetricBar 规则（>80 红 / 60-80 橙 / <60 绿）
        MetricBar(percent: percent, height: 3),
      ],
    );
  }
}

/* ============ 磁盘区 ============ */

/// 磁盘区：有 disks 列表时每块盘一张卡，缺失/空时回退旧单盘卡（不白屏）
class SystemDiskSection extends StatelessWidget {
  const SystemDiskSection({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final raw = data['disks'];
    final disks = raw is List
        ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : <Map<String, dynamic>>[];
    if (disks.isEmpty) return _DiskCard(diskRaw: data['disk']);
    return Column(
      children: [
        for (var i = 0; i < disks.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _DiskCard(
            diskRaw: disks[i],
            title: (disks[i]['mount'] ?? '').toString().trim().isEmpty
                ? '磁盘'
                : '磁盘 ${(disks[i]['mount']).toString().trim()}',
          ),
        ],
      ],
    );
  }
}

class _DiskCard extends StatelessWidget {
  const _DiskCard({required this.diskRaw, this.title = '磁盘'});

  final dynamic diskRaw;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final disk = diskRaw is Map ? diskRaw : null;
    if (disk == null) return const SizedBox.shrink();
    final percent = pctOf(disk['percent']);
    return PanelCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '已用 ${fmtBytes(numOr(disk['used']))}',
                style: TextStyle(
                  color: c.fg,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${percent.toStringAsFixed(0)}% · 共 ${fmtBytes(numOr(disk['total']))}',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          MetricBar(percent: percent),
          const SizedBox(height: 10),
          SystemKv(
            '剩余 / 总',
            '${fmtBytes(numOr(disk['free']))} / ${fmtBytes(numOr(disk['total']))}',
          ),
        ],
      ),
    );
  }
}

/* ============ 通用小组件 ============ */

/// PSI 行（对齐 Web PsiRow）：显示 some/full 的 avg10，压力越大越警示
class _PsiRow extends StatelessWidget {
  const _PsiRow(this.label, this.raw);

  final String label;
  final dynamic raw;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final o = raw is Map ? raw : null;
    final some = (o != null && o['some'] is Map) ? o['some'] as Map : null;
    if (some == null) return SystemKv(label, '—');
    final full = o!['full'] is Map ? o['full'] as Map : null;
    final s = pctOf(some['avg10']);
    final text = 'some ${s.toStringAsFixed(1)}% · '
        'full ${full == null ? '—' : '${pctOf(full['avg10']).toStringAsFixed(1)}%'}';
    return SystemKv(
      label,
      text,
      color: s >= 50 ? c.danger : (s >= 30 ? c.warn : null),
    );
  }
}

class SystemKv extends StatelessWidget {
  const SystemKv(
    this.label,
    this.value, {
    super.key,
    this.amber = false,
    this.color,
  });

  final String label;
  final String value;
  final bool amber;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color ?? (amber ? c.accent : c.fg),
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SystemRateStat extends StatelessWidget {
  const SystemRateStat(this.label, this.value, {super.key, this.amber = false});

  final String label;
  final String value;
  final bool amber;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: amber ? c.accent : c.fg,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class SystemHeadLabel extends StatelessWidget {
  const SystemHeadLabel(this.text, {super.key, this.right = false});

  final String text;
  final bool right;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        color: c.muted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class SystemVDivider extends StatelessWidget {
  const SystemVDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: c.border,
    );
  }
}
