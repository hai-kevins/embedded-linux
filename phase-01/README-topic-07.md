# Chủ đề 7 — Đồng bộ luồng trong Linux

> **Mục tiêu:** Hiểu thấu đáo vì sao nhiều luồng dùng chung dữ liệu lại cần đồng bộ. Nắm bắt đúng bản chất và vai trò của các công cụ cốt lõi: `mutex`, `condition variable`, `semaphore`, `barrier`, đồng thời nhận diện được các rủi ro hệ thống như `race condition`, `deadlock`, `starvation` và `priority inversion`.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Giữ nguyên các thuật ngữ hệ thống chuẩn để thuận tiện tra cứu tài liệu quốc tế: `race condition`, `data race`, `critical section`, `atomicity`, `memory visibility`, `mutex`, `condition variable`, `predicate`, `semaphore`, `barrier`, `deadlock`, `starvation`, `livelock`, `lock ordering`, `contention`, `priority inversion` và tên các API Pthreads.
>
> **Phạm vi:** Tập trung xây dựng mô hình tư duy về `race condition`, `critical section`, khái niệm `atomicity`, `memory visibility` giữa các luồng. Khai thác sâu bộ công cụ: `mutex`, `condition variable`, `semaphore`, mô hình `producer–consumer` và `barrier`. Nhận diện các vấn đề kiến trúc: `deadlock`, `starvation`, `livelock`, `lock ordering`, `lock granularity`, `contention` và `priority inversion` ở mức tổng quan.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để chuẩn bị tư duy trước khi viết code đa luồng thực tế. Các kỹ thuật đồng bộ hóa không chặn (lock-free), cơ chế RCU, raw `futex`, `spinlock` cấp độ Kernel hay mô hình Atomics của C/C++ nằm ngoài phạm vi chương này.

Đồng bộ hóa (Synchronization) chỉ trở nên dễ hiểu khi bạn xuất phát từ **một trạng thái chia sẻ (shared state) cần được bảo vệ để luôn giữ tính đúng đắn**. Khóa `mutex` không tự động "khóa một biến", nó chỉ là thỏa thuận để bảo vệ một giao thức truy cập dữ liệu. `Condition Variable` không tự thân nó chứa bất kỳ điều kiện nào, nó chỉ cung cấp giải pháp cho luồng chờ đợi một mốc dữ liệu (predicate) thay đổi. `Semaphore` lại là công cụ phù hợp cho việc đếm tài nguyên. 

Thay vì liệt kê các API Pthreads rời rạc, chương này sẽ dẫn dắt bạn qua căn nguyên của vấn đề (`race condition`, `critical section`), sau đó mới cung cấp công cụ giải quyết (Mutex, Condition Variable, Semaphore, Barrier) và cuối cùng là phân tích các vấn đề tiềm ẩn nếu dùng công cụ sai cách (`deadlock`, `starvation`).

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

Nhiều người lầm tưởng đồng bộ là áp một khóa lên một biến số nguyên `count`. Thực tế, thứ chúng ta cần bảo vệ thường lớn hơn: nó là **tính nhất quán của một tập hợp trạng thái (Invariant)**.

Giả sử bạn có một cấu trúc hàng đợi (Queue):
```c
struct Queue {
    int head;
    int tail;
    int size;
    int buffer[10];
};
```
Khi Luồng A thêm dữ liệu vào `buffer`, nó cũng phải cập nhật `tail` và `size`. Nếu trong khoảnh khắc Luồng A mới cập nhật `buffer` xong nhưng chưa kịp sửa `size`, Luồng B nhảy vào đọc, Luồng B sẽ nhận được một trạng thái hàng đợi sai lệch, vi phạm tính nhất quán (invariant). Do đó, đối tượng cần bảo vệ là **toàn bộ khối trạng thái logic**, chứ không phải từng biến đơn lẻ.

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

**(Ví dụ kinh điển: Hai luồng cùng rút tiền)**
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

