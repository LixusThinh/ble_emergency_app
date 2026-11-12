import 'package:flutter/material.dart';

import '../account/account_controller.dart';
import '../app/controller.dart';
import '../core/packet.dart';
import '../messaging/store.dart';
import 'account_tab.dart';
import 'location_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// Trang chủ: greeting, network, the SOS button, SOS nearby with their
/// addresses, recent activity and shortcuts.
class EmergencyTab extends StatelessWidget {
  final AppController c;
  final AccountController account;
  final VoidCallback onSos;
  final ValueChanged<int> onTab;
  const EmergencyTab({
    super.key,
    required this.c,
    required this.account,
    required this.onSos,
    required this.onTab,
  });
  bool get online => c.router?.running ?? false;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sos = c.messages
        .where((m) => m.packet.kind == MessageKind.sos)
        .take(3)
        .toList();
    final recent = c.messages
        .where((m) => m.packet.kind != MessageKind.sos)
        .take(3)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _Greeting(c: c, account: account, onAccount: () => onTab(3)),
        const SizedBox(height: 12),
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
        Text(
          'Kèm vị trí, địa chỉ và độ chính xác nếu có. Ứng dụng không tự gọi cơ quan cứu hộ.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: p.muted),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: !online || c.busy
                    ? null
                    : () => c.send(MessageKind.safe, 'Tôi an toàn'),
                icon: Icon(Icons.check_circle_outline, color: p.accent),
                label: const Text('Tôi an toàn'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onTab(1),
                icon: Icon(Icons.chat_bubble_outline, color: p.accent),
                label: const Text('Nhắn tin'),
              ),
            ),
          ],
        ),
        if (sos.isNotEmpty) ...[
          const SectionTitle('SOS gần đây'),
          for (final m in sos) _SosTile(c: c, m: m, onTap: () => onTab(1)),
        ],
        SectionTitle(
          'Hoạt động gần đây',
          trailing: TextButton(
            onPressed: () => onTab(1),
            child: const Text('Xem tất cả'),
          ),
        ),
        if (recent.isEmpty)
          const Card(
            child: EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Chưa có tin nhắn',
              detail: 'Tin gửi khi chưa gặp ai sẽ được lưu và tự chuyển tiếp khi gặp thiết bị.',
            ),
          ),
        ...recent.map((m) => MessageTile(c: c, m: m, onTap: () => onTab(1))),
        const SectionTitle('Lối tắt'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Shortcut(
                icon: Icons.radar,
                label: 'Thiết bị gần',
                onTap: () => onTab(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Shortcut(
                icon: Icons.science_outlined,
                label: 'Đánh giá mô phỏng',
                onTap: () => openSimulator(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Shortcut(
                icon: Icons.medical_information_outlined,
                label: 'Hồ sơ khẩn cấp',
                onTap: () => onTab(3),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  final AppController c;
  final AccountController account;
  final VoidCallback onAccount;
  const _Greeting({
    required this.c,
    required this.account,
    required this.onAccount,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: account,
    builder: (context, _) {
      final p = context.palette;
      final name = c.settings.name.trim().isNotEmpty
          ? c.settings.name.trim()
          : account.profile?.displayName ?? '';
      final hour = DateTime.now().hour;
      final hello = hour < 11
          ? 'Chào buổi sáng'
          : hour < 14
          ? 'Chào buổi trưa'
          : hour < 18
          ? 'Chào buổi chiều'
          : 'Chào buổi tối';
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? hello : '$hello, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  account.signedIn
                      ? account.blocked
                            ? 'Tài khoản bị khóa • SOS Bluetooth vẫn chạy'
                            : 'Đã đăng nhập • tự đồng bộ khi có mạng'
                      : 'Chế độ khách • SOS vẫn đầy đủ',
                  style: TextStyle(color: p.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Mở tài khoản',
            excludeSemantics: true,
            child: InkWell(
              onTap: onAccount,
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: p.accentSoft,
                child: account.signedIn
                    ? Text(
                        initials(name.isEmpty ? account.user!.email : name),
                        style: TextStyle(
                          color: p.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : Icon(Icons.person_outline, color: p.accent),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SosTile extends StatelessWidget {
  final AppController c;
  final StoredMessage m;
  final VoidCallback onTap;
  const _SosTile({required this.c, required this.m, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final where =
        m.placeName ??
        (m.hasLocation
            ? '${m.latitude!.toStringAsFixed(5)}, ${m.longitude!.toStringAsFixed(5)}'
            : 'Không kèm vị trí');
    final accuracy = accuracyLabel(m.accuracy);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: p.dangerSoft,
          child: Icon(Icons.campaign_rounded, color: p.danger, size: 20),
        ),
        title: Text(
          '${senderName(c, m)} • ${clock(m.packet.timestamp)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          [where, ?accuracy].join('  •  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: m.hasLocation
            ? IconButton(
                tooltip: 'Chỉ đường',
                icon: Icon(Icons.directions_rounded, color: p.accent),
                onPressed: () => LocationCard.openDirections(
                  context,
                  m.latitude!,
                  m.longitude!,
                ),
              )
            : null,
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.line),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: p.accent),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
          Text(
            'Tên này hiện trên máy của người khác.',
            style: TextStyle(color: context.palette.muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: c.settings.name,
            onChanged: (v) => c.settings.name = v,
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
    final p = context.palette;
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
                    color: p.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    c.demo ? Icons.science_outlined : Icons.bluetooth_connected,
                    color: p.accent,
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
                        style: TextStyle(color: p.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: c.busy ? null : c.stopNetwork,
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
