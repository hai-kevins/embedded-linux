# Chủ đề 3 — File I/O trong Linux

> **Mục tiêu:** Hiểu rõ cách một chương trình Linux thực sự đọc/ghi dữ liệu như thế nào thông qua `file descriptor` (viết tắt `fd`) và các `system call` cốt lõi: `open()`, `read()`, `write()`, `lseek()`, `close()`.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các thuật ngữ Linux/POSIX cần phân biệt chính xác như `file descriptor`, `open file description`, `file offset`, `partial I/O`, `short read`, `blocking`, `nonblocking`, `EOF`, `errno`, cùng tên API, cờ và mã lỗi được giữ nguyên bằng tiếng Anh để thuận tiện tra cứu.
>
> **Phạm vi:** `file descriptor`, `open file description`, `open`, quyền truy cập, cờ mở tệp, `read`, `write`, `partial I/O`, EOF, `file offset`, `lseek`, `close`, `blocking`/`nonblocking` I/O ở mức cơ bản, `errno`, `EINTR`, `EAGAIN`.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để xây dựng tư duy hệ thống, không có bài thực hành.

Ý tưởng trung tâm của File I/O trên Linux rất đơn giản: **`pathname` (đường dẫn) chủ yếu dùng để tìm và mở một đối tượng; sau khi mở thành công, chương trình làm việc với đối tượng đó thông qua một con số gọi là `file descriptor` (`fd`)**. Vì thế, cần phân biệt rạch ròi giữa tên tệp, `inode`, cấu trúc `open file description` trong Kernel và con số `fd` mà tiến trình đang sử dụng.

Từ mô hình đó, các API `open()`, `read()`, `write()`, `lseek()` và `close()` trở thành một chuỗi dây chuyền logic chặt chẽ thay vì năm hàm rời rạc. Phần còn lại của chương sẽ tập trung vào cách xử lý giá trị trả về, hiện tượng đọc/ghi một phần (`partial I/O`), kết thúc luồng (EOF), cơ chế chặn (`blocking`/`nonblocking`) và tư duy gỡ lỗi khi một lời gọi hệ thống thất bại.

---

## Mục lục

