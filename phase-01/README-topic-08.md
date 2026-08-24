# Chủ đề 8 — Giao tiếp liên tiến trình (IPC) trong Linux

> **Mục tiêu:** hiểu vì sao các tiến trình cần IPC, và phân biệt đúng `pipe`, `FIFO`, POSIX Message Hàng đợi và POSIX Shared Memory theo mô hình dữ liệu, cách đặt tên, hành vi chặn, vòng đời và trách nhiệm đồng bộ.
>
> **Quy ước ngôn ngữ:** phần giải thích dùng Tiếng Việt. Giữ nguyên những tên chuẩn cần tra cứu như `IPC`, `FIFO`, `POSIX`, `pipe()`, `mkfifo()`, `mq_open()`, `shm_open()`, `mmap()`, `MAP_SHARED`, `SIGPIPE`, `EPIPE`, `PIPE_BUF`.
>
> **Phạm vi:** IPC cơ bản, unnamed pipe, FIFO, POSIX Message Hàng đợi, POSIX Shared Memory, `mmap` dùng chung, semaphore/đồng bộ ở mức cần để hiểu shared memory, hành vi chặn, áp lực ngược và so sánh lựa chọn cơ chế IPC.
>
> Chương này chỉ có **lý thuyết**, không có bài thực hành. Unix Domain Socket thuộc **Chủ đề 9 — Socket Programming** và chỉ được nhắc khi cần so sánh phạm vi.

> **Cách đọc tài liệu này nếu bạn mới bắt đầu:**
> 1. Đọc câu **Nói đơn giản** ở đầu mỗi mục lớn để biết mục đó đang giải quyết vấn đề gì.
> 2. Xem sơ đồ và ví dụ trước; chưa cần nhớ ngay mọi cờ, mã lỗi hay trường hợp đặc biệt.
> 3. Sau khi đã hiểu ý chính, mới đọc các mục `###` theo thứ tự. Nếu gặp thuật ngữ mới, hãy quay lại câu giải thích đầu mục thay vì cố học thuộc định nghĩa.

---

## Mục lục

