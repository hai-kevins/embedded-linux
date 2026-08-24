# Chủ đề 3 — File I/O trong Linux

> **Mục tiêu:** hiểu một chương trình Linux thực sự đọc/ghi dữ liệu như thế nào thông qua `file descriptor` (viết tắt `fd`) và các `system call` `open()`, `read()`, `write()`, `lseek()`, `close()`.
>
> **Quy ước ngôn ngữ:** phần giải thích dùng Tiếng Việt. Các thuật ngữ Linux/POSIX cần phân biệt chính xác như `file descriptor`, `open file description`, `file offset`, `partial I/O`, `short read`, `blocking`, `nonblocking`, `EOF`, `errno`, cùng tên API, cờ và mã lỗi được giữ bằng tiếng Anh.
>
> **Phạm vi:** `file descriptor`, `open file description`, `open`, quyền truy cập, cờ mở tệp, `read`, `write`, `partial I/O`, EOF, `file offset`, `lseek`, `close`, `blocking`/`nonblocking` I/O ở mức cơ bản, `errno`, `EINTR`, `EAGAIN`.
>
> Chương này chỉ có **lý thuyết**, không có bài thực hành.

Ý tưởng trung tâm của File I/O trên Linux rất đơn giản: **pathname chủ yếu dùng để tìm và mở một đối tượng; sau khi mở thành công, chương trình làm việc với đối tượng đó thông qua file descriptor (`fd`)**. Vì thế cần phân biệt rõ tên tệp, `inode`, open file description và con số `fd` mà tiến trình đang giữ.

Từ mô hình đó, các API `open()`, `read()`, `write()`, `lseek()` và `close()` trở thành một chuỗi logic thay vì năm hàm rời rạc. Phần còn lại của chương tập trung vào giá trị trả về, `partial I/O`, EOF, `blocking`/`nonblocking` và cách suy luận khi một lời gọi thất bại.

**Cách đọc nếu bạn mới bắt đầu.** Trước hết hãy đọc phần **Nói đơn giản** ở đầu mỗi mục lớn để nắm câu hỏi mà mục đó đang giải quyết. Sau đó xem sơ đồ và ví dụ để hình thành mô hình trong đầu; chưa cần nhớ mọi cờ, mã lỗi hay trường hợp đặc biệt. Khi ý chính đã rõ, hãy đọc các mục `###` theo thứ tự và quay lại phần giải thích trước đó nếu gặp một thuật ngữ chưa quen.

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

> **Nói đơn giản:** Sau khi mở một đối tượng I/O, Linux trả về một số nguyên nhỏ gọi là `file descriptor` (`fd`). Chương trình dùng số này cho các thao tác đọc, ghi và đóng.

### 1.1 File I/O rộng hơn tệp thông thường

Trong Linux, các API `read()` và `write()` có thể làm việc với nhiều loại đối tượng:

```text
tệp thông thường
pipe
FIFO
terminal
socket
device node
mục trong procfs/sysfs trong một số trường hợp
```

Vì vậy “File I/O” trong Linux thường nên hiểu là:

```text
I/O thông qua file descriptor
```

chứ không chỉ là đọc/ghi tệp trên đĩa.

### 1.2 `file descriptor`

Một `fd` là một số nguyên không âm dùng làm chỉ mục trong bảng file descriptor của tiến trình.

```text
Tiến trình
+---------------------------+
| bảng fd                  |
| 0 -> stdin                |
| 1 -> stdout               |
| 2 -> stderr               |
| 3 -> đối tượng A             |
| 4 -> đối tượng B             |
+---------------------------+
```

### 1.3 `fd` không phải inode

`inode` thuộc lớp đối tượng trong filesystem.

`fd` thuộc ngữ cảnh của một tiến trình.

Hai tiến trình có thể cùng có:

```text
fd = 3
```

nhưng hai số `3` này có thể trỏ tới hai đối tượng hoàn toàn khác nhau.

### 1.4 `fd` không phải con trỏ ở userspace

