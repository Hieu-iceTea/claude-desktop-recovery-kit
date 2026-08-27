#!/usr/bin/env bash
# =============================================================================
# fix-all.sh  (v3.3.0) — khôi phục TẤT CẢ trong một lệnh
#
# Người dùng gần như luôn muốn "sửa hết", không sửa lẻ từng mục. Trước bản này
# phải nhớ và chạy tay 5 lệnh theo đúng thứ tự — dễ bỏ sót một bước (đã xảy ra:
# 26/08/2026 bỏ sót bước trỏ mục sau khi hợp nhất).
#
# HAI CHIỀU, sửa theo ĐÚNG THỨ TỰ:
#   ① DANH SÁCH  — hội thoại có mặt trong Recents hay không
#        restore-lost-entries  (mất hẳn)  → repair-missing  (mồ côi)  → dedup  (trùng)
#   ② NỘI DUNG   — mở ra có đủ tin nhắn không
#        merge-branches --apply --point cho từng chuỗi còn thiếu
#
# VÌ SAO DANH SÁCH TRƯỚC: `merge --point` cần một mục Recents để trỏ vào. Hội
# thoại chưa có mục thì không trỏ được — phải tạo mục trước.
#
# CHẠY LẠI ĐƯỢC (idempotent): việc nào đã xong thì lần sau tự bỏ qua, vì mọi
# phép đo đều so nội dung thực tế chứ không dựa vào cờ đã-chạy-hay-chưa.
#
# AN TOÀN: mặc định XEM TRƯỚC. `--apply` đòi Claude Desktop đã tắt. Một chuỗi
# hỏng KHÔNG làm dừng cả lượt — báo lỗi rồi đi tiếp, cuối cùng tổng kết.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOST="$HERE/restore-lost-entries.sh"
REPAIR="$HERE/repair-missing-sessions.sh"
DEDUP="$HERE/dedup-entries.sh"
MERGE="$HERE/merge-branches.sh"
VERIFY="$HERE/verify-entries.sh"
ACTIVITY="$HERE/fix-activity.sh"
STORE="$HERE/store.sh"

# ── ĐỒNG HỒ ─────────────────────────────────────────────────────────────────
# CHỈ ĐO, KHÔNG ĐOÁN. Bản v3.0.0 có in một dòng "ước tính ~N phút" tính theo
# `số_chuỗi × 31 giây`; đo lại ngày 26/08/2026 nó báo 23 phút cho lượt chạy
# thật 2 giờ 20 phút — sai 6 lần. Sai vì chi phí đi theo SỐ BYTE phải đọc chứ
# không theo số chuỗi. Dòng đó đã bị XOÁ chứ không sửa: một con số sai còn tệ
# hơn không có số nào, và giá trị duy nhất của bộ công cụ này là các con số của
# nó nói thật.
T0=$SECONDS
hms() {  # 3725 → "1g 02m 05s"
  local t=$1
  if   [ "$t" -ge 3600 ]; then printf "%dg %02dm %02ds" $((t/3600)) $(((t%3600)/60)) $((t%60))
  elif [ "$t" -ge 60   ]; then printf "%dm %02ds" $((t/60)) $((t%60))
  else                         printf "%ds" "$t"
  fi
}

# v3.3.0 — ĐÃ BỎ `PREFILTER_MB`. Nó lọc theo MB nguồn, mà MB KHÔNG tương quan
# với thứ quyết định điều gì cả. Đo thật 27/08/2026:
#     58dfea02   6,6 MB  →  ctx đỉnh 919.666
#     12345a85    61 MB  →  ctx đỉnh 847.935
# File nhỏ hơn 9 lần lại tốn ctx nhiều hơn. Từ v3.3.0 bước ② chỉ TRỎ nên không
# dựng file, không có gì để lọc trước.

