# SOS Mesh

**Ứng dụng nhắn tin khẩn cấp không cần Internet.** Điện thoại Android gần nhau kết nối bằng Bluetooth Low Energy (BLE) thành một mạng lưới (mesh). Mỗi máy vừa gửi, vừa nhận, vừa là trạm chuyển tiếp, nên tin nhắn và tín hiệu SOS có thể đi qua nhiều máy để tới người ở xa ngoài tầm Bluetooth.

🔗 **GitHub:** https://github.com/LixusThinh/ble_emergency_app

Flutter + Kotlin · Android 8.0 trở lên (API 26) · Đồ án môn học

> SOS chỉ phát tới các điện thoại đang chạy ứng dụng trong mạng. Ứng dụng **không** tự gọi hay gửi tin tới cơ quan cứu hộ.

---

## Chức năng

### 1. Khẩn cấp
- **Nút SOS** phát tín hiệu cầu cứu tới mọi thiết bị trong mạng, **kèm tọa độ GPS** nếu có. Nếu sau 12 giây chưa lấy được GPS, SOS vẫn được gửi và ứng dụng báo rõ là không kèm vị trí.
- **Mô tả nhanh tình trạng** bằng các nút chọn sẵn: *Bị thương*, *Bị mắc kẹt*, *Cần nước uống*, *Cần thuốc*, hoặc tự gõ (tối đa 250 ký tự).
- **Cảnh báo SOS trên máy nhận:** hộp cảnh báo đỏ kèm rung, hiện tên người gửi, nội dung, số chặng đã đi, tọa độ GPS và nút sao chép tọa độ.
- **"Tôi an toàn":** báo cho cả mạng biết mình đã an toàn chỉ bằng một chạm.
- SOS được **ưu tiên gửi trước** mọi loại tin khác khi đồng bộ với máy mới gặp.

### 2. Nhắn tin
- **Tin công khai** gửi tới toàn mạng.
- **Tin riêng mã hóa đầu cuối:** máy trung gian chuyển tiếp nhưng không đọc được nội dung.
- **Xác nhận đã nhận (ACK) cho tin riêng:** trạng thái đổi từ ⏱ *Đang chờ xác nhận* sang ✓✓ *Người nhận đã xác nhận*. ACK được ký số và chỉ được chấp nhận khi đến từ đúng người nhận.
- **Hiện đúng tên người gửi** kể cả khi họ cách nhiều chặng.
- Mỗi tin nhận được ghi **số chặng đã đi** và trạng thái chữ ký hợp lệ.
- Giao diện chat dạng bong bóng; chọn người nhận bằng các chip ngay trên khung chat.

### 3. Mạng mesh và lưu chờ chuyển tiếp
- **Hai vai trò BLE cùng lúc:** mỗi máy vừa quảng bá như máy chủ GATT (peripheral), vừa quét và chủ động kết nối (central), nên không cần máy nào làm trung tâm.
- **Chuyển tiếp nhiều chặng:** mặc định tối đa 6 chặng, giới hạn giao thức là 15. Giới hạn chặng nằm trong phần có chữ ký.
- **Chống trùng lặp:** mỗi tin chỉ được xử lý và chuyển tiếp một lần, nên mạng không bị tin lặp tràn ngập.
- **Lưu chờ chuyển tiếp (store-and-forward):** tin gửi khi chưa gặp ai được lưu lại, rồi tự gửi khi gặp máy mới hoặc khi kết nối lại. Tin có hiệu lực 24 giờ. Một máy có thể "mang" tin từ người này tới người kia dù hai người chưa từng ở gần nhau.
- **Thứ tự ưu tiên khi đồng bộ:** SOS → ACK → "Tôi an toàn" → chat.
- **Phân mảnh gói tin** theo MTU của từng kết nối (23–185 byte) và ghép lại ở máy nhận, có giới hạn bộ nhớ và thời gian chờ.
- Khi thấy ACK hợp lệ, mọi máy đang giữ tin riêng đó, kể cả máy trung gian, đều ngừng chuyển tiếp nó.

### 4. Thiết bị trong mạng
- Danh sách **kết nối trực tiếp** kèm cường độ tín hiệu (RSSI, cột sóng), mức tín hiệu và MTU.
- Hai điện thoại thường kết nối với nhau hai lần (mỗi máy một vai trò); ứng dụng **gộp lại thành một thiết bị**.
- Danh sách **danh tính đã gặp** (cả trực tiếp lẫn qua nhiều chặng) và nút nhắn riêng nhanh.
- Xem và sao chép **ID thiết bị của mình** để đối chiếu với người nhận trước khi gửi tin nhạy cảm.

### 5. Bảo mật
- **Mọi gói tin đều ký số Ed25519.** Gói bị sửa nội dung hoặc giả mạo sẽ bị loại và không được chuyển tiếp.
- **Tin riêng:** trao đổi khóa X25519 → HKDF-SHA256 → mã hóa AES-256-GCM. Phần xác thực gắn với ID tin và người nhận.
- **ID thiết bị** = 8 byte đầu SHA-256 của khóa công khai.
- **Khóa danh tính** được mã hóa bằng khóa trong Android Keystore và không đưa vào bản sao lưu.
- Loại gói quá cũ (hơn 24 giờ) hoặc có thời gian lệch về tương lai quá 5 phút.

### 6. Chạy nền và lưu trữ
- **Foreground service:** mạng tiếp tục hoạt động khi tắt màn hình hoặc chuyển sang ứng dụng khác (có thông báo thường trực).
- **SQLite** lưu hộp thư đến, tin chờ gửi và bảng chống trùng. Tin vẫn còn sau khi tắt và mở lại ứng dụng.
- Xin quyền đúng theo phiên bản Android: *Thiết bị lân cận* (12+), *Vị trí* (11 trở xuống), *Thông báo* (13+), GPS khi gửi SOS.

