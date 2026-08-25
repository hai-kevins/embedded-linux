# Chủ đề 1 — Dòng lệnh Linux cơ bản

> **Mục tiêu:** Hiểu luồng hoạt động cốt lõi của dòng lệnh Linux, từ khi người dùng nhập phím đến khi kernel thực thi chương trình, thay vì chỉ ghi nhớ tên lệnh rời rạc.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các thuật ngữ cần tra cứu đúng theo tài liệu chuẩn của Linux/POSIX như `shell`, `builtin`, `quoting`, `expansion`, `environment variable`, `file descriptor`, `redirection`, `pipeline`, `exit status`, `job control` được giữ nguyên bằng tiếng Anh.
>
> **Phạm vi:** Giao diện dòng lệnh, `terminal`, `TTY`, `PTY`, `shell`, cấu trúc một dòng lệnh, dấu nháy, mở rộng của `shell`, `PATH`, biến môi trường, `stdin/stdout/stderr`, chuyển hướng, `pipe`, `exit status`, tiến trình tiền cảnh/nền và các công cụ quan sát cơ bản.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để bạn hình dung rõ luồng dữ liệu thông qua các mô hình hệ thống trước khi bắt tay vào gõ lệnh thực tế.

Trước khi đi vào từng lệnh, hãy giữ một mô hình duy nhất trong đầu: **Bàn phím và terminal chỉ đưa ký tự tới hệ thống, nhưng Shell mới là thành phần phân tích dòng lệnh; sau đó Shell chạy builtin hoặc yêu cầu Kernel tạo tiến trình để thực thi chương trình**. Những khái niệm như dấu nháy, `PATH`, chuyển hướng, pipe hay `exit status` đều là các mảnh ghép của quá trình đó. Khi đã hiểu luồng này, việc điều khiển hệ thống—từ máy chủ đến thiết bị nhúng—sẽ trở nên có tính dự đoán và hệ thống hơn.

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

Dòng lệnh là cách bạn yêu cầu Linux làm việc thông qua ngôn ngữ văn bản. Nó cho phép bạn biểu đạt các tác vụ từ đơn giản đến phức tạp thông qua cú pháp của Shell.

### 1.1 CLI và GUI khác nhau ở đâu?

*   **GUI (Graphic User Interface):** Cung cấp các nút bấm và biểu tượng. GUI trực quan nhưng giới hạn hành động của người dùng trong khuôn khổ những gì phần mềm đã lập trình sẵn trên giao diện.
*   **CLI (Command Line Interface):** Cung cấp một ngôn ngữ lệnh. Sức mạnh của CLI không nằm ở việc gõ nhanh, mà ở khả năng tự do **ghép nhiều công cụ nhỏ thành một quy trình xử lý dữ liệu liên tục**.

```text
GUI:  Người dùng ---> [Tương tác qua đồ họa] ---> Ứng dụng
CLI:  Người dùng ---> [Nhập chuỗi văn bản] ---> Shell ---> Chương trình / System call
```

### 1.2 Dòng lệnh không phải `system call`

Khi bạn gõ `ls -l /etc`, bản thân Linux kernel không nhận nguyên chuỗi này để "hiểu lệnh". Kernel chỉ cung cấp các system call (như đọc file, tạo tiến trình). `Shell` mới là thành phần đọc chuỗi văn bản đó, phân tích cú pháp để biết lệnh là `ls`, các đối số là `-l` và `/etc`, sau đó Shell mới gọi system call để thực thi chương trình.

---

## 2. Terminal, TTY, PTY và Shell

Để ký tự từ bàn phím đi tới chương trình và kết quả quay lại màn hình, nó đi qua một chuỗi các lớp trừu tượng và ranh giới hệ thống:

*   **2.1 Terminal:** Thiết bị nhập/xuất vật lý hoặc một ứng dụng phần mềm (Terminal Emulator) chạy ở tầng user-space như GNOME Terminal.
*   **2.2 TTY (Teletype):** Lớp trừu tượng (subsystem) của Linux Kernel quản lý dòng dữ liệu văn bản. Nó xử lý các tính năng như hiển thị lại phím gõ (echo) và phát tín hiệu ngắt (SIGINT) khi bấm Ctrl+C.
*   **2.3 PTY (Pseudo-Terminal):** Một cặp thiết bị giả lập gồm Master và Slave. Các ứng dụng như SSH server hay `tmux` dùng PTY để cung cấp một môi trường TTY đầy đủ cho Shell bên trong nó.
*   **2.4 Shell:** Trình thông dịch (như Bash, sh). Shell hoạt động như một tiến trình đọc ký tự từ TTY/PTY, diễn giải cú pháp và gọi các chương trình khác.

