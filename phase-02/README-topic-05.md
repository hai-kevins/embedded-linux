# Chủ đề 5 — CMake Fundamentals

> **Mục tiêu:** Hiểu bản chất của CMake như một **build-system generator**; xây dựng mental model `configure → generate → build`; phân biệt `source tree`, `build tree`, generator và native build tool; hiểu mô hình **target-centric** của CMake; nắm được cách CMake mô tả executable, library, source file, include directory và link dependency; hiểu vai trò của `PUBLIC`, `PRIVATE`, `INTERFACE`, variable, cache và toolchain file ở mức nền tảng. Sau chương này, người học phải hiểu CMake đang mô tả **cái gì**, nó sinh ra **cái gì**, và GCC/Make/Ninja nằm ở đâu trong toàn bộ build flow.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các thuật ngữ cần tra cứu đúng theo tài liệu CMake như `source tree`, `build tree`, `target`, `property`, `usage requirement`, `generator`, `configure`, `generate`, `cache`, `toolchain file`, `single-config generator`, `multi-config generator` được giữ nguyên bằng tiếng Anh và giải thích tại vị trí phù hợp.
>
> **Phạm vi:** `CMakeLists.txt`, `cmake_minimum_required()`, `project()`, source/build tree, out-of-source build, generator, target, executable/library target, source, include directory, compile definition/option, link library, target property, usage requirement, `PUBLIC`/`PRIVATE`/`INTERFACE`, variable, cache, build configuration, `add_subdirectory()` và toolchain file ở mức nền tảng. Package management, `install()`/`export()`, `find_package()` nâng cao, generator expression chuyên sâu, presets, custom command phức tạp, testing/CTest, packaging/CPack và CMake internals không thuộc phạm vi chương này.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để xây dựng mental model về CMake. Không có bài thực hành.

Ở Chủ đề 4, ta đã thấy GNU Make giải quyết bài toán build bằng một **dependency graph**:

```text
Source files
    |
    v
Object files
    |
    v
Executable / Library

Makefile
    |
    | mô tả dependency + recipe
    v
GNU Make
    |
    | gọi compiler / linker
    v
Build artifacts
```

Nhưng một project lớn có thể cần được build trên nhiều môi trường khác nhau:

```text
Linux + GNU Make
Linux + Ninja
Windows + Visual Studio
macOS + Xcode
Cross-compile cho ARM Linux
...
```

Nếu project tự viết và duy trì một build description riêng cho từng build tool hoặc từng platform, chi phí bảo trì sẽ tăng nhanh.

CMake đưa thêm một tầng trừu tượng:

```text
                  CMakeLists.txt
                       |
                       | CMake đọc mô tả project
                       v
                     CMake
                       |
                       | generator
                       v
          Native build system được sinh ra
          /             |               \
      Makefiles       Ninja files      IDE project
          |             |               |
          v             v               v
        make          ninja       Visual Studio / ...
          \             |               /
           \            |              /
            +------ compiler/linker ---+
                       |
                       v
                 Build artifacts
```

> **Đọc sơ đồ:** CMake không thay thế compiler và cũng không nhất thiết trực tiếp thay thế Make/Ninja. CMake mô tả project ở mức cao hơn, sau đó **sinh build system** phù hợp với generator đã chọn. Build tool được sinh ra hoặc được điều khiển sau đó mới gọi compiler, linker và các tool khác.

Mental model trung tâm của chương:

```text
CMake project description
        |
        | configure
        v
Project + toolchain + cache
        |
        | generate
        v
Native build system
        |
        | build
        v
Compiler / Linker / Archiver
        |
        v
Executable / Library
```

---

## Mục lục

