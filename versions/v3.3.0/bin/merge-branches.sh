#!/usr/bin/env bash
# =============================================================================
# merge-branches.sh   (v3.3.0)
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
#   merge-branches.sh --id <8-ký-tự> --apply --point
#       dựng file RỒI TRỎ mục Recents sang nó, trong CÙNG một lệnh.
#   merge-branches.sh --id <mã> --apply --since 2026-07-01 --until 2026-07-31 \
#                     --title-suffix "(07/2026)"
#       gộp MỘT GIAI ĐOẠN và đặt tên riêng cho nó. Tên riêng là BẮT BUỘC nếu muốn
#       giai đoạn đó có mục Recents riêng — xem ghi chú ở chỗ xử lý --title-suffix.
#       Đòi hỏi Claude Desktop đã tắt — và chính vì app đã tắt nên KHÔNG có tin
#       nhắn mới nào sinh ra giữa hai việc ⇒ không mất đoạn nào.
# =============================================================================
set -uo pipefail
PROJ="$HOME/.claude/projects"
IDX="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
MODE=list; ID=""; APPLY=0; FORCE=0; POINT=0; REPOINT=0; ALLOWRN=0
SINCE=""; UNTIL=""; TSUFFIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list)  MODE=list ;;
    --ids)   MODE=ids ;;
    --id)    MODE=one; shift; ID="${1:-}" ;;
    --apply) APPLY=1 ;;
    --point) POINT=1 ;;
    --repoint) REPOINT=1 ;;   # chỉ TRỎ sang nhánh sẵn có, KHÔNG dựng file
    --allow-rename) ALLOWRN=1 ;;  # chấp nhận đổi tên khi trỏ sang nhánh tên khác
    --force) FORCE=1 ;;
    --since) shift; SINCE="${1:-}" ;;
    --until) shift; UNTIL="${1:-}" ;;
    --title-suffix) shift; TSUFFIX="${1:-}" ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Tham số lạ: $1"; exit 2 ;;
  esac
  shift
done
PROJ="$PROJ" IDX="$IDX" MODE="$MODE" ID="$ID" APPLY="$APPLY" FORCE="$FORCE" POINT="$POINT" \
SINCE="${SINCE:-}" UNTIL="${UNTIL:-}" TSUFFIX="${TSUFFIX:-}" REPOINT="$REPOINT" ALLOWRN="$ALLOWRN" /usr/bin/python3 - <<'PY'
import json,glob,os,uuid,hashlib,collections,datetime,shutil
PROJ=os.environ["PROJ"]; IDX=os.environ["IDX"]
MODE=os.environ["MODE"]; ID=os.environ["ID"]; APPLY=os.environ["APPLY"]=="1"
POINT=os.environ.get("POINT")=="1"
REPOINT=os.environ.get("REPOINT")=="1"
ALLOWRN=os.environ.get("ALLOWRN")=="1"

def _claude_running():
    """CỐ Ý dùng `ps -Ao args`, KHÔNG dùng `pgrep`: đo thực tế trên macOS,
    `pgrep -x Claude` trả về 0 tiến trình trong khi Claude Desktop ĐANG chạy."""
    import subprocess
    out=subprocess.run(["ps","-Ao","args"],capture_output=True).stdout.decode()
    return any(l.rstrip().endswith("Claude.app/Contents/MacOS/Claude") for l in out.split("\n"))

# Chặn SỚM: nếu định trỏ mục mà app đang chạy thì báo ngay, đừng dựng file 20 MB
# rồi mới từ chối — file đó sẽ thành một nhánh thừa nằm lại trên đĩa.
if POINT and _claude_running():
    print("⛔ Claude Desktop ĐANG CHẠY — không thể trỏ mục Recents.")
    print("   Thoát app trước rồi chạy lại:")
    print("     claude-history quit")
    print("     claude-history merge --id <mã> --apply --point")
    raise SystemExit(1)
