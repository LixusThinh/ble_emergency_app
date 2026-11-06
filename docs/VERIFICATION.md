# Kết quả xác minh — 06/10/2026

Nhóm thực hiện: **Trần Gia Thịnh** (nhóm trưởng, 2380602136), Đỗ Minh Quang (2380601802), Nguyễn Thanh Hải (1911065203), Hồ Uy Thiện (2380602107).

## Cập nhật 06/11/2026 — nâng cấp backend (nhánh `feat/backend`)

| Kiểm tra | Kết quả |
|---|---|
| `flutter analyze` | Không có issue |
| `flutter test` | 47 test đạt (36 trước đó + 9 test router trong `backend_test.dart` + 2 test SQLite: đếm máy đã nhận, thứ tự bỏ gói khi bảng đầy) |
| Android integration | Đạt; thêm kiểm tra dòng "Đã đến 1 máy gần • tự gửi tiếp" dưới SOS trong chế độ thử |
| Nâng cấp v2 → v3 trên emulator | Đạt. DB trên máy trước khi cài: `user_version` 2, tin "TIN TỪ BẢN 1.0.0". Sau khi cài bản mới và chạy integration: `user_version` 3, có thêm bảng `handoffs`, tin cũ vẫn còn |
| Mô phỏng 50 và 100 máy (một kết nối mỗi cặp) | Giống hệt bản trước: 43/49 và 92/99 máy nhận SOS, 148 và 308 frame |
| Chuỗi 4 máy, mỗi cặp hai kết nối như Android, gửi 10 tin | Bản trước: 180 frame, 60 gói trùng. Bản này: 60 frame, 0 gói trùng; máy cuối nhận đủ 10 tin |

Kiểm tra ngược: chạy test mới trên router cũ thì test hai kết nối thấy 6 gói trùng và test SOS thấy SOS chưa được nhận khi đang kẹt đồng bộ. Tắt ưu tiên trong hàng đợi thì SOS xuống vị trí thứ 20; tắt ghi nhớ "máy kề đã có gói" thì resync gửi lại 4 frame thừa. Các thay đổi chưa được thử trên điện thoại thật với BLE.

## Cập nhật 06/11/2026 — nâng cấp database (nhánh `feat/database`)

| Kiểm tra | Kết quả |
|---|---|
| `flutter analyze` | Không có issue |
| `flutter test` | 36 test đạt (29 trước đó + 6 test SQLite thật qua `sqflite_common_ffi` + 1 widget test chọn giao diện) |
| Android integration | Đạt; thêm bước kiểm tra `user_version` = 2 và lưu/đọc lại cài đặt bằng SQLite trên máy |
| Nâng cấp v1 → v2 trên emulator | Đạt. Cài bản `506fab4` (schema v1), ghi một tin "TIN TỪ BẢN 1.0.0", kéo file DB về: `user_version` 1, chỉ có `packets`, `messages`. Cài bản mới đè lên (giữ dữ liệu), chạy integration, kéo DB về: `user_version` 2, có thêm `contacts`, `settings` và 4 index, tin cũ vẫn còn |

Test migration chỉ đi từ v1 (bản đã phát hành duy nhất). Tên và giao diện lưu qua `main()` chưa được kiểm bằng integration (integration dựng app với cài đặt tạm); kho cài đặt SQLite được kiểm trực tiếp.

## Cập nhật 06/11/2026 — nâng cấp giao diện (nhánh `feat/ux-ui`)

| Kiểm tra | Kết quả |
|---|---|
| `flutter analyze` | Không có issue |
| `flutter test` | 29 test đạt (21 cũ + 8 mới: giao diện tối, lọc tin theo cuộc trò chuyện, soạn SOS, nhãn ngày, nhãn trạng thái mở tab Thiết bị) |
| Android integration | Đạt trên emulator Pixel 7 Pro / API 37; ảnh `screenshots/` chụp lại từ lần chạy này (giao diện sáng) |

Hai lỗi giao diện tìm thấy khi chạy integration và đã sửa: thông báo nổi "Đã phát SOS" che nút gửi tin sau khi chuyển tab (nay tự ẩn khi đổi tab); ô thống kê ở tab Đánh giá tràn 4.7 px trên Pixel 7 Pro (đổi tỉ lệ ô lưới). Giao diện tối chỉ được kiểm bằng widget test, chưa chụp ảnh.

## Kết quả 06/10/2026

Môi trường: Windows, Flutter 3.47.4 stable / Dart 3.13.3, Android Studio JBR, emulator Pixel 7 Pro / Android API 37.

| Kiểm tra | Kết quả |
|---|---|
| `flutter analyze` | Không có issue |
| `flutter test` | 18 test đạt: mesh/crypto/fragmentation/storage policy, hello/MTU khi kết nối lại, relay dừng sau ACK, relay gói không đọc được, banner lỗi, layout nhỏ, simulator isolate |
| Android integration | Đạt: Keystore, SQLite đóng/mở, demo 3 node, SOS, tin riêng/ACK, simulator 10 node |
| APK debug Android | Build thành công; artifact bàn giao build từ `lib/main.dart` |
| Simulator CLI | 50/100 node với TTL 3, 6, 10; so sánh dedup 10 node |
| BLE trên điện thoại thật | Chưa đo/kiểm chứng |
| GPS, background, pin, tầm phủ trên máy thật | Chưa đo/kiểm chứng |

Integration có 1 bài luồng ứng dụng và bước teardown; không cộng thành 2 luồng nghiệp vụ. Ảnh thực tế của giao diện Flutter từ emulator nằm trong `screenshots/`.

## Số liệu mô phỏng

| Node | TTL | Thiết bị nhận/đích còn lại | Delivery ratio | BLE frame |
|---:|---:|---:|---:|---:|
| 50 | 3 | 13/49 | 26.5% | 30 |
| 50 | 6 | 43/49 | 87.8% | 148 |
| 50 | 10 | 49/49 | 100% | 186 |
| 100 | 3 | 21/99 | 21.2% | 46 |
| 100 | 6 | 92/99 | 92.9% | 308 |
| 100 | 10 | 99/99 | 100% | 398 |

Topology cố định: vòng và shortcut seed 42. Với 10 node / TTL 6, dedup giảm 74 frame xuống 30 frame. Không có mô hình mất gói/vô tuyến/băng thông/pin; không suy rộng số liệu này thành kết quả thực địa.

Trong emulator debug, crypto Dart cho nhiều node có thể chậm. UI chạy mô phỏng trong isolate riêng để vẫn phản hồi; kiểm thử native dùng 10 node, CLI kiểm tra 50–100 node. Xem `simulation-results.json` để xem số liệu gốc và `TEST_PLAN.md` để tiếp tục đo trên thiết bị.
