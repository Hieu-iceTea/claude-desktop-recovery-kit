#!/usr/bin/env bash
# =============================================================================
# repair-missing-sessions.sh   (v2.3.1)
#
# Đưa lại vào Recents những hội thoại CÒN NỘI DUNG nhưng KHÔNG có mục chỉ mục.
#
# Vì sao cần: Recents đọc từ claude-code-sessions-shared/local_*.json, mỗi mục
# trỏ tới một cliSessionId. Transcript .jsonl không được mục nào trỏ tới thì
# thành "mồ côi" — nội dung còn nguyên nhưng app không hiển thị.
#
# TỰ DÒ, không chép cứng danh sách → bắt được cả phiên vừa tạo xong.
#
# BỎ QUA (không phục hồi):
#   • phiên đã có mục trong Recents
#   • phiên bạn CỐ Ý XOÁ trong app (có file deleted_<id>) ← tôn trọng ý bạn
#   • bản rẽ nhánh cũ đã bị thay thế (cùng tiêu đề, có bản mới hơn)
#   • phiên rỗng / quá ngắn
#
# AN TOÀN:
#   • CHỈ TẠO file mới. Không sửa, không xoá mục chỉ mục nào đang có.
#   • Mặc định XEM TRƯỚC. Phải có --apply mới ghi.
#   • Chặn khi Claude Desktop đang chạy (bắt buộc với --apply).
#   • Hoàn tác = xoá đúng file vừa tạo (script in sẵn lệnh).
#
# Cách dùng:
#   repair-missing-sessions.sh                 # xem trước, 30 ngày gần đây
#   repair-missing-sessions.sh --apply         # thực thi (sau khi Cmd+Q)
#   repair-missing-sessions.sh --since 90      # nới cửa sổ thời gian
#   repair-missing-sessions.sh --all           # không giới hạn thời gian
#   repair-missing-sessions.sh --scan          # liệt kê MỌI mồ côi (chỉ đọc)
#
# CHẾ ĐỘ --fix-stale (khác hẳn: SỬA mục đang có, không tạo mục mới)
#   Dùng khi mục Recents vẫn còn nhưng trỏ vào bản rẽ nhánh CŨ — mở ra thấy
#   trạng thái cũ, thiếu phần hội thoại mới. Có backup + lệnh hoàn tác.
#   Cũng KHÔNG BAO GIỜ trỏ sang bản bạn đã cố ý xoá (dấu deleted_).
#     repair-missing-sessions.sh --fix-stale                    # xem trước
#     repair-missing-sessions.sh --fix-stale --apply            # sửa tất cả
#     repair-missing-sessions.sh --fix-stale --apply --only 58dfea02 # nêu đích danh mã phiên
# =============================================================================
set -uo pipefail

IDXDIR="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
PROJ="$HOME/.claude/projects"
VERDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER="$(cat "$VERDIR/VERSION" 2>/dev/null || echo '?')"

APPLY=0; SCAN=0; SINCE=30; FIXSTALE=0; ONLY=""; UNREACH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)     APPLY=1 ;;
    --scan)      SCAN=1 ;;
    --all)       SINCE=0 ;;
    --since)     shift; SINCE="${1:-30}" ;;
    --fix-stale) FIXSTALE=1; SINCE=0 ;;
    --unreachable) UNREACH=1; SINCE=0 ;;
    --only)      shift; ONLY="${1:-}" ;;
    -h|--help) sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Tham số lạ: $1"; exit 2 ;;
  esac
  shift
done

[ -d "$IDXDIR" ] || { echo "❌ Không thấy thư mục chỉ mục: $IDXDIR"; exit 1; }
[ -d "$PROJ" ]   || { echo "❌ Không thấy thư mục transcript: $PROJ"; exit 1; }

# --- Chốt an toàn -----------------------------------------------------------
# Dùng `grep -c` (đọc hết đầu vào) + `|| true`. KHÔNG dùng `grep -q`: nó thoát
# sớm → ps nhận SIGPIPE → với `set -o pipefail` cả pipeline thành "sai" → chốt
# mất tác dụng đúng lúc cần chặn nhất.
# Cũng KHÔNG dùng `pgrep`: trên macOS nó có thể không thấy tiến trình chính của
# Claude Desktop, chỉ thấy các helper.
RUNNING="$(ps -Ao args | grep -c "Claude\.app/Contents/MacOS/Claude$" || true)"
if [ "$APPLY" -eq 1 ] && [ "${RUNNING:-0}" -gt 0 ]; then
  echo "❌ Claude Desktop ĐANG CHẠY. Hãy Cmd+Q thoát hẳn, đợi 3 giây, rồi chạy lại."
  echo "   (Nếu ghi lúc app đang mở, app có thể ghi đè ngược khi thoát.)"
  exit 1
