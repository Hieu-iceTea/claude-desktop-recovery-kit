#!/usr/bin/env bash
# =============================================================================
# store.sh   (v3.0.0)  — kho git thay cho snapshot hardlink
#
#   store.sh save      Ghi một bản mới vào kho (chạy được khi Claude đang mở)
#   store.sh verify    Kiểm tra toàn vẹn + so từng byte với bản sống
#   store.sh log       Lịch sử các bản đã lưu
#   store.sh compact   Nén sâu (~8 phút, ăn CPU) — chạy lúc máy rảnh
#   store.sh list <bản>                     Liệt kê file trong một bản
#   store.sh show <bản> <đường-dẫn>         In nội dung một file từ một bản
#   store.sh restore <bản> <đường-dẫn> [đích]   Lấy file ra (KHÔNG ghi đè)
#
# VÌ SAO GIT thay vì rsync --link-dest:
#   rsync chỉ liên kết cứng file KHÔNG ĐỔI. Claude ghi thêm vào transcript liên
#   tục ⇒ file đổi ⇒ chép lại NGUYÊN file. Đo thực tế trên máy này:
#     kho snapshot phình 3,0 → 5,6 GB, tổng 7,5 GB cho 10 bản
#     ghi thêm 1,5 MB vào 3 transcript: rsync tốn 64.440 KB · git tốn 0 KB
#
# AN TOÀN — hai chốt:
#   1) Kho nằm NGOÀI thư mục dữ liệu (--git-dir riêng, --work-tree trỏ vào).
#      ⇒ KHÔNG một file lạ nào sinh ra trong ~/.claude hay thư mục Claude Desktop.
#   2) `save`/`verify`/`log` chỉ ĐỌC dữ liệu sống. Chỉ `restore` mới ghi, và mặc
#      định ghi ra file .restored-<TS> bên cạnh, KHÔNG ghi đè bản sống.
#
# GIỚI HẠN đã biết:
#   - Kho nằm CÙNG Ổ với bản gốc ⇒ chống xoá nhầm, KHÔNG chống hỏng ổ.
#   - Commit đúng lúc Claude đang ghi có thể bắt được nửa dòng cuối (torn read).
#     Vô hại: bản sống không bị đụng tới, lần `save` sau tự đúng lại.
#   - Kho chứa nguyên văn hội thoại, có thể lẫn API key ⇒ chmod 700, đừng đẩy lên cloud.
#
# QUY ƯỚC: mọi định danh (biến, hàm, lệnh con) bằng TIẾNG ANH theo chuẩn kỹ
#          thuật; mọi thứ HIỂN THỊ cho người đọc bằng TIẾNG VIỆT CÓ DẤU.
# =============================================================================
set -uo pipefail

STORE="$HOME/DATA/claude-store"
TR_DIR="$HOME/.claude"
IX_DIR="$HOME/Library/Application Support/Claude"
TR_GIT="$STORE/transcripts.git"
IX_GIT="$STORE/index.git"

tr_g() { git --git-dir="$TR_GIT" --work-tree="$TR_DIR" "$@"; }
ix_g() { git --git-dir="$IX_GIT" --work-tree="$IX_DIR" "$@"; }

for dir in "$TR_GIT" "$IX_GIT"; do
  [ -d "$dir" ] || { echo "⛔ Chưa có kho: $dir" >&2; echo "   Xem CHANGELOG v3.0.0, mục 'kho git'." >&2; exit 1; }
done

# ── Chốt chống chạy chồng lên nhau ──────────────────────────────────────────
# git tự khoá bằng index.lock nhưng báo lỗi thô, người dùng không hiểu.
# Bắt trước và nói rõ.
for dir in "$TR_GIT" "$IX_GIT"; do
  if [ -e "$dir/index.lock" ]; then
    echo "⛔ Kho đang được một tiến trình khác dùng: $dir/index.lock" >&2
    echo "   Đợi lệnh kia xong rồi chạy lại." >&2
    echo "   Nếu chắc chắn không có lệnh nào chạy: rm '$dir/index.lock'" >&2
    exit 1
  fi
done

CMD="${1:-help}"; shift 2>/dev/null || true

case "$CMD" in

save)
  echo "💾 Ghi một bản mới vào kho"
  echo "   Chỉ ĐỌC dữ liệu sống — chạy được khi Claude đang mở."
  echo
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  failed=0
  for pair in "transcript:tr_g" "chỉ mục:ix_g"; do
    label="${pair%%:*}"; fn="${pair##*:}"
    printf "   %-10s " "$label"
    # Mọi bước git đều phải được kiểm. Bản đầu viết
    #   "$fn" commit -qm ... && echo "đã ghi"
    # ⇒ commit thất bại thì in ra DÒNG TRỐNG, exit=0, hỏng im lặng.
    # Đã tái hiện được: ổ đầy hoặc mất quyền ghi sẽ báo "thành công".
    if ! "$fn" add -A 2>/dev/null; then
      echo "⛔ THẤT BẠI ở bước 'add' — kiểm tra quyền ghi và dung lượng ổ"; failed=1; continue
    fi
    if "$fn" diff --cached --quiet 2>/dev/null; then
      echo "không đổi"; continue
    fi
    changed="$("$fn" diff --cached --name-only | wc -l | tr -d ' ')"
    if "$fn" commit -qm "save $timestamp" >/dev/null 2>&1; then
      echo "đã ghi ($changed file đổi)"
    else
      echo "⛔ THẤT BẠI ở bước 'commit' — KHÔNG có bản mới nào được lưu"; failed=1
    fi
  done
  echo
  echo "   Kho: $(du -sh "$STORE" 2>/dev/null | cut -f1)"
  if [ "$failed" -ne 0 ]; then
    echo
    echo "⛔ CÓ KHO GHI THẤT BẠI — đừng coi như đã sao lưu xong." >&2
    exit 1
  fi
  echo "   Xem lại: store.sh log"
  ;;

