# Chủ đề 8 — Giao tiếp liên tiến trình (IPC) trong Linux

> **Mục tiêu:** Hiểu vì sao các tiến trình cần IPC, phân biệt rõ các cơ chế `pipe`, `FIFO`, `POSIX Message Queue` và `POSIX Shared Memory` dựa trên mô hình dữ liệu, cách định danh, vòng đời và trách nhiệm đồng bộ hóa.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Giữ nguyên tên cơ chế và thuật ngữ chuẩn như `IPC`, `Pipe`, `FIFO`, `POSIX Message Queue`, `POSIX Shared Memory`, `byte stream`, `message boundary`, `framing`, `backpressure`, `mapping`, `kernel persistence`, cùng tên API, kiểu dữ liệu, cờ và mã lỗi để đối chiếu với tài liệu Linux/POSIX.
>
> **Phạm vi:** Khái niệm IPC cơ bản, unnamed pipe, FIFO, POSIX Message Queue, POSIX Shared Memory, kỹ thuật `mmap`, sử dụng semaphore để đồng bộ memory, hành vi `blocking`, khái niệm `backpressure` và tiêu chí lựa chọn cơ chế IPC.
>
> Chương này là **lý thuyết nền tảng** chuẩn bị cho kiến trúc đa tiến trình, không có bài thực hành. (Unix Domain Socket sẽ thuộc **Chủ đề 9 — Socket Programming**).

Các tiến trình bình thường có không gian bộ nhớ ảo hoàn toàn cách ly, do đó một tiến trình không thể trực tiếp đọc/ghi biến của tiến trình khác. Giao tiếp liên tiến trình (Inter-Process Communication - IPC) là việc hệ điều hành tạo ra **một kênh truyền tải hoặc một đối tượng dùng chung** để hai bên có thể phối hợp hoạt động.

Điều cốt lõi trong IPC không phải là học thuộc các hàm gọi, mà là hiểu **mô hình dữ liệu** của từng cơ chế: `Pipe/FIFO` cung cấp `byte stream`, `POSIX Message Queue` duy trì ranh giới từng thông điệp (`discrete messages`), còn `Shared Memory` cho phép nhiều tiến trình cùng ánh xạ một vùng nhớ.

---

## Mục lục

