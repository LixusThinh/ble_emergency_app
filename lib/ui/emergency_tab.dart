import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../core/packet.dart';
import 'theme.dart';
import 'widgets.dart';

class EmergencyTab extends StatelessWidget {
  final AppController c;
  final VoidCallback onSos;
  final ValueChanged<int> onTab;
  const EmergencyTab({
    super.key,
    required this.c,
    required this.onSos,
    required this.onTab,
  });
  bool get online => c.router?.running ?? false;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
    children: [
      if (online)
        NetworkCard(c: c)
      else ...[
        const _Hero(),
        const SizedBox(height: 12),
        _JoinCard(c: c),
      ],
      const SizedBox(height: 14),
      Center(child: SosButton(onPressed: online && !c.busy ? onSos : null)),
      Text(
        online
            ? 'Chạm để phát SOS tới mọi thiết bị trong mạng'
            : 'Bật mạng để gửi SOS',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      const SizedBox(height: 4),
      const Text(
        'Kèm GPS nếu có. Ứng dụng không tự gọi cơ quan cứu hộ.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: muted),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: !online || c.busy
                  ? null
                  : () => c.send(MessageKind.safe, 'Tôi an toàn'),
              icon: const Icon(Icons.check_circle_outline, color: teal),
              label: const Text('Tôi an toàn'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => onTab(1),
              icon: const Icon(Icons.chat_bubble_outline, color: teal),
              label: const Text('Nhắn tin'),
            ),
          ),
        ],
      ),
      SectionTitle(
        'Hoạt động gần đây',
        trailing: TextButton(
          onPressed: () => onTab(1),
          child: const Text('Xem tất cả'),
        ),
      ),
      if (c.messages.isEmpty)
        const Card(
          child: EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Chưa có tin nhắn',
            detail: 'Tin gửi khi chưa gặp ai sẽ được lưu và tự chuyển tiếp khi gặp thiết bị.',
          ),
        ),
      ...c.messages
          .take(3)
          .map((m) => MessageTile(c: c, m: m, onTap: () => onTab(1))),
    ],
  );
}

class _Hero extends StatelessWidget {
  const _Hero();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [teal, tealDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(
              'KHÔNG CẦN INTERNET',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .8),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Kết nối khi\nmọi thứ gián đoạn.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tin nhắn đi qua các điện thoại gần nhau bằng Bluetooth. Mỗi máy là một trạm chuyển tiếp.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .85),
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
      ],
    ),
  );
}

class _JoinCard extends StatelessWidget {
  final AppController c;
  const _JoinCard({required this.c});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tham gia mạng',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          const Text(
            'Tên này hiện trên máy của người khác.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: c.name == 'Người dùng' ? '' : c.name,
            onChanged: (v) => c.name = v,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Tên hiển thị',
              hintText: 'Ví dụ: Minh • Nhóm 2',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          FilledButton.icon(
            onPressed: c.busy ? null : () => c.start(simulated: false),
            icon: const Icon(Icons.bluetooth),
            label: const Text('Bật mạng Bluetooth'),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: c.busy ? null : () => c.start(simulated: true),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Thử mô phỏng 3 thiết bị'),
          ),
        ],
      ),
    ),
  );
}

class NetworkCard extends StatelessWidget {
  final AppController c;
  const NetworkCard({super.key, required this.c});
  @override
  Widget build(BuildContext context) {
    final r = c.router!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tealSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    c.demo ? Icons.science_outlined : Icons.bluetooth_connected,
                    color: teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.demo
                            ? 'Mạng thử nghiệm A → B → C'
                            : 'Mạng BLE đang hoạt động',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        c.demo
                            ? 'Dữ liệu trên màn hình là mô phỏng'
                            : 'Đang quảng bá và quét thiết bị gần',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: c.busy ? null : c.stop,
                  tooltip: 'Tắt mạng',
                  icon: const Icon(Icons.power_settings_new),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatTile(
                    value: '${r.directPeers.length}',
                    label: 'Kết nối trực tiếp',
                    icon: Icons.link,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    value: '${r.contacts.length}',
                    label: 'Danh tính đã gặp',
                    icon: Icons.people_outline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    value: '${c.messages.length}',
                    label: 'Tin đã lưu',
                    icon: Icons.inbox_outlined,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
