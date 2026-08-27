# v3.3.0 — 27/08/2026

## ⭐ A1 · Bảo toàn + khôi phục ĐIỂM CẮT NGỮ CẢNH — lỗi gốc của mọi sự cố

`merge-branches.sh` (v3.1.0–v3.2.0) nối MỌI bản ghi thành một chuỗi thẳng:

```python
o["parentUuid"]=prev; prev=o["uuid"]
```

Việc đó GHI ĐÈ `parentUuid=None` tại các bản ghi `compact_boundary` — chính giá
trị `None` đó là ĐIỂM CẮT app dùng để quyết định gửi bao nhiêu ngữ cảnh.

Bằng chứng đọc từ transcript (58dfea02):

```
type=system  subtype=compact_boundary
parentUuid         None
logicalParentUuid  2f2de111…
preTokens          924.674  →  postTokens  14.801
cumulativeDroppedTokens  13.088.700
```

Xoá điểm cắt ⇒ app phải gửi cả 13 triệu token đã bỏ ⇒ vỡ trần. Đo thật:
`ece09c56` sau khi gộp KHÔNG nhắn tiếp được; `ae968d22` (51 MB, cùng hội thoại,
chưa gộp) vẫn nhắn bình thường.

Sửa: bỏ qua `compact_boundary` khi nối chuỗi, giữ `logicalParentUuid`, và
**KHÔI PHỤC** `parentUuid=None` cho các điểm cắt đã bị bản cũ làm hỏng.
Phép kiểm ④ đổi từ "đúng 1 gốc" sang "số gốc = 1 + số điểm cắt".
Thêm phép kiểm ⑩: mọi `compact_boundary` phải còn `parentUuid=None`.

Kiểm chứng trên 699 nhánh: giữ 4 điểm cắt · 10/10 phép kiểm đạt.

## ⭐ B1 · Đổi mặc định từ GỘP sang TRỎ

Đo cách gốc của Claude Desktop: **app KHÔNG tách hội thoại dài**.

```
REDANCE-1715 · 715 file trên đĩa · 1 mục trong danh sách
```

App nén tại chỗ và giữ một mục. Việc app không tự lo là: sau khi thoát/mở lại,
mục Recents tụt về nhánh cũ. **Chỉ cần trỏ lại.**

Thêm `merge --repoint`: trỏ mục sang nhánh đầy đủ nhất, KHÔNG dựng file.
`fix --apply` nay dùng chế độ này thay vì gộp.

| | gộp | trỏ |
|---|---|---|
| tạo file | hàng chục–trăm MB | không |
| ctx sau đó | tăng 5–36 lần | giữ nguyên |
| rủi ro | đã giết ece09c56 | không có |
| hoàn tác | .bak + xoá file | một lệnh cp |

Đo trên 58dfea02: gộp cho 13.377 đoạn chữ nhưng trần hiển thị 48 MiB chỉ cho
thấy 550 (4%). Trỏ cho 609 đoạn chữ, không tạo file.

## ⭐ C1 · Phép kiểm chứng tự động — `verify-entries.sh`

Ba sự cố ngày 27/08 đều cùng hình dạng: script báo "✅ xong", người dùng mở app
lên thì THIẾU. Gốc rễ: script chưa bao giờ TỰ ĐO LẠI sau khi sửa.

Phép đo: với mỗi hội thoại nhiều nhánh, hỏi *"mục Recents có chứa BẢN GHI MỚI
NHẤT của chuỗi không?"*. `fix --apply` nay chạy phép này sau khi sửa.

Chạy lần đầu đã bắt được 2 hội thoại thiếu mà `fix --apply` trước đó bỏ sót.

## A3 · Bỏ mọi chốt theo MB

`PREFILTER_MB=1200` lọc theo MB nguồn — không tương quan với gì cả:

```
58dfea02   6,6 MB  →  ctx đỉnh 919.666
12345a85    61 MB  →  ctx đỉnh 847.935
```

Chế độ TRỎ không dựng file nên không còn gì để lọc trước.

## A4 · `--list-only` tự cảnh báo

Cờ này đặt `SCOPE=list` ⇒ bỏ TOÀN BỘ khối ② — đúng khối sửa nội dung. Dùng nó
vì tưởng "an toàn hơn" là sự cố thứ hai ngày 27/08. Nay nó tự nói ra.

## C3 · `claude-history forget <mã>` — gỡ mục vĩnh viễn

Gỡ file chỉ mục không thôi thì `fix` tạo lại (mục "⤷ kho gộp" mọc lại sau 1 giờ
17 phút). Lệnh này đặt dấu `deleted_<id>` — cơ chế sẵn có của app mà cả
`restore-lost-entries` lẫn `repair` đều tôn trọng.

## Ghi nhận sai sót của phiên bản trước

- Mọi con số "token" báo cáo trong quá trình phát triển v3.1.0–v3.2.0 là **ước
  lượng ký-tự÷4 tự chế**, sai tới **51 lần** so với `usage` thật do API trả về.
  Số thật đã có sẵn trong transcript (`usage`, `compactMetadata`) từ đầu.
- Kết luận "máy này không có `compact_boundary`" là **sai** — lệnh tìm hỏng.
  Thực tế có **1.062 file** chứa nó.

---

# v3.1.0 — 27/08/2026

## Hiển thị: tên hội thoại thay vì chỉ mã

`fix` từng in `[1/1] 58dfea02 ⏭ bỏ qua`. Nhìn mã 8 ký tự thì không biết cái vừa
bị bỏ qua có quan trọng không ⇒ không quyết định được gì. Nay in tên, số nhánh,
kích thước nguồn.

`merge --ids` đổi từ 1 cột sang **4 cột ngăn bằng TAB**: mã · tên · MB nguồn ·
số nhánh. Chỉ `fix-all.sh` dùng đầu ra này.

## Đồng hồ: ĐO, không ĐOÁN

Thêm thời gian từng chuỗi và **tổng thời gian** ở cuối.

**XOÁ** dòng "ước tính ~N phút" của v3.0.0. Công thức cũ `số_chuỗi × 31 giây`
báo 23 phút cho lượt chạy thật **2 giờ 20 phút** — sai 6 lần, vì chi phí đi theo
SỐ BYTE chứ không theo số chuỗi. Xoá chứ không sửa: một con số sai còn tệ hơn
không có số nào.

## Lọc trước chuỗi quá lớn — tiết kiệm 2,5 phút MỖI lượt

v3.0.0 dựng xong toàn bộ (56.537 bản ghi / 554 MB) rồi mới từ chối ở phép ⑨.
Mất ~2,5 phút và **lặp lại mỗi lần chạy `fix --apply`**.

Nay `fix` xem MB nguồn từ `--ids` và bỏ qua ngay, không dựng. Ngưỡng 1200 MB
nguồn ≈ 250 MB kết quả. Đo 27/08 trên REDANCE-1715, tỉ lệ nguồn→kết quả 16–21%:

| giai đoạn | nhánh | nguồn | kết quả | đoạn chữ | thời gian |
|---|---|---|---|---|---|
| 10/07 → 24/07 | 230 | 995 MB | 210 MB | 6.058 | 43s |
| 25/07 → 06/08 | 316 | 1129 MB | 225 MB | 5.864 | 46s |
| 10/08 → 26/08 | ~180 | 868 MB | 139 MB | 2.198 | 43s |
| **cả chuỗi** | **699** | **2941 MB** | **554 MB** ⛔ | 13.373 | ~2m30s |

