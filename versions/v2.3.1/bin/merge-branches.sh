#!/usr/bin/env bash
# =============================================================================
# merge-branches.sh   (v2.3.1)
#
# Dựng một transcript HỢP NHẤT chứa ĐỦ nội dung của mọi nhánh song song.
#
# Vì sao cần: khi hội thoại bị rewind hoặc ngắt giữa chừng, Claude tách nhánh.
# Mỗi nhánh giữ một phần. Recents chỉ trỏ được vào MỘT nhánh → mở ra thiếu.
# `--fix-stale` chỉ CHỌN giữa các nhánh có sẵn; đo ngày 18/08/2026: 0/36 chuỗi
# sửa được bằng cách chọn, vì KHÔNG nhánh nào chứa đủ. Phải hợp nhất.
#
# Script này CHỈ TẠO transcript mới. Không sửa nhánh gốc, không đụng chỉ mục.
# Trỏ Recents sang bản mới là việc riêng, dùng: repair-missing-sessions.sh --fix-stale
#
# 9 PHÉP KIỂM CHỨNG — trượt bất kỳ phép nào là KHÔNG ghi file:
#   ① JSON hợp lệ           ② sessionId đồng nhất    ③ 0 mắt xích parentUuid gãy
#   ④ đúng 1 dòng gốc       ⑤ đi hết chuỗi từ gốc    ⑥ có bản ghi tiêu đề
#   ⑦ thứ tự thời gian tăng ⑧⑨ BAO TRÙM mọi nhánh nguồn (thiếu 0)
#
#   merge-branches.sh --list                 # liệt kê chuỗi cần hợp nhất
#   merge-branches.sh --id <8-ký-tự>         # xem trước cho 1 chuỗi
#   merge-branches.sh --id <8-ký-tự> --apply # dựng file
# =============================================================================
set -uo pipefail
PROJ="$HOME/.claude/projects"
IDX="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
MODE=list; ID=""; APPLY=0; FORCE=0
SINCE=""; UNTIL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list)  MODE=list ;;
    --id)    MODE=one; shift; ID="${1:-}" ;;
    --apply) APPLY=1 ;;
    --force) FORCE=1 ;;
    --since) shift; SINCE="${1:-}" ;;
    --until) shift; UNTIL="${1:-}" ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Tham số lạ: $1"; exit 2 ;;
  esac
  shift
done
PROJ="$PROJ" IDX="$IDX" MODE="$MODE" ID="$ID" APPLY="$APPLY" FORCE="$FORCE" \
SINCE="${SINCE:-}" UNTIL="${UNTIL:-}" /usr/bin/python3 - <<'PY'
import json,glob,os,uuid,hashlib,collections,datetime
PROJ=os.environ["PROJ"]; IDX=os.environ["IDX"]
MODE=os.environ["MODE"]; ID=os.environ["ID"]; APPLY=os.environ["APPLY"]=="1"
FORCE=os.environ.get("FORCE")=="1"
SINCE=os.environ.get("SINCE","").strip(); UNTIL=os.environ.get("UNTIL","").strip()
MAX_MB=250             # ngưỡng THẬT, đo trên file đã dựng ngay trước khi ghi
MAX_RECORDS=200000     # chặn thô trước khi dựng, chỉ để khỏi vỡ bộ nhớ

def scan(p):
    title=None; lines=[]
    for line in open(p,errors="replace"):
        line=line.strip()
        if not line: continue
        try:o=json.loads(line)
        except Exception: continue
        ty=o.get("type")
        if ty=="custom-title" and o.get("customTitle"): title=o["customTitle"]
        elif ty=="ai-title" and o.get("aiTitle"): title=title or o["aiTitle"]
        lines.append(o)
    return title,lines

def _blocks(o):
    """tách một bản ghi thành (phần chữ, phần tool) — dùng chung cho 2 vân tay"""
    c=(o.get("message") or {}).get("content"); txt=[]; tool=[]
    if isinstance(c,str):
        if c.strip(): txt.append(c)
    elif isinstance(c,list):
        for x in c:
            if not isinstance(x,dict): continue
            ty=x.get("type")
            if ty=="text":
                if x.get("text","").strip(): txt.append(x["text"])
            elif ty=="tool_use":
                tool.append("TU:"+json.dumps(x.get("input"),sort_keys=True,ensure_ascii=False))
            elif ty=="tool_result":
                v=x.get("content")
                tool.append("TR:"+(v if isinstance(v,str) else json.dumps(v,sort_keys=True,ensure_ascii=False)))
            elif ty=="thinking":
                if x.get("thinking","").strip(): tool.append("TH:"+x["thinking"])
    return txt,tool

