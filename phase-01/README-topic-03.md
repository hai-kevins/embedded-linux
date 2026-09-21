# Topic 03 — File I/O cơ bản trong Linux

> **Mục tiêu:** Hiểu mô hình File I/O ở tầng system call của Linux: `file descriptor`, `open file description`, `open()`, `read()`, `write()`, `lseek()`, `close()`, blocking/nonblocking I/O và cách xử lý lỗi cơ bản.
>
> **Phạm vi:** `file descriptor`, giới hạn số lượng `fd` (`RLIMIT_NOFILE`, soft limit, hard limit), `open file description`, `open`, quyền truy cập, cờ mở tệp, `read`, `write`, `partial I/O`, EOF, `file offset`, `lseek`, `close`, `blocking`/`nonblocking` I/O ở mức cơ bản, `errno`, `EINTR`, `EAGAIN`.
>
> **Chưa đi sâu ở Topic này:** `select/poll/epoll`, asynchronous I/O, `io_uring`, page cache, `mmap`, VFS internals, locking, direct I/O.

---

## 1. `file descriptor` là gì?

Sau khi hệ thống mở thành công một đối tượng I/O, Linux trả về cho chương trình một số nguyên không âm gọi là **file descriptor** (`fd`).

Chương trình sẽ sử dụng con số này để tham chiếu đến đối tượng I/O trong các system call như:

```c
read(fd, buffer, size);
write(fd, buffer, size);
close(fd);
```

Điểm rất quan trọng:

> `fd` không phải chính file, không phải inode và cũng không phải con trỏ userspace. Nó là một **handle dạng số nguyên** mà process dùng để yêu cầu Kernel thao tác với một đối tượng I/O.

### 1.1 File I/O rộng hơn regular file

Trong UNIX/Linux, cùng các API như `read()` và `write()` có thể được dùng với nhiều loại đối tượng:

- regular file;
- terminal;
- pipe/FIFO;
- socket;
- device node;
- một số interface trong `/proc` và `/sys`.

Vì vậy, khi học **File I/O trong Linux**, nên hiểu rộng hơn là:

> **I/O thông qua file descriptor**, chứ không chỉ là đọc/ghi file trên ổ lưu trữ.

Ví dụ:

```text
fd
│
├── regular file
├── terminal
├── pipe
├── socket
└── device
```

### 1.2 `file descriptor` hoạt động như thế nào?

Mỗi process có ngữ cảnh quản lý các file descriptor mà nó đang sử dụng.

Có thể hình dung đơn giản:

```text
Process A
│
└── File Descriptor Table
    │
    ├── fd 0 ──> stdin
    ├── fd 1 ──> stdout
    ├── fd 2 ──> stderr
    ├── fd 3 ──> đối tượng I/O X
    └── fd 4 ──> đối tượng I/O Y
```

Ba file descriptor quen thuộc thường tồn tại khi chương trình được shell khởi chạy:

```text
fd 0 -> standard input  (stdin)
fd 1 -> standard output (stdout)
fd 2 -> standard error  (stderr)
```

Ví dụ:

```bash
echo "hello"
```

`echo` thường ghi dữ liệu vào:

```text
fd 1 -> terminal
```

Nếu redirect:

```bash
echo "hello" > output.txt
```

thì shell sắp xếp để:

```text
fd 1 -> output.txt
```

Chương trình `echo` vẫn ghi vào `fd 1`; chỉ có đối tượng mà `fd 1` tham chiếu tới đã thay đổi.

#### `fd` là số cục bộ trong ngữ cảnh process

Hai process có thể đều có:

```text
fd = 3
```

nhưng không nhất thiết cùng tham chiếu một đối tượng:

```text
Process A                  Process B
---------                  ---------
fd 3 ──> /etc/config       fd 3 ──> socket
```

Do đó không thể chỉ nhìn số `3` rồi kết luận hai process đang dùng cùng một file.

> Ở các Topic sau khi học `fork()`, `dup()` và thread, ta sẽ thấy có những trường hợp nhiều execution context có thể chia sẻ hoặc kế thừa các tham chiếu file descriptor. Hiện tại chỉ cần nắm mô hình cơ bản ở trên.

### 1.3 Một process có thể mở bao nhiêu `file descriptor`?

Số file descriptor mà process có thể sử dụng **không vô hạn**.

Linux sử dụng resource limit `RLIMIT_NOFILE` để giới hạn việc cấp thêm file descriptor cho process.

Theo định nghĩa của Linux:

> `RLIMIT_NOFILE` là giá trị **lớn hơn 1 so với số hiệu file descriptor lớn nhất** mà process có thể được cấp.

Ví dụ:

```text
RLIMIT_NOFILE = 1024
```

thì các số hiệu `fd` có thể nằm trong khoảng:

```text
0 ... 1023
```

Tổng cộng:

```text
1024 giá trị fd
```

chứ không phải 1023.

Nếu:

```text
fd 0 -> stdin
fd 1 -> stdout
fd 2 -> stderr
```

đều đang được sử dụng và chưa có descriptor nào khác, thì số slot còn lại là:

```text
1024 - 3 = 1021
```

Nhưng phải diễn đạt chính xác:

> Process còn **1021 file descriptor có thể cấp thêm**, không phải “chỉ mở được 1021 file”.

Bởi vì các descriptor đó có thể dùng cho:

```text
regular file
socket
pipe
device
...
```

Ngoài ra, `0`, `1`, `2` không phải các slot bất biến. Nếu chúng bị đóng, các số đó có thể được Kernel tái sử dụng cho những descriptor mới.

#### 1.3.1 `1024` không phải hằng số cố định của Linux

Không nên học thuộc:

```text
Mọi process Linux đều có tối đa 1024 fd
```

Câu này sai.

