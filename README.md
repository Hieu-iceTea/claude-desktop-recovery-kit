# 🛟 Claude Desktop — Bộ Kit Khôi Phục & Hợp Nhất Lịch Sử Hội Thoại

> v2.2.0 (HiếuND)

Giúp **hợp nhất** lịch sử hội thoại của **Claude Desktop (tab Code)** giữa **nhiều tài khoản & nhiều team**,
**chống mất dữ liệu**, và **sao lưu / khôi phục** khi đổi máy hoặc cài lại máy.

## ⚡ Bốn lớp mất dữ liệu — kiểm tra tất cả bằng một lệnh

```bash
versions/latest/bin/status.sh
```

| Lớp | Hiện tượng | Chặn bằng |
|-----|-----------|-----------|
| **A** | Recents phân mảnh giữa các account/team | `setup-unified-sessions.sh --apply` |
| **B** | Transcript **tự xoá sau 30 ngày** (mặc định Claude Code) | `"cleanupPeriodDays": 36500` trong `~/.claude/settings.json` |
| **C** | Còn nội dung nhưng **mất mục trong Recents** | `repair-missing-sessions.sh --apply` |
| **D** | Hỏng ổ / xoá nhầm | `snapshot.sh` + Time Machine |

> **Lớp B nguy hiểm nhất.** Ngày 06/08/2026 phát hiện **59/119** mục Recents đã mất sạch
> nội dung vì lớp này — tiêu đề còn, bấm vào thì hội thoại trống, và **không khôi phục được**.
> Nếu chỉ làm một việc trong bộ kit này, hãy làm Lớp B.

Chi tiết từng lớp + hai bẫy shell đã gặp thật: [`versions/v2.2.0/README.md`](versions/v2.2.0/README.md).


## 📁 Cấu trúc kit (một thư mục duy nhất)

```
<KIT>/                          ← thư mục gốc của kit (đặt ở đâu cũng được)
├── shared/                 ← tài liệu dùng chung mọi phiên bản
│   ├── README.md  RELATED-CONVERSATIONS.md  CHANGELOG.md  metadata.txt  RESTORE-PROMPT.md
├── versions/
│   ├── v1.0.0/             ← bản cũ (đóng băng)
│   ├── v2.0.0/             ← đóng băng
│   ├── v2.1.0/             ← đóng băng
│   ├── v2.2.0/             ← bản hiện tại (chống mất dữ liệu 4 lớp)
│   │   ├── VERSION  README.md
│   │   └── bin/  setup / rollback / status / backup-now / restore-from-backup
│   │              clean-orphan-transcripts / repair-missing-sessions / snapshot
│   └── latest -> v2.2.0
├── recovery-data/          ← BACKUP một lần. Tên thư mục: <TS>-<loại>-v<version>
│       • <TS>-full-v2.1.0/   = backup-now (đầy đủ, có transcript) → khôi phục máy mới
│       • <TS>-apply-v2.1.0/  = setup --apply (có orig-folders) → ROLLBACK
│       • orphan-trash-<TS>-v2.1.0/ = thùng rác transcript mồ côi
└── reports/                ← BÁO CÁO (status --save) → status-<TS>-v<version>.txt
```
> Quy ước tên: **`<dấu-thời-gian>-<loại>-v<version>`** → nhìn tên biết ngay LOẠI và VERSION (để rollback đúng script), `ls` vẫn sắp theo thời gian.

---

## 🗺️ Bản đồ đường dẫn — kit KHÔNG chứa hết mọi thứ

Kit chứa **công cụ**. Dữ liệu và cấu hình nằm ở nơi khác vì bản chất chúng thuộc về nơi đó.
Bảng này để sau này không phải đi tìm:

| Đường dẫn | Là gì | Vì sao không nằm trong kit |
|---|---|---|
| `<KIT>/versions/latest/bin/` | **toàn bộ script** | — đây chính là kit |
| `~/DATA/claude-backups/` | **dữ liệu snapshot** (~3 GB, 14 bản) + `HUONG-DAN.txt` | `git clean -xdf` **xoá cả file bị gitignore** → để trong repo là có ngày mất backup. Ngoài ra 3 GB trong repo làm IDE index rất chậm. `snapshot.sh` ở đây chỉ là **symlink** trỏ ngược vào kit — mã nguồn vẫn một chỗ. |
| `~/DATA/claude-backups/archives/` | **9 kho backup .tgz 06–07/2026** gom từ bản kit cũ | Ngày 06/08/2026, `20260706-115922-full/projects.tgz` trong đây đã cứu **53 hội thoại** mà không kho nào khác có. Vô giá — đừng xoá. |
| `~/.claude/settings.json` | `cleanupPeriodDays` (Lớp B) | file cấu hình của Claude Code, bắt buộc ở đúng chỗ này |
| `~/.claude/projects/` | transcript gốc `.jsonl` | dữ liệu do Claude ghi ra |
| `~/Library/Application Support/Claude/claude-code-sessions-shared/` | chỉ mục Recents `local_*.json` | dữ liệu của app |

> ⚠️ **`recovery-data/` nằm TRONG repo và bị gitignore** → `git clean -xdf` sẽ xoá nó.
> Ngày 06/08/2026 chính `recovery-data/20260805-201625-full-v2.1.0/projects.tgz` đã cứu được
> 5 hội thoại. Đừng chạy `git clean -x` trong kit nếu chưa kiểm tra.

---

## 🔧 Cách dùng (mọi việc đều qua script trong `versions/latest/bin/`)

```bash
cd <KIT>/versions/latest/bin      # <KIT> = nơi bạn đặt bộ kit (đặt ở đâu cũng được)
```