def _h(parts):
    if not parts: return None
    f=" ".join(" ".join(parts).split())
    if len(f)<10 or f.startswith(("This session is being continued","Caveat:","[Request interrupted")): return None
    return hashlib.sha1(f.encode()).hexdigest()

def key_of(o):
    """vân tay ĐẦY ĐỦ một dòng: chữ + tool_use + tool_result + thinking.

    Dùng để khử trùng lặp khi hợp nhất VÀ cho phép kiểm chứng ⑧.
    Sự cố 26/08/2026: bản cũ chỉ băm phần `text`, nên bản ghi thuần tool có vân
    tay None; vòng hợp nhất bỏ qua mọi dòng key=None → 493 khối lệnh/kết quả của
    11 nhánh rơi khỏi file hợp nhất. Phép kiểm chứng ⑧ lại dùng chính vân tay đó
    nên không bao giờ phát hiện được — đo cái thước bằng chính cái thước cong.
    """
    if o.get("type") not in ("user","assistant"): return None
    txt,tool=_blocks(o)
    return _h(txt+tool)

def tkey_of(o):
    """vân tay CHỮ — chỉ để đếm/hiển thị 'đoạn nội dung người đọc được'.

    KHÔNG dùng cho việc nhận dạng hội thoại: đo thực tế trên máy này, vân tay
    tool bị dùng chung giữa nhiều hội thoại khác nhau (một vân tay xuất hiện ở
    tới 12 hội thoại) — gộp chúng vào phép nhận dạng sẽ nối nhầm hội thoại rời.
    """
    if o.get("type") not in ("user","assistant"): return None
    txt,_=_blocks(o)
    return _h(txt)

files={}
for f in glob.glob(os.path.join(PROJ,"*","*.jsonl")):
    if os.path.getsize(f)<20000: continue
    files[os.path.basename(f)[:-6]]=f
indexed={}
for f in glob.glob(os.path.join(IDX,"local_*.json")):
    try:o=json.load(open(f))
    except Exception: continue
    if o.get("cliSessionId"): indexed[o["cliSessionId"]]=o.get("title")

# ── BỘ NHỚ: chỉ giữ TIÊU ĐỀ + hai tập vân tay (vài chục byte/bản ghi), KHÔNG
# giữ nội dung đã phân tích. Bản trước cache cả danh sách dòng của MỌI transcript
# ⇒ `--list` chiếm 4,85 GB RAM và mất 98 giây trên máy này (5,6 GB transcript).
# Nội dung chỉ được đọc lại khi thật sự hợp nhất, và chỉ cho các nhánh liên quan.
cache={}
def get(sid):
    if sid not in cache:
        t,l=scan(files[sid])
        ts=[o["timestamp"] for o in l if o.get("timestamp")]
        cache[sid]=(t,{key_of(o) for o in l}-{None},{tkey_of(o) for o in l}-{None},
                    ts[-1] if ts else "")
        del l
    return cache[sid]

def lines_of(sid):
    """đọc lại nội dung một nhánh — chỉ gọi khi đang hợp nhất"""
    return scan(files[sid])[1]

chains=collections.defaultdict(list)
for sid,p in files.items():
    t=get(sid)[0]
    if t: chains[(os.path.dirname(p),t.strip().lower())].append(sid)

todo=[]
for k,sids in chains.items():
    if len(sids)<2: continue
    hit=[s for s in sids if s in indexed]
    if not hit: continue
    cur=max(hit,key=lambda s:len(get(s)[1]))
    union=set().union(*[get(s)[1] for s in sids])
    if union==get(cur)[1]: continue
    todo.append((len(union)-len(get(cur)[1]),k[1],cur,sids,len(get(cur)[1]),len(union)))
todo.sort(reverse=True)

if MODE=="list":
    print(f"🧩 Chuỗi cần HỢP NHẤT: {len(todo)}\n")
    for miss,t,cur,sids,n,u in todo[:25]:
        print(f"  {cur[:8]}  {t[:54]}")
        print(f"            mở {n}/{u} bản ghi · thiếu {miss} · {len(sids)} nhánh")
    if len(todo)>25:
        print(f"\n  … còn {len(todo)-25} chuỗi nữa không hiện ở đây (danh sách cắt ở 25).")
    print("\n  Xem trước 1 chuỗi:  merge-branches.sh --id <8-ký-tự>")
    raise SystemExit(0)