FORCE=os.environ.get("FORCE")=="1"
SINCE=os.environ.get("SINCE","").strip(); UNTIL=os.environ.get("UNTIL","").strip()
TSUFFIX=os.environ.get("TSUFFIX","").strip()
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

if MODE=="ids":
    # Đầu ra ĐỌC-MÁY: mỗi dòng một chuỗi, KHÔNG cắt ở 25 như --list.
    # clig.dev: người đọc là mặc định, máy đọc thì phải xin.
    # 4 cột, ngăn bằng TAB:  mã · tên · MB nguồn · số nhánh
    # Tên để fix-all in cho người đọc hiểu (mã 8 ký tự không nói lên hội thoại nào).
    # MB nguồn để fix-all lọc trước chuỗi quá lớn mà KHÔNG phải dựng thử —
    # dựng thử rồi mới từ chối tốn ~2,5 phút mỗi lượt (đo thật 26/08 với 58dfea02).
    # Tiêu đề đã bị loại mọi ký tự TAB/xuống dòng để không vỡ cột.
    for miss,t,cur,sids,n,u in todo:
        mb=sum(os.path.getsize(files[s]) for s in sids)//1048576
        safe=" ".join(str(t).split())
        print(f"{cur}\t{safe}\t{mb}\t{len(sids)}")
    raise SystemExit(0)

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

