#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
#  ⚠️  ĐÃ CÓ BẢN THAY THẾ TỐT HƠN TỪ v3.0.0:  claude-history save
#
#  Script này dùng rsync --link-dest. Hardlink chỉ giúp với file KHÔNG ĐỔI, mà
#  Claude ghi thêm vào transcript liên tục => chép lại NGUYÊN file mỗi lần.
#  Đo thật: kho snapshot phình 3,0 → 5,6 GB, tổng 7,5 GB cho 10 bản.
#  Ghi thêm 1,5 MB vào 3 transcript: rsync tốn 64.440 KB · git tốn 0 KB.
#
#  Vẫn chạy được (chưa gỡ) nhưng đừng dùng cho việc mới.
# ─────────────────────────────────────────────────────────────────────────────
echo "⚠️  Script này đã có bản thay thế: claude-history save  (kho git, nhẹ hơn nhiều)" >&2
echo "   Vẫn chạy tiếp sau 3 giây. Ctrl+C để dừng." >&2
sleep 3
# Ảnh chụp (snapshot) toàn bộ lịch sử hội thoại Claude — chạy hằng ngày qua launchd.
#
# CHỈ ĐỌC nguồn, chỉ ghi vào thư mục backup. Không đụng gì tới Claude.
# An toàn khi Claude đang mở: transcript là JSONL ghi nối đuôi, bản chụp
# dở dang vẫn đọc được và lần chụp sau sẽ hoàn thiện.
#
# Dùng hardlink (--link-dest): file không đổi giữa 2 lần chụp KHÔNG tốn thêm đĩa.
# Viết cho bash 3.2 (bản mặc định của macOS) — không dùng mapfile/associative array.
#
# Chạy tay   : ~/DATA/claude-backups/snapshot.sh
# Xem nhật ký: tail -f ~/DATA/claude-backups/snapshot.log
# Gỡ tự động : launchctl bootout gui/$UID/com.hieund.claude-backup
#              rm ~/Library/LaunchAgents/com.hieund.claude-backup.plist

set -uo pipefail

DEST="$HOME/DATA/claude-backups"
KEEP=14                       # giữ 14 bản chụp gần nhất
STAMP="$(date +%Y%m%d-%H%M%S)"
NEW="$DEST/snap-$STAMP"
LATEST="$DEST/latest"
LOG="$DEST/snapshot.log"

mkdir -p "$DEST"
exec >>"$LOG" 2>&1
echo "───── $(date '+%Y-%m-%d %H:%M:%S') bắt đầu ─────"

# Đĩa còn dưới 10 GB thì bỏ qua, tránh làm đầy ổ
AVAIL_KB="$(df -k "$DEST" | awk 'NR==2 {print $4}')"
if [ "${AVAIL_KB:-0}" -lt 10485760 ]; then
  echo "⚠️  Còn dưới 10 GB trống — bỏ qua lần chụp này."
  exit 1
fi

# Chụp một thư mục nguồn vào $NEW/<sub>, hardlink từ bản chụp trước nếu có
snap_dir() {
  src="$1"; sub="$2"
  if [ ! -e "$src" ]; then
    echo "  (bỏ qua, không tồn tại: $src)"
    return 0
  fi
  mkdir -p "$NEW/$sub"
  prev=""
  if [ -d "$LATEST/$sub" ]; then
    prev="$(cd "$LATEST/$sub" && pwd -P)"
  fi
  # -a giữ thuộc tính; -L bám theo symlink (thư mục chỉ mục là symlink hợp nhất của kit)
  if [ -n "$prev" ]; then
    rsync -aL --exclude '.DS_Store' --link-dest="$prev" "$src/" "$NEW/$sub/"
  else
    rsync -aL --exclude '.DS_Store' "$src/" "$NEW/$sub/"
  fi
  echo "  ✔ $sub  →  $(du -sh "$NEW/$sub" 2>/dev/null | cut -f1)"
}

snap_dir "$HOME/.claude/projects"                                               "projects"
snap_dir "$HOME/Library/Application Support/Claude/claude-code-sessions-shared" "sessions-index"
# Thứ bạn TỰ TẠO, mất là phải làm lại từ đầu. Nhỏ, hardlink nên gần như miễn phí.
snap_dir "$HOME/.claude/skills"                                                 "skills"
snap_dir "$HOME/.claude/plugins"                                                "plugins"
# KHÔNG chép: cache/ telemetry/ statsig/ shell-snapshots/ — tự sinh lại được, chỉ tốn chỗ.

# Các file cấu hình nhỏ
mkdir -p "$NEW/config"
for f in "$HOME/.claude/settings.json" \
         "$HOME/.claude.json" \
         "$HOME/.claude/history.jsonl" \
         "$HOME/Library/Application Support/Claude/claude_desktop_config.json"; do
  [ -f "$f" ] && cp -p "$f" "$NEW/config/$(basename "$f")" 2>/dev/null
done

# BẢO MẬT: transcript chứa nguyên văn hội thoại — gồm cả nội dung file Claude đã đọc
# và output lệnh, nên có thể lẫn API key / token. Khoá thư mục backup về chỉ mình đọc.
chmod 700 "$DEST" 2>/dev/null || true
chmod -R go-rwx "$NEW" 2>/dev/null || true

NTR="$(find "$NEW/projects" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
NIX="$(find "$NEW/sessions-index" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' ')"
{
  echo "snapshot   : $STAMP"
  echo "transcript : $NTR file"
  echo "chỉ mục    : $NIX mục"
  echo "dung lượng : $(du -sh "$NEW" 2>/dev/null | cut -f1)  (phần TĂNG THÊM nhỏ hơn nhiều nhờ hardlink)"
} > "$NEW/MANIFEST.txt"
cat "$NEW/MANIFEST.txt"

ln -sfn "snap-$STAMP" "$LATEST"

# Dọn bản cũ, giữ $KEEP bản gần nhất.
# bash 3.2: không dùng mapfile. Và KHÔNG dùng `head`/`grep -q` giữa pipeline —
# lệnh thoát sớm gây SIGPIPE cho lệnh trước, với `pipefail` sẽ thành lỗi âm thầm.
# Ghi ra file tạm rồi đọc bằng redirect: không pipeline, không lệnh thoát sớm.
TMPLIST="$(mktemp)"
find "$DEST" -maxdepth 1 -type d -name 'snap-*' 2>/dev/null | sort > "$TMPLIST"
COUNT="$(wc -l < "$TMPLIST" | tr -d ' ')"
if [ "${COUNT:-0}" -gt "$KEEP" ]; then
  DROP=$((COUNT - KEEP))
  i=0
  while IFS= read -r o; do
    i=$((i + 1))
    [ "$i" -le "$DROP" ] || continue
    if [ -n "$o" ] && [ -d "$o" ]; then
      rm -rf "$o"
      echo "  🗑  dọn bản cũ: $(basename "$o")"
    fi
  done < "$TMPLIST"
fi
rm -f "$TMPLIST"

echo "✅ xong → $NEW"
echo "   tổng dung lượng backup: $(du -sh "$DEST" 2>/dev/null | cut -f1)"
