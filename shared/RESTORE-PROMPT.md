# PROMPT KHÔI PHỤC — dán nguyên văn phần dưới vào Claude Code (CLI hoặc tab Code của Desktop)

> Dùng trên máy mới / sau khi cài lại: mở Claude Code, `cd` tới thư mục chứa bộ kit này
> (đặt ở đâu cũng được), rồi dán toàn bộ khối dưới.

---

Bạn là trợ lý kỹ thuật. Hãy khôi phục & hợp nhất lịch sử hội thoại Claude Desktop (tab Code) cho tôi từ bộ kit nằm trong THƯ MỤC HIỆN TẠI (thư mục chứa các file của kit, ở bất kỳ đâu). Làm cẩn thận, không phá dữ liệu, giải thích từng bước bằng tiếng Việt, HỎI XÁC NHẬN trước khi ghi/sửa.

BỐI CẢNH KỸ THUẬT (đã xác minh — Claude Desktop trên macOS):
- Nội dung thật: `~/.claude/projects/<slug>/<cliSessionId>.jsonl`. `<slug>` tạo từ ĐƯỜNG DẪN TUYỆT ĐỐI của thư mục dự án, thay `/ . ~ khoảng trắng` thành `-`. Ví dụ `/Users/<user>/Projects/my-app` → `-Users-<user>-Projects-my-app`.
- Danh sách Recents do Desktop QUÉT THƯ MỤC (không có DB trung tâm): `~/Library/Application Support/Claude/claude-code-sessions/<ACCOUNT_UUID>/<ORG_UUID>/local_*.json`. Mỗi team = 1 thư mục. `local_*.json` chỉ là metadata, trỏ transcript qua `cliSessionId`.
- KIT v2 dùng **thư mục dùng chung**: `~/Library/Application Support/Claude/claude-code-sessions-shared/` chứa chỉ mục hợp nhất; mỗi folder team là SYMLINK trỏ vào đó.

DỮ LIỆU SAO LƯU (trong `recovery-data/<TS>-full-v<ver>/` do backup-now tạo):
- `projects.tgz` — toàn bộ transcript.
- `claude-code-sessions.tgz` — chỉ mục theo team.
- `claude-code-sessions-shared.tgz` — thư mục dùng chung (v2).
- `claude.json.bak`, `last-backup.txt`.
- `shared/metadata.txt` — ACCOUNT_UUID, các ORG_UUID, username & đường dẫn gốc.

CÁC BƯỚC:
1. Đọc `shared/metadata.txt` để biết ACCOUNT_UUID, ORG_UUID, username gốc (`hieu_icetea`, HOME `/Users/hieu_icetea`).
2. Yêu cầu tôi THOÁT HẲN Claude Desktop (Cmd+Q) trước khi ghi.
3. Bung `projects.tgz` → `~/.claude/`; `claude-code-sessions.tgz` và `claude-code-sessions-shared.tgz` → `~/Library/Application Support/Claude/`. CHỈ GỘP THÊM, trùng tên thì giữ bản mới hơn hoặc hỏi tôi.
4. KIỂM TRA định danh máy mới: `whoami`, HOME hiện tại; ACCOUNT_UUID/ORG_UUID hiện tại (đọc `~/.claude.json` hoặc liệt kê `claude-code-sessions/`).
5. XỬ LÝ LỆCH (nếu có):
   - USERNAME/HOME KHÁC gốc: slug trong `~/.claude/projects` và `cwd`/`originCwd` trong `local_*.json` (kể cả trong shared) còn trỏ đường dẫn cũ → "mồ côi". Đổi tên slug + sửa `cwd`/`originCwd`/`worktreePath` cho khớp đường dẫn mới (chỉ khi tôi xác nhận đường dẫn dự án mới).
   - ORG_UUID hiện tại có folder mới chưa symlink: chạy `versions/latest/bin/setup-unified-sessions.sh --apply` để dựng lại symlink về shared.
6. KIỂM TRA SAU KHÔI PHỤC: với mỗi `local_*.json` trong shared, xác nhận `<cliSessionId>.jsonl` tồn tại trong `~/.claude/projects/**`. Báo cáo tổng phiên / có transcript / thiếu. (Có thể chạy `versions/latest/bin/status.sh`.)
7. Yêu cầu tôi mở lại Claude Desktop và xác nhận tab Code đã hiện danh sách trên các team.

AN TOÀN: ưu tiên extract/gộp; backup nhanh thư mục đích trước khi sửa; KHÔNG xoá gì khi chưa hỏi; KHÔNG đụng nội dung trong `~/.claude/projects` ngoài việc đổi tên slug khi đã xác nhận.
