# 🛟 Claude Desktop — Bộ Kit Khôi Phục Lịch Sử Hội Thoại

Bộ kit này giúp **sao lưu** và **khôi phục** lịch sử hội thoại của **Claude Desktop (tab Code)**
khi: cài lại máy, chuyển sang máy khác, hoặc đổi/deactivate team.

> 💡 Cốt lõi: Nội dung hội thoại của tab Code được lưu **local trên máy** (không chỉ trên cloud).
> Vì vậy chỉ cần sao lưu đúng 2 thư mục là khôi phục được toàn bộ.

---

## 📦 Trong kit này có gì

| File | Vai trò |
|------|--------|
| `README.md` | Tài liệu này |
| `metadata.txt` | UUID tài khoản/team, username, đường dẫn của máy gốc |
| `backup-now.sh` | **Sao lưu** dữ liệu vào `backup/` (chạy trước khi cài lại máy) |
| `restore-from-backup.sh` | **Khôi phục** dữ liệu trên máy mới |
| `migrate-team-sessions.sh` | Copy danh sách phiên từ team CŨ sang team MỚI (khi đổi team) |
| `RESTORE-PROMPT.md` | Prompt dán vào Claude để **tự động** khôi phục & xử lý các tình huống khó |
| `backup/` | Nơi chứa dữ liệu đã nén (`projects.tgz`, `claude-code-sessions.tgz`, …) |

---

## 🔧 Quy trình sử dụng

### A. Định kỳ / trước khi cài lại máy — SAO LƯU
```bash
cd ~/Downloads/claude-desktop-recovery-kit
./backup-now.sh
```
Sau đó **copy cả thư mục kit** (đã gồm `backup/`) ra nơi an toàn: USB, ổ ngoài, hoặc cloud (Google Drive/iCloud/Dropbox).

### B. Trên máy mới / sau khi cài lại — KHÔI PHỤC
1. Cài **Claude Desktop**, đăng nhập **đúng tài khoản** (`hieu.icetea@gmail.com`).
2. **Thoát hẳn** Claude Desktop (Cmd+Q).
3. Copy thư mục kit về máy, rồi:
```bash
cd <thư-mục-kit>
./restore-from-backup.sh
```
4. Mở lại Claude Desktop → tab **Code** → chọn đúng team → danh sách hội thoại hiện lại.

> 🤖 **Cách thông minh hơn (khuyên dùng nếu có trục trặc):** mở Claude Code tại thư mục kit
> và **dán nội dung `RESTORE-PROMPT.md`**. Claude sẽ tự khôi phục và xử lý các tình huống như
> username máy mới khác, hoặc team có UUID mới.

### C. Khi đổi sang team mới (máy vẫn đang dùng) — DI CHUYỂN DANH SÁCH
```bash
cd <thư-mục-kit>
./migrate-team-sessions.sh <ORG_UUID_TEAM_CŨ>
# rồi khởi động lại Claude Desktop
```
(Các ORG_UUID đã biết xem trong `metadata.txt`.)

---

## ⚠️ Lưu ý quan trọng & rủi ro

- **An toàn dữ liệu:** mọi script chỉ `copy`/giải nén **gộp thêm**, không xoá dữ liệu cũ. `backup-now.sh` còn không đụng tới dữ liệu gốc.
- **Cùng username thì khôi phục y nguyên.** Nếu máy mới có **username khác** `hieu_icetea`,
  đường dẫn dự án sẽ lệch (lưu theo đường dẫn tuyệt đối) → dùng `RESTORE-PROMPT.md` để Claude sửa slug/cwd cho khớp.
- **Phải đăng nhập đúng tài khoản** để Desktop quét đúng thư mục theo `ACCOUNT_UUID`.
- **Bản sao lưu là ảnh chụp tại thời điểm chạy `backup-now.sh`** — nhớ chạy lại để cập nhật trước khi rời máy cũ.
- Nội dung backup có thể chứa thông tin nhạy cảm trong hội thoại → **giữ kit ở nơi an toàn**.

---

## 📂 Vị trí dữ liệu gốc (tham khảo)
- Nội dung hội thoại: `~/.claude/projects/<slug>/<sessionId>.jsonl`
- Chỉ mục Recents (theo team): `~/Library/Application Support/Claude/claude-code-sessions/<ACCOUNT_UUID>/<ORG_UUID>/`

*Cơ chế đã được xác minh và khớp với issue chính thức anthropics/claude-code #29373 ("no data loss").*
