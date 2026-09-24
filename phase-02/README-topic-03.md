# Chủ đề 3 — Static & Dynamic Library

> **Mục tiêu:** Hiểu bản chất của thư viện trong quá trình build và runtime trên Linux; phân biệt rõ static library với static linking, shared library với dynamic linking, link-time với load-time/runtime; hiểu cách linker chọn object từ archive, cách shared object được ghi nhận thành dependency trong ELF, vai trò của dynamic linker/loader, PIC, `SONAME`, library search path và các lỗi tương thích thường gặp. Sau chương này, người học phải có mental model đủ chắc để đọc một lệnh link, hiểu vì sao chương trình build thành công nhưng vẫn có thể không chạy được do thiếu `.so`, và chuẩn bị cho Makefile/CMake ở các chủ đề sau.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các thuật ngữ cần tra cứu đúng theo tài liệu GCC/GNU Binutils/Linux như `static library`, `archive`, `shared object`, `shared library`, `static linking`, `dynamic linking`, `position-independent code`, `dynamic linker/loader`, `DT_NEEDED`, `SONAME`, `RPATH`, `RUNPATH`, `symbol resolution`, `dlopen()` được giữ nguyên bằng tiếng Anh và giải thích tại vị trí phù hợp.
>
> **Phạm vi:** Static library `.a`, shared object/library `.so`, cách linker sử dụng library, PIC ở mức cần thiết, dependency động trong ELF, dynamic linker/loader, `SONAME`, library versioning, link-time search path và runtime search path, `dlopen()` ở mức khái niệm, lỗi library thường gặp và liên hệ với Embedded Linux. Chi tiết sâu về GOT/PLT, relocation model, symbol interposition, linker script, ELF dynamic section internals và packaging policy của từng distribution không thuộc phạm vi chương này.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để xây dựng mental model về cách library tham gia vào quá trình build và runtime. Không có bài thực hành.

Ở Chủ đề 1, quá trình build đã dừng ở mô hình:

```text
Object files
    |
    | Linker
    v
ELF output
```

Ở Chủ đề 2, ta bổ sung thêm một ràng buộc:

```text
Object / library đưa vào linker
phải phù hợp với target architecture + ABI + runtime environment
```

Chủ đề này trả lời câu hỏi tiếp theo:

> **Khi một chương trình gọi hàm không nằm trong chính source/object của nó, code của hàm đó đến từ đâu, được gắn vào executable khi nào, và ai chịu trách nhiệm tìm nó?**

Có hai mô hình nền tảng:

```text
Static library
--------------
Object files + libfoo.a
        |
        | link-time
        v
Executable chứa phần code cần thiết


Shared library
--------------
Object files + libfoo.so
        |
        | link-time: ghi dependency / giải quyết thông tin cần thiết
        v
Dynamically linked executable
        |
        | load-time / runtime
        v
Dynamic linker/loader tìm và map libfoo.so
```

> **Đọc sơ đồ:** Với static library, linker lấy các object cần thiết từ archive và đưa chúng vào output trong quá trình link. Với shared library, executable thường không chứa toàn bộ code của library; thay vào đó nó mang metadata/dependency để dynamic linker/loader tìm và nạp shared object khi chương trình chạy.

Đây là khác biệt trung tâm của toàn bộ chương.

---

## Mục lục

