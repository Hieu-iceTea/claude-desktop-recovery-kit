#!/usr/bin/env bash
# =============================================================================
# dedup-entries.sh   (v2.3.0)
# Dọn các mục Recents TRÙNG NHAU — nhiều mục cùng trỏ vào MỘT hội thoại.
#
# ⚠️ KHÔNG BAO GIỜ ĐỤNG VÀO NỘI DUNG. Script này chỉ di chuyển file chỉ mục
#    `local_*.json`. Transcript `.jsonl` trong ~/.claude/projects KHÔNG bị đọc
#    để ghi, không bị sửa, không bị xoá — chỉ đọc để so nội dung.
#    Dọn một mục = gỡ một LỐI VÀO, không phải xoá một hội thoại.
#
# Vì sao có mục trùng: `repair --apply` từng tạo mỗi bản rẽ nhánh thành một mục.
#   23/08/2026 một lần chạy đẻ 14 mục "Phong thủy hành lang và cửa sân sau";
#   18/08 đẻ 6 mục "REDANCE-1715 Mail investigation" (mtime: cùng một giây).
#
# PHÂN BIỆT DUPLICATE ≠ FORK:
#   • DUPLICATE (script tạo): cùng dự án + cùng tiêu đề + nội dung chồng lấp.
#   • FORK (bạn tự tách): tiêu đề KHÁC ("(fork) QA"…) → không bao giờ cùng nhóm.
#   • Cùng tên nhưng nội dung không dính nhau: hai hội thoại khác → giữ cả hai.
#
# HAI CHẾ ĐỘ — khác nhau ở chỗ có ẨN nội dung cũ khỏi danh sách hay không:
#
#   (mặc định) PHỦ KÍN — không ẩn gì
#       Chỉ dọn mục nào có nội dung ĐÃ NẰM TRỌN trong các mục được giữ.
#       Bảo đảm: mọi tin nhắn mở được TRƯỚC khi chạy thì SAU khi chạy vẫn mở được.
#       Các mục giữ lại (ngoài mục mới nhất) được đổi tên thêm hậu tố
#       "⤷ lưu trữ <ngày>" để danh sách đọc được, thay vì 15 dòng trùng tên.
#
#   --newest-only  GỌN TỐI ĐA — có ẩn
#       Mỗi hội thoại giữ đúng 1 mục (bản có tin nhắn mới nhất). Danh sách sạch
#       nhất, nhưng phần nội dung cũ không mở được từ danh sách nữa (VẪN CÒN
#       trên đĩa: xem `repair --unreachable`, gộp bằng `merge-branches.sh`).
#       Script in rõ số đoạn sẽ bị ẩn trước khi bạn quyết định.
#
# Cờ khác: --no-rename (không đổi tên mục lưu trữ) · --apply · --dry-run
# AN TOÀN: mặc định xem trước · --apply chuyển vào THÙNG RÁC (không xoá cứng)
#          · chặn khi Claude Desktop đang chạy · mỗi mục đổi tên có .bak-<TS>
#          · mục KHÔNG còn transcript thì luôn GIỮ (không đủ căn cứ kết luận)
# Tương thích bash 3.2.
# =============================================================================
set -uo pipefail
IDX="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
PROJ="$HOME/.claude/projects"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APPLY=0; NEWEST=0; RENAME=1
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    --newest-only) NEWEST=1 ;;
    --no-rename) RENAME=0 ;;
    -h|--help) sed -n '2,42p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Tham số lạ: $a"; exit 2 ;;
  esac
done

RUNNING="$(ps -Ao args | grep -c "Claude\.app/Contents/MacOS/Claude$" || true)"
if [ "$APPLY" -eq 1 ] && [ "${RUNNING:-0}" -gt 0 ]; then
  echo "⛔ Claude Desktop đang chạy. Thoát hẳn (safe-quit.sh) rồi chạy lại."; exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
TRASH="$KIT/recovery-data/dup-entries-$TS"
IDX="$IDX" PROJ="$PROJ" APPLY="$APPLY" NEWEST="$NEWEST" RENAME="$RENAME" \
TRASH="$TRASH" STAMP="$TS" /usr/bin/python3 - <<'PYEOF'
import json, glob, os, shutil, hashlib, collections, datetime

IDX=os.environ["IDX"]; PROJ=os.environ["PROJ"]; TRASH=os.environ["TRASH"]
APPLY=os.environ["APPLY"]=="1"; NEWEST=os.environ["NEWEST"]=="1"
RENAME=os.environ["RENAME"]=="1"; STAMP=os.environ["STAMP"]

