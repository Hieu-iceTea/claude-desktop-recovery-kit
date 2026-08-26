#!/usr/bin/env bash
# =============================================================================
# clean-orphan-transcripts.sh   (v2.1.0)
# Dọn "transcript mồ côi" = file .jsonl trong ~/.claude/projects KHÔNG còn được
# bất kỳ chỉ mục nào tham chiếu (đã bị "Xóa" khỏi danh sách Claude Desktop, nhưng
# nội dung vẫn nằm trên đĩa và TỐN bộ nhớ).
#
# AN TOÀN:
#   • Mặc định --dry-run : CHỈ LIỆT KÊ.
#   • --apply : CHUYỂN vào thùng rác recovery-data/orphan-trash-<TS>-v<VER>/ (hoàn tác được), hỏi xác nhận.
#   • --hard  : xoá CỨNG (giải phóng đĩa ngay), hỏi xác nhận 2 lần.
# ⚠️ Mồ côi cũng có thể là phiên CLI hữu ích — ĐỌC KỸ trước khi đồng ý.
# Tương thích bash 3.2.
# =============================================================================
set -euo pipefail
BASE="$HOME/Library/Application Support/Claude/claude-code-sessions"
SHARED="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
PROJ="$HOME/.claude/projects"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VER="$(cat "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VERSION" 2>/dev/null || echo '?')"

MODE="dry-run"
for a in "$@"; do case "$a" in --apply) MODE="apply";; --hard) MODE="hard";; --dry-run) MODE="dry-run";; *) echo "Tham số lạ: $a"; exit 2;; esac; done

# Liệt kê mồ côi: "<size_bytes>\t<path>" mỗi dòng, sắp giảm dần theo size
LIST="$(mktemp)"; trap 'rm -f "$LIST"' EXIT
/usr/bin/python3 - "$BASE" "$SHARED" "$PROJ" > "$LIST" <<'PY'
import json,glob,os,sys
BASE,SHARED,PROJ=sys.argv[1],sys.argv[2],sys.argv[3]
ref=set()
for d in (BASE,SHARED):
    for p in glob.glob(d+"/**/local_*.json",recursive=True):
        try: ref.add(json.load(open(p)).get("cliSessionId"))
        except: pass
ref.discard(None)
rows=[]
for f in glob.glob(PROJ+"/*/*.jsonl"):
    if os.path.basename(f)[:-6] in ref: continue
    rows.append((os.path.getsize(f),f))
rows.sort(reverse=True)
for sz,f in rows: print(f"{sz}\t{f}")
PY

CNT=$(wc -l < "$LIST" | tr -d ' ')
BYTES=$(awk -F'\t' '{s+=$1} END{print s+0}' "$LIST")
MB=$(/usr/bin/python3 -c "print(f'{$BYTES/1024/1024:.1f}')")

echo "════════ TRANSCRIPT MỒ CÔI ════════"
while IFS=$'\t' read -r sz f; do
  [ -n "$sz" ] || continue
  printf "%9.1f KB  %s\n" "$(/usr/bin/python3 -c "print($sz/1024)")" "${f/$HOME/~}"
done < "$LIST"
echo "-----------------------------------"
echo "TỔNG: $CNT file = $MB MB"
echo ""
[ "$CNT" = "0" ] && { echo "✅ Không có file mồ côi."; exit 0; }

# ── CẢNH BÁO: "mồ côi" KHÔNG có nghĩa là "rác" ──────────────────────────────
# Bài học 12/08/2026: hội thoại dài bị NÉN NGỮ CẢNH thành nhiều file; Recents chỉ
# trỏ được vào MỘT file, các file còn lại thành "mồ côi" nhưng vẫn giữ phần lớn
# lịch sử. Đo thực tế trên máy này: 721 file mồ côi chứa 2625 lượt hỏi KHÔNG mở
# được từ bất kỳ mục Recents nào. Xoá chúng = mất thật, không phải dọn rác.
LOSS="$(LIST="$LIST" /usr/bin/python3 - <<'PY'
import json, os
n = 0
for line in open(os.environ["LIST"]):
    p = line.rstrip("\n").split("\t", 1)
    if len(p) < 2: continue
    try:
        for l in open(p[1], errors="replace"):
            l = l.strip()
            if not l: continue
            o = json.loads(l)
            if o.get("type") != "user": continue
            c = (o.get("message") or {}).get("content")
            s = c if isinstance(c, str) else " ".join(
                x.get("text","") for x in c if isinstance(x, dict) and x.get("type")=="text"
            ) if isinstance(c, list) else ""
            s = " ".join(s.split())
            if s and len(s) >= 25 and not s.startswith(("<","[Request","This session","Caveat:")):
                n += 1
    except Exception:
        pass
print(n)
PY
)"
echo "⚠️  $CNT file này chứa khoảng ${LOSS:-?} lượt hỏi của bạn."
echo "   Phần lớn KHÔNG mở được từ Recents nhưng vẫn là nội dung thật."
echo "   Xem chính xác cái nào không tiếp cận được:"
echo "     repair-missing-sessions.sh --unreachable"
echo ""

if [ "$MODE" = "dry-run" ]; then
  echo "🔎 dry-run — KHÔNG xoá gì. Dùng --apply (thùng rác) hoặc --hard (xoá cứng)."; exit 0
fi

TS=$(date +%Y%m%d-%H%M%S)
if [ "$MODE" = "apply" ]; then
  TRASH="$KIT/recovery-data/orphan-trash-$TS-v$VER"
  printf "Gõ 'YES' để CHUYỂN %s file vào thùng rác %s: " "$CNT" "$TRASH"; read -r a
  [ "$a" = "YES" ] || { echo "Đã huỷ."; exit 0; }
  while IFS=$'\t' read -r sz f; do
    [ -n "$f" ] || continue
    rel="${f#$PROJ/}"; mkdir -p "$TRASH/$(dirname "$rel")"; mv "$f" "$TRASH/$rel"
  done < "$LIST"
  echo "✅ Đã chuyển $CNT file vào $TRASH (hoàn tác: mv trở lại $PROJ)."
elif [ "$MODE" = "hard" ]; then
  printf "⚠️ XOÁ CỨNG %s file (%s MB), KHÔNG hoàn tác. Gõ 'DELETE' lần 1: " "$CNT" "$MB"; read -r a1
  [ "$a1" = "DELETE" ] || { echo "Đã huỷ."; exit 0; }
  printf "Gõ 'DELETE' lần 2: "; read -r a2; [ "$a2" = "DELETE" ] || { echo "Đã huỷ."; exit 0; }
  while IFS=$'\t' read -r sz f; do [ -n "$f" ] && rm -f "$f"; done < "$LIST"
  echo "✅ Đã xoá cứng $CNT file, giải phóng ~$MB MB."
fi
