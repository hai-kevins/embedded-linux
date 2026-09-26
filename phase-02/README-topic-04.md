# Chủ đề 4 — Makefile

> **Mục tiêu:** Hiểu bản chất của GNU Make như một công cụ mô tả và thực thi **đồ thị phụ thuộc** (`dependency graph`) của quá trình build; phân biệt rõ `target`, `prerequisite`, `recipe`, `goal`; hiểu cơ chế Make quyết định một target có cần được build lại hay không; nắm được variable, automatic variable, pattern rule, implicit rule, phony target, dependency của header, parallel build và cách tổ chức các biến build như `CC`, `CPPFLAGS`, `CFLAGS`, `LDFLAGS`, `LDLIBS`. Sau chương này, người học phải có mental model đủ chắc để đọc một Makefile C/C++ điển hình và hiểu vì sao Make chỉ rebuild đúng phần cần thiết.
>
> **Quy ước ngôn ngữ:** Phần giải thích dùng Tiếng Việt. Các thuật ngữ cần tra cứu đúng theo tài liệu GNU Make/GCC như `target`, `prerequisite`, `recipe`, `goal`, `dependency graph`, `incremental build`, `phony target`, `automatic variable`, `pattern rule`, `implicit rule`, `order-only prerequisite` được giữ nguyên bằng tiếng Anh và giải thích tại vị trí phù hợp.
>
> **Phạm vi:** GNU Make trên Linux, cấu trúc rule, dependency graph, timestamp-based rebuild, recipe và shell, variable, các biến build chuẩn, automatic variable, pattern/implicit rule, phony target, dependency của header, generated files, order-only prerequisite, parallel build, lỗi Makefile thường gặp và liên hệ với cross-compilation trong Embedded Linux. Các kỹ thuật metaprogramming phức tạp của GNU Make, `eval`, `call`, `foreach`, secondary expansion, static pattern rule nâng cao, recursive Make quy mô lớn và internals của Make không thuộc phạm vi chương này.
>
> Chương này là **lý thuyết nền tảng**, được thiết kế để xây dựng mental model về build automation bằng Make. Không có bài thực hành.

Ở ba chủ đề trước, ta đã có mô hình:

```text
Source files
    |
    | compiler / assembler
    v
Object files
    |
    | linker + libraries
    v
ELF output
```

Khi project chỉ có một file C, việc gõ một command build trực tiếp còn tương đối đơn giản. Nhưng khi project có nhiều source file, header, library và nhiều output khác nhau, câu hỏi quan trọng không còn là chỉ **"dùng command nào để compile?"** mà là:

```text
File nào phụ thuộc vào file nào?

Khi một source/header thay đổi,
artifact nào thực sự cần được tạo lại?

Các bước build phải xảy ra theo quan hệ nào?
```

Đây là bài toán Make giải quyết.

Mental model trung tâm của chương:

```text
                     Dependency Graph

                         app
                      /       \
                  main.o      foo.o
                   /            \
               main.c          foo.c
                  |              |
              common.h       common.h

                         |
                         | Make xét graph
                         | + trạng thái file
                         v

                  Chỉ chạy các recipe
                  của target cần cập nhật
```

> **Đọc sơ đồ:** Make không đơn giản đọc Makefile từ trên xuống rồi chạy tất cả command. Nó xây dựng quan hệ giữa các target và prerequisite, bắt đầu từ một `goal`, sau đó xác định node nào trong dependency graph cần được cập nhật. Đây là nền tảng để hiểu `incremental build`.

---

## Mục lục

