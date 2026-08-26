# Kit v2.2.0 — có gì mới

v2.1.0 chỉ lo **một** kiểu mất: chỉ mục Recents bị phân mảnh giữa các account/team.
v2.2.0 bổ sung **ba lớp còn lại**, sau khi phát hiện ngày 06/08/2026 rằng
**59/119 mục trong Recents đã mất sạch nội dung** mà không ai hay biết.

## Bốn lớp mất dữ liệu (và lớp nào chặn được bằng gì)

| Lớp | Hiện tượng | Công cụ | Trạng thái |
|-----|-----------|---------|-----------|
| **A** | Recents phân mảnh giữa các team | `setup-unified-sessions.sh` | có từ v2.0 |
| **B** | Transcript bị **tự xoá sau 30 ngày** | `cleanupPeriodDays` trong `~/.claude/settings.json` | **MỚI** |
| **C** | Còn nội dung nhưng **mất mục Recents** | `repair-missing-sessions.sh` | **MỚI** |
| **D** | Hỏng ổ / xoá nhầm | `snapshot.sh` + Time Machine | **MỚI** |

`status.sh` giờ báo cáo cả bốn lớp.

---

## Lớp B — chặn tự xoá (quan trọng nhất)

Claude Code mặc định **`cleanupPeriodDays: 30`** — transcript cũ hơn 30 ngày bị xoá
tự động, im lặng. Mục trong Recents vẫn còn, bấm vào thì hội thoại trống.

Bằng chứng phát hiện: transcript cũ nhất còn lại trên máy đúng **29 ngày**.

Sửa — thêm vào `~/.claude/settings.json`:

```json
"cleanupPeriodDays": 36500
```

Đây là dòng có giá trị nhất trong cả bộ kit. Không có nó thì mọi thứ khác chỉ là
dọn dẹp phần ngọn.

---

## Lớp C — `repair-missing-sessions.sh`

Recents đọc từ `claude-code-sessions-shared/local_*.json`; mỗi mục trỏ tới một
`cliSessionId`. Transcript `.jsonl` không được mục nào trỏ tới thì **mồ côi** —
nội dung còn nguyên nhưng app không hiển thị.

Script **tự dò**, không chép cứng danh sách → bắt được cả phiên vừa tạo xong
(kể cả phiên bạn đang trò chuyện).

```bash
repair-missing-sessions.sh                # xem trước, 30 ngày gần đây
repair-missing-sessions.sh --apply        # thực thi (sau khi Cmd+Q)
repair-missing-sessions.sh --scan         # liệt kê mọi mồ côi (chỉ đọc)
repair-missing-sessions.sh --since 90     # nới cửa sổ
repair-missing-sessions.sh --all          # không giới hạn thời gian
```

**Bốn quy tắc bỏ qua** — vì sao không phục hồi bừa 681 mồ côi thành 681 mục rác:

1. đã có mục trong Recents
2. **có file `deleted_<id>`** → bạn cố ý xoá trong app, tôn trọng ý bạn
3. **bản rẽ nhánh cũ** — gom nhóm theo `(thư mục dự án, tiêu đề)`; chỉ giữ bản mới nhất
   mỗi chuỗi, và bỏ cả chuỗi nếu chuỗi đó đã có đại diện trong Recents
4. rỗng / dưới 20 KB / không có lượt hỏi nào

Tiêu đề lấy từ chính transcript (bản ghi `custom-title` / `ai-title` — có ở
299/300 file), nên tên hiện ra giống hệt app tự đặt.

**An toàn:** chỉ TẠO file mới, không sửa/xoá mục nào đang có; mặc định xem trước;
chặn khi Desktop đang chạy; in sẵn lệnh hoàn tác.

**Thứ tự trong chuỗi tính theo dấu thời gian TIN NHẮN CUỐI, không theo `mtime`.**
Một thao tác sao chép hàng loạt (khôi phục backup, chuyển máy) đặt lại mtime của hàng
trăm file cùng lúc — lúc đó mtime không còn cho biết bản nào mới hơn. Nội dung thì luôn đúng.
*(Đã gặp thật: 648 file bị đặt lại mtime cùng một phút ngày 05/08/2026.)*

### `safe-quit.sh` — dùng THAY CHO Cmd+Q

Vì app hiện không ghi chỉ mục, **hội thoại mới tạo sẽ biến mất khỏi Recents sau khi khởi
động lại**. Nguyên nhân và bằng chứng: mục "Lỗi đang hoạt động" bên dưới.

Thay vì phải nhớ ba bước (Cmd+Q → repair → mở lại), gõ một lệnh:

```bash
safe-quit.sh              # thoát → vá chỉ mục → mở lại
safe-quit.sh --no-reopen  # thoát → vá, không mở lại
safe-quit.sh --dry-run    # chỉ in ra sẽ làm gì, KHÔNG đụng vào Claude
```

Không có tiến trình chạy nền, không có lịch tự động — chỉ chạy khi bạn gõ.

Thoát êm bằng AppleScript (không `kill`), đợi tiến trình thật sự kết thúc rồi mới vá.
Nếu sau 40 giây app vẫn chạy (thường vì đang hỏi xác nhận thoát) thì **dừng lại và không
thay đổi gì** — xử lý cửa sổ đó rồi chạy lại.

> ⚠️ Đợi Claude trả lời xong rồi hãy chạy — script thoát app ngay lập tức.

### `--fix-stale` — mục còn nhưng trỏ vào bản rẽ nhánh CŨ

Khác `repair` ở chỗ nó **SỬA mục đang có** chứ không tạo mục mới. Dùng khi hội thoại
vẫn nằm trong Recents nhưng mở ra thấy trạng thái cũ, thiếu phần mới.

```bash
repair-missing-sessions.sh --fix-stale                    # xem trước
repair-missing-sessions.sh --fix-stale --apply            # sửa tất cả
repair-missing-sessions.sh --fix-stale --apply --only 1,4 # chỉ mục 1 và 4
```

In ra số lượt hỏi và thời điểm tin nhắn cuối của **cả hai bản** để bạn tự chọn — vì bản
mới hơn thường đã bị **nén ngữ cảnh** (ít lượt hỏi thô hơn) nên "mới nhất" chưa chắc là
bản bạn muốn đọc.

Mỗi mục sửa đều tạo `.bak-<dấu-thời-gian>` và in lệnh `cp` hoàn tác.
**Không bao giờ trỏ sang bản có dấu `deleted_`** — tôn trọng hội thoại bạn đã cố ý xoá.

---

## Lớp D — `snapshot.sh`

Ảnh chụp hardlink (`rsync --link-dest`) của `~/.claude/projects` + thư mục chỉ mục
+ file cấu hình, lưu ở `~/DATA/claude-backups` (**ngoài** repo kit).

Đo thực tế: bản đầu 3.0 GB / 16 giây, **bản thứ hai tốn 1 MB** — file không đổi
được hardlink chứ không chép lại. Giữ 14 bản, tự dừng nếu ổ còn dưới 10 GB.

Chỉ đọc nguồn → chạy được khi Claude đang mở.

Cài lịch tự động 2 lần/ngày:

```bash
cp ~/DATA/claude-backups/com.hieund.claude-backup.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.hieund.claude-backup.plist
```

> ⚠️ Snapshot nằm **cùng ổ** với dữ liệu gốc. Chống được xoá nhầm và cho phép quay
> về từng thời điểm, nhưng **hỏng ổ cứng là mất cả hai**. Time Machine với ổ ngoài
> là thứ duy nhất bịt được lỗ này.

---

## Hai bẫy shell đã gặp thật (đừng lặp lại)

**1. `set -euo pipefail` + lệnh thoát sớm trong pipeline.**

```bash
set -euo pipefail
if ps -Ao args | grep -q "…MacOS/Claude$"; then    # ← KHÔNG BAO GIỜ ĐÚNG
```

`grep -q` thoát ngay khi khớp → `ps` nhận SIGPIPE → pipeline trả mã lỗi →
`pipefail` biến điều kiện thành sai. **Càng khớp thì càng không chặn.**
Sự cố thật: chốt an toàn hỏng, script chạy khi Desktop đang mở.

Dùng `grep -c` (đọc hết đầu vào) kèm `|| true`:

```bash
RUNNING="$(ps -Ao args | grep -c "Claude\.app/Contents/MacOS/Claude$" || true)"
[ "${RUNNING:-0}" -gt 0 ] && { echo "đang chạy"; exit 1; }
```

*Đã rà 6 script của v2.1.0 — không script nào dính lỗi này.*

**2. Lệnh trả exit code 0 dù thất bại.**

`tmutil destinationinfo` trả **0 ngay cả khi không có đích sao lưu nào**.
Phải đếm dòng `^Name`, không tin exit code.

**Ngoài ra:** `pgrep` trên macOS có thể **không thấy tiến trình chính** của Claude
Desktop (chỉ thấy helper). Mọi kiểm tra "Desktop tắt chưa" phải dùng `ps -Ao args`.

---

## Tương thích

Viết cho **bash 3.2** (bản mặc định của macOS) — không dùng `mapfile`,
associative array, hay khai triển mảng rỗng dưới `set -u`.
`rsync` của macOS là `openrsync`; đã kiểm chứng `--link-dest` tạo hardlink thật.