- [1. Library giải quyết vấn đề gì?](#1-library-giải-quyết-vấn-đề-gì)
- [2. Library tham gia vào build flow ở đâu?](#2-library-tham-gia-vào-build-flow-ở-đâu)
- [3. Static library `.a` thực chất là gì?](#3-static-library-a-thực-chất-là-gì)
- [4. Static linking hoạt động như thế nào?](#4-static-linking-hoạt-động-như-thế-nào)
- [5. Shared library `.so` thực chất là gì?](#5-shared-library-so-thực-chất-là-gì)
- [6. Vì sao shared library thường cần Position-Independent Code?](#6-vì-sao-shared-library-thường-cần-position-independent-code)
- [7. Dynamic linking và dynamic linker/loader](#7-dynamic-linking-và-dynamic-linkerloader)
- [8. ELF ghi nhận shared-library dependency như thế nào?](#8-elf-ghi-nhận-shared-library-dependency-như-thế-nào)
- [9. `SONAME` và versioning của shared library](#9-soname-và-versioning-của-shared-library)
- [10. Link-time search path và runtime search path](#10-link-time-search-path-và-runtime-search-path)
- [11. Static và dynamic linking khác nhau như thế nào?](#11-static-và-dynamic-linking-khác-nhau-như-thế-nào)
- [12. Link order và dependency giữa các library](#12-link-order-và-dependency-giữa-các-library)
- [13. `dlopen()`: dynamic loading không hoàn toàn giống dynamic linking thông thường](#13-dlopen-dynamic-loading-không-hoàn-toàn-giống-dynamic-linking-thông-thường)
- [14. Tư duy chẩn đoán lỗi library](#14-tư-duy-chẩn-đoán-lỗi-library)
- [15. Liên hệ với Embedded Linux](#15-liên-hệ-với-embedded-linux)
- [16. Tổng kết và mô hình tư duy](#16-tổng-kết-và-mô-hình-tư-duy)
- [17. Tài liệu tham khảo](#17-tài-liệu-tham-khảo)

---

## 1. Library giải quyết vấn đề gì?

Một chương trình thực tế hiếm khi tự chứa source code cho mọi chức năng mà nó sử dụng.

Ví dụ, ứng dụng có thể cần:

- thao tác chuỗi;
- cấp phát bộ nhớ;
- tính toán toán học;
- làm việc với thread;
- mã hóa/giải mã;
- xử lý ảnh;
- giao tiếp với phần cứng qua một API dùng chung;
- sử dụng một module do nhóm khác phát triển.

Nếu mỗi executable phải copy toàn bộ source của mọi thành phần vào project riêng thì sẽ xuất hiện nhiều vấn đề:

```text
Cùng một code
   |
   +--> copy vào App A
   +--> copy vào App B
   +--> copy vào App C

Hậu quả:
- khó bảo trì
- dễ lệch version
- build phức tạp
- khó tái sử dụng
```

Library tạo ra một đơn vị tái sử dụng ở mức binary hoặc gần mức binary:

```text
Source của library
      |
      v
Object files
      |
      +-------------------+
      |                   |
      v                   v
Static library         Shared library
   libfoo.a               libfoo.so
```

Ứng dụng không cần biết toàn bộ source bên trong library. Nó thường chỉ cần biết **interface** mà library cung cấp, ví dụ declaration trong header:

```c
int foo_init(void);
int foo_read(void *buf, size_t len);
```

Trong khi implementation có thể nằm trong một hoặc nhiều object file của library.

Mô hình tổng quát:

```text
Header / API contract
        |
        v
Application source ---------
                            |
Library implementation -----+--> Linker / Loader
```

Điểm cần phân biệt:

```text
Header file     = mô tả interface cho compiler
Library file    = chứa implementation ở dạng binary/object
```

Có header **không đồng nghĩa** có library.

Có library **không đồng nghĩa** compiler đã biết prototype của API.

Ví dụ, compiler có thể compile được lời gọi hàm nếu declaration hợp lệ, nhưng linker vẫn báo `undefined reference` nếu không tìm thấy implementation tương ứng.

> **Điểm cần nhớ:** Library chủ yếu giải quyết việc đóng gói và tái sử dụng implementation. Header và library phục vụ hai tầng khác nhau trong build pipeline.

---

## 2. Library tham gia vào build flow ở đâu?

Library chủ yếu xuất hiện rõ ở **giai đoạn link**, nhưng ảnh hưởng của nó bắt đầu từ sớm hơn.

Mô hình:

```text
application.c
     |
     | #include "foo.h"
     v
Preprocess / Compile
     |
     v
application.o
     |
     | unresolved reference: foo_init
     |
     +----------------------+
                            |
                     Library implementation
                     libfoo.a / libfoo.so
                            |
                            v
                         Linker
                            |
                            v
                      ELF executable
```

Compiler cần header để biết:

- tên function;
- kiểu tham số;
- kiểu trả về;
- type/structure liên quan;
- macro và constant cần thiết.

Linker cần binary implementation để giải quyết symbol.

Do đó thường tồn tại hai nhóm path khác nhau:

```text
Header search path          Library search path
------------------          -------------------
-I...                       -L...

compiler/preprocessor       linker
```

Và hai loại option khác nhau:

```text
-I/path/to/include
        |
        +--> tìm header

-L/path/to/lib
-lfoo
        |
        +--> tìm library tên phù hợp với `foo`
```

`-lfoo` không có nghĩa là linker đi tìm file có tên chính xác `foo`.

Theo convention phổ biến của GNU toolchain trên Linux, tên logic:

```text
-lfoo
```

thường liên hệ tới các file dạng:

```text
libfoo.so
libfoo.a
```

Tùy chế độ link và library khả dụng, linker có thể chọn shared hoặc static form.

### 2.1 Compile thành công không có nghĩa link thành công

Giả sử source có declaration hợp lệ:

```c
int foo_add(int a, int b);

int main(void)
{
    return foo_add(1, 2);
}
```

Compiler có thể tạo `main.o` vì nó biết signature của `foo_add()`.

Nhưng object file có thể chỉ chứa một **undefined symbol reference**:

```text
main.o
  defined:   main
  undefined: foo_add
```

Đến giai đoạn link, implementation mới phải được tìm thấy:

```text
main.o
  U foo_add
     |
     v
libfoo.a hoặc libfoo.so
  D foo_add
```

Nếu không có definition phù hợp:

```text
undefined reference to `foo_add`
```

Đây là lỗi linker, không phải lỗi compiler.

### 2.2 Link thành công cũng chưa bảo đảm runtime thành công

Với shared library, còn một tầng khác:

```text
Compile thành công
      |
Link thành công
      |
      v
Executable có dependency libfoo.so.1
      |
      | chạy trên target
      v
Dynamic linker tìm libfoo.so.1 ?
      |
      +--> có    -> tiếp tục load
      |
      +--> thiếu -> chương trình không start được
```

Do đó đối với shared library:

```text
Build-time success != Runtime dependency đã được thỏa mãn
```

Đây là một khác biệt quan trọng so với tư duy chỉ dừng ở linker.

---

## 3. Static library `.a` thực chất là gì?

Static library trên Unix/Linux thường có phần mở rộng `.a` và về bản chất là một **archive chứa các object file**.

Ví dụ logic:

```text
foo_math.o
foo_io.o
foo_util.o
     |
     | GNU ar
     v
+--------------------+
|     libfoo.a       |
|--------------------|
| foo_math.o         |
| foo_io.o           |
| foo_util.o         |
+--------------------+
```

Công cụ GNU `ar` được dùng để tạo, thay đổi và đọc archive.

Điểm rất quan trọng:

> `libfoo.a` không phải một executable được “đóng gói lại”. Nó thường là một container chứa nhiều relocatable object file.

Mỗi member bên trong vẫn mang những thông tin quen thuộc từ Chủ đề 1:

- machine code;
- section;
- symbol;
- relocation;
- metadata ELF tương ứng với relocatable object.

### 3.1 Vì sao không đơn giản đưa hàng chục `.o` trực tiếp vào linker?

Về mặt kỹ thuật, có thể link trực tiếp nhiều object:

```text
main.o + foo_math.o + foo_io.o + foo_util.o
```

Nhưng archive cung cấp một đơn vị đóng gói thuận tiện:

```text
main.o + libfoo.a
```

Điều này giúp:

- quản lý library như một artifact duy nhất;
- phân phối implementation ở dạng object;
- cho linker chọn các member cần thiết;
- tái sử dụng cùng một library cho nhiều executable.

### 3.2 Symbol index của archive

Archive có thể chứa một index giúp linker nhanh chóng xác định member nào định nghĩa symbol cần thiết.

Mô hình:

```text
libfoo.a
  |
  +-- Symbol index
  |      foo_add   -> foo_math.o
  |      foo_read  -> foo_io.o
  |      foo_log   -> foo_util.o
  |
  +-- foo_math.o
  +-- foo_io.o
  +-- foo_util.o
```

GNU `ar` có thể tạo/cập nhật symbol index; `ranlib` về mặt lịch sử và công cụ cũng liên quan tới việc tạo index này.

### 3.3 Static library không có nghĩa toàn bộ archive bị copy vào executable

Đây là một hiểu lầm rất phổ biến.

Giả sử:

```text
libfoo.a
  |
  +-- math.o   : foo_add(), foo_sub()
  +-- io.o     : foo_read()
  +-- debug.o  : foo_dump()
```

Nếu ứng dụng chỉ cần `foo_add()` thì linker thường không cần lấy mọi member của archive.

Mô hình đơn giản:

```text
main.o
  U foo_add
     |
     v
scan libfoo.a
     |
     +--> math.o cung cấp foo_add
             |
             v
        đưa math.o vào link

io.o / debug.o có thể không được kéo vào
```

Tuy nhiên selection thường diễn ra ở **mức object member**, không phải tự động ở mức từng function.

Nếu `math.o` chứa cả `foo_add()` và một số code khác, việc member `math.o` được kéo vào có thể mang theo nhiều section/function của member đó; các optimization/linker garbage collection khác có thể loại thêm phần không dùng, nhưng đó là cơ chế khác.

> **Điểm cần nhớ:** Static archive cho linker khả năng lấy các object member cần thiết. Không nên hiểu `.a` là “copy nguyên file library vào executable”.

---

## 4. Static linking hoạt động như thế nào?

`Static linking` là quá trình linker lấy implementation cần thiết từ object/static libraries và đưa chúng vào output ở link-time.

Mô hình:

```text
main.o
  U foo_add
  U bar_init

libfoo.a
  D foo_add

libbar.a
  D bar_init
      |
      v
    Linker
      |
      +--> lấy object member phù hợp
      +--> resolve symbol
      +--> apply relocation
      |
      v
Executable
  chứa code được lấy từ các static library
```

Sau link, executable không còn cần file `libfoo.a` chỉ để chạy phần code đã được đưa vào binary.

### 4.1 Static library khác static executable

Hai khái niệm này không giống nhau:

```text
Static library      = artifact dạng archive, thường là `.a`
Static executable   = executable được link để tránh phụ thuộc vào shared library tương ứng
```

Một executable có thể dùng **một số static library** nhưng vẫn phụ thuộc các shared library khác.

Ví dụ khái niệm:

```text
App
 |
 +-- libfoo.a      -> linked statically
 |
 +-- libc.so       -> vẫn dynamic
 |
 +-- libpthread... -> tùy toolchain/runtime
```

Do đó:

```text
Có `.a` trong lệnh link
        !=
Executable hoàn toàn static
```

Option `-static` của GCC trên các hệ thống hỗ trợ dynamic linking yêu cầu linker tránh dùng shared libraries cho các dependency thông thường, nhưng việc tạo fully static executable còn phụ thuộc vào việc static variants có tồn tại và toolchain/runtime có hỗ trợ hay không.

### 4.2 Static executable không có nghĩa “không phụ thuộc gì bên ngoài”

Ngay cả khi executable không cần shared libraries lúc startup, nó vẫn chạy trên một hệ thống cụ thể và vẫn phụ thuộc vào nhiều thứ:

```text
Static executable
      |
      +--> Kernel ABI / syscalls
      +--> CPU / ISA
      +--> ABI
      +--> filesystem / config / device nodes nếu ứng dụng cần
      +--> data files / certificates / timezone / firmware... tùy chương trình
```

Vì vậy:

> **Fully static** chủ yếu nói về cách library code được link, không phải tuyên bố rằng chương trình độc lập hoàn toàn với hệ điều hành và môi trường target.

### 4.3 Lợi ích và đánh đổi của static linking

Ưu điểm thường gặp:

- runtime ít phụ thuộc `.so` hơn;
- deployment đơn giản hơn trong một số hệ thống nhỏ;
- tránh một số mismatch version của shared library;
- có thể phù hợp với utility tối giản hoặc recovery environment.

Đánh đổi:

- executable thường lớn hơn;
- nhiều process dùng cùng library có thể lặp lại code trong file/bộ nhớ thay vì dùng chung mapping ở mức shared object;
- update library có thể yêu cầu relink/redeploy từng executable;
- một số runtime/library được thiết kế và kiểm thử chủ yếu theo dynamic model;
- license và distribution obligations của từng library vẫn phải được xem xét riêng.

Không có quy tắc rằng static luôn tốt hơn cho Embedded Linux. Quyết định phụ thuộc vào system design.

---

## 5. Shared library `.so` thực chất là gì?

Shared library trên Linux thường xuất hiện dưới dạng ELF shared object, convention tên thường chứa `.so`:

```text
libfoo.so
libfoo.so.1
libfoo.so.1.2.3
```

Khác static archive, shared object là một ELF image có cấu trúc phục vụ cho việc được map vào virtual address space và tham gia dynamic linking.

Mô hình:

```text
Application executable
        |
        | cần symbols từ libfoo
        v
+-----------------------+
|      libfoo.so        |
|-----------------------|
| ELF header            |
| code / data           |
| dynamic symbols       |
| relocation metadata   |
| dynamic metadata      |
| ...                   |
+-----------------------+
```

Shared object có thể được nhiều process sử dụng.

Ở mức khái quát:

```text
Process A ----+
              |
Process B ----+----> cùng file libfoo.so trên filesystem
              |
Process C ----+
```

Kernel có thể chia sẻ các physical pages chỉ đọc như code giữa nhiều process trong những điều kiện phù hợp, trong khi các vùng dữ liệu ghi được vẫn có semantics riêng theo từng process/mapping.

### 5.1 `.so` không phải “file source được nạp lúc chạy”

`libfoo.so` đã là machine-code binary cho target architecture/ABI cụ thể.

Nó không phải source C được compiler compile lại khi chương trình start.

Runtime flow không phải:

```text
.so
  -> compile lại
  -> chạy
```

Mà gần hơn với:

```text
.so đã là ELF machine code
     |
     | loader map vào process
     | relocation / symbol resolution cần thiết
     v
code sẵn sàng được thực thi
```

### 5.2 Shared object không hoàn toàn đồng nghĩa shared library

Trong ELF, `ET_DYN` được dùng cho shared object; trên Linux hiện đại, PIE executable cũng thường có ELF type `ET_DYN`.

Do đó:

```text
ELF Type: DYN
```

một mình chưa đủ để kết luận:

```text
"đây chắc chắn là một shared library"
```

Cần nhìn thêm vai trò của file, program headers, interpreter/dependencies và metadata khác.

Điểm này giúp tránh việc suy luận binary chỉ dựa vào một field ELF duy nhất.

---

## 6. Vì sao shared library thường cần Position-Independent Code?

Shared library có thể được map vào những virtual address khác nhau ở các process hoặc các lần chạy khác nhau.

Nếu machine code giả định cứng rằng library luôn nằm ở một địa chỉ tuyệt đối cố định, việc load sẽ rất hạn chế và có thể yêu cầu nhiều relocation lên code pages.

`Position-Independent Code` (`PIC`) là code được sinh theo cách phù hợp với việc chạy khi được đặt ở các địa chỉ khác nhau mà không cần giả định một base address cố định theo cách đơn giản.

Mô hình:

```text
C source của library
       |
       | compile với mô hình PIC
       v
PIC object files
       |
       | link -shared
       v
libfoo.so
       |
       +--> có thể được map vào vị trí phù hợp trong process
```

GCC cung cấp các option như:

```text
-fpic
-fPIC
```

để sinh position-independent code phù hợp cho shared library trên target hỗ trợ.

### 6.1 PIC không có nghĩa “không còn relocation”

Đây là điểm cần hiểu chính xác.

PIC không biến library thành một blob hoàn toàn không cần loader xử lý.

Shared object vẫn có thể cần:

- dynamic relocation;
- symbol lookup;
- cập nhật các bảng/slot runtime;
- dependency resolution.

Do đó:

```text
PIC != không có relocation
```

PIC là một code-generation model giúp code phù hợp hơn với dynamic loading/sharing.

### 6.2 `-fPIC` và `-shared` thuộc hai stage khác nhau

Hai option này thường xuất hiện cùng nhau nhưng không làm cùng việc:

```text
-fPIC
  |
  +--> compile/code-generation stage
       sinh position-independent object code

-shared
  |
  +--> link stage
       tạo shared object
```

Mô hình:

```text
foo.c
  |
  | compiler: PIC
  v
foo.o
  |
  | linker: shared output
  v
libfoo.so
```

Chỉ có `-fPIC` không tự biến `.o` thành shared library.

Chỉ có `-shared` cũng không có nghĩa mọi input object tự động được compile lại thành PIC.

GCC documentation vì vậy khuyến nghị dùng code-generation options phù hợp khi tạo shared object.

### 6.3 Không cần đào sâu GOT/PLT ở chủ đề này

PIC trên ELF thường liên quan tới các cơ chế như:

```text
GOT
PLT
PC-relative addressing
Dynamic relocation
```

Nhưng ở mức chủ đề này chỉ cần giữ mental model:

> Shared library không nên phụ thuộc vào một địa chỉ load tuyệt đối cố định; compiler/linker/loader phối hợp để code và references hoạt động khi object được map vào process.

Chi tiết GOT/PLT thuộc tầng ELF/linker nâng cao.

---

## 7. Dynamic linking và dynamic linker/loader

Với dynamically linked executable, công việc không kết thúc hoàn toàn ở build-time.

Có hai giai đoạn cần tách rõ:

```text
Link-time
=========
Linker tạo executable
và ghi thông tin dependency/symbol cần thiết

Runtime / load-time
===================
Dynamic linker/loader
- tìm shared objects
- map chúng vào process
- xử lý relocation/symbol resolution cần thiết
- chuẩn bị để chương trình chạy
```

Trên Linux ELF, dynamic linker/loader thường có pathname dạng kiến trúc/runtime cụ thể, ví dụ các tên thuộc họ `ld-linux...`.

Executable động chứa thông tin để Kernel/runtime biết interpreter nào sẽ hỗ trợ load nó.

Mô hình khái quát:

```text
execve("./app")
      |
      v
Kernel đọc ELF
      |
      +--> nhận biết ELF interpreter
      |
      v
Dynamic linker/loader
      |
      +--> đọc dependency
      +--> tìm shared objects
      +--> map chúng
      +--> relocation / symbol resolution
      |
      v
Application bắt đầu chạy
```

### 7.1 Linker và dynamic linker/loader không phải cùng một chương trình

Đây là một cặp rất dễ nhầm:

```text
Linker (`ld` trong GNU toolchain)
    |
    +--> build-time
    +--> tạo ELF output

Dynamic linker/loader (`ld.so`, `ld-linux...`)
    |
    +--> runtime/load-time
    +--> tìm và nạp shared objects
```

Cả hai đều liên quan tới symbol và relocation, nhưng làm việc ở thời điểm và ngữ cảnh khác nhau.

### 7.2 Kernel không tự mình thực hiện toàn bộ dynamic linking

Kernel tham gia việc `exec`, virtual memory mapping và load interpreter, nhưng logic tìm shared-library dependency và nhiều phần dynamic symbol resolution nằm ở user-space dynamic linker/loader.

Mô hình đúng hơn:

```text
Kernel
  |
  +--> nhận ELF / tạo process image cơ bản
  +--> chuyển điều khiển qua ELF interpreter

Dynamic linker/loader (userspace)
  |
  +--> xử lý dynamic dependencies
  +--> chuẩn bị shared objects
```

Điều này rất quan trọng trong Embedded Linux vì target root filesystem phải chứa **đúng dynamic loader** mà executable yêu cầu.

Nếu loader pathname được ghi trong ELF nhưng file đó không tồn tại trên target, chương trình có thể không start dù chính executable vẫn hiện diện và có quyền execute.

---

## 8. ELF ghi nhận shared-library dependency như thế nào?

Khi executable được link với shared library, linker thường không copy toàn bộ implementation của library vào executable.

Thay vào đó, output chứa metadata động.

Một phần quan trọng là các entry dạng `DT_NEEDED` trong dynamic section.

Mô hình:

```text
Application ELF
+---------------------------+
| ELF / Program headers     |
| .text / .data / ...       |
|                           |
| Dynamic metadata          |
|   NEEDED: libfoo.so.1     |
|   NEEDED: libc.so.6       |
|   ...                     |
+---------------------------+
            |
            | runtime
            v
Dynamic linker tìm các object tương ứng
```

Điều này giải thích tại sao executable có thể rất nhỏ so với tổng code của tất cả shared libraries mà nó dùng.

### 8.1 Link-time symbol resolution và runtime resolution liên hệ với nhau

Giả sử `main.o` có:

```text
U foo_add
```

Shared library export:

```text
libfoo.so
D foo_add
```

Ở link-time, linker cần đủ thông tin để xác nhận dependency và tạo relocation/dynamic metadata thích hợp.

Nhưng địa chỉ runtime cuối cùng của `foo_add` phụ thuộc vào shared object được map ở đâu và symbol resolution của dynamic loader.

Do đó có thể hình dung:

```text
Build-time:
"foo_add sẽ được cung cấp bởi một dynamic dependency"

Runtime:
"foo_add thực tế nằm ở virtual address nào trong process này?"
```

### 8.2 `DT_NEEDED` thường lưu dependency name, không nhất thiết pathname tuyệt đối

Thông thường dependency được biểu diễn bằng tên như:

```text
libfoo.so.1
```

Thay vì luôn ghi:

```text
/opt/vendor/lib/libfoo.so.1
```

Dynamic loader sau đó áp dụng library search rules để tìm object phù hợp.

Điều này cho phép cùng executable chạy trên các filesystem layout hợp lệ khác nhau, miễn search policy tìm ra library tương thích.

### 8.3 Dependency tồn tại chưa đủ — binary compatibility vẫn phải đúng

Giả sử target có file đúng tên:

```text
/lib/libfoo.so.1
```

Nhưng file đó được build cho x86-64 trong khi target là AArch64.

Tên đúng không cứu được binary mismatch.

Ta vẫn phải thỏa mãn các lớp từ Chủ đề 2:

```text
Tên dependency đúng
        +
Architecture đúng
        +
ABI đúng
        +
ELF/runtime compatible
        +
Các dependent libraries khác cũng thỏa mãn
```

---

## 9. `SONAME` và versioning của shared library

Shared library thường cần một cơ chế để tách:

- tên dùng khi development/link;
- tên ABI mà executable phụ thuộc;
- file implementation cụ thể trên filesystem.

Một layout phổ biến có thể trông như:

```text
libfoo.so        -> libfoo.so.1
libfoo.so.1      -> libfoo.so.1.4.2
libfoo.so.1.4.2
```

Ba tên này thường đóng các vai trò khác nhau.

### 9.1 Linker name

Tên:

```text
libfoo.so
```

thường được dùng khi development/link với:

```text
-lfoo
```

File này có thể là symlink tới version thực tế.

### 9.2 `SONAME`

Shared object có thể chứa `DT_SONAME`, ví dụ:

```text
libfoo.so.1
```

Khi executable được link với shared object có `SONAME`, dependency runtime thường sử dụng `SONAME` này.

Mô hình:

```text
Link-time file:
libfoo.so -> libfoo.so.1.4.2

Inside libfoo.so.1.4.2:
SONAME = libfoo.so.1

Executable:
DT_NEEDED = libfoo.so.1
```

Điểm quan trọng:

> Runtime dependency không nhất thiết ghi lại chính xác filename mà developer đã truyền vào linker.

### 9.3 Vì sao có major version trong `SONAME`?

Một convention phổ biến là thay đổi major `SONAME` khi library phá vỡ ABI compatibility.

Ví dụ:

```text
libfoo.so.1   -> ABI generation 1
libfoo.so.2   -> ABI generation 2
```

Hai generation có thể cùng tồn tại trên filesystem:

```text
/usr/lib/libfoo.so.1
/usr/lib/libfoo.so.2
```

Executable cũ:

```text
NEEDED libfoo.so.1
```

Executable mới:

```text
NEEDED libfoo.so.2
```

Nhờ vậy nâng cấp library không nhất thiết buộc mọi application chuyển ABI cùng lúc.

### 9.4 API version và ABI version không phải một khái niệm

Một library có thể thêm function mới mà vẫn giữ binary compatibility cho code cũ.

Ngược lại, một thay đổi nhỏ trong source-level interface/layout cũng có thể phá ABI.

Ví dụ các thay đổi có thể ảnh hưởng ABI:

- thay đổi layout của public `struct`;
- thay đổi calling convention;
- thay đổi type của parameter;
- loại bỏ exported symbol;
- thay đổi symbol semantics theo cách không tương thích;
- thay đổi C++ ABI liên quan class/vtable/name mangling.

Do đó:

```text
Source version number
        !=
ABI compatibility guarantee
```

`SONAME` là một cơ chế runtime/dependency, không tự động xác minh rằng developer đã duy trì ABI đúng.

---

## 10. Link-time search path và runtime search path

Một trong những nguồn gây nhầm nhiều nhất là nghĩ rằng:

```text
Linker đã tìm thấy libfoo.so
        =>
Runtime chắc chắn cũng tìm thấy libfoo.so
```

Điều này **không đúng**.

Hai thời điểm dùng hai cơ chế tìm kiếm khác nhau.

### 10.1 Link-time search

Khi tạo executable/shared object, linker cần tìm library input.

Mô hình:

```text
-L/path/to/sdk/lib
-lfoo
     |
     v
Linker tìm libfoo.* trong search path link-time
```

`-L` chủ yếu ảnh hưởng **link-time library search**.

Nó không tự động có nghĩa dynamic loader ở target sẽ tìm cùng directory đó lúc chạy.

### 10.2 Runtime search

Khi chương trình chạy, dynamic linker/loader phải tìm dependency như:

```text
DT_NEEDED: libfoo.so.1
```

Runtime search có thể chịu ảnh hưởng bởi các cơ chế như:

```text
DT_RUNPATH / DT_RPATH trong ELF
LD_LIBRARY_PATH
/etc/ld.so.cache
default library directories
```

Cùng với các rule và ngoại lệ của dynamic loader, ví dụ secure-execution mode.

Thứ tự chính xác và semantics giữa `RPATH`/`RUNPATH` có nuance; khi cần chẩn đoán chính xác phải dựa vào `ld.so(8)` của runtime đang sử dụng.

### 10.3 `RPATH` và `RUNPATH` ở mức cần thiết

Executable/shared object có thể mang embedded search path trong dynamic metadata.

Khái niệm:

```text
App ELF
  |
  +-- NEEDED: libfoo.so.1
  +-- RUNPATH: $ORIGIN/../lib
```

Token như `$ORIGIN` có thể đại diện cho directory chứa binary/shared object trong ngữ cảnh dynamic loader.

Điều này hữu ích khi thiết kế application bundle có layout tương đối:

```text
app-root/
  bin/app
  lib/libfoo.so.1
```

Nhưng đây là policy deployment; không nên nhầm nó với sysroot của cross toolchain.

### 10.4 Sysroot khác runtime library search path

Từ Chủ đề 2:

```text
Sysroot
  |
  +--> build-time view của target headers/libraries
```

Trong khi:

```text
Runtime search path
  |
  +--> dynamic loader trên target tìm `.so` khi chương trình chạy
```

Một library có thể tồn tại trong sysroot để link nhưng bị thiếu trong root filesystem được deploy.

Ví dụ:

```text
SDK sysroot:
/usr/lib/libfoo.so.1     [có]

Target rootfs:
/usr/lib/libfoo.so.1     [thiếu]
```

Kết quả:

```text
Cross-link thành công
Runtime thất bại
```

Đây là lỗi cực kỳ điển hình trong Embedded Linux.

---

## 11. Static và dynamic linking khác nhau như thế nào?

Có thể đặt hai mô hình cạnh nhau:

```text
STATIC
======
main.o
  + libfoo.a
      |
      | linker lấy object code cần thiết
      v
executable chứa code đó

Runtime:
không cần libfoo.a


DYNAMIC
=======
main.o
  + libfoo.so
      |
      | linker tạo dynamic dependency
      v
executable có NEEDED libfoo.so.X
      |
      | runtime
      v
dynamic loader tìm/map libfoo.so.X
```

Bảng so sánh:

| Khía cạnh | Static linking | Dynamic linking |
|---|---|---|
| Artifact library điển hình | `.a` | `.so` |
| Code library vào executable | Thường được đưa vào ở link-time | Chủ yếu ở shared object riêng |
| Cần library file đó lúc runtime | Không cần `.a` đã dùng để link | Cần shared object dependency tương ứng |
| Kích thước executable | Thường lớn hơn | Thường nhỏ hơn |
| Chia sẻ code giữa process | Không theo shared-object mapping của library | Có thể chia sẻ read-only code pages |
| Update library | Thường cần relink/redeploy app để nhận code mới | Có thể cập nhật `.so` nếu ABI vẫn tương thích |
| Rủi ro runtime missing-library | Thấp hơn với phần đã static-link | Có thể xảy ra |
| ABI compatibility của runtime library | Không áp dụng cho phần đã copy vào binary theo cùng cách | Rất quan trọng |

### 11.1 Không có mô hình nào “luôn tốt hơn”

Trong Embedded Linux, lựa chọn phụ thuộc vào:

- dung lượng storage;
- số lượng process dùng chung library;
- RAM/page sharing;
- update strategy;
- rootfs design;
- recovery strategy;
- boot/startup requirements;
- security/update policy;
- licensing;
- SDK/vendor constraints.

Ví dụ:

```text
Một utility recovery nhỏ, độc lập
        -> static có thể hấp dẫn

Nhiều application cùng dùng Qt/GLib/OpenSSL lớn
        -> shared model thường hợp lý hơn
```

Nhưng phải đánh giá theo toàn hệ thống, không theo slogan “embedded thì static”.

### 11.2 Shared library có thể giảm duplication nhưng không miễn phí

Dynamic linking mang thêm:

- loader work;
- dynamic relocation;
- dependency management;
- compatibility policy;
- filesystem search;
- deployment/versioning complexity.

Do đó lợi ích dung lượng/chia sẻ phải đổi lấy thêm runtime infrastructure.

---

## 12. Link order và dependency giữa các library

Static archives làm lộ rõ một đặc tính quan trọng của linker: **thứ tự input có thể ảnh hưởng kết quả**.

Giả sử:

```text
main.o
  U foo

libfoo.a
  D foo
```

Mô hình đơn giản khi linker đi qua input từ trái sang phải:

```text
main.o
  -> thấy unresolved `foo`

libfoo.a
  -> tìm member cung cấp `foo`
  -> kéo member đó vào
```

Nếu archive xuất hiện trước khi linker biết cần symbol nào, tùy linker/options và dependency graph, member có thể không được chọn theo cách mong đợi.

Đây là lý do thường thấy quy tắc tư duy:

> Object/library cung cấp symbol thường phải xuất hiện sau object đã tạo ra nhu cầu đối với symbol đó khi làm việc với static archives và GNU-style linking.

### 12.1 Library A phụ thuộc Library B

Giả sử:

```text
main.o
  U foo

libA.a
  D foo
  U bar

libB.a
  D bar
```

Dependency graph:

```text
main.o
  |
  v
foo
  |
  v
libA.a
  |
  v
bar
  |
  v
libB.a
```

Linker cần nhìn thấy đủ input theo thứ tự/nhóm phù hợp để giải quyết toàn bộ chain.

Đây là một trong những lý do build system cần biểu diễn dependency chính xác thay vì ghép flags một cách ngẫu nhiên.

### 12.2 Circular dependency giữa static archives

Nếu:

```text
libA.a cần symbol từ libB.a
libB.a lại cần symbol từ libA.a
```

thì dependency vòng có thể cần linker group mechanism hoặc thiết kế library tốt hơn.

GNU `ld` có các cơ chế như `--start-group` / `--end-group` để tìm lặp giữa một nhóm archive, nhưng chúng có chi phí và không phải thứ cần dùng mặc định.

Ở mức chủ đề này chỉ cần nhớ:

```text
Static archive resolution phụ thuộc vào
- unresolved symbols tại thời điểm scan
- thứ tự input
- dependency graph
```

### 12.3 Shared library dependency cũng cần được mô hình hóa rõ

Với shared library, vấn đề không biến mất; nó chuyển một phần sang dynamic dependency graph:

```text
app
 |
 +--> libA.so
       |
       +--> libB.so
              |
              +--> libc.so...
```

Target rootfs phải cung cấp dependency closure phù hợp, không chỉ library trực tiếp mà developer nhớ tên.

---

## 13. `dlopen()`: dynamic loading không hoàn toàn giống dynamic linking thông thường

Một shared object có thể được nạp theo hai kiểu tư duy phổ biến.

### 13.1 Dependency được ghi sẵn trong executable/shared object

Mô hình thông thường:

```text
Link-time:
app linked against libfoo.so

ELF:
DT_NEEDED = libfoo.so.1

Runtime:
dynamic loader tự nạp dependency khi process start/load
```

### 13.2 Nạp explicit bằng `dlopen()`

Ứng dụng cũng có thể yêu cầu nạp shared object khi đang chạy:

```text
Application
   |
   | dlopen("plugin.so", ...)
   v
Dynamic linker/loader
   |
   v
Map plugin.so
   |
   | dlsym(...)
   v
Tìm symbol theo tên
```

Đây là cơ sở cho nhiều plugin architecture.

### 13.3 Shared library không đồng nghĩa plugin

Một `.so` được link như dependency thông thường không nhất thiết là plugin.

Một plugin thường có thêm contract riêng:

```text
Host application
      |
      | biết plugin ABI/API
      v
plugin.so
      |
      +--> export entry points đã quy ước
```

Do đó cần phân biệt:

```text
Shared object      = loại binary/object có thể tham gia dynamic linking/loading
Shared library     = shared object cung cấp library API
Plugin             = module được host load theo plugin contract
```

Chúng có liên quan nhưng không đồng nghĩa.

### 13.4 `dlopen()` không bỏ qua ABI

Dù library được nạp explicit, mọi ràng buộc binary vẫn còn:

- architecture;
- ABI;
- symbol names;
- function signatures;
- data layout;
- dependency của chính plugin;
- C/C++ runtime compatibility.

`dlsym()` trả về symbol address không có nghĩa caller có thể gọi nó với signature tùy ý.

Nếu host và plugin không thống nhất ABI contract, lỗi runtime có thể rất khó chẩn đoán.

---

## 14. Tư duy chẩn đoán lỗi library

Khi gặp lỗi liên quan library, nên xác định **lỗi xảy ra ở stage nào** trước.

```text
Compile-time?
     |
     v
Link-time?
     |
     v
Program load-time?
     |
     v
Runtime sau khi đã start?
```

Đây là cách phân lớp hiệu quả hơn việc chỉ nhìn tên `.a` hoặc `.so`.

### 14.1 Compiler báo không tìm thấy header

Ví dụ dạng:

```text
fatal error: foo/foo.h: No such file or directory
```

Đây chưa phải lỗi library binary.

Cần nghĩ tới:

```text
Header search path
SDK/sysroot include tree
Development package/header có tồn tại không
```

Không nên bắt đầu bằng runtime `LD_LIBRARY_PATH` vì compiler còn chưa đi đến giai đoạn link.

### 14.2 Linker báo `cannot find -lfoo`

Tư duy:

```text
Linker đang tìm input library
      |
      +--> search path có đúng không?
      +--> tên file/convention có đúng không?
      +--> library cho target có tồn tại không?
      +--> chỉ có runtime `.so.X` nhưng thiếu linker name `libfoo.so`?
```

Đây là **link-time search problem**.

### 14.3 Linker báo `undefined reference`

Library file có thể đã được tìm thấy nhưng symbol cần thiết chưa được giải quyết.

Các khả năng:

```text
- thiếu library cung cấp symbol
- sai link order
- sai version library
- symbol không được export
- tên/signature bị khác do C/C++ linkage
- static archive member không được chọn như kỳ vọng
- conditional build làm implementation không tồn tại
```

Do đó:

```text
"library file tồn tại"
    !=
"library cung cấp đúng symbol mà linker cần"
```

### 14.4 Program load-time báo không tìm thấy `.so`

Dạng lỗi điển hình:

```text
error while loading shared libraries: libfoo.so.1: cannot open shared object file
```

Tư duy:

```text
Executable đã build xong
      |
      v
Dynamic loader không resolve được runtime dependency
      |
      +--> library chưa deploy
      +--> runtime search path không thấy
      +--> sai SONAME/version
      +--> dependency bậc dưới bị thiếu
```

Đây không phải vấn đề của `-I` và thường cũng không phải vấn đề source code.

### 14.5 File tồn tại nhưng báo sai ELF class / architecture

Ví dụ tình huống:

```text
App: AArch64
libfoo.so: x86-64
```

Path đúng nhưng binary không tương thích.

Luôn kiểm tra theo chuỗi:

```text
File tồn tại?
   |
Tên/SONAME đúng?
   |
Architecture đúng?
   |
ABI / ELF class đúng?
   |
Dependencies con đầy đủ?
```

### 14.6 Build trên SDK được nhưng chạy trên target lỗi version symbol

Shared library có thể cùng tên/major nhưng runtime version không cung cấp symbol version mà binary yêu cầu.

Mô hình:

```text
SDK sysroot có libc/libfoo mới
        |
        | link
        v
Binary yêu cầu symbol/version mới
        |
        | deploy sang rootfs cũ
        v
Runtime library không đáp ứng
```

Đây là một biểu hiện của việc **sysroot và target rootfs không đồng bộ**.

### 14.7 Các công cụ quan sát nằm ở tầng nào?

Các công cụ quen thuộc từ Chủ đề 1 có thể được dùng để quan sát, nhưng ở đây chỉ cần hiểu vai trò:

| Công cụ | Câu hỏi chính |
|---|---|
| `file` | Artifact là ELF/archive gì, architecture nào? |
| `ar` | Static archive chứa những member nào? |
| `nm` | Symbol nào được định nghĩa/undefined? |
| `readelf -d` | Dynamic dependency/SONAME/RUNPATH metadata là gì? |
| `readelf -h` | ELF class/machine/type là gì? |
| `objdump` | Object code/symbol/relocation ở mức binary ra sao? |
| `ldd` | Runtime dependency resolution nhìn thấy gì trên hệ thống hiện tại? |

Với cross-built binary, cần cẩn thận khi dùng công cụ của host và khi suy luận từ runtime của host: target binary có thể cần target-specific `readelf/objdump` hoặc generic tool hỗ trợ format, và `ldd` trên host không đại diện cho rootfs của target.

> **Điểm cần nhớ:** Chẩn đoán library phải luôn gắn công cụ với đúng stage và đúng environment.

---

## 15. Liên hệ với Embedded Linux

Static/dynamic library trong Embedded Linux không chỉ là quyết định của một lệnh `gcc`. Nó liên quan trực tiếp tới thiết kế SDK, sysroot, root filesystem và cơ chế update sản phẩm.

### 15.1 Cross-link sử dụng library của target, không phải library của host

Mô hình đúng:

```text
Development host: x86-64
      |
      | aarch64-linux-gnu-gcc
      v
Target objects: AArch64
      |
      +--> sysroot/usr/lib/libfoo.so   [AArch64]
      +--> sysroot/usr/lib/libbar.a    [AArch64]
      |
      v
AArch64 executable
```

Mô hình sai:

```text
AArch64 object
   +
/usr/lib/x86_64-linux-gnu/libfoo.so
   |
   v
Không thể coi là dependency hợp lệ chỉ vì cùng tên API
```

Library phải phù hợp target architecture/ABI.

### 15.2 Sysroot và rootfs phải tạo thành một contract

Trong cross-development:

```text
SDK sysroot
   |
   | dùng khi compile/link
   v
Binary requirements
   |
   | phải được đáp ứng bởi
   v
Target rootfs
```

Nếu sysroot chứa:

```text
libfoo.so.2
```

nhưng rootfs chỉ có:

```text
libfoo.so.1
```

thì build host có thể hoàn toàn thành công trong khi target thất bại.

Do đó SDK không nên được xem là một thư mục library độc lập với image/rootfs của sản phẩm.

### 15.3 Dynamic loader cũng là một target runtime dependency

Executable động không chỉ cần `libc.so` và các `.so` khác.

Nó còn phụ thuộc vào ELF interpreter phù hợp:

```text
AArch64 dynamically linked app
       |
       +--> AArch64 dynamic loader
       +--> AArch64 libc
       +--> vendor/application shared libraries
```

Nếu copy một binary từ SDK sang một rootfs không có loader tương ứng, shell có thể báo lỗi gây hiểu nhầm như file không tồn tại hoặc không thể execute, dù pathname của executable là đúng.

Mental model cần là:

```text
Executable file tồn tại
        !=
Runtime environment đầy đủ
```

### 15.4 Shared libraries ảnh hưởng trực tiếp tới rootfs composition

Khi tạo firmware image, build system cần đưa vào dependency closure phù hợp:

```text
/app/bin/myapp
      |
      +--> libfoo.so.1
      +--> libbar.so.2
              |
              +--> libbaz.so.0
```

Nếu chỉ copy `myapp` mà bỏ các library cần thiết, image có thể build thành công nhưng ứng dụng không chạy.

Đây là lý do các hệ thống build Embedded Linux như Buildroot hoặc Yocto Project phải quản lý package/runtime dependencies chứ không chỉ compile source.

### 15.5 Static linking có thể hữu ích cho recovery nhưng không phải mặc định tuyệt đối

Một utility recovery/rescue có ít dependency runtime có thể hữu ích khi rootfs chính gặp vấn đề.

Mô hình:

```text
Recovery binary
      |
      +--> giảm phụ thuộc vào shared-library tree của rootfs chính
```

Nhưng fully static design có trade-off về kích thước, update, libc/runtime behavior và license.

Do đó cần thiết kế dựa trên requirement, không phải quy tắc “embedded = static”.

### 15.6 Shared library giúp cập nhật tập trung nhưng làm ABI trở thành trách nhiệm hệ thống

Nếu nhiều application dùng chung:

```text
libplatform.so.3
```

thì update library có thể sửa một bug cho nhiều application cùng lúc.

Nhưng nếu update phá ABI:

```text
App A ----+
App B ----+--> libplatform.so.3 mới nhưng không compatible
App C ----+
```

thì nhiều component có thể hỏng đồng thời.

Vì vậy firmware product cần có policy về:

- versioning;
- ABI compatibility;
- package dependencies;
- atomic update/rollback;
- SDK và rootfs synchronization.

### 15.7 Vendor SDK thường cung cấp cả static và shared variants

Một vendor SDK có thể chứa:

```text
sysroot/usr/include/vendor/foo.h
sysroot/usr/lib/libfoo.a
sysroot/usr/lib/libfoo.so
```

Điều này không có nghĩa hai artifact có thể dùng tùy tiện mà không đọc build/runtime constraints.

Shared variant có thể cần thêm runtime libraries; static variant có thể kéo thêm transitive dependencies hoặc chịu licensing khác.

Cần đọc SDK documentation và link interface cụ thể.

### 15.8 Cầu nối sang Makefile và CMake

Sau ba chủ đề đầu, ta đã có dependency graph kỹ thuật:

```text
Source
  |
  v
Object files
  |
  +--> target headers / sysroot
  +--> static libraries
  +--> shared libraries
  |
  v
Linker
  |
  v
Executable / shared object
```

Nhưng nếu project có hàng chục source file và nhiều library, gõ thủ công từng command không còn hợp lý.

Chủ đề 4 sẽ giải quyết câu hỏi:

> Làm thế nào mô tả dependency graph và chỉ rebuild những artifact cần thiết?

Đó là vai trò của `Make`/Makefile.

---

## 16. Tổng kết và mô hình tư duy

### 16.1 Mô hình tổng thể

Toàn bộ chủ đề có thể thu về hai nhánh chính:

```text
                         Library implementation
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
              Static library               Shared library
                libfoo.a                    libfoo.so.X
                    |                           |
                    | link-time                 | link-time
                    v                           v
              +-----------+              +--------------+
main.o ------>|  Linker   |              |    Linker    |<------ main.o
              +-----------+              +--------------+
                    |                           |
                    v                           v
          Executable chứa code          Executable chứa dynamic
          được lấy từ archive           dependency / relocation info
                                                |
                                                | runtime
                                                v
                                      Dynamic linker/loader
                                                |
                                                +--> tìm `.so`
                                                +--> map vào process
                                                +--> resolve/relocate
                                                |
                                                v
                                            Program runs
```

> **Đọc sơ đồ:** Static và dynamic library cùng tham gia giải quyết symbol nhưng tại các thời điểm khác nhau. Static archive cung cấp object code để linker đưa vào output. Shared library để lại một phần công việc cho runtime dynamic linker/loader, vì code vẫn nằm trong `.so` riêng trên target.

### 16.2 Các phân biệt cần nhớ

```text
Header file                  != Library file
Compile success              != Link success
Link success                 != Runtime dependency đầy đủ
Static library `.a`          != Static executable
Static archive               != Toàn bộ archive luôn bị copy vào output
Shared object `.so`          != Source được compile lại lúc runtime
Shared object                != Plugin
Shared library               != `dlopen()` bắt buộc
Linker                       != Dynamic linker/loader
Link-time search path        != Runtime search path
`-I`                         != `-L`
`-L`                         != runtime `LD_LIBRARY_PATH`
Sysroot                      != Runtime rootfs
`-fPIC`                      != `-shared`
PIC                          != Không còn relocation
ELF `ET_DYN`                 != Chắc chắn là shared library
Filename                     != `SONAME`
API compatibility            != ABI compatibility
Library cùng tên             != Library binary-compatible
File tồn tại                 != Dynamic loader load được
Static linking               != Không còn phụ thuộc Kernel/runtime environment
```

### 16.3 Các điểm cốt lõi

1.  Library đóng gói implementation để nhiều chương trình/component tái sử dụng; header mô tả interface cho compiler còn library cung cấp binary implementation cho link/runtime.
2.  Static library `.a` thường là archive chứa relocatable object files và symbol index.
3.  Khi link static archive, linker thường chỉ kéo vào các object member cần để giải quyết unresolved symbols, thay vì copy mù toàn bộ archive.
4.  Dùng một static library không đồng nghĩa executable trở thành fully static.
5.  Shared library là ELF shared object được giữ thành artifact riêng và thường được dynamic linker/loader map vào process khi chạy.
6.  Shared library thường được build từ position-independent code; `-fPIC` thuộc code-generation stage còn `-shared` thuộc link stage.
7.  Dynamic linker/loader khác build-time linker: một bên tạo output ELF, một bên xử lý dynamic dependencies lúc load/runtime.
8.  Shared-library dependencies được ghi trong dynamic metadata như `DT_NEEDED`; `SONAME` giúp biểu diễn runtime ABI identity của library.
9.  Link-time search và runtime search là hai cơ chế khác nhau. `-L` giúp linker tìm library nhưng không tự bảo đảm target loader tìm được `.so` lúc chạy.
10. `SONAME`/major version thường được dùng để quản lý ABI generations, nhưng naming convention không tự bảo đảm ABI compatibility.
11. Static archive resolution có thể phụ thuộc link order và dependency graph; build system phải mô tả dependency chính xác.
12. `dlopen()` cho phép nạp shared object explicit khi runtime, thường dùng cho plugin/module architecture, nhưng không loại bỏ các yêu cầu ABI.
13. Trong cross-compilation, mọi library phải thuộc target architecture/ABI; library của development host không thể dùng chỉ vì có cùng tên.
14. Sysroot dùng lúc build và target rootfs dùng lúc runtime phải được đồng bộ về library/runtime contract.
15. Trong Embedded Linux, lựa chọn static hay dynamic là system-design decision liên quan storage, RAM, updates, ABI, recovery, rootfs và deployment policy.

---

## 17. Tài liệu tham khảo

### 17.1 GCC

1. GNU Project — **Using the GNU Compiler Collection — Link Options** (`-static`, `-shared`, `-rdynamic`, ...)
   <https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html>

2. GNU Project — **Using the GNU Compiler Collection — Code Generation Options** (`-fpic`, `-fPIC`, `-fpie`, `-fPIE`)
   <https://gcc.gnu.org/onlinedocs/gcc/Code-Gen-Options.html>

3. GNU Project — **Using the GNU Compiler Collection — Directory Options** (`-I`, `-L`, `--sysroot`, ...)
   <https://gcc.gnu.org/onlinedocs/gcc/Directory-Options.html>

### 17.2 GNU Binutils / Linker

4. GNU Project / Sourceware — **GNU Binary Utilities — `ar`**
   <https://sourceware.org/binutils/docs/binutils/ar.html>

5. GNU Project / Sourceware — **GNU `ld` Manual**
   <https://sourceware.org/binutils/docs/ld.html>

6. GNU Project / Sourceware — **GNU `nm`**
   <https://sourceware.org/binutils/docs/binutils/nm.html>

7. GNU Project / Sourceware — **GNU `readelf`**
   <https://sourceware.org/binutils/docs/binutils/readelf.html>

### 17.3 Linux dynamic linker / loader

8. Linux man-pages — **`ld.so(8)` — dynamic linker/loader**
   <https://man7.org/linux/man-pages/man8/ld.so.8.html>

9. Linux man-pages — **`dlopen(3)` — open a shared object**
   <https://man7.org/linux/man-pages/man3/dlopen.3.html>

10. Linux man-pages — **`dlsym(3)` — obtain address of a symbol from a shared object**
    <https://man7.org/linux/man-pages/man3/dlsym.3.html>

11. Linux man-pages — **`ldd(1)` — print shared object dependencies**
    <https://man7.org/linux/man-pages/man1/ldd.1.html>

12. Linux man-pages — **`ldconfig(8)` — configure dynamic linker run-time bindings**
    <https://man7.org/linux/man-pages/man8/ldconfig.8.html>

### 17.4 ELF / ABI

13. System V Application Binary Interface — **Generic ABI (ELF)**
    <https://refspecs.linuxfoundation.org/elf/gabi4+/contents.html>

14. Arm — **Application Binary Interface for the Arm Architecture (ABI-AA)**
    <https://github.com/ARM-software/abi-aa>

### 17.5 Tài liệu nền tảng

15. John R. Levine — **Linkers and Loaders** — Morgan Kaufmann.

16. Michael Kerrisk — **The Linux Programming Interface** — No Starch Press.

17. Ulrich Drepper — **How To Write Shared Libraries** — tài liệu chuyên sâu về ELF/shared-library design; chỉ nên đọc sau khi đã chắc các khái niệm trong chương này.

> **Điều hướng:** [← Chủ đề 2 — Native & Cross Toolchain](README-topic-02.md) · [Chủ đề 4 — Makefile →](README-topic-04.md)
