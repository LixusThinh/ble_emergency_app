import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

const sosFallback = 'Tôi cần hỗ trợ khẩn cấp.';
const sosTags = ['Bị thương', 'Bị mắc kẹt', 'Cần nước uống', 'Cần thuốc'];

/// Builds the SOS text from the chosen tags and the free-text note.
String composeSos(Iterable<String> tags, String note) {
  final parts = [...tags, note.trim()].where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) {
    return sosFallback;
  }
  final text = parts.join('. ');
  return RegExp(r'[.!?]$').hasMatch(text) ? text : '$text.';
}

/// Asks for the SOS details; pops the message text, or null when cancelled.
class SosDialog extends StatefulWidget {
  const SosDialog({super.key});
  @override
  State<SosDialog> createState() => _SosDialogState();
}

class _SosDialogState extends State<SosDialog> {
  final _note = TextEditingController();
  final _tags = <String>{};
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final preview = composeSos(sosTags.where(_tags.contains), _note.text);
    return AlertDialog(
      icon: Icon(Icons.emergency, color: p.danger, size: 36),
      title: const Text('Gửi yêu cầu cứu trợ'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SOS được phát tới mọi thiết bị trong mạng, kèm GPS nếu có. Chọn tình trạng hoặc ghi thêm.',
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in sosTags)
                  FilterChip(
                    label: Text(s),
                    selected: _tags.contains(s),
                    selectedColor: p.dangerSoft,
                    checkmarkColor: p.danger,
                    onSelected: (on) =>
                        setState(() => on ? _tags.add(s) : _tags.remove(s)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 200,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Ví dụ: 2 người, tầng 3 nhà số 12',
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.dangerSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NỘI DUNG SẼ GỬI',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                      color: p.danger,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(preview, style: const TextStyle(height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: red,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
          ),
          onPressed: () {
            HapticFeedback.heavyImpact();
            Navigator.pop(context, preview);
          },
          icon: const Icon(Icons.campaign_rounded, size: 18),
          label: const Text('Gửi SOS'),
        ),
      ],
    );
  }
}
