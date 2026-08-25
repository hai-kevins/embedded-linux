# Chủ đề 5 — Signal trong Linux

> **Mục tiêu:** hiểu `signal` là cơ chế thông báo bất đồng bộ của Unix/Linux, từ lúc signal được tạo (`signal generation`), có thể ở trạng thái `pending`, cho tới lúc xảy ra `signal delivery` và xử lý.
>
> **Quy ước ngôn ngữ:** phần giải thích dùng Tiếng Việt nhưng giữ `signal` bằng tiếng Anh để không nhầm với tín hiệu điện trong Embedded. Các thuật ngữ chuẩn `signal generation`, `pending`, `signal delivery`, `signal disposition`, `signal mask`, `handler`, `async-signal-safe`, cùng tên signal, API, cờ và mã lỗi được giữ nguyên để tra cứu đúng Linux/POSIX.
>
> **Phạm vi:** `signal generation` → `pending` → `signal delivery`, `signal disposition`, `signal mask`, `sigaction()`, `sigprocmask()`, `kill()`, `raise()`, hàm xử lý signal, async-signal-safety, `EINTR`, `SA_RESTART`, các signal quan trọng.
>
> Chương này chỉ có **lý thuyết**, không có bài thực hành.

Signal nên được hiểu là **một cơ chế thông báo do kernel chuyển tới tiến trình hoặc luồng**, chứ không phải một lời gọi hàm bình thường. Khi signal phát sinh, nó có thể ở trạng thái `pending`, bị chặn bởi `signal mask`, bị bỏ qua, thực hiện hành động mặc định hoặc làm chương trình chuyển sang một handler đã đăng ký.

Điểm khó nhất của signal không nằm ở tên `SIGINT` hay `SIGTERM`, mà ở thời điểm `signal delivery` và những giới hạn khi handler chen vào luồng thực thi hiện tại. Vì vậy chương này đi từ vòng đời signal tới `sigaction()`, `signal mask`, `EINTR` và quy tắc async-signal-safe.