Đây là bộ LỌC TRƯỚC, không phải phép đo — ngưỡng thật vẫn là ⑨ đo trên file đã
dựng. Đoán sai hướng nào cũng vô hại.

## Dọn trùng LẦN HAI sau khi gộp  ⭐ sửa lỗi thứ tự

`fix` chạy `dedup` ở bước ① (TRƯỚC khi gộp). Nhưng hợp nhất sinh ra bản PHỦ TRÙM
bản cũ ⇒ mục trùng chỉ lộ ra SAU khi gộp. Lượt chạy 26/08 để lại 1 mục mất + 2
mục trùng, người dùng phải chạy `fix --apply` **lần thứ hai** mới sạch.

Nay `fix` chạy `dedup` lại sau bước gộp. Một lượt là xong.

## `--title-suffix` — mở khoá việc gộp theo giai đoạn

Lời khuyên `--since/--until` của v3.0.0 **đúng một nửa**: dựng được file, nhưng
không có đường nào đưa quá một file vào Recents. Cả ba script tạo mục đều khoá
theo `(dự án, TIÊU ĐỀ)`:

- `restore-lost-entries.sh` — "nhóm đã có mục → không đụng"
- `repair-missing-sessions.sh` — "cùng hội thoại với mục đã có" + CHỐT SỐ 2

Ba chốt đó chính là thứ đã chặn vụ đẻ 555 mục rác 12/08 — **không được nới**.
Nên `merge` nhận `--title-suffix "(07/2026)"` để đặt tên riêng cho bản hợp nhất
của từng giai đoạn. Tên khác thật ⇒ ba chốt tự cho qua, không nới gì cả.
Chỉ sửa tiêu đề của FILE MỚI; nhánh nguồn không bị đụng.

## `unify` — nối lại lệnh vốn ĐÃ CÓ (sửa một sai lầm của chính bản vá này)

Bản nháp v3.1.0 tự viết một script mới `teams.sh` cho việc "đổi tài khoản mà
không mất danh sách". **Sai — kit đã có sẵn `setup-unified-sessions.sh` từ
v2.0.0, chạy thật ngày 15/06/2026.** Nó chỉ chưa được nối vào dispatcher.
`teams.sh` đã bị XOÁ.

Sai lầm kèm theo, nghiêm trọng hơn, là hiểu ngược nguyên nhân: bản nháp ghi
"9/10 thư mục là symlink — đó là cách app tự làm". **Ngược hoàn toàn.** Claude
Desktop luôn tạo thư mục RIÊNG cho mỗi tài khoản/team:

```
claude-code-sessions/<tài-khoản>/<team>/local_*.json
```

Đăng xuất rồi đăng nhập tài khoản khác ⇒ app đọc thư mục khác ⇒ **mất trắng
danh sách cũ**. Đây chính là sự cố gốc đã dẫn tới việc lập bộ kit này.

9 symlink đang có là **do kit tạo ra** ngày 15/06, không phải app. Hệ quả thực
tế: **phải chạy lại `unify --apply` sau mỗi lần thêm tài khoản, thêm team, hoặc
sau khi Claude Desktop cập nhật** — thứ mà cách hiểu sai kia sẽ khiến bỏ qua.

Đo 27/08/2026: 1 thư mục thật còn sót (`d26e7c83…/d00b1a05…`, 0 phiên) — tài
khoản hiện tại, một team khác. Chuyển sang team đó thì Recents trống trơn.

`setup-unified-sessions.sh` làm nhiều hơn `teams.sh` đã định làm: gộp cả thư mục
team CÓ phiên vào shared trước khi trỏ symlink (không mất mục nào), backup kèm
MANIFEST + `status-before.txt` + `layout-before.txt` vào `recovery-data/`, hoãn
thư mục đang hoạt động xuống cuối cùng, và có `rollback-unified-sessions.sh`
đi kèm.

Định tuyến mới:

```
claude-history unify                       → setup-unified-sessions.sh
claude-history unify --apply
claude-history unify --rollback <thư-mục>  → rollback-unified-sessions.sh
```

`check` thêm chiều ⑥ để biết TRƯỚC khi đổi tài khoản, không phải đợi mất mới biết.

⚠️ Hệ quả của danh sách dùng chung: xoá / đổi tên / lưu trữ là **toàn cục**.

## Cách gọi lệnh: giữ ĐƯỜNG DẪN ĐẦY ĐỦ

Bản nháp có thêm `claude-history install` tạo symlink `ch` trong `~/.local/bin`.
**Đã gỡ bỏ theo yêu cầu người dùng**: luôn gõ đường dẫn đầy đủ để thấy rõ đang
chạy bản nào, ở đâu. Hai symlink đã tạo cũng đã xoá.

Kèm theo đó, đoạn gỡ symlink trong `HERE` cũng được trả về bản gốc — không còn
symlink nào để gỡ.

## Không đổi

Không đụng vào `repair-missing-sessions.sh`, `restore-lost-entries.sh`,
`dedup-entries.sh`, `store.sh`, `safe-quit.sh`, `status.sh`. shellcheck sạch toàn bộ 16 script.

---

# CHANGELOG — claude-desktop-recovery-kit