# ── --repoint: TRỎ sang nhánh SẴN CÓ, KHÔNG dựng file  ⭐ v3.3.0 ────────────
# VÌ SAO ĐÂY LÀ MẶC ĐỊNH MỚI: đo 27/08/2026 cho thấy Claude Desktop xử lý hội
# thoại rất dài bằng cách NÉN TẠI CHỖ, giữ đúng MỘT mục Recents —
#     REDANCE-1715: 715 file trên đĩa · 1 mục trong danh sách
#     compact_boundary: preTokens 924.674 → postTokens 14.801  (giảm 62 lần)
# Việc app KHÔNG tự làm là: sau khi thoát/mở lại, mục Recents tụt về nhánh cũ.
# Chỉ cần TRỎ lại là xong — không cần gộp.
#
# Trỏ hơn hẳn gộp ở mọi mặt đo được:
#   · không tạo file  · ctx giữ nguyên  · tức thì  · hoàn tác bằng một lệnh cp
#   · nhánh app tự sinh CHƯA BAO GIỜ chết; chỉ bản gộp mới có lần chết (ece09c56)
# Đo thật: gộp 58dfea02 cho 13.377 đoạn chữ nhưng trần hiển thị 48 MiB chỉ cho
# thấy 550 (4%) — đổi 274 lấy 550 kèm file 554 MB là không đáng.
if REPOINT:
    # Chốt "app đang chạy" chỉ áp cho lúc GHI. Xem trước là chỉ đọc, phải chạy
    # được khi app đang mở — nếu không thì không ai xem trước được bao giờ.
    if APPLY and _claude_running():
        print("⛔ Claude Desktop ĐANG CHẠY — không thể trỏ mục Recents.")
        print("   Thoát trước:  claude-history quit")
        raise SystemExit(1)
    # ── QUY TẮC BA TẦNG  ⭐ v3.3.0 ──────────────────────────────────────────
    # YÊU CẦU DUY NHẤT của người dùng: sau khi khởi động lại Claude Desktop,
    # KHÔNG mất tin nhắn nào — nhất là tin vừa mới nhắn.
    #
    # VÌ SAO KHÔNG chọn "nhánh giàu nhất" như bản trước: đo 27/08/2026 cho thấy
    # mỗi nhánh chỉ chứa MỘT LÁT thời gian, không chép lại nội dung cũ —
    #     d5bc396e  09:47 → 15:24   1.378 bản ghi
    #     c929c1c8  16:27 → 16:31   1.328 bản ghi   ← lát MỚI NHẤT, gầy
    # Nhánh giàu nhất thường là bản gộp cũ, KHÔNG chứa lát mới. Chọn nó là
    # mất đúng phần vừa nhắn — chính lỗi người dùng gặp mỗi lần mở lại.
    #
    # Tầng ①: chỉ xét nhánh CÓ CHỨA bản ghi mới nhất của cả chuỗi (ràng buộc CỨNG)
    # Tầng ②: trong số đó, chọn nhánh nhiều đoạn nội dung nhất
    # Tầng ③: không nhánh nào chứa nó ⇒ báo cần GỘP (thoát mã 2 để fix biết)
    _newest_ts=""; _newest_key=None
    for _s in sids:
        for _o in lines_of(_s):
            _ts=_o.get("timestamp") or ""
            if _ts>_newest_ts:
                _k=key_of(_o)
                if _k: _newest_ts=_ts; _newest_key=_k
    _have=[s for s in sids if _newest_key and _newest_key in get(s)[1]]
    if not _have:
        print(f"   ⚠️  KHÔNG nhánh nào chứa bản ghi mới nhất ({_newest_ts[:16].replace('T',' ')}).")
        print(f"      Trỏ thôi là chưa đủ — cần GỘP:")
        print(f"      claude-history merge --id {cur[:8]} --apply --point")
        raise SystemExit(2)
    # Trong số các nhánh CÓ CHỨA tin mới nhất, chọn nhánh giàu nội dung nhất.
    # Thứ tự hai điều kiện này là điểm mấu chốt — đo 27/08/2026 trên 41 hội thoại:
    #     chọn giàu nhất TRƯỚC, không lọc  → 37/41 đủ tin mới  (4 ca THIẾU)
    #     LỌC theo tin mới rồi mới chọn giàu → 41/41 đủ tin mới (0 ca thiếu)
    # Bốn ca hỏng đều cùng dạng: nhánh giàu là bản CŨ đã bị nén thay thế.
    #     phong thủy   : giàu ece09c56 (6033 đoạn) · mới 2b56a0b7 (77 đoạn)
    #     redance-1715 : giàu 48a90b72 (2121 đoạn) · mới 9deec795 (1084 đoạn)
    # Đây chính là cách app tự làm: mục luôn trỏ vào đoạn ĐANG TIẾP DIỄN.
    # ── TẦNG ②b: BẢO TOÀN TÊN NGƯỜI DÙNG ĐẶT  ⭐ v3.3.0 ────────────────────
    # SỰ CỐ 30/08/2026: người dùng fork một hội thoại rồi ĐỔI TÊN để phân biệt
    #   "REDANCE-1715 Mail investigation (fork) - feedbacks 27/08"
    # `--repoint` trỏ sang nhánh MỚI NHẤT (d38c08e9) — nhánh đó mang tiêu đề
    # CHUNG "…(fork)", nên app hiển thị lại tên chung. Tên tự đặt biến mất.
    # Repoint KHÔNG ghi đè trường title (bak chứng minh: chỉ đổi lastActivityAt);
    # tên đổi vì app đọc tiêu đề TỪ TRANSCRIPT của nhánh đang trỏ.
    #
    # Quy tắc: chỉ trỏ trong phạm vi CÙNG TIÊU ĐỀ với mục hiện tại. Khi phải
    # chọn giữa "giữ tên" và "lấy tin mới nhất tuyệt đối", script KHÔNG tự quyết
    # — nó dừng và đưa người dùng số liệu. Đây là bài học lặp lại nhiều lần:
    # tối ưu một ràng buộc rồi âm thầm bỏ mất ràng buộc kia.
    _cur_title=(get(cur)[0] or "").strip()
    _same_name=[s for s in _have if (get(s)[0] or "").strip()==_cur_title]
    if ALLOWRN: _same_name=_have
    if _same_name:
        _pool=_same_name
        if len(_same_name)<len(_have):
            print(f"   giữ tên hiện tại: {_cur_title[:50]!r}")
            print(f"      bỏ qua {len(_have)-len(_same_name)} nhánh mang tên khác")
    else:
        # ── MANG TÊN THEO SANG NHÁNH MỚI  ⭐ v3.3.0 ────────────────────────
        # Không phải chọn giữa "giữ tên" và "lấy tin mới" — làm được cả hai.
        # App lưu tên hiển thị bằng bản ghi `custom-title` NGAY TRONG transcript
        # (3 khoá: type · sessionId · customTitle), và ghi lại nhiều lần rải rác
        # trong file — dòng cuối cùng thắng. Nên NỐI THÊM một dòng như vậy vào
        # cuối nhánh đích là đúng cơ chế app, không phải mẹo.
        #
        # SỰ CỐ 30/08/2026: repoint kéo mục từ 6ac60748 (mang tên người dùng đặt
        # "…(fork) - feedbacks 27/08") sang d38c08e9 (tên chung) vì d38c08e9 chứa
        # tin mới nhất. Tên tự đặt biến mất khỏi danh sách.
        #
        # AN TOÀN: chỉ NỐI THÊM một dòng ở cuối, KHÔNG sửa dòng nào có sẵn.
        # Hoàn tác = xoá dòng cuối. Bản gốc còn trong kho git.
        _alt=max(_have, key=lambda s:(len(get(s)[1]), get(s)[3]))
        _alt_title=(get(_alt)[0] or "").strip()
        print(f"\n   ⚠️  Nhánh chứa tin mới nhất mang TÊN KHÁC:")
        print(f"      tên bạn đang dùng : {_cur_title[:56]!r}")
        print(f"      tên nhánh mới     : {_alt_title[:56]!r}")
        if not _cur_title:
            print(f"      ⛔ mục hiện tại không có tiêu đề — không mang theo được.")
            raise SystemExit(3)
        print(f"      → MANG TÊN THEO sang nhánh mới (nối 1 dòng vào cuối transcript)")
        if not APPLY:
            print(f"\n🔎 Xem trước — chưa ghi. Thêm --apply để trỏ.")
            raise SystemExit(0)
        # Chốt: ghi vào transcript khi app đang chạy là tranh chấp với chính app
        # (nó cũng đang ghi vào file đó). Mọi thao tác ghi khác đã có chốt này;
        # đường MANG TÊN THEO bị bỏ sót vì nó thêm sau.
        if _claude_running():
            print(f"      ⛔ Claude Desktop ĐANG CHẠY — không ghi vào transcript.")
            print(f"         Thoát trước:  claude-history quit")
            raise SystemExit(3)
        # THỨ TỰ QUAN TRỌNG: kiểm mục Recents tồn tại TRƯỚC khi ghi transcript.
        # Ghi xong mới phát hiện không trỏ được thì transcript đã bẩn một dòng
        # mà chẳng được gì — và người dùng không biết để dọn.
        _tgt=None
        for _f in glob.glob(os.path.join(IDX,"local_*.json")):
            try: _d=json.load(open(_f))
            except Exception: continue
            if _d.get("cliSessionId")==cur: _tgt=_f; break
        if not _tgt:
            print(f"      ⛔ Không thấy mục Recents nào trỏ vào {cur[:8]} — không trỏ được.")
            print(f"         KHÔNG ghi gì vào transcript.")
            raise SystemExit(3)
        _rec={"type":"custom-title","sessionId":_alt,"customTitle":_cur_title}
        _path=files[_alt]
        _before=os.path.getsize(_path)
        try:
            with open(_path,"a") as _fh:
                _fh.write(json.dumps(_rec,ensure_ascii=False)+"\n")
            print(f"      ✅ đã ghi tên vào {_alt[:8]}")
            print(f"         hoàn tác: truncate -s {_before} '{_path}'")
        except Exception as _e:
            print(f"      ⛔ không ghi được tên: {_e}")
            raise SystemExit(3)
        _pool=[_alt]
    best=max(_pool, key=lambda s:(len(get(s)[1]), get(s)[3]))
    print(f"   tin nhắn mới nhất: {_newest_ts[:16].replace('T',' ')} · {len(_have)}/{len(sids)} nhánh có chứa")
    # Trỏ đúng nhánh rồi NHƯNG mốc thời gian có thể vẫn lệch ⇒ mục chìm đáy.
    # Không được thoát sớm ở đây: phải đi tiếp để đồng bộ lastActivityAt.
    _same = (best==cur)
    if _same:
        print(f"   ✅ mục đã trỏ đúng nhánh — kiểm tiếp mốc thời gian.")
    if not _same:
        b_all=len(get(best)[1]); b_txt=len(get(best)[2])
        print(f"   → trỏ sang {best[:8]}  ({b_all} đoạn · {b_txt} đoạn CHỮ)")
        print(f"     thay cho {cur[:8]}  ({n} đoạn · {_tn} đoạn CHỮ)")
    if not APPLY:
        print(f"\n🔎 Xem trước — chưa ghi. Thêm --apply để trỏ.")
        raise SystemExit(0)
    target=None
    for f in glob.glob(os.path.join(IDX,"local_*.json")):
        try: d=json.load(open(f))
        except Exception: continue
        if d.get("cliSessionId")==cur: target=(f,d); break
    if not target:
        print(f"⛔ Không thấy mục Recents nào trỏ vào {cur[:8]}."); raise SystemExit(1)
    f,d=target
    bak=f+".bak-"+datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    shutil.copy2(f,bak)
    d["cliSessionId"]=best
    # ── ĐỒNG BỘ lastActivityAt  ⭐ v3.3.0 ───────────────────────────────────
    # App sắp xếp danh sách Recents theo lastActivityAt. Trỏ đúng nhánh mà để
    # mốc này cũ thì hội thoại CHÌM XUỐNG ĐÁY — có đủ nội dung nhưng không tìm
    # ra, tức là "mất" theo nghĩa người dùng. Đo 27/08/2026: 5 mục lệch tới
    # 3,3 ngày. Đây là bước app tự làm mỗi khi ghi tin nhắn; mô phỏng lại cho đủ.
    _ts=get(best)[3]
    if _ts:
        try:
            _ms=int(datetime.datetime.fromisoformat(_ts.replace("Z","+00:00")).timestamp()*1000)
            if _ms>(d.get("lastActivityAt") or 0):
                d["lastActivityAt"]=_ms
                d["lastFocusedAt"]=max(d.get("lastFocusedAt") or 0,_ms)
                print(f"   đồng bộ lastActivityAt → {_ts[:16].replace('T',' ')}")
        except Exception:
            pass
    json.dump(d,open(f,"w"),ensure_ascii=False,indent=2)
    if _same:
        print(f"\n✅ Đã đồng bộ mốc thời gian. KHÔNG tạo file nào.")
    else:
        print(f"\n✅ Đã trỏ mục Recents sang nhánh đầy đủ nhất. KHÔNG tạo file nào.")
    print(f"   Hoàn tác: cp '{bak}' '{f}'")
    raise SystemExit(0)

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

