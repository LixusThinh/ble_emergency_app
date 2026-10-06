import 'dart:convert';
import 'dart:io';

import 'package:ble_emergency_app/simulator/scenario.dart';

Future<void> main() async {
  final reports = <Map<String, dynamic>>[];
  for (final nodes in [50, 100]) {
    for (final ttl in [3, 6, 10]) {
      final report = await runScenario(nodes: nodes, ttl: ttl);
      reports.add(report.toJson());
      stdout.writeln(
        '$nodes nodes, TTL $ttl: ${(report.ratio * 100).toStringAsFixed(1)}%, ${report.frames} frames',
      );
    }
  }
  for (final dedup in [true, false]) {
    final report = await runScenario(nodes: 10, ttl: 6, dedup: dedup);
    reports.add(report.toJson());
    stdout.writeln('10 nodes, dedup=$dedup: ${report.frames} frames');
  }
  final result = {
    'topologySeed': 42,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'reports': reports,
  };
  await Directory('docs').create(recursive: true);
  await File('docs/simulation-results.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
}
