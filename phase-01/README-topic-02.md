# Chủ đề 2 — Hệ thống tệp Linux (Filesystem)

> **Mục tiêu:** Hiểu rõ cách Linux tổ chức, phân giải và quản lý tài nguyên thông qua hệ thống tệp: từ cây thư mục `/`, đường dẫn, quá trình `pathname resolution`, `inode`, `dentry`, quyền truy cập, cơ chế `mount` cho tới các hệ thống tệp giao diện như `/dev`, `/proc`, `/sys`.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các tên/thuật ngữ kỹ thuật cốt lõi chuẩn theo tài liệu Linux/POSIX như `filesystem`, `VFS`, `pathname`, `pathname resolution`, `dentry`, `inode`, `symbolic link`, `hard link`, `mount point`, `device node`, `procfs`, `sysfs`, `devtmpfs`, `open file description` được giữ nguyên bằng tiếng Anh để đảm bảo tính toàn vẹn ngữ nghĩa và dễ dàng tra cứu.
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

Hệ thống tệp (Filesystem) là phương pháp và cấu trúc dữ liệu mà Linux sử dụng để kiểm soát cách thông tin được lưu trữ, đặt tên, tổ chức thành cấu trúc cây và truy xuất.

### 1.1 Hai lớp dễ bị trộn lẫn

Để gỡ rối, hãy tách bạch hai khái niệm:
1. **Namespace (Không gian tên):** Tệp có đường dẫn (pathname) là gì trong cây thư mục? Ví dụ: `/home/user/a.txt`. Đây là cách con người và chương trình (userspace) gọi tên tệp.
2. **Backing Storage/Implementation:** Dữ liệu và siêu dữ liệu thực tế của tệp đó được lưu giữ bằng cấu trúc nào trên thiết bị? Nó có thể nằm trên ổ cứng định dạng `ext4`, `F2FS`, hay thậm chí nằm trên RAM dưới dạng `tmpfs`.

### 1.2 Linux cho nhiều filesystem cùng xuất hiện trong một cây

Khác với Windows thường chia thành ổ C:, D: rời rạc, Linux cung cấp một ảo giác về một cây thư mục duy nhất. Trong đó:

```text
/             -> ext4 (Ổ cứng chính)
/proc         -> procfs (Giao diện cấu trúc dữ liệu của Kernel)
/dev          -> devtmpfs (Quản lý các device node)
/mnt/sdcard   -> exFAT (Thẻ nhớ cắm ngoài)
```

Người dùng (và chương trình) chỉ việc đi theo nhánh thư mục, Linux Kernel sẽ tự biết khi nào bạn "bước" qua ranh giới từ hệ thống tệp này sang hệ thống tệp khác thông qua cơ chế `mount`.

### 1.3 Không nên hiểu quá máy móc câu “everything is a file”

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

Đây là quy trình Kernel diễn giải một pathname thành một đối tượng hệ thống thực sự.

```text
[ Process (Tiến trình) ]
      |
      | Yêu cầu: pathname "/a/b/c"
      v
[ VFS (Virtual File System) ]
      |
      | 1. Bắt đầu từ gốc "/" (hoặc CWD).
      | 2. Hỏi dcache (Dentry cache): Tìm thư mục "a".
      +---> [ dcache ] ---> Trả về dentry "a"
      |
      | 3. Từ "a", tìm thư mục "b".
      +---> [ dcache ] ---> Trả về dentry "b"
      |
      | 4. Từ "b", tìm tên "c".
      +---> [ dcache ] ---> Cache Miss (Chưa có trong RAM!)
      |
      | 5. Vì Cache Miss, gọi driver của Filesystem bên dưới.
      v
[ Filesystem Driver (vd: ext4) ]
      |
      +---> [ Lưu trữ vật lý ] ---> Đọc đĩa, tìm kiếm tên "c" trong thư mục "b".
      |
      | 6. Filesystem trả về Inode của "c". VFS tạo Dentry mới lưu vào dcache trên RAM.
      v
[ Trả đối tượng (Object) về cho Process ]
```