**2.5 Quan hệ tổng thể:**

```text
[ Bàn phím ] 
      |
      v
[ Terminal Emulator (User-space) ] (Ví dụ: GNOME Terminal, VS Code)
      |
      v
[ TTY / PTY Subsystem (Kernel) ]   (Lớp trừu tượng quản lý luồng I/O và tín hiệu)
      |
      v
[ Shell (User-space) ]             (Tiến trình phân tích ngôn ngữ lệnh)
      |
      v
[ Chương trình ngoài ]             (Thực hiện tác vụ thông qua System Call)
```

> **Đọc sơ đồ:** Luồng dữ liệu bắt đầu từ phím bấm đi vào Terminal Emulator. Tuy nhiên, Terminal Emulator không truyền thẳng ký tự đó cho Shell mà đẩy xuống TTY/PTY subsystem nằm sâu trong Kernel. Kernel xử lý các tác vụ như tạo tín hiệu ngắt hoặc cấu hình luồng, rồi mới chuyển các byte hợp lệ lên cho tiến trình Shell đọc. Sau khi phân tích hiểu ý người dùng, Shell yêu cầu Kernel tạo một tiến trình con mới để xử lý tác vụ thực tế.

---

## 3. Shell hiểu một dòng lệnh như thế nào?

Shell không chuyển nguyên chuỗi văn bản bạn gõ cho chương trình đích. Nó hoạt động như một trình thông dịch ngôn ngữ nhỏ, xử lý qua nhiều giai đoạn trước khi chương trình thực sự chạy.

### 3.1 Các giai đoạn chính

Khi bạn gõ: `echo "$HOME" | grep home > result.txt`

```text
"echo $HOME | grep home > result.txt"
           |
           v
[ 1. Parse (Tách từ)     ]  Tách cú pháp: 'echo', '|', 'grep', 'home', '> result.txt'.
           |
           v
[ 2. Expand (Mở rộng)    ]  Dịch biến '$HOME' thành giá trị thực (vd: NgocChien Trùm VT01).
           |
           v
[ 3. Prepare (Chuẩn bị)  ]  Phân tích cấu trúc pipeline, yêu cầu Kernel tạo Pipe.
           |
           v
[ 4. Fork & Exec         ]  Tạo process con, nối fd vào pipe/file, rồi gọi execve().
```

> **Đọc sơ đồ:** Sơ đồ này cho thấy quá trình Shell xử lý một dòng lệnh từ trên xuống dưới. Shell đọc toàn bộ dòng lệnh và tách thành các từ khóa, chuỗi và toán tử riêng biệt: echo, "$HOME", |, grep, home, >, result.txt. Tại đây, nó nhận diện | là toán tử đường ống (pipeline) và > là toán tử chuyển hướng đầu ra (redirection). Shell phát hiện $HOME nằm trong dấu ngoặc kép "", nên nó tiến hành nội suy (interpolate) và thay thế biến này bằng giá trị môi trường thực tế đang lưu trong hệ thống (Ví dụ: /home/ngocchien hoặc NgocChien Trùm VT01). Dựa vào cú pháp đã phân tích ở bước 1, Shell nhận ra đây là một chuỗi lệnh (pipeline). Nó gọi Kernel để tạo sẵn một bộ nhớ đệm luồng (Pipe) chuẩn bị cho việc đẩy dữ liệu từ echo sang grep. Ở bước 4, Shell thực hiện các thao tác: 
Fork (Nhân bản): Tạo ra các tiến trình con (child processes) riêng biệt cho echo và grep.
Cấu hình luồng (File Descriptors): Trỏ Standard Output (Đầu ra) của echo vào Pipe. Trỏ Standard Input (Đầu vào) của grep từ Pipe. Đồng thời, Shell cố gắng mở file result.txt để chuẩn bị ghi dữ liệu.
Execve (Thực thi): Nếu mọi thứ thiết lập thành công, Shell gọi hàm execve() để thay thế tiến trình con bằng mã thực thi của echo và grep.

