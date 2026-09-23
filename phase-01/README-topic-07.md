# Chủ đề 7 — Đồng bộ luồng trong Linux

> **Mục tiêu:** Hiểu vì sao nhiều luồng dùng chung dữ liệu lại cần đồng bộ. Nắm đúng bản chất và vai trò của các công cụ cốt lõi: `mutex`, `condition variable`, `semaphore`, `barrier`, đồng thời nhận diện được các rủi ro hệ thống như `race condition`, `deadlock`, `starvation` và `priority inversion`.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Giữ nguyên các thuật ngữ hệ thống chuẩn để thuận tiện tra cứu tài liệu quốc tế: `race condition`, `data race`, `critical section`, `atomicity`, `memory visibility`, `mutex`, `condition variable`, `predicate`, `semaphore`, `barrier`, `deadlock`, `starvation`, `livelock`, `lock ordering`, `contention`, `priority inversion` và tên các API Pthreads.
>
> **Phạm vi:** Tập trung xây dựng mô hình tư duy về `race condition`, `critical section`, khái niệm `atomicity`, `memory visibility` giữa các luồng. Trình bày các công cụ: `mutex`, `condition variable`, `semaphore`, mô hình `producer–consumer` và `barrier`. Nhận diện các vấn đề kiến trúc: `deadlock`, `starvation`, `livelock`, `lock ordering`, `lock granularity`, `contention` và `priority inversion` ở mức tổng quan.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để chuẩn bị tư duy trước khi viết code đa luồng thực tế. Các kỹ thuật đồng bộ hóa không chặn (lock-free), cơ chế RCU, raw `futex`, `spinlock` cấp độ Kernel hay mô hình Atomics của C/C++ nằm ngoài phạm vi chương này.

Đồng bộ hóa (Synchronization) chỉ trở nên dễ hiểu khi bạn xuất phát từ **một trạng thái chia sẻ (shared state) cần được bảo vệ để luôn giữ tính đúng đắn**. Khóa `mutex` không tự động "khóa một biến", nó chỉ là thỏa thuận để bảo vệ một giao thức truy cập dữ liệu. `Condition Variable` không tự thân nó chứa bất kỳ điều kiện nào, nó chỉ cung cấp giải pháp cho luồng chờ đợi một mốc dữ liệu (predicate) thay đổi. `Semaphore` lại là công cụ phù hợp cho việc đếm tài nguyên.

Thay vì liệt kê các API Pthreads rời rạc, chương này đi từ nguồn gốc của vấn đề (`race condition`, `critical section`), sau đó mới cung cấp công cụ giải quyết (Mutex, Condition Variable, Semaphore, Barrier) và cuối cùng là phân tích các vấn đề tiềm ẩn nếu dùng công cụ sai cách (`deadlock`, `starvation`).

---

## Mục lục

