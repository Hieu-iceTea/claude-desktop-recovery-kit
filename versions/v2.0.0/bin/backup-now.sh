#!/usr/bin/env bash
# =============================================================================
# backup-now.sh   (v2.0.0)
# Sao lưu ĐẦY ĐỦ để khôi phục máy mới / sau khi reset. Sao lưu:
#   1) Transcript (nội dung thật):  ~/.claude/projects
#   2) Chỉ mục Recents:             claude-code-sessions
#   3) Thư mục dùng chung (MỚI v2): claude-code-sessions-shared   ← QUAN TRỌNG
#   4) Legacy (nếu có):             local-agent-mode-sessions
#   5) ~/.claude.json
# Lưu vào recovery-data/<TS>/  (mỗi lần 1 thư mục có dấu thời gian).
# =============================================================================
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP="$HOME/Library/Application Support/Claude"
TS=$(date +%Y%m%d-%H%M%S)
OUT="$KIT/recovery-data/$TS"
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
echo "✅ Xong. Bản sao lưu: $OUT"
du -sh "$OUT"/*.tgz 2>/dev/null || true
echo "→ Bộ kit nằm tại: $KIT"
echo "  Hãy giữ TOÀN BỘ thư mục kit này ở nơi an toàn (USB / cloud / ổ ngoài) — bạn tự chọn vị trí."
