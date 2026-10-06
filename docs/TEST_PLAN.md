# Kế hoạch kiểm thử và đo đạc

## Tự động

```powershell
flutter analyze
flutter test
dart run tool/benchmark.dart
flutter drive --driver=test_driver/integration.dart --target=integration_test/app_flow_test.dart -d <device-id>
```

`flutter test`: packet binary/chữ ký, tamper, khôi phục danh tính, MTU 23, ghép đảo thứ tự, fragment sai, A–B–C, TTL, vòng dedup, gặp thiết bị gián đoạn, ciphertext/ACK, ACK sai người, relay ngừng chuyển tin riêng đã có ACK, kết nối lại không gửi lại hello cũ, báo lại MTU không đồng bộ lại và ưu tiên SOS trong outbox; thêm kiểm thử layout trên màn hình 360×800.

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