APPLY=0; SCOPE=both
for a in "$@"; do
  case "$a" in
    --apply)        APPLY=1 ;;
    --dry-run)      APPLY=0 ;;
    --list-only)    SCOPE=list
      # SỰ CỐ 27/08/2026: cờ này được dùng vì tưởng "an toàn hơn". Nó đặt
      # SCOPE=list ⇒ BỎ TOÀN BỘ khối ② — đúng khối trỏ mục về nhánh đầy đủ.
      # Người dùng chạy xong vẫn thiếu nội dung, phải chạy lại `fix --apply`.
      echo "⚠️  --list-only KHÔNG sửa lỗi thiếu tin nhắn mới nhất." >&2
      echo "    Nó chỉ dọn danh sách. Sau khi thoát/mở lại Claude, dùng:" >&2
      echo "        claude-history fix --apply" >&2
      echo >&2
      ;;
    --content-only) SCOPE=content ;;
    -h|--help)
      cat <<'EOF'
claude-history fix — khôi phục TẤT CẢ (danh sách + nội dung)

  claude-history fix                 Xem trước, không ghi gì
  claude-history fix --apply         Sửa tất cả (cần thoát Claude trước)

  --list-only      Chỉ sửa DANH SÁCH  (hội thoại mất khỏi Recents)
  --content-only   Chỉ sửa NỘI DUNG   (mở ra thiếu tin nhắn)

Sửa lẻ từng việc:
  claude-history fix lost | orphan | dup | stale

Hội thoại quá lớn sẽ bị bỏ qua — gộp tay theo giai đoạn, mỗi giai đoạn một tên:
  claude-history merge --id <mã> --apply --point \\
      --since 2026-07-01 --until 2026-07-31 --title-suffix "(07/2026)"
EOF
      exit 0 ;;
    *) echo "⛔ Tham số lạ: $a" >&2; exit 2 ;;
  esac
done

# CỐ Ý dùng `ps -Ao args`, KHÔNG dùng `pgrep`: đo thực tế trên macOS,
# `pgrep -x Claude` trả về 0 tiến trình trong khi Claude Desktop ĐANG chạy.
# shellcheck disable=SC2009
running() { ps -Ao args | grep -c "Claude\.app/Contents/MacOS/Claude$" || true; }

if [ "$APPLY" = 1 ] && [ "$(running)" -gt 0 ]; then
  echo "⛔ Claude Desktop đang chạy — không thể sửa." >&2
  echo "   Thoát trước:  claude-history quit" >&2
  exit 1
fi

if [ "$APPLY" = 1 ]; then
  echo "🔧 KHÔI PHỤC TẤT CẢ — 🟢 THỰC THI"
  # ── ĐIỂM LÙI TRƯỚC KHI SỬA ────────────────────────────────────────────────
  # Bắt buộc, không phải tuỳ chọn. Lệnh này ghi hàng chục file; không có điểm
  # lùi thì cả lượt thành thao tác một chiều.
  # Đặt Ở ĐÂY chứ không chỉ trong `quit`, để `fix --apply` TỰ ĐỦ — người dùng
  # thoát app bằng Cmd+Q rồi chạy thẳng lệnh này vẫn được bảo vệ.
  # `save` hỏng thường nghĩa là ổ đầy hoặc mất quyền ghi — đúng lúc KHÔNG nên
  # chạy một loạt thao tác ghi. Nên: DỪNG, không cảnh báo rồi đi tiếp.
  if [ -x "$STORE" ]; then
    printf "💾 Lưu điểm lùi trước khi sửa... "
    if "$STORE" save >/dev/null 2>&1; then
      echo "✅"
    else
      echo "⛔"
      echo "   Không lưu được điểm lùi — DỪNG, chưa sửa gì." >&2
      echo "   Xem lỗi:  claude-history save" >&2
      exit 1
    fi
  else
    echo "⛔ Không thấy store.sh — không có điểm lùi, DỪNG." >&2
    exit 1
  fi