tpath={os.path.basename(f)[:-6]: f for f in glob.glob(os.path.join(PROJ,"*","*.jsonl"))}

def scan(sid):
    """CHỈ ĐỌC transcript. Trả vân tay nội dung + số tin nhắn + mốc cuối."""
    p=tpath.get(sid)
    if not p: return None
    fp=set(); n=0; last=None
    for line in open(p, errors="replace"):
        line=line.strip()
        if not line: continue
        try: o=json.loads(line)
        except Exception: continue
        if o.get("type") not in ("user","assistant"): continue
        n+=1
        if o.get("timestamp"): last=o["timestamp"]
        cc=(o.get("message") or {}).get("content"); parts=[]
        if isinstance(cc,str): parts=[cc]
        elif isinstance(cc,list):
            for q in cc:
                if isinstance(q,dict) and q.get("type")=="text" and q.get("text","").strip():
                    parts.append(q["text"])
        if parts:
            flat=" ".join(" ".join(parts).split())
            if len(flat)>=10 and not flat.startswith(
                    ("This session is being continued","Caveat:","[Request interrupted")):
                fp.add(hashlib.sha1(flat.encode()).hexdigest())
    return dict(fp=fp, n=n, last=last)

groups=collections.defaultdict(list)
for f in glob.glob(os.path.join(IDX,"local_*.json")):
    try: d=json.load(open(f))
    except Exception: continue
    sid=d.get("cliSessionId")
    proj=os.path.basename(os.path.dirname(tpath[sid])) if sid in tpath else "(không rõ)"
    groups[(proj,(d.get("title") or "").strip())].append((f,d,sid))

def day(iso):
    """dd/mm HH:MM — đủ phân biệt hai nhánh cùng ngày (gặp thật: 2 nhánh 07/08)."""
    if not iso: return "?"
    v=str(iso)
    return f"{v[8:10]}/{v[5:7]} {v[11:16]}"

plans=[]           # (title, proj, keep[list], drop[list], hidden_fp, info)
for (proj,title),mem in groups.items():
    if len(mem)<2: continue
    info={f:scan(sid) for f,d,sid in mem}
    use=[(f,d,sid) for f,d,sid in mem if info[f] and info[f]["fp"]]
    if len(use)<2: continue
    par={f:f for f,_,_ in use}
    def find(x):
        while par[x]!=x: par[x]=par[par[x]]; x=par[x]
        return x
    inv=collections.defaultdict(list)
    for f,_,_ in use:
        for h in info[f]["fp"]: inv[h].append(f)
    for fs in inv.values():
        for x in fs[1:]:
            a,b=find(fs[0]),find(x)
            if a!=b: par[a]=b
    clusters=collections.defaultdict(list)
    for f,d,sid in use: clusters[find(f)].append((f,d,sid))
    for _root,cl in clusters.items():
        if len(cl)<2: continue
        universe=set().union(*[info[f]["fp"] for f,_,_ in cl])
        primary=max(cl, key=lambda x:(info[x[0]]["last"] or "", len(info[x[0]]["fp"])))
        if NEWEST:
            keep=[primary]
        else:
            # PHỦ KÍN: mục mới nhất trước, rồi tham lam thêm mục nào bù được
            # nhiều nội dung chưa phủ nhất, cho tới khi phủ hết universe.
            keep=[primary]; cov=set(info[primary[0]]["fp"])
            rest=[x for x in cl if x is not primary]
            while cov!=universe and rest:
                nxt=max(rest, key=lambda x: len(info[x[0]]["fp"]-cov))
                if not (info[nxt[0]]["fp"]-cov): break
                keep.append(nxt); cov|=info[nxt[0]]["fp"]; rest.remove(nxt)
        kept_fp=set().union(*[info[f]["fp"] for f,_,_ in keep])
        drop=[x for x in cl if x not in keep]
        plans.append((title,proj,keep,drop,universe-kept_fp,info))

mode = "GỌN TỐI ĐA (--newest-only) — CÓ ẩn nội dung cũ" if NEWEST \
       else "PHỦ KÍN (mặc định) — KHÔNG ẩn nội dung nào"