### 3.2 Builtin (Lệnh tích hợp) và Chương trình ngoài

*   **Builtin:** Là các tính năng nằm ngay trong mã nguồn của Shell. Ví dụ quan trọng nhất là `cd`. Việc thay đổi thư mục (`chdir`) chỉ ảnh hưởng đến tiến trình hiện tại. Nếu `cd` là một chương trình ngoài, Shell sẽ phải tạo một tiến trình con, tiến trình con đổi thư mục xong rồi thoát, và Shell cha vẫn đứng ở thư mục cũ. Vì vậy `cd` phải do chính Shell tự thực thi (builtin).
*   **Chương trình ngoài:** Các công cụ như `ls`, `grep` nằm trong hệ thống tệp (như `/bin/ls`). Shell sẽ tìm đường dẫn của chúng và yêu cầu Kernel tạo một tiến trình mới (fork/exec) để chạy.

---

## 4. Quoting và Shell expansion

Ký tự nháy quyết định phần văn bản nào được Shell giữ nguyên và phần nào được can thiệp (mở rộng). Shell có một số ký tự đặc biệt như khoảng trắng (để tách từ), `*`, `?`, `$`.

*   **4.1 Nháy đơn (`' '`):** Ngăn chặn hoàn toàn mọi phép mở rộng. Chuỗi `'$HOME'` sẽ được truyền nguyên vẹn thành `$HOME` cho chương trình.
*   **4.2 Nháy kép (`" "`):** Ngăn chặn việc tách từ bằng khoảng trắng (word splitting), nhưng vẫn cho phép Shell dịch biến (Parameter expansion) và thay thế lệnh (Command substitution). Chuỗi `"$HOME"` sẽ được dịch thành `/home/user`.
*   **4.3 Command substitution (`$(cmd)`):** Chạy lệnh bên trong, thu thập kết quả (stdout) và chèn ngược lại vào dòng lệnh cha trước khi thực thi. Ví dụ: `echo "Xin chao $(whoami)"` ra output `echo "Xin chao ngocchien"`.
*   **4.4 Globbing (`*`, `?`):** Cơ chế khớp tên file của Shell. Ký tự `*.c` sẽ được Shell tự động mở rộng thành một danh sách các file C hiện có trong thư mục. Khác với Regular Expression (biểu thức chính quy) của lệnh `grep` thường dùng để so khớp luồng văn bản, Globbing chỉ dành cho việc phân giải đường dẫn (pathname).

---

## 5. Shell tìm chương trình bằng `PATH` như thế nào?

Khi bạn gõ lệnh như `gcc`, làm sao hệ điều hành biết công cụ đó nằm ở đâu để thực thi?

### 5.1 Biến môi trường PATH
`PATH` là một chuỗi chứa danh sách các thư mục, cách nhau bởi dấu hai chấm `:`. Khi nhận một lệnh không chứa dấu `/`, Shell sẽ rà soát tuần tự từng thư mục trong `PATH`.

```text
Lệnh: gcc
  |
  +---> Tìm ở /usr/local/bin/gcc ? ---> (Không thấy)
  |
  +---> Tìm ở /usr/bin/gcc ?       ---> (CÓ! Bắt đầu chạy)
```

> **Đọc sơ đồ:** Quá trình tra cứu diễn ra nghiêm ngặt từ trái sang phải. Shell sẽ ghép tên lệnh `gcc` vào từng thư mục và gọi Kernel kiểm tra xem tệp thực thi đó có tồn tại hay không. Ngay khi tìm thấy kết quả hợp lệ đầu tiên (ví dụ ở `/usr/bin/gcc`), Shell dừng tìm kiếm và tiến hành khởi chạy. Nếu cấu hình `PATH` sai thứ tự, một phiên bản phần mềm cũ nằm ở đầu danh sách có thể bị gọi nhầm.

