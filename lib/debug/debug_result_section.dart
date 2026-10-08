import 'package:flutter/material.dart';

import '../debug_tools.dart';
import '../notification_model.dart';
import '../theme.dart';
import 'debug_common.dart';
import 'debug_controller.dart';

/// 「调用结果」：最近一次测试通知的状态码、响应体与发生时间。
class DebugResultSection extends StatelessWidget {
  const DebugResultSection({super.key, required this.result});

  final DebugCallResult? result;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = result;
    if (r == null) {
      return Text('尚无调用', style: TextStyle(color: c.muted, fontSize: 13));
    }
    final ok = r.status >= 200 && r.status < 300;
    final statusText = r.status > 0 ? 'HTTP ${r.status}' : 'HTTP —';
    final body = r.body.isEmpty ? '(空响应体)' : r.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              ok ? '成功' : '失败',
              style: TextStyle(
                color: ok ? c.ok : c.danger,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              statusText,
              style: TextStyle(
                color: c.fg,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const Spacer(),
            Text(
              formatNotificationTime(r.at),
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        debugCodeBox(c, truncateDebugText(body), color: c.fg),
      ],
    );
  }
}
