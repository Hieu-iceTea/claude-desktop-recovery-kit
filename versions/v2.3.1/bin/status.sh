#!/usr/bin/env bash
# =============================================================================
# status.sh   (v2.3.1)
# Kiểm tra sức khoẻ: thư mục dùng chung, symlink các team, đối chiếu transcript.
# Chỉ ĐỌC, không thay đổi dữ liệu Claude.
#
# Cách dùng:
#   status.sh            # in báo cáo ra màn hình
#   status.sh --save     # in màn hình + LƯU bản báo cáo vào <KIT>/reports/status-<TS>.txt
#                        # (reports/ tự tạo nếu chưa có; mỗi lần là file MỚI, KHÔNG xoá báo cáo cũ)
# =============================================================================
# KHÔNG dùng `-e`: toàn bộ báo cáo ghi vào $TMP rồi mới in ra. Với `-e`, chỉ cần MỘT
# lệnh trả mã khác 0 (grep không khớp, team chưa gộp…) là cả khối chết giữa chừng,
# trap xoá $TMP → script im lặng tuyệt đối, exit 1, người dùng không thấy dòng nào.
# Gặp thật 26/08/2026. Script BÁO CÁO thì không bao giờ được tự tử vì một lệnh con.
set -uo pipefail
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

echo ""
echo "Lớp B — Chặn tự xoá transcript (cleanupPeriodDays):"
/usr/bin/python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
v = None
try:
    v = json.load(open(p)).get("cleanupPeriodDays")
except Exception:
    pass
if v is None:
    print("  ⛔ CHƯA ĐẶT → Claude Code tự XOÁ transcript sau 30 ngày.")
    print("     Sửa: thêm \"cleanupPeriodDays\": 36500 vào ~/.claude/settings.json")
elif v < 365:
    print(f"  ⚠️  Đang là {v} ngày — transcript cũ hơn mốc này sẽ bị xoá.")
else:
    print(f"  ✅ {v} ngày (~{v//365} năm) — không bị tự xoá.")
PY

echo ""
echo "Lớp C — Hội thoại còn nội dung nhưng MẤT khỏi Recents:"
/usr/bin/python3 - "$SHARED" "$PROJ" <<'PY'
import json, glob, os, sys, time
SHARED, PROJ = sys.argv[1], sys.argv[2]
idx = set()
for p in glob.glob(SHARED + "/local_*.json"):
    try:
        c = json.load(open(p)).get("cliSessionId")
        if c: idx.add(c)
    except Exception:
        pass
dele = {os.path.basename(f)[len("deleted_"):] for f in glob.glob(SHARED + "/deleted_*")}
cut = time.time() - 30 * 86400
n = 0
for f in glob.glob(PROJ + "/*/*.jsonl"):
    cli = os.path.basename(f)[:-6]
    if cli in idx or cli in dele: continue
    if os.path.getsize(f) < 20000 or os.path.getmtime(f) < cut: continue
    n += 1
print(f"  {n} transcript mồ côi trong 30 ngày — phần lớn là bản rẽ nhánh cũ (bình thường).")
PY
# Con số THỰC SỰ đáng lo: hỏi chính các script sửa (một nguồn sự thật duy nhất).
# PHẢI hỏi CẢ HAI — repair bỏ qua mọi đoạn nén tiếp nối, nên hội thoại mà MỌI đoạn
# đều là đoạn nén thì repair báo "đủ" trong khi nó đã mất hẳn khỏi danh sách.
# Gặp thật 26/08/2026: repair báo ✅ trong khi 7 hội thoại không còn mục nào.
BINDIR="$(dirname "${BASH_SOURCE[0]}")"
REPAIR="$BINDIR/repair-missing-sessions.sh"
LOST="$BINDIR/restore-lost-entries.sh"
OK=1
if [ -x "$LOST" ]; then
  LN="$("$LOST" 2>/dev/null | sed -n 's/^Sẽ tạo \([0-9]*\) mục.*/\1/p' || true)"
  if [ -n "${LN:-}" ]; then
    OK=0
    echo "  ⛔ $LN hội thoại KHÔNG CÒN MỤC NÀO trong danh sách (mất hẳn, còn nguyên nội dung)."
    echo "     Sửa: Cmd+Q thoát Claude Desktop rồi chạy: restore-lost-entries.sh --apply"
  fi
else
  echo "     (không thấy restore-lost-entries.sh để soi chi tiết)"
fi
if [ -x "$REPAIR" ]; then
  RN="$("$REPAIR" 2>/dev/null | sed -n 's/^Sẽ đưa lại \([0-9]*\) hội thoại.*/\1/p' || true)"
  if [ -n "${RN:-}" ]; then
    OK=0
    echo "  ⛔ $RN phiên mồ côi có thể đưa lại vào Recents (còn nội dung, chưa từng bị bạn xoá)."
    echo "     Sửa: Cmd+Q thoát Claude Desktop rồi chạy: repair-missing-sessions.sh --apply"
  fi
else
  echo "     (không thấy repair-missing-sessions.sh để soi chi tiết)"
fi
[ "$OK" -eq 1 ] && echo "  ✅ Không hội thoại nào bị mất khỏi Recents."

echo ""
echo "Lớp D — Bản sao lưu (snapshot):"
SNAPDIR="$HOME/DATA/claude-backups"
if [ -d "$SNAPDIR" ] && [ -e "$SNAPDIR/latest" ]; then
  LASTSNAP="$(basename "$(readlink "$SNAPDIR/latest" 2>/dev/null || echo '?')")"
  AGE_H=$(( ( $(date +%s) - $(stat -f %m "$SNAPDIR/latest" 2>/dev/null || echo 0) ) / 3600 ))
  NSNAP="$(ls -1d "$SNAPDIR"/snap-* 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$AGE_H" -le 48 ]; then
    echo "  ✅ mới nhất: $LASTSNAP (${AGE_H}h trước) — $NSNAP bản, $(du -sh "$SNAPDIR" 2>/dev/null | cut -f1)"
  else
    echo "  ⚠️  mới nhất: $LASTSNAP đã ${AGE_H}h — kiểm tra lịch tự động"
  fi
else
  echo "  ⛔ CHƯA có snapshot nào — chạy: snapshot.sh"
fi
# grep -c đọc hết đầu vào; KHÔNG dùng grep -q (thoát sớm → SIGPIPE → pipefail sai)
LOADED="$(launchctl list 2>/dev/null | grep -c "com.hieund.claude-backup" || true)"
if [ "${LOADED:-0}" -gt 0 ]; then
  echo "  ✅ lịch tự động đang chạy (com.hieund.claude-backup)"
else
  echo "  ⚠️  CHƯA cài lịch tự động — snapshot sẽ không tự chạy"
fi
# LƯU Ý: `tmutil destinationinfo` trả exit code 0 KỂ CẢ khi không có đích nào.
# Phải đếm dòng "Name" chứ không tin vào exit code.
TMDEST="$(tmutil destinationinfo 2>/dev/null | grep -c '^Name' || true)"
if [ "${TMDEST:-0}" -gt 0 ]; then
  echo "  ✅ Time Machine: $TMDEST đích sao lưu"
else
  echo "  ⛔ KHÔNG có Time Machine — snapshot nằm CÙNG ổ, hỏng ổ là mất hết"
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
