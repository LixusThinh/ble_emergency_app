# SOS Mesh

**Ứng dụng nhắn tin khẩn cấp không cần Internet.** Điện thoại Android gần nhau kết nối bằng Bluetooth Low Energy (BLE) thành một mạng lưới (mesh). Mỗi máy vừa gửi, vừa nhận, vừa là trạm chuyển tiếp, nên tin nhắn và tín hiệu SOS có thể đi qua nhiều máy để tới người ở xa ngoài tầm Bluetooth.

🔗 **GitHub:** https://github.com/LixusThinh/ble_emergency_app

Flutter + Kotlin · Android 8.0 trở lên (API 26) · Đồ án môn học

> SOS chỉ phát tới các điện thoại đang chạy ứng dụng trong mạng. Ứng dụng **không** tự gọi hay gửi tin tới cơ quan cứu hộ.

---

## Chức năng

### 1. Khẩn cấp
- **Nút SOS** phát tín hiệu cầu cứu tới mọi thiết bị trong mạng, **kèm tọa độ GPS** nếu có. Nếu sau 12 giây chưa lấy được GPS, SOS vẫn được gửi và ứng dụng báo rõ là không kèm vị trí.
- **Mô tả nhanh tình trạng** bằng các nút chọn sẵn (bật/tắt): *Bị thương*, *Bị mắc kẹt*, *Cần nước uống*, *Cần thuốc*, kèm ghi chú tự gõ (tối đa 200 ký tự). Hộp thoại hiện trước đúng nội dung sẽ gửi.
- **Cảnh báo SOS trên máy nhận:** hộp cảnh báo đỏ kèm rung, hiện tên người gửi, nội dung, số chặng đã đi, tọa độ GPS và nút sao chép tọa độ.
- **"Tôi an toàn":** báo cho cả mạng biết mình đã an toàn chỉ bằng một chạm.
- SOS được **ưu tiên gửi trước** mọi loại tin khác, kể cả khi đang đồng bộ tồn đọng với máy khác.
- Dưới tin mình gửi có dòng **"Chưa đến máy nào" / "Đã đến N máy gần"**, để biết SOS đã thực sự rời khỏi máy chưa.

### 2. Nhắn tin
- **Tin công khai** gửi tới toàn mạng.
- **Tin riêng mã hóa đầu cuối:** máy trung gian chuyển tiếp nhưng không đọc được nội dung.
- **Xác nhận đã nhận (ACK) cho tin riêng:** trạng thái đổi từ ⏱ *Đang chờ xác nhận* sang ✓✓ *Người nhận đã xác nhận*. ACK được ký số và chỉ được chấp nhận khi đến từ đúng người nhận.
- **Hiện đúng tên người gửi** kể cả khi họ cách nhiều chặng.
- Mỗi tin nhận được ghi **số chặng đã đi** và trạng thái chữ ký hợp lệ.
- Giao diện chat dạng bong bóng, **tách theo cuộc trò chuyện**: chip *Toàn mạng* chỉ hiện kênh chung (SOS, an toàn, tin công khai); chip tên một người chỉ hiện tin riêng với người đó. Tin được nhóm theo ngày (*Hôm nay*, *Hôm qua*, ngày cụ thể).
- **Giao diện sáng/tối** theo cài đặt hệ thống; nhãn trạng thái mạng ở đầu màn hình bấm được để mở danh sách thiết bị; hỗ trợ TalkBack cho nút SOS, tiêu đề và cảnh báo.

### 3. Mạng mesh và lưu chờ chuyển tiếp
- **Hai vai trò BLE cùng lúc:** mỗi máy vừa quảng bá như máy chủ GATT (peripheral), vừa quét và chủ động kết nối (central), nên không cần máy nào làm trung tâm.
- **Chuyển tiếp nhiều chặng:** mặc định tối đa 6 chặng, giới hạn giao thức là 15. Giới hạn chặng nằm trong phần có chữ ký.
- **Chống trùng lặp:** mỗi tin chỉ được xử lý và chuyển tiếp một lần, nên mạng không bị tin lặp tràn ngập.
- **Lưu chờ chuyển tiếp (store-and-forward):** tin gửi khi chưa gặp ai được lưu lại, rồi tự gửi khi gặp máy mới hoặc khi kết nối lại. Tin có hiệu lực 24 giờ. Một máy có thể "mang" tin từ người này tới người kia dù hai người chưa từng ở gần nhau.
- **Thứ tự ưu tiên khi đồng bộ:** SOS → ACK → "Tôi an toàn" → chat.
- **Phân mảnh gói tin** theo MTU của từng kết nối (23–185 byte) và ghép lại ở máy nhận, có giới hạn bộ nhớ và thời gian chờ.
- Khi thấy ACK hợp lệ, mọi máy đang giữ tin riêng đó, kể cả máy trung gian, đều ngừng chuyển tiếp nó.
- **Mỗi máy kề một hàng đợi gửi riêng:** đồng bộ tồn đọng cho một máy không làm chậm việc nhận tin từ máy khác. Hai kết nối tới cùng một điện thoại chỉ gửi mỗi gói một lần (trước đây gửi hai lần và dội ngược lại). Gửi lỗi được tự thử lại mỗi 30 giây mà không cần ngắt kết nối.
- Kho 5000 gói khi đầy bỏ gói đã xác nhận trước, rồi bỏ từ người đang giữ nhiều gói nhất, nên một máy phát tràn không đẩy được SOS của người khác ra.

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
- **Database mã hóa toàn bộ** (SQLite3 Multiple Ciphers, ChaCha20): tin nhắn, danh bạ và cài đặt trên máy không đọc được nếu thiếu khóa. Khóa ngẫu nhiên 256 bit do Android Keystore giữ. Bản cũ chưa mã hóa được tự mã hóa khi cập nhật, giữ nguyên dữ liệu.
- Loại gói quá cũ (hơn 24 giờ) hoặc có thời gian lệch về tương lai quá 5 phút.
- **Chống flood:** mỗi người gửi có hạn mức (200 gói một lúc, sau đó 30 gói/phút; SOS 10 gói, sau đó 2/phút). Gói vượt hạn mức không được lưu hay chuyển tiếp. Kết nối gửi nhiều gói giả chữ ký bị bỏ qua 5 phút.

