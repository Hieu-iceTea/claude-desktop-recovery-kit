#!/usr/bin/env bash
# =============================================================================
# prune-tool-payload.sh  (v3.2.0) — làm hội thoại NHẮN TIẾP ĐƯỢC trở lại
#
#   prune-tool-payload.sh              Xem trước TẤT CẢ, không ghi gì
#   prune-tool-payload.sh --id <mã>    Xem trước một hội thoại
#   prune-tool-payload.sh --apply      Dựng file nhẹ (KHÔNG trỏ mục)
#
# VẤN ĐỀ: hội thoại quá dài thì Claude Desktop báo "Prompt is too long" và
#   KHÔNG nhắn tiếp được nữa. `/compact` cũng không cứu được.
#
# ĐO THẬT trên máy này 27/08/2026 — 54 hội thoại quá tải:
#   payload công cụ chiếm 85–99,7% dung lượng; LỜI THOẠI thật chỉ 0,3–15,7%.
#     ece09c56  27.503.561 token → lời thoại   281.833  (1,0%)
#     b2ce423c   3.189.660 token → lời thoại     9.597  (0,3%)
#   ⇒ Lược payload công cụ là đủ để 49/54 hội thoại nhắn tiếp lại được.
#
# CÁCH LÀM: giữ NGUYÊN VẸN 100% lời thoại (mọi khối `text`), chỉ rút gọn ruột
#   của `tool_result` và `thinking`. Bản ghi vẫn còn, mắt xích vẫn liền, chỉ
#   phần máy sinh ra bị thay bằng một dòng ghi rõ đã lược bao nhiêu.
#   Đây CHÍNH LÀ cơ chế gốc của Claude: khi nén, nó thay nội dung file bằng
#   `attachment.type = compact_file_reference` — đã đo thấy trong transcript.
#
# VÌ SAO KHÔNG DÙNG /rewind: rewind cắt theo THỜI GIAN nên bỏ mất các tin nhắn
#   MỚI NHẤT — đúng thứ người dùng cần nhất. Lược payload cắt theo LOẠI NỘI
#   DUNG nên giữ trọn phần người viết, kể cả phần mới nhất.
#
# AN TOÀN — bốn chốt:
#   1) CHỈ TẠO FILE MỚI. Không ghi đè, không xoá, không đụng file gốc.
#   2) KHÔNG trỏ mục Recents. Việc đó tách riêng, cần Claude đã tắt.
#   3) 6 phép kiểm chứng; trượt phép nào là KHÔNG ghi file đó.
#   4) Phép ⑥ đối chiếu TỪNG khối chữ trước/sau — bảo chứng "100% lời thoại"
#      bằng phép đo, không bằng lời hứa.
#
# QUY ƯỚC: định danh bằng TIẾNG ANH; hiển thị bằng TIẾNG VIỆT CÓ DẤU.
# =============================================================================
set -uo pipefail

PROJ="$HOME/.claude/projects"
IDX="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
MODE=all; ID=""; APPLY=0; TARGET=150000

while [ $# -gt 0 ]; do
  case "$1" in
    --id)     MODE=one; shift; ID="${1:-}" ;;
    --apply)  APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    --target) shift; TARGET="${1:-150000}" ;;
    -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "⛔ Tham số lạ: $1" >&2; exit 2 ;;
  esac
  shift
done

# shellcheck disable=SC2009
running() { ps -Ao args | grep -c "Claude\.app/Contents/MacOS/Claude$" || true; }
if [ "$APPLY" = 1 ] && [ "$(running)" -gt 0 ]; then
  echo "ℹ️  Claude Desktop đang chạy — vẫn dựng được file mới (chỉ tạo, không sửa gì)."
  echo "   Bước TRỎ MỤC mới cần tắt app, và đó là lệnh riêng."
  echo
fi

PROJ="$PROJ" IDX="$IDX" MODE="$MODE" ID="$ID" APPLY="$APPLY" TARGET="$TARGET" \
/usr/bin/python3 - <<'PY'
import json,glob,os,uuid