> **Đọc sơ đồ:** Tiến trình không cung cấp một "tọa độ" vật lý cho Kernel, nó chỉ đưa một chuỗi pathname. VFS phải xẻ chuỗi `/a/b/c` ra và tra cứu từng nấc. Để tăng tốc, VFS dùng một bộ nhớ đệm là `dcache` chứa các đối tượng `dentry`. Nếu Kernel tìm thấy đường đi trong bộ đệm (Cache Hit), tốc độ sẽ cực nhanh. Nếu một nấc bị thiếu (Cache Miss), VFS buộc phải gọi xuống filesystem driver (ví dụ ext4) để đọc thư mục trên ổ cứng. Do cơ chế dò từng nấc này, một pathname dài có thể gặp lỗi ở **bất kỳ một thư mục trung gian nào**, chứ không nhất thiết là lỗi do bản thân tệp đích `c` gây ra.

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

`VFS` là một tầng trừu tượng (abstraction layer) nằm bên trong Kernel. Nó đóng vai trò "người môi giới" để ứng dụng không cần quan tâm dữ liệu đang nằm trên định dạng hệ thống tệp nào.

```text
[ Ứng dụng (Userspace) ]
   |
   | Gọi các API tiêu chuẩn: open(), read(), write(), stat()
   v
[ System Call Interface ]
   |
   v
[ VFS (Virtual File System) ] (Tầng trừu tượng chung)
   |
   +----> [ ext4 driver ]    ----> Ổ cứng HDD/SSD
   +----> [ tmpfs driver ]   ----> RAM
   +----> [ procfs driver ]  ----> Cấu trúc dữ liệu nội bộ Kernel
   +----> [ ... ]
```

> **Đọc sơ đồ:** Ứng dụng ở tầng Userspace chỉ biết gọi các hàm System Call chuẩn. VFS nhận yêu cầu này, phân tích xem file đó thuộc loại filesystem nào, chuẩn hóa các thông số và gọi (dispatch) xuống driver cụ thể tương ứng (ext4, tmpfs...). Nhờ VFS, một lệnh `cp` copy tệp từ ổ cứng `ext4` sang thư mục `/tmp` chạy trên `tmpfs` vẫn diễn ra hoàn hảo mà người lập trình lệnh `cp` không cần viết riêng code xử lý cho từng loại định dạng. Tại sao dcache lại giúp tăng tốc? Hãy tưởng tượng mỗi lần muốn tìm phòng của "Anh Hải", bạn lại phải lội xuống tầng hầm lục lọi đống hồ sơ bằng giấy (ổ cứng vật lý), việc này rất lâu. Thay vào đó, VFS dán luôn một tấm biển tên "Phòng Anh Hải" ngay trên bảng chỉ đường ở sảnh chính bằng RAM (gọi là dcache). Lần sau bạn đến, chỉ cần liếc mắt nhìn bảng dcache là biết đường đi ngay lập tức mà không cần xuống tầng hầm nữa.

### 4.2 `dentry` là gì?

`dentry` (Directory Entry) là đối tượng cấu trúc dữ liệu của **VFS**, đại diện cho **mối quan hệ giữa một cái tên cụ thể và một thư mục**. 

*   Mô hình: `Parent directory + Tên tệp -> dentry -> inode` (`docs/baocao.txt`→ dentry → `số inode 2211`).
*   Các đối tượng `dentry` được VFS duy trì và lưu vào bộ nhớ đệm (gọi là `dcache`) để giúp việc `pathname resolution` diễn ra nhanh chóng. *Lưu ý: Khái niệm `dentry` của VFS nằm trên RAM hoàn toàn khác với các bản ghi directory entry vật lý được ghi cứng trên đĩa của một filesystem cụ thể.*
* Mô hình hoạt động: Khi bạn tìm đường dẫn `/home/user/a.txt`, Kernel sẽ ghép `Thư mục cha (/home/user/)` + `Tên tệp (a.txt)` để tạo ra một dentry, dentry này chỉ thẳng đến inode chứa dữ liệu thật của tệp `a.txt`.

### 4.3 `inode` là gì?

`inode` (Index Node) là hạt nhân lưu trữ của mọi đối tượng tệp tin. Nó chứa toàn bộ **siêu dữ liệu (metadata)** và bản đồ ánh xạ tới các block dữ liệu thực tế, **NGOẠI TRỪ TÊN TỆP**.