Giới hạn thực tế phụ thuộc vào resource limit của process và cấu hình hệ thống.

Kiểm tra soft limit của shell hiện tại:

```bash
ulimit -n
```

Có thể xem cả soft/hard limit bằng:

```bash
ulimit -Sn
ulimit -Hn
```

Hoặc:

```bash
cat /proc/$$/limits
```

Ví dụ:

```text
Limit                     Soft Limit     Hard Limit
Max open files            1024           1048576
```

#### 1.3.2 Soft limit và Hard limit

Mỗi resource limit có hai mức quan trọng:

```text
Soft limit
    │
    └── giới hạn hiện tại mà Kernel thực sự áp dụng

Hard limit
    │
    └── trần mà soft limit được phép nâng tới
```

Ví dụ:

```text
soft = 1024
hard = 4096
```

thì process hiện tại bị giới hạn ở:

```text
1024
```

không phải 4096.

Process không có đặc quyền có thể nâng soft limit tối đa tới hard limit:

```text
soft: 1024 -> 2048       OK
soft: 2048 -> 4096       OK
soft: 4096 -> 8192       Không được
```

Có thể ghi nhớ:

> **Soft limit = giới hạn đang được thực thi.**  
> **Hard limit = trần của soft limit.**

Process không đặc quyền cũng có thể hạ hard limit của chính nó, nhưng sau khi hạ thì không thể tự nâng trở lại vượt quá hard limit mới. Việc nâng hard limit cần đặc quyền phù hợp, trên Linux liên quan tới `CAP_SYS_RESOURCE`.

#### 1.3.3 Điều gì xảy ra khi hết file descriptor?

Nếu process cần một descriptor mới nhưng việc cấp descriptor sẽ vượt `RLIMIT_NOFILE`, các lời gọi như:

```text
open()
pipe()
dup()
...
```

có thể thất bại với:

```text
EMFILE
Too many open files
```

Cần phân biệt:

```text
EMFILE
└── process đã chạm giới hạn file descriptor của chính nó

ENFILE
└── hệ thống chạm giới hạn tài nguyên open-file ở mức system-wide
```

Phần lỗi sẽ được quay lại ở mục 10.

### 1.4 `fd` không phải inode

`inode` và `fd` nằm ở hai tầng khái niệm khác nhau.

```text
fd
│
└── handle mà process dùng để thực hiện I/O

inode
│
└── metadata/object của filesystem mô tả một file
```

Một `fd` không trực tiếp đồng nghĩa với một inode.

Giữa chúng còn có các cấu trúc Kernel khác, đặc biệt là **open file description**.

Mô hình chính xác hơn:

```text
Process
│
└── fd
    │
    v
Open File Description
    │
    v
Filesystem object / inode
```

### 1.5 `fd` không phải con trỏ bộ nhớ ở userspace

Ví dụ:

```c
int fd = open("data.txt", O_RDONLY);
```

Nếu:

```text
fd = 3
```

thì `3` không phải địa chỉ bộ nhớ mà chương trình có thể dereference:

```c
*fd;        // sai về mặt khái niệm
```

Chương trình bắt buộc phải đưa `fd` trở lại Kernel thông qua system call:

```c
read(fd, buffer, size);
write(fd, buffer, size);
close(fd);
```

Kernel dùng `fd` làm khóa tra cứu để xác định đối tượng cần thao tác.

---

## 2. `open file description` là gì?

Đây là khái niệm rất quan trọng để hiểu đúng File I/O.

Khi:

```c
int fd = open("data.txt", O_RDONLY);
```

Linux không đơn giản tạo ra một số `fd`.

Có thể hình dung Kernel tạo một **open file description** đại diện cho một lần mở đối tượng đó, rồi đặt một tham chiếu đến nó trong bảng file descriptor của process.

```text
Process
│
└── fd 3
    │
    v
Open File Description
    │
    ├── current file offset
    ├── file status flags
    └── reference tới filesystem object
```

Trong Linux kernel, khái niệm này gắn với file object (`struct file`).

### 2.1 `fd` và `open file description` không phải một

`fd`:

```text
là chỉ số trong bảng descriptor
```

Open file description:

```text
là trạng thái Kernel của một lần mở file
```

Ví dụ:

```text
fd 3
  │
  v
+-----------------------------+
| Open File Description       |
| file offset = 120           |
| status flags = O_RDONLY     |
| ...                         |
+-----------------------------+
```

### 2.2 File offset nằm ở open file description

Giả sử file:

```text
ABCDE
```

Sau:

```c
read(fd, buf, 2);
```

offset thường dịch:

```text
ban đầu: 0
sau read 2 byte: 2
```

Trạng thái offset này thuộc **open file description**, không phải nội dung inode.

Điều này rất quan trọng khi sau này học:

```text
dup()
fork()
```

vì nhiều file descriptor có thể tham chiếu cùng một open file description và do đó chia sẻ offset.

### 2.3 Mở cùng một pathname hai lần

Ví dụ:

```c
int fd1 = open("data.txt", O_RDONLY);
int fd2 = open("data.txt", O_RDONLY);
```

Thông thường ta có:

```text
fd1 ──> Open File Description A ──┐
                                  ├──> cùng file/inode
fd2 ──> Open File Description B ──┘
```

A và B là hai lần mở riêng biệt, nên có thể có hai file offset độc lập.

Ví dụ:

```text
fd1 offset = 100
fd2 offset = 0
```

Dù cả hai cùng đọc một file.

### 2.4 Tên file không phải thứ mà `read()` sử dụng

Sau khi `open()` thành công:

```c
int fd = open("/tmp/data.txt", O_RDONLY);
```

các thao tác tiếp theo không cần pathname:

```c
read(fd, buf, sizeof(buf));
close(fd);
```

Do đó có thể hình dung:

```text
pathname
   │
   │ open()
   v
Kernel resolve pathname
   │
   v
open file description
   │
   v
fd trả về cho process
```

Sau đó:

```text
read()/write()/lseek()/close()
```

làm việc thông qua `fd`.

---

## 3. `open()` — mở một đối tượng I/O

Prototype cơ bản:

```c
#include <fcntl.h>

int open(const char *path, int flags, ...);
```

Trường hợp sử dụng `O_CREAT` thường có thêm `mode`:

```c
int open(const char *path, int flags, mode_t mode);
```

Ví dụ:

```c
int fd = open("data.txt", O_RDONLY);
```

Nếu thành công:

```text
return >= 0
```

Nếu thất bại:

```text
return -1
errno được thiết lập
```

### 3.1 `open()` làm gì về mặt mô hình?

Có thể hình dung:

```text
open("data.txt", O_RDONLY)
        │
        v
Kernel resolve pathname
        │
        v
tạo open file description
        │
        v
chọn một fd chưa dùng
        │
        v
trả fd về userspace
```

Một lần `open()` thành công tạo một **open file description mới**.

File descriptor trả về là descriptor có số nhỏ nhất hiện chưa được sử dụng trong process.

Ví dụ process đang có:

```text
0, 1, 2
```

thì:

```c
open(...)
```

thường trả về:

```text
3
```

Nếu `3` bị đóng nhưng `4`, `5` vẫn đang dùng, lần cấp descriptor tiếp theo có thể tái sử dụng `3`.

### 3.2 Access mode

`flags` phải chỉ định một trong ba access mode chính:

```c
O_RDONLY
O_WRONLY
O_RDWR
```

Ý nghĩa:

```text
O_RDONLY  -> chỉ đọc
O_WRONLY  -> chỉ ghi
O_RDWR    -> đọc và ghi
```

Ví dụ:

```c
int fd = open("config.txt", O_RDONLY);
```

Nếu sau đó cố:

```c
write(fd, buf, len);
```

thì thao tác sẽ thất bại vì descriptor không được mở cho ghi.

### 3.3 Kết hợp flag bằng bitwise OR

Có thể kết hợp nhiều flag:

```c
int fd = open("log.txt",
              O_WRONLY | O_CREAT | O_APPEND,
              0644);
```

Không dùng logical OR:

```c
O_WRONLY || O_CREAT        // sai mục đích
```

mà dùng:

```c
O_WRONLY | O_CREAT         // đúng
```

### 3.4 Một số flag quan trọng

#### `O_CREAT`

Tạo file nếu file chưa tồn tại.

```c
open("data.txt", O_WRONLY | O_CREAT, 0644);
```

Khi dùng `O_CREAT`, cần truyền `mode` để chỉ định permission ban đầu.

Permission thực tế còn bị ảnh hưởng bởi `umask`.

Mô hình đơn giản:

```text
requested mode
      │
      v
    umask
      │
      v
permission thực tế
```

Ví dụ:

```text
requested = 0666
umask     = 0022

kết quả thường là:
0644
```

#### `O_EXCL`

Thường dùng cùng `O_CREAT`:

```c
O_CREAT | O_EXCL
```

Yêu cầu việc tạo file thất bại nếu file đã tồn tại.

Hữu ích khi cần semantics “tạo mới, không ghi đè file đã có”.

#### `O_TRUNC`

Nếu file phù hợp được mở để ghi, nội dung regular file có thể bị truncate về kích thước 0.

Ví dụ:

```c
open("data.txt", O_WRONLY | O_TRUNC);
```

Cần rất cẩn thận vì dữ liệu cũ có thể bị mất ngay khi `open()` thành công.

#### `O_APPEND`

Mở ở chế độ append.

Trước mỗi `write()`, Kernel đặt vị trí ghi ở cuối file và thực hiện việc cập nhật offset + ghi như một bước atomic đối với semantics của local filesystem.

Ví dụ:

```c
open("log.txt", O_WRONLY | O_APPEND);
```

Phù hợp cho log hơn kiểu:

```c
lseek(fd, 0, SEEK_END);
write(fd, ...);
```

vì cách tách `lseek()` và `write()` thành hai system call có thể tạo race khi nhiều writer hoạt động đồng thời.

> Với NFS, semantics append có hạn chế riêng vì client phải mô phỏng append; không nên suy rộng tính chất local filesystem sang mọi network filesystem.

#### `O_NONBLOCK`

Yêu cầu nonblocking mode khi đối tượng hỗ trợ semantics này.

Đặc biệt quan trọng với:

- pipe/FIFO;
- socket;
- terminal;
- device.

Với regular file, `O_NONBLOCK` thường không mang ý nghĩa mà người mới hay hình dung.

#### `O_CLOEXEC`

Đặt close-on-exec cho descriptor ngay lúc tạo.

```c
open(path, O_RDONLY | O_CLOEXEC);
```

Flag này rất quan trọng trong chương trình có nhiều thread vì tránh race khi tạo descriptor rồi mới gọi `fcntl()` để đặt `FD_CLOEXEC`.

Ở Topic này chỉ cần nhận biết:

> `O_CLOEXEC` giúp tránh vô tình để descriptor sống qua `execve()` khi ta không muốn.

### 3.5 Ví dụ `open()`

```c
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

int main(void)
{
    int fd = open("data.txt", O_RDONLY);

    if (fd == -1) {
        perror("open");
        return 1;
    }

    printf("fd = %d\n", fd);

    close(fd);
    return 0;
}
```

Biên dịch:

```bash
gcc -Wall -Wextra -O2 open_demo.c -o open_demo
```

Chạy:

```bash
./open_demo
```

---

## 4. `read()` — đọc dữ liệu

Prototype:

```c
#include <unistd.h>

ssize_t read(int fd, void *buf, size_t count);
```

Ý nghĩa:

```text
fd
  -> đọc tối đa count byte
  -> copy vào buf
```

Giá trị trả về:

```text
> 0   số byte thực sự đọc được
= 0   EOF trong trường hợp thích hợp
= -1  lỗi
```

### 4.1 `read()` không đảm bảo trả đủ `count`

Ví dụ:

```c
char buf[100];

ssize_t n = read(fd, buf, 100);
```

Không được mặc định:

```text
n == 100
```

`read()` có thể trả:

```text
100
60
10
1
0
-1
```

tùy đối tượng và trạng thái I/O.

Đây gọi là **partial read** khi:

```text
0 < n < count
```

Partial read không đồng nghĩa với lỗi.

### 4.2 Ví dụ regular file

Giả sử file chứa:

```text
Hello
```

và:

```c
char buf[100];
ssize_t n = read(fd, buf, 100);
```

có thể:

```text
n = 5
```

vì file chỉ còn 5 byte dữ liệu.

Lần tiếp theo:

```c
n = read(fd, buf, 100);
```

có thể trả:

```text
0
```

nghĩa là đã tới EOF.

### 4.3 EOF không phải lỗi

Với regular file:

```text
read() == 0
```

thường có nghĩa:

```text
đã tới end-of-file
```

Không phải:

```text
error
```

Do đó loop đọc thường có dạng:

```c
while (1) {
    ssize_t n = read(fd, buf, sizeof(buf));

    if (n > 0) {
        /* xử lý n byte */
    } else if (n == 0) {
        /* EOF */
        break;
    } else {
        /* error */
        break;
    }
}
```

### 4.4 Buffer không tự có `'\0'`

Nếu đọc text:

```c
char buf[100];
ssize_t n = read(fd, buf, sizeof(buf));
```

`read()` chỉ copy byte.

Nó không tự thêm:

```c
'\0'
```

Do đó nếu muốn dùng như C string, cần tự đảm bảo còn chỗ:

```c
char buf[100];

ssize_t n = read(fd, buf, sizeof(buf) - 1);

if (n > 0) {
    buf[n] = '\0';
}
```

Không nên:

```c
read(fd, buf, sizeof(buf));
buf[n] = '\0';
```

nếu `n == sizeof(buf)`, vì sẽ ghi vượt buffer.

### 4.5 File offset sau `read()`

Với đối tượng seekable như regular file, nếu đọc được `n` byte:

```text
offset mới = offset cũ + n
```

Ví dụ:

```text
file = ABCDEFGH

offset = 0
read 3 byte -> ABC
offset = 3

read 2 byte -> DE
offset = 5
```

---

## 5. `write()` — ghi dữ liệu

Prototype:

```c
#include <unistd.h>

ssize_t write(int fd, const void *buf, size_t count);
```

Ý nghĩa:

```text
lấy tối đa count byte từ buf
và yêu cầu ghi vào đối tượng fd
```

Giá trị trả về:

```text
>= 0  số byte đã được chấp nhận ghi
-1    lỗi
```

### 5.1 `write()` cũng có thể ghi thiếu

Không được giả định:

```c
write(fd, buf, count) == count
```

Một lời gọi có thể trả:

```text
0 < n < count
```

Đó là **partial write**.

Điều này đặc biệt quan trọng với:

- pipe;
- socket;
- nonblocking I/O;
- signal interruption;
- resource pressure.

Do đó code robust phải xử lý phần dữ liệu chưa ghi.

### 5.2 Không dùng `strlen()` cho dữ liệu binary

Ví dụ:

```c
char data[] = {0x01, 0x00, 0x02};
```

`strlen()` sẽ dừng ở byte `0x00`, nên không thể đại diện đúng kích thước binary buffer.

Với binary data, cần biết kích thước bằng cơ chế khác:

```c
sizeof(data)
```

hoặc một biến `length` riêng.

### 5.3 File offset sau `write()`

Với regular file thông thường:

```text
offset mới = offset cũ + số byte đã ghi
```

Ví dụ:

```text
offset = 10
write() thành công 4 byte
offset = 14
```

Nếu dùng `O_APPEND`, Kernel đưa vị trí ghi tới cuối file trước mỗi write theo semantics của append mode.

---

## 6. `file offset`

`file offset` là vị trí hiện tại dùng cho các thao tác I/O trên open file description đối với đối tượng hỗ trợ seek.

Có thể hình dung file như một dãy byte:

```text
Byte index:

0   1   2   3   4   5   6
A   B   C   D   E   F   G
            ^
            |
         offset = 3
```

Nếu gọi:

```c
read(fd, buf, 2);
```

sẽ đọc:

```text
D E
```

và offset thành:

```text
5
```

### 6.1 Offset thuộc open file description

Nhắc lại mô hình:

```text
fd
 │
 v
Open File Description
 │
 ├── file offset
 └── file status flags
```

Do đó nếu hai descriptor cùng tham chiếu **cùng một open file description**, chúng có thể chia sẻ offset.

Nếu hai lần `open()` tạo hai open file description khác nhau, offset độc lập.

### 6.2 Offset không phải lúc nào cũng tồn tại theo cách regular file có

Không phải mọi object có `fd` đều seekable.

Ví dụ:

```text
regular file -> thường seekable
pipe         -> không seekable
socket       -> không seekable
FIFO         -> không seekable
```

Đây là lý do không nên đồng nhất:

```text
fd == regular file
```

---

## 7. `lseek()` — thay đổi file offset

Prototype:

```c
#include <unistd.h>

off_t lseek(int fd, off_t offset, int whence);
```

`lseek()` thay đổi offset của **open file description** tương ứng với `fd`.

Ba giá trị cơ bản của `whence`:

```c
SEEK_SET
SEEK_CUR
SEEK_END
```

### 7.1 `SEEK_SET`

Offset mới tính từ đầu file:

```c
lseek(fd, 100, SEEK_SET);
```

nghĩa là:

```text
offset = 100
```

### 7.2 `SEEK_CUR`

Offset mới tính từ vị trí hiện tại:

```c
lseek(fd, 10, SEEK_CUR);
```

nghĩa là:

```text
offset_new = offset_current + 10
```

Có thể lấy offset hiện tại bằng:

```c
off_t pos = lseek(fd, 0, SEEK_CUR);
```

nếu đối tượng hỗ trợ seek.

### 7.3 `SEEK_END`

Offset tính từ cuối file:

```c
lseek(fd, 0, SEEK_END);
```

đưa offset tới cuối file.

Ví dụ:

```c
lseek(fd, -10, SEEK_END);
```

có thể đưa offset về vị trí cách cuối file 10 byte nếu kết quả hợp lệ.

### 7.4 Seek vượt cuối file

Linux cho phép với regular file:

```c
lseek(fd, 1_MB, SEEK_SET);
```

dù file hiện nhỏ hơn.

Chỉ riêng `lseek()` chưa làm file lớn lên.

Nếu sau đó ghi dữ liệu ở vị trí đó, khoảng trống giữa dữ liệu cũ và dữ liệu mới có thể trở thành **hole** trong sparse file.

Đọc vùng hole thường trả các byte zero.

### 7.5 Không phải fd nào cũng `lseek()` được

Ví dụ:

```c
lseek(pipe_fd, 0, SEEK_SET);
```

sẽ thất bại.

Lỗi điển hình:

```text
ESPIPE
```

với pipe, socket, FIFO hoặc đối tượng không seekable tương ứng.

### 7.6 `O_APPEND` và `lseek()`

Nếu open file description có `O_APPEND`, mỗi `write()` vẫn thực hiện ghi tại cuối file theo append semantics.

Do đó không nên nghĩ:

```c
lseek(fd, 0, SEEK_SET);
write(fd, ...);
```

sẽ ép một descriptor `O_APPEND` ghi ở đầu file.

---

## 8. `close()` — đóng file descriptor

Prototype:

```c
#include <unistd.h>

int close(int fd);
```

Thành công:

```text
0
```

Lỗi:

```text
-1
errno được thiết lập
```

### 8.1 `close()` đóng descriptor của process

Ví dụ trước:

```text
Process
│
├── fd 0
├── fd 1
├── fd 2
└── fd 3 ──> Open File Description
```

sau:

```c
close(3);
```

slot `3` không còn tham chiếu đó nữa:

```text
Process
│
├── fd 0
├── fd 1
└── fd 2
```

Số `3` có thể được tái sử dụng bởi một lần cấp descriptor sau này.

### 8.2 `close(fd)` không đồng nghĩa “xóa file”

`close()` chỉ giải phóng tham chiếu descriptor tương ứng.

Nó không có nghĩa:

```text
xóa pathname
```

Muốn xóa tên file khỏi filesystem thường liên quan tới:

```c
unlink()
```

là một khái niệm khác.

### 8.3 Vì sao phải `close()`?

Nếu process liên tục:

```c
open(...)
open(...)
open(...)
...
```

nhưng không `close()`, descriptor có thể bị leak.

Cuối cùng:

```text
RLIMIT_NOFILE
```

có thể bị chạm và `open()` mới thất bại với:

```text
EMFILE
```

Đây là **file descriptor leak**.

Trong embedded system chạy lâu ngày, leak kiểu này rất nguy hiểm vì chương trình có thể hoạt động tốt lúc mới boot nhưng lỗi sau hàng giờ hoặc hàng ngày.

### 8.4 Process kết thúc thì sao?

Kernel sẽ thu hồi file descriptor còn mở khi process kết thúc.

Nhưng điều đó **không phải lý do để bỏ qua `close()`** trong chương trình dài hạn.

Quản lý lifetime rõ ràng giúp:

- tránh leak;
- tránh giữ device/socket/file không cần thiết;
- tránh hết descriptor;
- làm ownership dễ hiểu hơn.

---

## 9. Blocking và Nonblocking I/O

Đây là khái niệm cần nắm ở mức cơ bản trước khi học `select/poll/epoll`.

### 9.1 Blocking I/O

Trong blocking mode, nếu thao tác chưa thể hoàn thành ngay, thread gọi system call có thể bị đưa vào trạng thái chờ.

Ví dụ pipe:

```text
Process A
read(pipe_fd, ...)
     │
     └── chưa có dữ liệu
            │
            v
       thread chờ
```

Khi dữ liệu xuất hiện:

```text
writer ghi dữ liệu
      │
      v
reader có thể tiếp tục
```

### 9.2 Nonblocking I/O

Descriptor có thể được mở hoặc cấu hình với:

```c
O_NONBLOCK
```

Khi thao tác sẽ phải chờ, system call có thể trả ngay:

```text
-1
errno = EAGAIN
```

hoặc với socket portable code thường cần xét cả:

```text
EAGAIN
EWOULDBLOCK
```

Ví dụ:

```c
ssize_t n = read(fd, buf, sizeof(buf));

if (n == -1 && errno == EAGAIN) {
    /* hiện tại chưa có dữ liệu; không phải EOF */
}
```

### 9.3 `EAGAIN` không có nghĩa EOF

Phải phân biệt:

```text
read() == 0
└── EOF trong trường hợp tương ứng

read() == -1 && errno == EAGAIN
└── hiện tại thao tác sẽ block, nhưng fd đang nonblocking
```

Hai trường hợp hoàn toàn khác nhau.

### 9.4 Vì sao nonblocking quan trọng?

