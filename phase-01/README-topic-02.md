# Chủ đề 2 — Hệ thống tệp Linux (Filesystem)

> **Mục tiêu:** Hiểu cách Linux tổ chức, phân giải và quản lý tài nguyên thông qua hệ thống tệp: từ cây thư mục `/`, `pathname`, quá trình `pathname resolution`, `VFS`, `dentry`, `inode`, quyền truy cập, cơ chế `mount`, cho tới các filesystem giao diện như `/dev`, `/proc`, `/sys`.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các thuật ngữ kỹ thuật cốt lõi như `filesystem`, `VFS`, `pathname`, `dentry`, `inode`, `symbolic link`, `hard link`, `mount point`, `device node`, `procfs`, `sysfs`, `devtmpfs`, `open file description` được giữ nguyên bằng tiếng Anh để thuận tiện tra cứu tài liệu Linux/POSIX.
>
> **Phạm vi:** Chỉ tập trung vào **chủ đề hệ thống tệp Linux**: namespace, pathname resolution, VFS, dentry/inode, metadata, file type, permission, mount, pseudo-filesystem và các công cụ quan sát filesystem. Không đi sâu vào lập trình I/O vì đó thuộc chủ đề tiếp theo.
>
> **Mental model cần xây dựng:** Một `pathname` không phải là “địa chỉ vật lý” của dữ liệu. Kernel phải phân giải tên qua namespace, VFS và filesystem implementation trước khi tới object hoặc dữ liệu tương ứng.

Cách dễ nhất để hiểu filesystem Linux là tách hai câu hỏi:

1. **Tên này nằm ở đâu trong namespace?**  
   Ví dụ: `/home/user/report.txt`.

2. **Object phía sau tên đó được filesystem quản lý như thế nào?**  
   Nó có thể là dữ liệu trên `ext4`, dữ liệu trong `tmpfs`, trạng thái Kernel trong `procfs`, hoặc một device interface dưới `/dev`.

`VFS` (Virtual File System) là lớp trừu tượng giúp Linux nối hai góc nhìn này lại với nhau.

---

## Mục lục

