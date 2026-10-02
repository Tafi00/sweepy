# Sweepy – dọn rác định kỳ cho macOS

> Native macOS disk cleaner for developers: build caches, package-manager caches, browser & chat app caches, leftovers of uninstalled apps — on a schedule, with safety guards.

App SwiftUI native (macOS 14+) quét và dọn những loại rác lặp đi lặp lại trên máy: cache build của dự án code,
cache công cụ dev, trình duyệt, Zalo/Telegram/Electron, log và file cài đặt cũ. Có lịch tự động chạy nền.

## Cài đặt

**Cách khuyên dùng – một dòng lệnh, macOS không chặn:**

```bash
curl -fsSL https://raw.githubusercontent.com/Tafi00/sweepy/main/install.sh | bash
```

Script tải bản mới nhất từ [Releases](https://github.com/Tafi00/sweepy/releases), cài vào `/Applications` và mở app.
File tải bằng `curl` không bị macOS gắn cờ quarantine nên Gatekeeper không hiện cảnh báo.

**Tải file zip thủ công:** tải `Sweepy.zip` ở [Releases](https://github.com/Tafi00/sweepy/releases/latest), giải nén,
kéo vào Applications. Nếu bản phát hành chưa được notarize, lần đầu macOS sẽ báo không mở được — chọn
*System Settings → Privacy & Security → Open Anyway*, hoặc chạy:

```bash
xattr -dr com.apple.quarantine /Applications/Sweepy.app
```

**Tự cập nhật:** từ bản 1.2.0, Sweepy kiểm tra Releases mỗi 6 giờ và chỉ cài bản được ký bằng cùng chứng chỉ
Developer ID (team `3JD7L6FN23`). Khi app chỉ nằm trên menu bar, bản mới được cài ngay; khi cửa sổ đang mở,
nút *Cập nhật* hiện trên thanh công cụ. Tắt ở *Cài đặt → Cập nhật*.

### Ký & notarize (cho người duy trì repo)

Workflow tự ký Developer ID và notarize khi repo có các secret sau, nhờ đó bản zip tải bằng trình duyệt mở được ngay.
Cách nhanh nhất: xuất chứng chỉ ra .p12 rồi chạy `./scripts/setup-signing.sh đường-dẫn.p12` – script hỏi mật khẩu,
kiểm tra với Apple rồi tự lưu cả 5 secret.

| Secret | Nội dung |
|---|---|
| `MACOS_CERT_P12` | Chứng chỉ *Developer ID Application* xuất ra .p12, mã hoá base64 (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERT_PASSWORD` | Mật khẩu file .p12 |
| `APPLE_ID` | Apple ID của tài khoản developer |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_APP_PASSWORD` | App-specific password tạo ở appleid.apple.com |

Không có secret thì app được ký ad-hoc (vẫn chạy bình thường khi cài bằng script ở trên).
Phát hành bản mới: `git tag v1.x.y && git push --tags` → GitHub Actions build bản universal (Apple Silicon + Intel) và đính kèm vào Release.

## Build từ mã nguồn

```bash
./build.sh            # tạo dist/Sweepy.app
./build.sh --install  # build rồi copy vào /Applications
UNIVERSAL=1 ./build.sh  # bản chạy cả Apple Silicon và Intel
```

`build.sh` tự ký bằng chứng chỉ Developer ID/Apple Development trong Keychain (hoặc `SIGN_IDENTITY=…`) để macOS
nhớ quyền đã cấp (Full Disk Access…) qua các lần build; không có chứng chỉ thì ký ad-hoc.

Cần Xcode Command Line Tools (Swift 5.9+). Nên chạy từ `/Applications` trước khi bật lịch tự động,
vì LaunchAgent lưu đường dẫn tuyệt đối tới app.

## Cách dùng

- **Tổng quan**: dung lượng ổ đĩa, tổng có thể dọn, mục lớn nhất.
- **Nhóm rác**: mỗi quy tắc có
  - ô tick: chọn để dọn khi bấm **Dọn** trên thanh công cụ,
  - công tắc **Tự động**: được dọn trong các lần chạy theo lịch,
  - *Chi tiết & tuỳ chỉnh*: đổi số ngày, cách xoá (vĩnh viễn / Thùng rác), bỏ tick từng mục,
    chuột phải → "Luôn bỏ qua đường dẫn này".
- **Cài đặt & lịch**: hằng ngày/tuần/tháng, chỉ chạy khi ổ trống dưới X GB, thư mục dự án, danh sách loại trừ.
- **Menu bar** (biểu tượng ✨): xem dung lượng, "Dọn các mục tự động ngay".
- **Khởi động cùng macOS**: bật trong *Cài đặt & lịch → Khởi động*; khi tự mở lúc đăng nhập, app chỉ nằm trên menu bar.

## Dòng lệnh

```bash
Sweepy.app/Contents/MacOS/Sweepy --scan                 # báo cáo, không xoá gì
Sweepy.app/Contents/MacOS/Sweepy --auto --dry-run       # xem lần chạy tự động sẽ xoá gì
Sweepy.app/Contents/MacOS/Sweepy --auto                 # chạy như lịch (LaunchAgent gọi lệnh này)
Sweepy.app/Contents/MacOS/Sweepy --auto --only dev.npm,web.chrome
Sweepy.app/Contents/MacOS/Sweepy --check-path ~/Documents   # kiểm tra lớp bảo vệ
```

## An toàn

- Không bao giờ xoá ngoài thư mục home (trừ `$TMPDIR`), không xoá chính các thư mục gốc
  (`~/Desktop`, `~/Documents`, `~/Library/Caches`…), không đụng `~/.ssh`, Keychain, iCloud Drive, Mail, Ảnh.
- Bỏ qua quy tắc khi app liên quan đang chạy (Chrome, Zalo, Telegram, Xcode…) — tắt được từng quy tắc.
- Bỏ qua dự án đang chạy dev server (`next dev`, gradle…) và dự án mới sửa gần đây (với `node_modules`, venv…).
- Không xoá thư mục chứa `.git`.
- File của người dùng (Downloads, file Zalo, Xcode Archives) mặc định chuyển vào Thùng rác và tắt tự động.

## Dữ liệu

| | |
|---|---|
| Cấu hình | `~/Library/Application Support/Sweepy/config.json` |
| Lịch sử | `~/Library/Application Support/Sweepy/history.json` |
| Log chạy tự động | `~/Library/Logs/Sweepy/auto.log` |
| LaunchAgent | `~/Library/LaunchAgents/local.sweepy.autoclean.plist` |

Quy tắc có sẵn nằm trong `Sources/Sweepy/DefaultRules.swift`; cấu hình chỉ lưu phần bạn thay đổi,
nên cập nhật quy tắc trong code không làm mất tuỳ chỉnh.

Gỡ: tắt lịch trong Cài đặt (hoặc xoá file LaunchAgent), xoá app và thư mục `~/Library/Application Support/Sweepy`.
