# Kiến trúc SOS Mesh

## Phạm vi

Project triển khai Flutter + Kotlin, Android API 26 trở lên. Bản thảo Word là nguồn yêu cầu sản phẩm. Những gợi ý về package hoặc lịch triển khai trong bản thảo không phải lệnh tác vụ tự động; lựa chọn triển khai dưới đây dựa trên chức năng cần có.

## Bốn tầng

```text
Flutter UI / AppController
          ↓
Messaging: Identity, AES-GCM, Ed25519, MessageStore
          ↓
Routing: MeshRouter, dedup, TTL, ACK, store-and-forward
          ↓
MeshTransport
    ├── AndroidBleTransport → MethodChannel → Kotlin BleEngine
    └── SimTransport → SimNetwork (không dùng BLE)
```

Transport chỉ biết peer, MTU và frame. Router nhận frame, ghép packet, xác minh chữ ký rồi lưu/chuyển tiếp. Simulator dùng chính router, crypto và bộ phân mảnh của ứng dụng, với MemoryStore thay SQLite.

Đánh giá nhiều node từ UI chạy trong Dart isolate riêng để chữ ký/mô phỏng không chặn luồng render. Emulator debug có thể xử lý crypto chậm; script CLI thuận tiện hơn cho benchmark 50–100 node.

## BLE Android

- Service UUID: `a8c10001-37d5-4b52-9c40-9ad6819b3000`.
- Characteristic UUID: `a8c10002-37d5-4b52-9c40-9ad6819b3000`.
- Mỗi máy quảng bá service, mở GATT server, đồng thời scan/connect như central.
- Central gửi bằng write có response. Peripheral gửi bằng indication sau khi peer bật CCCD.
- Một thao tác truyền đang chờ callback tại một thời điểm; timeout 10 giây. Mỗi peer có MTU riêng. MTU yêu cầu 185; fallback 23.
- Scan 12 giây, nghỉ 18 giây. Thử lại kết nối sau 30 giây; tối đa 4 kết nối central. Thực tế số kết nối đồng thời tùy phần cứng.
- Foreground service loại `connectedDevice`; FlutterEngine giữ trong process khi Activity bị hủy. Không tự khởi động sau reboot/force-stop/process kill. Background vẫn cần xác minh trên từng hãng điện thoại.
- Quyền BLE Android 12+ xin khi bật mạng; Android cũ xin vị trí cho scan. GPS xin riêng khi gửi SOS. Android 13+ vẫn có foreground service dù quyền thông báo chưa được cấp; người dùng có thể bật thông báo trong cài đặt.
- Không dùng `flutter_blue_plus` / plugin peripheral: bridge Kotlin triển khai cả hai vai trò để tránh phối hợp hai plugin có vòng đời GATT khác nhau.

## Wire protocol v1

Đa byte dùng big-endian. Không có JSON trên BLE.

| Offset | Byte | Ý nghĩa |
|---|---:|---|
| 0 | 2 | Magic `EM` |
| 2 | 1 | Version = 1 |
| 3 | 1 | Loại: SOS, safe, chat, private, hello, ACK |
| 4 | 1 | Giới hạn chặng, 1–15 |
| 5 | 1 | Số chặng đã đi |
| 6 | 8 | Unix timestamp milliseconds |
| 14 | 16 | Message ID ngẫu nhiên |
| 30 | 32 | Public key Ed25519 |
| 62 | 32 | Public key X25519 |
| 94 | 8 | Node ID người nhận; toàn 0 = broadcast |
| 102 | 2 | Độ dài payload |
| 104 | N | Payload, tối đa 4096 byte |
| 104+N | 64 | Chữ ký Ed25519 |

Node ID = 8 byte đầu SHA-256(public signing key). Header và payload được ký, trừ byte hopCount được chuẩn hóa về 0 để relay không cần khóa người gửi. Giới hạn chặng có chữ ký. Relay thiện chí tăng hopCount mỗi lần gửi. Relay độc hại có thể sửa hopCount; đây không phải cơ chế kiểm chứng đường đi.