- [1. IPC là gì?](#1-ipc-là-gì)
- [2. Trước khi chọn IPC cần hỏi những gì?](#2-trước-khi-chọn-ipc-cần-hỏi-những-gì)
- [3. Unnamed Pipe: luồng byte giữa các tiến trình có quan hệ](#3-unnamed-pipe-luồng-byte-giữa-các-tiến-trình-có-quan-hệ)
- [4. Ngữ nghĩa I/O, EOF, `SIGPIPE` và `PIPE_BUF` của Pipe](#4-ngữ-nghĩa-io-eof-sigpipe-và-pipe_buf-của-pipe)
- [5. FIFO: Pipe có tên trong hệ thống tệp](#5-fifo-pipe-có-tên-trong-hệ-thống-tệp)
- [6. POSIX Message Queue: gửi từng thông điệp riêng](#6-posix-message-queue-gửi-từng-thông-điệp-riêng)
- [7. POSIX Shared Memory: cùng nhìn một vùng nhớ](#7-posix-shared-memory-cùng-nhìn-một-vùng-nhớ)
- [8. Vì sao Shared Memory cần đồng bộ?](#8-vì-sao-shared-memory-cần-đồng-bộ)
- [9. Hành vi chặn, Backpressure và giới hạn tài nguyên](#9-hành-vi-chặn-backpressure-và-giới-hạn-tài-nguyên)
- [10. So sánh và lựa chọn cơ chế IPC](#10-so-sánh-và-lựa-chọn-cơ-chế-ipc)
- [11. Tư duy gỡ lỗi IPC](#11-tư-duy-gỡ-lỗi-ipc)
- [12. Liên hệ với Embedded Linux](#12-liên-hệ-với-embedded-linux)
- [13. Tổng kết](#13-tổng-kết)
- [14. Tài liệu tham khảo](#14-tài-liệu-tham-khảo)

---

## 1. IPC là gì?

> **Nói đơn giản:** IPC là các cách để những tiến trình riêng biệt trao đổi dữ liệu hoặc phối hợp với nhau.

### 1.1 Vì sao không thể dùng biến toàn cục giữa hai tiến trình?

Giả sử:

```text
Tiến trình A
  biến x ở địa chỉ 0x1000

Tiến trình B
  cũng có địa chỉ 0x1000
```

Hai địa chỉ ảo giống nhau không có nghĩa chúng trỏ tới cùng bộ nhớ vật lý.

Mỗi tiến trình bình thường có không gian địa chỉ riêng:

```text
+----------------------+       +----------------------+
| Tiến trình A         |       | Tiến trình B         |
| không gian địa chỉ A |       | không gian địa chỉ B |
+----------------------+       +----------------------+
```

IPC tạo một đường hoặc một đối tượng mà cả hai phía cùng có thể truy cập theo quy tắc của nó.

---

### 1.2 IPC dùng để truyền dữ liệu và phối hợp

Hai mục đích thường gặp:

```text
Truyền dữ liệu
  bytes
  message
  buffer lớn

Phối hợp
  báo có dữ liệu
  báo hoàn thành
  yêu cầu dừng
  đánh thức bên kia
```

Không phải cơ chế nào cũng phù hợp như nhau cho cả hai.

---

### 1.3 Các cơ chế trong Topic 8

```text
IPC
 |
 +--> Pipe
 |      luồng byte, không có tên pathname
 |
 +--> FIFO
 |      luồng byte, có tên trong filesystem
 |
 +--> POSIX Message Queue
 |      thông điệp riêng biệt
 |
 +--> POSIX Shared Memory
        nhiều tiến trình ánh xạ cùng vùng nhớ
```

---

### 1.4 IPC object và handle không phải lúc nào cũng giống nhau

Ví dụ:

```text
Pipe
  đối tượng pipe trong nhân Linux
  + bộ mô tả tệp đầu đọc/ghi

Message Queue
  đối tượng hàng đợi trong nhân Linux
  + mqd_t để tham chiếu

Shared Memory
  đối tượng bộ nhớ dùng chung
  + fd từ shm_open()
  + ánh xạ từ mmap()
```

Cần phân biệt:

```text
đối tượng IPC
```

với:

```text
handle mà tiến trình dùng để truy cập đối tượng đó
```

---

## 2. Trước khi chọn IPC cần hỏi những gì?

> **Nói đơn giản:** Trước khi chọn IPC, hãy hỏi: dữ liệu là luồng byte hay message, cần tốc độ hay đơn giản, cùng máy hay khác máy, và cần đồng bộ kiểu nào.

### 2.1 Dữ liệu là luồng byte hay từng thông điệp?

Pipe/FIFO:

```text
A B C D E F G ...
```

là **luồng byte**.

Message Hàng đợi:

```text
[Message 1]
[Message 2]
[Message 3]
```

giữ ranh giới từng thông điệp.

Shared Memory:

```text
[ứng dụng tự định nghĩa cấu trúc]
```

không tự là stream hay message.

---

### 2.2 Có cần tên để hai tiến trình độc lập tìm nhau không?

Unnamed Pipe:

```text
không có pathname/tên IPC để mở lại từ tiến trình độc lập
```

thường phù hợp khi bộ mô tả tệp được kế thừa hoặc truyền từ mối quan hệ đã có.

FIFO / MQ / SHM:

```text
có tên
```

nên hai tiến trình được khởi động độc lập có thể cùng tham chiếu tới một đối tượng biết trước.

---

### 2.3 Một chiều hay hai chiều?

Portable pipe nên được xem là:

```text
một chiều
writer ------> reader
```

Muốn trao đổi hai chiều bằng pipe thường cần:

```text
Pipe A: P1 -> P2
Pipe B: P2 -> P1
```

Message Hàng đợi và Shared Memory có thể xây giao thức hai chiều ở mức ứng dụng, nhưng cách tổ chức khác nhau.

---

### 2.4 Có cần giữ ranh giới message không?

Nếu giao thức tự nhiên là:

```text
Command A
Command B
Command C
```

Message Hàng đợi có lợi thế vì ranh giới thông điệp là một phần của cơ chế.

Nếu dùng Pipe/FIFO, ứng dụng phải tự tạo framing:

```text
fixed-size
length prefix
delimiter
```

---

### 2.5 Dữ liệu lớn hay nhỏ?

Dữ liệu nhỏ và rời rạc:

```text
command
event
job bộ mô tả
```

thường phù hợp với message-oriented IPC.

Dữ liệu lớn:

```text
frame ảnh
block audio
buffer cảm biến lớn
```

có thể phù hợp Shared Memory hơn vì không cần đưa toàn bộ payload qua một hàng đợi byte/message cho mỗi lần trao đổi.

---

### 2.6 Ai chịu trách nhiệm đồng bộ?

Pipe/MQ đã có các quy tắc chờ và hàng đợi do nhân Linux quản lý.

Shared Memory chỉ cung cấp:

```text
cùng vùng nhớ
```

nên ứng dụng phải tự giải quyết:

```text
ai đang ghi?
khi nào dữ liệu hợp lệ?
buffer nào trống?
buffer nào đã đầy?
```

---

### 2.7 Đối tượng sống bao lâu?

Cần hỏi:

```text
tiến trình chết thì IPC đối tượng còn không?
tên còn không?
dữ liệu còn không?
bao giờ đối tượng thật sự bị xóa?
```

Vòng đời khác nhau giữa pipe, FIFO, MQ và SHM.

---

## 3. Unnamed Pipe: luồng byte giữa các tiến trình có quan hệ

> **Nói đơn giản:** Unnamed Pipe là một ống byte do nhân Linux quản lý, thường dùng giữa các tiến trình có quan hệ như cha–con.

### 3.1 `pipe()` tạo gì?

`pipe()` tạo một pipe và trả về hai bộ mô tả tệp:

```text
fd[0]
  đầu đọc

fd[1]
  đầu ghi
```

Sơ đồ:

```text
Writer
  |
write(fd[1])
  |
  v
+------------------+
|  bộ đệm Pipe     |
|  trong nhân Linux    |
+------------------+
  |
read(fd[0])
  |
  v
Reader
```

---

### 3.2 Pipe thường đi cùng `fork()`

Một mô hình kinh điển:

```text
Parent
  |
pipe()
  |
fork()
 /    \
/      \
Parent  Child
```

Sau `fork()`, cả parent và child ban đầu đều có bản sao bộ mô tả tệp trỏ tới cùng pipe đối tượng.

Ứng dụng sau đó thường đóng các đầu không cần dùng để tạo đúng topology.

---

### 3.3 File descriptor inheritance là một phần của giao thức Pipe

Nếu muốn:

```text
Parent -> Child
```

thì mô hình mong muốn là:

```text
Parent:
  giữ đầu ghi
  đóng đầu đọc không dùng

Child:
  giữ đầu đọc
  đóng đầu ghi không dùng
```

Việc đóng các đầu thừa không chỉ “cho sạch code”; nó ảnh hưởng trực tiếp tới EOF và `SIGPIPE`.

---

### 3.4 Pipe không phải regular file tạm

Pipe không lưu dữ liệu như một file trên storage.

Nó là một đối tượng truyền byte trong nhân Linux:

```text
write -> nhân Linux pipe buffer -> read
```

Vì vậy không có khái niệm seek tới vị trí bất kỳ.

---

## 4. Ngữ nghĩa I/O, EOF, `SIGPIPE` và `PIPE_BUF` của Pipe

> **Nói đơn giản:** Pipe là luồng byte có giới hạn bộ đệm. EOF xuất hiện khi không còn writer; ghi khi không còn reader có thể gây `SIGPIPE`/`EPIPE`; `PIPE_BUF` liên quan tính nguyên tử của một số lần ghi nhỏ.

### 4.1 Pipe là luồng byte

Đây là điều quan trọng nhất.

Writer:

```text
write("ABC")
write("DEF")
```

Reader có thể nhận:

```text
"ABCDEF"
```

hoặc:

```text
"AB"
"CDEF"
```

Tùy kích thước `read()` và timing.

Pipe không lưu siêu dữ liệu:

```text
write #1 kết thúc ở đây
write #2 bắt đầu ở đây
```

---

### 4.2 Thứ tự byte vẫn được giữ

Nếu stream được ghi:

```text
A B C D E F
```

reader không tự nhiên nhận:

```text
A C B D F E
```

Pipe giữ thứ tự stream, nhưng không giữ ranh giới thông điệp.

---

### 4.3 Pipe rỗng chưa chắc là EOF

Nếu bộ đệm đang rỗng nhưng vẫn còn writer:

```text
read() blocking
  -> chờ dữ liệu mới
```

Nếu **tất cả** đầu ghi đã được đóng:

```text
read()
  -> trả 0 sau khi dữ liệu cũ đã đọc hết
```

Đó mới là EOF.

---

### 4.4 Vì sao descriptor rò rỉ làm reader chờ mãi?

Ví dụ:

```text
Parent write fd ----+
                    +--> cùng đầu ghi Pipe
Child write fd -----+
```

Parent đóng đầu ghi nhưng child vô tình vẫn giữ một bản sao.

Nhân Linux vẫn thấy:

```text
còn writer tham chiếu
```

nên reader chưa nhận EOF.

---

### 4.5 Khi không còn reader

Nếu mọi đầu đọc đã đóng mà writer vẫn ghi:

```text
write()
  |
  +--> phát sinh SIGPIPE
  |
  +--> nếu không bị terminate bởi signal thì lỗi EPIPE
```

Đây là liên hệ trực tiếp với Topic 5.

---

### 4.6 Pipe có dung lượng hữu hạn

```text
Producer
   |
   v
+--------------------+
| Pipe buffer hữu hạn|
+--------------------+
   |
   v
Consumer
```

Nếu producer nhanh hơn consumer:

```text
buffer đầy
  |
writer blocking chờ chỗ trống
```

hoặc nếu nonblocking:

```text
trả trạng thái EAGAIN/EWOULDBLOCK phù hợp
```

Topic 10 sẽ đi sâu vào nonblocking và readiness.

---

### 4.7 `PIPE_BUF` không phải dung lượng tổng của Pipe

Hai khái niệm khác nhau:

```text
Pipe capacity
  tổng lượng dữ liệu buffer có thể giữ

PIPE_BUF
  giới hạn liên quan tới bảo đảm atomic write giữa nhiều writer
```

Không được đồng nhất chúng.

---

### 4.8 Write không lớn hơn `PIPE_BUF`

POSIX bảo đảm mức atomicity nhất định cho write đủ nhỏ không vượt `PIPE_BUF`.

Với nhiều writer:

```text
Writer A ghi bản ghi A <= PIPE_BUF
Writer B ghi bản ghi B <= PIPE_BUF
```

các byte của từng write không bị trộn xen tùy ý vào nhau.

---

### 4.9 Write lớn hơn `PIPE_BUF`

Có thể bị xen kẽ với writer khác.

```text
A-part
B-part
A-part
B-part
```

Do đó nếu dùng pipe như record stream có nhiều writer, framing và kích thước write cần được thiết kế cẩn thận.

---

### 4.10 `PIPE_BUF` cũng không biến Pipe thành Message Queue

Ngay cả khi từng write nhỏ được atomic:

```text
Pipe vẫn là luồng byte
```

Reader vẫn phải biết cách chia record.

---

## 5. FIFO: Pipe có tên trong hệ thống tệp

> **Nói đơn giản:** FIFO giống pipe nhưng có tên trong filesystem, nên các tiến trình không cần có quan hệ cha–con để mở cùng kênh.

### 5.1 FIFO là một loại file đặc biệt

Ví dụ không gian tên:

```text
/run/myapp.fifo
```

Đây là một FIFO special file, không phải tệp thông thường chứa nội dung lâu dài.

---

### 5.2 Pathname dùng làm điểm hẹn

```text
Tiến trình A
   |
open("/run/myapp.fifo")
   |
   +--------------------+
                        v
                    FIFO name
                        ^
   +--------------------+
   |
Tiến trình B
```

Hai bên biết cùng pathname là có thể tìm tới cùng FIFO theo quyền truy cập cho phép.

---

### 5.3 Dữ liệu không nằm “trong file FIFO” như regular file

Filesystem entry giữ:

```text
tên
loại file
quyền
metadata
```

Dữ liệu truyền thực tế chạy qua pipe đối tượng/bộ đệm trong nhân Linux khi FIFO đang được mở.

Không nên nghĩ:

> “Ghi vào FIFO rồi ngày mai mở file ra đọc lại dữ liệu cũ.”

---

### 5.4 Sau khi mở, I/O giống Pipe

FIFO cũng có:

```text
luồng byte
không có message boundary
EOF theo writer tham chiếu
SIGPIPE/EPIPE theo reader tham chiếu
buffer hữu hạn
không seek
```

---

### 5.5 `open()` FIFO có thể chặn để chờ phía còn lại

Ở chế độ blocking thông thường:

```text
Reader mở đầu đọc
  -> có thể chờ writer

Writer mở đầu ghi
  -> có thể chờ reader
```

Do đó chính thao tác `open()` cũng là một điểm phối hợp giữa các tiến trình.

---

### 5.6 Nonblocking thay đổi hành vi mở

Với `O_NONBLOCK`, các thao tác mở có thể không chờ và trả kết quả/lỗi ngay theo phía còn lại.

Ví dụ phía ghi không có reader trên Linux có thể nhận:

```text
ENXIO
```

Chi tiết nonblocking thuộc Topic 10; ở đây chỉ cần hiểu rằng trạng thái cờ I/O thay đổi giao thức chờ.

---

### 5.7 Pathname sống khác dữ liệu truyền

FIFO pathname có thể còn:

```text
sau khi tất cả tiến trình đã close
```

cho tới khi nó được xóa khỏi filesystem.

Nhưng dữ liệu pipe không trở thành dữ liệu persistent của pathname đó.

---

### 5.8 Quyền truy cập

Vì FIFO là đối tượng trong filesystem nên chịu:

```text
owner
group
r/w permission
umask khi tạo
```

Đây là một lợi thế khi muốn dùng quyền filesystem làm lớp kiểm soát truy cập đơn giản.

---

## 6. POSIX Message Queue: gửi từng thông điệp riêng

> **Nói đơn giản:** POSIX Message Hàng đợi giữ ranh giới từng message. Mỗi lần gửi là một message độc lập thay vì trộn thành luồng byte.

### 6.1 Mô hình

```text
Sender
   |
 mq_send()
   |
   v
+-------------------------+
| POSIX Message Queue     |
|-------------------------|
| Message A               |
| Message B               |
| Message C               |
+-------------------------+
   |
 mq_receive()
   |
   v
Receiver
```

---

### 6.2 Queue có tên

POSIX MQ dùng một tên chuẩn dạng khái niệm:

```text
/my_queue
```

Các tiến trình biết tên này có thể dùng `mq_open()` để mở cùng hàng đợi nếu quyền cho phép.

---

### 6.3 `mqd_t`

`mq_open()` trả về một message hàng đợi bộ mô tả:

```text
mqd_t
```

Ứng dụng nên xem nó là handle POSIX của hàng đợi.

Linux có chi tiết triển khai fd-like, nhưng không nên dùng chi tiết đó làm giả định di động cho mọi POSIX system.

---

### 6.4 Message boundary được giữ

Nếu sender gửi:

```text
[ABC]
[DEF]
```

receiver nhận theo từng message, không phải tự hỏi byte nào thuộc message nào như Pipe.

Đây là một trong những khác biệt lớn nhất.

---

### 6.5 Queue có giới hạn

Các thuộc tính quan trọng:

```text
mq_maxmsg
  số message tối đa

mq_msgsize
  kích thước message tối đa

mq_curmsgs
  số message hiện tại
```

Hàng đợi không phải vùng chứa vô hạn.

---

### 6.6 Khi queue rỗng

Blocking receive:

```text
mq_receive()
  -> chờ tới khi có message
```

Nonblocking:

```text
queue rỗng
  -> EAGAIN
```

---

### 6.7 Khi queue đầy

Blocking send:

```text
mq_send()
  -> chờ tới khi có chỗ
```

Nonblocking:

```text
queue đầy
  -> EAGAIN
```

Đây là áp lực ngược tự nhiên của hàng đợi hữu hạn.

---

### 6.8 Priority của POSIX MQ

Mỗi message có một priority.

Receiver chọn:

```text
message có priority cao nhất
```

Nếu nhiều message cùng priority:

```text
message cũ hơn được lấy trước
```

Do đó POSIX MQ không phải FIFO toàn cục khi các priority khác nhau.

---

### 6.9 Vòng đời: `mq_close()` và `mq_unlink()`

Hai thao tác khác nhau:

```text
mq_close()
  đóng handle của tiến trình này

mq_unlink()
  gỡ tên queue khỏi namespace
```

Giống tư duy unlink file:

```text
tên bị gỡ
```

không nhất thiết có nghĩa mọi handle đang mở lập tức mất hiệu lực.

---

### 6.10 Linux có tính persistent ở mức kernel

Nếu hàng đợi chưa bị unlink, Linux có thể giữ nó tồn tại qua vòng đời của tiến trình cho tới khi được xóa hoặc hệ thống shutdown.

Do đó cleanup name/đối tượng là trách nhiệm thiết kế, không nên mặc định “tiến trình chết thì hàng đợi tự biến mất ngay”.

---

## 7. POSIX Shared Memory: cùng nhìn một vùng nhớ

> **Nói đơn giản:** POSIX Shared Memory cho nhiều tiến trình ánh xạ cùng một vùng nhớ. Nó nhanh vì không phải copy từng message qua nhân Linux sau khi thiết lập, nhưng cần synchronization.

### 7.1 Mô hình

```text
Tiến trình A                     Tiến trình B
+--------------+                +--------------+
| ánh xạ A    |                | ánh xạ B    |
+------+-------+                +------+-------+
       |                               |
       +------------+------------------+
                    |
                    v
          +--------------------+
          | Shared Memory      |
          | cùng vùng backing  |
          +--------------------+
```

---

### 7.2 POSIX Shared Memory có tên

Một đối tượng có thể được mở/tạo bằng:

```text
shm_open()
```

Nó trả về một bộ mô tả tệp đại diện cho shared-memory đối tượng.

---

### 7.3 Đối tượng mới có kích thước ban đầu bằng 0

Theo POSIX/Linux:

```text
shm_open(O_CREAT...)
```

khi tạo đối tượng mới, kích thước ban đầu là 0.

Ứng dụng thiết lập kích thước bằng:

```text
ftruncate()
```

trước khi ánh xạ vùng cần dùng.

---

### 7.4 `mmap(..., MAP_SHARED, ...)`

`mmap()` tạo ánh xạ vào không gian địa chỉ tiến trình.

`MAP_SHARED` nói rằng các thay đổi qua ánh xạ được chia sẻ với các ánh xạ chung của cùng đối tượng theo ngữ nghĩa đồng bộ thích hợp.

---

### 7.5 File descriptor và mapping có vòng đời tách nhau

Sau khi `mmap()` thành công:

```text
fd của SHM
   |
close(fd)
   |
   X
ánh xạ vẫn tồn tại
```

Ánh xạ có vòng đời riêng và được bỏ bằng `munmap()` hoặc khi không gian địa chỉ tiến trình kết thúc.

---

### 7.6 `shm_unlink()` xóa tên, không lập tức xóa mapping đang dùng

Cách hình dung:

```text
SHM name
  |
shm_unlink()
  |
  X

existing mappings/references
  vẫn có thể tồn tại
```

Đối tượng thật sự được giải phóng khi điều kiện vòng đời cuối cùng thỏa mãn.

---

### 7.7 Linux thường biểu diễn POSIX SHM dưới `/dev/shm`

Trên Linux, POSIX shared memory thường được hỗ trợ bằng `tmpfs`, thường thấy tại:

```text
/dev/shm
```

Đây là chi tiết Linux, không phải lý do để xem SHM như một tệp thông thường lưu trên đĩa.

---

### 7.8 Hai tiến trình có thể map cùng object ở địa chỉ ảo khác nhau

```text
Tiến trình A:
  base = 0x70000000

Tiến trình B:
  base = 0x50000000
```

Cùng underlying shared đối tượng, nhưng virtual address khác.

Vì vậy lưu raw pointer của A vào vùng dùng chung rồi để B sử dụng là nguy hiểm:

```text
pointer 0x70001234
```

có thể không có ý nghĩa tương ứng trong B.

---

### 7.9 Cấu trúc dùng chung nên không phụ thuộc địa chỉ tuyệt đối khi cần chia sẻ qua process

Thay vì:

```text
node->next = absolute_pointer
```

có thể dùng khái niệm:

```text
offset tính từ base
index trong vùng dùng chung
```

Tùy cấu trúc dữ liệu.

---

### 7.10 Shared Memory không tự có message boundary

Vùng nhớ chỉ là bytes/pages.

Ứng dụng tự định nghĩa:

```text
header
ring buffer
slots
indices
flags
payload
```

---

## 8. Vì sao Shared Memory cần đồng bộ?

> **Nói đơn giản:** Shared Memory chỉ giải quyết chuyện cùng nhìn thấy dữ liệu; nó không tự ngăn hai tiến trình sửa cùng lúc. Vì vậy cần mutex/semaphore hoặc cơ chế đồng bộ phù hợp.

### 8.1 Cùng thấy bộ nhớ không có nghĩa truy cập an toàn

Ví dụ:

```text
Tiến trình A                Tiến trình B
đọc write_index = 5      đọc write_index = 5
ghi slot 5               ghi slot 5
tăng index               tăng index
```

Có thể xảy ra race giống luồng.

---

### 8.2 Shared Memory giải quyết “dữ liệu ở đâu”, không giải quyết “khi nào được dùng”

```text
Shared Memory
  trả lời:
  dữ liệu chung nằm ở đâu?

Synchronization
  trả lời:
  ai được sửa?
  khi nào dữ liệu sẵn sàng?
  khi nào có buffer trống?
```

---

### 8.3 Có thể đặt synchronization object trong shared memory

POSIX cho phép một số synchronization đối tượng cấu hình ở chế độ tiến trình-shared.

Ví dụ khái niệm:

```text
+----------------------------------+
| Shared Memory                    |
|                                  |
| pthread_mutex_t                  |
|   PTHREAD_PROCESS_SHARED         |
|                                  |
| shared data                      |
+----------------------------------+
```

Cả hai tiến trình phải map cùng vùng chứa đối tượng đó.

---

### 8.4 Semaphore dùng chung giữa process

Unnamed POSIX semaphore có thể được khởi tạo với `pshared` phù hợp và đặt trong vùng nhớ dùng chung.

Cách hình dung:

```text
Shared payload
     +
Shared semaphore
```

Semaphore có thể biểu diễn:

```text
số slot có dữ liệu
số slot còn trống
```

---

### 8.5 Data plane và control plane

Một cách phân tách dễ hiểu:

```text
Dữ liệu lớn:
  Shared Memory

Thông tin trạng thái/chờ:
  Semaphore / Mutex / Condition / cơ chế báo sự kiện
```

Ví dụ:

```text
Producer
   |
   | ghi frame lớn
   v
Shared Memory
   |
   | semaphore báo "đã có frame"
   v
Consumer
```

---

### 8.6 Process chết giữa lúc cập nhật là bài toán khó hơn

Nếu tiến trình chết trong lúc:

```text
đang sở hữu lock
đang cập nhật metadata
```

shared trạng thái có thể không nhất quán.

Topic 7 đã giới thiệu synchronization; recovery sau crash là vấn đề kiến trúc nâng cao hơn và không được Shared Memory tự xử lý.

---

## 9. Hành vi chặn, Backpressure và giới hạn tài nguyên

> **Nói đơn giản:** Mọi IPC đều có giới hạn tài nguyên. Khi bộ đệm/hàng đợi đầy hoặc trống, lời gọi có thể block hoặc thất bại tùy chế độ.

### 9.1 Vì sao IPC có thể chặn?

Vì phía bên kia hoặc bộ đệm chưa sẵn sàng.

Ví dụ:

```text
Pipe rỗng        -> read chờ
Pipe đầy         -> write chờ
FIFO open        -> chờ peer
MQ rỗng          -> receive chờ
MQ đầy           -> send chờ
```

---

### 9.2 Backpressure là gì?

> **Nói đơn giản:** nếu bên sản xuất dữ liệu nhanh hơn bên tiêu thụ, một hệ thống hữu hạn phải có cách buộc producer chậm lại hoặc quyết định làm gì với dữ liệu dư.

```text
Producer nhanh
    |
    v
+-----------------+
| buffer hữu hạn  |
+-----------------+
    |
    v
Consumer chậm
```

Khi bộ đệm đầy:

```text
block producer
hoặc
trả trạng thái không sẵn sàng
hoặc
ứng dụng tự drop/buffer nơi khác
```

---

### 9.3 Pipe/FIFO có backpressure nội tại

Bộ đệm trong nhân Linux hữu hạn.

```text
đầy
  -> blocking writer ngủ
```

Đây có thể là hành vi tốt vì producer không chiếm RAM vô hạn.

---

### 9.4 Message Queue cũng hữu hạn

Các giới hạn:

```text
số message
kích thước mỗi message
resource limit của hệ thống
```

Hàng đợi đầy thì sender phải chờ hoặc xử lý `EAGAIN` nếu nonblocking.

---

### 9.5 Shared Memory không tự cung cấp backpressure

Nếu có 4 slot nhưng producer cứ ghi tiếp:

```text
slot cũ có thể bị ghi đè
```

trừ khi ứng dụng có protocol:

```text
free_count
used_count
read_index
write_index
semaphore
```

---

### 9.6 Nonblocking không làm mất bài toán backpressure

Nonblocking chỉ đổi:

```text
"chờ ở đây"
```

thành:

```text
"hiện giờ chưa thể làm, trả về"
```

Ứng dụng vẫn phải quyết định:

```text
retry lúc nào?
drop dữ liệu không?
buffer ở đâu?
chờ readiness bằng cách nào?
```

Chi tiết cuối cùng thuộc Topic 10.

---

## 10. So sánh và lựa chọn cơ chế IPC

> **Nói đơn giản:** Không có IPC tốt nhất cho mọi trường hợp. Pipe/FIFO đơn giản cho stream, MQ hợp message, SHM hợp dữ liệu lớn và tốc độ cao nhưng khó đồng bộ hơn.

### 10.1 Bảng tổng quan

| Cơ chế | Mô hình dữ liệu | Có tên? | Giữ ranh giới thông điệp? | Điểm mạnh chính |
|---|---|---:|---:|---|
| Pipe | luồng byte | Không | Không | đơn giản, hợp parent–child |
| FIFO | luồng byte | Pathname | Không | tiến trình độc lập có thể tìm nhau |
| POSIX MQ | message | Có | Có | message riêng, priority, nhân Linux hàng đợi |
| POSIX SHM | vùng nhớ | Có | Ứng dụng tự định nghĩa | dữ liệu lớn, truy cập trực tiếp |

---

### 10.2 Chọn Pipe khi nào?

Phù hợp khi:

```text
tiến trình có quan hệ
luồng dữ liệu một chiều
ordered luồng byte là đủ
EOF theo fd lifetime hữu ích
```

Ví dụ khái niệm:

```text
parent -> child luồng xử lý
```

---

### 10.3 Chọn FIFO khi nào?

Phù hợp khi muốn:

```text
pipe ngữ nghĩa
+
pathname để các tiến trình độc lập rendezvous
```

Nhưng vẫn phải tự framing nếu cần message.

---

### 10.4 Chọn Message Queue khi nào?

Phù hợp khi dữ liệu tự nhiên là:

```text
command
event
job
control message
```

và cần:

```text
message boundary
priority
nhân Linux-managed queue
```

---

### 10.5 Chọn Shared Memory khi nào?

Phù hợp khi:

```text
payload lớn
truy cập lặp lại nhiều
muốn giảm copy qua channel cho mỗi message
```

Đổi lại phải chịu trách nhiệm cao hơn về:

```text
synchronization
layout
lifetime
crash recovery
```

---

### 10.6 Không nên chọn chỉ vì “cái nào nhanh nhất”

Một thiết kế IPC tốt cần cân bằng:

```text
độ phức tạp
kích thước dữ liệu
latency
throughput
security/permission
restart behavior
cleanup
portability
khả năng gỡ lỗi
```

Shared Memory có thể nhanh về copy nhưng khó đúng hơn Message Hàng đợi rất nhiều.

---

## 11. Tư duy gỡ lỗi IPC

> **Nói đơn giản:** Debug IPC cần kiểm tra cả hai đầu: ai tạo, ai mở, ai đang đọc/ghi, dữ liệu có đúng định dạng không, có bị block và tài nguyên còn tồn tại không.

### 11.1 Kiểm tra theo tầng

```text
Hai bên có đang nói tới cùng IPC đối tượng không?
        |
Tên/path có đúng không?
        |
Permission có đúng không?
        |
Peer có tồn tại và giữ endpoint không?
        |
Blocking hay nonblocking?
        |
Buffer/queue đang rỗng hay đầy?
        |
Framing/message ngữ nghĩa có đúng không?
        |
Lifetime/unlink có đúng không?
        |
Shared memory có synchronization không?
```

---

### 11.2 Reader Pipe chờ mãi

Hãy nghĩ tới:

```text
writer thật sự chưa đóng
một tiến trình khác còn giữ write fd
fd bị kế thừa qua fork/exec
protocol chưa ghi dữ liệu
```

EOF phụ thuộc **mọi** writer tham chiếu, không chỉ writer bạn đang nhìn.

---

### 11.3 Pipe nhận message bị gộp/tách

Nếu ứng dụng mong:

```text
mỗi write = một message
```

thì giả định sai.

Pipe là luồng byte.

---

### 11.4 FIFO pathname có nhưng open/communication vẫn lỗi

Path tồn tại chỉ chứng minh:

```text
FIFO entry tồn tại
```

không chứng minh:

```text
reader đang mở
writer đang mở
permission đúng
tiến trình peer còn sống
```

---

### 11.5 MQ send chờ

Có thể hàng đợi đã đầy.

Cần phân biệt với:

```text
message quá lớn
permission sai
mqd không hợp lệ
resource limit
```

---

### 11.6 MQ receive chờ

Blocking hàng đợi rỗng thì chờ là đúng ngữ nghĩa.

Nonblocking rỗng trả:

```text
EAGAIN
```

---

### 11.7 MQ “không FIFO như mong đợi”

Kiểm tra priority.

POSIX MQ ưu tiên:

```text
priority cao hơn trước
```

sau đó mới xét thời gian trong cùng priority.

---

### 11.8 Shared Memory thấy dữ liệu lúc đúng lúc sai

Các hướng nghi ngờ:

```text
thiếu synchronization
MAP_PRIVATE thay vì MAP_SHARED
hai tiến trình mở khác đối tượng name
layout không thống nhất
raw pointer không hợp lệ giữa tiến trình
đối tượng bị resize/truncate
```

---

### 11.9 `SIGBUS` khi truy cập mapping

Một nguyên nhân quan trọng là truy cập vùng ánh xạ vượt phần backing hợp lệ của đối tượng, ví dụ đối tượng bị truncate hoặc chưa được đặt kích thước đúng.

Kích thước SHM cũng là một phần của giao thức vòng đời.

---

## 12. Liên hệ với Embedded Linux

> **Nói đơn giản:** Embedded Linux dùng IPC để tách service, logger, sensor collector, UI và daemon thành các tiến trình độc lập nhưng vẫn trao đổi dữ liệu.

### 12.1 Một sản phẩm thường có nhiều process

```text
sensor-service
control-service
network-service
logger
UI
supervisor
```

IPC nối các service này lại mà vẫn giữ biên tiến trình.

---

### 12.2 Pipe cho parent/child worker

Ví dụ:

```text
Supervisor
    |
   Pipe
    |
  Luồng xử lý
```

Có thể dùng cho:

```text
log
command đơn giản
stdout/stderr capture
```

---

### 12.3 FIFO cho endpoint đơn giản có tên

Một hệ thống nhỏ có thể dùng FIFO nếu chỉ cần:

```text
luồng byte
pathname cố định
ít peer
protocol đơn giản
```

Khi service cần nhiều máy khách hoặc giao thức hai chiều rõ ràng, Unix Domain Socket ở Topic 9 thường linh hoạt hơn.

---

### 12.4 Message Queue cho command/event

```text
Control Service
      |
      v
+----------------+
| command queue  |
+----------------+
      |
      v
Luồng xử lý
```

Message boundary giúp command không phải tự chia từ luồng byte.

---

### 12.5 Shared Memory cho audio/camera/buffer lớn

Ví dụ:

```text
Camera Tiến trình
    |
 ghi frame
    v
Shared Memory
    |
 đọc frame
    v
AI Tiến trình
```

Payload lớn nằm trong SHM; control có thể dùng semaphore hoặc cơ chế đồng bộ khác.

---

### 12.6 Bounded resource quan trọng trên board nhúng

RAM và nhân Linux memory hữu hạn.

Cần đặt câu hỏi:

```text
Pipe buffer đầy thì sao?
MQ đầy thì sao?
SHM có bao nhiêu slot?
Producer nhanh hơn consumer thì sao?
```

Áp lực ngược là một phần của độ ổn định hệ thống.

---

### 12.7 Restart và cleanup

Service crash có thể để lại:

```text
FIFO pathname
POSIX MQ name/đối tượng
POSIX SHM name/đối tượng
```

khác với unnamed pipe vốn gắn mạnh với bộ mô tả tham chiếu.

Supervisor/startup design cần biết cơ chế nào cần cleanup.

---

## 13. Tổng kết

> **Nói đơn giản:** Topic 08 cần để lại bản đồ lựa chọn: pipe/FIFO cho luồng byte, MQ cho message, SHM cho vùng nhớ dùng chung kèm synchronization.

### 13.1 Bản đồ IPC

```text
                    IPC
                     |
       +-------------+-------------+
       |             |             |
       v             v             v
   Luồng byte      Message      Vùng nhớ chung
       |             |             |
   +---+---+         |             |
   |       |         |             |
 Pipe    FIFO    POSIX MQ      POSIX SHM
```

---

### 13.2 Luồng byte và message

```text
Pipe/FIFO:
A B C D E F...

POSIX MQ:
[ABC] [DEF] [GHI]
```

---

### 13.3 Shared Memory

```text
Tiến trình A ánh xạ ----+
                      |
                      v
                  SHM đối tượng
                      ^
                      |
Tiến trình B ánh xạ ----+

+ synchronization riêng
```

---

### 13.4 Những điểm phải nhớ

1. IPC dùng để giao tiếp/phối hợp giữa các tiến trình tách biệt.
2. Pipe là luồng byte, không phải message hàng đợi.
3. Portable pipe là kênh một chiều với đầu đọc và đầu ghi.
4. EOF của pipe chỉ xuất hiện khi mọi writer tham chiếu đã biến mất và dữ liệu cũ đã đọc hết.
5. Ghi khi không còn reader có thể tạo `SIGPIPE`/`EPIPE`.
6. Pipe có dung lượng hữu hạn và tạo áp lực ngược.
7. `PIPE_BUF` liên quan atomic write, không phải tổng pipe capacity.
8. FIFO có I/O ngữ nghĩa như pipe nhưng có pathname làm điểm hẹn.
9. FIFO pathname không lưu dữ liệu như tệp thông thường.
10. POSIX MQ giữ ranh giới thông điệp.
11. POSIX MQ hỗ trợ priority và có giới hạn số/kích thước message.
12. `mq_close()` và `mq_unlink()` có ý nghĩa vòng đời khác nhau.
13. POSIX Shared Memory cho nhiều tiến trình map cùng backing đối tượng.
14. SHM mới có kích thước 0 và thường cần `ftruncate()` trước khi dùng.
15. `MAP_SHARED` là cơ sở cho ánh xạ dùng chung.
16. Đóng fd sau `mmap()` không tự hủy ánh xạ.
17. `shm_unlink()` xóa tên nhưng ánh xạ đang tồn tại có vòng đời riêng.
18. Raw pointer không nên được coi là địa chỉ dùng chung giữa các tiến trình nếu ánh xạ base khác nhau.
19. Shared Memory không tự cung cấp mutual exclusion hoặc notification.
20. Shared Memory cần synchronization/ownership protocol riêng.
21. Nonblocking không loại bỏ bài toán áp lực ngược.
22. Chọn IPC theo mô hình dữ liệu, vòng đời và độ phức tạp, không chỉ theo tốc độ.

---

## 14. Tài liệu tham khảo

> **Nói đơn giản:** Phần này liệt kê nguồn chuẩn về các cơ chế IPC đã học.

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

- The Linux Programming Giao diện: https://man7.org/tlpi/
- Bootlin Embedded Linux: https://bootlin.com/doc/training/embedded-linux/
- Unix & Linux Stack Exchange: https://unix.stackexchange.com/
- Stack Overflow: https://stackoverflow.com/

Nguồn cộng đồng hữu ích để tìm lỗi rò bộ mô tả, FIFO open bị chặn, MQ priority hoặc raw pointer trong SHM, nhưng ngữ nghĩa chuẩn phải đối chiếu lại với POSIX/Linux man-pages.

---

> **Điều hướng:** [← Chủ đề 7 — Đồng bộ luồng](README-topic-07.md) · [Chủ đề 9 — Socket Programming →](README-topic-09.md)
