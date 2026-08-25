# Chủ đề 4 — Tiến trình trong Linux

> **Mục tiêu:** Hiểu bản chất tiến trình (`process`) là gì, Linux kernel quản lý và lập lịch cho tiến trình ra sao, cũng như thấu hiểu vòng đời kinh điển `fork() → execve() → exit() → wait()` của môi trường UNIX/Linux.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các thuật ngữ chuẩn được giữ nguyên bằng tiếng Anh để thuận tiện tra cứu tài liệu system programming như: `program image`, `scheduler`, `context switch`, `open file description`, `exit status`, `zombie`, `orphan process`, `reparenting`, `subreaper`, `PID namespace`, `PID`, `PPID`, `COW` và `procfs`.
>
> Chương này là **lý thuyết nền tảng**, tập trung vào việc xây dựng mô hình vòng đời của tiến trình trong bộ nhớ, không có bài thực hành.

Một **chương trình (program)** là mã lệnh và dữ liệu ở trạng thái tĩnh trên hệ thống tệp; còn một **tiến trình (process)** là ngữ cảnh thực thi động mà Linux kernel quản lý cho một lần chạy, bao gồm PID, không gian địa chỉ ảo, các `file descriptor`, thông tin phân quyền và trạng thái lập lịch. Đây là sự phân biệt nền tảng để hiểu chính xác cách `fork()`, `execve()` và `wait()` hoạt động.

Chương này sẽ xây dựng mô hình “một tiến trình đang sở hữu những tài nguyên gì”, sau đó theo dõi toàn bộ vòng đời của nó: từ lúc được sinh ra, thay đổi `program image`, kết thúc, chuyển thành trạng thái zombie, và cuối cùng được tiến trình cha thu hồi.

---

## Mục lục

