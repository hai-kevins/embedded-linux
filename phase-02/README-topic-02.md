# Chủ đề 2 — Native & Cross Toolchain

> **Mục tiêu:** Hiểu bản chất của native compilation và cross-compilation trong Embedded Linux; phân biệt rõ máy đang chạy toolchain với hệ thống mà binary được tạo ra để chạy; hiểu vai trò của target architecture, ABI, target tuple/prefix, C library, runtime support và sysroot; xây dựng mental model đủ chắc để đọc tên cross toolchain, suy luận lỗi không tương thích và chuẩn bị cho các chủ đề Library, Makefile, CMake ở phía sau.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các thuật ngữ cần tra cứu đúng theo tài liệu GCC/GNU Binutils/Autoconf/Arm ABI như `native compiler`, `cross compiler`, `build`, `host`, `target`, `target tuple`, `toolchain prefix`, `ISA`, `ABI`, `calling convention`, `sysroot`, `C library`, `runtime`, `multilib` được giữ nguyên bằng tiếng Anh và giải thích tại vị trí phù hợp.
>
> **Phạm vi:** Native toolchain và cross toolchain trên Linux, mô hình `build/host/target`, target tuple/prefix, kiến trúc và ABI, thành phần chính của GNU toolchain, C library/runtime ở mức cần thiết, sysroot, quá trình chọn header/library và các dạng không tương thích thường gặp. Static/shared library sẽ học ở Chủ đề 3; Makefile/CMake sẽ học ở Chủ đề 4–5; remote debugging và GDB sẽ học ở Chủ đề 6.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để xây dựng mô hình tư duy về cross-development trong Embedded Linux. Không có bài thực hành.

Ở Chủ đề 1, luồng build đã được mô hình hóa thành:

```text
C source
   |
   v
Preprocess
   |
   v
Compile
   |
   v
Assemble
   |
   v
Object file
   |
   v
Link
   |
   v
ELF output
```

Pipeline đó chưa trả lời một câu hỏi rất quan trọng trong Embedded Linux:

> **Machine code bên trong ELF được tạo ra để chạy trên máy nào?**

Trên một máy tính phát triển x86-64, lệnh `gcc` thông thường thường tạo code x86-64 để chạy ngay trên chính hệ thống đó. Nhưng khi phát triển cho một board AArch64, compiler vẫn có thể chạy trên máy x86-64 trong khi machine code mà nó sinh ra lại dành cho AArch64.

Mô hình trung tâm của chương này là:

```text
Development machine
x86-64 Linux
      |
      | chạy cross toolchain
      v
+---------------------------+
| aarch64-linux-gnu-gcc     |
| assembler / linker / ...  |
+---------------------------+
      |
      | tạo code theo target
      v
AArch64 Linux ELF
      |
      | triển khai sang thiết bị
      v
Target board
AArch64 Linux
```

> **Đọc sơ đồ:** Toolchain là chương trình đang chạy trên development machine, nhưng output của toolchain được tạo theo kiến trúc và ABI của target. Đây chính là điểm cốt lõi của cross-compilation.

Hiểu được sự tách biệt này là nền tảng để lý giải vì sao Embedded Linux thường cần các executable như `aarch64-linux-gnu-gcc`, vì sao có sysroot, vì sao header/library của máy phát triển không thể tùy ý dùng cho target, và vì sao một ELF hoàn toàn hợp lệ vẫn có thể không chạy được trên máy đang build nó.

---

## Mục lục