Đánh số theo [Semantic Versioning](https://semver.org/).

> Dấu hiệu: bộ kit này được tạo/cập nhật với sự hỗ trợ của **Claude** — công cụ **Claude Code**, model **Claude Opus 4.8**.

## [3.0.0] — 2026-08-26

> Tạo từ v2.3.1 (sao chép + sửa khác biệt); **giữ nguyên v2.3.1** đóng băng.
> `latest -> v3.0.0`. Sao lưu trước khi vá: `recovery-data/script-bak-v231-20260826-125942/`.

### Thay đổi phá vỡ
- **Kho lưu trữ đổi từ hardlink snapshot sang GIT.** `snapshot.sh` và `backup-now.sh`
  vẫn chạy nhưng in cảnh báo có bản thay thế. Alias `cbackup` không còn là đường chính.
- **Một lệnh gốc `claude-history`** thay cho việc nhớ 14 script. Alias mới: `ch`.

### Vì sao đổi sang git — số đo thật trên máy này
| | |
|---|---|
| `~/.claude/projects` | 5,7 GB |
| kho snapshot cũ (10 bản) | **7,5 GB** — nhiều hơn cả bản gốc |
| kho git (vô hạn bản) | **2,5 GB** |
| ghi thêm 1,5 MB vào 3 transcript | rsync chép **64.440 KB** · git tốn **0 KB** |

`rsync --link-dest` chỉ liên kết cứng file **không đổi**. Claude ghi thêm vào transcript
liên tục ⇒ file đổi ⇒ chép lại nguyên file. Dấu vết: snapshot phình `3,0 → 3,5 → 4,5 → 5,6 GB`.

Nén thử trên mẫu 207 MB: gốc 207 · gzip 129 · zstd-19 81 · **git+gc 34 MB**. Tỉ lệ thay đổi
theo thư mục (2×–6×) vì git giới hạn cửa sổ tìm delta — thư mục 1067 file cho tỉ lệ kém nhất.

### Thêm mới
- **`~/DATA/claude-store/`** (chmod 700): `transcripts.git` + `index.git`, đều **bare và nằm
  NGOÀI thư mục dữ liệu** (`--git-dir` riêng, `--work-tree` trỏ vào). Kiểm chứng: **không một
  file lạ nào sinh ra** trong `~/.claude` hay thư mục Claude Desktop.
- **Chỉ mục Recents nằm dưới git** (2,6 MB). Từ nay mọi lệnh ghi nguy hiểm đều `git revert`
  được — cả ba sự cố 12/08, 18/08, 26/08 lẽ ra chỉ là một lệnh hoàn tác.
- **`store.sh`** — `save` / `verify` / `log` / `compact` / `list` / `show` / `restore`.
  `save` và `verify` chỉ ĐỌC nên chạy được khi Claude đang mở; `restore` mặc định **không
  ghi đè** bản sống mà xuất ra `.restored-<TS>`.
- **`claude-history check`** — kiểm tra cả 5 chiều trong một lệnh rồi in ra đúng lệnh cần chạy.
  Ngay lần chạy đầu đã bắt được một mất mát mới: "REDANCE-1877" (633 tin nhắn) không có mục nào.

### Thiết kế: dispatcher MỎNG, không viết lại
Đo từ `~/.zsh_history` (1425 dòng): **3 script chiếm ~90% lượt dùng**
(`repair` 132 · `status` 53 · `safe-quit` 44), còn **2 script chưa từng chạy lần nào**.
Người dùng phải nhớ 14 script / 17 cờ / 7 alias để làm 5 việc — và đã hỏi
*"tôi nên làm gì tiếp theo?"* **5 lần** trong một phiên.

Ban đầu định **viết lại** 12 script thành một. Đã rút lại: viết lại mã đang chạy đúng là cách
nhanh nhất để sinh lỗi mới. Dispatcher chỉ định tuyến và truyền tham số — rủi ro hồi quy gần
như bằng không, UX thu được y hệt. So sánh với `just` (thêm phụ thuộc vào chính công cụ cứu hộ)
và `make` (BSD/GNU khác nhau trên macOS, sinh ra để biên dịch) — cả hai đều thua ở ngữ cảnh này.

### 🔴 shellcheck — chạy lần đầu trong lịch sử dự án
`0 lỗi · 0 warning · 18 ghi chú style` → sau khi vá: **0 cảnh báo trên toàn bộ 14 script**.

- **5/18 là cảnh báo SAI (`SC2009`).** shellcheck khuyên thay `ps -Ao args | grep` bằng
  `pgrep`. Đo lúc Claude đang chạy: `pgrep -x Claude` → **0 tiến trình**, `ps -Ao args` → **1**.
  Nghe theo sẽ làm chốt "Claude đã tắt chưa" luôn trả lời sai ⇒ lệnh ghi chạy khi app đang mở,
  đúng nguyên nhân sự cố 12/08. Đã chặn kèm lý do trong mã, KHÔNG sửa theo.
- 13 cảnh báo còn lại (`SC2295` `SC2012` `SC2059`) đã vá. `status.sh` sửa xong được đối chiếu
  từng dòng với v2.3.1: **kết quả giống hệt**, chỉ khác dấu thời gian và số phiên bản.

### 🔴 Bốn lỗi trong `store.sh` — tự viết, tự tìm ra sau 40 phút
1. **`gc.auto 0` ⇒ kho phình mãi mãi.** Sau đúng 2 lần `save`: 21 object rời / 28 MiB, không
   bao giờ tự dọn. Đã gỡ override; thêm `compact` cho bản nén sâu thủ công.
2. **`save` hỏng im lặng.** Mẫu `commit && echo "da ghi"` ⇒ commit thất bại thì in ra **dòng
   trống**, `exit=0`. Ổ đầy hoặc mất quyền ghi sẽ báo "thành công". Tái hiện được. Đã đổi sang
   `if/then/else`, báo lỗi ra stderr, `exit 1`.
3. **Hai lệnh chạy chồng nhau** ⇒ git báo `index.lock` thô. Đã bắt trước và nói rõ.
4. **`SC2015`** — `[ ... ] && echo "✅" || { echo "⛔"; exit 1; }`: nếu `echo` thất bại thì
   nhánh `||` chạy, báo kho hỏng trong khi kho tốt.

Kiểm chứng mã thoát: có khoá → 1 · không ghi được → 1 · bình thường → 0.

### 🔴 `verify` từng báo ĐẠT trong khi không kiểm gì
Bản đầu dùng `shuf` để lấy mẫu — **macOS không có `shuf`**. Lệnh thất bại âm thầm, mẫu rỗng,
vòng lặp không chạy, và verify in `✅ Kho toàn vẹn` với `0 · 0 · 0`. Đã đổi sang `sort -R` và
thêm chốt: **mẫu rỗng ⇒ TRƯỢT**. Đây là lần thứ tư trong dự án một chốt an toàn hỏng vì đặt sai chỗ.

### Kiểm chứng
- **Đối chiếu TOÀN BỘ, không lấy mẫu**: transcript 4.301/4.319 giống từng byte; chỉ mục
  **334/334, 0 khác**. Ba khác biệt đều giải thích được (2 file bản sống dài hơn vì Claude
  đang ghi, 1 file dấu thời gian). 15 file "không còn" là rác tạm (`sessions/` lock,
  `.claude.json.backup.*` xoay vòng).
- `git fsck` sạch ở cả hai kho.
- 14 script cú pháp hợp lệ, `shellcheck` 0 cảnh báo.

### Thêm mới — `fix` sửa TẤT CẢ trong một lệnh (26/08 tối)
Người dùng nêu rõ: **gần như luôn khôi phục hết, không sửa lẻ từng mục**. Trước bản này
phải nhớ và chạy tay 5 lệnh theo đúng thứ tự — và đã bỏ sót một bước thật (26/08: quên
trỏ mục sau khi hợp nhất, mất 3 đoạn).

- **`fix-all.sh`** — sửa cả hai chiều theo đúng thứ tự: ① DANH SÁCH (`lost` → `orphan`
  → `dup`) rồi ② NỘI DUNG (`merge --apply --point` cho từng chuỗi).
  **Danh sách phải trước** vì `merge --point` cần một mục Recents để trỏ vào.
- **Chạy lại được (idempotent):** mọi phép đo so nội dung thực tế, không dựa vào cờ
  đã-chạy-hay-chưa. Chuỗi nào đã đủ thì lần sau tự bỏ qua.
- **Một chuỗi hỏng không dừng cả lượt** — báo lỗi rồi đi tiếp, cuối cùng tổng kết
  `hợp nhất N · bỏ qua M`, thoát mã 1 nếu có lỗi.
- **`merge --ids`** — đầu ra đọc-máy, mỗi dòng một mã, KHÔNG cắt ở 25 như `--list`.
  clig.dev: người đọc là mặc định, máy đọc thì phải xin.
- Cờ `--list-only` / `--content-only` cho ai cần sửa một chiều.

### Trợ giúp viết lại theo clig.dev
Bản cũ liệt kê 30 dòng phẳng mọi lệnh. clig.dev: *"display a concise help text by
default"* và *"lead with examples — by far the most read section"*.
Bản mới mặc định **13 dòng, dẫn bằng quy trình 3 bước**; `claude-history help all` mới
hiện đầy đủ. `fix` không tham số nay **xem trước việc sửa** thay vì in trợ giúp — đúng
với việc người dùng làm nhiều nhất.

### Đo được
- 43 chuỗi đang thiếu nội dung · **11 chuỗi có hoạt động từ 24/08** (thứ thật sự cần).
- Một lần `merge` mất **31 giây** ⇒ `fix --apply` toàn bộ ~23 phút. Script tự in ước tính.
- Chuỗi `REDANCE-1715` (699 nhánh, 2940 MB nguồn, 55.631 bản ghi thiếu) sẽ bị chốt kích
  thước chặn (~554 MB kết quả) — `fix-all` bỏ qua và chỉ sang `--since/--until`.

### 🔴 CỬA SỔ CHẾT — quy trình 3 lệnh làm mất nội dung (phát hiện 26/08 17:30)
Quy trình tôi hướng dẫn là **3 lệnh rời**: `merge --apply` → `quit` → `fix stale --apply`.
Mọi tin nhắn gửi trong khoảng giữa lệnh 1 và lệnh 3 rơi vào nhánh CŨ và **mất lối vào**.

Đo thật trên hội thoại "Recover missing Claude conversations and sessions":
merge chạy 17:15 dựng `f1a7de48` (406 tin nhắn) · người dùng nhắn tiếp tới 17:21 vào
`dbbac77a` · `fix stale` chạy 17:24 trỏ sang `f1a7de48` ⇒ **3 đoạn trong cửa sổ 6 phút
đó mất lối vào**. `fix stale` tự in `(+275 / -3)` — con số `-3` chính là cửa sổ chết,
nhưng không ai đọc nó như một lỗi quy trình.

**Vá — `merge --apply --point`:** dựng file RỒI trỏ mục Recents trong CÙNG một lệnh.
Đòi hỏi Claude Desktop đã tắt — và chính vì app đã tắt nên **không có tin nhắn mới nào
sinh ra giữa hai việc** ⇒ cửa sổ chết = 0. Chặn SỚM ngay đầu lệnh nếu app đang chạy,
để không dựng file 20 MB rồi mới từ chối (file đó sẽ thành nhánh thừa nằm lại trên đĩa).
Có `.bak-<TS>` và lệnh hoàn tác như mọi thao tác ghi khác.

Quy trình đúng còn **3 bước, cửa sổ chết = 0**:
`claude-history quit` → `claude-history merge --id <mã> --apply --point` → `open -a Claude`

### Bài học
Lỗi không nằm trong bất kỳ script nào — cả 3 lệnh đều chạy đúng. Lỗi nằm ở **khoảng
trống giữa chúng**. Thao tác nhiều bước trên dữ liệu đang thay đổi phải gộp thành một
thao tác nguyên tử, hoặc phải đóng băng dữ liệu trước khi bắt đầu.

### Còn lại — CHƯA sửa
- **Kho cùng ổ với bản gốc.** Chống xoá nhầm triệt để, KHÔNG chống hỏng ổ. Người dùng chỉ có
  1 ổ, từ chối ổ ngoài và Time Machine. Không script nào vá được.
- `merge` làm phẳng `parentUuid` rồi sắp theo thời gian. App đọc được (đã kiểm chứng thật:
  app mở file hợp nhất và ghi tiếp bình thường), nhưng không phải cấu trúc app tự sinh.
- `MIN_BYTES = 20.000` bỏ qua transcript nhỏ.
- Hook `PreCompact`/`SessionEnd` (GĐ 5) và dọn 7,5 GB snapshot cũ (GĐ 6) chưa làm.

## [2.3.1] — 2026-08-26

> Tạo từ v2.3.0 (sao chép + sửa khác biệt); **giữ nguyên v2.3.0** đóng băng để tra cứu.
> `latest -> v2.3.1`. Sao lưu script trước khi vá: `recovery-data/script-bak-v231-20260826-125942/`.

### 🔴 Sự cố — hợp nhất làm rơi khối lệnh
- **`merge-branches` bỏ mất 493 bản ghi** (247 `tool_use` + 244 `tool_result` + 2 `thinking`)
  của 11 nhánh khi hợp nhất. Không bản ghi nào trong số đó có chữ, nên phần hội thoại
  người đọc được vẫn nguyên — nhưng các khối lệnh và kết quả thì rơi mất.
- **Nguyên nhân:** `key_of()` chỉ băm phần `text`. Bản ghi thuần tool ⇒ vân tay `None`,
  mà vòng hợp nhất bỏ qua mọi dòng `key=None`.
- **Chỗ nguy hiểm nhất:** phép kiểm chứng ⑧ ("bao trùm nhánh X") dùng **chính vân tay
  hỏng đó**, nên nó không bao giờ phát hiện được lỗi do chính nó gây ra —
  *đo cái thước bằng chính cái thước cong*. Đây là lần thứ ba trong dự án một chốt an
  toàn hỏng vì đặt sai chỗ.

### Bài học kiến trúc: MỘT vân tay, HAI vai trò xung khắc
Vân tay nội dung bị dùng cho hai việc đòi hỏi ngược nhau:

| Vai trò | Cần gì | Nếu dùng nhầm |
|---|---|---|
| **NHẬN DẠNG** (union-find: hai bản này có cùng một hội thoại không?) | vân tay **ĐẶC TRƯNG** | thêm tool ⇒ nối nhầm hội thoại rời nhau |
| **PHỦ KÍN** (nội dung này đã đọc được từ mục khác chưa?) | vân tay **ĐẦY ĐỦ** | thiếu tool ⇒ dọn nhầm mục còn nội dung |

Đo thật trên máy này (200 file lớn nhất): vân tay `tool` bị dùng chung giữa nhiều hội
thoại khác nhau — **3.903/29.413 vân tay xuất hiện ở >1 hội thoại**, một vân tay có mặt
ở tới **12 hội thoại**. Gộp chúng vào phép nhận dạng sẽ nối nhầm hàng loạt.

⇒ Tách hẳn hai vân tay trong cả 4 script: `fp` (chữ, để nhận dạng) và
`fpx`/`fp_x`/`key_of` (đầy đủ, để đo phủ kín và để hợp nhất).

### 🔴 Sự cố — hai script đá nhau thành vòng lặp
- `dedup-entries` dọn mục theo tiêu chí "nội dung đã phủ kín bởi mục khác"; ngay sau đó
  `repair` thấy transcript không còn mục nào trỏ vào nên coi là **mồ côi** và định tạo
  lại đúng mục vừa dọn (gặp thật: `240ef0f0`, `b8aa66fb`).
- Union-find không bắt được vì nó đòi **≥2** vân tay dùng chung, mà hai phiên đó chỉ có
  1 đoạn nội dung nên không bao giờ nối được vào nhóm.
- **Vá — CHỐT SỐ 3 trong `repair`:** bỏ qua ứng viên có nội dung nằm **trọn** trong tập
  đọc được từ các mục đang có. Dùng **cùng một thước** với `dedup` (vân tay đầy đủ) —
  hai script khác thước thì vòng lặp quay lại. `restore-lost-entries` cũng nhận chốt này.
- **Chứng minh không còn vòng lặp:** phạm vi của `repair` (mọi mục) là **tập cha** của
  phạm vi `dedup` (trong cùng nhóm), nên `dedup` dọn X ⇒ `repair` chắc chắn bỏ qua X.

### 🔴 Sự cố — bản sao sinh ra từ git worktree
- Worktree tạo thư mục dự án riêng `<dự-án>--claude-worktrees-<slug>`. Cả 3 script gom
  nhóm theo `(dự án, tiêu đề)` nên **cùng một hội thoại tiếp tục trong worktree bị xếp
  sang nhóm khác** ⇒ không script nào dọn được bản trùng.
- Đo thật khi dựng lại danh sách từ chỉ mục rỗng: **6 mục cùng tên nằm ở 6 thư mục
  worktree khác nhau, nội dung chồng lấp tới 97%**, mà `dedup` vẫn báo "không có mục trùng".
- **Vá:** `normproj()` cắt hậu tố worktree trước khi gom nhóm, trong cả 3 script.
- Máy này có **16/25 thư mục dự án là worktree** — không phải trường hợp hiếm.

### Sửa / Vá
- **`dedup`: ngưỡng nối nhóm 1 → 2 đoạn dùng chung.** Ngưỡng 1 quá lỏng — một câu mở đầu
  lặp lại đủ để nối hai hội thoại rời. Gặp thật: `ff4ee253` và `9d10be11` chung 1/17 đoạn
  (6%) mà vẫn bị gom, khiến một hội thoại riêng bị gắn nhãn "⤷ lưu trữ" của hội thoại khác.
  `repair` đã dùng ngưỡng 2 từ trước — hai script phải cùng một thước.
- **`merge`: ngưỡng quy mô đo SAI THỨ.** Bản cũ chặn theo *tổng nguồn* (40 nhánh / 250 MB),
  trong khi thứ quyết định app mở nổi hay không là *file kết quả*. Các nhánh chồng lấp rất
  nhiều: REDANCE-1715 = **2941 MB nguồn → 554 MB kết quả**. Ước lượng theo tỉ lệ cũng sai
  (thử: báo 2 MB cho cả chuỗi 14 nhánh lẫn chuỗi 699 nhánh). ⇒ Chặn thô trước khi dựng
  (200.000 bản ghi, chỉ để khỏi vỡ bộ nhớ) + **phép ⑨ đo CHÍNH XÁC trên nội dung sắp ghi**,
  ngay trước khi ghi file.
- **`merge --since/--until`** — hợp nhất theo GIAI ĐOẠN. Mở khoá hai hội thoại nặng nhất
  vốn không gộp được: REDANCE-1715 (699 nhánh) và Phong thủy (61 nhánh). Mục Recents hiện
  tại luôn được giữ trong tập gộp, nếu không `--fix-stale` sẽ không có gì để trỏ.
- **`merge`: bộ nhớ 4,85 GB → 243 MB, thời gian 98s → 33s.** Bản cũ cache cả danh sách
  dòng đã phân tích của MỌI transcript (5,6 GB trên máy này). Nay chỉ giữ tiêu đề + hai
  tập vân tay; nội dung đọc lại khi thật sự hợp nhất, chỉ cho nhánh liên quan.
- **`merge` in sẵn lệnh tiếp theo kèm đúng mã phiên.** `--id` và `--only` dùng **hai không
  gian mã khác nhau** (`--only` khớp theo phiên mà MỤC đang mở), gõ nhầm thì fix-stale báo
  "không mục nào khớp" — đã xảy ra thật ngày 26/08.
- **`clean-junk-entries.sh` NGỪNG DÙNG** — cần `--force-legacy` mới chạy. Nó đoán "rác"
  theo dấu hiệu (`enabledMcpTools` rỗng + `effort=high`) mà **mục do app tạo cũng có**, và
  hoàn toàn mù với nội dung. Chính nó xoá mất mục gốc của "Phong thủy…" ngày 18/08.
  `dedup-entries` làm cùng việc nhưng **chứng minh được** nội dung vẫn đọc ra.
- **`safe-quit --deep`** — kiểm tra thêm chiều thứ 5: NỘI DUNG bên trong (nhánh chưa gộp).
  Không bật mặc định vì tốn ~30 giây; bản thường in một dòng nhắc rằng bốn phép kia chỉ
  nói về DANH SÁCH.
- Đồng bộ số phiên bản trong header 4 script (còn ghi v2.2.0 trong khi VERSION đã lên).

### Kiểm chứng
- **Dựng lại danh sách từ chỉ mục RỖNG** (phép thử mạnh nhất): `repair --apply` →
  `restore-lost --apply`, lặp đến điểm bất động. **Hội tụ sau 4 vòng ở 122 mục**, cả ba
  script đều báo sạch. 115 nhóm `(dự án gốc, tiêu đề)` phân biệt; 7 nhóm còn >1 mục là các
  hội thoại **thật sự khác nhau** trùng tiêu đề tự sinh, `dedup` xác nhận không trùng nội dung.
- **Hợp nhất hội thoại này**: 14/14 nhánh `⑧ bao trùm … 0` với vân tay ĐẦY ĐỦ (bản cũ chỉ
  bao trùm phần chữ).
- `dedup --apply` không đụng một byte nào của transcript: băm toàn bộ `~/.claude/projects`
  trước và sau — 3504 file · 5.908.588.495 byte · hash không đổi.
- 13/13 script cú pháp hợp lệ và chạy được; chỉ mục thật giữ nguyên 174 mục suốt phiên vá.

### Còn lại — CHƯA sửa
- **`merge` làm phẳng `parentUuid`** rồi sắp theo thời gian: cấu trúc rẽ nhánh bị san thành
  một mạch thẳng. App đọc được (đã kiểm chứng thật: app mở file hợp nhất và ghi tiếp bình
  thường), nhưng đây không phải cấu trúc app tự sinh ra.
- **`MIN_BYTES = 20.000`** bỏ qua transcript nhỏ. Hiện vô hại (8 file dưới ngưỡng, không
  file nào có ≥2 lượt hỏi thật) nhưng vẫn là rủi ro tiềm ẩn.
- **Chưa có Time Machine.** Snapshot nằm CÙNG Ổ với bản gốc — chống xoá nhầm, KHÔNG chống
  hỏng ổ. Đây là lỗ hổng lớn nhất còn lại và không script nào vá được.

## [2.3.0] — 2026-08-26
> Tạo từ v2.2.0 (sao chép + sửa khác biệt); **giữ nguyên v2.2.0** đóng băng để tra cứu.
> `latest -> v2.3.0`.
>
> ⚠️ v2.2.0 vẫn còn `--only <số thứ tự>` và `safe-quit` tự chạy `repair --apply` —
> đúng hai thứ gây mất dữ liệu ngày 26/08. **Gõ đường dẫn `versions/latest/bin/…`,
> đừng gõ số phiên bản**, để không lỡ chạy lại bản cũ theo thói quen.

### 🔴 Sự cố
- **`--fix-stale --apply --only 1,2,3,4` làm REDANCE-1715 tụt từ 89 xuống 48 đoạn nội dung**
  (1102 → 248 tin nhắn). Chốt an toàn KHÔNG hỏng: dựng lại chỉ mục trước lúc chạy trong
  sandbox rồi chạy lại đúng script, nó in ra cả 4 mục đều `🔴 … mặc định BỎ QUA`.
  `--all` không liên quan (chỉ đặt `SINCE=0`, mà `--fix-stale` đã đặt sẵn).
  Mất là do `--only` ép chạy — đúng thiết kế, sai công cụ.
- **Nguyên nhân gốc: `--only` nhận SỐ THỨ TỰ.** Danh sách đánh số lại sau mỗi lần sửa,
  nên `--only 1,2,3,4` hôm nay trỏ vào hội thoại khác hôm qua. `~/.zsh_history` cho thấy
  vòng lặp `safe-quit → --all → --only 1,2…` đã lặp ~10 lần trong nhiều ngày.

### Thay đổi phá vỡ
- **`--only` nay nhận MÃ PHIÊN 8 ký tự** (`--only 58dfea02`), khớp với bản đang mở hoặc
  bản mới. Đưa vào số → dừng, báo lỗi. Mã không khớp mục nào → dừng, báo lỗi.
  Mã phiên không bao giờ đổi nghĩa giữa hai lần chạy.
- **`safe-quit.sh` KHÔNG CÒN GHI GÌ vào chỉ mục.** Bỏ hẳn bước `repair --apply` tự động.
  Thay bằng: thoát êm → snapshot → kiểm tra chỉ đọc → **in ra lệnh** nếu thiếu.
  Lý do: cả 3 lần mất dữ liệu của dự án đều do một lệnh GHI chạy khi không cần
  (12/08 repair, 18/08 clean-junk, 26/08 fix-stale). Chưa lần nào mất vì thiếu chạy script.
  Sửa chỉ mục là việc CHỮA, không phải việc PHÒNG.

### 🔴 Sự cố thứ hai (phát hiện 26/08 khi soi ảnh chụp danh sách của người dùng)
- **`repair --apply` VẪN đang đẻ mục trùng hàng loạt** — lỗi còn sống, khác lỗi 12/08.
  Bằng chứng đọc từ mtime file chỉ mục: `23/08 13:01:44 → 14 file cùng lúc`
  ("Phong thủy hành lang và cửa sân sau"), `18/08 14:38:07 → 6 file`
  ("REDANCE-1715 Mail investigation"). Tổng cộng 35 mục trùng đang nằm trong danh sách.
- **Nguyên nhân:** nhánh `distinct = True` — *"trùng tiêu đề nhưng khác thành phần liên
  thông ⇒ hội thoại riêng"* — VÔ HIỆU HOÁ bộ lọc "bản rẽ nhánh cũ", nên **mỗi** đoạn
  rewind thành **một** mục. Union-find gom theo lượt hỏi chung; các bản rewind cũ
  (06–10/08) không chia sẻ lượt hỏi nào với đoạn nén mới nhất → không gom được →
  mỗi đoạn tự thành một "hội thoại riêng". Đã kiểm chứng: nới trần `len(ids) > 60`
  KHÔNG sửa được (vẫn 21 mục) — lỗi nằm ở logic, không ở ngưỡng.
- **Vá — CHỐT SỐ 2 "một hội thoại một mục":** sau mọi phân loại, gom các ứng viên theo
  `(dự án, tiêu đề)` và chỉ giữ MỘT. Chốt đặt cuối, không thể bị nhánh nào bỏ qua, và
  **không phụ thuộc union-find có đúng hay không** — nó chặn theo đúng thứ người dùng
  nhìn thấy trong danh sách. Kiểm chứng trên sandbox tái lập đúng trạng thái: **21 → 3**.

### Thêm mới
- **`dedup-entries.sh`** — dọn mục trùng đang tồn tại. **Không bao giờ đụng vào transcript**:
  chỉ di chuyển file `local_*.json`. Kiểm chứng bằng cách chạy thật `--apply` trên chỉ mục
  sandbox rồi băm lại toàn bộ `~/.claude/projects`: **3504 file · 5.908.588.495 byte, hash
  y nguyên trước/sau**. Hoàn tác cũng đã kiểm: 178 mục về đúng 178, 0 file lệch nội dung.
  Hai chế độ, khác nhau ở chỗ có ẩn lối vào nội dung cũ hay không:
  | chế độ | dọn | ẩn nội dung | danh sách còn |
  |---|---|---|---|
  | **PHỦ KÍN** (mặc định) | 11 mục | **0 đoạn** | 35 mục |
  | `--newest-only` | 35 mục | 755 đoạn | 11 mục |
  Mặc định chỉ dọn mục có nội dung NẰM TRỌN trong các mục được giữ (bao phủ tham lam từ
  bản mới nhất trở đi) → bảo đảm mọi tin nhắn mở được trước khi chạy thì sau vẫn mở được.
  Các mục lưu trữ được đổi tên thêm hậu tố `⤷ lưu trữ <dd/mm HH:MM>` (có `.bak-<TS>`) để
  danh sách đọc được thay vì 15 dòng trùng tên — nhãn có cả giờ vì gặp thật hai nhánh
  cùng ngày 07/08.
  Bản nháp đầu dùng quy tắc "giữ bản nhiều nội dung nhất" và suýt dọn mất đúng hai mục
  đang dùng (Phong thủy giữ nhánh rewind 10/08, REDANCE-1715 giữ bản 05/08 thay vì mục
  app đang trỏ tới). Quy tắc đúng: **giữ bản có TIN NHẮN MỚI NHẤT**.
- **Đo được: hợp nhất KHÔNG phải lối thoát cho hội thoại rất dài.** Ngưỡng của
  `merge-branches.sh` đếm NGUỒN (`40 nhánh / 250 MB`) trong khi thứ quyết định app có mở
  nổi hay không là KẾT QUẢ. Đo thật: Phong thủy 61 nhánh · 1090 MB nguồn → **226 MB** hợp
  nhất; REDANCE-1715 699 nhánh · 2941 MB nguồn → **597 MB**. Cái sau không dùng được.
  Vì vậy với hội thoại rất dài, "một mục thấy trọn nội dung" hiện KHÔNG khả thi —
  phải chấp nhận nhiều mục lưu trữ (chế độ phủ kín).
- **`--fix-stale` nay trỏ sang bản ĐỦ NHẤT, không phải bản MỚI NHẤT.** Đoạn mới nhất của
  hội thoại dài thường VỪA BỊ NÉN NGỮ CẢNH — chỉ chứa tóm tắt cộng vài lượt cuối.
  Đo 26/08: REDANCE-1715 đoạn mới nhất 48 đoạn nội dung, đoạn trước đó (cách 6 phút)
  267 đoạn. Quy tắc cũ "trỏ sang mới nhất" = tự tay bỏ 219 đoạn. Nay lấy bản nhiều nội
  dung nhất trong 24h cuối của chuỗi; hoà thì ưu tiên bản mới hơn.
  Hệ quả: số mục hiện ra tăng từ 1 lên 14 — không phải hỏng thêm, mà là **trước đây tool
  không nhìn thấy**. Thêm nhãn 🟡 (được nhiều hơn mất) tách khỏi 🔴 (mất nhiều hơn được),
  và ghi rõ ngay trong output rằng đây là ĐÁNH ĐỔI, danh sách không cần làm cho rỗng.
- **`safe-quit.sh` mặc định KHÔNG mở lại app.** Tên script nói "quit" thì mặc định phải là
  thoát; trước đây nó tự mở lại và phải gõ `--no-reopen` để nó đừng mở — trái với tên.
  Nay `--reopen` là cờ để bật. `--no-reopen` vẫn nhận (không báo lỗi) để lệnh cũ vẫn chạy.
- **`restore-lost-entries.sh`** — bịt điểm mù của repair. Sau bản vá 12/08, repair bỏ qua
  MỌI đoạn nén tiếp nối, vô điều kiện; hệ quả phụ là hội thoại mà **mọi** đoạn đều là đoạn
  nén (fork tạo trong app, hội thoại rất dài) không bao giờ được tạo mục → mất vĩnh viễn
  khỏi danh sách. Đo ngày 26/08: 918 đoạn bị bỏ qua, **7 hội thoại không còn mục nào**
  (cũ nhất 16/07, mới nhất 26/08 03:12; có cái 1410 tin nhắn).
  Chốt: **chỉ tạo mục khi cả nhóm (dự án + tiêu đề) không có mục nào** → không thể đẻ trùng.
  Trỏ vào đoạn NHIỀU NỘI DUNG NHẤT trong 24h cuối, không phải đoạn mới nhất
  (đoạn mới nhất thường vừa bị nén nên rỗng ruột).

### Sửa / Vá
- **`clean-junk-entries.sh` không bao giờ dọn mục mới nhất của một tiêu đề.**
  Sự cố 18/08: hai điều kiện nhận diện rác (`enabledMcpTools=={}` + `effort==high`, và
  "trỏ vào đoạn nén") đều KHÔNG phân biệt được mục thật — mục app tự tạo cũng y hệt, và
  mọi hội thoại dài đều trỏ vào đoạn nén. Kết quả: dọn sạch cả 15 mục "Phong thủy hành
  lang và cửa sân sau", gồm cả mục gốc `titleSource=user`. Hội thoại biến mất khỏi danh sách.
  Nay dù nhận diện sai, mỗi tiêu đề luôn còn ít nhất một mục, và là mục mới nhất.

- **`status.sh` in ra RỖNG và exit 1 — sửa.** Toàn bộ báo cáo ghi vào `$TMP` rồi mới in;
  với `set -e`, chỉ một lệnh con trả mã khác 0 (grep không khớp, team chưa gộp…) là cả khối
  chết giữa chừng, `trap` xoá `$TMP` → im lặng tuyệt đối. Lỗi có từ v2.1.0, không ai thấy vì
  triệu chứng là "không in gì". Script BÁO CÁO không được dùng `set -e`.
- **`status.sh` Lớp C báo ✅ sai — sửa.** Nó chỉ hỏi `repair-missing-sessions.sh`, mà repair
  bỏ qua mọi đoạn nén tiếp nối → hội thoại mà MỌI đoạn đều là đoạn nén thì repair báo "đủ".
  Ngày 26/08 Lớp C báo ✅ trong khi 7 hội thoại đã mất hẳn khỏi danh sách. Nay hỏi CẢ
  `restore-lost-entries.sh`.

### Đo được, cần biết
- **Không có file đơn lẻ nào chứa cả hội thoại dài.** REDANCE-1715 có 699 đoạn, hợp lại
  13.183 đoạn nội dung; đoạn giàu nhất chỉ chứa **2%**. Mọi thao tác "trỏ lại" đều là đánh
  đổi, không phải khôi phục. Muốn một mục mở ra thấy đủ thì phải **hợp nhất**
  (`merge-branches.sh`).

### Bài học
Lần thứ ba một chốt an toàn thất bại — nhưng lần này chốt chạy đúng, **giao diện** sai:
số thứ tự động nghĩa giữa hai lần chạy. Định danh trong lệnh phá huỷ phải là thứ **bất biến**.

## [2.2.1] — 2026-08-17
### 🔴 Sự cố & vá gấp
- **`repair --apply` đẻ ra 555 mục Recents rác trong một lần chạy** (12/08/2026 15:00),
  501 mục cùng tên "REDANCE-1715 Mail investigation", mỗi mục chỉ chứa một lát cắt nội dung.
  Người dùng nhìn thấy: danh sách đầy hội thoại trùng tên, mở ra cái nào cũng thiếu.
- **Nguyên nhân:** chốt "đoạn nén tiếp nối thì không tạo mục riêng" bị đặt LỒNG BÊN TRONG
  nhánh *"cùng thành phần liên thông với mục đã có"*. Các đoạn nén thuộc thành phần **chưa**
  có mục thì không bao giờ chạm tới chốt đó → lọt hết. Lỗi do đợt sửa union-find sáng 12/08.
- **Vá:** đưa kiểm tra `is_cont` lên **đầu vòng lặp, vô điều kiện**. Sau khi vá, `--all` đề xuất
  1 mục thay vì 555; 141 đoạn nén bị bỏ qua đúng.
- **Thêm `clean-junk-entries.sh`** dọn hậu quả. Nhận diện rác = có dấu vết repair ghi
  **VÀ** trỏ vào transcript mở đầu bằng "This session is being continued…". Chuyển vào
  thùng rác (không xoá cứng), chặn khi app đang chạy, in lệnh hoàn tác.

### Bài học
Chốt an toàn phải đặt ở **vị trí không thể bị bỏ qua**, không nằm trong nhánh điều kiện.
Đây là lần thứ hai trong dự án một chốt an toàn hỏng vì vị trí đặt sai — lần đầu là
`grep -q` + `pipefail` (xem v2.2.0).

## [2.2.0] — 2026-08-06
### Bối cảnh
Phát hiện **59/119 mục trong Recents đã mất sạch nội dung**. Nguyên nhân: Claude Code
mặc định `cleanupPeriodDays: 30` — tự xoá transcript sau 30 ngày, im lặng. Bằng chứng:
transcript cũ nhất còn lại trên máy đúng **29 ngày**. v2.1.0 hoàn toàn không nhìn thấy
kiểu mất này vì nó chỉ lo phân mảnh chỉ mục giữa các team.

### Thêm mới
- **`repair-missing-sessions.sh`** — tự dò transcript mồ côi (còn nội dung nhưng không có
  mục Recents) và tạo lại mục chỉ mục. **Không chép cứng danh sách** nên bắt được cả phiên
  vừa tạo xong, kể cả phiên đang trò chuyện. Bỏ qua: phiên đã có mục, phiên **cố ý xoá**
  (file `deleted_<id>`), bản rẽ nhánh cũ (gom nhóm theo `(dự án, tiêu đề)`), phiên rỗng.
  Tiêu đề lấy từ bản ghi `custom-title`/`ai-title` trong chính transcript.
  Chỉ TẠO file mới; mặc định xem trước; chặn khi Desktop đang chạy; in sẵn lệnh hoàn tác.
- **`snapshot.sh`** — ảnh chụp hardlink (`rsync --link-dest`) của transcript + chỉ mục +
  cấu hình vào `~/DATA/claude-backups` (ngoài repo). Đo thực tế: bản đầu 3.0 GB/16 giây,
  **bản thứ hai tốn 1 MB**. Giữ 14 bản, tự dừng nếu ổ còn dưới 10 GB. Chạy được khi Claude đang mở.
- **LaunchAgent** `com.hieund.claude-backup` — snapshot tự động 12:30 và 20:30 mỗi ngày.
- **`status.sh` báo cáo đủ 4 lớp**: A symlink/chỉ mục · B `cleanupPeriodDays` ·
  C hội thoại mất khỏi Recents (số liệu lấy từ chính `repair-missing-sessions.sh`,
  một nguồn sự thật duy nhất) · D snapshot + LaunchAgent + Time Machine.

### Thêm mới (bổ sung cuối ngày 06/08)
- **`safe-quit.sh` — dùng thay Cmd+Q.** Gộp 3 việc vào 1 lệnh: thoát êm Claude bằng AppleScript
  → đợi tiến trình thật sự kết thúc → `repair --apply` → mở lại. Giải quyết dứt điểm việc
  "hội thoại mới tạo biến mất sau khi khởi động lại" mà **không cần tiến trình chạy nền hay
  lịch tự động** (người dùng đã từ chối chạy tự động). Có `--dry-run` an toàn tuyệt đối.
  Nếu sau 40s app chưa thoát (đang hỏi xác nhận) thì dừng, không thay đổi gì.
- **`repair-missing-sessions.sh --fix-stale`** — sửa trường hợp mục Recents vẫn còn nhưng
  trỏ vào bản rẽ nhánh CŨ (mở ra thiếu phần hội thoại mới). Đây là chế độ **SỬA mục đang có**,
  khác hẳn chế độ mặc định chỉ tạo mục mới → mỗi mục sửa đều có `.bak-<TS>` và lệnh `cp` hoàn tác.
  `--only 1,4` để chọn riêng vài mục. In số lượt hỏi + thời điểm tin nhắn cuối của cả hai bản
  để tự chọn, vì bản mới hơn thường đã bị nén ngữ cảnh nên "mới nhất" chưa chắc đầy đủ hơn.
  **Không bao giờ trỏ sang bản có dấu `deleted_`** (bắt được khi kiểm thử: 2 mục định trỏ sang
  phiên người dùng đã cố ý xoá).
- **`restore-from-backup.sh` tự đặt `cleanupPeriodDays`** sau khi bung dữ liệu. Máy mới mặc định
  30 ngày → khôi phục xong tưởng an toàn, **30 ngày sau mất lại đúng số transcript vừa khôi phục**.

### Sửa / Vá
- **Thứ tự chuỗi rẽ nhánh: dùng dấu thời gian TIN NHẮN CUỐI, không dùng `mtime`.** Thao tác sao
  chép hàng loạt đặt lại mtime của hàng trăm file cùng lúc (gặp thật: 648 file trong một phút
  ngày 05/08/2026) → mtime không còn cho biết bản nào mới hơn, `repair` có thể chọn nhầm bản
  làm "mới nhất" trong chuỗi. Danh sách chuỗi tụt sắp theo mtime ra kết quả **khác hẳn** so với
  sắp theo nội dung.
- **`tmutil destinationinfo` trả exit code 0 kể cả khi KHÔNG có đích sao lưu nào** →
  phải đếm dòng `^Name`. Bản nháp đầu của `status.sh` đã báo ngược (nói "có Time Machine"
  trong khi máy hoàn toàn không có).
- Ghi lại bẫy **`set -euo pipefail` + `grep -q`**: `grep -q` thoát sớm gây SIGPIPE cho lệnh
  trước → `pipefail` biến điều kiện thành sai → **càng khớp càng không chặn**. Sự cố thật:
  chốt an toàn hỏng, script chạy khi Desktop đang mở. Dùng `grep -c … || true`.
  *Đã rà 6 script v2.1.0 — không script nào dính lỗi này.*
- Ghi lại: **`pgrep` không thấy tiến trình chính của Claude Desktop** trên macOS (chỉ thấy
  helper). Mọi kiểm tra "Desktop tắt chưa" phải dùng `ps -Ao args`.

### Tương thích
- Viết cho **bash 3.2** (mặc định của macOS): không `mapfile`, không associative array,
  không khai triển mảng rỗng dưới `set -u`.
- `rsync` của macOS là `openrsync`; đã kiểm chứng `--link-dest` tạo hardlink thật.

## [2.1.0] — 2026-06-15
### Thêm mới (an toàn rollback theo version)
- Mỗi backup nay có **`MANIFEST.txt`** ghi: phiên bản kit, script tạo, thời điểm, máy, nội dung, và **lệnh rollback/khôi phục chính xác theo đúng version**.
- `setup --apply` tự lưu **`status-before.txt`** (ảnh chụp trạng thái ngay trước khi đổi) vào thư mục backup.
- `rollback` **kiểm tra version**: đọc `MANIFEST.txt`, nếu version backup ≠ version script thì cảnh báo + yêu cầu `FORCE`.
- **Quy ước tên thư mục backup**: `<TS>-<loại>-v<version>` (`-full-` = backup-now đầy đủ; `-apply-` = setup --apply rollback; `orphan-trash-<TS>-v<ver>` = thùng rác). Báo cáo: `status-<TS>-v<ver>.txt`. → nhìn tên biết loại + version. (Script đọc backup `rollback`/`restore` nhận đường dẫn làm tham số nên KHÔNG bị ảnh hưởng bởi tên.)
- Tạo từ v2.0.0 (sao chép + sửa khác biệt); **giữ nguyên v2.0.0** đóng băng. `latest -> v2.1.0`.

## [2.0.0] — 2026-06-15
### Thêm mới
- **Cơ chế "thư mục dùng chung (shared) + symlink"** thay cho copy: mọi tài khoản/team
  cùng trỏ symlink vào `claude-code-sessions-shared` ⇒ thấy CÙNG một danh sách, **tự động đồng bộ**.
- `setup-unified-sessions.sh` — gộp (ưu tiên VIP > Kaopiz SBU1 > 10-InnerTwo) + symlink. Có `--dry-run`/`--apply`/`--yes`.
- `rollback-unified-sessions.sh` — hoàn tác, trả folder team về vị trí gốc.
- `status.sh` — kiểm tra sức khoẻ symlink/shared, đối chiếu transcript. Cờ `--save` ghi báo cáo vào thư mục `reports/` (tách riêng khỏi `recovery-data/`).
- `clean-orphan-transcripts.sh` — dọn transcript mồ côi (liệt kê → thùng rác → xoá cứng, đều có xác nhận).
- Cấu trúc kit MỚI: 1 thư mục duy nhất gồm `shared/` (tài liệu chung) + `versions/` (các phiên bản) + `recovery-data/` (backup, tách khỏi công cụ).
- `RELATED-CONVERSATIONS.md` — liệt kê ID + transcript các cuộc trò chuyện liên quan để đọc lại.

### Sửa / Vá
- `backup-now.sh` & `restore-from-backup.sh` nay **bao gồm `claude-code-sessions-shared`**
  (bản v1 thiếu → khôi phục máy mới sẽ mất danh sách hợp nhất).
- Mọi backup gom vào thư mục có **dấu thời gian** `recovery-data/<YYYYMMDD-HHMMSS>/`.

### Vị trí kit
- Kit trở thành **DI ĐỘNG**: đặt ở bất kỳ thư mục an toàn nào người dùng chọn (không còn ở `~/Downloads`).
  Mọi script **tự định vị** qua đường dẫn của chính chúng (`BASH_SOURCE`) — KHÔNG hardcode vị trí kit.

## [1.0.0] — 2026-06-02  (đóng băng, xem versions/v1.0.0/)
- Bản đầu: copy `local_*.json` giữa các folder org khi đổi/deactivate team (`migrate-team-sessions.sh`),
  `backup-now.sh`/`restore-from-backup.sh`, `RESTORE-PROMPT.md`. Cơ chế copy thủ công.
