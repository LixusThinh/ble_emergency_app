# Triển khai SOS Mesh 2.0

Có ba phần cần dựng: database và tài khoản (Supabase), web admin (Vercel) và
app Android build kèm địa chỉ máy chủ. App vẫn chạy được ở chế độ khách nếu
chưa làm các bước này.

## 1. Supabase

1. Vào https://supabase.com, tạo project mới, chọn region **Southeast Asia
   (Singapore)**. Lưu lại mật khẩu database.
2. **Chạy migration.** Vào SQL Editor → New query, dán toàn bộ
   `supabase/migrations/20261112000000_sos_mesh_v2.sql` rồi bấm Run. Kết quả
   phải là *Success. No rows returned*.
   - Nếu dùng CLI: `npx supabase login`, `npx supabase link --project-ref <ref>`,
     rồi `npx supabase db push`.
3. **Authentication → Sign In / Providers → Email**
   - Bật Email. Nên bật *Confirm email*. Chỉ tắt khi demo trên lớp và muốn
     đăng ký xong là vào ngay.
   - Password: *Minimum length* = 8, *Password requirements* = letters and
     digits. App cũng kiểm đúng quy tắc này.
4. **Authentication → Emails → Reset Password.** App đặt lại mật khẩu bằng
   mã 6 số, nên mẫu email phải có `{{ .Token }}`. Dán đoạn sau:

   ```html
   <h2>Đặt lại mật khẩu SOS Mesh</h2>
   <p>Mã xác nhận của bạn: <b>{{ .Token }}</b></p>
   <p>Nhập mã này trong ứng dụng. Mã hết hạn sau 1 giờ.</p>
   ```
5. **Authentication → URL Configuration → Site URL**: điền địa chỉ web admin
   trên Vercel (bước 2). Link xác nhận email sẽ quay về trang này.
6. **Project Settings → API Keys**: lấy *Project URL* và *Publishable key*
   (dạng `sb_publishable_…`; project cũ thì là *anon key*).
   - **Không bao giờ** dùng `service_role` hoặc *secret key* ở app hay web
     admin. Hai phần đó không cần key này, mọi quyền đã nằm trong RLS.

Email mặc định của Supabase chỉ gửi được vài thư mỗi giờ. Như vậy đủ để
demo. Dùng thật thì cấu hình SMTP riêng (Authentication → Emails → SMTP).

## 2. Web admin trên Vercel

1. https://vercel.com → Add New → Project → Import repo
   `LixusThinh/ble_emergency_app`.
2. **Root Directory**: `admin`. Framework Next.js được nhận tự động.
3. **Environment Variables**, cho cả Production và Preview:

   | Tên | Giá trị |
   |---|---|
   | `SUPABASE_URL` | Project URL |
   | `SUPABASE_PUBLISHABLE_KEY` | Publishable key |

4. Bấm Deploy, lấy URL (ví dụ `https://sos-mesh-admin.vercel.app`) rồi
   điền vào Site URL ở bước 1.5.

Chạy thử trên máy: `cd admin`, chép `.env.example` thành `.env.local`, điền
2 biến, chạy `npm install` rồi `npm run dev` và mở http://localhost:3000.

## 3. Tạo quản trị viên đầu tiên

1. Đăng ký một tài khoản trong app, hoặc tạo ở Supabase → Authentication →
   Users → Add user.
2. Mở `supabase/seed_admin.sql`, sửa email rồi chạy trong SQL Editor. Kết
   quả phải có đúng một dòng với `role = admin`.
3. Đăng nhập web admin bằng tài khoản đó. Tài khoản thường sẽ bị từ chối và
   bị đăng xuất ngay.

Từ quản trị viên thứ hai trở đi thì cấp quyền ngay trong web admin
(Người dùng → Đổi vai trò). Mọi thao tác đều được ghi vào Nhật ký quản trị.

## 4. Build app có kết nối máy chủ

Tạo file `supabase.env.json` ở thư mục gốc repo. File này đã nằm trong
`.gitignore`, không commit:

```json
{
  "SUPABASE_URL": "https://xxxxxxxxxxxx.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_xxxxxxxx"
}
```

```bash
flutter build apk --release --dart-define-from-file=supabase.env.json
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Build không có file này thì app chạy chế độ khách: SOS, nhắn tin và địa chỉ
vẫn đủ, chỉ ẩn phần đăng nhập.

## 5. Kiểm tra sau khi triển khai

- [ ] App: đăng ký → nhận email xác nhận → đăng nhập → tab Tài khoản hiện hồ sơ.
- [ ] App: sửa hồ sơ khẩn cấp → web admin → Người dùng thấy thông tin mới.
- [ ] App: bật mô phỏng, gửi SOS → web admin → SOS (bật "Gồm mô phỏng") thấy
      địa chỉ, bản đồ, nút chỉ đường.
- [ ] Web admin: đổi trạng thái SOS → Nhật ký quản trị có dòng tương ứng.
- [ ] Web admin: khóa một tài khoản thử → app của tài khoản đó báo "Tài khoản
      đã bị khóa", SOS Bluetooth vẫn gửi được.
- [ ] Đăng nhập web admin bằng tài khoản thường → bị từ chối.
- [ ] Quên mật khẩu trong app → nhận mã 6 số → đặt mật khẩu mới được.

## Bảo mật: những gì đã làm và còn giới hạn

**Đã làm**

- RLS bật ở mọi bảng, quyền cấp theo từng cột. Bộ test `supabase/tests`
  (15 test, chạy trong CI) kiểm từng quy tắc: người dùng không đọc được dữ
  liệu của nhau, không tự nâng quyền, không sửa hay xóa nhật ký; admin chỉ sửa
  dữ liệu qua hàm có audit; tài khoản bị khóa không ghi được gì.
- Web admin không có key nào ở trình duyệt. Đăng nhập chạy ở server action,
  cookie phiên là httpOnly. CSP có nonce, chặn nhúng iframe, có HSTS.
- App lưu phiên đăng nhập trong database đã mã hóa bằng khóa Android
  Keystore.
- Nhật ký chỉ ghi việc gì đã xảy ra, không ghi nội dung tin nhắn. Tin riêng
  vẫn mã hóa đầu cuối và không bao giờ lên máy chủ. Vị trí chỉ lên máy chủ
  khi người dùng đã đăng nhập và gửi hoặc nhận SOS.

**Giới hạn hiện tại**

- Supabase thấy mọi lần đăng nhập web admin đến từ IP của Vercel, nên giới
  hạn số lần thử theo IP kém hiệu quả. Admin cần đặt mật khẩu mạnh. Có thể
  bật MFA của Supabase ở bản sau.
- SOS chuyển lên giúp người khác (cầu nối) được tin theo máy chuyển lên. Máy
  chủ chưa tự kiểm chữ ký Ed25519 của gói mesh. Web admin ghi rõ SOS do ai
  chuyển lên.