- [1. IPC là gì?](#1-ipc-là-gì)
- [2. Trước khi chọn IPC cần hỏi những gì?](#2-trước-khi-chọn-ipc-cần-hỏi-những-gì)
- [3. Unnamed Pipe: `byte stream` giữa các tiến trình](#3-unnamed-pipe-byte-stream-giữa-các-tiến-trình)
- [4. Ngữ nghĩa I/O, EOF, `SIGPIPE` và `PIPE_BUF` của Pipe](#4-ngữ-nghĩa-io-eof-sigpipe-và-pipe_buf-của-pipe)
- [5. FIFO: Pipe có tên trong hệ thống tệp](#5-fifo-pipe-có-tên-trong-hệ-thống-tệp)
- [6. POSIX Message Queue: gửi từng thông điệp riêng](#6-posix-message-queue-gửi-từng-thông-điệp-riêng)
- [7. POSIX Shared Memory: cùng nhìn một vùng nhớ](#7-posix-shared-memory-cùng-nhìn-một-vùng-nhớ)
- [8. Vì sao Shared Memory cần đồng bộ?](#8-vì-sao-shared-memory-cần-đồng-bộ)
- [9. Hành vi chặn, `backpressure` và giới hạn tài nguyên](#9-hành-vi-chặn-backpressure-và-giới-hạn-tài-nguyên)
- [10. So sánh và lựa chọn cơ chế IPC](#10-so-sánh-và-lựa-chọn-cơ-chế-ipc)
- [11. Tư duy gỡ lỗi IPC](#11-tư-duy-gỡ-lỗi-ipc)
- [12. Liên hệ với Embedded Linux](#12-liên-hệ-với-embedded-linux)
- [13. Tổng kết](#13-tổng-kết)
- [14. Tài liệu tham khảo](#14-tài-liệu-tham-khảo)

---

## 1. IPC là gì?

IPC (Inter-Process Communication) là các phương thức do hệ điều hành cung cấp để những tiến trình biệt lập có thể trao đổi dữ liệu hoặc điều phối công việc với nhau.

### 1.1 Sự cách ly bộ nhớ giữa các tiến trình

Giả sử cả `Tiến trình A` và `Tiến trình B` đều gán một biến `x` ở địa chỉ ảo `0x1000`. Điều này không có nghĩa chúng đang chia sẻ dữ liệu.

```text
+-------------------------+       +-------------------------+
| Process A               |       | Process B               |
| virtual address space A |       | virtual address space B |
+-------------------------+       +-------------------------+
```

Mỗi tiến trình chạy trong một không gian địa chỉ ảo riêng biệt. Hai địa chỉ ảo giống nhau không có nghĩa chúng trỏ tới cùng một bộ nhớ vật lý. IPC tạo ra một đường dẫn hoặc một đối tượng mà cả hai phía cùng có thể truy cập theo quy tắc nhất định.

### 1.2 Hai mục đích chính của IPC

IPC thường phục vụ hai nhu cầu chính:
1.  **Truyền dữ liệu (Data Transfer):** Chuyển các luồng byte, các khối thông điệp (messages) hoặc bộ đệm dữ liệu lớn từ tiến trình này sang tiến trình khác.
2.  **Đồng bộ/Phối hợp (Synchronization/Coordination):** Chẳng hạn báo hiệu có dữ liệu mới, thông báo hoàn thành, yêu cầu dừng hoặc đánh thức phía bên kia.

Không phải cơ chế IPC nào cũng phù hợp cho cả hai mục đích này với cùng một mức độ hiệu quả.

### 1.3 Bản đồ các cơ chế IPC trong Linux

IPC không chỉ dùng để **truyền dữ liệu**, mà còn dùng để **đồng bộ và báo hiệu sự kiện** giữa các tiến trình. Vì vậy, có thể nhìn các cơ chế trong chương này theo hai nhóm chức năng lớn:

```text
                           [ IPC ]
                              |
              +---------------+---------------+
              |                               |
      [ Trao đổi dữ liệu ]            [ Phối hợp / Báo hiệu ]
              |                               |
      +-------+-------+                 +-----+------+
      |       |       |                 |            |
 Byte Stream Message Shared Memory   Semaphore     Signal
      |       |       |
   +--+--+    |       |
   |     |    |       |
 Pipe  FIFO  POSIX MQ POSIX SHM
```

> **Đọc sơ đồ:**
> - **Pipe/FIFO** truyền dữ liệu dưới dạng `byte stream`, không tự giữ ranh giới từng thông điệp.
> - **POSIX Message Queue** truyền các `message` riêng biệt và giữ `message boundary`.
> - **POSIX Shared Memory** cho nhiều process cùng ánh xạ một vùng nhớ chung để trao đổi dữ liệu; ứng dụng phải tự tổ chức cấu trúc dữ liệu và đồng bộ truy cập.
> - **POSIX Semaphore** chủ yếu dùng để đồng bộ/phối hợp hoạt động giữa các thread hoặc process, ví dụ báo rằng tài nguyên đã sẵn sàng hoặc giới hạn số bên được phép truy cập đồng thời.
> - **Signal** chủ yếu dùng để báo hiệu một sự kiện hoặc yêu cầu điều khiển cho process/thread khác; nó không phải kênh truyền payload dữ liệu thông thường. Phần Signal đã được học riêng ở **Chủ đề 5**.
>
> Vì vậy, khi chọn IPC không chỉ cần hỏi dữ liệu là `byte stream`, `message` hay vùng nhớ dùng chung, mà còn phải xác định **cơ chế nào truyền dữ liệu** và **cơ chế nào chịu trách nhiệm đồng bộ/báo hiệu**. Trong thực tế, nhiều thiết kế kết hợp chúng với nhau, ví dụ `POSIX Shared Memory + Semaphore`.

### 1.4 Phân biệt Đối tượng IPC và `handle`

Với nhiều cơ chế IPC, cần phân biệt giữa **đối tượng IPC tồn tại trong hệ thống** và `handle` mà một tiến trình dùng để tham chiếu tới đối tượng đó. Tuy nhiên, không phải mọi cơ chế IPC đều có mô hình "đối tượng + handle" giống nhau.

*   **Pipe:** Kernel tạo một đối tượng Pipe có vùng đệm dữ liệu; tiến trình truy cập nó thông qua hai `file descriptor`: đầu đọc và đầu ghi.
*   **FIFO:** Tên FIFO tồn tại dưới dạng một `special file` trong filesystem. Khi tiến trình gọi `open()`, nó nhận một `file descriptor` để đọc hoặc ghi qua FIFO đó.
*   **POSIX Message Queue:** Đối tượng là hàng đợi thông điệp do Kernel quản lý; `mq_open()` trả về một handle kiểu `mqd_t`.
*   **POSIX Shared Memory:** Đối tượng là vùng lưu trữ dùng chung được mở bằng `shm_open()`. Tiến trình nhận một `file descriptor`, sau đó dùng `mmap()` để tạo vùng ánh xạ trong không gian địa chỉ của mình.
*   **POSIX Semaphore:** Với **named semaphore**, tên semaphore xác định đối tượng và `sem_open()` trả về con trỏ `sem_t *` để thao tác trên nó. Với **unnamed semaphore**, đối tượng `sem_t` được đặt trực tiếp trong vùng nhớ mà các bên có thể cùng truy cập, chẳng hạn Shared Memory khi dùng giữa các process.
*   **Signal:** Không có một đối tượng dữ liệu IPC lâu dài để hai bên cùng mở như Pipe/MQ/SHM. Bên gửi thường xác định **đích nhận** (process/thread) và **signal number**; phía nhận cấu hình cách xử lý signal bằng các API như `sigaction()`.

Điểm cần nhớ là `handle`, `file descriptor`, vùng `mmap()` hoặc `sem_t *` chỉ là **cách process hiện tại tham chiếu và thao tác** với cơ chế IPC tương ứng; chúng không nên bị nhầm với bản thân đối tượng hoặc trạng thái IPC mà Kernel/hệ thống đang quản lý.

---

## 2. Trước khi chọn IPC cần hỏi những gì?

Trước khi chọn một cơ chế IPC, không nên bắt đầu từ câu hỏi "API nào dễ dùng nhất?". Trước hết cần xác định **ứng dụng đang cần truyền dữ liệu hay chỉ cần phối hợp/báo hiệu**, sau đó mới xét mô hình dữ liệu, cách các tiến trình tìm nhau, hướng giao tiếp, kích thước dữ liệu và hành vi khi phía bên kia chưa sẵn sàng.

### 2.1 Cần truyền dữ liệu hay chỉ cần đồng bộ/báo hiệu?

Đây là câu hỏi đầu tiên vì không phải mọi IPC đều được dùng để mang payload dữ liệu.

*   **Cần truyền dữ liệu:** Có thể cân nhắc `Pipe`, `FIFO`, `POSIX Message Queue` hoặc `POSIX Shared Memory`.
*   **Cần đồng bộ/phối hợp:** `POSIX Semaphore` phù hợp khi một process cần chờ một trạng thái/tài nguyên trở nên sẵn sàng hoặc cần điều phối quyền truy cập.
*   **Cần báo một sự kiện/điều khiển:** `Signal` phù hợp với các thông báo ngắn như yêu cầu dừng, tiếp tục hoặc báo một sự kiện đã xảy ra; nó không nên được xem như kênh truyền payload dữ liệu thông thường.

Trong thực tế, một hệ thống có thể kết hợp nhiều cơ chế. Ví dụ, Producer ghi một khung ảnh lớn vào `POSIX Shared Memory`, sau đó dùng `Semaphore` để báo cho Consumer rằng dữ liệu đã sẵn sàng.

### 2.2 Dữ liệu là `byte stream`, từng `message` hay vùng nhớ dùng chung?

Nếu cần truyền dữ liệu, tiếp theo phải xác định ngữ nghĩa dữ liệu mong muốn:

*   **`Byte stream` — Pipe/FIFO:** Dữ liệu là một chuỗi byte liên tục. Các lần `write()` ban đầu không tạo ra `message boundary`; phía nhận phải tự làm `framing` nếu cần tách thành từng bản tin.
*   **`Message` — POSIX Message Queue:** Mỗi lần gửi tạo ra một message độc lập và Kernel giữ ranh giới của từng message.
*   **Shared Memory:** Không tự định nghĩa dữ liệu là stream hay message. Ứng dụng tự thiết kế cấu trúc nằm trong vùng nhớ chung và tự quy định cách các process đọc/ghi nó.

Ví dụ, nếu ứng dụng cần gửi từng lệnh nhỏ độc lập như `START`, `STOP`, `SET_MODE`, mô hình `message` thường tự nhiên hơn `byte stream`. Ngược lại, nếu cần truyền một luồng byte liên tục, Pipe/FIFO có thể đơn giản hơn.

### 2.3 Các tiến trình có quan hệ với nhau hay khởi chạy độc lập?

Cách các process gặp nhau ảnh hưởng trực tiếp đến lựa chọn IPC:

*   **Unnamed Pipe:** Không có tên để một process bất kỳ tự tìm đến. Nó phù hợp tự nhiên khi các `file descriptor` được kế thừa qua `fork()` hoặc được truyền cho process khác bằng một cơ chế riêng.
*   **FIFO:** Có `pathname` trong filesystem, vì vậy các process không có quan hệ cha-con vẫn có thể cùng mở một FIFO nếu biết đường dẫn và có quyền truy cập.
*   **POSIX Message Queue / POSIX Shared Memory / named POSIX Semaphore:** Có tên định danh. Các process khởi chạy độc lập có thể cùng tham chiếu tới một đối tượng nếu biết trước tên đó và đáp ứng quyền truy cập.
*   **Signal:** Không dùng một tên IPC object chung; bên gửi xác định process/thread đích cần nhận signal.

Nói ngắn gọn: nếu hai process phải **tự tìm nhau sau khi được khởi động độc lập**, cần đặc biệt chú ý đến cơ chế định danh và vòng đời của IPC object.

### 2.4 Giao tiếp một chiều hay cần trao đổi theo cả hai hướng?

Theo ngữ nghĩa chuẩn, Pipe/FIFO nên được xem là kênh truyền **một chiều (`unidirectional`)** từ writer tới reader. Nếu cần request/response bằng Pipe theo cách dễ hiểu và di động, thường dùng hai Pipe riêng:

```text
Process A  ---- Pipe 1 ---->  Process B
Process A  <--- Pipe 2 -----  Process B
```

`POSIX Message Queue` và `POSIX Shared Memory` linh hoạt hơn, nhưng ứng dụng vẫn phải thiết kế rõ ai là Producer/Consumer, dữ liệu nào đi theo hướng nào và ai sở hữu từng trạng thái. `Semaphore` và `Signal` chủ yếu phục vụ phối hợp/báo hiệu nên không nên đánh giá chúng theo khái niệm "kênh dữ liệu hai chiều" như Pipe.

### 2.5 Payload lớn hay nhỏ?

Kích thước và tần suất truyền dữ liệu có ảnh hưởng lớn đến chi phí IPC:

*   **Dữ liệu nhỏ**, chẳng hạn command, event hoặc trạng thái điều khiển, thường phù hợp với `Pipe/FIFO` hoặc đặc biệt là `POSIX Message Queue` khi cần giữ `message boundary`.
*   **Dữ liệu lớn**, chẳng hạn frame camera, block audio hoặc tensor, thường phù hợp hơn với `POSIX Shared Memory`, vì các process có thể cùng ánh xạ vùng dữ liệu thay vì phải liên tục chuyển toàn bộ payload qua một kênh truyền có bộ đệm của Kernel.

Shared Memory giảm nhu cầu sao chép payload qua cơ chế gửi/nhận, nhưng đổi lại ứng dụng phải tự giải quyết **đồng bộ, ownership và vòng đời dữ liệu**. Vì vậy không nên chọn Shared Memory chỉ vì nó "nhanh hơn" nếu dữ liệu nhỏ và giao thức đơn giản.

### 2.6 Nếu phía bên kia chưa sẵn sàng thì chương trình phải làm gì?

Nhiều IPC API có thể **block** khi chưa thể hoàn thành thao tác ngay:

*   Pipe/FIFO rỗng có thể làm `read()` chờ dữ liệu.
*   Pipe/FIFO đầy có thể làm `write()` chờ chỗ trống.
*   FIFO có thể block ngay tại `open()` khi chưa có đầu đối diện phù hợp.
*   Message Queue rỗng có thể làm `mq_receive()` chờ; queue đầy có thể làm `mq_send()` chờ.
*   `sem_wait()` có thể chờ cho tới khi Semaphore cho phép tiếp tục.

Vì vậy trước khi chọn cơ chế IPC cần xác định: **được phép chờ hay không**, có cần `nonblocking`/timeout hay không, và khi Producer nhanh hơn Consumer thì ứng dụng sẽ xử lý `backpressure` như thế nào. Nội dung này sẽ được phân tích kỹ hơn ở phần 9.

### 2.7 IPC object cần tồn tại bao lâu và ai chịu trách nhiệm dọn dẹp?

Không phải mọi IPC object đều có vòng đời giống process tạo ra nó.

*   **Unnamed Pipe:** Thường tự biến mất khi không còn `file descriptor` nào tham chiếu tới nó.
*   **FIFO:** `pathname` vẫn tồn tại trong filesystem cho tới khi được xóa.
*   **POSIX Message Queue:** Có thể tiếp tục tồn tại cho tới khi được `mq_unlink()` hoặc hệ thống khởi động lại.
*   **POSIX Shared Memory:** Tên được gỡ bằng `shm_unlink()`, còn đối tượng thực sự chỉ bị hủy sau khi các tham chiếu còn lại kết thúc.
*   **Named POSIX Semaphore:** Có tên và cần chính sách `sem_unlink()` phù hợp.

Trong Embedded Linux, điều này đặc biệt quan trọng khi service có thể bị crash rồi được Supervisor khởi động lại. Thiết kế phải xác định rõ **process nào tạo object, process nào được phép unlink, và trạng thái cũ sau crash có được tái sử dụng hay phải dọn sạch**.

### 2.8 Tóm tắt luồng suy nghĩ khi lựa chọn

Có thể dùng chuỗi câu hỏi sau trước khi quyết định:

```text
Cần truyền payload?
 |
 +-- Không --> Chỉ cần đồng bộ/báo hiệu?
 |              |
 |              +-- Đồng bộ trạng thái/tài nguyên --> Semaphore
 |              +-- Báo sự kiện/điều khiển --------> Signal
 |
 +-- Có
     |
     +-- Cần byte stream? ---------> Pipe / FIFO
     |
     +-- Cần message boundary? ----> POSIX Message Queue
     |
     +-- Payload lớn, cần dùng chung vùng dữ liệu?
                                    -> POSIX Shared Memory
                                       + cơ chế đồng bộ phù hợp
```

Sơ đồ này chỉ là **điểm khởi đầu**, không phải quy tắc tuyệt đối. Quyết định cuối cùng còn phụ thuộc vào quan hệ giữa các process, vòng đời IPC object, yêu cầu blocking/nonblocking, quyền truy cập và độ phức tạp mà ứng dụng có thể chấp nhận.

---

## 3. Unnamed Pipe: `byte stream` giữa các tiến trình

Unnamed Pipe (Ống vô danh) là một kênh truyền dữ liệu dạng `byte stream` do Kernel quản lý. Nó không có `pathname` để một tiến trình khác tự tìm tới bằng `open()`, vì vậy thường được dùng giữa các tiến trình có thể **kế thừa hoặc chuyển giao `file descriptor`** cho nhau.

### 3.1 `pipe()` tạo ra gì?

Hàm `pipe(fd_array)` tạo ra **một đối tượng Pipe trong Kernel** và trả về 2 `file descriptor` cho tiến trình gọi:

*   `fd[0]`: Đầu đọc (`read end`).
*   `fd[1]`: Đầu ghi (`write end`).

```text
Writer
  |
write(fd[1])
  |
  v
+------------------------+
|   Kernel Pipe Buffer   |
+------------------------+
  |
read(fd[0])
  |
  v
Reader
```

> **Đọc sơ đồ:** `fd[0]` và `fd[1]` không phải hai Pipe khác nhau. Chúng là hai `file descriptor` dùng để truy cập hai đầu của **cùng một Pipe object** trong Kernel. Dữ liệu ghi vào `fd[1]` đi vào buffer của Pipe và được lấy ra bằng `fd[0]`.

Bản thân `fd[0]` và `fd[1]` chỉ là các số nguyên dùng làm `handle` trong tiến trình; dữ liệu thực tế nằm trong đối tượng Pipe do Kernel quản lý.

### 3.2 Vì sao Unnamed Pipe thường đi cùng `fork()`?

Vì Unnamed Pipe không có `pathname`, hai tiến trình khởi chạy độc lập không thể chỉ biết một cái tên rồi gọi `open()` để kết nối vào nó như FIFO.

Cách phổ biến là tiến trình cha tạo Pipe **trước khi `fork()`**:

```text
        [ Tiến trình Cha ]
                |
              pipe()
                |
              fork()
             /      \
            v        v
        [ Cha ]    [ Con ]
         fd[]       fd[]
            \        /
             \      /
           cùng Pipe
          trong Kernel
```

Sau `fork()`, tiến trình con kế thừa các `file descriptor` đang mở của tiến trình cha. Vì vậy cả Cha và Con đều có các `fd` tham chiếu tới **cùng một đối tượng Pipe trong Kernel**, chứ không phải mỗi tiến trình có một Pipe riêng.

Ngoài `fork()`, `file descriptor` cũng có thể được chuyển cho một tiến trình khác bằng cơ chế đặc biệt như Unix Domain Socket; phần này thuộc chủ đề Socket Programming.

### 3.3 Thiết lập hướng truyền dữ liệu

Ngay sau `fork()`, cả Cha và Con đều đang giữ cả `fd[0]` và `fd[1]`. Nếu thiết kế chỉ cần truyền dữ liệu một chiều từ **Cha -> Con**, hai bên nên đóng ngay đầu không sử dụng:

*   **Cha:** `close(fd[0])`, chỉ giữ `fd[1]` để ghi.
*   **Con:** `close(fd[1])`, chỉ giữ `fd[0]` để đọc.

```text
[ Cha ]                                  [ Con ]
 fd[1]                                     fd[0]
   |                                         ^
   |                                         |
   +----------> [ Kernel Pipe ] -------------+
       write()                     read()
```

Quy tắc thực tế là: **đầu Pipe nào tiến trình không sử dụng thì nên đóng ngay**. Việc này không chỉ tiết kiệm `file descriptor`; số lượng đầu đọc/ghi còn đang mở còn ảnh hưởng trực tiếp đến cách Kernel xác định EOF và `SIGPIPE`, được giải thích chi tiết ở phần 4.

---

## 4. Ngữ nghĩa I/O, EOF, `SIGPIPE` và `PIPE_BUF` của Pipe

### 4.1 Pipe là `byte stream` (Không có ranh giới thông điệp)

Người gửi:
```c
write(fd, "ABC", 3);
write(fd, "DEF", 3);
```
Người đọc có thể nhận được chuỗi `"ABCDEF"` trong một lần `read`, hoặc nhận làm hai lần `"AB"` và `"CDEF"`, tùy thuộc vào kích thước bộ đệm và thời điểm thực thi. Pipe không lưu lại thông tin siêu dữ liệu để đánh dấu lần ghi số 1 kết thúc ở đâu. Nếu ứng dụng cần phân định thông điệp, nó phải tự triển khai giao thức phân khung (framing) như cố định độ dài, hoặc dùng ký tự phân cách (delimiter).

### 4.2 Pipe bảo toàn thứ tự byte trong luồng

Pipe bảo toàn thứ tự byte trong luồng. Ghi `A B C D E F` thì người đọc sẽ lấy ra đúng theo thứ tự đó, không bị đảo lộn thành `A C B D F E`.

### 4.3 Nhận diện EOF (End-Of-File) thực sự

Nếu bộ đệm Pipe đang rỗng nhưng vẫn còn `writer` đang mở đầu ghi:
*   Hàm `read()` (chế độ chặn) sẽ ngủ chờ dữ liệu mới.

Hàm `read()` CHỈ trả về `0` (ngữ nghĩa EOF) khi và chỉ khi: **Tất cả các `file descriptor` trỏ vào đầu ghi (write end) của Pipe đó đều đã bị đóng (`close`) hoàn toàn trên toàn hệ thống** và toàn bộ dữ liệu tồn đọng trong bộ đệm đã được đọc hết.
> Đây là lý do tại sao ở mục 3.3, Tiến trình Con phải đóng `fd[1]` ngay sau khi `fork()`. Nếu con giữ một bản sao đầu ghi, Kernel đánh giá "vẫn còn writer tham chiếu", do đó lệnh `read()` của con sẽ tiếp tục chờ thay vì nhận EOF khi Cha kết thúc.

### 4.4 Lỗi đứt ống: `SIGPIPE`

Nếu tiến trình ghi dữ liệu, nhưng mọi đầu đọc (read end) đều đã bị đóng:
Kernel sẽ gửi một tín hiệu `SIGPIPE` đến tiến trình đang ghi (Mặc định tín hiệu này sẽ kết thúc tiến trình).
Nếu tiến trình đã cấu hình lờ đi (ignore) `SIGPIPE`, hàm `write()` sẽ thất bại và trả về mã lỗi `EPIPE`.

### 4.5 Backpressure (Áp lực dội ngược)

Bộ đệm của Pipe trong Kernel có kích thước hữu hạn.
Nếu Producer ghi dữ liệu nhanh hơn tốc độ Consumer đọc ra, lượng dữ liệu chờ sẽ tăng cho tới khi bộ đệm đầy. Lúc này, lệnh `write()` (ở chế độ blocking) sẽ buộc phải chờ, hoặc (ở chế độ non-blocking) sẽ trả về trạng thái báo hiệu chưa thể ghi thêm (như `EAGAIN`).
Cơ chế này được gọi là `Backpressure` (Áp lực dội ngược). Nó giúp điều tiết tốc độ giữa hai phía, đảm bảo hệ thống không tiêu thụ RAM vô hạn khi tải tăng cao.

### 4.6 Giới hạn nguyên tử `PIPE_BUF`

Dung lượng tổng (Capacity) của Pipe và `PIPE_BUF` là hai khái niệm hoàn toàn khác biệt.
`PIPE_BUF` (thường là 4096 bytes trên Linux) là một hạn mức đảm bảo tính nguyên tử (atomic) do chuẩn POSIX quy định.
Nếu nhiều tiến trình cùng ghi vào 1 Pipe, các thao tác ghi có kích thước **nhỏ hơn hoặc bằng `PIPE_BUF`** sẽ được bảo đảm ghi nguyên vẹn, không bị đan xen vào nhau. Nếu `write()` ghi khối dữ liệu lớn hơn `PIPE_BUF`, các khối byte có thể bị cắt mảnh và xen kẽ với dữ liệu từ các `writer` khác.

---

## 5. FIFO: Pipe có tên trong hệ thống tệp

FIFO giống hệt Pipe về mặt ngữ nghĩa I/O, nhưng nó được cấp một định danh (tên) trong hệ thống tệp, giúp các tiến trình không cần có quan hệ họ hàng vẫn có thể tìm thấy và giao tiếp với nhau.

### 5.1 FIFO là một `special file` (tệp đặc biệt)

Đường dẫn `/run/myapp.fifo` là một tệp đặc biệt trong không gian tên (namespace) của hệ thống tệp, dùng làm mục tiêu định tuyến. Dữ liệu thực tế truyền qua FIFO đi qua đối tượng Pipe và bộ đệm trong Kernel, không được lưu xuống thiết bị lưu trữ vật lý như một tệp văn bản thông thường.

### 5.2 Điểm hẹn của các tiến trình

```text
Tiến trình A
   |
open("/run/myapp.fifo")
   |
   +--------------------+
                        v
                    FIFO pathname
                        ^
   +--------------------+
   |
Tiến trình B
```
> **Đọc sơ đồ:** Hai tiến trình khởi chạy độc lập chỉ cần biết chung một pathname là có thể kết nối với nhau, miễn là chúng đáp ứng các quyền truy cập (`owner`, `group`, `r/w permissions`) do hệ thống tệp quy định đối với mục FIFO đó.

### 5.3 Lệnh `open()` trên FIFO có tính chất chặn

Theo mặc định (blocking mode), khi một tiến trình mở FIFO ở chế độ đọc, hàm `open()` sẽ chờ (block) cho tới khi có một tiến trình khác mở FIFO đó ở chế độ ghi, và ngược lại. Thao tác `open()` đóng vai trò như một điểm phối hợp giữa các tiến trình.

### 5.4 Sự khác biệt với cờ `O_NONBLOCK`

Với cờ `O_NONBLOCK`, hành vi mở sẽ thay đổi. Ví dụ điển hình của POSIX: Nếu một tiến trình cố gắng mở FIFO ở chế độ chỉ ghi (`O_WRONLY | O_NONBLOCK`) mà hiện tại chưa có tiến trình nào mở FIFO đó ở chế độ đọc, lệnh `open()` sẽ lập tức thất bại và trả về mã lỗi `ENXIO`.

---

## 6. POSIX Message Queue: gửi từng thông điệp riêng

`Message Queue` (MQ) khác Pipe/FIFO ở chỗ nó duy trì ranh giới của từng thông điệp.

### 6.1 Mô hình Thông điệp

```text
 Sender
   |
 mq_send()
   |
   v
+-------------------------+
| POSIX Message Queue     |
|-------------------------|
| [ Message A ]           |
| [ Message B ]           |
| [ Message C ]           |
+-------------------------+
   |
 mq_receive()
   |
   v
 Receiver
```

> **Đọc sơ đồ:** Kernel lưu trữ từng message như một đơn vị độc lập có ranh giới rõ ràng (`message boundary`). Sender gọi `mq_send()` để đưa một message vào, Receiver gọi `mq_receive()` để lấy ra đúng **một message** đó. Ứng dụng không cần tự triển khai logic `framing` (như độ dài cố định hay ký tự phân cách) để bóc tách thông điệp như khi dùng `byte stream`.

### 6.2 Định danh và Mở hàng đợi

POSIX MQ sử dụng một tên chuẩn (thường bắt đầu bằng dấu `/`, ví dụ `/my_queue`). Hàm `mq_open()` trả về một bộ mô tả hàng đợi có kiểu `mqd_t` (Nó được POSIX chuẩn hóa như một Handle, không nên ép kiểu nó thành `int` fd như Pipe).

### 6.3 Hàng đợi rỗng / đầy và Backpressure

MQ không phải là không gian vô hạn. Nó có các thuộc tính: số lượng thông điệp tối đa (`mq_maxmsg`) và kích thước thông điệp tối đa (`mq_msgsize`).
*   **Khi rỗng:** Hàm `mq_receive` (ở chế độ chặn) sẽ ngủ chờ thông điệp mới. Ở chế độ không chặn, nó trả về `EAGAIN`.
*   **Khi đầy:** Hàm `mq_send` (ở chế độ chặn) sẽ ngủ chờ đến khi có không gian trống. Đây là cơ chế `backpressure` có chủ đích do Kernel quản lý, ngăn không cho Producer đẩy lượng thông điệp chờ lên vô hạn.

### 6.4 Mức độ ưu tiên (Priority)

Khác với mô hình vào trước-ra trước (FIFO) tuyệt đối của Pipe, POSIX MQ cho phép gán độ ưu tiên (priority) cho mỗi thông điệp gửi đi.
Receiver sẽ luôn nhận được thông điệp có độ ưu tiên cao nhất trước. Nếu có nhiều thông điệp cùng độ ưu tiên, chúng mới được xử lý theo thứ tự gửi (FIFO). Do đó, POSIX MQ không phải là một hàng đợi FIFO toàn cục nếu các thông điệp có ưu tiên khác nhau.

### 6.5 Vòng đời: `mq_close()` và `mq_unlink()`

Cần phân biệt hai thao tác:
*   `mq_close()`: Đóng handle (`mqd_t`) của tiến trình hiện tại đối với hàng đợi.
*   `mq_unlink()`: Gỡ bỏ tên hàng đợi khỏi không gian tên của hệ thống.

Hàng đợi sở hữu đặc tính `kernel persistence` (tồn tại trong Kernel). Nếu chưa bị `mq_unlink()`, hàng đợi và các thông điệp bên trong nó vẫn có thể tồn tại kể cả khi tất cả tiến trình tạo ra nó đã kết thúc, cho tới khi hệ thống khởi động lại. Do đó, việc dọn dẹp đối tượng là trách nhiệm của thiết kế ứng dụng.

---

## 7. POSIX Shared Memory: cùng nhìn một vùng nhớ

POSIX Shared Memory (SHM) cho phép nhiều tiến trình ánh xạ chung một vùng bộ nhớ. Nó giúp giảm chi phí sao chép dữ liệu (copy) qua Kernel, đặc biệt hiệu quả với các khối dữ liệu lớn, nhưng bù lại đòi hỏi ứng dụng phải tự quản lý việc đồng bộ hóa.

### 7.1 Mô hình Ánh xạ chung (Mapping)

```text
Tiến trình A                     Tiến trình B
+--------------+                +--------------+
| mapping A    |                | mapping B    |
+------+-------+                +------+-------+
       |                               |
       +---------------+---------------+
                       |
                       v
             +--------------------+
             | Shared Memory      |
             | backing object     |
             +--------------------+
```

> **Đọc sơ đồ:** Hai tiến trình có không gian địa chỉ ảo khác nhau, nhưng Kernel cho phép ánh xạ (mapping) của chúng trỏ về chung một đối tượng lưu trữ (backing object) vật lý phía dưới. Địa chỉ ảo ở A và B không cần giống nhau, điều được chia sẻ là các trang nhớ vật lý.

### 7.2 Khởi tạo và Ánh xạ

*   **Tạo/Mở:** Hàm `shm_open()` (với cờ `O_CREAT`) tạo hoặc mở một đối tượng chia sẻ và trả về một `file descriptor`. Đối tượng mới tạo có kích thước ban đầu bằng `0`.
*   **Cấp phát:** Ứng dụng phải dùng lệnh `ftruncate()` để thiết lập kích thước cho đối tượng trước khi sử dụng.
*   **Ánh xạ:** Hàm `mmap(..., MAP_SHARED, ...)` thực hiện ánh xạ đối tượng vào không gian địa chỉ của tiến trình. Cờ `MAP_SHARED` đảm bảo các thay đổi do tiến trình này thực hiện sẽ được đồng bộ và các tiến trình khác ánh xạ cùng đối tượng sẽ nhìn thấy được (khác biệt với `MAP_PRIVATE` tạo ra một bản sao cục bộ).

*(Lưu ý: Trên Linux, POSIX SHM thường được hỗ trợ bởi hệ thống tệp `tmpfs` và hiển thị tại `/dev/shm`, nhưng không nên coi nó như một tệp lưu trữ lâu dài trên đĩa cứng).*

### 7.3 Địa chỉ tuyệt đối trong Shared Memory

Hai tiến trình có thể ánh xạ cùng một đối tượng Shared Memory nhưng nhận các địa chỉ ảo khác nhau (Ví dụ: Tiến trình A nhận địa chỉ gốc `0x70000000`, B nhận `0x50000000`).
Việc lưu một con trỏ địa chỉ ảo tuyệt đối (raw pointer) của A vào vùng dùng chung rồi hy vọng B sử dụng nguyên giá trị đó là một lỗi thiết kế nghiêm trọng, vì địa chỉ đó không có ý nghĩa tương ứng trong B. Thay vào đó, hãy sử dụng **độ lệch (offset)** tính từ địa chỉ gốc của vùng ánh xạ, hoặc các chỉ mục (index).

### 7.4 Vòng đời phân tách

Lệnh `shm_unlink()` chỉ xóa cái tên định danh khỏi hệ thống. Đối tượng SHM thực sự bên dưới sẽ tiếp tục tồn tại chừng nào vẫn còn các vùng ánh xạ (`mmap`) đang hoạt động hoặc các `file descriptor` đang mở trỏ tới nó. Đối tượng chỉ bị hủy hoàn toàn khi tham chiếu cuối cùng kết thúc.

---

## 8. Vì sao Shared Memory cần đồng bộ?

Shared Memory chỉ cung cấp cơ chế để các tiến trình cùng thấy một vùng nhớ; nó không tự ngăn chặn việc hai tiến trình sửa đổi dữ liệu cùng lúc.

### 8.1 Truy cập đồng thời cần giao thức bảo vệ

Việc hai tiến trình cùng ánh xạ và nhìn thấy dữ liệu không đảm bảo tính an toàn. Nếu tiến trình A đang cập nhật cấu trúc dữ liệu trong khi tiến trình B đọc đồng thời, B có thể đọc được dữ liệu bị xé rách hoặc sai lệch (Data Race). Các thao tác truy cập đồng thời vào trạng thái có thể thay đổi (concurrent mutable access) bắt buộc phải có một cơ chế đồng bộ hóa hoặc giao thức sở hữu (ownership protocol) đi kèm.

### 8.2 Tích hợp Đối tượng Đồng bộ vào SHM

POSIX cho phép đặt các đối tượng đồng bộ hóa (như `pthread_mutex_t` hoặc Semaphore) trực tiếp vào bên trong vùng nhớ dùng chung. Bằng cách thiết lập thuộc tính `PTHREAD_PROCESS_SHARED` (với Mutex) hoặc cờ `pshared` (với Semaphore), các cơ chế đồng bộ này có thể hoạt động xuyên qua ranh giới của các tiến trình.

### 8.3 Phân tách Data Plane và Control Plane

Trong các hệ thống hiệu suất cao, người ta thường phân chia rõ ràng:

```text
Data Plane:
  Shared Memory (Chứa Payload dữ liệu kích thước lớn)

Control Plane:
  Semaphore / Mutex / Message Queue (Chứa Thông tin trạng thái điều phối)
```

Ví dụ: Producer ghi một khối dữ liệu lớn vào Shared Memory (tránh sao chép tốn kém), sau đó sử dụng một tín hiệu Semaphore nhỏ gọn để thông báo cho Consumer rằng "khung dữ liệu mới đã sẵn sàng". Mô hình này phù hợp với các hệ thống cần trao đổi payload lớn và điều phối truy cập riêng.

---

## 9. Hành vi chặn, `backpressure` và giới hạn tài nguyên

Mọi cơ chế IPC đều tiêu thụ tài nguyên hữu hạn của hệ thống. Khi bộ đệm hoặc hàng đợi đạt giới hạn, các lệnh gọi I/O sẽ phải đối mặt với hành vi chặn (blocking) hoặc trả lỗi.

### 9.1 Vì sao IPC có thể chặn?

Các lệnh gọi bị chặn khi đối tượng hoặc đối tác giao tiếp chưa sẵn sàng:
*   Pipe/FIFO rỗng -> `read()` bị chặn (chờ dữ liệu).
*   Pipe/FIFO đầy -> `write()` bị chặn (chờ không gian trống).
*   FIFO `open()` -> Có thể chặn chờ tiến trình phía bên kia.
*   MQ rỗng -> `mq_receive()` bị chặn.

Hiểu được điều kiện chờ giúp bạn phân biệt một hành vi `blocking` hợp lệ với một trạng thái lỗi `deadlock` hoặc sự cố phía đối tác.

### 9.2 Khái niệm Backpressure (Áp lực dội ngược)

Nếu bên sản xuất (Producer) tạo ra dữ liệu nhanh hơn tốc độ tiêu thụ của bên nhận (Consumer), dữ liệu chờ sẽ tích tụ. Đối với các hệ thống có bộ đệm hữu hạn (như Pipe, MQ), khi bộ đệm đầy, thao tác ghi của Producer sẽ bị chặn lại.
Cơ chế buộc Producer phải chậm lại này chính là `Backpressure`. Nó là một tính năng thiết yếu giúp kiểm soát mức tiêu thụ RAM và giữ hệ thống ổn định dưới tải cao.

### 9.3 Chế độ Non-blocking không làm mất bài toán Backpressure

Việc bật cờ `O_NONBLOCK` chỉ thay đổi hành vi từ "chờ ở đây" thành "hiện giờ chưa thể làm, trả về mã lỗi `EAGAIN`". Ứng dụng vẫn phải đối mặt với bài toán Backpressure: Quyết định xem khi nào nên thử lại, có được phép vứt bỏ (drop) dữ liệu hay không, và lưu trữ dữ liệu tạm thời ở đâu.

---

## 10. So sánh và lựa chọn cơ chế IPC

Không có cơ chế IPC nào là "tốt nhất" cho mọi bài toán. Lựa chọn phải dựa trên mô hình dữ liệu, vòng đời, và mức độ phức tạp.

| Cơ chế | Mô hình Dữ liệu | Có tên gọi/Pathname? | Giữ ranh giới Message? | Đặc điểm ứng dụng (Khi nào dùng) |
| :--- | :--- | :--- | :--- | :--- |
| **Unnamed Pipe** | `byte stream` | Không | Không | Đơn giản, phù hợp khi `fd` được kế thừa tự nhiên qua `fork()`. Rất tốt để đẩy lệnh hoặc gom bắt Log `stdout`. |
| **FIFO (Named pipe)**| `byte stream` | Có | Không | Dành cho các tiến trình độc lập cần điểm hẹn trong hệ thống tệp và chung ngữ nghĩa luồng byte. |
| **POSIX MQ** | Thông điệp rời rạc | Có | Có | Truyền các Lệnh (Command/Event). Có ưu tiên Priority. Tránh được việc tự `framing` dữ liệu. |
| **Shared Memory** | Khối vùng nhớ chung | Có | Ứng dụng tự lo | Payload lớn (Video, AI Tensor). Cần giảm việc sao chép. Yêu cầu thiết kế đồng bộ và quy tắc vòng đời riêng biệt. |

---

## 11. Tư duy gỡ lỗi IPC

Khi IPC gặp sự cố, hãy kiểm tra theo trình tự phân lớp logic để khoanh vùng nguyên nhân.

### 11.1 Trình tự kiểm tra theo tầng

```text
Hai bên có đang tham chiếu cùng một IPC object không? (Sai tên, khác đối tượng?)
        |
Quyền hạn (Permissions) và Credentials có đúng không?
        |
Đối tác (Peer) có tồn tại và đang giữ endpoint không?
        |
Chế độ Blocking hay Non-blocking? (Chờ hợp lệ hay bị kẹt?)
        |
Buffer/Queue đang Rỗng hay Đầy?
        |
Luồng dữ liệu (Framing / Message semantics) có bị giải mã sai không?
        |
Vòng đời (Lifetime / Unlink semantics) có bị gỡ bỏ quá sớm không?
        |
Shared Memory có được đồng bộ hóa đúng cách không?
```
Đi từ việc định danh đối tượng -> Quyền hạn -> Trạng thái I/O -> Giao thức ứng dụng giúp bạn không bị lạc lối khi gỡ lỗi.

### 11.2 Reader của Pipe chờ mãi không nhận được EOF

Nguyên nhân thường do: Vẫn còn một tiến trình (có thể là một tiến trình con vô tình kế thừa `fd`) đang giữ một đầu ghi (write end) mở. EOF phụ thuộc vào **mọi** `writer` tham chiếu đến đối tượng Pipe đó, không chỉ riêng `writer` mà bạn đang chú ý tới.

### 11.3 Tên IPC (MQ/SHM/FIFO) tồn tại không có nghĩa đối tác đang sống

Sự tồn tại của một mục FIFO trong thư mục, hay tên một MQ, chỉ chứng minh đối tượng hoặc tên đó tồn tại. Điều này không chứng minh đối tác của bạn đang mở kết nối, có đủ quyền, hay tiến trình đó còn sống.

---

## 12. Liên hệ với Embedded Linux

Nhiều hệ thống Embedded Linux tách chức năng thành các tiến trình độc lập (như sensor, logger, UI, daemon) và sử dụng IPC để kết nối chúng.

### 12.1 Unnamed Pipe cho kiến trúc Supervisor - Worker

Supervisor có thể tạo một Pipe trước khi gọi `fork()`, để tiến trình con (Worker) kế thừa `fd` cần thiết. Sau khi đóng các đầu không sử dụng, Pipe trở thành một kênh truyền `byte stream` khép kín. Việc sử dụng Pipe kiểu này rất hiệu quả để thu thập `stdout`/`stderr` hoặc truyền nhận lệnh nội bộ giữa các tiến trình có quan hệ.

### 12.2 POSIX Message Queue cho Command/Event

Giữa Control Service và Worker Process, việc gửi các lệnh điều khiển thông qua Message Queue mang lại ưu điểm rõ rệt. Vì MQ duy trì `message boundary`, Worker sẽ nhận từng câu lệnh một cách độc lập và trọn vẹn mà không cần phải tự xử lý cắt khung (framing) luồng byte phức tạp như đối với Pipe. Message Queue còn hỗ trợ tính năng độ ưu tiên (Priority), giúp các cảnh báo khẩn cấp có thể vượt lên trên các bản tin dữ liệu bình thường.

### 12.3 AI Camera Pipeline và Shared Memory

Trong xử lý luồng Video hoặc Camera độ phân giải cao, việc đẩy dữ liệu qua Pipe sẽ bắt CPU thực hiện liên tục các lệnh `memcpy` trong Kernel.
Bằng cách sử dụng **Shared Memory**, Camera process có thể ghi khung hình vào bộ nhớ, và AI process có thể trực tiếp ánh xạ đọc khung hình đó. Nhằm đảm bảo trật tự đọc ghi, kiến trúc này thường dùng thêm các primitives đồng bộ (như Semaphore Process-shared) để báo hiệu vị trí buffer (slot) nào đã sẵn sàng. Cơ chế này giúp giảm lượng dữ liệu sao chép qua kênh gửi/nhận, tối ưu hóa hiệu năng tổng thể của Pipeline.

### 12.4 Khởi động lại và dọn dẹp tài nguyên

Khi một dịch vụ (Service) bị crash, không giống như unnamed pipe (tự động mất đi khi `fd` cuối cùng bị đóng), các đối tượng như FIFO, POSIX MQ, và SHM vẫn lưu lại tên và dữ liệu trong hệ thống (kernel persistence). Thiết kế Supervisor hoặc quá trình phục hồi sau lỗi cần phải có chính sách xử lý dọn dẹp (`unlink`) rõ ràng để khôi phục trạng thái chuẩn khi ứng dụng khởi động lại.

---

## 13. Tổng kết

### 13.1 Bản đồ IPC tổng kết

```text
                    [ BÀI TOÁN GIAO TIẾP ]
                             |
       +---------------------+---------------------+
       |                     |                     |
       v                     v                     v
 [ Dòng chảy Byte ]   [ Thông điệp rời rạc ]   [ Không gian RAM lớn ]
       |                     |                     |
   +---+---+                 |                     |
   |       |                 |                     |
 Pipe    FIFO            POSIX MQ              POSIX SHM
```

Bản đồ này cho thấy không có một cơ chế IPC nào phù hợp với mọi bài toán. Pipe/FIFO xử lý luồng dữ liệu liên tục; POSIX MQ bảo toàn ranh giới của từng gói lệnh nhỏ; POSIX SHM phù hợp với dữ liệu lớn nhưng yêu cầu ứng dụng tự quản lý việc đồng bộ. Việc lựa chọn phải xuất phát từ bài toán thiết kế dữ liệu thực tế.

### 13.2 Các điểm cần nhớ

1. IPC dùng để giao tiếp/phối hợp giữa các tiến trình có không gian bộ nhớ cách ly.
2. Cần phân biệt rõ bản thân đối tượng IPC (trong Kernel) và `handle` / `fd` mà tiến trình dùng để tham chiếu tới nó.
3. Pipe là `byte stream` (không có ranh giới thông điệp), thiết kế 1 chiều, phù hợp tự nhiên khi `fd` được kế thừa qua `fork()`.
4. EOF của pipe chỉ xuất hiện khi mọi `writer` tham chiếu đã biến mất và dữ liệu cũ đã được đọc hết.
5. Ghi vào ống khi không còn `reader` sẽ nhận tín hiệu `SIGPIPE` hoặc lỗi `EPIPE`.
6. `PIPE_BUF` liên quan đến giới hạn ghi nguyên tử (atomic write), không phải là tổng dung lượng Pipe.
7. FIFO (Named pipe) là một `special file` (tệp đặc biệt) trong không gian hệ thống tệp, dữ liệu của nó không lưu trên đĩa.
8. POSIX MQ giữ `message boundary`, hỗ trợ độ ưu tiên (priority) và được Kernel quản lý hàng đợi.
9. POSIX Shared Memory cho nhiều tiến trình ánh xạ cùng một đối tượng lưu trữ bên dưới.
10. Lệnh `shm_unlink()` xóa tên đối tượng, nhưng ánh xạ (`mapping`) đang tồn tại có vòng đời độc lập và chỉ bị hủy khi tham chiếu cuối cùng kết thúc.
11. Không nên giả định cùng một địa chỉ ảo tuyệt đối (`raw pointer`) khi sử dụng Shared Memory giữa các tiến trình; nên dùng `offset` hoặc `index`.
12. Shared Memory yêu cầu cơ chế đồng bộ (Mutex/Semaphore) và quy ước sở hữu dữ liệu từ phía ứng dụng đối với các truy cập thay đổi đồng thời (concurrent mutable access).
13. Chế độ `nonblocking` không loại bỏ được bài toán điều tiết lưu lượng (`backpressure`).
14. Sự tồn tại của tên IPC (MQ/SHM/FIFO) không chứng minh tiến trình đối tác còn sống hay hoạt động bình thường.

---

## 14. Tài liệu tham khảo

Phần này liệt kê nguồn chuẩn về các cơ chế IPC đã học.

### POSIX.1-2024 / The Open Group

- https://pubs.opengroup.org/onlinepubs/9799919799/
- `pipe()`: https://pubs.opengroup.org/onlinepubs/9799919799/functions/pipe.html
- `mmap()`: https://pubs.opengroup.org/onlinepubs/9799919799/functions/mmap.html
- `sem_init()`: https://pubs.opengroup.org/onlinepubs/9799919799/functions/sem_init.html

Nguồn chuẩn cho ngữ nghĩa di động của IPC và memory ánh xạ.

### Linux man-pages — Pipe/FIFO

- `pipe(7)`: https://man7.org/linux/man-pages/man7/pipe.7.html
- `fifo(7)`: https://man7.org/linux/man-pages/man7/fifo.7.html
- `mkfifo(3)`: https://man7.org/linux/man-pages/man3/mkfifo.3.html

### Linux man-pages — POSIX Message Queue

- `mq_overview(7)`: https://man7.org/linux/man-pages/man7/mq_overview.7.html
- `mq_open(3)`: https://man7.org/linux/man-pages/man3/mq_open.3.html
- `mq_send(3)`: https://man7.org/linux/man-pages/man3/mq_send.3.html
- `mq_receive(3)`: https://man7.org/linux/man-pages/man3/mq_receive.3.html

### Linux man-pages — POSIX Shared Memory

- `shm_overview(7)`: https://man7.org/linux/man-pages/man7/shm_overview.7.html
- `shm_open(3)`: https://man7.org/linux/man-pages/man3/shm_open.3.html
- `mmap(2)`: https://man7.org/linux/man-pages/man2/mmap.2.html
- `sem_overview(7)`: https://man7.org/linux/man-pages/man7/sem_overview.7.html

### Tài liệu bổ sung

- The Linux Programming Interface: https://man7.org/tlpi/
- Bootlin Embedded Linux: https://bootlin.com/doc/training/embedded-linux/
- Unix & Linux Stack Exchange: https://unix.stackexchange.com/
- Stack Overflow: https://stackoverflow.com/

Nguồn cộng đồng hữu ích để tìm lỗi rò file descriptor, FIFO open bị chặn, MQ priority hoặc raw pointer trong SHM, nhưng ngữ nghĩa chuẩn phải đối chiếu lại với POSIX/Linux man-pages.

---

> **Điều hướng:** [← Chủ đề 7 — Đồng bộ luồng](README-topic-07.md) · [Chủ đề 9 — Socket Programming →](README-topic-09.md)
