import 'dart:math';
import 'dart:isolate';

import '../core/identity.dart';
import '../core/packet.dart';
import '../messaging/store.dart';
import '../routing/router.dart';
import 'network.dart';

class SimulationReport {
  final int nodes, ttl, delivered, frames, duplicate, relay;
  final bool dedup;
  final Duration computeTime;
  final Map<int, int> hopDistribution;
  SimulationReport(
    this.nodes,
    this.ttl,
    this.delivered,
    this.frames,
    this.duplicate,
    this.relay,
    this.dedup,
    this.computeTime,
    this.hopDistribution,
  );
  double get ratio => delivered / (nodes - 1);
  Map<String, dynamic> toJson() => {
    'nodes': nodes,
    'ttl': ttl,
    'dedup': dedup,
    'deliveryRatio': ratio,
    'delivered': delivered,
    'frames': frames,
    'duplicatePackets': duplicate,
    'relayPackets': relay,
    'computeMs': computeTime.inMilliseconds,
    'hopDistribution': hopDistribution.map((k, v) => MapEntry('$k', v)),
    'note': 'CPU runtime; not real BLE latency. Synthetic ring + seeded shortcuts; no RF/battery model.',
  };
}

Future<SimulationReport> runScenarioInIsolate({int nodes = 50, int ttl = 6}) =>
    Isolate.run(() => runScenario(nodes: nodes, ttl: ttl));

Future<SimulationReport> runScenario({
  int nodes = 50,
  int ttl = 6,
  bool dedup = true,
}) async {
  if (nodes < 3 || nodes > 100 || ttl < 1 || ttl > 10) {
    throw ArgumentError('nodes 3..100, TTL 1..10');
  }
  final network = SimNetwork(), routers = <MeshRouter>[];
  for (var i = 0; i < nodes; i++) {
    final r = MeshRouter(
      identity: await Identity.create(),
      transport: network.node('$i'),
      store: MemoryStore(),
      name: 'Node $i',
      deduplicate: dedup,
    );
    routers.add(r);
    await r.start();
  }
  try {
    for (var i = 0; i < nodes; i++) {
      network.connect('$i', '${(i + 1) % nodes}');
    }
    final random = Random(42);
    for (var i = 0; i < nodes ~/ 2; i++) {
      final a = random.nextInt(nodes), b = random.nextInt(nodes);
      if (a != b) {
        network.connect('$a', '$b');
      }
    }
    await network.drain(routers);
    final before = network.frames;
    final beforeDuplicates = routers.fold<int>(
      0,
      (n, r) => n + r.stats.duplicate,
    );
    final beforeRelays = routers.fold<int>(0, (n, r) => n + r.stats.relayed);
    final timer = Stopwatch()..start();
    final p = await routers.first.publish(
      MessageKind.sos,
      MessageBody('SOS mô phỏng'),
      ttl: ttl,
    );
    await network.drain(routers);
    timer.stop();
    var delivered = 0;
    final hops = <int, int>{};
    for (final r in routers.skip(1)) {
      final messages = (await r.store.messages()).where(
        (m) => m.packet.messageId == p.messageId,
      );
      if (messages.isNotEmpty) {
        delivered++;
        final hop = messages.first.packet.hops;
        hops[hop] = (hops[hop] ?? 0) + 1;
      }
    }
    return SimulationReport(
      nodes,
      ttl,
      delivered,
      network.frames - before,
      routers.fold<int>(0, (n, r) => n + r.stats.duplicate) - beforeDuplicates,
      routers.fold<int>(0, (n, r) => n + r.stats.relayed) - beforeRelays,
      dedup,
      timer.elapsed,
      hops,
    );
  } finally {
    for (final r in routers) {
      await r.dispose();
    }
  }
}
