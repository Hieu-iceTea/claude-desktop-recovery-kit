#!/usr/bin/env bash
# =============================================================================
# merge-branches.sh   (v2.2.0)
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
while [ $# -gt 0 ]; do
  case "$1" in
    --list)  MODE=list ;;
    --id)    MODE=one; shift; ID="${1:-}" ;;
    --apply) APPLY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Tham số lạ: $1"; exit 2 ;;
  esac
  shift
done
PROJ="$PROJ" IDX="$IDX" MODE="$MODE" ID="$ID" APPLY="$APPLY" FORCE="$FORCE" /usr/bin/python3 - <<'PY'
import json,glob,os,uuid,hashlib,collections,datetime
PROJ=os.environ["PROJ"]; IDX=os.environ["IDX"]
MODE=os.environ["MODE"]; ID=os.environ["ID"]; APPLY=os.environ["APPLY"]=="1"
FORCE=os.environ.get("FORCE")=="1"
MAX_BRANCH=40          # trên mức này thì file hợp nhất quá lớn, app dễ treo
MAX_MB=250

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

def key_of(o):
    """dấu vân tay nội dung một dòng; None nếu không phải tin nhắn"""
    if o.get("type") not in ("user","assistant"): return None
    c=(o.get("message") or {}).get("content")
    parts=[x["text"] for x in c if isinstance(x,dict) and x.get("type")=="text" and x.get("text","").strip()] if isinstance(c,list) else ([c] if isinstance(c,str) else [])
    if not parts: return None
    f=" ".join(" ".join(parts).split())
    if len(f)<10 or f.startswith(("This session is being continued","Caveat:","[Request interrupted")): return None
    return hashlib.sha1(f.encode()).hexdigest()

files={}
for f in glob.glob(os.path.join(PROJ,"*","*.jsonl")):
    if os.path.getsize(f)<20000: continue
    files[os.path.basename(f)[:-6]]=f
indexed={}
for f in glob.glob(os.path.join(IDX,"local_*.json")):
    try:o=json.load(open(f))
    except Exception: continue
    if o.get("cliSessionId"): indexed[o["cliSessionId"]]=o.get("title")

cache={}
def get(sid):
    if sid not in cache:
        t,l=scan(files[sid]); cache[sid]=(t,l,{key_of(o) for o in l}-{None})
    return cache[sid]

chains=collections.defaultdict(list)
for sid,p in files.items():
    t,_,_=get(sid)
    if t: chains[(os.path.dirname(p),t.strip().lower())].append(sid)

todo=[]
for k,sids in chains.items():
    if len(sids)<2: continue
    hit=[s for s in sids if s in indexed]
    if not hit: continue
    cur=max(hit,key=lambda s:len(get(s)[2]))
    union=set().union(*[get(s)[2] for s in sids])
    if union==get(cur)[2]: continue
    todo.append((len(union)-len(get(cur)[2]),k[1],cur,sids,len(get(cur)[2]),len(union)))
todo.sort(reverse=True)

if MODE=="list":
    print(f"🧩 Chuỗi cần HỢP NHẤT: {len(todo)}\n")
    for miss,t,cur,sids,n,u in todo[:25]:
        print(f"  {cur[:8]}  {t[:54]}")
        print(f"            mở {n}/{u} tin nhắn · thiếu {miss} · {len(sids)} nhánh")
    if len(todo)>25:
        print(f"\n  … còn {len(todo)-25} chuỗi nữa không hiện ở đây (danh sách cắt ở 25).")
    print("\n  Xem trước 1 chuỗi:  merge-branches.sh --id <8-ký-tự>")
    raise SystemExit(0)

sel=[x for x in todo if x[2].startswith(ID)]
if not sel:
    print(f"❌ Không thấy chuỗi nào có mục Recents bắt đầu bằng '{ID}'."); raise SystemExit(1)
miss,title,cur,sids,n,u=sel[0]
print(f"🧩 {title}\n   mục Recents đang mở {cur[:8]} · {n}/{u} tin nhắn · thiếu {miss}")
print(f"   nhánh nguồn: {len(sids)}")

# ── CHỐT QUY MÔ ─────────────────────────────────────────────────────────
# Hội thoại dài bị nén ngữ cảnh có thể có hàng trăm nhánh; gộp hết sẽ ra file
# vài GB mà app nhiều khả năng không mở nổi — đổi một vấn đề lấy vấn đề nặng hơn.
tot_mb=sum(os.path.getsize(files[s]) for s in sids)//1048576
if (len(sids)>MAX_BRANCH or tot_mb>MAX_MB) and not FORCE:
    print(f"\n⛔ QUÁ LỚN: {len(sids)} nhánh · {tot_mb} MB nguồn.")
    print(f"   Ngưỡng an toàn: {MAX_BRANCH} nhánh / {MAX_MB} MB.")
    print(f"   File hợp nhất sẽ rất lớn và app nhiều khả năng KHÔNG mở nổi.")
    print(f"   Với hội thoại dài, nên hợp nhất theo TỪNG GIAI ĐOẠN thay vì gộp hết.")
    print(f"   Vẫn muốn thử: thêm --force")
    raise SystemExit(1)

# ── spine = nhánh nhiều nội dung nhất; chèn các đoạn thiếu theo thời gian ──
spine=max(sids,key=lambda s:len(get(s)[2]))
_,slines,sset=get(spine)
out=[dict(o) for o in slines]
have=set(sset)
added=0
for s in sorted(sids,key=lambda s:-len(get(s)[2])):
    if s==spine: continue
    _,ol,_=get(s)
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
    checks.append((f"⑧ bao trùm {s[:8]}", not (get(s)[2]-mset), str(len(get(s)[2]-mset))))
print("\n── KIỂM CHỨNG ──")
ok=True
for name,passed,info in checks:
    print(f"  {'✅' if passed else '❌'} {name}  {info}")
    ok = ok and passed
print(f"\n  Kết quả: {len(mset)} tin nhắn (trước: {n})  ·  thêm {added} dòng")
if not ok:
    print("\n❌ CÓ PHÉP KIỂM CHỨNG TRƯỢT — KHÔNG ghi file."); raise SystemExit(1)
if not APPLY:
    print(f"\n🔎 Xem trước — chưa ghi. Thêm --apply để dựng file.")
    raise SystemExit(0)
dest=os.path.join(os.path.dirname(files[spine]),f"{NEW}.jsonl")
with open(dest,"w") as fh:
    for o in final: fh.write(json.dumps(o,ensure_ascii=False)+"\n")
os.chmod(dest,0o600)
print(f"\n✅ Đã dựng: {NEW}")
print(f"   {dest}")
print(f"\nBước tiếp — Cmd+Q thoát Claude rồi trỏ Recents sang bản này:")
print(f"   repair-missing-sessions.sh --fix-stale")
print(f"\nHoàn tác: rm '{dest}'")
PY
