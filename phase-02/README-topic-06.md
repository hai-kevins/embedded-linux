# Chủ đề 6 — GDB Fundamentals

> **Mục tiêu:** Hiểu bản chất của debugger và vai trò của GDB trong quá trình tìm lỗi runtime; xây dựng mental model liên kết `source code → debug information → machine code → trạng thái tiến trình`; phân biệt symbol với debug information; hiểu breakpoint, `continue`, `step`, `next`, stack frame, backtrace, variable, memory và register; hiểu vì sao chương trình có thể dừng vì signal như `SIGSEGV`; nắm được ảnh hưởng của optimization tới quá trình debug và cách suy luận lỗi theo từng lớp. Sau chương này, người học phải hiểu GDB đang quan sát **trạng thái nào của chương trình**, dữ liệu đó đến từ đâu và vì sao debugger có thể nối một địa chỉ máy đang thực thi ngược trở lại source code.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các thuật ngữ chuẩn trong tài liệu GDB như `debug information`, `inferior`, `breakpoint`, `watchpoint`, `stack frame`, `backtrace`, `selected frame`, `program counter`, `stack pointer`, `core dump`, `post-mortem debugging`, `remote debugging` được giữ nguyên bằng tiếng Anh và giải thích tại vị trí phù hợp.
>
> **Phạm vi:** GDB ở mức nền tảng cho chương trình C trên Linux: debug information, symbol, breakpoint, stop/resume, `step`/`next`, stack frame, backtrace, variable/expression, memory, register, signal, segmentation fault, core dump, ảnh hưởng của optimization và remote debugging ở mức mental model. Reverse debugging, Python scripting cho GDB, pretty-printer nâng cao, tracepoint, JTAG/OpenOCD, kernel debugging, DWARF internals, unwind internals và debugging đa luồng chuyên sâu không thuộc phạm vi chương này.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để xây dựng mental model về debugger và GDB. Không có bài thực hành.

Ở các chủ đề trước, ta đã đi qua toàn bộ con đường từ source code đến executable:

```text
C source
   |
   | preprocess / compile / assemble / link
   v
ELF executable
   |
   | loader + runtime
   v
Process đang chạy
```

Build thành công chỉ chứng minh rằng compiler và linker đã tạo được chương trình hợp lệ về mặt build. Nó **không chứng minh hành vi runtime là đúng**.

Một chương trình vẫn có thể:

```text
- tính sai kết quả
- đi vào nhánh logic không mong muốn
- đọc/ghi nhầm vùng nhớ
- dereference con trỏ không hợp lệ
- crash vì signal
- treo trong một vòng lặp
- truyền sai dữ liệu qua nhiều hàm
```

Khi đó, câu hỏi không còn là:

```text
Compiler đã build được chưa?
```

mà là:

```text
Chương trình đang thực sự làm gì tại thời điểm lỗi xảy ra?
```

Debugger cung cấp một cách quan sát chương trình khi nó đang thực thi hoặc sau khi nó đã crash.

Mental model trung tâm của chương:

```text
                    Source code
                        |
                        | compiler tạo mapping
                        v
                Debug information
                        |
                        |
                        v
GDB  <---------- ELF executable ----------> Machine code
 |                                          |
 | điều khiển / quan sát                    | CPU thực thi
 v                                          v
                Process / inferior
                        |
          +-------------+--------------+
          |             |              |
          v             v              v
       Memory        Registers      Call stack
          |             |              |
          +-------------+--------------+
                        |
                        v
             Trạng thái tại thời điểm dừng
```

> **Đọc sơ đồ:** GDB không “chạy source code”. CPU vẫn chạy machine instructions của executable. Debug information giúp GDB ánh xạ trạng thái machine-level như địa chỉ instruction, stack frame và vị trí dữ liệu trở lại tên hàm, dòng source, kiểu dữ liệu và variable mà lập trình viên hiểu được.

---

## Mục lục

