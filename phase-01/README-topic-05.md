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
[ Sự kiện phát sinh Signal (Generation) ]
                   |
                   v
          Có thể Delivery ngay?
             /                      Có          Không (Ví dụ đang bị Mask chặn)
           |               |
           |               v
           |           [ PENDING (Nằm chờ) ]
           |               |
           |           (Sau khi gỡ chặn/unblock)
           |               |
           +-------+-------+
                   |
                   v
       [ SIGNAL DELIVERY (Phân phối) ]
                   |
          (Theo cấu hình Disposition)
          /        |                  /         |             [ Bỏ qua ]  [ Handler ]  [ Mặc định ]
```

> **Đọc sơ đồ:** Khi một sự kiện phát sinh (Generated), Kernel kiểm tra xem tiến trình nhận có đang chặn (Block) signal này hay không. Nếu bị chặn, signal sẽ bị giữ lại ở trạng thái `Pending`. Nó chờ ở đó cho tới khi tiến trình gỡ bỏ sự chặn (Unblock), lúc này Kernel mới thực hiện giao hàng (`Delivery`). Sau khi giao, hệ thống áp dụng cách hành xử tương ứng (bỏ qua, chạy Handler, hoặc ngắt chương trình). Đối với các signal được cấu hình là `SIG_IGN` (Ignore), về mặt ngữ nghĩa, signal thường bị loại bỏ (discard) ngay mà không cần chờ đến lúc delivery.
> **Lưu ý:** “Đã gửi signal” không có nghĩa là “Handler bên kia đã chạy ngay lập tức”.

---

## 3. Tiến trình làm gì khi nhận `signal`?

Khoảnh khắc Kernel thực hiện `signal delivery`, số phận tiến trình phụ thuộc vào các thiết lập gọi là `signal disposition` (cách hành xử).

### 3.1 `signal disposition` (Cách hành xử)

Mỗi loại `signal` đều được gán một cách hành xử. Tiến trình có 3 lựa chọn:

### 3.2 Hành động mặc định (Default action)

Nếu bạn không cấu hình gì, Kernel áp dụng luật mặc định:
*   `Terminate`: Kết thúc tiến trình (vd: SIGTERM).
*   `Terminate + Core dump`: Kết thúc tiến trình và ghi trạng thái RAM ra file `core` để debug (vd: SIGSEGV).
*   `Ignore`: Không làm gì (vd: SIGCHLD).
*   `Stop` / `Continue`: Dừng hoặc tiếp tục chạy.

### 3.3 Bỏ qua (Ignore)

Bạn có quyền cấu hình yêu cầu Kernel hoàn toàn lờ đi một signal (bằng cờ `SIG_IGN`). Khi đó, signal không gây ra tác động nào và không có bất kỳ Handler nào được chạy.

### 3.4 Bắt và xử lý bằng `Handler` (Catch)

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
*   `sa_mask`: Tập signal TẠM THỜI bị block trong khoảng thời gian hàm Handler đang chạy, giúp Handler không bị cắt ngang bởi các signal khác. Mặc định, signal đang được xử lý cũng tự động bị block trừ khi bạn dùng cờ `SA_NODEFER`.
*   `sa_flags`: Các cờ tinh chỉnh hành vi đặc biệt.

### 6.2 Cờ `SA_RESTART` (Khởi động lại System Call)

Một interrupted blocking call có thể trả về `-1` với lỗi `EINTR`. Nếu bạn dùng cờ `SA_RESTART` khi cấu hình `sigaction()`, một số syscall (như `read()` trên terminal) có thể được Kernel tự động restart sau khi handler kết thúc. *Lưu ý: `SA_RESTART` không áp dụng cho mọi giao diện (ví dụ các hàm chờ timeout như `select`, `poll` thường không được restart).*

### 6.3 Cờ `SA_SIGINFO`

Cho phép handler nhận thêm thông tin chi tiết về nguồn gốc của signal (ai gửi, tại sao gửi) thông qua cấu trúc `siginfo_t`.

---

## 7. `signal set` và `sigprocmask()`

Làm sao để thay đổi Signal Mask? Bằng cách dùng tập hợp tín hiệu (`sigset_t`) và áp dụng nó.

### 7.1 Thao tác với `sigset_t`

POSIX cung cấp các hàm chuyên dụng: khởi tạo rỗng (`sigemptyset`), nạp tất cả (`sigfillset`), thêm một signal (`sigaddset`), xóa (`sigdelset`).

### 7.2 Lệnh `sigprocmask()`

Là hàm dùng để thay đổi Signal Mask cho luồng hiện tại. Có 3 phép toán logic:
*   `SIG_BLOCK`: Lấy mask đang có, CỘNG thêm tập hợp mới.
*   `SIG_UNBLOCK`: Lấy mask đang có, TRỪ đi tập hợp mới.
*   `SIG_SETMASK`: Thay thế hoàn toàn mask cũ bằng tập hợp mới.

*(Lưu ý: Trong ứng dụng đa luồng, phải dùng hàm `pthread_sigmask()` thay thế).*

---

## 8. Gửi signal bằng `kill()` và `raise()`

### 8.1 Hàm `kill()`

Cái tên `kill` mang tính lịch sử. Bản chất của lệnh này là: **Gửi một signal tới một tiến trình hoặc nhóm tiến trình**. 
Nó có thể gửi `SIGTERM` để tắt, `SIGCONT` để yêu cầu chạy tiếp, hoặc gửi signal `0` để kiểm tra sự tồn tại/quyền truy cập đối với tiến trình đích.

### 8.2 Ngữ nghĩa của tham số PID trong `kill()`

*   `PID > 0`: Gửi signal tới tiến trình có PID đó.
*   `PID == 0`: Gửi signal tới mọi tiến trình trong cùng process group với tiến trình gọi.
*   `PID == -1`: Gửi tới mọi tiến trình mà người dùng có quyền gửi.
*   `PID < -1`: Gửi tới mọi tiến trình trong process group có ID là `|PID|`.

### 8.3 Quyền gửi signal

Có PID không đồng nghĩa bạn được gửi signal. Linux Kernel kiểm tra các quy tắc về `credentials` và `capability` để xem người dùng có đủ quyền tương tác với tiến trình đích hay không.

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
*   `sig_atomic_t`: Đảm bảo loại truy cập đọc/ghi đơn giản có thể thực hiện một cách nguyên tử (atomically) đối với asynchronous signal handling theo chuẩn C. Nó **không** phải là cơ chế đồng bộ tổng quát thay thế cho mutex giữa các luồng.

### 10.5 Bảo toàn `errno` trong Handler

Handler có thể làm thay đổi biến `errno` nếu nó gọi các hàm hệ thống. Một handler được viết cẩn thận sẽ lưu lại giá trị `errno` lúc bắt đầu và phục hồi nó trước khi kết thúc để tránh làm hỏng trạng thái của luồng bị gián đoạn.

---

## 11. Signal và `system call`: `EINTR`, `SA_RESTART`

### 11.1 Gián đoạn System call (Mã lỗi `EINTR`)

Khi một luồng đang ngủ chờ trong một System Call bị chặn (ví dụ chờ `read()`). Một Signal được phân phối tới, Kernel đánh thức luồng, bắt nó chạy Handler.

Chạy xong Handler, Kernel đối mặt với System Call đang bị dở dang kia. Tùy thuộc vào cờ `SA_RESTART` và loại API, System call có thể tự động restart, hoặc trả về không gian người dùng với giá trị `-1` và mã lỗi `errno = EINTR` (Interrupted System Call). (Nếu có `partial I/O` xảy ra, hàm có thể trả về số lượng byte đã xử lý thay vì lỗi `EINTR`).

### 11.2 `EINTR` không phải lúc nào cũng là Retry

Một thói quen dễ gây lỗi là tự động `while(retry)` gọi lại hàm khi gặp `EINTR`. Bạn phải phân tích ngữ cảnh:
*   Signal vừa tới có phải là yêu cầu tắt phần mềm (như `SIGTERM`) không?
*   Đã có `partial I/O` xảy ra chưa?
Retry phải dựa trên semantics của API và trạng thái của ứng dụng, không chỉ dựa trên mã `errno`.

---

## 12. Race condition và `sigsuspend()`

Lập trình với signal thường gặp phải các tình huống tương tranh (race condition) khó phát hiện.

### 12.1 Vấn đề Race Condition với `pause()`

Xem xét kịch bản sau:
```text
[ Luồng chính ]
1. Kiểm tra biến cờ (Condition = False)
      |
      | <--- (Signal đến ngay lúc này!)
      |      Handler chạy, gán Flag = True.
      v
2. Gọi pause() để ngủ chờ Signal
      |
      v
[ Luồng chính ngủ vô thời hạn vì Signal đã bị bỏ lỡ ]
```

Vấn đề ở đây là khoảng thời gian (window) giữa bước kiểm tra cờ và bước gọi `pause()`. Nếu Signal chen vào giữa khoảng này, `pause()` sẽ chờ một tín hiệu không bao giờ đến nữa.

### 12.2 Giải pháp nguyên tử: `sigsuspend()`

`sigsuspend()` giải quyết vấn đề bằng cách cung cấp một cơ chế **thay đổi Signal Mask và đi vào giấc ngủ (sleep) trong cùng một thao tác nguyên tử (atomic)**. Nó đảm bảo không có bất kỳ Signal nào có thể lọt qua khe hở thời gian giữa việc kiểm tra cờ và lúc tiến trình thực sự ngủ.

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
