# Chủ đề 1 — Dòng lệnh Linux cơ bản

> **Mục tiêu:** hiểu dòng lệnh Linux hoạt động như thế nào, thay vì chỉ ghi nhớ tên lệnh.
>
> **Quy ước ngôn ngữ:** phần giải thích dùng Tiếng Việt. Chỉ giữ nguyên những tên chuẩn cần tra cứu trực tiếp như `Linux`, `Bash`, `POSIX`, `TTY`, `PTY`, tên lệnh, tên biến, toán tử và API.
>
> **Phạm vi:** giao diện dòng lệnh, `terminal`, `TTY`, `PTY`, `shell`, cấu trúc một dòng lệnh, dấu nháy, mở rộng của `shell`, `PATH`, biến môi trường, `stdin/stdout/stderr`, chuyển hướng, `pipe`, mã kết thúc, tiến trình tiền cảnh/nền và các công cụ quan sát cơ bản.
>
> Chương này chỉ có **lý thuyết**, không chứa bài thực hành.

---

## Mục lục

- [1. Dòng lệnh Linux thực chất là gì?](#1-dòng-lệnh-linux-thực-chất-là-gì)
- [2. Terminal, TTY, PTY và Shell](#2-terminal-tty-pty-và-shell)
- [3. Shell hiểu một dòng lệnh như thế nào?](#3-shell-hiểu-một-dòng-lệnh-như-thế-nào)
- [4. Dấu nháy và quá trình mở rộng của Shell](#4-dấu-nháy-và-quá-trình-mở-rộng-của-shell)
- [5. Shell tìm chương trình bằng `PATH` như thế nào?](#5-shell-tìm-chương-trình-bằng-path-như-thế-nào)
- [6. Thư mục làm việc và đường dẫn](#6-thư-mục-làm-việc-và-đường-dẫn)
- [7. Biến Shell, biến môi trường và `argv`](#7-biến-shell-biến-môi-trường-và-argv)
- [8. `stdin`, `stdout`, `stderr` và chuyển hướng](#8-stdin-stdout-stderr-và-chuyển-hướng)
- [9. Pipe và Pipeline](#9-pipe-và-pipeline)
- [10. Mã kết thúc và toán tử điều khiển Shell](#10-mã-kết-thúc-và-toán-tử-điều-khiển-shell)
- [11. Tiền cảnh, nền và điều khiển tác vụ](#11-tiền-cảnh-nền-và-điều-khiển-tác-vụ)
- [12. Các nhóm lệnh Linux cơ bản](#12-các-nhóm-lệnh-linux-cơ-bản)
- [13. `grep` và `find`: tìm kiếm theo hai mô hình khác nhau](#13-grep-và-find-tìm-kiếm-theo-hai-mô-hình-khác-nhau)
- [14. `ps`, `top`, `mount`, `df`, `du` đang quan sát điều gì?](#14-ps-top-mount-df-du-đang-quan-sát-điều-gì)
- [15. Tư duy gỡ lỗi khi một lệnh không hoạt động](#15-tư-duy-gỡ-lỗi-khi-một-lệnh-không-hoạt-động)
- [16. Liên hệ với Embedded Linux](#16-liên-hệ-với-embedded-linux)
- [17. Tổng kết](#17-tổng-kết)
- [18. Tài liệu tham khảo](#18-tài-liệu-tham-khảo)

---

## 1. Dòng lệnh Linux thực chất là gì?

> **Nói đơn giản:** dòng lệnh là cách người dùng mô tả yêu cầu bằng văn bản; `shell` đọc yêu cầu đó, phân tích nó và tạo ra các thao tác cần thiết.

### 1.1 CLI và GUI khác nhau ở đâu?

`GUI` đưa ra nút bấm, cửa sổ và biểu tượng. `CLI` đưa ra một ngôn ngữ lệnh.

```text
GUI
Người dùng
   |
   v
Nút / menu / cửa sổ
   |
   v
Ứng dụng

CLI
Người dùng
   |
   v
Dòng lệnh
   |
   v
Shell
   |
   v
Chương trình / lời gọi hệ thống
```

Điểm mạnh của `CLI` không nằm ở việc “gõ nhanh hơn”, mà ở khả năng **ghép nhiều công cụ nhỏ thành một luồng xử lý**.

Ví dụ về mặt khái niệm:

```text
nguồn dữ liệu
     |
     v
công cụ A
     |
     v
công cụ B
     |
     v
kết quả
```

Đây là tư duy rất quan trọng trong Linux và Embedded Linux vì nhiều hệ thống nhúng không có giao diện đồ họa đầy đủ.

### 1.2 Dòng lệnh không phải lời gọi hệ thống

Khi người dùng nhập:

```text
ls -l /etc
```

nhân Linux không nhận nguyên chuỗi này rồi “hiểu lệnh”. `shell` mới là thành phần phân tích chuỗi.

Mô hình đúng hơn:

```text
"ls -l /etc"
      |
      v
Shell phân tích
      |
      +--> tên chương trình: ls
      +--> argv[1]: -l
      +--> argv[2]: /etc
      |
      v
Shell tìm executable và tạo tiến trình
      |
      v
Chương trình ls gọi các API/lời gọi hệ thống cần thiết
```

---

## 2. Terminal, TTY, PTY và Shell

> **Nói đơn giản:** `terminal` là nơi nhập/xuất ký tự; `shell` là chương trình đọc và hiểu lệnh. Hai thứ này không phải một.

### 2.1 Terminal

`terminal` là giao diện nhập/xuất dạng ký tự. Trên máy hiện đại, phần mềm như trình giả lập terminal cung cấp cửa sổ để hiển thị ký tự và nhận phím.

### 2.2 TTY

`TTY` là lớp trừu tượng của Linux cho kiểu giao tiếp terminal/serial.

Nó gắn với các khái niệm như:

```text
thiết bị đầu cuối
chế độ nhập ký tự
line discipline
terminal foreground process group
```

`TTY` có nguồn gốc lịch sử từ teletype, nhưng trong Linux hiện đại nó là một subsystem quan trọng.

### 2.3 PTY

`PTY` là cặp thiết bị giả lập terminal:

```text
PTY master <------> PTY slave
```

Một chương trình phía master có thể đóng vai trò “terminal”, còn phía slave trông giống TTY đối với chương trình chạy bên trong.

Các trường hợp thường gặp:

```text
terminal emulator
SSH session
terminal multiplexer
```

### 2.4 Shell

`Shell` là trình thông dịch ngôn ngữ lệnh.

Ví dụ phổ biến:

```text
sh
Bash
dash
zsh
```

Trong tài liệu này, tư duy chuẩn ưu tiên `POSIX shell`; khi một hành vi chỉ có ở `Bash`, cần xem nó là mở rộng riêng của `Bash`.

### 2.5 Quan hệ tổng thể

```text
Bàn phím
   |
   v
Terminal / PTY / TTY
   |
   v
Shell
   |
   v
Chương trình
   |
   v
Linux kernel
```

---

## 3. Shell hiểu một dòng lệnh như thế nào?

### 3.1 Shell là một ngôn ngữ nhỏ

Một dòng lệnh không chỉ là:

```text
program arg1 arg2
```

Nó còn có thể chứa:

```text
biến
pipe
chuyển hướng
subshell
command substitution
&&
||
;
```

Do đó `shell` phải phân tích cú pháp trước khi chạy chương trình.

### 3.2 Các giai đoạn chính

Mô hình đơn giản:

```mermaid
stateDiagram-v2
    [*] --> ReadLine: đọc dòng lệnh
    ReadLine --> Parse: phân tích cú pháp
    Parse --> Expand: thực hiện mở rộng
    Expand --> Redirect: chuẩn bị chuyển hướng
    Redirect --> Execute: chạy builtin hoặc executable
    Execute --> WaitOrContinue: chờ hoặc tiếp tục
    WaitOrContinue --> [*]
```

Đây là mô hình tư duy, không phải mô tả toàn bộ nội bộ của một `shell` cụ thể.

### 3.3 Builtin và chương trình ngoài

Một số lệnh là **builtin** của `shell`, ví dụ `cd` thường phải là builtin vì nó cần thay đổi thư mục làm việc của chính tiến trình `shell`.

Một số lệnh khác là executable độc lập:

```text
/bin/ls
/usr/bin/grep
/usr/bin/find
```

Điểm cần nhớ:

```text
builtin
  chạy trong ngữ cảnh shell

external executable
  thường chạy trong tiến trình riêng
```

---

## 4. Dấu nháy và quá trình mở rộng của Shell

> **Nói đơn giản:** trước khi chương trình nhận `argv`, `shell` có thể biến đổi nội dung người dùng đã gõ.

### 4.1 Vì sao phải dùng dấu nháy?

Một số ký tự có ý nghĩa đặc biệt với `shell`:

```text
space
*
?
$
>
<
|
;
&
```

Dấu nháy kiểm soát việc chúng được hiểu như cú pháp hay như dữ liệu thông thường.

### 4.2 Dấu nháy đơn

Trong dấu nháy đơn, phần lớn ký tự được giữ nguyên nghĩa chữ.

Mô hình:

```text
'$HOME'
   |
   v
chuỗi ký tự $HOME
```

`$HOME` không được mở rộng thành giá trị biến.

### 4.3 Dấu nháy kép

Dấu nháy kép vẫn cho phép một số mở rộng, đặc biệt là mở rộng biến và thay thế lệnh.

```text
"$HOME"
   |
   v
giá trị HOME nhưng vẫn giữ thành một word
```

### 4.4 Mở rộng tham số

Ví dụ khái niệm:

```text
$USER
${HOME}
```

`Shell` thay tham chiếu bằng giá trị trước khi chương trình được thực thi.

### 4.5 Thay thế lệnh

Kết quả chuẩn của một lệnh có thể được đưa trở lại dòng lệnh:

```text
$(command)
```

Về mặt tư duy:

```text
chạy lệnh con
   |
thu stdout
   |
chèn kết quả vào dòng lệnh cha
```

### 4.6 Tách từ và globbing

`Shell` có thể tách kết quả thành nhiều word và thực hiện khớp tên tệp bằng các mẫu như:

```text
*.c
file?.txt
```

`globbing` không phải `regular expression`.

```text
Shell glob
  dùng cho tên tệp/pathname

Regular expression
  dùng cho mô hình khớp văn bản của công cụ như grep
```

---

## 5. Shell tìm chương trình bằng `PATH` như thế nào?

### 5.1 `PATH`

`PATH` là danh sách thư mục mà `shell` dùng để tìm executable khi tên lệnh không chứa `/`.

Mô hình:

```text
PATH=/usr/local/bin:/usr/bin:/bin

command: tool
   |
   +--> /usr/local/bin/tool ?
   +--> /usr/bin/tool ?
   +--> /bin/tool ?
```

### 5.2 Khi tên lệnh có `/`

Nếu người dùng nhập:

```text
./app
```

hoặc:

```text
/opt/bin/app
```

`Shell` không cần tìm theo `PATH`; đường dẫn đã được chỉ ra.

### 5.3 Vì sao `.` thường không nằm sẵn trong `PATH`?

Nếu thư mục hiện tại luôn được ưu tiên tìm kiếm, một executable cùng tên với lệnh hệ thống có thể bị chạy nhầm.

Đây là lý do bảo mật và tính dự đoán được của môi trường dòng lệnh.

---

## 6. Thư mục làm việc và đường dẫn

### 6.1 Thư mục làm việc hiện tại

Mỗi tiến trình có một **thư mục làm việc hiện tại**.

Đường dẫn tương đối được phân giải từ đó.

```text
cwd = /home/user/project

relative path: src/main.c
        |
        v
/home/user/project/src/main.c
```

### 6.2 `cd`

`cd` thay đổi thư mục làm việc của chính `shell`.

Nếu `cd` chạy trong một tiến trình con rồi tiến trình con thoát, thư mục làm việc của `shell` cha sẽ không thay đổi.

### 6.3 Đường dẫn logic và vật lý

Khi có symbolic link, đường dẫn người dùng nhìn thấy có thể khác đường dẫn vật lý sau khi phân giải liên kết.

Điểm này sẽ được giải thích sâu hơn ở Topic 2.

---

## 7. Biến Shell, biến môi trường và `argv`

### 7.1 Biến Shell

Biến của `shell` là trạng thái nội bộ của `shell`.

Nó chưa chắc được truyền sang chương trình con.

### 7.2 Biến môi trường

Biến môi trường được truyền vào tiến trình con khi tạo ảnh chương trình mới.

```text
Shell
  |
  | environment
  v
Child process
```

### 7.3 `export`

`export` đánh dấu một biến của `shell` để nó xuất hiện trong môi trường của các tiến trình con được tạo sau đó.

Điểm rất quan trọng:

```text
parent -> child environment inheritance
```

không có nghĩa:

```text
child thay environment của parent trực tiếp
```

### 7.4 `argv`

Sau khi `shell` phân tích và mở rộng dòng lệnh, chương trình nhận danh sách đối số.

Ví dụ về mặt cấu trúc:

```text
argv[0] = tên chương trình
argv[1] = đối số thứ nhất
argv[2] = đối số thứ hai
...
```

Khoảng trắng sau xử lý của `shell` không còn là một chuỗi đơn; ranh giới đối số đã trở thành cấu trúc riêng.

---

## 8. `stdin`, `stdout`, `stderr` và chuyển hướng

### 8.1 Ba luồng chuẩn

Theo quy ước Unix/Linux:

```text
fd 0 -> stdin
fd 1 -> stdout
fd 2 -> stderr
```

Chúng chỉ là các bộ mô tả tệp được thiết lập sẵn khi chương trình bắt đầu.

### 8.2 Vì sao `stdout` và `stderr` tách riêng?

Một chương trình có thể gửi:

```text
kết quả bình thường -> stdout
thông báo lỗi       -> stderr
```

Nhờ đó `shell` có thể xử lý hai dòng dữ liệu khác nhau.

### 8.3 Chuyển hướng thực chất là nối lại bộ mô tả tệp

Ví dụ về mặt khái niệm:

```text
stdout
  |
  v
terminal
```

sau chuyển hướng:

```text
stdout
  |
  v
file
```

Chương trình không nhất thiết biết rằng đầu ra đã bị chuyển hướng. Nó vẫn ghi vào `fd 1`.

### 8.4 Thứ tự chuyển hướng có ý nghĩa

Chuyển hướng được xử lý theo thứ tự, vì việc sao chép một bộ mô tả tệp sử dụng trạng thái tại thời điểm đó.

Đây là lý do hai biểu thức có cùng các toán tử nhưng khác thứ tự có thể cho kết quả khác.

---

## 9. Pipe và Pipeline

### 9.1 Pipe

`pipe` là một kênh byte do nhân Linux quản lý.

```text
Bên ghi
   |
   v
+---------+
|  pipe   |
+---------+
   |
   v
Bên đọc
```

### 9.2 Pipeline của Shell

Khi viết:

```text
A | B
```

`Shell` tạo `pipe`, nối:

```text
stdout của A -> đầu ghi pipe
stdin của B  -> đầu đọc pipe
```

Sau đó A và B có thể chạy đồng thời.

### 9.3 `stderr` không tự đi vào pipe

Theo mô hình thông thường:

```text
stdout -> pipe
stderr -> nơi cũ
```

Muốn đưa `stderr` vào cùng kênh cần chuyển hướng rõ ràng.

### 9.4 Pipeline là ghép tiến trình

Điểm sâu hơn cần nhớ:

```text
pipeline
  không chỉ là ghép chuỗi văn bản
  mà là ghép các tiến trình thông qua file descriptor
```

Đây là nền tảng trực tiếp cho Topic 3 và Topic 8.

---

## 10. Mã kết thúc và toán tử điều khiển Shell

### 10.1 Mã kết thúc

Khi một chương trình kết thúc, nó trả về trạng thái để tiến trình cha có thể biết kết quả.

Theo quy ước shell:

```text
0      -> thành công
khác 0 -> một trạng thái không thành công nào đó
```

Ý nghĩa cụ thể của số khác `0` phụ thuộc từng chương trình.

### 10.2 `&&`

```text
A && B
```

B chỉ chạy nếu A được xem là thành công.

### 10.3 `||`

```text
A || B
```

B chạy khi A không thành công.

### 10.4 `;`

```text
A ; B
```

B được xét chạy sau A mà không phụ thuộc trực tiếp vào mã kết thúc của A.

### 10.5 Vì sao mã kết thúc quan trọng?

Đây là kênh điều khiển dành cho máy, khác với `stdout` vốn thường chứa dữ liệu dành cho người hoặc chương trình khác.

---

## 11. Tiền cảnh, nền và điều khiển tác vụ

### 11.1 Tiến trình tiền cảnh

Trong terminal tương tác, một nhóm tiến trình được xem là nhóm tiền cảnh của terminal.

Các tín hiệu tạo bởi terminal, như `SIGINT` khi nhấn `Ctrl+C`, thường nhắm vào nhóm tiền cảnh.

### 11.2 Tiến trình nền

Một công việc chạy nền không chiếm quyền điều khiển tương tác của `shell` theo cách của công việc tiền cảnh.

Tuy vậy, nó vẫn là tiến trình bình thường và vẫn dùng CPU, bộ nhớ, file descriptor, tín hiệu...

### 11.3 Job control

`Shell` tương tác sử dụng:

```text
process group
session
controlling terminal
signals
```

để triển khai job control.

Topic 4 và Topic 5 sẽ làm rõ các lớp này hơn.

---

## 12. Các nhóm lệnh Linux cơ bản

Mục đích của phần này không phải học thuộc cú pháp, mà hiểu **mỗi lệnh quan sát hoặc thay đổi lớp nào**.

### 12.1 Điều hướng và quản lý tên tệp

```text
pwd
cd
ls
cp
mv
rm
mkdir
```

Nhóm này chủ yếu làm việc với:

```text
pathname
thư mục
metadata
namespace của hệ thống tệp
```

### 12.2 Quan sát nội dung văn bản

```text
cat
head
tail
wc
```

Nhóm này chủ yếu đọc byte từ file descriptor và biểu diễn/đếm dữ liệu.

### 12.3 Lọc và biến đổi

```text
grep
sort
cut
tr
```

Tư duy chung:

```text
stdin -> xử lý -> stdout
```

Đây là lý do các công cụ Unix có thể ghép qua pipeline hiệu quả.

---

## 13. `grep` và `find`: tìm kiếm theo hai mô hình khác nhau

### 13.1 `grep`

`grep` tìm mẫu trong **nội dung dữ liệu đầu vào**.

```text
text stream
   |
   v
grep pattern
   |
   v
matching lines
```

`grep` có thể dùng biểu thức chính quy; biểu thức chính quy không giống glob của `shell`.

### 13.2 `find`

`find` đi qua **cây thư mục** và đánh giá điều kiện trên từng mục.

```text
filesystem tree
      |
      v
    find
      |
  tests/actions
```

Do đó:

```text
grep -> tìm trong nội dung
find -> tìm trong cây namespace/metadata
```

---

## 14. `ps`, `top`, `mount`, `df`, `du` đang quan sát điều gì?

### 14.1 `ps`

`ps` cung cấp một ảnh chụp trạng thái tiến trình tại thời điểm thu thập dữ liệu.

Nó không phải một lịch sử bất biến của hệ thống.

### 14.2 `top`

`top` lặp lại việc thu thập trạng thái và hiển thị động.

Các giá trị CPU/bộ nhớ phải được hiểu theo khoảng lấy mẫu và mô hình bộ nhớ Linux.

### 14.3 `mount`

`mount` liên quan đến việc gắn một hệ thống tệp vào cây namespace.

```text
filesystem object
      |
   mount
      |
      v
mount point trong cây /
```

### 14.4 `df`

`df` báo cáo dung lượng ở **mức hệ thống tệp**.

### 14.5 `du`

`du` đi qua **cây tệp/thư mục đã chọn** để ước lượng dung lượng sử dụng.

Vì vậy:

```text
df -> góc nhìn toàn filesystem
du -> góc nhìn cây pathname được duyệt
```

Hai số có thể khác nhau mà không có lỗi.

---

## 15. Tư duy gỡ lỗi khi một lệnh không hoạt động

### 15.1 “Không tìm thấy lệnh”

Kiểm tra theo lớp:

```text
tên lệnh đúng?
   |
PATH đúng?
   |
executable tồn tại?
   |
quyền thực thi?
   |
interpreter / dynamic loader tồn tại?
```

### 15.2 “Permission denied”

Có thể liên quan:

```text
quyền trên file
quyền search của thư mục cha
mount option
credential của tiến trình
security policy khác
```

### 15.3 Chương trình nhận sai số lượng đối số

Hãy nghĩ đến:

```text
quoting
word splitting
globbing
```

vì `shell` có thể đã biến đổi dòng nhập trước khi chương trình nhận `argv`.

### 15.4 Pipeline cho kết quả lạ

Tách từng lớp:

```text
A có tạo đúng stdout?
B có đọc đúng stdin?
stderr có bị bỏ sót?
mã kết thúc của tiến trình nào đang được quan sát?
```

---

## 16. Liên hệ với Embedded Linux

### 16.1 Board thường không có GUI đầy đủ

Trong giai đoạn bring-up, giao diện thường là:

```text
UART serial console
SSH
local shell
```

Nắm CLI giúp làm việc khi chưa có desktop.

### 16.2 BusyBox

Nhiều hệ thống nhúng dùng `BusyBox` để cung cấp nhiều tiện ích Linux trong một executable nhỏ.

Cú pháp chi tiết có thể khác GNU utilities, nhưng mô hình:

```text
stdin/stdout/stderr
file descriptor
pipe
exit status
```

vẫn cực kỳ quan trọng.

### 16.3 Dòng lệnh là công cụ quan sát hệ thống

Trong bring-up/debug thường cần quan sát:

```text
/proc
/sys
/dev
mounts
processes
memory
network
logs
```

Do đó Topic 1 là nền cho hầu hết các chủ đề tiếp theo.

---

## 17. Tổng kết

```text
Người dùng nhập dòng lệnh
        |
        v
Terminal / TTY / PTY
        |
        v
Shell
        |
        +--> phân tích cú pháp
        +--> quoting / expansion
        +--> PATH lookup
        +--> redirection
        +--> pipeline
        |
        v
Tiến trình / builtin
        |
        v
Linux kernel
```

Các ý cần nhớ:

1. `terminal` và `shell` là hai lớp khác nhau.
2. `shell` phân tích dòng lệnh trước khi chương trình nhận `argv`.
3. Dấu nháy quyết định ký tự nào được `shell` diễn giải.
4. `PATH` chỉ tham gia khi tên lệnh cần được tìm kiếm.
5. Mỗi tiến trình có thư mục làm việc hiện tại.
6. Biến môi trường được truyền từ cha sang con; tiến trình con không trực tiếp sửa môi trường của cha.
7. `stdin`, `stdout`, `stderr` tương ứng với các file descriptor chuẩn.
8. Chuyển hướng là thay đổi nơi các file descriptor trỏ tới.
9. Pipeline là ghép các tiến trình bằng `pipe`.
10. Mã kết thúc là kênh điều khiển, không phải nội dung `stdout`.
11. `grep` tìm trong dữ liệu; `find` duyệt cây filesystem.
12. `df` và `du` quan sát dung lượng từ hai góc khác nhau.

---

## 18. Tài liệu tham khảo

Nguồn ưu tiên cho chủ đề này:

- POSIX.1-2024 Shell Command Language: https://pubs.opengroup.org/onlinepubs/9799919799/
- GNU Bash Manual: https://www.gnu.org/software/bash/manual/
- Linux man-pages: https://man7.org/linux/man-pages/
- GNU Coreutils Manual: https://www.gnu.org/software/coreutils/manual/
- GNU Grep Manual: https://www.gnu.org/software/grep/manual/
- GNU Findutils Manual: https://www.gnu.org/software/findutils/manual/
- procps-ng: https://gitlab.com/procps-ng/procps
- util-linux: https://github.com/util-linux/util-linux
- Linux TTY documentation: https://docs.kernel.org/driver-api/tty/
- Bootlin Embedded Linux training: https://bootlin.com/training/embedded-linux/
- BusyBox documentation: https://busybox.net/

> **Điều hướng:** [Chủ đề 2 — Hệ thống tệp Linux →](README-topic-02.md)
