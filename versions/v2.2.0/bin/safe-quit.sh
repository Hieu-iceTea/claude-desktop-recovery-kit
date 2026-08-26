#!/usr/bin/env bash
# =============================================================================
# safe-quit.sh   (v2.2.0)
#
# DÙNG THAY CHO Cmd+Q.
#
# Vấn đề: Claude Desktop hiện KHÔNG ghi file chỉ mục Recents (lỗi của app, xem
# README v2.2.0). Hội thoại mới tạo có transcript đầy đủ nhưng KHÔNG có mục
# trong Recents → khởi động lại là biến mất khỏi danh sách.
#
# Script này gộp đúng 3 việc phải làm, theo đúng thứ tự, trong một lệnh:
#   1. Thoát hẳn Claude Desktop (thoát êm, không kill)
#   2. Đợi tiến trình thật sự kết thúc
#   3. Chạy repair-missing-sessions.sh --apply  (lúc này app đã đóng → an toàn)
#   4. Mở lại Claude Desktop
#
# KHÔNG có tiến trình chạy nền, KHÔNG có lịch tự động. Chỉ chạy khi bạn gõ.
#
# Cách dùng:
#   safe-quit.sh              # thoát → vá → mở lại
#   safe-quit.sh --no-reopen  # thoát → vá, không mở lại
#   safe-quit.sh --dry-run    # chỉ in ra sẽ làm gì, không đụng vào Claude
#
# ⚠️ Đợi Claude trả lời xong rồi hãy chạy — script thoát app ngay lập tức.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPAIR="$HERE/repair-missing-sessions.sh"
APPNAME="Claude"
WAIT_MAX=40                      # giây chờ tối đa cho app thoát

REOPEN=1; DRY=0
for a in "$@"; do
  case "$a" in
    --no-reopen) REOPEN=0 ;;
    --dry-run)   DRY=1 ;;
    -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Tham số lạ: $a"; exit 2 ;;
  esac
done

[ -x "$REPAIR" ] || { echo "❌ Không thấy $REPAIR"; exit 1; }

# Đếm tiến trình chính. grep -c đọc hết đầu vào + '|| true' — KHÔNG dùng grep -q
# (thoát sớm gây SIGPIPE cho ps, với pipefail sẽ làm điều kiện sai âm thầm).
running() { ps -Ao args | grep -c "Claude\.app/Contents/MacOS/Claude$" || true; }

if [ "$DRY" -eq 1 ]; then
  echo "🔍 XEM TRƯỚC — không đụng vào Claude"
  echo "   Claude đang chạy : $([ "$(running)" -gt 0 ] && echo CÓ || echo KHÔNG)"
  echo "   Sẽ làm:"
  echo "     1. osascript -e 'quit app \"$APPNAME\"'"
  echo "     2. đợi tối đa ${WAIT_MAX}s cho tiến trình kết thúc"
  echo "     3. $REPAIR --apply"
  [ "$REOPEN" -eq 1 ] && echo "     4. open -a $APPNAME"
  echo
  echo "   Hiện đang thiếu mục Recents:"
  "$REPAIR" 2>/dev/null | sed -n 's/^Sẽ đưa lại \([0-9]*\) hội thoại.*/     \1 hội thoại/p;s/^\(✅ Không có hội thoại nào bị mất.*\)/     \1/p'
  exit 0
fi

# ── 1. Thoát êm ─────────────────────────────────────────────────────────────
if [ "$(running)" -gt 0 ]; then
  echo "→ [1/4] Thoát Claude Desktop..."
  osascript -e "quit app \"$APPNAME\"" 2>/dev/null || true
else
  echo "→ [1/4] Claude Desktop không chạy sẵn — bỏ qua."
fi

# ── 2. Đợi thật sự kết thúc ─────────────────────────────────────────────────
echo "→ [2/4] Đợi tiến trình kết thúc..."
i=0
while [ "$(running)" -gt 0 ]; do
  i=$((i + 1))
  if [ "$i" -ge "$WAIT_MAX" ]; then
    echo "❌ Sau ${WAIT_MAX}s Claude vẫn chạy — có thể đang hỏi xác nhận thoát."
    echo "   Xử lý cửa sổ đó rồi chạy lại. KHÔNG có gì bị thay đổi."
    exit 1
  fi
  sleep 1
done
echo "   ✅ đã thoát hẳn (sau ${i}s)"

# ── 3. Vá chỉ mục ───────────────────────────────────────────────────────────
echo "→ [3/4] Đưa lại các hội thoại bị thiếu vào Recents..."
"$REPAIR" --apply
RC=$?

# ── 4. Mở lại ───────────────────────────────────────────────────────────────
if [ "$REOPEN" -eq 1 ]; then
  echo "→ [4/4] Mở lại Claude Desktop..."
  open -a "$APPNAME"
else
  echo "→ [4/4] Bỏ qua mở lại (--no-reopen)."
fi

echo
[ "$RC" -eq 0 ] && echo "✅ Xong. Hội thoại vừa làm việc đã nằm trong Recents." \
               || echo "⚠️  Bước vá trả mã lỗi $RC — đọc thông báo phía trên."
