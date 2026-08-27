#!/usr/bin/env bash

# ═══════════════════════════════════════════════════════════════════════════
#  ⛔ NGỪNG DÙNG TỪ v2.3.0 — hãy dùng dedup-entries.sh
#
#  Script này nhận diện "rác" bằng SUY ĐOÁN: enabledMcpTools rỗng + effort=high
#  + trỏ vào transcript nén tiếp nối. Cả ba dấu hiệu đó MỤC DO APP TẠO CŨNG CÓ.
#  Nó MÙ với nội dung — không hề kiểm tra transcript còn đọc được từ đâu không.
#
#  Sự cố 18/08/2026: một lần `--apply` dọn 572 mục, trong đó có mục GỐC do app
#  tạo (titleSource=user) của "Phong thủy hành lang và cửa sân sau" — hội thoại
#  biến mất hoàn toàn khỏi danh sách.
#
#  dedup-entries.sh làm cùng việc nhưng CHỨNG MINH được: chỉ dọn mục nào có nội
#  dung nằm trọn trong các mục được giữ, và in ra chính xác cái giá phải trả.
# ═══════════════════════════════════════════════════════════════════════════
if [ "${1:-}" != "--force-legacy" ]; then
  echo "⛔ clean-junk-entries.sh ĐÃ NGỪNG DÙNG từ v2.3.0."
  echo ""
  echo "   Lý do: nó đoán 'rác' theo dấu hiệu mà mục thật cũng có, và không hề"
  echo "   kiểm tra nội dung. Ngày 18/08/2026 nó đã dọn mất mục gốc của hội thoại"
  echo "   'Phong thủy hành lang và cửa sân sau'."
  echo ""
  echo "   Dùng thay thế:  dedup-entries.sh"
  echo "   (chỉ dọn khi nội dung đã nằm trọn trong mục được giữ — có kiểm chứng)"
  echo ""
  echo "   Thật sự cần bản cũ:  clean-junk-entries.sh --force-legacy"
  exit 2
fi
shift
# =============================================================================
# clean-junk-entries.sh   (v2.2.0)
#
# Dọn các mục Recents RÁC do repair-missing-sessions.sh tạo nhầm.
#
# Sự cố 12/08/2026: một lỗi trong repair khiến mỗi ĐOẠN NÉN của hội thoại dài
# bị tạo thành một mục Recents riêng — một lần --apply đẻ ra 555 mục, trong đó
# 501 mục cùng tên "REDANCE-1715 Mail investigation", mỗi mục chỉ chứa một lát
# cắt nội dung. Lỗi gốc đã vá; script này dọn hậu quả.
#
# Nhận diện RÁC = thoả CẢ BỐN:
#   ① mang dấu vết do repair ghi (enabledMcpTools rỗng + effort=high)
#   ② trỏ vào transcript mở đầu bằng "This session is being continued…"
#   ③ KHÔNG phải mục cuối cùng còn lại của tiêu đề đó
#   ④ KHÔNG phải mục MỚI NHẤT trong nhóm cùng tiêu đề
#
# ⚠️ Vì sao thêm ③④ (sự cố 18/08/2026):
#   ① và ② KHÔNG phân biệt được mục thật với mục rác. Mục app tự tạo cũng có
#   enabledMcpTools={} / effort=high; và mọi hội thoại dài đều trỏ vào đoạn nén.
#   Hai điều kiện sai nhân với nhau vẫn ra sai → lần chạy 18/08 dọn sạch cả 15
#   mục "Phong thủy hành lang và cửa sân sau", trong đó có mục GỐC do app tạo
#   (titleSource=user). Hội thoại biến mất hoàn toàn khỏi danh sách.
#   ③④ bảo đảm: dù nhận diện sai, mỗi tiêu đề LUÔN còn ít nhất một mục, và mục
#   còn lại là mục mới nhất.
#
# AN TOÀN: mặc định xem trước; --apply CHUYỂN VÀO THÙNG RÁC (không xoá cứng);
#          chặn khi Claude Desktop đang chạy; in sẵn lệnh hoàn tác.
#
#   clean-junk-entries.sh            # xem trước
#   clean-junk-entries.sh --apply    # dọn (sau khi Cmd+Q)
# =============================================================================
set -uo pipefail
IDX="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APPLY=0
for a in "$@"; do case "$a" in --apply) APPLY=1;; *) echo "Tham số lạ: $a"; exit 2;; esac; done

