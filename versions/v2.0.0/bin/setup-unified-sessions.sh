#!/usr/bin/env bash
# =============================================================================
# setup-unified-sessions.sh   (claude-desktop-recovery-kit v2.0.0)
# -----------------------------------------------------------------------------
# Gộp chỉ mục phiên Claude Code của MỌI tài khoản/team về MỘT thư mục dùng chung
# (shared), rồi cho mỗi folder team trỏ SYMLINK vào shared.
# => Mọi tài khoản/team thấy CÙNG một danh sách, tự động đồng bộ.
#
# Chỉ thao tác LỚP B (chỉ mục local_*.json). KHÔNG đụng ~/.claude/projects.
# Tương thích bash 3.2 (mặc định trên macOS) — không dùng mapfile / mảng kết hợp.
#
# Cách dùng:
#   setup-unified-sessions.sh                 # mặc định = --dry-run (chỉ xem trước)
#   setup-unified-sessions.sh --apply         # thực thi (tự backup trước)
#   setup-unified-sessions.sh --apply --yes   # thực thi, không hỏi (AI giám sát)
# =============================================================================
set -euo pipefail

BASE="$HOME/Library/Application Support/Claude/claude-code-sessions"
SHARED="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RECOVERY="$KIT/recovery-data"
VER="$(cat "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VERSION" 2>/dev/null || echo '?')"

# Ưu tiên khi trùng tên (org đứng trước = giữ). Team mới không liệt kê => ưu tiên thấp nhất.
PRIO_1="99e6a571-eec1-4a91-8901-d7484f3afb05"   # VIP
PRIO_2="cbb97b9c-5d5c-44c9-a495-5c9631c2966c"   # Kaopiz SBU1
PRIO_3="a917e5a5-5d62-4421-aa08-e22b88253f24"   # 10-InnerTwo
ACTIVE_ORG="$PRIO_2"   # folder đang hoạt động -> symlink SAU CÙNG cho an toàn

MODE="dry-run"; ASSUME_YES=0
for a in "$@"; do case "$a" in
  --apply) MODE="apply";; --dry-run) MODE="dry-run";; --yes|-y) ASSUME_YES=1;;
  *) echo "Tham số lạ: $a"; exit 2;; esac; done

note(){ printf '%s\n' "$*"; }
[ -d "$BASE" ] || { echo "❌ Không thấy: $BASE"; exit 1; }

rank(){ case "$(basename "$1")" in
  "$PRIO_1") echo 1;; "$PRIO_2") echo 2;; "$PRIO_3") echo 3;; *) echo 9;; esac; }

# Danh sách folder team THẬT, sắp theo ưu tiên -> file tạm SORTED
SORTED="$(mktemp)"; trap 'rm -f "$SORTED"' EXIT
find "$BASE" -mindepth 2 -maxdepth 2 -type d | while IFS= read -r d; do
  echo "$(rank "$d")|$d"
done | sort -t'|' -k1,1n -k2 | cut -d'|' -f2- > "$SORTED"

note "════════════════════════════════════════════════════════════════"
note " setup-unified-sessions  (kit v$VER)  •  CHẾ ĐỘ: $MODE"
note "════════════════════════════════════════════════════════════════"
note "Thư mục kit (tự định vị): $KIT"
note "Thư mục backup (recovery-data): $RECOVERY"
note "Thư mục gốc (Lớp B): $BASE"
note "Thư mục dùng chung : $SHARED"
note ""
note "Folder team THẬT sẽ gộp + symlink (theo ưu tiên):"
while IFS= read -r d; do
  [ -n "$d" ] || continue
  n=$(ls "$d"/local_*.json 2>/dev/null | wc -l | tr -d ' ')
  note "   [rank $(rank "$d")] ${d#$BASE/}  ($n phiên)"
done < "$SORTED"

# Folder đã là symlink (bỏ qua)
HAVE_LINK=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ "$HAVE_LINK" = 0 ] && { note ""; note "Folder đã là symlink (bỏ qua):"; HAVE_LINK=1; }
  note "   ${d#$BASE/} -> $(readlink "$d")"
