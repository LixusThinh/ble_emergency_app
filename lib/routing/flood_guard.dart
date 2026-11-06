import '../core/packet.dart';

/// Packets a sender may still get through: refills at a steady rate up to a
/// burst, so a backlog carried in by another phone fits but a stream does not.
class _Bucket {
  double tokens;
  int updated;
  _Bucket(this.tokens, this.updated);
}

/// Limits what one sender, and one neighbouring link, can make this phone
/// verify, store and forward.
///
/// * Each signing key has a budget for new packets ([burst], then
///   [perMinute]); SOS has a smaller one of its own ([sosBurst],
///   [sosPerMinute]) because it jumps every queue. The budget is only spent
///   on packets whose signature checked out, so forged packets cannot use up
///   someone else's. When it is empty, that sender's packets are dropped
///   before the signature check.
/// * A link that sends [badLimit] packets that are unreadable or fail the
///   signature check within [badWindow] is ignored for [muteFor]: checking a
///   signature costs about 3 ms, so a stream of forgeries would otherwise keep
///   the phone busy.
///
/// A new key gets a full budget, so many keys still get through (no Sybil
/// defence); the store's per-sender share (see [maxPackets]) bounds what they
/// can push out.
class FloodGuard {
  final int burst, perMinute, sosBurst, sosPerMinute, badLimit;
  final Duration badWindow, muteFor;

  /// Senders whose budgets are tracked; the least recently seen are forgotten
  /// beyond this, and start again with a full budget.
  final int maxTracked;
  final int Function() _now;

  final _buckets = <String, _Bucket>{};
  final _sos = <String, _Bucket>{};
  final _bad = <String, (int, int)>{};
  final _mutedUntil = <String, int>{};

  FloodGuard({
    this.burst = 200,
    this.perMinute = 30,
    this.sosBurst = 10,
    this.sosPerMinute = 2,
    this.badLimit = 20,
    this.badWindow = const Duration(minutes: 1),
    this.muteFor = const Duration(minutes: 5),
    this.maxTracked = 2000,
    int Function()? clock,
  }) : _now = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  (Map<String, _Bucket>, int, int) _limits(MessageKind kind) =>
      kind == MessageKind.sos
      ? (_sos, sosBurst, sosPerMinute)
      : (_buckets, burst, perMinute);

  /// [origin]'s bucket for [kind], refilled up to now and moved to the
  /// most recently used end.
  _Bucket _bucket(String origin, MessageKind kind) {
    final (map, size, rate) = _limits(kind);
    final now = _now();
    final b = map.remove(origin) ?? _Bucket(size.toDouble(), now);
    b.tokens = (b.tokens + (now - b.updated) * rate / 60000).clamp(
      0.0,
      size.toDouble(),
    );
    b.updated = now;
    map[origin] = b;
    while (map.length > maxTracked) {
      map.remove(map.keys.first);
    }
    return b;
  }

  /// Whether a [kind] packet from [origin] would be admitted; spends nothing.
  bool allows(String origin, MessageKind kind) =>
      _bucket(origin, kind).tokens >= 1;

  /// Spends one packet of [origin]'s budget; false when there was none left.
  bool admit(String origin, MessageKind kind) {
    final b = _bucket(origin, kind);
    if (b.tokens < 1) {
      return false;
    }
    b.tokens -= 1;
    return true;
  }

  /// Records an unreadable or forged packet from [link].
  void bad(String link) {
    final now = _now();
    final (start, count) = _bad[link] ?? (now, 0);
    final fresh = now - start > badWindow.inMilliseconds;
    final n = fresh ? 1 : count + 1;
    _bad[link] = (fresh ? now : start, n);
    if (n >= badLimit) {
      _mutedUntil[link] = now + muteFor.inMilliseconds;
      _bad.remove(link);
    }
  }

  /// Whether frames from [link] are being ignored.
  bool muted(String link) {
    final until = _mutedUntil[link];
    if (until == null) {
      return false;
    }
    if (_now() >= until) {
      _mutedUntil.remove(link);
      return false;
    }
    return true;
  }

  /// Forgets [link] when it disconnects; a new link starts clean.
  void forget(String link) {
    _bad.remove(link);
  }
}
