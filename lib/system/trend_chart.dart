import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../trend_granularity.dart';
import 'system_format.dart';
import 'system_granularity.dart';

/* ============ 趋势图（纯 CustomPainter，无图表库，对齐 Web 手写 SVG） ============ */

/// 趋势线配色（对齐 Web CSS 变量）：accent 琥珀 / muted 中性灰 / ok 绿 / danger 红
enum TrendTone { accent, muted, ok, danger }

Color _toneColor(AppColors c, TrendTone tone) {
  switch (tone) {
    case TrendTone.accent:
      return c.accent;
    case TrendTone.muted:
      return c.muted;
    case TrendTone.ok:
      return c.ok;
    case TrendTone.danger:
      return c.danger;
  }
}

class TrendSeries {
  final String key;
  final String label;
  final TrendTone tone;
  const TrendSeries(this.key, this.label, {this.tone = TrendTone.muted});
}

/// 趋势图平移位置记忆：键 `档位:图 id`。App 会话内有效，退出即失效（对齐 Web 模块级
/// `chartViewMemory`）。R8：切档不串位、切回保留。
final Map<String, ({int offset, bool follow})> _trendViewMemory = {};

class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.title,
    required this.chartId,
    required this.granularity,
    required this.history,
    required this.series,
    this.yMax,
    this.yLabel = '',
    this.recordedMinutes,
    required this.fmtValue,
  });

  final String title;

  /// 图标识（mem / psi / net / io）：平移位置按（档位 + 图）分别记忆。
  final String chartId;

  /// 当前粒度档位：决定窗口（秒 30 / 非秒 60）、X 轴刻度与稀疏渲染。
  final TrendGranularity granularity;

  final List<Map<String, dynamic>> history;
  final List<TrendSeries> series;
  final double? yMax;
  final String yLabel;

  /// 非秒档「数据积累中（已记录 N 分钟）」的 N；null 按 0。
  final int? recordedMinutes;

  final String Function(num) fmtValue;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int _offset = 0;
  // 跟随最新：初始为 true；用户平移离开最新后关闭，拖回末尾或点「回最新」恢复
  bool _follow = true;

  int get _window => trendWindow(widget.granularity);

  bool get _sparse => widget.granularity != TrendGranularity.sec;

  /// 平移记忆键：仅非秒档记忆（对齐 Web `memoryKey`，秒档返回 null，不读不写）。
  String? get _memoryKey => widget.granularity == TrendGranularity.sec
      ? null
      : '${trendGranularityId(widget.granularity)}:${widget.chartId}';

  @override
  void initState() {
    super.initState();
    _restoreView();
  }

  @override
  void didUpdateWidget(covariant TrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.granularity != widget.granularity ||
        oldWidget.chartId != widget.chartId) {
      _restoreView(); // 切档：恢复该（档位 + 图）上次的平移位置
    }
  }

  /// 秒档不参与平移记忆：重置为跟随最新，切回秒档仍是跟随态（R5）。
  void _restoreView() {
    final key = _memoryKey;
    if (key == null) {
      _offset = 0;
      _follow = true;
      return;
    }
    final m = _trendViewMemory[key];
    _offset = m?.offset ?? 0;
    _follow = m?.follow ?? true;
  }

  /// 秒档不写平移记忆（对齐 Web `remember` 里的 `if (memoryKey)`）。
  void _remember(int offset, bool follow) {
    final key = _memoryKey;
    if (key == null) return;
    _trendViewMemory[key] = (offset: offset, follow: follow);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final history = widget.history;
    final len = history.length;

    final slice = computeTrendSlice(
      len: len,
      window: _window,
      offset: _offset,
      follow: _follow,
    );
    _offset = slice.offset;
    _remember(slice.offset, _follow);
    final points = history.sublist(slice.start, slice.end);

    // 秒档不足 2 点仍是「采集中」占位；非秒档 0 点才占位（单点要能看见）
    final placeholder = _sparse ? len == 0 : len < 2;

    return PanelCard(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final s in widget.series)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _toneColor(c, s.tone),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        s.label,
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _latest(s.key),
                        style: TextStyle(color: c.fg, fontSize: 11),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (placeholder)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  _sparse
                      ? trendAccumulatingText(widget.recordedMinutes)
                      : '数据采集中…（约 3 秒后显示趋势）',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 160,
              child: ClipRect(
                child: GestureDetector(
                  onHorizontalDragEnd: (_) {},
                  onHorizontalDragUpdate: (d) {
                    if (len <= _window) return;
                    final maxOffset = len - _window;
                    final next = (_offset - (d.primaryDelta! / 6).round())
                        .clamp(0, maxOffset);
                    final following = next >= maxOffset;
                    setState(() {
                      _offset = next;
                      // 拖回最末窗口即恢复跟随
                      _follow = following;
                    });
                    _remember(next, following);
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _TrendPainter(
                      points: points,
                      series: widget.series,
                      yMax: widget.yMax,
                      yLabel: widget.yLabel,
                      fmtValue: widget.fmtValue,
                      granularity: widget.granularity,
                      c: c,
                    ),
                  ),
                ),
              ),
            ),
            if (!_follow && len > _window)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: InkWell(
                    onTap: () {
                      final next = math.max(0, len - _window);
                      setState(() {
                        _follow = true;
                        _offset = next;
                      });
                      _remember(next, true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.accentBorder),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '回最新',
                        style: TextStyle(color: c.accent, fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _latest(String key) {
    final h = widget.history;
    if (h.isEmpty) return '';
    final v = h.last[key];
    return v is num ? widget.fmtValue(v) : '';
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.series,
    required this.yMax,
    required this.yLabel,
    required this.fmtValue,
    required this.granularity,
    required this.c,
  });

  final List<Map<String, dynamic>> points;
  final List<TrendSeries> series;
  final double? yMax;
  final String yLabel;
  final String Function(num) fmtValue;
  final TrendGranularity granularity;
  final AppColors c;

  static const double _l = 52, _r = 12, _t = 12, _b = 24;

  double _niceMax(double v) {
    if (v <= 0) return 1;
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final f = v / exp;
    double nf;
    if (f <= 1) {
      nf = 1;
    } else if (f <= 2) {
      nf = 2;
    } else if (f <= 5) {
      nf = 5;
    } else {
      nf = 10;
    }
    return nf * exp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final plotW = w - _l - _r;
    final plotH = h - _t - _b;
    if (plotW <= 0 || plotH <= 0 || points.isEmpty) return;

    final gridPaint = Paint()
      ..color = c.border.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final textStyle = TextStyle(color: c.muted, fontSize: 9, fontFeatures: const [FontFeature.tabularFigures()]);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    double maxV;
    bool percentChart;
    if (yMax != null) {
      maxV = yMax!;
      percentChart = true;
    } else {
      var m = 0.0;
      for (final p in points) {
        for (final s in series) {
          final v = p[s.key];
          if (v is num) m = math.max(m, v.toDouble());
        }
      }
      maxV = _niceMax(m);
      percentChart = false;
    }

    final nTicks = percentChart ? 4 : 5;
    for (var i = 0; i < nTicks; i++) {
      final ratio = i / (nTicks - 1);
      final y = _t + plotH * (1 - ratio);
      canvas.drawLine(Offset(_l, y), Offset(_l + plotW, y), gridPaint);
      final val = maxV * ratio;
      final label = percentChart
          ? '${val.round()}$yLabel'
          : fmtValue(val.toDouble());
      textPainter.text = TextSpan(text: label, style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(_l - textPainter.width - 6, y - textPainter.height / 2));
    }

    // X 轴时间标签：首/1/3/2/3/尾；刻度格式随档位（秒 HH:mm:ss / 分钟 HH:mm / 小时 MM-DD HH:00 / 天 MM-DD）
    final single = points.length == 1;
    double xAt(int i) => single
        ? _l + plotW / 2
        : _l + plotW * (i / (points.length - 1));
    for (final i in trendTickIndices(points.length)) {
      final ts = points[i]['ts'];
      final x = xAt(i);
      textPainter.text = TextSpan(text: formatTrendTick(ts, granularity), style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, _t + plotH + 4));
    }

    for (final s in series) {
      final tone = _toneColor(c, s.tone);
      if (single) {
        // 稀疏单点：画点 + 水平虚线参考线（对齐 Web .chart-line-single）
        final v = points[0][s.key];
        if (v is! num) continue;
        final y = _t + plotH * (1 - (v.toDouble().clamp(0, maxV) / maxV));
        _dashedLine(
          canvas,
          Offset(_l, y),
          Offset(_l + plotW, y),
          Paint()
            ..color = tone
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(Offset(xAt(0), y), 3, Paint()..color = tone);
        continue;
      }
      final linePaint = Paint()
        ..color = tone
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      var first = true;
      for (var i = 0; i < points.length; i++) {
        final v = points[i][s.key];
        if (v is! num) continue;
        final x = xAt(i);
        final y = _t + plotH * (1 - (v.toDouble().clamp(0, maxV) / maxV));
        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      if (!first) canvas.drawPath(path, linePaint);
    }
  }

  /// 水平虚线（段长 4、间隔 3，对齐 Web `stroke-dasharray: 4 3`）
  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 3.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d = end + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points ||
      old.c != c ||
      old.yMax != yMax ||
      old.granularity != granularity;
}

/* ============ 趋势区（标题 + 粒度切换 + 四张图） ============ */

/// 趋势区：秒档用实时 history，非秒档用聚合点；粒度切换与平移记忆在子组件内。
class SystemTrendBlock extends StatelessWidget {
  const SystemTrendBlock({
    super.key,
    required this.granularity,
    required this.history,
    required this.recordedMinutes,
    required this.onSelect,
  });

  final TrendGranularity granularity;
  final List<Map<String, dynamic>> history;
  final int? recordedMinutes;
  final ValueChanged<TrendGranularity> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const BlockTitle('趋势'),
            const Spacer(),
            SystemGranularityBar(
              granularity: granularity,
              onSelect: onSelect,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TrendChart(
          title: 'CPU / 内存 / Swap（%）',
          chartId: 'mem',
          granularity: granularity,
          recordedMinutes: recordedMinutes,
          history: history,
          series: const [
            TrendSeries('cpu', 'CPU', tone: TrendTone.muted),
            TrendSeries('mem_percent', '物理内存', tone: TrendTone.accent),
            TrendSeries('swap_percent', 'Swap', tone: TrendTone.ok),
          ],
          yMax: 100,
          yLabel: '%',
          fmtValue: (v) => '${v.toStringAsFixed(1)}%',
        ),
        const SizedBox(height: 12),
        TrendChart(
          title: 'PSI 压力 · some avg10（%）',
          chartId: 'psi',
          granularity: granularity,
          recordedMinutes: recordedMinutes,
          history: history,
          series: const [
            TrendSeries('psi_mem_avg10', '内存', tone: TrendTone.danger),
            TrendSeries('psi_cpu_avg10', 'CPU', tone: TrendTone.accent),
            TrendSeries('psi_io_avg10', 'I/O', tone: TrendTone.muted),
          ],
          yMax: 100,
          yLabel: '%',
          fmtValue: (v) => '${v.toStringAsFixed(1)}%',
        ),
        const SizedBox(height: 12),
        TrendChart(
          title: '网速（/s）',
          chartId: 'net',
          granularity: granularity,
          recordedMinutes: recordedMinutes,
          history: history,
          series: const [
            TrendSeries('net_rx_rate', '↓ 下载', tone: TrendTone.accent),
            TrendSeries('net_tx_rate', '↑ 上传', tone: TrendTone.muted),
          ],
          fmtValue: (v) => fmtRate(v),
        ),
        const SizedBox(height: 12),
        TrendChart(
          title: '磁盘 I/O（/s）',
          chartId: 'io',
          granularity: granularity,
          recordedMinutes: recordedMinutes,
          history: history,
          series: const [
            TrendSeries('disk_io_read', '读', tone: TrendTone.accent),
            TrendSeries('disk_io_write', '写', tone: TrendTone.muted),
          ],
          fmtValue: (v) => fmtRate(v),
        ),
      ],
    );
  }
}