Nếu bạn mới bắt đầu, hãy đọc theo thứ tự từ mục lớn tới mục nhỏ và xem sơ đồ trước khi đi vào các chi tiết API. Mỗi sơ đồ chỉ giữ những thành phần cần thiết để tạo mô hình trong đầu; đoạn văn ngay bên dưới sẽ giải thích luồng dữ liệu, trạng thái hoặc quan hệ giữa các object. Sau khi đã hiểu mô hình, hãy quay lại tên API, flag và mã lỗi để gắn chúng vào đúng vị trí thay vì học thuộc rời rạc.

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
- [12. Tư duy gỡ lỗi signal](#12-tư-duy-gỡ-lỗi-signal)
- [13. Liên hệ với Embedded Linux](#13-liên-hệ-với-embedded-linux)
- [14. Tổng kết](#14-tổng-kết)
- [15. Tài liệu tham khảo](#15-tài-liệu-tham-khảo)

---

## 1. `signal` là gì?

`signal` là một thông báo bất đồng bộ mà Linux kernel hoặc tiến trình khác gửi tới tiến trình để báo một sự kiện như yêu cầu kết thúc, lỗi hay timer hết hạn.

### 1.1 `signal` không phải lời gọi hàm thông thường

Lời gọi hàm thông thường:

```text
code A
  |
gọi hàm
  |
hàm chạy
  |
trả về
  |
code A tiếp tục
```

Ở lời gọi hàm bình thường, control flow là **đồng bộ và explicit**: code hiện tại chủ động gọi hàm, biết vị trí quay về và tiếp tục ngay sau lời gọi. Signal khác ở chỗ handler có thể được kernel sắp xếp chạy tại một điểm delivery phù hợp mà code đang chạy không thực hiện một lời gọi hàm tới handler ngay trước đó. Sự khác biệt này là nguồn gốc của các quy tắc về signal mask và async-signal-safety.

Với `signal`:

```text
code đang chạy
    |
    | sự kiện xảy ra bất kỳ lúc thích hợp
    v
Linux kernel chuẩn bị signal delivery
    |
    v
signal handler / default action
    |
    v
có thể quay lại mã đang chạy trước đó hoặc thay đổi trạng thái tiến trình
```

Điểm khác biệt lớn là **thời điểm `signal delivery` xảy ra không nhất thiết do code hiện tại gọi trực tiếp**.

### 1.2 Nguồn tạo signal

`signal` có thể phát sinh do:

```text
một tiến trình gọi kill()
terminal tạo SIGINT/SIGTSTP
tiến trình con thay đổi trạng thái -> SIGCHLD
pipe/socket bị đóng -> SIGPIPE
CPU/memory fault -> SIGSEGV / SIGILL / SIGFPE ...
Linux kernel / subsystem tạo signal
```

Các mũi tên nhấn mạnh signal là **cơ chế thông báo chung** được tạo từ nhiều nguồn: process khác, terminal, kernel hoặc kết quả của một thao tác I/O. Điều đó giải thích vì sao không nên đồng nhất signal với `kill()`: `kill()` chỉ là một API có thể yêu cầu tạo signal, còn rất nhiều signal phát sinh mà không có process nào gọi `kill()` trực tiếp.

### 1.3 “Bất đồng bộ” không phải lúc nào cũng có nghĩa ngẫu nhiên

Một số signal gắn chặt với instruction đang thực thi, ví dụ fault như `SIGSEGV`.

Một số signal đến từ sự kiện bên ngoài luồng thực thi hiện tại, như `SIGTERM` do tiến trình khác gửi.

Do đó nên phân biệt lỗi đồng bộ phát sinh từ chính luồng thực thi hiện tại với thông báo bất đồng bộ đến từ bên ngoài. Cả hai trường hợp đều có thể được biểu diễn qua cơ chế `signal`, nhưng nguyên nhân và cách suy luận khác nhau.

---

## 2. Vòng đời của một `signal`

Một `signal` đi qua các bước: `signal generation`, có thể ở trạng thái `pending` nếu đang bị block, sau đó `signal delivery` xảy ra để hệ thống áp dụng cách xử lý tương ứng.

Ba khái niệm nền tảng:

```text
signal generation
      |
      v
   pending
      |
      v
signal delivery
```

Trong tài liệu này, cần tách ba khái niệm: **generation**, **pending** và **delivery**. Một signal được generated không có nghĩa nó bắt buộc phải nằm ở trạng thái pending. Nếu signal có thể được delivery ngay, kernel có thể xử lý delivery trực tiếp; trạng thái pending đặc biệt quan trọng khi signal chưa thể được delivery, chẳng hạn vì signal đó đang bị block bởi `signal mask`.

```text
signal generation
       |
       v
deliverable now?
   /         \
 yes          no
  |            |
  v            v
delivery      pending
                 |
              unblock / eligible
                 |
                 v
              delivery
```

Nhìn sơ đồ từ trên xuống: một sự kiện trước hết **generate** signal. Kernel sau đó xét signal có thể được delivery tới thread/process đích ngay hay không. Nếu có, nó đi thẳng tới delivery. Nếu chưa, signal được giữ ở trạng thái `pending`; khi điều kiện cản trở biến mất, ví dụ thread bỏ block signal tương ứng, signal mới trở thành deliverable. Mô hình này giúp tránh nhầm lẫn phổ biến rằng “gửi signal” đồng nghĩa với “handler chạy ngay”.

### 2.1 `signal generation`

`signal generation` xảy ra khi một sự kiện/API tạo ra nó cho đối tượng đích.

### 2.2 `pending`

Nếu `signal delivery` chưa thể xảy ra ngay, nó có thể ở trạng thái đang chờ.

Một lý do quan trọng:

```text
signal đang bị chặn bởi `signal mask`
```

### 2.3 `signal delivery`

Khi signal đủ điều kiện được delivery, Linux kernel áp dụng cách xử lý tương ứng: `ignore`, `handler` và hành động mặc định.

### 2.4 Sơ đồ trạng thái

```mermaid
flowchart TD
    Start([Signal generated]) --> Generated["Generated"]
    Generated --> Ready{"Deliverable now?"}
    Ready -->|No| Pending["Pending"]
    Pending -->|unblock / eligible| Delivery["Delivery"]
    Ready -->|Yes| Delivery
    Delivery --> Disposition{"Disposition"}
    Disposition -->|ignore| Ignored["Ignored"]
    Disposition -->|handler| Handler["Handler"]
    Disposition -->|default| DefaultAction["Default action"]
    Handler --> Resume["Resume"]
    Resume --> End((End))
    Ignored --> End
    DefaultAction --> End
```

Sơ đồ tách ba thời điểm thường bị người mới gộp thành một: **signal được generated**, **signal có thể pending**, và **signal được delivered**. Khi một signal được tạo, kernel trước hết xác định nó có đủ điều kiện delivery tới thread/process đích hay không. Nếu signal đang bị block thì nó có thể nằm ở trạng thái `Pending`; khi được unblock và trở nên deliverable, kernel mới áp dụng disposition tương ứng: bỏ qua, chạy handler hoặc thực hiện default action. Vì vậy “đã gửi signal” không đồng nghĩa “handler đã chạy ngay lập tức”.

---

## 3. Tiến trình làm gì khi nhận `signal`?

Khi `signal delivery` xảy ra, tiến trình có thể dùng hành vi mặc định, bỏ qua hoặc chạy handler nếu signal cho phép cấu hình.

### 3.1 `signal disposition`

Mỗi `signal` có một **cách xử lý** (`disposition`).

Ba hướng chính: hành động mặc định, bỏ qua và chạy handler do ứng dụng cài.

### 3.2 `default action`

Tùy `signal`, `default action` có thể là: `terminate`, `terminate` + `core dump`, `ignore`, `stop` và `continue`.

Không phải mọi signal mặc định đều “kết thúc tiến trình”.

### 3.3 `ignore`

Ứng dụng có thể chọn bỏ qua một số `signal`.

Khi `signal disposition` là `ignore`, signal không làm handler chạy.

### 3.4 Xử lý bằng `handler`

Ứng dụng cài hàm xử lý cho một signal có thể bắt (`catch`).

Khi `signal delivery` xảy ra:

```text
Linux kernel tạm chuyển control flow
      |
      v
signal handler
      |
      v
sigreturn mechanism
      |
      v
mã bị gián đoạn tiếp tục
```

nếu signal/disposition không làm tiến trình kết thúc hoặc dừng.

### 3.5 `SIGKILL` và `SIGSTOP`

Hai signal này đặc biệt: không thể `catch`, `ignore` hoặc `block`.

Chúng dành cho cơ chế điều khiển bắt buộc của Linux kernel.

---

## 4. Các signal thường gặp

Bạn không cần nhớ tất cả signal. Hãy hiểu trước vài signal thường gặp như `SIGINT`, `SIGTERM`, `SIGKILL`, `SIGSEGV`, `SIGCHLD`.

### 4.1 Không `hard-code` số signal

Ứng dụng nên dùng các tên chuẩn như `SIGINT`, `SIGTERM` và `SIGKILL` thay vì `hard-code` một số signal cố định cho mọi kiến trúc.

### 4.2 `SIGINT`

Thường gắn với yêu cầu interrupt từ terminal, ví dụ `Ctrl+C` gửi tới `foreground process group`.

Ý nghĩa thực tế phụ thuộc ngữ cảnh terminal/`job control`.

### 4.3 `SIGTERM`

Là yêu cầu kết thúc có thể được ứng dụng bắt và xử lý.

Nó phù hợp với `graceful shutdown` của service vì chương trình có cơ hội: dừng nhận việc mới, flush dữ liệu/trạng thái cần thiết, đóng tài nguyên và thoát có kiểm soát.

### 4.4 `SIGKILL`

Linux kernel buộc tiến trình kết thúc; ứng dụng không có cơ hội chạy signal handler để thực hiện cleanup.

Vì vậy `SIGKILL` không phải lựa chọn đầu tiên cho quy trình shutdown bình thường.

### 4.5 `SIGCHLD`

`signal generation` liên quan tới việc tiến trình con thay đổi trạng thái.

Nó nối trực tiếp Topic 4:

```text
tiến trình con exit
   |
SIGCHLD
   |
tiến trình cha biết trạng thái đã thay đổi
   |
wait()/waitpid()
```

`SIGCHLD` là thông báo; `wait()` mới là cơ chế thu trạng thái và thu hồi (`reap`) tiến trình con.

### 4.6 `SIGPIPE`

Khi ghi vào pipe/socket stream khi không còn `reader` theo điều kiện tương ứng:

```text
SIGPIPE
```

có thể được tạo (`generated`).

Nếu signal không làm tiến trình terminate, thao tác ghi thường báo `EPIPE`.

### 4.7 `SIGSEGV`

Thường liên quan truy cập bộ nhớ không hợp lệ theo quy tắc bảo vệ bộ nhớ hoặc `memory mapping`.

### 4.8 `SIGBUS`

Có thể liên quan lỗi bus, alignment hoặc backing store của mapping không hợp lệ tùy kiến trúc/trường hợp.

### 4.9 `SIGILL`

Liên quan instruction không hợp lệ/không được hỗ trợ.

### 4.10 `SIGFPE`

Liên quan lớp `arithmetic exception`; tên lịch sử không có nghĩa nó chỉ dành cho floating-point.

---

## 5. `disposition`, `signal mask` và trạng thái `pending`

`signal mask` quyết định signal nào tạm thời bị chặn; đang chờ nghĩa là signal đã tới nhưng chưa được giao xử lý.

Ba trạng thái dễ nhầm:

`disposition` cho biết tiến trình sẽ xử lý signal như thế nào khi signal được phân phối; `signal mask` cho biết signal nào đang bị chặn; trạng thái **pending** cho biết signal nào đã phát sinh nhưng chưa xảy ra `signal delivery`.

### 5.1 `signal disposition` có phạm vi toàn tiến trình

Trong mô hình POSIX Threads, signal disposition được chia sẻ ở mức tiến trình.

Nếu một luồng thay handler của `SIGTERM`, nó thay disposition của toàn tiến trình.

### 5.2 `signal mask`

`signal mask` là `signal set` đang bị chặn đối với luồng hiện tại.

```text
SIGUSR1 blocked
    |
signal generated
    |
    v
pending
    |
unblock
    |
    v
signal delivery
```

Khi một signal bị block, mask không làm signal “biến mất”. Nếu signal được tạo trong thời gian đó, nó có thể trở thành pending và chờ tới khi thread/process cho phép delivery. Đây là khác biệt quan trọng giữa **block** và **ignore**: block trì hoãn delivery, còn ignore là một disposition nói rằng khi signal được xử lý theo disposition đó thì không cần chạy handler/default action tương ứng.

### 5.3 `signal mask` là riêng từng thread

Trong tiến trình đa luồng, mỗi luồng có signal mask riêng.

Topic 6 sẽ giải thích luồng sâu hơn.

### 5.4 `block` không đồng nghĩa `ignore`

`blocked`: giữ signal ở đang chờ cho tới khi đủ điều kiện để `signal delivery` xảy ra; `ignored`: disposition yêu cầu bỏ qua signal.

Hai cơ chế có ý nghĩa khác nhau.

---

## 6. `sigaction()`: cấu hình `signal disposition`

`sigaction()` là API chuẩn để cấu hình handler và các cờ liên quan. Nó rõ ràng và kiểm soát tốt hơn cách dùng `signal()` cũ.

### 6.1 Vì sao ưu tiên `sigaction()`?

`signal()` có lịch sử ngữ nghĩa khác nhau giữa các hệ thống cũ.

`sigaction()` là giao diện chuẩn và rõ ràng hơn để cấu hình: `handler`, tập signal block trong handler và flags.

### 6.2 `struct sigaction`

Các trường quan trọng về mặt khái niệm:

```text
sa_handler / sa_sigaction
sa_mask
sa_flags
```

### 6.3 `sa_handler`

Có thể chỉ: hàm handler, `SIG_DFL` và `SIG_IGN`.

### 6.4 `sa_mask`

Khi handler chạy, có thể tạm block thêm các signal chỉ định.

Theo mặc định, signal đang được xử lý cũng thường bị block trong chính handler của nó trừ khi dùng flag thay đổi ngữ nghĩa như `SA_NODEFER`.

### 6.5 `SA_RESTART`

`SA_RESTART` yêu cầu hệ thống tự khởi động lại một số `system call` khi chúng bị signal làm gián đoạn. Việc restart cụ thể phụ thuộc lời gọi và ngữ nghĩa của hệ thống.

Điểm cần nhớ:

> `SA_RESTART` không áp dụng cho mọi giao diện và mọi trường hợp.

### 6.6 `SA_SIGINFO`

Cho handler dạng mở rộng nhận thêm thông tin về nguồn signal/ngữ cảnh khi API cung cấp.

Chi tiết trường nào hợp lệ phụ thuộc loại signal và nguồn phát sinh.

---

## 7. `signal set` và `sigprocmask()`

`sigprocmask()` thay đổi tập signal đang bị chặn của tiến trình/luồng theo quy tắc POSIX tương ứng.

### 7.1 `sigset_t`

POSIX dùng `sigset_t` để biểu diễn tập signal.

Các API tập hợp cho phép: khởi tạo tập rỗng, khởi tạo tập đầy, thêm signal, xóa signal và kiểm tra một signal có thuộc tập hay không.

### 7.2 `sigprocmask()`

Trong tiến trình đơn luồng, API này thay signal mask.

Ba thao tác logic:

`SIG_BLOCK`: thêm signal vào mask; `SIG_UNBLOCK`: bỏ signal khỏi mask; `SIG_SETMASK`: thay mask bằng tập mới.

Trong chương trình đa luồng nên dùng API dành cho thread phù hợp như `pthread_sigmask()`.

### 7.3 `sigpending()`

`sigpending()` cho phép lấy tập signal đang ở trạng thái `pending` đối với ngữ cảnh gọi theo ngữ nghĩa POSIX.

Tập signal `pending` không phải một hàng đợi thông điệp tổng quát.

---

## 8. Gửi signal bằng `kill()` và `raise()`

`kill()` gửi signal tới tiến trình hoặc nhóm tiến trình; `raise()` gửi signal cho chính tiến trình hiện tại.

### 8.1 `kill()` không có nghĩa chỉ là “kết thúc tiến trình”

Tên lịch sử dễ gây hiểu nhầm.

`kill()` có nghĩa rộng hơn:

```text
gửi signal tới một tiến trình hoặc process group tùy giá trị PID
```

Signal được gửi có thể là:

```text
SIGTERM
SIGUSR1
SIGCONT
signal 0 để kiểm tra sự tồn tại/quyền truy cập theo ngữ nghĩa của `kill()`
```

### 8.2 Ý nghĩa của tham số PID

Ở mức khái niệm, `kill()` có thể nhắm: một PID cụ thể, process group của tiến trình gọi, một process group cụ thể hoặc một tập tiến trình theo các giá trị PID đặc biệt.

Cần đọc `kill(2)` khi dùng các giá trị đặc biệt.

### 8.3 Quyền gửi signal

Linux kernel kiểm tra các quy tắc về `credentials`, `capability` và `session` phù hợp.

Có PID đúng không đồng nghĩa tiến trình gọi có quyền gửi mọi signal.

### 8.4 `raise()`

`raise(sig)` yêu cầu gửi signal tới chính ngữ cảnh thực thi của chương trình theo POSIX ngữ nghĩa.

Nó hữu ích để kích hoạt luồng xử lý signal từ chính ứng dụng.

---

## 9. `signal handler` chen vào luồng chạy như thế nào?

Handler có thể chen vào lúc chương trình đang chạy một đoạn code khác, vì vậy mã trong handler phải giả định rằng trạng thái chương trình đang dang dở.

### 9.1 Chuyển luồng điều khiển (`control transfer`) do kernel sắp xếp

Khi delivery tới một luồng:

```text
thread đang chạy
    |
Linux kernel lưu ngữ cảnh thực thi cần thiết
    |
tạo signal frame và chuẩn bị user-space context
    |
    v
handler chạy
    |
handler kết thúc
    |
sigreturn mechanism
    |
    v
thread tiếp tục
```

Sơ đồ cho thấy signal handler **chen vào execution context của thread nhận signal**, chứ kernel không tạo một worker thread riêng để chạy handler. Kernel chuẩn bị context để userspace chuyển sang hàm handler; khi handler kết thúc bình thường, cơ chế `sigreturn` khôi phục ngữ cảnh thích hợp để thread có thể tiếp tục. Vì handler có thể xuất hiện giữa lúc code bình thường đang cập nhật state, nó phải được thiết kế với các ràng buộc async-signal-safety.

Ứng dụng không nên tự gọi `sigreturn()`.

### 9.2 `handler` không phải một thread riêng

Handler chạy trong ngữ cảnh của luồng nhận signal.

Nó dùng stack và trạng thái thanh ghi CPU của luồng theo signal-frame ngữ nghĩa.

### 9.3 `reentrancy`

Nếu các signal khác vẫn đủ điều kiện để `signal delivery` xảy ra trong khi handler chạy, handler có thể bị lồng bởi signal khác.

Đây là lý do mã trong handler phải cực kỳ cẩn trọng.

---

## 10. Vì sao hàm xử lý signal phải rất hạn chế?

Không phải hàm nào cũng an toàn khi gọi trong hàm xử lý signal. Vì vậy handler nên làm rất ít việc và chuyển xử lý phức tạp ra luồng bình thường.

### 10.1 `async-signal-safe`

POSIX định nghĩa một tập hàm `async-signal-safe`, tức là có thể gọi an toàn từ signal handler trong các điều kiện mà chuẩn quy định.

Nhiều hàm thư viện **không** async-signal-safe.

Các hàm như `malloc()` hoặc `stdio` có thể đang giữ trạng thái nội bộ hay mutex đúng lúc signal handler chen vào. Nếu handler gọi lại một hàm không async-signal-safe, nó có thể đụng vào trạng thái đang dở dang và gây deadlock hoặc lỗi khó đoán.

### 10.2 Ví dụ deadlock nội bộ

```text
normal execution
   |
libc function đang giữ internal mutex
   |
signal delivery
   |
handler gọi lại hàm cần cùng mutex
   |
   v
deadlock
```

Tình huống này cho thấy handler có thể xen vào đúng lúc code bình thường đang giữ một internal lock của libc. Nếu handler gọi lại một hàm không async-signal-safe và hàm đó cần cùng lock, thread có thể tự chờ chính mình vô thời hạn. Do đó nguyên tắc an toàn không phải “handler ngắn là đủ”; handler còn phải giới hạn thao tác vào những API và kiểu dữ liệu phù hợp với async-signal context.

### 10.3 Thiết kế handler

Nguyên tắc tốt:

```text
handler làm tối thiểu
  |
  +--> set một flag đơn giản, an toàn
  +--> ghi qua API async-signal-safe phù hợp
  |
main loop / worker thread xử lý logic phức tạp
```

Mô hình an toàn là để handler chỉ **ghi nhận sự kiện** bằng một cơ chế tối thiểu, sau đó để main loop hoặc thread bình thường làm công việc phức tạp. Như vậy parsing, logging, cấp phát bộ nhớ, khóa mutex hay shutdown nhiều bước đều diễn ra ngoài signal context. Cách tách này vừa giảm rủi ro async-signal-safety vừa làm luồng điều khiển của chương trình dễ kiểm chứng hơn.

### 10.4 `volatile sig_atomic_t`

Kiểu `sig_atomic_t` cho phép một số thao tác đọc/ghi đơn giản phù hợp giữa mã thực thi bình thường và hàm xử lý signal theo quy tắc của C/POSIX.

Nó **không** thay thế mutex/cơ chế đồng bộ atomic giữa nhiều luồng cho mọi bài toán.

### 10.5 `errno`

Handler có thể làm thay đổi `errno` nếu gọi hàm tác động tới nó.

Một handler cần bảo toàn `errno` nếu chương trình bị gián đoạn cần giá trị cũ sau khi handler kết thúc.

---

## 11. Signal và `system call`: `EINTR`, `SA_RESTART`

Signal có thể làm `system call` đang chờ bị gián đoạn và trả `EINTR`; một số trường hợp `SA_RESTART` khiến Linux kernel/libc tự khởi động lại lời gọi.

### 11.1 Signal có thể làm gián đoạn `system call` đang blocking

Ví dụ:

```text
thread đang read()
     |
signal delivery
     |
handler chạy
     |
     v
system call được restart hoặc trả EINTR tùy API, flags và trạng thái
```

Nếu thread đang ngủ trong một blocking system call khi signal được delivered, kernel phải quyết định điều gì xảy ra với lời gọi đang chờ. Với một số API và cấu hình, lời gọi có thể được restart; ở trường hợp khác nó trở về userspace với `-1` và `errno == EINTR`. Nếu đã có partial I/O, giá trị trả về còn có thể là số byte đã xử lý. Vì vậy code đúng phải đọc semantics của từng API thay vì áp dụng một quy tắc retry chung cho mọi system call.

### 11.2 `EINTR`

`EINTR` nghĩa lời gọi bị gián đoạn bởi signal trước khi hoàn tất theo ngữ nghĩa của API.

Không nên mặc định:

```text
EINTR -> retry vô điều kiện (không phải lúc nào cũng đúng)
```

Sơ đồ phủ định một thói quen dễ gây lỗi: nhận `EINTR` rồi lặp lại system call mà không xem operation đang ở trạng thái nào. Một số API có thể đã xử lý một phần dữ liệu, deadline có thể đã thay đổi, hoặc signal vừa yêu cầu application chuyển sang shutdown. Vì vậy retry phải dựa trên **semantics của API và state của ứng dụng**, không chỉ dựa trên mã `errno`.

Hãy xét:

```text
ứng dụng có đang yêu cầu shutdown không?
đã có partial I/O chưa?
deadline đã hết chưa?
handler có thay trạng thái điều khiển không?
```

### 11.3 `SA_RESTART`

Một số giao diện blocking có thể tự restart nếu `signal disposition` dùng `SA_RESTART`.

Nhưng danh sách phụ thuộc giao diện và Linux/POSIX ngữ nghĩa.

### 11.4 `partial I/O`

Nếu một lời gọi đã truyền được một phần dữ liệu trước khi signal đến, nó có thể trả số byte đã xử lý thay vì `EINTR`.

Do đó Topic 3 và Topic 5 liên kết trực tiếp:

```text
signal interruption
+
partial I/O
+
giá trị trả về
```

---

## 12. Tư duy gỡ lỗi signal

Debug signal cần hỏi: signal nào được gửi, có bị block không, disposition là gì, handler có chạy không và `system call` có bị `EINTR` không.

### 12.1 “Handler không chạy”

Kiểm tra:

```text
signal có thực sự phát sinh?
đúng process/thread đích?
bị block?
disposition đúng?
tiến trình còn sống?
SIGKILL/SIGSTOP thì không có handler
```

### 12.2 “Gửi nhiều lần nhưng handler chạy ít hơn”

Standard signal không phải một hàng đợi đếm và bảo toàn từng lần phát sinh.

Nhiều lần phát sinh cùng một standard signal có thể không tạo thành nhiều mục `pending` riêng biệt.

### 12.3 “Chương trình treo sau khi thêm handler”

Nghi ngờ: handler gọi hàm không async-signal-safe, handler bị deadlock trên lock nội bộ và handler thực hiện logic quá lớn.

### 12.4 “`read()` đột nhiên trả -1”

Kiểm tra:

```text
errno == EINTR?
SA_RESTART?
chính sách shutdown?
```

### 12.5 “SIGTERM không dừng tiến trình”

`SIGTERM` có thể bị: caught, ignored và blocked tạm thời.

Không có ngữ nghĩa cưỡng bức giống `SIGKILL`.

### 12.6 “SIGKILL không biến mất ngay”

Nếu task đang ở trạng thái của Linux kernel đặc biệt như uninterruptible sleep, delivery/termination observable có thể chờ tới khi task thoát khỏi trạng thái đó.

Điều này không có nghĩa `SIGKILL` bị catch/ignore.

---

## 13. Liên hệ với Embedded Linux

Embedded Linux dùng signal để dừng service, reload cấu hình, nhận thông báo tiến trình con và xử lý timer/sự kiện hệ thống.

### 13.1 `graceful shutdown` của service

Service nhận `SIGTERM` có thể chuyển trạng thái:

```text
RUNNING
   |
SIGTERM
   |
   v
STOPPING
   |
controlled cleanup
   |
   v
EXIT
```

Signal như `SIGTERM` nên được xem là **yêu cầu thay đổi trạng thái ứng dụng**, không nhất thiết là lệnh “thoát ngay trong handler”. Handler có thể đặt cờ hoặc đánh thức event loop; main flow sau đó ngừng nhận công việc mới, hoàn tất hoặc hủy công việc đang chạy theo policy, đóng fd và giải phóng tài nguyên. Nhờ vậy shutdown vẫn tuân theo lifetime bình thường của chương trình.

### 13.2 Reload cấu hình

Một số daemon dùng `SIGHUP` như **quy ước ứng dụng** để reload configuration.

Linux kernel không quy định universal meaning “SIGHUP luôn là reload config”.

### 13.3 Tiến trình con/worker

Một supervisor có thể kết hợp `fork()`, `SIGCHLD` và `waitpid()` để quản lý vòng đời các tiến trình con.

### 13.4 UART/TTY

`Ctrl+C` qua serial terminal có thể tạo `SIGINT` tới foreground tiến trình group nếu TTY được cấu hình theo canonical/job-control ngữ nghĩa.

### 13.5 Pipe/socket

Một stream bị đóng/hỏng có thể gây `SIGPIPE`, vì vậy mã mạng/service cần chính sách xử lý rõ ràng.

### 13.6 Chẩn đoán lỗi (`fault diagnostics`)

`SIGSEGV`, `SIGBUS`, `SIGILL` là dấu hiệu quan trọng khi debug crash trên thiết bị đích.

Tuy nhiên signal name chỉ mô tả lớp sự kiện; root cause vẫn cần backtrace, register, memory ánh xạ, logs và subsystem ngữ cảnh.

---

## 14. Tổng kết

Topic 05 cần để lại mô hình: `signal generation` → `pending`/blocked → `signal delivery` → mặc định/ignore/handler.

```text
Event / API
    |
    v
signal generated
    |
    +--> blocked -> pending
    |                 |
    |               unblock
    |                 |
    +-----------------+
    |
    v
signal delivery
    |
    +--> default action
    +--> ignored
    +--> signal handler
```

Bản đồ này nhắc lại rằng **generation không phải delivery**. Một event hoặc API làm signal được generated; nếu signal chưa thể được delivered, ví dụ do mask đang block nó, signal có thể ở trạng thái pending. Khi đủ điều kiện delivery, kernel áp dụng disposition hiện tại: default action, ignore hoặc chạy handler. Với handler, control flow chen vào thread nhận signal nên code handler phải tuân theo async-signal-safety. Từ đây có thể hiểu tự nhiên các hiện tượng như signal bị chậm, `EINTR`, `SA_RESTART` và việc standard signal pending không hoạt động như message queue.

Các ý cần nhớ:

1. Signal là cơ chế thông báo/control, không phải lời gọi hàm thông thường.
2. Phải tách `generation`, `pending`, `delivery`.
3. Disposition quyết định hành động khi delivery.
4. Mask quyết định signal nào đang bị block.
5. Block khác ignore.
6. `SIGKILL` và `SIGSTOP` không thể catch/block/ignore.
7. `SIGTERM` là yêu cầu terminate có thể xử lý; `SIGKILL` là cưỡng bức Linux kernel-level.
8. `SIGCHLD` là notification; `wait()` thu trạng thái child.
9. `sigaction()` là giao diện chuẩn để cấu hình handler/flags/mask.
10. Handler chạy trong luồng ngữ cảnh nhận signal, không phải luồng riêng.
11. Chỉ gọi các thao tác `async-signal-safe` từ signal handler.
12. Signal có thể làm syscall trả `EINTR`; `SA_RESTART` không áp dụng cho mọi syscall.
13. Signal chuẩn ở trạng thái pending không phải một hàng đợi thông điệp bảo toàn mọi lần phát sinh.

---

## 15. Tài liệu tham khảo

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