else
  echo "🔧 KHÔI PHỤC TẤT CẢ — 🔍 XEM TRƯỚC, chưa ghi gì"
fi
echo

fails=0

# ── ① DANH SÁCH ─────────────────────────────────────────────────────────────
if [ "$SCOPE" != content ]; then
  echo "① DANH SÁCH"
  n_lost="$("$LOST"   2>/dev/null | sed -n 's/^Sẽ tạo \([0-9]*\) mục.*/\1/p')"
  n_orph="$("$REPAIR" 2>/dev/null | sed -n 's/^Sẽ đưa lại \([0-9]*\) hội thoại.*/\1/p')"
  n_dup="$( "$DEDUP"  2>/dev/null | sed -n 's/^Dọn \([0-9]*\) mục.*/\1/p')"
  for v in n_lost n_orph n_dup; do eval "[ -n \"\${$v:-}\" ] || $v=0"; done
  printf "   mất hẳn khỏi danh sách : %s\n" "$n_lost"
  printf "   phiên chưa có mục      : %s\n" "$n_orph"
  printf "   mục trùng              : %s\n" "$n_dup"
  if [ "$APPLY" = 1 ]; then
    [ "$n_lost" = 0 ] || { "$LOST"   --apply >/dev/null 2>&1 || { echo "   ⛔ lỗi khi tạo mục"; fails=$((fails+1)); }; }
    [ "$n_orph" = 0 ] || { "$REPAIR" --apply >/dev/null 2>&1 || { echo "   ⛔ lỗi khi đưa lại phiên mồ côi"; fails=$((fails+1)); }; }
    [ "$n_dup"  = 0 ] || { "$DEDUP"  --apply >/dev/null 2>&1 || { echo "   ⛔ lỗi khi dọn mục trùng"; fails=$((fails+1)); }; }
    echo "   ✅ xong"
  fi
  echo
fi

