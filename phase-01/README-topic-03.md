# Chủ đề 3 — Vào/ra tệp trong Linux

> **Mục tiêu:** hiểu một chương trình Linux thực sự đọc/ghi dữ liệu như thế nào thông qua bộ mô tả tệp (`file descriptor`, viết tắt `fd`) và các lời gọi hệ thống `open()`, `read()`, `write()`, `lseek()`, `close()`.
>
> **Quy ước ngôn ngữ:** phần giải thích dùng Tiếng Việt. Giữ nguyên tên API, cờ, mã lỗi và các thuật ngữ chuẩn khó dịch như `fd`, `EOF`, `O_NONBLOCK`, `errno`.
>
> **Phạm vi:** bộ mô tả tệp, mô tả tệp đang mở, `open`, quyền truy cập, cờ mở tệp, `read`, `write`, I/O từng phần, EOF, vị trí đọc/ghi, `lseek`, `close`, I/O chặn/không chặn ở mức cơ bản, `errno`, `EINTR`, `EAGAIN`.
>
> Chương này chỉ có **lý thuyết**, không có bài thực hành.

---

## Mục lục

- [1. Bộ mô tả tệp là gì?](#1-bộ-mô-tả-tệp-là-gì)
- [2. Từ đường dẫn đến tệp đang mở](#2-từ-đường-dẫn-đến-tệp-đang-mở)
- [3. `open()`: mở một đối tượng I/O](#3-open-mở-một-đối-tượng-io)
- [4. `read()`: đọc dữ liệu](#4-read-đọc-dữ-liệu)
- [5. `write()`: ghi dữ liệu](#5-write-ghi-dữ-liệu)
- [6. Vị trí đọc/ghi và `lseek()`](#6-vị-trí-đọcghi-và-lseek)
- [7. `close()` và vòng đời bộ mô tả tệp](#7-close-và-vòng-đời-bộ-mô-tả-tệp)
- [8. I/O chặn và không chặn](#8-io-chặn-và-không-chặn)
- [9. Giá trị trả về, `errno` và các lỗi quan trọng](#9-giá-trị-trả-về-errno-và-các-lỗi-quan-trọng)
- [10. Tư duy gỡ lỗi File I/O](#10-tư-duy-gỡ-lỗi-file-io)
- [11. Liên hệ với Embedded Linux](#11-liên-hệ-với-embedded-linux)
- [12. Tổng kết](#12-tổng-kết)
- [13. Tài liệu tham khảo](#13-tài-liệu-tham-khảo)

---

## 1. Bộ mô tả tệp là gì?

> **Nói đơn giản:** sau khi mở một tệp hoặc thiết bị, Linux đưa cho tiến trình một số nguyên nhỏ như `3`, `4`, `5`. Số đó là `fd`. Các lời gọi I/O sau này dùng `fd` thay vì phải tìm lại pathname mỗi lần.

### 1.1 File I/O rộng hơn regular file

Trong Linux, các API `read()` và `write()` có thể làm việc với nhiều loại đối tượng:

```text
regular file
pipe
FIFO
terminal
socket
device node
procfs/sysfs entry trong một số trường hợp
```

Vì vậy “File I/O” trong Linux thường nên hiểu là:

```text
I/O thông qua file descriptor
```

chứ không chỉ là đọc/ghi tệp trên đĩa.

### 1.2 File descriptor

Một `fd` là một số nguyên không âm dùng làm chỉ mục trong bảng descriptor của tiến trình.

```text
Process
+---------------------------+
| fd table                  |
| 0 -> stdin                |
| 1 -> stdout               |
| 2 -> stderr               |
| 3 -> object A             |
| 4 -> object B             |
+---------------------------+
```

### 1.3 `fd` không phải inode

`inode` thuộc lớp filesystem object.

`fd` thuộc ngữ cảnh của một tiến trình.

Hai tiến trình có thể cùng có:

```text
fd = 3
```

nhưng hai số `3` này có thể trỏ tới hai đối tượng hoàn toàn khác nhau.

### 1.4 `fd` không phải con trỏ ở userspace

Ứng dụng không dereference `fd` như địa chỉ bộ nhớ.

Nó truyền số đó vào lời gọi hệ thống:

```text
read(fd, ...)
write(fd, ...)
close(fd)
```

Nhân Linux dùng số này để tra bảng descriptor của tiến trình.

---

## 2. Từ đường dẫn đến tệp đang mở

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

> pathname chủ yếu được dùng để **tìm và mở đối tượng**; I/O sau đó dùng descriptor.

### 2.2 Mô tả tệp đang mở

Linux/POSIX phân biệt:

```text
file descriptor
```

và trạng thái tệp đang mở ở cấp hệ thống, thường gọi là:

```text
open file description
```

Trong tài liệu này ta gọi là **mô tả tệp đang mở**.

Nó chứa các trạng thái như:

```text
file offset
file status flags
reference tới object bên dưới
```

### 2.3 Quan hệ tổng thể

```text
pathname
   |
   v
VFS lookup
   |
   v
inode / filesystem object
   |
   v
mô tả tệp đang mở
   |
   v
fd trong process
```

Không phải mọi đối tượng đều có inode theo cùng cách, nhưng mô hình này rất hữu ích cho regular file.

---

## 3. `open()`: mở một đối tượng I/O

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

Nếu thất bại:

```text
return -1
errno chứa nguyên nhân
```

### 3.2 Chế độ truy cập

Ba chế độ cơ bản:

```text
O_RDONLY
O_WRONLY
O_RDWR
```

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

> `open()` không phải lúc nào cũng là thao tác “chỉ đọc metadata”; nó có thể thay đổi dữ liệu/trạng thái tệp.

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

### 4.1 `read()` yêu cầu đọc tối đa một số byte

Tư duy:

```text
read(fd, buffer, count)
```

có nghĩa:

> “hãy đọc **tối đa** `count` byte vào buffer”.

Không có nghĩa:

> “phải trả đủ `count` byte mới thành công”.

### 4.2 Giá trị trả về

```text
> 0
  số byte thực sự đã đọc

= 0
  EOF / end-of-stream theo loại object

= -1
  lỗi, xem errno
```

### 4.3 Đọc ngắn không phải lỗi

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
file offset đã tới cuối
```

Pipe:

```text
không còn writer và dữ liệu đệm đã hết
```

TCP stream:

```text
peer đóng chiều gửi có trật tự và dữ liệu đã đọc hết
```

Vì vậy “`read() == 0`” phải được hiểu trong ngữ cảnh object.

---

## 5. `write()`: ghi dữ liệu

### 5.1 `write()` cũng có thể hoàn thành một phần

```text
write(fd, buffer, count)
```

có thể trả về:

```text
M
0 < M < count
```

Nghĩa là chỉ `M` byte đầu đã được chấp nhận/ghi theo ngữ nghĩa API.

### 5.2 Vì sao ghi ngắn tồn tại?

Có thể do:

```text
pipe/socket buffer chỉ còn một phần chỗ
resource limit
signal
thiết bị/driver
filesystem condition
nonblocking I/O
```

Do đó code đúng phải xem **giá trị trả về**, không chỉ xem có `-1` hay không.

### 5.3 Ghi thành công không đồng nghĩa dữ liệu đã bền vững trên thiết bị lưu trữ

Một `write()` thành công thường chỉ chứng minh nhân Linux/filesystem đã chấp nhận dữ liệu theo interface.

Dữ liệu có thể còn ở:

```text
page cache
filesystem cache
controller cache
storage cache
```

Độ bền khi mất điện là vấn đề khác, liên quan `fsync()`, filesystem, thiết bị và policy.

### 5.4 Với pipe/socket

Ghi thành công cũng không có nghĩa ứng dụng ở đầu kia đã xử lý dữ liệu.

Ví dụ:

```text
send/write thành công
     |
     v
kernel buffer
     |
     v
network/peer
     |
     v
peer application
```

Mỗi lớp có trạng thái riêng.

---

## 6. Vị trí đọc/ghi và `lseek()`

### 6.1 File offset

Với regular file có thể seek, mô tả tệp đang mở giữ một vị trí byte hiện tại:

```text
0 1 2 3 4 5 6 7 ...
        ^
        |
     file offset
```

`read()`/`write()` thông thường có thể làm vị trí này thay đổi.

### 6.2 `lseek()`

`lseek()` thay đổi file offset.

Nó không tự đọc hay ghi dữ liệu.

### 6.3 Ba mốc phổ biến

```text
SEEK_SET
  tính từ đầu tệp

SEEK_CUR
  tính từ vị trí hiện tại

SEEK_END
  tính từ cuối tệp
```

### 6.4 Seek vượt qua EOF

Với regular file, có thể đặt offset vượt quá cuối tệp.

Chỉ riêng việc seek không nhất thiết làm tệp lớn lên.

Nếu sau đó ghi dữ liệu tại vị trí xa hơn, filesystem có thể tạo vùng hole/sparse tùy ngữ nghĩa.

### 6.5 Không phải object nào cũng seek được

Ví dụ thường không seek:

```text
pipe
FIFO
socket
terminal
nhiều character device
```

`lseek()` có thể trả `ESPIPE` với đối tượng không hỗ trợ seek.

---

## 7. `close()` và vòng đời bộ mô tả tệp

### 7.1 `close(fd)` đóng cái gì?

Nó giải phóng **descriptor entry của tiến trình**.

```text
fd table

3 -> object

close(3)

3 -> free slot
```

### 7.2 Số fd có thể được dùng lại

Sau khi `fd = 3` đóng, lần mở tiếp theo có thể nhận lại `3`.

Do đó:

> một số fd không phải định danh toàn cục hoặc định danh vĩnh viễn của tài nguyên.

### 7.3 Object có thể còn tồn tại

Nếu vẫn còn tham chiếu khác:

```text
fd khác
dup reference
process khác sau fork
kernel reference
mapping/reference khác
```

việc đóng một fd chưa chắc hủy object phía dưới.

### 7.4 Không tự ý `close()` lại sau lỗi

Trên Linux, một số lỗi được báo trong `close()` sau khi fd đã được giải phóng.

Việc retry mù quáng có thể nguy hiểm vì số fd có thể đã được tái sử dụng cho một object khác.

Đây là ví dụ cho thấy giá trị trả về và ngữ nghĩa của API phải được đọc chính xác.

---

## 8. I/O chặn và không chặn

### 8.1 Chặn nghĩa là gì?

Nếu thao tác chưa thể hoàn thành ngay, luồng thực thi có thể ngủ trong nhân Linux để chờ sự kiện.

```text
read()
  |
chưa có dữ liệu
  |
thread ngủ
  |
dữ liệu đến
  |
wakeup
  |
read tiếp tục
```

### 8.2 Chặn không phải busy-loop

Chặn đúng nghĩa cho phép CPU chạy công việc khác.

Nó khác với:

```text
while(no_data) {
    check_again();
}
```

### 8.3 Hành vi phụ thuộc loại object

Regular file:

```text
thường không có readiness semantics giống pipe/socket
```

Pipe/FIFO/socket:

```text
rất phụ thuộc dữ liệu/buffer/peer state
```

Terminal/device:

```text
phụ thuộc driver, mode, line discipline
```

### 8.4 `O_NONBLOCK`

Khi trạng thái không chặn được bật, một thao tác vốn phải chờ có thể trả ngay với:

```text
EAGAIN
hoặc
EWOULDBLOCK
```

Tùy interface.

### 8.5 Không chặn không có nghĩa “không bao giờ chậm”

`O_NONBLOCK` chủ yếu thay đổi hành vi khi object **chưa sẵn sàng theo interface**.

Nó không hứa mọi đường đi trong filesystem/kernel/hardware đều có thời gian bằng 0.

---

## 9. Giá trị trả về, `errno` và các lỗi quan trọng

### 9.1 Đừng bỏ qua giá trị trả về

Với I/O, giá trị trả về là một phần của giao thức.

```text
open
  fd hoặc -1

read/write
  số byte / 0 / -1

lseek
  offset mới hoặc -1

close
  0 hoặc -1
```

### 9.2 `size_t`, `ssize_t`, `off_t`

```text
size_t
  kiểu không dấu dùng cho kích thước/count

ssize_t
  kiểu có dấu để vừa biểu diễn byte count vừa biểu diễn -1

off_t
  kiểu biểu diễn file offset
```

### 9.3 `errno`

Khi lời gọi thất bại và API quy định dùng `errno`, chương trình đọc `errno` để biết nguyên nhân.

Không nên đọc `errno` sau một lời gọi thành công rồi suy luận lỗi.

### 9.4 `EBADF`

Thường biểu thị descriptor không hợp lệ cho thao tác hiện tại.

Hỏi:

```text
fd đã đóng?
fd chưa từng mở?
fd có đúng access mode?
```

### 9.5 `EINTR`

Lời gọi bị signal làm gián đoạn trước khi hoàn thành theo ngữ nghĩa tương ứng.

Không nên hiểu:

```text
EINTR = cứ retry vô điều kiện
```

Cần xem:

```text
đã có partial progress chưa?
application có muốn hủy không?
signal handler có thay state không?
```

### 9.6 `EAGAIN` / `EWOULDBLOCK`

Trong I/O không chặn, thường có nghĩa:

```text
hiện tại chưa thể hoàn thành
```

không phải lỗi vĩnh viễn.

---

## 10. Tư duy gỡ lỗi File I/O

### 10.1 `open()` thất bại

Kiểm tra theo lớp:

```text
pathname đúng?
  |
filesystem/mount đúng?
  |
quyền directory prefix?
  |
quyền object?
  |
flags phù hợp?
  |
resource limit?
```

### 10.2 `read()` trả `0`

Hỏi object là gì:

```text
regular file -> EOF?
pipe -> hết writer?
socket -> peer half-close/EOF?
device -> driver semantics?
```

### 10.3 Đọc ít hơn yêu cầu

Không vội kết luận lỗi. Short read là ngữ nghĩa bình thường của nhiều object.

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
fd layer đúng
không đồng nghĩa
driver/hardware/protocol layer đúng
```

---

## 11. Liên hệ với Embedded Linux

### 11.1 Device node

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

UART userspace thường là:

```text
open tty
configure termios
read/write fd
```

`read()` có thể chặn, trả ít byte, bị signal làm gián đoạn hoặc chịu ảnh hưởng của cấu hình TTY.

### 11.3 GPIO character-device API

Linux GPIO hiện đại dùng file descriptor cho chip/line request/event.

Điều này cho thấy file descriptor là abstraction chung của nhiều subsystem.

### 11.4 `/proc` và `/sys`

Một số interface đọc/ghi dạng text vẫn dùng:

```text
open
read
write
close
```

nhưng nội dung được tạo/xử lý bởi kernel subsystem chứ không phải regular file trên storage.

### 11.5 Board bring-up

Khi I/O thất bại, cần phân lớp:

```text
userspace fd/API
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
2. `fd` không phải inode và không phải con trỏ userspace.
3. Pathname được dùng để tìm/mở object; I/O sau đó dùng descriptor.
4. Mô tả tệp đang mở chứa trạng thái như file offset và status flags.
5. `read()` và `write()` có thể hoàn thành một phần.
6. `read() == 0` không phải lỗi; thường là EOF theo ngữ nghĩa object.
7. `O_APPEND` mạnh hơn tự ghép `lseek(end)` + `write()`.
8. `write()` thành công không đồng nghĩa dữ liệu đã bền vững trên thiết bị.
9. `lseek()` chỉ phù hợp với object có seek semantics.
10. `close()` giải phóng descriptor; số fd có thể được tái sử dụng.
11. Blocking I/O cho phép thread ngủ chờ thay vì busy-loop.
12. `EAGAIN` trong nonblocking I/O thường nghĩa “chưa sẵn sàng ngay lúc này”.
13. `errno` chỉ có ý nghĩa khi API báo thất bại theo quy ước tương ứng.

---

## 13. Tài liệu tham khảo

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