- [1. Debugger giải quyết vấn đề gì?](#1-debugger-giải-quyết-vấn-đề-gì)
- [2. Mental model cốt lõi: Source ↔ Debug Information ↔ Machine State](#2-mental-model-cốt-lõi-source--debug-information--machine-state)
- [3. Symbol và debug information không phải một khái niệm](#3-symbol-và-debug-information-không-phải-một-khái-niệm)
- [4. GDB quan sát một chương trình đang chạy như thế nào?](#4-gdb-quan-sát-một-chương-trình-đang-chạy-như-thế-nào)
- [5. Breakpoint: chủ động dừng execution tại một vị trí](#5-breakpoint-chủ-động-dừng-execution-tại-một-vị-trí)
- [6. `continue`, `step`, `next` và hai mức source/instruction](#6-continue-step-next-và-hai-mức-sourceinstruction)
- [7. Stack frame: trạng thái của từng lời gọi hàm](#7-stack-frame-trạng-thái-của-từng-lời-gọi-hàm)
- [8. Backtrace và selected frame](#8-backtrace-và-selected-frame)
- [9. Variable, expression và memory](#9-variable-expression-và-memory)
- [10. Register: cầu nối trực tiếp tới trạng thái CPU](#10-register-cầu-nối-trực-tiếp-tới-trạng-thái-cpu)
- [11. Signal, `SIGSEGV` và segmentation fault](#11-signal-sigsegv-và-segmentation-fault)
- [12. Core dump và post-mortem debugging](#12-core-dump-và-post-mortem-debugging)
- [13. Optimization làm thay đổi trải nghiệm debug như thế nào?](#13-optimization-làm-thay-đổi-trải-nghiệm-debug-như-thế-nào)
- [14. Tư duy chẩn đoán lỗi bằng GDB](#14-tư-duy-chẩn-đoán-lỗi-bằng-gdb)
- [15. Liên hệ với Embedded Linux và remote debugging](#15-liên-hệ-với-embedded-linux-và-remote-debugging)
- [16. Tổng kết và mô hình tư duy](#16-tổng-kết-và-mô-hình-tư-duy)
- [17. Tài liệu tham khảo](#17-tài-liệu-tham-khảo)

---

## 1. Debugger giải quyết vấn đề gì?

Một chương trình C có thể được nhìn ở nhiều tầng:

```text
Source code
    |
    v
Machine code
    |
    v
CPU execution
    |
    v
Process state
```

Khi chỉ đọc source, ta đang suy luận chương trình **đáng lẽ** phải làm gì.

Debugger giúp quan sát chương trình **thực tế đang làm gì**.

Ví dụ, source có thể chứa:

```c
result = divide(a, b);
```

Nhưng tại runtime, điều ta cần biết có thể là:

```text
a đang bằng bao nhiêu?
b đang bằng bao nhiêu?
CPU đang ở instruction nào?
Hàm divide() được gọi từ đâu?
Con trỏ đang trỏ tới địa chỉ nào?
Tại sao chương trình dừng ở đây?
```

Debugger tạo cầu nối giữa hai thế giới:

```text
Góc nhìn lập trình viên                 Góc nhìn CPU
----------------------                  ----------------------
main.c:42                               instruction address
function foo()                           program counter
variable count                           register / memory
call foo()                               call instruction
return                                   return address
local variable                           stack/register/storage
```

### 1.1 GDB không sửa lỗi thay chương trình

GDB không tự xác định “đâu là bug” theo nghĩa logic của ứng dụng.

Nó cung cấp **evidence**:

```text
- chương trình dừng ở đâu
- đi qua call chain nào
- variable có giá trị gì
- register có giá trị gì
- vùng memory chứa gì
- signal nào làm chương trình dừng
```

Lập trình viên dùng evidence đó để suy luận nguyên nhân.

Vì vậy mental model đúng là:

```text
GDB = công cụ quan sát + điều khiển execution
```

không phải:

```text
GDB = công cụ tự động tìm và sửa bug
```

### 1.2 Debugger đặc biệt hữu ích với lỗi runtime

Có thể phân loại rất thô:

```text
Build-time problem
    |
    +--> preprocessor/compiler/assembler/linker

Runtime problem
    |
    +--> logic sai
    +--> memory sai
    +--> signal/crash
    +--> state sai
    +--> control flow sai
```

GDB tập trung chủ yếu vào nhóm thứ hai.

Điều này nối trực tiếp Chủ đề 1 với Chủ đề 6:

```text
GCC Build Flow
      |
      | tạo executable
      v
Executable chạy được
      |
      | nhưng hành vi runtime có thể sai
      v
GDB Fundamentals
```

---

## 2. Mental model cốt lõi: Source ↔ Debug Information ↔ Machine State

CPU không biết tên variable `count`, tên hàm `process_data()` hay dòng 57 của `main.c`.

CPU chỉ thực thi instruction tại các địa chỉ machine-level.

Ví dụ ở mức khái niệm:

```text
Source:

    total = add(a, b);

Compiler
    |
    v

Machine code:

    0x401180  ...
    0x401184  ...
    0x401188  call ...
```

Để GDB có thể nói:

```text
đang dừng tại main.c:27
variable a = ...
variable b = ...
```

compiler phải cung cấp metadata mô tả mối liên hệ giữa source program và machine program.

Metadata đó gọi chung là **debug information**.

### 2.1 `-g` tạo debug information

Với GCC, option phổ biến để yêu cầu sinh debug information là:

```text
-g
```

Mental model:

```text
Source code
    |
    | gcc -g
    v
Machine code + debug information
    |
    v
ELF executable / object file
```

Debug information có thể mô tả những thông tin như:

```text
- source file nào
- line number nào tương ứng code address nào
- tên và kiểu của variable
- tên function
- phạm vi lexical của variable
- mô tả cần thiết để debugger tìm một giá trị
- thông tin hỗ trợ unwind stack
```

Trên phần lớn hệ Linux hiện đại, format debug information quan trọng là **DWARF**.

Ở mức chủ đề này chỉ cần hiểu:

```text
DWARF = format metadata phục vụ source-level debugging
```

Không cần đi sâu vào DIE, abbreviation table, location list hay DWARF expression.

### 2.2 Debug information không phải code được CPU thực thi

Một hiểu nhầm phổ biến là nghĩ `-g` chèn “lệnh debug” vào logic chương trình.

Mental model phù hợp hơn:

```text
ELF
 |
 +--> code / data phục vụ execution
 |
 +--> metadata phục vụ debugger
```

CPU chủ yếu thực thi machine code như bình thường.

Debugger đọc metadata để **diễn giải** trạng thái machine-level theo source-level.

### 2.3 Source line không phải đơn vị execution thật của CPU

Source có thể là:

```c
x = foo(a) + bar(b);
```

Một dòng C có thể trở thành nhiều machine instructions.

Ngược lại, compiler optimization có thể:

```text
- loại bỏ một phép tính
- inline function
- gộp nhiều source expression
- di chuyển instruction
```

Do đó mapping không phải lúc nào cũng là:

```text
1 source line = 1 machine instruction
```

Mà gần hơn với:

```text
Source constructs
      |
      | compiler-generated mapping
      v
Ranges / locations trong machine code
```

Điều này giải thích vì sao `step` theo source line và `stepi` theo machine instruction là hai khái niệm khác nhau.

---

## 3. Symbol và debug information không phải một khái niệm

Ở Chủ đề 1, ta đã học symbol trong object file và executable.

Ví dụ:

```text
main
calculate
global_counter
printf
```

Symbol giúp linker, loader và các tool khác ánh xạ **tên** với entity hoặc địa chỉ liên quan.

Debug information phong phú hơn nhiều.

### 3.1 Symbol table trả lời một loại câu hỏi

Một symbol table có thể giúp trả lời:

```text
Tên function này nằm ở địa chỉ nào?
Tên global symbol này là gì?
Symbol này defined hay undefined?
```

Ví dụ mental model:

```text
symbol name
   |
   v
address / section / binding / type
```

### 3.2 Debug information trả lời source-level question

Debug information có thể giúp trả lời:

```text
Address này tương ứng source line nào?
Local variable x nằm ở đâu tại thời điểm này?
x có kiểu dữ liệu gì?
Scope hiện tại là scope nào?
Function này được inline từ đâu?
```

Mental model:

```text
machine state
    |
    | debug metadata
    v
source-level meaning
```

Vì vậy:

```text
Symbol table != Debug information
```

### 3.3 Binary “có symbol” chưa chắc debug source-level đầy đủ

Một executable có thể còn một số symbol nhưng không còn debug information chi tiết.

Ngược lại, debug build thường chứa nhiều metadata hơn để GDB hiển thị source, type và local variable.

Có thể hình dung:

```text
ELF executable
 |
 +--> dynamic symbols cần cho dynamic linking
 |
 +--> symbol table phục vụ link/tooling nếu còn
 |
 +--> debug sections nếu được build/giữ lại
```

### 3.4 `strip` làm giảm thông tin phục vụ debug

Trong production hoặc Embedded Linux, binary thường được `strip` để giảm kích thước.

Khái niệm:

```text
Unstripped ELF
   |
   | strip
   v
Smaller ELF
```

Một phần symbol/debug metadata không cần cho execution có thể bị loại khỏi binary phân phối.

Nhưng điều đó không có nghĩa mọi thông tin symbol đều biến mất. Dynamic linking vẫn có thể cần dynamic symbol table.

Điểm cần nhớ:

```text
Strip để giảm binary size
        !=
Xóa mọi thứ liên quan tới symbol trong ELF
```

Trong workflow Embedded Linux chuyên nghiệp, thường có thể tồn tại hai artifact logic:

```text
Binary chạy trên target       Debug artifact giữ trên host
        |                              |
        | stripped                     | full debug info
        v                              v
   nhỏ hơn để deploy             dùng khi debug
```

Cách tổ chức chính xác tùy build system và distribution.

---

## 4. GDB quan sát một chương trình đang chạy như thế nào?

Trong thuật ngữ GDB, chương trình/process đang được debugger điều khiển thường được gọi là **inferior**.

Mental model đơn giản:

```text
GDB process
    |
    | debug control
    v
Inferior process
    |
    v
CPU + virtual memory + registers + threads
```

### 4.1 GDB và chương trình được debug là hai thực thể khác nhau

Ví dụ về mặt process:

```text
Userspace

+------------------+        +----------------------+
|       GDB        |        |   Program under      |
| debugger process | <----> |   debug / inferior   |
+------------------+        +----------------------+
           |                         |
           +-----------+-------------+
                       |
                       v
                  Linux Kernel
```

Trên Linux native, debugger sử dụng các cơ chế Kernel phù hợp, điển hình như `ptrace()` cùng các facility liên quan, để theo dõi và điều khiển process được debug.

Ở mức chương này không cần học `ptrace()` API. Điều cần nhớ là:

```text
GDB không phải một phần bên trong chương trình C.

GDB là một process/tool riêng có khả năng quan sát và điều khiển process khác
thông qua cơ chế debugging mà hệ điều hành cung cấp.
```

### 4.2 Running state và stopped state

Một mental model rất quan trọng của interactive debugging:

```text
              run / continue
GDB  ------------------------------>
                  Inferior RUNNING
                         |
                         | breakpoint
                         | signal
                         | step completes
                         v
                  Inferior STOPPED
GDB  <------------------------------
                quyền điều khiển quay lại
```

Khi inferior đang **running**, CPU đang thực thi code.

Khi inferior **stopped**, GDB có cơ hội quan sát trạng thái ổn định tại điểm dừng:

```text
- program counter
- registers
- stack frames
- variables
- memory
- reason for stop
```

### 4.3 Có nhiều lý do làm chương trình dừng

Không nên mặc định:

```text
Stopped == crash
```

Chương trình có thể dừng vì:

```text
Breakpoint hit
Step hoàn thành
Signal được nhận
Watchpoint trigger
User interrupt
Program exited
...
```

Vì vậy câu hỏi đầu tiên khi GDB lấy lại control thường là:

```text
Why did the inferior stop?
```

sau đó mới đến:

```text
Where did it stop?
What is the current state?
```

### 4.4 Thread là một lớp cần nhớ nhưng chưa đào sâu

Một process có thể có nhiều thread.

Mỗi thread có execution context riêng:

```text
Process
 |
 +--> Thread A --> registers + call stack
 |
 +--> Thread B --> registers + call stack
 |
 +--> Thread C --> registers + call stack
```

GDB có khái niệm selected thread và có thể inspect từng thread.

Tuy nhiên debugging multithreaded ở mức sâu không thuộc phạm vi chương này. Ở đây chỉ cần tránh mental model sai rằng một process luôn chỉ có duy nhất một call stack.

---

## 5. Breakpoint: chủ động dừng execution tại một vị trí

Breakpoint là một trong những cơ chế cốt lõi nhất của debugger.

Ý tưởng:

```text
Program chạy
    |
    v
... instruction ...
    |
    v
Breakpoint location
    |
    X  STOP
    |
    v
GDB inspect state
```

Ta chủ động yêu cầu:

```text
“Khi execution tới vị trí này, hãy dừng lại để tôi quan sát.”
```

### 5.1 Breakpoint có thể được mô tả ở nhiều mức

GDB có thể cho phép người dùng chỉ định breakpoint theo những dạng như:

```text
function name
source line
source file + line
machine address
```

Ví dụ mental model:

```text
break main
      |
      | GDB resolve symbol/debug info
      v
machine code location(s)
      |
      v
breakpoint được đặt ở target
```

Điểm quan trọng: CPU cuối cùng vẫn dừng tại một **machine-code location**. Tên hàm hoặc line number chỉ là cách source-level để GDB tìm ra location đó.

### 5.2 Software breakpoint ở mức khái niệm

Trên nhiều architecture/target, một software breakpoint có thể được hiện thực theo ý tưởng:

```text
Original instruction
       |
       | debugger tạm thay đổi
       v
Trap/break instruction
       |
       | CPU execute
       v
Debug trap
       |
       v
Control về debugger
```

Sau đó debugger quản lý việc khôi phục/tiếp tục instruction thích hợp.

Chi tiết implementation khác nhau theo architecture, OS và remote target, nên không nên coi mô hình trên là quy tắc cứng cho mọi hệ thống.

### 5.3 Hardware breakpoint khác software breakpoint

Một số CPU cung cấp hardware debug resources.

Khái quát:

```text
Software breakpoint
    -> thường liên quan tới việc chèn trap vào code

Hardware breakpoint
    -> CPU/debug hardware theo dõi địa chỉ execution
```

Trong Embedded Linux, sự khác biệt này có thể quan trọng khi code nằm trong vùng memory không tiện sửa trực tiếp, hoặc khi remote debug stub có giới hạn breakpoint resource.

Ở mức fundamentals chỉ cần nhận biết hai loại tồn tại; cách cấu hình JTAG/hardware breakpoint sâu hơn để dành cho chủ đề debugging nâng cao.

### 5.4 Conditional breakpoint

Breakpoint không nhất thiết phải dừng ở mọi lần đi qua.

Có thể tồn tại điều kiện logic:

```text
Dừng tại function X
chỉ khi count == 100
```

Mental model:

```text
Location reached
      |
      v
Condition true?
   /      \
 yes      no
  |        |
 stop    continue
```

Đây là cách giảm noise khi một location được thực thi rất nhiều lần.

### 5.5 Watchpoint liên quan nhưng không giống breakpoint thông thường

Breakpoint thường trả lời:

```text
“Khi execution đến đây thì dừng.”
```

Watchpoint trả lời một câu hỏi khác:

```text
“Khi giá trị/expression này thay đổi thì dừng.”
```

Ví dụ khái niệm:

```text
counter = 10
    |
    | chương trình chạy
    v
counter = 11
    |
    X watchpoint trigger
```

Hardware watchpoint phụ thuộc khả năng debug của CPU/target và thường có giới hạn số lượng.

Chương này không đi sâu watchpoint, nhưng cần phân biệt nó với breakpoint theo vị trí code.

---

## 6. `continue`, `step`, `next` và hai mức source/instruction

Sau khi chương trình dừng, debugger thường có hai loại hành động:

```text
1. Inspect state
2. Resume execution
```

Các lệnh `continue`, `step`, `next` đều resume execution, nhưng mục tiêu dừng tiếp theo khác nhau.

### 6.1 `continue`: chạy tiếp tới sự kiện dừng tiếp theo

Mental model:

```text
STOPPED
   |
   | continue
   v
RUNNING
   |
   | breakpoint / signal / exit / ...
   v
STOPPED hoặc TERMINATED
```

`continue` không có nghĩa là “chạy đúng một dòng nữa”. Nó cho chương trình tiếp tục cho tới khi một sự kiện thích hợp làm execution dừng lại.

### 6.2 `step`: đi sang source line tiếp theo và có thể đi vào function call

Giả sử:

```c
result = calculate(x);
next_statement();
```

Ở source-level, `step` có xu hướng đi **vào** function có debug line information:

```text
current line
    |
    | step
    v
calculate()
    |
    v
source line bên trong function
```

Đây là ý nghĩa cốt lõi cần nhớ, không phải một cam kết rằng CPU chỉ execute đúng một instruction.

### 6.3 `next`: đi sang source line tiếp theo nhưng không dừng bên trong function call hiện tại

Với cùng đoạn code:

```c
result = calculate(x);
next_statement();
```

`next` có mental model:

```text
current line
    |
    | calculate() vẫn thực sự chạy
    | nhưng debugger không dừng theo từng source line bên trong nó
    v
next source line trong current frame
```

Do đó:

```text
step -> step into
next -> step over
```

nhưng cần nhớ đây là cách nói ở mức source-level.

### 6.4 `finish`: chạy cho tới khi current function return

Một thao tác hữu ích khác về mặt mental model:

```text
Current function
    |
    | finish
    v
return to caller
    |
    v
STOP
```

Nó giúp thoát khỏi một function sau khi đã inspect đủ.

### 6.5 Source-level stepping khác instruction-level stepping

GDB còn có các thao tác theo machine instruction:

```text
stepi / si
nexti / ni
```

Khác biệt cốt lõi:

```text
step / next
    -> dựa trên source line + debug information

stepi / nexti
    -> dựa trên machine instruction
```

Sơ đồ:

```text
Source line 42
    |
    +--> instruction A
    +--> instruction B
    +--> instruction C
    +--> instruction D

step
    -> có thể chạy qua cả một nhóm instruction để đến source line khác

stepi
    -> chỉ tiến thêm một machine instruction
```

### 6.6 Vì sao `step` đôi khi có hành vi “lạ”? 

Nguồn của sự khác biệt thường nằm ở mapping source ↔ machine code:

```text
No debug line info
Optimization
Inlining
Một source line tạo nhiều instruction ranges
Macro/statement phức tạp
```

Vì vậy khi source-level stepping gây khó hiểu, mental model nên quay về tầng thấp hơn:

```text
Source line
    |
    v
Debug line mapping
    |
    v
Instruction address
```

---

## 7. Stack frame: trạng thái của từng lời gọi hàm

Ở Phase 1 ta đã gặp process stack và thread stack. Trong GDB, khái niệm quan trọng tiếp theo là **stack frame**.

Giả sử call chain:

```c
main()
  -> parse()
      -> validate()
          -> check_range()
```

Tại thời điểm đang ở `check_range()`, có thể hình dung:

```text
Call stack

+-------------------------+
| check_range()  frame #0 | <- đang thực thi
+-------------------------+
| validate()     frame #1 |
+-------------------------+
| parse()        frame #2 |
+-------------------------+
| main()         frame #3 |
+-------------------------+
```

### 7.1 Frame đại diện cho một invocation cụ thể

Không nên hiểu frame đơn giản là “một function”.

Cùng một function có thể được gọi nhiều lần, đặc biệt với recursion:

```text
factorial(3)
   |
   +--> factorial(2)
          |
          +--> factorial(1)
```

Ba invocation đó có thể tương ứng ba frame khác nhau.

Do đó:

```text
Function definition != Stack frame
```

Frame đại diện cho **một lần gọi cụ thể** trong call chain hiện tại.

### 7.2 Một frame liên quan tới những thông tin nào?

Ở mức khái niệm, frame giúp debugger diễn giải:

```text
- function invocation hiện tại
- caller/callee relationship
- return location
- arguments nếu có thể khôi phục
- local variables nếu có thông tin phù hợp
- register state gắn với frame
```

Không nên đồng nhất frame với một struct cố định nằm nguyên vẹn trên stack memory. Compiler optimization, ABI, register allocation và unwind mechanism có thể làm implementation thực tế phức tạp hơn.

Mental model an toàn hơn:

```text
Stack frame = logical execution context của một function invocation
```

### 7.3 Frame #0 là frame đang thực thi

Theo cách GDB đánh số thường dùng:

```text
#0 -> innermost/currently executing frame
#1 -> caller của #0
#2 -> caller của #1
...
```

Ví dụ:

```text
#0 check_range()
#1 validate()
#2 parse()
#3 main()
```

### 7.4 Frame pointer không đồng nghĩa stack frame

Một architecture/compiler có thể dùng một register làm frame pointer trong một số build, nhưng compiler cũng có thể omit frame pointer khi tối ưu.

Vì vậy:

```text
Stack frame        = khái niệm execution/unwind
Frame-pointer reg  = một cơ chế có thể hỗ trợ quản lý frame
```

Hai khái niệm có liên quan nhưng không đồng nhất.

---

## 8. Backtrace và selected frame

Khi một chương trình dừng vì bug hoặc breakpoint, một câu hỏi quan trọng là:

```text
“Làm thế nào execution đi tới đây?”
```

Backtrace trả lời bằng cách hiển thị call chain qua các frame.

### 8.1 `backtrace` là bản tóm tắt call chain

Mental model:

```text
main()
  |
  v
parse_config()
  |
  v
read_value()
  |
  v
convert()
  |
  v
CRASH / STOP
```

Backtrace có thể hiển thị theo hướng:

```text
#0 convert()
#1 read_value()
#2 parse_config()
#3 main()
```

Command thường được biết tới là:

```text
backtrace
bt
```

Ở mức lý thuyết, điều quan trọng không phải nhớ alias mà là hiểu:

```text
Backtrace = ảnh chụp call chain tại thời điểm dừng
```

### 8.2 Backtrace khác execution history

Một hiểu nhầm phổ biến:

```text
Backtrace == toàn bộ lịch sử chương trình đã chạy qua
```

Điều này sai.

Backtrace chỉ mô tả call chain **đang còn active** tại thời điểm dừng.

Ví dụ:

```text
foo() được gọi rồi return từ lâu
```

thì call của `foo()` đó không còn nằm trong current call stack.

Do đó:

```text
Backtrace != execution log
```

### 8.3 Selected frame quyết định context của nhiều lệnh inspect

GDB có một **selected frame**.

Nếu đang chọn frame `#0`:

```text
print local_var
```

sẽ được hiểu trong context của frame `#0`.

Nếu chuyển sang frame `#2`, cùng tên variable có thể mang nghĩa khác hoặc không tồn tại trong scope đó.

Mental model:

```text
Backtrace
   |
   +--> frame #0  <- selected
   +--> frame #1
   +--> frame #2

Commands xem local/argument
        |
        v
được diễn giải theo selected frame
```

### 8.4 Backtrace có thể thiếu hoặc kém chính xác trong một số build

Khả năng unwind call stack chịu ảnh hưởng bởi:

```text
- unwind information
- ABI
- compiler optimization
- frame-pointer policy
- code corruption
- stack corruption
- hand-written assembly
```

Vì vậy nếu stack đã bị ghi hỏng, backtrace cũng có thể bị ảnh hưởng.

Điều này rất quan trọng trong debugging memory corruption:

```text
Backtrace kỳ lạ
    |
    +--> có thể do debug info/unwind limitation
    |
    +--> cũng có thể do chính stack đã bị corrupt
```

Không nên mặc định backtrace luôn là sự thật tuyệt đối nếu memory state đã hỏng.

---

## 9. Variable, expression và memory

Một khi chương trình đã dừng ở vị trí có ý nghĩa, câu hỏi tiếp theo thường là:

```text
Dữ liệu tại đây đang là gì?
```

GDB có thể làm việc ở nhiều mức abstraction.

```text
Source variable
      |
      v
C expression
      |
      v
Address / raw memory
```

### 9.1 Variable là source-level abstraction

Ví dụ source:

```c
int count = 42;
```

Khi có debug information phù hợp, debugger có thể cho phép ta hỏi giá trị của `count` theo tên.

Nhưng tại machine-level, `count` có thể đang:

```text
- nằm trên stack
- nằm trong register
- nằm trong global/static storage
- bị tối ưu bỏ
- được compiler giữ dưới dạng một giá trị suy ra
```

Do đó:

```text
Variable name
    |
    | debug info + current frame + current PC
    v
physical/logical location của value
```

### 9.2 Local variable phụ thuộc scope và frame

Hai function có thể đều có local variable tên `count`:

```c
void foo(void) {
    int count;
}

void bar(void) {
    int count;
}
```

Tên giống nhau không có nghĩa cùng object.

Debugger cần context:

```text
Selected thread
Selected frame
Current source scope
```

để resolve variable đúng.

### 9.3 Expression trong GDB giúp hỏi trạng thái theo ngôn ngữ source

GDB có thể đánh giá nhiều expression C/C++-like trong context debug.

Ví dụ khái niệm:

```text
x
x + 1
ptr
*ptr
array[index]
```

Điều này cho phép suy luận theo cách gần với source code.

Nhưng cần cẩn thận: một số expression/call có thể làm thay đổi trạng thái inferior nếu debugger thực sự thực hiện side effect. Ở mức fundamentals nên ưu tiên mental model:

```text
Inspect first, mutate only khi hiểu rõ tác động.
```

### 9.4 Memory có thể được xem trực tiếp theo địa chỉ

Khi source-level information không đủ, debugger có thể nhìn memory trực tiếp.

Mental model:

```text
Virtual address
      |
      v
bytes trong address space của inferior
```

Đây là lớp thấp hơn variable:

```text
Variable-level
    |
    v
Typed value
    |
    v
Address
    |
    v
Raw bytes
```

### 9.5 Pointer debugging cần tách ba câu hỏi

Với một con trỏ:

```c
struct node *p;
```

nên tách:

```text
1. Giá trị của p là địa chỉ nào?
2. Địa chỉ đó có hợp lệ/readable trong process không?
3. Nội dung tại địa chỉ đó có còn là object đúng kiểu và đúng lifetime không?
```

Một pointer có thể khác `NULL` nhưng vẫn không hợp lệ:

```text
Dangling pointer
Out-of-bounds pointer
Corrupted pointer
Unmapped address
```

Đây là lý do chỉ kiểm tra:

```text
p != NULL
```

không đủ để chứng minh pointer hợp lệ trong mọi trường hợp.

### 9.6 Giá trị hiện tại không luôn chỉ ra nơi bug bắt đầu

Ví dụ:

```text
T0: buffer bị ghi vượt biên
T1: một pointer bên cạnh bị corrupt
T2: chương trình tiếp tục chạy
T3: pointer được dereference
T4: SIGSEGV
```

GDB có thể dừng ở T4.

Nhưng nguyên nhân gốc có thể đã xảy ra tại T0.

Mental model rất quan trọng:

```text
Crash location != luôn luôn root-cause location
```

---

## 10. Register: cầu nối trực tiếp tới trạng thái CPU

Variable và source line là abstraction do compiler/debugger giúp ta nhìn thấy.

Register là một phần trực tiếp hơn của machine state.

Ví dụ tùy architecture có thể tồn tại:

```text
General-purpose registers
Program counter
Stack pointer
Status/flags register
Floating-point/vector registers
```

### 10.1 Register set phụ thuộc architecture

x86-64 và AArch64 không có cùng tên register.

Ví dụ ở mức rất khái quát:

```text
x86-64                    AArch64
------                    -------
rip                       pc
rsp                       sp
rax/rbx/...               x0/x1/...
```

Do đó:

```text
Register names = architecture-specific
```

GDB cung cấp abstraction và command để xem register của target hiện tại.

### 10.2 Program counter cho biết instruction đang ở đâu

GDB thường cung cấp tên chuẩn `$pc` cho program counter khi target hỗ trợ abstraction đó.

Mental model:

```text
$pc
 |
 v
địa chỉ instruction hiện tại/tiếp theo trong execution context
```

Debug information giúp map từ `$pc` về source:

```text
Program Counter
      |
      v
Machine Address
      |
      | debug line mapping
      v
Source File : Line
```

Đây chính là một trong những cầu nối quan trọng nhất giữa CPU state và source-level debugging.

### 10.3 Stack pointer cho biết vị trí stack hiện tại

`$sp` là tên chuẩn GDB thường dùng cho stack pointer abstraction.

Khái niệm:

```text
Thread
  |
  +--> register state
         |
         +--> PC
         +--> SP
         +--> general registers
```

SP thường liên quan trực tiếp tới current stack state, nhưng layout chính xác phụ thuộc ABI và compiler-generated code.

### 10.4 Register có thể chứa variable

Compiler không bắt buộc phải lưu mọi local variable trên stack.

Ví dụ:

```text
int x
  |
  | register allocation
  v
CPU register
```

Khi optimization thay đổi, `x` có thể:

```text
- nằm trong register ở một khoảng instruction
- chuyển sang stack ở khoảng khác
- không tồn tại như một storage location độc lập
```

Debug info phải mô tả đủ để debugger biết cách tìm giá trị nếu có thể.

### 10.5 Source-level debugging và assembly-level debugging bổ sung cho nhau

Mental model:

```text
Source view
    |
    | dễ hiểu logic
    v
Function / line / variable

Machine view
    |
    | cho biết execution thực tế
    v
Instruction / register / address
```

Khi source-level state khó hiểu, nhìn xuống assembly/register có thể giải thích điều compiler thực sự đã tạo.

Đây là lý do kiến thức `objdump`, ELF, ABI và architecture ở các topic trước kết nối trực tiếp với GDB.

---

## 11. Signal, `SIGSEGV` và segmentation fault

Ở Phase 1, ta đã học signal là một cơ chế thông báo bất đồng bộ của Unix/Linux process model.

GDB có thể quan sát signal được gửi tới inferior.

### 11.1 Chương trình có thể dừng trong GDB vì signal

Mental model:

```text
Inferior RUNNING
      |
      | signal phát sinh / được gửi
      v
Kernel signal handling path
      |
      v
GDB được thông báo về stop event
      |
      v
Inferior STOPPED để debugger inspect
```

Tùy cấu hình debugger và signal, GDB có thể quyết định dừng, in thông báo, pass signal cho chương trình hoặc xử lý theo policy tương ứng.

Ở mức fundamentals, điều quan trọng là:

```text
GDB thấy signal
    !=
GDB là nơi tạo ra mọi signal
```

### 11.2 `SIGSEGV` thường liên quan memory access không hợp lệ

`SIGSEGV` thường xuất hiện khi process thực hiện một memory access vi phạm quy tắc virtual memory/protection phù hợp.

Ví dụ ở mức khái niệm:

```text
Invalid / unauthorized memory access
            |
            v
        CPU fault
            |
            v
       Linux Kernel
            |
            v
          SIGSEGV
            |
            v
          Process
```

GDB có thể dừng tại instruction nơi fault được quan sát.

### 11.3 “Segmentation fault” không chỉ có một nguyên nhân

Một số dạng bug có thể dẫn tới crash kiểu này:

```text
NULL pointer dereference
Dangling pointer
Use-after-free manifestation
Out-of-bounds access
Corrupted function/data pointer
Stack corruption
Write vào read-only mapping
Access tới unmapped virtual address
```

Không nên suy luận:

```text
SIGSEGV -> chắc chắn NULL pointer
```

### 11.4 Faulting instruction và root cause có thể khác nhau

Ví dụ:

```text
buffer overflow xảy ra sớm
        |
        v
pointer bị corrupt
        |
        v
nhiều function tiếp tục chạy
        |
        v
dereference pointer sai
        |
        v
SIGSEGV
```

GDB dừng ở instruction dereference.

Nhưng root cause nằm ở buffer overflow trước đó.

Do đó khi phân tích crash, nên tách:

```text
1. Fault manifestation
   -> instruction nào fault?

2. Corrupted state
   -> register/pointer/data nào sai?

3. Origin of corruption
   -> state sai được tạo ra từ đâu?
```

### 11.5 Backtrace là điểm bắt đầu mạnh nhưng không phải kết luận cuối

Khi `SIGSEGV` xảy ra, backtrace giúp trả lời:

```text
Chương trình đi qua call chain nào để tới faulting location?
```

Sau đó có thể inspect:

```text
current frame
caller frames
function arguments
local variables
pointer values
registers
```

Mental model:

```text
SIGSEGV
   |
   v
Where? -> current PC / source line
   |
   v
How?   -> backtrace
   |
   v
What?  -> variables / memory / registers
   |
   v
Why?   -> reasoning về state propagation
```

---

## 12. Core dump và post-mortem debugging

Interactive debugging yêu cầu chương trình đang chạy dưới sự điều khiển của debugger hoặc debugger attach vào process.

Nhưng nhiều lỗi chỉ xảy ra:

```text
- trên thiết bị thật
- sau nhiều giờ
- trong môi trường production/test
- khi GDB không attach trực tiếp
```

Core dump giải quyết một phần bài toán đó.

### 12.1 Core dump là snapshot của process state

Ở mức khái niệm:

```text
Running process
     |
     | crash / explicit core generation
     v
Core dump
     |
     +--> memory snapshot phù hợp
     +--> register/process state
     +--> metadata cần cho post-mortem analysis
```

Sau đó:

```text
Executable + matching symbols/debug info + core dump
                         |
                         v
                        GDB
                         |
                         v
                Post-mortem debugging
```

### 12.2 Core dump không phải process có thể tiếp tục chạy

Một core dump là snapshot, không phải process sống.

Vì vậy:

```text
Live debugging
    -> có thể continue/step

Core debugging
    -> inspect snapshot tại thời điểm dump
```

Ta có thể xem:

```text
backtrace
registers
memory
variables nếu debug info phù hợp
```

nhưng không thể resume core file như một inferior bình thường.

### 12.3 Matching binary và debug info rất quan trọng

Nếu core dump sinh từ binary A nhưng GDB lại dùng binary B khác build, địa chỉ và symbol mapping có thể không khớp.

Mental model:

```text
Core from Build A
      |
      +--> cần executable/debug symbols tương ứng Build A
```

Trong Embedded Linux đây là lý do cần quản lý build artifact cẩn thận:

```text
Firmware release / rootfs image
       |
       +--> exact ELF binaries
       +--> exact debug symbol files
       +--> build ID/version metadata
```

Nếu chỉ giữ source code nhưng mất binary/debug artifact tương ứng, post-mortem debugging có thể khó hơn đáng kể.

### 12.4 Core dump có thể rất lớn

Process có address space lớn nên core dump có thể chiếm nhiều dung lượng.

Trên embedded target bị giới hạn storage, hệ thống thường cần policy phù hợp cho:

```text
- có tạo core hay không
- lưu ở đâu
- giới hạn kích thước
- thu thập/chuyển core ra host như thế nào
```

Đây là vấn đề deployment/diagnostics riêng, không đi sâu trong chương này.

---

## 13. Optimization làm thay đổi trải nghiệm debug như thế nào?

Một trong những nguồn gây nhầm lẫn lớn nhất khi dùng debugger là **compiler optimization**.

Source code mô tả semantics mong muốn. Compiler được phép biến đổi implementation miễn là tuân thủ các quy tắc ngôn ngữ và optimization hợp lệ.

### 13.1 Không optimization: mapping thường dễ theo dõi hơn

Ở mức đơn giản:

```text
Source statements
      |
      v
Machine instructions tương đối trực tiếp
```

Debugger thường dễ map:

```text
source line
local variable
function call
```

sang machine state hơn.

### 13.2 Optimization có thể thay đổi code shape

Compiler có thể:

```text
Constant folding
Dead-code elimination
Inlining
Register allocation mạnh hơn
Instruction scheduling
Common-subexpression elimination
Loop transformations
Tail-call optimization
...
```

Kết quả:

```text
Source program
    |
    | optimization
    v
Equivalent machine behavior
nhưng structure không còn giống source một cách trực tiếp
```

### 13.3 Variable có thể thành `<optimized out>`

Giả sử source có:

```c
int x = 10;
int y = x + 5;
```

Compiler có thể nhận ra `x` không cần storage runtime độc lập.

Conceptually:

```text
x = 10
  |
  | compile-time reasoning
  v
y = 15
```

Khi đó debugger có thể không tìm thấy một object runtime cụ thể tương ứng với `x` ở điểm đang inspect.

Điều này không có nghĩa GDB “bị lỗi”. Nó có thể phản ánh machine code thực tế không còn chứa variable như source-level object độc lập.

### 13.4 Function có thể bị inline

Source:

```c
result = add(a, b);
```

Compiler có thể inline body của `add()` vào caller.

Machine-level:

```text
Không nhất thiết tồn tại một call instruction tới add()
```

Debugger hiện đại có thể mô hình hóa inline function từ debug info, nhưng stepping/backtrace có thể khác cảm giác so với unoptimized build.

### 13.5 Source lines có thể không chạy theo thứ tự trực quan

Optimization có thể di chuyển instruction.

Vì vậy có thể thấy:

```text
GDB line display
    20
    22
    21
    23
```

hoặc một line dường như bị bỏ qua, tùy mapping.

Điểm cần nhớ:

```text
Debugger hiển thị mapping từ machine execution trở lại source.
Nó không ép optimized machine code phải giữ nguyên cấu trúc source.
```

### 13.6 `-g` và `-O` có thể dùng cùng nhau

GCC hỗ trợ tạo debug information đồng thời với optimization.

Mental model:

```text
-g  -> debug metadata
-O* -> optimization policy
```

Hai loại option giải quyết hai khía cạnh khác nhau.

Ví dụ:

```text
-g -O2
```

vẫn có thể debug, nhưng source-level experience thường khó hơn vì code đã được tối ưu.

GCC cũng có `-Og`, được thiết kế như một mức optimization thân thiện hơn cho chu kỳ edit/compile/debug so với các mức optimization mạnh hơn. Tuy nhiên, không nên biến điều này thành quy tắc rằng `-Og` luôn cho mọi quan sát dễ hơn mọi build khác; điều cần hiểu là optimization level ảnh hưởng trực tiếp tới khả năng quan sát source-level state.

### 13.7 Build dùng để reproduce bug phải đủ gần build thật

Một bug có thể chỉ xuất hiện ở optimized build vì:

```text
- timing thay đổi
- memory layout thay đổi
- undefined behavior biểu hiện khác
- inlining/reordering làm manifestation khác
```

Nếu chỉ debug một binary `-O0` hoàn toàn khác, bug có thể biến mất.

Vì vậy trong thực tế có hai nhu cầu có thể xung đột:

```text
Debuggability
    vs
Reproduce chính xác production behavior
```

Một workflow tốt cần hiểu cả hai thay vì mặc định “tắt optimization là xong”.

---

## 14. Tư duy chẩn đoán lỗi bằng GDB

GDB hiệu quả nhất khi được dùng theo một chuỗi reasoning có cấu trúc, thay vì gõ command ngẫu nhiên.

### 14.1 Bước 1 — Xác định symptom

Trước khi inspect chi tiết, cần biết vấn đề là gì:

```text
Crash?
Wrong result?
Hang?
Unexpected branch?
Memory corruption?
Signal?
```

Mỗi symptom dẫn tới chiến lược khác nhau.

### 14.2 Bước 2 — Xác định điểm quan sát có ý nghĩa

Có thể là:

```text
Crash location
Function nghi ngờ
Boundary trước/sau một state transition
Nơi variable bắt đầu sai
```

Breakpoint giúp dừng tại điểm đó.

### 14.3 Bước 3 — Hỏi “Where am I?”

Khi chương trình dừng:

```text
Current function?
Current source line?
Current instruction/address?
Stop reason?
```

Mental model:

```text
STOP
 |
 +--> Why stopped?
 +--> Where stopped?
```

### 14.4 Bước 4 — Hỏi “How did I get here?”

Dùng call stack/backtrace để hiểu:

```text
Caller chain
Function arguments
Frame context
```

Đây thường là bước đầu tiên khi crash.

### 14.5 Bước 5 — Hỏi “What state is wrong?”

Inspect:

```text
local variables
arguments
pointers
memory
registers
```

Ví dụ reasoning:

```text
SIGSEGV at *ptr
    |
    v
ptr = 0x... có hợp lệ không?
    |
    v
ptr được truyền từ caller nào?
    |
    v
frame trước có value gì?
```

### 14.6 Bước 6 — Tìm thời điểm state chuyển từ đúng sang sai

Nếu hiện tại state đã sai, ta cần đi ngược về logic:

```text
State đúng
   |
   | operation A
   v
State đúng
   |
   | operation B
   v
State sai
```

Mục tiêu là thu hẹp boundary:

```text
“Trước B đúng, sau B sai.”
```

Sau đó mới đi sâu vào B.

Breakpoint, stepping và watchpoint đều phục vụ việc thu hẹp boundary này.

### 14.7 Bước 7 — Phân biệt manifestation với root cause

Ví dụ:

```text
Crash tại free()
```

không đồng nghĩa:

```text
Bug nằm trong free()
```

Có thể object đã bị corrupt trước đó.

Tương tự:

```text
Crash trong libc
    |
    +--> có thể libc bug
    |
    +--> nhưng thường cũng cần kiểm tra argument/state do application truyền vào
```

Debugger cung cấp evidence; reasoning phải theo data/control flow.

### 14.8 Một decision tree cơ bản

```text
Program có crash không?
        |
   +----+----+
   |         |
  Có       Không
   |         |
   v         v
Signal?   Wrong behavior / hang?
   |         |
   v         v
PC + bt   breakpoint tại boundary
   |         |
   v         v
Inspect   step/next + state
state        |
   |         v
   +------> Tìm điểm state đổi sai
                |
                v
           Xác định root cause
```

### 14.9 Những câu hỏi nên hình thành thành thói quen

Khi GDB dừng, nên tự hỏi theo thứ tự:

```text
1. Chương trình dừng vì lý do gì?
2. Đang ở thread/frame/function nào?
3. Current PC/source line là gì?
4. Call chain dẫn tới đây thế nào?
5. Arguments/local variables có hợp lý không?
6. Pointer/address nào đáng nghi?
7. Memory/register state nói gì?
8. State sai bắt đầu từ frame/operation nào?
9. Optimization có làm source view gây hiểu nhầm không?
10. Binary/debug symbols có đúng build không?
```

Đây là mental model quan trọng hơn việc ghi nhớ hàng chục command rời rạc.

---

## 15. Liên hệ với Embedded Linux và remote debugging

Trong desktop Linux, debugger và chương trình thường chạy trên cùng máy:

```text
HOST
+----------------------------------+
| GDB                              |
|   |                              |
|   v                              |
| Program being debugged           |
+----------------------------------+
```

Embedded Linux thường khác:

```text
Development Host                  Target Board
x86_64 Linux                      AArch64/ARM Linux
+------------------+              +------------------+
| source           |              | application      |
| debug symbols    |              | process          |
| GDB              | <----------> | gdbserver/stub   |
+------------------+   remote     +------------------+
```

### 15.1 Vì sao GDB thường chạy trên host?

Embedded target có thể hạn chế:

```text
RAM
Storage
CPU
Package set
UI/terminal environment
```

Trong khi host có:

```text
full source tree
unstripped ELF
large debug info
cross toolchain
IDE/editor integration
```

Do đó một mô hình phổ biến là:

```text
Host làm phần debug intelligence nặng
Target chỉ chạy application + remote debug agent/stub
```

### 15.2 `gdbserver` ở mức mental model

`gdbserver` là một chương trình nhỏ chạy trên target và điều khiển inferior thay cho GDB host.

Mental model:

```text
GDB on host
    |
    | GDB Remote Serial Protocol / transport
    v
gdbserver on target
    |
    v
Target process
```

GDB host vẫn cần hiểu architecture của target và có executable/debug information tương ứng.

### 15.3 Cross-debugger phải hiểu target architecture

Nối với Chủ đề 2:

```text
Host architecture  = x86_64
Target architecture = AArch64
```

Debugger phía host không thể chỉ giả định register set và instruction set của host.

Nó cần target architecture support:

```text
Target register model
Target instruction set
Target ABI/unwind conventions
Executable/debug info
```

Vì vậy toolchain cho Embedded Linux thường có debugger phù hợp với target hoặc một GDB được build multi-architecture.

### 15.4 Sysroot cũng có ý nghĩa khi debug

Ở Topic 2, sysroot giúp compiler/linker tìm header/library của target.

Trong debugging, GDB cũng có thể cần hiểu target filesystem layout và library/symbol tương ứng.

Ví dụ application có backtrace đi qua:

```text
app
 |
 +--> libfoo.so
 |
 +--> libc.so
```

Nếu GDB trên host không có đúng shared libraries/debug symbols của target build, symbolization có thể thiếu hoặc sai.

Mental model:

```text
Target runtime files
        |
        +--> executable
        +--> shared libraries
        +--> loader/libc

Host debug environment
        |
        +--> matching ELF/debug artifacts
        +--> source tree
        +--> target/sysroot view khi cần
```

### 15.5 Stripped target binary không có nghĩa không thể debug tốt

Một pattern thường thấy:

```text
Target
  |
  +--> stripped executable

Host
  |
  +--> unstripped/debug file của đúng build
```

GDB có thể dùng debug artifact trên host để symbolicate target addresses nếu mapping/build tương ứng đúng.

Đây là cách cân bằng:

```text
Target footprint nhỏ
        +
Host debugging đầy đủ
```

### 15.6 ASLR và runtime address

Modern Linux có thể dùng ASLR/PIE/shared-library relocation, làm runtime address khác địa chỉ tưởng tượng từ static layout.

Debugger biết process mappings và relocation context để resolve location phù hợp.

Điều quan trọng ở mức foundations:

```text
Runtime address
    != luôn luôn raw link-time address nhìn thấy theo cách đơn giản
```

Đây là một lý do khác khiến debugger cần phối hợp:

```text
ELF metadata
process mappings
loader state
debug information
```

### 15.7 GDB không thay thế các công cụ chẩn đoán khác

Trong Embedded Linux, bug có thể thuộc nhiều lớp:

```text
Application logic           -> GDB rất phù hợp
System call behavior        -> strace có thể hữu ích
Library/loader              -> readelf/ldd/GDB
Performance                 -> perf/profiler
Kernel/driver               -> kernel debugging/tracing tools
Build/link issue            -> gcc/readelf/nm/objdump
```

Mental model đúng là dùng GDB như một phần của **debugging toolbox**, không phải công cụ duy nhất cho mọi loại vấn đề.

---

## 16. Tổng kết và mô hình tư duy

### 16.1 Toàn bộ mental model của GDB Fundamentals

```text
                  C Source Code
                       |
                       | compiler -g
                       v
             +--------------------+
             | Machine Code       |
             | Debug Information  |
             | Symbols            |
             +--------------------+
                       |
                       v
                  ELF Program
                       |
                       | execute
                       v
                Process / Inferior
                       |
         +-------------+-------------+
         |             |             |
         v             v             v
      Memory        Registers     Call Stack
         |             |             |
         +-------------+-------------+
                       |
                       v
                      GDB
                       |
        +--------------+---------------+
        |              |               |
        v              v               v
    Breakpoint       Stepping        Inspect
        |              |               |
        v              v               v
      STOP       source/instruction   state
        |                              |
        +------------------------------+
                       |
                       v
                 Debug reasoning
```

### 16.2 Những phân biệt cần nhớ

```text
Build success                != Runtime correctness
Debugger                     != Compiler
GDB                          != Program being debugged
Source line                  != Machine instruction
Symbol table                 != Debug information
Function                     != Stack frame
Backtrace                    != Full execution history
Current frame                != Mọi caller frame
Breakpoint                   != Watchpoint
step                         != next
step                         != stepi
Variable                     != luôn luôn stack memory
Stack frame                  != frame-pointer register
Fault location               != luôn luôn root cause
SIGSEGV                      != chỉ có NULL dereference
Live debugging               != Core-dump debugging
-g                           != tắt optimization
Stripped target binary       != không thể dùng host debug symbols
Host architecture            != Target architecture
```

### 16.3 Chuỗi reasoning nên hình thành

Khi một chương trình runtime gặp vấn đề, nên suy nghĩ:

```text
1. Symptom là gì?
        |
        v
2. Chương trình dừng vì breakpoint, signal hay lý do khác?
        |
        v
3. PC/source location ở đâu?
        |
        v
4. Backtrace cho biết call chain nào?
        |
        v
5. Selected frame có arguments/local state gì?
        |
        v
6. Pointer/memory/register nào sai?
        |
        v
7. State sai bắt đầu từ thời điểm nào?
        |
        v
8. Optimization/debug info có ảnh hưởng cách quan sát không?
        |
        v
9. Binary/debug symbols có đúng build không?
        |
        v
10. Root cause nằm ở đâu trong data/control flow?
```

Nếu người học hình thành được chuỗi reasoning này, GDB sẽ không còn là tập hợp các lệnh như `break`, `next`, `print`, `bt`, mà trở thành một công cụ có mô hình rõ ràng.

### 16.4 Mối liên hệ của toàn bộ Phase 2

Sáu topic của Phase 2 ghép thành một pipeline hoàn chỉnh:

```text
1. GCC Build Flow
   |
   | source -> object -> ELF
   v
2. Native & Cross Toolchain
   |
   | build cho đúng target/ABI
   v
3. Static & Dynamic Library
   |
   | tổ chức và resolve reusable code
   v
4. Makefile
   |
   | dependency graph + incremental build
   v
5. CMake Fundamentals
   |
   | mô tả project + generate build system
   v
6. GDB Fundamentals
   |
   | quan sát runtime state và chẩn đoán lỗi
   v
Embedded Linux development workflow
```

Có thể nhìn Phase 2 theo hai nửa:

```text
BUILD SIDE
---------
GCC
Toolchain
Library
Make
CMake

       |
       | tạo chương trình
       v

RUNTIME DEBUG SIDE
------------------
GDB
```

Nhưng GDB vẫn phụ thuộc trực tiếp vào kiến thức của nửa build:

```text
ELF
symbols
debug info
architecture
ABI
shared libraries
toolchain
optimization
```

Vì vậy Chủ đề 6 không tách rời các topic trước; nó là nơi nhiều khái niệm build-time bắt đầu được dùng để hiểu runtime behavior.

---

## 17. Tài liệu tham khảo

### 17.1 GDB — tài liệu chính thức

- **Debugging with GDB — GNU GDB Manual**  
  https://sourceware.org/gdb/current/onlinedocs/gdb/

- **Compiling for Debugging**  
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Compilation.html

- **Stopping and Continuing**  
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Stopping.html

- **Breakpoints, Watchpoints and Catchpoints**  
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Breakpoints.html

- **Continuing and Stepping**  
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Continuing-and-Stepping.html

- **Examining the Stack**  
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Stack.html

- **Examining Data**  
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Data.html

- **Registers**  
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Registers.html

- **Signals**  
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Signals.html

- **Debugging Optimized Code**  
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Optimized-Code.html

- **Remote Debugging**  
  https://sourceware.org/gdb/current/onlinedocs/gdb.html/Remote-Debugging.html

### 17.2 GCC — debug information và optimization

- **GCC — Options for Debugging Your Program**  
  https://gcc.gnu.org/onlinedocs/gcc/Debugging-Options.html

- **GCC — Options That Control Optimization**  
  https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html

### 17.3 DWARF

- **DWARF Debugging Information Format**  
  https://dwarfstd.org/

Ở mức chương này, chỉ cần nhớ DWARF là format phổ biến để compiler mô tả mapping giữa source-level program và machine-level program cho debugger. Không cần đọc toàn bộ specification để sử dụng GDB Fundamentals.

### 17.4 Linux manual pages liên quan

- **`ptrace(2)` — process trace**  
  https://man7.org/linux/man-pages/man2/ptrace.2.html

- **`signal(7)` — overview of signals**  
  https://man7.org/linux/man-pages/man7/signal.7.html

- **`core(5)` — core dump files**  
  https://man7.org/linux/man-pages/man5/core.5.html

### 17.5 Mối liên hệ với các chủ đề trước

Để hiểu GDB chắc chắn hơn, nên nối lại các mental model đã xây trong Phase 2:

```text
README-topic-01
    -> ELF, section, symbol, machine code

README-topic-02
    -> architecture, ABI, cross toolchain, sysroot

README-topic-03
    -> shared library, dynamic loader, runtime dependency

README-topic-04
    -> debug/optimization flags đi qua build variables

README-topic-05
    -> target compile options và build configuration

README-topic-06
    -> dùng các artifact và metadata đó để hiểu runtime state
```

GDB là điểm giao giữa **source code**, **compiler output**, **OS process model** và **CPU machine state**. Khi bốn lớp này được nối đúng mental model, việc debug trở thành một quá trình reasoning có cấu trúc thay vì thử lệnh một cách ngẫu nhiên.

> **Điều hướng:** [← Chủ đề 5 — CMake Fundamentals](README-topic-05.md)