### 6. Chạy nền và lưu trữ
- **Foreground service:** mạng tiếp tục hoạt động khi tắt màn hình hoặc chuyển sang ứng dụng khác (có thông báo thường trực).
- **SQLite** lưu hộp thư đến, tin chờ gửi, bảng chống trùng, **danh bạ** các máy đã gặp và **cài đặt** (tên hiển thị, giao diện sáng/tối). Mở lại ứng dụng vẫn còn tin, tên của mọi người và có thể nhắn riêng ngay mà không cần chờ gặp lại.
- Database có **đánh số phiên bản và migration**: bản cập nhật nâng schema tại chỗ, giữ nguyên dữ liệu cũ.
- **Hiệu năng:** giao diện chỉ đọc lại những tin vừa thay đổi thay vì cả 2000 tin; chữ ký của gói nhận được kiểm trên một isolate nền nên đồng bộ hàng trăm gói không làm đứng màn hình; bảng đầy được cắt theo lô thay vì sắp xếp lại mỗi lần ghi. Số đo trước/sau trong [VERIFICATION.md](docs/VERIFICATION.md), đo lại bằng `flutter test benchmark/perf_test.dart`.
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
- `flutter test`: **77/77 test đạt** (trong đó 13 test chống flood: hạn mức theo người gửi, gói giả không làm cạn hạn mức của người thật, tắt tiếng kết nối gửi gói giả, chia đều kho theo người gửi, migration v5; 7 test mã hóa database: không khóa/sai khóa không mở được, nâng cấp DB cũ chưa mã hóa giữ dữ liệu, khôi phục khi bị ngắt giữa chừng, mất khóa; 10 test chạy SQLite thật qua FFI: migration từ bản 1.0.0, danh bạ, cài đặt, khôi phục danh bạ sau khởi động lại, đếm máy đã nhận, thứ tự bỏ gói khi đầy, đọc tin theo revision, cắt bảng tin; 9 test router: hai kết nối một máy, SOS không bị kẹt sau tồn đọng, thử lại khi gửi lỗi, không gửi ngược, kết nối không chào hỏi; 4 test isolate kiểm chữ ký; 4 test controller: gộp và đọc tăng dần). Các test gồm: ký và chống sửa gói, phân mảnh MTU 23, chuyển tiếp A–B–C, chống trùng trên mạng tam giác, lưu chờ chuyển tiếp, ACK, gói giả mạo, ưu tiên SOS, tên người gửi qua nhiều chặng, gộp kết nối trùng, giao diện trên màn hình nhỏ, giao diện tối, lọc tin theo cuộc trò chuyện, soạn SOS, nhãn ngày.
- Integration test trên Android (emulator Pixel 7 Pro, API 37) **đạt ngày 07/11/2026** sau khi nâng cấp hiệu năng, kể cả nâng cấp database lên v5 (đã mã hóa) giữ nguyên dữ liệu; ảnh trong `docs/screenshots/` chụp từ lần chạy này.
- **BLE trên điện thoại thật chưa được kiểm chứng.** Kế hoạch đo nằm ở [docs/TEST_PLAN.md](docs/TEST_PLAN.md).

## Giới hạn

- Tin công khai không có xác nhận toàn mạng; ACK chỉ có cho tin riêng và chỉ chứng minh ứng dụng người nhận đã xử lý tin, không chứng minh người đó đã đọc.
- Số chặng hiển thị không có chữ ký, nên máy trung gian xấu có thể sửa. Đây không phải bằng chứng về đường đi.
- Tên hiển thị là tên tự khai; chữ ký chỉ chứng minh khóa phát tin, không chứng minh danh tính ngoài đời.
- Chưa có forward secrecy. Database trên máy đã mã hóa, nhưng khi app đang chạy thì khóa nằm trong bộ nhớ, nên máy đã root vẫn đọc được.
- Chưa hỗ trợ iOS và bản đồ offline. Bản release hiện vẫn ký bằng debug key.

## Tài liệu

- [Kiến trúc và giao thức](docs/ARCHITECTURE.md)
- [Kế hoạch kiểm thử](docs/TEST_PLAN.md)
- [Kết quả xác minh](docs/VERIFICATION.md)
- [Hướng dẫn chạy chi tiết](README.vi.md)

## Nhóm thực hiện

| STT | Họ và tên | MSSV | Vai trò |
|:---:|---|---|---|
| 1 | Trần Gia Thịnh | 2380602136 | Nhóm trưởng |
| 2 | Đỗ Minh Quang | 2380601802 | Thành viên |
| 3 | Nguyễn Thanh Hải | 1911065203 | Thành viên |
| 4 | Hồ Uy Thiện | 2380602107 | Thành viên |

Repo: [github.com/LixusThinh/ble_emergency_app](https://github.com/LixusThinh/ble_emergency_app)
