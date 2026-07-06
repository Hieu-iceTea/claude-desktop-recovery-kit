# CHANGELOG — claude-desktop-recovery-kit

Đánh số theo [Semantic Versioning](https://semver.org/).

> Dấu hiệu: bộ kit này được tạo/cập nhật với sự hỗ trợ của **Claude** — công cụ **Claude Code**, model **Claude Opus 4.8**.

## [2.1.0] — 2026-06-15
### Thêm mới (an toàn rollback theo version)
- Mỗi backup nay có **`MANIFEST.txt`** ghi: phiên bản kit, script tạo, thời điểm, máy, nội dung, và **lệnh rollback/khôi phục chính xác theo đúng version**.
- `setup --apply` tự lưu **`status-before.txt`** (ảnh chụp trạng thái ngay trước khi đổi) vào thư mục backup.
- `rollback` **kiểm tra version**: đọc `MANIFEST.txt`, nếu version backup ≠ version script thì cảnh báo + yêu cầu `FORCE`.
- **Quy ước tên thư mục backup**: `<TS>-<loại>-v<version>` (`-full-` = backup-now đầy đủ; `-apply-` = setup --apply rollback; `orphan-trash-<TS>-v<ver>` = thùng rác). Báo cáo: `status-<TS>-v<ver>.txt`. → nhìn tên biết loại + version. (Script đọc backup `rollback`/`restore` nhận đường dẫn làm tham số nên KHÔNG bị ảnh hưởng bởi tên.)
- Tạo từ v2.0.0 (sao chép + sửa khác biệt); **giữ nguyên v2.0.0** đóng băng. `latest -> v2.1.0`.

## [2.0.0] — 2026-06-15
### Thêm mới
- **Cơ chế "thư mục dùng chung (shared) + symlink"** thay cho copy: mọi tài khoản/team
  cùng trỏ symlink vào `claude-code-sessions-shared` ⇒ thấy CÙNG một danh sách, **tự động đồng bộ**.
- `setup-unified-sessions.sh` — gộp (ưu tiên VIP > Kaopiz SBU1 > 10-InnerTwo) + symlink. Có `--dry-run`/`--apply`/`--yes`.
- `rollback-unified-sessions.sh` — hoàn tác, trả folder team về vị trí gốc.
- `status.sh` — kiểm tra sức khoẻ symlink/shared, đối chiếu transcript. Cờ `--save` ghi báo cáo vào thư mục `reports/` (tách riêng khỏi `recovery-data/`).
- `clean-orphan-transcripts.sh` — dọn transcript mồ côi (liệt kê → thùng rác → xoá cứng, đều có xác nhận).
- Cấu trúc kit MỚI: 1 thư mục duy nhất gồm `shared/` (tài liệu chung) + `versions/` (các phiên bản) + `recovery-data/` (backup, tách khỏi công cụ).
- `RELATED-CONVERSATIONS.md` — liệt kê ID + transcript các cuộc trò chuyện liên quan để đọc lại.

### Sửa / Vá
- `backup-now.sh` & `restore-from-backup.sh` nay **bao gồm `claude-code-sessions-shared`**
  (bản v1 thiếu → khôi phục máy mới sẽ mất danh sách hợp nhất).
- Mọi backup gom vào thư mục có **dấu thời gian** `recovery-data/<YYYYMMDD-HHMMSS>/`.

### Vị trí kit
- Kit trở thành **DI ĐỘNG**: đặt ở bất kỳ thư mục an toàn nào người dùng chọn (không còn ở `~/Downloads`).
  Mọi script **tự định vị** qua đường dẫn của chính chúng (`BASH_SOURCE`) — KHÔNG hardcode vị trí kit.

## [1.0.0] — 2026-06-02  (đóng băng, xem versions/v1.0.0/)
- Bản đầu: copy `local_*.json` giữa các folder org khi đổi/deactivate team (`migrate-team-sessions.sh`),
  `backup-now.sh`/`restore-from-backup.sh`, `RESTORE-PROMPT.md`. Cơ chế copy thủ công.