- [1. Chương trình và tiến trình khác nhau thế nào?](#1-chương-trình-và-tiến-trình-khác-nhau-thế-nào)
- [2. PID, PPID và cây tiến trình](#2-pid-ppid-và-cây-tiến-trình)
- [3. Một tiến trình đang nắm giữ những gì?](#3-một-tiến-trình-đang-nắm-giữ-những-gì)
- [4. Trạng thái tiến trình và `scheduler`](#4-trạng-thái-tiến-trình-và-scheduler)
- [5. `fork()`: tạo tiến trình con](#5-fork-tạo-tiến-trình-con)
- [6. `execve()`: thay `program image`](#6-execve-thay-program-image)
- [7. Kết thúc tiến trình và `exit status`](#7-kết-thúc-tiến-trình-và-exit-status)
- [8. Zombie, `wait()`, `orphan process` và chuyển tiến trình cha](#8-zombie-wait-orphan-process-và-chuyển-tiến-trình-cha)
- [9. Quan sát tiến trình qua `/proc`](#9-quan-sát-tiến-trình-qua-proc)
- [10. `ps`, `top` và góc nhìn của `scheduler`](#10-ps-top-và-góc-nhìn-của-scheduler)
- [11. Tư duy gỡ lỗi tiến trình](#11-tư-duy-gỡ-lỗi-tiến-trình)
- [12. Liên hệ với Embedded Linux](#12-liên-hệ-với-embedded-linux)
- [13. Tổng kết](#13-tổng-kết)
- [14. Tài liệu tham khảo](#14-tài-liệu-tham-khảo)

---

## 1. Chương trình và tiến trình khác nhau thế nào?

Chương trình là mã và dữ liệu tĩnh nằm trên thiết bị lưu trữ; tiến trình là ngữ cảnh động khi chương trình đang được chạy với PID, bộ nhớ và tài nguyên được cấp phát riêng.

### 1.1 Chương trình là dữ liệu tĩnh

Một tệp thực thi (`executable`) trên hệ thống tệp chỉ chứa các thành phần cấu trúc tĩnh như:
*   Mã máy (machine code).
*   Dữ liệu khởi tạo ban đầu (data).
*   Siêu dữ liệu định dạng (ELF metadata).
*   Thông tin symbol/relocation để liên kết thư viện.

Bản thân tệp tin này không "đang chạy", nó giống như một bản thiết kế nằm trên giấy.

### 1.2 Tiến trình là ngữ cảnh thực thi

Khi Linux tạo một ngữ cảnh thực thi và thiết lập `program image` cho chương trình, hệ thống có một tiến trình có thể được scheduler cấp CPU để chạy:

```text
[ Tệp Executable (Trên ổ cứng) ]
           |
      (Nạp vào RAM)
           v
[ Tiến trình (Đang thực thi) ]
           |
           +--> PID (Định danh)
           +--> Virtual address space (Không gian địa chỉ ảo)
           +--> CPU register state (Trạng thái thanh ghi CPU)
           +--> File descriptor table (Bảng tệp đang mở)
           +--> Credentials (Quyền truy cập)
           +--> Current working directory (Thư mục làm việc)
           +--> Signal state (Trạng thái xử lý tín hiệu)
```

> **Đọc sơ đồ:** Từ một tệp thực thi duy nhất (ví dụ `/bin/bash`), Kernel có thể khởi tạo ra hàng chục tiến trình hoàn toàn độc lập. Mỗi tiến trình sở hữu một không gian tài nguyên riêng biệt, nếu tiến trình A bị sập thì tiến trình B chạy cùng một tệp thực thi đó vẫn hoạt động bình thường.

### 1.3 Linux kernel nhìn tiến trình như thế nào?

Bên trong Kernel, đơn vị được quản lý và lập lịch được biểu diễn thông qua các cấu trúc `task`.
Về mặt mô hình, một tiến trình có thể được định nghĩa bằng: **Trạng thái thực thi + Tài nguyên nắm giữ + Định danh**. (Khi đi sâu vào đa luồng, ta sẽ thấy một tiến trình có thể chứa nhiều task/luồng chia sẻ chung tài nguyên).

---

## 2. PID, PPID và cây tiến trình

Mọi tiến trình đều có một mã định danh (PID) và mã của tiến trình đã sinh ra nó (PPID). Mối quan hệ này tạo thành một cấu trúc cây quản lý toàn bộ hệ thống.

### 2.1 PID (Process ID)

`PID` là số định danh duy nhất của tiến trình trong một không gian tên (`PID namespace`) tại một thời điểm.
Nó là chìa khóa để các API và công cụ tương tác với tiến trình:
*   `kill(pid, ...)`: Gửi tín hiệu.
*   `waitpid(pid, ...)`: Chờ tiến trình kết thúc.
*   Tra cứu thông tin qua `/proc/<pid>`.

### 2.2 PID có thể được tái sử dụng

Sau khi một tiến trình kết thúc và được Kernel thu hồi tài nguyên đầy đủ, con số PID của nó sẽ được trả lại vào quỹ chung và có thể được cấp cho một tiến trình mới. Do đó, **PID không phải là một định danh vĩnh viễn theo thời gian**.

### 2.3 PPID (Parent Process ID)

`PPID` là PID của tiến trình cha **hiện tại**. Khi một child vừa được tạo bằng `fork()`, parent ban đầu thường là tiến trình gọi `fork()`, nhưng quan hệ này có thể thay đổi về sau do `reparenting`. Quan hệ cha/con quyết định nhiều cơ chế cốt lõi như `wait()`, thu hồi `zombie`, job control của shell và việc giám sát process tree bởi các service manager như systemd.

### 2.4 Cây tiến trình (Process Hierarchy)

```text
[ PID 1 ] (init / systemd / BusyBox)
    |
    +---> [ shell ] (PPID = 1)
    |        |
    |        +---> [ app A ] (PPID = PID của shell)
    |        +---> [ app B ]
    |
    +---> [ sshd service ] (PPID = 1)
```

> **Đọc sơ đồ:** Sơ đồ này biểu diễn **mối quan hệ phả hệ (parent/child)**, tuyệt đối KHÔNG phải là thứ tự chạy trên CPU. Shell dùng `fork()` tạo ra `app A` và `app B`, vì vậy nó chịu trách nhiệm thu hồi kết quả của chúng. Bộ lập lịch (scheduler) của Kernel vẫn có toàn quyền chia thời gian CPU đan xen giữa PID 1, shell và app A một cách độc lập. Mối quan hệ phả hệ này có thể bị thay đổi (reparenting) nếu tiến trình cha chết trước tiến trình con.

---

## 3. Một tiến trình đang nắm giữ những gì?

Tiến trình không chỉ là mã đang chạy. Nó là một tập hợp trạng thái và tài nguyên gồm không gian địa chỉ ảo, bảng `file descriptor`, thông tin filesystem, credentials, signal state và trạng thái lập lịch.

### 3.1 Không gian địa chỉ ảo (Virtual Address Space)

Tiến trình không tương tác với các thanh RAM vật lý một cách trực tiếp. Kernel cung cấp cho nó một ảo giác về một dải bộ nhớ liền mạch, gọi là Không gian địa chỉ ảo.

```text
(Địa chỉ thấp)
+------------------+
| Code / Text      |  (Mã máy thực thi, Read-only)
+------------------+
| Data / BSS       |  (Biến toàn cục, biến tĩnh)
+------------------+
| Heap             |  (Bộ nhớ cấp phát động: malloc/free)
|       ↓          |  (Mở rộng xuống dưới)
|                  |
| mmap regions     |  (Thư viện động .so, file ánh xạ)
|                  |
|       ↑          |  (Mở rộng lên trên)
| Stack            |  (Biến cục bộ, call frame của hàm)
+------------------+
(Địa chỉ cao)
```

> **Đọc sơ đồ:** Đây là mô hình khái niệm thường dùng để hình dung không gian địa chỉ ảo của một tiến trình. Mã máy thường nằm ở vùng `Text`, dữ liệu toàn cục ở `Data/BSS`, bộ nhớ cấp phát động liên quan tới `Heap`, còn lời gọi hàm sử dụng `Stack`. Các vùng ánh xạ bởi `mmap()` có thể chứa shared libraries hoặc file mapping. Bố cục thực tế phụ thuộc ELF, dynamic loader, ASLR, kiến trúc CPU và các lời gọi `mmap()`, nên không nên coi hình trên là địa chỉ cố định cho mọi tiến trình.

### 3.2 Bộ nhớ ảo không đồng nghĩa với RAM vật lý

Một tiến trình có dải địa chỉ ảo 2GB không có nghĩa là nó đang ngốn 2GB RAM vật lý (RAM thực).
Cần tách biệt các trạng thái bộ nhớ:
*   `virtual address space`: Kích thước không gian địa chỉ ảo mà Kernel hứa cấp.
*   `resident pages`: Số trang nhớ thực sự đang nằm trên RAM vật lý.
*   `shared pages`: Bộ nhớ dùng chung (như thư viện libc.so).
*   `file-backed pages`: Bộ nhớ được ánh xạ trực tiếp từ tệp tin trên ổ đĩa.

### 3.3 file descriptor table và Ngữ cảnh

Như đã học ở Topic 03, tiến trình chứa một file descriptor table độc lập theo dõi các luồng `stdin (0)`, `stdout (1)`, `stderr (2)` và các tệp đang mở khác.
Bên cạnh đó, tiến trình còn nắm giữ:
*   **Ngữ cảnh Filesystem:** Thư mục làm việc hiện tại (`cwd`), thư mục gốc ảo (`chroot`), và `umask`.
*   **Tham số khởi tạo:** Mảng đối số (`argv`) và biến môi trường (Environment variables) truyền vào lúc `execve()`.
*   **Credentials:** Tập hợp UID/GID và capabilities quyết định quyền hạn bảo mật.

---

## 4. Trạng thái tiến trình và `scheduler`

Tiến trình không phải lúc nào cũng chạy. Bộ lập lịch (`scheduler`) của Kernel quyết định task nào được CPU theo scheduling policy hiện hành và chuyển task giữa các trạng thái chạy, sẵn sàng chạy hoặc chờ sự kiện.

### 4.1 `Running` và `Runnable`

Dù công cụ `ps` hay `top` thường gộp chung hiển thị thành trạng thái `R`, bản chất chúng khác nhau:
*   `Runnable`: Đã đủ điều kiện, đang đứng xếp hàng chờ được cấp CPU.
*   `Running`: Đang thực sự được CPU thực thi các mã lệnh (instruction).

### 4.2 `Sleeping` (Đang ngủ)

Khi tiến trình cần chờ một sự kiện (như chờ dữ liệu từ mạng, đọc ổ cứng, hoặc chờ khóa mutex), nó nhường CPU và rơi vào trạng thái ngủ. Kernel chia làm hai loại:
*   **Trạng thái `S` (Interruptible Sleep):** Ngủ nhưng có thể bị đánh thức bởi một tín hiệu (Signal) gửi đến.
*   **Trạng thái `D` (Uninterruptible Sleep):** Task đang chờ trong một đoạn Kernel không cho phép tín hiệu thông thường ngắt giữa chừng, thường liên quan tới một số đường I/O hoặc driver. Ngay cả `SIGKILL` cũng không làm task lập tức chạy code xử lý để thoát; tín hiệu chỉ có thể phát huy tác dụng khi task rời trạng thái chờ phù hợp. *Gặp `D` trong thời gian ngắn không nhất thiết là lỗi, nhưng kẹt ở `D` quá lâu có thể gợi ý storage/driver/hardware đang gặp vấn đề*.

### 4.3 `Stopped` và `Zombie`

*   **`Stopped` (T):** Tiến trình bị tạm dừng (ví dụ nhấn Ctrl+Z) hoặc đang bị debugger can thiệp.
*   **`Zombie` (Z):** Tiến trình đã kết thúc (đã chết), không còn chạy code, nhưng bộ xương của nó vẫn còn lưu trong bảng quản lý của Kernel chờ tiến trình cha đến thu thập.

### 4.4 `Context Switch` (Chuyển ngữ cảnh)

```text
[ Task A đang Running ]
         |
    (Hết thời lượng hoặc chờ I/O)
         v
[ Kernel lưu trạng thái thanh ghi CPU của Task A ]
         |
[ Scheduler chọn Task B từ danh sách Runnable ]
         |
[ Kernel khôi phục trạng thái thanh ghi CPU của Task B ]
         v
[ Task B bắt đầu Running ]
```

> **Đọc sơ đồ:** Mỗi CPU core chỉ thực thi một task tại một thời điểm. Khi xảy ra `context switch`, Kernel lưu execution context cần thiết của Task A, chọn Task B theo scheduling policy, khôi phục context của B rồi tiếp tục thực thi B. Trên hệ thống một lõi, việc chuyển đổi nhanh tạo cảm giác nhiều tiến trình cùng tiến triển; trên hệ thống nhiều lõi, một số task có thể thực sự chạy song song trên các core khác nhau.

---

## 5. `fork()`: tạo tiến trình con

`fork()` là cơ chế kinh điển của POSIX/UNIX để tạo một tiến trình con mới dựa trên tiến trình gọi. Trên Linux còn có các primitive/API khác như `clone()`/`clone3()` ở tầng thấp và `posix_spawn()` ở tầng thư viện, nhưng `fork()` vẫn là mental model quan trọng nhất để hiểu process creation và cách shell chạy chương trình ngoài.

### 5.1 Mô hình phân nhánh

```text
          [ Parent Process ] (PID=100)
                    |
                  fork()
                 /      \
                /        \
               v          v
        [ Parent ]      [ Child ] (PID=101)
        return 101      return 0
```

> **Đọc sơ đồ:** Sau một `fork()` thành công, parent và child đều tiếp tục từ vị trí ngay sau lời gọi nhưng nhận giá trị trả về khác nhau: parent nhận PID của child, còn child nhận `0`. Nếu `fork()` thất bại, parent nhận `-1` và không có child mới được tạo. Nhờ giá trị trả về này, cùng một đoạn code có thể phân nhánh logic cho parent và child.

### 5.2 Cơ chế Copy-on-Write (COW)

Sau `fork()`, child có một không gian địa chỉ riêng về mặt ngữ nghĩa, ban đầu phản ánh trạng thái bộ nhớ của parent tại thời điểm tạo. Linux tối ưu việc này bằng **Copy-on-Write (COW)** thay vì sao chép ngay toàn bộ nội dung RAM.

*   **Ngay sau `fork()`:** Với các private writable pages có thể áp dụng COW, parent và child tạm thời cùng tham chiếu tới các physical page hiện có; page table được thiết lập để phát hiện lần ghi đầu tiên.
*   **Khi một phía ghi:** CPU phát sinh page fault, Kernel cấp một page riêng, sao chép dữ liệu cần thiết rồi cho phía đang ghi tiếp tục trên bản sao của nó.

COW giúp `fork()` tránh chi phí sao chép toàn bộ memory contents ngay lập tức và thường tiết kiệm đáng kể thời gian/bộ nhớ. Tuy vậy, `fork()` vẫn phải tạo task metadata, page-table state và nhiều bookkeeping khác, nên không nên hiểu rằng chi phí của nó luôn bằng không.

### 5.3 Chia sẻ `File descriptor` sau `fork()`

Tiến trình con nhận các `file descriptor` tương ứng với parent. Các entry này tham chiếu tới cùng những `open file description` ở Kernel, nên parent và child có thể **chia sẻ `file offset` và file status flags**. Nếu child đọc từ một regular-file fd dùng chung, offset trong open file description thay đổi và parent sẽ quan sát vị trí mới ở lần I/O tiếp theo.

### 5.4 Không phải mọi trạng thái đều được sao chép giống hệt

`fork()` copy hoặc kế thừa rất nhiều trạng thái của parent, nhưng không có nghĩa mọi thuộc tính đều trở thành một bản sao nguyên trạng. POSIX/Linux quy định một số state có ngữ nghĩa riêng hoặc được reset ở child; chẳng hạn pending signal set của child ban đầu rỗng. Vì vậy, mental model đúng là **child bắt đầu từ trạng thái rất giống parent nhưng trở thành một process độc lập theo các quy tắc kế thừa cụ thể**, chứ không phải một bản clone tuyệt đối của mọi bit trạng thái.

---

## 6. `execve()`: thay `program image`

Nếu `fork()` tạo một process mới, thì `execve()` làm việc khác hẳn: nó **thay `program image` của process hiện tại** bằng chương trình mới. Process vẫn giữ cùng PID, nhưng mã lệnh, dữ liệu và nhiều vùng ánh xạ của chương trình cũ được thay thế theo quy tắc của `execve()`.

### 6.1 Ý nghĩa cốt lõi

`execve()` KHÔNG tạo ra tiến trình mới.

```text
[ Tiến trình PID = 1200 ]
  Đang chạy mã của Program A
            |
      gọi execve(Program B)
            |
            v
[ Tiến trình PID = 1200 ]
  Program image A đã được thay thế.
  Bắt đầu tại entry point của Program B.
```

> **Đọc sơ đồ:** PID vẫn giữ nguyên vì `execve()` không tạo process mới. Khi thành công, program image cũ được thay thế bằng program image mới: code, data, stack và nhiều memory mapping được thiết lập lại cho chương trình B. Sau đó process bắt đầu thực thi tại entry point của chương trình mới.

### 6.2 Không có đường lùi

Nếu `execve()` thành công, program image cũ đã được thay thế nên lời gọi **không return về dòng code cũ** như một hàm thông thường. `execve()` chỉ return `-1` khi thất bại, chẳng hạn khi pathname không tồn tại hoặc chương trình mới không thể được thực thi.

### 6.3 Trạng thái nào được giữ, trạng thái nào thay đổi qua `execve()`?

`execve()` giữ lại một số thuộc tính của process nhưng thay đổi hoặc reset nhiều thuộc tính khác theo quy tắc POSIX/Linux:

*   **Thường được giữ:** PID, PPID, current working directory và nhiều `file descriptor` đang mở.
*   **Được thay thế/reset:** program image cũ, phần lớn memory mappings và các signal handler đã được cài đặt theo cách bắt signal; `argv`/`envp` mới được lấy từ lời gọi `execve()`.
*   **Credentials:** không nên hiểu là luôn giữ nguyên tuyệt đối. Set-user-ID/set-group-ID bits, capabilities, `no_new_privs` và các quy tắc bảo mật khác có thể làm credentials thay đổi hoặc bị hạn chế khi `execve()`.

Các `file descriptor` không có cờ close-on-exec thường tiếp tục tồn tại qua `execve()`. Điều này hữu ích khi shell cố tình truyền pipe/redirection sang chương trình mới, nhưng cũng có thể gây rò rỉ tài nguyên. Cờ **`O_CLOEXEC`** (hoặc `FD_CLOEXEC`) yêu cầu Kernel đóng fd tương ứng khi `execve()` thành công.

### 6.4 Script `#!` (Shebang)

Khi bạn chạy một script executable có dòng đầu dạng `#!/bin/bash`, Kernel nhận diện shebang và dùng interpreter được chỉ định để thực thi nội dung script. Về mặt khái niệm, interpreter trở thành chương trình được chạy và pathname của script được truyền vào danh sách đối số theo quy tắc shebang.

### 6.5 Mô hình `fork()` + `execve()` của Shell

Đây là chiếc cầu nối trực tiếp giữa Topic 01 (Shell), Topic 03 (`file descriptor`, pipe/redirection) và Topic 04 (process):

```text
[ Shell ]
    |
    | fork()
    +-------------------------------+
    |                               |
    v                               v
[ Parent shell ]                [ Child process ]
    |                               |
    |                               +--> thiết lập stdin/stdout/stderr
    |                               +--> nối pipe / redirection
    |                               +--> đóng các fd không cần thiết
    |                               |
    |                               +--> execve(program, argv, envp)
    |                                            |
    |                                            v
    |                                     [ Program mới ]
    |
    +--> wait()/waitpid() hoặc tiếp tục tùy foreground/background
```

> **Đọc sơ đồ:** Shell tách việc **tạo process** và **thay program image** thành hai bước. Sau `fork()`, child vẫn đang chạy code của shell nên có cơ hội cấu hình `file descriptor`: nối pipe, chuyển hướng `stdin/stdout/stderr`, đóng fd thừa hoặc chuẩn bị environment. Chỉ sau khi execution environment đã sẵn sàng, child gọi `execve()` để trở thành chương trình ngoài như `ls` hay `grep`. Parent shell có thể `wait()` nếu đó là foreground job hoặc tiếp tục nhận lệnh tùy cách job được tổ chức.

---

## 7. Kết thúc tiến trình và `exit status`

Khi một process kết thúc, Kernel xử lý việc giải phóng tài nguyên thực thi và lưu thông tin kết thúc cần thiết theo cơ chế signal/wait để parent có thể quan sát trạng thái của child.

### 7.1 Sự khác biệt giữa `exit()` và `_exit()`

*   **`exit()`:** Hàm của thư viện C ở userspace. Nó chạy các handler đã đăng ký bằng `atexit()`, flush/close các `stdio` stream theo quy tắc của libc, rồi mới yêu cầu kết thúc process.
*   **`_exit()` / `_Exit()`:** API kết thúc process mà **không chạy cleanup của `stdio`/`atexit()` như `exit()`**. Trên Linux, chi tiết libc wrapper và raw kernel syscall có nuance riêng; ở mức chương này chỉ cần nhớ rằng `_exit()` bỏ qua cleanup của thư viện C.

*Lưu ý:* Trong child vừa `fork()` mà chuẩn bị thất bại trước `execve()`, `_exit()` thường được dùng để tránh flush lại `stdio` buffer đã được copy từ parent.

### 7.2 Mã trạng thái (Exit Status)

Khi process kết thúc bình thường, một `exit status` được giữ lại để parent thu thập bằng họ hàm `wait`. Theo convention, `0` thường biểu thị thành công; giá trị nonzero mang ý nghĩa do chương trình quy định và không phải lúc nào cũng đồng nghĩa với “lỗi chương trình”. Ngoài normal exit status, `wait()`/`waitpid()` còn cung cấp wait status để parent phân biệt các trường hợp như child bị signal terminate, bị stop hoặc được continue khi dùng các option phù hợp.

---

## 8. Zombie, `wait()`, `orphan process` và chuyển tiến trình cha

Phần này phân biệt hai trạng thái rất dễ nhầm: `zombie` là child đã kết thúc nhưng trạng thái chưa được parent thu thập; `orphan process` là child vẫn đang chạy nhưng parent cũ đã kết thúc.

### 8.1 `Zombie process`

Một child trở thành zombie khi execution của nó đã kết thúc nhưng wait status vẫn chưa được parent (hoặc process có trách nhiệm tương ứng) thu thập.

```text
[ Tiến trình con gọi exit() ]
          |
          v
[ Trạng thái ZOMBIE ] (Không còn chạy; Kernel giữ wait-related state tối thiểu)
          |
[ Tiến trình cha gọi wait() ]
          |
          v
[ REAPED (Được thu dọn hoàn toàn) ]
```

> **Đọc sơ đồ:** Zombie không còn thực thi code và không sử dụng CPU như một process đang chạy. Kernel chỉ giữ lại một lượng trạng thái tối thiểu cần cho cơ chế wait, chẳng hạn PID và thông tin kết thúc. Gửi thêm signal như `SIGKILL` không làm zombie “chết thêm” vì execution của nó đã kết thúc. Zombie biến mất khi trạng thái được một parent/subreaper phù hợp thu thập; nếu parent cũ kết thúc, reparenting có thể chuyển trách nhiệm này sang process khác.

### 8.2 Lệnh `wait()` / `waitpid()`

`wait()`/`waitpid()` cho phép parent thu thập trạng thái của child và cho Kernel reap zombie tương ứng. Nếu chưa có child phù hợp ở trạng thái có thể báo cáo, lời gọi có thể block; nếu trạng thái đã sẵn sàng thì có thể return ngay. `waitpid()` còn hỗ trợ các option như `WNOHANG` để kiểm tra mà không phải block.

### 8.3 `Orphan process` (Trẻ mồ côi)

`Zombie` và `orphan process` là hai khái niệm khác nhau. Zombie là child đã kết thúc nhưng chưa được reap; ngược lại, `orphan process` là **child vẫn đang chạy trong khi parent cũ đã kết thúc**.

### 8.4 Reparenting (Nhận nuôi)

Khi parent cũ kết thúc, Linux thực hiện `reparenting`: child còn sống được gắn sang một parent phù hợp, chẳng hạn một `subreaper` gần nhất hoặc process init/child reaper của PID namespace tương ứng. Cơ chế này bảo đảm vẫn có một process chịu trách nhiệm thu thập trạng thái khi child kết thúc về sau.

---

## 9. Quan sát tiến trình qua `/proc`

Như Topic 02 đã phân tích, `/proc` không phải ổ cứng. Nó là một giao diện giao tiếp mà Kernel dùng để xuất trạng thái tiến trình ra dưới dạng tệp văn bản.

### 9.1 Hệ thống tệp ảo `/proc/<pid>`

Nhiều trạng thái của một tiến trình đang chạy có thể được **quan sát** thông qua thư mục mang tên PID của nó. Khả năng đọc từng entry phụ thuộc permission/security policy; phần lớn entry không phải giao diện tùy ý ghi và `/proc/<pid>` không đại diện cho toàn bộ trạng thái process theo nghĩa “mọi thứ đều đọc/ghi được”.

*   **`status`**: Bản tóm tắt thân thiện với con người chứa trạng thái (R, S, D, Z), PPID, thông tin quyền (Uid/Gid), các trường bộ nhớ (Vm*) và thông tin signal.
*   **`stat`**: Biểu diễn thông số dạng hàng ngang cô đọng, tối ưu cho các công cụ như `ps` hay `top` parse dữ liệu.
*   **`cmdline`**: Phơi bày vùng đối số lệnh mà procfs nhìn thấy. Không nên coi đây là lịch sử lệnh bất biến vì process có thể thay đổi nội dung/vùng bộ nhớ liên quan.
*   **`environ`**: Phơi bày vùng environment theo cách procfs cung cấp; cũng không nên hiểu nó là bản ghi lịch sử bất biến của mọi thay đổi environment trong suốt vòng đời process.
*   **`maps`**: Bản đồ không gian địa chỉ ảo, hiển thị tiến trình đang map các thư viện và phân vùng bộ nhớ như thế nào (không phải bản đồ RAM vật lý).

### 9.2 Các tham chiếu hệ thống tệp
*   **`cwd`**: Liên kết mềm trỏ tới thư mục làm việc hiện tại.
*   **`root`**: Thư mục gốc ảo của tiến trình.
*   **`exe`**: Liên kết trỏ về tệp thực thi gốc trên ổ đĩa.
*   **`fd/`**: Thư mục cực kỳ quan trọng, chứa các liên kết đại diện cho mọi File Descriptor mà tiến trình đang mở. Rất hữu ích để gỡ lỗi xem ứng dụng đang cầm giữ socket hay tệp tin nào.

---

## 10. `ps`, `top` và góc nhìn của `scheduler`

### 10.1 `ps` (Process Status)

Lệnh `ps` hoạt động bằng cách rà soát thư mục `/proc` và chụp lại một tấm ảnh (snapshot) trạng thái tiến trình tại khoảnh khắc gọi lệnh. Vì tính chất đa nhiệm, trạng thái của tiến trình hoàn toàn có thể thay đổi ngay phần nghìn giây sau khi lệnh `ps` in ra màn hình.

### 10.2 `top`

Hoạt động theo cơ chế lấy mẫu chu kỳ (polling), hiển thị xu hướng tiêu thụ CPU/RAM. Tuy nhiên, nó bị giới hạn bởi tần số lấy mẫu (những tiến trình sinh ra và chết đi quá nhanh giữa hai chu kỳ sẽ bị `top` bỏ lỡ).

### 10.3 Scheduling ở mức cơ bản

Bộ lập lịch (scheduler) quyết định task runnable nào được CPU dựa trên scheduling policy, priority, CPU affinity và trạng thái hệ thống. Với normal scheduling, CPU time thường được chia sẻ theo chính sách công bằng tương đối; với real-time policy như `SCHED_FIFO`, một task ưu tiên cao có thể gây starvation cho task khác nếu nó không block/yield. Vì vậy, nguyên tắc cần nhớ là: **việc một task được chạy khi nào và trong bao lâu phụ thuộc scheduling policy hiện hành, không phải do userspace tự quyết định hoàn toàn**.

---

## 11. Tư duy gỡ lỗi tiến trình

Khi gặp lỗi, hãy tư duy theo trạng thái vòng đời thay vì phỏng đoán.

### 11.1 Tiến trình “biến mất”

Hãy kiểm tra: process tự thoát do lỗi code hay normal exit? Có bị signal kết thúc, chẳng hạn do OOM killer? Có gọi `execve()` để thay `program image` không? Hay service manager đã tự động khởi động lại service với một PID mới?

### 11.2 PID còn nhưng tên chương trình thay đổi

Đây là hành vi hoàn toàn hợp lệ nếu ứng dụng đó đã gọi hàm `execve()` để nạp một `program image` mới đè lên chính nó.

### 11.3 Tràn ngập tiến trình Zombie

Zombie xuất hiện vì trạng thái kết thúc của child chưa được parent/subreaper phù hợp thu thập. Trong chương trình tự quản lý child, cần kiểm tra logic xử lý `SIGCHLD` và các lời gọi `wait()` / `waitpid()` để bảo đảm child được reap đúng lúc.

### 11.4 Tiến trình bị kẹt ở trạng thái `D`

Không nên kết luận ngay rằng ứng dụng lỗi ở userspace. `D` cho thấy task đang ở uninterruptible sleep trong một đường chờ của Kernel. Nếu trạng thái kéo dài bất thường, hãy kiểm tra storage/device/driver liên quan, kernel stack nếu có thể và log hệ thống qua `dmesg`.

### 11.5 Bộ nhớ báo cáo rất lớn

Đừng vội kết luận rò rỉ bộ nhớ (Memory leak). Bạn phải phân biệt rõ `Virtual Size` (VIRT - bộ nhớ ảo được map) và `Resident Set Size` (RES - bộ nhớ RAM vật lý thực sự đang dùng). Một tiến trình có thể ánh xạ (`mmap`) một file 5GB nhưng chỉ dùng vài chục MB RAM vật lý.

---

## 12. Liên hệ với Embedded Linux

Thiết bị Embedded Linux thường chạy nhiều daemon/service phối hợp với nhau. Hiểu process lifecycle, isolation và resource inheritance là nền tảng để thiết kế, bring-up và debug kiến trúc phần mềm trên hệ thống nhúng.

### 12.1 Sự quan trọng của PID 1

Khi userspace khởi động, Kernel chạy tiến trình init có PID 1 trong PID namespace ban đầu. Tùy nền tảng, PID 1 có thể là systemd, SysV init hoặc BusyBox init. Nó có vai trò đặc biệt trong việc khởi động/quản lý service, tham gia reparenting/reaping process và điều phối quá trình shutdown theo kiến trúc của hệ thống.

### 12.2 Kiến trúc Service cách ly

Thay vì gom mọi chức năng vào một process duy nhất, một số kiến trúc Embedded Linux tách phần mềm thành nhiều service/process chuyên trách, ví dụ một service thu thập cảm biến và một service truyền dữ liệu qua mạng.
Nhờ thiết kế nhiều tiến trình, họ đạt được:
*   **Cô lập lỗi (Fault isolation):** Một tiến trình sập do tràn bộ nhớ sẽ không kéo theo toàn bộ hệ thống sập.
*   **Cô lập quyền (Privilege isolation):** Chỉ cấp đặc quyền Root cho những tiến trình thật sự cần chạm tới phần cứng.

### 12.3 Cẩn thận với Kế thừa File Descriptor

Trong hệ nhúng, process có thể giữ UART, GPIO line request, socket hoặc file log qua `file descriptor`. Sau `fork()`, child kế thừa các fd tương ứng; nếu child tiếp tục `execve()` mà fd không có `FD_CLOEXEC` (thường được thiết lập nguyên tử bằng `O_CLOEXEC` lúc `open()`), chương trình mới cũng giữ tham chiếu đó. Hệ quả có thể là device/socket vẫn bị giữ mở ngoài ý muốn dù process ban đầu đã đóng hoặc kết thúc.

### 12.4 `/proc` trên hệ thống Headless (Không màn hình)

Trên hệ thống headless, `/proc` là một trong những giao diện quan sát process quan trọng nhất. Kiểm tra `/proc/<pid>/fd` giúp xác định process đang giữ file/socket/device nào; `/proc/<pid>/maps` giúp quan sát virtual memory mappings khi bring-up và debug.

---

## 13. Tổng kết

Hãy ghi nhớ vòng đời của một Process từ góc nhìn hệ thống:

```text
[ Parent process ]
       |
     fork()
      /  \
     /    \
    v      v
Parent    Child  (address space riêng về semantics, COW tối ưu bộ nhớ)
             |
             | chuẩn bị fd / pipe / redirection nếu cần
             v
          execve()  (thay program image, giữ PID)
             |
             v
       [ Program mới ]
             |
           exit/_exit
             |
             v
         [ Zombie ]  (đã kết thúc, chờ thu thập wait status)
             |
       parent wait()/waitpid()
             |
             v
          [ Reaped ]
```

> **Đọc sơ đồ:** `fork()` và `execve()` thường đi cùng nhưng giải quyết hai bài toán khác nhau: `fork()` tạo child process, còn `execve()` thay `program image` của process gọi. Shell tận dụng khoảng thời gian giữa hai bước để cấu hình `file descriptor`, pipe và redirection trước khi child trở thành chương trình ngoài. Khi child kết thúc, parent thu thập wait status bằng `wait()`/`waitpid()` để Kernel reap zombie.

Trạng thái thực thi ở mức khái niệm:
```text
                 được scheduler chọn
[ Runnable ] --------------------------> [ Running ]
     ^                                      |   |
     |                                      |   +--> exit --> [ Zombie ]
     |                                      |
     |          wakeup / event ready        +--> chờ I/O/event
     +--------------- [ Sleeping ] <---------------+

[ Running ] -- preempt / hết lượt CPU --> [ Runnable ]
```

> **Đọc sơ đồ:** `Runnable` nghĩa là task đủ điều kiện chạy nhưng có thể đang chờ CPU; `Running` nghĩa là đang thực sự thực thi trên một core. Khi phải chờ I/O/event, task có thể chuyển sang `Sleeping`; khi điều kiện chờ hoàn tất, Kernel đánh thức nó trở lại hàng runnable. Một task cũng có thể bị preempt để nhường CPU cho task khác theo scheduling policy. Khi process kết thúc, nó có thể trở thành `Zombie` cho tới khi parent thu thập trạng thái.

**Các nguyên lý cần ghi nhớ:**
1. Chương trình là nội dung thực thi; process là một lần thực thi cùng toàn bộ trạng thái mà Kernel quản lý.
2. PID là định danh tạm thời trong một `PID namespace` và có thể được tái sử dụng.
3. Process bao gồm virtual address space, file descriptor table, filesystem context, credentials, signal state và scheduling state.
4. Task ở trạng thái sleeping không busy-wait; trong thời gian ngủ nó nhường CPU cho task khác.
5. `fork()` tạo child process có address space riêng về semantics; Linux tối ưu nhiều private writable pages bằng COW.
6. Các fd tương ứng sau `fork()` có thể cùng tham chiếu một `open file description`, vì vậy chia sẻ `file offset` và file status flags.
7. `execve()` không tạo PID mới; nó thay `program image` và áp dụng các quy tắc giữ/reset process attributes.
8. Shell thường dùng mô hình `fork()` → cấu hình fd/pipe/redirection → `execve()` để chạy external command.
9. `exit()` chạy cleanup của libc trước khi kết thúc; `_exit()`/`_Exit()` bỏ qua cleanup `stdio`/`atexit()`.
10. Zombie là child đã kết thúc nhưng chưa được reap; orphan process vẫn đang chạy và được reparent khi parent cũ kết thúc.
11. `/proc/<pid>` là giao diện quan trọng để quan sát trạng thái process, nhưng không phải mọi entry đều đọc/ghi được.
12. `wait()`/`waitpid()` thu thập wait status; lời gọi chỉ block khi chưa có trạng thái phù hợp và chế độ gọi yêu cầu chờ.

---

## 14. Tài liệu tham khảo

Phần này liệt kê nguồn chuẩn về tiến trình, `fork`, `exec`, `wait` và `/proc`.

- `fork(2)`: https://man7.org/linux/man-pages/man2/fork.2.html
- `clone(2)`: https://man7.org/linux/man-pages/man2/clone.2.html
- `execve(2)`: https://man7.org/linux/man-pages/man2/execve.2.html
- `wait(2)`: https://man7.org/linux/man-pages/man2/wait.2.html
- `_exit(2)`: https://man7.org/linux/man-pages/man2/_exit.2.html
- `exit(3)`: https://man7.org/linux/man-pages/man3/exit.3.html
- `getpid(2)`: https://man7.org/linux/man-pages/man2/getpid.2.html
- `credentials(7)`: https://man7.org/linux/man-pages/man7/credentials.7.html
- Linux procfs documentation: https://docs.kernel.org/filesystems/proc.html
- POSIX.1-2024: https://pubs.opengroup.org/onlinepubs/9799919799/
- The Linux Programming Interface: https://man7.org/tlpi/

> **Điều hướng:** [← Chủ đề 3 — Vào/ra tệp](README-topic-03.md) · [Chủ đề 5 — Signal →](README-topic-05.md)
