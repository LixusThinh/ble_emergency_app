import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/settings.dart';
import 'backend.dart';

/// Keeps the login session in the app's encrypted database instead of
/// plain SharedPreferences.
class EncryptedSessionStorage extends LocalStorage {
  static const key = 'auth_session';
  final AppSettings settings;
  const EncryptedSessionStorage(this.settings);
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => settings.value(key) != null;
  @override
  Future<String?> accessToken() async => settings.value(key);
  @override
  Future<void> removePersistedSession() => settings.setValue(key, null);
  @override
  Future<void> persistSession(String persistSessionString) =>
      settings.setValue(key, persistSessionString);
}

/// Connects to Supabase; returns null (guest mode) when that fails.
Future<AccountBackend> connectBackend(
  BackendConfig config,
  AppSettings settings,
) async {
  if (!config.enabled) {
    return const OfflineBackend();
  }
  try {
    await Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: EncryptedSessionStorage(settings),
        // Email links open in the browser; nothing comes back through a
        // deep link, so do not listen for one.
        detectSessionInUri: false,
      ),
    );
    return SupabaseBackend(Supabase.instance.client);
  } catch (e) {
    return const OfflineBackend();
  }
}

class SupabaseBackend implements AccountBackend {
  final SupabaseClient client;
  SupabaseBackend(this.client);

  @override
  bool get available => true;

  static AccountUser? _user(User? u) =>
      u == null ? null : AccountUser(u.id, u.email ?? '');

  @override
  AccountUser? get currentUser => _user(client.auth.currentUser);

  @override
  Stream<AccountUser?> get userChanges =>
      client.auth.onAuthStateChange.map((s) => _user(s.session?.user));

  String get _uid {
    final u = client.auth.currentUser;
    if (u == null) {
      throw const AccountException('Bạn cần đăng nhập lại.');
    }
    return u.id;
  }

  /// Runs [action] and turns every failure into an [AccountException] with
  /// a message in Vietnamese.
  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 20));
    } on AccountException {
      rethrow;
    } on AuthException catch (e) {
      throw AccountException(_authMessage(e));
    } on PostgrestException catch (e) {
      final forbidden =
          e.code == '42501' || e.message.contains('row-level security');
      throw AccountException(
        forbidden
            ? 'Tài khoản không được phép làm việc này (có thể đã bị khóa).'
            : e.code == '54000'
            ? 'Gửi quá nhiều, thử lại sau một phút.'
            : 'Máy chủ từ chối: ${e.message}',
        forbidden: forbidden,
      );
    } on SocketException {
      throw const AccountException('Không có kết nối Internet.');
    } on TimeoutException {
      throw const AccountException('Máy chủ không trả lời, thử lại sau.');
    } on Exception catch (e) {
      final s = '$e';
      throw AccountException(
        s.contains('SocketException') || s.contains('ClientException')
            ? 'Không có kết nối Internet.'
            : 'Lỗi không mong đợi: $s',
      );
    }
  }

  static String _authMessage(AuthException e) => switch (e.code) {
    'invalid_credentials' => 'Sai email hoặc mật khẩu.',
    'email_not_confirmed' =>
      'Email chưa được xác nhận. Mở thư xác nhận rồi đăng nhập lại.',
    'user_already_exists' ||
    'email_exists' => 'Email này đã có tài khoản. Hãy đăng nhập.',
    'weak_password' => 'Mật khẩu quá yếu: cần ít nhất 8 ký tự, có chữ và số.',
    'over_email_send_rate_limit' ||
    'over_request_rate_limit' => 'Thử quá nhiều lần. Đợi vài phút rồi thử lại.',
    'otp_expired' => 'Mã đã hết hạn hoặc không đúng. Gửi lại mã mới.',
    'user_banned' => 'Tài khoản đã bị khóa.',
    'validation_failed' => 'Email không hợp lệ.',
    _ =>
      e.statusCode == null
          ? 'Không có kết nối Internet.'
          : 'Không đăng nhập được: ${e.message}',
  };

  @override
  Future<AccountUser> signIn(String email, String password) => _call(() async {
    final r = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return _user(r.user)!;
  });

  @override
  Future<SignUpOutcome> signUp(
    String email,
    String password,
    String displayName,
  ) => _call(() async {
    final r = await client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': displayName.trim()},
    );
    return r.session == null
        ? SignUpOutcome.confirmEmail
        : SignUpOutcome.signedIn;
  });

  @override
  Future<void> signOut() => _call(() => client.auth.signOut());

  @override
  Future<void> sendResetCode(String email) =>
      _call(() => client.auth.resetPasswordForEmail(email.trim()));

  @override
  Future<void> resetPassword(String email, String code, String newPassword) =>
      _call(() async {
        await client.auth.verifyOTP(
          email: email.trim(),
          token: code.trim(),
          type: OtpType.recovery,
        );
        await client.auth.updateUser(UserAttributes(password: newPassword));
      });

  @override
  Future<Profile> profile() => _call(() async {
    final row = await client.from('profiles').select().eq('id', _uid).single();
    return Profile.fromRow(row);
  });

  @override
  Future<Profile> saveProfile(Profile profile) => _call(() async {
    final row = await client
        .from('profiles')
        .update(profile.toUpdate())
        .eq('id', _uid)
        .select()
        .maybeSingle();
    if (row == null) {
      throw const AccountException(
        'Không lưu được hồ sơ (tài khoản có thể đã bị khóa).',
        forbidden: true,
      );
    }
    return Profile.fromRow(row);
  });

  @override
  Future<String> registerDevice({
    required String installId,
    required String model,
    required String platform,
    required String appVersion,
  }) => _call(() async {
    final id = await client.rpc<String>(
      'register_device',
      params: {
        'p_install_id': installId,
        'p_model': model,
        'p_platform': platform,
        'p_app_version': appVersion,
      },
    );
    return id;
  });

  @override
  Future<void> insertActivity(List<Map<String, dynamic>> rows) => _call(() {
    final uid = _uid;
    return client.from('activity_logs').insert([
      for (final r in rows) {...r, 'user_id': uid},
    ]);
  });

  @override
  Future<void> insertSos(List<Map<String, dynamic>> rows) => _call(() {
    final uid = _uid;
    return client
        .from('sos_reports')
        .upsert(
          [
            for (final r in rows) {...r, 'user_id': uid},
          ],
          onConflict: 'message_id',
          ignoreDuplicates: true,
        );
  });

  @override
  Future<List<ActivityEntry>> myActivity({int limit = 50}) => _call(() async {
    final rows = await client
        .from('activity_logs')
        .select('action, details, created_at')
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return [
      for (final r in rows)
        ActivityEntry(
          r['action'] as String,
          Map<String, dynamic>.from(r['details'] as Map? ?? const {}),
          DateTime.parse(r['created_at'] as String).toLocal(),
        ),
    ];
  });
}
