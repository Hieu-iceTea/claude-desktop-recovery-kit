#!/usr/bin/env bash
# =============================================================================
# teams.sh  (v3.1.0) — một danh sách hội thoại dùng chung cho MỌI tài khoản/team
#
#   teams.sh            Xem trạng thái từng tài khoản/team (chỉ đọc)
#   teams.sh --apply    Nối các team đang rỗng vào danh sách chung
#
# VẤN ĐỀ: Claude Desktop giữ danh sách Recents ở hai tầng
#     claude-code-sessions-shared/                 ← danh sách THẬT
#     claude-code-sessions/<tài-khoản>/<team>/     ← mỗi tài khoản+team một thư mục
#   Bình thường tầng dưới là SYMLINK trỏ về tầng trên, nên đổi tài khoản hay đổi
#   team đều thấy y nguyên danh sách. Đo trên máy này 27/08/2026: 9/10 thư mục là
#   symlink — và đúng vì thế mà lần đổi tài khoản 21/08 KHÔNG mất gì, dù hội thoại
#   có từ 11/05.
#   Nhưng thỉnh thoảng app tạo một THƯ MỤC THẬT RỖNG cho team mới. Chuyển sang
#   team đó thì Recents trống trơn — trong khi dữ liệu còn nguyên vẹn.
#
# VÌ SAO SYMLINK chứ không CHÉP:
#   ~/.claude/migrate-team-sessions.sh (02/06/2026) chép các mục sang team mới.
#   Chép thì mỗi team một bản: tốn đĩa, và từ đó hai bản PHÂN KỲ — hội thoại mới
#   ở team A không bao giờ hiện ở team B, phải chép lại sau mỗi lần đổi.
#   Symlink là MỘT danh sách duy nhất, 0 byte, không phải chạy lại bao giờ. Đây
#   cũng đúng là cách app tự làm cho 9 thư mục kia.
#
# AN TOÀN — chỉ đụng vào thư mục thật RỖNG:
#   Thư mục thật CÓ mục nghĩa là team đó giữ danh sách riêng. Thay bằng symlink
#   sẽ mất chúng ⇒ script TỪ CHỐI, in ra cách gộp thủ công. Không đoán, không ép.
#
# QUY ƯỚC: định danh bằng TIẾNG ANH; hiển thị bằng TIẾNG VIỆT CÓ DẤU.
# =============================================================================
set -uo pipefail

BASE="$HOME/Library/Application Support/Claude/claude-code-sessions"
SHARED="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STORE="$HERE/store.sh"

APPLY=0
for a in "$@"; do
  case "$a" in
    --apply|--link) APPLY=1 ;;
    --dry-run)      APPLY=0 ;;
    -h|--help)
      cat <<'EOF'
claude-history teams — một danh sách hội thoại cho mọi tài khoản/team

  claude-history teams           Xem trạng thái, không ghi gì
  claude-history teams --apply   Nối các team đang rỗng vào danh sách chung

Khi nào cần: đổi tài khoản hoặc chuyển sang team khác mà Recents trống,
trong khi hội thoại vẫn còn trong ~/.claude/projects.

Chỉ đụng vào thư mục team RỖNG. Team đang giữ danh sách riêng thì script
từ chối và in ra cách gộp thủ công — sẽ không có mục nào bị mất.
EOF
      exit 0 ;;
    *) echo "⛔ Tham số lạ: $a" >&2; exit 2 ;;
  esac
done

[ -d "$SHARED" ] || { echo "⛔ Không thấy danh sách chung: $SHARED" >&2; exit 1; }
if [ ! -d "$BASE" ]; then
  echo "✅ Máy này chưa có thư mục theo tài khoản/team — không có gì phải làm."
  exit 0
fi

# CỐ Ý dùng `ps -Ao args`, KHÔNG dùng `pgrep`: đo thực tế trên macOS,
# `pgrep -x Claude` trả 0 tiến trình trong khi Claude Desktop ĐANG chạy.
# shellcheck disable=SC2009
running() { ps -Ao args | grep -c "Claude\.app/Contents/MacOS/Claude$" || true; }

if [ "$APPLY" = 1 ] && [ "$(running)" -gt 0 ]; then
  echo "⛔ Claude Desktop đang chạy — không thể sửa." >&2
  echo "   Thoát trước:  claude-history quit" >&2
  exit 1
fi

