import 'package:flutter_test/flutter_test.dart';
import 'package:ble_emergency_app/simulator/scenario.dart';

void main() {
  test(
    'simulator runs in worker isolate and returns a transferable report',
    () async {
      final report = await runScenarioInIsolate(nodes: 10, ttl: 6);
      expect(report.nodes, 10);
      expect(report.delivered, 9);
      expect(report.ratio, 1);
      expect(report.frames, greaterThan(0));
    },
  );
}
