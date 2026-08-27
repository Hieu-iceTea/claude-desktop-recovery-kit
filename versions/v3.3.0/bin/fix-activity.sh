#!/usr/bin/env bash
# =============================================================================
# fix-activity.sh  (v3.3.0) — kéo mục CHÌM ĐÁY lên đúng vị trí
#
#   fix-activity.sh            Xem trước (chỉ đọc)
#   fix-activity.sh --apply    Sửa lastActivityAt cho khớp nội dung thật
#
# VẤN ĐỀ (gặp thật 27/08/2026):
#   Claude Desktop sắp xếp Recents theo `lastActivityAt` trong file chỉ mục.
#   Khi số đó KHÔNG khớp mốc thời gian bản ghi cuối cùng của transcript, mục
#   tụt xuống đáy danh sách. Người dùng cuộn ở phần trên không thấy → tưởng MẤT.
#
#   Ca thật: "REDANCE-1715 Mail investigation (fork)"
#       lastActivityAt ghi   13/08 11:35
#       nội dung thật kéo tới 27/08 18:06     ← lệch 14 NGÀY
#   Hội thoại còn nguyên 33,2 MB / 5.993 bản ghi, chỉ là không ai tìm ra.
#
#   `check` và `verify-entries` đều báo "✅ sạch" — vì chúng đo "có mục không"
#   và "có đủ nội dung không", KHÔNG đo "mục có nổi lên đúng chỗ không".
#
# AN TOÀN: chỉ sửa MỘT SỐ trong file chỉ mục (~700 byte). Không đụng transcript,
#          không tạo file mới, mỗi mục sửa đều có .bak-<TS>.
#          KHÔNG cần Claude tắt — nhưng app đang chạy có thể ghi đè lúc thoát,
#          nên vẫn nên chạy trong quy trình quit → fix → open.
#
# QUY ƯỚC: định danh bằng TIẾNG ANH; hiển thị bằng TIẾNG VIỆT CÓ DẤU.
# =============================================================================
set -uo pipefail

APPLY=0
for a in "$@"; do
  case "$a" in
    --apply)   APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "⛔ Tham số lạ: $a" >&2; exit 2 ;;
  esac
done

APPLY="$APPLY" /usr/bin/python3 - <<'PY'
import json,glob,os,datetime,shutil

APPLY=os.environ["APPLY"]=="1"
PROJ=os.path.expanduser("~/.claude/projects")
IDX=os.path.expanduser("~/Library/Application Support/Claude/claude-code-sessions-shared")

# Lệch dưới ngưỡng này thì bỏ qua — app tự cập nhật lastActivityAt trong lúc
# dùng, chênh vài phút là bình thường và sửa cũng không đổi thứ tự danh sách.
MIN_DRIFT_H = 6

files={os.path.basename(p)[:-6]:p for p in glob.glob(os.path.join(PROJ,"*","*.jsonl"))}

def last_ts(p):
    """mốc thời gian bản ghi CUỐI CÙNG — đọc ngược từ đuôi cho nhanh"""
    best=None
    for line in open(p,errors="replace"):
        s=line.strip()
        if not s or '"timestamp"' not in s: continue
        try:o=json.loads(s)
        except Exception: continue
        t=o.get("timestamp")
        if t and (best is None or t>best): best=t
    return best

def to_ms(iso):
    try:
        return int(datetime.datetime.fromisoformat(iso.replace("Z","+00:00")).timestamp()*1000)
    except Exception:
        return None

rows=[]
for f in glob.glob(os.path.join(IDX,"local_*.json")):
    try: d=json.load(open(f))
    except Exception: continue
    cli=d.get("cliSessionId")
    if not cli or cli not in files: continue
    lt=last_ts(files[cli])
    if not lt: continue
    real=to_ms(lt)
    if real is None: continue
    cur=d.get("lastActivityAt") or 0
    drift=(real-cur)/3600000.0
    if drift < MIN_DRIFT_H: continue          # chỉ sửa khi mục TỤT so với thực tế
    rows.append((drift,f,d,cur,real,lt,d.get("title","")or"(không tên)"))

rows.sort(reverse=True)

print(f"🔼 MỤC CHÌM ĐÁY — {'🟢 THỰC THI' if APPLY else '🔍 XEM TRƯỚC, chưa ghi gì'}")
print(f"   Sắp xếp Recents dựa trên lastActivityAt. Lệch ⇒ mục tụt khỏi tầm nhìn.\n")

if not rows:
    print("✅ Mọi mục đều có lastActivityAt khớp nội dung thật.")
    raise SystemExit(0)

print(f"   {'lệch':>8}  {'đang ghi':<14}{'thực tế':<14} tiêu đề")
fixed=0
for drift,f,d,cur,real,lt,title in rows:
    a=datetime.datetime.fromtimestamp(cur/1000).strftime("%d/%m %H:%M") if cur else "(không có)"
    b=datetime.datetime.fromtimestamp(real/1000).strftime("%d/%m %H:%M")
    print(f"   {drift/24:>6.1f}n  {a:<14}{b:<14} {title[:44]}")
    if APPLY:
        shutil.copy2(f,f+".bak-"+datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
        d["lastActivityAt"]=real
        if not d.get("lastFocusedAt") or d["lastFocusedAt"]<real:
            d["lastFocusedAt"]=real
        json.dump(d,open(f,"w"),ensure_ascii=False,indent=2)
        fixed+=1

print()
if APPLY:
    print(f"✅ Đã kéo {fixed} mục lên đúng vị trí. Mỗi mục có .bak-<TS> để hoàn tác.")
else:
    print(f"🔎 {len(rows)} mục đang chìm. Chưa ghi gì — thêm --apply để sửa.")
    raise SystemExit(1)
PY
