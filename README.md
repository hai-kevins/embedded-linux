# Embedded Linux Roadmap — Fresher Level

Roadmap này tập trung vào **kiến thức cốt lõi mà một Fresher Embedded Linux / BSP nên nắm**.  
Mục tiêu là hiểu được một hệ thống Embedded Linux từ **userspace → bootloader → kernel → Device Tree → RootFS → driver → board bring-up**, đồng thời có đủ kỹ năng thực hành để tự build, boot và debug trên board thật.

## Quy ước môi trường thực hành

- **HOST:** Laptop/PC Ubuntu dùng để viết code, native build, cross-compile, build U-Boot/Kernel/RootFS/Buildroot và tạo image.
- **TARGET:** **BeagleBone Black (BBB)** dùng để boot, chạy chương trình, kiểm tra Device Tree, kernel module/driver, peripheral, bring-up và debug.

---

## Phase 1: Linux Fundamentals & System Programming

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Basic Linux CMD | - Shell và terminal.<br>- Các lệnh Linux cơ bản.<br>- Pipeline, redirect.<br>- `grep`, `find`, `ps`, `top`, `mount`, `df`, `du`. | **Môi trường:** `HOST`<br>- Thao tác hoàn toàn bằng terminal.<br>- Dùng pipeline để lọc output.<br>- Viết bash script đơn giản. |
| 2 | Linux File System | - Cấu trúc thư mục Linux từ `/`.<br>- Regular file, directory, symbolic link, device file, socket, FIFO.<br>- Permission `r/w/x`.<br>- Inode và filesystem cơ bản. | **Môi trường:** `HOST`<br>- Dùng `ls -l`, `stat`, `file`.<br>- Thực hành `chmod`, `chown`, `umask`.<br>- Mount/unmount filesystem. |
| 3 | File I/O | - File descriptor.<br>- `open`, `read`, `write`, `lseek`, `close`.<br>- Standard input/output/error.<br>- Blocking I/O cơ bản. | **Môi trường:** `HOST`<br>- Viết chương trình C đọc/ghi file.<br>- Quan sát file descriptor qua `/proc/<pid>/fd`. |
| 4 | Process | - Program và process.<br>- PID, PPID.<br>- Không gian bộ nhớ process.<br>- Process cha/con.<br>- `fork`, `exec`, `wait`, `exit`. | **Môi trường:** `HOST`<br>- Viết chương trình tạo process con.<br>- Chạy chương trình khác bằng `exec`.<br>- Quan sát process bằng `ps` và `/proc`. |
| 5 | Signal | - Khái niệm signal.<br>- Signal handler.<br>- `sigaction`, `kill`.<br>- `SIGINT`, `SIGTERM`. | **Môi trường:** `HOST`<br>- Viết chương trình gửi/nhận signal.<br>- Xử lý `Ctrl+C` đúng cách. |
| 6 | Multithreading | - POSIX thread.<br>- `pthread_create`, `pthread_join`.<br>- Process vs thread.<br>- Race condition. | **Môi trường:** `HOST`<br>- Viết chương trình nhiều thread.<br>- Tạo và quan sát race condition. |
| 7 | Thread Synchronization | - Mutex.<br>- Semaphore.<br>- Condition variable cơ bản.<br>- Deadlock khái niệm. | **Môi trường:** `HOST`<br>- Bảo vệ shared resource bằng mutex/semaphore.<br>- Sửa một ví dụ race condition. |
| 8 | IPC | - Pipe và FIFO.<br>- Shared memory.<br>- Message queue ở mức khái niệm.<br>- Giao tiếp giữa các process. | **Môi trường:** `HOST`<br>- Viết hai process trao đổi dữ liệu bằng pipe/FIFO hoặc shared memory. |
| 9 | Socket Programming | - TCP/UDP cơ bản.<br>- IP, port.<br>- `socket`, `bind`, `listen`, `accept`, `connect`.<br>- Client/server model. | **Môi trường:** `HOST`<br>- Viết TCP client/server bằng C.<br>- Kiểm tra socket bằng `ss`.<br>- Quan sát traffic bằng `tcpdump`. |

---

