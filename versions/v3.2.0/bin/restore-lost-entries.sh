#!/usr/bin/env bash
# =============================================================================
# restore-lost-entries.sh   (v2.3.1)
# Tạo lại mục Recents cho HỘI THOẠI KHÔNG CÒN MỤC NÀO.
#
# VÌ SAO CẦN RIÊNG script này:
#   repair-missing-sessions.sh bỏ qua MỌI "đoạn nén tiếp nối" (is_cont) —
#   chốt này được đặt vô điều kiện sau sự cố 555 mục rác ngày 12/08/2026.
#   Hệ quả phụ: hội thoại mà MỌI đoạn đều là đoạn nén (fork tạo trong app,
#   hội thoại rất dài) thì không bao giờ được tạo mục → biến mất vĩnh viễn
#   khỏi danh sách. Ngày 26/08/2026 đo được 918 đoạn bị bỏ qua, trong đó có
#   7 hội thoại không còn mục nào.
#
# CHỐT AN TOÀN (khác repair):
#   • CHỈ tạo mục khi cả nhóm (dự án + tiêu đề) KHÔNG có mục nào.
#     → không thể đẻ ra mục trùng như sự cố 12/08.
#   • Bỏ qua nhóm mà mọi đoạn đều có dấu `deleted_` (bạn đã cố ý xoá).
#   • CHỈ TẠO file mới, không sửa/xoá mục đang có.
#   • Mặc định xem trước; chặn khi Claude Desktop đang chạy.
#
# Chọn đoạn để trỏ tới: đoạn NHIỀU NỘI DUNG NHẤT trong 24 giờ cuối của nhóm
# (không phải đoạn mới nhất — đoạn mới nhất thường vừa bị nén nên rỗng ruột).
# Tương thích bash 3.2.
# =============================================================================
set -euo pipefail
IDXDIR="$HOME/Library/Application Support/Claude/claude-code-sessions-shared"
PROJ="$HOME/.claude/projects"
VERDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER="$(cat "$VERDIR/VERSION" 2>/dev/null || echo '?')"

APPLY=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Tham số lạ: $a"; exit 2 ;;
  esac
done

[ -d "$IDXDIR" ] || { echo "❌ Không thấy thư mục chỉ mục: $IDXDIR"; exit 1; }

# `grep -c` + `|| true` — KHÔNG dùng `grep -q` (thoát sớm → SIGPIPE → pipefail
# biến điều kiện thành sai đúng lúc cần chặn). KHÔNG dùng `pgrep` (không thấy
# tiến trình chính của Claude Desktop trên macOS).
# shellcheck disable=SC2009
# CỐ Ý dùng `ps -Ao args`, KHÔNG dùng `pgrep`: đo thực tế trên macOS,
# `pgrep -x Claude` trả về 0 tiến trình trong khi Claude Desktop ĐANG chạy
# (chỉ thấy helper). Nghe theo shellcheck ở đây sẽ làm chốt an toàn
# 'Claude đã tắt chưa' luôn trả lời sai ⇒ lệnh ghi chạy khi app đang mở.
RUNNING="$(ps -Ao args | grep -c "Claude\.app/Contents/MacOS/Claude$" || true)"
if [ "$APPLY" = "1" ] && [ "$RUNNING" != "0" ]; then
  echo "⛔ Claude Desktop đang chạy. Thoát hẳn (Cmd+Q hoặc safe-quit.sh) rồi chạy lại."
  exit 1
fi

IDXDIR="$IDXDIR" PROJ="$PROJ" APPLY="$APPLY" VER="$VER" /usr/bin/python3 - <<'PYEOF'
import json, glob, os, uuid, hashlib, datetime, collections, time, re
IDXDIR = os.environ["IDXDIR"]; PROJ = os.environ["PROJ"]

# ── Chuẩn hoá tên dự án: git worktree tạo thư mục riêng
# "<dự-án>--claude-worktrees-<slug>", nên CÙNG một hội thoại tiếp tục trong
# worktree bị xếp sang nhóm khác ⇒ không script nào dọn được bản trùng.
# Đo thật khi dựng lại danh sách từ chỉ mục rỗng: 6 mục cùng tên nằm ở 6 thư mục
# worktree khác nhau, nội dung chồng lấp tới 97%, mà dedup vẫn báo "không trùng".
def normproj(p):
    return re.sub(r"--claude-worktrees-.*$", "", p or "")

APPLY  = os.environ["APPLY"] == "1"; VER = os.environ["VER"]
MIN_BYTES = 20_000
RECENT_WINDOW_H = 24        # cửa sổ chọn đoạn "giàu nội dung nhất"

indexed = set(); 
for f in glob.glob(os.path.join(IDXDIR, "local_*.json")):
    try: indexed.add(json.load(open(f)).get("cliSessionId"))
    except Exception: pass
deleted = {os.path.basename(f)[len("deleted_"):] for f in glob.glob(os.path.join(IDXDIR, "deleted_*"))}

