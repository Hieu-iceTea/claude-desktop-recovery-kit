#!/usr/bin/env bash
# === SAO LƯU dữ liệu hội thoại Claude Desktop (tab Code) ===
# Chạy script này TRƯỚC KHI cài lại máy / chuyển sang máy khác để có bản mới nhất.
# Sao lưu 2 thứ:
#   1) Nội dung thật:  ~/.claude/projects               (các file .jsonl)
#   2) Chỉ mục Recents: claude-code-sessions             (để Desktop hiện danh sách)
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$KIT/backup"; mkdir -p "$OUT"
APP="$HOME/Library/Application Support/Claude"

echo "→ Sao lưu transcript (~/.claude/projects)..."
tar -czf "$OUT/projects.tgz" -C "$HOME/.claude" projects

echo "→ Sao lưu chỉ mục Desktop (claude-code-sessions)..."
tar -czf "$OUT/claude-code-sessions.tgz" -C "$APP" claude-code-sessions

if [ -d "$APP/local-agent-mode-sessions" ]; then
  echo "→ Sao lưu thư mục legacy (local-agent-mode-sessions)..."
  tar -czf "$OUT/local-agent-mode-sessions.tgz" -C "$APP" local-agent-mode-sessions
fi

{ date "+Backup lúc: %Y-%m-%d %H:%M:%S"; echo "Từ máy: $(whoami) @ $HOME"; } > "$OUT/last-backup.txt"
echo "✅ Xong. Bản sao lưu nằm trong: $OUT"
du -sh "$OUT"/*.tgz
echo "→ Hãy giữ TOÀN BỘ thư mục kit này ở nơi an toàn (USB, cloud, ổ ngoài)."