verify)
  echo "🔎 Kiểm tra toàn vẹn kho"
  echo
  failed=0
  for pair in "transcript:tr_g:$TR_DIR" "chỉ mục:ix_g:$IX_DIR"; do
    label="$(echo "$pair" | cut -d: -f1)"; fn="$(echo "$pair" | cut -d: -f2)"; root="$(echo "$pair" | cut -d: -f3-)"
    echo "── $label ──"
    if "$fn" fsck --no-progress >/dev/null 2>&1; then echo "   ✅ fsck sạch"; else echo "   ⛔ fsck BÁO LỖI"; failed=1; fi
    same=0; differ=0; gone=0
    # So từng byte 20 file ngẫu nhiên với bản sống.
    # `shuf` KHÔNG có sẵn trên macOS — bản đầu dùng nó, lệnh thất bại âm thầm,
    # mẫu rỗng, và verify báo "đạt" trong khi không kiểm gì. Dùng `sort -R`
    # (BSD có) và BẮT BUỘC mẫu không được rỗng (chốt ngay bên dưới).
    sample="$("$fn" ls-tree -r --name-only HEAD 2>/dev/null | sort -R | head -20)"
    if [ -z "$sample" ]; then
      echo "   ⛔ KHÔNG lấy được mẫu để đối chiếu — coi như TRƯỢT, không coi là đạt."
      failed=1
      continue
    fi
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if [ ! -f "$root/$path" ]; then gone=$((gone+1)); continue; fi
      in_store="$("$fn" show "HEAD:$path" 2>/dev/null | shasum | cut -d' ' -f1)"
      on_disk="$(shasum "$root/$path" 2>/dev/null | cut -d' ' -f1)"
      if [ "$in_store" = "$on_disk" ]; then same=$((same+1)); else differ=$((differ+1)); echo "   ⚠️  khác bản sống: $path"; fi
    done <<< "$sample"
    echo "   Đã đối chiếu $((same+differ+gone))/20 file"
    echo "   Giống bản sống: $same · khác: $differ · đã đổi tên hoặc xoá: $gone"
    # "khác" KHÔNG phải lỗi: Claude ghi thêm sau lần save gần nhất.
    if [ "$differ" -gt 0 ]; then
      echo "      (khác = đã ghi thêm sau lần save cuối — chạy 'store.sh save')"
    fi
  done
  echo
  # if/then/else, KHÔNG dùng `A && B || C`: nếu `echo` thất bại (stdout đóng)
  # thì nhánh || sẽ chạy và báo kho hỏng trong khi kho tốt.
  if [ "$failed" -eq 0 ]; then
    echo "✅ Kho toàn vẹn."
  else
    echo "⛔ Kho có vấn đề — DỪNG dùng, báo lại." >&2
    exit 1
  fi
  ;;

compact)
  # Git tự dọn định kỳ (gc.auto mặc định). Lệnh này chạy bản NÉN SÂU, tốn CPU
  # nhiều phút — để người dùng chọn lúc máy rảnh, không bao giờ tự chạy.
  echo "🗜  Nén sâu cả hai kho (ăn CPU, đo thực tế ~8 phút cho 5,7 GB)"
  echo "   Trước: $(du -sh "$STORE" | cut -f1)"
  failed=0
  tr_g gc --aggressive --prune=now || failed=1
  ix_g gc --aggressive --prune=now || failed=1
  echo "   Sau  : $(du -sh "$STORE" | cut -f1)"
  [ "$failed" -eq 0 ] || { echo "⛔ Nén thất bại." >&2; exit 1; }
  echo "✅ Xong."
  ;;

log)
  echo "── transcript ──"; tr_g log --oneline --date=short --pretty='  %h  %ad  %s' -15
  echo; echo "── chỉ mục ──";  ix_g log --oneline --date=short --pretty='  %h  %ad  %s' -15
  ;;

list)
  commit="${1:?cần mã bản — xem: store.sh log}"
  tr_g ls-tree -r --name-only "$commit" 2>/dev/null || ix_g ls-tree -r --name-only "$commit"
  ;;

show)
  commit="${1:?cần mã bản}"; path="${2:?cần đường dẫn}"
  tr_g show "$commit:$path" 2>/dev/null || ix_g show "$commit:$path"
  ;;

restore)
  commit="${1:?cần mã bản}"; path="${2:?cần đường dẫn}"; dest="${3:-}"
  [ -n "$dest" ] || dest="./$(basename "$path").restored-$(date +%Y%m%d-%H%M%S)"
  [ -e "$dest" ] && { echo "⛔ Đã có $dest — chọn tên đích khác." >&2; exit 1; }
  if tr_g show "$commit:$path" > "$dest" 2>/dev/null || ix_g show "$commit:$path" > "$dest" 2>/dev/null; then
    echo "✅ Đã lấy ra: $dest  ($(du -h "$dest" | cut -f1))"
    echo "   KHÔNG ghi đè bản sống. Muốn thay thế thì tự 'cp' sau khi đối chiếu."
  else
    rm -f "$dest"; echo "⛔ Không thấy '$path' trong bản '$commit'" >&2; exit 1
  fi
  ;;

*)
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  ;;
esac
