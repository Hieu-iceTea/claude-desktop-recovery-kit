#!/usr/bin/env bash
# =============================================================================
# rollback-unified-sessions.sh   (v2.1.0)
# Hoàn tác setup: gỡ symlink, trả các folder team gốc về đúng vị trí ban đầu.
#
# Cách dùng:
#   rollback-unified-sessions.sh <thư-mục-backup>
#   ví dụ: rollback-unified-sessions.sh <thư-mục-kit>/recovery-data/20260615-120000
# =============================================================================
set -euo pipefail
BASE="$HOME/Library/Application Support/Claude/claude-code-sessions"
VER="$(cat "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VERSION" 2>/dev/null || echo '?')"
BK="${1:-}"
[ -n "$BK" ] && [ -d "$BK/orig-folders" ] || {
  echo "❌ Thiếu/không thấy thư mục backup hợp lệ."
  echo "   Dùng: $(basename "$0") <thư-mục-backup-có-orig-folders>"; exit 1; }

# (v2.1.0) Kiểm tra version: backup nên được rollback bằng ĐÚNG version đã tạo nó
BK_VER="$(grep -E '^Phiên bản kit' "$BK/MANIFEST.txt" 2>/dev/null | sed -E 's/.*v//' | tr -d ' ' || true)"
echo "Rollback script: v$VER  |  Backup tạo bởi: ${BK_VER:-không rõ (backup cũ, trước v2.1.0)}"
if [ -n "$BK_VER" ] && [ "$BK_VER" != "$VER" ]; then
  echo "⚠️  CẢNH BÁO: version KHÁC nhau. Nên chạy rollback bằng:"
  echo "     <kit>/versions/v$BK_VER/bin/rollback-unified-sessions.sh \"$BK\""
  printf "Vẫn tiếp tục bằng v$VER? Gõ 'FORCE' để tiếp: "; read -r fa; [ "$fa" = "FORCE" ] || { echo "Đã huỷ."; exit 0; }
fi

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
