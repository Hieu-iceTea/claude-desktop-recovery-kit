#!/usr/bin/env bash
# =============================================================================
# safe-quit.sh   (v2.3.1)
#
# DÙNG THAY CHO Cmd+Q — hoặc chạy ngay SAU khi lỡ Cmd+Q / force quit / mất điện.
#
# ⚠️ THAY ĐỔI LỚN so với v2.2.0: script này KHÔNG CÒN GHI GÌ vào chỉ mục.
#
# Vì sao bỏ bước `repair --apply` tự động:
#   Cả ba lần mất dữ liệu trong dự án này đều do một script GHI vào chỉ mục:
#     12/08/2026  repair --apply          → đẻ 555 mục rác trùng tên
#     18/08/2026  clean-junk --apply      → dọn nhầm mục thật (Phong thủy)
#     26/08/2026  fix-stale --only 1,2,3,4 → REDANCE-1715 tụt 89 → 48 đoạn nội dung
#   Không lần nào mất vì THIẾU chạy script. Mọi lần mất đều vì ĐÃ chạy.
#   Sửa chỉ mục là việc CHỮA, không phải việc PHÒNG. Chữa khi ốm, không uống
#   thuốc mỗi ngày cho chắc.
#
# Bốn việc script làm, không việc nào ghi vào chỉ mục:
#   1. Thoát hẳn Claude Desktop (thoát êm, không kill) — để app kịp ghi nốt
#   2. Đợi tiến trình thật sự kết thúc
#   3. Ghi một bản vào kho git — có đường lùi trước mọi thao tác
#   4. Kiểm tra CHỈ ĐỌC rồi báo cáo. Thiếu gì thì IN RA LỆNH, không tự chạy.
#
# Cách dùng:
#   safe-quit.sh              # thoát → ghi kho git → kiểm tra. KHÔNG mở lại.
#   safe-quit.sh --reopen     # như trên rồi mở lại Claude
#   safe-quit.sh --dry-run    # chỉ in ra sẽ làm gì, không đụng vào Claude
#
# Tên script nói "quit" thì mặc định phải là THOÁT. Trước v2.3.0 nó tự mở lại app
# và phải gõ --no-reopen để nó đừng mở — trái với tên. Đã đảo lại.
# `--no-reopen` vẫn nhận (không báo lỗi) để lệnh cũ trong lịch sử terminal vẫn chạy.
#
# ⚠️ Đợi Claude trả lời xong rồi hãy chạy — script thoát app ngay lập tức.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPAIR="$HERE/repair-missing-sessions.sh"
LOST="$HERE/restore-lost-entries.sh"
DEDUP="$HERE/dedup-entries.sh"
STORE="$HERE/store.sh"
APPNAME="Claude"
WAIT_MAX=40                      # giây chờ tối đa cho app thoát

REOPEN=0; DRY=0
DEEP=0
for a in "$@"; do
  case "$a" in
    --reopen)    REOPEN=1 ;;
    --deep)      DEEP=1 ;;
    --no-reopen) REOPEN=0 ;;   # giữ lại cho tương thích: nay đã là mặc định
    --dry-run)   DRY=1 ;;
    -h|--help) sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Tham số lạ: $a"; exit 2 ;;
  esac
done

[ -x "$REPAIR" ] || { echo "❌ Không thấy $REPAIR"; exit 1; }

# Đếm tiến trình chính. grep -c đọc hết đầu vào + '|| true' — KHÔNG dùng grep -q
# (thoát sớm gây SIGPIPE cho ps, với pipefail sẽ làm điều kiện sai âm thầm).
# KHÔNG dùng pgrep: trên macOS nó không thấy tiến trình chính của Claude Desktop.
# shellcheck disable=SC2009
# CỐ Ý dùng `ps -Ao args`, KHÔNG dùng `pgrep`: đo thực tế trên macOS,
# `pgrep -x Claude` trả về 0 tiến trình trong khi Claude Desktop ĐANG chạy
# (chỉ thấy helper). Nghe theo shellcheck ở đây sẽ làm chốt an toàn
# 'Claude đã tắt chưa' luôn trả lời sai ⇒ lệnh ghi chạy khi app đang mở.
running() { ps -Ao args | grep -c "Claude\.app/Contents/MacOS/Claude$" || true; }

