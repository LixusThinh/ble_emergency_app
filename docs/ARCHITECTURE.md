# Kiến trúc SOS Mesh

Nhóm thực hiện: **Trần Gia Thịnh** (nhóm trưởng, 2380602136), Đỗ Minh Quang (2380601802), Nguyễn Thanh Hải (1911065203), Hồ Uy Thiện (2380602107).

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

Đánh giá nhiều node từ UI chạy trong Dart isolate riêng để chữ ký/mô phỏng không chặn luồng render. Ở chế độ BLE, chữ ký Ed25519 của gói nhận được (khoảng 3 ms mỗi gói bằng Dart thuần) được kiểm trên một isolate nền (`CryptoWorker`), nên đồng bộ hàng trăm gói không làm đứng giao diện. Ký tin của mình và giải mã tin riêng vẫn chạy trên isolate giao diện (mỗi tin một lần).

Giao diện đọc kho theo kiểu tăng dần: một đợt cập nhật dồn dập chỉ tốn một lần đọc đang chạy cộng tối đa một lần đọc nữa, và mỗi lần đọc chỉ trả các tin đã thay đổi. Emulator debug có thể xử lý crypto chậm; script CLI thuận tiện hơn cho benchmark 50–100 node.

## Lưu trữ SQLite (schema v5)

File `emergency_mesh.db` trong sandbox ứng dụng, **mã hóa toàn bộ** (xem bên dưới). Mã: `lib/messaging/schema.dart` (schema, migration, mở và mã hóa database), `sqlite_store.dart` (tin, gói, danh bạ), `settings_store.dart` (cài đặt), `lib/app/storage.dart` (lấy khóa từ Android lúc mở app).

| Bảng | Nội dung | Giới hạn |
|---|---|---|
| `packets` | Gói đã xác minh: chống trùng và hàng chờ store-and-forward; `acked` = đã có ACK hợp lệ; `origin` (v5) = khóa ký của người gửi | 24 giờ, tối đa 5000; khi đầy bỏ gói đã ACK trước, rồi bỏ từ người gửi đang giữ nhiều gói nhất (xem *Chống flood*) |
| `messages` | Inbox/outbox đã giải mã hiển thị trên UI | 2000 tin mới nhất (bảng được cắt theo lô khi vượt 2100) |
| `contacts` (v2) | Node đã gặp: ID, tên tự khai, khóa trao đổi công khai, lần cuối thấy | 500 node gần nhất |
| `settings` (v2) | Cặp khóa/giá trị: `display_name`, `theme_mode` | — |
| `handoffs` (v3) | Tin của chính mình đã trao cho máy kề nào (ID tin, ID máy) | Xóa theo tin khi tin bị cắt khỏi `messages` |

Cột `packets.origin` (v5) được điền cho gói cũ khi nâng cấp bằng cách đọc khóa ký trong gói; gói không đọc được nhận giá trị rỗng.

Cột `messages.rev` (v4): mỗi lần ghi, xác nhận ACK hoặc thêm máy đã nhận đều tăng số phiên bản của tin. Giao diện chỉ đọc các tin có `rev` lớn hơn lần đọc trước (`changes()`), không đọc lại cả 2000 tin.

Index: `packets(created)`, `packets(acked, priority, created)` cho `pending()`, `messages(created)` cho danh sách tin, `messages(rev)` cho `changes()`, `contacts(last_seen)`.

- **Cắt bảng theo lô:** số dòng được giữ trong bộ nhớ, nên mỗi lần ghi không phải sắp xếp lại cả bảng. Khi `packets` chạm 5000 dòng, một lần xóa 100 dòng ít hữu ích nhất; `messages` được cắt về 2000 khi vượt 2100. Gói hết hạn được xóa tối đa mỗi phút một lần (`pending()` vốn đã bỏ qua chúng).

- **Migration:** mỗi phiên bản là một bước trong `_migrations`; cài mới chạy từ bước 1, nâng cấp chạy các bước còn thiếu trong một transaction. Không sửa bước đã phát hành, chỉ thêm bước mới và tăng `schemaVersion`. Hạ phiên bản (cài APK cũ đè lên) không được hỗ trợ.
- **Kết nối:** WAL và `busy_timeout` 3 giây. Cài đặt dùng một kết nối riêng mở suốt vòng đời app; kho tin mở khi bật mạng và đóng khi tắt mạng, nên đóng kho tin không làm mất cài đặt.
- **Danh bạ:** router nạp danh bạ khi khởi động, nên tên người gửi và nhắn riêng dùng được ngay sau khi mở lại app, trước khi gặp lại máy kia. Router ghi khi gặp node mới, khi tên hoặc khóa thay đổi, hoặc khi lần ghi trước đã quá 1 phút.
- Mất file cài đặt hoặc lỗi mở database lúc khởi động không chặn app: cài đặt chuyển sang bộ nhớ tạm và chỉ không được lưu.

