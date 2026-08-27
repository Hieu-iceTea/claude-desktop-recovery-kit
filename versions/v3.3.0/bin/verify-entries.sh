#!/usr/bin/env bash
# =============================================================================
# verify-entries.sh  (v3.3.0) — ĐO xem đã đủ dữ liệu chưa, thay vì TIN là đủ
#
#   verify-entries.sh            Kiểm tất cả (chỉ đọc)
#   verify-entries.sh --quiet    Chỉ in dòng tổng kết
#
# VÌ SAO CÓ FILE NÀY — ba sự cố cùng một dạng, trong một ngày (27/08/2026):
#   1. `quit` → script → `open`  ⇒ thiếu 2 giờ 16 phút. Không có bước trỏ lại.
#   2. `fix --list-only --apply` ⇒ vẫn thiếu. Cờ đó bỏ TOÀN BỘ khối ② nội dung.
#   3. `fix --apply` báo "✅ xong" ⇒ đo lại vẫn còn 2 hội thoại thiếu.
#
#   Cả ba lần script đều báo THÀNH CÔNG. Người dùng phải tự phát hiện bằng mắt.
#   Gốc rễ: script chưa bao giờ TỰ ĐO LẠI sau khi sửa.
#
# PHÉP ĐO: với mỗi hội thoại nhiều nhánh, hỏi đúng một câu —
#   "mục Recents có chứa BẢN GHI MỚI NHẤT của cả chuỗi không?"
# Đây là câu trả lời trực tiếp cho "tôi có mất tin nhắn mới nhất không".
#
# QUY ƯỚC: định danh bằng TIẾNG ANH; hiển thị bằng TIẾNG VIỆT CÓ DẤU.
# =============================================================================
set -uo pipefail

QUIET=0
for a in "$@"; do
  case "$a" in
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "⛔ Tham số lạ: $a" >&2; exit 2 ;;
  esac
done

QUIET="$QUIET" /usr/bin/python3 - <<'PY'
import json,glob,os,hashlib,collections
import datetime as _dt

# Hội thoại có bản ghi mới hơn ngần này phút thì coi là ĐANG CHẠY, không báo thiếu.
LIVE_MIN=20
QUIET=os.environ.get("QUIET")=="1"
PROJ=os.path.expanduser("~/.claude/projects")
IDX=os.path.expanduser("~/Library/Application Support/Claude/claude-code-sessions-shared")

idx={}
for f in glob.glob(os.path.join(IDX,"local_*.json")):
    try: d=json.load(open(f))
    except Exception: continue
    c=d.get("cliSessionId")
    if c: idx[c]=d.get("title","") or "(không tên)"

def title_of(p):
    """Tiêu đề CUỐI CÙNG trong file — PHẢI khớp cách merge-branches.sh gom nhóm.

    LỖI 27/08/2026: bản đầu đọc tiêu đề ĐẦU rồi dừng sớm (i>500). Khi hội thoại
    được đổi tên (fork rồi đặt tên mới), tiêu đề đầu và cuối KHÁC NHAU:
        9deec795  đầu 'REDANCE-1715 Mail investigation'
                  cuối 'REDANCE-1715 Mail investigation (fork) - bù devkit'
    Hai script gom nhóm khác nhau ⇒ `fix` báo "đã đúng nhánh" trong khi
    `verify` báo "thiếu 53.097 đoạn". Cả hai đều đúng theo cách gom của mình,
    và người dùng nhận hai kết luận mâu thuẫn.
    Một phép đo chỉ có nghĩa khi nó dùng CÙNG một thước với phép sửa."""
    t=None
    for line in open(p,errors="replace"):
        s=line.strip()
        if not s: continue
        try:o=json.loads(s)
        except Exception: continue
        ty=o.get("type")
        if ty=="custom-title" and o.get("customTitle"): t=o["customTitle"]
        elif ty=="ai-title" and o.get("aiTitle"): t=t or o["aiTitle"]
    return t

def key(o):
    c=(o.get("message") or {}).get("content"); parts=[]
    if isinstance(c,str):
        if c.strip(): parts.append(c)
    elif isinstance(c,list):
        for x in c:
            if not isinstance(x,dict): continue
            ty=x.get("type")
            if ty=="text" and x.get("text","").strip(): parts.append(x["text"])
            elif ty=="tool_use": parts.append("TU:"+json.dumps(x.get("input"),sort_keys=True,ensure_ascii=False))
            elif ty=="tool_result":
                v=x.get("content"); parts.append("TR:"+(v if isinstance(v,str) else json.dumps(v,sort_keys=True,ensure_ascii=False)))
            elif ty=="thinking" and x.get("thinking","").strip(): parts.append("TH:"+x["thinking"])
    if not parts: return None
    return hashlib.sha1(" ".join(" ".join(parts).split()).encode()).hexdigest()

def scan(p):
    fp=set(); newest=""; nk=None
    for line in open(p,errors="replace"):
        s=line.strip()
        if not s: continue
        try:o=json.loads(s)
        except Exception: continue
        k=key(o)
        if not k: continue
        fp.add(k)
        ts=o.get("timestamp") or ""
        if ts>newest: newest=ts; nk=k
    return fp,newest,nk

