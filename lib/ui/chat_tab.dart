import 'package:flutter/material.dart';

import '../app/controller.dart';
import 'theme.dart';
import 'widgets.dart';

class ChatTab extends StatelessWidget {
  final AppController c;

  /// Null shows and sends the public channel; otherwise the contact whose
  /// private conversation is open.
  final String? recipientId;
  final ValueChanged<String?> onRecipient;
  final TextEditingController input;
  final VoidCallback onSend;
  final VoidCallback onFindPeers;
  const ChatTab({
    super.key,
    required this.c,
    required this.recipientId,
    required this.onRecipient,
    required this.input,
    required this.onSend,
    required this.onFindPeers,
  });
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final contacts = c.router?.contacts.values.toList() ?? [];
    final to = recipientId == null ? null : c.router?.contacts[recipientId];
    final online = c.router?.running ?? false;
    final visible = c.messages.where((m) => inConversation(m, to?.id)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: PageTitle(
            'Tin nhắn',
            trailing: Text(
              '${visible.length} tin',
              style: TextStyle(color: p.muted),
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
              for (final contact in contacts)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    avatar: const Icon(Icons.lock_outline, size: 16),
                    label: Text(contact.name),
                    selected: to?.id == contact.id,
                    onSelected: (_) => onRecipient(contact.id),
                  ),
                ),
              if (online && contacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.radar, size: 16),
                    label: const Text('Tìm người để nhắn riêng'),
                    onPressed: onFindPeers,
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
                color: to == null ? p.muted : p.accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  to == null
                      ? 'Kênh chung: mọi thiết bị trong mạng đều đọc được.'
                      : 'Mã hóa đầu cuối tới ${to.name}. Đối chiếu ID ${to.id.substring(0, 8)} trực tiếp với người nhận.',
                  style: TextStyle(
                    fontSize: 12,
                    color: to == null ? p.muted : p.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: c.messages.isEmpty
                        ? const EmptyState(
                            icon: Icons.forum_outlined,
                            title: 'Tin nhắn sẽ xuất hiện ở đây.',
                            detail: 'Tin gửi khi chưa gặp ai được lưu lại và tự chuyển tiếp khi gặp thiết bị.',
                          )
                        : EmptyState(
                            icon: to == null
                                ? Icons.public
                                : Icons.lock_outline,
                            title: to == null
                                ? 'Kênh chung chưa có tin.'
                                : 'Chưa có tin riêng với ${to.name}.',
                            detail: to == null
                                ? null
                                : 'Chỉ ${to.name} giải mã được tin bạn gửi ở đây.',
                          ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  reverse: true,
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final m = visible[i];
                    final day = dayOf(m.packet.timestamp);
                    // The list is newest first and reversed, so the oldest
                    // message of a day is the last index with that day.
                    final firstOfDay =
                        i == visible.length - 1 ||
                        dayOf(visible[i + 1].packet.timestamp) != day;
                    final bubble = MessageBubble(c: c, m: m);
                    return firstOfDay
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [DaySeparator(day), bubble],
                          )
                        : bubble;
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  enabled: online,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 400,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (!c.busy) {
                      onSend();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: !online
                        ? 'Bật mạng ở tab Khẩn cấp để nhắn'
                        : to == null
                        ? 'Nhắn cho toàn mạng…'
                        : 'Nhắn riêng cho ${to.name}…',
                    counterText: '',
                    fillColor: p.canvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder(
                valueListenable: input,
                builder: (_, value, _) => IconButton.filled(
                  onPressed: !online || c.busy || value.text.trim().isEmpty
                      ? null
                      : onSend,
                  tooltip: 'Gửi tin nhắn',
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
