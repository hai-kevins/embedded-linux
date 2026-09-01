# Embedded Linux Roadmap — Fresher Level

Roadmap này tập trung vào **kiến thức cốt lõi mà một Fresher Embedded Linux theo hướng BSP / Kernel / Device Driver nên nắm**.  
Mục tiêu là hiểu được một hệ thống Embedded Linux xuyên suốt **Hardware / SoC → Bootloader → Kernel / Driver / BSP → RootFS / Build System → System Services / Middleware → Product / Application**, đồng thời có đủ kỹ năng thực hành để build, boot, tích hợp và debug trên board thật.

## Quy ước môi trường thực hành

- **HOST:** Laptop/PC Ubuntu dùng để viết code, native build, cross-compile, build U-Boot/Kernel/RootFS/Buildroot, chạy test phía development và tạo artifact/image.
- **TARGET — BeagleBone Black (BBB):** dùng cho Tầng 1 → 4: boot, U-Boot, Kernel, Device Tree, RootFS, kernel module/driver, peripheral, board bring-up và debug trên hardware thật.
- **TARGET — Raspberry Pi:** dùng cho Tầng 5 → 6: system service/daemon, middleware, IPC/network communication, product application và system integration trên target thật.
- **HOST + TARGET:** dùng khi một topic có workflow **develop/build/test trên HOST → deploy → run/verify/debug trên TARGET**. Đây là workflow ưu tiên khi phát triển Embedded Linux, thay vì viết/build toàn bộ trực tiếp trên target.

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
| 3 | Linux Kernel Build | - Kernel source tree.<br>- `defconfig`, Kconfig, `menuconfig`.<br>- Built-in driver và kernel module.<br>- `Image`/`zImage`, modules. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Cross-compile Linux kernel cho board.<br>- Thay đổi một kernel config.<br>- Boot kernel mới trên board. |
| 4 | Device Tree Fundamentals | - DTS, DTSI, DTB.<br>- Node và property.<br>- `compatible`, `reg`, `interrupts`, GPIO, clocks, pinctrl ở mức cơ bản.<br>- Device Tree mô tả phần cứng cho kernel. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Sửa trạng thái một peripheral trong DTS.<br>- Build DTB.<br>- Kiểm tra `/proc/device-tree`. |
| 5 | Root Filesystem | - Cấu trúc root filesystem.<br>- `/dev`, `/proc`, `/sys`.<br>- Device node.<br>- Shared libraries.<br>- Mount point. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Tạo cấu trúc rootfs tối thiểu.<br>- Mount `proc`, `sysfs`, `devtmpfs` và kiểm tra nội dung. |
| 6 | BusyBox & Init | - Vai trò BusyBox.<br>- BusyBox applets.<br>- `init` và PID 1.<br>- BusyBox init cơ bản.<br>- Khái niệm service startup. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Build và cài BusyBox vào rootfs.<br>- Tạo `/etc/inittab`/startup script đơn giản.<br>- Boot vào BusyBox shell. |
| 7 | systemd Basics | - Vai trò của init/service manager.<br>- Unit/service ở mức cơ bản.<br>- `systemctl`, `journalctl`.<br>- Không đi sâu quản trị systemd. | **Môi trường:** `HOST`<br>- Kiểm tra service trên một Linux system dùng systemd.<br>- Tạo service đơn giản cho application nếu board/distro hỗ trợ. |

---

## Phase 4: Build an Embedded Linux System from Scratch

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Build U-Boot | - Chọn defconfig cho board.<br>- Cross-build U-Boot.<br>- Boot media layout cơ bản. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Build U-Boot cho target board.<br>- Boot và truy cập U-Boot console. |
| 2 | Build Kernel & DTB | - Kernel configuration.<br>- Kernel image.<br>- Kernel modules.<br>- Device Tree Blob. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Build kernel, modules và DTB.<br>- Đưa các artifact lên boot partition hoặc qua TFTP. |
| 3 | Build BusyBox RootFS | - BusyBox configuration.<br>- Thư mục rootfs.<br>- Shared libraries và device files cần thiết. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Tạo rootfs thủ công từ đầu.<br>- Cài BusyBox và các library cần thiết. |
| 4 | Full Boot Integration | - U-Boot truyền kernel command line.<br>- Kernel nhận DTB.<br>- Kernel mount rootfs.<br>- Init khởi chạy userspace. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Boot hoàn chỉnh: U-Boot → Kernel → DTB → RootFS → shell.<br>- Tự phân tích lỗi boot nếu hệ thống dừng ở một giai đoạn. |