- [1. `file descriptor` là gì?](#1-file-descriptor-là-gì)
- [2. Từ đường dẫn đến tệp đang mở](#2-từ-đường-dẫn-đến-tệp-đang-mở)
- [3. `open()`: mở một đối tượng I/O](#3-open-mở-một-đối-tượng-io)
- [4. `read()`: đọc dữ liệu](#4-read-đọc-dữ-liệu)
- [5. `write()`: ghi dữ liệu](#5-write-ghi-dữ-liệu)
- [6. Vị trí đọc/ghi và `lseek()`](#6-vị-trí-đọcghi-và-lseek)
- [7. `close()` và vòng đời `file descriptor`](#7-close-và-vòng-đời-file-descriptor)
- [8. `blocking` và `nonblocking` I/O](#8-blocking-và-nonblocking-io)
- [9. Giá trị trả về, `errno` và các lỗi quan trọng](#9-giá-trị-trả-về-errno-và-các-lỗi-quan-trọng)
- [10. Tư duy gỡ lỗi File I/O](#10-tư-duy-gỡ-lỗi-file-io)
- [11. Liên hệ với Embedded Linux](#11-liên-hệ-với-embedded-linux)
- [12. Tổng kết](#12-tổng-kết)
- [13. Tài liệu tham khảo](#13-tài-liệu-tham-khảo)

---

## 1. `file descriptor` là gì?

Sau khi hệ thống mở thành công một đối tượng I/O, Linux trả về cho chương trình một số nguyên nhỏ gọi là `file descriptor` (`fd`). Chương trình sẽ dùng con số này làm tham chiếu cho mọi thao tác đọc, ghi và đóng tệp sau đó.

### 1.1 File I/O rộng hơn tệp thông thường

Trong triết lý UNIX/Linux, các API `read()` và `write()` có thể làm việc với vô số loại đối tượng khác nhau:
*   Tệp văn bản/nhị phân thông thường (`regular file`).
*   Đường ống (`pipe`) và `FIFO`.
*   Giao diện dòng lệnh (`terminal`).
*   Kết nối mạng (`socket`).
*   Thiết bị phần cứng (`device node`).
*   Các mục cấu hình trong `procfs`/`sysfs`.

Vì vậy, cụm từ “File I/O” trong Linux nên được hiểu rộng ra là: **"I/O thông qua file descriptor"**, chứ không đơn thuần chỉ là đọc/ghi một tệp tin trên ổ cứng.

### 1.2 `file descriptor` hoạt động như thế nào?

Một `fd` thực chất chỉ là một số nguyên không âm (vd: 0, 1, 2, 3...), đóng vai trò làm chỉ mục (index) tra cứu trong **bảng file descriptor** của riêng tiến trình đó.

```text
[ Tiến trình A (Process A) ]
+-------------------------------------------------+
| Bảng File Descriptor (File Descriptor Table)    |
|   0 -> Trỏ tới stdin (Bàn phím)                 |
|   1 -> Trỏ tới stdout (Màn hình)                |
|   2 -> Trỏ tới stderr (Màn hình báo lỗi)        |
|   3 -> Trỏ tới [ Đối tượng Kernel X ]           |
|   4 -> Trỏ tới [ Đối tượng Kernel Y ]           |
+-------------------------------------------------+
```

> **Đọc sơ đồ:** Bảng tra cứu này nằm **riêng biệt bên trong từng tiến trình (process)**. Con số 3 chỉ là một vị trí (index) để tiến trình tham chiếu tới đối tượng I/O mà Kernel đang quản lý hộ nó. Vì là bảng riêng, nên `fd = 3` của Tiến trình A hoàn toàn không liên quan gì đến `fd = 3` của Tiến trình B (trừ khi chúng có quan hệ kế thừa qua `fork` hoặc truyền fd đặc biệt). Phải luôn phân biệt rõ **con số chỉ mục (fd)** và **đối tượng thực tế mà fd đó đang trỏ tới**.

### 1.3 `fd` không phải inode

*   `inode` là cấu trúc dữ liệu mô tả đối tượng nằm ở tầng Filesystem (như đã học ở Topic 02).
*   `fd` là tham chiếu giao dịch nằm ở tầng Tiến trình (Process context).
*   Hai tiến trình có thể cùng sở hữu biến `fd = 3`, nhưng hai số `3` này có thể trỏ tới hai đối tượng/inode hoàn toàn khác nhau.

### 1.4 `fd` không phải con trỏ bộ nhớ (pointer) ở userspace

Ứng dụng không thể thao tác trực tiếp với bộ nhớ thông qua `fd` như một con trỏ C/C++ (`*ptr`). Nó bắt buộc phải truyền con số này vào các `system call`:
```c
read(fd, buffer, size);
write(fd, buffer, size);
close(fd);
```
Linux Kernel sẽ nhận con số `fd` này, quét trong bảng File Descriptor Table của tiến trình gọi lệnh để tìm ra đối tượng thực sự cần thao tác.

---

## 2. Từ đường dẫn đến tệp đang mở

Sự phân tách trách nhiệm trong Linux rất rõ ràng: `pathname` dùng để định vị đối tượng, `open()` yêu cầu mở đối tượng đó, còn `fd` là tham chiếu được cấp để thực hiện các thao tác tiếp theo.

### 2.1 Hai giai đoạn khác nhau của File I/O

**Giai đoạn 1: Mở tệp**
```text
[ Pathname (Đường dẫn) ] ---> gọi hàm open() ---> Kernel tìm object và tạo handle
```

**Giai đoạn 2: Tương tác I/O**
```text
[ Nhận được fd ] 
      |
      +---> read(fd, ...)
      +---> write(fd, ...)
      +---> lseek(fd, ...)
      +---> close(fd)
```

> **Đọc sơ đồ:** Hàm `open()` dùng `pathname` để yêu cầu Kernel rà soát cây thư mục, **tìm đối tượng và tạo ra một bộ hồ sơ quản lý (handle)**. Sau khi `open()` thành công, các thao tác I/O phía sau chỉ làm việc bằng `fd`; Kernel KHÔNG đi rà soát lại `pathname` ở mỗi lần gọi `read()` hay `write()` nữa. Đó là lý do tại sao nếu bạn đổi tên tệp (rename) hoặc xóa tên (unlink) sau khi file đã được mở, tiến trình đang cầm `fd` vẫn có thể đọc/ghi dữ liệu bình thường mà không bị mất hiệu lực ngay lập tức.

### 2.2 `open file description` (Hồ sơ quản lý tệp đang mở)

Linux và chuẩn POSIX phân biệt rất rõ hai khái niệm:
*   `file descriptor` (fd): Con số chỉ mục ở phía ứng dụng.
*   **`open file description`**: Cấu trúc trạng thái do Kernel duy trì cho một phiên mở tệp. *(Tài liệu giữ nguyên tiếng Anh để tránh nhầm lẫn với file descriptor)*.

Một `open file description` chứa các trạng thái sống còn như:
*   Vị trí con trỏ đọc/ghi hiện tại (`file offset`).
*   Các cờ trạng thái của tệp (ví dụ cờ Read-Only, Write-Only, Non-blocking).
*   Con trỏ tham chiếu sâu xuống đối tượng Inode bên dưới.

### 2.3 Quan hệ tổng thể: Hành trình cấu trúc

```text
[ Pathname ] 
      |
      v  (VFS pathname lookup)
[ Inode / Đối tượng trong Filesystem ] 
      |
      v  (Kernel tạo hồ sơ quản lý phiên mở)
[ Open file description ] 
      |
      v  (Tiến trình lưu vào bảng tra cứu)
[ File descriptor (fd) ] 
```

> **Đọc sơ đồ:** Không phải đối tượng nào cũng có `inode` (ví dụ socket), nhưng với tệp tin thông thường, mô hình này là kim chỉ nam. Nếu bạn gọi `open()` hai lần trên cùng một tệp, Kernel sẽ tạo ra hai `open file description` độc lập (mỗi cái có một `file offset` riêng), sinh ra hai `fd` khác nhau, nhưng cả hai đều trỏ chung về một `Inode` vật lý. Ngược lại, nếu bạn dùng hàm `dup(fd)`, Kernel chỉ cấp thêm một `fd` mới trỏ vào CÙNG MỘT `open file description` cũ (chúng sẽ chia sẻ chung `file offset`).

---

## 3. `open()`: mở một đối tượng I/O

`open()` yêu cầu Linux kernel dò tìm `pathname`, xác thực quyền hạn, kiểm tra các cờ (flags) và thiết lập trạng thái. Thành công thì nó trả về `fd`; thất bại thì trả về lỗi hệ thống.

### 3.1 `open()` làm những việc gì?

Quy trình bên trong Kernel diễn ra như một chuỗi xử lý (pipeline):

```text
[ Chuỗi Pathname ]
        |
[ 1. Phân giải Pathname (Resolution) ]
        |
[ 2. Kiểm tra Quyền truy cập & Cờ mở tệp ]
        |
[ 3. Tạo/Tham chiếu Open file description ]
        |
[ 4. Trả về File Descriptor (fd) ]
```

> **Đọc sơ đồ:** Chỉ ở bước cuối cùng, con số `fd` mới được cấp cho Userspace. Do đó, hàm `open()` có thể báo lỗi từ rất sớm ở khâu 1 (sai đường dẫn), khâu 2 (thiếu quyền Permission, hoặc sai cờ) trước khi bất kỳ thao tác tạo I/O dữ liệu nào diễn ra.
*   Nếu thành công: `return >= 0` (số `fd` nhỏ nhất đang trống).
*   Nếu thất bại: `return -1`, và biến `errno` sẽ chứa nguyên nhân lỗi cụ thể.

### 3.2 Chế độ truy cập (Access Mode)

Khi mở tệp, bạn phải chọn một trong ba chế độ cơ bản: `O_RDONLY` (Chỉ đọc), `O_WRONLY` (Chỉ ghi), và `O_RDWR` (Đọc và ghi).
*Đây là chế độ áp dụng riêng cho **lần mở hiện tại**, nó hoàn toàn khác với các bit phân quyền `r/w/x` tĩnh của Filesystem*.

### 3.3 Quyền Filesystem và Quyền của FD

Là hai lớp cửa bảo vệ khác biệt:
1.  **Cửa 1 (Filesystem permission):** Bạn có đủ quyền để đi qua cây thư mục và gọi hàm `open()` lên tệp này không?
2.  **Cửa 2 (FD Access mode):** Sau khi `open()` thành công, `fd` được tạo ra với quyền gì? (Ví dụ: Bạn có quyền `w` trên tệp, nhưng lại gọi `open()` với cờ `O_RDONLY`, thì `fd` đó sẽ không thể dùng hàm `write()` được).

### 3.4 Cờ tạo tệp `O_CREAT`

`O_CREAT` hướng dẫn Kernel tự tạo tệp mới nếu `pathname` chưa tồn tại.
Khi dùng cờ này, bạn BẮT BUỘC phải truyền thêm tham số `mode` để mô tả các bit phân quyền ban đầu (ví dụ `0666`). Sau đó, `mode` này sẽ chịu ảnh hưởng của mặt nạ `umask` (và có thể cả ACL) để ra được quyền thực tế lưu xuống đĩa.

### 3.5 Cờ làm rỗng tệp `O_TRUNC`

Nếu tệp đã tồn tại và bạn có quyền ghi, cờ `O_TRUNC` sẽ lập tức cắt ngắn (truncate) toàn bộ nội dung tệp, đưa kích thước (size) về `0` ngay khoảnh khắc mở.
> Điều này minh chứng: `open()` không phải lúc nào cũng là thao tác “chỉ đọc siêu dữ liệu”; nó hoàn toàn có khả năng thay đổi và xóa dữ liệu tệp.

### 3.6 Cờ ghi nối `O_APPEND`

Khi thiết lập trạng thái append, Kernel đảm bảo việc định vị tới cuối tệp (EOF) và thực hiện `write()` diễn ra một cách nguyên tử (atomic) đối với các hệ thống tệp cục bộ hỗ trợ ngữ nghĩa này.
Hành động này an toàn và chuẩn xác hơn nhiều so với việc ứng dụng tự viết code thủ công:
```c
lseek(fd, 0, SEEK_END); // Nhảy xuống cuối
write(fd, data, size);  // Ghi
```
Bởi vì giữa hai dòng lệnh rời rạc trên, một tiến trình khác có thể chen ngang ghi đè dữ liệu lên file gây ra tranh chấp (race condition). *(Lưu ý: Một số hệ thống tệp mạng như NFS có thể có những ngoại lệ riêng với cờ O_APPEND).*

### 3.7 Cờ bảo mật `O_CLOEXEC`

Cờ `O_CLOEXEC` thiết lập thuộc tính `close-on-exec` một cách nguyên tử ngay tại thời điểm mở tệp.
*   **Mục đích:** Đảm bảo `fd` này sẽ tự động bị Kernel đóng lại (close) nếu tiến trình hiện tại gọi hàm `execve()` để chạy một chương trình khác.
*   Tránh rò rỉ `fd` ngoài ý muốn sang các chương trình con. Việc thiết lập ngay lúc `open()` là cực kỳ quan trọng trong môi trường đa luồng (multi-threading) nhằm ngăn chặn tranh chấp so với việc mở xong rồi mới gọi hàm `fcntl()` cài cờ.

---

## 4. `read()`: đọc dữ liệu

Hàm `read()` ra lệnh cho Kernel sao chép tối đa một lượng byte nhất định từ thiết bị vào bộ đệm của ứng dụng. Việc nó trả về số byte thực tế ít hơn yêu cầu là hiện tượng hoàn toàn bình thường.

### 4.1 Ý nghĩa của `read()`: Đọc "tối đa"

Tư duy đúng đắn khi gọi hàm:
```c
ssize_t bytes_read = read(fd, buffer, count);
```
Câu lệnh này mang ý nghĩa: *"Hãy đọc **tối đa** `count` byte vào bộ đệm"*.
Nó không có nghĩa: *"Bắt buộc phải trả đủ `count` byte mới được coi là thành công"*.

### 4.2 Giá trị trả về

Mọi logic xử lý phải dựa trên kết quả trả về của hàm `read()`:
*   `> 0`: Thành công, biểu thị số lượng byte thực sự đã đọc được vào bộ đệm.
*   `== 0`: Báo hiệu đã hết luồng dữ liệu (EOF - End Of File, hoặc End-of-stream tùy thuộc vào loại đối tượng).
*   `== -1`: Báo lỗi hệ thống. Cần kiểm tra biến `errno` để biết nguyên nhân.

### 4.3 `short read` (Đọc một phần) không phải là lỗi

Giả sử bạn yêu cầu đọc `count = 4096` byte, nhưng `read()` chỉ trả về `300` byte. Đây là hiện tượng `short read` (đọc một phần) và nó hoàn toàn hợp lệ.

Nguyên nhân tùy thuộc vào đối tượng:
*   **Regular file:** Tệp trên đĩa chỉ còn đúng 300 byte tính từ vị trí offset hiện tại.
*   **Pipe / Socket:** Bộ đệm của ống nước/mạng hiện tại mới chỉ nhận được 300 byte, nó trả về ngay dữ liệu có sẵn thay vì bắt luồng chờ đợi.
*   **Terminal:** Đang hoạt động ở chế độ `canonical` (chờ nhận theo từng dòng) hoặc `noncanonical` (từng ký tự).
*   **Signal:** Một ngắt tín hiệu hệ thống (signal) chen ngang sau khi hàm `read` đã kịp đọc được 300 byte.

### 4.4 Phân biệt rạch ròi EOF và Lỗi

*   **EOF (Hết dữ liệu):** Trả về `0`.
*   **Lỗi hệ thống:** Trả về `-1` và thiết lập mã `errno`.
Ứng dụng phải xử lý hai tình huống này hoàn toàn khác nhau.

### 4.5 EOF phụ thuộc vào ngữ nghĩa của loại đối tượng

Đọc về `0` mang những ý nghĩa khác biệt:
*   **Tệp thông thường (Regular file):** Vị trí `file offset` hiện tại đã chạm hoặc vượt qua điểm cuối của tệp.
*   **Đường ống (Pipe):** Đã hết sạch dữ liệu trong vùng đệm, ĐỒNG THỜI không còn bất kỳ tiến trình nào mở đầu ghi (writer) của ống này nữa.
*   **Mạng (TCP Stream):** Phía đối tác (peer) đã chủ động đóng kết nối chiều gửi (`orderly shutdown`) và ứng dụng đã đọc cạn toàn bộ dữ liệu tồn đọng.

Vì vậy, “`read() == 0`” phải được thấu hiểu trong bối cảnh đối tượng đang thao tác.

---

## 5. `write()`: ghi dữ liệu

Tương tự `read()`, lệnh `write()` hoàn toàn có thể ghi được số byte ít hơn so với mức ứng dụng yêu cầu. Chương trình vững chãi phải luôn kiểm tra giá trị trả về để ghi nốt phần còn thiếu.

### 5.1 `write()` có thể hoàn thành một phần (Partial I/O)

Lệnh gọi:
```c
ssize_t written = write(fd, buffer, count);
```
Có thể trả về giá trị `M`, trong đó `0 < M < count`. Điều này có nghĩa là Kernel chỉ mới chấp nhận và xử lý được `M` byte đầu tiên.

*(Lưu ý: Khác với `read()`, nếu `write()` trả về `0`, nó chỉ đơn thuần mang nghĩa "không có byte nào được ghi", không mang ngữ nghĩa EOF).*

### 5.2 Vì sao hiện tượng "ghi ngắn" (short write) tồn tại?

Hiện tượng này có thể xảy ra do:
*   **Pipe/Socket:** Vùng đệm trong Kernel sắp đầy, chỉ còn đủ không gian chứa một phần dữ liệu.
*   **Giới hạn tài nguyên (Resource limit):** Phân vùng hết dung lượng hoặc tiến trình chạm hạn mức (quota) kích thước tệp.
*   **Signal:** Bị ngắt tín hiệu giữa chừng sau khi đã ghi được một số byte.
*   **Nonblocking I/O:** Đối tượng mở ở chế độ không chặn chỉ có thể tiếp nhận ngay một phần dữ liệu rồi trả về.

Do đó, code chuẩn luôn phải đặt hàm `write()` trong vòng lặp và đánh giá **số byte trả về**, thay vì cho rằng gọi một lần là ghi xong toàn bộ.

### 5.3 Ghi thành công KHÔNG đồng nghĩa dữ liệu đã bền vững trên thiết bị

Đối với tệp thông thường (regular file) sử dụng I/O có bộ đệm (buffered I/O), một lệnh `write()` báo thành công thường chỉ có nghĩa là dữ liệu đã được Kernel tiếp nhận và chép vào bộ đệm RAM (gọi là `Page cache`). 

Các đối tượng khác như socket, pipe, hoặc thiết bị có ngữ nghĩa riêng. Để đẩy dữ liệu thực sự xuống thiết bị lưu trữ, bạn phải dùng các hàm đồng bộ hóa chuyên dụng như `fsync()`. Dù vậy, các lớp bộ đệm của bản thân thiết bị điều khiển (disk controller) vẫn có thể ảnh hưởng đến mức độ bền vững cuối cùng của dữ liệu khi xảy ra sự cố mất điện.

### 5.4 Với Pipe và Socket: Sự độc lập của các lớp

Ghi thành công vào `socket` hay `pipe` cũng không đảm bảo ứng dụng đầu kia đã đọc hay xử lý nó.

```text
[ write() thành công ]
         |
         v
[ Đẩy vào Kernel Buffer (Vẫn nằm trên RAM cục bộ) ]
         |
         v
[ Luân chuyển qua Network / Giao thức kết nối ]
         |
         v
[ Chờ Peer Application (Ứng dụng đầu kia) gọi read() để lấy ra ]
```

> **Đọc sơ đồ:** Hành động `write()` chỉ đảm bảo việc dữ liệu được đẩy vào không gian đệm của Kernel để gửi đi. Việc Kernel tiếp nhận thành công không đồng nghĩa với việc tiến trình đích (Peer application) đã gọi `read()` để đọc gói dữ liệu đó. Mỗi lớp hệ thống quản lý một trạng thái độc lập.

---

## 6. Vị trí đọc/ghi và `lseek()`

Tệp thông thường luôn duy trì một con trỏ ghi nhớ vị trí (offset). Hàm `lseek()` dùng để dịch chuyển con trỏ này, nhưng hãy cẩn thận vì không phải loại đối tượng nào cũng hỗ trợ thao tác này (seek).

### 6.1 `file offset` (Vị trí con trỏ tệp)

Đối với các tệp tin có thể seek, `open file description` bên trong Kernel sẽ âm thầm duy trì một vị trí byte hiện hành (file offset).

```text
Byte index:  0  1  2  3  4  5  6  7 ...
                         ^
                         |
                 File offset hiện tại
```

Mỗi lần bạn gọi `read()` hoặc `write()`, Kernel tự động đẩy con trỏ này tiến lên tương ứng với số byte đã xử lý.

### 6.2 Lệnh `lseek()`

Dùng để chủ động thay đổi (seek) `file offset` đến một tọa độ mới.
Hàm này chỉ cập nhật con trỏ số học bên trong RAM, nó không tạo ra bất kỳ thao tác đọc hay ghi dữ liệu vật lý nào.

### 6.3 Ba cột mốc căn chuẩn (Seek anchors) phổ biến

*   `SEEK_SET`: Dịch chuyển tính từ mốc byte 0 (Đầu tệp).
*   `SEEK_CUR`: Dịch chuyển tính từ vị trí `file offset` hiện tại (có thể bước lùi bằng số âm).
*   `SEEK_END`: Dịch chuyển tính từ cột mốc cuối cùng của tệp.

### 6.4 Dịch chuyển vượt quá EOF (Tạo tệp thưa - Sparse File)

Với tệp tin thông thường, Kernel cho phép bạn thay đổi `offset` vượt ra khỏi điểm kết thúc hiện tại của tệp. Nếu sau khi dịch chuyển, bạn gọi hàm `write()` để ghi dữ liệu, một vùng trống (hole) sẽ được tạo ra.

Hệ thống tệp (Filesystem) thường sẽ không cấp phát các block lưu trữ vật lý cho khoảng trống ở giữa này (tạo thành tệp thưa - sparse file). Khi ứng dụng tiến hành đọc qua vùng này, Kernel sẽ tự động trả về các byte 0 (NULL).

### 6.5 Không phải đối tượng nào cũng `seek` được

Các luồng dữ liệu (streams) như: `Pipe`, `FIFO`, `Socket`, `Terminal` và phần lớn thiết bị ký tự (Character device) không có khái niệm lưu trữ tĩnh để hỗ trợ dịch chuyển vị trí (seek). Nếu cố tình gọi `lseek()` lên các `fd` này, Kernel sẽ trả về mã lỗi `ESPIPE` (Illegal seek).

---

## 7. `close()` và vòng đời `file descriptor`

Lệnh `close()` xóa bỏ tham chiếu `fd` khỏi tiến trình. Tuy nhiên, nếu cấu trúc `open file description` bên dưới vẫn còn được tham chiếu bởi nơi khác, tài nguyên sẽ tiếp tục tồn tại.

### 7.1 Lệnh `close(fd)` thực chất đóng cái gì?

Lệnh này thực hiện giải phóng **một vị trí (chỉ mục) trong Bảng File Descriptor của riêng tiến trình đó**.

```text
[ File Descriptor Table ]

  3 -> [ Trỏ tới open file description X ]

(Gọi hàm close(3))

  3 -> [ Trở thành Slot trống, tham chiếu tới X bị hủy ]
```

> **Đọc sơ đồ:** `close(fd)` loại bỏ tham chiếu từ phía ứng dụng. Kernel sẽ kiểm tra xem còn tham chiếu nào khác (ví dụ qua hàm `dup()`, hoặc do `fork()` tạo tiến trình con) trỏ tới cấu trúc `open file description X` này không. Nếu không còn, Kernel giải phóng `open file description` và các tài nguyên I/O liên quan. Lưu ý: bản thân tệp (inode) trên hệ thống tệp vẫn tiếp tục tồn tại bình thường nếu nó còn đường dẫn (pathname) hoặc liên kết trỏ tới.

### 7.2 Số `fd` có thể được tái chế (Reuse)

Hệ điều hành luôn ưu tiên cấp phát con số `fd` nhỏ nhất đang trống. Sau khi bạn `close(3)`, lần gọi `open()` tiếp theo rất có khả năng sẽ nhận lại đúng số `3`.
Do đó: **Không bao giờ coi số `fd` là một mã định danh toàn cục hay vĩnh viễn**.

### 7.3 Xử lý cẩn trọng khi `close()` báo lỗi

Trên Linux, một số lỗi I/O có thể bị hoãn lại và chỉ bộc lộ khi gọi `close()`. Tuy nhiên, ngay cả khi `close()` trả về `-1`, Kernel thực tế đã giải phóng slot `fd` đó.
Việc viết code tự động thử lại (`retry`) lệnh `close(fd)` khi có lỗi là rất nguy hiểm, vì slot `fd` đó có thể đã được một luồng (thread) khác tái sử dụng để mở một tệp hoàn toàn mới. Nếu retry, bạn sẽ vô tình đóng nhầm tệp của luồng khác.

---

## 8. `blocking` và `nonblocking` I/O

Cơ chế chặn (Blocking) giúp luồng CPU được đưa vào trạng thái ngủ khi chờ dữ liệu; ngược lại, Không chặn (Non-blocking) bắt Kernel trả quyền điều khiển về ngay lập tức nếu thao tác chưa thể hoàn thành.

### 8.1 `blocking` (Chặn) nghĩa là gì?

Ở chế độ mặc định, nếu một thao tác I/O chưa thể phục vụ ngay lập tức, luồng thực thi (thread) sẽ bị Kernel đưa vào trạng thái ngủ (Sleep/Wait queue) để chờ đợi sự kiện.

```text
[ Ứng dụng gọi read() ]
        |
[ Kernel kiểm tra: Chưa có dữ liệu ]
        |
[ Luồng ứng dụng bị ĐƯA VÀO TRẠNG THÁI NGỦ (Block) ] ---> (Giải phóng CPU cho tác vụ khác)
        |
[ Phần cứng/Mạng đẩy dữ liệu đến ]
        |
[ Kernel đánh thức (Wake up) luồng ứng dụng ]
        |
[ Hàm read() tiếp tục thực thi và trả về dữ liệu ]
```

> **Đọc sơ đồ:** Thuật ngữ `blocking` mô tả **ngữ nghĩa chờ đợi chủ động của hệ điều hành**. Thread bị chặn sẽ ngủ và nhường CPU cho các tác vụ khác. Tuy nhiên, nó không phải là kiến trúc duy nhất cho mọi loại tải (workload). Ví dụ, các máy chủ mạng cần xử lý hàng chục ngàn kết nối đồng thời thường ưu tiên I/O bất đồng bộ hoặc kết hợp Non-blocking với `epoll`.

### 8.2 `blocking` KHÔNG phải là `busy loop` (Vòng lặp bận)

Cơ chế chặn là cách hiệu quả để nhường CPU. Nó khác hoàn toàn với việc dùng vòng lặp đốt CPU để chờ:
```c
// ĐÂY LÀ ANTI-PATTERN (Gây tốn chu kỳ CPU)
while(không_có_dữ_liệu) {
    kiểm_tra_lại(); 
}
```

### 8.3 Hành vi chặn phụ thuộc vào đặc tính đối tượng

*   **Tệp thông thường (Regular file):** Ngữ nghĩa sẵn sàng (readiness) khác với mạng. Nếu dữ liệu đã nằm trong `page cache`, thao tác có thể hoàn thành ngay từ RAM. Ngược lại, nếu phải chờ I/O từ thiết bị lưu trữ, luồng có thể bị đưa vào trạng thái ngủ (thường là uninterruptible sleep) trong khi Kernel xử lý thao tác với đĩa.
*   **Pipe / FIFO / Socket:** Phụ thuộc cực mạnh vào tốc độ luân chuyển dữ liệu của đối tác (peer) đầu kia và trạng thái vùng đệm.
*   **Terminal / Device:** Phụ thuộc vào tốc độ nhập liệu hoặc trạng thái của driver phần cứng.

### 8.4 Chế độ Không chặn (Cờ `O_NONBLOCK`)

Nếu lúc gọi `open()` (hoặc cấu hình sau bằng `fcntl()`) bạn bật cờ `O_NONBLOCK`, Kernel sẽ thay đổi chiến thuật:
Nếu thao tác đọc/ghi đòi hỏi phải chờ đợi, Kernel sẽ lập tức từ chối, trả quyền điều khiển về cho ứng dụng với mã lỗi `EAGAIN` hoặc `EWOULDBLOCK`.

### 8.5 `nonblocking` không đảm bảo "thời gian thực thi bằng 0"

Cờ `O_NONBLOCK` chỉ đảm bảo hàm sẽ trả về ngay nếu tài nguyên **chưa sẵn sàng cung cấp/nhận dữ liệu theo giao diện API**.
Đặc biệt, với tệp thông thường và thiết bị khối (block device), cờ `O_NONBLOCK` thường không mang lại ngữ nghĩa readiness giống như pipe hay socket; thao tác I/O vẫn có thể bị chặn bởi quá trình truy xuất thiết bị lưu trữ.

---

## 9. Giá trị trả về, `errno` và các lỗi quan trọng

Mọi API hệ thống đều dùng giá trị trả về (Return value) để báo tin trạng thái. Biến `errno` chỉ đóng vai trò thuyết minh chi tiết nguyên nhân khi có báo cáo thất bại.

### 9.1 Nguyên tắc sống còn: Kiểm tra giá trị trả về trước

Giá trị trả về chính là bản hợp đồng giao thức I/O:
*   **`open()`**: Trả về `fd` hợp lệ (>= 0), hoặc `-1` (Lỗi).
*   **`read()`**: Trả số byte thành công (> 0), `0` (EOF/End-of-stream), hoặc `-1` (Lỗi).
*   **`write()`**: Trả số byte thành công (> 0), `0` (Không ghi được byte nào, không đồng nghĩa với EOF), hoặc `-1` (Lỗi).
*   **`lseek()`**: Trả mốc offset mới, hoặc `-1` (Lỗi).
*   **`close()`**: Trả `0` (Thành công), hoặc `-1` (Lỗi).

### 9.2 Tìm hiểu các kiểu dữ liệu đo lường

*   `size_t`: Kiểu số nguyên không dấu (unsigned), dùng để định cỡ bộ đệm/count truyền vào.
*   `ssize_t`: Kiểu số nguyên CÓ dấu (signed), dùng để biểu diễn lượng byte (>0) và giá trị âm `-1` mang cờ báo lỗi.
*   `off_t`: Kiểu dữ liệu chuyên biệt để biểu diễn tọa độ `file offset` hiện tại.

### 9.3 Cách sử dụng biến `errno`

Khi system call thất bại, Kernel trả về một mã trạng thái nội bộ. Thư viện chuẩn C (`libc`) bọc hàm gọi này sẽ tiếp nhận trạng thái đó, trả về `-1` cho ứng dụng và thiết lập giá trị cho biến `errno` (trong các ứng dụng đa luồng, `errno` được triển khai dưới dạng biến cục bộ của luồng - `thread-local` - để tránh xung đột).

**Lưu ý:** Chỉ phân tích `errno` KHI VÀ CHỈ KHI lệnh gọi vừa báo thất bại. Việc đọc `errno` sau một lệnh thành công là không an toàn, vì hàm thành công không có nghĩa vụ phải reset `errno` về 0.

### 9.4 Lỗi `EBADF` (Bad File Descriptor)

Thông báo rằng con số `fd` bạn truyền vào không hợp lệ cho tác vụ hiện tại.
*Nguyên nhân phổ biến:* Kiểm tra xem `fd` đã bị `close()` trước đó chưa, hàm `open()` có thực sự thành công không, hoặc ứng dụng đang cố dùng hàm `write()` đè lên một `fd` mở bằng cờ `O_RDONLY`.

### 9.5 Lỗi ngắt tín hiệu `EINTR` (Interrupted system call)

Xảy ra khi một lời gọi hệ thống đang bị `blocking` chờ đợi bị một Ngắt tín hiệu (Signal) cắt ngang trước khi nó kịp hoàn thành công việc.

Không nên tự động lặp lại (retry) vô điều kiện khi gặp `EINTR`. Cần phân tích:
*   Hàm `read/write` đã kịp xử lý được một lượng byte nào chưa (nếu có, nó sẽ trả về số byte thay vì lỗi).
*   Bản thân ứng dụng có đang cố tình muốn hủy bỏ luồng thực thi thông qua Signal đó không.

### 9.6 Lỗi chưa sẵn sàng `EAGAIN` / `EWOULDBLOCK`

Trong chế độ Không chặn (`O_NONBLOCK`), mã lỗi này mang thông điệp: tài nguyên tạm thời chưa sẵn sàng cung cấp/nhận dữ liệu. Đây là trạng thái điều khiển luồng luân phiên bình thường, không phải là lỗi hệ thống.

---

## 10. Tư duy gỡ lỗi File I/O

Khi làm việc với File I/O, hãy bám sát trình tự phân lớp: `fd` có hợp lệ không? Cờ truy cập đúng không? Giá trị trả về là gì? Và đối tượng đang tương tác thuộc loại nào?

### 10.1 Khi `open()` thất bại

Hãy debug đúng theo trình tự phân giải mà Kernel đi qua:
1.  **Pathname (ENOENT):** Đường dẫn có tồn tại không?
2.  **Mount/Filesystem:** Phân vùng đó có đang sống không?
3.  **Traverse Permission (EACCES):** Các thư mục cha trên đường dẫn có bị mất quyền `x` không?
4.  **File Permission (EACCES / EROFS):** Bạn có đủ quyền `r/w` trên tệp đích không? Hệ thống tệp có đang bị khóa chế độ Read-only không?
5.  **Flags (EINVAL / EISDIR):** Các cờ mở tệp có xung đột với loại đối tượng không? (ví dụ cố mở thư mục để Ghi).
6.  **Resource Limit (EMFILE / ENFILE):** Tiến trình hoặc hệ thống có bị cạn kiệt số lượng `fd` tối đa cho phép mở không?

Đối chiếu `errno` với sơ đồ lớp này sẽ nhanh hơn nhiều so với việc sửa code I/O.

### 10.2 Khi `read()` trả về `0` (Phân tích EOF)

Tùy vào đối tượng mà `0` mang ngữ nghĩa khác biệt:
*   **Tệp thông thường:** Vị trí offset hiện tại đã tới cuối tệp.
*   **Pipe / FIFO:** Bộ đệm đã trống rỗng và không còn tiến trình nào mở đầu ghi (writer) của ống.
*   **Socket mạng:** Máy tính đối tác đã thực hiện thủ tục đóng kết nối chiều gửi dữ liệu (Half-close).
*   **Device phần cứng:** Hành vi `0` hoàn toàn do ngữ nghĩa mà trình điều khiển (Driver) định nghĩa.

Vì vậy, tuyệt đối không xử lý `read() == 0` bằng một phương pháp chung cho mọi loại `fd`.

### 10.3 Đọc ít hơn yêu cầu (Short read)

Short read là ngữ nghĩa tự nhiên của hệ điều hành, đặc biệt trên luồng mạng và thiết bị ngoại vi. Cần đem số byte đã nhận đi xử lý, và tiếp tục lặp để đọc phần còn lại.

### 10.4 Khi `write()` ghi ít hơn yêu cầu (Short write)

Phần chưa ghi vẫn là trách nhiệm của ứng dụng:
```text
Yêu cầu ban đầu (requested)  = N
Đã ghi thành công (written) = M
Cần phải ghi tiếp (remaining)= N - M
```
Lập trình viên phải điều khiển vòng lặp tịnh tiến con trỏ buffer và gửi lệnh `write()` cho phần `remaining` còn lại.

### 10.5 Khi `lseek()` khước từ với lỗi `ESPIPE`

Bạn đang cố thay đổi vị trí (seek) trên một thiết bị dòng chảy (Stream) vốn dĩ không hỗ trợ khả năng định vị ngẫu nhiên (Pipe, Socket, Terminal).

### 10.6 Thiết bị có `fd` nhưng I/O trả lỗi lạ

Hãy nhớ sự tách biệt trừu tượng:
Mở `fd` thành công không đồng nghĩa là phần cứng (Hardware) hay trình điều khiển (Driver) bên dưới đang hoạt động chuẩn xác. Lệnh `read/write` hoàn toàn có thể ném ra những mã lỗi dị biệt từ cấp driver.

---

## 11. Liên hệ với Embedded Linux

Trong thế giới nhúng (Embedded Linux), mô hình `fd` quen thuộc được sử dụng để làm việc với cả tệp cấu hình, UART, GPIO, pipe, socket và các `device node`.

### 11.1 Tương tác Thiết bị qua `device node`

Ứng dụng trên mạch nhúng giao tiếp với ngoại vi bằng cách thao tác `fd` với các tệp ảo:
*   `/dev/ttyS*` hoặc `/dev/ttyUSB*` (Giao tiếp Serial / UART).
*   `/dev/i2c-*` (Bus I2C).
*   `/dev/spidev*` (Bus SPI).
*   `/dev/gpiochip*` (Giao diện điều khiển GPIO).

Sau lệnh `open()` thành công trên các tệp này, luồng I/O thường vẫn đi qua mô hình:
`fd -> read / write / ioctl / mmap -> close`.

### 11.2 Điều khiển cổng Serial (UART)

Giao tiếp UART ở Userspace thực chất là:
1.  `open` tệp tty.
2.  Cấu hình tốc độ baud/parity qua cấu trúc `termios`.
3.  `read/write` qua `fd`.
`read()` trên UART thể hiện rất rõ các khái niệm: có thể bị chặn (blocking), trả về vài byte (short read), bị ngắt bởi tín hiệu, hoặc thay đổi hành vi tùy thuộc vào cấu hình TTY (chế độ Raw hay Canonical).

### 11.3 Giao diện điều khiển GPIO hiện đại

Linux hiện đại quản lý GPIO qua chuẩn `character-device API` thông qua `file descriptor` (`/dev/gpiochip*` cùng `libgpiod`) cho việc yêu cầu luồng chân pin hay ngắt sự kiện. Điều này chứng minh `file descriptor` là abstraction cốt lõi nối kết nhiều hệ thống phụ lại với nhau.

### 11.4 Các điểm neo `/proc` và `/sys`

Dù giao diện tĩnh của một số thư mục cấu trúc ảo (như sysfs legacy `/sys/class/gpio`) vẫn dùng `open`, `read`, `write`, `close`, nhưng nội dung không thực sự tồn tại trên ổ lưu trữ. Việc ghi vào các tệp ảo này là bạn đang gọi vào các hàm callback (interface) của Kernel. Trình điều khiển (driver) nhận dữ liệu này và sau đó có thể tiến hành thay đổi trạng thái hoặc cấu hình thanh ghi phần cứng tương ứng.

### 11.5 Phương pháp Bring-up mạch nhúng

Khi I/O điều khiển phần cứng thất bại, việc gỡ lỗi hệ thống yêu cầu không dừng lại ở thông báo lỗi của hàm `read()`, mà cần bóc tách sâu theo lớp:
```text
[ Tầng Userspace: fd / API gọi đúng không? ]
                    |
[ Tầng Driver: Mã nguồn C của Kernel có tương tác đúng không? ]
                    |
[ Tầng Hệ thống: Cấu trúc Device Tree / Bus / Xung clock / Pinctrl gán đúng chưa? ]
                    |
[ Tầng Hardware: Mạch/Chip vật lý hoạt động ổn định không? ]
```

---

## 12. Tổng kết

Topic 03 thiết lập chặt chẽ quy trình xương sống của File I/O: 

```text
[ Pathname ]
      |
   open()    (Kernel tìm Object, tạo open file description và phân quyền)
      |
      v
    [ fd ]   (Chỉ mục tham chiếu tại Tiến trình)
      |
      +---> read()
      +---> write()
      +---> lseek()
      +---> close()
```

> **Đọc sơ đồ:** Giai đoạn trên cùng (`Pathname` -> `open`) là bước dò đường và xác lập môi trường. Sau khi `open()` thành công, tiến trình sử dụng tham chiếu `fd` để trao đổi dữ liệu. `read()` và `write()` có thể hoàn thành một phần (partial I/O), `lseek()` dịch chuyển file offset (chỉ áp dụng cho các đối tượng hỗ trợ ngữ nghĩa seek, điển hình là tệp thông thường), và `close()` trả lại chỉ mục `fd` để tái sử dụng. Nhờ cơ chế trừu tượng của VFS/FD, Linux cung cấp một khuôn mẫu API chung để thao tác với ổ cứng, bàn phím, mạng LAN hay các giao diện phần cứng, bất kể sự khác biệt về ngữ nghĩa bên dưới.

**Các mốc tư duy cần lưu ý:**
1. `fd` là một số nguyên cục bộ trong một tiến trình.
2. `fd` không phải là Inode vật lý và không phải là con trỏ bộ nhớ không gian người dùng.
3. `open file description` là cấu trúc do Kernel quản lý chứa `file offset` và các trạng thái cờ.
4. Hiện tượng `read()` và `write()` đọc/ghi một phần (Partial I/O) là hợp lệ, ứng dụng phải tự vòng lặp xử lý.
5. Lệnh `read() == 0` biểu thị EOF/End-of-stream chứ không phải lỗi hệ thống. `write() == 0` không mang nghĩa EOF.
6. Cờ `O_APPEND` đảm bảo tính nguyên tử (atomic) trên các hệ thống cục bộ mạnh mẽ hơn việc tự nối lệnh `lseek(end)` + `write()`.
7. `write()` báo thành công không có nghĩa dữ liệu đã được khắc vĩnh viễn xuống bộ nhớ lưu trữ vật lý.
8. Lệnh `lseek()` trả lỗi `ESPIPE` nếu áp dụng lên các luồng động như Socket, Pipe.
9. `close()` xóa bỏ tham chiếu `fd` của tiến trình; đối tượng bên dưới vẫn tồn tại nếu còn các tham chiếu khác.
10. `Blocking I/O` cho phép luồng ngủ chờ sự kiện thay vì vắt kiệt CPU bởi `busy loop`.
11. `EAGAIN` trong Non-blocking báo hiệu "tài nguyên tạm thời chưa sẵn sàng", không phải lỗi hệ thống.
12. Chỉ đánh giá biến `errno` KHI VÀ CHỈ KHI API báo cáo thất bại theo quy ước (thường là `-1`).

---

## 13. Tài liệu tham khảo

Phần này liệt kê tài liệu chuẩn man-pages và POSIX cho các `system call` và khái niệm I/O đã dùng trong Topic 03.

- `open(2)`: https://man7.org/linux/man-pages/man2/open.2.html
- `read(2)`: https://man7.org/linux/man-pages/man2/read.2.html
- `write(2)`: https://man7.org/linux/man-pages/man2/write.2.html
- `lseek(2)`: https://man7.org/linux/man-pages/man2/lseek.2.html
- `close(2)`: https://man7.org/linux/man-pages/man2/close.2.html
- `fcntl(2)`: https://man7.org/linux/man-pages/man2/fcntl.2.html
- `errno(3)`: https://man7.org/linux/man-pages/man3/errno.3.html
- Linux VFS documentation: https://docs.kernel.org/filesystems/vfs.html
- POSIX.1-2024 System Interfaces: https://pubs.opengroup.org/onlinepubs/9799919799/
- The Linux Programming Interface: https://man7.org/tlpi/
- Bootlin Embedded Linux training: https://bootlin.com/training/embedded-linux/

> **Điều hướng:** [← Chủ đề 2 — Hệ thống tệp Linux](README-topic-02.md) · [Chủ đề 4 — Tiến trình →](README-topic-04.md)
