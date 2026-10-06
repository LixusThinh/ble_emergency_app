import 'dart:async';

import 'package:flutter/material.dart';

import 'app/controller.dart';
import 'core/packet.dart';
import 'messaging/store.dart';
import 'simulator/scenario.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EmergencyApp());
}

const ink = Color(0xff142a36),
    teal = Color(0xff086f72),
    red = Color(0xffc63736);

class EmergencyApp extends StatelessWidget {
  const EmergencyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SOS Mesh',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        surface: const Color(0xfff6f8f8),
      ),
      scaffoldBackgroundColor: const Color(0xfff6f8f8),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff6f8f8),
        foregroundColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final c = AppController();
  final input = TextEditingController();
  int tab = 0;
  String? recipientId;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  void _changed() {
    if (mounted) {
      if (recipientId != null &&
          recipientId != '' &&
          !(c.router?.contacts.containsKey(recipientId) ?? false)) {
        recipientId = null;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    unawaited(c.stop());
    input.dispose();
    super.dispose();
  }

  bool get online => c.router?.running ?? false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        children: [
          Icon(Icons.hub_rounded, color: teal),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              'SOS MESH',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Chip(
            avatar: Icon(
              Icons.circle,
              size: 9,
              color: online ? teal : Colors.grey,
            ),
            label: Text(
              online ? (c.demo ? 'Mô phỏng' : 'BLE đang bật') : 'Chưa kết nối',
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (c.busy) const LinearProgressIndicator(minHeight: 2),
          if (c.error != null)
            MaterialBanner(
              content: Text(c.error!, maxLines: 4),
              actions: [
                TextButton(
                  onPressed: () {
                    c.error = null;
                    setState(() {});
                  },
                  child: const Text('Đóng'),
                ),
              ],
            ),
          Expanded(
            child: switch (tab) {
              0 => _dashboard(),
              1 => _chat(),
              2 => _peers(),
              _ => const SimulatorPage(),
            },
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (i) {
        FocusScope.of(context).unfocus();
        setState(() => tab = i);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.shield_outlined),
          selectedIcon: Icon(Icons.shield),
          label: 'Khẩn cấp',
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: 'Tin nhắn',
        ),
        NavigationDestination(icon: Icon(Icons.radar), label: 'Thiết bị'),
        NavigationDestination(
          icon: Icon(Icons.science_outlined),
          selectedIcon: Icon(Icons.science),
          label: 'Đánh giá',
        ),
      ],
    ),
  );
  Widget _dashboard() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Kết nối khi\nmọi thứ gián đoạn.',
        style: TextStyle(
          fontSize: 32,
          height: 1.15,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Gửi tin qua các thiết bị gần bạn bằng Bluetooth.\nMỗi thiết bị là một trạm chuyển tiếp.',
        style: TextStyle(color: Color(0xff657981), height: 1.5),
      ),
      const SizedBox(height: 24),
      if (!online)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tham gia mạng',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => c.name = v,
                  decoration: const InputDecoration(
                    labelText: 'Tên hiển thị',
                    hintText: 'Ví dụ: Minh • Nhóm 2',
                  ),
                  maxLength: 40,
                ),
                FilledButton.icon(
                  onPressed: c.busy ? null : () => c.start(simulated: false),
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Bật mạng Bluetooth'),
                ),
                TextButton.icon(
                  onPressed: c.busy ? null : () => c.start(simulated: true),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Thử mô phỏng 3 thiết bị'),
                ),
              ],
            ),
          ),
        ),
      if (online) _networkCard(),
      const SizedBox(height: 22),
      Center(
        child: Semantics(
          button: true,
          label: 'Gửi tín hiệu SOS',
          child: SizedBox(
            width: 224,
            height: 224,
            child: ElevatedButton(
              onPressed: !online || c.busy ? null : _sos,
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: red.withValues(alpha: .35),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: const CircleBorder(),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sos, size: 80),
                  Text(
                    'YÊU CẦU CỨU TRỢ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'SOS gửi đến toàn mạng, kèm GPS nếu có.\nKhông tự gọi hoặc liên hệ cơ quan cứu hộ.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Color(0xff657981), height: 1.5),
      ),
      const SizedBox(height: 22),
      OutlinedButton.icon(
        onPressed: !online || c.busy
            ? null
            : () => c.send(MessageKind.safe, 'Tôi an toàn'),
        icon: const Icon(Icons.check_circle_outline),
        label: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Tôi an toàn'),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          const Text(
            'Hoạt động gần đây',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => tab = 1),
            child: const Text('Xem tất cả'),
          ),
        ],
      ),
      if (c.messages.isEmpty)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Chưa có tin nhắn. Tin gửi khi chưa gặp ai sẽ được lưu chờ chuyển tiếp.',
          ),
        ),
      ...c.messages.take(3).map(_messageCard),
    ],
  );
  Widget _networkCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bluetooth_connected, color: teal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.demo
                      ? 'Mạng thử nghiệm A → B → C'
                      : 'Mạng BLE đang hoạt động',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: c.busy ? null : c.stop,
                tooltip: 'Tắt mạng',
                icon: const Icon(Icons.power_settings_new),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${c.router!.transport.peers.length} kết nối trực tiếp  •  ${c.router!.contacts.length} danh tính đã gặp',
          ),
          const SizedBox(height: 6),
          Text(
            'ID: ${c.router!.identity.id}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (c.demo)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Dữ liệu trong màn hình này là mô phỏng.',
                style: TextStyle(color: teal, fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );
  Future<void> _sos() async {
    final detail = TextEditingController(text: 'Tôi cần hỗ trợ khẩn cấp.');
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gửi yêu cầu cứu trợ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Mô tả ngắn tình trạng và vị trí để các thiết bị trong mạng hỗ trợ bạn.',
            ),
            const SizedBox(height: 16),
            TextField(controller: detail, maxLength: 250, maxLines: 3),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: red),
            onPressed: () => Navigator.pop(
              context,
              detail.text.trim().isEmpty
                  ? 'Tôi cần hỗ trợ khẩn cấp.'
                  : detail.text.trim(),
            ),
            child: const Text('Gửi SOS'),
          ),
        ],
      ),
    );
    // Text controller lives until the dialog transition has completed.
    Future<void>.delayed(const Duration(seconds: 1), detail.dispose);
    if (text != null) {
      await c.send(MessageKind.sos, text, gps: true);
    }
  }

  Widget _chat() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            const Text(
              'Tin nhắn',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text('${c.messages.length} tin'),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: DropdownButtonFormField<String>(
          key: ValueKey(recipientId),
          initialValue: recipientId ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Người nhận'),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Toàn mạng • công khai'),
            ),
            ...?c.router?.contacts.values.map(
              (p) => DropdownMenuItem(
                value: p.id,
                child: Text(
                  '${p.name} • ${p.id.substring(0, 6)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (v) => setState(() => recipientId = v),
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Tin riêng được mã hóa đầu cuối. Đối chiếu ID trực tiếp để xác nhận người nhận.',
          style: TextStyle(fontSize: 12, color: Color(0xff657981)),
        ),
      ),
      Expanded(
        child: c.messages.isEmpty
            ? const Center(child: Text('Tin nhắn sẽ xuất hiện ở đây.'))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                reverse: true,
                itemCount: c.messages.length,
                itemBuilder: (_, i) => _messageCard(c.messages[i]),
              ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 4,
                maxLength: 400,
                decoration: const InputDecoration(
                  hintText: 'Viết tin nhắn…',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: !online || c.busy ? null : _sendChat,
              tooltip: 'Gửi tin nhắn',
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    ],
  );
  Future<void> _sendChat() async {
    final text = input.text.trim();
    if (text.isEmpty) {
      return;
    }
    final contact = recipientId == null || recipientId == ''
        ? null
        : c.router?.contacts[recipientId];
    if (recipientId != null && recipientId != '' && contact == null) {
      return;
    }
    final sent = await c.send(
      contact == null ? MessageKind.chat : MessageKind.privateChat,
      text,
      recipient: contact,
    );
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
    if (sent) {
      input.clear();
    }
  }

  Widget _messageCard(StoredMessage m) {
    final sos = m.packet.kind == MessageKind.sos,
        safe = m.packet.kind == MessageKind.safe;
    final color = sos
        ? red
        : safe
        ? teal
        : ink;
    final time = DateTime.fromMillisecondsSinceEpoch(m.packet.timestamp)
        .toLocal();
    final contact = c.router?.contacts[m.senderId];
    return Card(
      color: sos ? const Color(0xffffefed) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  sos
                      ? Icons.sos
                      : safe
                      ? Icons.verified_user_outlined
                      : m.packet.kind == MessageKind.privateChat
                      ? Icons.lock_outline
                      : Icons.chat_bubble_outline,
                  color: color,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.outgoing
                        ? 'Bạn'
                        : contact?.name ?? m.senderId.substring(0, 6),
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
                ),
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(m.text, style: const TextStyle(fontSize: 15, height: 1.4)),
            if (m.latitude != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  'GPS: ${m.latitude!.toStringAsFixed(6)}, ${m.longitude!.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              m.outgoing
                  ? (m.acknowledged
                        ? 'Người nhận đã xác nhận'
                        : m.packet.broadcast
                        ? 'Đã lưu • chuyển tiếp khi gặp thiết bị'
                        : 'Đang chờ xác nhận người nhận')
                  : '${m.packet.hops} chặng • chữ ký hợp lệ',
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: .7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _peers() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Thiết bị trong mạng',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        'RSSI cho biết chất lượng tín hiệu tương đối; không phải khoảng cách chính xác.',
        style: TextStyle(color: Color(0xff657981), height: 1.5),
      ),
      const SizedBox(height: 20),
      if (!online) const Text('Bật mạng trong tab Khẩn cấp để tìm thiết bị.'),
      if (online) _networkCard(),
      const SizedBox(height: 20),
      const Text(
        'Kết nối trực tiếp',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      if (online && c.router!.transport.peers.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'Đang tìm thiết bị. Bật Bluetooth và ứng dụng trên điện thoại khác.',
          ),
        ),
      ...?c.router?.transport.peers.map(
        (p) => Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xffe0f1ee),
              child: Icon(Icons.bluetooth, color: teal),
            ),
            title: Text(
              c.router!.contacts[c.router!.nodeForPeer(p.id)]?.name ?? p.id,
            ),
            subtitle: Text('${p.rssi} dBm • ${p.signal} • MTU ${p.mtu}'),
            trailing: const Icon(Icons.link, color: teal),
          ),
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Danh tính đã gặp',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      ...?c.router?.contacts.values.map(
        (p) => Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(p.name),
            subtitle: SelectableText(p.id),
            trailing: IconButton(
              tooltip: 'Nhắn riêng',
              onPressed: () => setState(() {
                recipientId = p.id;
                tab = 1;
              }),
              icon: const Icon(Icons.lock_outline),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Chữ ký xác nhận nguồn phát theo khóa, không xác nhận danh tính ngoài đời. Tên hiển thị có thể trùng.',
        style: TextStyle(color: Color(0xff657981), fontSize: 12, height: 1.5),
      ),
    ],
  );
}

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
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Phòng mô phỏng',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        'Kiểm tra cùng bộ định tuyến và mã hóa với ứng dụng thật trên mạng vòng và các liên kết bổ sung.',
        style: TextStyle(color: Color(0xff657981), height: 1.5),
      ),
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${nodes.toInt()} thiết bị ảo',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              Slider(
                value: nodes,
                min: 10,
                max: 100,
                divisions: 9,
                onChanged: busy ? null : (v) => setState(() => nodes = v),
              ),
              Text(
                'Giới hạn ${ttl.toInt()} chặng',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              Slider(
                value: ttl,
                min: 1,
                max: 10,
                divisions: 9,
                onChanged: busy ? null : (v) => setState(() => ttl = v),
              ),
              const Text('Có chống trùng • ưu tiên SOS • phân mảnh BLE'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: busy ? null : _run,
                icon: const Icon(Icons.play_arrow),
                label: Text(busy ? 'Đang chạy…' : 'Chạy đánh giá'),
              ),
            ],
          ),
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!, style: const TextStyle(color: red)),
      if (report != null) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TỶ LỆ NHẬN SOS',
                  style: TextStyle(letterSpacing: 1, color: teal),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(report!.ratio * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                Text('${report!.delivered}/${report!.nodes - 1} thiết bị nhận'),
                const SizedBox(height: 16),
                Text(
                  '${report!.frames} BLE frame  •  ${report!.duplicate} gói trùng bị bỏ',
                ),
                Text(
                  '${report!.relay} lượt chuyển tiếp  •  ${report!.computeTime.inMilliseconds} ms thời gian xử lý',
                ),
                const Divider(height: 30),
                ...report!.hopDistribution.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(width: 65, child: Text('${e.key} chặng')),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: e.value / (report!.nodes - 1),
                            minHeight: 10,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text('${e.value}', textAlign: TextAlign.right),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      const Text(
        'Kết quả mô phỏng không đo độ trễ vô tuyến, tầm phủ hoặc pin. Các số đo này cần 3–5 điện thoại thật.',
        style: TextStyle(fontSize: 12, color: Color(0xff657981), height: 1.5),
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