n_shared="$(find "$SHARED" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$APPLY" = 1 ]; then
  echo "🔗 TÀI KHOẢN & TEAM — 🟢 THỰC THI"
else
  echo "🔗 TÀI KHOẢN & TEAM — 🔍 XEM TRƯỚC, chưa ghi gì"
fi
echo "   Danh sách chung: $n_shared mục"
echo

linked=0; empty=0; owns=0; fails=0
todo_empty=()

while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  rel="${dir#"$BASE"/}"
  acct="${rel%%/*}"; team="${rel#*/}"
  label="$(printf '%s…/%s…' "${acct:0:8}" "${team:0:8}")"
  if [ -L "$dir" ]; then
    printf "  ✅ %s  dùng chung danh sách\n" "$label"
    linked=$((linked+1))
  else
    n="$(find "$dir" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$n" -eq 0 ]; then
      printf "  ⚠️  %s  thư mục RIÊNG, đang RỖNG — mở team này sẽ thấy danh sách trống\n" "$label"
      empty=$((empty+1)); todo_empty+=("$dir")
    else
      printf "  🔒 %s  thư mục RIÊNG, có %s mục — KHÔNG đụng tới\n" "$label" "$n"
      owns=$((owns+1))
    fi
  fi
done < <(find "$BASE" -mindepth 2 -maxdepth 2 \( -type d -o -type l \) 2>/dev/null | sort)

echo
printf "  dùng chung: %s · rỗng cần nối: %s · giữ riêng: %s\n" "$linked" "$empty" "$owns"

if [ "$owns" -gt 0 ]; then
  echo
  echo "  🔒 Team giữ danh sách riêng thì script KHÔNG tự động gộp — gộp nhầm là mất mục."
  echo "     Muốn gộp thì chép phần thiếu vào danh sách chung TRƯỚC, rồi chạy lại lệnh này:"
  echo "       cp -n '<thư-mục-team>'/local_*.json '$SHARED'/"
fi

if [ "$empty" -eq 0 ]; then
  echo
  echo "✅ Mọi team đều đã dùng chung một danh sách. Đổi tài khoản hay đổi team không mất gì."
  exit 0
fi

if [ "$APPLY" = 0 ]; then
  echo
  echo "──────────────────────────────────────────────"
  echo "Chưa ghi gì. Để nối $empty team rỗng vào danh sách chung:"
  echo "   claude-history quit"
  echo "   claude-history teams --apply"
  exit 0
fi

# ── ĐIỂM LÙI ────────────────────────────────────────────────────────────────
# Kho git đã theo dõi cả claude-code-sessions/ (gồm chính các symlink này) nên
# một bản save là đủ để lùi lại. `save` hỏng thường nghĩa là ổ đầy hoặc mất
# quyền ghi — đúng lúc KHÔNG nên đi sửa tiếp. Nên: DỪNG.
echo
if [ -x "$STORE" ]; then
  printf "💾 Lưu điểm lùi trước khi sửa... "
  if "$STORE" save >/dev/null 2>&1; then echo "✅"
  else
    echo "⛔"; echo "   Không lưu được điểm lùi — DỪNG, chưa sửa gì." >&2; exit 1
  fi
else
  echo "⛔ Không thấy store.sh — không có điểm lùi, DỪNG." >&2; exit 1
fi

echo
for dir in "${todo_empty[@]}"; do
  rel="${dir#"$BASE"/}"
  printf "   %s  " "$rel"
  # Kiểm lại NGAY TRƯỚC KHI XOÁ: giữa lúc liệt kê và lúc này app có thể đã ghi
  # mục vào đó. rmdir chỉ xoá được thư mục RỖNG ⇒ có mục là nó tự từ chối.
  if ! rmdir "$dir" 2>/dev/null; then
    echo "⛔ không còn rỗng — bỏ qua, không đụng tới"; fails=$((fails+1)); continue
  fi
  if ln -s "$SHARED" "$dir" 2>/dev/null; then
    echo "✅ đã nối vào danh sách chung"
  else
    echo "⛔ tạo symlink thất bại"; fails=$((fails+1))
  fi
done

echo
echo "──────────────────────────────────────────────"
if [ "$fails" -gt 0 ]; then
  echo "⚠️  Có $fails team chưa nối được — chạy lại 'claude-history teams' để xem."
  exit 1
fi
echo "✅ Xong. Mở lại Claude:  open -a Claude"
echo "   Từ giờ mọi tài khoản và team đều đọc CÙNG một danh sách."