### 2.2 `data race` là khái niệm chặt chẽ hơn ở cấp trình biên dịch

`Data race` xảy ra khi có từ hai luồng trở lên cùng truy cập đồng thời vào một vị trí bộ nhớ, trong đó có ít nhất một luồng đang thực hiện thao tác **ghi (write)**, và các luồng này không sử dụng cơ chế đồng bộ thích hợp theo quy định của mô hình bộ nhớ ngôn ngữ.

Trong C/C++, `data race` dẫn tới hành vi không xác định (Undefined Behavior - UB). Trình biên dịch có thể tối ưu hóa sai mã nguồn, dẫn đến hậu quả không thể dự đoán. 

### 2.3 Race Condition ở mức logic giao thức (Protocol)

Đôi khi, từng biến đã được bảo vệ bởi khóa, nhưng lỗi logic vẫn xảy ra:

```text
Luồng A: 
  Khóa(M);
  Kiểm tra: Nếu tài nguyên X còn trống -> Mở Khóa(M).

  ... (Luồng B xen vào, Khóa M, chiếm đoạt tài nguyên X, Mở Khóa M) ...

  Khóa(M);
  (Luồng A sử dụng X dựa trên kết quả kiểm tra cũ) -> LỖI!
  Mở Khóa(M).
```

> Mặc dù từng thao tác đọc/ghi đã được khóa, nhưng ranh giới giao dịch (transaction) lại quá hẹp. Hai thao tác `Kiểm tra -> Hành động` bắt buộc phải được xem như một quyết định nguyên khối không thể bị chia cắt nếu hành động đó phụ thuộc vào kết quả kiểm tra. Nhả khóa ở giữa có thể phá vỡ tính nhất quán của giao thức.

### 2.4 Vùng tới hạn (`critical section`)

`Critical section` là một đoạn mã thay đổi hoặc đọc trạng thái dữ liệu chia sẻ mà các thao tác xung đột không được phép thực hiện đồng thời.

```text
[ Luồng A ]
     |
  lock(M)
     |
     v
+-------------------------------+
|       CRITICAL SECTION        |
|  (Cập nhật Trạng thái chung)  |
+-------------------------------+
     |
 unlock(M)
```

> **Đọc sơ đồ:** Hành động `lock()` và `unlock()` tạo ranh giới bảo vệ đoạn mã bên trong. Bản thân Khóa Mutex không tự biết nó đang bảo vệ biến nào. Chính **quy ước (protocol) của chương trình** mới quy định rằng mọi luồng muốn truy cập biến đó đều phải lấy cùng một khóa.

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

Trong lập trình đa luồng ở mức ứng dụng, một thao tác được coi là `nguyên tử` (Atomic) khi:
**Các luồng khác không bao giờ quan sát thấy bất kỳ trạng thái trung gian không hợp lệ nào của nó.**

Mutex làm cho một tập hợp các thao tác trở nên nguyên tử theo góc nhìn của các luồng khác cũng tuân thủ cùng một giao thức khóa.

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
       Tiến trình gọi lock()                | Tiến trình Chủ sở hữu
                 |                          | gọi unlock()
                 v                          |
          [ LOCKED (Bị Khóa) ] -------------+