### Mã hóa database

- **Engine:** SQLite3 Multiple Ciphers (SQLite 3.54, ChaCha20-Poly1305 theo trang), đóng gói cùng app qua `package:sqlite3` (hook `source: sqlite3mc` trong `pubspec.yaml`) và dùng qua `sqflite_common_ffi`. Điện thoại và test trên máy tính/CI chạy cùng một engine, nên test kiểm được mã hóa thật. Mọi trang, kể cả file WAL, đều được mã hóa.
- **Khóa:** 32 byte ngẫu nhiên (`SecureRandom`), tạo lần đầu mở app. Khóa được bọc bằng khóa AES-GCM `mesh-database-v1` nằm trong Android Keystore (không rời thiết bị), lưu ở `shared_prefs/database.xml`. Khóa được ghi xuống đĩa (`commit()`) trước khi mã hóa database. `android:allowBackup="false"`.
- **Nâng cấp từ bản chưa mã hóa:** lần đầu mở bản mới, `useMeshDatabase` thấy header `SQLite format 3` thì gộp WAL vào file chính, chép một bản `.plain`, mã hóa tại chỗ bằng `PRAGMA hexrekey`, mở thử bằng khóa rồi xóa bản chép. Nếu app bị tắt giữa chừng, lần mở sau khôi phục từ bản `.plain` và làm lại.
- **Mất khóa** (Keystore bị xóa, khóa không mở được database): file cũ được đổi tên thành `.unreadable-<thời điểm>` (không xóa), app tạo database mới và báo cho người dùng. App vẫn mở được trong tình huống khẩn cấp.
- Chi phí đo trên máy tính: ghi gói/tin gần như không đổi (1,0 ms; 0,6 ms); `pending()` với 5000 gói 5 → 9–10 ms (chỉ chạy khi gặp máy mới).

## BLE Android

- Service UUID: `a8c10001-37d5-4b52-9c40-9ad6819b3000`.
- Characteristic UUID: `a8c10002-37d5-4b52-9c40-9ad6819b3000`.
- Mỗi máy quảng bá service, mở GATT server, đồng thời scan/connect như central.
- Central gửi bằng write có response. Peripheral gửi bằng indication sau khi peer bật CCCD.
- Một thao tác truyền đang chờ callback tại một thời điểm; timeout 10 giây. Mỗi peer có MTU riêng. MTU yêu cầu 185; fallback 23.
- Scan 12 giây, nghỉ 18 giây. Thử lại kết nối sau 30 giây; tối đa 4 kết nối central. Thực tế số kết nối đồng thời tùy phần cứng.
- Foreground service loại `connectedDevice`; FlutterEngine giữ trong process khi Activity bị hủy. Không tự khởi động sau reboot/force-stop/process kill. Background vẫn cần xác minh trên từng hãng điện thoại.
- Quyền BLE Android 12+ xin khi bật mạng; Android cũ xin vị trí cho scan. GPS xin riêng khi gửi SOS. Android 13+ xin thêm quyền thông báo khi bật mạng; nếu từ chối, BLE và foreground service vẫn chạy nhưng thông báo bị ẩn.
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

Body ứng dụng (SOS, safe, chat; với tin riêng là bản rõ trước khi mã hóa): 1 byte cờ — bit 0 = có vị trí, bit 1 = có tên người gửi, các bit khác phải bằng 0. Nếu có vị trí: latitude và longitude là hai float64. Nếu có tên: 1 byte độ dài rồi tối đa 255 byte UTF-8. Phần còn lại là nội dung UTF-8; nội dung gửi từ UI tối đa 2000 byte UTF-8. HELLO chứa tên hiển thị trong phần nội dung và chỉ đi 1 chặng, nên mỗi tin mang kèm tên người gửi để node cách nhiều chặng vẫn hiện đúng tên. Tên nằm trong phần được ký nhưng chỉ là tên tự khai, không phải danh tính đã xác minh. ACK chứa đúng 16 byte ID tin đã nhận.

Tương thích: bản trước bit 1 chỉ chấp nhận cờ 0 hoặc 1, nên không đọc được tin từ bản hiện tại (vẫn chuyển tiếp vì relay chạy trước khi đọc body). Mọi điện thoại trong một lần thử phải cài cùng một bản build.