# ── BẢO TOÀN ĐIỂM CẮT NGỮ CẢNH  ⭐ SỬA LỖI NGHIÊM TRỌNG NHẤT (v3.3.0) ────────
# Bản v3.1.0–v3.2.0 nối MỌI bản ghi thành một chuỗi parentUuid thẳng:
#       o["parentUuid"]=prev; prev=o["uuid"]
# Việc đó GHI ĐÈ parentUuid=None tại các bản ghi `compact_boundary` — mà chính
# giá trị None đó là ĐIỂM CẮT app dùng để quyết định gửi bao nhiêu ngữ cảnh.
#
# Bằng chứng đọc từ chính transcript (58dfea02, 25/08/2026 17:59):
#     type              system / compact_boundary
#     parentUuid        None            ← điểm cắt
#     logicalParentUuid 2f2de111…       ← chuỗi HIỂN THỊ, đi xuyên qua ranh giới
#     preTokens         924.674         ← ctx TRƯỚC khi cắt
#     postTokens         14.801         ← ctx SAU khi cắt
#     cumulativeDroppedTokens 13.088.700
#
# Xoá điểm cắt ⇒ app không còn chỗ nào để dừng ⇒ phải gửi cả 13 triệu token đã
# bị bỏ ⇒ vỡ trần ngữ cảnh. Đo thật: ece09c56 sau khi gộp KHÔNG nhắn tiếp được
# nữa, trong khi ae968d22 (51 MB, cùng hội thoại, chưa gộp) vẫn nhắn bình thường.
#
# Nên: đi qua compact_boundary thì KHÔNG nối, GIỮ NGUYÊN parentUuid=None và
# logicalParentUuid. Chuỗi trở thành nhiều đoạn — đúng như app tự sinh ra.
def _is_boundary(o):
    return o.get("type")=="system" and o.get("subtype")=="compact_boundary"

