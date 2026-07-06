#!/usr/bin/env bash
# === KHÔI PHỤC dữ liệu hội thoại Claude Desktop trên máy mới / sau khi cài lại ===
# Điều kiện: đã cài Claude Desktop và ĐĂNG NHẬP cùng tài khoản (hieu.icetea@gmail.com).
# Làm gì:
#   1) Bung transcript về ~/.claude/projects
#   2) Bung chỉ mục Recents về claude-code-sessions
# An toàn: chỉ GỘP thêm, không xoá dữ liệu sẵn có.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$KIT/backup"
APP="$HOME/Library/Application Support/Claude"

[ -f "$OUT/projects.tgz" ] || { echo "❌ Không thấy $OUT/projects.tgz — kit chưa có dữ liệu (chạy backup-now.sh ở máy cũ trước)."; exit 1; }

echo "⚠️  HÃY THOÁT HẲN Claude Desktop (Cmd+Q) trước khi tiếp tục."
printf "Đã thoát Desktop và muốn khôi phục? [y/N] "; read -r a
[ "$a" = "y" ] || { echo "Huỷ."; exit 0; }

mkdir -p "$HOME/.claude" "$APP"

echo "→ Khôi phục transcript..."
tar -xzf "$OUT/projects.tgz" -C "$HOME/.claude"

echo "→ Khôi phục chỉ mục Desktop..."
tar -xzf "$OUT/claude-code-sessions.tgz" -C "$APP"
[ -f "$OUT/local-agent-mode-sessions.tgz" ] && tar -xzf "$OUT/local-agent-mode-sessions.tgz" -C "$APP" || true

echo "✅ Khôi phục xong. Mở lại Claude Desktop → tab Code → chọn đúng team."
echo
echo "NẾU Recents vẫn trống, có 2 nguyên nhân thường gặp:"
echo "  (a) Username máy mới KHÁC 'hieu_icetea' => đường dẫn dự án lệch."
echo "  (b) Đang ở team có ORG_UUID khác với lúc backup."
echo "→ Lúc đó hãy mở Claude Code và dán nội dung file RESTORE-PROMPT.md để Claude tự xử lý,"
echo "  hoặc chạy: ./migrate-team-sessions.sh <ORG_UUID_CŨ>   (xem metadata.txt)"