Ứng dụng không thể dùng `fd` như một con trỏ hay địa chỉ bộ nhớ.

Nó truyền số đó vào `system call`:

```text
read(fd, ...)
write(fd, ...)
close(fd)
```

Linux kernel dùng số này để tra bảng file descriptor của tiến trình.

---

## 2. Từ đường dẫn đến tệp đang mở

> **Nói đơn giản:** Pathname chủ yếu dùng để tìm đối tượng lúc mở. Sau khi `open()` thành công, chương trình làm việc với `fd` và trạng thái tệp đang mở.

### 2.1 Hai giai đoạn khác nhau

Đầu tiên:

```text
pathname
   |
   v
open()
```

Sau khi `open()` thành công:

```text
fd
 |
 +--> read()
 +--> write()
 +--> lseek()
 +--> close()
```

Điểm quan trọng:

> pathname chủ yếu được dùng để **tìm và mở đối tượng**; I/O sau đó dùng `fd`.

### 2.2 `open file description`

Linux/POSIX phân biệt:

```text
file descriptor
```

và trạng thái tệp đang mở ở cấp hệ thống, thường gọi là:

```text
open file description
```

Trong tài liệu này giữ nguyên tên **`open file description`** vì đây là thuật ngữ chuẩn của POSIX/Linux; không nên dịch thành một cụm Việt khác dễ bị nhầm với `file descriptor`.

Nó chứa các trạng thái như:

```text
file offset hiện tại
các cờ trạng thái của tệp
tham chiếu tới đối tượng bên dưới
```

### 2.3 Quan hệ tổng thể

```text
pathname
   |
   v
VFS tìm pathname
   |
   v
inode / đối tượng trong filesystem
   |
   v
open file description
   |
   v
fd trong tiến trình
```

Không phải mọi đối tượng đều có inode theo cùng cách, nhưng mô hình này rất hữu ích cho tệp thông thường.

---

## 3. `open()`: mở một đối tượng I/O

> **Nói đơn giản:** `open()` yêu cầu Linux kernel tìm pathname, kiểm tra quyền/cờ mở và tạo trạng thái cần thiết. Thành công thì nhận `fd`; thất bại thì nhận lỗi.

### 3.1 `open()` làm gì?

Ở mức tư duy:

```text
pathname
  |
  v
phân giải đường dẫn
  |
kiểm tra quyền / cờ
  |
tạo hoặc tham chiếu trạng thái open
  |
  v
fd
```

Nếu thành công:

```text
return >= 0
```

Nếu thất bại: return -1 và errno chứa nguyên nhân.

### 3.2 Chế độ truy cập

Ba chế độ cơ bản: `O_RDONLY`, `O_WRONLY` và `O_RDWR`.

Đây là chế độ của **lần mở hiện tại**.

Nó khác với mode `r/w/x` của filesystem.

### 3.3 Quyền filesystem và quyền của fd

Hai lớp:

```text
filesystem permission
     |
     v
open() có được cho phép không?
     |
     v
fd được tạo với access mode nào?
```

Sau khi `open()` thành công, quyền của fd đã được xác lập cho lần mở đó theo ngữ nghĩa hệ thống.

### 3.4 `O_CREAT`

`O_CREAT` cho phép tạo tệp nếu pathname chưa tồn tại.

Khi đó tham số mode mô tả các bit quyền được yêu cầu, sau đó chịu ảnh hưởng của `umask` và có thể cả ACL/policy khác.

### 3.5 `O_TRUNC`

Khi dùng trong điều kiện phù hợp, tệp hiện có có thể bị rút kích thước về `0` khi mở.

Đây là ví dụ cho thấy:

> `open()` không phải lúc nào cũng là thao tác “chỉ đọc siêu dữ liệu”; nó có thể thay đổi dữ liệu/trạng thái tệp.

### 3.6 `O_APPEND`

Khi trạng thái append được thiết lập, mỗi lần ghi được thực hiện với vị trí phù hợp ở cuối tệp theo ngữ nghĩa append của hệ thống.