fi

IDXDIR="$IDXDIR" PROJ="$PROJ" APPLY="$APPLY" SCAN="$SCAN" SINCE="$SINCE" VER="$VER" \
FIXSTALE="$FIXSTALE" ONLY="$ONLY" UNREACH="$UNREACH" \
/usr/bin/python3 - <<'PYEOF'
import json, glob, os, sys, time, uuid, itertools, datetime, shutil, hashlib, re
STAMP = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")   # đuôi tên file backup

IDXDIR = os.environ["IDXDIR"]

# ── Chuẩn hoá tên dự án: git worktree tạo thư mục riêng
# "<dự-án>--claude-worktrees-<slug>", nên CÙNG một hội thoại tiếp tục trong
# worktree bị xếp sang nhóm khác ⇒ không script nào dọn được bản trùng.
# Đo thật khi dựng lại danh sách từ chỉ mục rỗng: 6 mục cùng tên nằm ở 6 thư mục
# worktree khác nhau, nội dung chồng lấp tới 97%, mà dedup vẫn báo "không trùng".
def normproj(p):
    return re.sub(r"--claude-worktrees-.*$", "", p or "")

PROJ   = os.environ["PROJ"]
APPLY  = os.environ["APPLY"] == "1"
SCAN   = os.environ["SCAN"] == "1"
SINCE  = int(os.environ["SINCE"])
VER    = os.environ["VER"]
FIXSTALE = os.environ.get("FIXSTALE") == "1"
UNREACH  = os.environ.get("UNREACH") == "1"
# --only nhận MÃ PHIÊN (8 ký tự đầu), KHÔNG nhận số thứ tự.
# Vì sao đổi: danh sách ĐÁNH SỐ LẠI sau mỗi lần sửa, nên "--only 1,2,3,4" hôm nay
# trỏ vào hội thoại khác hôm qua. Ngày 26/08/2026 đúng lỗi này làm REDANCE-1715
# tụt từ 89 xuống 48 đoạn nội dung. Mã phiên thì không bao giờ đổi nghĩa.
ONLY   = [x for x in os.environ.get("ONLY", "").replace(" ", "").split(",") if x]

MIN_BYTES = 20_000      # nhỏ hơn coi như phiên rỗng/thử nghiệm

# ---------- đọc chỉ mục hiện có ----------
indexed = {}            # cliSessionId -> (title, đường dẫn file chỉ mục)
for f in glob.glob(os.path.join(IDXDIR, "local_*.json")):
    try:
        o = json.load(open(f))
    except Exception:
        continue
    cli = o.get("cliSessionId")
    if cli:
        indexed[cli] = (o.get("title"), f)

# ---------- phiên đã CỐ Ý XOÁ trong app ----------
deleted = {os.path.basename(f)[len("deleted_"):]
           for f in glob.glob(os.path.join(IDXDIR, "deleted_*"))}