if [ "$DRY" -eq 1 ]; then
  echo "🔍 XEM TRƯỚC — không đụng vào Claude, không ghi gì"
  echo "   Claude đang chạy : $([ "$(running)" -gt 0 ] && echo CÓ || echo KHÔNG)"
  echo "   Sẽ làm:"
  echo "     1. osascript -e 'quit app \"$APPNAME\"'"
  echo "     2. đợi tối đa ${WAIT_MAX}s cho tiến trình kết thúc"
  echo "     3. $STORE save   (ghi mot ban vao kho git — diem lui)"
  echo "     4. kiểm tra chỉ đọc (repair / restore-lost-entries / fix-stale)"
  [ "$REOPEN" -eq 1 ] && echo "     5. open -a $APPNAME" || echo "     5. KHÔNG mở lại (thêm --reopen nếu muốn)"
  echo "
     ⚠️  RỒI, TRƯỚC KHI MỞ LẠI: claude-history fix --apply  (BẮT BUỘC)"
  exit 0
fi

# ── 1. Thoát êm ─────────────────────────────────────────────────────────────
if [ "$(running)" -gt 0 ]; then
  echo "→ [1/5] Thoát Claude Desktop..."
  osascript -e "quit app \"$APPNAME\"" 2>/dev/null || true
else
  echo "→ [1/5] Claude Desktop không chạy sẵn — bỏ qua."
fi

# ── 2. Đợi thật sự kết thúc ─────────────────────────────────────────────────
echo "→ [2/5] Đợi tiến trình kết thúc..."
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

# ── 3. Ghi một bản vào KHO GIT ──────────────────────────────────────────────
# Đặt TRƯỚC phần kiểm tra: nếu sau đó bạn quyết định chạy lệnh sửa, đã có sẵn
# một điểm lùi đúng bằng trạng thái ngay lúc này.
#
# v3.0.0 đổi từ snapshot.sh (rsync --link-dest) sang store.sh (git). Lý do:
# hardlink chỉ giúp với file KHÔNG ĐỔI, mà Claude ghi thêm liên tục ⇒ chép lại
# nguyên file mỗi lần ⇒ kho cũ phình ~1 GB/lần. Quan trọng hơn: kho git bao gồm
# CẢ CHỈ MỤC Recents, nên mọi lệnh sửa chạy sau đây đều `git revert` được.
if [ -x "$STORE" ]; then
  echo "→ [3/5] Ghi một bản vào kho git..."
  if "$STORE" save >/dev/null 2>&1; then
    echo "   ✅ xong — có điểm lùi đúng bằng trạng thái lúc này"
  else
    # KHÔNG được im lặng bỏ qua: không có điểm lùi thì mọi lệnh sửa bên dưới
    # trở thành thao tác một chiều.
    echo "   ⛔ GHI KHO THẤT BẠI — chưa có điểm lùi." >&2
    echo "      ĐỪNG chạy lệnh sửa nào cho tới khi xử lý xong." >&2
    echo "      Xem chi tiết: $STORE save" >&2
  fi
else
  echo "→ [3/5] Không thấy $STORE — bỏ qua (KHÔNG có điểm lùi)."
fi

# ── 4. Kiểm tra CHỈ ĐỌC ─────────────────────────────────────────────────────
echo "→ [4/5] Kiểm tra (chỉ đọc, không ghi gì)..."

MISSING="$("$REPAIR" 2>/dev/null | sed -n 's/^Sẽ đưa lại \([0-9]*\) hội thoại.*/\1/p')"
[ -n "${MISSING:-}" ] || MISSING=0
LOSTN=0
if [ -x "$LOST" ]; then
  LOSTN="$("$LOST" 2>/dev/null | sed -n 's/^Sẽ tạo \([0-9]*\) mục.*/\1/p')"
  [ -n "${LOSTN:-}" ] || LOSTN=0
fi
STALEN="$("$REPAIR" --fix-stale 2>/dev/null | grep -c '^\[[0-9]' || true)"
DUPN=0
if [ -x "$DEDUP" ]; then
  DUPN="$("$DEDUP" 2>/dev/null | sed -n 's/^Dọn \([0-9]*\) mục.*/\1/p')"
  [ -n "${DUPN:-}" ] || DUPN=0
fi

echo
if [ "$MISSING" = "0" ] && [ "$LOSTN" = "0" ] && [ "$DUPN" = "0" ]; then
  echo "   ✅ Danh sách đủ và sạch. Mỗi hội thoại đúng một mục."
else
  [ "$LOSTN" = "0" ] || {
    echo "   ⚠️  $LOSTN hội thoại KHÔNG CÒN MỤC NÀO trong danh sách."
    echo "       Xem trước :  $LOST"
    echo "       Khôi phục :  $LOST --apply"
  }
  [ "$DUPN" = "0" ] || {
    echo "   ⚠️  $DUPN mục TRÙNG hoàn toàn (nhiều mục cùng trỏ vào một hội thoại)."
    echo "       Xem trước :  $DEDUP"
    echo "       Dọn       :  $DEDUP --apply     (không ẩn nội dung nào)"
  }
  [ "$MISSING" = "0" ] || {
    echo "   ⚠️  $MISSING phiên mồ côi có thể đưa lại vào danh sách."
    echo "       Xem trước :  $REPAIR"
    echo "       Khôi phục :  $REPAIR --apply"
  }