# shellcheck disable=SC2009
# CỐ Ý dùng `ps -Ao args`, KHÔNG dùng `pgrep`: đo thực tế trên macOS,
# `pgrep -x Claude` trả về 0 tiến trình trong khi Claude Desktop ĐANG chạy
# (chỉ thấy helper). Nghe theo shellcheck ở đây sẽ làm chốt an toàn
# 'Claude đã tắt chưa' luôn trả lời sai ⇒ lệnh ghi chạy khi app đang mở.
RUNNING="$(ps -Ao args | grep -c "Claude\.app/Contents/MacOS/Claude$" || true)"
if [ "$APPLY" -eq 1 ] && [ "${RUNNING:-0}" -gt 0 ]; then
  echo "❌ Claude Desktop ĐANG CHẠY. Cmd+Q thoát hẳn, đợi 3 giây, rồi chạy lại."; exit 1
fi

TRASH="$KIT/recovery-data/junk-entries-$(date +%Y%m%d-%H%M%S)"
IDX="$IDX" APPLY="$APPLY" TRASH="$TRASH" /usr/bin/python3 - <<'PY'
import json, glob, os, shutil, collections
IDX=os.environ["IDX"]; APPLY=os.environ["APPLY"]=="1"; TRASH=os.environ["TRASH"]
paths={os.path.basename(f)[:-6]:f for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))}
def is_cont(sid):
    p=paths.get(sid)
    if not p: return False
    for line in open(p,errors="replace"):
        line=line.strip()
        if not line: continue
        try:o=json.loads(line)
        except:continue
        if o.get("type")!="user": continue
        c=(o.get("message") or {}).get("content")
        s=c if isinstance(c,str) else " ".join(x.get("text","") for x in c
              if isinstance(x,dict) and x.get("type")=="text") if isinstance(c,list) else ""
        s=" ".join(s.split())
        if not s: continue
        return s.startswith("This session is being continued") or s.startswith("Caveat:")
    return False
# Gom theo tiêu đề TRƯỚC, để biết mục nào là mục mới nhất của mỗi hội thoại.
by_title=collections.defaultdict(list)
docs={}
for f in glob.glob(os.path.join(IDX,"local_*.json")):
    try: d=json.load(open(f))
    except Exception: continue
    docs[f]=d
    by_title[(d.get("title") or "").strip()].append(f)
newest=set()
for t,fs in by_title.items():
    newest.add(max(fs, key=lambda x: docs[x].get("lastActivityAt") or 0))

junk=[]; keep=0
for f,d in docs.items():
    sig = d.get("enabledMcpTools")=={} and d.get("remoteMcpServersConfig")==[] and d.get("effort")=="high"
    cand = sig and is_cont(d.get("cliSessionId"))
    # ③④ — không bao giờ dọn mục mới nhất của một tiêu đề.
    if cand and f not in newest: junk.append((f,d.get("title")))
    else: keep+=1
c=collections.Counter(t for _,t in junk)
print(f"🧹 Mục RÁC cần dọn : {len(junk)}")
print(f"   Mục giữ nguyên  : {keep}\n")
for t,n in c.most_common(10): print(f"   {n:>4} × {str(t)[:58]}")
if not junk: print("\n✅ Không có gì để dọn."); raise SystemExit(0)
if not APPLY:
    print(f"\n🔎 Xem trước — chưa đụng gì. Cmd+Q thoát Claude rồi chạy lại với --apply.")
    raise SystemExit(0)
os.makedirs(TRASH, exist_ok=True)
for f,_ in junk: shutil.move(f, os.path.join(TRASH, os.path.basename(f)))
print(f"\n✅ Đã chuyển {len(junk)} mục vào thùng rác:\n   {TRASH}")
print(f"\nHoàn tác toàn bộ:\n   mv '{TRASH}'/*.json '{IDX}/'")
PY
