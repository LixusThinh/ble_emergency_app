# SOS Mesh — ứng dụng BLE ngoại tuyến

Project dựa trên `BLE_Emergency_App_Huong_Dan.docx`, dành cho đồ án Flutter về truyền tin khẩn cấp qua nhiều chặng BLE. Mã nguồn Android thực và simulator dùng chung packet, routing, crypto.

## Đã triển khai

- Giao diện tiếng Việt: SOS, “Tôi an toàn”, chat broadcast, nhắn riêng, peer/RSSI, đánh giá mạng.
- Android dual role: central scan/connect + peripheral advertising/GATT server.
- Managed flooding, TTL, dedup, store-and-forward khi gặp peer mới/kết nối lại.
- Packet binary, phân mảnh MTU 23 trở lên, ghép lại có giới hạn tài nguyên.
- Ed25519 ký packet; X25519 + HKDF + AES-GCM cho tin riêng; ACK ký số.
- SQLite lưu inbox/outbox/dedup; danh tính lưu qua Android Keystore.
- Foreground service để duy trì hoạt động trong nền trong cùng process.
- Demo 3 node A–B–C và simulator tới 100 node, script benchmark.

SOS chỉ phát trong mạng các thiết bị đang dùng ứng dụng. Ứng dụng không tự gọi hoặc gửi tới cơ quan cứu hộ.

## Mở và chạy

Máy phát triển cần Flutter stable có Dart 3.13.3 trở lên, Android SDK và JDK tương thích Flutter/Gradle (máy hiện tại có sẵn Android Studio). Android tối thiểu 8.0/API 26. Chỉ nền tảng Android được tạo trong project này.

```powershell
cd D:\Projects\Mobile\ble_emergency_app
flutter pub get
flutter devices
flutter run -d <device-id>
```

Máy hiện tại có Flutter tại `C:\Dev\flutter`. Nếu terminal chưa tìm thấy Git/JDK, dùng script để tự tìm Git có sẵn và JDK của Android Studio trong phiên chạy:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\dev.ps1 -Action run
```

Script cũng hỗ trợ `-Action test`, `analyze`, `build`, `benchmark`; `-Device <device-id>` chọn máy khi chạy app. VS Code có cấu hình F5 trong `.vscode/launch.json`.

Chọn **Thử mô phỏng 3 thiết bị** để kiểm tra giao diện trên emulator. Với máy thật, chọn **Bật mạng Bluetooth**, cấp quyền Thiết bị lân cận. Android 11 trở xuống cần quyền vị trí và có thể cần bật dịch vụ vị trí để scan BLE. SOS xin vị trí GPS riêng; nếu không có GPS sau 12 giây vẫn gửi SOS không tọa độ.

```powershell
flutter analyze
flutter test
flutter build apk --debug
dart run tool/simulate.dart 50 6
dart run tool/simulate.dart 10 6 --no-dedup
dart run tool/benchmark.dart
```

APK build nằm tại `build/app/outputs/flutter-apk/app-debug.apk`; bản APK giao kèm nằm tại `dist/SOS-Mesh-debug.apk`. Đây là bản debug để kiểm thử; release cần signing key riêng.

Integration trên Android:

```powershell
flutter drive --driver=test_driver/integration.dart --target=integration_test/app_flow_test.dart -d <device-id>
```

## Cấu trúc

```text
lib/
  core/          Packet, body binary, identity, chữ ký/mã hóa
  transport/     Interface, Android bridge, fragmentation/reassembly
  routing/       Managed flooding, peer sync, ACK
  messaging/     SQLite và MemoryStore
  simulator/     Network giả và benchmark scenario
  app/           Điều phối UI
  main.dart      4 màn hình Flutter
android/app/src/main/kotlin/vn/emergency/ble_emergency_app/
  MainActivity.kt  Permission, method channel, GPS, Keystore
  BleEngine.kt     GATT client/server, advertising, scan, transmit queue
  MeshService.kt   Foreground service
test/              Kiểm thử unit + widget
integration_test/  Luồng ứng dụng và persistence trên Android
tool/              CLI simulate / benchmark
docs/              Kiến trúc, kế hoạch test, kết quả, screenshots
```

## Giới hạn cần biết

BLE máy thật chưa thể được xác nhận chỉ qua emulator. Cần ít nhất 3 điện thoại để kiểm tra relay ngoài tầm, background, tầm phủ và pin. Giới hạn TTL và kiểu dedup nhận đầu tiên có thể khiến một số node không nhận tin.

Tin broadcast chưa có ACK toàn mạng; UI không khẳng định cứu hộ đã nhận. Tin riêng ACK chỉ chứng minh app người nhận đã xử lý, không chứng minh một người đã đọc.

Số chặng đã đi (hopCount) không nằm trong chữ ký để relay không cần khóa người gửi. Relay độc hại có thể sửa số này: đặt bằng giới hạn để chặn tin đi tiếp, hoặc hạ xuống để tin đi xa hơn. Giới hạn chặng thì có chữ ký. Vì vậy số chặng hiển thị trên UI không phải bằng chứng về đường đi.

Chữ ký xác nhận khóa nguồn phát, không chứng minh tên/người/cơ quan ngoài đời. Mã hóa tin riêng chưa có forward secrecy; SQLite local chứa nội dung đã giải mã. Đối chiếu ID trực tiếp trước khi gửi tin nhạy cảm. Xem [kiến trúc](docs/ARCHITECTURE.md) và [kế hoạch kiểm thử](docs/TEST_PLAN.md) để tiếp tục đồ án.

Chưa triển khai iOS, bản đồ offline và giao diện điều chỉnh duty cycle. Không dùng số CPU simulator làm số đo latency BLE.

Kết quả bàn giao: analyzer sạch, 18 test đạt, integration Android đạt. Xem [kết quả xác minh](docs/VERIFICATION.md) và ảnh giao diện trong `docs/screenshots/`.