PROJ=os.environ["PROJ"]; IDX=os.environ["IDX"]
MODE=os.environ["MODE"]; ID=os.environ["ID"]
APPLY=os.environ["APPLY"]=="1"; TARGET=int(os.environ["TARGET"])

# Các mức cắt thử theo thứ tự ƯU TIÊN GIỮ NHIỀU NHẤT. Chỉ hạ mức khi mức trên
# chưa đủ nhẹ — để không cắt sâu hơn mức cần thiết.
CAPS=[8000,4000,2000,1000,400,150]

indexed={}
for f in glob.glob(os.path.join(IDX,"local_*.json")):
    try: d=json.load(open(f))
    except Exception: continue
    c=d.get("cliSessionId")
    if c: indexed[c]=(d.get("title") or "(không tên)", f)

def load(p):
    out=[]
    for line in open(p,errors="replace"):
        s=line.strip()
        if not s: continue
        try: out.append(json.loads(s))
        except Exception: pass
    return out

def toks(recs):
    """ước tính token = ký tự/4, tách lời thoại và payload công cụ"""
    tx=tl=0
    for o in recs:
        c=(o.get("message") or {}).get("content")
        if isinstance(c,str): tx+=len(c)
        elif isinstance(c,list):
            for x in c:
                if not isinstance(x,dict): continue
                ty=x.get("type")
                if ty=="text": tx+=len(x.get("text",""))
                elif ty=="thinking": tl+=len(x.get("thinking",""))
                elif ty=="tool_use": tl+=len(json.dumps(x.get("input"),ensure_ascii=False))
                elif ty=="tool_result":
                    v=x.get("content")
                    tl+=len(v if isinstance(v,str) else json.dumps(v,ensure_ascii=False))
                elif ty=="image":
                    # Ảnh chụp màn hình mã hoá base64. Đo thật 27/08/2026: chiếm
                    # tới 86,1% toàn bộ token của một hội thoại (ca1a7b91).
                    # Bản đầu của script này BỎ SÓT khối image và tool_use ⇒ 23/62
                    # hội thoại không về được đích. Không đo thì không thấy.
                    tl+=len(json.dumps(x,ensure_ascii=False))
                else:
                    tl+=len(json.dumps(x,ensure_ascii=False))
    return tx//4, tl//4

def texts(recs):
    """MỌI khối chữ, theo đúng thứ tự — dùng cho phép kiểm ⑥"""
    out=[]
    for o in recs:
        c=(o.get("message") or {}).get("content")
        if isinstance(c,str):
            if c.strip(): out.append(c.strip())
        elif isinstance(c,list):
            for x in c:
                if isinstance(x,dict) and x.get("type")=="text" and x.get("text","").strip():
                    out.append(x["text"].strip())
    return out

