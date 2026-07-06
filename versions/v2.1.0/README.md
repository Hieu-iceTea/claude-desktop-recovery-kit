# claude-desktop-recovery-kit — v2.1.0

Đây là thư mục **công cụ** của phiên bản 2.1.0. Script nằm trong `bin/`.

📄 **Tài liệu đầy đủ (dùng chung mọi phiên bản) nằm ở `../../shared/`:**
- `../../shared/README.md` — hướng dẫn tổng quan & cách dùng
- `../../shared/RESTORE-PROMPT.md` — prompt khôi phục máy mới
- `../../shared/RELATED-CONVERSATIONS.md` — ID transcript các cuộc liên quan
- `../../shared/CHANGELOG.md` — lịch sử phiên bản
- `../../shared/metadata.txt` — UUID tài khoản/team & ghi chú định danh

> Thiết kế: tài liệu KHÔNG lặp lại theo từng phiên bản — chỉ giữ một bản trong `shared/`
> để tránh trùng lặp và lệch nội dung. Mỗi `versions/vX/` chỉ chứa CÔNG CỤ của phiên bản đó.

Bắt đầu nhanh:
```bash
cd bin
./setup-unified-sessions.sh           # xem trước (dry-run), KHÔNG đổi gì
./setup-unified-sessions.sh --apply   # thực thi (tự backup vào ../../../recovery-data/<TS>-apply-v<ver>/)
./status.sh                           # kiểm tra, in ra màn hình
./status.sh --save                    # kiểm tra + lưu báo cáo vào ../../../reports/status-<TS>.txt
```
> `--save`: `reports/` tự tạo nếu chưa có; mỗi lần là file mới theo dấu thời gian (không ghi đè báo cáo cũ).