Điều này mạnh hơn cách tự làm:

```text
lseek(end)
write(...)
```

vì giữa hai thao tác rời rạc có thể xuất hiện tranh chấp từ tiến trình khác.

### 3.7 `O_CLOEXEC`

`O_CLOEXEC` thiết lập close-on-exec ngay trong thao tác mở.

Mục đích:

```text
fd không bị giữ ngoài ý muốn qua execve()
```

Thiết lập nguyên tử ngay khi mở đặc biệt quan trọng trong chương trình đa luồng vì tránh cửa sổ tranh chấp giữa `open()` và thao tác đặt flag sau đó.

---

## 4. `read()`: đọc dữ liệu

> **Nói đơn giản:** `read()` yêu cầu đọc tối đa một số byte. Giá trị trả về mới cho biết thực tế đọc được bao nhiêu; ít hơn yêu cầu vẫn có thể hoàn toàn bình thường.

### 4.1 `read()` yêu cầu đọc tối đa một số byte

Tư duy:

```text
read(fd, buffer, count)
```

có nghĩa:

> “hãy đọc **tối đa** `count` byte vào bộ đệm”.

Không có nghĩa:

> “phải trả đủ `count` byte mới thành công”.

### 4.2 Giá trị trả về

```text
> 0
  số byte thực sự đã đọc

= 0
  EOF / end-of-stream theo loại đối tượng

= -1
  lỗi, xem errno
```

### 4.3 `short read` không phải lỗi

Ví dụ yêu cầu:

```text
4096 byte
```

nhưng `read()` trả:

```text
300 byte
```

vẫn có thể hoàn toàn hợp lệ.

Nguyên nhân phụ thuộc đối tượng:

```text
file còn ít byte
pipe chỉ có ít dữ liệu
socket mới nhận một phần
terminal có một dòng/ký tự theo chế độ
signal làm gián đoạn sau khi đã có tiến triển
```

### 4.4 EOF khác lỗi

EOF:

```text
return 0
```

Lỗi:

```text
return -1
errno = ...
```

Hai trạng thái này phải được xử lý khác nhau.

### 4.5 EOF phụ thuộc loại đối tượng

Regular file:

```text
file offset hiện tại đã tới cuối
```

Pipe:

```text
không còn writer và dữ liệu đệm đã hết
```

TCP stream:

```text
peer đã đóng chiều gửi theo `orderly shutdown` và dữ liệu đã đọc hết
```

Vì vậy “`read() == 0`” phải được hiểu trong ngữ cảnh đối tượng.

---

## 5. `write()`: ghi dữ liệu

> **Nói đơn giản:** `write()` cũng có thể ghi ít byte hơn yêu cầu. Chương trình đúng phải dựa vào giá trị trả về thay vì giả sử một lần gọi luôn ghi đủ.

### 5.1 `write()` cũng có thể hoàn thành một phần

```text
write(fd, buffer, count)
```

có thể trả về: `M` và 0 < M < count.

Nghĩa là chỉ `M` byte đầu đã được chấp nhận/ghi theo ngữ nghĩa API.

### 5.2 Vì sao ghi ngắn tồn tại?

Có thể do:

```text
pipe/bộ đệm socket chỉ còn một phần chỗ
resource limit
signal
thiết bị/driver
filesystem condition
nonblocking I/O
```

Do đó code đúng phải xem **giá trị trả về**, không chỉ xem có `-1` hay không.

### 5.3 Ghi thành công không đồng nghĩa dữ liệu đã bền vững trên thiết bị lưu trữ

Một `write()` thành công thường chỉ chứng minh Linux kernel/filesystem đã chấp nhận dữ liệu theo giao diện.

Dữ liệu có thể còn ở: `page cache`, cache của filesystem, cache của controller và cache của thiết bị lưu trữ.

Độ bền khi mất điện là vấn đề khác, liên quan `fsync()`, filesystem, thiết bị và policy.

### 5.4 Với pipe/socket

Ghi thành công cũng không có nghĩa ứng dụng ở đầu kia đã xử lý dữ liệu.

