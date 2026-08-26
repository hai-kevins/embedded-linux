# Chủ đề 6 — Đa luồng trong Linux (Multithreading)

> **Mục tiêu:** Hiểu luồng (`thread`) là gì, tại sao một tiến trình có thể (và cần) có nhiều luồng. Nắm vững ranh giới giữa những tài nguyên dùng chung và dùng riêng, cùng vòng đời cơ bản: `pthread_create() → chạy → kết thúc → pthread_join() / detach`.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Giữ nguyên các thuật ngữ/API chuẩn như `thread`, `Pthreads`, `NPTL`, `pthread_t`, `joinable`, `detached`, `concurrency`, `parallelism`, `race condition`, `atomic operation`, `signal mask`, `TID`, `PID` để thuận tiện cho việc tra cứu tài liệu quốc tế.
>
> **Phạm vi:** So sánh Tiến trình và Luồng, kiến trúc `Pthreads` và `NPTL`, định danh luồng (PID vs TID), không gian địa chỉ, tạo luồng, vòng đời, quản lý tài nguyên (joinable/detached), ngăn xếp (stack), `concurrency` vs `parallelism`, rủi ro `race condition` cơ bản, và cách quan sát luồng trên Linux.
>
> Chương này là **lý thuyết nền tảng** chuẩn bị cho lập trình đa luồng. Các cơ chế khóa (Mutex), biến điều kiện (Condition variable) và đồng bộ chi tiết sẽ thuộc **Chủ đề 7**.

Một tiến trình có thể chứa nhiều luồng thực thi. Các luồng **dùng chung phần lớn tài nguyên của tiến trình** (như không gian địa chỉ RAM, danh sách tệp đang mở `file descriptor`), nhưng mỗi luồng vẫn cần một không gian riêng tư (ngăn xếp/stack, thanh ghi CPU) để ghi nhớ mình đang làm việc đến đâu. Bản chất “dùng chung nhiều nhưng chạy độc lập” giúp việc phối hợp công việc thuận tiện, nhưng đồng thời tạo ra nguy cơ `race condition` nếu dữ liệu dùng chung không được đồng bộ đúng cách.

---

## Mục lục

