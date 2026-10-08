import 'package:flutter/material.dart';

import '../theme.dart';
import '../trend_granularity.dart';

/// 粒度分段按钮组：直角、发丝线分隔，选中档位单琥珀点缀（对齐 Web .granularity）
class SystemGranularityBar extends StatelessWidget {
  const SystemGranularityBar({
    super.key,
    required this.granularity,
    required this.onSelect,
  });

  final TrendGranularity granularity;
  final ValueChanged<TrendGranularity> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const options = TrendGranularity.values;
    return Semantics(
      container: true,
      label: '趋势粒度',
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++)
              _granularityBtn(c, options[i], first: i == 0),
          ],
        ),
      ),
    );
  }

  Widget _granularityBtn(
    AppColors c,
    TrendGranularity g, {
    required bool first,
  }) {
    final active = granularity == g;
    return InkWell(
      onTap: () => onSelect(g),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? c.accentSoft : Colors.transparent,
          border: first
              ? null
              : Border(left: BorderSide(color: c.border, width: 0.5)),
        ),
        child: Text(
          trendGranularityLabel(g),
          style: TextStyle(
            color: active ? c.accent : c.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}
