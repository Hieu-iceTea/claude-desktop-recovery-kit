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

# ── Lớp B: máy MỚI mặc định cleanupPeriodDays = 30 → sẽ xoá dần transcript vừa khôi phục.
# Đây là bẫy chết người: khôi phục xong tưởng an toàn, 30 ngày sau mất lại.
echo ""
echo "→ [4] Kiểm tra chặn tự xoá transcript (cleanupPeriodDays)..."
/usr/bin/python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
try:
    d = json.load(open(p))
except Exception:
    d = {}
v = d.get("cleanupPeriodDays")
if v is None or v < 365:
    d["cleanupPeriodDays"] = 36500
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    print(f"   ⚠️  Đang là {v!r} → ĐÃ ĐẶT 36500 ngày.")
    print("      (Mặc định 30 ngày sẽ xoá dần chính số transcript vừa khôi phục.)")
else:
    print(f"   ✅ Đã là {v} ngày — không bị tự xoá.")
PY

echo ""
echo "BƯỚC TIẾP THEO:"
echo "  • Nếu username máy mới = máy gốc (hieu_icetea): chạy lại"
echo "      $HERE/setup-unified-sessions.sh --apply"
echo "    để dựng lại symlink cho các team, rồi mở Claude Desktop."
echo "  • Nếu username/đường dẫn KHÁC: mở Claude Code và dán nội dung"
echo "      shared/RESTORE-PROMPT.md   (Claude sẽ sửa slug/cwd cho khớp)."
