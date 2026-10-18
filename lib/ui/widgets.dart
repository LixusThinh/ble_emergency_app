import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../core/packet.dart';
import '../messaging/store.dart';
import 'theme.dart';

String clock(int timestamp) {
  final t = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String senderName(AppController c, StoredMessage m) => m.outgoing
    ? 'Bạn'
    : c.router?.contacts[m.senderId]?.name ??
          'Thiết bị ${m.senderId.substring(0, 6)}';

const _palette = [
  Color(0xff0a7c7e),
  Color(0xff3b5bdb),
  Color(0xffc2410c),
  Color(0xff7c3aed),
  Color(0xff15803d),
  Color(0xffb45309),
];

/// Stable per-node colour so the same sender looks the same on every screen.
Color colorFor(String id) =>
    _palette[id.codeUnits.fold(0, (a, b) => a + b) % _palette.length];

String initials(String name) {
  final letters = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => RegExp(r'^\p{L}', unicode: true).hasMatch(w))
      .take(2)
      .map((w) => w.characters.first.toUpperCase())
      .join();
  return letters.isEmpty ? '?' : letters;
}

class Avatar extends StatelessWidget {
  final String id, name;
  final double size;
  const Avatar({
    super.key,
    required this.id,
    required this.name,
    this.size = 40,
  });
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: size / 2,
    backgroundColor: colorFor(id).withValues(alpha: .14),
    child: Text(
      initials(name),
      style: TextStyle(
        color: colorFor(id),
        fontWeight: FontWeight.w800,
        fontSize: size * .36,
      ),
    ),
  );
}

class PageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const PageTitle(this.title, {super.key, this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle!,
              style: const TextStyle(color: muted, fontSize: 13, height: 1.45),
            ),
          ),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class CountBadge extends StatelessWidget {
  final int count;
  const CountBadge(this.count, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: tealSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$count',
      style: const TextStyle(color: teal, fontWeight: FontWeight.w800),
    ),
  );
}

class StatTile extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: canvas,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: teal),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          maxLines: 2,
          style: const TextStyle(fontSize: 11.5, color: muted, height: 1.25),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: tealSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: teal, size: 30),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              detail!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12.5, height: 1.4),
            ),
          ),
      ],
    ),
  );
}

/// Small status dot; a ring pulses out of it while [active].
class PulseDot extends StatefulWidget {
  final Color color;
  final bool active;
  const PulseDot({super.key, required this.color, this.active = true});
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PulseDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active) {
      if (!_pulse.isAnimating) {
        _pulse.repeat();
      }
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 16,
    child: Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, _) => Container(
            width: 8 + 8 * _pulse.value,
            height: 8 + 8 * _pulse.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: .4 * (1 - _pulse.value)),
            ),
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
          ),
        ),
      ],
    ),
  );
}

/// Round SOS button; rings ripple out while it can be pressed.
class SosButton extends StatefulWidget {
  final VoidCallback? onPressed;
  const SosButton({super.key, this.onPressed});
  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with SingleTickerProviderStateMixin {
  late final _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool get _on => widget.onPressed != null;
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SosButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_on) {
      if (!_ripple.isAnimating) {
        _ripple.repeat();
      }
    } else {
      _ripple
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Gửi tín hiệu SOS',
    child: SizedBox(
      width: 236,
      height: 236,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_on)
            for (final shift in [0.0, .5])
              AnimatedBuilder(
                animation: _ripple,
                builder: (_, _) {
                  final t = (_ripple.value + shift) % 1;
                  return Container(
                    width: 168 + 68 * t,
                    height: 168 + 68 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: red.withValues(alpha: .16 * (1 - t)),
                    ),
                  );
                },
              ),
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: _on
                  ? [
                      BoxShadow(
                        color: red.withValues(alpha: .28),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: ElevatedButton(
              key: const ValueKey('sos-button'),
              onPressed: widget.onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xffe6ecec),
                disabledForegroundColor: muted,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: CircleBorder(
                  side: BorderSide(color: _on ? Colors.white : line, width: 5),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sos, size: 64),
                  Text(
                    _on ? 'GỬI CỨU TRỢ' : 'CHƯA BẬT MẠNG',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
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

class GpsRow extends StatelessWidget {
  final StoredMessage m;
  const GpsRow(this.m, {super.key});
  @override
  Widget build(BuildContext context) {
    final coords =
        '${m.latitude!.toStringAsFixed(6)}, ${m.longitude!.toStringAsFixed(6)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.place, color: red, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              coords,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            ),
          ),
          IconButton(
            tooltip: 'Sao chép tọa độ',
            iconSize: 18,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: coords));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép tọa độ')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }
}

/// Delivery state of a message; outgoing broadcasts have no network-wide ACK.
class DeliveryStatus extends StatelessWidget {
  final StoredMessage m;
  final Color color;
  const DeliveryStatus(this.m, {super.key, required this.color});
  @override
  Widget build(BuildContext context) {
    final (icon, text) = !m.outgoing
        ? (Icons.verified_outlined, '${m.packet.hops} chặng • chữ ký hợp lệ')
        : m.acknowledged
        ? (Icons.done_all, 'Người nhận đã xác nhận')
        : m.packet.broadcast
        ? (Icons.cell_tower, 'Đã phát • tự gửi tiếp khi gặp thiết bị')
        : (Icons.schedule, 'Đang chờ xác nhận người nhận');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: TextStyle(fontSize: 11, color: color)),
        ),
      ],
    );
  }
}

