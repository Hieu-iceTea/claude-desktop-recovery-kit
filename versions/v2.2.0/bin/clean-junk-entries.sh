#!/usr/bin/env bash
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
# Nhận diện RÁC = thoả CẢ HAI:
#   ① mang dấu vết do repair ghi (enabledMcpTools rỗng + effort=high)
#   ② trỏ vào transcript mở đầu bằng "This session is being continued…"
# Mục gốc của app và mục repair tạo ĐÚNG đều không khớp → không bị đụng.
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
junk=[]; keep=0
for f in glob.glob(os.path.join(IDX,"local_*.json")):
    try: d=json.load(open(f))
    except Exception: continue
    sig = d.get("enabledMcpTools")=={} and d.get("remoteMcpServersConfig")==[] and d.get("effort")=="high"
    if sig and is_cont(d.get("cliSessionId")): junk.append((f,d.get("title")))
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