Trong hệ thống event-driven, một thread không muốn bị kẹt vô thời hạn ở một I/O operation.

Nonblocking I/O là nền tảng để sau này hiểu:

```text
select()
poll()
epoll()
```

Nhưng ở Topic 03 chỉ cần dừng ở mô hình:

```text
blocking:
    chưa có dữ liệu -> có thể ngủ/chờ

nonblocking:
    chưa có dữ liệu -> trả về ngay với EAGAIN/EWOULDBLOCK
```

---

## 10. Lỗi và `errno`

System call thường báo lỗi theo pattern:

```text
return value cho biết thất bại
+
errno cho biết nguyên nhân
```

Ví dụ:

```c
int fd = open("abc.txt", O_RDONLY);

if (fd == -1) {
    perror("open");
}
```

### 10.1 Khi `open()` thất bại

Một số lỗi thường gặp:

#### `ENOENT`

Path không tồn tại hoặc một thành phần cần thiết không tồn tại.

Ví dụ:

```c
open("/not/exist/file", O_RDONLY);
```

#### `EACCES`

Không đủ quyền truy cập.

Ví dụ process không có quyền đọc file nhưng mở:

```c
O_RDONLY
```

#### `EEXIST`

Có thể xuất hiện khi:

```c
O_CREAT | O_EXCL
```

nhưng file đã tồn tại.

#### `EMFILE`

Process đã đạt giới hạn số file descriptor có thể mở.

Liên hệ mục 1.3:

```text
RLIMIT_NOFILE
```

#### `ENFILE`

Hệ thống không thể cấp thêm open-file resource ở mức system-wide.

Nhắc lại:

```text
EMFILE -> giới hạn của process
ENFILE -> giới hạn/tài nguyên mức hệ thống
```

### 10.2 `errno` chỉ có ý nghĩa khi lời gọi báo lỗi

Không nên làm:

```c
read(fd, buf, size);
printf("%d\n", errno);
```

rồi kết luận có lỗi chỉ vì `errno` khác 0.

`errno` có thể chứa giá trị còn lại từ một lời gọi trước.

Pattern đúng:

```c
ssize_t n = read(fd, buf, size);

if (n == -1) {
    /* lúc này mới đọc errno */
}
```

### 10.3 `perror()`

Ví dụ:

```c
if (fd == -1) {
    perror("open");
}
```

Có thể in:

```text
open: No such file or directory
```

`perror()` rất hữu ích khi debug system call.

### 10.4 `EINTR`

Một blocking system call có thể bị signal làm gián đoạn.

Một số lời gọi có thể trả:

```text
-1
errno = EINTR
```

Trong trường hợp thích hợp, chương trình thường retry operation.

Ví dụ pattern đơn giản cho `read()`:

```c
ssize_t n;

do {
    n = read(fd, buf, sizeof(buf));
} while (n == -1 && errno == EINTR);
```

Không nên áp dụng “cứ gặp `EINTR` là retry mọi system call” một cách máy móc; semantics cụ thể phụ thuộc system call. Ở Topic này chỉ cần nắm rằng `read()`/`write()` có thể bị signal interruption và robust code phải nghĩ tới trường hợp đó.

### 10.5 `EAGAIN` / `EWOULDBLOCK`

Khi descriptor đang nonblocking và thao tác hiện tại sẽ phải chờ:

```text
read()/write() -> -1
errno -> EAGAIN
```

Với socket, portable code thường kiểm tra:

```c
errno == EAGAIN || errno == EWOULDBLOCK
```

Đây không nhất thiết là lỗi “hỏng hệ thống”.

Nó thường có nghĩa:

> **Hiện tại chưa thể thực hiện I/O mà không block; hãy thử lại khi đối tượng sẵn sàng.**

---

## 11. Partial I/O và cách viết loop đúng

Một lỗi rất phổ biến của người mới là cho rằng:

```c
read(fd, buf, 4096);
```

luôn trả 4096 byte, hoặc:

```c
write(fd, buf, 4096);
```

luôn ghi đủ 4096 byte.

Không có đảm bảo chung như vậy.

### 11.1 Robust write loop

Ví dụ hàm ghi đủ dữ liệu ở mức cơ bản:

```c
#include <errno.h>
#include <stddef.h>
#include <unistd.h>

ssize_t write_all(int fd, const void *buffer, size_t count)
{
    const unsigned char *p = buffer;
    size_t total = 0;

    while (total < count) {
        ssize_t n = write(fd, p + total, count - total);

        if (n > 0) {
            total += (size_t)n;
            continue;
        }

        if (n == -1 && errno == EINTR) {
            continue;
        }

        return -1;
    }

    return (ssize_t)total;
}
```

Mô hình:

```text
cần ghi: 100 byte
    │
    ├── write() -> 40
    │      còn 60
    │
    ├── write() -> 35
    │      còn 25
    │
    └── write() -> 25
           hoàn thành
```

### 11.2 Read loop đến EOF

Ví dụ:

```c
#include <errno.h>
#include <unistd.h>

for (;;) {
    char buf[4096];

    ssize_t n = read(fd, buf, sizeof(buf));

    if (n > 0) {
        /* xử lý đúng n byte */
        continue;
    }

    if (n == 0) {
        /* EOF */
        break;
    }

    if (errno == EINTR) {
        continue;
    }

    /* lỗi thật sự */
    break;
}
```

### 11.3 Không xử lý buffer vượt quá số byte thực đọc

Nếu:

```c
n = read(fd, buf, sizeof(buf));
```

và:

```text
n = 37
```

thì chỉ:

```text
buf[0] ... buf[36]
```

là dữ liệu mới hợp lệ do lời gọi đó trả về.

Không được giả định toàn bộ:

```text
buf[0] ... buf[4095]
```

đều chứa dữ liệu hợp lệ mới đọc.

