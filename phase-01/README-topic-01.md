# Chủ đề 1 — Dòng lệnh Linux cơ bản

> **Mục tiêu:** Hiểu bản chất cách dòng lệnh Linux hoạt động giống như cách vận hành một dây chuyền, thay vì học vẹt từng lệnh máy móc.
>
> **Quy ước ngôn ngữ:** Giải thích bằng tiếng Việt đời thường, nhưng các từ khóa quan trọng (như `shell`, `pipe`, `stdout`...) vẫn giữ nguyên tiếng Anh để bạn dễ dàng tra cứu Google sau này.
>
> **Phạm vi:** Các khái niệm cơ bản nhất như `terminal`, `shell`, biến môi trường, đường ống (`pipe`), chuyển hướng (`redirection`), và cách gỡ lỗi.
>
> Chương này là **lý thuyết nền tảng**, đọc như một câu chuyện, không cần gõ code ngay.

Trước khi đi vào chi tiết, hãy nhớ một nguyên tắc sống còn: **Bàn phím của bạn không hề nói chuyện trực tiếp với lõi máy tính (Kernel). Bàn phím chỉ nói chuyện với một "tổng đài viên" tên là Shell**. Khi hiểu được ông Shell này làm việc thế nào, mọi lệnh Linux sẽ trở nên cực kỳ hiển nhiên.

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

Dòng lệnh đơn giản là cách bạn "nhắn tin sai vặt" hệ điều hành. 

### 1.1 CLI và GUI khác nhau ở đâu?
Hãy tưởng tượng bạn đi ăn nhà hàng:
*   **GUI (Giao diện đồ họa):** Giống như bạn ra quầy fast-food, nhìn bảng menu và **chỉ tay** vào "Combo 1". Rất tiện, rất dễ, nhưng bạn không thể kêu họ làm một món nằm ngoài menu.
*   **CLI (Giao diện dòng lệnh):** Giống như bạn đi thẳng vào bếp và nói với đầu bếp: *"Cho tôi 2 lạng thịt băm, xào hành tây, không bỏ muối"*. Ban đầu hơi khó vì bạn phải biết "từ vựng", nhưng bù lại, bạn có thể tự do ghép nối mọi thứ mình muốn.

```text
GUI:  Người dùng ---> [Nút bấm] ---> Ứng dụng
CLI:  Người dùng ---> [Dòng lệnh] ---> Shell ---> Chương trình
```

### 1.2 Dòng lệnh không phải `system call`
Khi bạn gõ `ls -l /etc` (lệnh xem danh sách file), máy tính không nhận nguyên cả câu đó. Máy tính sẽ đưa câu đó cho ông "tổng đài viên" Shell phân tích trước, sau đó Shell mới đi gọi đúng người chịu trách nhiệm chạy lệnh đó.

---

## 2. Terminal, TTY, PTY và Shell

Hãy coi việc bạn gõ lệnh giống như bạn đang **gọi điện thoại**:
*   **2.1 Terminal:** Là cái **vỏ điện thoại** (gồm màn hình và bàn phím của bạn).
*   **2.2 TTY / 2.3 PTY:** Là **sóng viễn thông** giúp truyền giọng nói của bạn đi và nhận âm thanh trả về.
*   **2.4 Shell:** Là **tổng đài viên** ở đầu dây bên kia (phổ biến nhất là Bash). Người này nghe bạn nói, hiểu cú pháp lệnh của bạn, sau đó mới bấm máy chuyển đến đúng phòng ban xử lý.

**2.5 Quan hệ tổng thể:**

```text
[Bàn phím] 
    |
    v
[Terminal / PTY] (Điện thoại/Sóng)
    |
    v
[Shell]          (Tổng đài viên hiểu lệnh)
    |
    v
[Chương trình]   (Phòng ban xử lý yêu cầu)
```

---

## 3. Shell hiểu một dòng lệnh như thế nào?

Shell là một "người phiên dịch", không phải một cái loa. 

Khi bạn gõ: `echo "$HOME" | grep home > result.txt`
Shell không ném nguyên câu này cho máy tính. Nó thực hiện quy trình sau:

```text
"echo $HOME > result.txt"
           |
           v
[ 1. Phân tích (Parse)   ]  Nhận ra 'echo' là lệnh, '>' là ký hiệu đặc biệt.
           |
           v
[ 2. Mở rộng (Expand)    ]  Dịch chữ '$HOME' thành '/home/user'.
           |
           v
[ 3. Ống dẫn (Redirect)  ]  Chuẩn bị sẵn file 'result.txt' để hứng dữ liệu.
           |
           v
[ 4. Thực thi (Execute)  ]  Chạy lệnh echo với đầu ra đã được bẻ lái vào file.
```

**Tóm lại:** Lỗi thường gặp nhất không phải do lệnh sai, mà do bạn viết sai cú pháp khiến ông Shell "dịch" nhầm ý bạn.

---

## 4. Quoting và Shell expansion

Ký hiệu nháy (`' '` hoặc `" "`) là cách bạn bảo vệ các chữ cái khỏi sự "táy máy" của ông Shell.

*   **4.1 Vì sao phải dùng dấu nháy?** Shell rất nhạy cảm với dấu cách, dấu `*`, dấu `$`. Nếu bạn có một file tên là `my file.txt` (có khoảng trắng), Shell sẽ tưởng đó là 2 file `my` và `file.txt`.
*   **4.2 Nháy đơn (`' '`):** Đóng băng mọi thứ. Nếu bạn gõ `'$HOME'`, máy tính in ra đúng chữ `$HOME`.
*   **4.3 Nháy kép (`" "`):** Đóng băng một nửa. Dấu cách được bảo vệ, nhưng dấu `$HOME` vẫn sẽ bị dịch ra thành `/home/user`.

---

## 5. Shell tìm chương trình bằng `PATH` như thế nào?

Làm sao máy tính biết lệnh `ls` nằm ở đâu trong cái ổ cứng mênh mông? Nó dùng "danh bạ điện thoại" mang tên `PATH`.

*   **5.1 PATH là gì?** `PATH` là một danh sách các thư mục. Khi bạn gõ `ls`, Shell sẽ lật danh bạ ra tìm từng phòng một:

```text
Lệnh: ls
  |
  +---> Tìm ở /usr/local/bin/ls ? ---> (Không thấy)
  |
  +---> Tìm ở /bin/ls ?           ---> (Không thấy)
  |
  +---> Tìm ở /usr/bin/ls ?       ---> (CÓ! Chạy ngay)
```

*   Nếu tìm hết các phòng trong `PATH` mà không có, Shell báo lỗi kinh điển: `Command not found`.
*   **5.2 Khi lệnh có dấu `/`:** Nếu bạn gõ `./app`, tức là bạn đã chỉ đích danh tọa độ cho Shell, nó không cần lật danh bạ `PATH` ra tìm nữa.

---

## 6. Thư mục làm việc và đường dẫn

*   **6.1 Thư mục làm việc hiện tại (cwd):** Hãy tưởng tượng bạn đang đứng trong một căn phòng. Khi bạn bảo *"lấy cái ly"*, người ta sẽ tự hiểu là cái ly trong căn phòng bạn đang đứng (Đường dẫn tương đối). 
*   **6.2 Đường dẫn tuyệt đối:** Là việc bạn đọc tọa độ GPS chính xác (bắt đầu bằng dấu `/`, ví dụ `/home/user/desktop/ly.txt`).
*   Lệnh `cd` (Change Directory) chính là hành động bạn tự nhấc chân bước sang căn phòng khác.

---

## 7. Shell variable, environment variable và `argv`

Làm sao các chương trình truyền thông tin cho nhau? Bằng cách dán "giấy ghi chú" (biến).

*   **7.1 Shell variable (Biến cục bộ):** Là tờ giấy nhớ bạn dán trên bàn của riêng bạn, người khác không đọc được.
*   **7.2 Environment variable (Biến môi trường):** Là tờ giấy nhớ mà bạn (tiến trình cha) chủ động nhét vào túi áo của người khác (tiến trình con) để họ mang đi làm việc.
*   **7.3 Lệnh `export`:** Chính là hành động cộp mác "Cho phép mang tờ giấy này sang chương trình con".