## Phase 2: Build Tools & Cross-Compilation

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | GCC Build Flow | - Preprocess → Compile → Assemble → Link.<br>- Object file và ELF.<br>- Symbol cơ bản. | **Môi trường:** `HOST`<br>- Build chương trình C theo từng bước.<br>- Dùng `file`, `readelf`, `nm`, `objdump`. |
| 2 | Native & Cross Toolchain | - Native compiler và cross compiler.<br>- GCC, assembler, linker, debugger.<br>- Target architecture.<br>- ABI/EABI và sysroot ở mức cơ bản. | **Môi trường:** `HOST`<br>- Cross-compile chương trình C cho ARM.<br>- So sánh binary host và target bằng `file`/`readelf`. |
| 3 | Static & Dynamic Library | - `.a` và `.so`.<br>- Static linking và dynamic linking.<br>- Runtime loader và library path cơ bản. | **Môi trường:** `HOST`<br>- Tạo thư viện `.a` và `.so`.<br>- Link vào application.<br>- Kiểm tra bằng `ldd`. |
| 4 | Makefile | - Target, dependency, recipe.<br>- Variable và compiler flags.<br>- Compile/link nhiều source file. | **Môi trường:** `HOST`<br>- Viết Makefile cho project C nhiều file.<br>- Thêm `all`, `clean` và dependency cơ bản. |
| 5 | CMake Fundamentals | - `CMakeLists.txt`.<br>- Target, source, include directory.<br>- Link library.<br>- Out-of-source build. | **Môi trường:** `HOST`<br>- Viết CMake cho project C nhỏ.<br>- Build trong thư mục `build/`. |
| 6 | GDB Fundamentals | - Breakpoint.<br>- Step/next.<br>- Register, variable, backtrace.<br>- Debug symbol. | **Môi trường:** `HOST`<br>- Debug chương trình C bằng GDB trên host.<br>- Phân tích segmentation fault đơn giản. |

---

## Phase 3: Embedded Linux Boot Architecture

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Embedded Linux Boot Flow | - BootROM → SPL/TPL nếu có → U-Boot → Linux Kernel → RootFS → init.<br>- Vai trò của từng thành phần.<br>- Boot media cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Quan sát boot log qua UART serial console.<br>- Chỉ ra từng giai đoạn trong boot log. |
| 2 | U-Boot Fundamentals | - U-Boot environment.<br>- `bootcmd`, `bootargs`.<br>- Load kernel và DTB.<br>- MMC/SD và TFTP ở mức cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Dừng autoboot và dùng U-Boot shell.<br>- Dùng `printenv`, `setenv`, `saveenv`.<br>- Boot kernel thủ công. |
| 3 | Linux Kernel Build | - Kernel source tree.<br>- `defconfig`, Kconfig, `menuconfig`.<br>- Built-in driver và kernel module.<br>- `Image`/`zImage`, modules. | **Môi trường:** `HOST`<br>- Cross-compile Linux kernel cho board.<br>- Thay đổi một kernel config.<br>- Boot kernel mới trên board. |
| 4 | Device Tree Fundamentals | - DTS, DTSI, DTB.<br>- Node và property.<br>- `compatible`, `reg`, `interrupts`, GPIO, clocks, pinctrl ở mức cơ bản.<br>- Device Tree mô tả phần cứng cho kernel. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Sửa trạng thái một peripheral trong DTS.<br>- Build DTB.<br>- Kiểm tra `/proc/device-tree`. |
| 5 | Root Filesystem | - Cấu trúc root filesystem.<br>- `/dev`, `/proc`, `/sys`.<br>- Device node.<br>- Shared libraries.<br>- Mount point. | **Môi trường:** `HOST`<br>- Tạo cấu trúc rootfs tối thiểu.<br>- Mount `proc`, `sysfs`, `devtmpfs` và kiểm tra nội dung. |
| 6 | BusyBox & Init | - Vai trò BusyBox.<br>- BusyBox applets.<br>- `init` và PID 1.<br>- BusyBox init cơ bản.<br>- Khái niệm service startup. | **Môi trường:** `HOST`<br>- Build và cài BusyBox vào rootfs.<br>- Tạo `/etc/inittab`/startup script đơn giản.<br>- Boot vào BusyBox shell. |
| 7 | systemd Basics | - Vai trò của init/service manager.<br>- Unit/service ở mức cơ bản.<br>- `systemctl`, `journalctl`.<br>- Không đi sâu quản trị systemd. | **Môi trường:** `HOST`<br>- Kiểm tra service trên một Linux system dùng systemd.<br>- Tạo service đơn giản cho application nếu board/distro hỗ trợ. |

---

