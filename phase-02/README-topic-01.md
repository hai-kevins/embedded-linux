# Chủ đề 1 — GCC Build Flow

> **Mục tiêu:** Hiểu bản chất của quá trình biến mã nguồn C thành chương trình có thể được Linux nạp và thực thi; phân biệt rõ bốn giai đoạn `Preprocess → Compile → Assemble → Link`; hiểu vai trò của GCC driver, compiler, assembler, linker, object file, ELF, section, symbol và relocation ở mức nền tảng.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các thuật ngữ cần tra cứu đúng theo tài liệu GCC/GNU Binutils/ELF như `preprocessor`, `translation unit`, `compiler`, `assembler`, `linker`, `object file`, `ELF`, `section`, `symbol`, `relocation`, `entry point` được giữ nguyên bằng tiếng Anh và giải thích tại vị trí phù hợp.
>
> **Phạm vi:** Luồng build chương trình C trên Linux, GCC driver, preprocessing, compilation, assembly, linking, object file, ELF ở mức cơ bản, section, symbol, relocation và vai trò khái quát của các công cụ `file`, `readelf`, `nm`, `objdump`. Cross-compilation, ABI/sysroot, static/shared library, Makefile, CMake và GDB sẽ được học ở các chủ đề tiếp theo.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để xây dựng mô hình tư duy về toolchain và luồng build. Không có bài thực hành.

Khi nhìn một lệnh như `gcc main.c -o app`, rất dễ hình thành cảm giác rằng GCC nhận một file C rồi trực tiếp "biến" nó thành chương trình chạy được. Thực tế, phía sau là một chuỗi xử lý gồm nhiều tầng, mỗi tầng giải quyết một bài toán khác nhau và tạo ra một loại đầu ra khác nhau.

Mô hình trung tâm của chương này là:

```text
Mã nguồn C
    |
    | Preprocess
    v
Mã nguồn C đã tiền xử lý
    |
    | Compile
    v
Assembly
    |
    | Assemble
    v
Object file
    |
    | Link
    v
ELF executable
```

> **Đọc sơ đồ:** Source C chưa đi thẳng thành executable. Preprocessor xử lý các chỉ thị tiền xử lý; compiler chuyển chương trình C sang mã Assembly cho kiến trúc đích; assembler mã hóa Assembly thành machine code nằm trong object file; cuối cùng linker ghép các object file và giải quyết các tham chiếu giữa chúng để tạo output cuối cùng.

Nếu hiểu rõ pipeline này, các khái niệm như `.i`, `.s`, `.o`, symbol, `undefined reference` hay ELF không còn là những chi tiết rời rạc. Chúng đều nằm ở một vị trí cụ thể trong cùng một chuỗi build.

---

## Mục lục

