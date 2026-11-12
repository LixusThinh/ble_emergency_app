/// What the app needs from the account server, so the UI and the tests do
/// not depend on Supabase directly.
library;

/// Server URL and public key, given at build time:
/// `flutter build apk --dart-define-from-file=supabase.env.json`.
/// The key is the publishable (anon) key, which is meant to ship in apps;
/// what it may do is decided by the database's row level security.
class BackendConfig {
  final String url, publishableKey;
  const BackendConfig(this.url, this.publishableKey);
  static const fromEnvironment = BackendConfig(
    String.fromEnvironment('SUPABASE_URL'),
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );
  bool get enabled =>
      url.startsWith('https://') && publishableKey.trim().isNotEmpty;
}

/// A message for the user; every backend error is turned into one.
class AccountException implements Exception {
  final String message;

  /// True when the account itself is refused (banned, deleted), not the
  /// network or the input.
  final bool forbidden;
  const AccountException(this.message, {this.forbidden = false});
  @override
  String toString() => message;
}

class AccountUser {
  final String id, email;
  const AccountUser(this.id, this.email);
}

enum SignUpOutcome {
  /// Signed in straight away (email confirmation is off).
  signedIn,

  /// The server sent a confirmation email; sign in after following it.
  confirmEmail,
}

const bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// The user's own row in `profiles`. Only the contact fields can be changed
/// by the user; role and ban are shown, never sent back.
class Profile {
  final String id, email, displayName;
  final String? phone, emergencyContact, bloodType, medicalNotes;
  final bool admin, banned;
  const Profile({
    required this.id,
    required this.email,
    this.displayName = '',
    this.phone,
    this.emergencyContact,
    this.bloodType,
    this.medicalNotes,
    this.admin = false,
    this.banned = false,
  });

  factory Profile.fromRow(Map<String, dynamic> r) => Profile(
    id: r['id'] as String,
    email: (r['email'] as String?) ?? '',
    displayName: (r['display_name'] as String?) ?? '',
    phone: r['phone'] as String?,
    emergencyContact: r['emergency_contact'] as String?,
    bloodType: r['blood_type'] as String?,
    medicalNotes: r['medical_notes'] as String?,
    admin: r['role'] == 'admin',
    banned: r['banned'] == true,
  );

  static String? _blank(String? v) =>
      v == null || v.trim().isEmpty ? null : v.trim();

  /// The columns a user may update, empty strings as null.
  Map<String, dynamic> toUpdate() => {
    'display_name': displayName.trim(),
    'phone': _blank(phone),
    'emergency_contact': _blank(emergencyContact),
    'blood_type': _blank(bloodType),
    'medical_notes': _blank(medicalNotes),
  };

  Profile copyWith({
    String? displayName,
    String? phone,
    String? emergencyContact,
    String? bloodType,
    String? medicalNotes,
  }) => Profile(
    id: id,
    email: email,
    displayName: displayName ?? this.displayName,
    phone: phone ?? this.phone,
    emergencyContact: emergencyContact ?? this.emergencyContact,
    bloodType: bloodType ?? this.bloodType,
    medicalNotes: medicalNotes ?? this.medicalNotes,
    admin: admin,
    banned: banned,
  );
}

/// One row of the user's own activity history.
class ActivityEntry {
  final String action;
  final Map<String, dynamic> details;
  final DateTime time;
  const ActivityEntry(this.action, this.details, this.time);
}

abstract interface class AccountBackend {
  /// False when the app was built without a server; everything else throws.
  bool get available;
  AccountUser? get currentUser;

  /// Fires when the user signs in or out, including a session that expired.
  Stream<AccountUser?> get userChanges;
  Future<AccountUser> signIn(String email, String password);
  Future<SignUpOutcome> signUp(
    String email,
    String password,
    String displayName,
  );
  Future<void> signOut();

  /// Emails a 6-digit code (see docs/DEPLOY_V2.md for the template).
  Future<void> sendResetCode(String email);

  /// Signs in with the emailed code and sets [newPassword].
  Future<void> resetPassword(String email, String code, String newPassword);
  Future<Profile> profile();
  Future<Profile> saveProfile(Profile profile);

  /// Registers this installation; returns the server's device id.
  Future<String> registerDevice({
    required String installId,
    required String model,
    required String platform,
    required String appVersion,
  });

  /// Appends rows to `activity_logs` (user_id is filled in by the backend).
  Future<void> insertActivity(List<Map<String, dynamic>> rows);

  /// Files SOS reports; one already filed (same message id) is skipped.
  Future<void> insertSos(List<Map<String, dynamic>> rows);
  Future<List<ActivityEntry>> myActivity({int limit = 50});
}

/// The app built without a server: guest mode only.
class OfflineBackend implements AccountBackend {
  const OfflineBackend();
  static const _no = AccountException(
    'Bản này chưa kết nối máy chủ tài khoản. Bạn vẫn dùng SOS và nhắn tin bình thường.',
  );
  @override
  bool get available => false;
  @override
  AccountUser? get currentUser => null;
  @override
  Stream<AccountUser?> get userChanges => const Stream.empty();
  @override
  Future<AccountUser> signIn(String email, String password) async => throw _no;
  @override
  Future<SignUpOutcome> signUp(String e, String p, String n) async => throw _no;
  @override
  Future<void> signOut() async {}
  @override
  Future<void> sendResetCode(String email) async => throw _no;
  @override
  Future<void> resetPassword(String e, String c, String p) async => throw _no;
  @override
  Future<Profile> profile() async => throw _no;
  @override
  Future<Profile> saveProfile(Profile profile) async => throw _no;
  @override
  Future<String> registerDevice({
    required String installId,
    required String model,
    required String platform,
    required String appVersion,
  }) async => throw _no;
  @override
  Future<void> insertActivity(List<Map<String, dynamic>> rows) async =>
      throw _no;
  @override
  Future<void> insertSos(List<Map<String, dynamic>> rows) async => throw _no;
  @override
  Future<List<ActivityEntry>> myActivity({int limit = 50}) async => throw _no;
}