- [1. Make giải quyết vấn đề gì?](#1-make-giải-quyết-vấn-đề-gì)
- [2. Mental model cốt lõi: target, prerequisite, recipe và goal](#2-mental-model-cốt-lõi-target-prerequisite-recipe-và-goal)
- [3. Make quyết định rebuild một target như thế nào?](#3-make-quyết-định-rebuild-một-target-như-thế-nào)
- [4. Dependency graph và incremental build](#4-dependency-graph-và-incremental-build)
- [5. Recipe và mối quan hệ giữa Make với Shell](#5-recipe-và-mối-quan-hệ-giữa-make-với-shell)
- [6. Variable trong Make và thời điểm expansion](#6-variable-trong-make-và-thời-điểm-expansion)
- [7. Các biến build thường dùng: `CC`, `CPPFLAGS`, `CFLAGS`, `LDFLAGS`, `LDLIBS`](#7-các-biến-build-thường-dùng-cc-cppflags-cflags-ldflags-ldlibs)
- [8. Automatic variable](#8-automatic-variable)
- [9. Pattern rule và implicit rule](#9-pattern-rule-và-implicit-rule)
- [10. Phony target, default goal và target tiện ích](#10-phony-target-default-goal-và-target-tiện-ích)
- [11. Header dependency và file `.d`](#11-header-dependency-và-file-d)
- [12. Generated files và order-only prerequisite](#12-generated-files-và-order-only-prerequisite)
- [13. Parallel build và tính đúng đắn của dependency graph](#13-parallel-build-và-tính-đúng-đắn-của-dependency-graph)
- [14. Tư duy chẩn đoán lỗi Makefile](#14-tư-duy-chẩn-đoán-lỗi-makefile)
- [15. Liên hệ với Embedded Linux và cross-compilation](#15-liên-hệ-với-embedded-linux-và-cross-compilation)
- [16. Tổng kết và mô hình tư duy](#16-tổng-kết-và-mô-hình-tư-duy)
- [17. Tài liệu tham khảo](#17-tài-liệu-tham-khảo)

---

## 1. Make giải quyết vấn đề gì?

Một project C thực tế có thể có cấu trúc logic như sau:

```text
main.c
foo.c
bar.c
common.h
foo.h
bar.h
```

Sau build:

```text
main.c  ---> main.o ---\
foo.c   ---> foo.o  ----+---> app
bar.c   ---> bar.o  ---/
```

Nếu mọi lần build đều compile lại toàn bộ source rồi link lại, kết quả có thể vẫn đúng nhưng chi phí build tăng theo kích thước project.

Ví dụ chỉ sửa `foo.c`:

```text
main.c  không đổi
foo.c   thay đổi
bar.c   không đổi

          |
          v

main.o  có thể giữ nguyên
foo.o   phải tạo lại
bar.o   có thể giữ nguyên

app     phải link lại
```

Một build system cần biết **quan hệ phụ thuộc** để suy ra điều đó.

### 1.1 Make không phải compiler

Make không tự compile C.

Make cũng không tự link ELF.

Mô hình đúng là:

```text
Make
 |
 | quyết định việc gì cần làm
 v
Recipe
 |
 | gọi công cụ thực hiện công việc
 v
GCC / Clang / as / ar / linker / cp / mkdir / ...
```

Ví dụ một rule có thể yêu cầu compiler tạo `main.o`:

```make
main.o: main.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c main.c -o main.o
```

Ở đây:

- Make hiểu quan hệ `main.o` phụ thuộc `main.c`;
- shell thực thi command trong recipe;
- compiler mới là thành phần thực sự biến `main.c` thành `main.o`.

Do đó:

```text
Make       != Compiler
Make       != Linker
Make       != Shell
Make       = Build dependency engine + rule executor
```

### 1.2 Make không chỉ là nơi lưu command build

Một Makefile có thể trông giống một tập hợp command shell, nhưng nếu chỉ nhìn nó như một "script chứa lệnh build" thì sẽ bỏ lỡ bản chất quan trọng nhất.

Shell script thường mô tả **trình tự thủ tục**:

```text
Bước 1
  |
Bước 2
  |
Bước 3
```

Makefile chủ yếu mô tả **quan hệ phụ thuộc**:

```text
              app
            /     \
        main.o    foo.o
          |         |
        main.c    foo.c
```

Sau đó Make tự suy luận thứ tự cần thiết dựa trên graph.

> **Điểm cần nhớ:** Trong Make, điều quan trọng nhất không phải "command nằm ở dòng thứ mấy", mà là **target nào phụ thuộc vào prerequisite nào**.

---

## 2. Mental model cốt lõi: target, prerequisite, recipe và goal

Một rule cơ bản có dạng:

```make
target: prerequisite1 prerequisite2
	recipe
```

Ba thành phần cần phân biệt:

```text
target       : prerequisite(s)
    |
    +-------- quan hệ dependency

recipe
    |
    +-------- cách cập nhật target khi cần
```

Ví dụ:

```make
app: main.o foo.o
	$(CC) main.o foo.o -o app
```

Có thể đọc theo nghĩa:

> `app` phụ thuộc vào `main.o` và `foo.o`. Nếu `app` cần được cập nhật, recipe bên dưới mô tả cách tạo/cập nhật `app`.

### 2.1 Target là gì?

Trong trường hợp phổ biến, `target` là tên file mà rule tạo ra:

```make
main.o: main.c
	...
```

Ở đây target là:

```text
main.o
```

Nhưng target **không bắt buộc** phải là một file thực. Phần `phony target` ở phía sau sẽ giải thích trường hợp như `clean`, `all`.

### 2.2 Prerequisite là gì?

`Prerequisite` là đối tượng mà target phụ thuộc vào.

Ví dụ:

```make
main.o: main.c common.h
```

Có nghĩa:

```text
main.o
  |
  +--> phụ thuộc main.c
  |
  +--> phụ thuộc common.h
```

Nếu một prerequisite cần được build, Make sẽ xử lý prerequisite đó trước target phụ thuộc vào nó.

### 2.3 Recipe là gì?

`Recipe` mô tả command được dùng để cập nhật target.

Ví dụ:

```make
main.o: main.c
	$(CC) -c main.c -o main.o
```

Recipe không phải dependency.

Hai lớp này cần tách rõ:

```text
Dependency:
main.o phụ thuộc main.c

Mechanism:
dùng compiler để tạo main.o từ main.c
```

Một dependency graph đúng quan trọng hơn việc recipe trông "có vẻ chạy đúng" trong một trường hợp cụ thể.

### 2.4 Goal là gì?

`Goal` là target mà người dùng yêu cầu Make cập nhật.

Ví dụ khái niệm:

```text
make app
     ^
     |
    goal
```

Make bắt đầu từ goal rồi đi ngược theo dependency graph:

```text
app
 |
 +--> main.o
 |      |
 |      +--> main.c
 |
 +--> foo.o
        |
        +--> foo.c
```

Nếu không chỉ rõ goal, GNU Make thường chọn **default goal**, thông thường là target phù hợp đầu tiên trong Makefile theo quy tắc của Make. Có thể chỉ định rõ default goal bằng `.DEFAULT_GOAL` nếu project cần.

### 2.5 Makefile mô tả graph, không nhất thiết mô tả thứ tự dòng

Giả sử Makefile có các rule:

```make
app: main.o foo.o
	...

foo.o: foo.c
	...

main.o: main.c
	...
```

Dù rule của `app` xuất hiện trước rule của `main.o`, Make vẫn biết rằng `main.o` phải được cập nhật trước `app` nếu cần.

Lý do là:

```text
Make đọc quan hệ
     |
     v
app phụ thuộc main.o
     |
     v
main.o phải sẵn sàng trước app
```

Không phải vì `main.o` nằm trước hay sau trong file.

---

## 3. Make quyết định rebuild một target như thế nào?

Một trong những khả năng cốt lõi của Make là tránh làm lại công việc không cần thiết.

Với target dạng file thông thường, Make chủ yếu dựa vào:

```text
Sự tồn tại của target
+
thời gian sửa đổi của target và prerequisite
```

Đây là cơ chế timestamp-based dependency checking.

### 3.1 Target chưa tồn tại

Ví dụ:

```make
main.o: main.c
	...
```

Nếu `main.o` chưa tồn tại:

```text
main.c   tồn tại
main.o   không tồn tại
```

thì Make coi `main.o` cần được tạo.

Mô hình:

```text
Target missing
     |
     v
Target is out-of-date
     |
     v
Run recipe
```

### 3.2 Prerequisite mới hơn target

Giả sử:

```text
main.c   modified 10:05
main.o   modified 10:00
```

`main.c` mới hơn `main.o`.

Điều này được diễn giải:

```text
Source đã thay đổi sau lần tạo object gần nhất
        |
        v
main.o có thể không còn phản ánh main.c hiện tại
        |
        v
rebuild main.o
```

### 3.3 Target mới hơn tất cả prerequisite

Giả sử:

```text
main.c   10:00
main.o   10:05
```

Nếu không có prerequisite nào mới hơn target, Make thường coi target là `up-to-date`.

```text
All normal prerequisites older than target
               |
               v
      target is up-to-date
               |
               v
         skip recipe
```

### 3.4 Make không so sánh nội dung file theo mặc định

Một hiểu lầm phổ biến là Make "biết source code có thay đổi hay không".

Thông thường Make không phân tích nội dung C để quyết định rebuild. Nó dựa trên metadata của filesystem và dependency graph.

Do đó:

```text
Make biết:
- file có tồn tại không
- dependency graph
- timestamp

Make không tự biết:
- semantic của code C
- header nào thực sự được include nếu dependency không được cung cấp
- thay đổi source có ảnh hưởng logic gì
```

### 3.5 Timestamp sai có thể làm suy luận build sai

Vì Make dựa nhiều vào modification time, clock/filesystem timestamp bất thường có thể dẫn đến tình huống khó hiểu.

Ví dụ khái quát:

```text
source timestamp nằm "trong tương lai"
            |
            v
target liên tục bị coi là cũ
```

hoặc artifact được restore với timestamp không phản ánh quan hệ build thực tế.

Đây là lý do Make thường cảnh báo về `clock skew` trong một số tình huống.

> **Điểm cần nhớ:** Make không hỏi "file có khác nội dung không?". Với file target thông thường, nó chủ yếu hỏi **"target có tồn tại không và prerequisite có mới hơn target không?"**.

---

## 4. Dependency graph và incremental build

`Incremental build` là khả năng chỉ rebuild phần bị ảnh hưởng thay vì build lại toàn project.

Ví dụ graph:

```text
                         app
                       /     \
                    main.o   foo.o
                    /   \      / \
              main.c  common.h foo.c foo.h
                         ^
                         |
                    dùng chung
```

Giả sử `foo.c` thay đổi:

```text
foo.c
 |
 v
foo.o cần rebuild
 |
 v
app cần relink
```

Trong khi:

```text
main.c không đổi
common.h không đổi
      |
      v
main.o có thể giữ nguyên
```

### 4.1 Dependency lan truyền theo graph

Nếu một node được cập nhật, các target phía trên phụ thuộc node đó có thể trở thành out-of-date.

```text
foo.c
  |
  v
foo.o
  |
  v
app
```

Đây là lý do thay một leaf node có thể dẫn đến nhiều bước build ở phía trên.

### 4.2 Header là dependency thực sự của object file

Giả sử:

```c
/* main.c */
#include "common.h"
```

Về build dependency:

```text
main.o
  |
  +--> main.c
  |
  +--> common.h
```

Nếu Makefile chỉ viết:

```make
main.o: main.c
```

thì graph đang **thiếu dependency**.

Hậu quả:

```text
common.h thay đổi
      |
      v
Make không thấy edge common.h -> main.o
      |
      v
main.o có thể không rebuild
      |
      v
stale object file
```

Đây là một trong những nguồn gây "build dường như thành công nhưng dùng artifact cũ" rất điển hình.

### 4.3 Over-dependency cũng có chi phí

Nếu khai báo quá nhiều dependency không cần thiết:

```text
mọi .o phụ thuộc mọi .h
```

thì build thường vẫn đúng, nhưng một header nhỏ thay đổi có thể làm quá nhiều object bị rebuild.

```text
Dependency thiếu     -> có thể build sai/stale
Dependency dư        -> build đúng nhưng chậm hơn cần thiết
Dependency chính xác -> incremental build hiệu quả
```

### 4.4 Make chỉ làm tốt khi graph đúng

Điểm này đặc biệt quan trọng:

```text
Make algorithm tốt
      +
Dependency graph sai
      =
Build behavior vẫn sai
```

Make không thể tự sửa một dependency mà Makefile không hề mô tả, trừ khi thông tin được cung cấp thông qua implicit rule/dependency file hoặc cơ chế khác.

> **Điểm cần nhớ:** Chất lượng của một Makefile trước hết nằm ở **độ chính xác của dependency graph**, không phải ở việc recipe ngắn hay dài.

---

## 5. Recipe và mối quan hệ giữa Make với Shell

Recipe là phần dễ khiến người mới nhầm Makefile với shell script.

Ví dụ:

```make
app: main.o foo.o
	$(CC) main.o foo.o -o app
```

Make xử lý rule và quyết định **có cần chạy recipe hay không**. Khi recipe cần chạy, command thường được chuyển cho shell thực thi.

Mô hình:

```text
Make parser / dependency engine
          |
          | target cần update
          v
       recipe text
          |
          | variable expansion
          v
        shell
          |
          v
 external command
```

### 5.1 Recipe line mặc định bắt đầu bằng TAB

Trong cú pháp Make truyền thống, recipe line mặc định được nhận biết bằng ký tự TAB ở đầu dòng:

```make
target: prerequisite
<TAB>command
```

Một chuỗi spaces nhìn giống TAB trên editor không nhất thiết tương đương.

Đây là nguồn của lỗi quen thuộc kiểu:

```text
missing separator
```

GNU Make có cơ chế `.RECIPEPREFIX` cho phép thay ký tự prefix, nhưng ở mức nền tảng nên giữ mental model:

```text
Rule header  -> không bắt đầu bằng recipe TAB
Recipe       -> mặc định bắt đầu bằng TAB
```

### 5.2 Make và shell có hai hệ cú pháp khác nhau

Ví dụ:

```make
OBJ = main.o foo.o

app: $(OBJ)
	$(CC) $(OBJ) -o $@
```

Các biểu thức:

```text
$(OBJ)
$(CC)
$@
```

là Make syntax được Make expand.

Trong khi các cú pháp như:

```text
&&
|
>
for ...; do ...; done
```

là shell syntax nếu xuất hiện bên trong recipe.

Do đó:

```text
Make language != Shell language
```

### 5.3 Mỗi recipe line thường chạy trong shell riêng

Theo hành vi mặc định của GNU Make, mỗi dòng recipe được thực thi trong một shell invocation riêng, trừ một số cơ chế đặc biệt như `.ONESHELL`.

Ví dụ:

```make
target:
	cd build
	pwd
```

Không nên mặc định suy luận rằng `pwd` ở dòng thứ hai vẫn đang ở directory mà dòng `cd build` đã chuyển tới.

Mental model:

```text
Line 1 -> shell A -> cd build -> shell A kết thúc
Line 2 -> shell B -> working directory ban đầu
```

Nếu các thao tác phải dùng cùng shell context, chúng thường cần nằm trong cùng logical recipe command, ví dụ thông qua shell syntax thích hợp.

### 5.4 Dấu `$` có thể được Make xử lý trước shell

Make dùng `$` cho variable/automatic variable của chính nó.

Nếu recipe cần truyền literal `$` tới shell, thường phải dùng `$$`.

Mô hình:

```text
Makefile text
    $$HOME
      |
      | Make processing
      v
    $HOME
      |
      | shell expansion
      v
/home/user
```

Đây là ví dụ điển hình cho việc phải phân biệt **Make expansion** với **shell expansion**.

### 5.5 Exit status của recipe có ý nghĩa với Make

Khi một command trong recipe kết thúc, nó trả về một **exit status** cho shell. Theo quy ước thông thường trên Linux/Unix:

```text
exit status = 0      -> command thành công
exit status != 0     -> command báo lỗi/thất bại
```

Make không cần hiểu chi tiết compiler, linker hay command bên ngoài đã lỗi vì nguyên nhân gì. Make chủ yếu dựa vào exit status để biết bước cập nhật target có thành công hay không.

Ví dụ:

```make
app: main.o foo.o
	$(CC) main.o foo.o -o app
```

Nếu linker thất bại:

```text
Compiler / linker
       |
       | exit status != 0
       v
      Shell
       |
       v
      Make
       |
       v
recipe bị xem là thất bại
       |
       v
target không được xem là đã update thành công
```

Do đó, nếu một prerequisite như `foo.o` không build thành công thì target phụ thuộc vào nó như `app` cũng không thể được xem là build thành công.

Mô hình tổng quát:

```text
External command
      |
      v
  exit status
   /      \
  0       != 0
  |         |
  v         v
success    failure
    \       /
       Make
```

GNU Make có một số prefix đặc biệt cho recipe line:

- `-command`: yêu cầu Make bỏ qua lỗi của command đó và tiếp tục.
- `@command`: chỉ ngăn Make echo command ra màn hình trước khi chạy; **không** làm Make bỏ qua lỗi.

Các prefix này nên được dùng có chủ đích, không nên dùng `-` để che lỗi build ngoài ý muốn.
---

## 6. Variable trong Make và thời điểm expansion

Variable giúp tách dữ liệu cấu hình khỏi cấu trúc dependency/recipe.

Ví dụ:

```make
CC = gcc
OBJ = main.o foo.o
```

Sau đó:

```make
app: $(OBJ)
	$(CC) $(OBJ) -o app
```

Make dùng cú pháp phổ biến:

```text
$(NAME)
```

hoặc:

```text
${NAME}
```

để tham chiếu variable.

### 6.1 `=`: recursively expanded variable

Ví dụ:

```make
A = $(B)
B = hello
```

Với flavor này, phần bên phải được giữ theo dạng có thể tiếp tục expand khi variable được sử dụng.

Mental model đơn giản:

```text
A = $(B)
     |
     | chưa cần chốt thành giá trị cuối ngay tại definition
     v
Khi dùng A -> expand B -> hello
```

Điều này linh hoạt nhưng có thể tạo expansion vòng lặp hoặc hành vi khó đọc nếu lạm dụng.

### 6.2 `:=`: simply expanded variable

Ví dụ:

```make
A := $(B)
```

Phần bên phải được expand tại thời điểm definition được xử lý.

Mental model:

```text
A := expression
       |
       | expand ngay
       v
A giữ kết quả đã expand
```

GNU Make cũng hỗ trợ `::=` với ý nghĩa tương ứng trong các phiên bản hiện đại/chuẩn POSIX mới hơn, nhưng `:=` là dạng rất phổ biến trong Makefile thực tế.

### 6.3 `?=`: chỉ gán khi variable chưa được định nghĩa

Ví dụ:

```make
CC ?= gcc
```

Ý nghĩa khái quát:

```text
Nếu CC chưa có giá trị định nghĩa
    -> dùng gcc
Nếu CC đã được cung cấp từ nơi khác
    -> giữ giá trị đó
```

Cách này hữu ích khi muốn có default nhưng vẫn cho phép bên ngoài tùy biến.

### 6.4 `+=`: nối thêm vào variable

Ví dụ:

```make
CFLAGS += -Wall
```

Thay vì thay thế toàn bộ giá trị, nội dung mới được append theo semantics của variable hiện tại.

Điều này phù hợp khi nhiều lớp cấu hình cần bổ sung option.

### 6.5 Variable có thể đến từ nhiều nguồn

Một Make variable có thể đến từ nhiều nơi, ví dụ:

```text
Built-in/default
Environment
Makefile
Included Makefile
Command line
```

Điểm quan trọng cần nhớ ở mức này là: **giá trị truyền trên command line thường có thể override assignment thông thường trong Makefile**.

Ví dụ Makefile có:

```make
CC = gcc
```

nhưng người dùng chạy:

```bash
make CC=clang
```

thì Make sẽ dùng:

```text
CC = clang
```

Do đó recipe:

```make
app: main.c
	$(CC) main.c -o app
```

sẽ tương đương với việc chạy:

```bash
clang main.c -o app
```

Mental model:

```text
Makefile:
CC = gcc

Command line:
make CC=clang

        |
        v

CC thực tế = clang
```

Cơ chế này rất hữu ích vì người dùng có thể thay compiler hoặc option build mà không cần sửa trực tiếp Makefile.

GNU Make có directive `override` để thay đổi quy tắc ưu tiên này, nhưng ở mức nền tảng chỉ cần nhớ rằng **command-line variable thường ưu tiên hơn assignment thông thường trong Makefile**.

### 6.6 Variable không đồng nghĩa environment variable

Make variable và shell environment variable là hai khái niệm liên quan nhưng không giống nhau.

Ví dụ:

```make
CC = gcc

target:
	echo $(CC)
```

Ở đây `$(CC)` là **Make variable**. Make expand nó trước khi đưa command cho shell:

```text
$(CC)
  |
  | Make expansion
  v
gcc
```

Shell thực tế nhận:

```bash
echo gcc
```

Ngược lại, nếu recipe viết:

```make
target:
	echo $$CC
```

thì Make biến `$$` thành `$` và shell nhận:

```bash
echo $CC
```

Lúc này `$CC` được **shell** xử lý như một shell/environment variable.

Mental model:

```text
$(CC)
  |
  +--> Make expansion

$$CC
  |
  | Make xử lý $$ -> $
  v
$CC
  |
  +--> shell expansion
```

Một Make variable không tự động trở thành environment variable của recipe process trong mọi trường hợp. Nếu muốn truyền nó xuống environment, có thể dùng `export`:

```make
CC = gcc
export CC

target:
	echo $$CC
```

Khi đó:

```text
Make variable
CC = gcc
   |
   | export
   v
Environment của shell
CC=gcc
```

Chiều ngược lại, khi Make khởi động, nó cũng có thể nhận nhiều variable từ environment của process đã gọi `make`.

> **Điểm cần nhớ:** `$(VAR)` là Make xử lý variable; `$$VAR` trong recipe thường dùng để truyền `$VAR` xuống cho shell xử lý.
---

## 7. Các biến build thường dùng: `CC`, `CPPFLAGS`, `CFLAGS`, `LDFLAGS`, `LDLIBS`

GNU Make có các built-in implicit rule và convention lâu đời quanh một số variable chuẩn. Ngay cả khi project tự viết recipe, giữ đúng vai trò của các variable này làm Makefile dễ tích hợp với toolchain và build environment hơn.

Mô hình:

```text
Preprocess / Compile                       Link
--------------------                       ----
CC       -> compiler driver                CC/CXX -> driver dùng để link
CPPFLAGS -> preprocessor options           LDFLAGS -> linker-related flags
CFLAGS   -> C compile options              LDLIBS  -> libraries
```

### 7.1 `CC`

`CC` chỉ command dùng làm C compiler/driver.

Ví dụ:

```make
CC = gcc
```

Trong cross-compilation:

```make
CC = aarch64-linux-gnu-gcc
```

Make không tự hiểu rằng tên đó là native hay cross compiler. Với Make, đây đơn giản là command được recipe hoặc implicit rule sử dụng.

### 7.2 `CPPFLAGS`

`CPPFLAGS` thường chứa option liên quan preprocessing, đặc biệt:

```text
-I...
-D...
-U...
```

Ví dụ khái quát:

```make
CPPFLAGS += -Iinclude -DFEATURE_X
```

Điểm phân biệt:

```text
-I include path       -> CPPFLAGS
-D macro definition   -> CPPFLAGS
```

### 7.3 `CFLAGS`

`CFLAGS` thường chứa option dành cho compilation của C:

```text
-O2
-g
-Wall
-Wextra
-std=c11
```

Ví dụ:

```make
CFLAGS += -O2 -Wall
```

Một option có thể ảnh hưởng nhiều stage thực tế của GCC driver, nhưng convention này giúp tách **compile configuration** khỏi link configuration.

### 7.4 `LDFLAGS`

`LDFLAGS` thường chứa option điều khiển link, đặc biệt các option truyền cho linker hoặc liên quan link layout/search path.

Ví dụ:

```text
-L/path/to/lib
-Wl,...
```

Điểm cần nhớ:

```text
LDFLAGS = option cho quá trình link
```

không nên dùng như nơi mặc định để nhét danh sách `-lfoo -lbar` nếu project muốn bám convention chuẩn.

### 7.5 `LDLIBS`

`LDLIBS` thường chứa các library được link:

```text
-lm
-lpthread
-lfoo
```

Mô hình link:

```text
Object files
   +
LDFLAGS
   +
LDLIBS
   |
   v
Link step
```

Tách `LDFLAGS` và `LDLIBS` cũng hữu ích vì **thứ tự library có thể có ý nghĩa**, đặc biệt với static archive như đã học ở Chủ đề 3.

### 7.6 `AR` và `ARFLAGS`

Khi project tạo static library `.a`, các variable thường gặp khác là:

```text
AR       -> archive tool, thường là ar
ARFLAGS  -> option cho archive tool
```

Trong cross toolchain, `AR` cũng phải là tool tương ứng target, ví dụ:

```text
aarch64-linux-gnu-ar
```

chứ không mặc định dùng `ar` của host nếu archive chứa target object files.

### 7.7 Vì sao việc phân loại flag quan trọng?

Nếu mọi flag bị dồn vào một variable:

```make
FLAGS = ...mọi thứ...
```

Makefile có thể vẫn hoạt động trong project nhỏ, nhưng mental model bị mờ:

```text
Cái nào ảnh hưởng preprocess?
Cái nào ảnh hưởng compile?
Cái nào chỉ có ý nghĩa ở link?
Library nằm ở đâu?
```

Tách vai trò giúp kết nối Makefile với pipeline đã học ở Chủ đề 1:

```text
Preprocess      Compile        Assemble        Link
    ^              ^                              ^
 CPPFLAGS       CFLAGS                        LDFLAGS
                                                +
                                              LDLIBS
```

> **Lưu ý:** Đây là convention build rất phổ biến, không phải "type system" bắt buộc của Make. Make không ngăn một project sử dụng tên variable khác.

---

## 8. Automatic variable

`Automatic variable` là các variable mà Make tự gán theo rule đang được thực thi.

Chúng giúp một pattern recipe có thể dùng lại cho nhiều target mà không hard-code tên file.

Ví dụ:

```make
%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
```

Ở đây:

```text
$@ -> target hiện tại
$< -> prerequisite đầu tiên
```

### 8.1 `$@` — target name

Với rule:

```make
main.o: main.c
	$(CC) -c $< -o $@
```

trong recipe:

```text
$@ = main.o
```

Mental model:

```text
"Tôi đang tạo target nào?"
        |
        v
       $@
```

### 8.2 `$<` — prerequisite đầu tiên

Trong rule trên:

```text
$< = main.c
```

Nó đặc biệt tiện với compile pattern rule có một source chính.

### 8.3 `$^` — danh sách prerequisite

`$^` biểu diễn danh sách các prerequisite của rule theo semantics của GNU Make, thường bỏ các tên trùng lặp.

Ví dụ:

```make
app: main.o foo.o
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@
```

Mô hình:

```text
$@ = app
$^ = main.o foo.o
```

### 8.4 `$?` — prerequisite mới hơn target

`$?` biểu diễn những prerequisite mới hơn target.

Nó hữu ích trong một số loại rule incremental đặc biệt, nhưng không phải automatic variable thường xuyên cần dùng trong mọi Makefile C.

### 8.5 `$*` — stem của pattern

Trong một pattern rule, `$*` là **stem**, tức là phần mà ký tự `%` đã match.

Ví dụ:

```make
%.o: %.c
```

Nếu Make đang build:

```text
foo.o
```

thì `%` tương ứng với:

```text
foo
```

Do đó:

```text
$@ = foo.o
$< = foo.c
$* = foo
```

Mental model:

```text
%.o : %.c
 ^
 |
 % = foo
 |
 v
foo.o : foo.c

$* = foo
```

Một ví dụ khác:

```make
build/%.o: src/%.c
```

Nếu target là:

```text
build/driver.o
```

thì:

```text
$@ = build/driver.o
$< = src/driver.c
$* = driver
```

> **Điểm cần nhớ:** `$*` không phải toàn bộ tên target hay prerequisite; nó là **phần mà `%` đại diện trong pattern rule**.

### 8.6 Automatic variable thuộc context của rule/recipe

Không nên nhìn `$@`, `$<`, `$^` như global variable thông thường.

Chúng có ý nghĩa gắn với rule đang được Make xử lý.

```text
Rule context
    |
    +--> $@
    +--> $<
    +--> $^
    +--> ...
```

> **Điểm cần nhớ:** Automatic variable giúp mô tả **mẫu build tổng quát** mà không phải viết riêng tên từng file trong recipe.

---

## 9. Pattern rule và implicit rule

Khi nhiều source file có cùng quy tắc build:

```text
main.c -> main.o
foo.c  -> foo.o
bar.c  -> bar.o
```

việc lặp ba rule gần giống nhau là không cần thiết.

Pattern rule cho phép mô tả quan hệ tổng quát:

```make
%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
```

Mental model:

```text
%.c
 |
 | cùng stem
 v
%.o
```

Ví dụ:

```text
main.c -> main.o
  ^         ^
  |         |
 stem = main
```

### 9.1 `%` đại diện phần stem

Trong:

```make
%.o: %.c
```

`%` không đơn giản là shell wildcard.

Nó là pattern syntax của Make.

Nếu target cần là `driver.o`, Make có thể suy ra prerequisite tương ứng `driver.c` theo cùng stem `driver`.

### 9.2 Implicit rule là gì?

GNU Make có nhiều built-in implicit rule mô tả các cách build phổ biến.

Ví dụ, Make có thể biết cách tạo `.o` từ `.c` mà Makefile không viết đầy đủ recipe, dựa trên built-in rule và các variable như `CC`, `CPPFLAGS`, `CFLAGS`.

Mô hình:

```text
Target cần: foo.o
      |
      | không có explicit recipe phù hợp
      v
Make tìm implicit rule
      |
      v
nhận ra foo.c có thể tạo foo.o
      |
      v
sử dụng compiler rule
```

### 9.3 Explicit pattern rule và built-in implicit rule không giống nhau

Hai trường hợp:

```text
Project tự viết:
%.o: %.c
    ...
```

và:

```text
GNU Make built-in rule:
.c -> .o
```

đều có thể tạo hành vi tương tự, nhưng nguồn của rule khác nhau.

Explicit pattern rule giúp project thể hiện chính xác policy của mình và giảm phụ thuộc vào built-in database.

### 9.4 Suffix rule là cơ chế cũ hơn

Make cũng hỗ trợ dạng suffix rule lịch sử như:

```make
.c.o:
	...
```

Nhưng pattern rule:

```make
%.o: %.c
```

thường rõ nghĩa và linh hoạt hơn cho Makefile hiện đại.

Ở mức chủ đề này chỉ cần nhận biết suffix rule có thể xuất hiện trong codebase cũ; không cần đào sâu.

### 9.5 Implicit rule search có thể làm behavior "ẩn"

Nếu Makefile không có recipe mà build vẫn xảy ra, nguyên nhân có thể là built-in implicit rule.

Điều này tiện, nhưng khi debug cần nhớ:

```text
"Tôi không thấy rule trong Makefile"
            !=
"Make không có rule"
```

GNU Make có một database rule/variable built-in ngoài nội dung project.

---

## 10. Phony target, default goal và target tiện ích

Không phải mọi target đều tương ứng một file.

Ví dụ:

```make
clean:
	rm -f *.o app
```

Mục đích của `clean` là thực hiện một action, không phải tạo file tên `clean`.

Đây là trường hợp điển hình của `phony target`.

### 10.1 Vấn đề nếu không khai báo `.PHONY`

Nếu filesystem vô tình có file tên `clean`, Make có thể áp dụng logic timestamp/file target thông thường và quyết định không chạy recipe như mong muốn.

Do đó thường viết:

```make
.PHONY: clean

clean:
	rm -f *.o app
```

Mental model:

```text
.PHONY
   |
   v
clean không được xem như file target thông thường
   |
   v
khi goal clean được yêu cầu -> recipe được xét như phony action
```

### 10.2 `all` thường là phony aggregation target

Ví dụ:

```make
.PHONY: all
all: app tool
```

`all` không nhất thiết có recipe.

Nó dùng dependency graph để gom nhiều mục tiêu:

```text
        all
       /   \
     app   tool
```

Khi `all` là goal, Make đi xuống cả hai nhánh.

### 10.3 Target có thể chỉ mô tả dependency mà không có recipe

Ví dụ:

```make
all: app tool
```

Không có command bên dưới vẫn hợp lý.

Target này đóng vai trò graph node/aggregation point.

Đây là ví dụ cho thấy:

```text
Target != bắt buộc phải có recipe
```

### 10.4 Default goal

Nếu người dùng chỉ yêu cầu:

```text
make
```

GNU Make chọn default goal theo rule của nó, thường là target thông thường đầu tiên được gặp trong Makefile.

Project có thể chỉ định rõ:

```make
.DEFAULT_GOAL := all
```

Điều này làm intent rõ hơn khi Makefile phức tạp hoặc có nhiều include.

### 10.5 Phony target không nên bị lạm dụng như thủ tục tuần tự

Một Makefile có thể bị viết theo kiểu:

```text
step1 -> step2 -> step3 -> step4
```

chỉ để ép thứ tự, dù các bước thực tế có dependency khác.

Cách này biến dependency graph thành một shell script trá hình, làm mất cơ hội incremental/parallel build.

Nguyên tắc tốt hơn:

```text
Mô tả dependency thật
thay vì
mô tả thứ tự giả tạo
```

---

## 11. Header dependency và file `.d`

Header dependency là một trong những phần quan trọng nhất khi dùng Make cho C/C++.

Giả sử:

```c
/* main.c */
#include "foo.h"
#include "config.h"
```

Object file thực sự phụ thuộc:

```text
main.o
  |
  +--> main.c
  +--> foo.h
  +--> config.h
```

Nếu `foo.h` còn include `types.h`:

```text
main.c
  |
  +--> foo.h
         |
         +--> types.h
```

thì thay `types.h` cũng có thể yêu cầu rebuild `main.o`.

### 11.1 Khai báo header bằng tay khó duy trì

Có thể viết:

```make
main.o: main.c foo.h config.h types.h
```

Nhưng khi include graph thay đổi:

```text
thêm header
xóa header
header include header khác
conditional include
```

Makefile rất dễ bị lệch với source.

Khi dependency thiếu:

```text
Header thay đổi
   |
   v
Make không biết
   |
   v
object không rebuild
```

### 11.2 Compiler biết include graph tốt hơn Make

Trong quá trình preprocessing, compiler/preprocessor đã phải xử lý `#include`.

Vì vậy GCC có khả năng phát sinh dependency information cho Make.

Các option phổ biến:

```text
-MD
-MMD
-MF
-MP
-MT / -MQ
```

Trong đó ở project C thông thường, cặp thường thấy là:

```text
-MMD -MP
```

### 11.3 `-MMD` tạo dependency cho user headers

`-MMD` cho phép dependency file được tạo như side effect của compilation, tương tự `-MD` nhưng bỏ các system header khỏi dependency output.

Ví dụ logic, compiler có thể tạo:

```text
main.o
main.d
```

Trong đó `main.d` chứa rule kiểu:

```make
main.o: main.c foo.h config.h types.h
```

Mô hình:

```text
main.c
  |
  | compiler/preprocessor
  +----------------------+
  |                      |
  v                      v
main.o                  main.d
                         |
                         v
              dependency information
```

### 11.4 `-MP` thêm dummy rule cho header dependency

Nếu dependency file nhắc tới một header sau đó bị xóa/đổi tên, Make có thể báo lỗi vì prerequisite không còn tồn tại và không có rule tạo nó.

`-MP` yêu cầu preprocessor thêm các phony-like dummy target cho dependency ngoài main file, giúp tránh một số lỗi kiểu này khi header bị loại bỏ.

Ví dụ dạng khái quát:

```make
main.o: main.c foo.h
foo.h:
```

### 11.5 Dependency file phải được Make đọc lại

Tạo `.d` chưa đủ.

Makefile cần đưa dependency information trở lại graph, thường thông qua `include` hoặc `-include`.

Mô hình:

```text
Compile
  |
  +--> main.o
  |
  +--> main.d
          |
          | include vào lần Make xử lý
          v
 Dependency graph đầy đủ hơn
```

`-include` thường được dùng vì dependency file có thể chưa tồn tại ở lần build đầu.

### 11.6 `.d` không phải object file

Cần phân biệt:

```text
.o = machine code + symbol/relocation metadata cho linker
.d = dependency description cho Make
```

Hai artifact phục vụ hai tầng hoàn toàn khác nhau.

> **Điểm cần nhớ:** Make không tự parse C để biết `#include`. Cách chắc chắn hơn là để compiler/preprocessor sinh dependency vì chính nó biết include graph thực tế.

---

## 12. Generated files và order-only prerequisite

Build graph không chỉ gồm source có sẵn trong repository. Một số file có thể được **generate** trong chính quá trình build.

Ví dụ:

```text
schema / config / protocol description
              |
              | generator
              v
         generated.h
              |
              v
            foo.o
```

Makefile phải mô tả quan hệ này:

```text
foo.o phụ thuộc generated.h
generated.h phụ thuộc input của generator
```

Nếu chỉ dựa vào việc recipe "tình cờ chạy generator trước", graph không phản ánh đúng dependency.

### 12.1 Directory cũng có thể là prerequisite về mặt thứ tự

Giả sử object được đặt trong:

```text
build/main.o
```

Directory `build/` phải tồn tại trước khi compiler ghi output.

Có thể hình dung:

```text
build/main.o
     |
     +--> main.c
     |
     +--> build/ phải tồn tại
```

Nhưng nếu timestamp của directory thay đổi vì thêm/xóa file bên trong, ta **không muốn** chỉ vì directory mới hơn `build/main.o` mà object phải compile lại.

Đây là tình huống phù hợp với `order-only prerequisite`.

### 12.2 Normal prerequisite và order-only prerequisite

GNU Make dùng dấu `|` để phân tách:

```make
target: normal-prerequisites | order-only-prerequisites
```

Ví dụ khái quát:

```make
build/main.o: main.c | build
```

Ý nghĩa:

```text
main.c
  |
  | normal dependency
  v
build/main.o

build directory
  |
  | phải sẵn sàng trước recipe
  | nhưng timestamp của nó không buộc object rebuild
  v
build/main.o
```

### 12.3 Order-only dependency không phải "dependency yếu" tùy ý

Nó có semantics cụ thể:

- prerequisite vẫn phải được cập nhật/sẵn sàng trước target;
- nhưng trạng thái mới hơn của order-only prerequisite không làm target file bị out-of-date theo logic timestamp thông thường.

Do đó phù hợp với **điều kiện cấu trúc/thứ tự** hơn là dependency nội dung.

### 12.4 Generated file phải có rule tạo ra nó

Một lỗi thiết kế phổ biến:

```text
foo.o depends on generated.h
nhưng không có rule tạo generated.h
```

Nếu file chưa tồn tại:

```text
Make cần prerequisite generated.h
           |
           v
không tìm thấy file
           |
           v
không tìm thấy rule tạo file
           |
           v
No rule to make target ...
```

Đây không phải lỗi compiler; đó là dependency graph thiếu producer cho một node.

---

## 13. Parallel build và tính đúng đắn của dependency graph

GNU Make có thể build nhiều target độc lập song song, thường thông qua tùy chọn dạng `-j`.

Ví dụ graph:

```text
              app
           /   |   \
       main.o foo.o bar.o
         |      |     |
      main.c  foo.c  bar.c
```

Ba object file không phụ thuộc lẫn nhau.

Vì vậy về mặt graph:

```text
main.o  ─┐
foo.o   ─┼─ có thể build đồng thời
bar.o   ─┘

sau khi cả ba sẵn sàng
        |
        v
       app
```

### 13.1 Parallel build không thay dependency semantics

Make không "đổi thứ tự dependency" khi chạy song song.

Nó chỉ cho phép các node độc lập được xử lý đồng thời.

```text
Correct graph
    |
    +--> serial build đúng
    |
    +--> parallel build cũng đúng và nhanh hơn
```

### 13.2 Dependency thiếu thường lộ rõ khi dùng `-j`

Giả sử:

```text
foo.o thực tế cần generated.h
```

nhưng Makefile không khai báo edge đó.

Serial build có thể tình cờ chạy generator trước vì thứ tự hiện tại:

```text
Generate header
Compile foo
```

nên trông có vẻ đúng.

Khi parallel:

```text
Generate header  ---->

Compile foo      ----> bắt đầu cùng lúc
```

compiler có thể đọc file chưa tồn tại hoặc file chưa hoàn tất.

Đây là **race condition của build graph**.

### 13.3 Không nên dùng sleep hoặc thứ tự dòng để sửa dependency race

Nếu build chỉ đúng khi thêm delay:

```text
sleep 1
```

thì thường dependency thật chưa được mô tả.

Cách tư duy đúng:

```text
"Step B cần artifact A"
        |
        v
Mô tả A là prerequisite của B
```

không phải:

```text
"Hy vọng A hoàn tất trước vì command được đặt phía trên"
```

### 13.4 Parallel-safe Makefile là dấu hiệu graph chính xác hơn

Không phải mọi build system đều có thể song song vô hạn do resource/tool limitation, nhưng về dependency logic:

```text
Nếu hai target có dependency thật
-> graph phải thể hiện

Nếu không có dependency
-> Make được quyền schedule độc lập
```

Đây là một lý do dependency graph chính xác quan trọng hơn recipe sequencing.

---

## 14. Tư duy chẩn đoán lỗi Makefile

Khi Make build sai hoặc không build như mong đợi, nên xác định **lỗi thuộc tầng nào** thay vì sửa ngẫu nhiên command.

Mental model:

```text
Makefile syntax / parsing
        |
Dependency graph
        |
Variable expansion
        |
Rule selection
        |
Recipe execution
        |
Compiler / linker / external tool
```

### 14.1 `missing separator`

Một nguyên nhân rất phổ biến là recipe indentation sai.

Mô hình:

```text
Make parser mong recipe prefix
        |
        v
nhận spaces / syntax không hợp lệ
        |
        v
missing separator
```

Đây là **Make syntax error**, chưa phải compiler error.

### 14.2 `No rule to make target ...`

Thông báo này thường có nghĩa Make cần một prerequisite/target nhưng:

```text
file không tồn tại
+
Make không tìm được explicit/implicit rule để tạo nó
```

Cần kiểm tra:

```text
Tên file đúng không?
Path đúng không?
Dependency có typo không?
Generated file có producer rule không?
Pattern rule có match không?
```

### 14.3 Recipe chạy mọi lần dù source không đổi

Các khả năng:

```text
target là .PHONY
hoặc
recipe không tạo đúng target đã khai báo
hoặc
prerequisite luôn mới hơn
hoặc
một prerequisite luôn được xem là out-of-date
hoặc
timestamp bất thường
```

Ví dụ sai mental model:

```make
output.bin: input
	tool input -o real-output.bin
```

Target mà Make theo dõi là `output.bin`, nhưng recipe lại tạo `real-output.bin`.

Kết quả:

```text
output.bin vẫn không tồn tại
        |
        v
lần sau Make lại thấy target missing
        |
        v
recipe chạy lại
```

### 14.4 File thay đổi nhưng target không rebuild

Đây thường là **missing dependency**.

Ví dụ:

```text
header thay đổi
     |
     v
object không rebuild
```

Câu hỏi đầu tiên nên là:

```text
Header có thật sự nằm trong prerequisite graph của object không?
```

chứ không phải ngay lập tức nghi compiler cache hoặc GCC lỗi.

### 14.5 Variable có giá trị khác dự kiến

Cần xác định nguồn variable:

```text
Built-in?
Environment?
Makefile?
Included file?
Command line?
Automatic variable?
```

và loại assignment:

```text
=
:=
?=
+=
```

Ngoài ra cần phân biệt:

```text
$(VAR)  -> Make expansion
$VAR    -> có thể bị Make hiểu khác trước khi shell thấy
$$VAR   -> thường dùng để truyền $VAR cho shell
```

### 14.6 Compiler/linker error không phải Make error

Ví dụ:

```text
undefined reference to foo
```

nếu xuất hiện trong recipe link thì nguyên nhân chính thường ở link inputs/library/order như Chủ đề 1 và 3, không phải dependency engine của Make.

Tương tự:

```text
fatal error: header.h: No such file or directory
```

là compiler/preprocessor không tìm thấy header trong invocation hiện tại.

Make chỉ là thành phần gọi command đó.

Mô hình chẩn đoán:

```text
Make có gọi đúng command không?
      |
      +-- Không -> xem rule/variable/graph
      |
      +-- Có
          |
          v
       Tool được gọi báo lỗi gì?
          |
          +--> compiler layer
          +--> linker layer
          +--> archive layer
          +--> shell layer
```

### 14.7 Các option quan sát của GNU Make

GNU Make cung cấp các option hữu ích để hiểu quyết định của nó, ví dụ:

```text
-n / --just-print       hiển thị recipe dự kiến mà không thực thi thông thường
--trace                 cho biết rule/target được update vì lý do nào
-p                      in database rule/variable
-d                      debug output chi tiết
--warn-undefined-variables
                        cảnh báo tham chiếu variable chưa định nghĩa
```

Các option này nên được hiểu như **công cụ quan sát dependency engine**, tương tự `readelf`/`nm` ở các chủ đề ELF trước.

> **Điểm cần nhớ:** Khi Makefile có vấn đề, hãy xác định đang sai ở **graph, expansion, rule selection hay external tool**. Không phải mọi lỗi xuất hiện sau lệnh `make` đều là lỗi của Make.

---

## 15. Liên hệ với Embedded Linux và cross-compilation

Make trở nên đặc biệt quan trọng trong Embedded Linux vì một project thường không build cho development host mà build cho target khác kiến trúc/ABI.

Mô hình từ Chủ đề 2:

```text
HOST x86-64 Linux
      |
      | cross toolchain
      v
TARGET AArch64 Linux artifacts
```

Make không thay đổi mô hình cross-compilation này. Nó chỉ tổ chức các command của cross toolchain thành dependency graph.

### 15.1 GNU Make không có khái niệm built-in "cross compiler" đặc biệt

Với Make:

```text
CC = gcc
```

và:

```text
CC = aarch64-linux-gnu-gcc
```

đều chỉ là giá trị của variable `CC`.

Make không tự kiểm tra:

```text
compiler này sinh x86-64 hay AArch64?
ABI nào?
sysroot nào?
```

Đó là trách nhiệm của toolchain configuration/project.

### 15.2 `CROSS_COMPILE` là convention của nhiều project, không phải keyword của GNU Make

Nhiều Embedded/Linux project dùng pattern:

```make
CROSS_COMPILE ?= aarch64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
AR := $(CROSS_COMPILE)ar
```

Nhưng cần hiểu:

```text
CROSS_COMPILE
```

không phải special variable bắt buộc của GNU Make.

Nó là **project convention** được Makefile lựa chọn.

Ví dụ Linux kernel và nhiều embedded codebase dùng convention tương tự, nhưng project khác có thể cấu hình toolchain bằng cách khác.

### 15.3 Các tool trong cùng target toolchain phải nhất quán

Nếu compiler sinh AArch64 object:

```text
aarch64-linux-gnu-gcc
```

thì archive/object utilities cũng thường phải đến từ toolchain target tương ứng:

```text
aarch64-linux-gnu-ar
aarch64-linux-gnu-ranlib
aarch64-linux-gnu-strip
...
```

Mental model:

```text
CC / AR / linker-facing tools
           |
           v
phải cùng phục vụ target binary model
```

Không nên trộn tool host và target chỉ vì command name giống nhau.

### 15.4 Sysroot và Make nằm ở hai tầng khác nhau

`Sysroot` đã học ở Chủ đề 2 là môi trường target headers/libraries mà compiler/linker nhìn vào.

Make chỉ chuyển option/configuration cần thiết tới toolchain.

```text
Make
 |
 | recipe + variable
 v
Cross GCC
 |
 | --sysroot=...
 v
Target headers / libraries
```

Do đó:

```text
Makefile     != sysroot
Make         != ABI knowledge engine
```

### 15.5 Host tool và target artifact có thể tồn tại trong cùng build

Một Embedded Linux project đôi khi cần:

```text
Host generator
   chạy trên x86-64 build machine

Target program
   chạy trên AArch64 board
```

Hai loại artifact này dùng toolchain khác nhau:

```text
                    Build machine
                        |
          +-------------+-------------+
          |                           |
          v                           v
    HOST compiler                CROSS compiler
          |                           |
          v                           v
 generator chạy host        binary chạy target
          |
          | sinh source/header
          +---------------------------> target build
```

Make dependency graph có thể mô tả cả hai, nhưng variable/tool selection phải rõ ràng.

Đây là nền tảng quan trọng cho các build system lớn hơn như Buildroot/Yocto sau này.

### 15.6 `ARCH` cũng thường là project-specific convention

Một số codebase cho phép:

```text
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
```

Không nên suy luận rằng GNU Make tự hiểu ý nghĩa `ARCH`.

Make chỉ thấy variable.

Project Makefile mới là nơi diễn giải:

```text
ARCH=arm64
      |
      v
chọn source / flags / configuration phù hợp
```

### 15.7 Makefile phải giữ separation giữa build policy và target details

Một Makefile dễ cross-compile thường tránh hard-code:

```make
CC = /usr/bin/gcc
```

ở mọi nơi.

Thay vào đó, dependency graph dùng variable:

```text
$(CC)
$(AR)
$(CPPFLAGS)
$(CFLAGS)
$(LDFLAGS)
$(LDLIBS)
```

nhờ đó toolchain/configuration có thể thay đổi mà graph cơ bản vẫn giữ.

Mô hình:

```text
Dependency Graph
      |
      | tương đối độc lập
      v
Build Recipes
      |
      | parameterized by variables
      v
Native toolchain hoặc Cross toolchain
```

### 15.8 Make là một tầng, không phải toàn bộ Embedded Linux build system

Trong một Embedded Linux stack lớn:

```text
Yocto / Buildroot / SDK / CI
          |
          v
package/project build system
          |
          +--> Make
          +--> CMake + Ninja/Make
          +--> Meson
          +--> custom
          |
          v
compiler/linker/toolchain
```

Make có thể là build tool trực tiếp của một package, hoặc là backend được một build-system generator tạo ra.

Điều này dẫn trực tiếp tới Chủ đề 5:

```text
CMake
   |
   | generate build system
   v
Make / Ninja / ...
   |
   v
Compiler + Linker
```

> **Điểm cần nhớ:** Make tổ chức **dependency và execution**. Cross-compilation correctness vẫn phụ thuộc toolchain, ABI, sysroot và library target đã học ở các chủ đề trước.

---

## 16. Tổng kết và mô hình tư duy

### 16.1 Mô hình toàn chương

Có thể gom toàn bộ kiến thức của Make vào sơ đồ:

```text
                         Makefile
                            |
                            | mô tả
                            v
                    Dependency Graph
                            |
                            | bắt đầu từ goal
                            v
                  Check target/prerequisite
                            |
                +-----------+-----------+
                |                       |
                v                       v
          up-to-date                out-of-date
                |                       |
                |                       v
                |                    Recipe
                |                       |
                |                 Make expansion
                |                       |
                |                       v
                |                     Shell
                |                       |
                |                       v
                |             compiler/linker/tool
                |                       |
                +-----------+-----------+
                            |
                            v
                     Updated artifacts
```

Với project C:

```text
Headers / Sources
       |
       | dependency information
       v
Object targets
       |
       | dependency graph
       v
Executable / Library targets
```

Với cross-compilation:

```text
Make dependency graph
       |
       | CC/AR/... variables
       v
Cross toolchain
       |
       | target ABI + sysroot
       v
Target ELF / library
```

### 16.2 Các phân biệt cần nhớ

```text
Make                      != Compiler
Make                      != Linker
Make                      != Shell
Makefile                  != Shell script
Target                    != Luôn luôn là file
Prerequisite              != Recipe
Dependency                != Thứ tự dòng trong Makefile
Recipe                    != Dependency graph
Goal                      != Tất cả target trong Makefile
Target tồn tại            != Chắc chắn up-to-date
Timestamp mới hơn         != Nội dung chắc chắn khác
Variable Make             != Environment variable
Make expansion            != Shell expansion
`$@`                      != Shell variable `$@` theo cùng nghĩa
Pattern `%`               != Shell wildcard
Pattern rule              != Built-in implicit rule
`.PHONY`                  != File target bình thường
Header include            != Make tự động biết dependency
`.o`                      != `.d`
Normal prerequisite       != Order-only prerequisite
Serial build chạy đúng    != Dependency graph chắc chắn đúng
`CROSS_COMPILE`           != GNU Make keyword built-in
`ARCH`                    != GNU Make tự hiểu kiến trúc
Make                      != Sysroot
Make                      != Toàn bộ Embedded Linux build system
```

### 16.3 Các điểm cốt lõi

1.  GNU Make là công cụ xử lý dependency graph và thực thi recipe cần thiết, không phải compiler hay linker.
2.  Rule cơ bản gồm `target`, `prerequisite` và `recipe`; `goal` là target mà Make được yêu cầu cập nhật.
3.  Với file target thông thường, Make chủ yếu dựa vào sự tồn tại và modification timestamp để xác định target có out-of-date hay không.
4.  Incremental build chỉ chính xác khi dependency graph chính xác; thiếu dependency có thể tạo stale artifact.
5.  Recipe thường được Make expand rồi chuyển cho shell; Make syntax và shell syntax là hai lớp khác nhau.
6.  Mỗi recipe line mặc định thường chạy trong shell riêng, nên shell state không tự động tồn tại qua nhiều dòng.
7.  Variable `=`, `:=`, `?=`, `+=` có semantics khác nhau; thời điểm expansion ảnh hưởng trực tiếp tới kết quả Makefile.
8.  `CC`, `CPPFLAGS`, `CFLAGS`, `LDFLAGS`, `LDLIBS`, `AR` là các convention quan trọng giúp phản ánh đúng pipeline compile/link.
9.  Automatic variable như `$@`, `$<`, `$^` cho phép viết recipe tổng quát theo rule context.
10. Pattern rule mô tả một họ target/prerequisite; implicit rule là rule Make có thể tự tìm từ built-in database hoặc rule được định nghĩa gián tiếp.
11. `.PHONY` dùng cho target mang ý nghĩa action/aggregation thay vì file artifact.
12. Header dependency cần được đưa vào graph; GCC có thể sinh `.d` bằng các option như `-MMD`, và Make có thể include dependency file này.
13. Order-only prerequisite biểu diễn điều kiện phải sẵn sàng trước nhưng không nên làm target rebuild chỉ vì timestamp của prerequisite mới hơn.
14. Parallel build không sửa graph; nó làm lộ rõ missing dependency/race vốn có trong Makefile.
15. Khi debug, cần phân biệt lỗi parser/graph/variable/rule của Make với lỗi compiler/linker/shell bên trong recipe.
16. Trong cross-compilation, Make chỉ tổ chức command; tính đúng đắn của target binary vẫn phụ thuộc cross toolchain, ABI, sysroot và target libraries.
17. `CROSS_COMPILE` và `ARCH` là convention của project phổ biến trong Embedded Linux, không phải khái niệm tự động của GNU Make.

---

## 17. Tài liệu tham khảo

### 17.1 GNU Make — tài liệu chính thức

1. GNU Project — **GNU Make Manual**
   <https://www.gnu.org/software/make/manual/>

2. GNU Project — **GNU Make Manual — Introduction / How to Write Makefiles**
   <https://www.gnu.org/software/make/manual/html_node/Introduction.html>

3. GNU Project — **GNU Make Manual — Writing Rules**
   <https://www.gnu.org/software/make/manual/html_node/Rules.html>

4. GNU Project — **GNU Make Manual — Phony Targets**
   <https://www.gnu.org/software/make/manual/html_node/Phony-Targets.html>

5. GNU Project — **GNU Make Manual — Variables**
   <https://www.gnu.org/software/make/manual/html_node/Using-Variables.html>

6. GNU Project — **GNU Make Manual — Automatic Variables**
   <https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html>

7. GNU Project — **GNU Make Manual — Pattern Rules / Implicit Rules**
   <https://www.gnu.org/software/make/manual/html_node/Pattern-Rules.html>

8. GNU Project — **GNU Make Manual — Parallel Execution**
   <https://www.gnu.org/software/make/manual/html_node/Parallel.html>

9. GNU Project — **GNU Make Manual — Order-Only Prerequisites**
   <https://www.gnu.org/software/make/manual/html_node/Prerequisite-Types.html>

### 17.2 GCC — dependency generation

10. GNU Project — **Using the GNU Compiler Collection — Preprocessor Options** (`-M`, `-MD`, `-MMD`, `-MF`, `-MP`, `-MT`, `-MQ`)
    <https://gcc.gnu.org/onlinedocs/gcc/Preprocessor-Options.html>

11. GNU Project — **Using the GNU Compiler Collection — Option Summary**
    <https://gcc.gnu.org/onlinedocs/gcc/Option-Summary.html>

### 17.3 Makefile conventions

12. GNU Project — **GNU Coding Standards — Makefile Conventions**
    <https://www.gnu.org/prep/standards/html_node/Makefile-Conventions.html>

### 17.4 Tài liệu nền tảng

13. Robert Mecklenburg — **Managing Projects with GNU Make** — O'Reilly.

14. GNU Make source/documentation — dùng khi cần tra cứu behavior chi tiết của built-in rules, variable expansion và dependency update semantics.

> **Điều hướng:** [← Chủ đề 3 — Static & Dynamic Library](README-topic-03.md) · [Chủ đề 5 — CMake Fundamentals →](README-topic-05.md)