- [1. Build một chương trình C thực chất là gì?](#1-build-một-chương-trình-c-thực-chất-là-gì)
- [2. `gcc` là compiler hay compiler driver?](#2-gcc-là-compiler-hay-compiler-driver)
- [3. Giai đoạn 1 — Preprocess và `translation unit`](#3-giai-đoạn-1--preprocess-và-translation-unit)
- [4. Giai đoạn 2 — Compile](#4-giai-đoạn-2--compile)
- [5. Giai đoạn 3 — Assemble](#5-giai-đoạn-3--assemble)
- [6. Object file và `separate compilation`](#6-object-file-và-separate-compilation)
- [7. ELF và section ở mức cơ bản](#7-elf-và-section-ở-mức-cơ-bản)
- [8. Symbol: tên dùng để nối các thành phần chương trình](#8-symbol-tên-dùng-để-nối-các-thành-phần-chương-trình)
- [9. Relocation: vì sao object file chưa biết địa chỉ cuối cùng?](#9-relocation-vì-sao-object-file-chưa-biết-địa-chỉ-cuối-cùng)
- [10. Giai đoạn 4 — Link](#10-giai-đoạn-4--link)
- [11. Object file, executable, section và segment](#11-object-file-executable-section-và-segment)
- [12. Các option GCC phản ánh từng stage như thế nào?](#12-các-option-gcc-phản-ánh-từng-stage-như-thế-nào)
- [13. `file`, `readelf`, `nm`, `objdump` quan sát lớp nào?](#13-file-readelf-nm-objdump-quan-sát-lớp-nào)
- [14. Lỗi build và tư duy gỡ lỗi theo từng tầng](#14-lỗi-build-và-tư-duy-gỡ-lỗi-theo-từng-tầng)
- [15. Liên hệ với Embedded Linux](#15-liên-hệ-với-embedded-linux)
- [16. Tổng kết và mô hình tư duy](#16-tổng-kết-và-mô-hình-tư-duy)
- [17. Tài liệu tham khảo](#17-tài-liệu-tham-khảo)

---

## 1. Build một chương trình C thực chất là gì?

Trong giao tiếp hằng ngày, từ "compile" thường được dùng theo nghĩa rộng để chỉ toàn bộ quá trình biến source code thành chương trình. Tuy nhiên khi học toolchain, cần tách rõ **build** và **compile proper**.

Mô hình tổng quát:

```text
Build
  |
  +-- Preprocess
  |
  +-- Compile
  |
  +-- Assemble
  |
  +-- Link
```

Ở đây:

*   **Preprocess:** Xử lý các chỉ thị tiền xử lý như `#include`, `#define`, `#if`.
*   **Compile:** Phân tích chương trình C và sinh biểu diễn Assembly phù hợp với kiến trúc đích.
*   **Assemble:** Chuyển Assembly thành machine code và đặt nó trong object file.
*   **Link:** Ghép các object file và thành phần cần thiết, giải quyết symbol và relocation để tạo output cuối cùng.

Vì vậy, khi nói chính xác:

```text
Build  ≠  Compile proper
```

`Compile proper` chỉ là một stage bên trong quy trình build rộng hơn.

### 1.1 Vì sao pipeline lại được chia thành nhiều giai đoạn?

Mỗi giai đoạn giải quyết một lớp vấn đề khác nhau:

```text
Source C
   |
   | Các macro và #include có ý nghĩa gì?
   v
Preprocessor
   |
   | Chương trình C này mô tả tính toán nào?
   v
Compiler
   |
   | Instruction Assembly được mã hóa thành byte nào?
   v
Assembler
   |
   | Các object file tham chiếu lẫn nhau như thế nào?
   v
Linker
```

Sự phân tách này đem lại một số đặc tính quan trọng:

*   Mỗi source file có thể được xử lý tương đối độc lập trước bước link.
*   Object file đã tạo có thể được tái sử dụng nếu source tương ứng không thay đổi.
*   Nhiều object file khác nhau có thể được ghép thành một executable.
*   Library có thể cung cấp code đã được build sẵn thay vì phải biên dịch lại toàn bộ source.
*   Toolchain có thể thay đổi target architecture mà vẫn giữ mô hình pipeline tương tự.

Đây là nền tảng để hiểu Makefile, CMake và cross-compilation ở các chủ đề sau.

### 1.2 `.c → .i → .s → .o → executable` là mô hình logic

Một cách biểu diễn rất phổ biến là:

```text
main.c
  |
  v
main.i
  |
  v
main.s
  |
  v
main.o
  |
  v
app
```

Các hậu tố này có ý nghĩa khái quát:

| Hậu tố | Ý nghĩa |
|---|---|
| `.c` | C source cần preprocessing |
| `.i` | C source đã preprocessing |
| `.s` | Assembly source |
| `.o` | Object file |
| không cố định | Executable cuối cùng có thể mang tên tùy ý |

Tuy nhiên, đây là **mô hình logic**, không có nghĩa một lần build bình thường luôn phải để lại tất cả file trung gian trên đĩa. Compiler driver có thể dùng file tạm hoặc pipe giữa các stage rồi xóa artifact trung gian sau khi hoàn tất.

---
## 2. `gcc` là compiler hay compiler driver?

Tên GCC thường được dùng theo nhiều nghĩa. Ở mức đơn giản, người ta gọi GCC là "compiler". Nhưng executable `gcc` mà người dùng gọi trên command line chủ yếu đóng vai trò **compiler driver**.

Nó điều phối pipeline:

```text
                         gcc driver
                            |
              +-------------+-------------+
              |             |             |
              v             v             v
       Compiler proper   Assembler       Linker
                          (`as`)           (`ld`)
              |             |             |
              +-------------+-------------+
                            |
                            v
                          Output
```

> **Đọc sơ đồ:** `gcc` nhận input file và option, xác định stage nào cần chạy, sau đó điều phối các thành phần của toolchain. Compiler proper xử lý ngôn ngữ C; assembler xử lý Assembly; linker xử lý object file và library. Vì vậy không nên đồng nhất toàn bộ pipeline với một bước "compiler" duy nhất.

### 2.1 `gcc` không tự mình thay thế mọi công cụ phía dưới

Trong một GCC toolchain điển hình trên GNU/Linux:

*   Compiler proper cho C có thể liên quan đến thành phần nội bộ như `cc1`.
*   GNU assembler thường là `as`.
*   GNU linker thường là `ld`.

Tuy nhiên đây là chi tiết triển khai của toolchain cụ thể. Điều cần giữ trong đầu là **vai trò logic**, không phải học thuộc pathname hay tên process nội bộ của một distro.

### 2.2 Preprocessor có nhất thiết là một process riêng không?

Không.

Về mặt mô hình, preprocessing vẫn là một **stage riêng về chức năng**. Tuy nhiên, một stage logic không bắt buộc phải tương ứng với một executable hoặc process riêng khi toolchain thực thi.

Trong GCC, cần hiểu thêm khái niệm **compiler front end**. Front end là phần của compiler chịu trách nhiệm **đọc và hiểu ngôn ngữ đầu vào**. Với C, ở mức khái quát nó tham gia các công việc như:

*   Nhận các token của chương trình C.
*   Phân tích cú pháp.
*   Kiểm tra ngữ nghĩa và kiểu dữ liệu.
*   Chuyển chương trình sang biểu diễn nội bộ để các bước tối ưu hóa và sinh code phía sau tiếp tục xử lý.

Có thể hình dung:

```text
C source
   |
   v
+---------------------------+
| GCC C front end           |
|                           |
| preprocessing             |
|      |                    |
|      v                    |
| tokenization / parsing    |
|      |                    |
|      v                    |
| semantic/type checking    |
+---------------------------+
   |
   v
Biểu diễn nội bộ
```

> **Điểm cần nhớ:** `front end` không đồng nghĩa với toàn bộ compiler. Nó là phần gắn với ngôn ngữ nguồn và chịu trách nhiệm hiểu chương trình ở mức ngôn ngữ trước khi các tầng phía sau tối ưu hóa và sinh code cho target.

Với GCC, preprocessing mặc định có thể được **tích hợp vào quá trình tokenization và parsing của language front end**. Vì vậy không nên hình dung rằng mỗi lần chạy `gcc main.c` thì GCC bắt buộc phải khởi chạy một executable `cpp` riêng, tạo `main.i`, rồi mới gọi compiler.

Mô hình thực thi có thể gần với:

```text
gcc driver
    |
    v
C front end (`cc1`)
    |
    +-- preprocessing
    +-- parsing
    +-- semantic analysis
    +-- tạo biểu diễn nội bộ
```

GNU C Preprocessor được triển khai dưới dạng thư viện `cpplib`, có thể được dùng cả trong preprocessor độc lập lẫn tích hợp với các front end C/C++/Objective-C. GCC cũng có option `-no-integrated-cpp` để yêu cầu preprocessing diễn ra như một pass riêng trước compilation.

Do đó cần phân biệt:

```text
Stage logic:       Preprocess -> Compile -> Assemble -> Link

Process thực tế:   không bắt buộc có đúng một process riêng cho mỗi stage
```

Điều này cũng giải thích vì sao `gcc` nên được nhìn như một **driver điều phối**, còn `front end`, preprocessor, assembler và linker là các vai trò/thành phần khác nhau bên trong toàn bộ toolchain.

---
## 3. Giai đoạn 1 — Preprocess và `translation unit`

Preprocessor hoạt động trước khi compiler phân tích cú pháp và ngữ nghĩa C. Nó xử lý các directive bắt đầu bằng `#`.

Một số nhóm quan trọng:

*   `#include`
*   `#define`
*   `#undef`
*   `#if`, `#ifdef`, `#ifndef`, `#elif`, `#else`, `#endif`

Mô hình:

```text
main.c
  |
  | xử lý #include
  | thay thế macro
  | chọn nhánh conditional compilation
  v
C source đã tiền xử lý
```

### 3.1 `#include` là chèn nội dung header vào translation unit

Ví dụ về mặt ý tưởng:

```c
#include "calc.h"

int main(void)
{
    return add(1, 2);
}
```

Nếu `calc.h` chứa:

```c
int add(int a, int b);
```

thì sau preprocessing, compiler có thể hình dung input gần với:

```c
int add(int a, int b);

int main(void)
{
    return add(1, 2);
}
```

Đây chỉ là mô hình giản lược; output thực tế của preprocessor còn có thể chứa nhiều line marker và nội dung từ các header lồng nhau.

> **Điểm cần nhớ:** `#include` không "link library". Nó xử lý source text trước compilation. Linking là một stage hoàn toàn khác diễn ra sau khi đã có object file.

### 3.2 Macro là phép biến đổi trước compiler proper

Giả sử có:

```c
#define BUFFER_SIZE 256

char buffer[BUFFER_SIZE];
```

Preprocessor thay token macro bằng nội dung tương ứng trước khi compiler proper xử lý chương trình.

Điều này dẫn đến một nguyên tắc quan trọng:

```text
Macro không phải biến runtime.
```

Macro không chiếm một vùng nhớ giống biến C chỉ vì nó có tên giống một hằng số.

### 3.3 Conditional compilation thay đổi source mà compiler nhìn thấy

Ví dụ:

```c
#ifdef DEBUG
    log_debug();
#endif
```

Nếu điều kiện không được thỏa mãn, đoạn code tương ứng có thể bị loại khỏi translation unit trước khi compiler phân tích chương trình.

Conditional compilation rất phổ biến trong Embedded Linux, nơi cùng một codebase có thể phải hỗ trợ nhiều board, architecture hoặc feature configuration khác nhau.

### 3.4 Header guard giải quyết việc include lặp

Mẫu quen thuộc:

```c
#ifndef DEVICE_H
#define DEVICE_H

int device_init(void);

#endif
```

Mục tiêu là đảm bảo nội dung chính của header chỉ được đưa vào một lần trong cùng một translation unit, tránh nhiều khai báo hoặc định nghĩa không hợp lệ do include lặp.

Header guard hoạt động bằng cơ chế macro của preprocessor, không phải một tính năng đặc biệt của filesystem hay linker.

### 3.5 Lỗi ở stage preprocessing

Một số lỗi điển hình thuộc tầng này:

*   Header không được tìm thấy.
*   Directive tiền xử lý sai cú pháp.
*   Cấu trúc `#if/#endif` không cân bằng.
*   Macro mở rộng thành nội dung không như mong đợi.

Một lỗi phát sinh ở đây nghĩa là pipeline chưa đi đến compilation proper.

---

### 3.6 `translation unit`: compiler thực sự nhìn thấy gì?

Một **translation unit** là **toàn bộ mã C sau preprocessing mà compiler xử lý như một đơn vị biên dịch**. Nó được hình thành từ một source file `.c` cùng với nội dung các header được `#include`, sau khi macro và conditional compilation đã được xử lý.

Vì vậy, `translation unit` không có nghĩa là "toàn bộ project". Mỗi file `.c` thường tạo ra một translation unit riêng.

Có thể hình dung:

```text
main.c
  + các header được include
  + macro đã được xử lý
  + conditional compilation đã được quyết định
                |
                | preprocessing
                v
        Translation Unit
                |
                | compiler proper
                v
             Assembly
```

> **Điểm cần nhớ:** Translation unit là **đầu vào C đã được preprocessing hoàn chỉnh** mà compiler proper sẽ phân tích. File `.i` chỉ là artifact có thể dùng để lưu mã đã preprocessing; translation unit là khái niệm về **đơn vị chương trình được biên dịch**, không bắt buộc phải tồn tại dưới dạng một file `.i` trên đĩa.

**Mỗi `.c` thường tạo một translation unit riêng**

Giả sử project có:

```text
main.c
sensor.c
network.c
```

Về mô hình:

```text
main.c     -> Translation Unit A -> main.o
sensor.c   -> Translation Unit B -> sensor.o
network.c  -> Translation Unit C -> network.o
```

Compiler không tự động nhập toàn bộ source file khác vào khi xử lý một `.c` chỉ vì chúng nằm cùng thư mục.

Đây là lý do header rất quan trọng: header cung cấp **declaration/interface** để một translation unit biết cách tham chiếu tới thành phần được định nghĩa ở translation unit khác.

**Declaration và definition có vai trò khác nhau**

Ví dụ declaration:

```c
int sensor_read(void);
```

Ví dụ definition:

```c
int sensor_read(void)
{
    return 42;
}
```

Declaration cho compiler biết tên và kiểu giao diện. Definition mới cung cấp implementation hoặc storage thực tế.

Một translation unit có thể compile thành công khi chỉ nhìn thấy declaration của một function được gọi. Việc definition có thật sự tồn tại ở object file nào đó hay không thường chỉ được xác nhận đầy đủ ở bước link.

Đây là nguồn gốc của nhiều lỗi `undefined reference`.

**Header thường mô tả interface, không chứa machine code**

Một header `.h` thông thường chứa declaration, macro, type definition và các interface cần chia sẻ. Nó không tự trở thành object file chỉ vì được `#include`.

Mô hình đúng:

```text
header + source
      |
      v
translation unit
      |
      v
compiler / assembler
      |
      v
object file
```

---
## 4. Giai đoạn 2 — Compile

Sau preprocessing, **compiler proper** bắt đầu xử lý translation unit.

`Compiler proper` là phần thực sự thực hiện công việc biên dịch ngôn ngữ C: nó phân tích cú pháp và ngữ nghĩa, kiểm tra kiểu, tạo biểu diễn nội bộ, thực hiện tối ưu hóa khi cần và sinh code cho target. Khái niệm này được dùng để phân biệt phần biên dịch thực sự với `gcc` driver, preprocessor, assembler và linker.

Có thể nhớ ngắn gọn:

```text
Translation Unit
       |
       v
Compiler proper
       |
       +-- parsing
       +-- semantic/type checking
       +-- internal representation
       +-- optimization
       +-- code generation
       v
    Assembly
```

Ở mức khái quát, compiler phải thực hiện nhiều công việc:

```text
Preprocessed C
      |
      v
Phân tích token / cú pháp
      |
      v
Kiểm tra ngữ nghĩa và kiểu
      |
      v
Biểu diễn trung gian nội bộ
      |
      v
Tối ưu hóa nếu được yêu cầu
      |
      v
Sinh Assembly cho target
```

### 4.1 Compiler hiểu ngôn ngữ C, assembler thì không

Compiler biết các khái niệm như:

*   Kiểu `int`, `char`, pointer, `struct`.
*   Scope của biến.
*   Function declaration và definition.
*   Biểu thức và phép toán C.
*   Quy tắc chuyển kiểu.
*   Cú pháp `if`, `for`, `while`, `switch`.

Assembler không làm công việc đó. Khi pipeline tới assembler, chương trình đã được hạ xuống mức instruction/directive Assembly.

### 4.2 Output Assembly phụ thuộc target architecture

Cùng một source C có thể sinh Assembly khác nhau tùy target:

```text
                 +--> x86-64 Assembly
C source --------|
                 +--> AArch64 Assembly
                 |
                 +--> ARM32 Assembly
                 |
                 +--> RISC-V Assembly
```

Điểm này là cầu nối trực tiếp tới cross-compilation: compiler không chỉ cần hiểu ngôn ngữ C mà còn phải biết cách sinh code cho **target architecture**.

### 4.3 Compilation không giải quyết toàn bộ tham chiếu giữa các file

Nếu `main.c` gọi `sensor_read()` và compiler đã thấy declaration hợp lệ, compilation có thể tạo được `main.o` dù definition của `sensor_read()` nằm trong `sensor.o`.

Compiler có thể để lại một tham chiếu chưa được giải quyết:

```text
main.o
  |
  +-- định nghĩa: main
  |
  +-- cần: sensor_read
```

Linker sẽ xử lý mối quan hệ đó sau.

### 4.4 Optimization thuộc stage compiler

Các mức tối ưu hóa như `-O0`, `-O1`, `-O2`, `-O3`, `-Os` chủ yếu ảnh hưởng đến cách compiler biến biểu diễn chương trình thành machine-oriented code.

Vì vậy cùng một source C có thể tạo ra Assembly rất khác nhau mà vẫn giữ cùng hành vi quan sát được theo quy tắc của ngôn ngữ.

Ở Phase này chỉ cần hiểu vị trí của optimization trong pipeline. Chi tiết compiler optimization không thuộc phạm vi chủ đề.

---
## 5. Giai đoạn 3 — Assemble

Assembler nhận Assembly và mã hóa nó thành machine code tương ứng với target architecture.

```text
Assembly source
      |
      | Assembler
      v
Object file
```

Nếu compiler sinh ra các mnemonic như instruction của x86-64 hoặc AArch64, assembler biến chúng thành byte encoding mà CPU target có thể hiểu sau khi chương trình được link và nạp.

### 5.1 Assembler không chỉ tạo một chuỗi machine code thô

Output của assembler thường là **object file**, không chỉ là một file chứa các opcode nối tiếp nhau.

Object file còn cần chứa metadata phục vụ linker, chẳng hạn:

*   Các section.
*   Symbol table.
*   Relocation entry.
*   Thông tin về kiến trúc/object format.
*   Có thể có debug information nếu build yêu cầu.

Do đó:

```text
Object file = machine code + data + metadata cho bước link
```

### 5.2 Assembler không biết đầy đủ địa chỉ cuối cùng

Khi tạo `main.o`, assembler thường chưa biết:

*   `main.o` sẽ được đặt ở đâu trong executable cuối cùng.
*   Function từ object file khác sẽ nằm ở địa chỉ nào.
*   Library được link sẽ cung cấp symbol ở vị trí nào.

Vì thế object file cần relocation information để linker có thể hoàn thiện địa chỉ/tham chiếu sau này.

---
## 6. Object file và `separate compilation`

Object file là artifact trung gian quan trọng nhất giữa compilation/assembly và linking.

Mô hình:

```text
Translation Unit
      |
      v
Compiler + Assembler
      |
      v
Object file
      |
      +-- Machine code
      +-- Data
      +-- Section table
      +-- Symbol table
      +-- Relocation information
```

### 6.1 Object file đã có machine code nhưng thường chưa chạy độc lập được

Điều này dễ gây nhầm lẫn.

`main.o` có thể đã chứa machine code của `main()`, nhưng nó vẫn có thể:

*   Chứa symbol chưa được giải quyết.
*   Chứa relocation chưa được áp dụng đầy đủ.
*   Chưa có bố cục memory image cuối cùng.
*   Chưa có các thành phần runtime/startup cần thiết.
*   Chưa có program headers theo dạng mà loader cần cho một executable bình thường.

Do đó:

```text
Có machine code  ≠  Đã là chương trình hoàn chỉnh
```

### 6.2 Object file cho phép separate compilation

Một project nhiều source file không cần biên dịch lại toàn bộ mọi file mỗi khi chỉ một source thay đổi.

Mô hình:

```text
A.c -> A.o ---+
              |
B.c -> B.o ---+--> Linker --> app
              |
C.c -> C.o ---+
```

Đây là cơ sở của incremental build và dependency graph trong Makefile.

### 6.3 Object file và source file không có quan hệ 1:1 tuyệt đối trong mọi hệ thống build

Trong mô hình C truyền thống, mỗi translation unit thường tạo một object file. Tuy nhiên các công nghệ như Link-Time Optimization (`LTO`) có thể thay đổi chi tiết bên trong artifact và cách compiler/linker phối hợp.

Ở mức chủ đề này, mô hình `.c -> .o` vẫn là mental model đúng và hữu ích nhất.

---

### 6.4 Chương trình nhiều source file được build theo mô hình nào?

Giả sử có ba source file:

```text
main.c
sensor.c
network.c
```

Mô hình build chuẩn:

```text
main.c    -> preprocess/compile/assemble -> main.o -----+
                                                       |
sensor.c  -> preprocess/compile/assemble -> sensor.o ---+--> link --> app
                                                       |
network.c -> preprocess/compile/assemble -> network.o --+
```

**Compile riêng và link chung**

Điểm cốt lõi là:

```text
Mỗi translation unit được xử lý riêng trước.
Các object file gặp nhau ở linker.
```

Đây là nguyên lý quan trọng nhất để hiểu một project C nhiều file.

**Vì sao header cần nhất quán với implementation?**

Nếu `sensor.h` khai báo:

```c
int sensor_read(void);
```

nhưng implementation thực tế ở `sensor.c` không tương thích, một số loại sai lệch có thể được compiler phát hiện trong translation unit chứa definition; một số vấn đề ABI/API khác có thể dẫn tới lỗi hoặc hành vi không mong muốn về sau.

Header đóng vai trò "hợp đồng" giữa các translation unit, nên declaration phải phản ánh đúng interface của definition.

**Separate compilation là tiền đề cho build system**

Khi chỉ một source file thay đổi, về nguyên tắc chỉ object tương ứng cần được rebuild trước khi link lại.

Mô hình dependency:

```text
sensor.c ---->
sensor.h ----> sensor.o ----+
                           |
main.c ------> main.o ------+--> app
```

Makefile ở Topic 4 sẽ biến quan hệ này thành dependency graph có thể được tự động đánh giá dựa trên timestamp và rule.

---
## 7. ELF và section ở mức cơ bản

Trên Linux, object file và executable thường dùng định dạng **ELF — Executable and Linkable Format**.

Tên ELF phản ánh đúng hai vai trò lớn:

```text
ELF
 |
 +-- Linkable: object file dùng cho linker
 |
 +-- Executable: binary có thể được loader xử lý
```

ELF không phải chỉ là "định dạng executable". Nó là một format có thể biểu diễn nhiều loại object khác nhau.

### 7.1 ELF header

Mỗi ELF file bắt đầu bằng ELF header chứa metadata tổng quát, ví dụ:

*   File có phải ELF hay không.
*   32-bit hay 64-bit.
*   Little-endian hay big-endian.
*   Target machine/architecture.
*   Loại ELF object.
*   Entry point nếu phù hợp.
*   Vị trí của section header table.
*   Vị trí của program header table nếu có.

Mô hình đơn giản:

```text
+--------------------------+
| ELF Header               |
+--------------------------+
| Program Header Table     |  <- quan trọng khi load executable
+--------------------------+
| Sections / contents      |
| .text                    |
| .rodata                  |
| .data                    |
| ...                      |
+--------------------------+
| Section Header Table     |
+--------------------------+
```

Không phải mọi ELF file đều sử dụng mọi thành phần theo cùng cách.

### 7.2 Một số ELF type quan trọng

Ba loại thường gặp:

| ELF type | Ý nghĩa khái quát |
|---|---|
| `ET_REL` | Relocatable object, điển hình là `.o` |
| `ET_EXEC` | Executable file kiểu truyền thống |
| `ET_DYN` | Shared object hoặc PIE executable tùy ngữ cảnh |

Điểm cần cẩn thận: không nên khẳng định mọi executable Linux hiện đại đều là `ET_EXEC`. Nhiều distro build executable theo kiểu PIE (`Position Independent Executable`), và ELF type khi đó thường là `ET_DYN`.

Ở chủ đề này chỉ cần hiểu rằng **ELF type mô tả vai trò của file trong quy trình link/load**, không phải chỉ nhìn đuôi filename.

---

### 7.3 ELF section ở mức cơ bản

Section là cách ELF tổ chức nội dung phục vụ linking và phân loại code/data.

Một số section thường gặp:

| Section | Ý nghĩa khái quát |
|---|---|
| `.text` | Machine code của chương trình |
| `.rodata` | Dữ liệu chỉ đọc |
| `.data` | Dữ liệu có giá trị khởi tạo |
| `.bss` | Dữ liệu zero-initialized hoặc uninitialized theo mô hình phổ biến |
| `.symtab` | Symbol table đầy đủ phục vụ linking/debugging |
| `.strtab` | Chuỗi tên liên quan symbol/section |
| `.rela.*` / `.rel.*` | Relocation information tùy kiến trúc/format |

**C variable không ánh xạ 1:1 cứng nhắc vào section**

Ví dụ:

```c
int a = 10;
static const char name[] = "sensor";
int buffer[1024];
```

Một cách suy nghĩ phổ biến là:

```text
a       -> .data
name    -> .rodata
buffer  -> .bss
```

Nhưng đây chỉ là mô hình điển hình. Compiler/linker có quyền tổ chức section chi tiết khác tùy option, ABI và optimization.

Do đó không nên biến tên section thành quy tắc ngôn ngữ C tuyệt đối.

**`.bss` giúp tránh lưu các byte zero không cần thiết trong file**

Một vùng dữ liệu cần được khởi tạo bằng zero khi chương trình chạy không nhất thiết phải chiếm đúng từng byte zero tương ứng trong ELF file trên storage.

ELF có thể mô tả kích thước vùng cần cấp phát, còn loader chuẩn bị vùng memory khi chương trình được nạp.

Ý tưởng:

```text
Trong file ELF:      metadata mô tả vùng BSS
                           |
                           v
Khi load vào memory: [ vùng memory được chuẩn bị / zero-init ]
```

Điều này giúp phân biệt **kích thước file trên storage** với **kích thước memory image khi chương trình chạy**.

---
## 8. Symbol: tên dùng để nối các thành phần chương trình

Symbol là một khái niệm trung tâm của linker.

Có thể hiểu symbol là một tên gắn với một thực thể mà object file định nghĩa hoặc tham chiếu, ví dụ:

*   Function.
*   Global variable.
*   Một số label hoặc đối tượng khác tùy toolchain/object format.

Ví dụ source:

```c
int counter = 0;

int sensor_read(void)
{
    return 42;
}
```

Object file có thể chứa các symbol tương ứng như `counter` và `sensor_read`.

### 8.1 Defined symbol và undefined symbol

Giả sử `main.c` chứa lời gọi:

```c
int sensor_read(void);

int main(void)
{
    return sensor_read();
}
```

Còn `sensor.c` chứa definition của `sensor_read()`.

Mô hình symbol có thể là:

```text
main.o
  |
  +-- defines: main
  |
  +-- requires: sensor_read

sensor.o
  |
  +-- defines: sensor_read
```

Từ góc nhìn `main.o`, `sensor_read` là một **undefined symbol**: object này cần symbol đó nhưng không định nghĩa nó.

Từ góc nhìn `sensor.o`, `sensor_read` là một **defined symbol**.

Linker cố nối hai phía này lại.

### 8.2 Undefined symbol không đồng nghĩa object file bị lỗi

Một object file riêng lẻ hoàn toàn có thể hợp lệ dù còn undefined symbol. Đây chính là cách separate compilation hoạt động.

Lỗi chỉ xuất hiện khi tới thời điểm link output cuối cùng mà linker vẫn không tìm thấy definition phù hợp.

### 8.3 `static` ở file scope làm thay đổi linkage

Ví dụ:

```c
static int helper(void)
{
    return 1;
}
```

Một function `static` ở file scope có **internal linkage**. Nó không được cung cấp như một external symbol theo cách một function thông thường có external linkage được dùng giữa các translation unit.

Điểm này rất quan trọng khi hiểu vì sao hai file có thể cùng có một `static helper()` mà không tạo xung đột tên external.

### 8.4 Symbol không phải biến runtime theo nghĩa đơn giản

Symbol table là metadata trong object/binary. Một symbol có thể mô tả function hoặc object, nhưng không nên đồng nhất "symbol" với "một biến đang tồn tại trong RAM".

Sau stripping hoặc optimization, một số symbol có thể không còn trong binary cuối theo dạng ban đầu dù chương trình vẫn hoạt động bình thường.

---
## 9. Relocation: vì sao object file chưa biết địa chỉ cuối cùng?

Giả sử `main.o` gọi `sensor_read()` nằm ở `sensor.o`.

Khi assembler tạo `main.o`, nó chưa biết linker sẽ đặt `sensor_read()` tại địa chỉ cuối cùng nào trong executable.

Do đó object file cần ghi lại một yêu cầu đại loại như:

```text
"Tại vị trí này có một tham chiếu tới symbol sensor_read.
 Khi biết địa chỉ/bố cục cuối cùng, hãy sửa giá trị phù hợp vào đây."
```

Đó là vai trò của **relocation information**.

### 9.1 Mô hình relocation

```text
main.o
+------------------------------+
| Machine code                 |
| call ???                     |----+
+------------------------------+    |
| Symbol: sensor_read = UND    |    |
+------------------------------+    |
| Relocation entry ------------+----+
+------------------------------+

sensor.o
+------------------------------+
| Symbol: sensor_read = defined|
+------------------------------+

              |
              v
            Linker
              |
              v
Biết vị trí cuối cùng -> áp dụng relocation
```

> **Đọc sơ đồ:** `main.o` biết rằng có một tham chiếu cần trỏ tới `sensor_read`, nhưng chưa biết giá trị địa chỉ cuối cùng. Linker tìm definition của symbol trong `sensor.o`, quyết định bố cục output rồi cập nhật tham chiếu theo loại relocation phù hợp.

### 9.2 Relocation không đơn giản luôn là "ghi địa chỉ tuyệt đối"

Tùy kiến trúc và loại code, relocation có thể liên quan tới:

*   Địa chỉ tuyệt đối.
*   Offset tương đối so với vị trí hiện tại.
*   Entry trong GOT/PLT.
*   Các kiểu relocation đặc thù kiến trúc.

Các chi tiết đó thuộc mức sâu hơn. Ở đây chỉ cần giữ mental model:

```text
Relocation = thông tin cho phép linker/loader hoàn thiện các tham chiếu chưa thể cố định trước đó.
```

---
## 10. Giai đoạn 4 — Link

Linker nhận các object file và library làm input rồi tạo output đã được tổ chức ở mức chương trình.

Mô hình:

```text
main.o --------+
               |
sensor.o ------+----> Linker ----> executable
               |
other objects -+
               |
libraries -----+
```

Các trách nhiệm quan trọng của linker gồm:

*   Thu thập các input object cần thiết.
*   Kết hợp các section tương ứng.
*   Giải quyết symbol reference.
*   Phát hiện symbol không tồn tại hoặc xung đột definition.
*   Quyết định bố cục địa chỉ theo quy tắc/linker script.
*   Áp dụng relocation phù hợp.
*   Tạo ELF output cuối cùng.

### 10.1 Symbol resolution

Linker xây dựng mối quan hệ giữa bên **cần symbol** và bên **định nghĩa symbol**.

```text
main.o:       cần sensor_read
sensor.o:     định nghĩa sensor_read
                         |
                         v
                      Linker
                         |
                         v
                tham chiếu được giải quyết
```

Nếu không có definition phù hợp:

```text
undefined reference
```

Nếu có nhiều strong definition không hợp lệ cho cùng symbol:

```text
multiple definition
```

### 10.2 Linker không phải compiler C

Linker làm việc chủ yếu với object file, symbol, section, relocation và library. Nó không phân tích lại ý nghĩa C source theo cách compiler proper đã làm.

Do đó một lỗi kiểu C như sai cú pháp thường không phải lỗi linker, còn `undefined reference` thường là lỗi thuộc tầng linking.

### 10.3 Startup code và C runtime

Một chương trình C thông thường không chỉ gồm object file do người dùng viết. Khi tạo executable theo môi trường GNU/Linux thông thường, quá trình link còn liên quan tới các thành phần runtime/startup do toolchain cung cấp.

Mô hình giản lược:

```text
Object của ứng dụng
       +
Startup objects / runtime support
       +
Libraries cần thiết
       |
       v
     Linker
       |
       v
  ELF executable
```

Điều này giúp giải thích vì sao entry point của ELF không nhất thiết trỏ trực tiếp vào `main()`.

`main()` là entry point ở mức chương trình C theo mô hình runtime, còn ELF entry point là địa chỉ mà loader bắt đầu chuyển điều khiển tới theo ABI/runtime setup.

---

### 10.4 Vì sao thường dùng `gcc` để điều phối bước link?

GNU linker `ld` là công cụ linker thực sự. Tuy nhiên với chương trình C thông thường, người dùng thường để GCC driver điều phối bước link.

Lý do là GCC driver biết cấu hình toolchain và có thể cung cấp các thành phần/option mặc định phù hợp với môi trường C runtime.

Mô hình:

```text
Người dùng
   |
   v
gcc driver
   |
   +--> chọn startup objects phù hợp
   +--> thêm runtime/library mặc định khi cần
   +--> truyền option xuống linker
   |
   v
ld / linker được cấu hình
```

Điều này không có nghĩa `ld` không thể được gọi trực tiếp. `ld` là tầng thấp hơn và cho phép kiểm soát chi tiết hơn, nhưng khi gọi trực tiếp người dùng phải chịu trách nhiệm nhiều hơn về startup object, library, dynamic linker, linker script và các chi tiết ABI liên quan.

Trong Embedded Linux, hiểu ranh giới này rất quan trọng vì linker script và cấu hình runtime có thể trở nên rõ ràng hơn khi đi sâu vào bootloader, bare-metal hoặc hệ thống đặc thù. Tuy nhiên ở Phase này chỉ cần hiểu vai trò của từng tầng.

---
## 11. Object file, executable, section và segment

Hai file đều có thể là ELF và đều có thể chứa machine code, nhưng vai trò của chúng khác nhau.

| Thuộc tính | Object file | Executable |
|---|---|---|
| Vai trò chính | Input trung gian cho linker | Output có thể được loader xử lý để chạy |
| ELF type điển hình | `ET_REL` | `ET_EXEC` hoặc PIE dạng `ET_DYN` |
| Undefined symbol | Có thể còn | Thông thường phải được xử lý theo mô hình link/load phù hợp |
| Relocation | Thường còn nhiều relocation cho linker | Đã được xử lý đáng kể để tạo image chạy được |
| Program headers | Thường không dùng như executable | Quan trọng cho loader |
| Bố cục runtime | Chưa hoàn chỉnh | Được tổ chức để nạp vào process image |

### 11.1 Quyền executable trên filesystem không quyết định cấu trúc binary

Đặt bit `x` bằng filesystem permission chỉ cho phép Kernel cân nhắc file như một đối tượng có thể được thực thi theo cơ chế phù hợp. Nó không biến một relocatable object thành executable ELF hoàn chỉnh.

Vì vậy cần phân biệt:

```text
Filesystem execute permission
          ≠
Binary format đã sẵn sàng để loader chạy
```

Một file cần cả định dạng/nội dung phù hợp lẫn quyền truy cập phù hợp.

---

### 11.2 Section và segment không phải một khái niệm

Đây là một điểm dễ nhầm khi bắt đầu đọc ELF.

**Section chủ yếu phục vụ góc nhìn link-time**

Các section như:

```text
.text
.rodata
.data
.bss
.symtab
.rela.text
```

giúp compiler/assembler/linker tổ chức nội dung file.

**Segment chủ yếu phục vụ góc nhìn load-time**

Khi executable được Linux loader nạp, program header table mô tả các **segment** cần được ánh xạ vào memory với quyền thích hợp.

Mô hình:

```text
Link-time view                      Load-time view

Sections                            Segments
---------                           --------
.text ---------+                    +--> LOAD (R-X)
.rodata -------+------------------->|
                                    |
.data ---------+                    +--> LOAD (RW-)
.bss ----------+------------------->|
```

Một segment có thể bao phủ nhiều section. Vì vậy:

```text
Section ≠ Segment
```

Ở Topic 1 chỉ cần nắm ranh giới khái niệm này. Chi tiết loader, virtual memory mapping và dynamic linking sẽ được mở rộng ở các phase thích hợp.

---
## 12. Các option GCC phản ánh từng stage như thế nào?

Các option `-E`, `-S`, `-c` rất hữu ích về mặt khái niệm vì chúng làm lộ ranh giới của pipeline.

| Option | Điểm dừng logic | Output điển hình |
|---|---|---|
| `-E` | Sau preprocessing | Preprocessed source |
| `-S` | Sau compilation proper | Assembly `.s` |
| `-c` | Sau assembly, không link | Object `.o` |
| không dùng các option dừng trên | Đi qua link nếu input phù hợp | Executable/output link |

Mô hình:

```text
source.c
   |
   | -E
   v
source.i
   |
   | -S
   v
source.s
   |
   | -c
   v
source.o
   |
   | link
   v
executable
```

> **Lưu ý:** Bảng này dùng để biểu diễn điểm dừng của GCC driver. Không nên hiểu `-c` theo nghĩa "chỉ chạy compiler proper"; `-c` có nghĩa là compile/assemble input cần thiết nhưng **không chạy linker**.

### 12.1 `-v` và `-###` phản ánh vai trò driver

Ở mức khái niệm:

*   `-v` yêu cầu GCC hiển thị thông tin verbose, bao gồm các command/stage mà driver thực thi.
*   `-###` hiển thị command mà driver dự định chạy nhưng không thực thi chúng.

Hai option này cho thấy một sự thật quan trọng: `gcc` không phải một hộp đen duy nhất; nó đang điều phối các thành phần khác nhau của toolchain.

### 12.2 `-o` đặt tên primary output, không xác định stage

`-o` chủ yếu quyết định tên file output. Stage được quyết định bởi loại input và các option như `-E`, `-S`, `-c` hoặc việc link.

Do đó:

```text
-o = chọn tên output
-E/-S/-c = kiểm soát điểm dừng pipeline
```

---
## 13. `file`, `readelf`, `nm`, `objdump` quan sát lớp nào?

Các công cụ này không thay thế nhau. Mỗi công cụ nhìn binary từ một góc khác nhau.

### 13.1 `file`: nhận diện loại file

`file` trả lời câu hỏi khái quát:

```text
"Đây là file gì?"
```

Với binary, nó thường giúp xác định:

*   ELF hay loại format khác.
*   32-bit hay 64-bit.
*   Architecture.
*   Một số đặc tính như dynamically linked, interpreter, stripped tùy file.

`file` thích hợp cho việc phân loại nhanh, không phải công cụ phân tích sâu cấu trúc ELF.

### 13.2 `readelf`: nhìn trực tiếp cấu trúc ELF

`readelf` được thiết kế để hiển thị thông tin từ ELF object.

Các nhóm thông tin tiêu biểu:

```text
ELF header
Program headers / segments
Section headers
Symbol tables
Relocation entries
Dynamic section
```

Mental model:

```text
ELF file
   |
   v
readelf
   |
   +--> Header
   +--> Sections
   +--> Segments
   +--> Symbols
   +--> Relocations
```

### 13.3 `nm`: tập trung vào symbol

`nm` trả lời câu hỏi kiểu:

```text
"Object/binary này định nghĩa symbol nào và còn cần symbol nào?"
```

Trong output GNU `nm`, một số ký hiệu thường gặp là:

| Ký hiệu | Ý nghĩa điển hình |
|---|---|
| `T` / `t` | Symbol nằm trong code/text section |
| `D` / `d` | Initialized data |
| `B` / `b` | BSS/zero-initialized data |
| `R` / `r` | Read-only data |
| `U` | Undefined symbol |

Chữ hoa/thường thường còn gợi ý global/local binding, dù chi tiết phụ thuộc loại symbol/object format.

### 13.4 `objdump`: nhìn object code và disassembly

`objdump` có thể hiển thị nhiều loại thông tin binary, nhưng trong mental model của Phase 2, vai trò nổi bật là **disassembly**:

```text
Machine-code bytes
       |
       v
    objdump
       |
       v
Assembly mnemonic để con người đọc
```

Điều này khác với Assembly `.s` do compiler sinh trước assembler.

```text
Compiler-generated .s        Disassembly từ object/binary
        |                               |
        | trước assembler               | sau khi đã có machine code
        v                               v
 Assembly source                  Assembly representation
```

Hai phía có thể tương tự về instruction nhưng không phải cùng artifact hay cùng giai đoạn.

### 13.5 Bản đồ công cụ

```text
file      -> nhận diện file/architecture/format ở mức tổng quát
readelf   -> cấu trúc ELF
nm        -> symbol
objdump   -> object contents / disassembly
```

Cách phân lớp này quan trọng hơn việc học thuộc option riêng lẻ.

---
## 14. Lỗi build và tư duy gỡ lỗi theo từng tầng

Một lợi ích lớn của việc hiểu build pipeline là có thể phân loại lỗi theo stage.

### 14.1 Preprocessor error

Ví dụ nhóm vấn đề:

```text
header không tồn tại
include path sai
directive #if/#endif sai
macro gây expansion bất hợp lệ
```

Pipeline:

```text
Source
  |
  X  Preprocess lỗi
```

Compiler proper chưa thực sự có được translation unit hợp lệ để tiếp tục.

### 14.2 Compiler error

Ví dụ:

*   Sai cú pháp C.
*   Dùng type không hợp lệ.
*   Gọi function với declaration không tương thích ở mức compiler có thể phát hiện.
*   Biểu thức vi phạm rule ngôn ngữ.

```text
Preprocessed C
      |
      X  Compile lỗi
```

### 14.3 Assembler error

Assembler error thường liên quan Assembly syntax, instruction, directive hoặc target-specific constraint.

Trong workflow C thông thường, lỗi assembler ít gặp hơn lỗi compiler/linker vì Assembly thường do compiler sinh. Tuy nhiên chúng có thể xuất hiện khi:

*   Có source Assembly viết tay.
*   Dùng inline assembly sai.
*   Toolchain/option target không tương thích.
*   Generated assembly không phù hợp với assembler đang được dùng.

### 14.4 Linker error — `undefined reference`

Mô hình:

```text
main.o: cần foo
lib/object khác: không có definition foo
                 |
                 v
               Linker
                 |
                 X
        undefined reference to `foo`
```

Điểm quan trọng là source có thể **compile thành công** nhưng chương trình vẫn **link thất bại**.

### 14.5 Linker error — `multiple definition`

Nếu nhiều object cùng cung cấp strong definition không hợp lệ cho cùng symbol, linker không thể chọn một cách tùy tiện.

```text
A.o: defines foo
B.o: defines foo
       |
       v
     Linker
       X
multiple definition
```

### 14.6 Runtime error không phải build error

Nếu executable đã được tạo và bắt đầu chạy rồi mới crash hoặc trả kết quả sai, vấn đề đã vượt qua pipeline build cơ bản.

Ví dụ:

```text
Build thành công
      |
      v
Executable chạy
      |
      X segmentation fault
```

Đó là runtime failure, không phải compiler/linker failure theo nghĩa trực tiếp.

---

### 14.7 Cách suy luận lỗi theo từng tầng

Thay vì nhìn toàn bộ toolchain như một hộp đen, hãy đặt câu hỏi theo pipeline.

**Nếu header không tìm thấy**

Tập trung vào:

```text
Preprocessor
  |
  +-- include path
  +-- tên header
  +-- loại #include
  +-- macro/conditional ảnh hưởng include
```

Không nên bắt đầu bằng linker vì pipeline chưa đi tới đó.

**Nếu compiler báo lỗi ngôn ngữ**

Tập trung vào translation unit:

```text
Source sau preprocessing
  |
  +-- declaration có tồn tại không?
  +-- type có đúng không?
  +-- syntax có hợp lệ không?
  +-- macro có làm source biến dạng không?
```

**Nếu `undefined reference`**

Tập trung vào symbol/link input:

```text
Function đã được khai báo?
        |
        v
Object chứa definition có được tạo?
        |
        v
Object/library đó có tham gia link?
        |
        v
Tên symbol/linkage có khớp?
```

Một declaration hợp lệ chỉ giúp compiler hiểu lời gọi; nó không tạo ra implementation.

**Nếu binary sai architecture**

Tập trung vào target của toolchain và ELF metadata:

```text
Compiler target
    |
Assembler target
    |
Object architecture
    |
Link output architecture
```

Đây là lớp vấn đề sẽ trở nên đặc biệt quan trọng trong cross-compilation.

**Nếu executable tạo được nhưng loader không chạy**

Cần phân biệt build artifact với môi trường runtime:

```text
ELF architecture đúng?
Interpreter/dynamic loader tồn tại?
Shared libraries phù hợp?
Filesystem có quyền execute?
Kernel hỗ trợ binary format/architecture?
```

Một phần các câu hỏi này thuộc Topic 2 và Topic 3, nhưng mental model nên được hình thành ngay từ GCC Build Flow.

---
## 15. Liên hệ với Embedded Linux

Build flow của Embedded Linux về bản chất vẫn là:

```text
Preprocess -> Compile -> Assemble -> Link
```

Điểm thay đổi quan trọng là **target**.

### 15.1 Host và target có thể khác architecture

Trong native build:

```text
Build machine: x86-64 Linux
        |
        v
x86-64 executable
        |
        v
chạy trên chính x86-64 Linux
```

Trong cross build:

```text
Build machine: x86-64 Linux
        |
        | Cross toolchain
        v
AArch64 object / ELF
        |
        v
Target board: AArch64 Linux
```

Pipeline không thay đổi về bản chất; compiler/assembler/linker được cấu hình để tạo output cho kiến trúc khác.

### 15.2 Architecture xuất hiện từ rất sớm trong pipeline

Architecture không chỉ là thông tin được gắn vào ELF ở cuối.

Compiler cần target architecture để sinh Assembly phù hợp. Assembler cần target architecture để mã hóa instruction. Linker cần bảo đảm các input object tương thích.

```text
C source
   |
   | compiler biết target ISA/ABI
   v
Target Assembly
   |
   | assembler biết encoding target
   v
Target Object
   |
   | linker ghép target objects
   v
Target ELF
```

Topic 2 sẽ bổ sung ABI, toolchain prefix, target triplet và sysroot để hoàn thiện mô hình này.

### 15.3 Object file sai target không thể tùy ý ghép chung

Nếu một object là x86-64 và object khác là AArch64, linker thông thường không thể ghép chúng thành một executable duy nhất cho một CPU architecture.

```text
x86-64 main.o ----+
                  X--> không cùng target machine
AArch64 sensor.o -+
```

Đây là một trong các lý do phải duy trì toolchain nhất quán trong Embedded Linux project.

### 15.4 ELF là điểm giao nhau của nhiều công cụ Embedded Linux

Trong quy trình embedded, cùng một ELF có thể được quan sát bởi nhiều công cụ:

```text
Compiler / Linker
        |
        v
       ELF
   +----+----+----------+
   |         |          |
readelf     nm       objdump
   |         |          |
metadata   symbols   instructions
```

Khi bring-up hoặc debug build, hiểu ELF giúp phân biệt nhanh vấn đề thuộc architecture, linking, symbol hay runtime environment.

### 15.5 Kích thước và bố cục binary có ý nghĩa thực tế hơn trên thiết bị nhúng

Embedded Linux thường có giới hạn storage và RAM chặt hơn desktop/server. Vì vậy các khái niệm như:

*   `.text`
*   `.rodata`
*   `.data`
*   `.bss`
*   static/shared library
*   debug symbol
*   stripping

sẽ có ảnh hưởng trực tiếp tới kích thước image và memory footprint. Topic 1 chỉ xây nền tảng về section/object; các lựa chọn linking sẽ được đi sâu ở Topic 3.

---
## 16. Tổng kết và mô hình tư duy

### 16.1 Pipeline đầy đủ

```text
                        SOURCE CODE
                            |
                            v
+----------------------------------------------------------+
| 1. PREPROCESS                                            |
|                                                          |
| #include, #define, #if ...                               |
+----------------------------------------------------------+
                            |
                            v
                    TRANSLATION UNIT
                            |
                            v
+----------------------------------------------------------+
| 2. COMPILE                                               |
|                                                          |
| C semantics -> target-oriented Assembly                  |
+----------------------------------------------------------+
                            |
                            v
                       ASSEMBLY
                            |
                            v
+----------------------------------------------------------+
| 3. ASSEMBLE                                              |
|                                                          |
| Assembly -> machine code + ELF metadata                  |
+----------------------------------------------------------+
                            |
                            v
                       OBJECT (.o)
              +-------------+-------------+
              |                           |
              v                           v
           Symbols                    Relocations
              |                           |
              +-------------+-------------+
                            |
                            v
+----------------------------------------------------------+
| 4. LINK                                                  |
|                                                          |
| combine objects + resolve symbols + apply relocation     |
+----------------------------------------------------------+
                            |
                            v
                     ELF EXECUTABLE
```

> **Đọc sơ đồ:** Preprocessor tạo translation unit; compiler chuyển ngôn ngữ C sang code phụ thuộc target; assembler tạo object file có machine code nhưng vẫn giữ metadata cho linking; linker ghép các object, giải quyết symbol và relocation để tạo ELF cuối cùng.

### 16.2 Các phân biệt cần nhớ

```text
Build                     != Compile proper
GCC driver                != Linker
Preprocessor              != Compiler proper
Compiler                  != Assembler
Assembler                 != Linker
Header declaration        != Function implementation
Object file               != Executable
Undefined symbol trong .o != .o bị hỏng
Section                   != Segment
ELF                       != chỉ riêng executable
Filesystem execute bit    != binary format hợp lệ
```

### 16.3 Các điểm cốt lõi

1.  Một chương trình C thông thường đi qua bốn stage: **Preprocess → Compile → Assemble → Link**.
2.  `gcc` trên command line đóng vai trò **compiler driver**, điều phối các thành phần của toolchain.
3.  Preprocessor tạo ra translation unit mà compiler thực sự phân tích.
4.  Mỗi translation unit thường được build thành một object file độc lập trước bước link.
5.  Object file đã có machine code nhưng vẫn có thể còn undefined symbol và relocation.
6.  Linux sử dụng ELF làm định dạng quan trọng cho relocatable object, executable và shared object.
7.  Section tổ chức code/data ở góc nhìn link-time; segment phục vụ chủ yếu cho load-time.
8.  Symbol cho phép object file tham chiếu tới function/data được định nghĩa ở nơi khác.
9.  Relocation lưu thông tin cần thiết để linker/loader hoàn thiện các tham chiếu chưa biết địa chỉ cuối cùng.
10. `undefined reference` là lỗi linker điển hình, khác bản chất với lỗi cú pháp C của compiler.
11. `file`, `readelf`, `nm`, `objdump` quan sát các lớp khác nhau của binary.
12. Cross-compilation không thay đổi bản chất pipeline; nó thay đổi target mà toolchain sinh code cho.

---
## 17. Tài liệu tham khảo

### 17.1 GCC

1. GNU Project — **Using the GNU Compiler Collection (GCC), GCC Command Options**  
   <https://gcc.gnu.org/onlinedocs/gcc/Invoking-GCC.html>

2. GNU Project — **Options Controlling the Kind of Output**  
   <https://gcc.gnu.org/onlinedocs/gcc/Overall-Options.html>

3. GNU Project — **The C Preprocessor**  
   <https://gcc.gnu.org/onlinedocs/cpp/>

4. GNU Project — **Preprocessor Options — `-no-integrated-cpp`**  
   <https://gcc.gnu.org/onlinedocs/gcc/Preprocessor-Options.html>

5. GNU Project — **GCC Internals — Language Front Ends**  
   <https://gcc.gnu.org/onlinedocs/gccint/Languages.html>

### 17.2 GNU Binutils

6. GNU Project / Sourceware — **GNU Binary Utilities**  
   <https://sourceware.org/binutils/docs/binutils.html>

7. GNU Project / Sourceware — **Using as — The GNU Assembler**  
   <https://sourceware.org/binutils/docs/as.html>

8. GNU Project / Sourceware — **LD — The GNU Linker**  
   <https://sourceware.org/binutils/docs/ld.html>

9. GNU Project / Sourceware — **readelf**  
   <https://sourceware.org/binutils/docs/binutils/readelf.html>

10. GNU Project / Sourceware — **nm**  
   <https://sourceware.org/binutils/docs/binutils/nm.html>

11. GNU Project / Sourceware — **objdump**  
   <https://sourceware.org/binutils/docs/binutils/objdump.html>

### 17.3 ELF / ABI

12. System V ABI — **ELF Object File Format**  
    <https://gabi.xinuos.com/>

### 17.4 Tài liệu nền tảng Linux

13. Michael Kerrisk — **The Linux Programming Interface** — No Starch Press.

14. Robert Love — **Linux System Programming** — O'Reilly Media.