sel=[x for x in todo if x[2].startswith(ID)]
if not sel:
    print(f"❌ Không thấy chuỗi nào có mục Recents bắt đầu bằng '{ID}'."); raise SystemExit(1)
miss,title,cur,sids,n,u=sel[0]
_tn=len(get(cur)[2]); _tu=len(set().union(*[get(s)[2] for s in sids]))
print(f"🧩 {title}")
print(f"   mục Recents đang mở {cur[:8]} · {n}/{u} bản ghi · thiếu {miss}")
print(f"   trong đó đoạn CHỮ người đọc được: {_tn}/{_tu}")
print(f"   nhánh nguồn: {len(sids)}")

# ── LỌC THEO GIAI ĐOẠN (--since / --until) ─────────────────────────────
# Hội thoại rất dài (đo thật: REDANCE-1715 có 699 nhánh / 2941 MB) không thể gộp
# hết — file kết quả ~597 MB, app gần như chắc chắn không mở nổi. Gộp theo từng
# giai đoạn cho ra nhiều mục vừa phải, mỗi mục đọc được.
def _lastday(sid):
    return get(sid)[3][:10]
if SINCE or UNTIL:
    before=len(sids)
    sids=[x for x in sids
          if (not SINCE or _lastday(x)>=SINCE) and (not UNTIL or _lastday(x)<=UNTIL)]
    if not sids:
        print(f"\n⛔ Không nhánh nào nằm trong khoảng {SINCE or '…'} → {UNTIL or '…'}.")
        raise SystemExit(1)
    if cur not in sids:
        # Mục Recents phải nằm trong tập gộp, nếu không --fix-stale sẽ không có gì để trỏ.
        sids.append(cur)
    print(f"   giai đoạn {SINCE or '…'} → {UNTIL or '…'}: giữ {len(sids)}/{before} nhánh")

# ── CHỐT QUY MÔ ─────────────────────────────────────────────────────────
# Hội thoại dài bị nén ngữ cảnh có thể có hàng trăm nhánh; gộp hết sẽ ra file
# vài GB mà app nhiều khả năng không mở nổi — đổi một vấn đề lấy vấn đề nặng hơn.
# Ngưỡng phải đo THỨ SẼ SINH RA, không đo nguồn — các nhánh chồng lấp rất nhiều
# nên tổng nguồn phóng đại kích thước kết quả nhiều lần (đo thật REDANCE-1715:
# 2941 MB nguồn nhưng chỉ 56.537 bản ghi phân biệt). Ước lượng theo tỉ lệ cũng
# sai (thử: báo 2 MB cho cả chuỗi 14 nhánh lẫn chuỗi 699 nhánh) vì các nhánh
# không đồng đều. Nên: CHẶN THÔ ở đây cho khỏi vỡ bộ nhớ, còn ngưỡng THẬT thì đo
# CHÍNH XÁC trên file đã dựng, ngay trước khi ghi.
tot_bytes=sum(os.path.getsize(files[s]) for s in sids)
tot_mb=tot_bytes//1048576
print(f"   kích thước nguồn: {tot_mb} MB")
if len(union)>MAX_RECORDS and not FORCE:
    print(f"\n⛔ QUÁ LỚN: {len(union)} bản ghi phân biệt (ngưỡng {MAX_RECORDS}).")
    print(f"   Dựng file này sẽ ngốn rất nhiều bộ nhớ. Hợp nhất theo TỪNG GIAI ĐOẠN:")
    print(f"     merge-branches.sh --id {cur[:8]} --since 2026-07-01 --until 2026-07-31")
    print(f"   Vẫn muốn thử: thêm --force")
    raise SystemExit(1)

# ── spine = nhánh nhiều nội dung nhất; chèn các đoạn thiếu theo thời gian ──
spine=max(sids,key=lambda s:len(get(s)[1]))
slines=lines_of(spine); sset=get(spine)[1]
out=[dict(o) for o in slines]
have=set(sset)
added=0
for s in sorted(sids,key=lambda s:-len(get(s)[2])):
    if s==spine: continue
    ol=lines_of(s)
    run=[]
    for o in ol:
        k=key_of(o)
        if k and k not in have:
            run.append(o); have.add(k)
        elif run:
            out.extend(dict(x) for x in run); added+=len(run); run=[]
    if run: out.extend(dict(x) for x in run); added+=len(run)