Ví dụ:

```text
send/write thành công
     |
     v
Linux kernel buffer
     |
     v
network/peer
     |
     v
ứng dụng ở đầu bên kia
```

Mỗi lớp có trạng thái riêng.

---

## 6. Vị trí đọc/ghi và `lseek()`

> **Nói đơn giản:** Regular file thường có `file offset` hiện tại. `lseek()` thay đổi vị trí này, nhưng không phải mọi loại `fd` đều hỗ trợ seek.

### 6.1 `file offset`

Với tệp thông thường có thể seek, `open file description` giữ một vị trí byte hiện tại:

```text
0 1 2 3 4 5 6 7 ...
        ^
        |
     file offset hiện tại
```

`read()`/`write()` thông thường có thể làm vị trí này thay đổi.

### 6.2 `lseek()`

`lseek()` thay đổi `file offset` hiện tại.

Nó không tự đọc hay ghi dữ liệu.

### 6.3 Ba mốc phổ biến

`SEEK_SET`: tính từ đầu tệp; `SEEK_CUR`: tính từ vị trí hiện tại; `SEEK_END`: tính từ cuối tệp.

### 6.4 `seek` vượt qua EOF

Với tệp thông thường, có thể đặt offset vượt quá cuối tệp.

Chỉ riêng việc seek không nhất thiết làm tệp lớn lên.

Nếu sau đó ghi dữ liệu tại vị trí xa hơn, filesystem có thể tạo vùng hole/sparse tùy ngữ nghĩa.

### 6.5 Không phải đối tượng nào cũng `seek` được

Ví dụ thường không seek: pipe, `FIFO`, socket, terminal và nhiều character device.

`lseek()` có thể trả `ESPIPE` với đối tượng không hỗ trợ seek.

---

## 7. `close()` và vòng đời `file descriptor`

> **Nói đơn giản:** `close()` bỏ tham chiếu `fd` của tiến trình. Nếu còn tham chiếu khác tới cùng đối tượng thì tài nguyên bên dưới chưa chắc được giải phóng ngay.

### 7.1 `close(fd)` đóng cái gì?

Nó giải phóng **mục `file descriptor` của tiến trình**.

```text
bảng fd

3 -> đối tượng

close(3)

3 -> free slot
```

### 7.2 Số fd có thể được dùng lại

Sau khi `fd = 3` đóng, lần mở tiếp theo có thể nhận lại `3`.

Do đó:

> một số fd không phải định danh toàn cục hoặc định danh vĩnh viễn của tài nguyên.

### 7.3 Đối tượng có thể còn tồn tại

Nếu vẫn còn tham chiếu khác:

```text
fd khác
tham chiếu do dup tạo
tiến trình khác sau fork
tham chiếu của Linux kernel
ánh xạ/tham chiếu khác
```

việc đóng một fd chưa chắc hủy đối tượng phía dưới.

### 7.4 Không tự ý `close()` lại sau lỗi

Trên Linux, một số lỗi được báo trong `close()` sau khi fd đã được giải phóng.

Việc retry mù quáng có thể nguy hiểm vì số fd có thể đã được tái sử dụng cho một đối tượng khác.

Đây là ví dụ cho thấy giá trị trả về và ngữ nghĩa của API phải được đọc chính xác.

---

## 8. `blocking` và `nonblocking` I/O

> **Nói đơn giản:** I/O chặn có thể làm luồng phải chờ dữ liệu hoặc chờ tài nguyên; I/O không chặn trả về ngay nếu chưa thể tiếp tục. Topic này chỉ cần hiểu khác biệt cơ bản đó.

### 8.1 `blocking` nghĩa là gì?

Nếu thao tác chưa thể hoàn thành ngay, luồng thực thi có thể ngủ trong Linux kernel để chờ sự kiện.

```text
read()
  |
chưa có dữ liệu
  |
luồng ngủ
  |
dữ liệu đến
  |
wakeup
  |
read tiếp tục
```