def read(path):
    """title, cwd, model, last-timestamp, dấu vân tay nội dung, số tin nhắn."""
    title = cwd = model = last = None; fp = set(); fpx = set(); n = 0
    for line in open(path, errors="replace"):
        line = line.strip()
        if not line: continue
        try: o = json.loads(line)
        except Exception: continue
        t = o.get("type")
        if not cwd and o.get("cwd"): cwd = o["cwd"]
        if t in ("custom-title", "ai-title"):
            v = o.get("title") or o.get("customTitle") or ""
            if v: title = v
        if t == "assistant":
            m = (o.get("message") or {}).get("model")
            if m: model = m
        if t in ("user", "assistant"):
            n += 1
            if o.get("timestamp"): last = o["timestamp"]
            cc = (o.get("message") or {}).get("content"); parts = []; tool = []
            if isinstance(cc, str):
                if cc.strip(): parts = [cc]
            elif isinstance(cc, list):
                for p in cc:
                    if not isinstance(p, dict): continue
                    ty = p.get("type")
                    if ty == "text":
                        if p.get("text", "").strip(): parts.append(p["text"])
                    elif ty == "tool_use":
                        tool.append("TU:" + json.dumps(p.get("input"), sort_keys=True, ensure_ascii=False))
                    elif ty == "tool_result":
                        v = p.get("content")
                        tool.append("TR:" + (v if isinstance(v, str)
                                             else json.dumps(v, sort_keys=True, ensure_ascii=False)))
                    elif ty == "thinking":
                        if p.get("thinking", "").strip(): tool.append("TH:" + p["thinking"])
            def _put(dst, ps):
                if not ps: return
                flat = " ".join(" ".join(ps).split())
                if len(flat) >= 10 and not flat.startswith(
                        ("This session is being continued", "Caveat:", "[Request interrupted")):
                    dst.add(hashlib.sha1(flat.encode()).hexdigest())
            _put(fp,  parts)            # CHỮ  — nhận dạng + hiển thị
            _put(fpx, parts + tool)     # ĐẦY ĐỦ — đo phủ kín
    return dict(title=title, cwd=cwd, model=model, last=last, fp=fp, fpx=fpx, n=n)

groups = collections.defaultdict(list)
for path in glob.glob(os.path.join(PROJ, "*", "*.jsonl")):
    if os.path.getsize(path) < MIN_BYTES: continue
    if "-private-var-folders" in path: continue
    try: m = read(path)
    except Exception: continue
    if not m["title"] or not m["last"]: continue
    m["sid"] = os.path.basename(path)[:-6]
    groups[(normproj(os.path.basename(os.path.dirname(path))), m["title"].strip())].append(m)

def ms(iso):
    try: return int(datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() * 1000)
    except Exception: return int(time.time() * 1000)

# Nội dung ĐANG ĐỌC ĐƯỢC từ danh sách hiện có — dùng cho chốt phủ kín bên dưới.
readable = set()
for _mem in groups.values():
    for _m in _mem:
        if _m["sid"] in indexed: readable |= _m["fpx"]

todo = []
for (proj, title), mem in groups.items():
    if any(m["sid"] in indexed for m in mem): continue          # nhóm đã có mục → không đụng
    live = [m for m in mem if m["sid"] not in deleted]
    if not live: continue                                        # bạn đã cố ý xoá cả nhóm
    live.sort(key=lambda m: m["last"])
    cut = ms(live[-1]["last"]) - RECENT_WINDOW_H * 3600 * 1000
    recent = [m for m in live if ms(m["last"]) >= cut] or live
    best = max(recent, key=lambda m: len(m["fp"]))
    # ── CHỐT PHỦ KÍN: nội dung đã đọc được hết từ mục khác ⇒ không tạo mục mới.
    # Cùng một thước với dedup-entries và repair (vân tay ĐẦY ĐỦ), để ba script
    # không đá nhau thành vòng lặp dọn/tạo. Chỉ bỏ qua khi phủ KÍN HOÀN TOÀN.
    if not (set().union(*[m["fpx"] for m in live]) - readable): continue
    todo.append((title, proj, best, len(live)))
todo.sort(key=lambda x: x[2]["last"], reverse=True)

print(f"🧩 restore-lost-entries v{VER} — hội thoại KHÔNG CÒN MỤC NÀO trong Recents")
print(f"   {'🟢 THỰC THI (--apply)' if APPLY else '🔍 XEM TRƯỚC — chưa ghi gì'}\n")
if not todo:
    print("✅ Mọi hội thoại đều có ít nhất một mục. Không cần làm gì."); raise SystemExit(0)

made = []
for title, proj, b, cnt in todo:
    when = b["last"][:16].replace("T", " ")
    print(f"• {title}")
    print(f"    {b['sid'][:8]}  {b['n']:>5} tin nhắn  ·  {len(b['fp'])} đoạn nội dung  ·  {when}  ·  {cnt} đoạn trong chuỗi")
    if not APPLY:
        print()
        continue
    name = f"local_{uuid.uuid4()}"
    doc = {
        "sessionId": name,
        "cliSessionId": b["sid"],
        "cwd": b["cwd"] or os.path.expanduser("~"),
        "originCwd": b["cwd"] or os.path.expanduser("~"),
        "lastFocusedAt": ms(b["last"]),
        "createdAt": ms(b["last"]),
        "lastActivityAt": ms(b["last"]),
        "model": b["model"] or "claude-opus-5",
        "effort": "high",
        "isArchived": False,
        "title": title,
        "titleSource": "user",
        "permissionMode": "auto",
        "enabledMcpTools": {},
        "remoteMcpServersConfig": [],
        "completedTurns": 0,
        "alwaysAllowedReasons": [],
        "sessionPermissionUpdates": [],
        "classifierSummaryEnabled": True,
        "spawnSeed": {},
    }
    out = os.path.join(IDXDIR, name + ".json")
    with open(out, "w") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
    os.chmod(out, 0o600)
    made.append(out)
    print(f"    ✅ đã tạo {os.path.basename(out)}\n")

print("─" * 50)
if APPLY:
    print(f"✅ Đã tạo {len(made)} mục. Mở lại Claude Desktop để thấy.")
    print("   Hoàn tác (xoá đúng các mục vừa tạo):")
    for o in made:
        print(f"     rm '{o}'")
else:
    print(f"Sẽ tạo {len(todo)} mục. Chưa ghi gì.")
    print("Thoát hẳn Claude Desktop rồi chạy lại với --apply.")
PYEOF
