# Chủ đề 5 — Signal trong Linux

> **Mục tiêu:** Hiểu rõ `signal` là cơ chế thông báo bất đồng bộ của UNIX/Linux: từ khoảnh khắc phát sinh (`signal generation`), trạng thái chờ đợi (`pending`), cho tới lúc được phân phối (`signal delivery`) và xử lý.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt, nhưng thuật ngữ `signal` được giữ nguyên để không nhầm lẫn với tín hiệu điện phần cứng trong hệ nhúng. Các thuật ngữ chuẩn như `signal generation`, `pending`, `signal delivery`, `signal disposition`, `signal mask`, `handler`, `async-signal-safe` cùng tên API, cờ và mã lỗi được giữ nguyên tiếng Anh để đối chiếu tài liệu POSIX.
>
> **Phạm vi:** `signal generation` → `pending` → `signal delivery`, `signal disposition`, `signal mask`, `sigaction()`, `sigprocmask()`, `kill()`, `raise()`, hàm xử lý (handler), `async-signal-safety`, `EINTR`, `SA_RESTART`, và các signal quan trọng.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để định hình tư duy về luồng thực thi bất đồng bộ, không có bài thực hành.

Signal nên được hiểu là **một cơ chế thông báo do Kernel can thiệp và chuyển tới tiến trình (hoặc luồng)**, hoàn toàn khác biệt với một lời gọi hàm (function call) bình thường. Khi một signal phát sinh, nó có thể bị chặn lại (`pending`), bị lờ đi, thực thi hành động mặc định của Kernel, hoặc khiến luồng chương trình rẽ ngang vào một đoạn mã xử lý do bạn tự định nghĩa (`handler`).

Điểm cốt lõi của signal không nằm ở việc ghi nhớ tên gọi `SIGINT` hay `SIGTERM`, mà ở việc thấu hiểu **thời điểm `signal delivery` xảy ra** và những **giới hạn khắt khe** khi handler bất ngờ chen ngang vào giữa luồng thực thi đang chạy dở dang của ứng dụng.

---

## Mục lục