---

## 8. `stdin`, `stdout`, `stderr` và redirection

Hãy tưởng tượng mọi chương trình trong Linux đều là một cái hộp có **3 cái lỗ (File descriptor)**:
*   **Lỗ hút vào (`stdin` - fd 0):** Nhận nguyên liệu (mặc định là từ bàn phím).
*   **Lỗ xả sạch (`stdout` - fd 1):** Trả ra kết quả đúng (mặc định in ra màn hình).
*   **Lỗ xả thải (`stderr` - fd 2):** Trả ra thông báo lỗi (cũng in ra màn hình).

```text
[ Bàn phím ] ---> (stdin 0) ---> [ CHƯƠNG TRÌNH ] ---> (stdout 1) ---> [ Màn hình ]
                                        |
                                        +------------> (stderr 2) ---> [ Màn hình ]
```

**Chuyển hướng (Redirection >):**
Giống như bạn lấy băng keo bịt "Lỗ xả sạch" lại, cắm một cái ống để nó chảy vào file `.txt` thay vì chảy ra màn hình.

```text
SAU KHI CHUYỂN HƯỚNG: Lệnh > result.txt

[ Bàn phím ] ---> (stdin 0) ---> [ CHƯƠNG TRÌNH ] ---> (stdout 1) --X-- [ Màn hình ]
                                        |                 |
                                        |                 +-----------> [ result.txt ]
                                        |
                                        +------------> (stderr 2) ----> [ Màn hình ]
```

---

## 9. Pipe và Pipeline

**Pipe (`|`) là đường ống nối ghép dây chuyền nhà máy**.

Thay vì xả "nước sạch" của lệnh A ra một cái file trung gian, tại sao không dẫn nó cắm thẳng vào "lỗ hút" của lệnh B?
*Ví dụ:* `Lệnh_Vắt_Cam | Lệnh_Thêm_Đường`.
Đầu ra của máy vắt cam được truyền trực tiếp làm nguyên liệu đầu vào cho máy thêm đường.

```text
[ Lệnh A (Vắt cam) ]                        [ Lệnh B (Thêm đường) ]
       |                                              ^
       | (stdout xả ra)                               | (stdin hút vào)
       +-----------------> [ ỐNG PIPE | ] ------------+
```

---

## 10. `exit status` và toán tử điều khiển Shell

Các chương trình trong Linux rất ít nói. Khi làm xong việc, nó không la lên *"Tôi xong rồi!"*, mà nó giơ bảng số (exit status).
*   Giơ số **0**: Nghĩa là "Thành công mỹ mãn!".
*   Giơ số **khác 0 (1, 2, 255...)**: Nghĩa là "Lỗi rồi, toang rồi!".

Nhờ cái bảng số này, Shell dùng các toán tử để quyết định bước tiếp theo:
*   `&&` (VÀ): Chỉ chạy lệnh 2 nếu lệnh 1 thành công (giơ số 0).
*   `||` (HOẶC): Chỉ chạy lệnh 2 nếu lệnh 1 thất bại.

---

## 11. `foreground`, `background` và `job control`

*   **Tiền cảnh (Foreground):** Giống như bạn đang tự tay thái rau. Bạn phải làm xong thì mới rảnh tay làm việc khác.
*   **Nền (Background):** Giống như bạn ném quần áo vào máy giặt rồi bấm nút. Máy giặt vẫn chạy ầm ầm, nhưng tay bạn thì rảnh để ra lướt điện thoại (gõ lệnh tiếp).

---

## 12. Các nhóm lệnh Linux cơ bản

Bạn không cần học thuộc vẹt hàng trăm lệnh, chỉ cần biết "hộp đồ nghề" nhà mình có những món gì:
*   *Nhóm đi lại:* `cd`, `ls`, `pwd`.
*   *Nhóm xem nội dung:* `cat`, `head`, `tail`.
*   *Nhóm lọc dữ liệu:* `grep`, `sort`, `cut` (Thường được ghép nối qua ống Pipe `|`).

---

## 13. `grep` và `find`: tìm kiếm theo hai mô hình khác nhau