```

> **Đọc sơ đồ:** Mutex có hai trạng thái cốt lõi: Không có chủ (`Unlocked`), hoặc đang có chủ (`Locked`). Nếu Mutex đang bị Luồng A chiếm giữ, và Luồng B cũng gọi lệnh `lock()`, Luồng B sẽ phải chờ. Trạng thái Locked mô tả quyền sở hữu chứ không mô tả bản thân dữ liệu. 

### 4.3 Khác biệt cốt lõi: Ownership

Quy tắc: **Luồng nào khóa Mutex, Luồng đó phải là người mở Mutex.**
Thiết kế Luồng A gọi `lock()` rồi Luồng B gọi `unlock()` thay là một vi phạm nguyên tắc quyền sở hữu, thường dẫn tới hành vi không xác định (Undefined behavior). Sự sở hữu này phân biệt rõ ràng Mutex với Semaphore.

### 4.4 Mutex không tự bảo vệ dữ liệu

Hệ thống không ghi nhận "Mutex M đang bảo vệ biến X". Đó là quy ước của chương trình. Nếu Luồng A đọc `X` dưới Mutex `M` nhưng Luồng B ghi `X` mà không dùng chung Mutex `M`, thì `M` không thể bảo vệ quyền truy cập của B. Tất cả các phía phải tuân thủ cùng một giao thức.

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
Nó hữu ích khi luồng có thể làm công việc khác thay vì bị kẹt cứng chờ đợi.

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

Condition Variable (CV) cho phép luồng ngủ trong khi điều kiện chưa đúng và được đánh thức khi trạng thái có thể đã thay đổi. Nó luôn gắn liền với một mốc trạng thái dữ liệu (predicate) cụ thể.

### 7.1 Vấn đề của việc kiểm tra liên tục

Giả sử Consumer chờ lấy dữ liệu từ một Hàng đợi (Queue). Việc kiểm tra liên tục bằng vòng lặp rỗng (busy-wait) sẽ lãng phí chu kỳ CPU vô ích.
Ta mong muốn một cơ chế:
```text
Hàng đợi rỗng
    |
Consumer chờ (ngủ)
    |
Producer thêm data
    |
Đánh thức Consumer
```

### 7.2 `condition variable` không chứa điều kiện nghiệp vụ

Bản thân CV không biết Hàng đợi rỗng hay đầy. Điều kiện logic thực sự (Predicate) như `queue_size > 0` phải nằm trong Dữ liệu chia sẻ. Condition Variable chỉ là cơ chế ngủ/đánh thức gắn liền với việc kiểm tra predicate đó.

### 7.3 Vì sao phải đi cùng Mutex?

Predicate nằm trong dữ liệu dùng chung nên phải được kiểm tra một cách nhất quán để tránh các lỗi tranh chấp.

Mô hình:
```text
Shared data
      |
      +--> Predicate
      |
     Mutex
      |
