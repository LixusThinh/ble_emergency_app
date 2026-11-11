import 'package:flutter/material.dart';

import '../account/account_controller.dart';
import '../account/backend.dart';
import '../app/settings.dart';
import 'auth_page.dart';
import 'simulator_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Account, emergency profile, appearance and tools.
class AccountTab extends StatelessWidget {
  final AccountController account;
  final AppSettings settings;
  const AccountTab({super.key, required this.account, required this.settings});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([account, settings]),
    builder: (context, _) {
      final p = context.palette;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const PageTitle(
            'Tài khoản',
            subtitle: 'Hồ sơ khẩn cấp, đồng bộ và cài đặt.',
          ),
          if (account.signedIn)
            _ProfileCard(account: account)
          else
            _GuestCard(account: account),
          if (account.signedIn) ...[
            const SectionTitle('Thông tin khẩn cấp'),
            _EmergencyInfo(account: account),
            const SectionTitle('Đồng bộ'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      account.blocked
                          ? Icons.block
                          : account.pending == 0
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_upload_outlined,
                      color: account.blocked ? p.danger : p.accent,
                    ),
                    title: Text(
                      account.blocked
                          ? 'Tài khoản đã bị khóa'
                          : account.pending == 0
                          ? 'Đã đồng bộ'
                          : '${account.pending} mục chờ gửi',
                    ),
                    subtitle: Text(
                      account.blocked
                          ? 'Liên hệ quản trị viên. SOS qua Bluetooth vẫn hoạt động.'
                          : 'Nhật ký và SOS tự gửi lên khi có Internet.',
                    ),
                    trailing: account.blocked || account.pending == 0
                        ? null
                        : IconButton(
                            tooltip: 'Gửi ngay',
                            onPressed: account.flush,
                            icon: const Icon(Icons.sync),
                          ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Lịch sử hoạt động'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ActivityPage(account: account),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SectionTitle('Giao diện'),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('Theo máy'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Sáng'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Tối'),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (v) => settings.themeMode = v.single,
          ),
          const SectionTitle('Công cụ'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Đánh giá mô phỏng'),
                  subtitle: const Text(
                    'Đo tỷ lệ SOS đến nơi với nhiều thiết bị ảo',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openSimulator(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Phiên bản'),
                  trailing: Text(appVersion, style: TextStyle(color: p.muted)),
                ),
              ],
            ),
          ),
          if (account.signedIn) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: account.busy
                  ? null
                  : () async {
                      final error = await account.signOut();
                      if (error != null && context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(error)));
                      }
                    },
              icon: Icon(Icons.logout, color: p.danger),
              label: const Text('Đăng xuất'),
            ),
          ],
        ],
      );
    },
  );
}

/// Opens the simulator's evaluation page.
void openSimulator(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Đánh giá mô phỏng'),
      ),
      body: const SimulatorPage(),
    ),
  ),
);

class _ProfileCard extends StatelessWidget {
  final AccountController account;
  const _ProfileCard({required this.account});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final profile = account.profile;
    final email = profile?.email ?? account.user!.email;
    final name = profile?.displayName ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: p.accentSoft,
              child: Text(
                initials(name.isEmpty ? email : name),
                style: TextStyle(
                  color: p.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Chưa đặt tên' : name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  if (profile?.admin ?? false) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: p.accentSoft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'Quản trị viên',
                        style: TextStyle(
                          color: p.accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Sửa hồ sơ',
              onPressed: profile == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProfilePage(account: account),
                      ),
                    ),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  final AccountController account;
  const _GuestCard({required this.account});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Future<void> open(bool signUp) => Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AuthPage(account: account, startWithSignUp: signUp),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: p.muted),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Bạn đang dùng không cần tài khoản',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              account.available
                  ? 'SOS và nhắn tin qua Bluetooth vẫn đầy đủ. Đăng nhập để lưu hồ sơ khẩn cấp và đưa SOS lên trung tâm điều phối khi có mạng.'
                  : 'Bản này chưa kết nối máy chủ tài khoản. SOS và nhắn tin qua Bluetooth vẫn đầy đủ.',
              style: TextStyle(color: p.muted, height: 1.45, fontSize: 13.5),
            ),
            if (account.available) ...[
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => open(false),
                child: const Text('Đăng nhập'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => open(true),
                child: const Text('Tạo tài khoản'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmergencyInfo extends StatelessWidget {
  final AccountController account;
  const _EmergencyInfo({required this.account});
  @override
  Widget build(BuildContext context) {
    final p = account.profile;
    if (p == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Chưa tải được hồ sơ'),
          subtitle: Text('Cần Internet để tải lần đầu.'),
        ),
      );
    }
    Widget row(IconData icon, String label, String? value) => ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label),
      subtitle: Text(
        value == null || value.isEmpty ? 'Chưa nhập' : value,
        style: TextStyle(
          color: value == null || value.isEmpty
              ? context.palette.muted
              : context.palette.ink,
          fontSize: 14,
        ),
      ),
    );
    return Card(
      child: Column(
        children: [
          row(Icons.phone_outlined, 'Số điện thoại', p.phone),
          row(
            Icons.contact_phone_outlined,
            'Người liên hệ khẩn cấp',
            p.emergencyContact,
          ),
          row(Icons.bloodtype_outlined, 'Nhóm máu', p.bloodType),
          row(
            Icons.medical_information_outlined,
            'Ghi chú y tế',
            p.medicalNotes,
          ),
        ],
      ),
    );
  }
}