Hãy tưởng tượng bạn vào một nhà sách khổng lồ:
*   **13.2 `find` (Tìm ngoài bìa sách):** Bạn nhờ thủ thư đi gom tất cả các cuốn sách *Bìa màu xanh, xuất bản năm 2023*. Thủ thư lướt qua các kệ sách rất nhanh, gom đủ sách nhưng **không thèm đọc ruột sách**.
*   **13.1 `grep` (Tìm trong ruột sách):** Bạn đưa cho thủ thư 1 cuốn sách, yêu cầu lật từng trang, lấy bút dạ quang tô đậm những câu có chữ "Kho báu".

**Tóm tắt:** `find` tìm đồ vật dựa trên vỏ ngoài (tên file). `grep` tìm văn bản dựa trên ruột bên trong. Dùng `find` gom sách lại `|` đưa cho `grep` lật từng trang.

---

## 14. `ps`, `top`, `mount`, `df`, `du` đang quan sát điều gì?

Đây là nhóm lệnh giống như đồ nghề khám bệnh của bác sĩ:
*   `ps`: Chụp cho hệ thống 1 tấm ảnh X-Quang xem ai đang chạy.
*   `top`: Lắp máy đo nhịp tim, dữ liệu nhảy liên tục theo thời gian thực.
*   `df`: Mở bản đồ kho hàng xem tổng dung lượng trống của kho.
*   `du`: Xách cái cân đi cân thử từng kiện hàng xem kiện nào nặng nhất.

---

## 15. Tư duy gỡ lỗi khi một lệnh không hoạt động

Đừng bao giờ gõ bừa khi gặp lỗi. Hãy dùng "sổ tay sơ cứu":
*   **Bệnh "Command not found":** Có gõ sai chính tả không? Máy đã cài phần mềm đó chưa? (Kiểm tra danh bạ `PATH`).
*   **Bệnh "Permission denied":** Bạn là "nhân viên quèn" nhưng đòi vào "phòng giám đốc". Giải pháp: Thêm lệnh `sudo` (mượn thẻ VIP) trước dòng lệnh.
*   **Bệnh lạ khi dùng Pipe (`|`):** Cứ tách dây chuyền ra, kiểm tra từng máy một xem máy nào nhổ ra đồ hỏng.

---

## 16. Liên hệ với Embedded Linux

Khi làm việc với các board mạch nhúng như STM32, ESP32-S3 hay lúc bạn build firmware cho OpenWrt, thiết bị của bạn không có màn hình cảm ứng hay chuột. 

Thứ duy nhất bạn có là một màn hình đen xì qua cổng UART Serial hoặc SSH. Lúc này, kỹ năng dùng lệnh để cấu hình, kiểm tra `exit status`, dùng `pipe` để nối luồng xử lý hay tra log hệ thống (BusyBox) chính là cầu nối duy nhất giúp bạn giao tiếp và debug thiết bị nhúng.

---

## 17. Tổng kết

Hãy nhớ mô hình duy nhất này: **Bạn gõ chữ -> Shell dịch cú pháp -> Cắm ống nước (pipe/redirection) -> Tìm đúng người (PATH) -> Chạy chương trình -> Trả về bảng số (exit status)**.

Nếu lệnh không chạy, đừng vội chửi cái chương trình bị hỏng. Hãy xem lại xem bạn có viết sai cú pháp khiến ông Shell "dịch" sai ý bạn không nhé.

---

## 18. Tài liệu tham khảo

*   POSIX.1-2024 Shell Command Language: https://pubs.opengroup.org/onlinepubs/9799919799/
*   GNU Bash Manual: https://www.gnu.org/software/bash/manual/
*   Linux man-pages: https://man7.org/linux/man-pages/
*   GNU Coreutils Manual: https://www.gnu.org/software/coreutils/manual/
*   GNU Grep Manual: https://www.gnu.org/software/grep/manual/
*   GNU Findutils Manual: https://www.gnu.org/software/findutils/manual/
*   Bootlin Embedded Linux training: https://bootlin.com/training/embedded-linux/

> **Điều hướng:** [Chủ đề 2 — Hệ thống tệp Linux →](README-topic-02.md)