## Phase 4: Build an Embedded Linux System from Scratch

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Build U-Boot | - Chọn defconfig cho board.<br>- Cross-build U-Boot.<br>- Boot media layout cơ bản. | **Môi trường:** `HOST`<br>- Build U-Boot cho target board.<br>- Boot và truy cập U-Boot console. |
| 2 | Build Kernel & DTB | - Kernel configuration.<br>- Kernel image.<br>- Kernel modules.<br>- Device Tree Blob. | **Môi trường:** `HOST`<br>- Build kernel, modules và DTB.<br>- Đưa các artifact lên boot partition hoặc qua TFTP. |
| 3 | Build BusyBox RootFS | - BusyBox configuration.<br>- Thư mục rootfs.<br>- Shared libraries và device files cần thiết. | **Môi trường:** `HOST`<br>- Tạo rootfs thủ công từ đầu.<br>- Cài BusyBox và các library cần thiết. |
| 4 | Full Boot Integration | - U-Boot truyền kernel command line.<br>- Kernel nhận DTB.<br>- Kernel mount rootfs.<br>- Init khởi chạy userspace. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Boot hoàn chỉnh: U-Boot → Kernel → DTB → RootFS → shell.<br>- Tự phân tích lỗi boot nếu hệ thống dừng ở một giai đoạn. |

---

## Phase 5: Buildroot Fundamentals

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Buildroot Overview | - Vai trò của embedded Linux build system.<br>- Toolchain, bootloader, kernel, rootfs, packages.<br>- `make menuconfig` và defconfig. | **Môi trường:** `HOST`<br>- Build một Linux image hoàn chỉnh bằng Buildroot.<br>- Boot image trên board. |
| 2 | RootFS Customization | - Root filesystem overlay.<br>- Custom configuration files.<br>- Post-build script ở mức cơ bản. | **Môi trường:** `HOST`<br>- Thêm file/config/application vào rootfs bằng overlay.<br>- Tạo startup script cho application. |
| 3 | Custom Application Package | - Buildroot package cơ bản.<br>- `Config.in` và `.mk` ở mức cần thiết.<br>- Dependency cơ bản. | **Môi trường:** `HOST`<br>- Đưa một application C tự viết vào Buildroot.<br>- Build application trực tiếp vào image. |
| 4 | Defconfig & Reproducible Build | - Lưu cấu hình board/project.<br>- Tái tạo image từ source và config. | **Môi trường:** `HOST`<br>- Tạo project defconfig.<br>- Clean build lại và xác minh image có thể tái tạo. |

---

## Phase 6: Linux Kernel Module & Device Driver Fundamentals

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Kernel Module Workflow | - Kernel module là gì.<br>- Built-in vs loadable module.<br>- Module init/exit.<br>- `insmod`, `rmmod`, `lsmod`, `modinfo`, `modprobe`, `depmod`.<br>- `dmesg`. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Viết `hello_module`.<br>- Build module ngoài kernel tree.<br>- Load/unload module và quan sát kernel log. |
| 2 | Character Device Driver | - Major/minor number.<br>- `cdev`.<br>- `file_operations`.<br>- `open`, `read`, `write`, `release`.<br>- Device node. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Viết character driver đơn giản.<br>- Tạo `/dev` node nếu cần.<br>- Viết userspace app read/write driver. |
| 3 | Linux Device Model | - Device, driver, bus, class.<br>- Quan hệ giữa `/sys`, device và driver.<br>- udev ở mức khái niệm.<br>- Driver binding cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Khám phá `/sys/bus`, `/sys/class`, `/sys/devices`.<br>- Xác định driver đang bind với một device. |
| 4 | Platform Driver | - `platform_device` và `platform_driver`.<br>- `probe()` và `remove()`.<br>- Resource management cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Viết platform driver tối giản.<br>- Quan sát khi `probe()` được gọi. |
| 5 | Device Tree Driver Matching | - `of_device_id`.<br>- `compatible` matching.<br>- Driver lấy resource từ Device Tree. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Thêm node vào DTS.<br>- Match Device Tree node với platform driver.<br>- Đọc một resource cơ bản từ DT. |
| 6 | GPIO Driver | - GPIO subsystem.<br>- GPIO descriptor API.<br>- Input/output cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Điều khiển LED hoặc đọc button bằng driver. |
| 7 | Interrupt Handling | - Polling vs interrupt.<br>- Interrupt handler.<br>- `request_irq`/`free_irq`.<br>- Không sleep/xử lý dài trong hard IRQ.<br>- Threaded IRQ/workqueue ở mức khái niệm. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Viết button driver dùng interrupt.<br>- So sánh với polling.<br>- Quan sát interrupt trong `/proc/interrupts`. |
| 8 | I2C Fundamentals | - I2C subsystem.<br>- `i2c_client`, `i2c_driver`.<br>- Device Tree matching.<br>- Userspace I2C tools. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Kiểm tra bus bằng `i2cdetect`.<br>- Giao tiếp với một I2C peripheral có sẵn driver hoặc driver đơn giản. |
| 9 | SPI Fundamentals | - SPI subsystem.<br>- `spi_device`, `spi_driver`.<br>- SPI transfer cơ bản.<br>- Device Tree matching. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Kiểm tra/giao tiếp với một SPI peripheral hoặc `spidev`.<br>- Hiểu đường đi từ DT đến SPI device/driver. |
| 10 | Userspace ↔ Driver Interface | - `read/write`.<br>- `ioctl` cơ bản.<br>- sysfs ở mức cơ bản.<br>- Khi nào dùng từng interface. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Thêm một command `ioctl` đơn giản hoặc một sysfs attribute vào driver học tập. |