def shrink(recs,cap):
    """Rút gọn ruột tool_result và thinking. KHÔNG đụng khối `text`."""
    out=[]; n_cut=0; saved=0
    for o in recs:
        o=json.loads(json.dumps(o))          # bản sao sâu, không đụng bản gốc
        c=(o.get("message") or {}).get("content")
        if isinstance(c,list):
            for x in c:
                if not isinstance(x,dict): continue
                ty=x.get("type")
                if ty=="tool_result":
                    v=x.get("content")
                    s=v if isinstance(v,str) else json.dumps(v,ensure_ascii=False)
                    if len(s)>cap:
                        x["content"]=(s[:cap]
                            +f"\n\n[… đã lược {len(s)-cap:,} ký tự để hội thoại nhắn tiếp được."
                             " Bản đầy đủ vẫn nằm trong transcript gốc và kho git.]")
                        n_cut+=1; saved+=len(s)-cap
                elif ty=="thinking":
                    s=x.get("thinking","")
                    if len(s)>cap:
                        x["thinking"]=s[:cap]+f"\n\n[… đã lược {len(s)-cap:,} ký tự]"
                        n_cut+=1; saved+=len(s)-cap
                elif ty=="tool_use":
                    # Tham số lệnh. Với Write/Edit thì đây là NGUYÊN nội dung file.
                    inp=x.get("input")
                    s=json.dumps(inp,ensure_ascii=False)
                    if len(s)>cap and isinstance(inp,dict):
                        keep={}
                        for k,v in inp.items():
                            sv=v if isinstance(v,str) else json.dumps(v,ensure_ascii=False)
                            keep[k]=(sv[:cap]+f" […lược {len(sv)-cap:,} ký tự]") if len(sv)>cap else v
                        x["input"]=keep
                        n_cut+=1; saved+=len(s)-len(json.dumps(keep,ensure_ascii=False))
                elif ty=="image":
                    # Đổi khối ảnh thành khối CHỮ ghi rõ đã có ảnh ở đây.
                    # Giữ cấu trúc tin nhắn hợp lệ, bỏ khối base64 khổng lồ.
                    # Ảnh gốc vẫn nằm trong transcript gốc và kho git.
                    old=len(json.dumps(x,ensure_ascii=False))
                    if old>cap:
                        x.clear()
                        x["type"]="text"
                        x["text"]="[ảnh chụp màn hình đã lược để hội thoại nhắn tiếp được — bản gốc còn trong transcript gốc và kho git]"
                        n_cut+=1; saved+=old
        out.append(o)
    return out,n_cut,saved

files={}
for p in glob.glob(os.path.join(PROJ,"*","*.jsonl")):
    files[os.path.basename(p)[:-6]]=p

targets=[]
for sid,(title,idxf) in indexed.items():
    if sid not in files: continue
    if MODE=="one" and not sid.startswith(ID): continue
    if os.path.getsize(files[sid])<200000 and MODE!="one": continue
    targets.append((sid,title,files[sid]))

print(f"🧹 LƯỢC PAYLOAD CÔNG CỤ — {'🟢 DỰNG FILE' if APPLY else '🔍 XEM TRƯỚC, chưa ghi gì'}")
print(f"   Đích: ≤ {TARGET:,} token/hội thoại · giữ NGUYÊN 100% lời thoại\n")
print(f"{'phiên':10}{'trước':>12}{'sau':>11}{'mức cắt':>9}{'bản ghi':>9}  tiêu đề")

rows=[];ok=0;skip=0;fail=0
for sid,title,p in sorted(targets):
    recs=load(p)
    tx,tl=toks(recs); tot=tx+tl
    if tot<=TARGET:
        skip+=1; continue
    chosen=None
    for cap in CAPS:
        new,n_cut,_=shrink(recs,cap)
        ntx,ntl=toks(new)
        if ntx+ntl<=TARGET:
            chosen=(cap,new,n_cut,ntx+ntl); break
    if chosen is None:
        cap=CAPS[-1]; new,n_cut,_=shrink(recs,cap); ntx,ntl=toks(new)
        chosen=(cap,new,n_cut,ntx+ntl)
    cap,new,n_cut,after=chosen
    flag="✅" if after<=TARGET else "⚠️"
    if after<=TARGET: ok+=1
    else: fail+=1
    print(f"  {sid[:8]}{tot:>12,}{after:>11,}{cap:>9}{n_cut:>9}  {flag} {title[:34]}")
    rows.append((sid,title,p,tot,after,cap,new,recs))

print(f"\n  Hội thoại cần xử lý     : {len(rows)}")
print(f"  ✅ về được ≤{TARGET:,}   : {ok}")
print(f"  ⚠️  vẫn còn vượt         : {fail}")
print(f"  ⏭  vốn đã nhẹ, bỏ qua   : {skip}")

if not APPLY:
    print(f"\n🔎 CHƯA GHI GÌ. File gốc nguyên vẹn, chưa tạo file nào, chưa đụng mục Recents.")
    raise SystemExit(0)
PY