- [1. CMake giải quyết vấn đề gì?](#1-cmake-giải-quyết-vấn-đề-gì)
- [2. Mental model cốt lõi: Configure → Generate → Build](#2-mental-model-cốt-lõi-configure--generate--build)
- [3. CMake project, source tree và build tree](#3-cmake-project-source-tree-và-build-tree)
- [4. Target là trung tâm của mô hình CMake](#4-target-là-trung-tâm-của-mô-hình-cmake)
- [5. Source file và cấu trúc project nhiều thư mục](#5-source-file-và-cấu-trúc-project-nhiều-thư-mục)
- [6. Target property và compile requirement](#6-target-property-và-compile-requirement)
- [7. Link library và dependency giữa các target](#7-link-library-và-dependency-giữa-các-target)
- [8. `PRIVATE`, `PUBLIC`, `INTERFACE` và usage requirement](#8-private-public-interface-và-usage-requirement)
- [9. Variable, cache và trạng thái của build tree](#9-variable-cache-và-trạng-thái-của-build-tree)
- [10. Generator, native build tool và build configuration](#10-generator-native-build-tool-và-build-configuration)
- [11. CMake và cross-compilation](#11-cmake-và-cross-compilation)
- [12. Tư duy chẩn đoán lỗi theo từng tầng](#12-tư-duy-chẩn-đoán-lỗi-theo-từng-tầng)
- [13. Liên hệ với Embedded Linux](#13-liên-hệ-với-embedded-linux)
- [14. Tổng kết và mô hình tư duy](#14-tổng-kết-và-mô-hình-tư-duy)
- [15. Tài liệu tham khảo](#15-tài-liệu-tham-khảo)

---

## 1. CMake giải quyết vấn đề gì?

Một build system cho project C/C++ thường phải biết nhiều thông tin:

```text
Source nào thuộc executable nào?
Library nào phải được build?
Target nào phụ thuộc library nào?
Header nằm ở include directory nào?
Compile option nào áp dụng cho target nào?
Compiler/toolchain nào được dùng?
Build tool nào sẽ điều khiển quá trình build?
```

GNU Make có thể mô tả toàn bộ những điều đó. Tuy nhiên, Makefile gắn khá trực tiếp với mô hình của Make và với command cụ thể mà project viết ra.

CMake cung cấp một cách mô tả project ở mức cao hơn.

Ví dụ, thay vì mô tả trực tiếp:

```text
main.c -> main.o
foo.c  -> foo.o
main.o + foo.o -> app
```

cùng toàn bộ command compiler/linker tương ứng, CMake có thể mô tả ý định ở mức:

```cmake
add_executable(app
    main.c
    foo.c
)
```

Ý nghĩa chính là:

```text
Project có một executable target tên app
và target đó được tạo từ main.c + foo.c.
```

CMake sau đó chuyển mô hình này thành rule phù hợp với generator và toolchain đang được sử dụng.

### 1.1 CMake không phải compiler

CMake không biến source C thành machine code.

Mô hình đúng:

```text
CMake
  |
  | sinh build rules
  v
Build tool
  |
  | gọi compiler
  v
GCC / Clang / ...
  |
  v
Object file
```

Do đó:

```text
CMake != GCC
CMake != Clang
```

Nếu compiler báo lỗi cú pháp C, bản chất lỗi nằm ở compiler stage, không phải vì CMake tự compile source code.

### 1.2 CMake không đồng nghĩa với Make

Tên `CMake` dễ làm người mới nghĩ rằng nó là một biến thể của GNU Make.

Đó không phải mental model đúng.

```text
CMake
  |
  | có thể sinh
  +------> Unix Makefiles ------> make
  |
  +------> Ninja files ---------> ninja
  |
  +------> Visual Studio project
  |
  +------> Xcode project
  |
  +------> ...
```

GNU Make là một **native build tool** mà CMake có thể dùng thông qua một generator phù hợp.

### 1.3 CMake mô tả intent nhiều hơn command cụ thể

Trong CMake hiện đại, project nên cố gắng mô tả:

```text
Target này là gì?
Target này cần source nào?
Target này cần include directory nào?
Target này phụ thuộc target/library nào?
Requirement nào phải truyền cho consumer?
```

thay vì tự ghép một chuỗi compiler command cố định cho mọi platform.

Đây là lý do mô hình **target-centric** rất quan trọng và sẽ được dùng xuyên suốt chương.

---

## 2. Mental model cốt lõi: Configure → Generate → Build

Toàn bộ workflow CMake có thể hiểu bằng ba giai đoạn logic:

```text
1. Configure
2. Generate
3. Build
```

Mặc dù một invocation CMake thông thường có thể thực hiện cả configure và generate liên tiếp, việc tách ba khái niệm này giúp hiểu đúng vai trò từng tầng.

### 2.1 Configure

Trong configure phase, CMake đọc project description và thu thập thông tin cần thiết.

Mô hình:

```text
CMakeLists.txt
Toolchain information
Cache values
Platform information
        |
        v
     Configure
        |
        v
Internal project model
```

Ở giai đoạn này CMake có thể:

- đọc các `CMakeLists.txt`;
- xử lý variable và điều kiện của CMake language;
- xác định compiler/toolchain;
- xác định platform mục tiêu;
- xử lý các target và dependency;
- đọc hoặc tạo cache của build tree;
- thực hiện một số kiểm tra capability của toolchain khi project yêu cầu.

> **Điểm cần nhớ:** Configure không có nghĩa là "compile toàn bộ project". Nó chủ yếu xây dựng và kiểm tra mô hình build.

### 2.2 Generate

Sau khi có project model hợp lệ, CMake tạo build system tương ứng với generator.

Ví dụ:

```text
Generator = Unix Makefiles
         |
         v
      Makefiles

Generator = Ninja
         |
         v
     build.ninja
```

Generate phase chuyển mô hình CMake sang mô hình mà native build tool hiểu được.

### 2.3 Build

Build phase là lúc native build tool thực thi dependency graph đã được sinh ra.

```text
Generated buildsystem
        |
        v
   make / ninja / IDE
        |
        +----> compiler
        |
        +----> linker
        |
        +----> archiver
        |
        v
 Build artifacts
```

CMake cung cấp giao diện `cmake --build` để điều khiển build theo cách độc lập hơn với generator, nhưng backend thực sự vẫn là native build tool tương ứng.

### 2.4 Ba lớp không nên bị trộn lẫn

Một mental model hữu ích:

```text
CMake language / CMakeLists.txt
            |
            | cấu hình project
            v
Generated build system
            |
            | điều phối dependency
            v
Compiler / linker / tools
            |
            v
Binary artifacts
```

Khi có lỗi, phải xác định lỗi thuộc lớp nào thay vì gọi mọi lỗi là "lỗi CMake".

---

## 3. CMake project, source tree và build tree

Một CMake project thông thường bắt đầu từ file top-level:

```text
CMakeLists.txt
```

Đây là file viết bằng **CMake language**, không phải Makefile và cũng không phải shell script.

Một cấu trúc tối thiểu thường có dạng:

```cmake
cmake_minimum_required(VERSION 3.20)

project(my_app LANGUAGES C)

add_executable(my_app main.c)
```

Con số version ở đây chỉ là ví dụ minh họa; project thực tế phải chọn minimum version theo feature/policy mà nó thực sự cần hỗ trợ.

### 3.1 `cmake_minimum_required()`

`cmake_minimum_required()` khai báo mức CMake tối thiểu mà project yêu cầu và thiết lập policy behavior tương ứng.

Mental model:

```text
Project
  |
  | yêu cầu behavior/API tối thiểu
  v
cmake_minimum_required(...)
```

Nó nên xuất hiện gần đầu top-level `CMakeLists.txt`, trước `project()`.

Không nên hiểu nó chỉ là một "version check trang trí". CMake có hệ thống policy để quản lý thay đổi behavior qua các phiên bản, nên minimum/policy version có ảnh hưởng tới semantics của project.

### 3.2 `project()`

`project()` khai báo project và có thể bật các language cần dùng.

Ví dụ:

```cmake
project(my_app LANGUAGES C)
```

Ở mức chương này, có thể hiểu:

```text
project(... LANGUAGES C)
          |
          v
CMake enable C toolchain
          |
          +--> xác định C compiler
          +--> compiler identification
          +--> các biến/toolchain data liên quan
```

Nếu chỉ xây chương trình C, việc khai báo rõ `LANGUAGES C` giúp mô hình project chính xác hơn thay vì mặc định bật cả C và C++.

### 3.3 CMake language không phải Shell

Ví dụ:

```cmake
set(MY_VALUE hello)
```

không phải cú pháp shell variable.

Tương tự:

```cmake
if(...)
endif()
```

là command/control structure của CMake language.

Do đó:

```text
CMake language != Bash
CMakeLists.txt  != shell script
```

Việc nhầm hai lớp này dễ dẫn tới cách xử lý variable, quoting hoặc command invocation sai.

---


Một trong những mental model quan trọng nhất của CMake là phân biệt:

```text
Source Tree
    và
Build Tree
```

### 3.4 Source tree

`source tree` chứa source code và project description.

Ví dụ logic:

```text
project/
├── CMakeLists.txt
├── src/
│   ├── main.c
│   └── foo.c
└── include/
    └── foo.h
```

Đây là dữ liệu nguồn của project.

### 3.5 Build tree

`build tree` là nơi CMake lưu trạng thái của một cấu hình build và nơi build system/artifact được tạo ra.

Ví dụ:

```text
build/
├── CMakeCache.txt
├── CMakeFiles/
├── generated build files
├── object files
└── executable / library
```

Tùy generator và project, layout thực tế có thể khác.

### 3.6 Out-of-source build

`out-of-source build` nghĩa là source tree và build tree là hai directory khác nhau.

```text
project/
├── CMakeLists.txt
├── src/
└── include/

build/
├── CMakeCache.txt
├── CMakeFiles/
└── ...
```

So với việc đưa generated files vào thẳng source tree:

```text
Source Tree
  + Source files
  + CMake metadata
  + Object files
  + Generated build files
  + Binary
```

out-of-source build giữ ranh giới sạch hơn:

```text
Source Tree                 Build Tree
------------                ----------
Source code                 Cache
CMakeLists.txt              Generated buildsystem
Headers                     Object files
                            Executables/Libraries
```

### 3.7 Một source tree có thể có nhiều build tree

Đây là một lợi ích rất quan trọng:

```text
                 Source Tree
                /     |      \
               /      |       \
              v       v        v
       build-debug  build-arm  build-release
```

Mỗi build tree có thể mang trạng thái khác nhau:

```text
Compiler khác
Toolchain khác
Generator khác
Build configuration khác
Cache khác
```

Đặc biệt trong Embedded Linux, cách tách này rất hữu ích vì cùng một source tree có thể được build cho host và cho target architecture khác nhau.

> **Điểm cần nhớ:** `build/` không chỉ là một directory chứa binary cuối cùng. Nó đại diện cho **một configured build tree** với cache, generator và toolchain context riêng.

---

## 4. Target là trung tâm của mô hình CMake

CMake hiện đại nên được hiểu chủ yếu qua **target**.

Target là một đối tượng logic trong buildsystem, không đơn giản chỉ là một filename.

Ví dụ:

```cmake
add_executable(app
    main.c
    foo.c
)
```

Tạo một executable target có logical name là:

```text
app
```

CMake sẽ dùng thông tin của target để sinh rule compile/link phù hợp.

### 4.1 Executable target

```cmake
add_executable(app main.c foo.c)
```

Mental model:

```text
Target: app
  |
  +-- type: executable
  +-- sources: main.c, foo.c
  +-- include requirements
  +-- compile requirements
  +-- link dependencies
  +-- properties
```

Tên target là identity logic trong CMake. Tên file output thực tế có thể chịu ảnh hưởng bởi platform convention và target property.

### 4.2 Library target

Một library có thể được mô tả bằng `add_library()`.

Ví dụ:

```cmake
add_library(core STATIC
    foo.c
    bar.c
)
```

Mental model:

```text
Target: core
  |
  +-- type: STATIC library
  +-- sources
  +-- compile requirements
  +-- usage requirements
```

Một shared library có thể được mô tả bằng:

```cmake
add_library(core SHARED
    foo.c
    bar.c
)
```

CMake sẽ xử lý nhiều platform convention về tên output, suffix/prefix và command build tương ứng thông qua generator/toolchain.

### 4.3 Target logic khác file output

Không nên đồng nhất:

```text
CMake target name
      ==
physical filename
```

Ví dụ logical target `core` có thể tạo output mang convention khác nhau trên các platform.

Target là đối tượng mà project gắn requirement vào; file output chỉ là một artifact được tạo từ target đó.

### 4.4 Dependency nên được mô tả giữa target với target khi có thể

Nếu project có:

```text
app
 |
 +--> core library
```

mô hình tốt là để CMake biết `core` là một target và `app` phụ thuộc target đó.

Khi dependency được biểu diễn bằng target, CMake hiểu được nhiều metadata hơn so với việc chỉ đưa một chuỗi filename library vào command line.

Đây là nền tảng cho usage requirement ở phần sau.

---

## 5. Source file và cấu trúc project nhiều thư mục

Target thường được tạo từ nhiều source file.

Ví dụ:

```cmake
add_library(core STATIC
    foo.c
    bar.c
)
```

Ở đây `foo.c` và `bar.c` là source thuộc target `core`.

### 5.1 Source file thuộc target nào mới là câu hỏi quan trọng

Mental model:

```text
foo.c ----\
           +--> core target
bar.c ----/
```

Sau đó CMake sinh compile rule tương ứng cho từng source rồi link/archive thành output của target.

Điều này nối trực tiếp với GCC Build Flow đã học:

```text
foo.c --> foo.o --\
                   +--> libcore.a
bar.c --> bar.o --/
```

CMake không thay đổi bản chất pipeline; nó chỉ mô tả và tự động sinh các build rule cần thiết.

### 5.2 Header và source không có cùng vai trò

Header thường được đưa vào source code bằng `#include`, còn compiler cần **include search path** để tìm header.

Do đó cần phân biệt:

```text
Source file list
      !=
Include directory list
```

Một header có thể được liệt kê trong metadata/source list để project structure rõ hơn, nhưng việc compiler tìm được:

```c
#include <foo.h>
```

phụ thuộc vào include search path và layout phù hợp, không phải chỉ vì tên header xuất hiện đâu đó trong `add_library()`.

### 5.3 Project nhiều directory

Project thực tế thường có dạng:

```text
project/
├── CMakeLists.txt
├── app/
│   ├── CMakeLists.txt
│   └── main.c
└── core/
    ├── CMakeLists.txt
    ├── foo.c
    └── include/
        └── foo.h
```

CMake hỗ trợ cấu trúc phân cấp bằng `add_subdirectory()`.

Mental model:

```text
Top-level CMakeLists.txt
        |
        +--> add_subdirectory(core)
        |
        +--> add_subdirectory(app)
```

Mỗi subdirectory có thể khai báo target của nó, nhưng các target cùng tham gia vào buildsystem tổng thể.

### 5.4 Directory structure không nên thay thế target dependency

Việc một target nằm trong subdirectory khác không tự nói rằng hai target phụ thuộc nhau.

Ví dụ:

```text
app/
core/
```

không tự tạo dependency:

```text
app --> core
```

Dependency vẫn phải được mô tả thông qua target relationship thích hợp, thường là link dependency hoặc dependency command tương ứng.

---

## 6. Target property và compile requirement

Một target trong CMake mang nhiều **property** mô tả cách nó được compile, link hoặc được consumer sử dụng.

Mental model:

```text
Target
  |
  +-- sources
  +-- include directories
  +-- compile definitions
  +-- compile options
  +-- link libraries
  +-- language standard
  +-- output properties
  +-- interface requirements
  +-- ...
```

CMake cung cấp nhiều command theo mô hình:

```text
target_<something>(target ...)
```

Ví dụ:

```cmake
target_include_directories(...)
target_compile_definitions(...)
target_compile_options(...)
target_link_libraries(...)
target_sources(...)
```

### 6.1 Target-scoped setting giúp giảm ảnh hưởng ngoài ý muốn

Giả sử project có hai target:

```text
app
libA
```

Nếu một compiler option chỉ cần cho `libA`, mental model tốt là:

```text
libA
 |
 +-- option X

app
 |
 +-- không nhận option X trừ khi dependency interface yêu cầu
```

Thay vì áp dụng option toàn cục cho mọi target.

### 6.2 Target property là state của target

Các `target_*` command thường cập nhật property của target.

Ví dụ về mặt khái niệm:

```cmake
target_include_directories(core PRIVATE include)
```

có thể hiểu là:

```text
core target
  |
  +--> compile include requirement: include/
```

Một số property còn có `INTERFACE_...` counterpart để biểu diễn requirement truyền sang consumer.

### 6.3 Modern CMake thiên về target-centric model

CMake vẫn có nhiều command/variable mang tính directory-wide hoặc global vì lý do lịch sử và nhiều use case khác nhau.

Tuy nhiên với project mới, target-scoped API thường tạo dependency và scope rõ ràng hơn:

```text
Setting gắn đúng target
        |
        v
Ít side effect hơn
        |
        v
Dependency model dễ reasoning hơn
```

> **Điểm cần nhớ:** CMake không chỉ là tập hợp variable. Mental model mạnh hơn là **target + property + dependency + usage requirement**.

---


Ba loại thông tin này đều ảnh hưởng compilation nhưng có ý nghĩa khác nhau.

### 6.4 Include directory

Ví dụ source có:

```c
#include <foo/foo.h>
```

Compiler cần biết những directory nào phải được tìm kiếm.

Trong CMake, requirement này có thể được gắn vào target:

```cmake
target_include_directories(core
    PUBLIC include
)
```

Về mặt compiler, CMake có thể chuyển thông tin đó thành option thích hợp như `-I...` hoặc equivalent của toolchain.

Mental model:

```text
CMake include directory
        |
        | generator/toolchain mapping
        v
Compiler include search path
```

### 6.5 Include directory không phải library directory

Cần phân biệt:

```text
include directory
    |
    +--> compiler tìm header

library/link dependency
    |
    +--> linker tìm/nhận library cần link
```

Hai khái niệm thuộc hai stage khác nhau của build flow.

### 6.6 Compile definition

Preprocessor definition như:

```c
#ifdef FEATURE_X
```

có thể được cung cấp cho target bằng `target_compile_definitions()`.

Ví dụ:

```cmake
target_compile_definitions(core PRIVATE FEATURE_X=1)
```

Mental model:

```text
CMake definition
      |
      v
Preprocessor definition
      |
      v
Compilation behavior
```

### 6.7 Compile option

Các compiler option khác có thể được gắn qua `target_compile_options()`.

Ví dụ về mặt ý nghĩa:

```cmake
target_compile_options(core PRIVATE ...)
```

Cần phân biệt:

```text
Compile definition  -> preprocessor macro
Include directory   -> header search path
Compile option      -> option khác của compiler
```

Không nên dồn mọi loại setting vào một chuỗi flag toàn cục nếu CMake có abstraction cụ thể hơn cho semantics đó.

---

## 7. Link library và dependency giữa các target

Giả sử project có:

```text
core library
app executable
```

và `app` sử dụng symbol do `core` cung cấp.

Mô hình build flow:

```text
main.c ---------> main.o -----\
                              +--> app
core source ----> libcore.a --/
```

CMake có thể mô tả dependency bằng:

```cmake
target_link_libraries(app
    PRIVATE core
)
```

### 7.1 Khi `core` là CMake target

CMake hiểu đây không chỉ là một string library name mà là dependency giữa hai target:

```text
app
 |
 +--> core
```

Từ đó CMake có thể suy ra:

```text
core phải được build khi cần
        |
        v
app mới được link với output phù hợp của core
```

và có thể truyền usage requirement từ `core` sang `app` theo interface đã khai báo.

### 7.2 Link dependency và build-order dependency có liên hệ nhưng không đồng nhất

Nếu `app` link `core`, relation đó có cả ý nghĩa build dependency và link information.

Nhưng không phải mọi dependency trong buildsystem đều là link dependency.

Ví dụ generated file hoặc custom target có thể tạo dependency thứ tự mà không hề tham gia linker command.

Ở mức chủ đề này cần nhớ:

```text
Link dependency
    là một loại dependency có semantics liên quan linking,
    không phải tên chung cho mọi dependency trong CMake.
```

### 7.3 Prefer target identity thay vì tự ghép linker flag khi có thể

Nếu dependency là một target CMake, việc link bằng target name cho phép CMake giữ nhiều metadata hơn:

```text
Target identity
  |
  +-- output location
  +-- build dependency
  +-- usage requirements
  +-- platform-specific details
```

Trong khi một chuỗi raw như:

```text
-lcore
```

chỉ truyền một phần intent xuống linker và không tự biểu diễn đầy đủ mô hình target của CMake.

### 7.4 `target_link_directories()` không phải lựa chọn mặc định cho mọi library

Một hiểu lầm phổ biến là:

```text
Muốn link library
=> luôn phải thêm library directory
```

Trong CMake, nếu library là target hoặc đã có full path/được tìm bằng cơ chế thích hợp, việc thêm global/search directory không nhất thiết cần thiết.

Tài liệu CMake cũng khuyến nghị tránh `target_link_directories()` khi có thể dùng target hoặc full path rõ ràng hơn, vì search path có thể khiến linker chọn nhầm library cùng tên.

---

## 8. `PRIVATE`, `PUBLIC`, `INTERFACE` và usage requirement

Đây là một trong những khái niệm quan trọng nhất của modern CMake.

Giả sử:

```text
app ---> core
```

`app` là **consumer** của `core`.

Một requirement có thể chỉ cần cho `core`, hoặc còn cần cho consumer của `core`.

CMake dùng ba scope phổ biến:

```text
PRIVATE
PUBLIC
INTERFACE
```

### 8.1 `PRIVATE`

`PRIVATE` nghĩa là requirement cần cho chính target, nhưng không được công bố như usage requirement cho consumer.

```text
core
 |
 +-- PRIVATE requirement
 |
 v
Dùng khi build core

app ---> core
 |
 +-- không tự nhận requirement đó như interface của core
```

Ví dụ điển hình: header nội bộ chỉ source của `core` sử dụng.

### 8.2 `PUBLIC`

`PUBLIC` nghĩa là requirement cần cho cả target và consumer.

```text
          PUBLIC requirement
                |
          +-----+-----+
          |           |
          v           v
        core         app
                    consumer
```

Ví dụ một public header của library chứa:

```c
#include <dependency/header.h>
```

thì consumer include public header đó cũng có thể cần include requirement tương ứng.

### 8.3 `INTERFACE`

`INTERFACE` nghĩa là requirement dành cho consumer, không dùng để build implementation của target đó.

```text
core
 |
 | interface requirement
 v
consumer
```

Đây là nền tảng cho `INTERFACE` library và header-only usage model, dù chi tiết nâng cao chưa cần đi sâu trong chủ đề này.

### 8.4 Bảng mental model

| Scope | Target dùng | Consumer nhận |
|---|---:|---:|
| `PRIVATE` | Có | Không |
| `PUBLIC` | Có | Có |
| `INTERFACE` | Không | Có |

Bảng trên diễn tả **usage requirement semantics** ở mức cơ bản.

### 8.5 Usage requirement lan truyền theo dependency graph

Giả sử:

```text
app ---> middleware ---> core
```

Nếu `core` công bố một requirement qua interface, và dependency relationship ở các tầng cho phép propagation, CMake có thể truyền requirement đó tới consumer phù hợp.

Mental model:

```text
core
 |
 | INTERFACE_* properties
 v
middleware
 |
 | propagated usage requirements
 v
app
```

Đây là điểm khác biệt lớn giữa:

```text
"thêm flag toàn cục"
```

và:

```text
"mô tả requirement thuộc target nào và consumer nào cần nó"
```

### 8.6 `PUBLIC` không có nghĩa "mọi target trong project"

`PUBLIC` trong CMake không có nghĩa global.

Nó có nghĩa:

```text
Requirement áp dụng cho target
+
được đưa vào usage interface cho consumer của target.
```

Một target không phụ thuộc target đó sẽ không tự nhiên nhận requirement chỉ vì keyword là `PUBLIC`.

---

## 9. Variable, cache và trạng thái của build tree

CMake có variable, nhưng cần phân biệt variable với target property và cache entry.

Mental model:

```text
Variable
  |
  +--> giá trị dùng trong quá trình xử lý CMake language

Target Property
  |
  +--> metadata/requirement gắn với target

Cache Entry
  |
  +--> giá trị persistent thuộc configured build tree
```

### 9.1 Normal variable

Ví dụ:

```cmake
set(MY_SOURCES
    foo.c
    bar.c
)
```

Sau đó:

```cmake
add_library(core STATIC ${MY_SOURCES})
```

Variable giúp tổ chức logic CMake nhưng variable không tự tạo target hay dependency.

### 9.2 Variable không phải target property

Ví dụ:

```text
CFLAGS-like variable
```

và:

```text
target_compile_options(core ...)
```

không có cùng semantic scope.

Target property gắn rõ với target. Variable chỉ là dữ liệu mà CMake language có thể sử dụng để tạo hoặc cấu hình object/model khác.

### 9.3 Cache là trạng thái persistent của build tree

Khi configure một build tree, CMake tạo và sử dụng:

```text
CMakeCache.txt
```

Cache có thể chứa:

```text
Compiler path
Detected toolchain information
User-configurable options
Search/result information
Project configuration values
...
```

Quan trọng là:

```text
Cache thuộc Build Tree
```

không thuộc source tree về mặt conceptual ownership.

### 9.4 `CMakeCache.txt` không phải file project nên sửa tùy ý

Cache được CMake quản lý.

Người dùng có thể cấu hình cache entry thông qua interface thích hợp, nhưng việc mở file `CMakeCache.txt` và chỉnh ngẫu nhiên không phải cách thiết kế project tốt.

Đặc biệt khi thay đổi những yếu tố nền tảng như compiler/toolchain, một build tree cũ có thể đang giữ nhiều state không còn phù hợp.

Mental model an toàn:

```text
Build Tree A
  |
  +-- toolchain/configuration A

Build Tree B
  |
  +-- toolchain/configuration B
```

thay vì cố biến một build tree đã được configure cho môi trường A thành môi trường hoàn toàn khác mà không hiểu cache state.

### 9.5 `-D...` thường tạo/cập nhật cache entry

CMake command line cho phép cấu hình giá trị dạng:

```text
-DNAME=value
```

Ở mức mental model:

```text
User configuration
       |
       v
Cache entry
       |
       v
Configure logic
```

Nhưng không nên hiểu mọi CMake variable đều là cache variable. Hai loại có lifetime/scope khác nhau.

---

## 10. Generator, native build tool và build configuration

CMake cần một **generator** để quyết định dạng buildsystem được sinh ra.

Ví dụ:

```text
CMake
 |
 +--> Unix Makefiles generator
 |       |
 |       v
 |    GNU Make compatible buildsystem
 |
 +--> Ninja generator
 |       |
 |       v
 |    Ninja buildsystem
 |
 +--> Visual Studio generator
         |
         v
      VS project/solution
```

### 10.1 Generator không phải compiler

Cần tách:

```text
Generator
    |
    +--> quyết định native buildsystem format

Compiler
    |
    +--> compile source
```

Có thể cùng GCC compiler nhưng dùng generator khác:

```text
CMake + Unix Makefiles + GCC
CMake + Ninja          + GCC
```

Kết quả build pipeline về compiler có thể tương tự, nhưng build backend khác nhau.

### 10.2 `cmake --build` là abstraction phía trên native build tool

CMake cung cấp một interface chung:

```text
cmake --build <build-tree>
```

Mental model:

```text
cmake --build
      |
      | biết generator của build tree
      v
native build tool
      |
      v
actual build
```

Nó không có nghĩa CMake tự biến thành compiler/linker.

### 10.3 Single-config generator và multi-config generator

Không phải mọi generator xử lý build configuration giống nhau.

Có hai mô hình lớn:

```text
Single-config generator
        |
        +--> một build tree thường được configure cho một configuration

Multi-config generator
        |
        +--> một generated project có thể hỗ trợ nhiều configuration
```

Ví dụ phổ biến:

- Unix Makefiles và Ninja truyền thống thường là single-config;
- Visual Studio, Xcode và Ninja Multi-Config là multi-config.

### 10.4 `CMAKE_BUILD_TYPE` không phải khái niệm áp dụng giống nhau cho mọi generator

Với single-config generator, `CMAKE_BUILD_TYPE` thường chọn configuration như:

```text
Debug
Release
RelWithDebInfo
MinSizeRel
```

Với multi-config generator, configuration thường được chọn tại build time và `CMAKE_BUILD_TYPE` không đóng vai trò tương tự.

> **Điểm cần nhớ:** Khi đọc tài liệu hoặc build script, luôn hỏi generator thuộc single-config hay multi-config trước khi suy luận behavior của build configuration.

---

## 11. CMake và cross-compilation

Chủ đề 2 đã xây mental model:

```text
HOST
 |
 | cross toolchain
 v
TARGET binary
```

CMake không thay đổi nguyên lý đó.

Nó chỉ cần biết toolchain/platform mục tiêu để sinh buildsystem đúng.

### 11.1 Native build và cross build khác nhau ở toolchain context

Native:

```text
CMake chạy trên x86_64 Linux
        |
        +--> GCC x86_64
        |
        v
x86_64 ELF
```

Cross:

```text
CMake chạy trên x86_64 Linux
        |
        +--> AArch64 cross compiler
        +--> target sysroot
        +--> target platform information
        |
        v
AArch64 ELF
```

CMake vẫn chạy trên host. Output binary có thể dành cho target khác.

### 11.2 Toolchain file

CMake hỗ trợ `toolchain file` để cung cấp thông tin cross-compilation từ rất sớm trong configure process.

Một toolchain file Linux điển hình có thể mô tả các ý như:

```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_SYSROOT /path/to/sysroot)
```

Đây chỉ là mô hình minh họa; toolchain thực tế còn phụ thuộc toolchain distribution và project.

Mental model:

```text
Toolchain file
   |
   +-- target system
   +-- target processor
   +-- compiler
   +-- sysroot/search policy
   +-- toolchain-specific settings
   |
   v
CMake configure
   |
   v
Generated buildsystem cho target
```

### 11.3 Toolchain file được đọc sớm

Điểm quan trọng là compiler/platform phải được xác định trước khi CMake hoàn tất việc enable language và kiểm tra toolchain.

Do đó toolchain file không nên được xem như một config file tùy ý đọc rất muộn sau khi project đã cấu hình xong compiler.

### 11.4 `CMAKE_SYSROOT` và sysroot của toolchain

Khi phù hợp, CMake có thể dùng `CMAKE_SYSROOT` để mô tả sysroot target và truyền thông tin đó xuống toolchain/search logic.

Nhưng cần giữ mental model từ Chủ đề 2:

```text
Sysroot
  !=
Root filesystem đang chạy của host
```

và cũng không đồng nghĩa mọi root filesystem target đều có thể dùng trực tiếp làm sysroot hoàn chỉnh mà không xét header/library/development files.

### 11.5 Không nên hard-code cross compiler vào project logic chung nếu không cần thiết

Một project có thể cần build:

```text
Host x86_64
Target AArch64
Target ARM32
```

Nếu `CMakeLists.txt` gắn cứng một compiler cụ thể, khả năng tái sử dụng build description giảm đi.

Mental model tốt hơn:

```text
Project description
        |
        +--> target relationships
        +--> build requirements

Toolchain description
        |
        +--> compiler/platform/sysroot
```

Tách hai concern này giúp cùng source/project model có thể được configure với nhiều toolchain khác nhau.

---

## 12. Tư duy chẩn đoán lỗi theo từng tầng

Khi dùng CMake, một message xuất hiện trong terminal chưa đủ để kết luận "CMake bị lỗi".

Cần xác định tầng gây lỗi.

Mental model:

```text
CMake Configure
      |
      v
CMake Generate
      |
      v
Native Build Tool
      |
      v
Compiler / Linker
      |
      v
Runtime
```

### 12.1 Configure error

Ví dụ nhóm lỗi:

```text
CMake command sai
File/path cần thiết không tồn tại
Target được tham chiếu trước khi được định nghĩa theo cách không hợp lệ
Compiler không được nhận diện/cấu hình được
Logic CMake language sai
```

Dấu hiệu quan trọng là buildsystem chưa được configure thành công.

### 12.2 Generate error

Một số vấn đề chỉ lộ khi CMake tạo buildsystem cuối cùng, ví dụ một số property/dependency conflict hoặc generator-specific requirement.

Mental model:

```text
Configure model có thể được đọc
        |
        v
Generate kiểm tra/chuyển model
        |
        X
Không tạo được native buildsystem hợp lệ
```

### 12.3 Native build tool error

Nếu CMake đã generate xong và build tool bắt đầu chạy, lỗi có thể thuộc Make/Ninja hoặc dependency graph đã sinh.

Ví dụ:

```text
Backend không tìm được rule/artifact
Generated command thất bại
```

Cần đọc command và context thực tế thay vì chỉ nhìn prefix của log.

### 12.4 Compiler error

Ví dụ:

```text
syntax error
unknown type
header not found
warning-as-error
```

Đây là compiler/preprocessor layer.

CMake có thể là nguyên nhân gián tiếp nếu include directory/definition/flag được cấu hình sai, nhưng message cuối cùng vẫn đến từ compiler.

Mental model:

```text
Compiler says "header not found"
        |
        v
Kiểm tra include requirement của target
        |
        v
Kiểm tra CMake model sinh compiler command gì
```

### 12.5 Linker error

Ví dụ:

```text
undefined reference
multiple definition
incompatible object/library
```

Đây là link layer.

CMake có thể mô tả thiếu/sai `target_link_libraries()`, nhưng phải quay lại mental model symbol/linking từ Chủ đề 1 và library từ Chủ đề 3 để phân tích.

### 12.6 Runtime error không phải build error

Nếu binary đã build thành công nhưng chạy trên target bị:

```text
missing shared library
wrong loader
Exec format error
segmentation fault
```

thì cần phân biệt runtime/target compatibility với CMake configure/build failure.

Ví dụ:

```text
Exec format error
```

có thể là dấu hiệu binary dành cho architecture khác, nối trực tiếp với Chủ đề 2.

### 12.7 Đừng sửa sai tầng

Một nguyên tắc rất quan trọng:

```text
Compiler error
   != sửa bằng cách thay generator ngẫu nhiên

Linker undefined reference
   != sửa bằng cách thêm include directory

Header not found
   != sửa bằng cách thêm link library một cách mù quáng
```

CMake chỉ hiệu quả khi mental model về GCC build flow, toolchain, library và dependency ở các topic trước đã rõ.

---

## 13. Liên hệ với Embedded Linux

CMake xuất hiện rất thường xuyên trong userspace software, SDK, middleware và thư viện được build cho Embedded Linux.

Nhưng cần đặt nó đúng tầng.

### 13.1 CMake nằm ở build-description layer

Một stack khái quát:

```text
Application / Library source
          |
          v
      CMake project
          |
          v
Generated native buildsystem
          |
          v
Make / Ninja / ...
          |
          v
Cross compiler + linker
          |
          v
Target ELF / .so / .a
```

CMake không thay thế cross toolchain.

### 13.2 CMake không tự biến host compiler thành cross compiler

Nếu project phải tạo AArch64 binary:

```text
CMake
  |
  | cần được configure với target toolchain phù hợp
  v
AArch64 compiler + target sysroot
```

Nếu CMake vẫn dùng host GCC x86_64, output vẫn là host binary dù project source giống hệt.

### 13.3 Source tree có thể dùng cho host tool và target artifact

Embedded project đôi khi vừa cần:

```text
Host tools
Target libraries/applications
```

Ví dụ:

```text
Code generator chạy trên x86_64 host
        |
        +--> tạo source/data
                 |
                 v
        AArch64 target program
```

Điều này làm nổi bật lại ba khái niệm:

```text
build/host environment
        !=
target architecture
        !=
project source tree
```

CMake có thể tham gia mô tả các phần đó, nhưng project phải tổ chức dependency và toolchain boundary đúng.

### 13.4 Một build tree nên gắn với một toolchain context rõ ràng

Trong Embedded Linux, cách tổ chức dễ reasoning là:

```text
source/

build-host/
  -> host compiler

build-aarch64/
  -> AArch64 toolchain

build-arm32/
  -> ARM32 toolchain
```

Mỗi build tree có cache/toolchain state riêng.

Điều này giúp tránh việc target object/library của architecture này bị trộn vào build của architecture khác.

### 13.5 CMake thường chỉ là một thành phần của hệ build lớn hơn

Trong Embedded Linux, các hệ thống như Buildroot, Yocto Project hoặc SDK vendor có thể gọi CMake như build system của một package.

Mental model:

```text
Embedded Linux build framework
          |
          | cung cấp toolchain/sysroot/config
          v
        CMake
          |
          v
Package buildsystem
          |
          v
Target artifacts
```

Do đó:

```text
CMake != toàn bộ Embedded Linux build system
```

Nó thường là build system của **một package/project** nằm bên trong workflow lớn hơn.

---

## 14. Tổng kết và mô hình tư duy

### 14.1 Mô hình toàn chương

Có thể gom toàn bộ CMake Fundamentals thành sơ đồ:

```text
                       Source Tree
                CMakeLists.txt + source
                           |
                           |
                           v
                    CMake Configure
                           |
              +------------+-------------+
              |                          |
        Toolchain info                Cache
              |                          |
              +------------+-------------+
                           |
                           v
                     CMake Generate
                           |
                           v
                 Native Build System
                 /        |         \
            Makefiles   Ninja     IDE project
                 \        |         /
                  \       |        /
                   v      v       v
                  Native Build Tool
                           |
              +------------+------------+
              |            |            |
              v            v            v
           Compiler      Linker       Archiver
              |            |            |
              +------------+------------+
                           |
                           v
                   Build Artifacts
```

Target model nằm xuyên suốt ở giữa:

```text
Target
 |
 +-- Source
 +-- Include directories
 +-- Compile definitions/options
 +-- Link dependencies
 +-- Properties
 +-- Usage requirements
 |
 v
Generated build rules
```

### 14.2 Những phân biệt cần nhớ

```text
CMake                    != Compiler
CMake                    != Linker
CMake                    != GNU Make
CMake                    != Ninja
CMakeLists.txt           != Makefile
CMakeLists.txt           != Shell script

Source Tree              != Build Tree
Target logical name      != Physical output filename
Source list              != Include directory list
Include directory        != Link library
Variable                 != Target property
Normal variable          != Cache entry
Generator                != Compiler
Build configuration      != Generator
Toolchain file           != CMake project description
CMake build error        != mọi compiler/linker/runtime error
```

### 14.3 Chuỗi reasoning nên hình thành

Khi nhìn một CMake project, nên suy nghĩ theo thứ tự:

```text
1. Source tree ở đâu?
        |
2. Build tree nào đang được dùng?
        |
3. Generator nào tạo native buildsystem?
        |
4. Toolchain/compiler nào đang được configure?
        |
5. Project có những target nào?
        |
6. Source thuộc target nào?
        |
7. Include/compile requirement thuộc target nào?
        |
8. Target nào link/phụ thuộc target nào?
        |
9. Requirement nào PRIVATE/PUBLIC/INTERFACE?
        |
10. Lỗi đang xảy ra ở configure, generate, build, compile, link hay runtime?
```

Nếu trả lời được chuỗi câu hỏi này, người học đã có mental model nền tảng đủ tốt để đọc phần lớn CMake project C nhỏ và tiếp tục sang cross-compilation phức tạp hơn sau này.

### 14.4 Cầu nối tới Chủ đề 6

CMake giúp tạo executable/library đúng cách, nhưng khi chương trình đã build thành công mà hành vi runtime sai, ta cần một lớp công cụ khác:

```text
Build thành công
      |
      v
Program chạy sai / crash
      |
      v
Debugger
      |
      v
GDB
```

Chủ đề tiếp theo sẽ tập trung vào **GDB Fundamentals**: debug symbol, breakpoint, `step`/`next`, variable, register, stack frame, backtrace và cách phân tích lỗi runtime cơ bản.

---

## 15. Tài liệu tham khảo

### 15.1 CMake — tài liệu chính thức

- **CMake command-line tool (`cmake(1)`)**  
  https://cmake.org/cmake/help/latest/manual/cmake.1.html

- **CMake Buildsystem (`cmake-buildsystem(7)`)**  
  https://cmake.org/cmake/help/latest/manual/cmake-buildsystem.7.html

- **CMake Language (`cmake-language(7)`)**  
  https://cmake.org/cmake/help/latest/manual/cmake-language.7.html

- **CMake Toolchains (`cmake-toolchains(7)`)**  
  https://cmake.org/cmake/help/latest/manual/cmake-toolchains.7.html

- **CMake Generators (`cmake-generators(7)`)**  
  https://cmake.org/cmake/help/latest/manual/cmake-generators.7.html

- **CMake Tutorial**  
  https://cmake.org/cmake/help/latest/guide/tutorial/index.html

### 15.2 Các command quan trọng trong chương

- `cmake_minimum_required()`  
  https://cmake.org/cmake/help/latest/command/cmake_minimum_required.html

- `project()`  
  https://cmake.org/cmake/help/latest/command/project.html

- `add_executable()`  
  https://cmake.org/cmake/help/latest/command/add_executable.html

- `add_library()`  
  https://cmake.org/cmake/help/latest/command/add_library.html

- `add_subdirectory()`  
  https://cmake.org/cmake/help/latest/command/add_subdirectory.html

- `target_sources()`  
  https://cmake.org/cmake/help/latest/command/target_sources.html

- `target_include_directories()`  
  https://cmake.org/cmake/help/latest/command/target_include_directories.html

- `target_compile_definitions()`  
  https://cmake.org/cmake/help/latest/command/target_compile_definitions.html

- `target_compile_options()`  
  https://cmake.org/cmake/help/latest/command/target_compile_options.html

- `target_link_libraries()`  
  https://cmake.org/cmake/help/latest/command/target_link_libraries.html

### 15.3 Tài liệu nền tảng liên quan

Để hiểu sâu những gì CMake đang sinh ra phía dưới, cần nối lại với các chủ đề trước:

```text
GCC Build Flow
    |
    +--> compile / link / object / ELF / symbol

Native & Cross Toolchain
    |
    +--> architecture / ABI / sysroot / cross compiler

Static & Dynamic Library
    |
    +--> .a / .so / linker / runtime loader

GNU Make
    |
    +--> dependency graph / target / prerequisite / incremental build

CMake
    |
    +--> mô tả target ở mức cao và sinh native buildsystem
```

CMake không loại bỏ các lớp phía dưới. Nó chỉ tổ chức và mô tả chúng ở một tầng abstraction cao hơn.