Siêu dữ liệu trong inode bao gồm:
*   Loại tệp (file type).
*   Quyền truy cập (mode/permissions).
*   Chủ sở hữu (UID/GID).
*   Kích thước (size).
*   Các mốc thời gian (timestamps).
*   Số lượng liên kết cứng (link count).
*   Con trỏ tới các khối dữ liệu (data mapping).

### 4.4 `inode` không chứa pathname đầy đủ

Tên tệp không nằm trong `inode`. Tên tệp thuộc quyền quản lý của cấu trúc thư mục (directory) trỏ tới `inode` đó. Sự chia tách kiến trúc này vô cùng mạnh mẽ: nó cho phép một `inode` dữ liệu (một object) có thể sở hữu nhiều cái tên ở các thư mục hoàn toàn khác nhau thông qua cơ chế liên kết cứng (`hard link`).

### 4.5 `inode number` không phải ID toàn hệ thống

Chỉ số `inode number` chỉ mang tính duy nhất (unique) trong giới hạn của một vùng mount filesystem cụ thể. Nếu bạn kiểm tra hai filesystem khác nhau (ext4 và tmpfs), việc tìm thấy hai tệp có chung một `inode number` là chuyện bình thường.

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

### 5.2 Dung lượng được cấp phát (Allocated size)

Filesystem vật lý quản lý lưu trữ theo từng khối (Block) để tối ưu hiệu suất, ví dụ block size chuẩn thường là 4096 bytes (4KB).
*   Một tệp có `logical size` 1000 bytes vẫn sẽ tiêu tốn 1 block (4096 bytes) dung lượng ổ cứng cấp phát do `filesystem overhead`.
*   Trái lại, với tệp thưa (`sparse file`), một file ảo 1GB chứa toàn số không (0) có thể được filesystem khéo léo ánh xạ mà chỉ tốn vài KB dung lượng thật.

### 5.3 `st_size`, `st_blocks`, `st_blksize` (Các trường trong cấu trúc `stat`)

*   `st_size`: Kích thước logic (1000 bytes).
*   `st_blocks`: Số lượng block lưu trữ 512-byte đã thực sự được cấp phát (8 blocks).
*   `st_blksize`: Kích thước block tối ưu (preferred I/O block size) để ứng dụng nên dùng khi đọc/ghi file này (vd 4096 bytes). 

---

## 6. Các loại tệp trong Linux

Thế giới "file" trong Linux rất đa dạng và được phân biệt ở cấp độ `inode`, hoàn toàn không phụ thuộc vào phần đuôi mở rộng (extension) như `.txt` hay `.exe`.

### 6.1 `regular file` (Tệp thông thường)

Là tệp chứa nội dung dữ liệu (văn bản, nhị phân, ảnh, database). 

### 6.2 `directory` (Thư mục)

Thư mục chính nó là một loại tệp đặc biệt. Nhiệm vụ của nó là ánh xạ (map) các cái tên (filename) thành số thứ tự của các đối tượng (inode number) bên trong không gian tên đó.

### 6.3 `symbolic link` (Liên kết mềm)

Là tệp chỉ chứa một đoạn chuỗi văn bản làm "biển báo" trỏ đường (pathname mục tiêu).
Mục tiêu trỏ tới có thể là một tệp tồn tại, hoặc một tệp chưa hề tồn tại (dangling link).

### 6.4 `character device` (Thiết bị ký tự)

Một `device node` giao tiếp với phần cứng hoạt động theo luồng chuỗi byte tuần tự (stream), không có địa chỉ đĩa ngẫu nhiên (ví dụ cổng UART `ttyS0`).

### 6.5 `block device` (Thiết bị khối)

Một `device node` giao tiếp với phần cứng cho phép truy cập ngẫu nhiên dữ liệu theo từng khối (ví dụ ổ đĩa `sda`, thẻ nhớ `mmcblk0`).

### 6.6 `major` và `minor`

Mỗi `device node` mang một cặp ID:
*   `major number`: Định danh loại trình điều khiển (Driver) chịu trách nhiệm.
*   `minor number`: Phân biệt các thiết bị/phân vùng vật lý khác nhau cùng dùng chung Driver đó.
*Lưu ý: Sự tồn tại của một file `device node` trong `/dev` không chứng minh phần cứng vật lý đó đang được cắm vào máy.*