---

## 12. Ví dụ hoàn chỉnh: copy file bằng `open/read/write/close`

Ví dụ này minh họa flow cơ bản:

```text
open source
    │
open destination
    │
read loop
    │
write loop
    │
close
```

Code:

```c
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int write_all(int fd, const char *buf, size_t count)
{
    size_t total = 0;

    while (total < count) {
        ssize_t n = write(fd, buf + total, count - total);

        if (n > 0) {
            total += (size_t)n;
            continue;
        }

        if (n == -1 && errno == EINTR) {
            continue;
        }

        return -1;
    }

    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "Usage: %s SOURCE DEST\n", argv[0]);
        return EXIT_FAILURE;
    }

    int src_fd = open(argv[1], O_RDONLY);
    if (src_fd == -1) {
        perror("open source");
        return EXIT_FAILURE;
    }

    int dst_fd = open(argv[2],
                      O_WRONLY | O_CREAT | O_TRUNC,
                      0644);

    if (dst_fd == -1) {
        perror("open destination");
        close(src_fd);
        return EXIT_FAILURE;
    }

    char buf[4096];

    for (;;) {
        ssize_t n = read(src_fd, buf, sizeof(buf));

        if (n > 0) {
            if (write_all(dst_fd, buf, (size_t)n) == -1) {
                perror("write");
                close(dst_fd);
                close(src_fd);
                return EXIT_FAILURE;
            }

            continue;
        }

        if (n == 0) {
            break;
        }

        if (errno == EINTR) {
            continue;
        }

        perror("read");
        close(dst_fd);
        close(src_fd);
        return EXIT_FAILURE;
    }

    if (close(dst_fd) == -1) {
        perror("close destination");
        close(src_fd);
        return EXIT_FAILURE;
    }

    if (close(src_fd) == -1) {
        perror("close source");
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
```

Biên dịch:

```bash
gcc -Wall -Wextra -O2 copy.c -o copy
```

Chạy:

```bash
./copy source.bin destination.bin
```

Ví dụ này chưa phải utility `cp` hoàn chỉnh. Nó chưa xử lý metadata, sparse file preservation, symlink semantics, xattr, ACL, durability... Mục đích chỉ là luyện đúng mô hình system-call I/O cơ bản.

---

## 13. Quan sát file descriptor qua `/proc`

Linux cung cấp:

```text
/proc/<pid>/fd/
```

để quan sát các file descriptor của process.

Với shell hiện tại:

```bash
ls -l /proc/$$/fd
```

Ví dụ có thể thấy:

```text
0 -> /dev/pts/0
1 -> /dev/pts/0
2 -> /dev/pts/0
```

Ý nghĩa:

```text
stdin
stdout
stderr
```

đều đang nối với terminal.

### 13.1 Quan sát descriptor của process khác

Ví dụ:

```bash
ls -l /proc/<PID>/fd
```

nếu permission cho phép.

Đây là công cụ debug rất hữu ích khi nghi ngờ:

- file descriptor leak;
- process đang giữ file/device nào;
- socket/pipe nào còn mở;
- redirect có đúng hay không.

### 13.2 Đếm số descriptor đang mở

Ví dụ:

```bash
ls /proc/<PID>/fd | wc -l
```

Cho ta một cách quan sát nhanh số descriptor hiện có.

Cần nhớ đây là quan sát tại một thời điểm; process có thể mở/đóng descriptor đồng thời trong lúc ta kiểm tra.

---

## 14. Flow tổng thể cần ghi nhớ

Toàn bộ Topic có thể gom lại thành:

```text
Pathname
   │
   │ open()
   v
Kernel resolve path
   │
   v
Open File Description
   │
   ├── file offset
   ├── file status flags
   └── reference tới object/filesystem
   ^
   │
File Descriptor Table
   ^
   │
   fd
   ^
   │
Process
```

Ứng dụng thao tác:

```text
open()
  │
  v
fd
  │
  ├── read()
  ├── write()
  ├── lseek()
  └── close()
```

Giới hạn descriptor:

```text
RLIMIT_NOFILE
│
├── soft limit -> Kernel đang áp dụng
└── hard limit -> trần của soft limit
```

I/O return value:

```text
read()
├── > 0 -> số byte đọc được
├── = 0 -> EOF trong trường hợp tương ứng
└── = -1 -> lỗi, xem errno

write()
├── >= 0 -> số byte đã ghi/chấp nhận
└── = -1 -> lỗi, xem errno
```

Blocking:

```text
blocking
└── chưa sẵn sàng -> có thể chờ

nonblocking
└── chưa sẵn sàng -> EAGAIN/EWOULDBLOCK
```

---

## 15. Những nhầm lẫn cần tránh

### Nhầm 1

```text
fd = file
```

Sai.

Đúng hơn:

```text
fd -> open file description -> object
```

### Nhầm 2

```text
fd = inode
```

Sai.

`fd` là handle ở process; inode là đối tượng metadata của filesystem.

### Nhầm 3

```text
fd = con trỏ
```

Sai.

`fd` là số nguyên dùng trong system call.

### Nhầm 4

```text
RLIMIT_NOFILE = 1024
=> fd lớn nhất là 1024
```

Sai.

Nếu limit là `1024`:

```text
fd lớn nhất có thể được cấp = 1023
```

### Nhầm 5

```text
soft = 1024
hard = 4096
=> process hiện dùng được 4096 fd
```

Sai.

Giới hạn đang được Kernel thực thi là:

```text
1024
```

### Nhầm 6

```text
read(fd, buf, 4096)
=> luôn đọc 4096 byte
```

Sai.

Partial read là bình thường.

### Nhầm 7

```text
read() == 0
=> lỗi
```

Sai.

Với regular file, đó thường là EOF.

### Nhầm 8

