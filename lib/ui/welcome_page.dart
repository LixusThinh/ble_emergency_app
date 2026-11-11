import 'package:flutter/material.dart';

import '../account/account_controller.dart';
import 'auth_page.dart';
import 'theme.dart';

/// First launch: three short screens, then sign in, sign up, or go straight
/// to the app. None of it stands between the user and an SOS for long:
/// "Dùng ngay" is on every screen.
class WelcomePage extends StatefulWidget {
  final AccountController account;
  final VoidCallback onDone;
  const WelcomePage({super.key, required this.account, required this.onDone});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _Slide {
  final IconData icon;
  final String eyebrow, title, body;
  const _Slide(this.icon, this.eyebrow, this.title, this.body);
}

const _slides = [
  _Slide(
    Icons.hub_rounded,
    'KHÔNG CẦN INTERNET',
    'Kết nối khi mọi thứ gián đoạn',
    'Tin nhắn đi qua các điện thoại gần nhau bằng Bluetooth. Mỗi máy là một trạm chuyển tiếp, tin tự đi tiếp khi gặp người.',
  ),
  _Slide(
    Icons.location_on_rounded,
    'VỊ TRÍ CHÍNH XÁC',
    'Người cứu biết bạn ở đâu',
    'SOS kèm địa chỉ, độ chính xác và bản đồ. Người nhận bấm "Chỉ đường" là tới nơi, không phải đọc tọa độ.',
  ),
  _Slide(
    Icons.verified_user_rounded,
    'TÀI KHOẢN TÙY CHỌN',
    'Đồng bộ khi có mạng',
    'Đăng nhập để lưu hồ sơ khẩn cấp và đưa SOS lên trung tâm điều phối khi có Internet. Không đăng nhập vẫn gửi SOS được.',
  ),
];

class _WelcomePageState extends State<WelcomePage> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AuthPage(account: widget.account, allowGuest: true),
      ),
    );
    if (ok != null && mounted) {
      // true: signed in; false: chose to continue without an account.
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDone,
                child: const Text('Dùng ngay'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _SlideView(_slides[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page ? p.accent : p.line,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!last)
                    FilledButton(
                      onPressed: () => _pages.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                      ),
                      child: const Text('Tiếp tục'),
                    )
                  else if (widget.account.available) ...[
                    FilledButton.icon(
                      onPressed: _signIn,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Đăng nhập / Đăng ký'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: widget.onDone,
                      child: const Text('Dùng ngay không cần tài khoản'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: widget.onDone,
                      child: const Text('Bắt đầu'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide s;
  const _SlideView(this.s);
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [teal, tealDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: teal.withValues(alpha: .3),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(s.icon, color: Colors.white, size: 46),
              ),
              const SizedBox(height: 28),
              Text(
                s.eyebrow,
                style: TextStyle(
                  color: p.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                s.title,
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                s.body,
                style: TextStyle(fontSize: 15, height: 1.5, color: p.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