# sắp theo thời gian, giữ header lên đầu
hdr=[o for o in out if not o.get("timestamp")]
body=sorted([o for o in out if o.get("timestamp")],key=lambda o:o["timestamp"])
NEW=str(uuid.uuid4())
final=hdr+body
prev=None
for o in final:
    if "sessionId" in o: o["sessionId"]=NEW
    if o.get("uuid"):
        o["parentUuid"]=prev; prev=o["uuid"]

# ── 9 phép kiểm chứng ──
uu={o["uuid"] for o in final if o.get("uuid")}
dang=[o for o in final if o.get("parentUuid") and o["parentUuid"] not in uu]
root=[o for o in final if "parentUuid" in o and o["parentUuid"] is None]
sids_set={o.get("sessionId") for o in final if o.get("sessionId")}
ts=[o["timestamp"] for o in final if o.get("timestamp")]
child=collections.defaultdict(list)
for o in final:
    if o.get("parentUuid"): child[o["parentUuid"]].append(o["uuid"])
seen=set(); st=[o["uuid"] for o in root if o.get("uuid")]
while st:
    x=st.pop()
    if x in seen: continue
    seen.add(x); st.extend(child.get(x,[]))
mset={key_of(o) for o in final}-{None}
checks=[
 ("① JSON hợp lệ", True, f"{len(final)} dòng"),
 ("② sessionId đồng nhất", len(sids_set)<=1, str(len(sids_set))),
 ("③ mắt xích gãy = 0", not dang, str(len(dang))),
 ("④ đúng 1 dòng gốc", len(root)==1, str(len(root))),
 ("⑤ đi hết chuỗi từ gốc", len(seen)==len(uu), f"{len(seen)}/{len(uu)}"),
 ("⑥ có bản ghi tiêu đề", any(o.get("type") in ("custom-title","ai-title") for o in final), ""),
 ("⑦ thời gian tăng dần", ts==sorted(ts), ""),
]
for s in sids:
    checks.append((f"⑧ bao trùm {s[:8]}", not (get(s)[1]-mset), str(len(get(s)[1]-mset))))
print("\n── KIỂM CHỨNG ──")
ok=True
for name,passed,info in checks:
    print(f"  {'✅' if passed else '❌'} {name}  {info}")
    ok = ok and passed
_tfin={tkey_of(o) for o in final}-{None}
print(f"\n  Kết quả: {len(mset)} bản ghi (trước: {n}) · thêm {added} dòng")
print(f"           trong đó đoạn CHỮ: {len(_tfin)} (trước: {_tn})")
if not ok:
    print("\n❌ CÓ PHÉP KIỂM CHỨNG TRƯỢT — KHÔNG ghi file."); raise SystemExit(1)
# ── CHỐT KÍCH THƯỚC THẬT: đo trên chính nội dung sắp ghi ──────────────────
_blob=[json.dumps(o,ensure_ascii=False) for o in final]
real_mb=(sum(len(x.encode()) for x in _blob)+len(_blob))//1048576
print(f"  ⑨ kích thước file kết quả: {real_mb} MB")
if real_mb>MAX_MB and not FORCE:
    print(f"\n⛔ File kết quả {real_mb} MB > ngưỡng {MAX_MB} MB — app nhiều khả năng KHÔNG mở nổi.")
    print(f"   KHÔNG ghi gì. Hợp nhất theo TỪNG GIAI ĐOẠN:")
    print(f"     merge-branches.sh --id {cur[:8]} --since <YYYY-MM-DD> --until <YYYY-MM-DD>")
    print(f"   Vẫn muốn thử: thêm --force")
    raise SystemExit(1)
if not APPLY:
    print(f"\n🔎 Xem trước — chưa ghi. Thêm --apply để dựng file.")
    raise SystemExit(0)
dest=os.path.join(os.path.dirname(files[spine]),f"{NEW}.jsonl")
with open(dest,"w") as fh:
    for x in _blob: fh.write(x+"\n")
os.chmod(dest,0o600)
print(f"\n✅ Đã dựng: {NEW}")
print(f"   {dest}")
# In SẴN mã phiên đúng. Sự cố 26/08/2026: hướng dẫn đưa mã của chuỗi (--id) sang
# cho --only, nhưng hai cờ này dùng HAI KHÔNG GIAN MÃ khác nhau — --only khớp theo
# phiên mà MỤC ĐANG MỞ. Gõ nhầm thì fix-stale báo "không mục nào khớp".
print(f"\nBước tiếp — thoát Claude rồi trỏ mục Recents sang bản này:")
print(f"   safe-quit.sh")
print(f"   repair-missing-sessions.sh --fix-stale --apply --only {cur[:8]}")
print(f"\nHoàn tác: rm '{dest}'")
PY