### 8.2 `blocking` không phải `busy loop`

Chặn đúng nghĩa cho phép CPU chạy công việc khác.

Nó khác với:

```text
while(no_data) {
    check_again();
}
```

### 8.3 Hành vi phụ thuộc loại đối tượng

Regular file:

```text
thường không có readiness ngữ nghĩa giống pipe/socket
```

Pipe/FIFO/socket:

```text
phụ thuộc mạnh vào dữ liệu, trạng thái buffer và peer
```

Terminal/device:

```text
phụ thuộc driver, mode, line discipline
```

### 8.4 `O_NONBLOCK`

Khi trạng thái không chặn được bật, một thao tác vốn phải chờ có thể trả về ngay với `EAGAIN` hoặc `EWOULDBLOCK`, tùy giao diện.


### 8.5 `nonblocking` không có nghĩa “không bao giờ chậm”

`O_NONBLOCK` chủ yếu thay đổi hành vi khi đối tượng **chưa sẵn sàng theo giao diện**.

Nó không hứa mọi đường đi trong filesystem/Linux kernel/hardware đều có thời gian bằng 0.

---

## 9. Giá trị trả về, `errno` và các lỗi quan trọng

> **Nói đơn giản:** System call thường báo thành công/thất bại bằng giá trị trả về; khi lỗi, `errno` cho biết nguyên nhân cụ thể như bị ngắt hoặc tạm thời chưa có dữ liệu.

### 9.1 Đừng bỏ qua giá trị trả về

Với I/O, giá trị trả về là một phần của giao thức.

**open**: fd hoặc -1; `read/write`: số byte / 0 / -1; **lseek**: offset mới hoặc -1; **close**: 0 hoặc -1.

### 9.2 `size_t`, `ssize_t`, `off_t`

`size_t`: kiểu không dấu dùng cho kích thước/count; `ssize_t`: kiểu có dấu để vừa biểu diễn byte count vừa biểu diễn -1; `off_t`: kiểu biểu diễn `file offset` hiện tại.

### 9.3 `errno`

Khi lời gọi thất bại và API quy định dùng `errno`, chương trình đọc `errno` để biết nguyên nhân.

Không nên đọc `errno` sau một lời gọi thành công rồi suy luận lỗi.

### 9.4 `EBADF`

Thường biểu thị bộ mô tả không hợp lệ cho thao tác hiện tại.

Hãy kiểm tra: `fd` đã bị đóng chưa, nó có thực sự được mở thành công không và access mode có phù hợp với thao tác hiện tại không.

### 9.5 `EINTR`

Lời gọi bị signal làm gián đoạn trước khi hoàn thành theo ngữ nghĩa tương ứng.

Không nên hiểu:

```text
EINTR = cứ retry vô điều kiện
```

Cần xem lời gọi đã xử lý được một phần dữ liệu chưa, ứng dụng có chủ động muốn hủy thao tác không và signal handler có làm thay đổi trạng thái liên quan hay không.

### 9.6 `EAGAIN` / `EWOULDBLOCK`

Trong I/O không chặn, thường có nghĩa:

```text
hiện tại chưa thể hoàn thành
```

không phải lỗi vĩnh viễn.

---

## 10. Tư duy gỡ lỗi File I/O

> **Nói đơn giản:** Debug File I/O nên đi theo thứ tự: `fd` có hợp lệ không, quyền/cờ mở đúng không, giá trị trả về là gì, `errno` là gì và loại đối tượng đang đọc/ghi là gì.

### 10.1 `open()` thất bại

Kiểm tra theo lớp:

```text
pathname đúng?
  |
filesystem/mount đúng?
  |
quyền directory prefix?
  |
quyền đối tượng?
  |
flags phù hợp?
  |
resource limit?
```

### 10.2 `read()` trả `0`

Hỏi đối tượng là gì:

```text
tệp thông thường -> EOF?
pipe -> hết writer?
socket -> peer `half-close`/EOF?
device -> driver ngữ nghĩa?
```

### 10.3 Đọc ít hơn yêu cầu

