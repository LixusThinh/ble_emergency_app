import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../core/packet.dart';
import 'chat_tab.dart';
import 'emergency_tab.dart';
import 'peers_tab.dart';
import 'simulator_page.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

/// Holds navigation state only; the header and the visible tab rebuild from
/// [AppController] through a ListenableBuilder, the navigation bar does not.
class _HomePageState extends State<HomePage> {
  final c = AppController();
  final input = TextEditingController();
  int tab = 0;
  String? recipientId;
  bool _alertOpen = false;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    if (recipientId != null &&
        !(c.router?.contacts.containsKey(recipientId) ?? false)) {
      setState(() => recipientId = null);
    }
    _popSos();
  }

  void _popSos() {
    if (_alertOpen || c.sosAlerts.isEmpty) {
      return;
    }
    final m = c.sosAlerts.removeAt(0);
    _alertOpen = true;
    unawaited(HapticFeedback.heavyImpact());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _alertOpen = false;
        return;
      }
      final open = await showDialog<bool>(
        context: context,
        builder: (_) => SosAlert(name: senderName(c, m), m: m),
      );
      _alertOpen = false;
      if (!mounted) {
        return;
      }
      if (open ?? false) {
        _go(1);
      }
      _popSos();
    });
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    unawaited(c.stop());
    input.dispose();
    super.dispose();
  }

  void _go(int i) {
    FocusScope.of(context).unfocus();
    setState(() => tab = i);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => Column(
          children: [
            _Header(c: c),
            if (c.busy) const LinearProgressIndicator(minHeight: 2),
            if (c.error != null)
              _ErrorBanner(message: c.error!, onClose: c.dismissError),
            Expanded(
              child: switch (tab) {
                0 => EmergencyTab(c: c, onSos: _sos, onTab: _go),
                1 => ChatTab(
                  c: c,
                  recipientId: recipientId,
                  onRecipient: (id) => setState(() => recipientId = id),
                  input: input,
                  onSend: _sendChat,
                ),
                2 => PeersTab(
                  c: c,
                  onMessage: (id) {
                    recipientId = id;
                    _go(1);
                  },
                ),
                _ => const SimulatorPage(),
              },
            ),
          ],
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: _go,
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

  Future<void> _sos() async {
    const fallback = 'Tôi cần hỗ trợ khẩn cấp.';
    final detail = TextEditingController(text: fallback);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.emergency, color: red, size: 36),
        title: const Text('Gửi yêu cầu cứu trợ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'SOS được phát tới mọi thiết bị trong mạng, kèm GPS nếu có. Mô tả ngắn tình trạng của bạn.',
                style: TextStyle(color: muted, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in [
                    'Bị thương',
                    'Bị mắc kẹt',
                    'Cần nước uống',
                    'Cần thuốc',
                  ])
                    ActionChip(
                      label: Text(s),
                      onPressed: () =>
                          detail.text = '${detail.text.trim()} $s.'.trim(),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: detail,
                maxLength: 250,
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: red,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(
              context,
              detail.text.trim().isEmpty ? fallback : detail.text.trim(),
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

  Future<void> _sendChat() async {
    final text = input.text.trim();
    if (text.isEmpty) {
      return;
    }
    final contact = recipientId == null
        ? null
        : c.router?.contacts[recipientId];
    if (recipientId != null && contact == null) {
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
}

class _Header extends StatelessWidget {
  final AppController c;
  const _Header({required this.c});
  @override
  Widget build(BuildContext context) {
    final r = c.router;
    final online = r?.running ?? false;
    final peers = online ? r!.directPeers.length : 0;
    final (label, tint) = !online
        ? ('Ngoại tuyến', muted)
        : c.demo
        ? ('Mô phỏng', amber)
        : peers == 0
        ? ('Đang tìm…', teal)
        : ('$peers thiết bị', teal);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [teal, tealDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.hub_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'SOS MESH',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  online
                      ? 'ID ${r!.identity.id.substring(0, 8)}'
                      : 'Nhắn tin không cần Internet',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: online ? tint.withValues(alpha: .1) : Colors.white,
              border: Border.all(
                color: online ? tint.withValues(alpha: .25) : line,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulseDot(color: tint, active: online),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: tint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _ErrorBanner({required this.message, required this.onClose});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
    decoration: BoxDecoration(
      color: amberSoft,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: amber.withValues(alpha: .25)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: amber, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        TextButton(onPressed: onClose, child: const Text('Đóng')),
      ],
    ),
  );
}
