# Chủ đề 2 — Hệ thống tệp Linux (Filesystem)

> **Mục tiêu:** Hiểu rõ cách Linux tổ chức, phân giải và quản lý tài nguyên thông qua hệ thống tệp: từ cây thư mục `/`, đường dẫn, quá trình `pathname resolution`, `inode`, `dentry`, quyền truy cập, cơ chế `mount` cho tới các hệ thống tệp giao diện như `/dev`, `/proc`, `/sys`.
>
> **Quy ước ngôn ngữ:** Phần giải thích ưu tiên Tiếng Việt khi có cách dịch sát nghĩa và không làm sai khái niệm. Các thuật ngữ, tên định danh và tên cơ chế chuẩn của Linux/POSIX như `filesystem`, `VFS`, `pathname`, `pathname resolution`, `dentry`, `inode`, `symbolic link`, `hard link`, `mount`, `mount point`, `device node`, `procfs`, `sysfs`, `devtmpfs`, `tmpfs`, `open file description` được giữ nguyên để đảm bảo đúng ngữ nghĩa kỹ thuật và thuận tiện tra cứu tài liệu quốc tế. Khi cần, bản dịch Tiếng Việt sẽ được đặt bên cạnh ở lần xuất hiện đầu tiên.
>
> **Phạm vi:** Cây không gian tên (namespace), chuẩn FHS, đường dẫn, quá trình phân giải đường dẫn, `VFS`, `dentry`, `inode`, block lưu trữ, các loại tệp (file types), siêu dữ liệu (metadata), quyền `r/w/x`, các tiện ích cấu hình (`chmod`, `chown`, `umask`), cơ chế mount, các filesystem đặc biệt (`/dev`, `/proc`, `/sys`), công cụ quan sát (`df`, `du`).
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để xây dựng mô hình kiến trúc bộ nhớ và tệp tin trong tâm trí bạn trước khi thực hành viết code hoặc debug hệ thống.

Cách dễ nhất để nắm bắt filesystem Linux là giải quyết độc lập hai bài toán: **một tên tệp (pathname) được hệ thống rà soát như thế nào trong cây thư mục**, và **đối tượng thực tế mà tên đó trỏ tới được filesystem bên dưới lưu giữ/quản lý ra sao**. Pathname, thư mục và mount point thuộc về lớp không gian tên (namespace) hiển thị cho người dùng; còn `inode`, block và siêu dữ liệu (metadata) mô tả cấu trúc vật lý phía dưới. `VFS` (Virtual File System) chính là lớp "đại sứ" giúp Linux ghép nối hai góc nhìn này lại với nhau một cách xuyên suốt.

Chương này sẽ dẫn dắt bạn đi đúng con đường mà Kernel đi khi một chương trình (process) yêu cầu truy cập tệp: từ gốc `/` và pathname, lặn xuống tầng `dentry`/`inode`, kiểm tra quyền hạn, đi qua các điểm mount, và cuối cùng tương tác với các hệ thống tệp đặc biệt như `/dev`, `/proc` và `/sys`. Khi thấu hiểu luồng này, bạn sẽ làm chủ hoàn toàn cách dữ liệu tồn tại, đặc biệt trên các hệ thống Embedded Linux giới hạn tài nguyên.

---

## Mục lục