Frame có header 12 byte: magic `F`, version, token 4 byte, index uint16, totalFragments uint16, totalLength uint16. Dữ liệu mỗi frame ≤ MTU−3. MTU 23 còn 8 byte dữ liệu sau header frame. Ghép theo peer+token, tối đa 64 assembly, hết hạn sau 30 giây, giới hạn 1024 fragment và 4264 byte/packet. Fragment chưa xác thực riêng; chỉ tin packet sau khi đủ dữ liệu và xác minh chữ ký.

## Routing và store-and-forward

1. Kết nối mới: gửi HELLO ký số. Khi nhận HELLO của bên kia, router biết kết nối này dẫn tới máy nào và mới bắt đầu sync gói lưu chưa hết hạn. Kết nối không gửi HELLO trong 5 giây vẫn được sync như một máy riêng. HELLO tạo mới cho mỗi kết nối, không lưu chờ gửi. Android báo lại một kết nối đang mở (đổi MTU, mất một vai trò GATT) chỉ cập nhật MTU, không gửi HELLO hay sync lại.
2. Tin mới: ký/mã hóa, lưu packet và bản ghi UI trước khi gửi.
3. Nhận packet: kiểm tra cấu trúc, dedup, tuổi tin (24 giờ), lệch thời gian tương lai ≤5 phút và chữ ký.
4. Nhận tin của mình hoặc broadcast: lưu inbox. Với tin riêng gửi ACK có chữ ký.
5. Nếu còn chặng và không phải tin riêng đã đến đích: gửi cho các peer khác nguồn vào. Bước này chạy trước khi đọc body, nên gói có chữ ký hợp lệ mà node không giải mã được vẫn được chuyển tiếp.
6. Mỗi máy kề có một hàng đợi gửi riêng, chạy tách khỏi luồng nhận: gửi tồn đọng cho một máy không làm chậm việc nhận và chuyển tiếp tin từ máy khác. Trong hàng đợi, SOS → ACK → trạng thái → chat; SOS đến giữa lúc đang đồng bộ tồn đọng được gửi ngay sau gói đang truyền. Không ngắt một packet đang truyền để chen SOS.
7. Gặp peer mới hoặc kết nối lại: sync gói chưa hết hạn. Dedup/pending dùng cùng bảng packets; tối đa 5000 gói. Tin UI giữ tối đa 2000 bản ghi.
8. Hai kết nối tới cùng một máy (vai trò central và peripheral của Android) được tính là một máy kề: mỗi gói chỉ gửi một lần, qua kết nối có RSSI mạnh hơn. Router ghi nhớ máy kề nào đã có gói nào (do mình gửi hoặc do nó gửi tới), nên không gửi ngược gói về nơi nó đến.
9. Gửi lỗi trên kết nối còn sống được thử lại: mỗi 30 giây router đưa lại các gói đang chờ cho mọi máy kề, bỏ qua gói máy đó đã có. Lỗi gửi được đếm trong `failedSends`, không hiện thành thông báo lỗi.
10. Gói không đọc được (sai cấu trúc, sai chữ ký, không giải mã được) được đếm là bị loại. Lỗi của chính máy mình khi xử lý gói hợp lệ (ví dụ ghi database thất bại) được báo lên giao diện thay vì bị đếm lẫn vào gói bị loại.
11. Với tin của chính mình, router ghi máy kề đã nhận vào bảng `handoffs`; giao diện hiện "Chưa đến máy nào" hoặc "Đã đến N máy gần". Chỉ tính máy đã chứng minh danh tính bằng HELLO. Con số này là số máy kề trực tiếp, không phải số máy trong cả mạng.
12. Chống flood (`lib/routing/flood_guard.dart`), xem mục bên dưới.

### Chống flood

Một máy xấu có thể phát hàng nghìn gói hợp lệ (ký bằng khóa của chính nó) để làm đầy kho 5000 gói của cả mạng và đẩy SOS thật ra ngoài, hoặc gửi gói giả chữ ký để bắt máy khác tốn 3 ms CPU cho mỗi lần kiểm. Ba lớp chặn:

