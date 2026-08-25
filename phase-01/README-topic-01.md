# Chủ đề 1 — Dòng lệnh Linux cơ bản

> **Mục tiêu:** Hiểu bản chất cách dòng lệnh Linux hoạt động giống như cách vận hành một dây chuyền, thay vì học vẹt từng lệnh máy móc.
>
> **Quy ước ngôn ngữ:** Giải thích bằng tiếng Việt đời thường kết hợp với ngôn ngữ kỹ thuật chuẩn mực. Các thuật ngữ cốt lõi như `shell`, `pipe`, `stdout`, `environment variable` được giữ nguyên tiếng Anh để đảm bảo tính chính xác và thuận tiện cho việc tra cứu tài liệu.
>
> **Phạm vi:** Các khái niệm từ cơ bản đến chuyên sâu về `terminal`, `TTY`, `shell`, cấu trúc dòng lệnh, biến môi trường, đường ống (`pipe`), chuyển hướng (`redirection`), và tư duy gỡ lỗi.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để bạn có thể đọc, hình dung rõ luồng dữ liệu thông qua các mô hình, trước khi tự mình áp dụng vào thực tế.

Trước khi đi vào chi tiết, hãy nhớ một nguyên tắc sống còn: **Bàn phím của bạn không hề nói chuyện trực tiếp với lõi máy tính (Kernel). Bàn phím chỉ nói chuyện với một "tổng đài viên" tên là Shell**. Khi hiểu được Shell làm việc thế nào, việc điều khiển hệ thống, từ các máy chủ mạnh mẽ cho đến các thiết bị nhúng nhỏ gọn, sẽ trở nên hiển nhiên và hoàn toàn nằm trong tầm kiểm soát.

---

## Mục lục