- [1. Hệ thống tệp trong Linux thực chất là gì?](#1-hệ-thống-tệp-trong-linux-thực-chất-là-gì)
- [2. Cây thư mục bắt đầu từ `/`](#2-cây-thư-mục-bắt-đầu-từ-)
- [3. Đường dẫn và cách Linux kernel tìm một tệp](#3-đường-dẫn-và-cách-linux-kernel-tìm-một-tệp)
- [4. VFS, `dentry` và `inode`](#4-vfs-dentry-và-inode)
- [5. Block, kích thước tệp và dung lượng thật](#5-block-kích-thước-tệp-và-dung-lượng-thật)
- [6. Các loại tệp trong Linux](#6-các-loại-tệp-trong-linux)
- [7. Metadata và `stat`](#7-metadata-và-stat)
- [8. Chủ sở hữu, nhóm và quyền `r/w/x`](#8-chủ-sở-hữu-nhóm-và-quyền-rwx)
- [9. `chmod`, `chown` và `umask`](#9-chmod-chown-và-umask)
- [10. `mount`: ghép nhiều filesystem vào một cây](#10-mount-ghép-nhiều-filesystem-vào-một-cây)
- [11. `/dev`, `/proc`, `/sys`: những hệ thống tệp đặc biệt](#11-dev-proc-sys-những-hệ-thống-tệp-đặc-biệt)
- [12. `ls`, `stat`, `file`, `df`, `du` quan sát lớp nào?](#12-ls-stat-file-df-du-quan-sát-lớp-nào)
- [13. Vòng đời tên tệp, liên kết và tệp đang mở](#13-vòng-đời-tên-tệp-liên-kết-và-tệp-đang-mở)
- [14. Tư duy gỡ lỗi hệ thống tệp](#14-tư-duy-gỡ-lỗi-hệ-thống-tệp)
- [15. Liên hệ với Embedded Linux](#15-liên-hệ-với-embedded-linux)
- [16. Tổng kết](#16-tổng-kết)
- [17. Tài liệu tham khảo](#17-tài-liệu-tham-khảo)

---

## 1. Hệ thống tệp trong Linux thực chất là gì?

Hệ thống tệp (`filesystem`) là tập hợp các quy tắc và cấu trúc dữ liệu dùng để tổ chức, đặt tên, quản lý metadata, lưu trữ và truy xuất các tệp/thư mục. Trong Linux, nhiều filesystem khác nhau như `ext4`, `F2FS`, `tmpfs`, `procfs` có thể đồng thời xuất hiện trong cùng một cây thư mục mà userspace nhìn thấy; lớp `VFS` giúp cung cấp một giao diện thống nhất để truy cập chúng.

### 1.1 Hai lớp dễ bị trộn lẫn

Để gỡ rối, hãy tách bạch hai khái niệm:

1. **Namespace (Không gian tên):** Là cách một tệp hoặc thư mục được **đặt tên và xuất hiện trong cây thư mục của Linux**. Mỗi đối tượng được truy cập thông qua một `pathname`, ví dụ `/home/user/a.txt`. Pathname này cho biết **đối tượng nằm ở đâu trong cây thư mục mà tiến trình nhìn thấy**, nhưng chưa cho biết dữ liệu thực sự được cung cấp bởi filesystem nào hay nằm trên thiết bị nào. Chỉ nhìn `/home/user/a.txt` thì chưa thể kết luận nó thuộc `ext4`, `F2FS`, `tmpfs` hay một filesystem khác.

2. **Backing Storage / Implementation:** Là **filesystem và cơ chế thực sự đứng phía sau pathname đó để quản lý dữ liệu và metadata của đối tượng**. Ví dụ, `/home/user/a.txt` có thể thuộc `ext4` nằm trên eMMC; `/tmp/a.txt` có thể thuộc `tmpfs` và dữ liệu nằm trong RAM; còn `/proc/cpuinfo` thuộc `procfs`, trong đó nội dung được Kernel tạo động thay vì được lưu như một regular file trên thiết bị khối. Vì vậy, `pathname` mô tả **đối tượng xuất hiện ở đâu**, còn backing storage/implementation mô tả **đối tượng đó thực sự được cung cấp và lưu trữ như thế nào**.

Có thể ghi nhớ ngắn gọn:

```text
pathname -> filesystem -> nơi/cơ chế cung cấp dữ liệu

/home/user/a.txt -> ext4   -> eMMC
/tmp/a.txt       -> tmpfs  -> RAM
/proc/cpuinfo    -> procfs -> Kernel tạo động
```

### 1.2 Mô hình tư duy: Nguồn dữ liệu → Filesystem → Mount point → Pathname

Một cách đơn giản để hình dung filesystem trong Linux là tách quá trình thành các lớp sau:

```text
Nguồn lưu trữ / nguồn cung cấp dữ liệu
                ↓
        Thực thể filesystem
                ↓
            Mount point
                ↓
   Pathname mà userspace nhìn thấy
```

Với filesystem nằm trên thiết bị khối, thực thể filesystem thường được tạo theo một **loại/định dạng filesystem** cụ thể như `ext4`, `FAT32`, `F2FS` hoặc `XFS`.

Ví dụ với một phân vùng trên SSD:

```text
SSD
 ↓
/dev/nvme0n1p2
 ↓
được tạo filesystem theo định dạng ext4
 ↓
một thực thể ext4 tồn tại trên phân vùng
 ↓
mount tại /
 ↓
/home/user/a.txt
```

Hoặc với thẻ nhớ ngoài:

```text
SD card
 ↓
/dev/mmcblk0p1
 ↓
được tạo filesystem theo định dạng FAT32
 ↓
một thực thể FAT32 tồn tại trên phân vùng
 ↓
mount tại /mnt/sdcard
 ↓
/mnt/sdcard/photo.jpg
```

Linux cũng có các filesystem không cần một định dạng dữ liệu cố định trên thiết bị khối. Ví dụ `tmpfs` lưu dữ liệu trong bộ nhớ ảo, còn `procfs` và `sysfs` biểu diễn dữ liệu do Kernel cung cấp.

```text
Nguồn/cơ chế       Loại filesystem     Mount point      Pathname ví dụ
-------------------------------------------------------------------------
SSD / partition    ext4                /                /home/user/a.txt
RAM / swap         tmpfs               /tmp             /tmp/a.txt
SD card            FAT32               /mnt/sdcard      /mnt/sdcard/photo.jpg
Kernel             procfs              /proc            /proc/cpuinfo
Kernel             sysfs               /sys             /sys/class/...
```

Điểm quan trọng là **filesystem được gắn (`mount`) vào cây namespace**, chứ không phải filesystem được “mount vào thiết bị lưu trữ”. Với trường hợp `ext4`, `FAT32`, `F2FS`... trên thiết bị khối, thiết bị hoặc phân vùng là nơi chứa thực thể filesystem; `mount` chỉ làm cho thực thể đó xuất hiện tại một vị trí trong namespace.

```text
Thiết bị / phân vùng
        ↓
chứa một thực thể filesystem
        ↓
filesystem được mount vào một mount point
        ↓
userspace truy cập qua pathname
```

Ví dụ:

```text
/dev/nvme0n1p2
       │
       │ chứa một thực thể ext4
       ▼
      ext4
       │
       │ mount
       ▼
       /
```

Do đó, từ góc nhìn userspace, các nguồn dữ liệu rất khác nhau vẫn xuất hiện trong cùng một cây pathname:

```text
/home/user/a.txt
/tmp/a.txt
/proc/cpuinfo
/sys/class/...
```

Mô hình cần ghi nhớ:

```text
Nguồn dữ liệu → Thực thể filesystem → Mount point → Pathname
```

Riêng với filesystem nằm trên thiết bị khối, có thể mở rộng thành:

```text
Block device / partition
        ↓
Định dạng filesystem (ví dụ ext4, FAT32)
        ↓
Thực thể filesystem
        ↓
Mount point
        ↓
Pathname
```

### 1.3 Phân biệt định dạng, filesystem type, phần hiện thực và thực thể filesystem

Từ `filesystem` thường được dùng ở nhiều mức khác nhau. Đây là nguyên nhân khiến các câu như “`ext4` là filesystem”, “phân vùng này được format `ext4`” hoặc “Linux mount FAT32 bằng `vfat`” dễ gây nhầm lẫn. Để hiểu chính xác, nên tách bốn khái niệm sau.

#### 1.3.1 Filesystem format — định dạng filesystem

**Filesystem format** mô tả cách dữ liệu và metadata được bố trí và biểu diễn trên nơi lưu trữ. Với filesystem lưu trên block device, đây thường là **định dạng trên thiết bị lưu trữ (on-disk format)**.

Ví dụ:

```text
ext4
FAT32
F2FS
XFS
```

Định dạng `ext4` quy định các cấu trúc như:

```text
superblock
block group
inode table
block/inode bitmap
directory entry
extent
journal
...
```

Khi chạy:

```bash
mkfs.ext4 /dev/nvme0n1p2
```

công cụ `mkfs.ext4` tạo các cấu trúc cần thiết trên `/dev/nvme0n1p2` để vùng lưu trữ đó chứa một filesystem theo định dạng `ext4`.

```text
/dev/nvme0n1p2
       │
       │ mkfs.ext4
       ▼
┌──────────────────────────────┐
│ một thực thể ext4            │
│                              │
│ superblock                   │
│ inode tables                 │
│ bitmaps                      │
│ extents                      │
│ directory entries            │
│ data blocks                  │
│ journal                      │
│ ...                          │
└──────────────────────────────┘
```

Ở mức này, `ext4` không phải ổ cứng hay phân vùng. Nó là **định dạng filesystem** quy định cách các cấu trúc được bố trí và diễn giải.

`FAT32` cũng là một định dạng filesystem, nhưng sử dụng cách tổ chức khác, chẳng hạn FAT, cluster và directory entry.

> **Lưu ý:** Không phải filesystem nào cũng có một định dạng on-disk. `tmpfs`, `procfs`, `sysfs` không cần một cấu trúc filesystem bền vững được ghi sẵn trên SSD/eMMC như `ext4`.

#### 1.3.2 Filesystem type — tên loại filesystem mà Kernel đăng ký với VFS

Trong Linux, một phần hiện thực filesystem đăng ký một **filesystem type** với `VFS`. Tên này là tên mà Kernel dùng để nhận diện loại filesystem khi mount.

Ví dụ thường gặp:

```text
Filesystem format     Filesystem type thường thấy trên Linux
-------------------------------------------------------------
ext4                  ext4
FAT32                 vfat
F2FS                  f2fs
XFS                   xfs
-                     tmpfs
-                     proc
-                     sysfs
```

Với `ext4`, tên định dạng và filesystem type đều là `ext4`, nên hai khái niệm dễ bị xem là một.

Với FAT thì sự khác biệt dễ thấy hơn. Một phân vùng có thể được định dạng **FAT32**, nhưng trên Linux bạn thường mount nó bằng filesystem type `vfat`, ví dụ:

```bash
mount -t vfat /dev/mmcblk0p1 /mnt/sdcard
```

Vì vậy:

```text
FAT32  → nói chủ yếu về định dạng dữ liệu trên thiết bị
vfat   → filesystem type/implementation mà Linux dùng để truy cập họ FAT có tên dài
```

#### 1.3.3 Filesystem implementation — phần hiện thực filesystem trong Kernel

Kernel cần có **phần hiện thực filesystem** tương ứng để biết cách đọc, ghi và quản lý filesystem đó. Đây là phần mã nằm trong Kernel hoặc được nạp dưới dạng kernel module, hiện thực các thao tác mà `VFS` yêu cầu đối với một loại filesystem cụ thể.

Ví dụ:

```text
Ứng dụng
   ↓
System call
   ↓
VFS
   ↓
phần hiện thực ext4 trong Kernel
   ↓
thực thể ext4 trên /dev/nvme0n1p2
```

`VFS` cung cấp giao diện chung và thực hiện nhiều xử lý dùng chung ở tầng filesystem. Khi cần một thao tác phụ thuộc vào filesystem cụ thể, `VFS` gọi các operation mà phần hiện thực filesystem đã cung cấp, chẳng hạn các operation liên quan đến `inode`, file đang mở, thư mục hoặc `superblock`.

Có thể hiểu ngắn gọn:

```text
VFS
 ↓
"Cần tạo / tìm / đọc / ghi / xóa đối tượng này"
 ↓
phần hiện thực filesystem tương ứng
 ↓
thao tác trên thực thể filesystem cụ thể
```

Ví dụ, giả sử `/data` là mount point của một thực thể `ext4` nằm trên `/dev/mmcblk0p1`. Khi ứng dụng yêu cầu tạo `/data/a.txt`:

```text
Ứng dụng
   │
   │ open("/data/a.txt", O_CREAT, ...)
   ▼
System call
   ▼
VFS
   │
   │ xác định /data thuộc filesystem ext4
   ▼
phần hiện thực ext4
   │
   │ thực hiện các thao tác đặc thù của ext4
   ▼
thực thể ext4 trên /dev/mmcblk0p1
```

Ở mức khái niệm, quá trình tạo file có thể bao gồm các công việc như:

```text
1. Tìm thư mục cha /data
2. Kiểm tra xem tên a.txt đã tồn tại hay chưa
3. Cấp phát và khởi tạo inode mới
4. Tạo directory entry cho tên a.txt
5. Liên kết directory entry với inode mới
6. Cập nhật metadata và các cấu trúc quản lý cần thiết
7. Khi có dữ liệu được ghi, cấp phát vùng lưu trữ và cập nhật ánh xạ dữ liệu
```

Với `ext4`, phần hiện thực `ext4` phải thực hiện các bước trên theo đúng cấu trúc và quy tắc của `ext4`. Với `tmpfs`, cùng yêu cầu tạo file vẫn đi qua `VFS`, nhưng phần hiện thực `tmpfs` sẽ quản lý đối tượng theo cơ chế của `tmpfs` thay vì ghi các cấu trúc `ext4` xuống block device.

Do đó, không nên hiểu phần hiện thực filesystem chỉ là mã "đọc định dạng". Nó là phần mã thực hiện các thao tác cụ thể của filesystem, ví dụ:

- tra cứu tên trong thư mục;
- tạo và xóa file;
- tạo và xóa thư mục;
- tạo `hard link` hoặc `symbolic link`;
- đọc và ghi dữ liệu;
- quản lý metadata;
- cấp phát hoặc giải phóng vùng lưu trữ khi filesystem đó cần;
- đồng bộ dữ liệu và metadata theo cơ chế của filesystem.

Mối quan hệ cần ghi nhớ:

```text
Filesystem format
    │
    │ quy định dữ liệu phải được tổ chức như thế nào
    ▼
Filesystem implementation
    │
    │ mã trong Kernel biết cách thao tác theo các quy tắc đó
    ▼
Filesystem instance
    │
    │ một filesystem cụ thể đang tồn tại
    ▼
file / directory / metadata / dữ liệu
```

Nếu một thiết bị chứa filesystem theo định dạng `ext4` nhưng Kernel không có hỗ trợ `ext4`, Kernel vẫn có thể nhận ra block device, nhưng không có phần hiện thực cần thiết để diễn giải và thao tác các cấu trúc `ext4` thành file, thư mục và metadata để mount theo cách thông thường.

#### 1.3.4 Filesystem instance — thực thể filesystem cụ thể

**Thực thể filesystem** là một filesystem cụ thể đang tồn tại, thay vì chỉ là tên của định dạng hoặc filesystem type.

Ví dụ:

```text
/dev/nvme0n1p2  → một thực thể ext4
/dev/sda1        → một thực thể ext4 khác
/dev/mmcblk0p1   → một thực thể FAT32
```

Hai phân vùng khác nhau đều có thể được format `ext4`; khi đó chúng là **hai thực thể filesystem khác nhau**, mặc dù cùng sử dụng định dạng và filesystem type `ext4`.

```text
/dev/nvme0n1p2 ──→ thực thể ext4 A
/dev/sda1      ──→ thực thể ext4 B
```

Với `tmpfs`, `procfs` hoặc `sysfs`, Kernel có thể tạo một thực thể filesystem khi filesystem type tương ứng được mount; chúng không cần một filesystem on-disk đã được tạo trước bằng `mkfs`.

#### 1.3.5 Không phải filesystem nào cũng cần `mkfs`

Không phải mọi filesystem đều phải được tạo trước trên thiết bị lưu trữ bằng một công cụ `mkfs`. Có thể chia thành hai trường hợp chính.

**Trường hợp 1 — Filesystem có định dạng lưu trữ trên thiết bị (`on-disk filesystem`)**

Các filesystem như `ext4`, `F2FS`, `XFS` hoặc FAT thường tồn tại dưới dạng các cấu trúc dữ liệu được ghi trên một block device hoặc partition.

Ví dụ với `ext4`:

```text
/dev/mmcblk0p1
        ↓
    mkfs.ext4
        ↓
tạo các cấu trúc ext4
(superblock, inode, bitmap, journal, ...)
        ↓
một thực thể ext4 tồn tại trên thiết bị
        ↓
       mount
        ↓
      /data
```

Ở trường hợp này, `mkfs` có nhiệm vụ **tạo filesystem trước**, còn `mount` đưa filesystem đã tồn tại đó vào namespace của Linux.

Có thể ghi nhớ:

```text
Block device → mkfs → thực thể filesystem tồn tại → mount → namespace
```

**Trường hợp 2 — Filesystem được tạo hoặc thiết lập khi hệ thống đang chạy**

Các filesystem như `tmpfs`, `procfs` và `sysfs` không cần một filesystem đã được tạo trước trên block device bằng `mkfs`.

Ví dụ:

```bash
mount -t tmpfs tmpfs /tmp
mount -t proc proc /proc
mount -t sysfs sysfs /sys
```

Khi có yêu cầu `mount`, Kernel sử dụng phần hiện thực filesystem tương ứng để tạo hoặc thiết lập thực thể filesystem cần thiết trong lúc hệ thống đang chạy.

```text
Yêu cầu mount
      ↓
Kernel
      ↓
phần hiện thực filesystem
(tmpfs / procfs / sysfs)
      ↓
tạo hoặc thiết lập thực thể filesystem tại runtime
      ↓
mount vào namespace
```

Ví dụ:

```text
tmpfs
  ↓
thực thể filesystem sử dụng bộ nhớ
  ↓
/tmp
```

```text
procfs
  ↓
thực thể filesystem biểu diễn dữ liệu Kernel
  ↓
/proc
```

```text
sysfs
  ↓
thực thể filesystem biểu diễn Kernel device model
  ↓
/sys
```

Do đó, không nên ghi nhớ máy móc rằng:

```text
Filesystem → phải mkfs → mới mount được
```

Quy tắc chính xác hơn là:

```text
Filesystem on-disk:
Block device → mkfs → thực thể filesystem → mount

Filesystem runtime:
yêu cầu mount → Kernel tạo/thiết lập thực thể filesystem → mount
```

> **Lưu ý:** Kernel không nhất thiết tự ý mount `tmpfs`, `procfs` hoặc `sysfs`. Thông thường một thành phần userspace như `init`, `systemd` hoặc script khởi động sẽ yêu cầu thao tác `mount`; Kernel sau đó thực hiện việc tạo hoặc thiết lập thực thể filesystem tương ứng.

#### 1.3.6 Ghép các khái niệm lại với nhau

Ví dụ đầy đủ với `ext4`:

```text
SSD
 ↓
/dev/nvme0n1
 ↓
partition /dev/nvme0n1p2
 ↓
mkfs.ext4
 ↓
định dạng ext4 được ghi lên phân vùng
 ↓
một thực thể ext4 tồn tại trên phân vùng
 ↓
filesystem type ext4 + phần hiện thực ext4 trong Kernel
 ↓
VFS
 ↓
mount tại /home
 ↓
/home/user/a.txt
```

Bảng phân biệt:

| Khái niệm | Ví dụ | Ý nghĩa |
|---|---|---|
| Thiết bị khối (`block device`) | `/dev/nvme0n1` | Giao diện thiết bị lưu trữ dạng block |
| Phân vùng (`partition`) | `/dev/nvme0n1p2` | Một vùng logic của block device; không phải lúc nào cũng bắt buộc phải có |
| Định dạng filesystem | `ext4`, `FAT32`, `F2FS` | Quy định cách dữ liệu/metadata được bố trí trên nơi lưu trữ |
| Filesystem type | `ext4`, `vfat`, `tmpfs`, `proc`, `sysfs` | Tên loại filesystem mà Kernel/VFS dùng để nhận diện khi mount |
| Phần hiện thực filesystem | mã `ext4`, `vfat`, `tmpfs`... trong Kernel | Mã thực hiện các operation đặc thù để `VFS` thao tác trên thực thể filesystem tương ứng |
| Thực thể filesystem | `ext4` trên `/dev/nvme0n1p2` | Một filesystem cụ thể đang tồn tại |
| `mount point` | `/home`, `/mnt/sdcard` | Vị trí mà thực thể filesystem xuất hiện trong namespace |

> **Ghi nhớ:** Khi nói ngắn gọn “`ext4` là một filesystem”, ngữ cảnh có thể đang nói về **định dạng**, **filesystem type**, **phần hiện thực**, hoặc một **thực thể ext4 cụ thể**. Với `ext4`, nhiều lớp trùng tên nên thường không gây vấn đề. Với FAT32/`vfat`, sự khác nhau hiện ra rõ hơn, vì tên định dạng trên thiết bị và filesystem type của Linux không nhất thiết giống nhau.

### 1.4 Linux cho nhiều filesystem cùng xuất hiện trong một cây

Khác với Windows thường chia thành ổ C:, D: rời rạc, Linux cung cấp một ảo giác về một cây thư mục duy nhất. Trong đó:

```text
/             -> ext4 (Filesystem gốc, ví dụ nằm trên SSD/eMMC)
/proc         -> procfs (Giao diện dữ liệu của Kernel)
/dev          -> devtmpfs (Quản lý các device node)
/mnt/sdcard   -> exFAT (Ví dụ filesystem trên thẻ nhớ ngoài)
```

Người dùng (và chương trình) chỉ việc đi theo nhánh thư mục, Linux Kernel sẽ tự biết khi nào bạn "bước" qua ranh giới từ filesystem này sang filesystem khác thông qua cơ chế `mount`.

### 1.5 Không nên hiểu quá máy móc câu “everything is a file”

"Mọi thứ đều là tệp" là triết lý UNIX, nghĩa là Kernel cố gắng cung cấp một bộ API chung (`open`, `read`, `write`, `close`) để tương tác với đa dạng tài nguyên: tệp tin, thiết bị, tiến trình, socket. 

Tuy nhiên, **ngữ nghĩa** của chúng hoàn toàn khác biệt. Ví dụ, `read()` trên một tệp văn bản (`regular file`) sẽ trả về nội dung từ đĩa cứng, nhưng `read()` từ `/dev/ttyS0` (thiết bị UART serial) lại là chờ nhận các byte đến từ phần cứng ngoại vi.

---

## 2. Cây thư mục bắt đầu từ `/`

Mọi thứ trong Linux đều quy về một cây không gian tên duy nhất, có chung một gốc là `/` (root). 

### 2.1 `/` là gốc của namespace

`/` là điểm xuất phát để Kernel bắt đầu bất kỳ hành trình phân giải đường dẫn tuyệt đối nào.

```text
/
├── bin   (Chứa các file thực thi cơ bản)
├── dev   (Các device node thiết bị)
├── etc   (Các file cấu hình hệ thống)
├── home  (Thư mục cá nhân của người dùng)
├── proc  (Filesystem ảo về tiến trình và Kernel)
├── run   (Dữ liệu runtime trên RAM)
├── sys   (Mô hình thiết bị hệ thống)
├── tmp   (File tạm thời)
├── usr   (Phần mềm, thư viện dùng chung)
└── var   (Dữ liệu thay đổi thường xuyên như log)
```

> **Ghi chú quan trọng:** Cây trên biểu diễn **namespace mà một tiến trình (process) nhìn thấy**, nó KHÔNG phải sơ đồ mô tả các phân vùng vật lý (partitions). Thư mục `/proc` là `procfs` sinh ra động trên RAM, trong khi `/etc` lại lấy dữ liệu từ `ext4` trên ổ cứng. Do đó, gốc `/` không nên bị mặc định đồng nghĩa cố định với “phân vùng đĩa vật lý đầu tiên”. Việc gắn kết các không gian tên (mount), `chroot` hoặc công nghệ Container hoàn toàn có thể định nghĩa lại gốc `/` này cho các tiến trình khác nhau.

### 2.2 Ý nghĩa khái quát của một số thư mục cốt lõi

*   **`/etc`**: Trung tâm chứa các file cấu hình hệ thống (như cấu hình mạng, dịch vụ khởi động).
*   **`/var`**: Chứa dữ liệu có tần suất thay đổi liên tục (Variable data) như log hệ thống (`/var/log`). Trong hệ nhúng (Embedded Linux), vì bộ nhớ Flash có giới hạn số lần ghi xóa, thư mục `/var` thường được thiết kế đặc biệt (mount trên RAM hoặc phân vùng log riêng biệt).
*   **`/dev`, `/proc`, `/sys`**: KHÔNG chứa "file bình thường". Chúng là các cánh cửa (interfaces) mở ra để userspace nhìn sâu vào cấu trúc phần cứng và Kernel.

### 2.3 FHS là quy ước, không phải định luật vật lý

Chuẩn `Filesystem Hierarchy Standard` (FHS) giúp các bản phân phối (distro) có tính đồng nhất (phần mềm cài trên Ubuntu hay Fedora đều biết tìm file cấu hình ở `/etc`). Tuy nhiên, khi build hệ thống Embedded Linux (ví dụ bằng Yocto hoặc Buildroot), các rootfs tối giản hoàn toàn có quyền lược bỏ những thư mục không cần thiết.

---

## 3. Đường dẫn và cách Linux kernel tìm một tệp

Khi nhận một `pathname`, Linux kernel không nhảy thẳng đến kết quả; nó phải dò tìm từng thành phần (component) thư mục một.

### 3.1 Tên tệp, thành phần đường dẫn và đường dẫn

Ví dụ với `pathname`: `/home/user/docs/report.txt`

Chuỗi này có 4 thành phần (component): `home`, `user`, `docs` và tệp đích `report.txt`. Mỗi thành phần bắt buộc phải được tra cứu lần lượt trong thư mục cha của nó.

### 3.2 Đường dẫn tuyệt đối & Tương đối

*   **Tuyệt đối:** Bắt đầu bằng `/` (ví dụ `/etc/passwd`). Quá trình phân giải luôn xuất phát từ gốc namespace.
*   **Tương đối:** Không có `/` ở đầu (ví dụ `src/main.c`). Quá trình phân giải xuất phát từ Thư mục làm việc hiện tại (Current Working Directory - CWD) của tiến trình.

### 3.3 `.` và `..`

*   `.` (chấm): Đại diện cho thư mục hiện tại. Giữ lookup đứng yên.
*   `..` (hai chấm): Yêu cầu Kernel bước lùi lên thư mục cha (parent directory) trong namespace hiện hành.

### 3.4 `pathname resolution` (Phân giải đường dẫn)

Đây là quy trình Kernel diễn giải một `pathname` thành đối tượng mà hệ thống có thể thao tác. VFS tra cứu từng thành phần của đường dẫn và tận dụng `dcache` để tránh phải thực hiện lại những phép tra cứu tên đã biết.

```text
[ Process (Tiến trình) ]
      |
      | Yêu cầu: pathname "/a/b/c"
      v
[ VFS (Virtual File System) ]
      |
      | 1. Bắt đầu từ gốc "/" (hoặc CWD với đường dẫn tương đối).
      |
      | 2. Tra cứu thành phần "a".
      +----> [ dcache ]
      |
      | 3. Từ "a", tra cứu thành phần "b".
      +----> [ dcache ]
      |
      | 4. Từ thư mục "b", tra cứu tên "c".
      +----> [ dcache ]
      |
      | Nếu dcache chưa có câu trả lời cho "c":
      | VFS phải thực hiện slow lookup.
      |
      | 5. VFS gọi phép lookup do filesystem implementation
      |    đang quản lý thư mục "b" cung cấp.
      v
[ Filesystem Implementation, ví dụ ext4 ]
      |
      | Hiểu cách directory, inode và các cấu trúc của ext4
      | được tổ chức để tìm entry có tên "c".
      |
      +----> [ Cache dữ liệu filesystem trong RAM ]
      |             |
      |             | Nếu dữ liệu cần thiết chưa có trong RAM
      |             v
      |       [ Block I/O Layer ]
      |             |
      |             v
      |       [ Device Driver ]
      |       (NVMe / MMC / SATA / ...)
      |             |
      |             v
      |       [ SSD / eMMC / ... ]
      |
      | 6. Nếu tìm thấy "c", filesystem implementation
      |    lấy hoặc tạo VFS inode tương ứng.
      v
[ VFS liên kết dentry "c" với inode ]
      |
      | dentry được đưa vào dcache
      v
[ Pathname resolution tiếp tục hoặc hoàn tất ]
```

> **Đọc sơ đồ:** Tiến trình chỉ đưa cho Kernel một `pathname`, ví dụ `/a/b/c`. VFS phân giải đường dẫn theo từng thành phần `a` → `b` → `c` và sử dụng `dcache` để tăng tốc tra cứu tên. Nếu thông tin về một thành phần chưa có trong `dcache`, điều đó **không có nghĩa là tệp không tồn tại**, cũng không có nghĩa Kernel chắc chắn phải đọc ngay thiết bị lưu trữ vật lý. VFS sẽ gọi phép `lookup` do `filesystem implementation` đang quản lý thư mục hiện tại cung cấp.
>
> Ví dụ, nếu thư mục `b` nằm trên một filesystem `ext4`, VFS sẽ gọi phần hiện thực `ext4`. Phần hiện thực này biết cách directory, inode và các cấu trúc khác của `ext4` được tổ chức nên có thể tìm entry tên `c`. Dữ liệu cần thiết cho quá trình tra cứu có thể đã nằm trong RAM; chỉ khi chưa có thì I/O mới phải đi tiếp qua `block layer`, `device driver` và cuối cùng tới SSD, eMMC hoặc thiết bị lưu trữ tương ứng.
>
> Cần phân biệt rõ ba lớp:
>
> ```text
> VFS
>   ↓
> Filesystem implementation
>   ↓
> Device driver
> ```
>
> `VFS` cung cấp cơ chế và giao diện chung; `filesystem implementation` biết cách thực hiện thao tác trên filesystem cụ thể; còn `device driver` biết cách giao tiếp với phần cứng. Do quá trình phân giải diễn ra từng thành phần, một `pathname` dài có thể lỗi tại bất kỳ thư mục trung gian nào chứ không nhất thiết chỉ tại tệp đích.

### 3.5 `symbolic link` làm thay đổi đường tra cứu

Một liên kết mềm (`symbolic link`) thực chất chứa nội dung là một đoạn chuỗi pathname khác.
Khi Kernel dò đường và đụng phải một symbolic link, nó sẽ dừng đường đi hiện tại, đọc nội dung của link đó, thay thế đoạn pathname và phân giải lại từ đầu (đối với đường dẫn tuyệt đối) hoặc từ thư mục chứa link đó (đối với đường dẫn tương đối).
Ví dụ:
- Với đường dẫn tuyệt đối (Bắt đầu bằng /): Bạn tạo một link tại `/ban_lam_viec/chu_ky_link` và nội dung bên trong link này là chuỗi `/o_cung/du_lieu/chu_ky.txt`. Khi bạn mở `/ban_lam_viec/chu_ky_link`, Kernel đi đến thư mục `/ban_lam_viec` và đụng phải link, nó sẽ dừng lại để đọc chuỗi bên trong. Vì thấy dấu / ở đầu, Kernel lập tức bỏ con đường cũ, quay ngược về tận gốc / rồi tiến hành tra cứu lại từ đầu theo hướng / → o_cung → du_lieu → chu_ky.txt.
- Với đường dẫn tương đối (Bắt đầu bằng tên file hoặc ..): Bạn tạo một link khác cũng tại `/ban_lam_viec/chu_ky_link_2` nhưng nội dung bên trong link này lại là chuỗi `../o_cung/du_lieu/chu_ky.txt`. Khi bạn mở link này, Kernel đụng phải link và đọc được chuỗi ../. Vì đây là đường dẫn tương đối, Kernel không quay về gốc / mà đứng ngay tại thư mục chứa link là `/ban_lam_viec`, sau đó làm theo lệnh .. để lùi lại một bước ra thư mục mẹ / rồi từ đó mới rẽ tiếp vào o_cung → du_lieu → chu_ky.txt.

---

## 4. VFS, `dentry` và `inode`

VFS là hạt nhân điều phối, `dentry` ánh xạ cấu trúc tên, còn `inode` lưu trữ đặc tính kỹ thuật của đối tượng.

### 4.1 VFS (Virtual File System) là gì?

`VFS` là một tầng trừu tượng (`abstraction layer`) nằm bên trong Kernel. Nó cung cấp mô hình và giao diện chung để userspace có thể dùng các system call như `open()`, `read()`, `write()` hay `stat()` mà không cần biết đối tượng phía dưới thuộc `ext4`, `tmpfs`, `procfs`, `NFS` hay một filesystem khác.

```text
[ Ứng dụng (Userspace) ]
   |
   | open(), read(), write(), stat(), ...
   v
[ System Call Interface ]
   |
   v
[ VFS ]
   |
   +----> [ ext4 implementation ]  ---> ext4 filesystem instance
   |                                      |
   |                                      +--> block layer
   |                                           |
   |                                           +--> device driver
   |                                                |
   |                                                +--> SSD / eMMC / ...
   |
   +----> [ tmpfs implementation ] ---> bộ nhớ
   |
   +----> [ procfs implementation ] --> dữ liệu nội bộ Kernel
   |
   +----> [ sysfs implementation ] ---> Kernel device model
   |
   +----> [ ... ]
```

> **Đọc sơ đồ:** Ứng dụng chỉ sử dụng các system call chuẩn. VFS xác định đối tượng đang thuộc filesystem nào rồi gọi các operation mà `filesystem implementation` tương ứng cung cấp. Nhờ vậy cùng một lệnh `cp` có thể sao chép tệp từ `ext4` sang `tmpfs` mà chương trình không cần tự viết riêng logic cho từng filesystem.

#### Phân biệt `VFS`, `filesystem implementation` và `device driver`

Ba khái niệm này thuộc các tầng khác nhau:

```text
Userspace
   ↓
System call
   ↓
VFS
   ↓
Filesystem Implementation
   ↓
Filesystem Instance
   ↓
Block I/O Layer        ← nếu filesystem sử dụng block device
   ↓
Device Driver
   ↓
Phần cứng
```

Có thể ghi nhớ:

```text
VFS
→ biết cần thực hiện loại thao tác nào và cung cấp giao diện chung.

Filesystem implementation
→ biết thao tác đó phải được thực hiện như thế nào
  trên filesystem cụ thể.

Device driver
→ biết giao tiếp với phần cứng như thế nào.
```

Ví dụ khi truy cập một tệp trên `ext4` nằm trong eMMC:

```text
VFS
 ↓
ext4 implementation
 ↓
ext4 filesystem instance trên /dev/mmcblk0p1
 ↓
block layer
 ↓
MMC/eMMC driver
 ↓
eMMC
```

`ext4 implementation` **không phải device driver**. Nó là phần mã filesystem trong Kernel biết cách xử lý các cấu trúc của `ext4`, chẳng hạn directory, inode, extent, metadata và việc cấp phát block. Ngược lại, MMC/eMMC driver không hiểu khái niệm file hay directory của `ext4`; nó chịu trách nhiệm chuyển các yêu cầu I/O ở tầng block thành thao tác giao tiếp với phần cứng.

Mối quan hệ cốt lõi có thể tóm tắt như sau:

```text
VFS
  ↓  "Cần lookup / create / read / write ..."
Filesystem implementation
  ↓  "Thao tác đó được biểu diễn và thực hiện thế nào trong filesystem này?"
Filesystem instance
  ↓
Block layer / bộ nhớ / dữ liệu Kernel / mạng / ...
  ↓  (nếu có thiết bị phần cứng)
Device driver
```

### 4.2 `dentry` là gì?

`dentry` là viết tắt của **directory entry**, nhưng trong ngữ cảnh VFS, nó là một **đối tượng runtime nằm trong RAM** do VFS quản lý. Một `dentry` biểu diễn một **thành phần tên (`pathname component`) trong một thư mục cha cụ thể** và thường liên kết tên đó với một `inode`.

Mô hình cơ bản:

```text
Thư mục cha + Tên
        ↓
      dentry
        ↓
      inode
```

Ví dụ với pathname:

```text
/home/user/a.txt
```

VFS không xem `a.txt` như một cái tên độc lập. Nó quan tâm đến quan hệ:

```text
parent: /home/user
name:   a.txt
        ↓
      dentry
        ↓
      inode tương ứng
```

Một `dentry` quan trọng thường chứa ba thông tin về mặt khái niệm:

* Tên của thành phần pathname, ví dụ `a.txt`.
* Tham chiếu tới `dentry` của thư mục cha, ví dụ `user`.
* Tham chiếu tới `inode` của đối tượng mang tên đó. Tham chiếu này cũng có thể rỗng nếu Kernel đã xác định tên đó không tồn tại; trường hợp này được gọi là **negative dentry**.

Các `dentry` được lưu trong **`dcache` (dentry cache)**. Vì `dentry` sống trong RAM và không được ghi xuống thiết bị lưu trữ, Kernel có thể dùng `dcache` để tăng tốc `pathname resolution` mà không phải yêu cầu filesystem bên dưới tra cứu lại cùng một tên ở mỗi lần truy cập.

#### 4.2.1 VFS `dentry` khác với `directory entry` của filesystem cụ thể

Đây là hai khái niệm có tên gần giống nhau nhưng thuộc **hai tầng khác nhau**.

Ví dụ `/home` nằm trên một filesystem `ext4` và trong thư mục `/home/user` có tệp `a.txt`.

Ở tầng `ext4`, dữ liệu của directory phải lưu một ánh xạ tương tự:

```text
Filesystem instance ext4

Directory /home/user
        │
        └── "a.txt" → inode number 1234
```

Bản ghi này là **directory entry theo định dạng của `ext4`**. Nó thuộc dữ liệu của filesystem instance và, đối với `ext4`, được lưu bền vững trên block device.

Ở tầng VFS, Kernel có thể đồng thời có một đối tượng `dentry` trong RAM:

```text
RAM / VFS

parent dentry: "user"
name:          "a.txt"
                   │
                   ▼
             dentry "a.txt"
                   │
                   ▼
              VFS inode
```

Do đó không nên hiểu:

```text
ext4 directory entry = VFS dentry
```

Hai thứ này có vai trò liên quan nhưng **không phải cùng một cấu trúc dữ liệu**:

```text
Directory entry của filesystem cụ thể
→ cấu trúc do filesystem implementation quản lý
→ biểu diễn tên theo quy tắc của filesystem đó

VFS dentry
→ đối tượng runtime chung của VFS
→ nằm trong RAM
→ dùng trong pathname lookup và dcache
```

Với `ext4`, directory entry thường ánh xạ tên tệp tới `inode number`. Với các filesystem khác như FAT, tmpfs hoặc NFS, cách filesystem bên dưới biểu diễn và tìm tên có thể khác. VFS che giấu sự khác biệt đó bằng mô hình `dentry` chung.

#### 4.2.2 `dentry` được tạo và sử dụng khi lookup như thế nào?

Giả sử tiến trình truy cập:

```text
/home/user/a.txt
```

và VFS đã đi tới thư mục `/home/user` nhưng chưa có thông tin về tên `a.txt` trong `dcache`:

```text
VFS
 ↓
tìm "a.txt" trong dcache
 ↓
cache miss
```

`cache miss` chỉ có nghĩa là **VFS chưa có câu trả lời được cache trong RAM**. Nó chưa thể kết luận `a.txt` không tồn tại.

VFS sẽ yêu cầu `filesystem implementation` đang quản lý thư mục `/home/user` thực hiện phép `lookup`:

```text
VFS
 │
 │ lookup tên "a.txt" trong thư mục cha
 ▼
Filesystem implementation
(ví dụ ext4)
 │
 │ tra cứu cấu trúc directory của filesystem
 ▼
Tìm thấy:
"a.txt" → inode number 1234
 │
 ▼
lấy/tạo VFS inode tương ứng
 │
 ▼
gắn inode với dentry "a.txt"
 │
 ▼
lưu dentry vào dcache
```

Nếu lần sau pathname đó được tra cứu và `dentry` vẫn còn hợp lệ trong `dcache`, VFS có thể sử dụng kết quả đã cache thay vì thực hiện đầy đủ filesystem lookup một lần nữa.

Nếu filesystem xác nhận tên không tồn tại, VFS vẫn có thể cache kết quả dưới dạng **negative dentry**:

```text
parent: /home/user
name:   missing.txt
inode:  NULL
```

Điều này giúp những lần lookup lặp lại đối với một tên không tồn tại cũng có thể được xử lý nhanh hơn.

#### 4.2.3 Không phải filesystem nào cũng có `directory entry` vật lý trên đĩa

Cụm từ "directory entry được ghi trên đĩa" chỉ phù hợp với các filesystem lưu trữ bền vững trên block device như `ext4`.

Ví dụ:

```text
ext4
→ directory entry thuộc dữ liệu filesystem trên block device

tmpfs
→ dữ liệu filesystem tồn tại trong bộ nhớ

procfs / sysfs
→ các entry được filesystem implementation tạo/biểu diễn từ dữ liệu Kernel
```

Vì vậy cách diễn đạt tổng quát hơn là:

> **`dentry` của VFS là đối tượng runtime trong RAM dùng để biểu diễn và cache quan hệ giữa một tên và một đối tượng filesystem. Nó khác với cấu trúc directory entry do từng filesystem implementation quản lý. Với filesystem on-disk như `ext4`, directory entry của filesystem được lưu trong dữ liệu của filesystem trên block device; còn với các pseudo-filesystem như `procfs` hoặc `sysfs`, không tồn tại một directory entry vật lý trên đĩa theo nghĩa đó.**

Mô hình cần ghi nhớ:

```text
Cấu trúc directory của filesystem cụ thể
                ↓
      filesystem implementation
                ↓
             lookup
                ↓
           VFS dentry
                ↓
            VFS inode
```

Nói ngắn gọn:

```text
Directory entry của filesystem
→ filesystem bên dưới lưu/biểu diễn tên như thế nào.

VFS dentry
→ Kernel biểu diễn và cache tên đó như thế nào trong RAM.
```

### 4.3 `inode` là gì?

`inode` (Index Node) là hạt nhân lưu trữ của mọi đối tượng tệp tin. Nó chứa toàn bộ **siêu dữ liệu (metadata)** và bản đồ ánh xạ tới các block dữ liệu thực tế, **NGOẠI TRỪ TÊN TỆP**. Việc dữ liệu thực tế không năm ở inode bởi vì dữ liệu thực tế quá lớn, inode chỉ cung cấp cho bạn các con trỏ tới các block dữ liệu đó trên ổ cứng. Khi bạn mở tệp, các dữ liệu sẽ được ghép lại hoàn chỉnh.

Siêu dữ liệu trong inode bao gồm:
*   Loại tệp (file type).
*   Quyền truy cập (mode/permissions).
*   Chủ sở hữu (UID/GID).
*   Kích thước (size).
*   Các mốc thời gian (timestamps).
*   Số lượng liên kết cứng (link count).
*   Con trỏ tới các khối dữ liệu (data mapping).

### 4.4 `inode` không chứa pathname đầy đủ

Tên tệp không nằm trong `inode`. Tên tệp thuộc quyền quản lý của cấu trúc thư mục (directory) trỏ tới `inode` đó. Sự chia tách kiến trúc này vô cùng mạnh mẽ: nó cho phép một `inode` dữ liệu (một object) có thể sở hữu nhiều cái tên ở các thư mục hoàn toàn khác nhau thông qua cơ chế liên kết cứng (`hard link`). Có nghĩa là các file có tên khác nhau, nằm ở các thư mục khác nhau sẽ có cùng nội dung vì chúng trỏ đến cùng inode. Ví dụ:
`docs/baocao.txt` → số inode 2004,
`Desktop/thuctap.txt` → số inode 2004.

### 4.5 `inode number` không phải ID toàn hệ thống

Chỉ số `inode number` chỉ mang tính duy nhất (unique) trong giới hạn của một vùng mount filesystem cụ thể. Nếu bạn kiểm tra hai filesystem khác nhau (ext4 và tmpfs), việc tìm thấy hai tệp có chung một `inode number` là chuyện bình thường. Ví dụ: số inode 2211 ở ext4 chứa file ảnh, nhưng số inode 2211 ở tmpfs chứa file nhạc.

### 4.6 Quan hệ tổng thể: Hành trình tới dữ liệu

```text
[ Pathname (Chuỗi tên) ]
   |
   | Pathname resolution (Dò theo từng thư mục)
   v
[ Dentry (Đối tượng VFS mang Tên) ]
   |
   | Trỏ tới Index Node
   v
[ Inode (Object mang siêu dữ liệu) ]
   |
   +---> Metadata (Kích thước, Quyền truy cập...)
   |
   +---> Data mapping (Vị trí các khối Block dữ liệu)
```

> **Đọc sơ đồ:** Sơ đồ này liên kết 3 định nghĩa quan trọng nhất. Tiến trình đẩy vào một **Pathname**. Kernel dùng cơ chế dò tìm để chuyển chuỗi đó thành một đối tượng **Dentry**. Dentry lại làm nhiệm vụ như một nhãn tên dán lên một cái thùng chứa hàng là **Inode**. Bản thân Inode lưu thông số về thùng hàng (Metadata) và vị trí đặt các linh kiện trong thùng (Data mapping). Vì vậy, nếu bạn đổi tên tệp (đổi nhãn Dentry), toàn bộ Inode bên dưới vẫn giữ nguyên trạng thái không bị xê dịch.

---

## 5. Block, kích thước tệp và dung lượng thật

Kích thước logic mà bạn nhìn thấy và dung lượng vật lý thực sự mà tệp chiếm dụng trên đĩa không phải lúc nào cũng bằng nhau.

### 5.1 Kích thước logic (`logical size`)

Là số byte dữ liệu mà tệp biểu diễn ra cho các lệnh đọc/ghi API (như khi bạn chạy lệnh `ls -l` hoặc hàm `stat()`). Ví dụ tệp ghi là 1000 bytes.

### 5.2 Dung lượng được cấp phát (`allocated size`)

Filesystem thường quản lý không gian lưu trữ theo các đơn vị cấp phát như block. Vì vậy, **kích thước logic của tệp (`logical size`) và dung lượng lưu trữ thực sự được cấp phát (`allocated size`) không nhất thiết giống nhau**.

Ví dụ, với filesystem có block size 4096 byte, một tệp thông thường có `logical size` chỉ 1000 byte vẫn có thể cần một block dữ liệu được cấp phát.

Ở chiều ngược lại, một **tệp thưa (`sparse file`)** có thể có kích thước logic rất lớn nhưng chỉ chiếm một lượng nhỏ dung lượng lưu trữ thực tế.

#### `sparse file` và `hole`

Một `sparse file` có thể chứa những vùng trong không gian logic của tệp chưa được ánh xạ tới data block vật lý. Những vùng như vậy được gọi là **`hole`**.

Ví dụ:

```text
Không gian logic của file:

0                                                1 GiB
|--------------------------------------------------|
| DATA |        HOLE        | DATA |      HOLE     |
|------|--------------------|------|---------------|
   │                           │
   ▼                           ▼
data block                 data block
đã cấp phát                đã cấp phát
```

Các vùng `DATA` có data block thực sự được cấp phát trên storage.

Ngược lại, các vùng `HOLE` vẫn thuộc phạm vi logic của file nhưng **không có data block tương ứng được cấp phát**.

Có thể hình dung data mapping như sau:

```text
Logical blocks:

0      1      2      3      4      5
│      │      │      │      │      │
▼      ▼      ▼      ▼      ▼      ▼
100   101    HOLE   HOLE   500    HOLE
```

Trong đó `100`, `101`, `500` đại diện cho các block vật lý đã được cấp phát, còn `HOLE` biểu thị những vùng logic không có block vật lý tương ứng.

Khi ứng dụng đọc một vùng `hole`, Kernel/filesystem trả về các byte có giá trị `0`. Vì vậy, từ góc nhìn của ứng dụng, vùng đó hoạt động giống như một vùng dữ liệu chứa toàn số `0`, mặc dù filesystem không cần lưu các block toàn số `0` xuống storage.

```text
Application
    ↓
read()
    ↓
VFS
    ↓
Filesystem implementation
    ↓
Data mapping
    ↓
phát hiện vùng HOLE
    ↓
trả về các byte 0
```

Do đó, một `sparse file` có thể có:

```text
logical size:      1 GiB
allocated size:    chỉ một phần nhỏ của 1 GiB
```

Dung lượng thực tế phụ thuộc vào filesystem, kích thước block, metadata và số vùng dữ liệu thực sự đã được cấp phát.

Điểm cần ghi nhớ:

```text
HOLE
≠ các block toàn số 0 đã được lưu trên storage

HOLE
= vùng trong không gian logic của file chưa được ánh xạ
  tới data block vật lý; khi đọc sẽ nhận về các byte 0
```

Vì vậy:

```text
logical size ≠ allocated size
```

### 5.3 `st_size`, `st_blocks`, `st_blksize` (Các trường trong cấu trúc `stat`)

* **`st_size`**: Kích thước logic của file, tính bằng byte. Với `sparse file`, giá trị này **bao gồm cả các vùng `hole`**.
* **`st_blocks`**: Số đơn vị 512 byte đã thực sự được cấp phát cho file theo giao diện `stat`. Vì vậy, một `sparse file` có thể có `st_size` rất lớn nhưng `st_blocks` nhỏ.
* **`st_blksize`**: Kích thước block I/O được filesystem khuyến nghị cho các thao tác đọc/ghi hiệu quả; đây **không phải** là số block đã cấp phát cho file.

Ví dụ về mặt khái niệm:

```text
Sparse file:

st_size   = 1 GiB
st_blocks = nhỏ hơn rất nhiều so với kích thước logic

→ file có không gian logic 1 GiB
→ nhưng phần lớn không gian đó có thể là HOLE
→ storage không cần cấp phát 1 GiB data block
```

Có thể nối ba khái niệm như sau:

```text
logical size
    ↓
bao gồm toàn bộ phạm vi logic của file
    ↓
có thể chứa DATA + HOLE

allocated size
    ↓
chỉ phản ánh phần storage thực sự được cấp phát

stat()
    ↓
st_size   → kích thước logic
st_blocks → lượng block đã được cấp phát
```

---

## 6. Các loại tệp trong Linux

Thế giới "file" trong Linux rất đa dạng và được phân biệt ở cấp độ `inode`, hoàn toàn không phụ thuộc vào phần đuôi mở rộng (extension) như `.txt` hay `.exe`.

### 6.1 `regular file` (Tệp thông thường)

Là tệp chứa nội dung dữ liệu (văn bản, nhị phân, ảnh, database). 

### 6.2 `directory` (Thư mục)

Thư mục chính nó là một loại tệp đặc biệt. Nhiệm vụ của nó là ánh xạ (map) các cái tên (filename) thành số thứ tự của các đối tượng (inode number) bên trong không gian tên đó. Tại sao gọi là tệp đặc biệt? Vì bạn không thể dùng các phần mềm thông thường để mở và tự do gõ chữ vào tệp thư mục này. Chỉ có hệ điều hành (Kernel) mới có quyền ghi dữ liệu vào đây khi bạn tạo file mới, đổi tên hoặc xóa file. Ví dụ:
nội dung của thư mục phase-01:
README-topic-01.md → số inode 1000,
README-topic-02.md → số inode 2026

### 6.3 `symbolic link` (Liên kết mềm)

Là tệp chỉ chứa một đoạn chuỗi văn bản làm "biển báo" trỏ đường (pathname mục tiêu).
Mục tiêu trỏ tới có thể là một tệp tồn tại, hoặc một tệp chưa hề tồn tại (dangling link).

### 6.4 `character device` (Thiết bị ký tự)

Một `device node` giao tiếp với phần cứng hoạt động theo luồng chuỗi byte tuần tự (stream), không có địa chỉ đĩa ngẫu nhiên (ví dụ cổng UART `ttyS0`).

### 6.5 `block device` (Thiết bị khối)

Một `device node` giao tiếp với phần cứng cho phép truy cập ngẫu nhiên dữ liệu theo từng khối (ví dụ ổ đĩa `sda`, thẻ nhớ `mmcblk0`).

### 6.6 `major` và `minor`

Mỗi `device node` mang một cặp ID:
*   `major number`: Định danh loại trình điều khiển (Driver) chịu trách nhiệm. Ví dụ, tất cả các ổ đĩa cứng chuẩn SCSI/SATA đều có số Major là 8. Cứ nhìn thấy số 8 là hệ thống tự động giao cho Driver ổ cứng xử lý, thay vì gửi nhầm sang Driver của bàn phím hay chuột. Cứ cùng một loại phần cứng (dùng chung một Driver) thì sẽ có chung số Major.
*   `minor number`: Phân biệt các thiết bị/phân vùng vật lý khác nhau cùng dùng chung Driver đó. Ví dụ: ổ cứng thứ nhất (sda) là số 0, ổ cứng thứ hai (sdb) là số 16, phân vùng đầu tiên của ổ cứng thứ nhất (sda1) là số 1. 
*Lưu ý: Sự tồn tại của một file `device node` trong `/dev` không chứng minh phần cứng vật lý đó đang được cắm vào máy.*

### 6.7 FIFO (Named Pipe)

Là một đường ống (Pipe) được đặt tên hiển thị thẳng trong filesystem. Pathname của FIFO đóng vai trò như một "địa điểm gặp gỡ" để hai tiến trình không quen biết nhau có thể tìm thấy và truyền dữ liệu cho nhau. Khác với dấu gạch đứng `|` (đường ống vô danh) chỉ dùng giữa các lệnh cha-con đi liền nhau, FIFO cho phép hai tiến trình hoàn toàn độc lập kết nối qua một file đại diện trên ổ cứng. Dữ liệu truyền qua FIFO chạy trực tiếp trên bộ nhớ RAM theo cơ chế một chiều (First In, First Out) và không làm tăng dung lượng file thật. Khi một tiến trình ghi dữ liệu vào FIFO, nó sẽ bị chặn (block) và dừng lại cho đến khi có một tiến trình khác mở đầu kia ra để đọc.

### 6.8 Unix-domain socket

Tương tự FIFO, nó dùng pathname làm một địa chỉ liên lạc (endpoint) cục bộ cho các tiến trình trên cùng một máy, cung cấp tính năng gửi dữ liệu hai chiều và truyền các file descriptor.

---

## 7. Metadata và `stat`

Siêu dữ liệu (Metadata) là lý lịch trích ngang của tệp. Hàm `stat()` là cách tiến trình xem bảng lý lịch này.

### 7.1 Lệnh gọi `stat`, `lstat`, `fstat`

Ba System Call truy vấn siêu dữ liệu:
*   `stat(path)`: Tra cứu theo đường dẫn. Nếu đụng `symbolic link`, nó sẽ đi qua link đó và trả về siêu dữ liệu của tệp đích cuối cùng.
*   `lstat(path)`: Tương tự, nhưng nếu đụng `symbolic link`, nó sẽ trả về siêu dữ liệu của **chính cái link đó**, không đi tiếp.
*   `fstat(fd)`: Khỏi cần phân giải đường dẫn, tra thẳng siêu dữ liệu bằng cái "cuống vé" (file descriptor) đang mở.

### 7.2 Các mốc thời gian: `mtime`, `ctime`, `atime`

*   `mtime` (Modify time): Thời điểm **nội dung** dữ liệu bị sửa đổi.
*   `ctime` (Change time): Thời điểm **trạng thái Inode (metadata)** như phân quyền, chủ sở hữu, hoặc tên liên kết bị thay đổi. *Rất nhiều người nhầm ctime là creation time (ngày tạo), đây là một hiểu lầm tai hại trong Linux.*
*   `atime` (Access time): Thời điểm có ứng dụng đọc/truy cập file.

### 7.3 Siêu dữ liệu có tính biến động

Hệ thống tệp là môi trường đa nhiệm. Giữa khoảnh khoắc chương trình của bạn lấy siêu dữ liệu từ `stat()` và thời điểm bạn thực sự mở file, một tiến trình khác hoàn toàn có thể đã thay đổi chủ sở hữu hoặc xóa file đó (Race condition – TOCTOU). Lỗi TOCTOU nhắc nhở các lập trình viên rằng: Trong Linux, những gì bạn vừa kiểm tra cách đây 1 mili giây chưa chắc bây giờ đã đúng! Để giải quyết tận gốc vấn đề này, các lập trình viên Linux hiện đại không bao giờ dùng cặp lệnh stat() rồi mới open(). Thay vào đó, họ sẽ gộp hai bước làm một: Cứ đánh bạo open() file ra trước để lấy chiếc chìa khóa (File Descriptor), sau đó mới kiểm tra tệp dựa trên chính chiếc chìa khóa đó (dùng hàm fstat). Như vậy sẽ không ai có thể nhảy vào giữa để tráo file được nữa.

---

## 8. Chủ sở hữu, nhóm và quyền `r/w/x`

Cơ chế phân quyền cơ bản chia tài nguyên cho ba nhóm chủ thể: `User`, `Group`, và `Others`. Ý nghĩa của ba bit đọc, ghi, thực thi có sự khác biệt tinh tế giữa tệp dữ liệu và thư mục.

### 8.1 UID và GID

Ở tầng Kernel, hệ thống chỉ hiểu chủ sở hữu thông qua các con số nguyên: UID (User ID) và GID (Group ID). Các chuỗi tên như `root` hay `ngocchien` chỉ là bản đồ ánh xạ ở tầng Userspace thông qua `/etc/passwd`.

### 8.2 Ba lớp phân quyền cơ bản

*   **u (User/Owner):** Quyền của người chủ sở hữu file.
*   **g (Group):** Quyền của những thành viên thuộc nhóm sở hữu.
*   **o (Others):** Quyền của toàn bộ những người dùng khác trong hệ thống.
*   Quyền truy cập bao gồm: `r` (Read), `w` (Write), `x` (eXecute).

### 8.3 Ngữ nghĩa trên Tệp thông thường (Regular File)

*   `r`: Quyền đọc dữ liệu nội dung.
*   `w`: Quyền chỉnh sửa, ghi đè, hoặc cắt bớt (truncate) nội dung tệp. *(Lưu ý: Quyền `w` trên tệp KHÔNG cho phép bạn xóa tệp đó bằng lệnh `rm`. Việc xóa tệp thực chất là tác động vào thư mục chứa nó).*
*   `x`: Xin cấp phép thực thi tệp đó như một chương trình. *(Lưu ý: Kernel kiểm tra `x` chỉ là điều kiện cần; tệp có định dạng executable chuẩn ELF/script hay không, thư viện loader có đủ không mới quyết định tệp có chạy được không).*

### 8.4 Ngữ nghĩa trên Thư mục (Directory)

Đây là khác biệt cốt lõi:
*   `r`: Có quyền lấy danh sách tên các tệp nằm trực tiếp bên trong thư mục (chạy lệnh `ls`).
*   `w`: Được quyền tạo mới, xóa bỏ (đây mới là nơi quyết định bạn có thể `rm` tệp con hay không), và đổi tên các tệp bên trong thư mục đó.
*   **`x` (Quan trọng nhất):** Có quyền băng qua (Search/Traverse) thư mục. Nếu mất bit `x`, quá trình phân giải `pathname resolution` bị Kernel chặn lập tức, bạn hoàn toàn mất quyền truy cập vào mọi file nằm sâu bên trong, bất chấp việc bạn có đủ quyền trên các file con đó.

---

## 9. `chmod`, `chown` và `umask`

Ba công cụ để can thiệp vào các tham số bảo mật của hệ thống.

### 9.1 `chmod` (Change Mode)

Thay đổi các bit phân quyền (Permission bits).
Có thể biểu diễn bằng toán tử ký hiệu (vd `chmod u+x,g-w file`) hoặc dùng hệ đếm bát phân (Octal mode) truyền thống (vd `chmod 755 file`, trong đó 7 là `rwx` cho Owner, 5 là `r-x` cho Group/Others).

### 9.2 `chown` (Change Owner)

Chuyển giao quyền chủ sở hữu hoặc nhóm UID/GID (vd `chown root:admin config.txt`). Đây là tác vụ chỉnh sửa Metadata trong `inode`.

### 9.3 `umask` (User File-creation Mask)

`umask` hoạt động như một "tấm khiên" tước bỏ bớt quyền hạn mặc định khi một tệp MỚI được ứng dụng tạo ra. 

```text
[ Quyền ứng dụng yêu cầu (vd: 0666 cho file) ]
                  |
        (Phép logic AND NOT)  <--- [ Umask hệ thống (vd: 022) ]
                  v
[ Quyền thực tế được cấp ban đầu (vd: 0644) ]
```

> **Ghi nhớ:** `umask` là mặt nạ loại trừ, nó KHÔNG bao giờ tự cộng thêm quyền cho tệp. Thông thường, ứng dụng sẽ yêu cầu quyền cơ sở là `0666` (`rw-rw-rw-`) khi tạo file dữ liệu và `0777` (`rwxrwxrwx`) khi tạo thư mục. Nếu umask là `022`, nó sẽ che bớt quyền write của Group và Others, tạo ra file `0644` (`rw-r--r--`). Việc file text mới tạo ra không có bit `x` (execute) đơn giản là vì ứng dụng không yêu cầu bit đó, chứ không phải do Kernel cấm.

---

## 10. `mount`: ghép nhiều filesystem vào một cây

Lệnh `mount` đóng vai trò như việc ghép những mảnh ghép của các bộ lego (filesystem) độc lập vào một mô hình kiến trúc duy nhất (Cây namespace Linux).

### 10.1 Khái niệm Mount Point (Điểm gắn kết)

```text
(Trước khi Mount)
/mnt/sdcard/
   ├── readme.txt   (Thuộc filesystem hiện tại)
```

Giả sử bạn có thư mục `/mnt/sdcard`. Trước khi cắm thẻ nhớ, mọi tên tệp bạn tạo ra ở đây vẫn được ghi lên filesystem hiện tại (ổ cứng chính). `/mnt/sdcard` lúc này chỉ là một thư mục (Directory) bình thường.

### 10.2 Quá trình che phủ (Over-mounting)

```text
(Thực hiện lệnh mount: mount /dev/mmcblk0p1 /mnt/sdcard)

[ Gốc của Filesystem thẻ nhớ exFAT ]
                  |
                  v (Đè lên)
           /mnt/sdcard/
```

Sau khi bạn thực hiện lệnh mount thẻ nhớ vào thư mục /mnt/sdcard, một cơ chế định tuyến thông minh sẽ được kích hoạt bên trong lớp VFS (Virtual File System) của nhân Linux. Kể từ khoảnh khắc này, mỗi khi hệ thống tiến hành phân giải đường dẫn (pathname resolution) và chạm đến nhánh thư mục /mnt/sdcard, VFS sẽ nhận diện được điểm gắn kết (mount point) này và lập tức "bẻ lái" luồng truy cập sang cấu trúc gốc của hệ thống tệp mới (ở đây là thẻ nhớ định dạng exFAT).
Điều này dẫn đến một hiện tượng thú vị: toàn bộ nội dung cũ vốn có bên trong thư mục (ví dụ như tệp readme.txt) không hề bị lệnh mount xóa bỏ hay làm tổn hại; chúng vẫn nằm im và an toàn trên phân vùng ổ cứng chính. Tuy nhiên, do mảnh ghép hệ thống tệp exFAT mới đã được đặt đè lên trên, không gian dữ liệu của thẻ nhớ sẽ hoàn toàn che lấp (shadowed) nội dung cũ, khiến người dùng và các ứng dụng tạm thời không thể nhìn thấy hay tương tác với tệp readme.txt được nữa. Trạng thái che phủ này sẽ được duy trì liên tục cho đến khi bạn thực hiện thao tác tháo gỡ an toàn (unmount) thẻ nhớ ra khỏi hệ thống, lúc đó "tấm màn che" bị nhấc bỏ và các tệp tin cũ ngầm bên dưới lại lập tức hiện ra nguyên vẹn.
Chính vì mối quan hệ gắn kết chặt chẽ này, thư mục /mnt/sdcard lúc này đóng vai trò giống như một "cửa sổ điều khiển" trực tiếp của thiết bị vật lý /dev/mmcblk0p1. Mọi hành động thêm, sửa hoặc xóa file tại thư mục này đều được VFS bẻ hướng và ra lệnh cho trình điều khiển hệ thống tệp ghi trực tiếp dữ liệu xuống các khối nhớ vật lý của thẻ nhớ . Do đó, nếu bạn thêm một tệp tin mới vào /mnt/sdcard, tệp tin đó đồng thời sẽ được lưu giữ thực tế trên /dev/mmcblk0p1. Ngược lại, khi bạn rút chiếc thẻ nhớ này ra và cắm sang một thiết bị khác, tất cả dữ liệu bạn đã thao tác qua thư mục mount trước đó đều sẽ xuất hiện nguyên vẹn trong thẻ nhớ. Bạn không thể thêm file trực tiếp vào tệp thiết bị /dev/mmcblk0p1 mà không qua bước mount, bởi vì bản thân file thiết bị khối đó chỉ là phần cứng thô (Raw Data) gồm các ô nhớ byte khô khan, hoàn toàn không có khái niệm về quản lý tên tệp hay thư mục. Bước mount là bắt buộc để hệ thống tệp (Filesystem) đứng ra làm biên dịch viên, tạo dựng bảng mục lục và siêu dữ liệu (metadata) nhằm biến các khối nhớ thô kệch thành các tệp tin ngăn nắp cho con người sử dụng.


### 10.3 Thiết bị khối, phân vùng, thực thể filesystem và điểm gắn kết

Các khái niệm này thường bị gọi chung là “ổ đĩa”, nhưng chúng nằm ở các lớp khác nhau. Với một filesystem lưu trên thiết bị khối, mô hình thường gặp là:

```text
[ Thiết bị khối - Block Device ]
Ví dụ: /dev/nvme0n1
                |
                v
[ Phân vùng - Partition ]
Ví dụ: /dev/nvme0n1p1
                |
                v
[ Thực thể filesystem ]
Ví dụ: một filesystem được tạo theo định dạng ext4
                |
                v
[ Mount Point - Điểm gắn kết ]
Ví dụ: /home
                |
                v
[ Pathname trong namespace ]
Ví dụ: /home/user/a.txt
```

> **Đọc sơ đồ:** `/dev/nvme0n1` là block device mà Kernel cung cấp cho thiết bị lưu trữ. Một partition như `/dev/nvme0n1p1` là một vùng logic bên trong block device; partition không phải điều kiện bắt buộc vì filesystem cũng có thể được tạo trực tiếp trên toàn bộ block device trong một số trường hợp. Lệnh kiểu `mkfs.ext4` tạo một **thực thể filesystem theo định dạng `ext4`** trên vùng lưu trữ đã chọn. `mount` không “biến partition thành ext4”; nó gắn thực thể filesystem đã tồn tại vào một `mount point` trong namespace để userspace truy cập qua pathname.

Mục 1.3 đã phân biệt **định dạng filesystem**, **filesystem type**, **phần hiện thực filesystem trong Kernel** và **thực thể filesystem**. Mục này chỉ tập trung vào bước ghép thực thể đó vào namespace bằng `mount`.

---

## 11. `/dev`, `/proc`, `/sys`: những hệ thống tệp đặc biệt

Không phải filesystem nào cũng lưu xuống chip nhớ vật lý. Linux tận dụng VFS để biến dữ liệu cấu trúc nội bộ của Kernel thành các thư mục ảo, giúp userspace thao tác quản trị bằng những lệnh `cat`, `echo` cực kỳ quen thuộc.

### 11.1 `/dev` (devtmpfs)

Lưu trữ các `device node` đại diện cho phần cứng (loa, chuột, cổng serial). Khi phần cứng cắm vào, Kernel thông qua `devtmpfs` tạo một entry tại đây. 

### 11.2 `/proc` (procfs)

`procfs` không cần một filesystem on-disk được tạo trước bằng `mkfs`. Khi có yêu cầu mount, Kernel thiết lập thực thể `procfs` tại runtime để biểu diễn trạng thái và dữ liệu nội bộ của Kernel trong namespace.

Hệ thống tệp ảo trên RAM, là cửa sổ phơi bày trạng thái động của hệ điều hành.
*   Chứa thông tin tiến trình (`/proc/[PID]/`).
*   Thông số tài nguyên (`/proc/meminfo`, `/proc/cpuinfo`).
*   Cấu hình runtime của Kernel (`/proc/sys/`).
*   Nội dung trong `procfs` thường là số không tròn trĩnh (size 0) và được Kernel sinh/tổng hợp động theo thời gian thực (real-time) ngay khi có ứng dụng gọi hàm `read()`.

### 11.3 `/sys` (sysfs)

Tương tự `procfs`, `sysfs` không cần được tạo trước bằng `mkfs`; Kernel thiết lập thực thể `sysfs` khi filesystem type này được mount.

`sysfs` là mô hình cây ảo phân cấp rõ ràng mô tả cách các thiết bị (devices), trình điều khiển (drivers), bus, và firmware kết nối với nhau.
Với dân lập trình Embedded Linux, `/sys` là tài nguyên số 1 để quan sát cấu trúc vật lý và các thuộc tính phần cứng ngoại vi.

### 11.4 Bản chất giao diện ảo

```text
[ Lệnh: cat /proc/cpuinfo ] 
          |
[ VFS gọi driver procfs ] 
          |
[ Kernel truy vấn cấu trúc dữ liệu CPU ] 
          |
[ Kernel chuyển số liệu CPU thành dạng Text và trả lại User ]
```

> **Đọc sơ đồ:** Dù bạn dùng công cụ đọc file truyền thống (`cat`), nhưng bản chất dòng văn bản in ra màn hình từ `/proc` không hề tồn tại dưới dạng một file `.txt` trên ổ cứng. Đây là cơ chế Kernel dùng interface hệ thống tệp (VFS API) để giao tiếp, mô phỏng (fake) các cấu trúc RAM thành dạng file đọc được cho con người.

---

## 12. `ls`, `stat`, `file`, `df`, `du` quan sát lớp nào?

Mỗi công cụ đo đạc nhìn vào một tầng thông tin khác biệt của kiến trúc lưu trữ:

*   **`ls`:** Quan sát tại tầng thư mục (Directory Entry). Chỉ thấy danh sách tên và một phần nhỏ siêu dữ liệu hiển thị tóm tắt.
*   **`stat`:** Chọc thẳng vào tầng Inode/Metadata. Hiển thị thông số chi tiết mtime, size, inode number.
*   **`file`:** Bỏ qua metadata, mở tệp ra, đọc hàng byte (magic number) bên trong ruột tệp để "đoán" định dạng (đây là script Python, file ELF, hay ảnh PNG).
*   **`df` (Disk Free):** Quan sát tổng thể cấp độ Filesystem (Superblock). Nó đọc số liệu quản lý vĩ mô để báo cáo không gian đã cấp phát và còn trống.
*   **`du` (Disk Usage):** Chạy lệnh đệ quy dò hỏi từng `pathname` một, cộng dồn số lượng khối bộ nhớ (`allocated disk blocks`) tiêu tốn của từng tệp con. Do hoạt động từ hai tầng khác nhau, con số dung lượng tổng của `du` và dung lượng toàn cục của `df` có thể lệch nhau là việc bình thường.

---

## 13. Vòng đời tên tệp, liên kết và tệp đang mở

Khái niệm hệ thống của Linux: **"Tên tệp và Dữ liệu là hai thực thể tách rời"**.

### 13.1 `hard link` (Liên kết cứng)

Một `inode` (dữ liệu vật lý) có thể gánh nhiều cái nhãn tên (pathname/dentry) hoàn toàn bằng vai phải lứa.
Biến số `Link count` trong inode sẽ đếm số lượng "tên" đang trỏ tới dữ liệu đó.

### 13.2 Lệnh xóa `unlink()`

Khi bạn chạy lệnh `rm`, hệ thống thực hiện API `unlink()`. Lệnh này chỉ đơn giản là lột bỏ nhãn dán (xóa directory entry), giảm biến số `Link count` đi 1 đơn vị. 
*Nếu Link count vẫn > 0 (còn một liên kết cứng khác), dữ liệu vật lý vẫn bình yên vô sự.*

### 13.3 Tệp bị xóa nhưng tiến trình vẫn đang mở

Điều gì xảy ra nếu Link count giảm về 0, nhưng tiến trình (ví dụ ứng dụng log server) vẫn đang nắm File Descriptor mở tệp đó?

```text
[ Tiến trình ] ---> (File Descriptor) ---> [ open file description ] 
                                                   |
                                            [ Inode Dữ liệu ] 
                                                   ^
[ Lệnh rm xóa Pathname ] -X-> [ Dentry (Đã bị loại bỏ) ]
```

> **Đọc sơ đồ:** Dù tên tệp (Dentry) đã bị loại bỏ khỏi không gian tên (namespace), nhưng do Tiến trình vẫn nắm giữ tham chiếu (open file description) trỏ thẳng vào Inode dữ liệu, hệ thống tệp sẽ KHÔNG thu hồi các block dung lượng. Tiến trình vẫn ung dung đọc/ghi vào tệp-bị-xóa-nhưng-còn-mở (unlinked-but-open file) này. Chỉ khi tiến trình đóng file (`close()`) hoặc sập (Crash), Kernel phá hủy nốt đường link tham chiếu cuối cùng, lúc đó dung lượng ổ cứng mới thực sự được giải phóng. (Đây là hiện tượng dung lượng báo ảo thường gặp giữa kết quả của `df` và `du`).

---

## 14. Tư duy gỡ lỗi hệ thống tệp

Khi VFS trả về lỗi, đừng thử sai mù quáng. Hãy tư duy theo luồng phân giải (resolution) của Kernel:

### 14.1 Lỗi “No such file” (`ENOENT`)

Lỗi này không ám chỉ 100% là tệp cuối cùng biến mất. Hãy dò theo chuỗi:
1.  **CWD đúng không?** Bạn đang đứng sai thư mục nên đường dẫn tương đối không hợp lệ.
2.  **Đứt gãy giữa chừng:** Một thư mục cha ở giữa đường dẫn (vd `/a/b/c`) bị thiếu.
3.  **Symbolic link rỗng:** Link trung gian trỏ ra khoảng không.
4.  **Mount point:** Filesystem chứa nhánh đó bị rớt kết nối.

### 14.2 Lỗi “Permission denied” (`EACCES`)

Liên quan trực tiếp đến phân quyền truy cập:
1.  **Mất quyền Traverse (`x`):** Đây là lỗi phổ biến nhất. Bạn thiếu quyền `x` ở một thư mục nằm giữa đường đi nên Kernel chặn ngay quá trình phân giải `pathname resolution`.
2.  **Mất quyền `r/w/x` trên chính tệp đích:** Kiểm tra chủ sở hữu (Ownership) và chế độ phân quyền.
3.  **Tùy chọn cấm thực thi:** Filesystem được mount với cờ `noexec` (Cấm chạy bất kỳ chương trình/script nào trên phân vùng này, dù file có bit `x`).

### 14.3 Ghi lỗi do hệ thống tệp bị khóa (`EROFS`)

Nếu bạn cố ghi (`w`) vào một file nằm trên phân vùng được mount ở chế độ Read-Only, lỗi trả về thường là `Read-only file system` (`EROFS`) thay vì `EACCES`.

### 14.4 `device node` tồn tại nhưng phần cứng tịt ngòi

Cái node `/dev/ttyS0` chỉ là một file cấp VFS mang hai số `major/minor`. Phải đi qua các lớp:
*   Driver trong Kernel đã thực sự bind với hai số `major/minor` này chưa?
*   Device Tree (DTS) khai báo đúng địa chỉ thanh ghi phần cứng chưa?
*   Phần cứng đã được cấp xung nhịp (Clock), nguồn, thiết lập chân tín hiệu (Pinctrl) chưa?

---

## 15. Liên hệ với Embedded Linux

Hiểu hệ thống tệp là nền móng để phát triển và bring-up trong môi trường Embedded Linux (Linux nhúng), nơi lưu trữ và bộ nhớ bị nén khắt khe.

### 15.1 Rootfs siêu nhỏ

Khác với máy chủ, Rootfs cho bo mạch (vd Buildroot/Yocto) được build tối giản, gộp chung hàng loạt công cụ như `ls`, `mount`, `cat` vào một file thực thi duy nhất là `BusyBox`. Dù giao diện thu nhỏ, các quy luật về `inode`, `vfs`, `mount` tuyệt đối không đổi.

### 15.2 Kiến trúc lưu trữ và các loại Chip nhớ

Kiến trúc Embedded Linux thường phân hóa loại Filesystem dựa theo phần cứng lưu trữ:
*   **eMMC / Thẻ SD:** Hoạt động như một *Block Device* thông thường. Thường được định dạng bằng `ext4` hoặc `F2FS` (Flash-Friendly File System). Để chống hiện tượng hao mòn (Wear/Tear) và mất dữ liệu khi ngắt nguồn, Rootfs (`/bin`, `/usr`) thường được đóng gói nén lại và mount thành **Read-only** (`SquashFS`). 
*   **Raw NAND / NOR Flash:** Yêu cầu các hệ thống tệp quản lý bad-block và wear-leveling phức tạp hơn, thường dùng `UBIFS` hoặc `JFFS2` (chuẩn cũ).
*   Các vùng dữ liệu thay đổi cực kỳ nhanh (như logs trong `/var/log`) sẽ được ném lên RAM thông qua `tmpfs`.

### 15.3 Debugger vạn năng qua File Interface

Khi bring-up một bo mạch mới, các thao tác chẩn đoán của kỹ sư Nhúng thường đi qua giao diện file:
*   **Kernel Log:** Chạy lệnh `dmesg` để đọc bộ đệm thông báo của Kernel, qua đó biết driver nào vừa được load thành công, thiết bị nào boot lỗi.
*   **GPIO Interface:** Trên Kernel hiện đại, GPIO được điều khiển qua `character device` tại `/dev/gpiochipN` (tương tác bằng các công cụ `libgpiod`). Ngoài ra, giao diện cũ (legacy) `sysfs` tại `/sys/class/gpio` vẫn thường gặp trên các hệ thống đời trước để chọc thẳng tín hiệu HIGH/LOW cho linh kiện.
*   **LED:** Viết lệnh `echo 1 > /sys/class/leds/blue/brightness` để bật đèn LED trên mạch trực tiếp thông qua Sysfs.

Đây chính là lúc triết lý "mọi thứ là tệp" phát huy sức mạnh to lớn nhất.

---

## 16. Tổng kết

Hãy lưu giữ chuỗi tư duy kết nối xuyên suốt chương này:

```text
[ Pathname ] 
   |
[ VFS Pathname Resolution ] (Rà soát từng nấc thư mục)
   |
[ Dentry ]                  (Bộ đệm ánh xạ Tên -> Inode trên dcache)
   |
[ Inode ]                   (Quản lý Metadata)
   |
[ Khối lưu trữ / Object ]   (Dữ liệu thô trên thiết bị vật lý / Kernel Interface)
```

> **Đọc sơ đồ:** Sơ đồ này tóm lược sự chia tách tuyệt vời giữa **Định dạng hiển thị (Tên/Pathname)** và **Thực thể dữ liệu vật lý (Object/Inode)**. Process cung cấp Pathname. VFS rà soát từng thành phần đường dẫn trong Namespace, lấy Dentry để làm nhãn dán, tìm ra được Inode quản lý lý lịch siêu dữ liệu. Nhờ cơ chế trừu tượng này, thao tác mount/unmount quyết định ta sẽ nhìn thấy filesystem nào ở nhánh Pathname, thao tác rename/unlink xử lý vòng đời của Pathname, nhưng một tiến trình đang mở tệp vẫn giữ Inode sống yên ổn dưới tầng lưu trữ bất chấp Namespace phía trên có biến động.

Các nguyên tắc không được quên:
1. Hệ thống quy về một cây Namespace gốc `/` duy nhất (dù nó được ráp nối bởi hàng tá filesystem qua `mount`).
2. Đường dẫn (`pathname resolution`) được dò tuần tự, do đó quyền `x` của các thư mục cha là then chốt.
3. Pathname KHÔNG được lưu ở lớp `inode`. Một `inode` dữ liệu có thể mang nhiều cái tên (hard link).
4. `symbolic link` chứa "bản đồ chỉ đường" chữ, không chứa dữ liệu.
5. Quyền hạn `umask` là phép loại trừ, không phải thêm quyền. Ứng dụng chủ động quyết định việc có yêu cầu quyền `x` hay không.
6. Mount che lấp không gian tên tại điểm nối, không copy dữ liệu.
7. Đọc `/dev`, `/proc`, `/sys` là chọc vào mạch đập của phần cứng và Kernel thông qua giao diện File API quen thuộc.

---

## 17. Tài liệu tham khảo

Phần này liệt kê nguồn chuẩn để tra cứu chi tiết về filesystem, quyền truy cập và mount.

- Filesystem Hierarchy Standard: https://refspecs.linuxfoundation.org/FHS_3.0/fhs/index.html
- Linux VFS documentation: https://docs.kernel.org/filesystems/vfs.html
- Linux ext4 on-disk format documentation: https://docs.kernel.org/filesystems/ext4/about.html
- Linux ext4 high-level design: https://docs.kernel.org/filesystems/ext4/overview.html
- Linux VFAT documentation: https://docs.kernel.org/filesystems/vfat.html
- Linux tmpfs documentation: https://docs.kernel.org/filesystems/tmpfs.html
- Linux pathname lookup documentation: https://docs.kernel.org/filesystems/path-lookup.html
- `path_resolution(7)`: https://man7.org/linux/man-pages/man7/path_resolution.7.html
- `inode(7)`: https://man7.org/linux/man-pages/man7/inode.7.html
- `stat(2)`: https://man7.org/linux/man-pages/man2/stat.2.html
- `chmod(2)`: https://man7.org/linux/man-pages/man2/chmod.2.html
- `chown(2)`: https://man7.org/linux/man-pages/man2/chown.2.html
- `umask(2)`: https://man7.org/linux/man-pages/man2/umask.2.html
- `mount(8)`: https://man7.org/linux/man-pages/man8/mount.8.html
- Linux procfs documentation: https://docs.kernel.org/filesystems/proc.html
- Linux sysfs documentation: https://docs.kernel.org/filesystems/sysfs.html
- Bootlin Embedded Linux training: https://bootlin.com/training/embedded-linux/

> **Điều hướng:** [← Chủ đề 1 — Dòng lệnh Linux cơ bản](README-topic-01.md) · [Chủ đề 3 — Vào/ra tệp →](README-topic-03.md)