---

## Phase 5: Buildroot Fundamentals

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Buildroot Overview | - Vai trò của embedded Linux build system.<br>- Toolchain, bootloader, kernel, rootfs, packages.<br>- `make menuconfig` và defconfig. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Build một Linux image hoàn chỉnh bằng Buildroot.<br>- Boot image trên board. |
| 2 | RootFS Customization | - Root filesystem overlay.<br>- Custom configuration files.<br>- Post-build script ở mức cơ bản. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Thêm file/config/application vào rootfs bằng overlay trên HOST.<br>- Rebuild image, deploy và xác minh thay đổi trên BBB. |
| 3 | Custom Application Package | - Buildroot package cơ bản.<br>- `Config.in` và `.mk` ở mức cần thiết.<br>- Dependency cơ bản. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Đưa một application C tự viết vào Buildroot và build trực tiếp vào image trên HOST.<br>- Deploy image và xác minh application chạy trên BBB. |
| 4 | Defconfig & Reproducible Build | - Lưu cấu hình board/project.<br>- Tái tạo image từ source và config. | **Môi trường:** `HOST`<br>- Tạo project defconfig.<br>- Clean build lại và xác minh image có thể tái tạo. |

---

## Phase 6: Linux Kernel Module & Device Driver Fundamentals

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Kernel Module Workflow | - Kernel module là gì.<br>- Built-in vs loadable module.<br>- Module init/exit.<br>- `insmod`, `rmmod`, `lsmod`, `modinfo`, `modprobe`, `depmod`.<br>- `dmesg`. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Viết và cross-build `hello_module` trên HOST.<br>- Deploy sang BBB, load/unload module và quan sát kernel log. |
| 2 | Character Device Driver | - Major/minor number.<br>- `cdev`.<br>- `file_operations`.<br>- `open`, `read`, `write`, `release`.<br>- Device node. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Viết/cross-build character driver và userspace test app trên HOST.<br>- Deploy sang BBB, tạo `/dev` node nếu cần và kiểm tra `read/write`. |
| 3 | Linux Device Model | - Device, driver, bus, class.<br>- Quan hệ giữa `/sys`, device và driver.<br>- udev ở mức khái niệm.<br>- Driver binding cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Khám phá `/sys/bus`, `/sys/class`, `/sys/devices`.<br>- Xác định driver đang bind với một device. |
| 4 | Platform Driver | - `platform_device` và `platform_driver`.<br>- `probe()` và `remove()`.<br>- Resource management cơ bản. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Viết/cross-build platform driver trên HOST.<br>- Deploy sang BBB và quan sát khi `probe()` được gọi. |
| 5 | Device Tree Driver Matching | - `of_device_id`.<br>- `compatible` matching.<br>- Driver lấy resource từ Device Tree. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Thêm node vào DTS.<br>- Match Device Tree node với platform driver.<br>- Đọc một resource cơ bản từ DT. |
| 6 | GPIO Driver | - GPIO subsystem.<br>- GPIO descriptor API.<br>- Input/output cơ bản. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Điều khiển LED hoặc đọc button bằng driver. |
| 7 | Interrupt Handling | - Polling vs interrupt.<br>- Interrupt handler.<br>- `request_irq`/`free_irq`.<br>- Không sleep/xử lý dài trong hard IRQ.<br>- Threaded IRQ/workqueue ở mức khái niệm. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Viết button driver dùng interrupt.<br>- So sánh với polling.<br>- Quan sát interrupt trong `/proc/interrupts`. |
| 8 | I2C Fundamentals | - I2C subsystem.<br>- `i2c_client`, `i2c_driver`.<br>- Device Tree matching.<br>- Userspace I2C tools. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Kiểm tra bus bằng `i2cdetect`.<br>- Giao tiếp với một I2C peripheral có sẵn driver hoặc driver đơn giản. |
| 9 | SPI Fundamentals | - SPI subsystem.<br>- `spi_device`, `spi_driver`.<br>- SPI transfer cơ bản.<br>- Device Tree matching. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Kiểm tra/giao tiếp với một SPI peripheral hoặc `spidev`.<br>- Hiểu đường đi từ DT đến SPI device/driver. |
| 10 | Userspace ↔ Driver Interface | - `read/write`.<br>- `ioctl` cơ bản.<br>- sysfs ở mức cơ bản.<br>- Khi nào dùng từng interface. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Thêm một command `ioctl` đơn giản hoặc một sysfs attribute vào driver học tập. |