- [1. `Multithreading` là gì?](#1-multithreading-là-gì)
- [2. Tiến trình và luồng khác nhau thế nào?](#2-tiến-trình-và-luồng-khác-nhau-thế-nào)
- [3. POSIX Threads và NPTL](#3-posix-threads-và-nptl)
- [4. Định danh luồng: `pthread_t`, TID và PID](#4-định-danh-luồng-pthread_t-tid-và-pid)
- [5. Các luồng dùng chung gì và có gì riêng?](#5-các-luồng-dùng-chung-gì-và-có-gì-riêng)
- [6. `pthread_create()`: tạo một luồng mới](#6-pthread_create-tạo-một-luồng-mới)
- [7. Vòng đời và cách một luồng kết thúc](#7-vòng-đời-và-cách-một-luồng-kết-thúc)
- [8. Luồng joinable và detached](#8-luồng-joinable-và-detached)
- [9. Thuộc tính, ngăn xếp và chi phí của một luồng](#9-thuộc-tính-ngăn-xếp-và-chi-phí-của-một-luồng)
- [10. `concurrency` và `parallelism`](#10-concurrency-và-parallelism)
- [11. Vì sao dùng chung bộ nhớ dẫn tới `race condition`?](#11-vì-sao-dùng-chung-bộ-nhớ-dẫn-tới-race-condition)
- [12. Quan sát luồng trên Linux](#12-quan-sát-luồng-trên-linux)
- [13. Tư duy gỡ lỗi đa luồng](#13-tư-duy-gỡ-lỗi-đa-luồng)
- [14. Liên hệ với Embedded Linux](#14-liên-hệ-với-embedded-linux)
- [15. Tổng kết](#15-tổng-kết)
- [16. Tài liệu tham khảo](#16-tài-liệu-tham-khảo)

---

## 1. `Multithreading` là gì?

Multithreading (Đa luồng) là kỹ thuật cho phép một tiến trình chia nhỏ công việc thành nhiều dòng thực thi (luồng) chạy song hành hoặc xen kẽ nhau.

### 1.1 Từ một dòng tới nhiều dòng thực thi

Chương trình truyền thống chỉ có một luồng thực thi (thường gọi là main thread):
```text
[ Tiến trình ] ---> (Luồng A thực hiện tuần tự từ trên xuống dưới)
```

Chương trình đa luồng:
```text
                 [ Tiến trình ]
                       |
          +------------+------------+
          |            |            |
          v            v            v
      [ Luồng A ]  [ Luồng B ]  [ Luồng C ]
```
Dù nằm chung một tiến trình, bộ lập lịch (`scheduler`) của Linux Kernel có thể phân bổ CPU để chúng chạy một cách độc lập.

### 1.2 Vì sao cần nhiều luồng?

Một ứng dụng thực tế hiếm khi chỉ làm một việc tuần tự. Giả sử ứng dụng của bạn cần: (1) Đọc dữ liệu từ cảm biến, (2) Xử lý số liệu, và (3) Hiển thị lên màn hình.

Nếu dùng 1 luồng duy nhất:
```text
(Đọc cảm biến) ---> [ Bị chặn (Block) chờ thiết bị phản hồi ] ---> (Xử lý và Hiển thị bị đóng băng)
```

Nếu dùng đa luồng:
```text
[ Luồng 1: Đọc cảm biến ] ---> (Bị block chờ thiết bị)
[ Luồng 2: Hiển thị     ] ---> (Vẫn lấy dữ liệu cũ vẽ lên màn hình bình thường)
[ Luồng 3: Mạng         ] ---> (Vẫn nhận lệnh từ User bình thường)
```
Tránh tình trạng "chờ một việc mà chặn toàn bộ dòng thực thi" là lý do lớn nhất để dùng đa luồng.

### 1.3 Luồng không chỉ là “một hàm chạy nền”

Một luồng thường bắt đầu bằng cách thực thi một hàm C, nhưng bản thân nó là một **ngữ cảnh thực thi** hoàn chỉnh mang trong mình: bộ đếm lệnh (đang chạy tới dòng code nào), thanh ghi CPU, ngăn xếp (chứa biến cục bộ), và trạng thái lập lịch riêng để Kernel quản lý.

---

## 2. Tiến trình và luồng khác nhau thế nào?

Tiến trình cung cấp ranh giới cách ly tài nguyên mạnh mẽ; Luồng chia sẻ tài nguyên nhiều hơn, giúp giao tiếp nhanh nhưng đổi lại rủi ro cách ly lỗi (fault isolation) thấp hơn.

### 2.1 Tiến trình là vùng chứa tài nguyên

Nhắc lại Topic 04, một tiến trình có một không gian bộ nhớ ảo khổng lồ, chứa mã lệnh, heap, bảng tệp đang mở. Nếu bạn tạo một **tiến trình mới** (bằng `fork()`), Kernel xây dựng một vùng chứa độc lập với không gian địa chỉ riêng. Các tiến trình chia sẻ dữ liệu thường yêu cầu các cơ chế giao tiếp liên tiến trình (IPC).

### 2.2 Luồng nằm trong cùng tiến trình

```text
+-------------------------------------------------------------+
|                      [ TIẾN TRÌNH ]                         |
|  Tài nguyên dùng chung (Shared):                            |
|    Mã lệnh (Code) / Dữ liệu toàn cục (Data/BSS) / Heap      |
|    Bảng File Descriptor / Thư mục làm việc (cwd)            |
|                                                             |
|  +-----------------------+       +-----------------------+  |
|  | [ Luồng A ]           |       | [ Luồng B ]           |  |
|  | - Ngăn xếp (Stack A)  |       | - Ngăn xếp (Stack B)  |  |
|  | - Thanh ghi CPU (A)   |       | - Thanh ghi CPU (B)   |  |
|  | - Signal Mask (A)     |       | - Signal Mask (B)     |  |
|  +-----------------------+       +-----------------------+  |
+-------------------------------------------------------------+
```

> **Đọc sơ đồ:** Không gian bộ nhớ lớn (Heap, Data) được dùng chung. Luồng A và Luồng B có thể cùng đọc/ghi một biến toàn cục `int counter` trực tiếp. Tuy nhiên, mỗi luồng được cấp một Ngăn xếp (Stack) và bộ thanh ghi CPU riêng. Điều đáng chú ý là `Signal mask` cũng thuộc cấu trúc riêng của từng luồng (kết nối với kiến thức Topic 05).

### 2.3 So sánh nhanh

| Thuộc tính | Đa Tiến Trình (Multi-Processing) | Đa Luồng (Multi-Threading) |
| :--- | :--- | :--- |
| **Không gian địa chỉ** | Tách biệt hoàn toàn (Có COW sau fork) | Dùng chung 100% |
| **Dữ liệu Heap/Toàn cục** | Không dùng chung trực tiếp (mặc định) | Chia sẻ chung |
| **Bảng File Descriptor** | Tách biệt (dù có thể kế thừa) | Cùng chung một bảng |
| **Tốc độ giao tiếp** | Thường cần IPC (Pipe, Socket, Shm) | Truy cập thẳng bộ nhớ chung |
| **Cách ly lỗi (Fault Isolation)** | Tốt. Tiến trình A sập, tiến trình B vẫn chạy | Kém. Luồng A gây lỗi bộ nhớ, toàn tiến trình chết. |

---

## 3. POSIX Threads và NPTL

`Pthreads` là tiêu chuẩn giao diện lập trình, còn `NPTL` là kiến trúc triển khai tiêu chuẩn đó trên Linux.

### 3.1 `Pthreads` là gì?

`POSIX Threads` (`Pthreads`) là một bộ giao diện API chuẩn hóa quốc tế để viết ứng dụng đa luồng trên các hệ điều hành UNIX-like.
Các hàm cốt lõi: `pthread_create()`, `pthread_join()`, `pthread_detach()`, `pthread_mutex_lock()`...

Lập trình viên ứng dụng nên tư duy và viết code trên lớp API `Pthreads` thay vì thao tác trực tiếp với các cơ chế tạo luồng cấp thấp của nhân hệ điều hành.

### 3.2 Linux dùng `NPTL` (Native POSIX Thread Library)

Khi bạn gọi hàm `pthread_create()` trong thư viện C (glibc), Linux sử dụng thư viện `NPTL` làm lớp thực thi.

```text
[ Ứng dụng C ] ---> Gọi API: pthread_create()
       |
[ Thư viện glibc (NPTL) ]
       |
[ Kernel Linux ] ---> Gọi cơ chế tạo task (dựa trên clone() primitives)
```

NPTL là implementation Pthreads của glibc trên Linux. Việc ứng dụng gọi API chuẩn giúp mã nguồn linh hoạt (portable), không bị khóa cứng (lock-in) vào chi tiết hệ thống như `syscall clone()`.

### 3.3 Mô hình 1:1

Kiến trúc NPTL ánh xạ theo tỷ lệ 1:1: Mỗi một luồng POSIX (Pthread) bạn tạo ra trên userspace sẽ tương ứng với đúng một "Task" (thực thể lập lịch) thực sự bên trong Kernel.
Nhờ đó, trên máy tính đa lõi (multi-core):
```text
Lõi CPU số 0 ---> Chạy Luồng A
Lõi CPU số 1 ---> Chạy Luồng B
```
Các luồng trong cùng một tiến trình có thể thực sự chạy song song cùng một lúc.

---

## 4. Định danh luồng: `pthread_t`, TID và PID

Các định danh `pthread_t`, TID và PID phục vụ các lớp API và mục đích quản lý khác nhau, vì vậy không nên đánh đồng chúng.

### 4.1 `pthread_t` (Định danh POSIX)

`pthread_t` là một kiểu dữ liệu do POSIX định nghĩa để quản lý luồng ở tầng ứng dụng.
*   Bạn **không được phép** coi nó là một con số nguyên đơn giản (`int`), vì nó là kiểu dữ liệu có cách biểu diễn phụ thuộc hệ thống (trên nhiều hệ thống Linux, nó là con trỏ).
*   Để lấy ID của luồng đang chạy: `pthread_self()`.
*   Để so sánh 2 luồng: Phải dùng hàm `pthread_equal(t1, t2)`.

### 4.2 Góc nhìn từ Kernel: PID và TID

Bên trong Kernel, mọi đơn vị thực thi được quản lý bởi bộ lập lịch đều gọi là `task` và được cấp một mã `TID` (Thread ID).
Khi một tiến trình khởi tạo, nó có một luồng duy nhất (Main thread).
Khi Main thread tạo ra các luồng con, kiến trúc nhóm sẽ như sau:

```text
             (Tiến trình)  PID / TGID = 4200
                                |
             +------------------+------------------+
             |                  |                  |
      Main Thread (A)     Worker Thread (B)  Worker Thread (C)
      TID = 4200          TID = 4201         TID = 4255
```

> **Đọc sơ đồ:** Nhóm các luồng này được Kernel gộp lại thành một Thread Group. Khái niệm `PID` mà ứng dụng lấy bằng hàm `getpid()` thực chất là Thread Group ID (TGID = 4200). Luồng chính có TID bằng đúng PID (4200). Các luồng con có TID cấp phát độc lập (ví dụ 4201, 4255 - không nhất thiết liên tiếp), nhưng chúng vẫn báo cáo chung một `PID` (4200) để hệ thống nhận diện chúng thuộc về cùng một tiến trình. Để lấy được giá trị TID thực sự, ta phải dùng `gettid()`.

**Tóm lại:**
*   `getpid()` -> Lấy định danh tiến trình (TGID).
*   `gettid()` -> Lấy định danh task hiện tại của Kernel (TID).
*   `pthread_self()` -> Định danh cấu trúc quản lý luồng ở tầng thư viện C.

---

## 5. Các luồng dùng chung gì và có gì riêng?

### 5.1 Phần dùng chung (Shared)

Các luồng như người chung một nhà:
*   Không gian bộ nhớ ảo (Mã lệnh, Dữ liệu toàn cục, Heap, vùng Mmap).
*   Bảng File Descriptor: Nếu Luồng A mở tệp `/dev/ttyS0` và nhận `fd = 5`, Luồng B hoàn toàn có quyền gọi hàm `write(5, ...)` (việc đồng bộ truy cập sẽ thảo luận sau).
*   Thư mục làm việc (`cwd`), Umask.
*   Cách xử lý tín hiệu toàn cục (Signal disposition).

### 5.2 Phần riêng tư (Private)

Các luồng giữ những không gian riêng để vận hành luồng thực thi:
*   Ngăn xếp (Stack): Chứa các khung lời gọi hàm và biến cục bộ.
*   Thanh ghi CPU và Bộ đếm lệnh (Instruction pointer).
*   Tấm khiên tín hiệu (`Signal mask`): Mỗi luồng có một mask chặn tín hiệu riêng biệt (Kết nối Topic 05).
*   Mã lỗi `errno`: Biến này được triển khai theo cơ chế cục bộ cho từng luồng (thread-local), đảm bảo lỗi do I/O của Luồng A sẽ không đè bẹp mã lỗi của Luồng B.

### 5.3 Ngăn xếp riêng nhưng không cách ly vật lý

```text
[ Không gian địa chỉ ảo chung của Tiến trình ]
+-------------------------------+
| Stack của Luồng A             | <--- (Biến cục bộ int x nằm ở đây)
+-------------------------------+
| Stack của Luồng B             | <--- (Luồng B cầm con trỏ trỏ tới x)
+-------------------------------+
| Heap chung                    |
+-------------------------------+
```

Mặc dù được gọi là "riêng", Stack của các luồng vẫn nằm chung trong một không gian địa chỉ ảo. Nếu Luồng A rò rỉ địa chỉ con trỏ của biến `x` sang cho Luồng B, Luồng B hoàn toàn có thể truy cập `x`.
Rủi ro: Việc truyền con trỏ tới biến trên stack đòi hỏi sự đảm bảo về vòng đời (lifetime). Nếu Luồng A kết thúc hàm, vùng Stack A bị thu hồi, con trỏ của Luồng B sẽ trỏ vào vùng nhớ không hợp lệ, dẫn đến hành vi không xác định (undefined behavior).

---

## 6. `pthread_create()`: tạo một luồng mới

### 6.1 Mô hình `pthread_create()`

Khác với `fork()` nhân bản tiến trình, `pthread_create()` yêu cầu bạn chỉ định rõ một **hàm C** (start routine) để luồng mới bắt đầu chạy từ đó.

```text
[ Luồng gọi lệnh (Creator) ]
             |
      pthread_create(&thread_id, NULL, my_worker_func, &data)
             |
             +-----------------------+
             |                       |
             v                       v
[ Vẫn tiếp tục chạy ]       [ Luồng Mới (New Thread) ]
                            Bắt đầu thực thi my_worker_func(&data)
```

Luồng mới sẽ thừa kế một bản sao `signal mask` của luồng gọi nó, sau đó tự điều chỉnh mask riêng của mình.

### 6.2 Thứ tự thực thi không được bảo đảm

Sau lệnh `pthread_create()`, **không có bất kỳ cam kết nào** về việc luồng tạo (creator) hay luồng mới sẽ được Scheduler cấp quyền chạy tiếp trước. Không nên viết logic chương trình dựa trên giả định rằng "luồng tạo sẽ chạy thêm vài dòng code trước khi luồng mới kịp khởi động".

---

## 7. Vòng đời và cách một luồng kết thúc

### 7.1 Vòng đời ở mức khái niệm

```text
[ Created (Được tạo) ]
           |
           v
  (Đưa vào hàng đợi)
           |
           v
[ Runnable (Sẵn sàng) ] <-------+
           |                    |
     (Scheduler chọn)           | (Bị ngắt / Chờ I/O xong)
           v                    |
 [ Running (Đang chạy) ] -------+
           |                    | (Chờ Mutex, I/O)
  (Return / pthread_exit)       |
           v                    v
[ Terminated (Đã kết thúc) ] [ Blocked/Sleeping (Ngủ chờ) ]
```
> **Đọc sơ đồ:** Luồng liên tục luân phiên giữa trạng thái chạy `Running`, nhường CPU để chờ đến lượt ở `Runnable`, hoặc chủ động ngủ `Blocked` khi chờ đợi dữ liệu I/O hay Khóa Mutex. Khi hàm thực thi chính chạy đến lệnh `return` (hoặc gọi `pthread_exit()`), luồng rời khỏi chu kỳ lập lịch và chuyển sang trạng thái `Terminated`. Vòng đời của tài nguyên quản lý luồng này sau đó sẽ phụ thuộc vào thiết lập Joinable/Detached.

### 7.2 Lệnh `pthread_exit()`

Lệnh `pthread_exit(value)` kết thúc riêng rẽ luồng đang gọi nó; các luồng khác trong cùng tiến trình vẫn tiếp tục hoạt động. Việc gọi `return value;` từ hàm khởi tạo (start routine) cũng có tác dụng tương tự.

### 7.3 Khác biệt với `exit()`

*   `pthread_exit()`: Kết thúc một luồng.
*   `exit()` (hoặc `return` từ hàm `main()`): Kết thúc **toàn bộ tiến trình**, vì vậy các luồng còn lại trong tiến trình cũng kết thúc.

---

## 8. Luồng joinable và detached

Khi một luồng hoàn tất (`Terminated`), tài nguyên quản lý của nó cần được hệ thống dọn dẹp. Pthreads chia cách thức dọn dẹp thành hai loại: Joinable và Detached.

### 8.1 Luồng `joinable` (Mặc định)

Luồng được tạo ra mặc định ở trạng thái `Joinable`. Nghĩa là khi luồng chết đi, hệ thống vẫn giữ lại thông tin (trạng thái kết thúc) để chờ một luồng khác tới thu nhận.

```text
[ Luồng Đích (Target Thread) ]
      |
 (Terminated)
      |
      | (Giữ lại kết quả trả về)
      v
[ Một Luồng Khác gọi pthread_join() ] ---> (Có thể bị Block chờ nếu luồng đích chưa kết thúc)
      |
      v
[ Nhận kết quả. Tài nguyên quản lý luồng đích được thu dọn hoàn toàn (Reclaimed) ]
```
> Pthreads không có quan hệ cha/con theo kiểu PPID của tiến trình. Bất kỳ luồng nào trong cùng tiến trình cũng có thể gọi `pthread_join()` để thu hồi luồng khác. Nếu bạn tạo luồng Joinable mà quên gọi `join()`, ứng dụng sẽ tích tụ các thông tin không được thu hồi, dẫn tới rò rỉ tài nguyên (resource leak).

### 8.2 Luồng `detached` (Tự thu hồi)

Nếu ứng dụng không quan tâm đến kết quả trả về của một luồng, bạn có thể thiết lập nó là Detached (gọi `pthread_detach()` hoặc truyền thuộc tính lúc tạo).

```text
[ Luồng Đích (Detached) ]
      |
 (Terminated)
      |
      v
[ Hệ thống tự động thu dọn toàn bộ tài nguyên, không cần ai gọi join() ]
```

> **Hiểu lầm phổ biến:** Từ `Detached` (tách rời) ĐƠN THUẦN CHỈ ĐỊNH NGHĨA chính sách quản lý tài nguyên sau khi kết thúc. Nó KHÔNG CÓ NGHĨA là luồng đó chạy ngầm (background daemon), cũng không làm thay đổi đặc quyền, ưu tiên lập lịch hay ngăn cản nó chạy song song với các luồng khác.

---

## 9. Thuộc tính, ngăn xếp và chi phí của một luồng

Đa luồng không miễn phí. Mỗi luồng tạo ra đòi hỏi tài nguyên hệ thống hữu hình.

### 9.1 Đối tượng Thuộc tính `pthread_attr_t`

Là đối tượng cấu hình được dùng tại thời điểm gọi `pthread_create()`. Nó cho phép tinh chỉnh trạng thái (Joinable/Detached), thuộc tính lập lịch, kích thước ngăn xếp và vùng bảo vệ (guard size).

### 9.2 Chi phí Ngăn xếp (Stack)

Tiến trình tạo bao nhiêu luồng thì phải tạo bấy nhiêu bộ Ngăn xếp:
```text
N threads ===> N vùng nhớ Stack riêng biệt
```
Kích thước ngăn xếp mặc định phụ thuộc vào kiến trúc và cấu hình hệ thống (glibc, giới hạn `RLIMIT_STACK`). Việc gán một ngăn xếp quá lớn sẽ làm tăng mạnh không gian địa chỉ được dự trữ (address-space reservation), mặc dù nó không ép hệ thống nạp toàn bộ số trang đó vào RAM vật lý (resident physical RAM) ngay lập tức. Tuy nhiên, trên hệ thống nhúng (Embedded) hạn chế RAM, bạn cần đo lường và dùng `pthread_attr_setstacksize()` để cấu hình kích thước phù hợp; thu nhỏ tuỳ tiện có thể gây tràn ngăn xếp (Stack overflow).

### 9.3 Vùng bảo vệ (Guard region)

Pthreads có thể bố trí một vùng nhớ đệm `guard region/page` sát dưới đáy ngăn xếp. Mục đích là để ngăn chặn một số trường hợp rò rỉ vùng nhớ âm thầm do tràn ngăn xếp; nếu luồng ghi lố vào vùng này, chương trình sẽ phát sinh lỗi phân đoạn (fault) thay vì lặng lẽ ghi đè lên ánh xạ bộ nhớ bên cạnh.

---

## 10. `concurrency` và `parallelism`

Hai khái niệm cốt lõi của khoa học máy tính mà mọi lập trình viên đều phải phân định. Nó không loại trừ lẫn nhau, một hệ thống đa lõi có thể vừa cung cấp tính đồng thời, vừa hỗ trợ tính song song.

### 10.1 Concurrency (Đồng thời)

Nhiều luồng có khoảng thời gian sống hoặc tiến trình công việc chồng lấp lên nhau.

**(Chạy trên 1 lõi CPU duy nhất)**
```text
Thời gian --->
Luồng A:  [==X==]          [====]
Luồng B:         [===]
Luồng C:              [==]
```
> Scheduler luân phiên thực thi A, B, C. Các luồng có thể tạo cảm giác chạy đồng thời dù tại một thời điểm một lõi CPU chỉ thực thi một luồng.

### 10.2 Parallelism (Song song)

Nhiều luồng thực sự (physically) được thực thi đồng thời trên các tài nguyên tính toán khác nhau.

**(Chạy trên 3 lõi CPU riêng biệt)**
```text
Thời gian --->
CPU Lõi 0 (Luồng A):  [========]
CPU Lõi 1 (Luồng B):  [========]
CPU Lõi 2 (Luồng C):  [========]
```

### 10.3 Tại sao tác vụ I/O lại hợp với Concurrency?

Ngay cả trên hệ thống đơn lõi, đa luồng vẫn hiệu quả cho tác vụ I/O (mạng, đọc ổ đĩa). Khi Luồng A bị chặn (sleep) chờ dữ liệu mạng, Scheduler sẽ lập tức cấp CPU cho Luồng B để thực hiện tính toán.

### 10.4 Tác vụ CPU-Bound (Nặng tính toán)

Tạo thêm luồng không đồng nghĩa với việc tạo thêm lõi CPU. Với các tác vụ nặng tính toán (không có quãng nghỉ I/O), việc tạo 100 luồng trên một máy chỉ có 2 lõi sẽ làm CPU tiêu tốn một lượng lớn thời gian chỉ để thực hiện việc `context switch`, làm suy giảm hiệu suất tổng thể.

---

## 11. Vì sao dùng chung bộ nhớ dẫn tới `race condition`?

`Race condition` (Điều kiện tương tranh) phát sinh khi tính đúng đắn của chương trình phụ thuộc vào chuỗi thời điểm và thứ tự thực thi (timing/order) của các luồng.
Dạng nguy hiểm nhất là `data race`, xảy ra khi hai hay nhiều luồng có những thao tác truy cập đồng thời vào một bộ nhớ chia sẻ, trong đó có ít nhất một thao tác ghi, mà không sử dụng bất kỳ cơ chế đồng bộ (synchronization) hợp lý nào. Việc này theo chuẩn ngôn ngữ (C/C++) sẽ dẫn đến hành vi không xác định (Undefined Behavior).

### 11.1 Ví dụ: tăng biến đếm

Mã nguồn C: `counter++`

Mô hình thao tác ở mức khái niệm (không khẳng định trình biên dịch sẽ sinh chính xác 3 lệnh):
1.  Đọc giá trị từ bộ nhớ.
2.  Tăng giá trị đó lên 1.
3.  Ghi lại vào bộ nhớ.

**Sự xen kẽ tai hại:**
Giả sử `counter = 10`.
```text
[ Luồng A ]                          [ Luồng B ]
1. Đọc counter (thấy 10)
                                     1. Đọc counter (cũng thấy 10)
2. Cộng 10 + 1 = 11
                                     2. Cộng 10 + 1 = 11
3. Ghi số 11 về bộ nhớ
                                     3. Ghi số 11 về bộ nhớ
```
> **Kết quả:** Ta có 2 luồng cùng thực hiện lệnh tăng biến đếm, kỳ vọng kết quả là 12. Nhưng do sự chồng lấp truy cập, giá trị cuối cùng lưu lại là 11. Dữ liệu đã bị sai lệch hoàn toàn.

### 11.2 Các giải pháp đồng bộ (Sẽ học ở Topic 07)

Các truy cập xung đột đồng thời (concurrent conflicting accesses) vào các trạng thái dùng chung bắt buộc phải có một chiến lược đồng bộ. Tuy nhiên, việc chia sẻ biến mà không dùng khóa (lock) **không phải lúc nào cũng gây lỗi**. Các dữ liệu bất biến (Read-only data), thao tác nguyên tử (Atomics), hay thiết kế truyền tin nhắn (Message passing) hoàn toàn hợp lệ. Khóa Mutex chỉ là một trong những giải pháp đồng bộ cơ bản nhất sẽ được giới thiệu ở Topic 07.

---

## 12. Quan sát luồng trên Linux

Không nên chỉ dựa vào các dòng log `printf`; hãy dùng thêm các công cụ quan sát của Kernel để xác thực.

### 12.1 Quan sát thư mục `/proc/<pid>/task/`

Như đã học ở phần định danh (Mục 4), nếu tiến trình của bạn có PID = 4200, bạn có thể kiểm tra:
```text
/proc/4200/task/
```
Thư mục này cho phép quan sát chi tiết từng Linux task (TID) đang chạy trong tiến trình đó (vd: `4200/`, `4201/`, `4202/`). Bằng cách phân tích, bạn có thể xác nhận chương trình thật sự sinh ra bao nhiêu luồng, và luồng TID nào đang ngủ (sleeping), đang chạy hay bị kẹt.
Bên cạnh đó, file `/proc/thread-self` cung cấp một lối đi tắt để biểu diễn thông tin trạng thái cho "luồng hiện tại" đang truy cập nó.

### 12.2 Công cụ `ps` và `top`

*   Lệnh `ps -eLf` hiển thị chi tiết thông tin lập lịch của mọi luồng (LWP - Light Weight Process / TID).
*   Trong `top`, nhấn phím `H` để bật chế độ theo dõi từng luồng. Bạn có thể phát hiện việc CPU 100% chỉ thuộc về 1 luồng duy nhất bị kẹt, trong khi các luồng khác đang chờ hoặc ngủ.

### 12.3 Đặt tên cho Luồng

Lập trình viên chuyên nghiệp dùng hàm đặt tên cho luồng (vd: `Sensor-Thrd`, `Net-Thrd`). Tên này sẽ hiển thị lên công cụ `top`/`htop`, biến việc gỡ lỗi trở nên trực quan. Tuy nhiên, tên chỉ để con người và công cụ debug đọc, không dùng nó thay thế cho `pthread_t` hay TID trong các API hệ thống.

---

## 13. Tư duy gỡ lỗi đa luồng

Khi ứng dụng đa luồng gặp sự cố, hãy chia lỗi thành các nhóm chuyên biệt thay vì vội vàng suy luận "luồng bị treo".

### 13.1 Quy trình phân lớp chuẩn

```text
1. Vòng đời       -> Hàm tạo luồng có thành công không? Main có thoát quá sớm không?
          |
2. Nhận diện      -> Đang phân tích log dựa trên pthread_t, PID hay TID?
          |
3. Thu hồi        -> Luồng là Joinable hay Detached? Có gây rò rỉ (leak) không?
          |
4. Đồng bộ        -> Có rủi ro Data race khi dùng chung biến không? Con trỏ Stack truyền vào còn sống không?
```
Kiểm tra theo chuỗi này giúp tránh việc tốn thời gian gỡ lỗi Mutex trong khi luồng thậm chí chưa bao giờ được tạo.

### 13.2 Vì sao luồng mới chưa chạy?

*   Lỗi rất cơ bản: Hàm `main()` kết thúc tiến trình quá sớm trước khi luồng mới kịp khởi động.
*   Luồng mới bị khóa ngay tại lệnh I/O (ví dụ mạng) đầu tiên.
*   Thứ tự lập lịch không tuân theo suy đoán chủ quan của bạn.

### 13.3 Timing và ảnh hưởng của logging

Thêm lệnh `printf` hay log có thể làm lỗi tự nhiên biến mất. Việc thêm log làm thay đổi thời gian thực thi (timing), khiến hai luồng lệch pha nhau và né được điểm tương tranh dữ liệu. Việc lỗi tạm thời biến mất không chứng minh rằng mã nguồn đã an toàn.

---

## 14. Liên hệ với Embedded Linux

Trên các hệ thống Nhúng (Embedded Linux), việc lựa chọn kiến trúc xử lý tác vụ là một quyết định kỹ thuật sâu sắc.

### 14.1 Phân chia công việc linh hoạt

Một ứng dụng IoT thường thiết kế các luồng chuyên trách: `Sensor thread`, `Processing thread`, `Network thread`, và `Logging thread`. Vì mỗi tiến trình có thể độc lập chịu độ trễ (delay) từ thiết bị và mạng, việc tách chúng giúp hệ thống duy trì được tính phản hồi.

### 14.2 Dùng chung File Descriptor và Ownership

Các luồng trong hệ thống chia sẻ chung Bảng tệp (File Descriptor Table).
*   Nếu Luồng A mở UART `/dev/ttyS0` thành `fd 5`, Luồng B cũng có thể gọi hàm ghi vào `fd 5` đó.
*   Tuy nhiên, phải xây dựng thiết kế quyền sở hữu (ownership) rõ ràng: Luồng nào chịu trách nhiệm cấu hình (open/ioctl), luồng nào nắm quyền đóng tệp (close), và luồng nào chịu trách nhiệm đọc/ghi, để tránh tình trạng tranh chấp cấu hình thiết bị.

### 14.3 Luồng hay Tiến trình?

Ranh giới thiết kế hệ thống Nhúng:
*   **Đa Luồng (Threads):** Lựa chọn hàng đầu khi các tác vụ đòi hỏi chia sẻ dữ liệu khổng lồ với độ trễ tối thiểu (chạy trong cùng một miền tài nguyên).
*   **Đa Tiến trình (Processes):** Được dùng để đảm bảo cách ly lỗi (fault isolation), quản lý cấp quyền (privileges) và khả năng khởi động lại các mô-đun độc lập. Một hệ thống Embedded hoàn chỉnh thường là sự kết hợp khéo léo giữa cả hai mô hình này.

---

## 15. Tổng kết

Có thể tóm tắt chương bằng các mô hình sau:

### 15.1 Kiến trúc tài nguyên

```text
                         TIẾN TRÌNH
                             |
          +------------------+------------------+
          |                                     |
          v                                     v
   Tài Nguyên Dùng Chung (Shared)             Luồng (Threads)
   ------------------------------             -------
   Không gian bộ nhớ ảo                       Luồng A
   Heap / Dữ liệu toàn cục                      |- Stack riêng A
   Bảng File Descriptor                         |- Thanh ghi CPU A
   Thư mục làm việc (cwd)                       |- TID / pthread_t A
                                                `- Signal mask A

                                              Luồng B
                                                |- Stack riêng B
                                                |- Thanh ghi CPU B
                                                |- TID / pthread_t B
                                                `- Signal mask B
```

> **Đọc sơ đồ:** Tiến trình cung cấp không gian tài nguyên dùng chung, còn mỗi luồng có một ngữ cảnh thực thi (`execution context`) riêng bên trong tiến trình đó. Vì các luồng cùng truy cập một không gian địa chỉ, việc trao đổi dữ liệu thuận tiện hơn, nhưng dữ liệu dùng chung cần có chiến lược đồng bộ hóa (`synchronization`) phù hợp. Đây là một khác biệt quan trọng giữa đa luồng và đa tiến trình.

### 15.2 Vòng đời của một Pthread

```text
      pthread_create()  (Tạo mới)
             |
             v
   [ Trạng thái Chạy (Runnable/Running/Blocked) ]
             |
             v
      return / pthread_exit() (Hàm thực thi kết thúc)
             |
             v
        [ TERMINATED ]
       /               (Joinable)        (Detached)
     |                 |
pthread_join()    Tự động thu hồi RAM
```

> Thiết kế đa luồng cần quản lý vòng đời rõ ràng. Việc một luồng là `Joinable` (cần `pthread_join()`) hay `Detached` quyết định cách tài nguyên của luồng được thu hồi. Quản lý sai trạng thái này có thể dẫn tới việc giữ tài nguyên lâu hơn cần thiết.

### 15.3 Các nguyên lý cốt lõi
1. Luồng là một dòng thực thi nằm bên trong một tiến trình.
2. Các luồng cùng tiến trình chia sẻ chung bộ nhớ ảo và tài nguyên File Descriptor.
3. Mỗi luồng bảo toàn Ngăn xếp (Stack), mã lỗi `errno` và ngữ cảnh CPU riêng biệt.
4. `Pthreads` là bộ giao diện POSIX; Linux/glibc hiện đại triển khai nó bằng kiến trúc `NPTL`.
5. `pthread_t` (Mã ứng dụng POSIX) hoàn toàn khác biệt với `TID` (Mã tác vụ của Kernel).
6. Hàm `pthread_create()` không tạo ra tiến trình mới, và không cam kết thứ tự luồng nào sẽ được chạy trước.
7. `pthread_exit()` kết thúc luồng đang gọi; `exit()` kết thúc toàn bộ tiến trình.
8. Sự khác biệt giữa Joinable và Detached nằm ở cách thu hồi tài nguyên của luồng.
9. Đa luồng tạo ra khả năng Chạy đồng thời (Concurrency), trong khi việc Chạy song song (Parallelism) đòi hỏi phân bổ luồng trên nhiều lõi phần cứng.
10. Truy cập đồng thời thiếu đồng bộ vào dữ liệu chia sẻ có thể gây `Data Race` và Hành vi không xác định. Cơ chế khóa sẽ được khai mở ở Topic 07.

---

## 16. Tài liệu tham khảo

Phần này liệt kê nguồn chuẩn về pthread và luồng trên Linux.

### POSIX.1-2024 / The Open Group

- https://pubs.opengroup.org/onlinepubs/9799919799/
- `pthread_create()`: https://pubs.opengroup.org/onlinepubs/9799919799/functions/pthread_create.html
- `pthread_join()`: https://pubs.opengroup.org/onlinepubs/9799919799/functions/pthread_join.html
- `pthread_detach()`: https://pubs.opengroup.org/onlinepubs/9799919799/functions/pthread_detach.html
- `pthread_exit()`: https://pubs.opengroup.org/onlinepubs/9799919799/functions/pthread_exit.html

### Linux man-pages

- `pthreads(7)`: https://man7.org/linux/man-pages/man7/pthreads.7.html
- `pthread_create(3)`: https://man7.org/linux/man-pages/man3/pthread_create.3.html
- `pthread_self(3)`: https://man7.org/linux/man-pages/man3/pthread_self.3.html
- `pthread_equal(3)`: https://man7.org/linux/man-pages/man3/pthread_equal.3.html
- `gettid(2)`: https://man7.org/linux/man-pages/man2/gettid.2.html
- `nptl(7)`: https://man7.org/linux/man-pages/man7/nptl.7.html
- `pthread_attr_setstacksize(3)`: https://man7.org/linux/man-pages/man3/pthread_attr_setstacksize.3.html
- `proc_pid_task(5)`: https://man7.org/linux/man-pages/man5/proc_pid_task.5.html

> **Điều hướng:** [← Chủ đề 5 — Signal](README-topic-05.md) · [Chủ đề 7 — Đồng bộ luồng →](README-topic-07.md)
