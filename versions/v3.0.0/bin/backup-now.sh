#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────────────────────
#  ⚠️  ĐÃ CÓ BẢN THAY THẾ TỐT HƠN TỪ v3.0.0:  claude-history save
#
#  Script này dùng rsync --link-dest. Hardlink chỉ giúp với file KHÔNG ĐỔI, mà
#  Claude ghi thêm vào transcript liên tục => chép lại NGUYÊN file mỗi lần.
#  Đo thật: kho snapshot phình 3,0 → 5,6 GB, tổng 7,5 GB cho 10 bản.
#  Ghi thêm 1,5 MB vào 3 transcript: rsync tốn 64.440 KB · git tốn 0 KB.
#
#  Vẫn chạy được (chưa gỡ) nhưng đừng dùng cho việc mới.
# ─────────────────────────────────────────────────────────────────────────────
echo "⚠️  Script này đã có bản thay thế: claude-history save  (kho git, nhẹ hơn nhiều)" >&2
echo "   Vẫn chạy tiếp sau 3 giây. Ctrl+C để dừng." >&2
sleep 3
# =============================================================================
# backup-now.sh   (v2.1.0)
# Sao lưu ĐẦY ĐỦ để khôi phục máy mới / sau khi reset. Sao lưu:
#   1) Transcript (nội dung thật):  ~/.claude/projects
#   2) Chỉ mục Recents:             claude-code-sessions
#   3) Thư mục dùng chung (MỚI v2): claude-code-sessions-shared   ← QUAN TRỌNG
#   4) Legacy (nếu có):             local-agent-mode-sessions
#   5) ~/.claude.json
# Lưu vào recovery-data/<TS>-full-v<VER>/  (mỗi lần 1 thư mục: dấu thời gian + loại + version).
# =============================================================================
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VER="$(cat "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VERSION" 2>/dev/null || echo '?')"
APP="$HOME/Library/Application Support/Claude"
TS=$(date +%Y%m%d-%H%M%S)
OUT="$KIT/recovery-data/$TS-full-v$VER"
mkdir -p "$OUT"

echo "→ [1] Transcript (~/.claude/projects)..."
tar -czf "$OUT/projects.tgz" -C "$HOME/.claude" projects

echo "→ [2] Chỉ mục Desktop (claude-code-sessions)..."
tar -czf "$OUT/claude-code-sessions.tgz" -C "$APP" claude-code-sessions

if [ -d "$APP/claude-code-sessions-shared" ]; then
  echo "→ [3] Thư mục dùng chung (claude-code-sessions-shared)..."
  tar -czf "$OUT/claude-code-sessions-shared.tgz" -C "$APP" claude-code-sessions-shared
fi
if [ -d "$APP/local-agent-mode-sessions" ]; then
  echo "→ [4] Legacy (local-agent-mode-sessions)..."
  tar -czf "$OUT/local-agent-mode-sessions.tgz" -C "$APP" local-agent-mode-sessions
fi
[ -f "$HOME/.claude.json" ] && cp "$HOME/.claude.json" "$OUT/claude.json.bak" || true

{ date "+Backup lúc: %Y-%m-%d %H:%M:%S"; echo "Máy: $(whoami) @ $HOME"; } > "$OUT/last-backup.txt"
# (v2.1.0) MANIFEST: ghi version + lệnh khôi phục chính xác theo đúng version
{ echo "MANIFEST — claude-desktop-recovery-kit backup"
  echo "Loại backup   : backup-now (đầy đủ — khôi phục máy mới/thảm hoạ)"
  echo "Phiên bản kit : v$VER"
  echo "Script tạo    : backup-now.sh"
  echo "Thời điểm     : $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Máy           : $(whoami) @ $HOME"
  echo "Kit           : $KIT"
  echo "Nội dung      : projects.tgz (transcript), claude-code-sessions.tgz, claude-code-sessions-shared.tgz (nếu có), local-agent-mode-sessions.tgz (nếu có), claude.json.bak"
  echo ""
  echo "KHÔI PHỤC (dùng ĐÚNG version đã tạo backup này):"
  echo "  \"$KIT/versions/v$VER/bin/restore-from-backup.sh\" \"$OUT\""
  echo "  rồi: \"$KIT/versions/v$VER/bin/setup-unified-sessions.sh\" --apply"
} > "$OUT/MANIFEST.txt"
echo "✅ Xong. Bản sao lưu: $OUT  (kèm MANIFEST.txt — kit v$VER)"
du -sh "$OUT"/*.tgz 2>/dev/null || true
echo "→ Bộ kit nằm tại: $KIT"
echo "  Hãy giữ TOÀN BỘ thư mục kit này ở nơi an toàn (USB / cloud / ổ ngoài) — bạn tự chọn vị trí."