- [1. Toolchain là gì?](#1-toolchain-là-gì)
- [2. Native compilation và cross-compilation](#2-native-compilation-và-cross-compilation)
- [3. `build`, `host`, `target`: ba khái niệm dễ nhầm](#3-build-host-target-ba-khái-niệm-dễ-nhầm)
- [4. Target tuple và toolchain prefix](#4-target-tuple-và-toolchain-prefix)
- [5. Architecture, ISA, CPU và ABI khác nhau như thế nào?](#5-architecture-isa-cpu-và-abi-khác-nhau-như-thế-nào)
- [6. ABI quyết định những gì?](#6-abi-quyết-định-những-gì)
- [7. Một GNU cross toolchain gồm những thành phần nào?](#7-một-gnu-cross-toolchain-gồm-những-thành-phần-nào)
- [8. C library, runtime support và startup files](#8-c-library-runtime-support-và-startup-files)
- [9. Sysroot là gì?](#9-sysroot-là-gì)
- [10. Toolchain tìm header và library của target như thế nào?](#10-toolchain-tìm-header-và-library-của-target-như-thế-nào)
- [11. Cross-build diễn ra như thế nào?](#11-cross-build-diễn-ra-như-thế-nào)
- [12. Vì sao binary của target thường không chạy trực tiếp trên host?](#12-vì-sao-binary-của-target-thường-không-chạy-trực-tiếp-trên-host)
- [13. Những lớp tương thích phải đồng thời khớp](#13-những-lớp-tương-thích-phải-đồng-thời-khớp)
- [14. Linux cross toolchain và bare-metal toolchain không giống nhau](#14-linux-cross-toolchain-và-bare-metal-toolchain-không-giống-nhau)
- [15. `-march`, `-mcpu`, `-mtune` và multilib ở mức nền tảng](#15--march--mcpu--mtune-và-multilib-ở-mức-nền-tảng)
- [16. Tư duy chẩn đoán lỗi cross-compilation](#16-tư-duy-chẩn-đoán-lỗi-cross-compilation)
- [17. Liên hệ với Embedded Linux](#17-liên-hệ-với-embedded-linux)
- [18. Tổng kết và mô hình tư duy](#18-tổng-kết-và-mô-hình-tư-duy)
- [19. Tài liệu tham khảo](#19-tài-liệu-tham-khảo)

---

## 1. Toolchain là gì?

`Toolchain` là một tập hợp các công cụ phối hợp với nhau để biến source code thành binary và xử lý các binary đó trong quá trình phát triển phần mềm.

Trong ngữ cảnh C/C++ trên Linux, một toolchain điển hình có thể bao gồm:

```text
Source code
    |
    v
Compiler driver
    |
    +--> Preprocessor
    |
    +--> Compiler proper
    |
    +--> Assembler
    |
    +--> Linker
    |
    v
ELF / object / library

Các công cụ hỗ trợ:
    ar
    ranlib
    nm
    objdump
    objcopy
    strip
    readelf
    ...
```

Ở phạm vi rộng hơn, khi nói đến một **cross toolchain hoàn chỉnh cho Linux**, người ta thường còn quan tâm tới:

```text
Compiler + Binutils
       +
Target headers
       +
Target C library
       +
Runtime support
       +
Sysroot
```

Vì vậy từ `toolchain` có thể được dùng theo hai mức:

| Cách dùng | Ý nghĩa thường gặp |
|---|---|
| Nghĩa hẹp | Compiler, assembler, linker và các binary utilities |
| Nghĩa rộng | Các công cụ trên cộng với target headers, C library, runtime, sysroot và cấu hình target |

Trong Embedded Linux, nghĩa rộng thường hữu ích hơn vì chỉ có compiler chưa đủ để build một chương trình userspace thực tế.

Ví dụ, một compiler có thể biết cách sinh instruction AArch64 nhưng nếu không có bộ header và library phù hợp với Linux userspace trên target thì nó vẫn chưa tạo thành một môi trường cross-development hoàn chỉnh.

> **Điểm cần nhớ:** Toolchain không chỉ trả lời câu hỏi "sinh instruction cho CPU nào?". Với Linux userspace, nó còn phải phù hợp với ABI, object format, C library và môi trường runtime của target.

---

## 2. Native compilation và cross-compilation

### 2.1 Native compilation

`Native compilation` là quá trình dịch mã nguồn của một chương trình máy tính thành mã máy (mã nhị phân) để chạy trực tiếp trên cấu trúc phần cứng và hệ điều hành của chính máy tính đó mà không cần qua trình thông dịch hay máy ảo.
Ví dụ khái quát:

```text
Machine đang chạy compiler
x86-64 Linux
      |
      | gcc
      v
x86-64 Linux ELF
      |
      v
chạy trên x86-64 Linux
```

Trong mô hình đơn giản này:

```text
Machine chạy compiler  ~=  Machine chạy output
```

Dấu `~=` ở đây nhằm nhấn mạnh rằng "giống nhau" không chỉ là tên CPU. Binary còn phải phù hợp với các điều kiện runtime cần thiết như ABI và library.

### 2.2 Cross-compilation

`Cross-compilation` xảy ra khi compiler/toolchain chạy trên một loại hệ thống nhưng tạo code cho một target khác.

Ví dụ rất phổ biến trong Embedded Linux:

```text
Development host
x86-64 Linux
      |
      | aarch64-linux-gnu-gcc
      v
AArch64 Linux ELF
      |
      v
Embedded target
AArch64 Linux
```

Ở đây:

```text
Machine chạy compiler  !=  Machine mà output được tạo ra để chạy
```

Đây là lý do người phát triển có thể sử dụng một workstation mạnh để build phần mềm cho một board nhúng có CPU khác hoàn toàn.

### 2.3 Cross-compilation không thay đổi build pipeline

Điều rất quan trọng là cross-compilation **không tạo ra một pipeline build mới**.

Pipeline vẫn là:

```text
Preprocess
    -> Compile
    -> Assemble
    -> Link
```

Điểm thay đổi nằm ở target:

```text
Native:
C source
   -> compiler cho x86-64 Linux
   -> x86-64 object
   -> x86-64 ELF

Cross:
C source
   -> compiler cho AArch64 Linux
   -> AArch64 object
   -> AArch64 ELF
```

Preprocessor vẫn xử lý macro/header. Compiler vẫn phân tích C. Assembler vẫn tạo object file. Linker vẫn giải quyết symbol và relocation.

Nhưng machine code, ABI, object metadata và các library được chọn phải hướng về target thay vì development machine.

### 2.4 Cross-compilation không có nghĩa source code tự động portable

Một source file C có thể được compiler chấp nhận trên nhiều architecture, nhưng điều đó không đảm bảo chương trình có cùng hành vi ở mọi target.

Source có thể phụ thuộc vào:

- kích thước kiểu dữ liệu;
- alignment;
- endianness;
- assumption về instruction/CPU feature;
- API chỉ có trên một hệ điều hành;
- layout của structure khi trao đổi dữ liệu nhị phân;
- behavior phụ thuộc ABI;
- library hoặc device interface chỉ tồn tại trên target cụ thể.

Do đó:

```text
Cross compiler chạy thành công
            !=
Chương trình chắc chắn portable và chạy đúng trên target
```

Cross-compilation chỉ giải quyết bài toán **tạo binary cho target**. Tính portable của source là một vấn đề rộng hơn.

---

## 3. `build`, `host`, `target`: ba khái niệm dễ nhầm

Các từ `build`, `host`, `target` xuất hiện rất nhiều trong GCC, Autoconf và tài liệu cross-compilation. Chúng đặc biệt dễ gây nhầm vì từ `host` trong hội thoại Embedded Linux hằng ngày không phải lúc nào cũng được dùng đúng theo nghĩa của GNU build system.

### 3.1 Nghĩa chuẩn khi xây dựng một compiler/toolchain

Khi đang **build chính compiler**, ba hệ thống có thể được hiểu như sau:

```text
BUILD
Máy thực hiện quá trình build compiler
        |
        v
HOST
Máy mà compiler sau khi build sẽ chạy trên đó
        |
        v
TARGET
Máy/kiến trúc mà compiler đó sẽ sinh code cho
```

Ví dụ:

```text
Build machine : x86-64 Linux
Host machine  : x86-64 Linux
Target        : AArch64 Linux
```

Kết quả là một compiler:

```text
chạy trên x86-64 Linux
nhưng sinh code cho AArch64 Linux
```

Đây là cross compiler điển hình dùng trong phát triển Embedded Linux.

### 3.2 Vì sao cần cả `build` và `host`?

Trong trường hợp thông thường:

```text
build == host
```

nên hai khái niệm dễ bị tưởng là một.

Nhưng về nguyên tắc, có thể xảy ra:

```text
build != host != target
```

Ví dụ về mặt mô hình:

```text
Compiler được build trên:       x86-64 Linux
Compiler sau đó chạy trên:       AArch64 Linux
Compiler sinh code cho:          một target khác
```

Trường hợp phức tạp kiểu này thường được gọi là `Canadian Cross`. Ở mức chủ đề này chỉ cần biết nó giải thích vì sao GNU toolchain phân biệt ba vai trò riêng biệt; chưa cần đi sâu vào quy trình tạo Canadian Cross.

### 3.3 Với một application thông thường, `host` có nghĩa hơi khác trực giác

Khi dùng Autoconf để build **một chương trình ứng dụng**, `host` là hệ thống mà chương trình được build ra sẽ chạy trên đó.

Ví dụ:

```text
Đang build application trên x86-64
            |
            | cross compile
            v
Application sẽ chạy trên AArch64
```

Theo thuật ngữ Autoconf:

```text
build = x86_64-...
host  = aarch64-...
```

`target` chủ yếu có ý nghĩa riêng khi package đang build là một compiler hoặc công cụ sinh code cho một target khác.

Do đó cần phân biệt hai ngữ cảnh:

```text
Ngữ cảnh Embedded hằng ngày:
"host PC"   = máy phát triển
"target"    = board nhúng

Ngữ cảnh GNU configure:
build       = máy thực hiện build
host        = máy chạy chương trình đang được build
target      = máy mà công cụ đang được build sẽ sinh code cho
```

> **Ghi nhớ:** Không nên lấy nghĩa đời thường của từ `host` rồi áp thẳng vào mọi tùy chọn `--host` của GNU build system.

### 3.4 Mô hình cần dùng trong phần còn lại của chương

Để tránh làm phần giải thích trở nên nặng nề, khi nói về việc **sử dụng một cross toolchain đã có sẵn**, chương này chủ yếu dùng mô hình:

```text
Development machine / build machine
              |
              | chạy cross compiler
              v
           TARGET
     nơi binary sẽ chạy
```

Khi thuật ngữ GNU `build/host/target` được dùng theo nghĩa chính thức, ngữ cảnh sẽ được nói rõ.

---

## 4. Target tuple và toolchain prefix

Khi cài cross toolchain trên Linux, rất thường gặp các tên như:

```text
aarch64-linux-gnu-gcc
arm-linux-gnueabihf-gcc
arm-none-eabi-gcc
```

Phần đứng trước `gcc` thường được gọi trong thực tế là `toolchain prefix` hoặc liên hệ với một `target tuple/triplet`.

### 4.1 Target tuple dùng để mô tả cấu hình hệ thống

GNU configuration sử dụng một tên chuẩn hóa để mô tả loại hệ thống. Tài liệu Autoconf thường mô tả dạng khái quát:

```text
cpu-vendor-os
```

trong đó phần `os` có thể bản thân chứa thông tin theo dạng:

```text
kernel-system
```

Vì vậy không nên hiểu chữ "triplet" theo kiểu máy móc rằng **mọi tên luôn có đúng ba chuỗi được ngăn bởi hai dấu `-`**.

Ví dụ các tên thực tế có thể trông như:

```text
x86_64-pc-linux-gnu
aarch64-linux-gnu
arm-linux-gnueabihf
```

Điều quan trọng hơn số lượng dấu `-` là: tên đó mô tả **target configuration đã được canonicalize hoặc quy ước bởi toolchain/distribution**.

### 4.2 Đọc `aarch64-linux-gnu-gcc` ở mức cần thiết

Có thể hình dung:

```text
aarch64-linux-gnu-gcc
|       |     |   |
|       |     |   +-- GCC driver
|       |     +------ GNU userspace / ABI environment
|       +------------ Linux target environment
+-------------------- AArch64 CPU architecture family
```

Đây là cách đọc **theo ý nghĩa thực tế**, không phải quy tắc parser chính thức rằng mỗi đoạn luôn ánh xạ 1:1 vào một trường cố định.

Điều cần rút ra là:

```text
aarch64-linux-gnu-gcc
```

không đơn giản là một bản `gcc` được đổi tên. Nó là GCC được cấu hình để tạo code cho một target cụ thể.

### 4.3 Toolchain prefix tạo thành một họ công cụ

Nếu prefix là:

```text
aarch64-linux-gnu-
```

thì thường có thể gặp một họ công cụ như:

```text
aarch64-linux-gnu-gcc
aarch64-linux-gnu-as
aarch64-linux-gnu-ld
aarch64-linux-gnu-ar
aarch64-linux-gnu-ranlib
aarch64-linux-gnu-objdump
aarch64-linux-gnu-objcopy
aarch64-linux-gnu-strip
aarch64-linux-gnu-nm
aarch64-linux-gnu-readelf
```

Prefix giúp build system chọn **một bộ công cụ cùng hướng về target**, thay vì vô tình trộn native compiler với cross assembler/linker.

Mô hình:

```text
                 aarch64-linux-gnu-
                          |
        +-----------------+-----------------+
        |                 |                 |
       gcc                as                ld
        |                 |                 |
        +-----------------+-----------------+
                          |
                          v
                    AArch64 target
```

### 4.4 `-dumpmachine` cho biết target được cấu hình của GCC

GCC có option:

```text
gcc -dumpmachine
```

để in target machine mà compiler được cấu hình cho.

Ý nghĩa lý thuyết của nó là:

```text
Tên executable
      !=
nguồn chân lý tuyệt đối về target
```

Tên chương trình có thể bị symlink hoặc được đóng gói theo cách riêng. Cấu hình nội tại của compiler mới quyết định target mà nó thực sự phục vụ.

### 4.5 Không nên suy luận quá mức từ tên prefix

Tên như `arm-linux-gnueabihf` cung cấp thông tin rất hữu ích, nhưng không thể thay thế hoàn toàn cho việc hiểu toolchain được cấu hình ra sao.

Hai toolchain có tên gần giống nhau vẫn có thể khác về:

- GCC version;
- Binutils version;
- libc và version của libc;
- sysroot;
- default CPU/ISA;
- default linker options;
- multilib set;
- các patch của vendor;
- default hardening options.

Vì vậy:

```text
"cùng prefix"
    !=
"mọi khía cạnh của toolchain hoàn toàn giống nhau"
```

---

## 5. Architecture, ISA, CPU và ABI khác nhau như thế nào?

Đây là một trong những phần quan trọng nhất để hiểu cross-compilation.

Các khái niệm sau liên quan chặt chẽ nhưng không đồng nghĩa:

```text
Architecture / ISA
CPU implementation
ABI
Operating environment
```

### 5.1 ISA — tập lệnh mà software có thể sử dụng

`ISA` — `Instruction Set Architecture` — mô tả giao diện instruction-level giữa software và processor.

Ví dụ:

```text
x86-64
AArch64
Arm 32-bit instruction sets
RISC-V
```

ISA liên quan tới những thứ như:

- tập register kiến trúc;
- instruction encoding;
- kiểu instruction có thể thực thi;
- addressing mode;
- một số đặc tính ở mức kiến trúc.

Compiler backend phải biết target ISA để sinh machine code đúng.

### 5.2 CPU implementation cụ thể không đồng nghĩa ISA

Nhiều CPU khác nhau có thể cùng thực thi một ISA cơ sở.

Ví dụ ở mức khái quát:

```text
AArch64 ISA
   |
   +-- CPU core A
   +-- CPU core B
   +-- CPU core C
```

Các CPU có thể khác nhau về:

- pipeline;
- cache;
- branch predictor;
- execution resources;
- supported ISA extensions;
- performance characteristics.

Vì vậy compiler có thể cần biết hai câu hỏi khác nhau:

```text
Instruction nào được phép sinh?
            vs
Nên tối ưu scheduling/code shape cho CPU nào?
```

Đây là nền tảng để hiểu `-march`, `-mcpu`, `-mtune` ở phần sau.

### 5.3 ABI — quy ước nhị phân giữa các thành phần

`ABI` — `Application Binary Interface` — quy định cách các thành phần binary tương tác với nhau.

Nếu API trả lời:

```text
Source code gọi hàm nào?
Function prototype là gì?
```

thì ABI trả lời các câu ở mức binary như:

```text
Argument được truyền qua register nào?
Stack phải alignment ra sao?
Return value nằm ở đâu?
Kiểu dữ liệu có layout thế nào?
Object file biểu diễn các thành phần theo quy ước nào?
```

Có thể hình dung:

```text
SOURCE LEVEL
API
 |
 v
foo(int x)

------------------------------

BINARY LEVEL
ABI
 |
 +--> argument register
 +--> stack convention
 +--> return register
 +--> data layout
 +--> binary conventions
```

### 5.4 Cùng architecture chưa chắc cùng ABI

Đây là điểm rất dễ nhầm.

Hai binary có thể cùng hướng tới một họ CPU nhưng vẫn dùng các ABI khác nhau.

Ví dụ nổi tiếng ở ARM 32-bit là sự khác biệt liên quan tới floating-point calling convention trong các môi trường ABI khác nhau. Tên toolchain như:

```text
arm-linux-gnueabi-
arm-linux-gnueabihf-
```

phản ánh rằng chỉ biết "ARM" là chưa đủ để kết luận mọi object file đều link/chạy tương thích.

Mô hình:

```text
Same broad CPU architecture
          |
          +--> ABI A
          |
          +--> ABI B

ABI A object  +  ABI B object
        có thể không tương thích
```

### 5.5 Operating system/runtime environment cũng là một chiều riêng

Một binary cho AArch64 Linux và một binary bare-metal AArch64 có thể dùng cùng ISA cơ sở nhưng kỳ vọng môi trường runtime hoàn toàn khác nhau.

```text
AArch64 + Linux userspace
          !=
AArch64 + bare metal
```

Một bên kỳ vọng Linux process model, system call interface, ELF conventions, C library/runtime phù hợp với Linux userspace; bên kia có thể không có kernel/userspace theo mô hình đó.

> **Ghi nhớ:** "Đúng architecture" chỉ là một điều kiện. Nó không đủ để chứng minh binary tương thích với target.

---

## 6. ABI quyết định những gì?

ABI là khái niệm rộng. Ở mức của chủ đề này, cần hiểu các nhóm quy ước quan trọng nhất thay vì đi sâu vào từng tài liệu psABI.

### 6.1 Calling convention

Khi một function gọi function khác, hai phía phải thống nhất:

- argument đặt ở register nào hoặc trên stack thế nào;
- return value nằm ở đâu;
- register nào caller phải bảo toàn;
- register nào callee phải bảo toàn;
- stack pointer phải alignment bao nhiêu;
- structure lớn được truyền/return theo cơ chế nào.

Ví dụ khái quát:

```text
Caller
  |
  | ABI quy định cách đặt arguments
  v
Callee
  |
  | ABI quy định cách trả result
  v
Caller tiếp tục
```

Nếu caller và callee không tuân cùng quy ước, source code có thể trông hoàn toàn đúng nhưng binary interface sẽ không khớp.

### 6.2 Data model và layout

ABI còn liên quan tới kích thước/alignment của nhiều kiểu dữ liệu và layout nhị phân mà compiler phải tuân theo.

Ví dụ cần quan tâm tới các khái niệm như:

```text
sizeof(long)
sizeof(void *)
alignment
structure layout
```

Không nên ghi dữ liệu nhị phân ra file/network rồi mặc định rằng một structure C có cùng layout trên mọi ABI.

### 6.3 Endianness

`Endianness` mô tả thứ tự byte của giá trị nhiều byte trong memory.

Ví dụ minh họa một giá trị 32-bit:

```text
Giá trị logic: 0x11223344

Little-endian memory:
44 33 22 11

Big-endian memory:
11 22 33 44
```

Endianness là một thuộc tính quan trọng khi phần mềm trao đổi dữ liệu nhị phân với:

- file format;
- network protocol;
- memory-mapped hardware;
- firmware data;
- hệ thống khác kiến trúc.

Không phải mọi ABI/target đều hỗ trợ mọi endianness theo cùng cách.

### 6.4 Object-file và relocation conventions

ABI/psABI còn xác định nhiều quy tắc về ELF, relocation, symbol và dynamic linking cho target cụ thể.

Ở Chủ đề 1 chúng ta đã học ELF ở mức format tổng quát. Nhưng ELF chỉ là khung chung. Một target architecture còn cần quy định cụ thể như:

```text
Relocation type nào tồn tại?
Register nào mang ý nghĩa đặc biệt?
Machine ID nào được dùng?
Cách biểu diễn một số symbol/section ra sao?
```

Các chi tiết này thường nằm trong tài liệu ABI dành riêng cho architecture, ví dụ Arm ABI.

### 6.5 ABI tạo ra "hợp đồng" giữa các binary component

Có thể hình dung:

```text
Application object
      |
      | cùng ABI
      v
C library
      |
      | cùng ABI
      v
Runtime / loader / kernel-facing environment
```

Nếu các thành phần không cùng thỏa mãn hợp đồng binary cần thiết, lỗi có thể xảy ra ngay khi link hoặc chỉ lộ ra lúc runtime.

> **Điểm cần nhớ:** Cross toolchain không chỉ phải sinh instruction đúng ISA; nó phải sinh binary tuân đúng ABI mà target userspace đang sử dụng.

---

## 7. Một GNU cross toolchain gồm những thành phần nào?

Một cross toolchain Linux điển hình không phải một executable duy nhất.

### 7.1 GCC driver

Ví dụ:

```text
aarch64-linux-gnu-gcc
```

GCC driver điều phối các stage đã học ở Chủ đề 1.

Nó có thể gọi những thành phần phía dưới phù hợp với target và truyền các option cần thiết cho:

- preprocessor;
- compiler proper;
- assembler;
- linker.

### 7.2 Assembler

Ví dụ:

```text
aarch64-linux-gnu-as
```

Assembler hiểu Assembly syntax/instruction của target và tạo relocatable object tương ứng.

Một native x86-64 assembler không thể được mặc định thay thế cho AArch64 assembler chỉ vì cả hai đều tạo ELF.

```text
ELF là container format
        !=
Machine code bên trong giống nhau
```

### 7.3 Linker

Ví dụ:

```text
aarch64-linux-gnu-ld
```

Linker ghép object/library cho target và áp dụng relocation theo quy tắc target tương ứng.

Thông thường người phát triển vẫn dùng GCC driver để thực hiện bước link:

```text
aarch64-linux-gnu-gcc ...
```

thay vì gọi `ld` trực tiếp, bởi driver biết thêm các startup file, runtime library và default option của toolchain.

### 7.4 `ar` và `ranlib`

```text
aarch64-linux-gnu-ar
aarch64-linux-gnu-ranlib
```

Các công cụ này làm việc với archive/static library. Nội dung static/shared library sẽ được học kỹ ở Chủ đề 3.

Ở đây chỉ cần hiểu chúng cũng thuộc họ công cụ target-aware vì archive chứa object file của target.

### 7.5 `objdump`, `objcopy`, `nm`, `readelf`, `strip`

Các công cụ binary utilities thường cũng có bản mang prefix target:

```text
aarch64-linux-gnu-objdump
aarch64-linux-gnu-objcopy
aarch64-linux-gnu-nm
aarch64-linux-gnu-readelf
aarch64-linux-gnu-strip
```

Chúng phục vụ những mục đích khác nhau:

| Công cụ | Vai trò khái quát |
|---|---|
| `objdump` | Quan sát object/binary, disassembly |
| `objcopy` | Sao chép/chuyển đổi nội dung object theo khả năng hỗ trợ |
| `nm` | Quan sát symbol |
| `readelf` | Quan sát metadata ELF |
| `strip` | Loại bỏ một số symbol/debug information khỏi binary |

Một số GNU Binutils có thể được build với khả năng đọc nhiều target format, nhưng không nên dựa vào điều đó để trộn lẫn tùy tiện giữa native và cross tools. Dùng đúng toolchain prefix giúp giữ model nhất quán và tránh phụ thuộc vào cách distribution đã cấu hình Binutils.

### 7.6 Toolchain là một hệ thống có cấu hình target thống nhất

Điểm quan trọng nhất không phải ghi nhớ danh sách executable, mà là hiểu:

```text
Compiler
Assembler
Linker
Binary utilities
Runtime files
Sysroot
```

phải tạo thành một hệ thống hợp lý quanh cùng target.

Nếu build process vô tình dùng:

```text
AArch64 compiler
        +
x86-64 linker
```

thì pipeline đã bị phá vỡ ở ranh giới target.

---

## 8. C library, runtime support và startup files

Một hiểu lầm phổ biến là:

> "Có cross GCC rồi thì đã đủ build mọi chương trình C cho Linux target."

Thực tế, phần lớn chương trình C userspace cần thêm môi trường runtime phù hợp.

### 8.1 C library cung cấp nhiều API userspace nền tảng

Ví dụ source C có thể sử dụng:

```c
printf(...);
malloc(...);
fopen(...);
strlen(...);
```

Compiler hiểu cú pháp của lời gọi, nhưng implementation của các function này không nằm trong compiler proper.

Chúng thường đến từ một C library như:

```text
glibc
musl
uClibc-ng
...
```

Trong Embedded Linux, lựa chọn libc có ảnh hưởng tới:

- ABI/runtime compatibility;
- kích thước;
- feature set;
- dynamic loader;
- bộ header/library trong sysroot.

Nội dung library/linking chi tiết sẽ được học ở Chủ đề 3. Ở đây chỉ cần hiểu rằng libc là một thành phần của môi trường target.

### 8.2 Header và library phải thuộc cùng target environment hợp lý

Ví dụ source dùng:

```c
#include <stdio.h>
```

Header `stdio.h` mà cross compiler nhìn thấy phải mô tả interface phù hợp với libc của target.

Sau đó khi link, implementation tương ứng cũng phải đến từ library target.

Mô hình:

```text
Target headers
      |
      v
Compile source
      |
      v
Target object
      |
      +---- link với target libraries
      |
      v
Target executable
```

Nếu lấy header của development host nhưng link library của target một cách tùy tiện, compile có thể thành công nhưng contract giữa compile-time và link/runtime có thể sai.

### 8.3 `libgcc` là runtime support của GCC

GCC đôi khi cần các helper routine để thực hiện những operation mà target instruction set không cung cấp trực tiếp hoặc compiler chọn triển khai qua runtime helper.

Những routine như vậy có thể nằm trong `libgcc`.

Do đó GCC driver không chỉ điều phối compiler và linker mà còn biết cách đưa runtime support phù hợp vào quá trình link khi cần.

### 8.4 Startup files nối ELF entry với C runtime

Ở Chủ đề 1 đã nhấn mạnh rằng source có `main()` không có nghĩa ELF kernel-load entry point trực tiếp là `main()`.

Trước `main()`, thường có startup code/runtime initialization.

Các object đặc biệt thường được gọi theo các tên như:

```text
crt*.o
```

Mô hình khái quát:

```text
Kernel / dynamic loader
        |
        v
ELF entry point
        |
        v
C runtime startup
        |
        +--> runtime initialization
        |
        v
main()
```

Cross toolchain phải sử dụng startup object phù hợp với target ABI và C runtime.

### 8.5 Compiler và libc là hai lớp khác nhau

Cần tránh đồng nhất:

```text
GCC = glibc
```

Đây là hai project/lớp khác nhau.

```text
GCC
  -> compiler + runtime support liên quan compiler

C library
  -> standard C/POSIX/Linux userspace interfaces và runtime components
```

Một toolchain có thể kết hợp GCC với các libc khác nhau tùy hệ thống.

---

## 9. Sysroot là gì?

`Sysroot` là một khái niệm trung tâm của cross-compilation Linux.

### 9.1 Sysroot là logical root dùng khi tìm target files

Giả sử target userspace về mặt logic có:

```text
/usr/include
/usr/lib
/lib
```

Development machine cũng có các đường dẫn cùng tên, nhưng đó là file dành cho development host.

Cross compiler không thể mặc định lấy chúng.

Sysroot tạo ra một root logic khác, ví dụ về mặt mô hình:

```text
/opt/target-sysroot/
|
+-- usr/
|   +-- include/
|   +-- lib/
|
+-- lib/
```

Khi sysroot là:

```text
/opt/target-sysroot
```

thì một search path target logic như:

```text
/usr/include
```

có thể được ánh xạ thành:

```text
/opt/target-sysroot/usr/include
```

và library path target logic:

```text
/usr/lib
```

có thể được ánh xạ thành:

```text
/opt/target-sysroot/usr/lib
```

Theo cách đó, compiler/linker có thể làm việc như thể đang nhìn vào một phần filesystem của target mà không cần chạy trên target.

### 9.2 Sysroot không phải `chroot`

Hai khái niệm này khác bản chất.

```text
sysroot
  -> thay đổi logical search root của toolchain

chroot
  -> thay đổi filesystem root nhìn thấy bởi một process theo cơ chế hệ điều hành
```

Dùng sysroot không có nghĩa compiler process bị nhốt vào một filesystem namespace mới hoặc root directory thật của process bị đổi.

### 9.3 Sysroot không đồng nghĩa root filesystem hoàn chỉnh

Một sysroot thường có cấu trúc giống một phần root filesystem target, nhưng:

```text
Sysroot
   !=
Bản sao bắt buộc phải hoàn chỉnh của target rootfs
```

Sysroot chủ yếu cần những thành phần phục vụ compile/link, chẳng hạn:

- development headers;
- libraries;
- startup objects;
- dynamic-link related files cần ở link time;
- các metadata/development symlink phù hợp.

Một rootfs dùng để boot/chạy target lại chứa nhiều thứ không cần cho compiler:

```text
/etc
/var
application data
service configuration
runtime state
...
```

Ngược lại, target rootfs tối giản có thể thiếu development header và unversioned linker symlink nên không tự động trở thành một sysroot tốt.

### 9.4 Sysroot phải tương thích với target runtime

Điểm quan trọng không phải chỉ là "có thư mục `/usr/include` và `/usr/lib`".

Nội dung sysroot phải phù hợp với:

- architecture;
- ABI;
- C library family;
- C library version/compatibility expectations;
- các third-party library mà application cần;
- môi trường target thực tế.

Mô hình:

```text
Cross compiler target configuration
              |
              +----------+
                         |
                         v
                    Sysroot
                         |
        +----------------+----------------+
        |                |                |
    headers           libraries        crt/runtime
        |                |                |
        +----------------+----------------+
                         |
                         v
               Target-compatible ELF
```

### 9.5 `--sysroot` thay đổi nơi GCC tìm target header/library

GCC hỗ trợ option `--sysroot=DIR` để dùng `DIR` như logical root cho header và library search theo cấu hình tương ứng.

Điểm cần hiểu ở đây không phải thuộc lệnh, mà là cơ chế:

```text
Host absolute-looking path
/usr/include

không nhất thiết phải là

Target logical /usr/include
```

Sysroot cho phép toolchain giữ hai thế giới này tách biệt.

### 9.6 `-print-sysroot` chỉ là cửa sổ quan sát cấu hình

GCC có thể cho biết sysroot target mà nó đang dùng thông qua option kiểu:

```text
-print-sysroot
```

Đây là một ví dụ về cách compiler driver có thể tự mô tả một phần cấu hình target của nó.

> **Ghi nhớ:** Sysroot là **môi trường header/library của target được nhìn từ development machine**, không phải target board và cũng không phải cơ chế filesystem isolation.

---

## 10. Toolchain tìm header và library của target như thế nào?

Một trong những lý do sysroot quan trọng là cùng một tên file có thể tồn tại ở cả development host và target nhưng mang nội dung hoàn toàn khác.

### 10.1 Hai thế giới filesystem phải được tách ra

Ví dụ development machine có:

```text
/usr/include/stdio.h
/usr/lib/...
```

Đây là environment của host development machine.

Target AArch64 cũng có logic tương tự:

```text
/usr/include/stdio.h
/usr/lib/...
```

nhưng các file đó phải dành cho target.

Nếu cross compiler vô tình dùng host environment:

```text
Cross source
    |
    +--> x86-64 header/library  <-- sai thế giới
    |
    v
AArch64 output
```

thì build có thể thất bại hoặc tệ hơn: một phần compile thành công nhưng tạo ra assumption không phù hợp runtime.

### 10.2 Header ảnh hưởng ngay từ preprocessing/compilation

Header không chỉ chứa function declaration đơn giản. Nó có thể chứa:

- type definitions;
- structure definitions;
- macro;
- conditional compilation;
- feature-test logic;
- ABI-sensitive definitions;
- inline functions.

Do đó chọn sai header có thể làm compiler nhìn thấy một chương trình khác.

Mô hình:

```text
Source code
    |
    +--> Target headers
    |
    v
Translation unit
    |
    v
Target compiler
```

### 10.3 Library ảnh hưởng ở link time

Sau khi source thành object file, linker cần resolve symbol từ các library phù hợp.

```text
AArch64 object
      |
      +--> AArch64 target library
      |
      v
AArch64 executable
```

Một x86-64 `.a` hoặc `.so` không trở thành AArch64 library chỉ vì function name trùng nhau.

```text
Tên symbol giống nhau
        !=
Object code tương thích architecture/ABI
```

### 10.4 Search path có nhiều lớp

GCC driver có các built-in search path, target-specific paths, sysroot logic và các option bổ sung như `-I`, `-L`.

Do đó câu hỏi đúng khi chẩn đoán thường không phải:

> "File này có tồn tại trên máy không?"

mà là:

> "Compiler/linker đang tìm file này trong **search path nào cho target hiện tại**?"

Hai câu hỏi này khác nhau đáng kể.

### 10.5 Toolchain installation prefix và sysroot không phải một

Toolchain binaries có thể được cài dưới một nơi như:

```text
/opt/toolchains/...
```

trong khi sysroot có thể nằm ở một nơi khác hoặc được nhúng trong cấu trúc toolchain.

```text
Toolchain installation prefix
      -> nơi đặt gcc/as/ld và internal compiler files

Sysroot
      -> logical root của target headers/libraries
```

Một distribution/toolchain package có thể bố trí chúng gần nhau, nhưng đó không làm hai khái niệm trở thành một.

---

## 11. Cross-build diễn ra như thế nào?

Kết hợp các phần trước, có thể xây dựng mô hình đầy đủ hơn cho một chương trình C userspace.

```text
Development machine: x86-64 Linux

Source code
    |
    | preprocess với target headers từ sysroot
    v
Translation unit
    |
    | AArch64 compiler backend
    v
AArch64 Assembly
    |
    | AArch64 assembler
    v
AArch64 object file
    |
    | AArch64 linker
    | + target crt objects
    | + target libraries
    | + compiler runtime support
    v
AArch64 Linux ELF
```

### 11.1 Preprocess đã phụ thuộc target environment

Một hiểu lầm là cross-compilation chỉ bắt đầu từ compiler backend khi sinh Assembly.

Thực tế preprocessing cũng có thể phụ thuộc target vì:

- predefined macro của compiler khác nhau;
- header target khác nhau;
- conditional compilation có thể chọn nhánh khác.

Ví dụ khái quát:

```c
#if defined(SOME_TARGET_MACRO)
    /* target-specific declarations */
#endif
```

Do đó target ảnh hưởng pipeline từ rất sớm.

### 11.2 Compilation sinh machine model của target

Compiler proper phải sử dụng backend/configuration phù hợp để sinh Assembly theo ISA và ABI target.

```text
C semantics
    |
    v
Target-independent compiler reasoning
    |
    v
Target-specific code generation
    |
    v
AArch64 Assembly
```

Cách tổ chức nội bộ compiler thực tế phức tạp hơn nhiều, nhưng mental model này đủ để hiểu vai trò target.

### 11.3 Assembly tạo object mang target machine information

Object file không chỉ chứa byte instruction. ELF header và các relocation/symbol conventions cũng gắn với target.

Vì vậy linker có thể nhận ra object thuộc architecture không phù hợp.

### 11.4 Link phải dùng toàn bộ target-side dependency

Ở bước link, tất cả các component machine-code-level phải phù hợp.

```text
main.o      -> AArch64
libfoo.a    -> AArch64
crt*.o      -> AArch64
libc        -> AArch64
libgcc      -> AArch64-compatible
```

Không thể lấy một `.o` x86-64 rồi kỳ vọng AArch64 linker biến machine code đó thành AArch64.

Linker **không phải compiler dịch lại object giữa các ISA**.

### 11.5 Output sau cross-build chỉ mới là binary dành cho target

Build thành công chưa có nghĩa chương trình đã được chạy/kiểm thử.

```text
Cross-build success
       |
       v
Target ELF được tạo
       |
       v
Cần chạy trong môi trường target phù hợp
```

Môi trường đó có thể là:

- board thật;
- hệ thống target tương ứng;
- emulator/virtualized environment thích hợp.

Chi tiết emulator không thuộc phạm vi chủ đề này.

---

## 12. Vì sao binary của target thường không chạy trực tiếp trên host?

Giả sử:

```text
Host:   x86-64 Linux
Output: AArch64 Linux ELF
```

Cả hai đều là Linux và đều dùng ELF, nhưng điều đó không làm machine code tương thích.

### 12.1 ELF chỉ là container format

Một ELF có metadata chỉ ra target machine và chứa code dành cho architecture tương ứng.

Có thể hình dung:

```text
ELF
 |
 +-- ELF header
 |    +-- machine = AArch64
 |
 +-- sections/segments
 |
 +-- AArch64 machine instructions
```

Kernel x86-64 không thể tự nhiên thực thi AArch64 instruction stream như x86-64 code.

### 12.2 `same OS` không đồng nghĩa `same executable architecture`

```text
Linux x86-64
Linux AArch64
```

chia sẻ rất nhiều semantics ở tầng operating system nhưng khác ISA của userspace binary.

Mô hình:

```text
Linux API concepts
       /
      /
     +----------------+
     |                |
 x86-64 ELF       AArch64 ELF
     |                |
 x86-64 CPU       AArch64 CPU
```

### 12.3 `Exec format error` thường chỉ ra sai lớp format/architecture

Khi kernel không thể nhận executable theo format/architecture được hỗ trợ, một lỗi kiểu `Exec format error` có thể xuất hiện.

Điều cần học không phải ghi nhớ một message duy nhất, mà là cách suy luận:

```text
Build thành công
      |
      v
Không start được executable
      |
      +--> Kiểm tra ELF format
      +--> Kiểm tra machine architecture
      +--> Kiểm tra interpreter/runtime requirements
```

Không phải mọi lỗi "không chạy được" đều là sai architecture. Dynamic loader/library mismatch có thể tạo biểu hiện khác; nội dung đó sẽ rõ hơn sau Chủ đề 3.

### 12.4 CPU cùng architecture family vẫn có thể thiếu extension

Một binary có thể mang đúng architecture cơ bản nhưng compiler đã sinh instruction extension mà CPU cụ thể không hỗ trợ.

Khi đó vấn đề không còn là:

```text
x86-64 vs AArch64
```

mà có thể là:

```text
AArch64 code requiring feature X
          vs
AArch64 CPU lacking feature X
```

Đây là lý do chọn `-march`/`-mcpu` phù hợp rất quan trọng.

---

## 13. Những lớp tương thích phải đồng thời khớp

Khi nói "binary dành cho target", cần tránh coi target chỉ là một tên CPU.

Một mô hình tốt hơn là nhiều lớp tương thích:

```text
+----------------------------------+
| Application assumptions          |
+----------------------------------+
| User-space libraries / libc      |
+----------------------------------+
| ABI / calling conventions        |
+----------------------------------+
| OS/runtime environment           |
+----------------------------------+
| ISA + required CPU extensions    |
+----------------------------------+
| Hardware CPU                     |
+----------------------------------+
```

### 13.1 Architecture mismatch

Ví dụ:

```text
AArch64 ELF -> x86-64 CPU
```

Đây là mismatch rất rõ ở ISA.

### 13.2 ABI mismatch

Có thể cùng broad architecture nhưng object/library không tuân cùng ABI.

Lỗi có thể xuất hiện ở link time hoặc runtime tùy loại mismatch.

### 13.3 C library/runtime mismatch

Một executable được link cho một userspace environment nhất định có expectation về C library và dynamic loader.

Ví dụ về mặt khái niệm:

```text
Binary build against environment A
              |
              v
Target provides incompatible environment B
```

Không nên suy luận rằng "đều là Linux" nên mọi userspace library ABI đều giống nhau.

### 13.4 Version compatibility cũng là một chiều

Ngay cả khi cùng library family, binary mới có thể yêu cầu symbol/version mà target cũ chưa cung cấp.

Điều này đặc biệt quan trọng trong Embedded Linux vì:

```text
Development SDK có thể mới
Target rootfs có thể cũ
```

Do đó sysroot cần phản ánh environment mà target thực sự có hoặc một baseline tương thích phù hợp.

### 13.5 Kernel/userspace boundary là một lớp khác

Application thường không gọi raw kernel internals trực tiếp; phần lớn đi qua libc hoặc wrapper/API userspace.

Kernel cũng có userspace ABI riêng cần duy trì tương thích ở nhiều interface.

Tuy nhiên không nên trộn:

```text
CPU ABI / psABI
        với
Linux userspace-kernel ABI
```

Chúng đều là "ABI" theo nghĩa rộng nhưng thuộc các boundary khác nhau.

### 13.6 Tính tương thích là giao của nhiều điều kiện

Có thể tóm tắt:

```text
Runnable binary
    =
ISA compatible
    AND
ABI compatible
    AND
runtime/library compatible
    AND
environment assumptions satisfied
```

Nếu một điều kiện sai, việc các điều kiện còn lại đúng không cứu được binary.

---

## 14. Linux cross toolchain và bare-metal toolchain không giống nhau

Tên toolchain thường cung cấp manh mối về runtime environment.

Ví dụ có thể gặp:

```text
aarch64-linux-gnu-
arm-linux-gnueabihf-
arm-none-eabi-
```

### 14.1 Linux-targeting toolchain

Một toolchain kiểu:

```text
aarch64-linux-gnu-
```

được cấu hình hướng tới Linux userspace environment.

Nó thường được dùng cùng:

- Linux-compatible target ABI;
- Linux C library/sysroot;
- ELF executable/shared objects cho Linux userspace.

### 14.2 Bare-metal toolchain

Một toolchain kiểu:

```text
arm-none-eabi-
```

thường hướng tới môi trường không có một hosted Linux userspace theo mô hình trên.

Application có thể chạy:

```text
trực tiếp trên hardware
hoặc
trên một RTOS / runtime riêng
```

Tùy toolchain/runtime, C library có thể là loại dành cho embedded/bare-metal và system call layer phải được cung cấp theo cách khác.

### 14.3 Cùng CPU family không đủ để thay thế lẫn nhau

```text
ARM Linux toolchain
        !=
ARM bare-metal toolchain
```

Ngay cả khi machine instructions có phần chung, hai toolchain hướng tới môi trường thực thi khác nhau.

Ví dụ, Linux application kỳ vọng:

```text
process model
virtual address space theo OS
Linux syscall-facing runtime
Linux userspace libraries
ELF loader semantics tương ứng
```

Bare-metal firmware không mặc định có các thành phần đó.

### 14.4 Không nên đọc `none` theo nghĩa quá máy móc

Trong target naming, các trường và canonical form có lịch sử/quy ước của GNU ecosystem. Vì vậy chỉ nên dùng tên như một chỉ dấu về target environment, không tự suy ra mọi property chưa được toolchain documentation xác nhận.

> **Điểm cần nhớ:** Khi chọn compiler, câu hỏi không chỉ là "CPU có phải ARM/AArch64 không?" mà còn là "binary được tạo ra cho **môi trường nào**?".

---

## 15. `-march`, `-mcpu`, `-mtune` và multilib ở mức nền tảng

Một cross compiler đã có target architecture tổng quát, nhưng trong cùng target đó vẫn có nhiều lựa chọn code generation.

### 15.1 `-march` — tập capability instruction được phép sử dụng

Ở mức khái niệm:

```text
-march
   -> target ISA level / extension set
```

Nếu chọn một `-march` yêu cầu feature mà CPU target không có, compiler có thể sinh instruction không chạy được trên thiết bị.

Mô hình:

```text
Compiler allowed ISA set
          |
          v
Generated instructions
          |
          v
CPU must support them
```

### 15.2 `-mcpu` — chọn CPU model cho code generation/tuning

Trong GCC target như AArch64, `-mcpu` có thể ảnh hưởng cả:

- loại instruction/features được dùng;
- tuning theo processor cụ thể.

Có thể hình dung:

```text
-mcpu = "tôi nhắm tới CPU này"
```

nhưng chi tiết chính xác phụ thuộc target GCC và phải tra target-specific options.

### 15.3 `-mtune` — tối ưu cho CPU nhưng không nhất thiết mở thêm ISA

Mental model hữu ích:

```text
-march
  -> code được phép yêu cầu instruction set nào

-mtune
  -> trong tập instruction hợp lệ đó, sắp xếp/chọn code shape để chạy tốt trên CPU nào
```

Ví dụ một binary có thể được tune cho một core nhưng vẫn giữ ISA baseline đủ rộng để chạy trên nhiều CPU tương thích.

### 15.4 Không áp dụng máy móc option giữa các architecture

Tên và semantics chi tiết của `-m...` option phụ thuộc target.

Không nên học theo kiểu:

```text
"-mcpu luôn có nghĩa chính xác X trên mọi GCC target"
```

Cách đúng là:

```text
Hiểu khái niệm
      +
Tra target-specific GCC documentation
```

### 15.5 Multilib là gì?

Một compiler có thể hỗ trợ nhiều biến thể library/runtime cho các lựa chọn ABI hoặc machine option khác nhau. Cơ chế này thường được gọi là `multilib`.

Mô hình khái quát:

```text
Một compiler installation
        |
        +--> library variant A
        |
        +--> library variant B
        |
        +--> library variant C
```

Compiler driver chọn variant phù hợp dựa trên target option.

Ví dụ khái niệm có thể liên quan tới:

- 32-bit vs 64-bit trong một số toolchain;
- floating-point ABI variant;
- architecture variant;
- các cấu hình runtime khác mà toolchain được build để hỗ trợ.

Không phải mọi toolchain đều cung cấp mọi multilib.

### 15.6 Compiler option và sysroot/runtime phải đồng bộ

Nếu compiler được yêu cầu sinh theo một ABI/variant nhưng sysroot không có library tương ứng, compile có thể đi qua nhưng link thất bại.

```text
Code-generation option
          |
          v
Selected ABI/variant
          |
          +----> cần matching runtime/library
```

Đây là ví dụ điển hình cho việc toolchain phải được nhìn như một hệ thống, không phải chỉ compiler executable.

---

## 16. Tư duy chẩn đoán lỗi cross-compilation

Cross-compilation thêm một chiều mới vào debugging build: **mọi artifact cần được hỏi xem nó thuộc host hay target**.

### 16.1 Không tìm thấy compiler

Nếu build system báo không tìm được:

```text
aarch64-linux-gnu-gcc
```

thì đây trước hết là vấn đề chọn/định vị toolchain trên development machine.

Mental model:

```text
Build system
    |
    X  không tìm thấy compiler executable
```

Chưa cần suy luận tới source code hay target library.

### 16.2 Compiler chạy nhưng không tìm thấy header

Ví dụ conceptual error:

```text
fatal error: some_header.h: No such file or directory
```

Cần hỏi:

```text
Header là của project?
Header là của libc?
Header là của third-party target library?
Sysroot có đúng không?
Search path có trỏ vào target environment không?
```

Không nên chữa mặc định bằng cách thêm host `/usr/include`, vì điều đó có thể làm lẫn hai environment.

### 16.3 Linker báo object/library sai format hoặc architecture

Đây thường là dấu hiệu một artifact host bị trộn vào target link hoặc ngược lại.

Mô hình:

```text
AArch64 linker
     |
     +--> AArch64 main.o      OK
     |
     +--> x86-64 libfoo.a     mismatch
```

Câu hỏi quan trọng:

```text
File này được build bởi compiler nào?
ELF machine là gì?
Library archive chứa object architecture nào?
```

### 16.4 `undefined reference` vẫn là linker-level symbol problem

Cross-compilation không làm thay đổi bản chất của `undefined reference` đã học ở Chủ đề 1.

Nhưng nguyên nhân có thêm khả năng như:

- target library chưa được link;
- sysroot thiếu library cần thiết;
- chọn nhầm variant/multilib;
- library đúng tên nhưng không có symbol/version phù hợp;
- thứ tự/link rule có vấn đề.

Do đó:

```text
undefined reference
    !=
"chắc chắn cross compiler bị lỗi"
```

### 16.5 Build thành công nhưng target không chạy được

Hãy phân tách theo lớp:

```text
ELF machine đúng không?
        |
ABI/runtime đúng không?
        |
CPU feature có phù hợp không?
        |
Dynamic loader/library có tồn tại không?
        |
Application assumption có đúng không?
```

Đây là cách suy luận tốt hơn việc thay ngẫu nhiên compiler flag.

### 16.6 Binary chạy trên host không chứng minh đó là target binary

Nếu mục tiêu là AArch64 nhưng executable lại chạy bình thường trên host x86-64 mà không qua emulator/compatibility layer, cần đặt câu hỏi:

```text
Build system có thật sự dùng cross compiler không?
```

Một lỗi cấu hình rất phổ biến về mặt tư duy là build system âm thầm dùng `gcc` native thay vì compiler có target prefix.

### 16.7 Đừng sửa lỗi bằng cách trộn host paths vào cross-build

Một anti-pattern nguy hiểm về mặt thiết kế là:

```text
Thiếu header/library target
        |
        v
thêm /usr/include hoặc /usr/lib của host
```

Điều này đôi khi làm error message biến mất nhưng phá vỡ tính nhất quán target.

Cách suy luận đúng:

```text
Thiếu dependency
      |
      v
Tìm đúng dependency cho target
      |
      v
Đặt nó vào sysroot/target search environment phù hợp
```

---

## 17. Liên hệ với Embedded Linux

Cross-compilation không phải một kỹ thuật phụ trong Embedded Linux. Nó là một phần trung tâm của workflow phát triển.

### 17.1 Vì sao không build trực tiếp trên board?

Một board nhúng có thể có:

- CPU chậm hơn development workstation;
- RAM hạn chế;
- storage hạn chế;
- rootfs tối giản;
- không cài compiler/development headers;
- yêu cầu build reproducible trong CI.

Do đó workflow phổ biến là:

```text
Powerful development machine
          |
          | cross-build
          v
Target binaries / libraries
          |
          | deploy
          v
Embedded target
```

### 17.2 BSP/SDK thường cung cấp nhiều hơn compiler

Một vendor SDK hoặc Embedded Linux build system thường không chỉ đưa ra `gcc`.

Nó có thể cung cấp:

```text
Cross compiler
Binutils
Sysroot
C library
Headers
Target libraries
Environment setup
Debugging tools
```

Điều này phản ánh đúng mô hình của chương: một usable target development environment là tập hợp nhiều thành phần đồng bộ.

### 17.3 Sysroot là cầu nối giữa build machine và target userspace

Có thể xem sysroot là ảnh chụp ở góc nhìn development của **phần target filesystem cần cho compile/link**.

```text
Target userspace environment
            |
            | development representation
            v
          Sysroot
            |
            v
      Cross toolchain
```

Nếu target rootfs thay đổi library quan trọng nhưng SDK/sysroot không được cập nhật tương ứng, nguy cơ mismatch xuất hiện.

### 17.4 Cross toolchain và root filesystem phải được xem như một cặp

Một toolchain không tồn tại độc lập với target userspace.

Ví dụ:

```text
Toolchain A + sysroot A + rootfs A
```

thường là một tổ hợp được thiết kế để tương thích.

Việc lấy:

```text
compiler từ SDK A
sysroot từ SDK B
rootfs từ image C
```

có thể hoạt động trong một số trường hợp nếu ABI thực sự tương thích, nhưng không nên mặc định là an toàn chỉ vì architecture giống nhau.

### 17.5 Yocto/Buildroot sẽ xây chính những lớp này

Ở các phase Embedded Linux sau, khi gặp Yocto hoặc Buildroot, bạn sẽ thấy các hệ thống đó tự động hóa việc tạo/quản lý:

- cross toolchain;
- target sysroot;
- native build tools;
- target packages;
- root filesystem;
- SDK.

Nếu chưa hiểu Native/Cross Toolchain, các khái niệm như `recipe sysroot`, `staging`, `SDK`, `TARGET_CC`, `HOSTCC` rất dễ trở thành các biến cần học thuộc lòng.

Chương này nhằm tạo mental model trước khi đi tới các build system lớn đó.

### 17.6 Kernel build cũng có khái niệm host tools và target code

Khi build Linux kernel cho target khác architecture, build process có thể đồng thời cần:

```text
Tool chạy trên build host
          +
Code được build cho target
```

Vì vậy trong các hệ thống build phức tạp, không phải **mọi thứ được compile trong một build** đều dành cho cùng một machine.

Một số utility được tạo ra chỉ để chạy trong quá trình build trên host; kernel/image cuối lại dành cho target.

Đây là một ví dụ thực tế cho việc luôn phải hỏi:

> Artifact này sẽ chạy **ở đâu**?

### 17.7 Mental model Embedded Linux tổng quát

```text
DEVELOPMENT HOST
x86-64 Linux
      |
      | runs
      v
CROSS TOOLCHAIN
      |
      | target configuration
      +--------------------+
      |                    |
      v                    v
TARGET SYSROOT        TARGET ABI/ISA
      |                    |
      +---------+----------+
                |
                v
         TARGET ELF FILES
                |
                v
         ROOT FILESYSTEM
                |
                v
        EMBEDDED TARGET
       AArch64 / ARM / ...
```

> **Đọc sơ đồ:** Development host cung cấp tài nguyên để build; cross toolchain định hướng toàn bộ pipeline về target; sysroot cung cấp header/library/runtime view của target; output sau đó được đặt vào môi trường runtime trên embedded target.

---

## 18. Tổng kết và mô hình tư duy

### 18.1 Mô hình đầy đủ

```text
                         DEVELOPMENT MACHINE
                           x86-64 Linux
                                |
                                | chạy
                                v
+----------------------------------------------------------------+
|                     CROSS TOOLCHAIN                            |
|                                                                |
|   GCC driver -> compiler -> assembler -> linker                |
|                     |             |                            |
|                     |             +--> target Binutils         |
|                     |                                          |
|                     +--> target ISA / ABI                      |
+----------------------------------------------------------------+
                                |
              +-----------------+------------------+
              |                                    |
              v                                    v
       TARGET SYSROOT                      TARGET CONFIGURATION
              |                                    |
   +----------+-----------+              +---------+---------+
   |          |           |              |                   |
headers   libraries    crt/runtime      ISA                 ABI
   |          |           |              |                   |
   +----------+-----------+              +---------+---------+
              |                                    |
              +-----------------+------------------+
                                |
                                v
                       TARGET ELF OUTPUT
                                |
                                v
                         EMBEDDED TARGET
```

> **Đọc sơ đồ:** Cross compiler không hoạt động một mình. Code generation phải hướng về đúng ISA/ABI; compile và link phải sử dụng target headers/libraries/runtime từ một environment phù hợp; toàn bộ output cuối cùng mới tạo thành binary dành cho embedded target.

### 18.2 Các phân biệt cần nhớ

```text
Native compiler             != Cross compiler
Toolchain                   != Chỉ riêng `gcc`
Development host            != Target board
GNU `host`                  != Luôn là "host PC" theo cách nói hằng ngày
Architecture / ISA          != ABI
CPU model                   != ISA
Same architecture           != Same ABI
Same OS family              != Binary chắc chắn tương thích
Target tuple                != Chuỗi có thể tách máy móc theo dấu `-`
Toolchain prefix            != Bảo đảm hai SDK hoàn toàn giống nhau
Toolchain install prefix    != Sysroot
Sysroot                     != chroot
Sysroot                     != Bắt buộc là full target rootfs
Header của host             != Header của target
Library cùng tên            != Library cùng architecture/ABI
Linux cross toolchain       != Bare-metal toolchain
`-march`                    != `-mtune`
Build thành công            != Chạy đúng trên target
```

### 18.3 Các điểm cốt lõi

1.  `Native compilation` tạo code cho environment mà compiler được cấu hình phục vụ trên cùng loại hệ thống chạy compiler; `cross-compilation` tách machine chạy toolchain khỏi target của output.
2.  Cross-compilation vẫn dùng pipeline **Preprocess → Compile → Assemble → Link**; chỉ target của pipeline thay đổi.
3.  Trong GNU build terminology, `build`, `host`, `target` có nghĩa cụ thể và không nên trộn với cách dùng từ `host PC` trong hội thoại Embedded Linux.
4.  Target tuple/prefix giúp nhận diện một họ công cụ hướng tới target, nhưng tên không mô tả mọi chi tiết của SDK/toolchain.
5.  Architecture/ISA xác định instruction interface; CPU implementation là processor cụ thể; ABI quy định binary contract giữa các component.
6.  Cùng architecture chưa đủ để bảo đảm object/library tương thích nếu ABI hoặc runtime environment khác nhau.
7.  Một Linux cross toolchain thực tế bao gồm compiler, Binutils và các thành phần target-side như C library, runtime/startup files và sysroot.
8.  Sysroot là logical root để toolchain tìm target headers/libraries; nó không phải `chroot` và cũng không nhất thiết là full target root filesystem.
9.  Header và library của development host không được tùy ý đưa vào cross-build cho target chỉ vì pathname hoặc API name giống nhau.
10. Linux-targeting toolchain và bare-metal toolchain phục vụ các runtime environment khác nhau dù có thể cùng họ CPU.
11. Các option như `-march`, `-mcpu`, `-mtune` quyết định những khía cạnh khác nhau của target code generation và phải phù hợp với CPU/runtime thực tế.
12. Khi chẩn đoán cross-build, luôn hỏi từng artifact: **nó được tạo cho host hay target, architecture nào, ABI nào, và đến từ sysroot nào?**
13. Trong Embedded Linux, cross toolchain, sysroot và target rootfs phải được xem như các phần liên quan của cùng một hệ thống phát triển.

---

## 19. Tài liệu tham khảo

### 19.1 GCC

1. GNU Project — **Installing GCC: Configuration — Host, Build and Target specification**  
   <https://gcc.gnu.org/install/configure.html>

2. GNU Project — **Using the GNU Compiler Collection — Directory Options** (`--sysroot`, `-isysroot`, `-I`, `-L`, `-B`)  
   <https://gcc.gnu.org/onlinedocs/gcc/Directory-Options.html>

3. GNU Project — **Using the GNU Compiler Collection — Developer Options** (`-dumpmachine`, `-print-sysroot`, `-print-search-dirs`)  
   <https://gcc.gnu.org/onlinedocs/gcc/Developer-Options.html>

4. GNU Project — **Using the GNU Compiler Collection — Target-Specific Options**  
   <https://gcc.gnu.org/onlinedocs/gcc/Target-Specific-Options.html>

5. GNU Project — **Using the GNU Compiler Collection — AArch64 Options**  
   <https://gcc.gnu.org/onlinedocs/gcc/AArch64-Options.html>

### 19.2 GNU Binutils

6. GNU Project / Sourceware — **GNU Binary Utilities**  
   <https://sourceware.org/binutils/docs/binutils.html>

7. GNU Project / Sourceware — **Selecting the Target System**  
   <https://sourceware.org/binutils/docs/binutils/Selecting-the-Target-System.html>

8. GNU Project / Sourceware — **Target Selection**  
   <https://sourceware.org/binutils/docs/binutils/Target-Selection.html>

### 19.3 GNU configuration / Autoconf

9. GNU Project — **Autoconf — Specifying Target Triplets**  
   <https://www.gnu.org/software/autoconf/manual/autoconf-2.71/html_node/Specifying-Target-Triplets.html>

### 19.4 GNU C Library

10. GNU Project / Sourceware — **The GNU C Library — Configuring and compiling**  
    <https://sourceware.org/glibc/manual/latest/html_node/Configuring-and-compiling.html>

### 19.5 Arm ABI

11. Arm — **Application Binary Interface for the Arm Architecture (ABI-AA)**  
    <https://github.com/ARM-software/abi-aa>

12. Arm — **Procedure Call Standard for the Arm 64-bit Architecture (AAPCS64)**  
    <https://github.com/ARM-software/abi-aa/releases>

### 19.6 Tài liệu nền tảng

13. John R. Levine — **Linkers and Loaders** — Morgan Kaufmann.

14. Michael Kerrisk — **The Linux Programming Interface** — No Starch Press.

15. Robert Love — **Linux System Programming** — O'Reilly Media.

> **Điều hướng:** [← Chủ đề 1 — GCC Build Flow](README-topic-01.md) · [Chủ đề 3 — Static & Dynamic Library →](README-topic-03.md)