---

## Phase 7: Board Bring-up & Hardware Integration

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Reading Hardware Information | - Đọc schematic ở mức cần cho software.<br>- SoC pin, GPIO, UART, I2C, SPI.<br>- Clock/reset/pinmux ở mức nhận biết.<br>- Mapping phần cứng sang Device Tree. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Từ schematic xác định một peripheral và các pin liên quan.<br>- Tìm node tương ứng trong DTS/DTSI. |
| 2 | Peripheral Bring-up | - Enable peripheral trong Device Tree.<br>- Kiểm tra driver probe.<br>- Kiểm tra `/dev`, `/sys` và kernel log. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Bring-up ít nhất UART + GPIO và một trong I2C/SPI.<br>- Xác minh peripheral hoạt động trên board thật. |
| 3 | Boot Bring-up | - Phân biệt lỗi U-Boot, kernel, DT và rootfs.<br>- Kernel command line.<br>- Root filesystem mount failure cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Đọc UART boot log.<br>- Chẩn đoán một lỗi boot có chủ đích như sai root device hoặc sai DTB. |
| 4 | Bring-up Checklist | - Bootloader.<br>- Kernel.<br>- RootFS.<br>- Console.<br>- Storage.<br>- GPIO/UART/I2C/SPI.<br>- Network cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Viết checklist bring-up cho board đang sử dụng.<br>- Ghi kết quả PASS/FAIL và log tương ứng. |

---

## Phase 8: Debugging Essentials

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Linux Runtime Debugging | - `ps`, `top`.<br>- `/proc` và `/sys`.<br>- `dmesg`.<br>- `journalctl` khi dùng systemd.<br>- `strace`. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Theo dõi process và tài nguyên.<br>- Dùng `strace` tìm lỗi open/read/write hoặc missing file/library. |
| 2 | Application Debugging on Target | - GDB/GDB server.<br>- Debug symbol.<br>- Backtrace.<br>- Remote debugging cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Chạy `gdbserver` trên target và GDB trên host để debug application. |
| 3 | Kernel/Driver Debugging | - `printk`/`pr_*`.<br>- `dmesg`.<br>- Module load failure.<br>- Probe failure.<br>- Kernel Oops ở mức nhận biết. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Debug driver bằng kernel log.<br>- Xác định nguyên nhân một module không load hoặc driver không probe. |
| 4 | Peripheral Debugging | - Kết hợp Device Tree, kernel log và userspace tools.<br>- UART serial console.<br>- Logic analyzer/oscilloscope ở mức hỗ trợ khi cần. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Debug một lỗi GPIO/I2C/SPI/UART theo chuỗi: hardware → DT → driver → userspace. |
| 5 | Networking Basics | - `ip addr`, `ip link`, `ip route`.<br>- Ping.<br>- DHCP/static IP.<br>- `ss`, `tcpdump`.<br>- Ethernet troubleshooting cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Cấu hình network cho board.<br>- SSH vào target.<br>- Dùng `tcpdump` kiểm tra traffic khi có lỗi. |

---

