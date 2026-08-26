# 🛟 Claude Desktop — Bộ Kit Khôi Phục & Hợp Nhất Lịch Sử Hội Thoại (v2.0.0)

Giúp **hợp nhất** lịch sử hội thoại của **Claude Desktop (tab Code)** giữa **nhiều tài khoản & nhiều team**,
và **sao lưu / khôi phục** khi đổi máy hoặc cài lại máy.

> Tạo với sự hỗ trợ của **Claude** — công cụ **Claude Code**, model **Claude Opus 4.8**.

---

## 💡 Cơ chế cốt lõi (đã xác minh)

Claude Desktop lưu **2 lớp tách biệt**:

- **Lớp A — Transcript (nội dung thật, NGUỒN SỰ THẬT):**
  `/Users/hieu_icetea/.claude/projects/<slug>/<cliSessionId>.jsonl` — dùng chung mọi tài khoản, **không gắn team**.
- **Lớp B — Chỉ mục "Recents" (metadata):**
  `…/Claude/claude-code-sessions/<ACCOUNT>/<ORG>/local_*.json` — **chia theo tài khoản/team** → đổi team là "mất" danh sách.

**Giải pháp v2:** tạo MỘT thư mục **dùng chung (shared)**
`…/Claude/claude-code-sessions-shared/` chứa toàn bộ chỉ mục hợp nhất, rồi cho **mỗi folder team
trỏ symlink** vào đó ⇒ mọi tài khoản/team thấy **cùng một danh sách**, phiên mới **tự động đồng bộ**.

```
<ACCOUNT>/<ORG team A> ─┐
<ACCOUNT>/<ORG team B> ─┼─symlink─►  claude-code-sessions-shared/  ──(cliSessionId)──►  ~/.claude/projects/.../*.jsonl
<ACCOUNT>/<ORG team C> ─┘                 (chỉ mục hợp nhất)                              (nội dung thật)
```

---

## 📍 Vị trí kit
Bộ kit là **một thư mục duy nhất, DI ĐỘNG** — đặt ở **bất kỳ nơi an toàn nào bạn chọn**
(ổ ngoài, cloud sync, thư mục dữ liệu cá nhân…). **Không phụ thuộc vị trí cố định.**
Mọi script tự xác định thư mục kit qua đường dẫn của chính nó, nên cứ `cd` vào `versions/latest/bin`
ở bất kỳ đâu rồi chạy. Trong tài liệu này, `<KIT>` = thư mục gốc chứa bộ kit.

## 📁 Cấu trúc kit (một thư mục duy nhất)

```
<KIT>/                          ← thư mục gốc của kit (đặt ở đâu cũng được)
├── shared/                 ← tài liệu dùng chung mọi phiên bản
│   ├── README.md  RELATED-CONVERSATIONS.md  CHANGELOG.md  metadata.txt  RESTORE-PROMPT.md
├── versions/
│   ├── v1.0.0/             ← bản cũ (đóng băng)
│   ├── v2.0.0/             ← đóng băng
│   ├── v2.1.0/             ← bản hiện tại (MANIFEST + status-before + rollback kiểm tra version)
│   │   ├── VERSION  README.md
│   │   └── bin/  setup / rollback / status / backup-now / restore-from-backup / clean-orphan-transcripts
│   └── latest -> v2.1.0
├── recovery-data/          ← BACKUP. Tên thư mục: <TS>-<loại>-v<version>
│       • <TS>-full-v2.1.0/   = backup-now (đầy đủ, có transcript) → khôi phục máy mới
│       • <TS>-apply-v2.1.0/  = setup --apply (có orig-folders) → ROLLBACK
│       • orphan-trash-<TS>-v2.1.0/ = thùng rác transcript mồ côi
└── reports/                ← BÁO CÁO (status --save) → status-<TS>-v<version>.txt
```
> Quy ước tên: **`<dấu-thời-gian>-<loại>-v<version>`** → nhìn tên biết ngay LOẠI và VERSION (để rollback đúng script), `ls` vẫn sắp theo thời gian.

---

## 🔧 Cách dùng (mọi việc đều qua script trong `versions/latest/bin/`)

```bash
cd <KIT>/versions/latest/bin      # <KIT> = nơi bạn đặt bộ kit (đặt ở đâu cũng được)
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

### B. Sao lưu (để đổi máy / reset máy)
```bash
./backup-now.sh           # nén transcript + chỉ mục + shared vào recovery-data/<TS>/
```
**Giữ TOÀN BỘ thư mục kit `<KIT>` ở nơi an toàn** (bạn tự chọn vị trí & tự sao lưu).

### C. Khôi phục trên máy mới
```bash
./restore-from-backup.sh <recovery-data/TS>
./setup-unified-sessions.sh --apply        # dựng lại symlink
```
Nếu username máy mới khác `hieu_icetea` → dán `shared/RESTORE-PROMPT.md` vào Claude Code.

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

## ⚠️ Lưu ý quan trọng khi dùng SYMLINK
- Vì mọi team **dùng chung một danh sách**, thao tác **Xóa / Đổi tên / Lưu trữ (archive)
  trở thành TOÀN CỤC** (áp dụng cho mọi tài khoản/team). Đây là hệ quả của việc "dùng chéo".
- Tiếp tục / Fork / Duplicate / CLI resume: hoạt động bình thường.
- Mọi script **không bao giờ đụng `~/.claude/projects`** (transcript). Luôn có backup + rollback.

*Cơ chế khớp issue chính thức [anthropics/claude-code #29373](https://github.com/anthropics/claude-code/issues/29373) ("no data loss") và [#48511](https://github.com/anthropics/claude-code/issues/48511).*