Condition Variable
```

Mutex bảo đảm việc kiểm tra và thay đổi trạng thái chia sẻ diễn ra có trật tự, còn Condition Variable hỗ trợ chuyển luồng sang trạng thái chờ. 

### 7.4 `pthread_cond_wait()` làm hai việc quan trọng

Về mặt khái niệm, `pthread_cond_wait()` cung cấp cơ chế thực hiện nguyên tử: **nhả mutex và chuyển luồng sang trạng thái chờ**. Điều này đóng khoảng hở có thể khiến một thông báo đánh thức bị bỏ lỡ giữa lúc luồng kiểm tra điều kiện và lúc luồng thực sự đi ngủ.

Khi luồng thức dậy từ `pthread_cond_wait()`, nó phải tự động **lấy lại Mutex** trước khi hàm này trả về quyền điều khiển cho mã gọi.

---

## 8. Predicate, spurious wakeup và lost wakeup

Luồng phải kiểm tra điều kiện trong vòng lặp vì việc thức dậy không đồng nghĩa với việc điều kiện đã chắc chắn đúng.

### 8.1 Luôn kiểm tra Predicate trong vòng lặp `while`

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

Chuẩn POSIX cho phép `pthread_cond_wait()` trả về ngay cả khi không có ai gọi hàm đánh thức (thường do cách cài đặt nội bộ bị ảnh hưởng bởi tín hiệu/ngắt). 
Hơn nữa, ngay cả khi được đánh thức hợp lệ, một luồng khác có thể đã nhanh tay giành được Mutex và thay đổi trạng thái trước khi luồng hiện tại lấy lại được khóa.
Vì thế, **được đánh thức không có nghĩa là predicate chắc chắn đúng**. Vòng lặp `while` là bắt buộc để luồng kiểm tra lại điều kiện sau mỗi lần thức.

### 8.3 Mất đánh thức (Lost Wakeup)

Lỗi kinh điển xảy ra nếu một luồng (A) kiểm tra điều kiện, sau đó một luồng khác (B) đổi trạng thái và phát tín hiệu đánh thức ngay trước khi A kịp bắt đầu quá trình chờ. Tín hiệu này không được lưu lại; A sẽ đi ngủ vô thời hạn dù điều kiện đã thỏa mãn.
Việc tuân thủ nghiêm ngặt protocol: **giữ Mutex khi thay đổi trạng thái và gọi wait** sẽ loại bỏ khoảng hở này.

---

## 9. `signal`, `broadcast` và chờ có thời hạn

Làm sao để đánh thức luồng đang chờ?

### 9.1 `pthread_cond_signal()`

Đánh thức **ít nhất một** luồng đang chờ đợi phù hợp. Dùng khi trạng thái mới chỉ cho phép một luồng duy nhất được tiến lên xử lý (ví dụ: một phần tử mới được đưa vào queue). Không nên phụ thuộc vào việc luồng nào cụ thể sẽ được hệ thống chọn đánh thức.

### 9.2 `pthread_cond_broadcast()`

Đánh thức **tất cả** các luồng đang chờ.
Dùng khi trạng thái mới cho phép nhiều luồng cùng tiếp tục (ví dụ: phát lệnh shutdown cho mọi worker thread). Mặc dù thức dậy cùng lúc, các luồng vẫn sẽ phải cạnh tranh nhau để lấy lại Mutex.

### 9.3 Chờ có thời hạn (Timed wait)

Hàm `pthread_cond_timedwait()` cho phép chờ tới một thời điểm giới hạn. Mặc dù hàm có thể trả về lỗi do timeout, ứng dụng vẫn nên kiểm tra lại trạng thái theo giao thức, vì thời điểm timeout và sự thay đổi predicate có thể diễn ra rất sát nhau.

---

## 10. `Semaphore`: bộ đếm tài nguyên hoặc token

Semaphore là một bộ đếm. Giá trị lớn hơn 0 có thể xem như số 'token' hoặc tài nguyên còn sẵn để lấy.

### 10.1 Khái niệm Bộ đếm

Bên trong Semaphore duy trì một con số nguyên. Nó thường đại diện cho số lượng slot rỗng trong buffer, hoặc số sự kiện chưa được xử lý.

### 10.2 Lấy thẻ: `sem_wait()`

Nếu giá trị Semaphore lớn hơn 0, `sem_wait()` giảm bộ đếm và tiến trình đi tiếp. Nếu giá trị bằng 0, caller phải chờ cho tới khi một luồng khác thực hiện hàm post để cấp thêm token.
Semaphore không có tính sở hữu; nó thường dùng cho việc đếm lượng tài nguyên khả dụng.

### 10.3 Cấp thẻ: `sem_post()`

Tăng số đếm lên 1 và có thể làm một luồng đang chờ có cơ hội tiếp tục. Khác với Mutex, Semaphore không yêu cầu luồng gọi `post` phải là luồng đã gọi `wait` trước đó.

### 10.4 Binary Semaphore vs Mutex

Dù giới hạn Semaphore ở giá trị 0 và 1, nó vẫn khác Mutex ở tính chất **quyền sở hữu (Ownership)**. Sự phân biệt này rất quan trọng đối với thiết kế ứng dụng và các giao thức như Kế thừa ưu tiên (Priority Inheritance) trong thời gian thực.

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

Mẫu thiết kế (pattern) kinh điển nhất kết hợp cả Mutex và Condition Variable. Producer đưa dữ liệu vào hàng đợi, Consumer lấy ra.

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

Mô hình hàng đợi giúp tách nhịp hoạt động giữa Producer và Consumer, hấp thụ các luồng dữ liệu bùng nổ (burst) trong giới hạn dung lượng của nó. Nó điều hòa lưu lượng, tuy nhiên **không loại bỏ được sự chênh lệch thông lượng (throughput) kéo dài** (ví dụ: Producer liên tục sinh ra lượng lớn dữ liệu nhanh hơn mức Consumer có thể xử lý thì cuối cùng hàng đợi cũng sẽ đầy).

### 12.2 Bảo vệ tính nhất quán bằng Mutex

Mọi trường liên đới của cấu trúc hàng đợi (như `head`, `tail`, `size`, `buffer`) cần một giao thức nhất quán được bảo vệ chung bởi một Mutex.

### 12.3 Điều phối tiến độ bằng Condition Variable

*   **Rỗng (`not_empty`):** Consumer chờ khi hàng đợi rỗng. Producer thêm dữ liệu và phát tín hiệu `not_empty` để đánh thức Consumer.
*   **Đầy (`not_full`):** Nếu hàng đợi hữu hạn, Producer chờ khi hàng đợi đầy. Consumer lấy phần tử ra và phát tín hiệu `not_full` để đánh thức Producer tiếp tục ghi vào.

---

## 13. `Barrier`: các luồng chờ nhau ở cuối một giai đoạn

`Barrier` buộc một nhóm luồng chờ nhau tại một mốc trước khi tất cả cùng được đi tiếp sang giai đoạn sau.

### 13.1 Bài toán của Barrier

Barrier chuyên dùng để **đồng bộ tiến độ giữa các pha (Phasing)**.

```text
Luồng A --------> barrier --Luồng B ------> barrier -----+--> Tất cả thành viên đã tới --> Phase 2
Luồng C ----------> barrier -/
```

Mỗi luồng đi tới barrier được tính là một thành viên. Nếu nó chưa phải thành viên cuối cùng, nó phải chờ. Thành viên cuối cùng tới ranh giới sẽ thỏa mãn điều kiện barrier, giải phóng toàn bộ những luồng đang chờ để cùng bước sang giai đoạn tiếp theo. Barrier không thay thế Mutex trong việc bảo vệ dữ liệu dùng chung.

### 13.2 Chờ vô hạn nếu thiếu thành viên

Vòng đời thành viên phải được thiết kế đồng bộ với barrier. Nếu barrier cần 4 luồng tham gia nhưng chỉ có 3 luồng tới, cả 3 luồng kia sẽ bị kẹt vĩnh viễn ở trạng thái chờ.

---

## 14. `Deadlock` (Khóa chéo / Bế tắc)

Deadlock xảy ra khi các luồng kẹp nhau trong một vòng tròn chờ đợi tài nguyên khép kín, không ai tiến lên được.

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

Các điều kiện cần đồng thời cho deadlock loại tài nguyên:
1.  **Loại trừ lẫn nhau (Mutual Exclusion)**
2.  **Giữ và Chờ (Hold and Wait)**
3.  **Không thể Tước đoạt (No Preemption)**
4.  **Chờ đợi xoay vòng (Circular Wait)**

### 14.3 Tự bóp cổ chính mình (Self-Deadlock)

Xảy ra khi cấu hình Mutex ở dạng tiêu chuẩn (Normal), một luồng khóa `M1`, sau đó (do lỗi logic) lại tiếp tục gọi `lock(M1)`. Nó tự đứng chờ chính nó mở khóa.

---

## 15. `Starvation` và `livelock`

Hai biến thể vấn đề đồng bộ tinh vi hơn deadlock.

### 15.1 `Starvation` (Chết đói)

Hệ thống vẫn đang tiến triển, nhưng một luồng liên tục bị bỏ lại, thiếu cơ hội chạy hoặc không giành được tài nguyên (khóa Mutex) trong thời gian dài (thường do chính sách ưu tiên bất công).

### 15.2 `Livelock` (Sống dở chết dở)

Các luồng không bị ngủ kẹt như Deadlock. Chúng vẫn hoạt động, vẫn phản ứng với nhau, nhưng cứ liên tục thay đổi trạng thái để tránh né xung đột mà công việc chính thì không thể tiến triển. CPU bận rộn một cách vô ích.

---

## 16. `Lock ordering`, `critical-section granularity` và `contention`

Nghệ thuật thiết kế đồng bộ là giữ an toàn mà không đánh sập hiệu năng.

### 16.1 Quy tắc Thứ tự Khóa (Lock Ordering) nhất quán

Một kỹ thuật để đánh gãy điều kiện "Chờ đợi xoay vòng" là chọn **một thứ tự toàn cục** cho các Mutex và buộc mọi nhánh code phải khóa chúng theo đúng một chiều (Vd: Luôn lấy `M1` xong mới được lấy `M2`, cấm chiều ngược lại).

### 16.2 Độ mịn của Vùng tới hạn (Lock Granularity)

Độ mịn phải cân bằng giữa hiệu suất và việc duy trì tính nhất quán.
*   **Khóa thô (Coarse-grained):** Dùng ít Mutex để bảo vệ các vùng trạng thái lớn. Dễ thiết kế, ít vòng phụ thuộc khóa, nhưng nhiều luồng phải chờ cùng một khóa làm giảm tính song song.
*   **Khóa mịn (Fine-grained):** Dùng nhiều Mutex bảo vệ từng phần nhỏ. Tăng mức độ song song nhưng mã phức tạp hơn và rủi ro deadlock tăng cao.

### 16.3 Xung đột khóa (Contention)

Nếu nhiều luồng thường xuyên dồn dập tranh giành một Khóa Mutex, Mutex đó trở thành "điểm nóng" (Contention), dẫn tới thời gian chờ cao và chi phí chuyển đổi ngữ cảnh tăng vọt.

**Nguyên lý thiết kế:** Giữ critical section ngắn gọn **trong giới hạn vẫn bảo toàn được tính nhất quán (invariant) và ý nghĩa giao dịch (transaction semantics)** của nghiệp vụ. Hạn chế tối đa việc giữ khóa khi đang thực hiện các thao tác không xác định thời gian chờ (blocking I/O, tải mạng, ngâm giấc ngủ).

---

## 17. `Priority inversion` và `priority inheritance`

Vấn đề đe dọa sinh mạng hệ thống trên các kiến trúc có ưu tiên thực thi khắt khe (Real-time).

### 17.1 Hiện tượng Đảo ngược Ưu tiên (Priority Inversion)

Giả sử hệ thống có 3 mức ưu tiên: Cao (H), Trung bình (M), Thấp (L).
```text
High priority H:   [bị block bởi Mutex do L giữ] ----------------
Medium priority M:        RUN RUN RUN RUN
Low priority L:     giữ Mutex      không được cấp CPU      RUN -> unlock(Mutex)
```

Luồng H có ưu tiên cao nhất bị đứng chờ vì luồng L đang cầm khóa. Tuy nhiên, luồng L lại bị luồng M (có ưu tiên trung bình) giành mất thời gian CPU. Do đó, L không có cơ hội chạy để nhả khóa, gián tiếp khiến luồng H phải chờ vô thời hạn.

### 17.2 Giải pháp Kế thừa Ưu tiên (Priority Inheritance)

Cơ chế `PTHREAD_PRIO_INHERIT` có thể áp dụng cho Mutex để giảm bớt hiện tượng này. Khi luồng H bị block bởi Mutex do L giữ, L sẽ tạm thời "thừa hưởng" mức ưu tiên cao của H. Nhờ đó, L mạnh ngang H, nó đánh bật M ra khỏi CPU để nhanh chóng hoàn thành critical section và nhả khóa cho H.

Priority Inheritance chỉ giải quyết một lớp priority inversion nhất định. Nó không phải là thuốc chữa bách bệnh cho mọi lỗi đồng bộ hay thiết kế khóa kém.

---

## 18. Tư duy gỡ lỗi đồng bộ

Khi gặp lỗi, hãy nhóm các triệu chứng và khoanh vùng hệ thống.

### 18.1 Phân loại Triệu chứng

*   **Dữ liệu hỏng (corruption) ngẫu nhiên:** Thường hướng tới Data Race hoặc lỗi vòng đời (Lifetime). Các luồng truy cập mà không tuân theo đúng giao thức bảo vệ.
*   **Chương trình đông cứng, CPU thấp:** Hướng tới Deadlock hoặc có luồng đang chờ vô thời hạn (Indefinite wait).
*   **CPU vọt cao nhưng không tiến triển:** Có thể là Livelock hoặc lỗi thiết kế Busy-waiting.
*   **Một luồng bị chậm trễ kéo dài:** Hướng tới Starvation, Priority inversion hoặc Contention quá cao.

### 18.2 Câu hỏi gỡ lỗi theo trình tự
1. Dữ liệu trạng thái chia sẻ (Shared state) nào đang sai?
2. Mọi truy cập vào dữ liệu đó có tuân theo cùng một giao thức đồng bộ (protocol) không?
3. Khóa Mutex nào đang bảo vệ `invariant` nào?
4. Trật tự lấy khóa (Lock ordering) có nhất quán trên toàn bộ các luồng không?
5. Mốc trạng thái (Predicate) của Condition Variable là gì? Nó có luôn được đánh giá bên trong vòng lặp `while` không?
6. Critical section có đang chứa các thao tác chặn (blocking/IO) giữ khóa quá lâu không?

---

## 19. Liên hệ với Embedded Linux

Môi trường Embedded Linux thường xử lý nhiều luồng I/O nhạy cảm về thời gian; đồng bộ sai có thể gây treo hệ thống hoặc sai lệch dữ liệu rất khó tái hiện.

### 19.1 Hàng đợi Cảm biến (Sensor Pipeline)

Một kiến trúc điển hình:
*   **Luồng Sensor (Producer):** Đọc cảm biến, giữ Mutex để đưa mẫu dữ liệu (sample) vào hàng đợi (Shared queue), nhả Mutex, rồi gửi tín hiệu Condition Variable để báo `queue_not_empty`.
*   **Luồng Phân tích (Consumer):** Ngủ chờ Condition Variable. Tỉnh dậy, giữ Mutex, bóc dữ liệu ra xử lý, nhả Mutex.
Mutex ở đây bảo vệ **tính nhất quán của dữ liệu**, còn Condition Variable hỗ trợ việc **ngủ/thức theo trạng thái dữ liệu**.

### 19.2 Đụng độ điều khiển Thiết bị gốc

Nếu hai luồng cùng cần giao tiếp SPI để điều khiển ngoại vi. `Critical section` của Mutex bảo vệ luồng SPI không nên đặt rải rác. Nó phải khóa bao trùm toàn bộ **một Giao dịch (Transaction) hoàn chỉnh**: Từ lúc kéo chân `CS (Chip Select)` xuống LOW, truyền chuỗi byte, nhận phản hồi, cho tới lúc đưa chân `CS` lên HIGH.

### 19.3 Quản trị Logger tập trung

Trong thiết kế hệ thống Nhúng, thay vì để mọi luồng cùng giữ Lock để tự ghi file (dễ gây nghẽn do thời gian I/O đĩa bất định), người ta thường thiết kế một Hàng đợi Log tập trung đẩy tới một `Logger thread` duy nhất (Single-owner). Cách thiết kế này giảm thiểu sự tranh chấp (contention) hiệu quả.

### 19.4 Bài toán PREEMPT_RT

Khi làm việc với các hệ thống nhúng thời gian thực (Real-time Linux), độ trễ (latency) sinh ra do chờ Lock cần phải được phân tích có giới hạn rõ ràng. Cơ chế Priority Inheritance (`PTHREAD_PRIO_INHERIT`) trở thành một công cụ cực kỳ quan trọng để bảo vệ các tuyến đường thực thi nhạy cảm trước rủi ro Priority Inversion.

---

## 20. Tổng kết

### 20.1 Bản đồ chọn cơ chế đồng bộ

Hãy đặt đúng câu hỏi trước khi chọn công cụ:

```text
Bài toán đồng bộ là gì?
        |
        +--> Chỉ cho phép 1 luồng sửa trạng thái tại một thời điểm?
        |       -> Dùng [ Mutex ]
        |
        +--> Luồng cần đi ngủ chờ tới khi trạng thái biến thay đổi (Mốc Predicate)?
        |       -> Dùng [ Condition Variable ] (Bắt buộc kèm Mutex)
        |
        +--> Cần đếm số lượng tài nguyên / thẻ token?
        |       -> Dùng [ Semaphore ]
        |
        +--> Mọi luồng phải hội quân tại điểm hẹn ở cuối một giai đoạn?
                -> Dùng [ Barrier ]