# ── ② NỘI DUNG ──────────────────────────────────────────────────────────────
# v3.3.0 — ĐỔI MẶC ĐỊNH TỪ **GỘP** SANG **TRỎ**.
#
# VÌ SAO: đo 27/08/2026 cho thấy Claude Desktop xử lý hội thoại rất dài bằng
# cách NÉN TẠI CHỖ và giữ đúng MỘT mục Recents:
#     REDANCE-1715 · 715 file trên đĩa · 1 mục trong danh sách
#     compact_boundary: preTokens 924.674 → postTokens 14.801 (giảm 62 lần)
# App KHÔNG tách hội thoại. Việc duy nhất app không tự lo là: sau khi thoát và
# mở lại, mục Recents tụt về nhánh cũ. Chỉ cần TRỎ LẠI là xong.
#
# Trỏ hơn gộp ở mọi mặt đo được:
#     không tạo file · ctx giữ nguyên · tức thì · hoàn tác bằng một lệnh cp
#     nhánh app tự sinh CHƯA BAO GIỜ chết; chỉ bản gộp mới có lần chết (ece09c56)
# Còn gộp thì: đo trên 58dfea02 cho 13.377 đoạn chữ nhưng trần hiển thị 48 MiB
# chỉ cho thấy 550 (4%). Đổi 274 lấy 550 kèm file 554 MB — không đáng.
#
# Muốn gộp thật thì gọi riêng:  claude-history merge --id <mã> --apply --point
if [ "$SCOPE" != list ]; then
  echo "② NỘI DUNG (trỏ mục về nhánh đầy đủ nhất)"
  IDS="$("$MERGE" --ids 2>/dev/null)"
  total="$(printf '%s\n' "$IDS" | grep -c . || true)"
  if [ "${total:-0}" = 0 ]; then
    echo "   ✅ mọi hội thoại đã trỏ đúng nhánh đầy đủ nhất"
  elif [ "$APPLY" = 0 ]; then
    echo "   $total hội thoại có nhánh đầy đủ hơn bản đang mở:"
    # shellcheck disable=SC2034
    while IFS="$(printf '\t')" read -r id title mb nbr; do
      [ -n "$id" ] || continue
      printf "     %s  %s\n" "${id:0:8}" "$title"
      printf "               %s nhánh — sẽ TRỎ sang bản đầy đủ nhất (không tạo file)\n" "$nbr"
    done <<< "$IDS"
    echo "   Xem chi tiết:  claude-history merge --list"
  else
    ok=0; same=0; i=0; merged=0
    # shellcheck disable=SC2034  # cột mb giữ trong định dạng --ids, chế độ TRỎ không dùng
    while IFS="$(printf '\t')" read -r id title mb nbr; do
      [ -n "$id" ] || continue
      i=$((i+1)); t1=$SECONDS
      printf "   [%s/%s] %s\n" "$i" "$total" "$title"
      printf "         %s · %s nhánh  " "${id:0:8}" "$nbr"
      out="$("$MERGE" --id "$id" --repoint --apply 2>&1)"; rc=$?
      el=$(( SECONDS - t1 ))
      if printf '%s' "$out" | grep -q "Đã trỏ mục Recents"; then
        gain="$(printf '%s' "$out" | grep -oE '\([0-9]+ đoạn · [0-9]+ đoạn CHỮ\)' | head -1)"
        printf "✅ trỏ sang %s   ⏱ %s\n" "${gain:-bản đầy đủ hơn}" "$(hms $el)"
        ok=$((ok+1)); merged=1
      elif printf '%s' "$out" | grep -q "không cần đổi"; then
        printf "✅ đã đúng nhánh   ⏱ %s\n" "$(hms $el)"; same=$((same+1))
      elif [ "$rc" = 2 ]; then
        # ── TẦNG ③: không nhánh nào chứa bản ghi mới nhất ⇒ GỘP ─────────────
        # Đây là lúc DUY NHẤT gộp thật sự cần. Yêu cầu của người dùng là không
        # mất tin nhắn vừa nhắn; trỏ không đạt được thì phải gộp, không bỏ qua.
        printf "⚠️  trỏ không đủ → gộp... "
        out2="$("$MERGE" --id "$id" --apply --point 2>&1)"
        el=$(( SECONDS - t1 ))
        if printf '%s' "$out2" | grep -q "Đã trỏ mục Recents"; then
          g2="$(printf '%s' "$out2" | grep -oE 'đoạn CHỮ: [0-9]+ \(trước: [0-9]+\)' | head -1)"
          printf "✅ gộp %s   ⏱ %s\n" "${g2:-xong}" "$(hms $el)"
          ok=$((ok+1)); merged=1
        else
          why="$(printf '%s' "$out2" | grep -oE '⛔ File kết quả [0-9]+ MB.*' | head -1)"
          printf "⛔ gộp không được   ⏱ %s\n" "$(hms $el)"
          [ -z "$why" ] || echo "         ${why}"
          fails=$((fails+1))
        fi
      else
        printf "⛔ lỗi   ⏱ %s\n" "$(hms $el)"; fails=$((fails+1))
      fi
    done <<< "$IDS"
    echo "   ✅ trỏ lại $ok · đã đúng sẵn $same"

    # ── DỌN TRÙNG LẦN HAI ────────────────────────────────────────────────────
    # BẮT BUỘC, không phải cho chắc. Hợp nhất sinh ra bản PHỦ TRÙM bản cũ, nên
    # mục trùng chỉ lộ ra SAU khi gộp — dedup chạy ở bước ① (trước khi gộp)
    # không thể thấy được. Sự cố 26/08/2026: lượt chạy đầu để lại 1 mục mất +
    # 2 mục trùng, người dùng phải chạy `fix --apply` lần thứ hai mới sạch.
    if [ "$merged" = 1 ]; then
      n_dup2="$("$DEDUP" 2>/dev/null | sed -n 's/^Dọn \([0-9]*\) mục.*/\1/p')"
      [ -n "${n_dup2:-}" ] || n_dup2=0
      if [ "$n_dup2" != 0 ]; then
        printf "   🧹 dọn %s mục trùng mới sinh ra sau khi gộp... " "$n_dup2"
        if "$DEDUP" --apply >/dev/null 2>&1; then echo "✅"
        else echo "⛔ lỗi"; fails=$((fails+1)); fi
      fi
    fi
  fi
  echo