---

## Phase 7: Board Bring-up & Hardware Integration

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Reading Hardware Information | - Đọc schematic ở mức cần cho software.<br>- SoC pin, GPIO, UART, I2C, SPI.<br>- Clock/reset/pinmux ở mức nhận biết.<br>- Mapping phần cứng sang Device Tree. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Từ schematic xác định một peripheral và các pin liên quan.<br>- Tìm node tương ứng trong DTS/DTSI. |
| 2 | Peripheral Bring-up | - Enable peripheral trong Device Tree.<br>- Kiểm tra driver probe.<br>- Kiểm tra `/dev`, `/sys` và kernel log. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Chuẩn bị DTS/DTB hoặc artifact trên HOST khi cần.<br>- Bring-up ít nhất UART + GPIO và một trong I2C/SPI, sau đó xác minh trên board thật. |
| 3 | Boot Bring-up | - Phân biệt lỗi U-Boot, kernel, DT và rootfs.<br>- Kernel command line.<br>- Root filesystem mount failure cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Đọc UART boot log.<br>- Chẩn đoán một lỗi boot có chủ đích như sai root device hoặc sai DTB. |
| 4 | Bring-up Checklist | - Bootloader.<br>- Kernel.<br>- RootFS.<br>- Console.<br>- Storage.<br>- GPIO/UART/I2C/SPI.<br>- Network cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Viết checklist bring-up cho board đang sử dụng.<br>- Ghi kết quả PASS/FAIL và log tương ứng. |

---

## Phase 8: Debugging Essentials

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Linux Runtime Debugging | - `ps`, `top`.<br>- `/proc` và `/sys`.<br>- `dmesg`.<br>- `journalctl` khi dùng systemd.<br>- `strace`. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Theo dõi process và tài nguyên.<br>- Dùng `strace` tìm lỗi open/read/write hoặc missing file/library. |
| 2 | Application Debugging on Target | - GDB/GDB server.<br>- Debug symbol.<br>- Backtrace.<br>- Remote debugging cơ bản. | **Môi trường:** `HOST + TARGET — BeagleBone Black`<br>- Chạy `gdbserver` trên target và GDB trên host để debug application. |
| 3 | Kernel/Driver Debugging | - `printk`/`pr_*`.<br>- `dmesg`.<br>- Module load failure.<br>- Probe failure.<br>- Kernel Oops ở mức nhận biết. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Debug driver bằng kernel log.<br>- Xác định nguyên nhân một module không load hoặc driver không probe. |
| 4 | Peripheral Debugging | - Kết hợp Device Tree, kernel log và userspace tools.<br>- UART serial console.<br>- Logic analyzer/oscilloscope ở mức hỗ trợ khi cần. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Debug một lỗi GPIO/I2C/SPI/UART theo chuỗi: hardware → DT → driver → userspace. |
| 5 | Networking Basics | - `ip addr`, `ip link`, `ip route`.<br>- Ping.<br>- DHCP/static IP.<br>- `ss`, `tcpdump`.<br>- Ethernet troubleshooting cơ bản. | **Môi trường:** `TARGET — BeagleBone Black`<br>- Cấu hình network cho board.<br>- SSH vào target.<br>- Dùng `tcpdump` kiểm tra traffic khi có lỗi. |

---

## Phase 9: System Services & Daemon Development

