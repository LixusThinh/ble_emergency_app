# Kế hoạch kiểm thử và đo đạc

Nhóm thực hiện: **Trần Gia Thịnh** (nhóm trưởng, 2380602136), Đỗ Minh Quang (2380601802), Nguyễn Thanh Hải (1911065203), Hồ Uy Thiện (2380602107).

## Tự động

```powershell
flutter analyze
flutter test
dart run tool/benchmark.dart
flutter drive --driver=test_driver/integration.dart --target=integration_test/app_flow_test.dart -d <device-id>
```

`flutter test`: packet binary/chữ ký, tamper, khôi phục danh tính, MTU 23, ghép đảo thứ tự, fragment sai, A–B–C, TTL, vòng dedup, gặp thiết bị gián đoạn, ciphertext/ACK, ACK sai người, relay ngừng chuyển tin riêng đã có ACK, kết nối lại không gửi lại hello cũ, báo lại MTU không đồng bộ lại, vẫn relay broadcast có body không đọc được và ưu tiên SOS trong outbox; thêm kiểm thử layout trên màn hình 360×800 và banner lỗi đã đóng không hiện lại.

Integration chạy trên Android: lưu/đọc lại Keystore, SQLite qua đóng/mở database, màn hình ban đầu, demo ba node, gửi SOS, nhắn riêng và ACK, chạy simulator. Ảnh giao diện lưu vào `docs/screenshots/` bằng test driver. Integration không kiểm tra sóng BLE.

## Mô phỏng 50–100 node

`tool/benchmark.dart` tạo vòng kết nối và thêm liên kết từ seed topology 42. Các node không di chuyển, không mô hình RF, pin, mất packet hoặc độ trễ vô tuyến. Crypto identity vẫn ngẫu nhiên nhưng không thay topology. `computeMs` chỉ là thời gian xử lý trên CPU, không phải latency mesh.

Kết quả chạy thật của simulator nằm trong `simulation-results.json`. So sánh chống trùng dùng cùng topology 10 node, TTL 6, hai chế độ bật/tắt dedup. Đây là so sánh chống trùng; chưa đánh giá ưu tiên dưới tắc nghẽn, vì mạng giả không mô hình bandwidth/queue congestion.

## Máy thật: 3–5 Android có peripheral

1. Cài cùng APK, bật Bluetooth và cấp quyền. Có thể bật airplane mode rồi bật lại Bluetooth. GPS cần bật nếu muốn tọa độ.
2. Hai máy: xác nhận scan + advertising, GATT write và indication đều nhận được tin hai chiều. Thử MTU thực tế, tên, RSSI và mất kết nối.
3. Ba máy A–B–C: đặt A và C ngoài tầm trực tiếp; xác nhận danh sách peer không có A–C. Gửi SOS A, kiểm tra C nhận hai chặng.
4. Gián đoạn: gửi tin khi A đơn độc, cho A gặp B, tách A/B, cho B gặp C; kiểm tra C nhận tin lưu. Lặp lại sau khi đóng/mở ứng dụng B.
5. Nhắn riêng: xác nhận C là recipient, B không hiện nội dung riêng, A nhận ACK từ C. Thử tắt C trước khi ACK tới A và kết nối lại.
6. Screen-off/background 30–60 phút: so sánh từng hãng, kiểm tra service, nguồn điện và việc hệ điều hành dừng process. Force-stop không tự khởi động lại.
7. Chạy thêm Android 8–11 và Android 12+; thử từ chối quyền, Bluetooth tắt, GPS chưa có fix, thu hồi quyền, peripheral không hỗ trợ.

## Hạn mức chống flood khi thử nghiệm

Chống flood (`lib/routing/flood_guard.dart`) cũng áp dụng cho máy của nhóm khi thử. Máy trung gian chỉ nhận và chuyển tiếp từ **mỗi máy gửi**:

