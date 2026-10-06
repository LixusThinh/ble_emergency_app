# Kết quả xác minh — 06/10/2026

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