/// Edits the user's own profile.
class ProfilePage extends StatefulWidget {
  final AccountController account;
  const ProfilePage({super.key, required this.account});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _form = GlobalKey<FormState>();
  late final Profile _p = widget.account.profile!;
  late final _name = TextEditingController(text: _p.displayName);
  late final _phone = TextEditingController(text: _p.phone);
  late final _contact = TextEditingController(text: _p.emergencyContact);
  late final _notes = TextEditingController(text: _p.medicalNotes);
  late String? _blood = _p.bloodType;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _contact, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    final error = await widget.account.saveProfile(
      Profile(
        id: _p.id,
        email: _p.email,
        displayName: _name.text,
        phone: _phone.text,
        emergencyContact: _contact.text,
        bloodType: _blood,
        medicalNotes: _notes.text,
        admin: _p.admin,
        banned: _p.banned,
      ),
    );
    if (!mounted) {
      return;
    }
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      title: const Text('Hồ sơ khẩn cấp'),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text(
            'Thông tin này giúp đội cứu hộ khi bạn gửi SOS. Chỉ bạn và quản trị viên xem được.',
            style: TextStyle(color: context.palette.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Họ và tên',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Nhập tên của bạn' : null,
          ),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Số điện thoại',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (v) {
              final s = (v ?? '').trim();
              return s.isEmpty || RegExp(r'^\+?[0-9 .-]{8,20}$').hasMatch(s)
                  ? null
                  : 'Số điện thoại không hợp lệ';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contact,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Người liên hệ khẩn cấp',
              hintText: 'Ví dụ: Mẹ - 0901 234 567',
              prefixIcon: Icon(Icons.contact_phone_outlined),
            ),
          ),
          DropdownButtonFormField<String?>(
            initialValue: _blood,
            decoration: const InputDecoration(
              labelText: 'Nhóm máu',
              prefixIcon: Icon(Icons.bloodtype_outlined),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Không rõ')),
              for (final b in bloodTypes)
                DropdownMenuItem(value: b, child: Text(b)),
            ],
            onChanged: (v) => setState(() => _blood = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Ghi chú y tế',
              hintText: 'Dị ứng, bệnh nền, thuốc đang dùng…',
              prefixIcon: Icon(Icons.medical_information_outlined),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                style: TextStyle(color: context.palette.danger),
              ),
            ),
          ListenableBuilder(
            listenable: widget.account,
            builder: (context, _) => FilledButton(
              onPressed: widget.account.busy ? null : _save,
              child: const Text('Lưu'),
            ),
          ),
        ],
      ),
    ),
  );
}

const activityLabels = {
  'sign_up': 'Tạo tài khoản',
  'sign_in': 'Đăng nhập',
  'sign_out': 'Đăng xuất',
  'app_open': 'Mở ứng dụng',
  'mesh_start': 'Bật mạng',
  'mesh_stop': 'Tắt mạng',
  'sos_sent': 'Gửi SOS',
  'safe_sent': 'Báo an toàn',
  'sos_received': 'Nhận SOS',
  'profile_updated': 'Sửa hồ sơ',
};

/// The user's own activity log, as the server has it.
class ActivityPage extends StatelessWidget {
  final AccountController account;
  const ActivityPage({super.key, required this.account});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      title: const Text('Lịch sử hoạt động'),
    ),
    body: FutureBuilder<List<ActivityEntry>>(
      future: account.history(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Chưa tải được',
            detail: '${snap.error}',
          );
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            title: 'Chưa có hoạt động',
            detail: 'Đăng nhập, gửi SOS hay bật mạng sẽ hiện ở đây.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (context, i) {
            final e = list[i];
            final t = e.time;
            String two(int n) => n.toString().padLeft(2, '0');
            return Card(
              child: ListTile(
                leading: Icon(
                  e.action.startsWith('sos')
                      ? Icons.campaign_outlined
                      : Icons.bolt_outlined,
                ),
                title: Text(activityLabels[e.action] ?? e.action),
                subtitle: Text(
                  '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}/${t.year}'
                  '${e.details['demo'] == true ? ' • mô phỏng' : ''}',
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