- [1. Hệ thống tệp trong Linux thực chất là gì?](#1-hệ-thống-tệp-trong-linux-thực-chất-là-gì)
- [2. Cây thư mục bắt đầu từ `/`](#2-cây-thư-mục-bắt-đầu-từ-)
- [3. Đường dẫn và cách Linux Kernel tìm một tệp](#3-đường-dẫn-và-cách-linux-kernel-tìm-một-tệp)
- [4. VFS, `dentry` và `inode`](#4-vfs-dentry-và-inode)
- [5. Block, kích thước tệp và dung lượng thật](#5-block-kích-thước-tệp-và-dung-lượng-thật)
- [6. Các loại tệp trong Linux](#6-các-loại-tệp-trong-linux)
- [7. Metadata và `stat`](#7-metadata-và-stat)
- [8. Chủ sở hữu, nhóm và quyền `r/w/x`](#8-chủ-sở-hữu-nhóm-và-quyền-rwx)
- [9. `chmod`, `chown` và `umask`](#9-chmod-chown-và-umask)
- [10. `mount`: ghép filesystem vào namespace](#10-mount-ghép-filesystem-vào-namespace)
- [11. `/dev`, `/proc`, `/sys`: các filesystem/giao diện đặc biệt](#11-dev-proc-sys-các-filesystemgiao-diện-đặc-biệt)
- [12. `ls`, `stat`, `file`, `df`, `du` quan sát lớp nào?](#12-ls-stat-file-df-du-quan-sát-lớp-nào)
- [13. Vòng đời tên tệp, hard link và tệp đang mở](#13-vòng-đời-tên-tệp-hard-link-và-tệp-đang-mở)
- [14. Tư duy gỡ lỗi filesystem](#14-tư-duy-gỡ-lỗi-filesystem)
- [15. Liên hệ với Embedded Linux](#15-liên-hệ-với-embedded-linux)
- [16. Tổng kết mental model](#16-tổng-kết-mental-model)
- [17. Tài liệu tham khảo](#17-tài-liệu-tham-khảo)

---

# 1. Hệ thống tệp trong Linux thực chất là gì?

Filesystem không chỉ là “nơi chứa file”. Nó là tập hợp quy tắc và cấu trúc dữ liệu để:

- đặt tên object;
- tổ chức chúng thành cây thư mục;
- lưu metadata;
- ánh xạ dữ liệu;
- kiểm tra quyền truy cập;
- cung cấp các thao tác chung cho userspace.

## 1.1 Hai lớp rất dễ bị trộn lẫn

### Lớp 1 — Namespace

Namespace trả lời:

> Tên nào dẫn tới object nào?

Ví dụ:

```text
/home/user/report.txt
```

Userspace làm việc chủ yếu với `pathname`.

### Lớp 2 — Backing implementation

Lớp này trả lời:

> Object phía sau pathname được filesystem cụ thể quản lý như thế nào?

Ví dụ:

```text
/home/user/report.txt
        |
        +--> ext4 --> block storage

/tmp/a.txt
        |
        +--> tmpfs --> memory-backed storage

/proc/cpuinfo
        |
        +--> procfs --> Kernel state
```

Điểm cần nhớ:

> **Namespace và nơi dữ liệu/object được hiện thực hóa là hai chuyện khác nhau.**

## 1.2 Linux ghép nhiều filesystem vào một namespace

Một process có thể nhìn thấy:

```text
/
├── etc
├── home
├── proc        -> procfs
├── sys         -> sysfs
├── dev         -> devtmpfs
└── mnt
    └── sdcard  -> filesystem trên thẻ SD
```

Khi pathname đi qua một `mount point`, Kernel chuyển việc lookup sang filesystem được mount tại đó.

### Không nên nói “cả hệ thống luôn có đúng một cây duy nhất”

Ở góc nhìn **một process**, filesystem hierarchy xuất hiện như một cây có root `/`.

Nhưng Linux hỗ trợ:

- `mount namespace`;
- `chroot()`;
- container;
- các cơ chế thay đổi root dùng cho pathname resolution.

Vì vậy, hai process khác nhau **có thể nhìn thấy các mount khác nhau**, hoặc thậm chí có root `/` khác nhau.

Mental model chính xác hơn:

```text
Process
   |
   +--> root directory của process
   |
   +--> mount namespace của process
   |
   +--> pathname resolution
```

## 1.3 “Everything is a file” nên hiểu thế nào?

Không nên hiểu máy móc rằng mọi tài nguyên đều được tạo bằng `open()`.

Ví dụ:

- regular file thường được mở bằng `open()`;
- socket thường được tạo bằng `socket()`;
- pipe có thể được tạo bằng `pipe()`;
- nhiều device được truy cập qua device node.

Ý tưởng UNIX quan trọng hơn là:

> **Rất nhiều tài nguyên được userspace biểu diễn bằng file descriptor và có thể sử dụng một tập I/O API tương đối thống nhất như `read()`, `write()`, `poll()`, `close()`.**

Ví dụ:

```text
read(fd, ...)
```

có thể đọc:

- bytes từ regular file;
- bytes từ UART;
- dữ liệu từ pipe;
- dữ liệu từ socket.

Nhưng **semantics phía sau hoàn toàn khác nhau**.

---

# 2. Cây thư mục bắt đầu từ `/`

## 2.1 `/` là root của pathname resolution đối với process

Với pathname tuyệt đối:

```text
/etc/passwd
```

Kernel bắt đầu từ **root directory của process gọi**.

Trong hệ thống thông thường, root đó chính là root filesystem hierarchy mà ta quen gọi là `/`.

Nhưng root của process có thể bị thay đổi bởi các cơ chế như `chroot()`, container hoặc một số pathname-resolution API.

Ví dụ một cây thường thấy:

```text
/
├── bin
├── dev
├── etc
├── home
├── proc
├── run
├── sys
├── tmp
├── usr
└── var
```

Cây này mô tả **namespace**, không phải sơ đồ partition vật lý.

Ví dụ:

```text
/etc        -> có thể thuộc ext4
/proc       -> procfs
/sys        -> sysfs
/dev        -> devtmpfs
/run        -> thường là tmpfs
```

## 2.2 Ý nghĩa khái quát của một số thư mục

- `/etc`: cấu hình hệ thống.
- `/usr`: chương trình, thư viện và dữ liệu dùng chung.
- `/var`: dữ liệu thay đổi thường xuyên như log, spool, state.
- `/run`: runtime state, thường nằm trên filesystem volatile.
- `/tmp`: temporary files.
- `/dev`: device nodes và một số special nodes.
- `/proc`: interface tới process và Kernel state.
- `/sys`: interface tới Kernel device model và các subsystem.

Trong Embedded Linux, layout thực tế có thể được tối giản mạnh.

## 2.3 FHS là quy ước, không phải định luật của Kernel

Filesystem Hierarchy Standard giúp distro thống nhất vị trí file.

Nhưng Kernel không bắt buộc một rootfs embedded phải có đầy đủ mọi thư mục của một distro desktop/server.

Buildroot hoặc Yocto có thể tạo rootfs rất nhỏ, chỉ giữ những thành phần cần thiết.

---

# 3. Đường dẫn và cách Linux Kernel tìm một tệp

## 3.1 Pathname gồm nhiều component

Ví dụ:

```text
/home/user/docs/report.txt
```

Các component là:

```text
home
user
docs
report.txt
```

Kernel phải resolve từng component theo thứ tự.

Nó không thể “nhảy thẳng” tới `report.txt`.

## 3.2 Pathname tuyệt đối và tương đối

### Tuyệt đối

```text
/etc/passwd
```

Bắt đầu bằng `/`.

Kernel bắt đầu từ root directory dùng cho pathname resolution của process.

### Tương đối

```text
docs/report.txt
```

Không bắt đầu bằng `/`.

Thông thường Kernel bắt đầu từ Current Working Directory (`CWD`).

Ngoài ra, họ API dạng `*at()` còn cho phép pathname tương đối được resolve dựa trên một directory file descriptor.

## 3.3 `.` và `..`

- `.`: directory hiện tại.
- `..`: directory cha trong namespace hiện hành.

Việc xử lý `..` còn phải tôn trọng root hiện hành và mount topology; nó không đơn giản là thao tác chuỗi trên pathname.

## 3.4 Pathname resolution

Mental model đơn giản:

```text
Process
  |
  | pathname "/a/b/c"
  v
VFS
  |
  | resolve "a"
  v
dentry "a"
  |
  | resolve "b"
  v
dentry "b"
  |
  | resolve "c"
  v
dentry "c"
  |
  v
inode/object
```

Trong quá trình lookup, VFS tận dụng `dcache`.

Nếu thông tin tên đã có trong cache, lookup có thể hoàn thành nhanh.

Nếu chưa có, VFS có thể phải gọi method của filesystem cụ thể để lookup object.

Ví dụ với block filesystem:

```text
VFS
 |
 +--> dcache miss
 |
 +--> ext4 lookup
 |
 +--> metadata trên storage
 |
 +--> inode được nạp/khởi tạo trong RAM
 |
 +--> dentry được liên kết với inode
```

Nhưng không phải filesystem nào cũng dẫn xuống disk:

```text
VFS
 ├── ext4  -> block storage
 ├── tmpfs -> memory-backed storage
 ├── procfs -> Kernel state
 └── sysfs -> Kernel objects
```

## 3.5 Negative dentry

Một điểm rất quan trọng:

> `dentry` không nhất thiết phải trỏ tới một inode tồn tại.

Kernel có thể cache cả kết quả:

```text
"tên này không tồn tại trong thư mục cha"
```

Khi đó ta có **negative dentry**:

```text
Parent dentry + component name
             |
             v
          dentry
             |
             +--> inode != NULL
             |      tên tồn tại
             |
             +--> inode == NULL
                    negative dentry
```

Negative dentry giúp Kernel tránh phải hỏi lại filesystem nhiều lần cho cùng một tên không tồn tại.

Khi object được tạo với tên đó, negative dentry có thể được gắn với inode mới.

## 3.6 Symbolic link làm thay đổi pathname resolution

Symlink chứa một pathname khác.

Ví dụ:

```text
/link -> /data/file.txt
```

Khi lookup gặp symlink, Kernel phải tiếp tục resolution dựa trên nội dung của link.

### Target tuyệt đối

```text
/link -> /data/file.txt
```

Target bắt đầu bằng `/`, nên resolution tiếp tục theo root hiện hành.

### Target tương đối

```text
/home/user/link -> ../data/file.txt
```

Target tương đối được hiểu **so với directory chứa symlink**, không phải so với CWD của process.

---

# 4. VFS, `dentry` và `inode`

Đây là phần quan trọng nhất của Topic 02.

## 4.1 VFS là gì?

`VFS` là abstraction layer trong Kernel cho phép nhiều filesystem implementation cùng cung cấp interface chung.

```text
Userspace
   |
   | open(), stat(), read(), write(), chmod(), ...
   v
System call interface
   |
   v
VFS
   |
   +--> ext4
   +--> tmpfs
   +--> procfs
   +--> sysfs
   +--> ...
```

Ứng dụng không cần tự biết cách ext4 lookup directory entry hay cách procfs tổng hợp `/proc/cpuinfo`.

VFS dispatch thao tác tới implementation phù hợp.

## 4.2 `dentry` là gì?

`dentry` là object của VFS dùng để biểu diễn **một tên trong context của parent directory**.

Mental model:

```text
(parent dentry, component name)
              |
              v
           dentry
              |
              +--> inode
```

Ví dụ:

```text
parent: /home/user
name:   report.txt
```

kết hợp thành một dentry đại diện cho tên `report.txt` trong directory `/home/user`.

### Dentry nằm trong RAM

`dentry` của VFS:

- nằm trong memory;
- được quản lý trong `dcache`;
- không phải chính directory entry on-disk của ext4.

Filesystem cụ thể có thể có cấu trúc directory entry riêng trên storage.

### Dentry có thể âm

```text
dentry -> inode
```

là trường hợp tên tồn tại.

```text
dentry -> NULL inode
```

là negative dentry.

## 4.3 `inode` là gì?

Trong góc nhìn VFS, inode là object đại diện cho một filesystem object và metadata của nó.

Các thông tin thường liên quan tới inode gồm:

- file type;
- permission/mode;
- UID;
- GID;
- size;
- timestamps;
- link count;
- filesystem-specific operations/data.

### Không được đồng nhất `struct inode` với “inode trên ổ đĩa”

Có hai lớp phải phân biệt:

```text
VFS inode object trong RAM
            |
            v
filesystem-specific representation
            |
            +--> ext4 inode trên storage
            +--> tmpfs state trong memory
            +--> pseudo-filesystem object
```

Đối với block filesystem, metadata bền vững có thể nằm trên storage và được nạp vào VFS inode trong memory khi cần.

Đối với pseudo-filesystem, object có thể không có “on-disk inode” nào cả.

Vì vậy, câu:

> inode luôn chứa con trỏ tới block trên ổ cứng

là **quá hẹp và không đúng cho toàn bộ VFS**.

Mental model tốt hơn:

> VFS inode chứa metadata và các thông tin/operations mà filesystem implementation cần để đại diện object. Cách ánh xạ tới dữ liệu thực tế là trách nhiệm của filesystem cụ thể.

## 4.4 Inode không chứa pathname đầy đủ

Tên thuộc về namespace/directory structure.

Inode đại diện object.

Do đó nhiều tên có thể trỏ tới cùng một inode thông qua hard link:

```text
docs/report.txt ----+
                    |
                    +--> inode X
                    |
backup/report.txt --+
```

Cả hai tên cùng tham chiếu một object.

## 4.5 Inode number không phải global ID

`inode number` chỉ có ý nghĩa trong filesystem tương ứng.

Hai filesystem khác nhau có thể có cùng `st_ino`.

Để nhận diện theo kiểu Unix ở mức `stat`, cần nghĩ theo cặp:

```text
(st_dev, st_ino)
```

Không nên diễn đạt rằng inode number “unique theo mount point”, vì cùng một filesystem có thể xuất hiện qua nhiều mount mà inode number của object không vì vậy thay đổi.

## 4.6 Mental model tổng thể

```text
Pathname
   |
   v
pathname resolution
   |
   v
dentry
   |
   v
VFS inode
   |
   +--> metadata
   |
   +--> filesystem-specific implementation
              |
              +--> block-backed data
              +--> memory-backed data
              +--> Kernel-generated object
```

Đây là mental model nên giữ cho các phần còn lại.

---

# 5. Block, kích thước tệp và dung lượng thật

## 5.1 Logical size

`st_size` mô tả kích thước logic theo byte của regular file.

Ví dụ:

```text
st_size = 1000
```

nghĩa là file có logical length 1000 byte.

## 5.2 Allocated space

Block-backed filesystem thường cấp phát storage theo các đơn vị nhất định.

Logical size và allocated size không nhất thiết bằng nhau.

Ví dụ file 1000 byte có thể chiếm nhiều hơn 1000 byte storage vì allocation granularity và metadata.

Không nên coi “một file 1000 byte chắc chắn tốn đúng một block 4096 byte” là quy luật chung, vì:

- filesystem khác nhau có cơ chế allocation khác nhau;
- compression, inline data, reflink hoặc các cơ chế khác có thể thay đổi cách sử dụng storage;
- metadata overhead không chỉ nằm ở một block data duy nhất.

## 5.3 Sparse file

Sparse file có logical range chưa được cấp phát block vật lý.

Ví dụ:

```text
logical size: 1 GiB
allocated:    nhỏ hơn rất nhiều
```

Khi process đọc vào hole, filesystem trả về byte `0` mà không cần có đầy đủ block dữ liệu chứa các số 0 đó trên storage.

## 5.4 `st_size`, `st_blocks`, `st_blksize`

Một số trường thường gặp trong `struct stat`:

- `st_size`: logical size.
- `st_blocks`: số block 512-byte được cấp phát theo interface `stat`.
- `st_blksize`: preferred block size cho I/O, **không nhất thiết là filesystem block size vật lý**.

Đây là chỗ rất dễ nhầm:

```text
st_blksize != "số byte filesystem luôn cấp phát cho mỗi file"
```

---

# 6. Các loại tệp trong Linux

Linux xác định file type từ metadata/mode, không dựa vào extension.

## 6.1 Regular file

Chứa byte stream dữ liệu.

Ví dụ:

```text
.txt
ELF executable
image
database
```

Extension chỉ là convention ở userspace.

## 6.2 Directory

Directory là object đặc biệt dùng để tổ chức mapping từ tên sang filesystem object.

Mental model đơn giản:

```text
directory
  |
  +--> "a.txt" -> object/inode A
  +--> "b.txt" -> object/inode B
```

Không nên hiểu directory là file text mà userspace có thể tự ý ghi bytes vào để tạo entry.

Các thao tác tạo/xóa/rename entry phải đi qua filesystem operations để đảm bảo consistency.

## 6.3 Symbolic link

Symlink chứa target pathname.

Target có thể:

- tồn tại;
- không tồn tại;
- thay đổi theo namespace/mount state.

Một symlink không “giữ sống” target.

## 6.4 Character device

Character device node là interface tới character-device semantics của Kernel.

Ví dụ:

```text
/dev/ttyS0
/dev/null
/dev/zero
```

Không phải character device nào cũng đại diện trực tiếp cho một phần cứng vật lý.

## 6.5 Block device

Block device cung cấp block-oriented/random-access storage semantics cho Kernel/userspace.

Ví dụ:

```text
/dev/mmcblk0
/dev/mmcblk0p1
/dev/nvme0n1
/dev/loop0
```

Một block device cũng không nhất thiết tương ứng 1:1 với một phần cứng vật lý; `loop`, device mapper, RAID... là các ví dụ quan trọng.

## 6.6 `major` và `minor`

Device special file mang device number gồm:

- major;
- minor.

Ở mức khái niệm:

```text
major -> xác định nhóm/subsystem/driver mapping phù hợp
minor -> phân biệt device instance hoặc đối tượng trong major đó
```

Không nên học thuộc rằng:

> cùng driver thì chắc chắn cùng major trong mọi subsystem và mọi kernel

vì device-number allocation phụ thuộc subsystem và quy ước Kernel.

Các ví dụ major/minor cụ thể hữu ích khi debug nhưng không phải bản chất cần học thuộc.

## 6.7 FIFO (Named Pipe)

FIFO có pathname trong filesystem nhưng dữ liệu trao đổi không được lưu như payload của regular file.

Pathname của FIFO giúp process tìm được cùng một IPC endpoint.

Với blocking mode mặc định, thao tác mở FIFO thường có semantics đồng bộ giữa reader và writer.

Ví dụ:

- mở read-only có thể chờ writer;
- mở write-only có thể chờ reader.

Sau khi hai đầu đã mở:

- `read()` có thể block khi chưa có dữ liệu;
- `write()` có thể block khi buffer không còn đủ chỗ;
- nếu không còn reader, writer có thể gặp `SIGPIPE`/`EPIPE`.

Vì vậy không nên nói đơn giản:

> `write()` luôn block cho tới khi có process mở đầu đọc.

Phần “chờ đầu kia xuất hiện” chủ yếu liên quan tới semantics lúc `open()` FIFO.

## 6.8 Unix-domain socket

Unix-domain socket có thể dùng pathname làm local IPC address.

Nó hỗ trợ các khả năng như:

- bidirectional communication;
- datagram hoặc stream semantics tùy socket type;
- truyền file descriptor trong một số use case.

Socket pathname là endpoint name, không phải regular-file payload.

---

# 7. Metadata và `stat`

## 7.1 `stat()`, `lstat()`, `fstat()`

### `stat(path)`

Resolve pathname và trả metadata của target.

Nếu pathname cuối là symlink, `stat()` mặc định follow symlink.

### `lstat(path)`

Nếu object cuối là symlink, trả metadata của chính symlink.

### `fstat(fd)`

Trả metadata của object đang được file descriptor tham chiếu.

`fstat()` tránh phải pathname-resolve lại object.

## 7.2 `mtime`, `ctime`, `atime`

### `mtime`

Thời điểm file data được sửa đổi.

### `ctime`

Thời điểm inode status/metadata thay đổi.

`ctime` **không phải creation time**.

### `atime`

Thời điểm access data theo semantics của filesystem/mount option.

Trong thực tế, mount option như `relatime`, `noatime`, `strictatime` có thể ảnh hưởng việc cập nhật access time.

## 7.3 Metadata là snapshot, không phải lời hứa cho tương lai

Trong hệ thống đa nhiệm:

```text
stat(path)
   |
   | process khác đổi pathname/object
   v
open(path)
```

hai thao tác này có thể không còn nói về cùng một trạng thái.

Đó là lớp vấn đề TOCTOU:

```text
Time Of Check
    |
    | race window
    v
Time Of Use
```

### Không nên kết luận “không bao giờ dùng stat rồi open”

`stat()` rồi `open()` vẫn hợp lệ trong nhiều tình huống.

Vấn đề xuất hiện khi chương trình:

1. kiểm tra một thuộc tính security-sensitive theo pathname;
2. sau đó dùng pathname đó;
3. nhưng pathname có thể bị thay đổi trong khoảng giữa.

Khi cần gắn việc kiểm tra với **chính object đã mở**, mô hình tốt hơn là:

```text
open(...)
  |
  v
file descriptor
  |
  v
fstat(fd)
```

Nhưng ngay cả vậy, nếu yêu cầu bảo mật là:

> “phải chắc chắn pathname được resolve theo một tập constraint nhất định”

thì có thể cần các API/flag pathname-resolution phù hợp như `openat2()` cùng các `RESOLVE_*` constraints.

Điểm cần học trong Topic 02:

> **Pathname là tên có thể thay đổi; file descriptor là một reference tới object đã được mở.**

---

# 8. Chủ sở hữu, nhóm và quyền `r/w/x`

## 8.1 UID và GID

Kernel chủ yếu làm việc với numeric IDs:

```text
UID
GID
```

Tên như:

```text
root
user
admin
```

là mapping ở userspace, thường thông qua NSS và các nguồn như `/etc/passwd`, `/etc/group`.

Không nên coi `/etc/passwd` là nguồn duy nhất trong mọi hệ thống, vì NSS có thể dùng nhiều backend khác nhau.

## 8.2 Ba lớp permission cơ bản

Traditional mode bits chia thành:

- `u`: owner;
- `g`: group;
- `o`: others.

Ba permission cơ bản:

- `r`;
- `w`;
- `x`.

## 8.3 Permission trên regular file

### `r`

Cho phép đọc file data.

### `w`

Cho phép sửa nội dung file theo policy và filesystem state.

Quyền `w` trên file **không quyết định trực tiếp việc xóa pathname của file**.

`unlink()` tác động vào directory entry của parent directory.

### `x`

Cho phép execute khi các điều kiện khác cũng thỏa mãn.

Có bit `x` chưa đủ để một file chạy thành công.

Còn phụ thuộc:

- executable format;
- interpreter;
- loader;
- mount flags;
- LSM/security policy;
- kiến trúc CPU;
- dependency.

## 8.4 Permission trên directory

Đây là phần phải hiểu thật chắc.

### `r` trên directory

Cho phép đọc danh sách tên directory entry.

Đơn giản hóa:

```text
r -> list names
```

### `x` trên directory

Cho phép **search/traverse** directory.

Pathname resolution qua directory thường cần `x`.

Ví dụ:

```text
/a/b/c.txt
```

muốn tới `c.txt`, process cần có quyền search phù hợp trên các directory component trung gian.

### `w` trên directory

`w` cho phép thay đổi directory entries, nhưng trong thực tế các thao tác như:

```text
create
unlink
rename
```

thường cần **`w` + `x` trên directory**.

Vì vậy không nên ghi:

```text
w = chắc chắn được xóa file
```

Mental model tốt hơn:

```text
r -> đọc danh sách tên
x -> traverse/search
w + x -> có khả năng sửa namespace entry trong directory
```

Sau đó vẫn còn các rule khác có thể áp dụng, ví dụ:

- sticky bit;
- ACL;
- capabilities;
- LSM;
- mount state;
- immutable flags;
- filesystem-specific restrictions.

## 8.5 Sticky bit trên shared directory

Ví dụ phổ biến:

```text
/tmp
```

thường có mode tương tự:

```text
drwxrwxrwt
```

Sticky bit hạn chế việc user tùy ý xóa/rename entry của user khác trong shared writable directory.

Điều này cho thấy:

> permission bits `r/w/x` là nền tảng, nhưng không phải toàn bộ access-control model của Linux.

---

# 9. `chmod`, `chown` và `umask`

## 9.1 `chmod`

Thay đổi mode bits.

Ví dụ:

```bash
chmod 755 app
chmod u+x file
chmod g-w file
```

Octal:

```text
7 = rwx
6 = rw-
5 = r-x
4 = r--
```

## 9.2 `chown`

Thay đổi owner/group metadata theo quyền cho phép.

Ví dụ:

```bash
chown root:admin config.txt
```

## 9.3 `umask`

`umask` không phải permission mặc định.

Nó là **mask loại bỏ permission** khỏi mode mà application yêu cầu lúc tạo object.

Mental model:

```text
requested mode
     |
     | AND NOT umask
     v
initial permission
```

Ví dụ:

```text
requested: 0666
umask:     0022
result:    0644
```

Với directory:

```text
requested: 0777
umask:     0022
result:    0755
```

Điểm phải nhớ:

> `umask` không tự thêm permission mà application không yêu cầu.

---

# 10. `mount`: ghép filesystem vào namespace

## 10.1 Mount point là gì?

Giả sử đang có:

```text
/mnt/sdcard/
└── old.txt
```

Directory này hiện thuộc filesystem đang chứa `/mnt`.

Sau đó:

```bash
mount /dev/mmcblk0p1 /mnt/sdcard
```

Kernel gắn root của filesystem nguồn vào vị trí `/mnt/sdcard` trong mount namespace.

Từ đó, pathname resolution khi đi qua `/mnt/sdcard` sẽ đi vào mounted filesystem.

## 10.2 Over-mount che nội dung cũ, không xóa nó

Trước mount:

```text
/mnt/sdcard/
└── old.txt
```

Sau mount:

```text
/mnt/sdcard/
├── file_on_sd_1
└── file_on_sd_2
```

`old.txt` phía dưới chưa bị xóa.

Nó chỉ bị namespace của mounted filesystem che phủ.

Sau khi unmount, nội dung cũ có thể nhìn thấy lại.

## 10.3 Không nên đồng nhất mount point với “cửa sổ trực tiếp tới phần cứng”

Nếu mounted filesystem nằm trên `/dev/mmcblk0p1`, dữ liệu cuối cùng có thể đi tới block device đó.

Nhưng giữa VFS và physical storage có thể tồn tại nhiều lớp:

```text
VFS
 |
filesystem
 |
page cache / writeback
 |
block layer
 |
device mapper / crypto / RAID / ...
 |
block device
 |
controller
 |
physical media
```

Do đó, mount point nên hiểu là:

> **vị trí trong namespace nơi một mounted filesystem được gắn vào.**

## 10.4 Có thể đọc/ghi raw block device mà không mount

Ví dụ `/dev/mmcblk0p1` là block-device interface.

Userspace có thể mở nó như raw block device nếu đủ quyền.

Do đó câu:

> “không thể ghi gì vào `/dev/mmcblk0p1` nếu chưa mount”

là sai.

Điều đúng là:

> Nếu muốn thao tác **theo semantics file/directory của filesystem bằng VFS pathname thông thường**, filesystem phải được Kernel nhận diện và thông thường được mount vào namespace.

Raw write vào block device bỏ qua file-level semantics và có thể làm hỏng filesystem.

## 10.5 Block device → partition → filesystem → mount không phải pipeline bắt buộc

Một trường hợp phổ biến:

```text
physical storage
      |
block device
      |
partition
      |
filesystem
      |
mount
```

Nhưng partition là **optional**.

Có thể có:

```text
block device
    |
filesystem
```

hoặc:

```text
block device
    |
partition
    |
dm-crypt
    |
LVM logical volume
    |
filesystem
    |
mount
```

Trong Embedded Linux còn có kiến trúc raw flash như:

```text
Raw NAND
   |
MTD
   |
UBI
   |
UBIFS
   |
mount
```

Do đó không nên biến một sơ đồ desktop phổ biến thành quy luật chung.

## 10.6 Mount namespace

Linux cho phép process thuộc các mount namespace khác nhau.

Ví dụ:

```text
Process A:
    /data -> filesystem X

Process B:
    /data -> filesystem Y
```

Cùng pathname `/data/file`, nhưng hai process có thể thấy object khác nhau.

Đây là nền tảng quan trọng của container.

Trong Topic 02 chỉ cần nhớ:

> **Mount table là một phần của namespace mà process quan sát.**

---

# 11. `/dev`, `/proc`, `/sys`: các filesystem/giao diện đặc biệt

## 11.1 `/dev` và `devtmpfs`

`/dev` thường chứa device nodes và các special nodes.

Ví dụ:

```text
/dev/ttyS0
/dev/mmcblk0
/dev/null
/dev/zero
/dev/gpiochip0
```

Không nên nói tất cả entry trong `/dev` đều “đại diện cho phần cứng”.

Một số đại diện cho Kernel interfaces hoặc virtual devices.

`devtmpfs` giúp Kernel tạo device nodes cho registered devices; userspace device manager có thể tiếp tục áp dụng naming, symlink và permission policy.

## 11.2 `/proc` và `procfs`

`procfs` là pseudo-filesystem cung cấp interface tới Kernel state.

Ví dụ:

```text
/proc/[PID]/
/proc/meminfo
/proc/cpuinfo
/proc/sys/
```

Không nên mô tả procfs đơn giản là:

> “filesystem lưu file trên RAM”

vì điều đó dễ khiến người học tưởng các file text dưới `/proc` tồn tại như payload của tmpfs.

Mental model đúng hơn:

```text
cat /proc/cpuinfo
       |
       v
VFS/procfs
       |
       v
Kernel lấy trạng thái hiện hành
       |
       v
Kernel tạo dữ liệu để trả về read()
```

Nội dung thường được tổng hợp động từ Kernel state.

## 11.3 `tmpfs` khác `procfs`

`tmpfs` là memory-backed filesystem thực sự cho phép tạo regular files/directories.

Ví dụ:

```text
/run
/tmp
/dev/shm
```

tùy hệ thống.

`tmpfs` sử dụng virtual memory và có thể tương tác với swap tùy cấu hình.

So sánh:

```text
tmpfs
  -> chứa filesystem data trong memory-backed storage

procfs
  -> interface trình bày Kernel/process state qua filesystem API
```

## 11.4 `/sys` và `sysfs`

`sysfs` trình bày Kernel object model và nhiều subsystem dưới dạng hierarchy.

Ví dụ:

```text
/sys/class/
/sys/bus/
/sys/devices/
/sys/block/
```

Nó đặc biệt quan trọng trong Embedded Linux vì giúp quan sát:

- device;
- driver;
- bus;
- class;
- firmware-related attributes;
- power-management state;
- subsystem attributes.

Không nên nghĩ mọi file trong sysfs đều là “thanh ghi phần cứng”.

Nhiều attribute là representation của Kernel state hoặc subsystem API.

## 11.5 File interface không có nghĩa là regular file semantics

Ví dụ:

```bash
cat /proc/meminfo
cat /sys/.../attribute
echo value > /sys/.../attribute
```

nhìn giống thao tác regular file.

Nhưng bên dưới:

```text
read()/write()
    |
    v
filesystem callback
    |
    v
Kernel logic
```

Không nhất thiết có payload được lưu như regular file.

---

# 12. `ls`, `stat`, `file`, `df`, `du` quan sát lớp nào?

## 12.1 `ls`

`ls` kết hợp directory traversal và metadata query để hiển thị:

- tên;
- mode;
- owner;
- group;
- size;
- timestamp;
- ...

Không nên hiểu `ls` chỉ “đọc dentry cache”; command ở userspace tương tác thông qua filesystem syscalls.

## 12.2 `stat`

`stat` quan sát metadata của filesystem object.

Các thông tin thường có:

```text
mode
UID/GID
size
inode number
timestamps
device ID
link count
blocks
```

## 12.3 `file`

`file` thường đọc nội dung đầu file và dùng database về magic/signature cùng các heuristic khác để phân loại format.

Không nên nói nó chỉ đọc đúng “magic number”, vì logic thực tế có thể phong phú hơn.

## 12.4 `df`

`df` quan sát **filesystem-wide space accounting**.

Ở userspace, loại dữ liệu này thường được lấy qua interface như `statfs()`/`statvfs()`.

Mental model:

```text
df
 |
 +--> filesystem-level statistics
       |
       +--> total blocks
       +--> free blocks
       +--> available blocks
       +--> inode statistics
```

Không nên mô tả `df` theo nghĩa đen là:

> “chương trình đi đọc raw superblock trực tiếp”.

## 12.5 `du`

`du` đi qua directory tree và cộng usage của các file/directory nhìn thấy.

Vì vậy `df` và `du` có thể khác nhau.

Một nguyên nhân kinh điển:

```text
file đã unlink
nhưng process vẫn đang mở
```

Filesystem vẫn giữ storage vì object chưa được giải phóng, nên `df` vẫn tính.

`du` lại không tìm thấy pathname đã bị xóa để cộng vào.

---

# 13. Vòng đời tên tệp, hard link và tệp đang mở

## 13.1 Hard link

Hai directory entries có thể trỏ tới cùng một inode/object:

```text
name_A ----+
           |
           +--> inode X
           |
name_B ----+
```

Không có hard link nào “gốc hơn” hard link khác ở mức namespace thông thường.

## 13.2 Link count

Inode metadata giữ link count thể hiện số hard links phù hợp theo semantics filesystem.

Với regular file, đây là nền tảng để hiểu tại sao xóa một tên chưa chắc xóa object ngay.

## 13.3 `unlink()`

`unlink()` loại bỏ một name-to-object association khỏi parent directory.

Mental model:

```text
before:
name -> inode

unlink(name)

after:
name -X-> inode
```

Nếu vẫn còn hard link khác, object vẫn reachable qua tên khác.

## 13.4 Unlinked-but-open file

Giả sử:

```text
Process
   |
   v
file descriptor
   |
   v
open file description
   |
   v
filesystem object/inode
```

Sau đó process khác:

```text
unlink(pathname)
```

Pathname có thể biến mất khỏi namespace, nhưng process đang giữ FD vẫn dùng object đã mở.

Storage chưa được giải phóng nếu filesystem vẫn còn reference cần thiết.

Khi reference cuối cùng biến mất, filesystem mới có thể reclaim object/data.

Đây là một lý do phổ biến khiến:

```text
df
```

vẫn báo filesystem đầy trong khi:

```text
du
```

không tìm ra file lớn tương ứng.

---

# 14. Tư duy gỡ lỗi filesystem

## 14.1 `ENOENT` — No such file or directory

Đừng chỉ kiểm tra component cuối.

Ví dụ:

```text
/a/b/c
```

Có thể lỗi vì:

- CWD sai nếu dùng relative path;
- `a` không tồn tại;
- `b` không tồn tại;
- `c` không tồn tại;
- symlink target không tồn tại;
- mount topology không như mong đợi.

Debug theo từng component.

## 14.2 `EACCES` — Permission denied

Kiểm tra:

1. permission của file đích;
2. `x`/search permission trên **mọi directory component**;
3. parent directory permission nếu create/delete/rename;
4. ACL;
5. mount/security policy;
6. LSM nếu hệ thống có dùng.

## 14.3 `noexec`

Mount option `noexec` ngăn **direct execution** theo semantics mount.

Không nên diễn đạt quá tuyệt đối rằng:

> “mọi script nằm trên filesystem `noexec` đều hoàn toàn không thể chạy bằng bất kỳ cách nào”.

Một script có thể được interpreter ở nơi khác mở như input, tùy tình huống và policy.

Điểm Topic 02 cần nhớ:

> `x` mode bit của file không phải điều kiện duy nhất quyết định execution.

## 14.4 `EROFS` — Read-only filesystem

Nếu filesystem được mount read-only, một operation cần ghi filesystem có thể trả:

```text
EROFS
```

Điều này khác với:

```text
EACCES
```

do permission check.

Khi debug Embedded Linux phải phân biệt:

```text
permission problem
```

với:

```text
filesystem đang read-only
```

## 14.5 Device node có nhưng device vẫn không hoạt động

Thấy:

```text
/dev/ttyS0
```

không đủ để kết luận UART hoạt động đúng.

Cần phân biệt nhiều lớp:

```text
device node
   |
driver
   |
device registration/binding
   |
device tree / ACPI / platform description
   |
clock/reset/power
   |
pinctrl
   |
physical signal
```

Tương tự với GPIO, I2C, SPI, block device...

## 14.6 Debug mount

Khi thấy nội dung directory “biến mất”, kiểm tra mount trước khi kết luận file bị xóa.

Các nguồn thông tin hữu ích:

```text
/proc/self/mountinfo
/proc/mounts
```

và các công cụ userspace như:

```bash
mount
findmnt
```

Mount namespace của process cũng phải được tính tới.

---

# 15. Liên hệ với Embedded Linux

## 15.1 Root filesystem tối giản

Embedded rootfs thường chỉ giữ thành phần cần thiết.

BusyBox có thể cung cấp nhiều applet như:

```text
ls
cat
mount
cp
mv
```

trong một executable.

Nhưng underlying VFS/filesystem semantics vẫn là semantics của Linux Kernel.

## 15.2 eMMC và SD card

eMMC/SD thường được Kernel expose dưới block-device model:

```text
/dev/mmcblk0
/dev/mmcblk0p1
```

Filesystem có thể là:

- ext4;
- F2FS;
- FAT/exFAT cho vùng trao đổi dữ liệu;
- SquashFS cho image read-only;
- filesystem khác tùy product requirement.

Không nên mặc định mọi embedded rootfs dùng ext4.

## 15.3 SquashFS cho vùng read-only

Một thiết kế phổ biến:

```text
read-only rootfs -> SquashFS
writable state   -> ext4/F2FS/UBIFS/tmpfs/overlay...
```

Lợi ích có thể gồm:

- giảm storage;
- tránh ghi không cần thiết;
- dễ kiểm soát root image;
- thuận lợi cho update strategy.

Cách chia cụ thể phụ thuộc thiết kế sản phẩm.

## 15.4 Raw NAND: MTD, UBI, UBIFS

Raw NAND không nên được hình dung y hệt block device như eMMC.

Mental model thường gặp:

```text
Raw NAND
   |
  MTD
   |
  UBI
   |
 UBIFS
```

UBI xử lý các vấn đề liên quan tới raw flash ở lớp phù hợp, còn UBIFS là filesystem chạy trên UBI volume.

JFFS2 vẫn tồn tại nhưng với NAND dung lượng lớn, UBIFS thường là kiến trúc cần hiểu quan trọng hơn.

## 15.5 `tmpfs` cho dữ liệu volatile

Các vùng ghi nhiều nhưng không cần giữ sau reboot có thể đặt trên tmpfs.

Ví dụ tùy thiết kế:

```text
/run
/tmp
một số runtime state
một số log volatile
```

Không nên nói mọi `/var/log` trong Embedded Linux đều “được ném lên RAM”; đó là một lựa chọn thiết kế, không phải rule.

## 15.6 `/sys` và `/dev` khi bring-up board

Trong bring-up, filesystem interfaces rất hữu ích để quan sát hệ thống.

Ví dụ:

```text
/sys/class/
/sys/bus/
/sys/devices/
/dev/
```

Nhưng cần nhớ:

> Có file interface không đồng nghĩa hardware path chắc chắn đã hoạt động đầy đủ.

Phải kết hợp với:

- `dmesg`;
- driver binding;
- clock/reset/power;
- pinctrl;
- Device Tree;
- signal-level debugging.

## 15.7 GPIO trên Linux hiện đại

GPIO userspace API hiện đại dùng **GPIO character device**:

```text
/dev/gpiochipN
```

và thường được thao tác bằng `libgpiod`.

API sysfs cũ:

```text
/sys/class/gpio
```

đã được Kernel documentation đánh dấu **obsolete**.

Do đó:

```text
new development
    |
    v
GPIO character-device API
```

thay vì thiết kế mới dựa trên legacy sysfs GPIO.

Ngoài ra, nếu phần cứng đã có Kernel subsystem/driver phù hợp thì nên dùng subsystem đó thay vì bit-bang GPIO từ userspace.

## 15.8 Sysfs LED

Với LED đã được Kernel LED subsystem quản lý, userspace có thể thấy interface kiểu:

```text
/sys/class/leds/<name>/
```

Ví dụ attribute `brightness`.

Điểm quan trọng không phải lệnh `echo` cụ thể, mà là kiến trúc:

```text
userspace
   |
sysfs attribute
   |
Kernel subsystem
   |
driver
   |
hardware
```

---

# 16. Tổng kết mental model

Chuỗi tư duy cốt lõi:

```text
[ Pathname ]
     |
     v
[ Pathname Resolution ]
     |
     v
[ Dentry ]
     |
     v
[ VFS Inode / Filesystem Object ]
     |
     v
[ Filesystem-specific implementation ]
     |
     +--> block-backed storage
     +--> memory-backed storage
     +--> Kernel state/interface
```

Nhưng cần bổ sung mount:

```text
Process
   |
   +--> root directory
   |
   +--> mount namespace
   |
   v
pathname
   |
   v
VFS lookup
   |
   +--> dcache
   |      |
   |      +--> positive dentry
   |      +--> negative dentry
   |
   v
inode/object
   |
   v
filesystem implementation
```

## Các nguyên tắc không được quên

1. **Pathname là tên trong namespace, không phải địa chỉ vật lý của dữ liệu.**

2. **Pathname tuyệt đối bắt đầu từ root dùng cho process**, và process có thể nằm trong mount namespace/root khác process khác.

3. **Pathname resolution diễn ra theo từng component.**

4. **`dentry` là VFS object trong RAM**, biểu diễn name-in-parent và có thể là negative dentry.

5. **VFS inode không đồng nhất với on-disk inode.** Block filesystem có persistent representation; pseudo-filesystem có thể không có storage inode tương ứng.

6. **Inode không chứa pathname đầy đủ.** Hard link cho phép nhiều tên tham chiếu cùng object.

7. **Inode number không phải global ID.** Khi cần định danh theo kiểu `stat`, nghĩ tới `(st_dev, st_ino)`.

8. **Permission của directory khác regular file.** Đặc biệt, `x` là search/traverse và sửa directory entries thường cần `w + x`.

9. **`unlink()` xóa name association, không nhất thiết giải phóng object ngay.**

10. **File descriptor có thể tiếp tục tham chiếu object sau khi pathname bị unlink.**

11. **Mount gắn filesystem vào namespace; over-mount che nội dung cũ chứ không copy/xóa nó.**

12. **Partition là optional.** Không có pipeline bắt buộc `device -> partition -> filesystem -> mount` cho mọi hệ thống.

13. **Raw block device vẫn có thể được đọc/ghi mà không mount**, nhưng thao tác đó không dùng file/directory semantics của mounted filesystem và rất dễ phá dữ liệu.

14. **`/proc` và `/sys` là pseudo-filesystem interfaces tới Kernel state**, không nên đồng nhất với `tmpfs`.

15. **`/dev` không chỉ chứa “phần cứng”; nó chứa device/special interfaces do Kernel/userspace quản lý.**

16. **`df` nhìn filesystem-level accounting; `du` cộng usage của object reachable qua tree mà nó traverse.**

17. **`noexec` không đơn giản đồng nghĩa “mọi byte trên filesystem không thể được interpreter đọc và chạy”.**

18. **GPIO sysfs API là legacy/obsolete; development mới nên dùng GPIO character-device API.**

Nếu giữ được các nguyên tắc trên, bạn đã có mental model đủ vững để đi tiếp sang file I/O, device access và system programming mà không phải “đập đi xây lại” kiến thức filesystem.

---

# 17. Tài liệu tham khảo

Ưu tiên tài liệu upstream Kernel và Linux man-pages:

- Filesystem Hierarchy Standard 3.0:  
  <https://refspecs.linuxfoundation.org/FHS_3.0/fhs/index.html>

- Linux Kernel — VFS:  
  <https://docs.kernel.org/filesystems/vfs.html>

- Linux Kernel — Pathname lookup:  
  <https://docs.kernel.org/filesystems/path-lookup.html>

- Linux man-pages — `path_resolution(7)`:  
  <https://man7.org/linux/man-pages/man7/path_resolution.7.html>

- Linux man-pages — `inode(7)`:  
  <https://man7.org/linux/man-pages/man7/inode.7.html>

- Linux man-pages — `stat(2)`:  
  <https://man7.org/linux/man-pages/man2/stat.2.html>

- Linux man-pages — `statfs(2)`:  
  <https://man7.org/linux/man-pages/man2/statfs.2.html>

- Linux man-pages — `open(2)`:  
  <https://man7.org/linux/man-pages/man2/open.2.html>

- Linux man-pages — `openat2(2)`:  
  <https://man7.org/linux/man-pages/man2/openat2.2.html>

- Linux man-pages — `fifo(7)`:  
  <https://man7.org/linux/man-pages/man7/fifo.7.html>

- Linux man-pages — `chmod(2)`:  
  <https://man7.org/linux/man-pages/man2/chmod.2.html>

- Linux man-pages — `chown(2)`:  
  <https://man7.org/linux/man-pages/man2/chown.2.html>

- Linux man-pages — `umask(2)`:  
  <https://man7.org/linux/man-pages/man2/umask.2.html>

- Linux man-pages — `mount(8)`:  
  <https://man7.org/linux/man-pages/man8/mount.8.html>

- Linux Kernel — procfs:  
  <https://docs.kernel.org/filesystems/proc.html>

- Linux Kernel — sysfs:  
  <https://docs.kernel.org/filesystems/sysfs.html>

- Linux Kernel — tmpfs:  
  <https://docs.kernel.org/filesystems/tmpfs.html>

- Linux Kernel — GPIO Character Device Userspace API v2:  
  <https://docs.kernel.org/userspace-api/gpio/chardev.html>

- Linux Kernel — legacy GPIO sysfs API:  
  <https://docs.kernel.org/userspace-api/gpio/sysfs.html>

- Bootlin — Embedded Linux training:  
  <https://bootlin.com/training/embedded-linux/>

---

> **Điều hướng:** ← Chủ đề 1 — Dòng lệnh Linux cơ bản · Chủ đề 3 — Vào/ra tệp →