### 5.2 Vì sao thư mục hiện tại (`.`) thường không nằm sẵn trong PATH?
Nếu thư mục hiện tại luôn được ưu tiên tìm kiếm, một tệp thực thi trùng tên với lệnh hệ thống (ví dụ: một tệp độc hại tên là `ls` trong thư mục tải xuống) có thể bị chạy nhầm. Khi cần chạy phần mềm tại thư mục hiện hành, bạn phải dùng đường dẫn rõ ràng: `./app`.

---

## 6. Thư mục làm việc và đường dẫn

Mỗi tiến trình (bao gồm cả tiến trình Shell) đều duy trì một trạng thái độc lập gọi là **Thư mục làm việc hiện tại (Current Working Directory - CWD)**.

*   **Đường dẫn tuyệt đối:** Bắt đầu bằng gốc `/` (ví dụ: `/etc/fstab`). Đường dẫn này luôn đúng bất kể CWD của tiến trình là gì.
*   **Đường dẫn tương đối:** Bắt đầu từ CWD hiện tại (ví dụ: `src/main.c`).
*   **Lệnh `cd`:** Thay đổi CWD của chính phiên Shell.

---

## 7. Shell variable, environment variable và `argv`

### 7.1 Shell Variable (Biến cục bộ)
Các biến định nghĩa thông thường (`VAR=123`) là trạng thái nội bộ của phiên Shell đó. Các tiến trình con không thể truy cập biến này.

### 7.2 Environment Variable (Biến môi trường)
Khi sử dụng `export VAR=123`, biến này sẽ được đánh dấu để sao chép vào bộ nhớ môi trường của tiến trình con. Khi một tiến trình con được tạo ra, hệ điều hành tuân theo luồng một chiều từ cha sang con: Cha sẽ sao chép toàn bộ các biến môi trường của mình vào bộ nhớ môi trường của con. Tiến trình con có quyền tự do chỉnh sửa các biến đó trong bộ nhớ môi trường của nó, nhưng mọi thay đổi đó hoàn toàn không ảnh hưởng hay dội ngược lại về tiến trình cha.

### 7.3 Mảng `argv`
Khi bạn gõ lệnh, Shell sẽ kiểm tra và chia các từ vào từng 'chiếc hộp' riêng biệt (gọi là danh sách đối số argv). Lúc này, các từ đã được phân chia rõ ràng và khóa chặt ranh giới. Dù bên trong một chiếc hộp có khoảng trắng, nó cũng không bị tách làm đôi nữa. Cuối cùng, Shell sẽ trao toàn bộ các hộp này cho hệ điều hành thông qua họ hàm exec*() (chính xác là lệnh execve()) để chạy chương trình.

---

## 8. `stdin`, `stdout`, `stderr` và redirection

Các tiến trình được Shell khởi chạy thông thường sẽ kế thừa 3 luồng dữ liệu chuẩn (Standard Streams) được quản lý bởi File Descriptor (fd). *(Lưu ý: Một số tiến trình nền như daemon có thể chủ động đóng hoặc nối lại các luồng này).*

*   **`stdin` (fd 0):** Luồng dữ liệu vào (mặc định nối với bàn phím).
*   **`stdout` (fd 1):** Luồng dữ liệu ra thông thường (mặc định nối với terminal).
*   **`stderr` (fd 2):** Luồng lỗi. Việc tách riêng `stdout` và `stderr` giúp Shell có thể điều hướng dữ liệu sạch vào file, đồng thời vẫn giữ được thông báo lỗi hiện lên màn hình.

**Chuyển hướng (Redirection):**
Chuyển hướng thực chất là việc Shell yêu cầu Kernel nối lại các File Descriptor trước khi chạy chương trình.
Thứ tự chuyển hướng cực kỳ quan trọng vì quá trình sao chép fd phụ thuộc vào trạng thái tại thời điểm phân tích.

```text
(Trạng thái mặc định)
[ Terminal ] <--- (stderr 2) ---+
                                |
[ Terminal ] <--- (stdout 1) ---+--- [ Chương trình ] <--- (stdin 0) <--- [ Bàn phím ]

(Sau khi áp dụng cú pháp "> output.txt")
[ Terminal ] <--- (stderr 2) ---+
                                |
[ output.txt ] <--- (stdout 1) -+--- [ Chương trình ] <--- (stdin 0) <--- [ Bàn phím ]
```

