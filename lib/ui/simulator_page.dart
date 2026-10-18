import 'package:flutter/material.dart';

import '../simulator/scenario.dart';
import 'theme.dart';
import 'widgets.dart';

class SimulatorPage extends StatefulWidget {
  const SimulatorPage({super.key});
  @override
  State<SimulatorPage> createState() => _SimulatorPageState();
}

class _SimulatorPageState extends State<SimulatorPage> {
  double nodes = 50, ttl = 6;
  bool busy = false;
  SimulationReport? report;
  String? error;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
    children: [
      const PageTitle(
        'Phòng mô phỏng',
        subtitle: 'Chạy cùng bộ định tuyến và mã hóa của ứng dụng thật trên mạng vòng có thêm liên kết ngẫu nhiên.',
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SliderRow(
                label: '${nodes.toInt()} thiết bị ảo',
                icon: Icons.devices_other,
                value: nodes,
                min: 10,
                max: 100,
                onChanged: busy ? null : (v) => setState(() => nodes = v),
              ),
              const SizedBox(height: 8),
              _SliderRow(
                label: 'Giới hạn ${ttl.toInt()} chặng',
                icon: Icons.alt_route,
                value: ttl,
                min: 1,
                max: 10,
                onChanged: busy ? null : (v) => setState(() => ttl = v),
              ),
              const SizedBox(height: 8),
              const Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Tag('Chống trùng'),
                  _Tag('Ưu tiên SOS'),
                  _Tag('Phân mảnh BLE'),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: busy ? null : _run,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(busy ? 'Đang chạy…' : 'Chạy đánh giá'),
              ),
            ],
          ),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(error!, style: const TextStyle(color: red)),
        ),
      if (report != null) ...[const SizedBox(height: 6), _Result(report!)],
      const SizedBox(height: 14),
      const Text(
        'Kết quả mô phỏng không đo độ trễ vô tuyến, tầm phủ hoặc pin. Các số đo này cần 3–5 điện thoại thật.',
        style: TextStyle(fontSize: 12, color: muted, height: 1.5),
      ),
    ],
  );
  Future<void> _run() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await runScenarioInIsolate(
        nodes: nodes.toInt(),
        ttl: ttl.toInt(),
      );
      if (mounted) {
        setState(() => report = result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value, min, max;
  final ValueChanged<double>? onChanged;
  const _SliderRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 18, color: teal),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: 9,
        onChanged: onChanged,
      ),
    ],
  );
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: tealSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check, size: 14, color: teal),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: teal,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _Result extends StatelessWidget {
  final SimulationReport report;
  const _Result(this.report);
  @override
  Widget build(BuildContext context) {
    final others = report.nodes - 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TỶ LỆ NHẬN SOS',
              style: TextStyle(
                letterSpacing: 1.2,
                color: teal,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(report.ratio * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${report.delivered}/$others thiết bị nhận',
                    style: const TextStyle(color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: report.ratio,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: tealSoft,
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.9,
              children: [
                StatTile(
                  value: '${report.frames}',
                  label: 'BLE frame đã gửi',
                  icon: Icons.bluetooth,
                ),
                StatTile(
                  value: '${report.relay}',
                  label: 'Lượt chuyển tiếp',
                  icon: Icons.repeat,
                ),
                StatTile(
                  value: '${report.duplicate}',
                  label: 'Gói trùng bị bỏ',
                  icon: Icons.filter_alt_outlined,
                ),
                StatTile(
                  value: '${report.computeTime.inMilliseconds} ms',
                  label: 'Thời gian xử lý',
                  icon: Icons.timer_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Số thiết bị nhận theo số chặng',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            ...report.hopDistribution.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 62,
                      child: Text(
                        '${e.key} chặng',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: e.value / others,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(5),
                        backgroundColor: canvas,
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${e.value}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