1. **Hạn mức theo người gửi** (theo khóa ký): mỗi khóa được 200 gói mới một lúc, sau đó 30 gói/phút; SOS có hạn mức riêng nhỏ hơn (10 gói, sau đó 2/phút) vì SOS được ưu tiên trong mọi hàng đợi. Gói vượt hạn mức bị bỏ trước khi kiểm chữ ký: không lưu, không chuyển tiếp, đếm vào `limited`. Hạn mức chỉ bị trừ **sau khi** chữ ký hợp lệ, nên gói giả mạo không làm cạn hạn mức của người thật. Tin của chính máy mình không bị giới hạn. Một lượt mang tồn đọng (store-and-forward) của một người tới 200 tin vẫn qua được.
2. **Tắt tiếng kết nối gửi gói giả:** kết nối gửi 20 gói sai cấu trúc hoặc sai chữ ký trong 1 phút bị bỏ qua 5 phút (frame bị bỏ trước khi ghép, đếm vào `ignoredFrames`). Gói hết hạn hoặc lệch giờ không bị tính, vì relay lệch đồng hồ vẫn là relay trung thực.
3. **Chia đều kho theo người gửi:** khi kho đầy, gói đã ACK bị bỏ trước; sau đó mỗi người gửi giữ được gói tốt nhất của mình trước khi bất kỳ ai giữ gói thứ hai (trong cùng mức: SOS trước, mới trước). Người flood chỉ đẩy ra gói của chính họ. Trước đây kho bỏ gói cũ nhất trước, nên 5000 SOS giả mới hơn đẩy được SOS thật ra ngoài. Hàm `keepOrder` (MemoryStore) và câu SQL `ROW_NUMBER() OVER (PARTITION BY origin …)` (SqliteStore) dùng cùng thứ tự.

Giới hạn: khóa mới có hạn mức đầy ngay, nên kẻ tấn công tạo nhiều khóa (Sybil) vẫn đi qua được. Lớp 3 làm việc này tốn công hơn: để đẩy ra một SOS thật của một người, kẻ tấn công cần khoảng 5000 khóa khác nhau, mỗi khóa ký một gói. Bộ đếm theo người gửi nằm trong bộ nhớ, giữ 2000 người gửi gần nhất, và đặt lại khi mở lại app.

ACK chỉ xác nhận tin riêng, và chỉ được chấp nhận khi sender của ACK trùng recipient của tin gốc. Mọi node đang giữ tin gốc, kể cả relay, đánh dấu nó đã xong khi thấy ACK hợp lệ và ngừng sync tin đó. Broadcast không có xác nhận toàn mạng; UI chỉ thể hiện đã lưu/chuyển tiếp. Tin lỗi gửi được giữ để thử khi kết nối lại. Không có retry vô hạn trên kết nối đang giữ nguyên.

Chống trùng giữ bản nhận đầu tiên, nên tuyến dài đến trước có thể làm giảm độ phủ trong giới hạn TTL; không đảm bảo tìm đường ngắn nhất. Broadcast và chính gói ACK vẫn được relay giữ và sync đến hết thời hạn 24 giờ. Thời hạn của ACK không được rút ngắn: người nhận bỏ qua bản trùng của tin đã nhận nên không gửi lại ACK, và nếu ACK hết hạn trước khi gặp người gửi thì người gửi không bao giờ nhận được xác nhận. Không có global ACK cho broadcast.

## Bảo mật

- Ed25519 mọi packet, public key X25519 nằm trong nội dung được ký.
- Tin riêng: X25519 tĩnh → HKDF-SHA256, salt = message ID, context `emergency-mesh-v1/private` → AES-256-GCM nonce 12 byte, tag 16 byte. AAD ràng buộc ID và recipient.
- Relay chỉ lưu/chuyển ciphertext tin riêng; không đưa vào inbox của relay.
- Seeds danh tính được mã hóa AES-GCM bằng khóa Android Keystore, lưu ciphertext trong SharedPreferences, tắt backup.
- Tên hiển thị không chứng minh danh tính. So sánh ID qua kênh đáng tin trước khi gửi tin nhạy cảm. Không có danh bạ được xác minh trước hoặc chứng chỉ cơ quan cứu hộ.
- Chưa có forward secrecy, key ratchet hoặc cơ chế chống Sybil (xem *Chống flood*: hạn mức theo khóa, tắt tiếng kết nối gửi gói giả, chia đều kho theo người gửi). Headers làm lộ metadata.
- Database được mã hóa bằng khóa trong Android Keystore, nhưng khi app đang chạy thì khóa nằm trong bộ nhớ. Máy đã root hoặc mã độc chạy cùng quyền app vẫn đọc được. Mã hóa bảo vệ file khi bị sao chép ra ngoài (sao lưu, chép qua adb, đọc trực tiếp bộ nhớ flash). Đây là bản đồ án cần audit trước khi dùng cho vận hành cứu hộ.

## Nguồn kỹ thuật

- [Android Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [BLE background](https://developer.android.com/develop/connectivity/bluetooth/ble/background)
- [GATT transfer](https://developer.android.com/develop/connectivity/bluetooth/ble/transfer-ble-data)
- [Dart cryptography](https://pub.dev/packages/cryptography)
