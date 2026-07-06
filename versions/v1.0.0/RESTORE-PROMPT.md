# PROMPT KHÔI PHỤC — dán nguyên văn phần dưới vào Claude Code (CLI hoặc tab Code của Desktop)

> Cách dùng: trên máy mới / sau khi cài lại, mở Claude Code tại chính thư mục kit này
> (`cd` tới thư mục chứa file này), rồi dán toàn bộ khối prompt bên dưới.

---

Bạn là trợ lý kỹ thuật. Hãy khôi phục lịch sử hội thoại Claude Desktop (tab Code) cho tôi từ bộ kit sao lưu nằm trong thư mục hiện tại. Làm cẩn thận, không phá dữ liệu, giải thích từng bước bằng tiếng Việt.

BỐI CẢNH KỸ THUẬT (đã xác minh, đúng với Claude Desktop trên macOS):
- Nội dung hội thoại thật được lưu LOCAL ở: `~/.claude/projects/<slug>/<sessionId>.jsonl`
  trong đó `<slug>` được tạo từ ĐƯỜNG DẪN TUYỆT ĐỐI của thư mục dự án, thay mọi ký tự `/ . ~ khoảng trắng` thành `-`. Ví dụ `/Users/hieu_icetea/DATA/Code/Kaopiz/12_ReDance` → `-Users-hieu-icetea-DATA-Code-Kaopiz-12-ReDance`.
- Danh sách "Recents" của tab Code do Desktop dựng bằng cách QUÉT THƯ MỤC (không có DB trung tâm):
  `~/Library/Application Support/Claude/claude-code-sessions/<ACCOUNT_UUID>/<ORG_UUID>/local_*.json`
  Mỗi team (org) là 1 thư mục con riêng. File `local_*.json` chỉ là METADATA (tiêu đề, cwd, model, mốc thời gian, cliSessionId) — KHÔNG chứa nội dung hội thoại.
- File `local_*.json` trỏ tới transcript qua trường `cliSessionId` (khớp tên file `<cliSessionId>.jsonl`).

DỮ LIỆU SAO LƯU TRONG KIT (thư mục `backup/`):
- `projects.tgz` — toàn bộ `~/.claude/projects` (nội dung hội thoại).
- `claude-code-sessions.tgz` — toàn bộ chỉ mục Recents (mọi team).
- `local-agent-mode-sessions.tgz` — (nếu có) thư mục legacy.
- `metadata.txt` — chứa ACCOUNT_UUID, các ORG_UUID, username & đường dẫn của máy gốc.

CÁC BƯỚC BẠN CẦN LÀM:
1. Đọc `metadata.txt` để biết ACCOUNT_UUID, ORG_UUID và username gốc (gốc: `hieu_icetea`, HOME `/Users/hieu_icetea`).
2. Yêu cầu tôi THOÁT HẲN Claude Desktop (Cmd+Q) trước khi ghi file.
3. Bung `projects.tgz` vào `~/.claude/` và `claude-code-sessions.tgz` (+ legacy nếu có) vào
   `~/Library/Application Support/Claude/`. CHỈ GỘP THÊM, không xoá dữ liệu sẵn có (nếu trùng tên thì giữ cái mới hơn hoặc hỏi tôi).
4. KIỂM TRA định danh máy mới:
   a) Lấy username hiện tại (`whoami`) và HOME hiện tại.
   b) Lấy ACCOUNT_UUID + ORG_UUID hiện tại bằng cách đọc `~/.claude.json` (trường `oauthAccount.accountUuid` / `organizationUuid`) HOẶC liệt kê thư mục con trong `claude-code-sessions/`.
5. XỬ LÝ LỆCH (nếu có):
   - Nếu USERNAME/HOME mới KHÁC máy gốc: các slug trong `~/.claude/projects` và trường `cwd` trong file `local_*.json` vẫn trỏ đường dẫn cũ → sẽ "mồ côi". Hãy đổi tên các thư mục slug và sửa `cwd`/`originCwd`/`worktreePath` trong `local_*.json` cho khớp đường dẫn mới (chỉ khi tôi xác nhận đường dẫn dự án tương ứng trên máy mới).
   - Nếu ORG_UUID hiện tại KHÁC ORG_UUID trong backup (vì đang ở team khác/mới): copy các file `local_*.json` từ thư mục org cũ (trong backup) sang thư mục `claude-code-sessions/<ACCOUNT_UUID hiện tại>/<ORG_UUID hiện tại>/` (skip-if-exists). Đây chính là việc `migrate-team-sessions.sh` làm.
6. KIỂM TRA SAU KHÔI PHỤC: với mỗi `local_*.json` trong thư mục org đang dùng, xác nhận file `<cliSessionId>.jsonl` tồn tại trong `~/.claude/projects/**`. Báo cáo: tổng số phiên, số phiên có transcript, số phiên thiếu (nếu có).
7. Yêu cầu tôi mở lại Claude Desktop và xác nhận tab Code đã hiện danh sách.

LƯU Ý AN TOÀN: ưu tiên `cp`/extract gộp; tạo backup nhanh thư mục đích trước khi sửa tên/đường dẫn; không xoá gì khi chưa hỏi.