- [1. Vì sao cần đồng bộ luồng?](#1-vì-sao-cần-đồng-bộ-luồng)
- [2. `race condition`, `data race` và `critical section`](#2-race-condition-data-race-và-critical-section)
- [3. Đồng bộ còn liên quan tới `memory visibility`](#3-đồng-bộ-còn-liên-quan-tới-memory-visibility)
- [4. Mutex: chỉ một luồng được sở hữu vùng bảo vệ](#4-mutex-chỉ-một-luồng-được-sở-hữu-vùng-bảo-vệ)
- [5. Vòng đời và thao tác của Mutex](#5-vòng-đời-và-thao-tác-của-mutex)
- [6. Các loại Mutex cơ bản](#6-các-loại-mutex-cơ-bản)
- [7. `Condition variable`: ngủ để chờ trạng thái thay đổi](#7-condition-variable-ngủ-để-chờ-trạng-thái-thay-đổi)
- [8. Predicate, spurious wakeup và lost wakeup](#8-predicate-spurious-wakeup-và-lost-wakeup)
- [9. `signal`, `broadcast` và chờ có thời hạn](#9-signal-broadcast-và-chờ-có-thời-hạn)
- [10. `Semaphore`: bộ đếm tài nguyên hoặc token](#10-semaphore-bộ-đếm-tài-nguyên-hoặc-token)
- [11. Khi nào dùng `mutex`, `condition variable` hay `semaphore`?](#11-khi-nào-dùng-mutex-condition-variable-hay-semaphore)
- [12. Mô hình `producer–consumer`](#12-mô-hình-producerconsumer)
- [13. `Barrier`: các luồng chờ nhau ở cuối một giai đoạn](#13-barrier-các-luồng-chờ-nhau-ở-cuối-giai-đoạn)
- [14. `Deadlock`](#14-deadlock)
- [15. `Starvation` và `livelock`](#15-starvation-và-livelock)
- [16. `Lock ordering`, `critical-section granularity` và `contention`](#16-lock-ordering-critical-section-granularity-và-contention)
- [17. `Priority inversion` và `priority inheritance`](#17-priority-inversion-và-priority-inheritance)
- [18. Tư duy gỡ lỗi đồng bộ](#18-tư-duy-gỡ-lỗi-đồng-bộ)
- [19. Liên hệ với Embedded Linux](#19-liên-hệ-với-embedded-linux)
- [20. Tổng kết](#20-tổng-kết)
- [21. Tài liệu tham khảo](#21-tài-liệu-tham-khảo)

---

## 1. Vì sao cần đồng bộ luồng?

Khi nhiều luồng cùng đọc và sửa một dữ liệu chung, kết quả cuối cùng có thể sai lệch nghiêm trọng nếu thứ tự truy cập không được kiểm soát. Đồng bộ (`synchronization`) là cơ chế tạo ra các quy tắc để bắt buộc các luồng phải phối hợp với nhau một cách an toàn.

### 1.1 Vấn đề bắt nguồn từ dữ liệu chia sẻ có thể thay đổi (Mutable Shared State)

```text
[ Luồng A ] --------+
                    |
                    v
          (Dữ liệu dùng chung)
                    ^
                    |
[ Luồng B ] --------+
```

Nếu dữ liệu là chỉ đọc (Read-only), mọi luồng đều có thể lấy dữ liệu cùng lúc mà không gây ra bất kỳ vấn đề nào.

Nguy hiểm xuất hiện khi dữ liệu đó **có thể bị thay đổi (mutable)**. Các thao tác đọc, sửa và ghi của nhiều luồng có thể bị cắt ngang và đan xen lẫn nhau. Lúc này, tính đúng đắn của chương trình phụ thuộc vào thứ tự chạy ngẫu nhiên của bộ lập lịch (Scheduler).

### 1.2 Đồng bộ không chỉ là “khóa một biến đơn lẻ”

Nhiều người lầm tưởng đồng bộ là áp một khóa lên một biến số nguyên `count`. Thực tế, thứ chúng ta cần bảo vệ thường lớn hơn: đó là **các ràng buộc nhất quán (`invariant`) của trạng thái** — tức những quan hệ logic giữa các trường dữ liệu phải được duy trì đúng khi trạng thái được các luồng khác quan sát.

Giả sử bạn có một cấu trúc hàng đợi (Queue):
```c
struct Queue {
    int head;
    int tail;
    int size;
    int buffer[10];
};
```
Khi Luồng A thêm dữ liệu vào `buffer`, nó cũng phải cập nhật `tail` và `size`. Nếu trong khoảnh khắc Luồng A mới cập nhật `buffer` xong nhưng chưa kịp sửa `size`, Luồng B nhảy vào đọc, Luồng B sẽ nhận được một trạng thái hàng đợi sai lệch, vi phạm **ràng buộc nhất quán (`invariant`)** của hàng đợi. Do đó, đối tượng cần bảo vệ là **toàn bộ khối trạng thái logic**, chứ không phải từng biến đơn lẻ.

### 1.3 Ba câu hỏi quan trọng trước khi chọn cơ chế đồng bộ

Trước khi thiết kế đồng bộ, cần xác định:
1.  **Dữ liệu/trạng thái nào** đang được dùng chung giữa các luồng?
2.  **Những thao tác nào (đoạn code nào)** không được phép chạy chồng lấp lên nhau?
3.  Luồng có cần phải **chờ đợi một điều kiện (predicate) cụ thể nào đó** mới được đi tiếp hay không?

Trả lời được 3 câu hỏi này, bạn mới có thể đưa ra quyết định chính xác là nên dùng `Mutex`, `Condition Variable` hay `Semaphore`.

---

## 2. `race condition`, `data race` và `critical section`

Đây là ba khái niệm cốt lõi để mô tả và khoanh vùng các vấn đề tranh chấp dữ liệu.

### 2.1 `race condition` (Điều kiện tương tranh)

`Race condition` xảy ra khi tính đúng đắn của hệ thống bị phụ thuộc vào thời điểm (timing) và thứ tự chạy đan xen của các luồng.

**(Ví dụ: Hai luồng cùng rút tiền)**
Giả sử Tài khoản đang có `balance = 100`.
```text
  [ Luồng A (Rút 10) ]                  [ Luồng B (Rút 20) ]
1. Đọc balance (thấy 100)
                                      1. Đọc balance (cũng thấy 100)
2. Tính: 100 - 10 = 90
                                      2. Tính: 100 - 20 = 80
3. Ghi số 90 lại vào balance
                                      3. Ghi số 80 lại vào balance
```

> **Kết quả:** Luồng B lưu chậm hơn một chút, đè bẹp kết quả của Luồng A. Tài khoản còn 80 thay vì phải là 70. Nếu thứ tự đảo lại, kết quả lại ra 90. Sự không chắc chắn này chính là `Race condition`.

### 2.2 `data race` là khái niệm chặt chẽ hơn ở cấp mô hình bộ nhớ

`Data race` xảy ra khi có từ hai luồng trở lên cùng truy cập đồng thời vào **cùng một vị trí bộ nhớ**, trong đó có ít nhất một luồng thực hiện thao tác **ghi (`write`)**, và các truy cập đó không được phối hợp bằng cơ chế đồng bộ phù hợp theo mô hình bộ nhớ của ngôn ngữ.

Ví dụ đơn giản:

```c
int count = 0;

// Thread A
count++;

// Thread B
count++;
```

Thoạt nhìn, ta có thể nghĩ hai phép `count++` chỉ đơn giản chạy lần lượt và kết quả cuối cùng sẽ là `2`. Nhưng về mặt khái niệm, `count++` gồm nhiều bước:

```text
đọc count
    ↓
cộng thêm 1
    ↓
ghi lại count
```

Hai luồng có thể xen kẽ như sau:

```text
count = 0

Thread A                     Thread B
   |                            |
   | đọc count = 0              |
   |                            | đọc count = 0
   | tính 0 + 1                 |
   |                            | tính 0 + 1
   | ghi count = 1              |
   |                            | ghi count = 1
   v                            v

             count = 1
```

Trong trường hợp này:

```text
Thread A ── đọc/ghi ──┐
                      ├── cùng một vị trí nhớ: count
Thread B ── đọc/ghi ──┘

Có ít nhất một thao tác ghi: Có
Có đồng bộ thích hợp:          Không
```

Do đó đây là một `data race`.

Điểm quan trọng là trong C/C++, `data race` trên dữ liệu thông thường dẫn tới **Undefined Behavior (UB)**. Điều này có nghĩa là không thể chỉ suy luận rằng chương trình "cùng lắm tính sai một giá trị". Compiler được phép tối ưu dựa trên các quy tắc của mô hình bộ nhớ; khi chương trình vi phạm các quy tắc đó, hành vi không còn được ngôn ngữ đảm bảo.

Có thể phân biệt ngắn gọn:

```text
Data race
= nhiều luồng truy cập cùng vị trí nhớ
+ có ít nhất một bên ghi
+ thiếu synchronization phù hợp

Race condition
= tính đúng đắn của chương trình phụ thuộc vào
  timing hoặc thứ tự xen kẽ giữa các thao tác
```

`Data race` và `race condition` thường xuất hiện cùng nhau, nhưng không phải là hai khái niệm đồng nghĩa.

### 2.3 Race Condition ở mức logic giao thức (Protocol)

Ngay cả khi từng lần đọc/ghi đã được đặt dưới Mutex, chương trình vẫn có thể xảy ra `race condition` nếu **ranh giới của thao tác logic được bảo vệ quá hẹp**.

Ví dụ, Luồng A cần kiểm tra xem tài nguyên `X` còn trống hay không rồi mới sử dụng nó:

```text
Luồng A:
  lock(M)
  kiểm tra X còn trống
  unlock(M)

  ... khoảng thời gian không giữ khóa ...

  lock(M)
  sử dụng X dựa trên kết quả kiểm tra trước đó
  unlock(M)
```

Thoạt nhìn, cả thao tác kiểm tra lẫn thao tác sử dụng đều có Mutex. Tuy nhiên, sau khi A nhả khóa lần thứ nhất, kết quả kiểm tra `X còn trống` không còn được đảm bảo giữ nguyên.

Một Luồng B có thể chen vào:

```text
Thread A                              Thread B
   |                                    |
   | lock(M)                            |
   | thấy X = FREE                      |
   | unlock(M)                          |
   |                                    |
   |                                    | lock(M)
   |                                    | sử dụng / chiếm X
   |                                    | unlock(M)
   |                                    |
   | lock(M)                            |
   | sử dụng X dựa trên                 |
   | thông tin cũ: X = FREE             |
   |                                    |
```

Sai lầm ở đây không nằm ở một lần đọc hay ghi riêng lẻ, mà nằm ở **mối quan hệ logic giữa `CHECK` và `USE`**:

```text
CHECK trạng thái
      ↓
quyết định dựa trên trạng thái đó
      ↓
USE / cập nhật tài nguyên
```

Nếu hành động phía sau phụ thuộc vào kết quả kiểm tra phía trước, hai bước đó thường phải được xem như **một giao dịch logic (`transaction`) không được phép bị thread khác chen vào giữa**.

Cách thiết kế phù hợp hơn:

```text
lock(M)

    kiểm tra X

    nếu X phù hợp:
        sử dụng / cập nhật X

unlock(M)
```

Như vậy, trong suốt thời gian từ lúc kiểm tra đến lúc hành động, thread khác muốn thao tác xung đột lên `X` bằng cùng Mutex phải chờ.

Điểm cần nhớ:

> **Không có `data race` chưa có nghĩa là không có `race condition`.** Từng truy cập bộ nhớ có thể đã được khóa đúng, nhưng logic tổng thể vẫn sai nếu transaction bị chia nhỏ và thread khác có thể thay đổi trạng thái ở giữa.

### 2.4 Vùng tới hạn (`critical section`)

`Critical section` là **đoạn code thao tác trên shared state mà các thao tác xung đột của thread khác không được phép chạy đồng thời**.

Ví dụ:

```text
[ Luồng A ]
     |
  lock(M)
     |
     v
+-------------------------------+
|       CRITICAL SECTION        |
|  cập nhật shared state        |
+-------------------------------+
     |
  unlock(M)
```

`lock()` và `unlock()` tạo ra ranh giới bảo vệ, nhưng bản thân Mutex **không tự biết nó đang bảo vệ biến hay cấu trúc dữ liệu nào**. Chính protocol của chương trình quy định rằng mọi thread muốn thực hiện thao tác xung đột trên cùng shared state phải sử dụng **cùng một Mutex**.

Ví dụ, nếu cả hai thread đều tuân thủ:

```text
Muốn truy cập balance
        |
        v
     lock(M)
        |
        v
  truy cập balance
        |
        v
    unlock(M)
```

thì `balance` mới thực sự được bảo vệ bởi protocol đó. Nếu một thread khác truy cập `balance` mà bỏ qua `M`, Mutex không thể tự ngăn thread đó lại.

Một `critical section` cũng không nhất thiết chỉ gồm một câu lệnh. Nó phải bao phủ **toàn bộ nhóm thao tác cần giữ tính nhất quán**.

Ví dụ với Queue:

```c
struct Queue {
    int head;
    int tail;
    int size;
    int buffer[10];
};
```

Khi thêm một phần tử, các cập nhật sau có liên quan logic với nhau:

```c
buffer[tail] = value;
tail++;
size++;
```

Nếu thread khác quan sát Queue sau khi `buffer` đã đổi nhưng `tail` và `size` chưa đổi, nó có thể nhìn thấy một trạng thái trung gian không nhất quán. Vì vậy ba thao tác trên nên nằm trong cùng một critical section:

```c
pthread_mutex_lock(&mutex);

buffer[tail] = value;
tail++;
size++;

pthread_mutex_unlock(&mutex);
```

Có thể hình dung quan hệ giữa 2.3 và 2.4 như sau:

```text
2.3 hỏi:
"Toàn bộ thao tác logic nào không được phép bị thread khác chen vào giữa?"

                    ↓

2.4 trả lời:
"Đoạn code đó chính là critical section cần được bảo vệ."
```

Vì vậy, khi xác định `critical section`, không nên chỉ hỏi **"biến nào cần khóa?"**, mà phải hỏi:

> **"Toàn bộ thao tác nào cần được thực hiện như một khối thống nhất để các ràng buộc nhất quán (`invariant`) của shared state được duy trì?"**

---

## 3. Đồng bộ còn liên quan tới `memory visibility`

Sự đồng bộ không chỉ là cấm hai luồng cùng chạy một đoạn code. Nó còn đảm bảo cho một luồng nhìn thấy (visibility) được những dữ liệu mà luồng khác đã thay đổi.

### 3.1 Ghi trước, Đọc sau là chưa đủ nếu thiếu đồng bộ

Trong mã C:
```c
data = 123;
ready = 1;
```
Người đọc dễ nghĩ rằng luồng khác chắc chắn sẽ thấy `data` thay đổi trước `ready`. Tuy nhiên, với kiến trúc CPU hiện đại và Trình biên dịch có thể sắp xếp lại lệnh (reorder) để tối ưu, thứ tự cập nhật bộ nhớ có thể bị đảo lộn. Luồng khác có thể thấy `ready == 1` nhưng `data` vẫn là giá trị cũ.

### 3.2 Khóa Mutex tạo quan hệ đồng bộ bộ nhớ (Memory Synchronization)

```text
 [ Luồng A ]                            [ Luồng B ]

 lock(M)
 cập nhật data
 cập nhật ready
 unlock(M)  -------------------------->  lock(M)
                                            |
                                            v
                                 đọc data và ready (An toàn)
```

Lệnh `pthread_mutex_unlock()` không chỉ là đổi một cờ. Các hàm đồng bộ của POSIX cung cấp ngữ nghĩa đồng bộ bộ nhớ mạnh: Các thay đổi trạng thái được thực hiện bởi Luồng A trước khi `unlock()` sẽ được đồng bộ hóa và đảm bảo Luồng B nhìn thấy toàn bộ, theo đúng thứ tự, sau khi B gọi `lock()` trên cùng một Mutex.

### 3.3 Khái niệm `Atomicity` (Tính nguyên tử) ở mức Giao thức

Trong lập trình đa luồng ở mức ứng dụng, một thao tác được coi là `nguyên tử` (Atomic) ở mức giao thức khi **các luồng khác không quan sát thấy trạng thái trung gian không hợp lệ của thao tác đó**.

Điều này **không có nghĩa là trong lúc một luồng đang thực hiện thao tác thì toàn bộ hệ thống phải dừng lại**. Scheduler vẫn có thể chuyển CPU sang luồng khác, interrupt vẫn có thể xảy ra, và các luồng trên những lõi CPU khác vẫn có thể tiếp tục chạy. Điều được bảo đảm là những luồng cùng tuân thủ một giao thức Mutex sẽ không thể truy cập vào vùng trạng thái đang được bảo vệ cho tới khi luồng đang sở hữu Mutex hoàn tất và `unlock()`.

Ví dụ, khi cập nhật một Queue cần nhiều bước:

```c
pthread_mutex_lock(&mutex);

buffer[tail] = value;
tail++;
size++;

pthread_mutex_unlock(&mutex);
```

Ba câu lệnh cập nhật trên không biến thành một lệnh CPU duy nhất. Tuy nhiên, nếu mọi luồng truy cập Queue đều sử dụng cùng `mutex`, một luồng khác sẽ không thể chen vào giữa để quan sát trạng thái kiểu `buffer` đã cập nhật nhưng `tail` hoặc `size` vẫn còn giá trị cũ. Từ góc nhìn của các luồng tuân thủ giao thức khóa, chúng chỉ quan sát được **trạng thái trước khi cập nhật** hoặc **trạng thái sau khi toàn bộ cập nhật đã hoàn tất**.

Vì vậy, Mutex có thể làm cho **một nhóm nhiều thao tác** trở thành một đơn vị logic nguyên tử ở mức giao thức. Tính nguyên tử này đến từ việc mọi bên cùng tuân thủ đúng ranh giới `lock()` / `unlock()`, chứ không phải vì bên trong `critical section` không còn scheduler, interrupt hay hoạt động của các luồng khác.

---

## 4. Mutex: chỉ một luồng được sở hữu vùng bảo vệ

Mutex (viết tắt của MUTual EXclusion - Loại trừ lẫn nhau) hoạt động như một chìa khóa: tại một thời điểm chỉ một luồng được phép giữ khóa và đi vào vùng bảo vệ.

### 4.1 Mô hình Quyền sở hữu (Ownership)

Khi Mutex ở trạng thái `Locked`, luồng giữ khóa là Chủ sở hữu (Owner) của Mutex đó.
Các luồng khác không được đi vào `critical section` do Mutex này bảo vệ cho tới khi Owner kết thúc quyền sở hữu bằng lệnh `unlock()`. Các luồng khác sẽ phải chờ hoặc nhận thông báo đang bận, tùy thuộc vào API được gọi.

### 4.2 Trạng thái cơ bản

```text
             (Khởi tạo)
                 |
                 v
          [ UNLOCKED (Mở) ] <---------------+
                 |                          |
       Luồng gọi lock()                     | Luồng chủ sở hữu
                 |                          | gọi unlock()
                 v                          |
          [ LOCKED (Bị Khóa) ] -------------+
```

> **Đọc sơ đồ:** Mutex có hai trạng thái cốt lõi: Không có chủ (`Unlocked`), hoặc đang có chủ (`Locked`). Nếu Mutex đang được Luồng A giữ, và Luồng B cũng gọi lệnh `lock()`, Luồng B sẽ phải chờ. Trạng thái Locked mô tả quyền sở hữu chứ không mô tả bản thân dữ liệu.

### 4.3 Khác biệt cốt lõi: Ownership

Quy tắc: **Luồng nào khóa Mutex, Luồng đó phải là người mở Mutex.**
Thiết kế Luồng A gọi `lock()` rồi Luồng B gọi `unlock()` thay là một vi phạm nguyên tắc quyền sở hữu, thường dẫn tới hành vi không xác định (Undefined behavior). Sự sở hữu này phân biệt rõ ràng Mutex với Semaphore.

### 4.4 Mutex không tự bảo vệ dữ liệu

Hệ thống không ghi nhận một quan hệ kiểu "Mutex `M` đang bảo vệ biến `X`". Mutex chỉ kiểm soát những luồng **cùng cố lấy chính Mutex đó**; việc `M` được dùng để bảo vệ `X` là một quy ước (`locking protocol`) do chương trình thiết kế.

Ví dụ, nếu Luồng A truy cập `X` như sau:

```c
pthread_mutex_lock(&m);
X++;
pthread_mutex_unlock(&m);
```

nhưng Luồng B lại ghi trực tiếp vào `X` mà không khóa `m`, thì Luồng B vẫn có thể truy cập `X` trong lúc A đang giữ Mutex. Vì vậy, việc A dùng Mutex **không tự động biến `X` thành dữ liệu được bảo vệ**.

Quy tắc đúng phải là: **mọi đường code thực hiện các truy cập xung đột tới cùng trạng thái chia sẻ đều phải tuân thủ cùng một giao thức khóa**. Chẳng hạn, nếu quy ước rằng `m` bảo vệ `X`, thì cả A, B và mọi luồng khác muốn đọc/ghi `X` theo cách có thể xung đột đều phải lấy `m` trước khi truy cập.

Có thể ghi nhớ: **Mutex không khóa một biến; Mutex thực thi quyền truy cập theo một giao thức mà các luồng cùng tuân thủ.**

---

## 5. Vòng đời và thao tác của Mutex

Mutex phải được khởi tạo, sử dụng và hủy đúng quy trình. Quên unlock sẽ gây tắc nghẽn hệ thống.

### 5.1 Khởi tạo

Trước khi sử dụng, Mutex phải được thiết lập hợp lệ thông qua khởi tạo tĩnh (`PTHREAD_MUTEX_INITIALIZER`) hoặc hàm khởi tạo động (`pthread_mutex_init()`).

### 5.2 `pthread_mutex_lock()`

Đây là thao tác chặn (Blocking):
*   Nếu Mutex đang Unlocked: Luồng lấy khóa và tiếp tục.
*   Nếu Mutex đang Locked bởi luồng khác: Luồng gọi hàm sẽ đi vào trạng thái chờ cho tới khi lấy được Mutex.

### 5.3 `pthread_mutex_trylock()`

Hàm này thay đổi hành vi chặn:
*   Nếu Mutex trống: Lấy khóa và trả về `0`.
*   Nếu Mutex đang bị giữ: Hàm sẽ **không chờ**, mà lập tức trả về mã lỗi `EBUSY`.
Nó hữu ích khi luồng có thể làm công việc khác thay vì bị chặn để chờ đợi.

### 5.4 `pthread_mutex_unlock()`

Luồng sở hữu giải phóng Mutex. Nếu có nhiều luồng khác đang chờ, một trong số chúng sẽ có cơ hội được lập lịch để chạy tiếp. Không nên giả định thứ tự lấy lại khóa luôn luôn là FIFO trừ khi tài liệu hệ thống có cam kết cụ thể.

### 5.5 Tiêu hủy Mutex

Việc gọi `pthread_mutex_destroy()` khi đối tượng vẫn đang được tham chiếu, đang bị khóa, hoặc đang có luồng chờ là một lỗi vòng đời tài nguyên, có thể gây ra hành vi không xác định.

---

## 6. Các loại Mutex cơ bản

POSIX định nghĩa một số loại Mutex với hành vi khác biệt, đặc biệt là khi xảy ra các thao tác bất thường.

### 6.1 `PTHREAD_MUTEX_NORMAL`

Đây là loại tiêu chuẩn, ưu tiên hiệu suất. Nếu một luồng đang giữ khóa mà vô ý gọi `lock()` trên chính Mutex đó một lần nữa, luồng có thể tự làm mình bị deadlock vĩnh viễn.

### 6.2 `PTHREAD_MUTEX_ERRORCHECK`

Được thiết kế để hỗ trợ phát hiện lỗi. Nó sẽ trả về mã lỗi thay vì deadlock nếu một luồng cố khóa lại Mutex nó đang giữ, hoặc trả lỗi nếu một luồng cố mở khóa Mutex mà nó không sở hữu. Loại này rất hữu ích cho việc gỡ lỗi.

### 6.3 `PTHREAD_MUTEX_RECURSIVE` (Khóa đệ quy)

Loại này cho phép **chính chủ sở hữu** có thể gọi lệnh `lock()` nhiều lần mà không bị deadlock. Nó duy trì một biến đếm số lần khóa (recursion count); Mutex chỉ thực sự được giải phóng khi số lần gọi `unlock()` cân bằng với số lần gọi `lock()`. Recursive mutex có mục đích riêng, nhưng lạm dụng nó có thể che giấu những cấu trúc khóa rối rắm.

### 6.4 `PTHREAD_MUTEX_DEFAULT`

Trên các nền tảng khác nhau, kiểu mặc định có thể trỏ về Normal, Errorcheck hoặc một thiết lập tùy biến. Khi ứng dụng phụ thuộc vào một hành vi đặc thù (như kiểm tra lỗi), nên dùng loại có tên cụ thể thay vì mặc định.

---

## 7. `Condition variable`: ngủ để chờ trạng thái thay đổi

`Condition Variable` (CV) được dùng khi một luồng **chưa thể tiếp tục công việc vì trạng thái dữ liệu hiện tại chưa phù hợp**, và thay vì liên tục kiểm tra trạng thái đó, luồng có thể đi vào trạng thái chờ (`wait`).

Ví dụ trong mô hình `producer–consumer`, Consumer chỉ có thể lấy dữ liệu khi hàng đợi có ít nhất một phần tử:

```c
queue_size > 0
```

Nếu hàng đợi đang rỗng, Consumer có thể ngủ để nhường CPU cho công việc khác. Khi Producer thêm dữ liệu, nó thông báo qua Condition Variable để Consumer được đánh thức và kiểm tra lại trạng thái.

### 7.1 Vấn đề của việc kiểm tra liên tục

Giả sử Consumer đang chờ dữ liệu xuất hiện trong một Queue.

Một cách không tốt là liên tục kiểm tra:

```c
while (queue_size == 0) {
    // tiếp tục kiểm tra
}
```

Đây là dạng `busy-wait`: luồng vẫn chiếm thời gian CPU chỉ để lặp lại việc kiểm tra dù chưa có công việc hữu ích.

Điều mong muốn là:

```text
Queue rỗng
    |
    v
Consumer kiểm tra trạng thái
    |
    v
Chưa có dữ liệu
    |
    v
Consumer đi vào trạng thái chờ
    |
    |   CPU có thể chạy công việc khác
    |
Producer thêm dữ liệu
    |
    v
Producer thông báo
    |
    v
Consumer được đánh thức
```

Condition Variable cung cấp cơ chế `wait/wakeup` cho mô hình này.

### 7.2 `Condition Variable` không chứa điều kiện nghiệp vụ

Mặc dù tên là `Condition Variable`, bản thân đối tượng này **không lưu điều kiện mà chương trình đang chờ**.

Ví dụ:

```c
queue_size > 0
```

mới là điều kiện logic thực sự. Điều kiện logic như vậy thường được gọi là **`predicate`**.

Có thể phân biệt:

```text
Shared state:
    queue_size

Predicate:
    queue_size > 0

Condition Variable:
    cơ chế để luồng ngủ và được đánh thức
    khi trạng thái có khả năng đã thay đổi
```

Condition Variable không biết Queue đang rỗng hay có dữ liệu. Khi một luồng được đánh thức, ý nghĩa chỉ nên hiểu là:

> Trạng thái mà luồng đang quan tâm **có thể đã thay đổi**, hãy kiểm tra lại predicate.

Vì vậy, dữ liệu chia sẻ và predicate mới là nguồn sự thật; Condition Variable chỉ hỗ trợ việc chờ và đánh thức.

### 7.3 Vì sao phải đi cùng Mutex?

Predicate thường phụ thuộc vào dữ liệu dùng chung.

Ví dụ:

```c
queue_size > 0
```

Trong đó `queue_size` có thể được:

- Producer thay đổi khi thêm dữ liệu.
- Consumer đọc và thay đổi khi lấy dữ liệu.

Do đó việc kiểm tra và cập nhật trạng thái này cũng cần được đồng bộ bằng Mutex.

Mô hình:

```text
        Shared Queue
             |
             v
        queue_size
             |
             v
   Predicate: size > 0
             ^
             |
      Mutex bảo vệ
             |
             v
   Condition Variable
    wait / wakeup
```

Hai công cụ có nhiệm vụ khác nhau:

```text
Mutex
    -> bảo vệ việc đọc và thay đổi shared state.

Condition Variable
    -> cho phép luồng ngủ khi predicate chưa đúng
       và được đánh thức khi trạng thái có thể đã thay đổi.
```

Mẫu sử dụng cơ bản:

```c
pthread_mutex_lock(&mutex);

while (queue_size == 0) {
    pthread_cond_wait(&cond, &mutex);
}

/* Queue đang ở trạng thái phù hợp để xử lý */

pthread_mutex_unlock(&mutex);
```

### 7.4 `pthread_cond_wait()` làm hai việc quan trọng

Trước khi gọi:

```c
pthread_cond_wait(&cond, &mutex);
```

luồng phải đang giữ `mutex`.

Về mặt giao thức, hàm này thực hiện một thao tác rất quan trọng:

```text
nhả Mutex
    +
đưa luồng vào trạng thái chờ
```

hai việc này được phối hợp như một thao tác nguyên tử đối với cơ chế chờ.

Điều này tránh xuất hiện khoảng hở nguy hiểm kiểu:

```text
Consumer kiểm tra predicate
        |
        v
predicate chưa đúng
        |
        v
nhả Mutex
        |
        |  <-- nếu có khoảng hở ở đây,
        |      Producer có thể thay đổi trạng thái
        |      và phát tín hiệu trước khi
        |      Consumer thực sự bắt đầu chờ
        v
Consumer mới bắt đầu ngủ
```

`pthread_cond_wait()` được thiết kế để tránh khoảng hở giữa **nhả Mutex** và **bắt đầu chờ**.

Khi Condition Variable đánh thức luồng, `pthread_cond_wait()` chưa lập tức trả về. Luồng phải **lấy lại chính Mutex đó trước**, sau đó hàm mới trả quyền điều khiển cho chương trình:

```text
đang giữ Mutex
      |
      v
pthread_cond_wait()
      |
      +--> nhả Mutex
      |
      +--> đi vào trạng thái chờ
                |
                | được đánh thức
                v
          lấy lại Mutex
                |
                v
 pthread_cond_wait() trả về
```

Nhờ đó, khi luồng quay lại kiểm tra predicate, nó lại đang giữ Mutex và có thể truy cập shared state theo đúng giao thức đồng bộ.

> **Ý chính:** Mutex bảo vệ trạng thái dữ liệu; Condition Variable giúp luồng chờ trạng thái thay đổi; còn `pthread_cond_wait()` kết nối hai cơ chế này bằng cách nhả Mutex và đi vào trạng thái chờ một cách an toàn, sau đó lấy lại Mutex trước khi trả về.

---

## 8. Predicate, spurious wakeup và lost wakeup

Luồng phải kiểm tra điều kiện trong vòng lặp vì việc thức dậy không đồng nghĩa với việc điều kiện đã chắc chắn đúng.

### 8.1 Kiểm tra Predicate trong vòng lặp `while`

Mental pattern chuẩn mực:
```c
pthread_mutex_lock(&mutex);

while (predicate == false) {
    pthread_cond_wait(&cond, &mutex);
}

// Xử lý dữ liệu
pthread_mutex_unlock(&mutex);
```

### 8.2 Spurious Wakeup (Thức giấc ảo)

Chuẩn POSIX cho phép `pthread_cond_wait()` trả về ngay cả khi không có ai gọi hàm đánh thức. Ngoài ra, ngay cả khi được đánh thức hợp lệ, một luồng khác có thể lấy được Mutex trước và làm predicate thay đổi trở lại trước khi luồng hiện tại lấy lại khóa.

Ví dụ Consumer đang chờ `queue_size > 0`: nó có thể thức dậy nhưng khi lấy lại Mutex thì `queue_size` vẫn bằng `0`. Vì vậy, **được đánh thức không có nghĩa là predicate chắc chắn đúng**.

Do đó phải kiểm tra predicate bằng `while`:

```c
while (queue_size == 0) {
    pthread_cond_wait(&cond, &mutex);
}
```

Nếu thức dậy mà predicate vẫn chưa đúng, luồng đơn giản quay lại `wait`.

### 8.3 Mất đánh thức (Lost Wakeup)

`Lost wakeup` xảy ra khi tín hiệu đánh thức được phát ra **trước khi luồng thực sự bắt đầu chờ**, nên tín hiệu đó không được lưu lại để dùng về sau. Luồng có thể đi ngủ dù predicate đã đúng.

Mô hình lỗi:

```text
Luồng A: kiểm tra predicate -> chưa đúng
         nhả Mutex
                              Luồng B: đổi trạng thái + signal
Luồng A: lúc này mới bắt đầu wait
```

Nếu tự tách `unlock()` và thao tác chờ như trên, sẽ xuất hiện một khoảng hở nguy hiểm. `pthread_cond_wait()` tránh khoảng hở này bằng cách **nhả Mutex và bắt đầu chờ một cách được phối hợp nguyên tử**, sau đó lấy lại Mutex trước khi trả về.

Vì vậy, giao thức chuẩn là: giữ Mutex khi kiểm tra/thay đổi predicate và dùng `pthread_cond_wait()` để thực hiện bước chuyển từ **đang giữ Mutex** sang **đang chờ** một cách an toàn.

---

## 9. `signal`, `broadcast` và chờ có thời hạn

Condition Variable cung cấp các cách khác nhau để đánh thức luồng đang chờ. Việc được đánh thức chỉ có nghĩa là **trạng thái có thể đã thay đổi**; luồng vẫn phải lấy lại Mutex và kiểm tra lại `predicate` trước khi tiếp tục xử lý.

### 9.1 `pthread_cond_signal()`

`pthread_cond_signal()` đánh thức **ít nhất một** luồng đang chờ trên Condition Variable. Cách này phù hợp khi trạng thái mới thường chỉ cho phép một luồng tiến tiếp, ví dụ Producer vừa thêm một phần tử vào Queue và chỉ cần một Consumer thức dậy để xử lý.

```text
Consumer A ─┐
Consumer B ─┼── đang wait
Consumer C ─┘

Producer thêm 1 phần tử
        |
        v
    signal(cond)
        |
        v
ít nhất một Consumer được đánh thức
```

Không nên phụ thuộc vào việc luồng cụ thể nào sẽ được hệ thống chọn đánh thức. Sau khi thức dậy, luồng vẫn phải lấy lại Mutex và kiểm tra lại `predicate`.

### 9.2 `pthread_cond_broadcast()`

`pthread_cond_broadcast()` đánh thức **tất cả** các luồng đang chờ trên Condition Variable. Cách này phù hợp khi một thay đổi trạng thái có liên quan đến nhiều hoặc toàn bộ luồng, ví dụ đặt cờ `shutdown` để yêu cầu mọi worker thread kiểm tra trạng thái kết thúc.

```text
Worker A ─┐
Worker B ─┼── đang wait
Worker C ─┘

shutdown = 1
     |
     v
broadcast(cond)
     |
     +--> A thức dậy
     +--> B thức dậy
     +--> C thức dậy
```

Mặc dù nhiều luồng được đánh thức gần như cùng lúc, chúng **không cùng đi vào critical section**. Mỗi luồng vẫn phải cạnh tranh để lấy lại cùng Mutex, sau đó kiểm tra lại `predicate`.

Có thể nhớ ngắn gọn:

```text
signal()     -> đánh thức một waiter phù hợp
broadcast()  -> đánh thức tất cả waiter
```

### 9.3 Chờ có thời hạn (Timed wait)

`pthread_cond_timedwait()` giống `pthread_cond_wait()` nhưng có thêm một **thời điểm giới hạn (`deadline`)**. Luồng có thể kết thúc việc chờ khi được đánh thức hoặc khi đã tới deadline.

```text
pthread_cond_timedwait()
        |
        +--> được signal / broadcast
        |
        +--> tới deadline -> timeout
```

Ngay cả khi hàm trả về do timeout, ứng dụng vẫn nên kiểm tra lại `predicate`, vì thời điểm timeout và thời điểm shared state thay đổi có thể xảy ra rất sát nhau.

---

## 10. `Semaphore`: bộ đếm tài nguyên hoặc token

Semaphore là một **bộ đếm số lượng tài nguyên hoặc quyền sử dụng (`token`) đang sẵn sàng**. Nếu giá trị Semaphore lớn hơn 0, luồng có thể lấy một token để tiếp tục; nếu giá trị bằng 0, luồng phải chờ cho tới khi có token mới được cấp lại.

Có thể hình dung:

```text
Semaphore = 3

[ token ] [ token ] [ token ]
```

Mỗi lần một luồng lấy quyền sử dụng, bộ đếm giảm đi 1. Khi quyền đó được trả lại hoặc có thêm tài nguyên, bộ đếm tăng lên 1.

### 10.1 Khái niệm Bộ đếm

Bên trong Semaphore duy trì một giá trị nguyên không âm. Giá trị này thường đại diện cho số lượng tài nguyên đang khả dụng, số slot còn trống trong buffer, hoặc số sự kiện/item đang sẵn sàng để xử lý.

Ví dụ, nếu hệ thống có 3 tài nguyên giống nhau:

```text
sem = 3
```

thì có thể hiểu là hiện còn 3 token để các luồng lấy.

### 10.2 Lấy thẻ: `sem_wait()`

`sem_wait()` có thể hiểu là **lấy một token**:

- Nếu Semaphore lớn hơn 0: bộ đếm giảm đi 1 và luồng tiếp tục.
- Nếu Semaphore bằng 0: không còn token, luồng phải chờ cho tới khi một luồng khác gọi `sem_post()`.

```text
sem = 2
   |
sem_wait()
   v
sem = 1
```

Semaphore không có tính sở hữu; nó thường phù hợp với các bài toán cần đếm số lượng tài nguyên khả dụng.

### 10.3 Cấp thẻ: `sem_post()`

`sem_post()` **cấp hoặc trả lại một token**, làm bộ đếm tăng lên 1 và có thể giúp một luồng đang chờ tiếp tục.

```text
sem = 0
   |
sem_post()
   v
sem = 1
```

Khác với Mutex, Semaphore không yêu cầu luồng gọi `sem_post()` phải là luồng đã gọi `sem_wait()` trước đó.

### 10.4 Binary Semaphore vs Mutex

Nếu Semaphore chỉ được sử dụng với giá trị 0 và 1, nó được gọi là **Binary Semaphore** và nhìn bề ngoài khá giống Mutex. Tuy nhiên, điểm khác biệt cốt lõi vẫn là **quyền sở hữu (`ownership`)**:

```text
Mutex:
Luồng A lock()  -> Luồng A phải unlock()

Semaphore:
Luồng A sem_wait()
Luồng B vẫn có thể sem_post()
```

Vì vậy có thể nhớ ngắn gọn:

```text
Mutex     -> "Ai đang sở hữu quyền độc quyền?"
Semaphore -> "Còn bao nhiêu token/tài nguyên khả dụng?"
```

Sự phân biệt này đặc biệt quan trọng trong thiết kế đồng bộ và các cơ chế thời gian thực như Kế thừa ưu tiên (`Priority Inheritance`).

---

## 11. Khi nào dùng `mutex`, `condition variable` hay `semaphore`?

Sử dụng đúng công cụ cho bài toán sẽ tạo ra kiến trúc sạch.

| Công cụ | Bản chất cốt lõi | Câu hỏi nhận diện bài toán | Có chủ sở hữu? |
| :--- | :--- | :--- | :--- |
| **Mutex** | Khóa loại trừ | "Ai được quyền vào vùng cập nhật trạng thái ngay lúc này?" | Có (Ai khóa người nấy mở) |
| **Condition Variable** | Cơ chế chờ & Đánh thức | "Khi nào luồng nên chờ/wakeup để kiểm tra lại predicate?" | Không đứng riêng lẻ |
| **Semaphore** | Bộ đếm | "Có bao nhiêu đơn vị tài nguyên / token đang sẵn sàng?" | Không |
| **Barrier** | Điểm hẹn | "Mọi thành viên đã tới ranh giới giai đoạn này chưa?" | Không |

---

## 12. Mô hình `producer–consumer`

Mẫu thiết kế (`pattern`) phổ biến kết hợp cả Mutex và Condition Variable. Producer tạo hoặc nhận dữ liệu rồi đưa vào hàng đợi, còn Consumer lấy dữ liệu từ hàng đợi ra để xử lý.

### 12.1 Kiến trúc tổng quan

```text
 Producer
    |
    v
+-------------------+
|   Shared queue    |  <--- (Được bảo vệ bằng MUTEX)
+-------------------+
    |
    v
 Consumer
```

Hàng đợi nằm giữa giúp **tách nhịp hoạt động** của hai phía: Producer có thể đưa dữ liệu vào Queue rồi tiếp tục công việc của mình, trong khi Consumer xử lý dữ liệu theo tốc độ riêng. Queue cũng có thể hấp thụ các đợt dữ liệu đến dồn dập (`burst`) trong giới hạn dung lượng của nó.

Tuy nhiên, Queue chỉ hấp thụ được chênh lệch tốc độ **tạm thời**. Nếu Producer liên tục tạo dữ liệu nhanh hơn mức Consumer có thể xử lý trong thời gian dài, số phần tử tồn đọng sẽ tăng dần và cuối cùng Queue vẫn đầy. Vì vậy, Queue không loại bỏ được sự chênh lệch thông lượng (`throughput`) kéo dài.

### 12.2 Bảo vệ tính nhất quán bằng Mutex

Queue là dữ liệu dùng chung: Producer có thể cập nhật `tail`, `size`, `buffer`, còn Consumer có thể cập nhật `head`, `size`, `buffer`. Các trường này liên quan logic với nhau nên mọi thao tác đọc/sửa xung đột cần tuân thủ cùng một giao thức Mutex.

Nói ngắn gọn:

```text
Mutex
   -> bảo vệ tính nhất quán của Shared Queue
```

### 12.3 Điều phối tiến độ bằng Condition Variable

Mutex chỉ bảo vệ Queue; nó không giải quyết việc một phía **chưa thể tiếp tục** vì trạng thái Queue chưa phù hợp. Condition Variable được dùng để cho thread ngủ và được đánh thức khi trạng thái có thể đã thay đổi.

* **`not_empty`:** Consumer chờ khi Queue rỗng. Sau khi Producer thêm một phần tử, Producer phát tín hiệu `not_empty` để báo rằng Consumer có thể kiểm tra lại điều kiện `size > 0`.
* **`not_full`:** Với Queue hữu hạn, Producer chờ khi Queue đầy. Sau khi Consumer lấy một phần tử ra, Consumer phát tín hiệu `not_full` để báo rằng Producer có thể kiểm tra lại điều kiện `size < capacity`.

Mô hình tư duy:

```text
Producer:
    nếu Queue đầy   -> wait(not_full)
    thêm dữ liệu    -> signal(not_empty)

Consumer:
    nếu Queue rỗng  -> wait(not_empty)
    lấy dữ liệu     -> signal(not_full)
```

> **Ý chính:** Queue giúp tách nhịp giữa Producer và Consumer; Mutex bảo vệ trạng thái Queue; còn `not_empty` và `not_full` điều phối thời điểm mỗi phía có thể tiếp tục công việc.

---

## 13. `Barrier`: các luồng chờ nhau ở cuối một giai đoạn

`Barrier` buộc một nhóm luồng chờ nhau tại một mốc trước khi tất cả cùng được đi tiếp sang giai đoạn sau.

### 13.1 Bài toán của Barrier

Barrier chuyên dùng để **đồng bộ tiến độ giữa các pha (Phasing)**.

```text
                 PHASE 1                     BARRIER                     PHASE 2

Luồng A  ------------------------------->  +--------------+  ------------------------------->  tiếp tục
Luồng B  ------------------------------->  |   chờ đủ N   |  ------------------------------->  tiếp tục
Luồng C  ------------------------------->  |    luồng     |  ------------------------------->  tiếp tục
                                           +------+-------+
                                                  |
                                                  v
                                      Luồng cuối cùng tới
                                      -> mở barrier
                                      -> giải phóng tất cả luồng
```

Mỗi luồng đi tới barrier được tính là một thành viên. Nếu nó chưa phải thành viên cuối cùng, nó phải chờ. Thành viên cuối cùng tới ranh giới sẽ thỏa mãn điều kiện barrier, giải phóng toàn bộ những luồng đang chờ để cùng bước sang giai đoạn tiếp theo. Barrier không thay thế Mutex trong việc bảo vệ dữ liệu dùng chung.

### 13.2 Chờ vô hạn nếu thiếu thành viên

Vòng đời thành viên phải được thiết kế đồng bộ với barrier. Nếu barrier cần 4 luồng tham gia nhưng chỉ có 3 luồng tới, cả 3 luồng kia sẽ chờ vô thời hạn.

---

## 14. `Deadlock`

Deadlock xảy ra khi các luồng tạo thành một vòng chờ tài nguyên khép kín khiến không luồng nào có thể tiếp tục.

### 14.1 Ví dụ Khóa chéo hai Mutex

```text
Luồng A đang cầm Khóa M1. Đang chờ M2.
Luồng B đang cầm Khóa M2. Đang chờ M1.

  [ A ] --(chờ)--> [ M2 ]
    ^                |
    |                v
  [ M1 ] <--(chờ)-- [ B ]
```

Vòng chờ khép kín này khiến hệ thống rơi vào bế tắc toàn cục. Deadlock không chỉ đến từ mutex; nó còn có thể phát sinh từ quan hệ phụ thuộc giữa thread join, condition variable, barrier, hoặc I/O.

### 14.2 Bốn điều kiện Coffman

Với deadlock do tranh chấp tài nguyên, bốn điều kiện Coffman sau phải **cùng tồn tại**:

1. **Loại trừ lẫn nhau (Mutual Exclusion):** Có ít nhất một tài nguyên chỉ cho phép một luồng sử dụng tại một thời điểm. Ví dụ, một Mutex chỉ có thể được một luồng sở hữu tại một thời điểm.
2. **Giữ và Chờ (Hold and Wait):** Một luồng đang giữ ít nhất một tài nguyên nhưng vẫn tiếp tục chờ thêm tài nguyên khác. Ví dụ, Luồng A đang giữ `M1` nhưng chờ lấy `M2`.
3. **Không thể Tước đoạt (No Preemption):** Tài nguyên đang được một luồng giữ không thể bị hệ thống tự ý thu hồi để cấp cho luồng khác; luồng đang sở hữu phải tự giải phóng nó theo đúng giao thức.
4. **Chờ đợi xoay vòng (Circular Wait):** Các luồng tạo thành một vòng chờ khép kín. Ví dụ, A giữ `M1` và chờ `M2`, trong khi B giữ `M2` và chờ `M1`.

```text
A giữ M1 ──> chờ M2
   ^              |
   |              v
chờ M1 <── B giữ M2
```

Nếu phá vỡ được ít nhất một trong bốn điều kiện trên thì loại deadlock này không thể hình thành. Trong thực tế, một kỹ thuật phổ biến là phá điều kiện **Circular Wait** bằng cách áp dụng `lock ordering` nhất quán, ví dụ luôn lấy `M1` trước `M2` ở mọi luồng.

### 14.3 `Self-deadlock`

Xảy ra khi cấu hình Mutex ở dạng tiêu chuẩn (Normal), một luồng khóa `M1`, sau đó (do lỗi logic) lại tiếp tục gọi `lock(M1)`. Nó tự đứng chờ chính nó mở khóa.

---

## 15. `Starvation` và `livelock`

Hai biến thể vấn đề đồng bộ tinh vi hơn deadlock. Khác với deadlock, hệ thống có thể vẫn đang chạy nhưng một phần công việc không tiến triển đúng cách.

### 15.1 `Starvation`

`Starvation` xảy ra khi hệ thống vẫn tiến triển, nhưng một luồng liên tục bị bỏ lại, thiếu cơ hội chạy hoặc không giành được tài nguyên (như khóa Mutex) trong thời gian dài, thường do chính sách ưu tiên hoặc phân phối tài nguyên không công bằng.

Ví dụ:

```text
Luồng A lấy Mutex -> làm việc -> nhả Mutex
Luồng C lấy Mutex -> làm việc -> nhả Mutex
Luồng A lại lấy Mutex trước
Luồng C lại lấy Mutex trước
...

Luồng B: -------------------- tiếp tục chờ -------------------->
```

Hệ thống không deadlock vì A và C vẫn tiến triển, nhưng B bị "đói" tài nguyên quá lâu.

### 15.2 `Livelock`

`Livelock` xảy ra khi các luồng không bị ngủ kẹt như deadlock. Chúng vẫn chạy, vẫn thay đổi trạng thái và phản ứng với nhau, nhưng cứ liên tục né tránh xung đột nên công việc chính không thể hoàn thành. CPU có thể vẫn bận nhưng tiến độ thực tế gần như bằng không.

Ví dụ hai luồng cùng cố nhường nhau:

```text
Luồng A thử làm việc -> thấy xung đột -> nhường -> thử lại
Luồng B thử làm việc -> thấy xung đột -> nhường -> thử lại

A và B vẫn chạy, nhưng cứ lặp lại mà không hoàn thành công việc.
```

Có thể phân biệt nhanh:

```text
Deadlock   : một nhóm luồng mắc kẹt và không ai tiếp tục được.
Starvation : hệ thống vẫn chạy, nhưng một luồng bị bỏ lại quá lâu.
Livelock   : các luồng vẫn hoạt động, nhưng công việc chính không tiến triển.
```

---

## 16. `Lock ordering`, `critical-section granularity` và `contention`

Mục tiêu của thiết kế đồng bộ là giữ tính đúng đắn mà không tạo contention không cần thiết.

### 16.1 Quy tắc `lock ordering` nhất quán

Một kỹ thuật để phá vỡ điều kiện "Chờ đợi xoay vòng" là chọn **một thứ tự toàn cục** cho các Mutex và buộc mọi nhánh code phải khóa chúng theo đúng một chiều (Ví dụ: luôn lấy `M1` trước `M2` và không khóa theo chiều ngược lại).

### 16.2 Độ mịn của Vùng tới hạn (Lock Granularity)

Độ mịn phải cân bằng giữa hiệu suất và việc duy trì tính nhất quán.
*   **Khóa thô (Coarse-grained):** Dùng ít Mutex để bảo vệ các vùng trạng thái lớn. Dễ thiết kế, ít vòng phụ thuộc khóa, nhưng nhiều luồng phải chờ cùng một khóa làm giảm tính song song.
*   **Khóa mịn (Fine-grained):** Dùng nhiều Mutex bảo vệ từng phần nhỏ. Tăng mức độ song song nhưng mã phức tạp hơn và rủi ro deadlock tăng cao.

### 16.3 Xung đột khóa (Contention)

Nếu nhiều luồng thường xuyên dồn dập tranh giành một Khóa Mutex, Mutex đó trở thành "điểm nóng" (Contention), dẫn tới thời gian chờ cao và chi phí chuyển đổi ngữ cảnh tăng vọt.

**Nguyên lý thiết kế:** Giữ critical section ngắn gọn **trong giới hạn vẫn bảo toàn được các ràng buộc nhất quán (`invariant`) và ý nghĩa giao dịch (`transaction semantics`)** của nghiệp vụ. Hạn chế tối đa việc giữ khóa khi đang thực hiện các thao tác không xác định thời gian chờ (blocking I/O, tải mạng, ngâm giấc ngủ).

---

## 17. `Priority inversion` và `priority inheritance`

`Priority inversion` đặc biệt quan trọng trong các hệ thống có yêu cầu ưu tiên và độ trễ chặt chẽ (Real-time).

### 17.1 `Priority inversion`

Giả sử hệ thống có 3 mức ưu tiên: Cao (H), Trung bình (M), Thấp (L).
```text
High priority H:   [bị block bởi Mutex do L giữ] ----------------
Medium priority M:        RUN RUN RUN RUN
Low priority L:     giữ Mutex      không được cấp CPU      RUN -> unlock(Mutex)
```

Luồng H có ưu tiên cao nhất bị đứng chờ vì luồng L đang cầm khóa. Tuy nhiên, luồng L lại bị luồng M (có ưu tiên trung bình) giành mất thời gian CPU. Do đó, L không có cơ hội chạy để nhả khóa, gián tiếp khiến luồng H phải chờ vô thời hạn.

### 17.2 `Priority inheritance`

Cơ chế `PTHREAD_PRIO_INHERIT` có thể áp dụng cho Mutex để giảm bớt hiện tượng này. Khi luồng H bị block bởi Mutex do L giữ, L sẽ tạm thời "thừa hưởng" mức ưu tiên cao của H. Nhờ đó, L được nâng mức ưu tiên tạm thời để có cơ hội hoàn thành critical section và nhả khóa cho H sớm hơn.

Priority Inheritance chỉ giải quyết một lớp priority inversion nhất định. Nó không phải là thuốc chữa bách bệnh cho mọi lỗi đồng bộ hay thiết kế khóa kém.

---

## 18. Tư duy gỡ lỗi đồng bộ

Khi gặp lỗi, hãy nhóm các triệu chứng và khoanh vùng hệ thống.

### 18.1 Phân loại triệu chứng

*   **Dữ liệu hỏng (corruption) ngẫu nhiên:** Thường hướng tới Data Race hoặc lỗi vòng đời (Lifetime). Các luồng truy cập mà không tuân theo đúng giao thức bảo vệ.
*   **Chương trình không tiến triển, CPU thấp:** Hướng tới Deadlock hoặc có luồng đang chờ vô thời hạn (Indefinite wait).
*   **CPU vọt cao nhưng không tiến triển:** Có thể là Livelock hoặc lỗi thiết kế Busy-waiting.
*   **Một luồng bị chậm trễ kéo dài:** Hướng tới Starvation, Priority inversion hoặc Contention quá cao.

### 18.2 Câu hỏi gỡ lỗi theo trình tự
1. Dữ liệu trạng thái chia sẻ (Shared state) nào đang sai?
2. Mọi truy cập vào dữ liệu đó có tuân theo cùng một giao thức đồng bộ (protocol) không?
3. Khóa Mutex nào đang bảo vệ **ràng buộc nhất quán (`invariant`)** nào của shared state?
4. Trật tự lấy khóa (Lock ordering) có nhất quán trên toàn bộ các luồng không?
5. Mốc trạng thái (Predicate) của Condition Variable là gì? Nó có luôn được đánh giá bên trong vòng lặp `while` không?
6. Critical section có đang chứa các thao tác chặn (blocking/IO) giữ khóa quá lâu không?

---

## 19. Liên hệ với Embedded Linux

Môi trường Embedded Linux thường xử lý nhiều luồng I/O nhạy cảm về thời gian; đồng bộ sai có thể gây treo hệ thống hoặc sai lệch dữ liệu rất khó tái hiện.

### 19.1 Hàng đợi cảm biến (`sensor pipeline`)

Một kiến trúc điển hình:
*   **Luồng Sensor (Producer):** Đọc cảm biến, giữ Mutex để đưa mẫu dữ liệu (sample) vào hàng đợi (Shared queue), nhả Mutex, rồi gửi tín hiệu Condition Variable để báo `queue_not_empty`.
*   **Luồng Phân tích (Consumer):** Ngủ chờ Condition Variable. Tỉnh dậy, giữ Mutex, lấy dữ liệu ra xử lý, nhả Mutex.
Mutex ở đây bảo vệ **tính nhất quán của dữ liệu**, còn Condition Variable hỗ trợ việc **ngủ/thức theo trạng thái dữ liệu**.

### 19.2 Tranh chấp khi điều khiển thiết bị

Nếu hai luồng cùng cần giao tiếp SPI để điều khiển ngoại vi. `Critical section` của Mutex bảo vệ luồng SPI không nên đặt rải rác. Critical section nên bao trùm toàn bộ **một giao dịch (`transaction`) hoàn chỉnh**: Từ lúc kéo chân `CS (Chip Select)` xuống LOW, truyền chuỗi byte, nhận phản hồi, cho tới lúc đưa chân `CS` lên HIGH.

### 19.3 Quản lý logger tập trung

Trong thiết kế hệ thống Nhúng, thay vì để mọi luồng cùng giữ Lock để tự ghi file (dễ gây nghẽn do thời gian I/O đĩa bất định), người ta thường thiết kế một Hàng đợi Log tập trung đẩy tới một `Logger thread` duy nhất (Single-owner). Cách thiết kế này giảm thiểu sự tranh chấp (contention) hiệu quả.

### 19.4 Bài toán PREEMPT_RT

Khi làm việc với các hệ thống nhúng thời gian thực (Real-time Linux), độ trễ (latency) sinh ra do chờ Lock cần phải được phân tích có giới hạn rõ ràng. Cơ chế Priority Inheritance (`PTHREAD_PRIO_INHERIT`) là một công cụ quan trọng để bảo vệ các tuyến đường thực thi nhạy cảm trước rủi ro Priority Inversion.

---

## 20. Tổng kết

### 20.1 Bản đồ chọn cơ chế đồng bộ

Có thể chọn cơ chế đồng bộ theo các câu hỏi sau:

```text
Bài toán đồng bộ là gì?
        |
        +--> Chỉ cho phép 1 luồng sửa trạng thái tại một thời điểm?
        |       -> Dùng [ Mutex ]
        |
        +--> Luồng cần chờ tới khi trạng thái thay đổi (Predicate)?
        |       -> Dùng [ Condition Variable ] (kèm Mutex)
        |
        +--> Cần đếm số lượng tài nguyên / thẻ token?
        |       -> Dùng [ Semaphore ]
        |
        +--> Mọi luồng phải chờ nhau tại cuối một giai đoạn?
                -> Dùng [ Barrier ]
```

> **Đọc sơ đồ:** Các primitive đồng bộ phục vụ những mục đích khác nhau. Nếu cần loại trừ lẫn nhau cho trạng thái dùng chung, dùng Mutex. Nếu cần luồng chờ một predicate thay đổi, dùng Condition Variable kèm Mutex. Nếu bài toán là đếm lượng tài nguyên, Semaphore là phù hợp. Nếu đồng bộ tiến độ giữa các pha, Barrier là công cụ phù hợp. Lựa chọn sai cấu trúc sẽ làm mất đi ý nghĩa của giao thức bảo vệ.

### 20.2 Vòng lặp nguyên lý của Condition Variable

```text
 [ Cấu trúc Dữ liệu chia sẻ ]
              |
      [ Predicate Logic ] (Ví dụ: Số lượng > 0)
              |
      [ Khóa Mutex bảo vệ ]
              |
 [ Tín hiệu Condition Variable ]
              |
(Thức dậy) -> LẤY LẠI KHÓA MUTEX -> (Kiểm tra Lại Predicate bằng vòng lặp WHILE)
```

> Trạng thái dữ liệu là cốt lõi của ứng dụng. Condition Variable không chứa dữ liệu; nó hỗ trợ cơ chế chờ và đánh thức. **Việc được đánh thức không đảm bảo Predicate chắc chắn đã đúng** (do `spurious wakeup` hoặc trạng thái đã bị luồng khác thay đổi). Việc sử dụng vòng lặp `while` để kiểm tra lại Predicate sau khi lấy lại Mutex là một quy tắc quan trọng để tránh sai lệch trạng thái.

### 20.3 Các nguyên lý cốt lõi
1. Đồng bộ luồng bản chất là bảo vệ **các ràng buộc nhất quán (`invariant`) của trạng thái** và thứ tự truy cập.
2. `Race condition` phụ thuộc vào thời điểm thực thi; `Data race` liên quan đến việc thiếu cơ chế đồng bộ cấp ngôn ngữ (C/C++) gây Undefined Behavior.
3. Các truy cập xung đột vào một trạng thái chia sẻ cần một chiến lược đồng bộ hóa; Mutex là một trong số đó.
4. Mutex thiết lập Quyền Sở Hữu: Luồng khóa phải là luồng mở. Tất cả các luồng truy cập phải tuân thủ cùng một giao ước.
5. Mutex tạo ra ranh giới đồng bộ bộ nhớ (Memory Visibility), đảm bảo các luồng thấy được cập nhật của nhau.
6. `Condition Variable` chỉ là cơ chế gọi dậy. Logic kiểm tra dữ liệu (`Predicate`) cần được thực hiện trong vòng lặp `while`.
7. `Semaphore` mang tính đếm, không có tính sở hữu (như Mutex).
8. Giữ vùng `Critical Section` ngắn gọn trong giới hạn vẫn bảo toàn được tính nhất quán và ý nghĩa giao dịch (transaction) để giảm `Contention`.
9. `Deadlock` là một chu trình phụ thuộc khiến các bên không thể tiếp tục. `Lock ordering` nhất quán là một kỹ thuật quan trọng để giảm nguy cơ deadlock khi sử dụng nhiều Mutex.
10. `Priority inversion` có thể làm tăng độ trễ của luồng ưu tiên cao. `PTHREAD_PRIO_INHERIT` hỗ trợ xử lý một phần vấn đề nhưng không thay thế một thiết kế khóa phù hợp.

---

## 21. Tài liệu tham khảo

Phần này liệt kê nguồn chuẩn về mutex, condition variable, semaphore và đồng bộ POSIX.

### POSIX.1-2024 / The Open Group

- https://pubs.opengroup.org/onlinepubs/9799919799/
- `pthread_mutex_lock()`: https://pubs.opengroup.org/onlinepubs/9799919799/functions/pthread_mutex_lock.html
- Condition Variable: https://pubs.opengroup.org/onlinepubs/9799919799/functions/pthread_cond_clockwait.html
- `<pthread.h>`: https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/pthread.h.html

Nguồn cho ngữ nghĩa chuẩn của mutex, condition variable, barrier, protocol ưu tiên và memory synchronization.

### Linux man-pages

- `pthreads(7)`: https://man7.org/linux/man-pages/man7/pthreads.7.html
- `pthread_mutex_lock(3p)`: https://man7.org/linux/man-pages/man3/pthread_mutex_lock.3p.html
- `pthread_cond_wait(3)`: https://man7.org/linux/man-pages/man3/pthread_cond_wait.3.html
- `sem_overview(7)`: https://man7.org/linux/man-pages/man7/sem_overview.7.html
- `pthread_barrier_wait(3p)`: https://man7.org/linux/man-pages/man3/pthread_barrier_wait.3p.html
- `pthread_mutexattr_setprotocol(3p)`: https://man7.org/linux/man-pages/man3/pthread_mutexattr_setprotocol.3p.html

### Tài liệu Embedded Linux / Linux system programming

- Bootlin PREEMPT_RT: https://bootlin.com/doc/training/preempt-rt/
- Bootlin Embedded Linux: https://bootlin.com/doc/training/embedded-linux/
- The Linux Programming Interface: https://man7.org/tlpi/

### Nguồn cộng đồng

- Unix & Linux Stack Exchange: https://unix.stackexchange.com/
- Stack Overflow: https://stackoverflow.com/

Các nguồn cộng đồng hữu ích để tìm trường hợp deadlock, lost wakeup hoặc lỗi producer–consumer thực tế, nhưng cần đối chiếu lại với POSIX/man-pages trước khi kết luận về ngữ nghĩa chuẩn.

---

> **Điều hướng:** [← Chủ đề 6 — Đa luồng](README-topic-06.md) · [Chủ đề 8 — Giao tiếp liên tiến trình →](README-topic-08.md)
