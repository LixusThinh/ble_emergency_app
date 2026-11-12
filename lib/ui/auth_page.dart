import 'package:flutter/material.dart';

import '../account/account_controller.dart';
import '../account/backend.dart';
import 'theme.dart';

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(String? v) =>
    v == null || !_email.hasMatch(v.trim()) ? 'Nhập email hợp lệ' : null;

/// Same rule the server is set to enforce (docs/DEPLOY_V2.md): 8+ characters
/// with letters and digits.
String? validatePassword(String? v) {
  if (v == null || v.length < 8) {
    return 'Ít nhất 8 ký tự';
  }
  if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
    return 'Cần có cả chữ và số';
  }
  return null;
}

/// Sign in or sign up. Pops true when signed in, false when the user chose
/// to go on without an account ([allowGuest]).
class AuthPage extends StatefulWidget {
  final AccountController account;
  final bool allowGuest;
  final bool startWithSignUp;
  const AuthPage({
    super.key,
    required this.account,
    this.allowGuest = false,
    this.startWithSignUp = false,
  });
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late bool _signUp = widget.startWithSignUp;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) {
      return;
    }
    final a = widget.account;
    SignUpOutcome? outcome;
    final error = _signUp
        ? await a.signUp(
            _email.text,
            _password.text,
            _name.text,
            onOutcome: (o) => outcome = o,
          )
        : await a.signIn(_email.text, _password.text);
    if (!mounted) {
      return;
    }
    setState(() => _error = error);
    if (error != null) {
      return;
    }
    if (outcome == SignUpOutcome.confirmEmail) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.mark_email_read_outlined, size: 36),
          title: const Text('Kiểm tra email'),
          content: Text(
            'Đã gửi thư xác nhận tới ${_email.text.trim()}. Mở thư, bấm xác nhận rồi quay lại đăng nhập.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
      if (mounted) {
        setState(() {
          _signUp = false;
          _password.clear();
          _confirm.clear();
        });
      }
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final busy = widget.account.busy;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_signUp ? 'Tạo tài khoản' : 'Đăng nhập'),
      ),
      body: ListenableBuilder(
        listenable: widget.account,
        builder: (context, _) => Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Đăng nhập')),
                  ButtonSegment(value: true, label: Text('Đăng ký')),
                ],
                selected: {_signUp},
                onSelectionChanged: busy
                    ? null
                    : (v) => setState(() {
                        _signUp = v.single;
                        _error = null;
                      }),
              ),
              const SizedBox(height: 18),
              Text(
                _signUp
                    ? 'Tài khoản lưu hồ sơ khẩn cấp và đưa SOS của bạn lên trung tâm điều phối khi có mạng.'
                    : 'Đăng nhập để đồng bộ hồ sơ và lịch sử hoạt động.',
                style: TextStyle(color: p.muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              if (_signUp) ...[
                TextFormField(
                  key: const ValueKey('auth-name'),
                  controller: _name,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Họ và tên',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Nhập tên của bạn' : null,
                ),
                const SizedBox(height: 4),
              ],
              TextFormField(
                key: const ValueKey('auth-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: validateEmail,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('auth-password'),
                controller: _password,
                obscureText: _hidden,
                autofillHints: [
                  _signUp ? AutofillHints.newPassword : AutofillHints.password,
                ],
                textInputAction: _signUp
                    ? TextInputAction.next
                    : TextInputAction.done,
                onFieldSubmitted: (_) => _signUp ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _hidden ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: _signUp
                    ? validatePassword
                    : (v) => (v ?? '').isEmpty ? 'Nhập mật khẩu' : null,
              ),
              if (_signUp) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('auth-confirm'),
                  controller: _confirm,
                  obscureText: _hidden,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Nhập lại mật khẩu',
                    prefixIcon: Icon(Icons.lock_reset),
                  ),
                  validator: (v) =>
                      v != _password.text ? 'Mật khẩu không khớp' : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.dangerSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: p.danger, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(_signUp ? 'Tạo tài khoản' : 'Đăng nhập'),
              ),
              if (!_signUp)
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final ok = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => ResetPasswordPage(
                                account: widget.account,
                                email: _email.text,
                              ),
                            ),
                          );
                          if ((ok ?? false) && context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
                  child: const Text('Quên mật khẩu?'),
                ),
              if (widget.allowGuest) ...[
                const Divider(height: 32),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Dùng ngay không cần tài khoản'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Emails a 6-digit code, then signs in with it and sets a new password.
/// Pops true when done.
class ResetPasswordPage extends StatefulWidget {
  final AccountController account;
  final String email;
  const ResetPasswordPage({super.key, required this.account, this.email = ''});
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) {
      return;
    }
    final a = widget.account;
    final error = _sent
        ? await a.resetPassword(_email.text, _code.text, _password.text)
        : await a.sendResetCode(_email.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _error = error;
      if (error == null && !_sent) {
        _sent = true;
      }
    });
    if (error == null && _code.text.isNotEmpty && _sent) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Đặt lại mật khẩu'),
      ),
      body: ListenableBuilder(
        listenable: widget.account,
        builder: (context, _) => Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              Text(
                _sent ? 'Nhập mã 6 số trong email và mật khẩu mới.' : 'Nhập email tài khoản, chúng tôi gửi mã 6 số để đặt lại mật khẩu.',
                style: TextStyle(color: p.muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                enabled: !_sent,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: validateEmail,
              ),
              if (_sent) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Mã xác nhận',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                  validator: (v) =>
                      RegExp(r'^\d{6}$').hasMatch((v ?? '').trim())
                      ? null
                      : 'Mã gồm 6 chữ số',
                ),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mật khẩu mới',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: validatePassword,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: p.danger)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: widget.account.busy ? null : _go,
                child: Text(_sent ? 'Đặt mật khẩu mới' : 'Gửi mã'),
              ),
              if (_sent)
                TextButton(
                  onPressed: widget.account.busy
                      ? null
                      : () => setState(() {
                          _sent = false;
                          _code.clear();
                        }),
                  child: const Text('Gửi lại mã'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