prev=None; _kept=0; _fixed=0
for o in final:
    if "sessionId" in o: o["sessionId"]=NEW
    if not o.get("uuid"): continue
    if _is_boundary(o):
        # KHÔI PHỤC bất biến: app LUÔN ghi parentUuid=None cho compact_boundary.
        # Các file đã bị gộp bởi v3.1.0–v3.2.0 mang sẵn điểm cắt HỎNG (parentUuid
        # bị ghi đè thành uuid). Gộp lại mà chỉ "giữ nguyên" thì thừa hưởng cái
        # hỏng đó. Nên ép về None — đây là SỬA CHỮA, không phải phá.
        if o.get("parentUuid") is not None:
            o["parentUuid"]=None; _fixed+=1
        # logicalParentUuid giữ nguyên: đó là chuỗi HIỂN THỊ, đi xuyên ranh giới.
        prev=o["uuid"]; _kept+=1
        continue
    o["parentUuid"]=prev; prev=o["uuid"]
if _kept:
    _msg=f"   giữ {_kept} điểm cắt ngữ cảnh (compact_boundary)"
    if _fixed: _msg+=f" · KHÔI PHỤC {_fixed} điểm cắt bị bản cũ làm hỏng"
    print(_msg)

# ── --title-suffix: ĐẶT TÊN RIÊNG cho bản hợp nhất ───────────────────────────
# VÌ SAO CẦN: gộp theo giai đoạn cho ra nhiều file, nhưng cả ba script tạo mục
# đều khoá theo (dự án, TIÊU ĐỀ) — một hội thoại chỉ được một mục:
#   restore-lost-entries.sh  "nhóm đã có mục → không đụng"
#   repair-missing-sessions  "cùng hội thoại với mục đã có"  + CHỐT SỐ 2
# Ba chốt đó chính là thứ đã chặn vụ đẻ 555 mục rác 12/08 — KHÔNG được nới.
# Nên muốn mỗi giai đoạn có mục riêng thì phải cho nó một TÊN riêng thật sự.
# Chỉ sửa tiêu đề của FILE MỚI. Nhánh nguồn không bị đụng tới.
if TSUFFIX:
    _done=False
    for o in final:
        if o.get("type")=="custom-title" and o.get("customTitle"):
            o["customTitle"]=f"{o['customTitle']} {TSUFFIX}"; _done=True
        elif o.get("type")=="ai-title" and o.get("aiTitle"):
            o["aiTitle"]=f"{o['aiTitle']} {TSUFFIX}"; _done=True
    if not _done:
        print(f"\n⛔ --title-suffix: không thấy bản ghi tiêu đề nào để đổi tên.")
        raise SystemExit(1)
    print(f"   tên bản hợp nhất: … {TSUFFIX}")