> Từ Phase 9 → 12, source code/config ưu tiên được quản lý và build/test trên **HOST**, sau đó deploy sang **Raspberry Pi** để integration, hardware access và runtime debugging. Native build trực tiếp trên Pi vẫn có thể dùng cho thử nghiệm nhanh nhưng không phải workflow chính của roadmap.

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Linux Daemon Fundamentals | - Daemon là gì và vai trò trong Embedded Linux.<br>- Foreground process vs background service.<br>- Vòng đời của long-running process.<br>- Graceful shutdown bằng signal. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Viết một daemon C chạy liên tục.<br>- Xử lý `SIGTERM`/`SIGINT` để shutdown đúng cách.<br>- Ghi log khi daemon start/stop. |
| 2 | systemd Service | - Service unit.<br>- `ExecStart`, `Restart`, `After`, `WantedBy`.<br>- Enable/start/stop/restart service.<br>- Quan sát trạng thái service. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Đưa daemon thành `systemd service`.<br>- Enable service tự chạy khi boot.<br>- Kiểm tra bằng `systemctl status` và `journalctl`. |
| 3 | Service Configuration | - File cấu hình cho service.<br>- Command-line argument.<br>- Environment variable cơ bản.<br>- Không hard-code cấu hình vào source. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Cho daemon đọc file cấu hình trong `/etc`.<br>- Thay đổi cấu hình mà không cần compile lại chương trình. |
| 4 | Logging | - Log level cơ bản: debug/info/warning/error.<br>- stdout/stderr và journal.<br>- Timestamp và thông tin lỗi cần thiết.<br>- Không spam log. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Thêm logging cho daemon.<br>- Dùng `journalctl` để debug lỗi service. |
| 5 | Service Reliability | - Restart service khi process crash.<br>- Timeout cơ bản.<br>- Resource cleanup.<br>- Tránh daemon chết âm thầm. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Chủ động làm daemon exit lỗi.<br>- Cấu hình systemd tự restart.<br>- Kiểm tra service phục hồi đúng. |

---

## Phase 10: Middleware & Device Communication

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | IPC in Embedded Product | - Chọn IPC phù hợp giữa các process.<br>- Unix Domain Socket.<br>- Pipe/FIFO và shared memory ở mức ứng dụng.<br>- Phân biệt IPC nội bộ và network communication. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Tạo hai process trao đổi dữ liệu bằng Unix Domain Socket.<br>- Một process giả lập hardware service, một process làm application. |
| 2 | Hardware Access Service | - Tách hardware access khỏi application.<br>- Một service chịu trách nhiệm đọc/ghi peripheral.<br>- Application giao tiếp với hardware service qua interface rõ ràng. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Viết hardware daemon đọc GPIO/I2C/UART hoặc dữ liệu giả lập.<br>- Application lấy dữ liệu qua IPC. |
| 3 | MQTT Fundamentals | - Publisher/subscriber.<br>- Broker.<br>- Topic.<br>- QoS ở mức khái niệm.<br>- Retained message và connection lifecycle cơ bản. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Cài MQTT broker hoặc kết nối broker trong mạng lab.<br>- Publish dữ liệu sensor.<br>- Subscribe command từ một client khác. |
| 4 | MQTT Application Integration | - Tích hợp MQTT client vào application/service.<br>- Reconnect khi mất broker.<br>- Tách network logic khỏi hardware logic. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Gửi telemetry qua MQTT.<br>- Tắt broker/network rồi bật lại và kiểm tra reconnect. |
| 5 | HTTP/REST Basics | - HTTP request/response.<br>- GET/POST ở mức cơ bản.<br>- JSON payload.<br>- Khi nào dùng HTTP và khi nào dùng MQTT. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Gửi trạng thái thiết bị tới HTTP endpoint hoặc viết API nhỏ để đọc trạng thái thiết bị.<br>- Không yêu cầu backend phức tạp. |
| 6 | Data Serialization | - Text vs binary data.<br>- JSON ở mức thực hành.<br>- Thiết kế message đơn giản.<br>- Version field và error field cơ bản. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Định nghĩa JSON message cho telemetry và command.<br>- Parse/validate message trong application. |
| 7 | Device State & Error Handling | - Online/offline state.<br>- Hardware error.<br>- Network error.<br>- Retry và timeout cơ bản.<br>- Không để một lỗi làm treo toàn bộ hệ thống. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Vô hiệu hóa peripheral/network có chủ đích.<br>- Kiểm tra service ghi log, retry hoặc chuyển sang trạng thái lỗi hợp lý. |