fi

# ── Lưu một bản vào kho git để có điểm lùi cho lần sau ──────────────────────
if [ "$APPLY" = 1 ] && [ -x "$STORE" ]; then
  "$STORE" save >/dev/null 2>&1 && echo "💾 Đã lưu bản sau khi sửa vào kho git."
fi

# ── ③ THỨ TỰ DANH SÁCH ──────────────────────────────────────────────────────
# Chế độ hỏng thứ BA, phát hiện 27/08/2026. Mục vẫn tồn tại và vẫn đủ nội dung,
# nhưng `lastActivityAt` lệch so với mốc bản ghi cuối ⇒ tụt đáy Recents ⇒ người
# dùng không tìm ra ⇒ tưởng MẤT hội thoại.
# Ca thật: REDANCE-1715 (fork) ghi 13/08 11:35 trong khi nội dung tới 27/08 18:06
# — lệch 14 ngày, hội thoại 33,2 MB nằm tận đáy danh sách.
# Bước ① và ② không bắt được: chúng đo "có mục" và "đủ nội dung", không đo
# "mục có nổi lên đúng chỗ".
if [ -x "$ACTIVITY" ]; then
  echo "③ THỨ TỰ DANH SÁCH (kéo mục chìm đáy lên)"
  if [ "$APPLY" = 1 ]; then
    if "$ACTIVITY" --apply 2>&1 | sed -n '/lệch/,$p' | sed 's/^/   /'; then :; fi
  else
    "$ACTIVITY" 2>&1 | sed -n '/lệch/,$p' | sed 's/^/   /' || true
  fi
  echo
fi

# ── KIỂM CHỨNG SAU KHI SỬA  ⭐ v3.3.0 ───────────────────────────────────────
# Ba sự cố ngày 27/08/2026 đều có chung một hình dạng: script báo "✅ xong",
# người dùng mở app lên thì THIẾU. Gốc rễ là script chưa bao giờ tự đo lại.
# Từ nay: sửa xong thì ĐO, và nếu còn thiếu thì nói ra ngay tại đây.
if [ "$APPLY" = 1 ] && [ -x "$VERIFY" ]; then
  echo "🔎 Kiểm chứng lại sau khi sửa..."
  if "$VERIFY" >/tmp/.ch-verify.$$ 2>&1; then
    echo "   ✅ mọi hội thoại đều chứa tin nhắn mới nhất"
  else
    sed -n '/⛔/,$p' /tmp/.ch-verify.$$ | head -20
    fails=$((fails+1))
  fi
  rm -f /tmp/.ch-verify.$$
  echo
fi

echo "──────────────────────────────────────────────"
TOTAL=$(( SECONDS - T0 ))
if [ "$APPLY" = 0 ]; then
  echo "Chưa ghi gì. Để sửa:"
  echo "   claude-history quit"
  echo "   claude-history fix --apply"
  echo
  printf "⏱  Xem trước mất %s.\n" "$(hms $TOTAL)"
  exit 0
fi
if [ "$fails" -gt 0 ]; then
  echo "⚠️  Xong, nhưng có $fails việc lỗi — chạy lại 'claude-history fix' để xem còn gì."
  printf "⏱  Tổng thời gian: %s\n" "$(hms $TOTAL)"
  exit 1
fi
echo "✅ Xong. Mở lại Claude:  open -a Claude"
printf "⏱  Tổng thời gian: %s\n" "$(hms $TOTAL)"