/// One message in the chat list: SOS and safe reports as cards, chat as bubbles.
class MessageBubble extends StatelessWidget {
  final AppController c;
  final StoredMessage m;
  const MessageBubble({super.key, required this.c, required this.m});
  @override
  Widget build(BuildContext context) {
    final name = senderName(c, m), kind = m.packet.kind;
    if (kind == MessageKind.sos || kind == MessageKind.safe) {
      final sos = kind == MessageKind.sos, tint = sos ? red : teal;
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sos ? redSoft : tealSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: tint.withValues(alpha: .25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sos ? 'SOS' : 'AN TOÀN',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, color: tint),
                  ),
                ),
                Text(
                  clock(m.packet.timestamp),
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              m.text,
              style: const TextStyle(
                fontSize: 15.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (m.latitude != null) ...[const SizedBox(height: 10), GpsRow(m)],
            const SizedBox(height: 8),
            DeliveryStatus(m, color: tint.withValues(alpha: .85)),
          ],
        ),
      );
    }
    final out = m.outgoing, meta = out ? Colors.white70 : muted;
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .8,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: out ? teal : Colors.white,
            border: out ? null : Border.all(color: line),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(out ? 18 : 4),
              bottomRight: Radius.circular(out ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!out)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    name,
                    style: TextStyle(
                      color: colorFor(m.senderId),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              Text(
                m.text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: out ? Colors.white : ink,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (kind == MessageKind.privateChat) ...[
                    Icon(Icons.lock, size: 12, color: meta),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    clock(m.packet.timestamp),
                    style: TextStyle(fontSize: 11, color: meta),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: DeliveryStatus(m, color: meta)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact one-line row for the dashboard's recent activity.
class MessageTile extends StatelessWidget {
  final AppController c;
  final StoredMessage m;
  final VoidCallback onTap;
  const MessageTile({
    super.key,
    required this.c,
    required this.m,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final (icon, tint) = switch (m.packet.kind) {
      MessageKind.sos => (Icons.campaign_rounded, red),
      MessageKind.safe => (Icons.verified_user_outlined, teal),
      MessageKind.privateChat => (Icons.lock_outline, const Color(0xff3b5bdb)),
      _ => (Icons.chat_bubble_outline, teal),
    };
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: tint.withValues(alpha: .12),
          child: Icon(icon, color: tint, size: 20),
        ),
        title: Text(
          senderName(c, m),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(m.text, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(
          clock(m.packet.timestamp),
          style: const TextStyle(fontSize: 11, color: muted),
        ),
      ),
    );
  }
}

/// Full-screen-style alert shown on the phone that receives an SOS.
class SosAlert extends StatelessWidget {
  final String name;
  final StoredMessage m;
  const SosAlert({super.key, required this.name, required this.m});
  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: red,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.campaign_rounded, color: Colors.white, size: 40),
              const SizedBox(height: 6),
              const Text(
                'TÍN HIỆU SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  fontSize: 16,
                ),
              ),
              Text(
                '${m.packet.hops} chặng • ${clock(m.packet.timestamp)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(m.text, style: const TextStyle(fontSize: 15, height: 1.4)),
              if (m.latitude != null) ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: GpsRow(m),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Đóng'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: red,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Xem tin nhắn'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