Không vội kết luận lỗi. Short read là ngữ nghĩa bình thường của nhiều đối tượng.

### 10.4 `write()` ghi ít hơn yêu cầu

Phần chưa ghi vẫn còn trách nhiệm của ứng dụng.

```text
requested = N
written = M
remaining = N - M
```

### 10.5 `lseek()` trả `ESPIPE`

Đối tượng có thể không seek được.

### 10.6 Thiết bị có fd nhưng I/O lạ

Hãy nhớ:

```text
fd lớp đúng
không đồng nghĩa
driver/hardware/lớp giao thức đúng
```

---

## 11. Liên hệ với Embedded Linux

> **Nói đơn giản:** Trên Embedded Linux, cùng mô hình `fd` được dùng để làm việc với tệp cấu hình, UART, GPIO qua sysfs cũ, pipe, socket và nhiều `device node`.

### 11.1 `device node`

Ứng dụng nhúng thường tương tác với:

```text
/dev/ttyS*
/dev/i2c-*
/dev/spidev*
/dev/gpiochip*
/dev/input/*
```

Sau `open()`, phần lớn luồng I/O vẫn quay về mô hình:

```text
fd
read/write/ioctl/mmap...
```

### 11.2 UART

UART không gian người dùng thường là:

```text
open tty
configure termios
read/write fd
```

`read()` có thể chặn, trả ít byte, bị signal làm gián đoạn hoặc chịu ảnh hưởng của cấu hình TTY.

### 11.3 GPIO character-device API

Linux GPIO hiện đại dùng `file descriptor` cho chip/line request/event.

Điều này cho thấy `file descriptor` là abstraction chung của nhiều subsystem.

### 11.4 `/proc` và `/sys`

Một số giao diện dạng văn bản vẫn dùng `open`, `read`, `write` và `close`, nhưng nội dung được tạo hoặc xử lý bởi subsystem của kernel chứ không phải một tệp thông thường nằm trên thiết bị lưu trữ.

### 11.5 Board bring-up

Khi I/O thất bại, cần phân lớp:

```text
không gian người dùng fd/API
   |
driver
   |
device tree / bus / pinctrl / clock
   |
hardware
```

Không nên dừng ở câu “`read()` bị lỗi”.

---

## 12. Tổng kết

> **Nói đơn giản:** Topic 03 cần để lại mô hình: pathname → `open()` → `fd` → `read/write/lseek` → `close()`.

```text
pathname
   |
 open()
   |
   v
fd
   |
   +--> read()
   +--> write()
   +--> lseek()
   +--> close()
```

Các ý cần nhớ:

1. `fd` là số nguyên cục bộ trong một tiến trình.
2. `fd` không phải inode và không phải con trỏ không gian người dùng.
3. Pathname được dùng để tìm/mở đối tượng; I/O sau đó dùng `fd`.
4. `Open file description` chứa trạng thái như `file offset` hiện tại và `file status flags`.
5. `read()` và `write()` có thể hoàn thành một phần.
6. `read() == 0` không phải lỗi; thường là EOF theo ngữ nghĩa đối tượng.
7. `O_APPEND` mạnh hơn tự ghép `lseek(end)` + `write()`.
8. `write()` thành công không đồng nghĩa dữ liệu đã bền vững trên thiết bị.
9. `lseek()` chỉ phù hợp với đối tượng có seek ngữ nghĩa.
10. `close()` giải phóng bộ mô tả; số fd có thể được tái sử dụng.
11. Blocking I/O cho phép luồng ngủ chờ thay vì busy-loop.
12. `EAGAIN` trong `nonblocking` I/O thường nghĩa “chưa sẵn sàng ngay lúc này”.
13. `errno` chỉ có ý nghĩa khi API báo thất bại theo quy ước tương ứng.

---

## 13. Tài liệu tham khảo

> **Nói đơn giản:** Phần này liệt kê tài liệu chuẩn cho các `system call` và khái niệm I/O đã dùng trong Topic 03.

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