| Loại tin | Một lúc | Sau đó |
|---|---:|---:|
| Chat, tin riêng, "Tôi an toàn", ACK, HELLO | 200 | 30 tin/phút |
| SOS | 10 | 2 tin/phút |

- Máy gửi luôn lưu đủ tin của mình, chỉ máy trung gian bỏ phần vượt hạn mức. Trên giao diện không có thông báo nào; gói bị bỏ chỉ được đếm vào `RouterStats.limited`.
- Phần bị bỏ vẫn nằm trong hàng chờ của máy gửi và được gửi lại khi hai máy **ngắt rồi kết nối lại** (nếu hạn mức đã hồi). Trong lúc kết nối vẫn giữ nguyên, máy gửi không tự gửi lại, vì việc gửi không bị lỗi.
- Hạn mức nằm trong bộ nhớ của máy trung gian. Mở lại app trên máy đó sẽ đặt lại hạn mức.
- Kết nối gửi 20 gói sai cấu trúc hoặc sai chữ ký trong 1 phút bị bỏ qua 5 phút (đếm vào `RouterStats.ignoredFrames`). Máy cài cùng một bản build sẽ không gặp trường hợp này. Nếu thấy bị bỏ qua, kiểm tra xem các máy có cài cùng APK không.

Để không nhầm hạn mức với lỗi mạng:

1. Đo tỷ lệ tới đích bằng **chat**, không dùng SOS. Mỗi lượt ≥30 tin vẫn nằm trong hạn mức 200.
2. Lượt dài hơn 200 tin từ cùng một máy thì gửi chậm hơn 30 tin/phút (cách nhau ≥2 giây), hoặc chia thành nhiều lượt cách nhau vài phút.
3. Bài thử SOS: không bấm quá 10 SOS liên tục từ một máy; sau đó cách nhau ≥30 giây.
4. Bài đo cần gửi dồn nhiều tin hơn thì dùng bản build tăng hạn mức, ví dụ `MeshRouter(..., guard: FloodGuard(burst: 5000, sosBurst: 1000))`, như `benchmark/perf_test.dart`. Ghi rõ trong cột "Ghi chú" của biểu mẫu là đã đổi hạn mức.
5. Giữa các lượt đo, mở lại app trên các máy trung gian để bắt đầu với hạn mức đầy.

## Biểu mẫu số đo thực nghiệm

Không điền số đo giả. Mỗi cấu hình nên ≥30 tin, ghi phiên bản Android/thiết bị, vị trí, môi trường và lặp thử.

| Run | Thiết bị | Trong/ngoài nhà | TTL | Chặng | Tin gửi | Tin nhận | Median/P95 latency ms | RSSI dBm | Khoảng cách m | Pin %/giờ | Ghi chú |
|---|---|---|---:|---:|---:|---:|---|---|---|---|---|
| | | | | | | | | | | | |

- Delivery ratio = số ID duy nhất đến đích / số tin nguồn phát.
- Latency end-to-end cần đồng bộ đồng hồ trước khi offline, ghi độ lệch; hoặc dùng round-trip ACK. RTT không tự suy ra latency từng hop nếu không có log tại từng node.
- Latency từng hop: instrument thời điểm nhận đủ packet và lúc gửi tại mỗi node, ghi cùng ID; hiện chưa có logger thực nghiệm này.
- Pin: ghi model, dung lượng, brightness, screen-off, thời gian, baseline không BLE, và scan duty cycle. Mặc định code 12s/18s; thay cấu hình trong `BleEngine.kt` khi so sánh.
- RSSI không quy đổi đáng tin sang mét nếu chưa hiệu chuẩn môi trường và anten.

## Phần chưa triển khai

iOS/Windows BLE, bản đồ offline, cấu hình tiết kiệm pin trong UI, cơ chế liên hệ cơ quan cứu hộ, log thời gian từng hop và đánh giá pin/tầm phủ ngoài đời. Những phần này không được tính là kết quả đã kiểm chứng.
