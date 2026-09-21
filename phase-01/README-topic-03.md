# Phần cập nhật cho README-topic-03.md

## 1. `file descriptor` là gì?

Sau khi hệ thống mở thành công một đối tượng I/O, Linux trả về cho chương trình một số nguyên nhỏ gọi là `file descriptor` (`fd`). Chương trình sẽ dùng con số này làm tham chiếu cho mọi thao tác đọc, ghi và đóng tệp sau đó.

### 1.1 File I/O rộng hơn tệp thông thường

Trong triết lý UNIX/Linux, các API `read()` và `write()` có thể làm việc với vô số loại đối tượng khác nhau:

* Tệp văn bản/nhị phân thông thường (`regular file`).
* Đường ống (`pipe`) và `FIFO`.
* Giao diện dòng lệnh (`terminal`).
* Kết nối mạng (`socket`).
* Thiết bị phần cứng (`device node`).
* Các mục cấu hình trong `procfs`/`sysfs`.

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

### 1.3 Một tiến trình có thể mở bao nhiêu `file descriptor`?

Bảng `file descriptor` của một tiến trình **không có số lượng phần tử khả dụng vô hạn**. Linux sử dụng một resource limit có tên `RLIMIT_NOFILE` để giới hạn việc cấp thêm `file descriptor` cho tiến trình.

`RLIMIT_NOFILE` được hiểu là:

> **một giá trị lớn hơn 1 so với số hiệu `fd` lớn nhất mà tiến trình có thể được cấp.**

Ví dụ, nếu giới hạn hiện tại là:

```text
RLIMIT_NOFILE = 1024
```

thì các số hiệu `fd` có thể được cấp nằm trong khoảng:

```text
0 ... 1023
```

Tổng cộng có **1024 giá trị `fd` khả dụng về mặt đánh số**, chứ không phải 1023.

Trong một tiến trình thông thường, ba `fd` đầu tiên thường đã được sử dụng:

```text
fd 0 -> stdin
fd 1 -> stdout
fd 2 -> stderr
```

Nếu `RLIMIT_NOFILE = 1024`, ba `fd` trên vẫn đang mở và chưa có `fd` nào khác được sử dụng, thì tiến trình còn có thể cấp thêm tối đa:

```text
1024 - 3 = 1021 file descriptor
```

cho các đối tượng I/O khác như regular file, socket, pipe hoặc device.

Điều cần nhớ là **1024 không phải một hằng số cố định của Linux**. Giá trị giới hạn phụ thuộc vào cấu hình và resource limit của từng tiến trình.

#### Soft limit và Hard limit

Mỗi resource limit thường có hai mức:

```text
Soft limit
    |
    +-- Giới hạn hiện tại mà Kernel thực sự áp dụng

Hard limit
    |
    +-- Trần tối đa mà soft limit được phép nâng tới
```

Ví dụ:

```text
Soft limit = 1024
Hard limit = 4096
```

thì hiện tại tiến trình bị giới hạn ở mức `1024`, không phải `4096`.

Một tiến trình không có đặc quyền có thể thay đổi soft limit trong khoảng từ `0` đến hard limit:

```text
soft: 1024 -> 2048     OK
soft: 2048 -> 4096     OK
soft: 4096 -> 8192     Không được vì vượt hard limit
```

Vì vậy, có thể ghi nhớ:

> **Soft limit là giới hạn đang được áp dụng; Hard limit là giới hạn tối đa mà Soft limit có thể được nâng tới.**

Có thể xem giới hạn `fd` của shell hiện tại bằng:

```bash
ulimit -n
```

Lệnh này thường hiển thị **soft limit** của `RLIMIT_NOFILE`.

Muốn xem đồng thời cả soft limit và hard limit của tiến trình:

```bash
cat /proc/$$/limits
```

Ví dụ:

```text
Limit                     Soft Limit     Hard Limit
Max open files            1024           4096
```

Nếu tiến trình cần cấp thêm một `fd` nhưng việc cấp đó vượt `RLIMIT_NOFILE`, các lời gọi tạo `fd` như `open()`, `pipe()` hoặc `dup()` có thể thất bại với lỗi:

```text
EMFILE
Too many open files
```

Điểm này sẽ được gặp lại ở phần **10.1 Khi `open()` thất bại**.

> **Lưu ý:** Nói “process mở tối đa 1021 file” là chưa chính xác. Nếu giới hạn là 1024 và `fd 0`, `1`, `2` đang được sử dụng, tiến trình còn **1021 vị trí `fd`** để cấp thêm. Các vị trí đó có thể trỏ tới regular file, socket, pipe, device... chứ không chỉ là file trên filesystem.

### 1.4 `fd` không phải inode

* `inode` là cấu trúc dữ liệu mô tả đối tượng nằm ở tầng Filesystem (như đã học ở Topic 02).
* `fd` là tham chiếu giao dịch nằm ở tầng Tiến trình (Process context).
* Hai tiến trình có thể cùng sở hữu biến `fd = 3`, nhưng hai số `3` này có thể trỏ tới hai đối tượng/inode hoàn toàn khác nhau.

### 1.5 `fd` không phải con trỏ bộ nhớ (pointer) ở userspace

Ứng dụng không thể thao tác trực tiếp với bộ nhớ thông qua `fd` như một con trỏ C/C++ (`*ptr`). Nó bắt buộc phải truyền con số này vào các `system call`:

```c
read(fd, buffer, size);
write(fd, buffer, size);
close(fd);
```

Linux Kernel sẽ nhận con số `fd` này, tra cứu trong File Descriptor Table của tiến trình gọi lệnh để tìm ra đối tượng thực sự cần thao tác.