> **Đọc sơ đồ:** Sơ đồ trên mô phỏng sự can thiệp của Shell vào luồng dữ liệu. Ban đầu, `stdout` (fd 1) trỏ thẳng ra màn hình. Khi có toán tử `>`, Shell yêu cầu Kernel mở tệp `output.txt`, sau đó sao chép (nối lại) `fd 1` để nó trỏ vào tệp này thay vì màn hình. Chương trình khi chạy vẫn ghi dữ liệu vào `fd 1`; nó không cần biết `fd 1` hiện đang tham chiếu tới terminal, regular file, pipe hay một đối tượng I/O khác.

---

## 9. Pipe và Pipeline

**Pipe (`|`) là cơ chế ghép nối tiến trình, không chỉ là ghép chuỗi văn bản.**

Pipe là một vùng đệm (buffer) do Kernel quản lý. Khi bạn viết `A | B`, Shell tạo ra một pipe, nối `stdout` của tiến trình A vào đầu ghi của pipe, và `stdin` của tiến trình B vào đầu đọc của pipe. Kernel sẽ đồng bộ hóa luồng dữ liệu giữa hai tiến trình này.

```text
[ Tiến trình A ]                        [ Tiến trình B ]
       |                                       ^
       | (stdout 1)                            | (stdin 0)
       +--------> [ Pipe Buffer (Kernel) ] ----+
```

> **Đọc sơ đồ:** Shell yêu cầu Kernel tạo ra một Pipe Buffer nằm gọn trong bộ nhớ lõi. Tiếp đó, Shell cấu hình `stdout` của Tiến trình A nối vào cổng ghi của ống, và `stdin` của Tiến trình B nối vào cổng đọc. Nhờ vậy, Kernel đóng vai trò làm điều phối viên: tiến trình A sẽ bị block (tạm dừng) nếu pipe buffer đã đầy và đang dùng blocking I/O; tiến trình B sẽ bị block chờ nếu pipe chưa có dữ liệu nhưng vẫn còn writer (A) đang mở. Đặc biệt, nếu mọi đầu ghi đã đóng và buffer đã hết dữ liệu, lệnh đọc của B sẽ nhận được tín hiệu kết thúc (EOF) thay vì ngủ chờ vô thời hạn.

*Lưu ý:* Theo mặc định, `stderr` của lệnh A không đi vào pipe mà vẫn xuất ra màn hình. Muốn đưa `stderr` vào pipe, cần thực hiện cú pháp chuyển hướng rõ ràng (ví dụ: `2>&1`). `2>&1` nghĩa là toàn bộ output từ luồng lỗi sẽ vào chung với luồng dữ liệu ra, nếu `2>1` thì sẽ hiểu lầm ghi luồng lỗi vào một file văn bản có tên là `1`.

---

## 10. `exit status` và toán tử điều khiển Shell

Mọi tiến trình khi kết thúc đều trả về một mã số cho tiến trình cha, gọi là `exit status`. Đây là kênh giao tiếp dành cho máy (machine-to-machine), khác với `stdout` là luồng dữ liệu.

*   **Quy ước:** Mã `0` thường biểu thị trạng thái thành công. Mã khác `0` biểu thị một trạng thái khác hoặc thất bại theo quy ước của từng phần mềm cụ thể. Ví dụ: lệnh `grep` trả về `1` khi quá trình chạy vẫn an toàn nhưng không tìm thấy đoạn văn bản khớp mẫu (không nhất thiết là chương trình bị "lỗi").

Shell cung cấp các toán tử để phản ứng với `exit status` này:
*   `&&`: Chạy lệnh tiếp theo chỉ khi lệnh trước trả về 0 (thành công).
*   `||`: Chạy lệnh tiếp theo chỉ khi lệnh trước trả về khác 0 (thất bại).
*   `;`: Chạy tuần tự, không phụ thuộc vào `exit status` của lệnh trước.

---

## 11. `foreground`, `background` và `job control`