# ── 9 phép kiểm chứng ──
uu={o["uuid"] for o in final if o.get("uuid")}
dang=[o for o in final if o.get("parentUuid") and o["parentUuid"] not in uu]
root=[o for o in final if "parentUuid" in o and o["parentUuid"] is None]
sids_set={o.get("sessionId") for o in final if o.get("sessionId")}
ts=[o["timestamp"] for o in final if o.get("timestamp")]
child=collections.defaultdict(list)
for o in final:
    if o.get("parentUuid"): child[o["parentUuid"]].append(o["uuid"])
# v3.3.0: sau khi bảo toàn compact_boundary thì file có NHIỀU gốc — đó là ĐÚNG,
# giống hệt file app tự sinh. Duyệt từ MỌI gốc, không chỉ một.
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
 # v3.3.0: mỗi compact_boundary mở một đoạn mới ⇒ số gốc = 1 + số ranh giới.
 # Đòi đúng 1 gốc là SAI kể từ khi bảo toàn điểm cắt.
 ("④ số gốc khớp số điểm cắt", len(root)==1+sum(1 for o in final if o.get("type")=="system" and o.get("subtype")=="compact_boundary"),
   f"{len(root)} gốc"),
 ("⑤ đi hết chuỗi từ gốc", len(seen)==len(uu), f"{len(seen)}/{len(uu)}"),
 ("⑥ có bản ghi tiêu đề", any(o.get("type") in ("custom-title","ai-title") for o in final), ""),
 ("⑦ thời gian tăng dần", ts==sorted(ts), ""),
 # v3.3.0 — phép kiểm SỐNG CÒN: mọi compact_boundary phải còn parentUuid=None.
 # Trượt phép này nghĩa là đã tái phạm đúng lỗi giết ece09c56.
 ("⑩ điểm cắt ngữ cảnh nguyên vẹn",
   all(o.get("parentUuid") is None for o in final
       if o.get("type")=="system" and o.get("subtype")=="compact_boundary"),
   f"{sum(1 for o in final if o.get('type')=='system' and o.get('subtype')=='compact_boundary')} điểm cắt"),
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

