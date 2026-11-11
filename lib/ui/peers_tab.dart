import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../routing/router.dart';
import '../transport/transport.dart';
import 'theme.dart';
import 'widgets.dart';

class PeersTab extends StatelessWidget {
  final AppController c;
  final ValueChanged<String> onMessage;
  final VoidCallback onStart;
  const PeersTab({
    super.key,
    required this.c,
    required this.onMessage,
    required this.onStart,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = c.router;
    final online = r?.running ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const PageTitle(
          'Thiết bị trong mạng',
          subtitle: 'RSSI cho biết tín hiệu mạnh hay yếu, không phải khoảng cách chính xác.',
        ),
        if (!online || r == null)
          Card(
            child: EmptyState(
              icon: Icons.bluetooth_disabled,
              title: 'Mạng đang tắt',
              detail: 'Bật mạng ở Trang chủ để tìm thiết bị.',
              action: FilledButton.tonalIcon(
                onPressed: onStart,
                icon: const Icon(Icons.bluetooth),
                label: const Text('Đến Trang chủ'),
              ),
            ),
          )
        else
          ..._online(context, r),
        const SizedBox(height: 14),
        Text(
          'Chữ ký xác nhận nguồn phát theo khóa, không xác nhận danh tính ngoài đời. Tên hiển thị có thể trùng.',
          style: TextStyle(color: p.muted, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }

  List<Widget> _online(BuildContext context, MeshRouter r) {
    final p = context.palette;
    final direct = r.directPeers;
    final directNodes = {for (final peer in direct) r.nodeForPeer(peer.id)};
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Avatar(id: r.identity.id, name: r.name, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      c.demo
                          ? 'Thiết bị của bạn • mô phỏng'
                          : 'Thiết bị của bạn',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      r.identity.id,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sao chép ID',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: r.identity.id));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã sao chép ID')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
        ),
      ),
      SectionTitle('Kết nối trực tiếp', trailing: CountBadge(direct.length)),
      if (direct.isEmpty)
        const Card(
          child: ListTile(
            leading: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            title: Text('Đang tìm thiết bị gần…'),
            subtitle: Text('Mở ứng dụng và bật mạng trên điện thoại khác.'),
          ),
        ),
      for (final peer in direct)
        Card(
          child: ListTile(
            leading: _SignalBadge(peer),
            title: Text(
              r.contacts[r.nodeForPeer(peer.id)]?.name ?? peer.id,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${peer.rssi} dBm • ${peer.signal} • MTU ${peer.mtu}',
            ),
            trailing: Icon(Icons.link, color: p.accent),
          ),
        ),
      SectionTitle('Danh tính đã gặp', trailing: CountBadge(r.contacts.length)),
      if (r.contacts.isEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Chưa nhận được gói tin có chữ ký nào.',
            style: TextStyle(color: p.muted),
          ),
        ),
      for (final contact in r.contacts.values)
        Card(
          child: ListTile(
            leading: Avatar(id: contact.id, name: contact.name),
            title: Text(
              contact.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${contact.id.substring(0, 8)}…${directNodes.contains(contact.id) ? '  •  đang kết nối trực tiếp' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              tooltip: 'Nhắn riêng',
              onPressed: () => onMessage(contact.id),
              icon: Icon(Icons.lock_outline, color: p.accent),
            ),
          ),
        ),
    ];
  }
}

class _SignalBadge extends StatelessWidget {
  final Peer peer;
  const _SignalBadge(this.peer);
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, tint, label) = peer.rssi > -60
        ? (Icons.signal_cellular_alt, p.accent, 'mạnh')
        : peer.rssi > -80
        ? (Icons.signal_cellular_alt_2_bar, p.warn, 'trung bình')
        : (Icons.signal_cellular_alt_1_bar, p.danger, 'yếu');
    return Semantics(
      label: 'Tín hiệu $label',
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: tint),
      ),
    );
  }
}
