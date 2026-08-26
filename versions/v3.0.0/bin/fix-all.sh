#!/usr/bin/env bash
# =============================================================================
# fix-all.sh  (v3.0.0) — khôi phục TẤT CẢ trong một lệnh
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
STORE="$HERE/store.sh"

APPLY=0; SCOPE=both
for a in "$@"; do
  case "$a" in
    --apply)        APPLY=1 ;;
    --dry-run)      APPLY=0 ;;
    --list-only)    SCOPE=list ;;
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
if [ "$SCOPE" != list ]; then
  echo "② NỘI DUNG (hợp nhất các nhánh bị tách)"
  IDS="$("$MERGE" --ids 2>/dev/null)"
  total="$(printf '%s\n' "$IDS" | grep -c . || true)"
  if [ "${total:-0}" = 0 ]; then
    echo "   ✅ mọi hội thoại đã đủ nội dung"
  elif [ "$APPLY" = 0 ]; then
    echo "   $total hội thoại đang thiếu nội dung."
    echo "   Xem chi tiết:  claude-history merge --list"
    echo "   Ước tính ~$(( total * 31 / 60 + 1 )) phút khi chạy --apply."
  else
    # Mỗi chuỗi ~31 giây (đo thật). Một chuỗi hỏng KHÔNG dừng cả lượt.
    ok=0; skip=0; i=0
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      i=$((i+1))
      printf "   [%2s/%s] %s " "$i" "$total" "${id:0:8}"
      out="$("$MERGE" --id "$id" --apply --point 2>&1)"
      if printf '%s' "$out" | grep -q "Đã trỏ mục Recents"; then
        gain="$(printf '%s' "$out" | grep -oE 'đoạn CHỮ: [0-9]+ \(trước: [0-9]+\)' | head -1)"
        echo "✅ ${gain:-xong}"; ok=$((ok+1))
      elif printf '%s' "$out" | grep -q "QUÁ LỚN\|> ngưỡng"; then
        echo "⏭  bỏ qua — quá lớn, cần gộp theo giai đoạn (--since/--until)"; skip=$((skip+1))
      else
        echo "⛔ lỗi"; fails=$((fails+1))
      fi
    done <<< "$IDS"
    echo "   ✅ hợp nhất $ok · bỏ qua $skip"
  fi
  echo
fi

# ── Lưu một bản vào kho git để có điểm lùi cho lần sau ──────────────────────
if [ "$APPLY" = 1 ] && [ -x "$STORE" ]; then
  "$STORE" save >/dev/null 2>&1 && echo "💾 Đã lưu bản sau khi sửa vào kho git."
fi

echo "──────────────────────────────────────────────"
if [ "$APPLY" = 0 ]; then
  echo "Chưa ghi gì. Để sửa:"
  echo "   claude-history quit"
  echo "   claude-history fix --apply"
  exit 0
fi
if [ "$fails" -gt 0 ]; then
  echo "⚠️  Xong, nhưng có $fails việc lỗi — chạy lại 'claude-history fix' để xem còn gì."
  exit 1
fi
echo "✅ Xong. Mở lại Claude:  open -a Claude"