## Phase 9: Fresher Capstone Project

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Manual Linux Bring-up | - Toolchain.<br>- U-Boot.<br>- Kernel.<br>- DTB.<br>- BusyBox RootFS. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Tự build và boot một hệ thống Linux tối thiểu trên board ARM. |
| 2 | Buildroot System | - Tái tạo cùng hệ thống bằng Buildroot.<br>- Custom application.<br>- Rootfs customization. | **Môi trường:** `HOST`<br>- Build image bằng một lệnh từ project config.<br>- Application tự khởi động sau boot. |
| 3 | Hardware Integration | - Device Tree.<br>- Platform/device driver.<br>- GPIO/IRQ hoặc I2C/SPI. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Tích hợp ít nhất một peripheral thật.<br>- Viết userspace test app hoặc driver nhỏ phù hợp. |
| 4 | Debug & Documentation | - Boot flow.<br>- Kernel/user logs.<br>- Reproducible build.<br>- README và architecture description. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Ghi lại build/run/debug commands.<br>- Mô tả boot flow và data flow.<br>- Lưu các lỗi đã gặp và cách xác định nguyên nhân. |

---

# Kiến thức Fresher cần đạt sau roadmap

Sau khi hoàn thành phần cốt lõi, một Fresher Embedded Linux nên có thể:

- Sử dụng Linux command line và viết C trên Linux.
- Hiểu file descriptor, process, thread, signal, IPC và socket ở mức thực hành.
- Hiểu GCC build flow, Makefile/CMake và cross-compilation.
- Giải thích được boot flow: **BootROM → U-Boot → Kernel → Device Tree → RootFS → init**.
- Tự cross-build và boot U-Boot, Linux kernel, DTB và BusyBox rootfs.
- Dùng Buildroot để tạo một embedded Linux image có thể tái tạo.
- Hiểu kernel module, character driver, Linux Device Model và platform driver.
- Hiểu cách Device Tree match với driver và khi nào `probe()` được gọi.
- Làm việc cơ bản với GPIO, interrupt, I2C và SPI.
- Đọc UART boot log, `dmesg`, `/proc`, `/sys` và debug application bằng GDB/strace.
- Thực hiện board bring-up cơ bản và phân biệt lỗi nằm ở bootloader, kernel, Device Tree, rootfs hay application.

---

# Ngoài phạm vi bắt buộc của Fresher

Các chủ đề dưới đây **có giá trị nhưng không nên chặn tiến độ Fresher**. Học sau khi phần core phía trên đã chắc hoặc khi công việc yêu cầu:

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Yocto / OpenEmbedded | - BitBake, recipe, layer, MACHINE, DISTRO.<br>- Phù hợp khi công ty/project sử dụng Yocto. | **Môi trường:** `HOST`<br>- Build image mẫu và viết một recipe cơ bản sau khi đã hiểu Embedded Linux foundation. |
| 2 | Kernel Internals chuyên sâu | - VFS internals, page table, RCU, scheduler internals, network stack internals. | **Môi trường:** `HOST`<br>- Học theo nhu cầu driver/kernel cụ thể. |
| 3 | Advanced Driver Topics | - DMA, advanced locking, power management, complex kernel subsystems. | **Môi trường:** `HOST`<br>- Thực hành khi project phần cứng yêu cầu. |
| 4 | Production Embedded Linux | - OTA/A-B update.<br>- Secure Boot.<br>- Read-only rootfs.<br>- Boot-time optimization.<br>- PREEMPT_RT. | **Môi trường:** `HOST`<br>- Học khi chuyển sang product/production hoặc yêu cầu công việc cụ thể. |

---

## Luồng học đề xuất

```text
HOST — Ubuntu Laptop
    │
    ├── Linux Fundamentals / System Programming
    ├── GCC / Make / CMake / GDB
    ├── Cross Toolchain
    ├── Build U-Boot / Kernel / DTB / BusyBox RootFS
    └── Buildroot
            │
            │ deploy
            ▼
TARGET — BeagleBone Black
    │
    ├── Boot Flow / U-Boot
    ├── Device Tree verification
    ├── Kernel Module / Device Driver
    ├── GPIO / IRQ / I2C / SPI
    ├── Board Bring-up
    └── Debugging
            ↓
      Fresher Capstone Project
```

**Điểm kết thúc Fresher:** không cần biết mọi phần của Linux kernel. Quan trọng là có thể **build → boot → tích hợp hardware → debug** một hệ thống Embedded Linux cơ bản và giải thích rõ vì sao từng thành phần hoạt động.
