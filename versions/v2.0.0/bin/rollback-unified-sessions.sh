#!/usr/bin/env bash
# =============================================================================
# rollback-unified-sessions.sh   (v2.0.0)
# Hoàn tác setup: gỡ symlink, trả các folder team gốc về đúng vị trí ban đầu.
#
# Cách dùng:
#   rollback-unified-sessions.sh <thư-mục-backup>
#   ví dụ: rollback-unified-sessions.sh <thư-mục-kit>/recovery-data/20260615-120000
# =============================================================================
set -euo pipefail
BASE="$HOME/Library/Application Support/Claude/claude-code-sessions"
BK="${1:-}"
[ -n "$BK" ] && [ -d "$BK/orig-folders" ] || {
  echo "❌ Thiếu/không thấy thư mục backup hợp lệ."
  echo "   Dùng: $(basename "$0") <thư-mục-backup-có-orig-folders>"; exit 1; }

echo "Sẽ khôi phục các folder team gốc từ: $BK/orig-folders"
printf "Gõ 'ROLLBACK' để tiếp tục: "; read -r a; [ "$a" = "ROLLBACK" ] || { echo "Đã huỷ."; exit 0; }

while IFS= read -r -d '' src; do
  rel="${src#"$BK"/orig-folders/}"; target="$BASE/$rel"
  [ -L "$target" ] && rm "$target"          # gỡ symlink nếu có
  rm -rf "$target"
  mkdir -p "$(dirname "$target")"
  mv "$src" "$target"
  echo "  ↩︎  $rel"
done < <(find "$BK/orig-folders" -mindepth 2 -maxdepth 2 -print0)

echo "✅ Đã trả các folder team về trạng thái ban đầu."
echo "   (Thư mục dùng chung 'claude-code-sessions-shared' vẫn còn — xoá thủ công nếu muốn.)"
echo "   Khôi phục TUYỆT ĐỐI từ ảnh chụp:"
echo "     rm -rf \"$BASE\" && tar -xzf \"$BK/claude-code-sessions.tgz\" -C \"$(dirname "$BASE")\""
echo "→ Cmd+Q thoát hẳn Claude Desktop rồi mở lại."
