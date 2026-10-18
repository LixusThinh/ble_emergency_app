import 'package:flutter/material.dart';

import '../app/controller.dart';
import 'theme.dart';
import 'widgets.dart';

class ChatTab extends StatelessWidget {
  final AppController c;

  /// Null sends a public broadcast; otherwise the contact to message privately.
  final String? recipientId;
  final ValueChanged<String?> onRecipient;
  final TextEditingController input;
  final VoidCallback onSend;
  const ChatTab({
    super.key,
    required this.c,
    required this.recipientId,
    required this.onRecipient,
    required this.input,
    required this.onSend,
  });
  @override
  Widget build(BuildContext context) {
    final contacts = c.router?.contacts.values.toList() ?? [];
    final to = recipientId == null ? null : c.router?.contacts[recipientId];
    final online = c.router?.running ?? false;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: PageTitle(
            'Tin nhắn',
            trailing: Text(
              '${c.messages.length} tin',
              style: const TextStyle(color: muted),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              ChoiceChip(
                showCheckmark: false,
                avatar: const Icon(Icons.public, size: 18),
                label: const Text('Toàn mạng'),
                selected: to == null,
                onSelected: (_) => onRecipient(null),
              ),
              for (final p in contacts)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    avatar: const Icon(Icons.lock_outline, size: 16),
                    label: Text(p.name),
                    selected: to?.id == p.id,
                    onSelected: (_) => onRecipient(p.id),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Row(
            children: [
              Icon(
                to == null ? Icons.info_outline : Icons.lock,
                size: 14,
                color: to == null ? muted : teal,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  to == null
                      ? 'Tin công khai: mọi thiết bị trong mạng đều đọc được.'
                      : 'Mã hóa đầu cuối tới ${to.name}. Đối chiếu ID ${to.id.substring(0, 8)} trực tiếp với người nhận.',
                  style: TextStyle(
                    fontSize: 12,
                    color: to == null ? muted : teal,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: c.messages.isEmpty
              ? const Center(
                  child: SingleChildScrollView(
                    child: EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'Tin nhắn sẽ xuất hiện ở đây.',
                      detail: 'Tin gửi khi chưa gặp ai được lưu lại và tự chuyển tiếp khi gặp thiết bị.',
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  reverse: true,
                  itemCount: c.messages.length,
                  itemBuilder: (_, i) => MessageBubble(c: c, m: c.messages[i]),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 400,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: to == null
                        ? 'Nhắn cho toàn mạng…'
                        : 'Nhắn riêng cho ${to.name}…',
                    counterText: '',
                    fillColor: canvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: !online || c.busy ? null : onSend,
                tooltip: 'Gửi tin nhắn',
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