---

## Phase 11: Product Application & System Integration

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Embedded Application Architecture | - Phân tách hardware, service/middleware và application.<br>- Data flow giữa các thành phần.<br>- Tránh viết toàn bộ hệ thống trong một process lớn. | **Môi trường:** `HOST`<br>- Thiết kế architecture cho project nhỏ.<br>- Vẽ data flow từ hardware đến application/network. |
| 2 | Application State Machine | - State machine cho trạng thái thiết bị.<br>- INIT, RUNNING, ERROR, RECOVERY cơ bản.<br>- Event-driven processing ở mức đơn giản. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Xây state machine cho application.<br>- Thử hardware/network failure và quan sát state transition. |
| 3 | Configuration & Persistent State | - Runtime configuration.<br>- Persistent configuration.<br>- Lưu trạng thái nhỏ vào filesystem.<br>- Khôi phục cấu hình khi reboot. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Lưu một số cấu hình thiết bị.<br>- Reboot Pi và xác minh application đọc lại đúng cấu hình. |
| 4 | Startup & Shutdown Flow | - Thứ tự khởi động service.<br>- Dependency giữa các service.<br>- Graceful shutdown.<br>- Hardware cleanup khi shutdown. | **Môi trường:** `TARGET — Raspberry Pi`<br>- Thiết lập systemd dependency giữa các service.<br>- Reboot/shutdown và kiểm tra log khởi động/dừng. |
| 5 | Runtime Monitoring | - CPU, RAM, process state.<br>- Service status.<br>- Application health ở mức cơ bản.<br>- Không đi sâu observability/cloud monitoring. | **Môi trường:** `TARGET — Raspberry Pi`<br>- Theo dõi bằng `top`, `ps`, `/proc`, `systemctl`, `journalctl`.<br>- Xác định một lỗi CPU/RAM/process đơn giản. |
| 6 | System Integration Test | - Kiểm tra end-to-end.<br>- Hardware → service → middleware → application.<br>- Boot test.<br>- Network failure test.<br>- Service restart test. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Viết checklist PASS/FAIL cho toàn bộ hệ thống.<br>- Test reboot, mất network và restart service. |

---

## Phase 12: Product Reliability & Integration Completion

| # | Tên topic | Nội dung | Thực hành |
|---|---|---|---|
| 1 | Hardware Integration | - Raspberry Pi giao tiếp với một peripheral thật hoặc MCU.<br>- UART/I2C/SPI/GPIO tùy project.<br>- Luồng dữ liệu từ hardware lên service. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Thu dữ liệu thực từ sensor hoặc MCU.<br>- Kiểm tra dữ liệu ở hardware interface và service. |
| 2 | Service-to-Application Integration | - Hardware service.<br>- IPC nội bộ.<br>- Application logic.<br>- Interface giữa các process rõ ràng. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Nối hardware service với application qua IPC.<br>- Kiểm tra dữ liệu/command hai chiều. |
| 3 | Network Integration | - MQTT hoặc HTTP.<br>- Telemetry và command.<br>- Reconnect/timeout cơ bản.<br>- Message format rõ ràng. | **Môi trường:** `HOST + TARGET — Raspberry Pi`<br>- Gửi telemetry ra network.<br>- Nhận command từ client và chuyển xuống application/hardware service. |
| 4 | Boot-to-Application Integration | - Hệ thống hoạt động sau khi cấp nguồn mà không cần thao tác thủ công.<br>- systemd dependency.<br>- Service startup order.<br>- Recovery cơ bản. | **Môi trường:** `TARGET — Raspberry Pi`<br>- Power on → Linux boot → services start → application hoạt động.<br>- Không cần SSH để start chương trình thủ công. |
| 5 | Failure & Recovery Test | - Service crash.<br>- Mất network.<br>- Peripheral lỗi/mất kết nối.<br>- Logging và recovery cơ bản. | **Môi trường:** `TARGET — Raspberry Pi`<br>- Tạo ít nhất ba lỗi có chủ đích.<br>- Xác minh hệ thống log đúng, không treo và phục hồi theo thiết kế. |
| 6 | Documentation & Reproducibility | - Architecture.<br>- Data flow.<br>- Build/run/deploy procedure.<br>- Reproducibility.<br>- Known limitations.<br>- Test checklist. | **Môi trường:** `HOST`<br>- Hoàn thiện README, architecture và data flow của hệ thống.<br>- Từ source/config có thể build/deploy lại theo tài liệu và lưu checklist PASS/FAIL cuối cùng. |