Body công khai: flag vị trí 1 byte; nếu có, latitude và longitude là hai float64; còn lại UTF-8. Nội dung gửi từ UI tối đa 2000 byte UTF-8. HELLO chứa tên hiển thị trong body. ACK chứa đúng 16 byte ID tin đã nhận.

Frame có header 12 byte: magic `F`, version, token 4 byte, index uint16, totalFragments uint16, totalLength uint16. Dữ liệu mỗi frame ≤ MTU−3. MTU 23 còn 8 byte dữ liệu sau header frame. Ghép theo peer+token, tối đa 64 assembly, hết hạn sau 30 giây, giới hạn 1024 fragment và 4264 byte/packet. Fragment chưa xác thực riêng; chỉ tin packet sau khi đủ dữ liệu và xác minh chữ ký.

## Routing và store-and-forward

1. Kết nối mới: gửi HELLO ký số, sau đó sync gói lưu chưa hết hạn.
2. Tin mới: ký/mã hóa, lưu packet và bản ghi UI trước khi gửi.
3. Nhận packet: kiểm tra cấu trúc, dedup, tuổi tin (24 giờ), lệch thời gian tương lai ≤5 phút và chữ ký.
4. Nhận tin của mình hoặc broadcast: lưu inbox. Với tin riêng gửi ACK có chữ ký.
5. Nếu còn chặng và không phải tin riêng đã đến đích: gửi cho các peer khác nguồn vào.
6. Outbox sync ưu tiên SOS → ACK → trạng thái → HELLO → chat. Không ngắt một packet đang truyền để chen SOS.
7. Gặp peer mới hoặc kết nối lại: sync gói chưa hết hạn. Dedup/pending dùng cùng bảng packets; tối đa 5000 gói. Tin UI giữ tối đa 2000 bản ghi.

ACK chỉ xác nhận tin riêng, và chỉ được chấp nhận khi sender của ACK trùng recipient của tin gốc. Broadcast không có xác nhận toàn mạng; UI chỉ thể hiện đã lưu/chuyển tiếp. Tin lỗi gửi được giữ để thử khi kết nối lại. Không có retry vô hạn trên kết nối đang giữ nguyên.

Thuật toán giữ bản nhận đầu tiên, nên tuyến dài đến trước có thể làm giảm độ phủ trong giới hạn TTL; không đảm bảo tìm đường ngắn nhất. Tin relay vẫn được giữ dù đích đã nhận, đến hết thời hạn. Không có global ACK cho broadcast.

## Bảo mật

- Ed25519 mọi packet, public key X25519 nằm trong nội dung được ký.
- Tin riêng: X25519 tĩnh → HKDF-SHA256, salt = message ID, context `emergency-mesh-v1/private` → AES-256-GCM nonce 12 byte, tag 16 byte. AAD ràng buộc ID và recipient.
- Relay chỉ lưu/chuyển ciphertext tin riêng; không đưa vào inbox của relay.
- Seeds danh tính được mã hóa AES-GCM bằng khóa Android Keystore, lưu ciphertext trong SharedPreferences, tắt backup.
- Tên hiển thị không chứng minh danh tính. So sánh ID qua kênh đáng tin trước khi gửi tin nhạy cảm. Không có danh bạ được xác minh trước hoặc chứng chỉ cơ quan cứu hộ.
- Chưa có forward secrecy, key ratchet, cơ chế chống Sybil hoặc chống spam theo danh tính. Headers làm lộ metadata.
- SQLite trong sandbox ứng dụng chứa nội dung inbox/outbox đã giải mã; chưa mã hóa database. Đây là bản đồ án cần audit trước khi dùng cho vận hành cứu hộ.

## Nguồn kỹ thuật

- [Android Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [BLE background](https://developer.android.com/develop/connectivity/bluetooth/ble/background)
- [GATT transfer](https://developer.android.com/develop/connectivity/bluetooth/ble/transfer-ble-data)
- [Dart cryptography](https://pub.dev/packages/cryptography)