*   **Foreground (Tiền cảnh):** Trong một terminal tương tác, nhóm tiến trình tiền cảnh là nhóm nhận tín hiệu trực tiếp từ bàn phím. Khi bạn nhấn `Ctrl+C`, một tín hiệu `SIGINT` được gửi tới nhóm tiền cảnh để ngắt công việc.
*   **Background (Nền):** Tiến trình chạy ở chế độ nền (bằng cách thêm dấu `&` ở cuối lệnh) sẽ chạy ngầm dưới hệ thống. Tuy nhiên, theo nguyên tắc, chỉ nhóm tiến trình tiền cảnh mới được quyền đọc trực tiếp từ controlling terminal. Nếu một tiến trình nền cố tình đọc dữ liệu từ terminal, Kernel sẽ gửi cho nó tín hiệu `SIGTTIN` để đình chỉ hoạt động.
*   **Job Control:** Các tính năng của Shell tương tác giúp di chuyển tiến trình qua lại giữa foreground và background (`fg`, `bg`, `Ctrl+Z`).

---

## 12. Các nhóm lệnh Linux cơ bản

Mục đích của phần này không phải để học thuộc cú pháp, mà hiểu mỗi nhóm lệnh đang tương tác với tầng nào của hệ thống:

*   **Điều hướng & Namespace:** `pwd`, `cd`, `ls`, `mkdir`, `cp`, `mv`, `rm`. Nhóm này tương tác với pathname, thư mục và siêu dữ liệu của hệ thống tệp.
*   **Quan sát nội dung:** `cat`, `head`, `tail`, `less`. Đọc byte từ các file descriptor và xuất ra màn hình.
*   **Lọc và Biến đổi:** `grep`, `sort`, `cut`, `awk`. Nhận dữ liệu từ `stdin`, áp dụng xử lý, và xuất ra `stdout` – cực kỳ phù hợp để ghép nối thành các pipeline.

---

## 13. `grep` và `find`: tìm kiếm theo hai mô hình khác nhau

Sự khác biệt quan trọng nhất là chúng hoạt động trên hai lớp trừu tượng khác nhau:

*   **13.1 `find` (Tìm theo metadata):** Duyệt qua cấu trúc cây thư mục (namespace). Nó đối chiếu điều kiện dựa trên siêu dữ liệu như tên file, quyền truy cập, kích thước, và thời gian sửa đổi (mtime). Nó chủ yếu làm việc với pathname và metadata chứ không đi sâu phân tích dữ liệu byte bên trong tệp.
*   **13.2 `grep` (Tìm theo content):** Đọc luồng dữ liệu hoặc nội dung trực tiếp của file. Nó dùng Biểu thức chính quy (Regular Expressions) để tìm kiếm và trích xuất các dòng văn bản khớp mẫu.

Một bài toán thực tế như *"Tìm tất cả các file cấu hình sửa đổi gần đây và có chứa từ khóa 'ERROR'"* sẽ cần kết hợp cả hai: dùng `find` thu thập file, rồi dẫn hướng sang `grep` để kiểm tra nội dung.

---

## 14. `ps`, `top`, `mount`, `df`, `du` đang quan sát điều gì?

Mỗi công cụ cung cấp một lăng kính quan sát tài nguyên riêng biệt:

*   **`ps`:** Cung cấp ảnh chụp (snapshot) tĩnh về trạng thái các tiến trình tại khoảnh khắc gọi lệnh.
*   **`top`:** Thu thập trạng thái vòng lặp, hiển thị sự thay đổi động của CPU và bộ nhớ theo thời gian thực.
*   **`mount`:** Quản lý và quan sát việc các hệ thống tệp/thiết bị được gắn vào cấu trúc cây thư mục gốc `/`.
*   **`df`:** Đứng ở cấp độ filesystem, báo cáo không gian đã cấp phát (allocation) và còn trống dựa trên siêu dữ liệu quản lý tổng quát của hệ thống tệp đó.
*   **`du`:** Hoạt động bằng cách duyệt đệ quy qua cây thư mục (pathname), đo lường và cộng dồn **số lượng disk blocks đã cấp phát** (allocated disk blocks) của từng tệp tin. Đây chính là lý do khiến dung lượng báo bởi `du` có thể khác với kích thước logic của file khi xem bằng lệnh `ls -l`.

*(Vì đo đạc từ hai góc nhìn khác biệt, số liệu của `df` và `du` đôi khi sẽ có độ lệch tự nhiên mà không phải do lỗi hệ thống).*

---

## 15. Tư duy gỡ lỗi khi một lệnh không hoạt động