# ── --point: TRỎ MỤC RECENTS NGAY, trong CÙNG một lệnh ───────────────────────
# Sự cố 26/08/2026: quy trình cũ là 3 lệnh rời — merge → quit → fix-stale. Mọi
# tin nhắn gửi trong khoảng giữa merge và fix-stale rơi vào nhánh CŨ và mất lối
# vào (đo thật: 3 đoạn mất). Gọi đó là CỬA SỔ CHẾT.
# Chạy khi app ĐÃ TẮT thì không có tin nhắn mới nào sinh ra ⇒ cửa sổ chết = 0.
if POINT:
    target=None
    for f in glob.glob(os.path.join(IDX,"local_*.json")):
        try: d=json.load(open(f))
        except Exception: continue
        if d.get("cliSessionId")==cur: target=(f,d); break
    if not target:
        print(f"\n⛔ Không thấy mục Recents nào trỏ vào {cur[:8]} — không trỏ được.")
        raise SystemExit(1)
    f,d = target
    stamp=datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    bak=f+".bak-"+stamp
    shutil.copy2(f,bak)
    d["cliSessionId"]=NEW
    json.dump(d,open(f,"w"),ensure_ascii=False,indent=2)
    print(f"\n✅ Đã trỏ mục Recents sang bản hợp nhất.")
    print(f"   {d.get('title')}")
    print(f"   Hoàn tác: cp '{bak}' '{f}'")
    print(f"\n   Mở lại Claude Desktop để xem.")
    raise SystemExit(0)
# In SẴN mã phiên đúng. Sự cố 26/08/2026: hướng dẫn đưa mã của chuỗi (--id) sang
# cho --only, nhưng hai cờ này dùng HAI KHÔNG GIAN MÃ khác nhau — --only khớp theo
# phiên mà MỤC ĐANG MỞ. Gõ nhầm thì fix-stale báo "không mục nào khớp".
print(f"\nBước tiếp — trỏ mục Recents sang bản này.")
print(f"   ⚠️  Mọi tin nhắn gửi TỪ GIỜ tới lúc trỏ sẽ rơi vào nhánh cũ và mất lối vào.")
print(f"   Cách an toàn — thoát app rồi dựng + trỏ trong MỘT lệnh:")
print(f"     claude-history quit")
print(f"     claude-history merge --id {cur[:8]} --apply --point")
print(f"\nHoàn tác: rm '{dest}'")
PY