grp=collections.defaultdict(list)
for p in glob.glob(os.path.join(PROJ,"*","*.jsonl")):
    if os.path.getsize(p)<20000: continue
    t=title_of(p)
    if t: grp[(os.path.dirname(p),t.strip().lower())].append(p)

bad=[]; good=0; solo=0; live=0
for k,ps in grp.items():
    cur=[p for p in ps if os.path.basename(p)[:-6] in idx]
    if not cur: continue
    if len(ps)<2: solo+=1; continue
    data={p:scan(p) for p in ps}
    nts=max(d[1] for d in data.values())
    nk=next(d[2] for d in data.values() if d[1]==nts)
    if any(nk in data[p][0] for p in cur):
        good+=1; continue
    # ── HỘI THOẠI ĐANG CHẠY thì bỏ qua ──────────────────────────────────────
    # Hội thoại bạn đang mở luôn sinh bản ghi mới trong lúc script chạy, nên
    # LUÔN bị báo thiếu. Báo động giả kiểu đó nguy hiểm: quen thấy ⛔ mãi thì
    # sẽ bỏ qua cả lúc thiếu thật. Nó tự đúng ở lần `fix --apply` sau khi thoát.
    try:
        _age=(_dt.datetime.now(_dt.timezone.utc)
              - _dt.datetime.fromisoformat(nts.replace("Z","+00:00"))).total_seconds()/60
    except Exception:
        _age=1e9
    if _age <= LIVE_MIN:
        live+=1; continue
    uni=set().union(*[d[0] for d in data.values()])
    curfp=set().union(*[data[p][0] for p in cur])
    sid=os.path.basename(cur[0])[:-6]
    best=max(ps,key=lambda p:len(data[p][0]))
    bad.append((len(uni)-len(curfp),idx.get(sid,k[1]),sid[:8],os.path.basename(best)[:8],nts[:16]))

if not QUIET:
    print("🔎 KIỂM CHỨNG — mục Recents có chứa bản ghi MỚI NHẤT không?\n")
    print(f"   ✅ đủ tin nhắn mới nhất : {good}")
    print(f"   ⛔ THIẾU                : {len(bad)}")
    print(f"   ·  hội thoại một nhánh  : {solo} (không có gì để so)")
    if live: print(f"   ·  đang chạy, bỏ qua    : {live} (tự đúng ở lần fix sau khi thoát)")
    print()
    for miss,t,sid,best,ts in sorted(bad,reverse=True):
        print(f"   ⛔ {t[:52]}")
        print(f"      thiếu {miss} đoạn · mục trỏ {sid} · bản đủ nhất {best} · mới nhất {ts.replace('T',' ')}")
        print(f"      khắc phục:  claude-history merge --id {sid} --repoint --apply")
        print()

# ── CHIỀU 2: mục có nổi lên đúng chỗ không ──────────────────────────────────
# Mục đủ nội dung nhưng lastActivityAt lệch thì vẫn "mất" theo nghĩa người dùng
# không tìm ra. Đo luôn ở đây để một lệnh trả lời trọn câu "tôi có mất gì không".
import datetime as _dt
sunk=[]
for f in glob.glob(os.path.join(IDX,"local_*.json")):
    try: d=json.load(open(f))
    except Exception: continue
    cli=d.get("cliSessionId")
    if not cli: continue
    g=glob.glob(os.path.join(PROJ,"*",cli+".jsonl"))
    if not g: continue
    lt=""
    for line in open(g[0],errors="replace"):
        ln=line.strip()
        if not ln or '"timestamp"' not in ln: continue
        try:o=json.loads(ln)
        except Exception: continue
        t=o.get("timestamp")
        if t and t>lt: lt=t
    if not lt: continue
    try: real=int(_dt.datetime.fromisoformat(lt.replace("Z","+00:00")).timestamp()*1000)
    except Exception: continue
    cur=d.get("lastActivityAt") or 0
    if (real-cur)/3600000.0 >= 6:
        sunk.append(((real-cur)/86400000.0, d.get("title","")or"(không tên)", cli[:8]))
sunk.sort(reverse=True)
if not QUIET and sunk:
    print(f"   ⚠️  {len(sunk)} mục CHÌM ĐÁY danh sách (lastActivityAt lệch):")
    for drift,t,sid in sunk[:8]:
        print(f"      lệch {drift:.1f} ngày · {sid} · {t[:48]}")
    print(f"      khắc phục:  claude-history fix --apply")
    print()

if bad or sunk:
    if bad: print(f"⛔ {len(bad)} hội thoại đang THIẾU tin nhắn mới nhất.")
    if sunk: print(f"⚠️  {len(sunk)} mục chìm đáy — có mà không tìm ra.")
    print(f"   Chạy (lúc Claude đã tắt):  claude-history fix --apply")
    raise SystemExit(1)
print("✅ Mọi hội thoại đều chứa tin nhắn mới nhất và nổi đúng vị trí.")
PY