Khi hệ thống báo lỗi, hãy tư duy theo cấu trúc các lớp (layers) đã học thay vì thử ngẫu nhiên:

1.  **Lỗi "Command not found":**
    *   Tên lệnh gõ đúng chính tả không?
    *   Thư mục chứa file thực thi đã có trong biến `PATH` chưa?
    *   Bản thân file executable đó có tồn tại không? (Đối với script, hãy kiểm tra cả dòng interpreter `#!/bin/bash` ở đầu tệp).
2.  **Lỗi "Permission denied":**
    *   Hãy kiểm tra chủ sở hữu (ownership) và cờ phân quyền (read/write/execute bits) trên bản thân file.
    *   Kiểm tra quyền truy cập (execute bit) của các thư mục cha dẫn đến file đó.
    *   Kiểm tra các tùy chọn của hệ thống tệp (ví dụ phân vùng được mount với cờ `noexec`).
    *   Chỉ khi xác nhận thiết lập cấu hình thuộc về tài khoản quản trị viên thì mới cần gọi đặc quyền hệ thống (`sudo`).
3.  **Pipeline không hoạt động đúng:**
    *   Phân tách từng mắt xích. Đảm bảo tiến trình A xả ra `stdout` đúng định dạng mong đợi trước khi `pipe` nó vào `stdin` của tiến trình B. Chú ý luồng lỗi `stderr` có thể bị rò rỉ ra terminal.

---

## 16. Liên hệ với Embedded Linux

Khi mang Linux lên các hệ thống nhúng, các thiết bị thường không có GUI, thậm chí không có cả kết nối mạng trong quá trình bring-up ban đầu. 

Các giao diện phổ biến để kết nối thường là cổng serial UART (console) hoặc SSH (PTY). Trong môi trường này, kỹ năng dòng lệnh là một trong những công cụ chẩn đoán quan trọng nhất. Sự thông hiểu về `file descriptor`, chuyển hướng `stdout/stderr` để kiểm soát log hệ thống (như xuất từ dmesg), và khai thác `exit status` trong các Makefile hay CMake trở thành kỹ năng sinh tồn thiết yếu để phát triển và bring-up hệ thống Embedded Linux.

Thêm vào đó, để tối ưu dung lượng lưu trữ, hệ thống nhúng thường gói gọn hàng chục công cụ vào một tệp thực thi duy nhất gọi là **BusyBox**. Mặc dù cú pháp của BusyBox có thể được rút gọn so với các tiện ích GNU tiêu chuẩn, các mô hình cốt lõi về shell parsing, pipeline và xử lý tiến trình hoàn toàn không thay đổi.

---

## 17. Tổng kết

Hãy lưu giữ mô hình vận hành duy nhất này trong tư duy:

```text
Người dùng nhập chuỗi 
   |
Terminal/TTY truyền dữ liệu 
   |
Shell phân tích (Parse) 
   |
Shell mở rộng cú pháp (Expand) 
   |
Shell chuẩn bị luồng I/O (Redirection/Pipe) 
   |
Shell tra cứu lệnh (PATH) 
   |
Kernel tạo tiến trình (Fork/Execve) 
   |
Tiến trình chạy và báo cáo (Exit status)
```

> **Đọc sơ đồ:** Đọc chuỗi này từ trên xuống dưới, ta thấy rõ trách nhiệm của từng thành phần. Terminal/TTY làm nhiệm vụ dẫn truyền tín hiệu thô; Shell đóng vai trò như một bộ não trung tâm chuyên dịch cú pháp, thiết lập môi trường và cấu hình các File Descriptor/Pipe; cuối cùng, Kernel đảm nhiệm vai trò cung cấp tài nguyên, tạo tiến trình và thực thi công việc thực tế. Khi đối mặt với một chuỗi lệnh phức tạp bị lỗi, hãy bóc tách tuần tự theo lớp: Lỗi đang xảy ra ở khâu cấu hình chuẩn bị của Shell, hay ở khâu chạy của bản thân chương trình?

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
- Linux TTY documentation: https://docs.kernel.org/driver-api/tty/

> **Điều hướng:** [Chủ đề 2 — Hệ thống tệp Linux →](README-topic-02.md)