fi
# ── Chiều thứ 5: NỘI DUNG bên trong hội thoại (nhánh chưa gộp) ──────────────
# Bốn phép trên chỉ nói về DANH SÁCH. Một hội thoại có thể đủ mục mà vẫn thiếu
# nội dung vì bị nén ngữ cảnh tách thành nhiều nhánh, mục chỉ mở được một nhánh.
# Phép này quét toàn bộ transcript (~30 giây) nên chỉ chạy khi có --deep.
# ── LUÔN kiểm nội dung, KHÔNG còn đợi --deep ────────────────────────────────
# SỰ CỐ 27/08/2026: người dùng hỏi ba lần "khởi động lại có mất dữ liệu không?".
# Bốn phép trên chỉ soi DANH SÁCH nên đều báo sạch, và câu trả lời đưa ra là
# "không sao". Mở lại thì hội thoại đang làm việc THIẾU 2 giờ 16 phút nội dung.
# Nguyên nhân: nén ngữ cảnh sinh nhánh mới liên tục (ca1a7b91 → … → fed858e2),
# app theo dõi nhánh hiện tại trong BỘ NHỚ chứ không cập nhật mục Recents; thoát
# xong thì mục vẫn trỏ nhánh cũ nhất.
# Phép này tốn ~40 giây. Đúng bằng thứ lẽ ra phải cảnh báo. Không đánh đổi nữa.
# --deep giữ lại cho tương thích ngược; kiểm nội dung NAY LÀ MẶC ĐỊNH nên cờ này
# không còn điều khiển gì. Tham chiếu một lần cho rõ ý đồ.
: "${DEEP:-0}"
MERGE="$HERE/merge-branches.sh"
if [ -x "$MERGE" ]; then
  MERGEN="$("$MERGE" --list 2>/dev/null | sed -n 's/^🧩 Chuỗi cần HỢP NHẤT: \([0-9]*\).*/\1/p')"
  [ -n "${MERGEN:-}" ] || MERGEN=0
  if [ "$MERGEN" != "0" ]; then
    echo
    echo "   ℹ️  $MERGEN hội thoại có nhánh CHƯA GỘP — mục chỉ mở được một phần nội dung."
    echo "       Xem trước :  $MERGE --list"
    echo "       Gộp 1 mục :  $MERGE --id <8-ký-tự> --apply"
  fi
fi

if [ "${STALEN:-0}" != "0" ]; then
  echo
  echo "   ℹ️  $STALEN mục đang mở bản cũ hơn bản mới nhất."
  echo "       ĐỪNG sửa nếu không thấy thiếu thật. Xem trước: $REPAIR --fix-stale"
  echo "       Mục gắn 🔴 đổi sẽ MẤT nội dung — chỉ đổi khi bạn thật sự cần."
fi

# ── NHẮC BẮT BUỘC: việc phải làm SAU khi mở lại ────────────────────────────
# Đây là bước bị bỏ sót ngày 27/08/2026 và là nguyên nhân trực tiếp của sự cố.
# In VÔ ĐIỀU KIỆN — kể cả khi mọi phép kiểm đều sạch — vì nhánh mới sinh ra
# trong lúc app còn chạy thì không phép kiểm nào lúc này thấy được.
echo
echo "══════════════════════════════════════════════════════════════"
echo "⚠️  CHẠY NGAY BÂY GIỜ — TRƯỚC khi mở lại Claude:"
echo
echo "      claude-history fix --apply"
echo
echo "   VÌ SAO: hội thoại bạn vừa làm việc gần như chắc chắn sẽ hiện"
echo "   THIẾU nội dung. Nén ngữ cảnh sinh nhánh mới liên tục, nhưng mục"
echo "   Recents vẫn trỏ nhánh cũ. Dữ liệu KHÔNG mất — chỉ mất lối vào."
echo "   Lệnh trên gộp các nhánh và trỏ mục về bản đủ nhất."
echo
echo "   ⚠️ PHẢI chạy LÚC APP ĐANG ĐÓNG — mở Claude lên rồi thì lệnh này"
echo "      bị CHẶN. Thứ tự đúng:  quit → fix --apply → open -a Claude"
echo
echo "   Xong rồi mới mở, và kiểm tin nhắn cuối cùng có mặt chưa."
echo "══════════════════════════════════════════════════════════════"

# ── 5. Mở lại ───────────────────────────────────────────────────────────────
echo
if [ "$REOPEN" -eq 1 ]; then
  echo "→ [5/5] Mở lại Claude Desktop..."
  open -a "$APPNAME"
else
  echo "→ [5/5] Không mở lại. Muốn mở lại luôn thì thêm --reopen."
fi
