import 'dart:convert';
import 'dart:io';

import 'package:ble_emergency_app/simulator/scenario.dart';

Future<void> main(List<String> args) async {
  final nodes = args.isEmpty ? 50 : int.parse(args[0]);
  final ttl = args.length < 2 ? 6 : int.parse(args[1]);
  final dedup = !args.contains('--no-dedup');
  final report = await runScenario(nodes: nodes, ttl: ttl, dedup: dedup);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
}