- [1. Dòng lệnh Linux thực chất là gì?](#1-dòng-lệnh-linux-thực-chất-là-gì)
- [2. Terminal, TTY, PTY và Shell](#2-terminal-tty-pty-và-shell)
- [3. Shell hiểu một dòng lệnh như thế nào?](#3-shell-hiểu-một-dòng-lệnh-như-thế-nào)
- [4. Quoting và Shell expansion](#4-quoting-và-shell-expansion)
- [5. Shell tìm chương trình bằng `PATH` như thế nào?](#5-shell-tìm-chương-trình-bằng-path-như-thế-nào)
- [6. Thư mục làm việc và đường dẫn](#6-thư-mục-làm-việc-và-đường-dẫn)
- [7. Shell variable, environment variable và `argv`](#7-shell-variable-environment-variable-và-argv)
- [8. `stdin`, `stdout`, `stderr` và redirection](#8-stdin-stdout-stderr-và-redirection)
- [9. Pipe và Pipeline](#9-pipe-và-pipeline)
- [10. `exit status` và toán tử điều khiển Shell](#10-exit-status-và-toán-tử-điều-khiển-shell)
- [11. `foreground`, `background` và `job control`](#11-foreground-background-và-job-control)
- [12. Các nhóm lệnh Linux cơ bản](#12-các-nhóm-lệnh-linux-cơ-bản)
- [13. `grep` và `find`: tìm kiếm theo hai mô hình khác nhau](#13-grep-và-find-tìm-kiếm-theo-hai-mô-hình-khác-nhau)
- [14. `ps`, `top`, `mount`, `df`, `du` đang quan sát điều gì?](#14-ps-top-mount-df-du-đang-quan-sát-điều-gì)
- [15. Tư duy gỡ lỗi khi một lệnh không hoạt động](#15-tư-duy-gỡ-lỗi-khi-một-lệnh-không-hoạt-động)
- [16. Liên hệ với Embedded Linux](#16-liên-hệ-với-embedded-linux)
- [17. Tổng kết](#17-tổng-kết)
- [18. Tài liệu tham khảo](#18-tài-liệu-tham-khảo)

---

## 1. Dòng lệnh Linux thực chất là gì?

Dòng lệnh là phương thức giao tiếp cốt lõi, nơi bạn dùng văn bản (text) để yêu cầu hệ điều hành thực thi các tác vụ.

### 1.1 CLI và GUI khác nhau ở đâu?

*   **GUI (Graphic User Interface):** Cung cấp các nút bấm, menu và cửa sổ. GUI giống như bạn ra quầy fast-food, nhìn bảng menu và **chỉ tay** vào món đồ có sẵn. Nó trực quan, dễ dùng nhưng bị giới hạn bởi những gì nhà phát triển đã thiết kế sẵn trên giao diện.
*   **CLI (Command Line Interface):** Cung cấp một ngôn ngữ lệnh. CLI giống như bạn đi thẳng vào bếp và nói với đầu bếp: *"Lấy nguyên liệu A, xử lý qua máy B, rồi đưa kết quả vào hộp C"*. Nó đòi hỏi bạn phải nhớ từ vựng, nhưng bù lại, cung cấp quyền lực tối thượng để ghép nối các công cụ nhỏ thành một quy trình tự động hóa phức tạp.

```text
GUI:  Người dùng ---> [Nhấp chuột/Nút bấm] ---> Ứng dụng xử lý cố định
CLI:  Người dùng ---> [Dòng lệnh linh hoạt] ---> Shell ---> Chương trình/System Call
```

### 1.2 Dòng lệnh không phải `system call`

Khi bạn gõ `ls -l /etc`, bản thân hạt nhân Linux (Kernel) không nhận cả chuỗi ký tự này. Hạt nhân chỉ hiểu các lệnh gọi hệ thống (system call). `Shell` mới là thành phần đọc, hiểu cú pháp của dòng lệnh đó, tách nó ra thành tên chương trình (`ls`) và các đối số (`-l`, `/etc`), sau đó nhờ Kernel tạo một tiến trình mới để chạy chương trình `ls`.

---

## 2. Terminal, TTY, PTY và Shell

Để một ký tự từ bàn phím đi tới chương trình xử lý, nó phải đi qua một chuỗi các lớp môi giới.

### 2.1 Terminal

Terminal (Thiết bị đầu cuối) là phần xác vật lý hoặc phần mềm mô phỏng (ví dụ: cửa sổ terminal trên Ubuntu, VS Code terminal) dùng để hiển thị ký tự và nhận phím bấm từ bạn. 

### 2.2 TTY (Teletype)

TTY là lớp trừu tượng trong Linux quản lý việc truyền nhận văn bản. Nó quy định các tính năng như "khi người dùng bấm Ctrl+C, hãy gửi tín hiệu ngắt" hoặc "hiển thị lại ký tự vừa gõ lên màn hình (echo)".

### 2.3 PTY (Pseudo-Terminal)

Khi bạn kết nối SSH vào một mạch nhúng hoặc một server từ xa, bạn không dùng cáp nối trực tiếp. Lúc này, PTY (thiết bị giả lập) sẽ đóng vai trò tạo ra một luồng TTY ảo để mô phỏng lại quá trình giao tiếp, giúp phần mềm ở xa tưởng rằng bạn đang ngồi ngay trước máy.

### 2.4 Shell

Shell (như `Bash`, `Zsh`, `sh`) là trình thông dịch (interpreter). Nó lắng nghe luồng ký tự từ TTY, phân tích ngữ pháp, tìm chương trình tương ứng và kích hoạt chương trình đó.

**2.5 Quan hệ tổng thể:**

```text
[Bàn phím] 
    |
    v
[Terminal / PTY / TTY] (Kênh truyền tải sóng/kết nối)
    |
    v
[Shell]                (Tổng đài viên phân tích ngôn ngữ)
    |
    v
[Chương trình ngoài]   (Thực hiện tác vụ và gọi Kernel)
```

---

## 3. Shell hiểu một dòng lệnh như thế nào?

Shell là một ngôn ngữ lập trình thu nhỏ. Trước khi bất kỳ chương trình nào thực sự chạy, Shell phải tiến hành một loạt các bước tiền xử lý. Nếu bạn gõ: `echo "$USER" > log.txt`

```text
"echo $USER > log.txt"
           |
           v
[ 1. Parse (Tách từ)     ]  Nhận ra 'echo' là lệnh, '>' là toán tử điều hướng.
           |
           v
[ 2. Expand (Mở rộng)    ]  Dịch biến '$USER' thành giá trị thực (vd: NgocChien Trùm VT01).
           |
           v
[ 3. Redirect (Điều hướng)] Mở/tạo file 'log.txt' để hứng dữ liệu đầu ra.
           |
           v
[ 4. Execute (Thực thi)  ]  Chạy chương trình 'echo' với kết quả sau khi đã biên dịch.
```

Điều quan trọng nhất cần nhớ: Lỗi như "file không tồn tại" hay "sai cú pháp" thường xảy ra ở giai đoạn 1, 2, 3 do Shell báo lỗi, trước cả khi chương trình (như `echo`, `cat`, `gcc`) kịp khởi động.

---

## 4. Quoting và Shell expansion

Ký tự nháy (`'`, `"`) được dùng để bảo vệ văn bản khỏi sự phân tích tự động của Shell.

*   **Dấu cách (Space):** Shell dùng khoảng trắng để tách các từ. Nếu bạn muốn truy cập thư mục `My Projects`, bạn phải bọc nó lại `"My Projects"`, nếu không Shell sẽ tìm hai thư mục riêng biệt là `My` và `Projects`.
*   **Nháy đơn (`' '`):** Đóng băng tuyệt đối mọi ký tự. Chuỗi `'$HOME'` sẽ được truyền nguyên vẹn là `$HOME`.
*   **Nháy kép (`" "`):** Đóng băng khoảng trắng, nhưng vẫn cho phép Shell dịch các biến (như `$VAR`) hoặc chạy lệnh con (như `$(cmd)`). Cú pháp `"$HOME"` sẽ được dịch ra thành `/home/user`.
*   **Globbing (Khớp mẫu):** Ký tự `*` hay `?`. Ví dụ `*.c` sẽ được Shell tự động mở rộng thành danh sách tất cả các file mã nguồn C trong thư mục trước khi nạp vào chương trình.

---

## 5. Shell tìm chương trình bằng `PATH` như thế nào?

Khi bạn gõ lệnh như `make` hay `cmake`, làm sao hệ điều hành biết công cụ đó nằm ở đâu?

### 5.1 Biến môi trường PATH
`PATH` là một danh sách các thư mục, được ngăn cách bởi dấu hai chấm `:`. Khi nhận một lệnh không có đường dẫn rõ ràng, Shell sẽ rà soát từng thư mục trong danh sách này từ trái sang phải.

```text
Lệnh: cmake
  |
  +---> Tìm ở /usr/local/bin/cmake ? ---> (Không thấy)
  |
  +---> Tìm ở /bin/cmake ?           ---> (Không thấy)
  |
  +---> Tìm ở /usr/bin/cmake ?       ---> (CÓ! Bắt đầu chạy)
```

Nếu rà soát hết mà không thấy, Shell sẽ trả về thông báo lỗi: `Command not found`.

### 5.2 Lệnh có chứa dấu `/`
Nếu bạn gõ `./build.sh` hoặc `/opt/toolchain/bin/gcc`, Shell hiểu rằng bạn đã chỉ định tọa độ chính xác. Nó bỏ qua `PATH` và đi thẳng tới vị trí đó để chạy tệp tin.

---

## 6. Thư mục làm việc và đường dẫn

Mỗi tiến trình trong Linux (bao gồm cả Shell) đều có một trạng thái gọi là **Thư mục làm việc hiện tại (Current Working Directory - CWD)**.

*   **Đường dẫn tuyệt đối:** Bắt đầu bằng dấu gạch chéo gốc `/` (ví dụ: `/home/user/workspace/app.c`). Đây là tọa độ cố định, ở đâu gọi cũng giống nhau.
*   **Đường dẫn tương đối:** Bắt đầu từ CWD hiện hành (ví dụ: `src/main.c` hoặc `../include/`).
*   **Lệnh `cd`:** Đây là một lệnh tích hợp sẵn (builtin) của Shell. Nó thay đổi trạng thái CWD của chính phiên Shell hiện tại để bạn "bước" sang một không gian khác.

---

## 7. Shell variable, environment variable và `argv`

Biến (Variables) là cách lưu trữ thông tin cấu hình và truyền dữ liệu giữa các tiến trình.

### 7.1 Shell Variable (Biến cục bộ)
Được tạo ra và chỉ có ý nghĩa bên trong phiên Shell hiện tại (ví dụ: `MY_VAR=123`). Các chương trình con bạn khởi chạy từ Shell này sẽ không nhìn thấy biến đó.

### 7.2 Environment Variable (Biến môi trường)
Khi bạn dùng lệnh `export MY_VAR=123`, bạn biến nó thành biến môi trường. Khi Shell tạo ra một tiến trình con (ví dụ: chạy một script Python hoặc trình biên dịch C), tiến trình con đó sẽ kế thừa và nhìn thấy biến `MY_VAR`.

### 7.3 `argv` (Danh sách đối số)
Sau khi Shell thực hiện việc mở rộng biến và tách từ, nó đóng gói các thành phần lại thành một mảng dữ liệu gọi là `argv`. Chương trình C/C++ của bạn sẽ nhận mảng này thông qua tham số `int main(int argc, char *argv[])`.

---

## 8. `stdin`, `stdout`, `stderr` và redirection

Mỗi chương trình Linux sinh ra đều được cấp sẵn 3 luồng dữ liệu tiêu chuẩn (File Descriptors - fd):

*   **`stdin` (fd 0 - Standard Input):** Lỗ hút dữ liệu đầu vào. Thường được nối với bàn phím.
*   **`stdout` (fd 1 - Standard Output):** Lỗ xả kết quả bình thường. Thường in ra màn hình terminal.
*   **`stderr` (fd 2 - Standard Error):** Lỗ xả thông báo lỗi. Cũng thường in ra màn hình để người dùng lập tức chú ý.

```text
[ Bàn phím ] ---> (stdin 0) ---> [ CHƯƠNG TRÌNH ] ---> (stdout 1) ---> [ Màn hình ]
                                        |
                                        +------------> (stderr 2) ---> [ Màn hình ]
```

**Chuyển hướng (Redirection):**
Bạn có thể can thiệp vào các luồng này. Ví dụ lệnh `ls > output.txt` sẽ "bẻ lái" luồng xả sạch `stdout` ghi thẳng vào tệp văn bản.

```text
SAU KHI ĐIỀU HƯỚNG: Lệnh > output.txt

[ Bàn phím ] ---> (stdin 0) ---> [ CHƯƠNG TRÌNH ] ---> (stdout 1) --X-- [ Màn hình ]
                                        |                 |
                                        |                 +-----------> [ output.txt ]
                                        |
                                        +------------> (stderr 2) ----> [ Màn hình ]
```

---

## 9. Pipe và Pipeline

**Pipe (`|`) là cơ chế ghép nối sức mạnh cốt lõi của UNIX/Linux.**

Đường ống này nối thẳng `stdout` của chương trình đứng trước vào `stdin` của chương trình đứng sau. Dữ liệu được luân chuyển trực tiếp qua bộ nhớ của Kernel mà không cần phải ghi xuống một file tạm trên ổ cứng.

```text
[ Lệnh A (Tạo dữ liệu) ]                        [ Lệnh B (Lọc dữ liệu) ]
       |                                              ^
       | (stdout xả ra)                               | (stdin hút vào)
       +-----------------> [ ỐNG PIPE | ] ------------+
```

*Ví dụ:* `cat system.log | grep "ERROR" | wc -l`. Lệnh này đọc log, truyền qua bộ lọc chỉ giữ lại dòng có chữ ERROR, rồi truyền qua máy đếm để biết có bao nhiêu lỗi đã xảy ra.

---

## 10. `exit status` và toán tử điều khiển Shell

Các chương trình làm việc rất âm thầm. Khi kết thúc, chúng không báo cáo bằng lời nói mà trả về cho hệ điều hành một mã số gọi là `exit status`.

*   **Mã `0`:** Chương trình thực thi thành công mỹ mãn.
*   **Mã `1` đến `255`:** Xảy ra lỗi (mỗi chương trình quy định mã lỗi mang ý nghĩa riêng).

Shell sử dụng mã này để điều khiển logic chuỗi lệnh:
*   `&&` (Toán tử AND): `A && B` -> B chỉ chạy nếu A trả về 0 (Thành công).
*   `||` (Toán tử OR): `A || B` -> B chỉ chạy nếu A trả về mã lỗi (Thất bại).
*   `;` (Chạy tuần tự): `A ; B` -> Chạy A xong, bất kể sống chết, chạy tiếp B.

---

## 11. `foreground`, `background` và `job control`

*   **Tiền cảnh (Foreground):** Khi bạn chạy một lệnh như `nano` hay trình biên dịch, tiến trình này sẽ chiếm dụng màn hình terminal. Bạn không thể gõ lệnh mới cho đến khi nó kết thúc hoặc bị bạn ngắt (Ctrl+C).
*   **Nền (Background):** Thêm dấu `&` vào cuối dòng lệnh (ví dụ `server_app &`). Tiến trình sẽ chạy ngầm dưới hệ thống, trả lại dấu nhắc lệnh (`prompt`) để bạn tiếp tục thao tác khác trên terminal.
*   **Job control:** Các phím tắt như Ctrl+Z (tạm dừng), lệnh `bg` (đưa vào chạy nền) và `fg` (gọi lại ra tiền cảnh) giúp bạn quản lý đồng thời nhiều công việc trong một phiên duy nhất.

---

## 12. Các nhóm lệnh Linux cơ bản

Bạn không cần học vẹt từ điển, chỉ cần gom nhóm các công cụ dựa theo mục đích sử dụng:

*   **Điều hướng & Quản lý File:** `pwd`, `cd`, `ls`, `mkdir`, `cp`, `mv`, `rm`. Làm việc với không gian thư mục.
*   **Quan sát nội dung:** `cat` (in toàn bộ), `head` (in phần đầu), `tail` (in phần cuối), `less` (cuộn trang). Dùng để đọc text.
*   **Lọc và Biến đổi:** `grep` (lọc dòng), `sort` (sắp xếp), `awk` (xử lý cột), `sed` (tìm/thay thế). Chuyên gia xử lý luồng dữ liệu (stream) qua Pipe.

---

## 13. `grep` và `find`: tìm kiếm theo hai mô hình khác nhau

Đây là sự nhầm lẫn phổ biến nhất. Hai lệnh này giải quyết bài toán tìm kiếm ở hai tầng hoàn toàn khác biệt.

### 13.1 `find` (Tìm ngoài vỏ metadata)
`find` quét qua cấu trúc cây thư mục. Nó kiểm tra tên file, kích thước, quyền hạn, ngày tạo. Nó **không bao giờ mở file ra đọc**.
*Ví dụ:* "Tìm mọi file `.c` hoặc `.h` trong thư mục `src/`".

### 13.2 `grep` (Tìm trong ruột nội dung)
`grep` quét qua luồng văn bản hoặc chui vào bên trong các file được chỉ định để tìm kiếm các chuỗi ký tự khớp với yêu cầu.
*Ví dụ:* "Tìm hàm `main` hoặc chuỗi cấu hình `UART_Init` nằm bên trong các file mã nguồn".

Bạn có thể kết hợp chúng: Dùng `find` gom hết các file cấu hình lại, băm qua đường ống `|` hoặc `xargs` để giao cho `grep` lật từng dòng tìm lỗi.

---

## 14. `ps`, `top`, `mount`, `df`, `du` đang quan sát điều gì?

Đây là bộ đồ nghề chẩn đoán sức khỏe hệ thống:
*   `ps` (Process Status): Chụp lại một bức ảnh X-Quang tĩnh xem tiến trình nào đang chạy tại thời điểm gõ lệnh.
*   `top` / `htop`: Màn hình theo dõi nhịp tim động, cập nhật liên tục CPU, RAM của các tiến trình.
*   `mount`: Kiểm tra xem các thiết bị ngoại vi, phân vùng ổ cứng đang được "gắn" vào gốc `/` ở đâu.
*   `df` (Disk Free): Đứng ở góc nhìn hệ thống tệp, báo cáo dung lượng tổng quát của toàn bộ ổ cứng/phân vùng.
*   `du` (Disk Usage): Đứng ở góc nhìn thư mục, đếm dung lượng thực tế của từng file/thư mục con cộng dồn lại.

---

## 15. Tư duy gỡ lỗi khi một lệnh không hoạt động

Khi hệ thống báo lỗi, đừng thử sai ngẫu nhiên. Hãy tư duy theo từng lớp:

1.  **Lỗi "Command not found":** 
    *   Bạn có gõ sai chính tả không? 
    *   Chương trình đã cài chưa?
    *   Đường dẫn chứa file thực thi có nằm trong biến danh bạ `PATH` chưa?
2.  **Lỗi "Permission denied":** 
    *   Bạn đang đóng vai người dùng thường, nhưng đụng vào cấu hình của quyền Root (Giám đốc). Giải pháp: chạy qua `sudo`.
    *   File đó thiếu quyền thực thi (`chmod +x`).
3.  **Lệnh Pipe ra kết quả trắng tinh hoặc báo lỗi lạ:**
    *   Hãy tách chuỗi ra. Chạy riêng phần lệnh đầu tiên xem `stdout` của nó có đúng định dạng không, trước khi băm nó sang cho chương trình phía sau.

---

## 16. Liên hệ với Embedded Linux

Nếu bạn đang làm việc với các dự án điện tử viễn thông, lập trình vi điều khiển như STM32, ESP32, hay xây dựng firmware trên OpenWrt, dòng lệnh (CLI) không phải là tùy chọn, nó là môi trường bắt buộc.

Ví dụ như khi bạn SSH vào `[NgocChien Trùm VT01@openwrt:~]#` trên một router, hoặc quan sát log OTA qua cổng UART Serial (`/dev/ttyUSB0`), thiết bị nhúng sẽ không có màn hình GUI đồ họa. 

Kỹ năng dùng CLI, sử dụng `dmesg | grep tty` để tìm cổng COM thiết bị, viết các script `Makefile` hay `CMake` (vốn khai thác sức mạnh của biến môi trường và exit status), hoặc dùng `BusyBox` để điều hướng hệ thống file nhỏ gọn, chính là nền tảng cốt lõi phân biệt một kỹ sư Embedded Systems nắm rõ bản chất so với việc chỉ click chuột mù mờ trên các IDE truyền thống.

---

## 17. Tổng kết

Hãy lưu giữ mô hình vận hành duy nhất này trong tư duy:

```text
Bạn gõ chữ -> Terminal truyền đi -> Shell dịch cú pháp -> Thực hiện mở rộng biến 
-> Thiết lập ống nước (pipe/redirection) -> Tìm đường dẫn (PATH) 
-> Giao việc (Process/Kernel) -> Trả về kết quả (Exit status).
```

Nếu một lệnh không chạy, đừng vội đổ lỗi cho chương trình hỏng. Hãy xem xét lại chuỗi dây chuyền trên, xác định xem cú pháp nháy (`' '`), toán tử ống dẫn (`|`, `>`) đã được ông "tổng đài viên Shell" hiểu đúng ý định của bạn hay chưa.

---

## 18. Tài liệu tham khảo

Phần này liệt kê các nguồn chính thống để bạn tra cứu khi cần kiểm chứng hoặc học sâu hơn.

- POSIX.1-2024 Shell Command Language: https://pubs.opengroup.org/onlinepubs/9799919799/
- GNU Bash Manual: https://www.gnu.org/software/bash/manual/
- Linux man-pages: https://man7.org/linux/man-pages/
- GNU Coreutils Manual: https://www.gnu.org/software/coreutils/manual/
- GNU Grep Manual: https://www.gnu.org/software/grep/manual/
- GNU Findutils Manual: https://www.gnu.org/software/findutils/manual/
- Bootlin Embedded Linux training: https://bootlin.com/training/embedded-linux/
- BusyBox documentation: https://busybox.net/

> **Điều hướng:** [Chủ đề 2 — Hệ thống tệp Linux →](README-topic-02.md)