---


# Kiến thức Fresher cần đạt sau roadmap

Sau khi hoàn thành toàn bộ roadmap, một Fresher Embedded Linux nên có thể:

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
- Viết Linux daemon và quản lý bằng `systemd`.
- Tổ chức configuration, logging, graceful shutdown và restart policy cho service.
- Dùng IPC để giao tiếp giữa các process và tách hardware access khỏi application logic ở mức cơ bản.
- Giao tiếp với hệ thống bên ngoài bằng MQTT hoặc HTTP ở mức ứng dụng Embedded/IoT.
- Xử lý network disconnect/reconnect, timeout và lỗi hardware cơ bản.
- Xây application có state machine và persistent configuration đơn giản.
- Tích hợp **hardware → driver/BSP → rootfs → service/middleware → product application** thành một hệ thống end-to-end.
- Thiết lập hệ thống tự hoạt động sau boot mà không cần start application thủ công.
- Debug end-to-end bằng boot log, kernel log, service log, process/network tools và application log.
- Xác định lỗi theo đúng tầng thay vì debug toàn hệ thống một cách mù quáng.
- Giải thích được architecture, boot flow và data flow của một Embedded Linux product cơ bản xuyên suốt cả 6 tầng.

---

## Luồng học đề xuất

```text
PHASE 1 → 8
HOST + TARGET — BeagleBone Black
    │
    ├── Linux Fundamentals / System Programming
    ├── GCC / Make / CMake / GDB
    ├── Cross Toolchain
    ├── U-Boot / Kernel / Device Tree
    ├── BusyBox RootFS / Buildroot
    ├── Kernel Module / Device Driver
    ├── GPIO / IRQ / I2C / SPI
    ├── Board Bring-up
    └── Debugging
            │
            ▼
      Hoàn thành Tầng 1 → 4
            │
            ▼
PHASE 9 → 12
HOST + TARGET — Raspberry Pi
    │
    ├── System Services / Daemon
    ├── systemd / Logging / Reliability
    ├── IPC / Hardware Access Service
    ├── MQTT / HTTP / Data Serialization
    ├── Product Application / State Machine
    └── Product Integration / Failure & Recovery
            │
            ▼
      Hoàn thành Tầng 5 → 6
            │
            ▼
   Embedded Linux Fresher
```

**Điểm kết thúc Fresher:** không cần biết mọi phần của Linux kernel hay các kiến trúc cloud/production phức tạp. Quan trọng là có thể **build → boot → tích hợp hardware → xây service/middleware → chạy product application → debug end-to-end**, đồng thời xác định được lỗi nằm ở tầng nào và giải thích rõ vai trò của từng tầng.

## Kiến trúc Embedded Linux

```text
┌──────────────────────────────────┐
│ 6. PRODUCT / APPLICATION         │ ← Phase 11–12 / HOST + Raspberry Pi
├──────────────────────────────────┤
│ 5. SYSTEM SERVICES / MIDDLEWARE  │ ← Phase 9–10, 12 / HOST + Raspberry Pi
├──────────────────────────────────┤
│ 4. ROOTFS / BUILD SYSTEM         │ ← Phase 3–5 / HOST + BBB
├──────────────────────────────────┤
│ 3. KERNEL / DRIVER / BSP         │ ← Phase 3, 6–8 / HOST + BBB
├──────────────────────────────────┤
│ 2. BOOTLOADER                    │ ← Phase 3–4 / HOST + BBB
├──────────────────────────────────┤
│ 1. HARDWARE / SoC                │ ← Phase 6–8 / BBB
└──────────────────────────────────┘
```
