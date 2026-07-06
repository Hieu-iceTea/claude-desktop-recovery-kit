# 🛟 Claude Desktop — Bộ Kit Khôi Phục & Hợp Nhất Lịch Sử Hội Thoại

> v2.0.0 (HiếuND)

Giúp **hợp nhất** lịch sử hội thoại của **Claude Desktop (tab Code)** giữa **nhiều tài khoản & nhiều team**,
và **sao lưu / khôi phục** khi đổi máy hoặc cài lại máy.


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

### B. Sao lưu (để đổi máy / reset máy)
```bash
./backup-now.sh           # nén transcript + chỉ mục + shared vào recovery-data/<TS>/
```

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