Kiểm tra trạng thái:
```bash
./status.sh                           # kiểm tra, in ra màn hình
./status.sh --save                    # kiểm tra + lưu báo cáo vào reports/status-<TS>.txt
```

### A. Hợp nhất danh sách giữa các tài khoản/team
```bash
./setup-unified-sessions.sh            # XEM TRƯỚC (dry-run), không đổi gì
./setup-unified-sessions.sh --apply    # thực thi (tự backup vào recovery-data/<TS>/)
```
Sau đó **Cmd+Q thoát hẳn Claude Desktop rồi mở lại**.
- Tạo team MỚI hoặc sau khi cập nhật Desktop → chạy lại `--apply` (idempotent).
- Kiểm tra sức khoẻ bất kỳ lúc nào: `./status.sh` (thêm `--save` để lưu báo cáo vào `<KIT>/reports/status-<TS>.txt`; `reports/` tự tạo nếu chưa có; mỗi lần là file mới theo dấu thời gian, **không xoá báo cáo cũ**)
- Hoàn tác: `./rollback-unified-sessions.sh <recovery-data/TS>`

### A2. Đưa lại hội thoại bị mất khỏi Recents  *(v2.2.0)*
```bash
./repair-missing-sessions.sh              # XEM TRƯỚC, 30 ngày gần đây
./repair-missing-sessions.sh --apply      # thực thi — PHẢI Cmd+Q thoát Desktop trước
./repair-missing-sessions.sh --scan       # liệt kê mọi transcript mồ côi (chỉ đọc)
./repair-missing-sessions.sh --since 90   # nới cửa sổ  (--all = không giới hạn)
```
Tự dò, không chép cứng danh sách → bắt được **cả phiên bạn đang trò chuyện**.
Tự bỏ qua: phiên đã có mục, phiên **bạn cố ý xoá**, bản rẽ nhánh cũ, phiên rỗng.
Chỉ TẠO file mới — hoàn tác bằng cách xoá đúng file vừa tạo (script in sẵn lệnh).

### A0. ⭐ Thoát Claude an toàn — DÙNG THAY Cmd+Q  *(v2.2.0)*
```bash
./safe-quit.sh              # thoát → vá chỉ mục → mở lại (một lệnh)
./safe-quit.sh --dry-run    # xem trước, không đụng vào Claude
```
**Đây là việc cần làm hằng ngày.** App hiện không ghi chỉ mục Recents → hội thoại mới
tạo sẽ biến mất khỏi danh sách sau khi khởi động lại. Dùng lệnh này thay Cmd+Q là xong,
không phải nhớ gì thêm. Không có tiến trình chạy nền.

### A3. Mục còn nhưng mở ra thấy bản CŨ  *(v2.2.0)*
```bash
./repair-missing-sessions.sh --fix-stale                    # xem trước
./repair-missing-sessions.sh --fix-stale --apply            # sửa tất cả
./repair-missing-sessions.sh --fix-stale --apply --only 1,4 # chỉ mục 1 và 4
```
Chế độ này **SỬA mục đang có** (khác A2 chỉ tạo mục mới) → mỗi mục đều có `.bak-<TS>`
và lệnh `cp` hoàn tác. In số lượt hỏi + tin nhắn cuối của cả hai bản để bạn tự chọn.

### B. Sao lưu (để đổi máy / reset máy)
```bash
./backup-now.sh           # nén transcript + chỉ mục + shared vào recovery-data/<TS>/
```

### B2. Ảnh chụp tự động hằng ngày  *(v2.2.0)*
```bash
./snapshot.sh             # chụp ngay vào ~/DATA/claude-backups (hardlink, rất nhẹ)
```
Cài lịch tự động 12:30 & 20:30 mỗi ngày:
```bash
cp ~/DATA/claude-backups/com.hieund.claude-backup.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.hieund.claude-backup.plist
```
⚠️ Snapshot nằm **cùng ổ** với dữ liệu gốc → chống xoá nhầm, **không** chống hỏng ổ.
Muốn an toàn thật thì cần Time Machine với ổ ngoài.

### C. Khôi phục trên máy mới
```bash
./restore-from-backup.sh <recovery-data/TS>
./setup-unified-sessions.sh --apply        # dựng lại symlink
```

### D. Dọn bộ nhớ (transcript mồ côi)
```bash
./clean-orphan-transcripts.sh          # CHỈ liệt kê
./clean-orphan-transcripts.sh --apply  # chuyển vào thùng rác (hoàn tác được)
./clean-orphan-transcripts.sh --hard   # xoá cứng (hỏi 2 lần)
```

---

## ⚠️ XÓA hội thoại & "transcript mồ côi" — phải xác nhận

Khi bạn **"Xóa" một hội thoại trong Claude Desktop, chỉ chỉ mục bị xóa; transcript `.jsonl`
vẫn nằm trong `~/.claude/projects/` và tiếp tục chiếm đĩa** ("mồ côi").
- Muốn thật sự giải phóng bộ nhớ: chạy `clean-orphan-transcripts.sh`.
- Script **luôn liệt kê đầy đủ** (đường dẫn, dung lượng) và **hỏi xác nhận** trước khi đụng;
  mặc định chỉ **chuyển vào thùng rác** `recovery-data/orphan-trash-<TS>/` (hoàn tác được).
- ⚠️ Mồ côi cũng có thể là phiên CLI hữu ích — **đọc kỹ trước khi đồng ý**, tránh xoá nhầm.


*Cơ chế khớp issue chính thức [anthropics/claude-code #29373](https://github.com/anthropics/claude-code/issues/29373) ("no data loss") và [#48511](https://github.com/anthropics/claude-code/issues/48511).*