```text
write() thành công
=> luôn ghi đủ count byte
```

Sai.

Phải xét giá trị trả về.

### Nhầm 9

```text
EAGAIN = EOF
```

Sai.

`EAGAIN` thường có nghĩa thao tác nonblocking hiện chưa thể hoàn thành ngay.

### Nhầm 10

```text
close(fd)
=> file trên filesystem bị xóa
```

Sai.

`close()` đóng descriptor; `unlink()` mới liên quan đến xóa một directory entry/pathname.

---

## 16. Bài thực hành đề xuất

### Bài 1 — Quan sát `fd`

Viết chương trình:

```c
open("a.txt", O_RDONLY);
open("b.txt", O_RDONLY);
```

in hai fd nhận được.

Sau đó thử:

```c
close(fd_a);
open("c.txt", O_RDONLY);
```

quan sát Kernel có tái sử dụng số fd vừa giải phóng hay không.

### Bài 2 — Quan sát `/proc/<pid>/fd`

Trong chương trình:

```c
open(...)
sleep(60);
```

Trong terminal khác:

```bash
ls -l /proc/<PID>/fd
```

đối chiếu với fd chương trình in ra.

### Bài 3 — File offset

File:

```text
ABCDEFGH
```

Thực hiện:

```c
read(fd, buf, 3);
read(fd, buf, 2);
```

dự đoán dữ liệu và offset sau mỗi lần.

Sau đó kiểm tra bằng:

```c
lseek(fd, 0, SEEK_CUR);
```

### Bài 4 — `lseek()`

Thử:

```c
lseek(fd, 2, SEEK_SET);
read(fd, buf, 2);
```

với file:

```text
ABCDEFGH
```

Dự đoán kết quả trước khi chạy.

### Bài 5 — `RLIMIT_NOFILE`

Quan sát:

```bash
ulimit -Sn
ulimit -Hn
cat /proc/$$/limits
```

Tự trả lời:

1. soft limit hiện tại là bao nhiêu?
2. hard limit là bao nhiêu?
3. nếu stdin/stdout/stderr đang mở thì còn bao nhiêu slot descriptor về mặt lý thuyết?
4. `EMFILE` khác `ENFILE` như thế nào?

### Bài 6 — File descriptor leak

Viết chương trình cố tình:

```c
while (1) {
    open("/dev/null", O_RDONLY);
}
```

**Chỉ chạy trong môi trường học tập/VM hoặc máy thử nghiệm**, quan sát tới khi `open()` thất bại và in `errno`.

Sau đó sửa chương trình bằng cách `close()` descriptor mỗi vòng và so sánh.

---

## 17. Checklist kiến thức trước khi sang Topic tiếp theo

Sau Topic 03, cần tự giải thích được:

- [ ] `file descriptor` là gì?
- [ ] Vì sao `fd` là số nguyên nhưng không phải “file”?
- [ ] `fd 0`, `1`, `2` thường là gì?
- [ ] `RLIMIT_NOFILE` là gì?
- [ ] soft limit khác hard limit như thế nào?
- [ ] vì sao limit `1024` tương ứng các số `fd` từ `0` tới `1023`?
- [ ] `EMFILE` khác `ENFILE` như thế nào?
- [ ] `open file description` là gì?
- [ ] file offset nằm ở đâu về mặt mô hình?
- [ ] hai lần `open()` cùng pathname có nhất thiết dùng chung offset không?
- [ ] `open()` trả gì khi thành công/thất bại?
- [ ] `O_RDONLY`, `O_WRONLY`, `O_RDWR` khác nhau thế nào?
- [ ] `O_CREAT`, `O_TRUNC`, `O_APPEND`, `O_NONBLOCK`, `O_CLOEXEC` dùng để làm gì ở mức cơ bản?
- [ ] vì sao `read()` có thể trả ít byte hơn yêu cầu?
- [ ] `read() == 0` có nghĩa gì với regular file?
- [ ] vì sao `write()` phải xử lý partial write?
- [ ] `lseek()` thay đổi cái gì?
- [ ] vì sao pipe/socket không dùng `lseek()` như regular file?
- [ ] blocking và nonblocking khác nhau thế nào?
- [ ] `EINTR` và `EAGAIN` có ý nghĩa gì?
- [ ] vì sao descriptor leak có thể gây `EMFILE`?

Nếu trả lời được các câu trên bằng lời của chính mình và viết được một chương trình `open -> read/write -> close` có xử lý return value, phần nền tảng File I/O ở mức Topic này đã đủ chắc để tiếp tục.

---

## 18. Tài liệu tham khảo

Ưu tiên đọc manual page và tài liệu Kernel khi cần xác minh semantics cụ thể:

- Linux man-pages — `open(2)`: <https://man7.org/linux/man-pages/man2/open.2.html>
- Linux man-pages — `read(2)`: <https://man7.org/linux/man-pages/man2/read.2.html>
- Linux man-pages — `write(2)`: <https://man7.org/linux/man-pages/man2/write.2.html>
- Linux man-pages — `lseek(2)`: <https://man7.org/linux/man-pages/man2/lseek.2.html>
- Linux man-pages — `close(2)`: <https://man7.org/linux/man-pages/man2/close.2.html>
- Linux man-pages — `getrlimit(2)`: <https://man7.org/linux/man-pages/man2/getrlimit.2.html>
- Linux Kernel documentation — file descriptor table: <https://docs.kernel.org/filesystems/files.html>
- Linux Kernel documentation — VFS: <https://docs.kernel.org/filesystems/vfs.html>

> Khi cần biết chính xác một flag hoặc một `errno`, ưu tiên `man 2 <system_call>` trên target/toolchain đang sử dụng, vì chi tiết có thể phụ thuộc Kernel, libc và loại đối tượng I/O.