done < <(find "$BASE" -mindepth 2 -maxdepth 2 -type l | sort)

# Union (số phiên duy nhất) = tên file local_*.json duy nhất trên mọi folder (+ shared nếu có)
set +e
UNION=$( { while IFS= read -r d; do [ -n "$d" ] && ls "$d"/local_*.json 2>/dev/null; done < "$SORTED"
           [ -d "$SHARED" ] && ls "$SHARED"/local_*.json 2>/dev/null
           true; } | sed 's#.*/##' | sort -u | grep -c . )
set -e
note ""
note "→ HỢP NHẤT (số phiên duy nhất): $UNION"

if [ "$MODE" = "dry-run" ]; then
  note ""
  note "🔎 XEM TRƯỚC (dry-run) — KHÔNG thay đổi gì. Chạy --apply để thực thi."
  exit 0
fi

# ============================ APPLY =========================================
if [ "$ASSUME_YES" != 1 ]; then
  printf "\nGõ 'APPLY' để thực thi (backup + gộp + symlink): "
  read -r ans; [ "$ans" = "APPLY" ] || { echo "Đã huỷ."; exit 0; }
fi

TS=$(date +%Y%m%d-%H%M%S); BK="$RECOVERY/$TS"; mkdir -p "$BK/orig-folders"
note ""; note "[1/4] Backup -> $BK"
tar -czf "$BK/claude-code-sessions.tgz" -C "$(dirname "$BASE")" "$(basename "$BASE")"
[ -d "$SHARED" ] && tar -czf "$BK/claude-code-sessions-shared.tgz" -C "$(dirname "$SHARED")" "$(basename "$SHARED")" || true
[ -f "$HOME/.claude.json" ] && cp "$HOME/.claude.json" "$BK/claude.json.bak" || true
{ find "$BASE" -mindepth 2 -maxdepth 2 -type d  -exec echo "DIR     {}" \;
  find "$BASE" -mindepth 2 -maxdepth 2 -type l -exec sh -c 'echo "SYMLINK $1 -> $(readlink "$1")"' _ {} \; ; } > "$BK/layout-before.txt" 2>/dev/null || true
note "      ✅ Đã backup chỉ mục + claude.json + layout-before.txt"

note "[2/4] Tạo shared & gộp (ưu tiên VIP > Kaopiz SBU1 > 10-InnerTwo)"
mkdir -p "$SHARED"; copied=0; skipped=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  for f in "$d"/local_*.json; do
    [ -e "$f" ] || continue
    dest="$SHARED/$(basename "$f")"
    if [ ! -e "$dest" ]; then cp -p "$f" "$dest"; copied=$((copied+1)); else skipped=$((skipped+1)); fi
  done
done < "$SORTED"
note "      ✅ shared: thêm $copied, bỏ qua $skipped ⇒ tổng $(ls "$SHARED"/local_*.json 2>/dev/null | wc -l | tr -d ' ') phiên"

note "[3/4] Di chuyển folder gốc vào backup & trỏ symlink (folder đang hoạt động sau cùng)"
do_link(){ d="$1"; rel="${d#$BASE/}"
  mkdir -p "$BK/orig-folders/$(dirname "$rel")"
  mv "$d" "$BK/orig-folders/$rel"; ln -s "$SHARED" "$d"; note "      → symlink: $rel"; }
DEFER=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  if [ "$(basename "$d")" = "$ACTIVE_ORG" ]; then DEFER="$d"; else do_link "$d"; fi
done < "$SORTED"
[ -n "$DEFER" ] && do_link "$DEFER"

note "[4/4] Hoàn tất."
note "════════════════════════════════════════════════════════════════"
note "✅ XONG. Backup tại: $BK"
note "→ Cmd+Q thoát hẳn Claude Desktop rồi mở lại để thấy danh sách chung."
note "→ Hoàn tác: rollback-unified-sessions.sh \"$BK\""
