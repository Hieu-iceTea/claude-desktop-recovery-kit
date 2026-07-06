#!/usr/bin/env bash
# =============================================================================
# status.sh   (v2.1.0)
# Kiểm tra sức khoẻ: thư mục dùng chung, symlink các team, đối chiếu transcript.
# Chỉ ĐỌC, không thay đổi dữ liệu Claude.
#
# Cách dùng:
#   status.sh            # in báo cáo ra màn hình
#   status.sh --save     # in màn hình + LƯU bản báo cáo vào <KIT>/reports/status-<TS>.txt
#                        # (reports/ tự tạo nếu chưa có; mỗi lần là file MỚI, KHÔNG xoá báo cáo cũ)
# =============================================================================
set -euo pipefail
BASE="$HOME/Library/Application Support/Claude/claude-code-sessions"
SHARED="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
PROJ="$HOME/.claude/projects"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REPORTS="$KIT/reports"
VERDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"           # versions/vX.Y.Z
VER="$(cat "$VERDIR/VERSION" 2>/dev/null || echo '?')"

SAVE=0
for a in "$@"; do case "$a" in --save) SAVE=1;; *) echo "Tham số lạ: $a"; exit 2;; esac; done

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

# ---- Toàn bộ báo cáo ghi vào TMP (để vừa in vừa có thể lưu file) ----
{
echo "════════ BÁO CÁO TRẠNG THÁI UNIFIED SESSIONS ════════"
echo "Thời điểm    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Phiên bản kit: v$VER   (claude-desktop-recovery-kit)"
echo "Máy          : $(whoami) @ $HOME"
echo "Kit          : $KIT"
echo "Thư mục dùng chung: $SHARED"
if [ -d "$SHARED" ]; then
  echo "  ✅ tồn tại — $(ls "$SHARED"/local_*.json 2>/dev/null | wc -l | tr -d ' ') phiên"
else
  echo "  ❌ CHƯA tạo (chạy setup-unified-sessions.sh --apply)"
fi
echo ""
echo "Các folder team:"
nlink=0; nreal=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  rel="${d#$BASE/}"
  if [ -L "$d" ]; then
    tgt="$(readlink "$d")"
    if [ "$tgt" = "$SHARED" ]; then echo "  ✅ [symlink→shared] $rel"; nlink=$((nlink+1))
    else echo "  ⚠️  [symlink→KHÁC] $rel -> $tgt"; fi
  else
    n=$(ls "$d"/local_*.json 2>/dev/null | wc -l | tr -d ' ')
    echo "  ⛔ [folder THẬT, CHƯA gộp] $rel ($n phiên) — chạy lại setup để gộp"
    nreal=$((nreal+1))
  fi
done < <(find "$BASE" -mindepth 2 -maxdepth 2 \( -type d -o -type l \) | sort)
echo ""
echo "Tổng: $nlink team đã symlink, $nreal team chưa gộp."
[ "$nreal" -gt 0 ] && echo "⚠️  Có team chưa gộp (team mới / sau update) → chạy: setup-unified-sessions.sh --apply"

if [ -d "$SHARED" ]; then
  echo ""
  echo "Đối chiếu chỉ mục ↔ transcript (Lớp A):"
  /usr/bin/python3 - "$SHARED" "$PROJ" <<'PY'
import json,glob,os,sys
SHARED,PROJ=sys.argv[1],sys.argv[2]
ref=set()
for p in glob.glob(SHARED+"/local_*.json"):
    try: ref.add(json.load(open(p)).get("cliSessionId"))
    except: pass
ref.discard(None)
have={os.path.basename(f)[:-6] for f in glob.glob(PROJ+"/*/*.jsonl")}
miss=ref-have
print(f"  Phiên trong shared: {len(ref)} | có transcript: {len(ref&have)} | THIẾU transcript: {len(miss)}")
for m in list(miss)[:10]: print("    ⚠️ thiếu:", m)
PY
fi
echo "═════════════════════════════════════════════════════"
} > "$TMP" 2>&1

cat "$TMP"

if [ "$SAVE" = 1 ]; then
  mkdir -p "$REPORTS"
  OUT="$REPORTS/status-$(date +%Y%m%d-%H%M%S)-v$VER.txt"
  cp "$TMP" "$OUT"
  echo ""
  echo "💾 Đã lưu báo cáo: $OUT"
fi
