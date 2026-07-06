#!/usr/bin/env bash
# Di chuyển danh sách phiên Claude Code (tab Code của Claude Desktop) từ team CŨ sang team MỚI.
# Dùng khi đổi/deactivate team làm Recents trong Desktop trống.
#
# Nội dung hội thoại (transcript) nằm ở ~/.claude/projects/ — KHÔNG bị đụng tới.
# Script này chỉ copy file CHỈ MỤC metadata (local_*.json), an toàn & hoàn tác được.
#
# Cách dùng:
#   1) Tắt Claude Desktop trước (khuyến nghị), hoặc chạy rồi restart Desktop sau.
#   2) ./migrate-team-sessions.sh <ORG_UUID_CŨ> <ORG_UUID_MỚI>
#      (Nếu bỏ trống ORG_MỚI, script tự lấy org đang active từ ~/.claude.json)
#   Tìm ORG_UUID: ls "~/Library/Application Support/Claude/claude-code-sessions/<account>/"
#
set -euo pipefail
BASE="$HOME/Library/Application Support/Claude/claude-code-sessions"

# Account UUID (thư mục con duy nhất theo tài khoản)
ACC=$(ls "$BASE" | head -1)
ROOT="$BASE/$ACC"

OLD="${1:-}"
NEW="${2:-$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.claude.json')))['oauthAccount']['organizationUuid'])")}"

if [ -z "$OLD" ] || [ ! -d "$ROOT/$OLD" ]; then
  echo "❌ Thiếu/không thấy ORG_CŨ. Các org hiện có:"; ls "$ROOT"; exit 1
fi
mkdir -p "$ROOT/$NEW"

# Backup trước
TS=$(date +%Y%m%d-%H%M%S); BK="$HOME/.claude/backups/team-migration-$TS"
mkdir -p "$BK"; tar -czf "$BK/claude-code-sessions.tgz" -C "$(dirname "$BASE")" "$(basename "$BASE")"
echo "✅ Backup: $BK/claude-code-sessions.tgz"

# Copy skip-if-exists
c=0; s=0
for f in "$ROOT/$OLD"/local_*.json; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  if [ -f "$ROOT/$NEW/$b" ]; then s=$((s+1)); else cp "$f" "$ROOT/$NEW/$b"; c=$((c+1)); fi
done
echo "✅ Đã copy $c phiên mới, bỏ qua $s phiên đã có."
echo "→ Khởi động lại Claude Desktop để thấy danh sách trong team mới."
