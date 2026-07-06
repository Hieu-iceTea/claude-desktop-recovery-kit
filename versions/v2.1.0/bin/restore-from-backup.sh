#!/usr/bin/env bash
# =============================================================================
# restore-from-backup.sh   (v2.1.0)
# Khôi phục trên máy mới / sau khi reset.
# Điều kiện: đã cài Claude Desktop và ĐĂNG NHẬP đúng (các) tài khoản.
#
# Cách dùng:
#   restore-from-backup.sh <thư-mục-backup>
#   ví dụ: restore-from-backup.sh <thư-mục-kit>/recovery-data/20260615-120000
#
# Làm gì:
#   1) Bung transcript  -> ~/.claude/projects
#   2) Bung chỉ mục      -> claude-code-sessions
#   3) Bung shared (v2)  -> claude-code-sessions-shared
#   4) Nhắc chạy setup-unified-sessions.sh --apply để dựng lại symlink.
# An toàn: chỉ GỘP thêm; nếu username/đường dẫn khác máy gốc, xem RESTORE-PROMPT.md.
# =============================================================================
set -euo pipefail
BK="${1:-}"
APP="$HOME/Library/Application Support/Claude"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "$BK" ] && [ -f "$BK/projects.tgz" ] || {
  echo "❌ Thiếu/không thấy backup hợp lệ (cần projects.tgz)."
  echo "   Dùng: $(basename "$0") <thư-mục-backup>"; exit 1; }

echo "⚠️  HÃY THOÁT HẲN Claude Desktop (Cmd+Q) trước khi tiếp tục."
printf "Đã thoát Desktop, muốn khôi phục từ '$BK'? [gõ RESTORE] "; read -r a
[ "$a" = "RESTORE" ] || { echo "Đã huỷ."; exit 0; }

mkdir -p "$HOME/.claude" "$APP"
echo "→ [1] Khôi phục transcript..."
tar -xzf "$BK/projects.tgz" -C "$HOME/.claude"
echo "→ [2] Khôi phục chỉ mục..."
tar -xzf "$BK/claude-code-sessions.tgz" -C "$APP"
[ -f "$BK/claude-code-sessions-shared.tgz" ] && { echo "→ [3] Khôi phục thư mục dùng chung..."; tar -xzf "$BK/claude-code-sessions-shared.tgz" -C "$APP"; }
[ -f "$BK/local-agent-mode-sessions.tgz" ] && tar -xzf "$BK/local-agent-mode-sessions.tgz" -C "$APP" || true

echo "✅ Đã bung dữ liệu."
echo ""
echo "BƯỚC TIẾP THEO:"
echo "  • Nếu username máy mới = máy gốc (hieu_icetea): chạy lại"
echo "      $HERE/setup-unified-sessions.sh --apply"
echo "    để dựng lại symlink cho các team, rồi mở Claude Desktop."
echo "  • Nếu username/đường dẫn KHÁC: mở Claude Code và dán nội dung"
echo "      shared/RESTORE-PROMPT.md   (Claude sẽ sửa slug/cwd cho khớp)."