# ---------- quét transcript ----------
def read_meta(path):
    """Đọc tiêu đề nhúng, cwd, model, mốc thời gian, số lượt hỏi thật."""
    title = ai_title = None
    cwd = model = None
    first = last = None
    turns = 0
    # Dấu vân tay NỘI DUNG: băm từng lượt hỏi của người dùng.
    # Cần vì tiêu đề KHÔNG đủ để định danh hội thoại — hai transcript có thể
    # trùng tiêu đề mà nội dung rời nhau hoàn toàn (gặp thật 12/08/2026:
    # 3a13b33a và 967e3f4d cùng tên "Phong thủy…", chỉ giao nhau 1/37 lượt).
    fp = set()
    # fp_x: băm ĐẦY ĐỦ (chữ + tool_use + tool_result + thinking). Chỉ dùng để trả
    # lời câu hỏi "nội dung này đã đọc được từ mục khác chưa" — KHÔNG dùng để nhận
    # dạng hội thoại, vì vân tay tool bị dùng chung giữa các hội thoại rời nhau.
    fp_x = set()
    # fp_all: băm MỌI tin nhắn (user VÀ assistant). Dùng cho --fix-stale.
    # Vì sao cần riêng: đếm "lượt hỏi của người dùng" là thước đo SAI cho nội dung —
    # 18/08/2026 hai bản đều 22 lượt nên kit báo "ngang nhau", trong khi thực tế bản
    # kia thiếu 15 tin nhắn, hầu hết là câu TRẢ LỜI của Claude (phần chứa nội dung).
    fp_all = set()
    is_cont = None      # True nếu transcript mở đầu bằng đoạn nén tiếp nối
    with open(path, errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except Exception:
                continue
            t = o.get("type")
            if t == "custom-title" and o.get("customTitle"):
                title = o["customTitle"]
            elif t == "ai-title" and o.get("aiTitle"):
                ai_title = o["aiTitle"]
            ts = o.get("timestamp")
            if ts:
                if first is None:
                    first = ts
                last = ts
            if not cwd and o.get("cwd"):
                cwd = o["cwd"]
            if t in ("assistant", "user"):
                cc = (o.get("message") or {}).get("content")
                _parts = []; _tool = []
                if isinstance(cc, str):
                    if cc.strip(): _parts = [cc]
                elif isinstance(cc, list):
                    for _p in cc:
                        if not isinstance(_p, dict): continue
                        _ty = _p.get("type")
                        if _ty == "text":
                            if _p.get("text", "").strip(): _parts.append(_p["text"])
                        elif _ty == "tool_use":
                            _tool.append("TU:" + json.dumps(_p.get("input"), sort_keys=True, ensure_ascii=False))
                        elif _ty == "tool_result":
                            _v = _p.get("content")
                            _tool.append("TR:" + (_v if isinstance(_v, str)
                                                  else json.dumps(_v, sort_keys=True, ensure_ascii=False)))
                        elif _ty == "thinking":
                            if _p.get("thinking", "").strip(): _tool.append("TH:" + _p["thinking"])
                def _put(dst, ps):
                    if not ps: return
                    _flat = " ".join(" ".join(ps).split())
                    if len(_flat) >= 10 and not _flat.startswith(
                            ("This session is being continued", "Caveat:", "[Request interrupted")):
                        dst.add(hashlib.sha1(_flat.encode()).hexdigest())
                _put(fp_all, _parts)            # CHỮ  — đo nội dung người đọc được
                _put(fp_x, _parts + _tool)      # ĐẦY ĐỦ — đo phủ kín (gồm khối lệnh)
            if t == "assistant":
                m = (o.get("message") or {}).get("model")
                if m:
                    model = m
            if t == "user":
                c = (o.get("message") or {}).get("content")
                if isinstance(c, str):
                    txt = c
                elif isinstance(c, list):
                    txt = " ".join(p.get("text", "") for p in c
                                   if isinstance(p, dict) and p.get("type") == "text")
                else:
                    txt = ""
                txt = txt.strip()
                if txt and not txt.startswith("<"):
                    flat = " ".join(txt.split())
                    if is_cont is None:
                        is_cont = flat.startswith("This session is being continued") \
                                  or flat.startswith("Caveat:")
                    if not flat.startswith("This session is being continued") \
                       and not flat.startswith("[Request interrupted") \
                       and not flat.startswith("Caveat:") and len(flat) >= 25:
                        fp.add(hashlib.sha1(flat.encode()).hexdigest())
                    turns += 1
                    if not title and not ai_title and turns == 1:
                        # Dự phòng khi transcript không có bản ghi tiêu đề:
                        # lấy câu hỏi đầu, bỏ ký tự markdown/slash-command cho gọn
                        s = " ".join(txt.split())
                        s = s.lstrip("#/*->` ").strip()
                        ai_title = (s[:60] + "…") if len(s) > 60 else s
    return {
        "title": title or ai_title,
        "titleSource": "user" if title else "auto",
        "cwd": cwd, "model": model or "claude-opus-5",
        "first": first, "last": last, "turns": turns,
        "fp": fp, "fp_all": fp_all, "fp_x": fp_x, "is_cont": bool(is_cont),
    }

def ms(iso):
    if not iso:
        return int(time.time() * 1000)
    try:
        return int(datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() * 1000)
    except Exception:
        return int(time.time() * 1000)

cutoff = 0 if SINCE == 0 else time.time() - SINCE * 86400

cands = []
for path in glob.glob(os.path.join(PROJ, "*", "*.jsonl")):
    cli = os.path.basename(path)[:-6]
    mt = os.path.getmtime(path)
    size = os.path.getsize(path)
    proj = normproj(os.path.basename(os.path.dirname(path)))
    rec = {"cli": cli, "path": path, "mt": mt, "size": size, "proj": proj}
    if cli in indexed:
        rec["skip"] = "đã có trong Recents"
    elif cli in deleted:
        rec["skip"] = "bạn đã cố ý xoá"
    elif size < MIN_BYTES:
        rec["skip"] = "rỗng/quá ngắn"
    elif mt < cutoff:
        rec["skip"] = "ngoài cửa sổ thời gian"
    else:
        rec["skip"] = None
    cands.append(rec)

# đọc metadata cho phần cần xét (--scan và --fix-stale cần cả phiên ĐÃ có mục)
need = [c for c in cands
        if c["skip"] is None or ((SCAN or FIXSTALE or UNREACH) and c["skip"] != "rỗng/quá ngắn")]
for c in need:
    c.update(read_meta(c["path"]))

# ---------- gom nhóm theo chuỗi rẽ nhánh: (project, tiêu đề) ----------
# THỨ TỰ TRONG CHUỖI phải theo DẤU THỜI GIAN TIN NHẮN CUỐI trong transcript,
# KHÔNG theo mtime của file. Lý do: một thao tác sao chép hàng loạt (ví dụ khôi phục
# từ backup, di chuyển máy) đặt lại mtime của hàng trăm file cùng một lúc — lúc đó
# mtime không còn phản ánh bản nào mới hơn. Nội dung thì luôn đúng.
def order_key(c):
    return (ms(c.get("last")), c["mt"])      # mt chỉ để phá hoà khi thiếu timestamp

chains = {}
for c in need:
    key = (c["proj"], (c.get("title") or "").strip().lower())
    chains.setdefault(key, []).append(c)
for v in chains.values():
    v.sort(key=order_key)

# ---------- chọn bản ĐỦ NHẤT, không phải bản MỚI NHẤT ----------
# Trước v2.3.0 fix-stale luôn trỏ sang bản MỚI NHẤT theo thời gian. Sai ở chỗ:
# đoạn mới nhất của một hội thoại dài thường VỪA BỊ NÉN NGỮ CẢNH — nó chỉ chứa
# bản tóm tắt cộng vài lượt cuối, rỗng ruột so với đoạn ngay trước.
# Đo 26/08/2026: REDANCE-1715 đoạn mới nhất 48 đoạn nội dung, đoạn trước đó
# (cách 6 phút) 267 đoạn. Trỏ sang "mới nhất" = tự tay làm mất 219 đoạn.
# Vì thế: lấy bản NHIỀU NỘI DUNG NHẤT trong 24h cuối của chuỗi — vừa gần như
# mới nhất, vừa đầy đặn nhất. Hoà thì ưu tiên bản mới hơn.
BEST_WINDOW_MS = 24 * 3600 * 1000

def best_of(live):
    newest = ms(live[-1].get("last"))
    win = [m for m in live if ms(m.get("last")) >= newest - BEST_WINDOW_MS] or live
    return max(win, key=lambda m: (len(m.get("fp_all", set())), ms(m.get("last"))))

# ---------- --fix-stale: mục Recents đang trỏ vào bản KHÔNG ĐỦ NHẤT ----------
if FIXSTALE:
    stale = []
    for key, members in chains.items():
        # KHÔNG BAO GIỜ trỏ sang bản mà người dùng đã CỐ Ý XOÁ trong app.
        live = [m for m in members if m["cli"] not in deleted]
        ids = [m["cli"] for m in live]
        hit = [s for s in ids if s in indexed]
        if not hit or len(ids) < 2:
            continue                      # nhóm không có mục nào
        cur = hit[-1]
        cm = live[ids.index(cur)]
        nm = best_of(live)
        if nm["cli"] == cm["cli"]:
            continue                      # đang trỏ đúng bản đủ nhất rồi
        stale.append((indexed[cur][0], indexed[cur][1], cm, nm))
    stale.sort(key=lambda x: order_key(x[3]), reverse=True)

    def when(c):
        v = c.get("last")
        if not v:
            return "?"
        try:
            return (datetime.datetime.fromisoformat(v.replace("Z", "+00:00"))
                    .astimezone().strftime("%d/%m %H:%M"))
        except Exception:
            return "?"

    print(f"🔁 fix-stale v{VER} — mục Recents KHÔNG mở bản đủ nội dung nhất")
    print("   Đây là ĐÁNH ĐỔI, không phải hỏng hóc: không thao tác gì thì cũng KHÔNG")
    print("   mất thêm gì. Chỉ đổi khi bạn thật sự cần đọc lại phần cũ của hội thoại đó.")
    print(f"   {'🟢 THỰC THI (--apply)' if APPLY else '🔍 XEM TRƯỚC — chưa ghi gì'}\n")
    if not stale:
        print("✅ Không mục nào bị tụt. Mọi hội thoại đều mở đúng bản đủ nhất.")
        sys.exit(0)

    # MẶC ĐỊNH CHỈ ĐỔI KHI KHÔNG MẤT NỘI DUNG.
    # Bản "mới nhất theo thời gian" có thể ÍT nội dung hơn bản đang mở — xảy ra khi
    # bản đang mở là file đã HỢP NHẤT nhiều đoạn, hoặc khi bản mới vừa bị nén ngữ cảnh.
    # Đổi sang đó là tự tay làm mất lịch sử. Muốn đổi vẫn được, nhưng phải nêu đích danh
    # trong --only để đó là quyết định có ý thức, không phải mặc định.
    # So sánh theo TẬP TIN NHẮN, không theo số lượt hỏi.
    bad = [t for t in ONLY if t.isdigit()]
    if bad:
        print("⛔ --only nay nhan MA PHIEN 8 ky tu, khong nhan so thu tu.")
        print(f"   Ban dua vao: {','.join(bad)}")
        print("   Danh sach danh so LAI sau moi lan sua, nen so thu tu tro nham muc.")
        print("   Chay khong co --apply de xem ma phien roi dung ma do.")
        sys.exit(2)

    safe = {i for i, s in enumerate(stale, 1)
            if not (s[2].get("fp_all", set()) - s[3].get("fp_all", set()))}

    def forced(cm, nm):
        """--only khop khi ma phien trung phan dau cua ban dang mo HOAC ban moi."""
        return [t for t in ONLY
                if cm["cli"].startswith(t) or nm["cli"].startswith(t)]

    if ONLY:
        hit = set()
        for _t, _f, _cm, _nm in stale:
            hit.update(forced(_cm, _nm))
        miss = [t for t in ONLY if t not in hit]
        if miss:
            print(f"⛔ Khong muc nao khop --only: {','.join(miss)}")
            print("   Chay khong co --apply de xem lai danh sach ma phien.")
            sys.exit(2)

    changed = []
    for i, (title, idxfile, cm, nm) in enumerate(stale, 1):
        cur_fp = cm.get("fp_all", set()); new_fp = nm.get("fp_all", set())
        lose = len(cur_fp - new_fp)      # tin nhắn mất nếu đổi
        gain = len(new_fp - cur_fp)      # tin nhắn được thêm
        delta = gain - lose
        # 🟢 không mất gì · 🟡 được nhiều hơn mất · 🔴 mất nhiều hơn được
        flag = "🟢" if not lose else ("🟡" if gain > lose else "🔴")
        if not lose and not gain: flag = "⚪"
        pick = bool(forced(cm, nm)) if ONLY else (i in safe)
        mark = " " if pick else "·"
        print(f"[{i}]{mark}{flag} {title}")
        print(f"     đang mở : {cm['cli'][:8]}  {len(cur_fp):>4} tin nhắn  → {when(cm)}")
        print(f"     đủ nhất : {nm['cli'][:8]}  {len(new_fp):>4} tin nhắn  → {when(nm)}"
              f"   (+{gain} / -{lose})")
        if lose and not (ONLY and forced(cm, nm)):
            print(f"     ⚠️  ĐỔI ĐƯỢC {gain}, MẤT {lose} tin nhắn — mặc định BỎ QUA.")
            print(f"         Vẫn muốn đổi thì nêu đích danh: --only {cm['cli'][:8]}\n")
            continue
        if not pick:
            print("     (bỏ qua — không nằm trong --only)\n")
            continue
        if not APPLY:
            print("     → sẽ trỏ sang bản mới\n")
            continue
        bak = idxfile + ".bak-" + STAMP
        shutil.copy2(idxfile, bak)
        d = json.load(open(idxfile))
        d["cliSessionId"] = nm["cli"]
        d["lastActivityAt"] = ms(nm.get("last"))
        with open(idxfile, "w") as fh:
            json.dump(d, fh, ensure_ascii=False, indent=2)
        changed.append((idxfile, bak, cm["cli"]))
        print(f"     ✅ đã trỏ sang {nm['cli'][:8]}  (backup: {os.path.basename(bak)})\n")

    print("─" * 50)
    if APPLY and changed:
        print(f"✅ Đã sửa {len(changed)} mục. Mở lại Claude Desktop để xem.\n")
        print("Hoàn tác (phục hồi từ backup):")
        for f, b, old in changed:
            print(f"  cp '{b}' '{f}'")
    elif APPLY:
        print("Không sửa mục nào.")
    else:
        print("Chưa ghi gì. Cmd+Q thoát Claude Desktop rồi thêm --apply.")
        print("Chọn riêng vài mục:  --fix-stale --apply --only <mã phiên 8 ký tự>")
        print("")
        print("🟢 đổi không mất gì   🟡 được nhiều hơn mất   🔴 mất nhiều hơn được")
        print("Mọi mục 🟡/🔴 đều BỎ QUA theo mặc định. Danh sách này KHÔNG cần làm cho rỗng.")
        print("Muốn một mục chứa TRỌN hội thoại (không đánh đổi) thì phải hợp nhất:")
        print("  merge-branches.sh --list")
    sys.exit(0)

# ── Nhóm LIÊN THÔNG THEO NỘI DUNG (union-find) ──────────────────────────────
# Chỉ trùng tiêu đề KHÔNG đủ để kết luận "hội thoại này đã có mục". Hai transcript
# có thể cùng tên mà nội dung rời hẳn nhau (gặp thật 12/08/2026: 3a13b33a vs
# 967e3f4d cùng tên "Phong thủy…", giao nhau 1/37 lượt hỏi).
# Ngược lại, một hội thoại dài có hàng chục bản rẽ nhánh nối tiếp nhau — phải coi
# là MỘT. Nối hai bản khi chúng dùng chung ≥2 lượt hỏi, rồi lấy bao đóng bắc cầu.
for c in cands:
    if "fp" not in c and c["size"] >= MIN_BYTES:
        c.update(read_meta(c["path"]))

_par = {}
def _find(x):
    _par.setdefault(x, x)
    while _par[x] != x:
        _par[x] = _par[_par[x]]; x = _par[x]
    return x
def _union(a, b):
    ra, rb = _find(a), _find(b)
    if ra != rb: _par[rb] = ra

by_title = {}
for c in cands:
    if not c.get("fp"): continue
    by_title.setdefault((c["proj"], (c.get("title") or "").strip().lower()), []).append(c)

for members in by_title.values():
    inv = {}
    for c in members:
        for h in c["fp"]:
            inv.setdefault(h, []).append(c["cli"])
    shared = {}
    for h, ids in inv.items():
        if len(ids) < 2 or len(ids) > 60: continue
        for a, b in itertools.combinations(sorted(set(ids)), 2):
            shared[(a, b)] = shared.get((a, b), 0) + 1
    for (a, b), n in shared.items():
        if n >= 2: _union(a, b)

# thành phần liên thông nào đã có đại diện trong Recents
comp_indexed = set()
for c in cands:
    if c.get("fp") and c["cli"] in indexed:
        comp_indexed.add(_find(c["cli"]))

# ── Nội dung ĐANG ĐỌC ĐƯỢC từ danh sách: hợp mọi vân tay ĐẦY ĐỦ của các phiên đã
# có mục. Dùng cho CHỐT SỐ 3 bên dưới.
readable = set()
for c in cands:
    if c["cli"] in indexed and c.get("fp_x"):
        readable |= c["fp_x"]

restore, skipped = [], []
for c in need:
    if c["skip"] is not None:
        skipped.append(c); continue
    key = (c["proj"], (c.get("title") or "").strip().lower())
    # ── CHỐT SỐ 1, đặt TRƯỚC mọi kiểm tra khác ──────────────────────────────
    # Transcript mở đầu bằng "This session is being continued…" là một ĐOẠN NÉN
    # của hội thoại dài, KHÔNG BAO GIỜ được tạo thành mục Recents riêng.
    # Sự cố 12/08/2026: chốt này từng nằm LỒNG BÊN TRONG nhánh "cùng thành phần
    # liên thông", nên các đoạn nén thuộc thành phần chưa có mục thì lọt qua —
    # một lần --apply đẻ ra 555 mục, 501 mục cùng tên "REDANCE-1715 Mail
    # investigation", mỗi mục chỉ chứa một lát cắt. Phải kiểm vô điều kiện.
    if c.get("is_cont"):
        c["skip"] = "đoạn nén tiếp nối — không tạo mục riêng"
        skipped.append(c); continue
    # ── CHỐT SỐ 3: NỘI DUNG ĐÃ ĐỌC ĐƯỢC TỪ MỤC KHÁC ⇒ KHÔNG TẠO MỤC MỚI ─────
    # Sự cố 26/08/2026: `dedup-entries` dọn mục trùng theo tiêu chí "nội dung đã
    # phủ kín bởi mục khác"; ngay sau đó `repair` thấy transcript không còn mục
    # nào trỏ vào nên coi là mồ côi và định tạo lại đúng mục vừa dọn — thành
    # VÒNG LẶP dọn/tạo vô tận (gặp thật: 240ef0f0 và b8aa66fb).
    # Union-find bên trên không bắt được vì nó đòi ≥2 vân tay dùng chung, mà hai
    # phiên đó chỉ có 1 đoạn nội dung nên không bao giờ nối được vào nhóm.
    # Chốt này dùng CÙNG một định nghĩa phủ kín với dedup-entries (vân tay ĐẦY
    # ĐỦ) — hai script phải cùng một thước, nếu không vòng lặp sẽ quay lại.
    if c.get("fp_x") and not (c["fp_x"] - readable):
        c["skip"] = "nội dung đã đọc được từ mục khác"
        skipped.append(c); continue
    distinct = False        # trùng tiêu đề nhưng là hội thoại KHÁC
    if _find(c["cli"]) in comp_indexed:
        # Cùng một hội thoại với mục đã có → không tách ra làm mục riêng, nếu không
        # một hội thoại dài sẽ đẻ ra hàng chục mục trùng tên trong Recents.
        c["skip"] = "cùng hội thoại với mục đã có"
        skipped.append(c); continue
    if key in by_title and any(m["cli"] in indexed for m in by_title[key]):
        # Trùng tiêu đề nhưng KHÁC thành phần liên thông ⇒ là hội thoại riêng.
        # Các phép so "mới/cũ trong chuỗi" bên dưới gom theo TIÊU ĐỀ nên vô nghĩa ở đây.
        distinct = True
    if not distinct and chains[key][-1]["cli"] != c["cli"]:
        c["skip"] = "bản rẽ nhánh cũ (có bản mới hơn)"; skipped.append(c); continue
    if c["turns"] < 1:
        c["skip"] = "không có lượt hỏi nào"; skipped.append(c); continue
    restore.append(c)

# ── CHỐT SỐ 2: MỘT HỘI THOẠI — MỘT MỤC. Đặt SAU mọi phân loại, không thể bị bỏ qua.
# Sự cố 23/08/2026: một lần `repair --apply` tạo 15 mục cùng tên "Phong thủy hành lang
# và cửa sân sau" và 6 mục cùng tên "REDANCE-1715 Mail investigation" (đọc được từ
# mtime của các file chỉ mục: tất cả cùng một giây).
# Nguyên nhân: nhánh `distinct = True` ("trùng tiêu đề nhưng khác thành phần liên thông
# ⇒ hội thoại riêng") VÔ HIỆU HOÁ bộ lọc "bản rẽ nhánh cũ" → mỗi đoạn rẽ nhánh thành
# một mục. Union-find gom theo lượt hỏi chung, nhưng các bản rewind cũ (06–10/08) không
# chia sẻ lượt hỏi nào với đoạn nén mới nhất → không gom được → mỗi đoạn tự thành một
# "hội thoại riêng".
# Bài học lặp lại lần thứ ba: khi không chắc, mặc định phải là KHÔNG TẠO.
# Chốt này không cần union-find đúng — nó chặn theo (dự án, tiêu đề), là thứ người dùng
# NHÌN THẤY trong danh sách. Một lần chạy không bao giờ tạo hai mục trùng tên.
_best = {}
for c in restore:
    k = (c["proj"], (c.get("title") or "").strip().lower())
    b = _best.get(k)
    if b is None or (len(c.get("fp_all", set())), ms(c.get("last"))) > \
                    (len(b.get("fp_all", set())), ms(b.get("last"))):
        _best[k] = c
_dupes = [c for c in restore if _best.get((c["proj"], (c.get("title") or "").strip().lower())) is not c]
for c in _dupes:
    c["skip"] = "cùng tiêu đề với một mục khác trong đợt này — chỉ tạo 1"
    skipped.append(c)
restore = [c for c in restore if c not in _dupes]

restore.sort(key=order_key, reverse=True)

# ---------- --unreachable: ĐO TRỰC TIẾP, không phân loại ----------
# Câu hỏi duy nhất không mơ hồ: lượt hỏi này có mở ra được từ MỘT mục Recents nào
# không? Việc "đây là hội thoại riêng hay chỉ là một đoạn" thì suy đoán được, còn
# "nội dung này có tiếp cận được không" thì đo được chính xác.
if UNREACH:
    reachable = set()
    for c in cands:
        if c["cli"] in indexed and c.get("fp"):
            reachable |= c["fp"]
    rows = []
    for c in cands:
        if c["cli"] in indexed or c["cli"] in deleted or not c.get("fp"):
            continue
        lack = c["fp"] - reachable
        if lack:
            rows.append((len(lack), len(c["fp"]), c))
    # sắp theo 2 phần tử đầu; KHÔNG để Python so sánh phần tử thứ 3 (dict) khi hoà
    rows.sort(key=lambda r: (r[0], r[1]), reverse=True)
    tot = len(set().union(*[c["fp"] - reachable for _, _, c in rows])) if rows else 0
    print(f"🔦 unreachable v{VER} — lượt hỏi KHÔNG mở được từ bất kỳ mục Recents nào\n")
    print(f"   Transcript chứa nội dung không tiếp cận được : {len(rows)}")
    print(f"   Tổng lượt hỏi không tiếp cận được (đã lọc trùng): {tot}\n")
    for n, tt, c in rows[:30]:
        print(f"  {c['cli'][:8]}  {c['size']//1024:>6} KB  {n}/{tt} lượt không tiếp cận ({100*n//tt}%)")
        print(f"      {c.get('title')}")
    if len(rows) > 30:
        print(f"\n  … và {len(rows)-30} transcript nữa")
    print("\n  Ghi chú: phần lớn là các ĐOẠN NÉN của hội thoại dài — nội dung vẫn nằm")
    print("  nguyên trên đĩa, chỉ là app chỉ mở được một đoạn mỗi lần.")
    sys.exit(0)

# ---------- --scan: chỉ liệt kê ----------
if SCAN:
    orph = sorted([c for c in cands if c["skip"] != "đã có trong Recents"],
                  key=lambda x: x["mt"], reverse=True)
    print(f"🔎 {len(orph)} transcript KHÔNG có mục Recents (mới nhất trước)\n")
    for c in orph[:60]:
        d = datetime.datetime.fromtimestamp(c["mt"]).strftime("%d/%m %H:%M")
        tag = "→ SẼ PHỤC HỒI" if c in restore else f"(bỏ qua: {c['skip']})"
        print(f"{d}  {c['cli'][:8]}  {c['size']//1024:>6} KB  {tag}")
        print(f"          {c.get('title') or '(không rõ tiêu đề)'}")
    if len(orph) > 60:
        print(f"\n… và {len(orph)-60} mục nữa (dùng --since để lọc hẹp hơn)")
    sys.exit(0)

# ---------- báo cáo + thực thi ----------
win = "toàn bộ" if SINCE == 0 else f"{SINCE} ngày gần đây"
print(f"🛟 repair-missing-sessions v{VER} — cửa sổ: {win}")
print(f"   {'🟢 THỰC THI (--apply)' if APPLY else '🔍 XEM TRƯỚC — chưa ghi gì'}\n")

if not restore:
    print("✅ Không có hội thoại nào bị mất khỏi Recents. Mọi thứ đều đủ.")
else:
    print(f"Sẽ đưa lại {len(restore)} hội thoại vào Recents:\n")

created = []
for c in restore:
    d = datetime.datetime.fromtimestamp(c["mt"]).strftime("%d/%m %H:%M")
    print(f"• {c.get('title')}")
    print(f"  {c['cli']}  ·  {d}  ·  {c['size']//1024} KB  ·  {c['turns']} lượt")
    if not APPLY:
        print()
        continue
    sid = "local_" + str(uuid.uuid4())
    dest = os.path.join(IDXDIR, sid + ".json")
    entry = {
        "sessionId": sid,
        "cliSessionId": c["cli"],
        "cwd": c.get("cwd") or os.path.expanduser("~"),
        "originCwd": c.get("cwd") or os.path.expanduser("~"),
        "lastFocusedAt": ms(c.get("last")),
        "createdAt": ms(c.get("first")),
        "lastActivityAt": ms(c.get("last")),
        "model": c.get("model"),
        "effort": "high",
        "isArchived": False,
        "title": c.get("title"),
        "titleSource": c.get("titleSource", "auto"),
        "permissionMode": "auto",
        "enabledMcpTools": {},
        "remoteMcpServersConfig": [],
        "completedTurns": c["turns"],
        "alwaysAllowedReasons": [],
        "sessionPermissionUpdates": [],
        "classifierSummaryEnabled": True,
        "spawnSeed": {},
    }
    with open(dest, "w") as fh:
        json.dump(entry, fh, ensure_ascii=False, indent=2)
    os.chmod(dest, 0o600)
    created.append(dest)
    print(f"  ✅ đã tạo {sid}.json\n")

# thống kê phần bỏ qua
reasons = {}
for c in skipped:
    reasons[c["skip"]] = reasons.get(c["skip"], 0) + 1
if reasons:
    print("── Đã bỏ qua ──")
    for k, v in sorted(reasons.items(), key=lambda x: -x[1]):
        print(f"  {v:>4}  {k}")

print("\n" + "─" * 50)
if APPLY:
    if created:
        print(f"✅ Đã tạo {len(created)} mục. Mở lại Claude Desktop để xem.\n")
        print("Hoàn tác (xoá đúng những mục vừa tạo, không đụng gì khác):")
        for f in created:
            print(f"  rm '{f}'")
    else:
        print("Không tạo mục nào.")
else:
    print("Chưa ghi gì. Cmd+Q thoát Claude Desktop rồi chạy lại với --apply.")
PYEOF
