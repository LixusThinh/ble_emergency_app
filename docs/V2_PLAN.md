# Kế hoạch SOS Mesh 2.0

Ngày lập: 12/11/2026, nhánh `feat/v2`. Quyết định đã chốt với trưởng nhóm:

| Câu hỏi | Chốt |
|---|---|
| Backend | Supabase (Postgres + Auth + Row Level Security) |
| Đăng nhập | Không chặn SOS: có nút "Dùng ngay không cần tài khoản" |
| Vị trí SOS | Địa chỉ đọc được + bản đồ nhỏ + độ chính xác ± m + nút chỉ đường |
| Web admin | Next.js trên Vercel, chỉ tài khoản có vai trò `admin` vào được |
| Phạm vi | Code trên `feat/v2`, mở PR vào `main`, không tự merge |

## Nguyên tắc không đổi

1. **SOS luôn chạy offline.** Mọi thứ cần Internet (đăng nhập, đồng bộ, địa chỉ,
   bản đồ) đều là phần thêm. Mất mạng thì app vẫn phát và chuyển tiếp SOS như 1.x.
2. **Máy chủ không đọc được tin riêng.** Tin nhắn riêng vẫn mã hóa đầu cuối;
   server chỉ nhận nhật ký hành động (đăng nhập, gửi SOS, …) do chính người dùng
   đẩy lên, không bao giờ nhận nội dung tin riêng.
3. **Bảo mật nằm ở database, không nằm ở giao diện.** Mọi quyền được kiểm bằng
   RLS trong Postgres. Web admin chỉ dùng anon key + phiên đăng nhập của admin,
   không đặt `service_role` key ở Vercel. Thao tác quản trị đi qua hàm SQL
   `security definer` có kiểm `is_admin()` và tự ghi `admin_audit`.

## Các phần việc (mỗi phần một commit hoặc vài commit)

### P1. Vị trí chính xác cho SOS
- `MessageBody` thêm cờ `address` (chuỗi UTF-8 ≤ 255 byte, nằm trong phần đã ký)
  và `accuracy` (mét). Máy 1.x không đọc được thân tin mới nhưng vẫn chuyển tiếp
  vì router chuyển tiếp trước khi giải mã thân.
- Lấy vị trí: GPS trước, nếu quá thời gian thì dùng vị trí mạng/đã biết gần nhất;
  trả kèm độ chính xác.
- Đổi tọa độ ra địa chỉ: `android.location.Geocoder` (tiếng Việt, không cần key),
  dự phòng Nominatim (OpenStreetMap). Máy gửi có mạng thì địa chỉ đi kèm SOS;
  không có mạng thì máy nhận tự tra khi có mạng và lưu vào cột `messages.address`
  (schema v6), ghi rõ "địa chỉ do máy này tra".
- Giao diện: thẻ vị trí hiện địa chỉ to, tọa độ + "± 8 m" nhỏ, bản đồ OSM có ghim
  (`flutter_map`), nút "Chỉ đường" mở Google Maps, nút sao chép.

### P2. Supabase: schema, RLS, hàm quản trị (`supabase/`)
- Bảng: `profiles` (vai trò, bị khóa hay không, thông tin liên hệ khẩn cấp),
  `devices` (máy của người dùng + ID mesh), `activity_logs` (nhật ký hành động),
  `sos_reports` (SOS đã đồng bộ, trạng thái xử lý), `admin_audit` (admin làm gì).
- Người dùng: đọc/sửa hồ sơ của mình (không tự đổi vai trò/khóa), thêm nhật ký của
  mình, không sửa/xóa nhật ký. Tài khoản bị khóa không ghi được gì.
- Admin: đọc mọi thứ; khóa/mở khóa, đổi vai trò, cập nhật trạng thái SOS qua RPC.
- Kiểm thử: chạy migration + kiểm RLS trên PGlite (Postgres chạy trong Node) với
  schema `auth` giả lập, chạy được trong CI.

### P3. App: tài khoản, hồ sơ, đồng bộ nhật ký
- `supabase_flutter`; URL và anon key đưa vào lúc build bằng `--dart-define`.
  Không có cấu hình thì app chạy chế độ chỉ offline như cũ.
- Phiên đăng nhập lưu trong database đã mã hóa của app (không dùng
  SharedPreferences dạng rõ).
- Màn hình: chào mừng, đăng nhập, đăng ký, quên mật khẩu, hồ sơ.
- Hàng đợi nhật ký trong SQLite (schema v6 `outbox_events`): ghi khi offline, tự
  đẩy lên khi có mạng và đã đăng nhập.

### P4. UX/UI mới
- Luồng: Chào mừng → Đăng nhập / Đăng ký / Dùng ngay → khung chính.
- Thanh điều hướng: **Trang chủ** (nút SOS lớn, trạng thái mạng, SOS gần đây,
  việc nhanh), **Tin nhắn**, **Thiết bị**, **Tài khoản** (hồ sơ, giao diện,
  công cụ đánh giá mô phỏng, giới thiệu).
- Giữ nguyên `chat_tab.dart`, `peers_tab.dart` để issue #1–#3, #9 của các bạn
  vẫn làm được trên nền mới.

### P5. Web admin (`admin/`, Next.js trên Vercel)
- Trang: đăng nhập admin, tổng quan (số người dùng, SOS 24 giờ, máy hoạt động),
  danh sách SOS + bản đồ + đổi trạng thái, người dùng (tìm, xem nhật ký, khóa,
  đổi vai trò), nhật ký hành động (lọc theo loại/người/ngày), nhật ký admin.
- Bảo mật: middleware kiểm phiên và vai trò, header bảo mật (CSP, chống nhúng
  iframe, HSTS), cookie httpOnly do `@supabase/ssr` quản lý, không có secret
  phía trình duyệt.

### P6. CI, tài liệu, kiểm thử trên máy
- CI thêm job kiểm SQL (PGlite) và build web admin.
- `docs/DEPLOY_V2.md`: tạo project Supabase, chạy migration, tạo admin đầu tiên,
  deploy Vercel, build APK có cấu hình.
- Chạy integration test trên emulator, chụp ảnh màn hình mới.

## Việc trưởng nhóm cần làm (cần tài khoản thật)
1. Tạo project Supabase, chạy `supabase/migrations/*.sql` (SQL Editor hoặc CLI).
2. Đăng ký tài khoản trong app, rồi chạy `supabase/seed_admin.sql` với email đó.
3. Import thư mục `admin/` lên Vercel, đặt 2 biến môi trường.
4. Build APK với `--dart-define-from-file=supabase.env.json`.
Chi tiết từng bước nằm ở `docs/DEPLOY_V2.md`.