print("🧬 dedup-entries — nhiều mục cùng trỏ vào MỘT hội thoại")
print(f"   Chế độ: {mode}")
print(f"   {'🟢 THỰC THI (--apply)' if APPLY else '🔍 XEM TRƯỚC — chưa ghi gì'}")
print("   Chỉ di chuyển file chỉ mục. Transcript (nội dung) KHÔNG bị đụng tới.\n")
if not plans:
    print("✅ Không có mục trùng. Mỗi hội thoại đúng một mục.")
    raise SystemExit(0)

n_drop=sum(len(p[3]) for p in plans)
n_hide=sum(len(p[4]) for p in plans)
renames=[]
# Mọi tiêu đề đang tồn tại — để nhãn lưu trữ không đụng nhau và không đụng mục sẵn có.
used_titles={(d.get("title") or "").strip() for mem in groups.values() for _f,d,_s in mem}
for title,proj,keep,drop,hidden,info in sorted(plans, key=lambda r:-len(r[3])):
    print(f"▸ {title}   [{len(keep)+len(drop)} mục → giữ {len(keep)}]")
    for i,(f,d,sid) in enumerate(sorted(keep, key=lambda x: str(info[x[0]]['last'] or ''), reverse=True)):
        tag = "GIỮ " if i==0 else "GIỮ↩"
        new_title=None
        if i>0 and RENAME and "⤷ lưu trữ" not in (d.get("title") or ""):
            new_title=f"{title}  ⤷ lưu trữ {day(info[f]['last'])}"
            # Nhãn phải DUY NHẤT, nếu không lại đẻ ra đúng thứ đang đi dọn.
            # Gặp thật: hai nhánh REDANCE-1715 cùng kết thúc lúc 05/08 05:56.
            if new_title in used_titles:
                new_title += f" ·{sid[:4]}"
            used_titles.add(new_title)
            renames.append((f,new_title))
        print(f"   {tag} {sid[:8]}  {info[f]['n']:>5} tin nhắn · {len(info[f]['fp']):>4} đoạn"
              f" · tin cuối {str(info[f]['last'])[:16].replace('T',' ')}"
              + (f"\n         → đổi tên: {new_title}" if new_title else ""))
    for f,d,sid in sorted(drop, key=lambda x: str(info[x[0]]['last'] or ''), reverse=True):
        kept_fp=set().union(*[info[k[0]]['fp'] for k in keep])
        extra=len(info[f]['fp']-kept_fp)
        note = "trùng hoàn toàn" if extra==0 else f"⚠️ còn {extra} đoạn riêng"
        print(f"   DỌN {sid[:8]}  {info[f]['n']:>5} tin nhắn · {len(info[f]['fp']):>4} đoạn · {note}")
    if hidden:
        print(f"   ↳ ⚠️ {len(hidden)} đoạn nội dung sẽ KHÔNG mở được từ danh sách nữa")
        print(f"       (vẫn nguyên trên đĩa — merge-branches.sh · repair --unreachable)")
    print()

print("─"*54)
print(f"Dọn {n_drop} mục · đổi tên {len(renames)} mục lưu trữ · ẩn {n_hide} đoạn nội dung.")
if n_hide==0:
    print("✅ KHÔNG mất lối vào nội dung nào: mọi tin nhắn mở được trước khi chạy,")
    print("   sau khi chạy vẫn mở được.")
else:
    print("⚠️  Có nội dung bị ẩn khỏi danh sách. Bỏ --newest-only để không ẩn gì.")
if not APPLY:
    print("\n🔎 Chưa đụng gì. Thoát hẳn Claude Desktop rồi chạy lại với --apply.")
    raise SystemExit(0)

os.makedirs(TRASH, exist_ok=True)
moved=0
for title,proj,keep,drop,hidden,info in plans:
    for f,d,sid in drop:
        shutil.move(f, os.path.join(TRASH, os.path.basename(f))); moved+=1
for f,new_title in renames:
    if not os.path.exists(f): continue
    shutil.copy2(f, f + ".bak-" + STAMP)
    d=json.load(open(f)); d["title"]=new_title; d["titleSource"]="user"
    json.dump(d, open(f,"w"), ensure_ascii=False, indent=2)
print(f"\n✅ Đã chuyển {moved} mục vào thùng rác, đổi tên {len(renames)} mục lưu trữ.")
print(f"   {TRASH}")
print(f"\nHoàn tác:")
print(f"   mv '{TRASH}'/*.json '{IDX}/'")
print(f"   for b in '{IDX}'/*.bak-{STAMP}; do mv \"$b\" \"${{b%.bak-{STAMP}}}\"; done")
PYEOF