```

> **Đọc sơ đồ:** Công cụ Pthreads rất đa dạng và phục vụ các mục đích cụ thể. Nếu cần loại trừ lẫn nhau cho trạng thái dùng chung, dùng Mutex. Nếu cần luồng ngủ đợi một mốc điều kiện thay đổi, dùng Condition Variable kèm Mutex. Nếu bài toán là đếm lượng tài nguyên, Semaphore là phù hợp. Nếu đồng bộ tiến độ giữa các pha, Barrier là công cụ chuẩn xác. Lựa chọn sai cấu trúc sẽ làm mất đi ý nghĩa của giao thức bảo vệ.

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

> Trạng thái dữ liệu là cốt lõi của ứng dụng. Condition Variable không chứa dữ liệu, nó chỉ hỗ trợ kỹ thuật ru ngủ và gọi dậy. **Việc được đánh thức không đảm bảo mốc điều kiện (Predicate) chắc chắn đã đúng** (do rủi ro Thức giấc ảo - Spurious wakeup hoặc bị luồng khác lấy mất). Việc sử dụng vòng lặp `while` để kiểm tra lại Predicate sau khi lấy lại Khóa Mutex là ranh giới sống còn để loại bỏ lỗi.

### 20.3 Sổ tay các nguyên lý cốt lõi
1. Đồng bộ luồng bản chất là bảo vệ **tính nhất quán của tập hợp trạng thái (Invariant)** và thứ tự truy cập.
2. `Race condition` phụ thuộc vào thời điểm thực thi; `Data race` liên quan đến việc thiếu cơ chế đồng bộ cấp ngôn ngữ (C/C++) gây Undefined Behavior.
3. Các truy cập xung đột vào một trạng thái chia sẻ cần một chiến lược đồng bộ hóa; Mutex là một trong số đó.
4. Mutex thiết lập Quyền Sở Hữu: Luồng khóa phải là luồng mở. Tất cả các luồng truy cập phải tuân thủ cùng một giao ước.
5. Mutex tạo ra ranh giới đồng bộ bộ nhớ (Memory Visibility), đảm bảo các luồng thấy được cập nhật của nhau.
6. `Condition Variable` chỉ là cơ chế gọi dậy. Khối Logic kiểm tra dữ liệu (`Predicate`) phải được nhốt trong vòng lặp `while`.
7. `Semaphore` mang tính đếm, không có tính sở hữu (như Mutex).
8. Giữ vùng `Critical Section` ngắn gọn trong giới hạn vẫn bảo toàn được tính nhất quán và ý nghĩa giao dịch (transaction) để giảm `Contention`.
9. `Deadlock` là vòng lặp phụ thuộc không ai nhường ai. Ngăn chặn triệt để nhất bằng quy tắc Trật tự Khóa (Lock Ordering) nhất quán toàn cục.
10. `Priority Inversion` đe dọa các luồng ưu tiên cao. Cơ chế `PTHREAD_PRIO_INHERIT` giúp giải quyết một phần nhưng không chữa được những thiết kế khóa tồi.

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