### 6.7 FIFO (Named Pipe)

Là một đường ống (Pipe) được đặt tên hiển thị thẳng trong filesystem. Pathname của FIFO đóng vai trò như một "địa điểm gặp gỡ" (rendezvous point) để hai tiến trình không quen biết nhau có thể tìm thấy và truyền dữ liệu cho nhau.

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

Hệ thống tệp là môi trường đa nhiệm. Giữa khoảnh khoắc chương trình của bạn lấy siêu dữ liệu từ `stat()` và thời điểm bạn thực sự mở file, một tiến trình khác hoàn toàn có thể đã thay đổi chủ sở hữu hoặc xóa file đó (Race condition - TOCTOU).

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

Sau khi mount thẻ nhớ vào `/mnt/sdcard`, khi VFS phân giải pathname chạm đến nhánh `/mnt/sdcard`, nó sẽ lập tức "bẻ lái" sang gốc của filesystem mới (exFAT). 
Nội dung cũ (`readme.txt`) không hề bị lệnh mount xóa đi; nó chỉ bị che lấp (shadowed) bởi không gian của thẻ nhớ mới, cho đến khi thẻ nhớ được tháo gỡ (unmount).

### 10.3 Thiết bị khối, Phân vùng, Hệ thống tệp, và Điểm gắn kết

Đây là bốn khái niệm cấu trúc phân tầng thường bị gọi chung chung là "ổ đĩa". 

```text
[ Thiết bị khối - Block Device ]     (Phần cứng vật lý: Ổ SSD /dev/nvme0n1)
                |
[ Phân vùng - Partition ]            (Chia tách không gian: Phân vùng số 1 /dev/nvme0n1p1)
                |
[ Hệ thống tệp - Filesystem Format ] (Cấu trúc tổ chức: Định dạng ext4 trên phân vùng)
                |
[ Mount Point - Điểm gắn kết ]       (Gắn kết không gian tên: Ánh xạ ext4 vào thư mục "/home")
```

> **Đọc sơ đồ:** Hardware cung cấp block device. Quản trị viên cắt nó thành các partition. Để sử dụng, cần format thành một filesystem để tạo cấu trúc `inode`/metadata. Cuối cùng, để phần mềm tương tác được với đống cấu trúc đó, bạn phải đưa nó vào không gian tên của hệ điều hành thông qua Mount Point. Vì thế, lỗi "không thấy file" ở Mount Point có thể xuất phát từ việc mount bị rớt, chứ không có nghĩa là Block Device vật lý đã hỏng.

---

## 11. `/dev`, `/proc`, `/sys`: những hệ thống tệp đặc biệt

Không phải filesystem nào cũng lưu xuống chip nhớ vật lý. Linux tận dụng VFS để biến dữ liệu cấu trúc nội bộ của Kernel thành các thư mục ảo, giúp userspace thao tác quản trị bằng những lệnh `cat`, `echo` cực kỳ quen thuộc.

### 11.1 `/dev` (devtmpfs)

Lưu trữ các `device node` đại diện cho phần cứng (loa, chuột, cổng serial). Khi phần cứng cắm vào, Kernel thông qua `devtmpfs` tạo một entry tại đây. 

### 11.2 `/proc` (procfs)

Hệ thống tệp ảo trên RAM, là cửa sổ phơi bày trạng thái động của hệ điều hành.
*   Chứa thông tin tiến trình (`/proc/[PID]/`).
*   Thông số tài nguyên (`/proc/meminfo`, `/proc/cpuinfo`).
*   Cấu hình runtime của Kernel (`/proc/sys/`).
*   Nội dung trong `procfs` thường là số không tròn trĩnh (size 0) và được Kernel sinh/tổng hợp động theo thời gian thực (real-time) ngay khi có ứng dụng gọi hàm `read()`.

### 11.3 `/sys` (sysfs)

Tương tự `procfs`, `sysfs` là mô hình cây ảo phân cấp rõ ràng mô tả cách các thiết bị (devices), trình điều khiển (drivers), bus, và firmware kết nối với nhau.
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