- [1. `signal` là gì?](#1-signal-là-gì)
- [2. Vòng đời của một `signal`](#2-vòng-đời-của-một-signal)
- [3. Tiến trình làm gì khi nhận `signal`?](#3-tiến-trình-làm-gì-khi-nhận-signal)
- [4. Các signal thường gặp](#4-các-signal-thường-gặp)
- [5. `disposition`, `signal mask` và trạng thái `pending`](#5-disposition-signal-mask-và-trạng-thái-pending)
- [6. `sigaction()`: cấu hình `signal disposition`](#6-sigaction-cấu-hình-signal-disposition)
- [7. `signal set` và `sigprocmask()`](#7-signal-set-và-sigprocmask)
- [8. Gửi signal bằng `kill()` và `raise()`](#8-gửi-signal-bằng-kill-và-raise)
- [9. `signal handler` chen vào luồng chạy như thế nào?](#9-signal-handler-chen-vào-luồng-chạy-như-thế-nào)
- [10. Vì sao hàm xử lý signal phải rất hạn chế?](#10-vì-sao-hàm-xử-lý-signal-phải-rất-hạn-chế)
- [11. Signal và `system call`: `EINTR`, `SA_RESTART`](#11-signal-và-system-call-eintr-sa_restart)
- [12. Race condition và `sigsuspend()`](#12-race-condition-và-sigsuspend)
- [13. Tư duy gỡ lỗi signal](#13-tư-duy-gỡ-lỗi-signal)
- [14. Liên hệ với Embedded Linux](#14-liên-hệ-với-embedded-linux)
- [15. Tổng kết](#15-tổng-kết)
- [16. Tài liệu tham khảo](#16-tài-liệu-tham-khảo)

---

## 1. `signal` là gì?

`signal` là một phương thức truyền thông điệp bất đồng bộ, trong đó Kernel hoặc một tiến trình khác gửi một thông báo tới tiến trình đích để báo hiệu một sự kiện (ví dụ: yêu cầu kết thúc, vi phạm bộ nhớ, hoặc ngắt từ bàn phím). Nó là cơ chế thông báo/điều khiển (notification/control mechanism), không phải là một kênh truyền dữ liệu (data channel) như pipe, socket hay shared memory.

### 1.1 `signal` không phải lời gọi hàm thông thường

Trong lập trình tuần tự, luồng kiểm soát là **đồng bộ và tường minh**:
```text
[ Code đang chạy ] 
       |
  (Gọi hàm A) 
       v
    [ Hàm A ] 
       |
  (Return về) 
       v
[ Code tiếp tục chạy ]
```

Ngược lại, `signal` mang tính **bất đồng bộ**:
```text
[ Code đang chạy bình thường ]
            |
            | (Bất ngờ có sự kiện từ bên ngoài / hoặc lỗi)
            v
[ Kernel đóng băng luồng hiện tại, chuẩn bị Signal Delivery ]
            |
            v
[ Ép luồng nhảy sang chạy Signal Handler (nếu có) ]
            |
            v
[ Trả về dòng code đang chạy dở dang trước đó ]
```

> **Đọc sơ đồ:** Thời điểm `signal delivery` xảy ra hoàn toàn nằm ngoài sự kiểm soát của dòng code bạn đang viết. Sự kiện có thể giáng xuống ngay giữa lúc chương trình đang thực hiện lệnh `malloc()` hoặc đang mở một kết nối mạng. Đây chính là gốc rễ tạo ra những quy tắc nghiêm ngặt về `signal mask` và `async-signal-safety`.

### 1.2 Nguồn tạo ra signal

`signal` là một cơ chế giao tiếp đa dụng, nó có thể được sinh ra từ:
*   Tiến trình khác: Gọi hàm API `kill()`.
*   Terminal: Người dùng nhấn `Ctrl+C` (tạo `SIGINT`).
*   Kernel (Thông báo trạng thái): Tiến trình con kết thúc tạo ra `SIGCHLD`; Ghi vào một `pipe/socket` đã bị đóng tạo ra `SIGPIPE`.
*   CPU/Memory Fault: Truy cập con trỏ NULL tạo ra `SIGSEGV` (Segmentation fault); chia cho 0 tạo ra `SIGFPE`.

### 1.3 “Bất đồng bộ” không có nghĩa là hoàn toàn ngẫu nhiên

Một số signal thực chất gắn chặt (đồng bộ) với câu lệnh đang thực thi, ví dụ như lỗi truy cập vùng nhớ `SIGSEGV`.
Tuy nhiên, phần lớn các signal như `SIGTERM` (yêu cầu tắt) đều đến từ bên ngoài (bất đồng bộ). Cả hai trường hợp đều đi chung một con đường xử lý, nhưng cách bạn suy luận để debug sẽ rất khác nhau.

---

## 2. Vòng đời của một `signal`

Một `signal` đi qua các trạm kiểm soát của Kernel trước khi thực sự tác động đến tiến trình.

### 2.1 Ba khái niệm nền tảng

```text
[ Signal Generation (Phát sinh) ]
             |
             v
         [ Pending (Đang chờ) ]
             |
             v
[ Signal Delivery (Phân phối xử lý) ]
```

### 2.2 Sơ đồ trạng thái chi tiết

```text
             [ SIGNAL GENERATION ]
          Signal được phát sinh/gửi đến
                     |
                     v
              [ SIGNAL PENDING ]
        Signal đang chờ được phân phối
                     |
                     v
          Signal có đang bị BLOCK
          bởi signal mask không?
                /           \
              Có             Không
              |                |
              |                v
              |        [ Có thể được chọn
              |          để DELIVERY ]
              |                |
              |                v
              |      [ SIGNAL DELIVERY ]
              |                |
              |                v
              |        Xét signal disposition
              |          /      |      \
              |         /       |       \
              |        v        v        v
              |    SIG_IGN   Handler   SIG_DFL
              |       |         |         |
              |       v         v         v
              |    Bỏ qua    Chạy      Hành động
              |              handler    mặc định
              |
              +---- chờ đến khi được UNBLOCK ----+
                                                  |
                                                  +--> quay lại bước
                                                       kiểm tra BLOCK
```

> **Đọc sơ đồ:** Sau khi một signal được **phát sinh** (`signal generation`), signal được xem là **pending** trong khoảng thời gian từ lúc phát sinh cho tới khi được **phân phối** (`signal delivery`). Nếu signal đang bị chặn bởi `signal mask`, nó tiếp tục ở trạng thái `pending` và chưa được phân phối. Khi signal không còn bị chặn, Kernel có thể chọn signal đó để thực hiện `delivery`.
>
> Khi `signal delivery` xảy ra, hành động cụ thể phụ thuộc vào `signal disposition` đã cấu hình:
> - `SIG_IGN`: bỏ qua signal.
> - `Handler`: chuyển luồng điều khiển sang chạy hàm xử lý signal.
> - `SIG_DFL`: thực hiện hành động mặc định của signal, chẳng hạn `Terminate`, `Terminate + Core dump`, `Stop`, `Continue` hoặc `Ignore`, tùy loại signal.
>
> **Lưu ý:** `Block` và `Ignore` là hai khái niệm khác nhau. `Block` chỉ **trì hoãn việc delivery**, khiến signal tiếp tục ở trạng thái `pending`; còn `SIG_IGN` là một `signal disposition` yêu cầu bỏ qua signal. Trên Linux, nếu một signal vừa bị block vừa có disposition là `SIG_IGN`, signal đó không được thêm vào tập pending khi phát sinh. Vì vậy, sơ đồ trên nên được hiểu chủ yếu là luồng của một signal **không bị loại bỏ do `SIG_IGN`**. Ngoài ra, “đã gửi signal” không đồng nghĩa với “handler bên kia đã chạy ngay lập tức”.


---

## 3. Tiến trình làm gì khi nhận `signal`?

Khoảnh khắc Kernel thực hiện `signal delivery`, số phận tiến trình phụ thuộc vào các thiết lập gọi là `signal disposition` (cách hành xử).

### 3.1 `signal disposition` (Cách hành xử)

Mỗi loại `signal` đều được gán một cách hành xử. Tiến trình có 3 lựa chọn:

#### 3.1.1 Hành động mặc định (Default action)

Nếu bạn không cấu hình gì, Kernel áp dụng luật mặc định:
*   `Terminate`: Kết thúc tiến trình (vd: SIGTERM).
*   `Terminate + Core dump`: Kết thúc tiến trình và ghi trạng thái RAM ra file `core` để debug (vd: SIGSEGV).
*   `Ignore`: Không làm gì (vd: SIGCHLD).
*   `Stop` / `Continue`: Dừng hoặc tiếp tục chạy.

#### 3.1.2 Bỏ qua (Ignore)

Bạn có quyền cấu hình yêu cầu Kernel hoàn toàn lờ đi một signal (bằng cờ `SIG_IGN`). Khi đó, signal không gây ra tác động nào và không có bất kỳ Handler nào được chạy.

#### 3.1.3 Bắt và xử lý bằng `Handler` (Catch)

Bạn tự viết một hàm C (gọi là Handler) và đăng ký với Kernel. Khi signal được `delivery`, Kernel sẽ ép luồng thực thi tạm nhảy sang chạy hàm Handler của bạn. Chạy xong, nó dùng cơ chế `sigreturn` để quay về dòng code cũ đang chạy dở dang.

### 3.5 Hai ngoại lệ: `SIGKILL` và `SIGSTOP`

Kernel không cho phép tiến trình can thiệp vào hai signal này. Bạn không thể Bắt (Catch), Bỏ qua (Ignore) hay Chặn (Block) chúng. Đây là cơ chế của Kernel để đảm bảo luôn có thể kiểm soát được hệ thống khi ứng dụng bị treo.

---

## 4. Các signal thường gặp

Không cần học thuộc toàn bộ bảng Signal. Hãy nắm vững ngữ nghĩa của các loại phổ biến. *(Luôn dùng tên macro như `SIGINT` thay vì hard-code số `9` hay `15` trong mã nguồn).*

### 4.1 `SIGINT` (Interrupt)

Ngắt từ bàn phím (thường do gõ `Ctrl+C`). Được Terminal gửi tới nhóm tiến trình đang chạy ở Tiền cảnh (Foreground process group).

### 4.2 `SIGTERM` (Terminate)

Yêu cầu kết thúc. 
Ứng dụng CÓ THỂ bắt (catch) signal này. Nó là tiêu chuẩn cho quá trình `graceful shutdown`: Khi nhận `SIGTERM`, Service sẽ ngừng nhận request mới, ghi nốt dữ liệu, đóng kết nối mạng rồi mới kết thúc.

### 4.3 `SIGKILL` (Kill)

Yêu cầu kết thúc bắt buộc.
Do không thể bị Catch hay Block, Kernel sẽ kết thúc tiến trình ngay lập tức. Ứng dụng không có cơ hội gọi các lệnh dọn dẹp bộ nhớ hay lưu file. Vì vậy, `SIGKILL` (`kill -9`) chỉ nên dùng như giải pháp cuối cùng.

### 4.4 `SIGCHLD` (Child)

Được Kernel gửi cho Tiến trình cha khi một Tiến trình con thay đổi trạng thái (kết thúc, bị dừng). 
`SIGCHLD` đóng vai trò thông báo; tiến trình cha vẫn phải chủ động gọi hàm `wait()` / `waitpid()` để thực sự thu hồi trạng thái của tiến trình con. Việc đặt disposition của `SIGCHLD` thành `SIG_IGN` có những hệ quả đặc biệt trong POSIX (có thể khiến tiến trình con tự động bị reap mà không thành zombie, nhưng chi tiết phụ thuộc cấu hình).

### 4.5 Các lỗi trầm trọng (Faults)

*   `SIGSEGV` (Segmentation fault): Vi phạm quy tắc bảo vệ bộ nhớ, hoặc giải tham chiếu con trỏ NULL.
*   `SIGILL` (Illegal instruction): CPU gặp phải mã máy không hợp lệ.
*   `SIGFPE` (Floating-point exception): Các lỗi toán học (không chỉ dành riêng cho số thực, mà bao gồm cả lỗi chia cho 0).
*   `SIGPIPE`: Cố gắng ghi vào một đường ống (`pipe`/`socket`) mà đầu đọc bên kia đã đóng kết nối. (Thường phải Ignore signal này để ứng dụng tự xử lý qua mã lỗi `EPIPE` của hàm write).

---

## 5. `disposition`, `signal mask` và trạng thái `pending`

Đây là ba mảng khái niệm hay bị nhầm lẫn nhất.
*   **`Disposition` (Cách xử lý):** Hành động được áp dụng khi signal được phân phối.
*   **`Signal mask` (Tập chặn):** Danh sách các signal đang bị tiến trình/luồng chặn tại thời điểm hiện tại.
*   **`Pending` (Chờ xử lý):** Signal đã phát sinh nhưng chưa được phân phối.

### 5.1 `Disposition` có phạm vi toàn tiến trình

Cách hành xử được chia sẻ chung cho mọi luồng (Thread) trong một tiến trình. Nếu một luồng thay đổi Handler của `SIGTERM`, thì toàn bộ tiến trình sẽ áp dụng disposition mới đó.

### 5.2 `Signal mask` (Tập chặn)

Là tập hợp các loại signal đang bị CHẶN (Block) tại thời điểm hiện tại.

```text
[ Signal Mask đang Block SIGUSR1 ]
             |
   (Signal SIGUSR1 phát sinh)
             |
             v
[ Signal bị giữ ở trạng thái PENDING ]
             |
   (Ứng dụng gỡ chặn: Unblock)
             |
             v
[ SIGNAL DELIVERY: Chạy Handler ]
```

> **Đọc sơ đồ:** Block không làm signal biến mất. Nó chỉ bắt tín hiệu đó đứng chờ (Pending). Khi ứng dụng Unblock, tín hiệu đó sẽ được phân phối. Đây là khác biệt cốt lõi giữa **Block** (tạm hoãn phân phối) và **Ignore** (loại bỏ signal).

### 5.3 `Signal mask` là của riêng từng luồng

Trái với Disposition, trong môi trường đa luồng (multi-threading), mỗi luồng (Thread) tự giữ một `Signal mask` riêng biệt. (Chi tiết ở Topic 6).

---

## 6. `sigaction()`: cấu hình `signal disposition`

Để đăng ký một Handler (cấu hình disposition), API chuẩn của POSIX là `sigaction()`. Ưu tiên sử dụng API này thay cho hàm `signal()` cũ vì `signal()` có lịch sử ngữ nghĩa thiếu nhất quán giữa các hệ điều hành.

### 6.1 Cấu trúc `struct sigaction`

Để dùng API, bạn điền cấu hình vào một struct, gồm 3 trường quan trọng nhất:
*   `sa_handler`: Hàm bạn muốn Kernel gọi. (Hoặc điền `SIG_DFL` để khôi phục mặc định, `SIG_IGN` để lơ đi).
*   `sa_mask`: Tập các signal mà Kernel sẽ **tạm thời block thêm trong lúc Handler đang chạy**. Các signal này được cộng vào `signal mask` hiện tại của luồng, nhằm ngăn chúng được `delivery` và chen ngang Handler. Ngoài các signal được liệt kê trong `sa_mask`, **signal đang kích hoạt Handler cũng mặc định tự động bị block** trong thời gian Handler thực thi, trừ khi sử dụng cờ `SA_NODEFER`. Khi Handler kết thúc bình thường, Kernel khôi phục `signal mask` trước đó.
*   `sa_flags`: Các cờ tinh chỉnh hành vi đặc biệt.

### 6.2 Cờ `SA_RESTART` (Khởi động lại System Call)

Khi một luồng đang bị chặn trong một lời gọi chờ (`blocking call`) như `read()`, một signal có thể được `delivery` và khiến Kernel tạm dừng lời gọi đó để chuyển sang chạy `handler`.

Mô hình tổng quát:

```text
[ Blocking system call ]
          |
          v
   Đang ngủ / chờ
          |
          | Signal được delivery
          v
     [ Handler chạy ]
          |
          v
    Handler kết thúc
          |
          v
  System call đang dở dang
  sẽ được xử lý thế nào?
```

Nếu handler **không** được cài với cờ `SA_RESTART`, một số lời gọi có thể kết thúc và trả:

```text
return = -1
errno  = EINTR
```

`EINTR` (`Interrupted system call`) cho biết lời gọi đang chờ đã bị việc xử lý signal làm gián đoạn. Điều này không nhất thiết có nghĩa là file descriptor bị hỏng hay thiết bị gặp lỗi.

Ví dụ:

```text
read()
  |
  | chưa có dữ liệu
  v
BLOCK
  |
  | SIGINT được delivery
  v
handler()
  |
  v
handler return
  |
  v
read() kết thúc
  |
  v
-1, errno = EINTR
```

Khi dùng:

```c
sa.sa_flags = SA_RESTART;
```

Kernel/libc có thể tự động **restart một số interface hỗ trợ restart** sau khi handler kết thúc. Khi đó, ứng dụng có thể không nhìn thấy lỗi `EINTR`.

Ví dụ với `read()` trên một đối tượng phù hợp như terminal:

```text
read()
  |
  | chưa có dữ liệu
  v
BLOCK
  |
  | Signal được delivery
  v
handler()
  |
  v
handler return
  |
  v
SA_RESTART
  |
  v
read() được restart
  |
  v
tiếp tục chờ dữ liệu
```

Có thể ghi nhớ theo mô hình:

```text
           Blocking call
                |
          Signal delivery
                |
                v
           Handler chạy
                |
                v
         Handler kết thúc
                |
                v
       Interface có hỗ trợ
          restart không?
          /           \
        Có             Không
        |                |
        v                v
   Có SA_RESTART?      return -1
     /      \          errno = EINTR
   Có       Không
    |          |
    v          v
 restart    return -1
  call      errno = EINTR
```

> **Quan trọng:** `SA_RESTART` **không có nghĩa là mọi system call đều được tự động restart**. Trên Linux, một số interface như `select()`, `pselect()`, `poll()`, `ppoll()`, `epoll_wait()` và `epoll_pwait()` vẫn có thể trả về `-1` với `errno = EINTR` khi bị signal handler làm gián đoạn.

Điều này đặc biệt hữu ích trong thiết kế event loop:

```text
Main Loop
   |
   v
poll()
   |
   | đang chờ sự kiện
   |
   | SIGTERM được delivery
   v
handler:
    stop = 1
   |
   v
poll() -> -1, EINTR
   |
   v
Main Loop thức dậy
   |
   v
kiểm tra stop
   |
   v
shutdown
```

Trong trường hợp này, `EINTR` không chỉ là một "lỗi" cần retry ngay lập tức. Nó có thể là cơ hội để vòng lặp chính thức dậy, kiểm tra trạng thái ứng dụng và quyết định có tiếp tục chờ hay bắt đầu shutdown.

Ngoài ra, `SA_RESTART` được cấu hình **theo từng signal**, vì nó nằm trong `struct sigaction` tương ứng với signal đó. Ví dụ, handler của `SIGUSR1` có thể dùng `SA_RESTART`, trong khi handler của `SIGTERM` không dùng cờ này để cho phép các blocking call trả về `EINTR` và đánh thức main loop.

Một nuance quan trọng với I/O: nếu một lời gọi như `read()` đã xử lý được một phần dữ liệu trước khi signal tới, nó có thể trả về **số byte đã đọc được** thay vì trả `-1` với `EINTR`.

Vì vậy, code bền vững cần phân biệt:

```text
return > 0     -> đã xử lý được dữ liệu
return == 0    -> EOF (đối với read)
return == -1
    |
    +-- errno == EINTR -> bị signal làm gián đoạn
    |
    +-- lỗi khác       -> xử lý theo lỗi tương ứng
```

> **Kết luận:** `SA_RESTART` giúp che đi một số lần gián đoạn do signal bằng cách tự động tiếp tục những blocking call hỗ trợ restart sau khi handler kết thúc. Tuy nhiên, đây không phải cơ chế restart chung cho mọi system call; với các interface như `select()` hoặc `poll()`, ứng dụng vẫn phải chuẩn bị xử lý `EINTR`.

### 6.3 Cờ `SA_SIGINFO`

Cho phép handler nhận thêm thông tin chi tiết về nguồn gốc của signal (ai gửi, tại sao gửi) thông qua cấu trúc `siginfo_t`.

---

## 7. `signal set` và `sigprocmask()`

Làm sao để thay đổi Signal Mask? Bằng cách dùng tập hợp tín hiệu (`sigset_t`) và áp dụng nó.

### 7.1 Thao tác với `sigset_t`

POSIX cung cấp các hàm chuyên dụng: khởi tạo rỗng (`sigemptyset`), nạp tất cả (`sigfillset`), thêm một signal (`sigaddset`), xóa (`sigdelset`).

### 7.2 Lệnh `sigprocmask()`

Là hàm dùng để kiểm tra và thay đổi `Signal Mask` của luồng hiện tại. `Signal Mask` là tập các signal đang bị block. Khi gọi `sigprocmask()`, tham số `how` xác định cách tập signal mới được áp dụng vào mask hiện tại:

- `SIG_BLOCK`: Thêm các signal trong tập mới vào mask hiện tại. Các signal đã bị block trước đó vẫn được giữ nguyên.
- `SIG_UNBLOCK`: Loại các signal trong tập mới ra khỏi mask hiện tại, tức là cho phép chúng được `delivery` trở lại.
- `SIG_SETMASK`: Thay thế toàn bộ mask hiện tại bằng tập signal mới.

Nếu truyền `oldset` khác `NULL`, Kernel sẽ lưu lại `Signal Mask` cũ vào đó để chương trình có thể khôi phục lại sau này.

*(Lưu ý: Trong ứng dụng đa luồng, nên sử dụng `pthread_sigmask()` thay cho `sigprocmask()`, vì `Signal Mask` là thuộc tính riêng của từng thread.)*

---

## 8. Gửi signal bằng `kill()` và `raise()`

### 8.1 Hàm `kill()`

Cái tên `kill` mang tính lịch sử. Bản chất của lệnh này là: **Gửi một signal tới một tiến trình hoặc nhóm tiến trình**. 
Nó có thể gửi `SIGTERM` để tắt, `SIGCONT` để yêu cầu chạy tiếp, hoặc gửi signal `0` để kiểm tra sự tồn tại/quyền truy cập đối với tiến trình đích.

### 8.2 Ngữ nghĩa của tham số PID trong `kill()`

1. `PID > 0`: Gửi signal tới **đúng một tiến trình** có PID bằng giá trị này.
2. `PID == 0`: Gửi signal tới **tất cả tiến trình trong cùng process group** với tiến trình gọi `kill()`.
3. `PID == -1`: Gửi signal tới **mọi tiến trình mà tiến trình gọi có quyền gửi signal tới**.
4. `PID < -1`: Gửi signal tới **tất cả tiến trình trong process group có PGID bằng giá trị tuyệt đối của PID** (`|PID|`).

### 8.3 Quyền gửi signal

Biết PID của một tiến trình **không có nghĩa là bạn luôn có quyền gửi signal tới tiến trình đó**. Khi `kill()` được gọi, Linux Kernel sẽ kiểm tra **thông tin định danh và quyền của tiến trình gửi** (`credentials`) cùng với các **Linux capabilities** liên quan, rồi mới quyết định signal có được phép gửi tới tiến trình đích hay không.

### 8.4 Hàm `raise(sig)`

Yêu cầu gửi signal tới chính tiến trình hiện tại. Trong chương trình đa luồng (multi-threaded), theo ngữ nghĩa hiện đại, `raise()` nhắm thẳng tới luồng (calling thread) đã gọi nó, không phải gửi cho một luồng ngẫu nhiên trong tiến trình.

---

## 9. `signal handler` chen vào luồng chạy như thế nào?

Handler không phải là một luồng (thread) mới hay một tiến trình con. Nó chạy trên chính luồng đang bị cắt ngang.

### 9.1 Sự chuyển luồng điều khiển (Control Transfer)

```text
[ Luồng chính đang chạy ] 
           |
(Signal Delivery xảy ra)
           |
           v
[ Kernel lưu ngữ cảnh thanh ghi CPU của Luồng chính ]
           |
[ Kernel chuẩn bị Signal Frame trên Stack, đổi con trỏ lệnh ]
           |
           v
[ HÀM HANDLER CHẠY Ở USERSPACE ]
           |
   (Handler kết thúc)
           |
           v
[ Cơ chế sigreturn được kích hoạt ]
           |
[ Khôi phục lại ngữ cảnh thanh ghi cũ ]
           |
           v
[ Luồng chính tiếp tục chạy ]
```

> **Đọc sơ đồ:** Kernel tự cấu trúc lại thanh ghi và ngăn xếp (Stack) của luồng hiện tại để ép nó chuyển sang chạy hàm Handler. Khi hàm Handler kết thúc, nó sử dụng cơ chế `sigreturn` để báo Kernel khôi phục lại hiện trạng cũ. Vì Handler dùng chung không gian với luồng chính, nếu nó làm thay đổi các biến toàn cục không an toàn, luồng chính sẽ bị ảnh hưởng. Ứng dụng không nên tự gọi `sigreturn()`.

---

## 10. Vì sao hàm xử lý signal phải rất hạn chế?

Vì bản chất chen ngang, mã trong handler phải giả định rằng trạng thái chương trình đang dang dở.

### 10.1 Khái niệm `async-signal-safe`

POSIX liệt kê một tập hợp các hàm C được xem là `async-signal-safe` (an toàn khi bị ngắt bất đồng bộ). 
Chỉ những hàm trong danh sách này (như `write()`, `read()`, `_exit()`) mới được phép gọi an toàn từ bên trong Handler.

**Nhiều hàm thư viện C quen thuộc KHÔNG an toàn:**
Bạn KHÔNG ĐƯỢC dùng `printf()`, `malloc()`, `free()` bên trong Handler.

### 10.2 Ví dụ Deadlock nội bộ

```text
[ Luồng chính đang gọi printf("Log...") ]
           |
           |--> printf lấy Khóa (Mutex Lock) nội bộ của thư viện stdio
           |
   (Signal Delivery chen ngang luồng)
           v
[ Chuyển sang chạy Handler ]
           |
           |--> Handler lại gọi printf("Signal received!")
           |
           v
   printf thứ 2 cố gắng lấy Khóa Mutex. 
   Nhưng Khóa đang bị chính Luồng này giữ dở dang ở trên.
           |
           v
[ TIẾN TRÌNH TREO CỨNG (DEADLOCK) ]
```

> **Đọc sơ đồ:** Handler chen ngang ngay lúc chương trình đang giữ một khóa (lock) nội bộ của `libc`. Handler lại gọi hàm yêu cầu chính khóa đó, dẫn đến việc luồng tự chờ chính mình nhả khóa vô thời hạn. Do đó, handler phải giới hạn thao tác vào những API phù hợp với async-signal context.

### 10.3 Thiết kế Handler chuẩn mực

Nguyên tắc tốt: **Handler làm tối thiểu công việc.**

```text
[ Signal Handler ]
      |
      |--> Chỉ gán một biến cờ (Flag) đơn giản, an toàn.
      |
  (Return ngay)
      v
[ Vòng lặp chính (Main Loop) của chương trình ]
      |
      |--> Kiểm tra Flag -> Gọi hàm xử lý logic phức tạp, ghi log.
```

Nhường việc nặng cho luồng chính (Main Loop) tự làm vào thời điểm an toàn giúp giảm rủi ro `async-signal-safety`. (Lưu ý: mô hình flag là pattern tốt, nhưng bản thân việc đồng bộ flag này giữa các luồng khác nhau lại là một vấn đề riêng biệt).

### 10.4 Biến `volatile sig_atomic_t`

Để gán cờ an toàn giữa luồng chính và handler, biến cờ nên được khai báo với kiểu `volatile sig_atomic_t`. 
*   `volatile`: Tránh việc trình biên dịch (Compiler) tối ưu hóa sai lệch.
*   `sig_atomic_t`: Kiểu dữ liệu phù hợp để chia sẻ một giá trị đơn giản giữa code đang chạy bình thường và `signal handler`. Một thao tác đọc hoặc ghi đơn giản trên biến kiểu này sẽ không bị quan sát ở trạng thái “đang thực hiện dở”. Tuy nhiên, điều đó không có nghĩa các phép toán phức hợp như `counter++` đều atomic, và `sig_atomic_t` cũng không phải cơ chế đồng bộ giữa các thread để thay thế `mutex`.

### 10.5 Bảo toàn `errno` trong Handler

Handler có thể làm thay đổi biến `errno` nếu nó gọi các hàm hệ thống. Một handler được viết cẩn thận sẽ lưu lại giá trị `errno` lúc bắt đầu và phục hồi nó trước khi kết thúc để tránh làm hỏng trạng thái của luồng bị gián đoạn.

---

## 11. Signal và `system call`: `EINTR`, `SA_RESTART`

### 11.1 Gián đoạn System call (Mã lỗi `EINTR`)

Khi một luồng đang ngủ chờ trong một System Call bị chặn (ví dụ chờ `read()`). Một Signal được phân phối tới, Kernel đánh thức luồng, bắt nó chạy Handler.

Chạy xong Handler, Kernel đối mặt với System Call đang bị dở dang kia. Tùy thuộc vào cờ `SA_RESTART` và loại API, System call có thể tự động restart, hoặc trả về không gian người dùng với giá trị `-1` và mã lỗi `errno = EINTR` (Interrupted System Call). (Nếu có `partial I/O` xảy ra, hàm có thể trả về số lượng byte đã xử lý thay vì lỗi `EINTR`).

### 11.2 `EINTR` không phải lúc nào cũng là Retry

Một số hàm như `read()`, `poll()` hoặc `wait()` có thể phải **dừng lại để chờ dữ liệu hoặc chờ một sự kiện**.

Trong lúc chương trình đang chờ, nếu một signal được `delivery` và handler chạy, lời gọi đang chờ có thể bị gián đoạn:

```text
read() / poll() / wait()
        |
        v
   Đang chờ...
        |
        | Signal tới
        v
   Handler chạy
        |
        v
Lời gọi bị gián đoạn
        |
        v
return -1
errno = EINTR
```

Khi gặp `EINTR`, chương trình cần quyết định **có còn muốn tiếp tục công việc đang chờ hay không**.

Điểm quan trọng là không nên chia signal thành “đơn giản” hay “nghiêm trọng”, mà phải xem **signal đó có làm thay đổi trạng thái của ứng dụng hay không**:

- Nếu signal chỉ thông báo một sự kiện và ứng dụng vẫn cần tiếp tục chờ dữ liệu hoặc sự kiện, có thể gọi lại (`retry`) hàm đó.
- Nếu signal làm ứng dụng chuyển sang trạng thái chuẩn bị kết thúc, ví dụ handler của `SIGTERM` đặt `stop = 1`, thì không nên retry lời gọi đang chờ. Main loop nên nhận ra trạng thái mới, thoát khỏi vòng chờ, đóng các tài nguyên cần thiết và kết thúc tiến trình một cách có kiểm soát (`graceful shutdown`).

Có thể hình dung:

```text
Signal làm gián đoạn lời gọi đang chờ
                |
                v
             EINTR
                |
                v
Signal có làm ứng dụng đổi trạng thái không?
          /                         \
        Không                        Có
         |                           |
         v                           v
Ứng dụng vẫn cần chờ?       Ví dụ: SIGTERM làm
         |                   stop = 1
         v                           |
       Retry                         v
                              Không retry nữa
                                     |
                                     v
                             Dọn dẹp tài nguyên
                                     |
                                     v
                             Kết thúc tiến trình
```

> **Ghi nhớ:** `EINTR` chỉ cho biết lời gọi đang chờ đã bị signal làm gián đoạn. Nếu ứng dụng vẫn muốn tiếp tục công việc đang chờ thì có thể retry; nếu signal khiến ứng dụng chuyển sang trạng thái kết thúc, như cách thường xử lý `SIGTERM`, thì không nên retry máy móc.

---

## 12. Race condition và `sigsuspend()`

Lập trình với signal thường gặp một race condition điển hình khi chương trình muốn làm theo logic:

```text
Kiểm tra xem signal đã tới chưa
        |
        +-- Đã tới --> tiếp tục xử lý
        |
        +-- Chưa tới --> ngủ để chờ signal
```

Vấn đề nằm ở **khoảng thời gian giữa lúc kiểm tra điều kiện và lúc thực sự đi ngủ**.

### 12.1 Race condition khi dùng `pause()`

Giả sử handler chỉ đặt một biến cờ:

```c
volatile sig_atomic_t received = 0;

void handler(int sig)
{
    received = 1;
}
```

Main loop có thể được viết như sau:

```c
while (!received) {
    pause();
}
```

Thoạt nhìn, logic này có vẻ đúng. Tuy nhiên, signal có thể tới đúng vào khoảng giữa lúc kiểm tra `received` và lúc gọi `pause()`:

```text
received = 0

Main kiểm tra received
        |
        v
    thấy == 0
        |
        |  <-- SIGUSR1 tới đúng lúc này
        |          |
        |          v
        |      Handler chạy
        |      received = 1
        |          |
        |      Handler return
        |
        v
     pause()
        |
        v
Ngủ chờ signal tiếp theo
```

Signal ở đây **không bị mất**: nó đã được `delivery` và handler đã chạy. Vấn đề là chương trình đã **bỏ lỡ thời điểm đánh thức**, vì signal xảy ra trước khi `pause()` bắt đầu ngủ.

Nếu sau đó không còn signal nào khác tới, `pause()` có thể chờ vô thời hạn.

Có thể hình dung race condition này như sau:

```text
Kiểm tra điều kiện
        |
        |  <-- signal có thể chen vào ở đây
        |
      pause()
```

### 12.2 Vì sao phải block signal trước?

Để loại bỏ khe hở trên, chương trình trước tiên phải **block signal mà nó đang chờ**.

Ví dụ đang chờ `SIGUSR1`:

```text
SIGUSR1 bị BLOCK
```

Nếu `SIGUSR1` tới trong lúc đang bị block:

```text
SIGUSR1 tới
    |
    v
Đang bị BLOCK
    |
    v
PENDING
```

Handler chưa chạy ngay. Signal được giữ ở trạng thái `pending`.

Nhờ đó, chương trình có thể an toàn kiểm tra biến `received` mà không sợ handler của `SIGUSR1` chen vào đúng giữa bước kiểm tra.

### 12.3 `sigsuspend()` giải quyết khe hở giữa `unblock` và `sleep`

Sau khi kiểm tra và thấy `received == 0`, chương trình cần:

1. Cho phép `SIGUSR1` được `delivery` trở lại (`unblock`).
2. Đi ngủ để chờ signal.

Nếu tự làm hai bước riêng biệt:

```text
UNBLOCK SIGUSR1
       |
       |  <-- signal có thể tới ở đây
       |
     SLEEP
```

thì race condition lại xuất hiện.

`sigsuspend()` giải quyết chính vấn đề này.

Về mặt ý tưởng, `sigsuspend()` thực hiện:

```text
┌────────────────────────────┐
│       sigsuspend()         │
│                            │
│  1. Tạm thay signal mask   │
│  2. Đi vào trạng thái chờ  │
│                            │
└────────────────────────────┘
```

Hai việc này được thực hiện **nguyên tử đối với việc chờ signal**, nghĩa là không tồn tại khoảng thời gian mà signal đã được unblock nhưng thread vẫn chưa bắt đầu chờ.

Có thể hiểu ngắn gọn:

```text
Cách nguy hiểm:

UNBLOCK
   |
   |  <-- có khe hở
   |
SLEEP


Dùng sigsuspend():

     UNBLOCK + SLEEP
     ───────────────
      một thao tác
```

### 12.4 Nếu signal tới trước hoặc sau `sigsuspend()` thì sao?

Giả sử `SIGUSR1` đang bị block và main vừa kiểm tra thấy:

```text
received == 0
```

#### Trường hợp 1: `SIGUSR1` tới trước khi gọi `sigsuspend()`

Vì signal vẫn đang bị block:

```text
SIGUSR1 tới
    |
    v
PENDING
```

Sau đó main gọi `sigsuspend()` với một mask tạm thời cho phép `SIGUSR1`:

```text
SIGUSR1 đang PENDING
        |
        v
sigsuspend() tạm UNBLOCK SIGUSR1
        |
        v
SIGUSR1 được DELIVERY
        |
        v
Handler chạy
        |
        v
received = 1
```

Signal không bị bỏ lỡ.

#### Trường hợp 2: `SIGUSR1` tới sau khi `sigsuspend()` đã bắt đầu chờ

```text
sigsuspend()
      |
      v
Thread đang chờ
      |
      | SIGUSR1 tới
      v
Signal được DELIVERY
      |
      v
Handler chạy
      |
      v
received = 1
```

Trường hợp này cũng an toàn.

Có thể tổng hợp:

```text
                  SIGUSR1 tới
                       |
             +---------+---------+
             |                   |
        Tới trước              Tới sau
      sigsuspend()           sigsuspend()
             |                   |
             v                   v
          PENDING          Thread đang chờ
             |                   |
             v                   |
       sigsuspend()              |
       tạm unblock               |
             |                   |
             v                   v
          DELIVERY            DELIVERY
             |                   |
             +---------+---------+
                       |
                       v
                    Handler
                       |
                       v
                 received = 1
```

### 12.5 Pattern sử dụng chuẩn

Mô hình tổng quát là:

```text
1. BLOCK signal cần chờ
       |
       v
2. Kiểm tra điều kiện
       |
       v
3. Nếu điều kiện chưa xảy ra:
       |
       v
4. sigsuspend()
   -> tạm dùng mask cho phép signal đó
   -> đồng thời đi ngủ để chờ
       |
       v
5. Signal được delivery
       |
       v
6. Handler cập nhật biến cờ
       |
       v
7. sigsuspend() return
       |
       v
8. Kiểm tra lại điều kiện
```

Ví dụ:

```c
volatile sig_atomic_t received = 0;

void handler(int sig)
{
    received = 1;
}
```

```c
sigset_t block_mask;
sigset_t old_mask;
sigset_t wait_mask;

sigemptyset(&block_mask);
sigaddset(&block_mask, SIGUSR1);

/* Block SIGUSR1 trước */
sigprocmask(SIG_BLOCK, &block_mask, &old_mask);

/* Tạo mask tạm dùng khi chờ */
wait_mask = old_mask;
sigdelset(&wait_mask, SIGUSR1);

/* Chờ đến khi handler xác nhận SIGUSR1 đã tới */
while (!received) {
    sigsuspend(&wait_mask);
}

/* Khôi phục signal mask ban đầu */
sigprocmask(SIG_SETMASK, &old_mask, NULL);
```

Nên dùng `while` thay vì `if`, vì `sigsuspend()` có thể thức dậy bởi một signal khác không phải signal mà chương trình đang chờ. Sau mỗi lần thức dậy, chương trình cần kiểm tra lại điều kiện.

> **Ghi nhớ:** `sigsuspend()` không tự giải quyết race condition nếu dùng một mình. Pattern đúng là **block signal trước khi kiểm tra điều kiện**, sau đó dùng `sigsuspend()` để tạm unblock signal và đi ngủ mà không tạo ra khe hở giữa hai thao tác đó.

---

## 13. Tư duy gỡ lỗi signal

Khi làm việc với Signal, hãy kiểm tra theo chuỗi logic thay vì hoang mang.

### 13.1 “Tại sao Handler không chạy?”

*   Signal có thực sự được phát sinh không? (Do ai gửi, gửi đúng PID không).
*   Luồng hiện tại có đang bật `Signal Mask` chặn nó lại (Pending) không?
*   Cách xử lý (Disposition) có bị thiết lập nhầm thành `SIG_IGN` (Bỏ qua) không?
*   Tiến trình còn sống không?
*   Signal đó là `SIGKILL` hoặc `SIGSTOP` thì không có handler.

### 13.2 “Tại sao gửi nhiều Signal mà Handler chỉ chạy ít hơn?”

Signal tiêu chuẩn (Standard signal) KHÔNG phải là một hàng đợi (Queue).
Nhiều lần phát sinh cùng một standard signal trong lúc nó đang bị block có thể không tạo thành nhiều mục `pending` riêng biệt. Khi Unblock, Handler có thể chỉ chạy 1 lần.

### 13.3 “Đang chạy, thêm Handler vào là Crash/Treo”

Nghi ngờ ngay lập tức: 
*   Bạn đã gọi hàm vi phạm `async-signal-safe` (như `printf`, `malloc`) bên trong Handler?
*   Handler bị deadlock trên một lock nội bộ.

### 13.4 “Lệnh `read()` / `wait()` tự dưng bung lỗi -1”

Kiểm tra ngay `errno` có phải bằng `EINTR` không. Nếu đúng, kiểm tra lại cờ `SA_RESTART` và chính sách shutdown của ứng dụng.

---

## 14. Liên hệ với Embedded Linux

Trong hệ thống nhúng (Embedded Linux), Signal đóng vai trò quan trọng trong việc dừng service, reload cấu hình, và nhận thông báo tiến trình con.

### 14.1 `Graceful shutdown` (Tắt máy có kiểm soát)

Một service khi nhận `SIGTERM` sẽ chuyển trạng thái:
```text
[ RUNNING ] -> Nhận SIGTERM -> Đổi cờ Flag -> Quay lại Main Loop -> [ STOPPING ] -> Dọn dẹp tài nguyên -> [ EXIT ]
```
Signal nên được xem là yêu cầu thay đổi trạng thái ứng dụng, không phải là lệnh ngắt điện lập tức.

### 14.2 Reload cấu hình bằng `SIGHUP`

Một số daemon dùng `SIGHUP` như **quy ước ứng dụng** để reload cấu hình. Tuy nhiên, Linux Kernel không quy định bắt buộc "SIGHUP luôn là reload config".

### 14.3 Quản lý Worker

Một tiến trình giám sát (Supervisor) có thể kết hợp `fork()`, `SIGCHLD` và `waitpid()` để quản lý vòng đời các tiến trình con. Tuy nhiên, thiết kế tốt là để handler chỉ ghi nhận sự kiện (hoặc dùng các cơ chế như `signalfd`), còn vòng lặp chính (main loop) sẽ chịu trách nhiệm gọi `waitpid()` và `fork` lại worker mới. Không nên đặt logic nghiệp vụ phức tạp trực tiếp vào trong Signal Handler.

### 14.4 Bắt bệnh hệ thống (Fault diagnostics)

Các tín hiệu `SIGSEGV`, `SIGBUS`, `SIGILL` là dấu hiệu quan trọng khi debug lỗi ứng dụng trên thiết bị. Mặc dù vậy, tên signal chỉ mô tả lớp sự kiện; để tìm nguyên nhân gốc rễ vẫn cần đến backtrace, thanh ghi, bản đồ bộ nhớ và logs.

---

## 15. Tổng kết

Sơ đồ vòng đời của một Signal:

```text
   [ Sự kiện / Lệnh kill() ]
             |
             v
 [ SIGNAL GENERATED (Phát sinh) ]
             |
             +---------> Bị Mask chặn lại -> [ Trạng thái PENDING ]
             |                                    |
             |                                (Gỡ Mask)
             v                                    |
  [ SIGNAL DELIVERY (Phân phối) ] <---------------+
             |
      (Kiểm tra Disposition)
             |
    +--------+--------+
    |        |        |
    v        v        v
[ Mặc định ] [ Lờ đi ] [ Chạy Hàm Handler ] ---> Rủi ro Async-Safe / Trả về EINTR
```

> **Đọc sơ đồ:** Hành trình diễn giải nguyên lý: Phát sinh (Generation) không có nghĩa là Phân phối ngay (Delivery). Tín hiệu có thể bị giữ ở khâu Pending do `Signal Mask` bảo vệ. Khi lọt qua được và tiến hành Delivery, số phận của tín hiệu mới được phán quyết bởi `Disposition`. Nếu chạy vào Handler, nó tạo ra rủi ro gián đoạn System Call (`EINTR`) và treo hệ thống nếu lập trình viên không hiểu rõ giới hạn `Async-signal-safe`.

**Các nguyên tắc khắc cốt ghi tâm:**
1. Signal mang tính bất đồng bộ, cắt ngang dòng code hiện tại.
2. `Generation` (tạo) khác biệt hoàn toàn với `Delivery` (phân phối).
3. `Disposition` là cách ứng xử; `Mask` là tập các signal đang bị chặn.
4. Block (chặn) giữ signal ở trạng thái chờ; Ignore (lờ đi) sẽ loại bỏ signal.
5. `SIGKILL` và `SIGSTOP` không thể bị bắt hay chặn.
6. `SIGTERM` là yêu cầu kết thúc có thể xử lý; `SIGKILL` là thao tác cưỡng bức của Kernel.
7. Ưu tiên dùng `sigaction()` để cài đặt Handler.
8. Handler chạy chung không gian ngữ cảnh với luồng bị cắt ngang.
9. CHỈ sử dụng các hàm `async-signal-safe` bên trong Handler.
10. Mã lỗi `EINTR` báo hiệu System Call bị Signal làm gián đoạn; cần phân tích ngữ cảnh trước khi gọi lại (retry).
11. Signal tiêu chuẩn ở trạng thái Pending không phải là Message Queue bảo toàn số lượng.

---

## 16. Tài liệu tham khảo

Phần này liệt kê nguồn chuẩn về signal và các API POSIX liên quan.

- `signal(7)`: https://man7.org/linux/man-pages/man7/signal.7.html
- `sigaction(2)`: https://man7.org/linux/man-pages/man2/sigaction.2.html
- `sigprocmask(2)`: https://man7.org/linux/man-pages/man2/sigprocmask.2.html
- `sigpending(2)`: https://man7.org/linux/man-pages/man2/sigpending.2.html
- `kill(2)`: https://man7.org/linux/man-pages/man2/kill.2.html
- `signal-safety(7)`: https://man7.org/linux/man-pages/man7/signal-safety.7.html
- `wait(2)`: https://man7.org/linux/man-pages/man2/wait.2.html
- POSIX.1-2024: https://pubs.opengroup.org/onlinepubs/9799919799/
- The Linux Programming Interface: https://man7.org/tlpi/

> **Điều hướng:** [← Chủ đề 4 — Tiến trình](README-topic-04.md) · [Chủ đề 6 — Đa luồng →](README-topic-06.md)