### 7. Mô phỏng và đánh giá
- **Chế độ thử 3 thiết bị** (Bạn → Trạm tiếp sức → Đội cứu hộ): xem toàn bộ luồng ứng dụng mà không cần điện thoại thật hay Bluetooth.
- **Phòng mô phỏng 10–100 thiết bị ảo**, chỉnh giới hạn chặng 1–10. Kết quả gồm tỷ lệ nhận SOS, số BLE frame, số lượt chuyển tiếp, số gói trùng bị loại và phân bố số chặng. Mô phỏng chạy cùng code định tuyến, mã hóa và phân mảnh với ứng dụng thật, trong một isolate riêng nên giao diện không bị đứng.
- **Công cụ dòng lệnh:** `tool/simulate.dart` và `tool/benchmark.dart`.

Kết quả mô phỏng hiện tại (mạng vòng có thêm liên kết ngẫu nhiên, seed 42):

| Thiết bị | Giới hạn chặng | Số máy nhận SOS | Tỷ lệ nhận |
|---:|---:|---:|---:|
| 50 | 3 | 13/49 | 26.5% |
| 50 | 6 | 43/49 | 87.8% |
| 50 | 10 | 49/49 | 100% |
| 100 | 3 | 21/99 | 21.2% |
| 100 | 6 | 92/99 | 92.9% |
| 100 | 10 | 99/99 | 100% |

Mô phỏng không có mô hình mất gói, sóng vô tuyến hay pin, nên đây không phải kết quả đo thực địa.

---

## Cài đặt nhanh

**Cài lên điện thoại:** build bản release rồi gửi file APK sang máy (Zalo, Drive…) và mở để cài.

```powershell
git clone https://github.com/LixusThinh/ble_emergency_app.git
cd ble_emergency_app
flutter pub get
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

**Chạy khi phát triển:** `flutter run -d <device-id>`. Trên máy ảo, chọn **Thử mô phỏng 3 thiết bị**, vì máy ảo không có Bluetooth thật.

Mọi điện thoại cùng thử nghiệm phải cài **cùng một bản build**. Bản trước ngày 18/10/2026 dùng định dạng tin cũ và không đọc được tin của bản mới.

Hướng dẫn đầy đủ (môi trường, script, test, integration): [README.vi.md](README.vi.md).

---

## Cấu trúc mã nguồn

```text
lib/
  main.dart        Điểm khởi động ứng dụng
  ui/              Giao diện: theme, các tab Khẩn cấp / Tin nhắn / Thiết bị / Đánh giá
  app/             AppController: điều phối giao diện và mạng
  core/            Gói tin nhị phân, danh tính, chữ ký, mã hóa
  routing/         Định tuyến mesh: chống trùng, giới hạn chặng, ACK, lưu chờ chuyển tiếp
  transport/       Giao tiếp BLE, phân mảnh và ghép gói
  messaging/       Lưu trữ SQLite và bộ nhớ tạm
  simulator/       Mạng giả lập và kịch bản đánh giá
android/.../ble_emergency_app/
  BleEngine.kt     GATT client/server, quảng bá, quét, hàng đợi truyền
  MainActivity.kt  Quyền, kênh Flutter ↔ Kotlin, GPS, Keystore
  MeshService.kt   Foreground service
test/              Unit test và widget test
integration_test/  Luồng ứng dụng trên Android
tool/              Mô phỏng và benchmark bằng dòng lệnh
docs/              Kiến trúc, kế hoạch kiểm thử, kết quả xác minh
```

## Kiểm thử

- `flutter analyze`: không có lỗi.
- `flutter test`: **21/21 test đạt**. Các test gồm: ký và chống sửa gói, phân mảnh MTU 23, chuyển tiếp A–B–C, chống trùng trên mạng tam giác, lưu chờ chuyển tiếp, ACK, gói giả mạo, ưu tiên SOS, tên người gửi qua nhiều chặng, gộp kết nối trùng, giao diện trên màn hình nhỏ.
- Integration test trên Android đạt ở bản ngày 06/10/2026, **chưa chạy lại** sau khi làm lại giao diện.
- **BLE trên điện thoại thật chưa được kiểm chứng.** Kế hoạch đo nằm ở [docs/TEST_PLAN.md](docs/TEST_PLAN.md).

## Giới hạn

- Tin công khai không có xác nhận toàn mạng; ACK chỉ có cho tin riêng và chỉ chứng minh ứng dụng người nhận đã xử lý tin, không chứng minh người đó đã đọc.
- Số chặng hiển thị không có chữ ký, nên máy trung gian xấu có thể sửa. Đây không phải bằng chứng về đường đi.
- Tên hiển thị là tên tự khai; chữ ký chỉ chứng minh khóa phát tin, không chứng minh danh tính ngoài đời.
- Chưa có forward secrecy; cơ sở dữ liệu trên máy lưu nội dung đã giải mã.
- Chưa hỗ trợ iOS và bản đồ offline. Bản release hiện vẫn ký bằng debug key.

## Tài liệu

- [Kiến trúc và giao thức](docs/ARCHITECTURE.md)
- [Kế hoạch kiểm thử](docs/TEST_PLAN.md)
- [Kết quả xác minh](docs/VERIFICATION.md)
- [Hướng dẫn chạy chi tiết](README.vi.md)

## Tác giả

**Lixusthinh** · [github.com/LixusThinh](https://github.com/LixusThinh)
