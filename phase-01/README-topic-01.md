# Chủ đề 1 — Basic Linux Command Line

> **Phạm vi:** HOST — Ubuntu Laptop/PC  
>
> Chương này xây nền tảng làm việc với Linux bằng command line. Mục tiêu không phải học thuộc càng nhiều lệnh càng tốt, mà là hiểu **shell nhận lệnh như thế nào, command được tìm và thực thi ra sao, dữ liệu đi qua stdin/stdout/stderr như thế nào, và vì sao pipeline/redirection là nền tảng của cách làm việc trên Linux**.
>
> Sau chương này, người học phải có thể thao tác bằng terminal, đọc hiểu một command line, kết hợp các utility nhỏ thành pipeline, kiểm tra exit status, và viết một Bash script đơn giản để tự động hóa thao tác lặp lại.

> **Điều hướng:** [← Root README](README.md) · [Chủ đề 2 — Linux File System →](README-topic-02.md)

---

## Mục lục

> Mục lục rút gọn theo cụm kiến thức. Các mục đánh số chi tiết vẫn được giữ nguyên trong nội dung.

- **Command-line mental model**
  - [1. Terminal, shell và command là ba khái niệm khác nhau](#1-terminal-shell-và-command-là-ba-khái-niệm-khác-nhau)
  - [2. Shell xử lý một command line như thế nào?](#2-shell-xử-lý-một-command-line-như-thế-nào)
  - [3. Command, argument và option](#3-command-argument-và-option)
  - [4. Builtin và external command](#4-builtin-và-external-command)
  - [5. PATH và command lookup](#5-path-và-command-lookup)
- **Navigation & basic utilities**
  - [6. Current working directory và path](#6-current-working-directory-và-path)
  - [7. Nhóm lệnh thao tác thư mục và file cơ bản](#7-nhóm-lệnh-thao-tác-thư-mục-và-file-cơ-bản)
  - [8. Nhóm lệnh quan sát nội dung text](#8-nhóm-lệnh-quan-sát-nội-dung-text)
  - [9. Tìm kiếm bằng grep và find](#9-tìm-kiếm-bằng-grep-và-find)
  - [10. Quan sát process và tài nguyên hệ thống](#10-quan-sát-process-và-tài-nguyên-hệ-thống)
- **Data flow**
  - [11. stdin, stdout và stderr](#11-stdin-stdout-và-stderr)
  - [12. Redirection](#12-redirection)
  - [13. Pipeline](#13-pipeline)
  - [14. Quoting, globbing và expansion cơ bản](#14-quoting-globbing-và-expansion-cơ-bản)
  - [15. Exit status và command chaining](#15-exit-status-và-command-chaining)
- **Automation & debugging**
  - [16. Bash script tối thiểu](#16-bash-script-tối-thiểu)
  - [17. Thực hành tổng hợp trên HOST](#17-thực-hành-tổng-hợp-trên-host)
  - [18. Failure modes và cách debug command line](#18-failure-modes-và-cách-debug-command-line)
  - [19. Mô hình tư duy tổng hợp](#19-mô-hình-tư-duy-tổng-hợp)
  - [20. Các nguyên tắc cốt lõi](#20-các-nguyên-tắc-cốt-lõi)
- [Tài liệu tham khảo](#tài-liệu-tham-khảo)

---

# 1. Terminal, shell và command là ba khái niệm khác nhau

Khi mới học Linux, ba khái niệm này thường bị gọi chung là "terminal". Về bản chất chúng là ba lớp khác nhau.

```text
+--------------------------------------------------+
| Terminal emulator                                |
| gnome-terminal / Konsole / xterm / ...           |
|                                                  |
| Hiển thị text và truyền keyboard input           |
+----------------------------+---------------------+
                             |
                             v
+--------------------------------------------------+
| Shell                                            |
| bash / zsh / dash / ...                          |
|                                                  |
| Đọc, parse và thực thi command line              |
+----------------------------+---------------------+
                             |
                             v
+--------------------------------------------------+
| Command / Program                                |
| ls / grep / ps / gcc / application tự viết      |
+--------------------------------------------------+
```

## 1.1 Terminal

Terminal emulator là chương trình cung cấp giao diện text để người dùng tương tác với shell.

Nó chịu trách nhiệm những việc như:

- hiển thị ký tự;
- nhận input từ bàn phím;
- hỗ trợ scrollback;
- quản lý tab/window;
- kết nối shell với pseudo-terminal.

Terminal **không tự hiểu** ý nghĩa của:

```bash
ls -l
```

Việc phân tích command line thuộc về shell.

---

## 1.2 Shell

GNU Bash mô tả shell là một **command language interpreter**. Shell có thể chạy ở:

```text
Interactive mode
    |
    +--> người dùng nhập command từ terminal

Non-interactive mode
    |
    +--> shell đọc command từ script/file/string
```

Shell không chỉ chạy chương trình. Nó còn thực hiện:

- parsing;
- variable expansion;
- wildcard expansion;
- redirection;
- pipeline;
- conditional;
- loop;
- function;
- environment handling.

Vì vậy:

```bash
ls *.c > files.txt
```

không phải toàn bộ công việc của `ls`.

Shell phải xử lý:

```text
*.c
 >
files.txt
```

trước hoặc trong quá trình chuẩn bị chạy chương trình.

---

## 1.3 Command

Một command có thể là:

```text
shell builtin
external executable
shell function
alias
script
```

Ví dụ:

```bash
cd /tmp
```

`cd` thường là shell builtin.

Trong khi:

```bash
/usr/bin/grep
```

là executable bên ngoài shell.

Mental model cần nhớ:

```text
Terminal
   ↓
Shell
   ↓
Parse command
   ↓
Resolve command
   ↓
Execute builtin hoặc program
   ↓
Collect exit status
   ↓
Hiển thị output / tiếp tục pipeline
```

---

# 2. Shell xử lý một command line như thế nào?

GNU Bash mô tả quá trình xử lý command theo các bước logic gồm:

1. đọc input;
2. tách input thành words/operators;
3. parse thành command;
4. thực hiện shell expansion;
5. thiết lập redirection;
6. thực thi command;
7. thu exit status.

Có thể hình dung:

```text
User input
   |
   v
"grep -i error *.log > errors.txt"
   |
   v
Tokenization / parsing
   |
   +--> command = grep
   +--> option  = -i
   +--> arg     = error
   +--> pattern = *.log
   +--> redirect stdout -> errors.txt
   |
   v
Expansion
   |
   +--> *.log -> app.log kernel.log ...
   |
   v
Command lookup
   |
   v
Execute grep
   |
   v
stdout redirected to errors.txt
   |
   v
Exit status
```

Điểm quan trọng:

> Shell không đơn giản "gửi nguyên chuỗi" cho chương trình.

Một số ký tự như:

```text
|
>
<
*
$
"
'
;
&
```

có ý nghĩa với shell và có thể được xử lý trước khi chương trình nhận argument.

---

# 3. Command, argument và option

Một simple command thường có dạng:

```text
command [options] [arguments]
```

Ví dụ:

```bash
ls -l /etc
```

Ta có:

```text
command   = ls
option    = -l
argument  = /etc
```

Một ví dụ khác:

```bash
grep -n "error" app.log
```

```text
command   = grep
option    = -n
pattern   = error
file      = app.log
```

## 3.1 Short option

Thường có dạng:

```bash
-l
-a
-r
```

Nhiều GNU utility cho phép gộp:

```bash
ls -la
```

tương đương về ý nghĩa với:

```bash
ls -l -a
```

trong trường hợp các option đó không cần argument riêng.

---

## 3.2 Long option

GNU utilities thường hỗ trợ dạng dễ đọc hơn:

```bash
ls --all
rm --interactive
grep --ignore-case
```

Không phải mọi program đều tuân cùng một convention, vì vậy không nên đoán option.

Tra cứu bằng:

```bash
command --help
```

hoặc:

```bash
man command
```

Ví dụ:

```bash
man grep
man ps
man mount
```

---

# 4. Builtin và external command

Đây là distinction quan trọng khi hiểu shell.

## 4.1 Shell builtin

Một số command phải thao tác trực tiếp với trạng thái của shell hiện tại.

Ví dụ:

```bash
cd /tmp
```

Nếu `cd` chỉ chạy trong một process con:

```text
shell
  |
  +--> child process changes directory
  |
child exits
  |
shell vẫn ở directory cũ
```

thì command không có tác dụng mong muốn.

Vì vậy `cd` được thực hiện trong shell.

Các builtin thường gặp:

```text
cd
echo
printf
read
export
unset
alias
history
jobs
fg
bg
```

Danh sách thực tế phụ thuộc shell.

---

## 4.2 External command

External command là executable nằm trong filesystem.

Ví dụ trên Ubuntu:

```bash
command -v grep
command -v ls
command -v ps
```

Có thể cho kết quả tương tự:

```text
/usr/bin/grep
/usr/bin/ls
/usr/bin/ps
```

Không nên hard-code đường dẫn nếu không có lý do cụ thể.

---

## 4.3 Kiểm tra command thuộc loại nào

Dùng:

```bash
type cd
type ls
type grep
```

hoặc:

```bash
command -V cd
command -V grep
```

Mental model:

```text
command name
    |
    v
Shell resolution
    |
    +--> alias?
    +--> function?
    +--> builtin?
    +--> executable trong PATH?
    |
    v
Execute
```

---

# 5. PATH và command lookup

Khi nhập:

```bash
grep
```

shell phải tìm executable tương ứng.

Biến môi trường `PATH` chứa danh sách directory dùng cho command search.

Kiểm tra:

```bash
echo "$PATH"
```

Ví dụ cấu trúc:

```text
/usr/local/sbin
/usr/local/bin
/usr/sbin
/usr/bin
/sbin
/bin
```

Các directory được phân tách bằng dấu `:`.

Mental model:

```text
grep
 |
 v
Search PATH từ trái sang phải
 |
 +--> /usr/local/sbin/grep ?
 +--> /usr/local/bin/grep ?
 +--> /usr/sbin/grep ?
 +--> /usr/bin/grep ?  ---> found
 |
 v
execute
```

## 5.1 Tìm executable

```bash
command -v grep
```

Nên ưu tiên `command -v` khi muốn kiểm tra command resolution trong shell script.

---

## 5.2 Vì sao `./app` thường cần `./`?

Giả sử có executable:

```text
/home/user/project/app
```

và current directory là:

```text
/home/user/project
```

Nhập:

```bash
app
```

chỉ hoạt động nếu directory hiện tại nằm trong `PATH`.

Thông thường current directory không mặc định nằm trong `PATH`.

Vì vậy dùng:

```bash
./app
```

Ý nghĩa:

```text
.
|
+--> current directory

./app
|
+--> executable "app" trong current directory
```

Điều này tránh việc shell vô tình chạy một executable không đáng tin chỉ vì nó nằm trong directory hiện tại.

---

# 6. Current working directory và path

Mỗi process có khái niệm **current working directory**.

Shell cũng là một process, nên shell có working directory của riêng nó.

Kiểm tra:

```bash
pwd
```

Ví dụ:

```text
/home/hai
```

## 6.1 Absolute path

Absolute path bắt đầu từ root `/`.

```text
/home/hai/project/main.c
/etc/passwd
/usr/bin/grep
```

Ưu điểm:

- không phụ thuộc current directory;
- rõ ràng trong script/config.

---

## 6.2 Relative path

Relative path được resolve từ current working directory.

Ví dụ:

```bash
cd /home/hai
cat project/README.md
```

`project/README.md` tương đương:

```text
/home/hai/project/README.md
```

trong context đó.

---

## 6.3 `.` và `..`

```text
.   current directory
..  parent directory
```

Ví dụ:

```bash
cd ..
```

hoặc:

```bash
./app
```

---

## 6.4 Home directory

Trong shell:

```bash
cd ~
```

hoặc đơn giản:

```bash
cd
```

thường đưa user về home directory.

Kiểm tra:

```bash
echo "$HOME"
```

---

# 7. Nhóm lệnh thao tác thư mục và file cơ bản

Phần này chỉ tập trung vào **thao tác cơ bản**. Cấu trúc filesystem, inode, permission, hard link, symbolic link và device file sẽ được học sâu ở Topic 2.

---

## 7.1 `pwd` — xác định vị trí hiện tại

```bash
pwd
```

Mental model:

```text
shell process
    |
    +--> current working directory
              |
              v
             pwd
```

Đây nên là command đầu tiên khi bạn không chắc mình đang thao tác ở đâu.

---

## 7.2 `ls` — quan sát directory

```bash
ls
```

Một số dạng thường dùng:

```bash
ls -l
ls -a
ls -la
ls -lh
```

Ý nghĩa khái quát:

```text
-l  long listing
-a  hiển thị cả entry bắt đầu bằng .
-h  human-readable size khi kết hợp option phù hợp
```

GNU Coreutils lưu ý rằng khi không truyền argument, `ls` thao tác trên current directory.

---

## 7.3 `cd` — thay đổi current directory

```bash
cd /etc
cd ..
cd ~
cd -
```

`cd -` thường quay lại previous working directory trong Bash.

Sau khi `cd`, nên xác nhận bằng:

```bash
pwd
```

khi đang thực hiện thao tác nhạy cảm.

---

## 7.4 `mkdir` — tạo directory

```bash
mkdir logs
```

Tạo cả parent directory khi cần:

```bash
mkdir -p build/output/logs
```

---

## 7.5 `touch`

Một cách dùng phổ biến:

```bash
touch notes.txt
```

Nếu file chưa tồn tại, file regular trống có thể được tạo.

Nếu file đã tồn tại, `touch` chủ yếu cập nhật timestamp theo option/default behavior.

Không nên hiểu `touch` đơn giản là "lệnh tạo file"; bản chất utility này liên quan đến timestamp.

---

## 7.6 `cp` — copy

```bash
cp source.txt backup.txt
```

Copy vào directory:

```bash
cp source.txt backup/
```

Copy directory recursively:

```bash
cp -r config/ backup/
```

Mental model:

```text
source
  |
  | read
  v
cp
  |
  | create/write
  v
destination
```

Copy tạo destination độc lập về nội dung; không phải alias tới source.

---

## 7.7 `mv` — move hoặc rename

Rename:

```bash
mv old.txt new.txt
```

Move:

```bash
mv app.log logs/
```

Một nuance quan trọng:

- trong cùng filesystem, `mv` thường có thể thực hiện rename;
- qua filesystem khác, implementation có thể cần copy rồi xóa source.

Không nên mặc định rằng mọi `mv` đều chỉ thay đổi tên entry.

---

## 7.8 `rm` — remove

```bash
rm file.txt
```

Remove directory tree:

```bash
rm -r directory/
```

Khi học và thực hành, có thể dùng:

```bash
rm -i file.txt
```

để được hỏi xác nhận.

Điểm quan trọng:

> `rm` không có khái niệm "Recycle Bin" như GUI desktop theo mặc định.

Do đó trước lệnh recursive, nên kiểm tra:

```bash
pwd
ls
```

và xác minh argument.

---

# 8. Nhóm lệnh quan sát nội dung text

Linux command line mạnh vì rất nhiều utility có thể:

```text
read text
   ↓
transform/filter
   ↓
write text
```

Điều này làm chúng dễ nối bằng pipe.

---

## 8.1 `cat`

```bash
cat file.txt
```

`cat` đọc file và ghi nội dung ra standard output.

Nó đặc biệt hữu ích khi:

- file nhỏ;
- cần nối nhiều file;
- cần feed nội dung vào pipeline.

Ví dụ:

```bash
cat part1.txt part2.txt
```

---

## 8.2 `head`

Mặc định GNU `head` in phần đầu của input.

```bash
head file.txt
```

Ví dụ:

```bash
head -n 20 file.txt
```

---

## 8.3 `tail`

```bash
tail file.txt
```

Theo dõi file tăng liên tục:

```bash
tail -f app.log
```

Đây là pattern rất thường dùng khi debug log userspace.

---

## 8.4 `wc`

```bash
wc file.txt
```

Các dạng thường gặp:

```bash
wc -l file.txt
wc -w file.txt
wc -c file.txt
```

Trong pipeline:

```bash
grep "error" app.log | wc -l
```

Mental model:

```text
app.log
   |
   v
grep "error"
   |
matching lines
   |
   v
wc -l
   |
count
```

---

# 9. Tìm kiếm bằng grep và find

Hai command này giải quyết hai bài toán khác nhau.

```text
grep
 |
 +--> tìm pattern trong nội dung text

find
 |
 +--> tìm filesystem object theo điều kiện
```

---

## 9.1 `grep`

GNU grep có nhiệm vụ chính là tìm các line match pattern.

Ví dụ:

```bash
grep "error" app.log
```

Không phân biệt hoa/thường:

```bash
grep -i "error" app.log
```

Hiển thị line number:

```bash
grep -n "error" app.log
```

Recursive search:

```bash
grep -R "CONFIG_UART" .
```

Một pattern rất hữu ích khi đọc source tree:

```bash
grep -R -n "function_name" src/
```

---

## 9.2 `find`

`find` duyệt filesystem tree và chọn entry theo expression.

Theo tên:

```bash
find . -name "*.c"
```

Theo loại:

```bash
find . -type f
find . -type d
```

Theo tên không phân biệt hoa/thường:

```bash
find . -iname "readme*"
```

Một khác biệt quan trọng:

```bash
grep -R "UART" .
```

tìm **text `UART` bên trong file**.

Trong khi:

```bash
find . -name "*uart*"
```

tìm **tên filesystem entry**.

---

# 10. Quan sát process và tài nguyên hệ thống

Topic Process sau này sẽ đi sâu `fork`, `exec`, PID, state và lifecycle. Ở Topic 1 chỉ cần biết cách quan sát hệ thống.

---

## 10.1 `ps`

`ps` hiển thị snapshot thông tin process.

Các cách dùng phổ biến:

```bash
ps
ps -ef
ps aux
```

Lưu ý:

`ps` hỗ trợ nhiều style option khác nhau do lịch sử UNIX/BSD/GNU. Vì vậy:

```text
ps -ef
```

và:

```text
ps aux
```

không đơn giản là cùng một syntax convention.

Khi cần chính xác:

```bash
man ps
```

---

## 10.2 `top`

`top` cung cấp view động về process và tài nguyên.

```bash
top
```

Có thể quan sát:

- CPU usage;
- memory;
- load;
- process;
- PID;
- state;
- command.

Khác với `ps`:

```text
ps   -> snapshot

top  -> interactive / periodically updated view
```

---

## 10.3 `df`

GNU `df` báo cáo dung lượng đã dùng và còn khả dụng theo filesystem.

```bash
df
df -h
```

Mental model:

```text
filesystem
   |
   +--> capacity
   +--> used
   +--> available
   +--> mount point
```

---

## 10.4 `du`

`du` ước lượng space usage của file/directory tree.

```bash
du -sh .
du -sh *
```

Phân biệt:

```text
df
 |
 +--> nhìn từ filesystem

du
 |
 +--> nhìn từ file/directory tree
```

Vì hai công cụ đo ở hai abstraction khác nhau, kết quả không phải lúc nào cũng trùng trực tiếp.

---

## 10.5 `mount`

Ở mức Topic 1, cần hiểu `mount` là thao tác gắn một filesystem vào namespace/tree để truy cập qua một mount point.

Xem mount hiện tại:

```bash
mount
```

hoặc:

```bash
findmnt
```

Ví dụ khái niệm:

```text
block device / filesystem
        |
        v
mount operation
        |
        v
/mnt/data
        |
        v
accessible through filesystem tree
```

Chi tiết filesystem, VFS và mount sẽ được đào sâu ở các topic sau.

---

# 11. stdin, stdout và stderr

Đây là phần quan trọng nhất của Topic 1.

Một process command-line thường bắt đầu với ba standard file descriptor:

```text
fd 0 -> stdin
fd 1 -> stdout
fd 2 -> stderr
```

Mental model:

```text
                 +----------------------+
stdin (fd 0) --->|      Program         |---> stdout (fd 1)
                 |                      |
                 +----------------------+---> stderr (fd 2)
```

Thông thường khi chạy từ terminal:

```text
stdin  <- terminal keyboard
stdout -> terminal
stderr -> terminal
```

Nhưng shell có thể thay đổi các connection này bằng redirection và pipe.

---

## 11.1 Vì sao stdout và stderr tách riêng?

Giả sử program:

```text
kết quả hợp lệ   -> stdout
diagnostic/error -> stderr
```

Nhờ tách riêng, ta có thể:

```bash
command > result.txt
```

mà diagnostic vẫn xuất hiện trên terminal.

Hoặc:

```bash
command 2> error.log
```

để giữ riêng lỗi.

Đây là một design cực kỳ quan trọng cho automation.

---

# 12. Redirection

Bash thực hiện redirection **trước khi command được chạy** theo command execution flow.

---

## 12.1 Redirect stdout

```bash
command > output.txt
```

Mental model:

```text
Before:

program stdout ---> terminal

After:

program stdout ---> output.txt
```

`>` tạo file nếu chưa có và thường truncate file hiện có.

---

## 12.2 Append stdout

```bash
command >> output.txt
```

Khác với `>`:

```text
>   replace/truncate output file
>>  append to end
```

---

## 12.3 Redirect stdin

```bash
command < input.txt
```

Mental model:

```text
input.txt
   |
   v
stdin
   |
   v
program
```

Ví dụ:

```bash
wc -l < file.txt
```

---

## 12.4 Redirect stderr

```bash
command 2> error.log
```

Giải thích:

```text
2
|
+--> stderr file descriptor
```

---

## 12.5 Redirect stdout và stderr cùng file

```bash
command > all.log 2>&1
```

Bash xử lý redirection từ trái sang phải.

Vì vậy thứ tự có ý nghĩa.

Concept:

```text
> all.log
 |
 +--> stdout -> all.log

2>&1
 |
 +--> stderr -> nơi stdout đang trỏ
```

Bash cũng hỗ trợ cú pháp:

```bash
command &> all.log
```

nhưng khi học file descriptor, dạng:

```bash
> all.log 2>&1
```

giúp nhìn rõ cơ chế hơn.

---

# 13. Pipeline

Theo Bash, pipeline là chuỗi command nối bởi `|` hoặc `|&`.

Dạng cơ bản:

```bash
command1 | command2
```

Ý nghĩa:

```text
command1 stdout
        |
        v
      pipe
        |
        v
command2 stdin
```

Ví dụ:

```bash
ps aux | grep ssh
```

Không nên hiểu pipe là:

> "chạy command 1 xong, copy text rồi đưa sang command 2".

Ở mức OS, pipe là cơ chế IPC dạng byte stream. Shell thiết lập pipe và nối file descriptor giữa các process.

Mental model:

```text
       stdout                    stdin
[ process A ] -----> [ pipe ] -----> [ process B ]
```

---

## 13.1 Pipeline nhiều stage

```bash
ps aux | grep python | wc -l
```

Data flow:

```text
ps aux
   |
   v
process list
   |
   v
grep python
   |
   v
matching lines
   |
   v
wc -l
   |
   v
count
```

Đây là tinh thần "small tools composed together":

```text
generate
  ↓
filter
  ↓
transform
  ↓
summarize
```

---

## 13.2 `|` chỉ nối stdout mặc định

Giả sử:

```text
command1:
stdout = data
stderr = error
```

Với:

```bash
command1 | command2
```

mặc định:

```text
stdout -> pipe -> command2

stderr -> terminal
```

Nếu muốn cả stderr đi qua pipeline, Bash hỗ trợ:

```bash
command1 |& command2
```

`|&` tương đương về ý nghĩa với việc đưa stderr vào stdout rồi pipe trong context Bash.

---

# 14. Quoting, globbing và expansion cơ bản

Đây là phần dễ gây bug nhất khi viết command và shell script.

---

## 14.1 Globbing

Ví dụ:

```bash
ls *.c
```

Thông thường `*.c` được shell expand thành danh sách filename trước khi `ls` chạy.

Giả sử directory có:

```text
main.c
uart.c
gpio.c
```

Shell có thể biến command logic thành:

```bash
ls gpio.c main.c uart.c
```

`ls` không nhất thiết tự xử lý `*.c`.

---

## 14.2 Single quote

```bash
echo '$HOME'
```

Single quote giữ nội dung literal mạnh hơn.

Output:

```text
$HOME
```

---

## 14.3 Double quote

```bash
echo "$HOME"
```

Variable expansion vẫn xảy ra.

Output có thể là:

```text
/home/hai
```

Quy tắc thực tế rất quan trọng:

> Khi dùng variable chứa path/string, mặc định nên quote bằng `"` nếu không có lý do rõ ràng để word splitting/globbing xảy ra.

Ví dụ:

```bash
file="my notes.txt"
cat "$file"
```

Tốt hơn:

```bash
cat $file
```

vì dạng sau có thể bị shell tách thành hai argument.

---

## 14.4 Variable expansion

```bash
name="embedded-linux"
echo "$name"
```

Shell thay:

```text
$name
```

bằng value trước khi command nhận argument.

---

## 14.5 Command substitution

```bash
kernel=$(uname -r)
echo "$kernel"
```

Mental model:

```text
uname -r
   |
stdout
   |
   v
command substitution
   |
   v
value assigned to kernel
```

Không cần dùng command substitution cho mọi thứ; nó chỉ cần khi output của một command trở thành dữ liệu trong command expression khác.

---

# 15. Exit status và command chaining

Mỗi command khi kết thúc trả một **exit status** cho shell.

Theo convention phổ biến:

```text
0       success
nonzero failure / other status
```

Kiểm tra status của command gần nhất:

```bash
echo $?
```

Ví dụ:

```bash
ls /etc
echo $?
```

Sau đó thử:

```bash
ls /path/does/not/exist
echo $?
```

---

## 15.1 `&&`

```bash
command1 && command2
```

`command2` chỉ chạy khi `command1` thành công theo exit status.

Ví dụ:

```bash
mkdir build && cd build
```

Mental model:

```text
command1
   |
exit == 0 ?
   |
   +-- yes --> command2
   |
   +-- no  --> stop chain
```

---

## 15.2 `||`

```bash
command1 || command2
```

`command2` chạy khi `command1` không thành công.

Ví dụ:

```bash
test -f config.ini || echo "config.ini not found"
```

---

## 15.3 `;`

```bash
command1 ; command2
```

Hai command được chạy tuần tự theo list syntax, không dùng success của command trước làm điều kiện như `&&`.

---

## 15.4 Vì sao exit status quan trọng?

Automation cần machine-readable result.

Human-readable text:

```text
Build completed successfully
```

không phải interface tốt để shell quyết định flow.

Exit status cho phép:

```bash
make && ./test_app
```

Nếu build fail:

```text
make exit != 0
      |
      v
test_app không chạy
```

Đây là một pattern quan trọng trong build/test script sau này.

---

# 16. Bash script tối thiểu

Shell script là tập command được shell đọc từ file.

Ví dụ:

```bash
#!/usr/bin/env bash

echo "Embedded Linux host check"
pwd
uname -a
```

Lưu file:

```text
host-check.sh
```

Cho phép execute:

```bash
chmod +x host-check.sh
```

Chạy:

```bash
./host-check.sh
```

---

## 16.1 Shebang

Dòng:

```bash
#!/usr/bin/env bash
```

chỉ ra interpreter mong muốn khi kernel/user-space execution path xử lý script executable.

Trong môi trường học tập, cách này giúp dùng Bash được tìm qua environment.

---

## 16.2 Variable

```bash
project="embedded-linux"
echo "$project"
```

Không có space quanh `=`:

```bash
project = "embedded-linux"
```

không phải variable assignment hợp lệ theo syntax Bash thông thường.

---

## 16.3 Positional parameter

Script:

```bash
#!/usr/bin/env bash

echo "Script: $0"
echo "Arg 1: $1"
echo "Arg 2: $2"
```

Chạy:

```bash
./args.sh hello linux
```

Mental model:

```text
$0 -> script invocation name
$1 -> hello
$2 -> linux
```

---

## 16.4 `if`

Ví dụ:

```bash
#!/usr/bin/env bash

if command -v gcc >/dev/null 2>&1; then
    echo "gcc is available"
else
    echo "gcc is not available"
fi
```

Điểm đáng chú ý:

```text
if
 |
 +--> dựa vào exit status của command
```

Shell conditional gắn rất chặt với exit status.

---

## 16.5 Loop cơ bản

```bash
#!/usr/bin/env bash

for file in *.c; do
    echo "$file"
done
```

Không cần học shell programming quá sâu ở Topic 1.

Mục tiêu chỉ là:

```text
repeatable command sequence
        ↓
script
        ↓
reproducible operation
```

---

# 17. Thực hành tổng hợp trên HOST

> **Môi trường:** HOST — Ubuntu Laptop/PC  
>
> Không cần BeagleBone Black ở Topic 1.

---

## Lab 1 — Xác định shell và command resolution

Chạy:

```bash
echo "$SHELL"
ps -p $$ -o pid,ppid,comm,args
type cd
type ls
type grep
command -v ls
command -v grep
```

### Cần trả lời được

1. Shell đang chạy là gì?
2. `cd` là builtin hay executable?
3. `grep` được resolve từ đâu?
4. Vì sao `cd` cần là shell builtin?

---

## Lab 2 — Navigation và file operations

Tạo workspace:

```bash
mkdir -p ~/embedded-linux-labs/topic-01
cd ~/embedded-linux-labs/topic-01
pwd
```

Tạo dữ liệu:

```bash
mkdir logs config backup
touch config/app.conf
printf "INFO boot\nERROR uart timeout\nINFO retry\nERROR i2c\n" > logs/app.log
```

Quan sát:

```bash
ls
ls -la
find . -maxdepth 2 -type f
```

Copy và rename:

```bash
cp config/app.conf backup/
mv backup/app.conf backup/app.conf.bak
```

### Cần hiểu

```text
mkdir/touch/cp/mv
```

thay đổi filesystem state.

Trong khi:

```text
pwd/ls/find
```

chủ yếu quan sát state.

---

## Lab 3 — Pipeline

Dùng file:

```text
logs/app.log
```

Chạy:

```bash
cat logs/app.log
grep "ERROR" logs/app.log
grep "ERROR" logs/app.log | wc -l
```

Sau đó:

```bash
cat logs/app.log | grep "ERROR" | wc -l
```

So sánh với:

```bash
grep "ERROR" logs/app.log | wc -l
```

### Câu hỏi

Có cần `cat` trong pipeline thứ hai không?

Không phải lúc nào `cat file | command` cũng sai, nhưng nếu command đã nhận filename trực tiếp thì:

```bash
grep "ERROR" logs/app.log
```

thường đơn giản hơn:

```bash
cat logs/app.log | grep "ERROR"
```

Điều quan trọng là hiểu data flow, không phải học một luật máy móc kiểu "never use cat".

---

## Lab 4 — stdout và stderr

Tạo command success:

```bash
ls /etc > success.txt
```

Kiểm tra:

```bash
head success.txt
```

Tạo command fail:

```bash
ls /path/does/not/exist
```

Redirect stderr:

```bash
ls /path/does/not/exist 2> error.txt
```

Kiểm tra:

```bash
cat error.txt
```

Redirect cả hai:

```bash
ls /etc /path/does/not/exist > all.txt 2>&1
```

### Cần giải thích được

```text
fd 1 = stdout
fd 2 = stderr
```

và vì sao:

```bash
2> error.txt
```

không giống:

```bash
> error.txt
```

---

## Lab 5 — Exit status

Chạy:

```bash
true
echo $?

false
echo $?
```

Sau đó:

```bash
mkdir build && echo "build directory ready"
```

Thử lại:

```bash
mkdir build && echo "created"
```

nếu `build` đã tồn tại và command không thành công theo điều kiện mặc định, quan sát behavior.

Thử:

```bash
test -f logs/app.log && echo "log exists"
test -f missing.log || echo "missing.log does not exist"
```

---

## Lab 6 — Process observation

Mở một terminal:

```bash
sleep 300
```

Mở terminal khác:

```bash
ps aux | grep sleep
```

hoặc:

```bash
pgrep -a sleep
```

Quan sát:

```bash
top
```

### Cần trả lời

- PID của `sleep` là gì?
- `ps` và `top` khác nhau ở đâu?
- command `sleep` có phải shell builtin trên hệ của bạn không? Kiểm tra bằng `type`.

Sau lab, kết thúc process nếu nó còn chạy.

---

## Lab 7 — Disk observation

Chạy:

```bash
df -h
du -sh ~/embedded-linux-labs
mount | head
```

Nếu có `findmnt`:

```bash
findmnt
```

### Cần phân biệt

```text
df -> filesystem capacity/usage
du -> file tree space usage
mount/findmnt -> filesystem attachment/mount relationships
```

---

## Lab 8 — Bash script

Tạo:

```text
topic01-report.sh
```

Nội dung:

```bash
#!/usr/bin/env bash

echo "=== HOST REPORT ==="
echo "User: $USER"
echo "Home: $HOME"
echo "PWD: $(pwd)"
echo "Kernel: $(uname -r)"
echo

echo "=== DISK ==="
df -h /

echo
echo "=== TOP-LEVEL FILES ==="
find . -maxdepth 1 -type f
```

Cho phép execute:

```bash
chmod +x topic01-report.sh
```

Chạy:

```bash
./topic01-report.sh
```

Redirect report:

```bash
./topic01-report.sh > report.txt
```

Kiểm tra:

```bash
cat report.txt
```

---

# 18. Failure modes và cách debug command line

Không nên debug bằng cách thay command ngẫu nhiên.

Hãy tìm layer đầu tiên bị sai.

---

## 18.1 `command not found`

Ví dụ:

```text
mytool: command not found
```

Causal chain:

```text
command name
    |
    v
shell lookup
    |
    +--> alias/function/builtin?
    |
    +--> PATH search
            |
            +--> executable found? --- no ---> command not found
```

Checklist:

```bash
type mytool
command -v mytool
echo "$PATH"
```

Nếu biết file:

```bash
ls -l ./mytool
file ./mytool
```

Không nên ngay lập tức thêm mọi directory vào `PATH`.

---

## 18.2 `Permission denied`

Causal possibilities:

```text
file exists
   |
   +--> execute permission?
   |
   +--> directory traversal permission?
   |
   +--> filesystem mounted noexec?
   |
   +--> wrong file/interpreter?
```

Topic 2 sẽ học permission chi tiết.

Ở Topic 1 chỉ cần biết rằng:

```text
file exists
```

không đồng nghĩa:

```text
file executable
```

---

## 18.3 `No such file or directory`

Có thể là:

```text
path sai
current directory sai
file không tồn tại
symlink target không tồn tại
script interpreter trong shebang không tồn tại
dynamic loader không tồn tại
```

Vì vậy message này không phải lúc nào cũng đơn giản là "file bị thiếu".

Basic checks:

```bash
pwd
ls -l
file target
```

---

## 18.4 Pipeline cho kết quả sai

Debug từng stage.

Thay vì:

```bash
producer | grep pattern | wc -l
```

hãy kiểm tra:

```bash
producer
```

sau đó:

```bash
producer | grep pattern
```

rồi mới:

```bash
producer | grep pattern | wc -l
```

Mental model:

```text
Stage A output đúng?
     |
    no -> sửa A
     |
    yes
     v
Stage B nhận đúng input?
     |
    no -> sửa pipe/format/pattern
     |
    yes
     v
Stage C
```

---

## 18.5 Redirection không có output trên terminal

Ví dụ:

```bash
command > output.txt
```

Sau đó terminal im lặng.

Điều này có thể hoàn toàn đúng vì:

```text
stdout
  |
  X terminal
  |
  v
output.txt
```

Kiểm tra:

```bash
cat output.txt
```

---

## 18.6 Variable có space làm command sai

Sai pattern:

```bash
file="my log.txt"
cat $file
```

Shell có thể tạo:

```text
arg1 = my
arg2 = log.txt
```

Đúng:

```bash
cat "$file"
```

Causal chain:

```text
variable expansion
       |
       v
word splitting
       |
       v
argument list thay đổi
       |
       v
command behavior sai
```

Đây là lý do quoting phải được hiểu, không chỉ ghi nhớ.

---

## 18.7 Script chạy tay được nhưng chạy bằng `./script.sh` không được

Kiểm tra:

```text
file exists?
  ↓
execute bit?
  ↓
shebang đúng?
  ↓
interpreter tồn tại?
  ↓
line endings hợp lệ?
```

Commands hỗ trợ:

```bash
ls -l script.sh
head -n 1 script.sh
file script.sh
```

---

# 19. Mô hình tư duy tổng hợp

Một command line Linux có thể nhìn như một **data-flow graph nhỏ**.

Ví dụ:

```bash
find logs -type f | grep '\.log$' | wc -l > count.txt
```

Mental model:

```text
                shell
                  |
        parse / expand / redirect
                  |
                  v
+------+       pipe       +------+       pipe       +------+
| find | ---------------->| grep | ---------------->|  wc  |
+------+                   +------+                   +--+---+
                                                         |
                                                         | stdout
                                                         v
                                                    count.txt
```

Tách theo trách nhiệm:

```text
Shell
 |
 +--> parse syntax
 +--> expand expressions
 +--> lookup commands
 +--> create pipe
 +--> configure file descriptors
 +--> execute processes
 +--> track exit status

Programs
 |
 +--> read arguments
 +--> read stdin/file
 +--> perform one focused job
 +--> write stdout/stderr
 +--> return exit status
```

Đây là mental model sẽ lặp lại rất nhiều trong Embedded Linux.

Sau này:

```text
application
   |
   +--> file descriptor
   +--> pipe
   +--> socket
   +--> device node
   +--> sysfs
```

đều tiếp tục dựa trên tư duy "process + file descriptor + byte stream + kernel object".

Topic 1 vì vậy không chỉ là học vài command.

Nó là bước đầu để hiểu cách Linux tổ chức **interaction giữa process và dữ liệu**.

---

# 20. Các nguyên tắc cốt lõi

1. **Terminal không phải shell.** Terminal cung cấp giao diện; shell parse và thực thi command.

2. **Shell không gửi nguyên command line cho program.** Shell có thể expansion, globbing, quoting, pipeline và redirection trước khi program nhận argument.

3. **Command có thể là builtin hoặc external executable.** Hiểu distinction này giúp giải thích `cd`, PATH và command resolution.

4. **PATH là search path, không phải danh sách mọi program trong hệ thống.**

5. **Current working directory là context của process.** Relative path chỉ có nghĩa khi biết context đó.

6. **stdin/stdout/stderr là interface nền tảng của command-line program.**

7. **Redirection thay đổi nơi file descriptor trỏ tới.** Nó không thay đổi logic chính của program.

8. **Pipeline nối stdout của stage trước với stdin của stage sau.**

9. **GNU/Linux command-line tools mạnh nhờ composition.** Một utility nhỏ có thể trở thành stage trong pipeline lớn hơn.

10. **Quote variable khi cần giữ nó là một argument duy nhất.**

11. **Exit status là interface cho automation.** Human-readable output không thay thế exit status.

12. **Khi debug pipeline, kiểm tra từng stage từ trái sang phải.**

13. **Không học thuộc option một cách máy móc.** Dùng `--help`, `man` và tài liệu chính thức để xác nhận behavior.

14. **Topic 1 chỉ xây nền thao tác.** Filesystem internals, permission, inode, process lifecycle và system programming sẽ được tách thành các topic chuyên sâu sau.

---

# Checklist hoàn thành Topic 1

Bạn có thể coi Topic 1 hoàn thành khi tự làm được các việc sau mà không cần copy nguyên command từ tài liệu:

- [ ] Phân biệt terminal, shell và external program.
- [ ] Giải thích được shell xử lý một simple command ở mức khái niệm.
- [ ] Dùng `type` và `command -v` để xác định command.
- [ ] Hiểu `PATH` và vì sao executable local thường chạy bằng `./app`.
- [ ] Di chuyển bằng `pwd`, `cd`, `ls`.
- [ ] Thao tác cơ bản bằng `mkdir`, `cp`, `mv`, `rm`.
- [ ] Quan sát text bằng `cat`, `head`, `tail`, `wc`.
- [ ] Phân biệt `grep` và `find`.
- [ ] Dùng `ps`, `top`, `df`, `du`, `mount/findmnt` ở mức cơ bản.
- [ ] Giải thích được stdin, stdout, stderr và fd 0/1/2.
- [ ] Dùng `>`, `>>`, `<`, `2>` đúng mục đích.
- [ ] Tạo pipeline có ít nhất ba stage.
- [ ] Hiểu cơ bản single quote, double quote, globbing và variable expansion.
- [ ] Kiểm tra exit status bằng `$?`.
- [ ] Dùng `&&` và `||` theo success/failure.
- [ ] Viết và chạy một Bash script đơn giản trên HOST.
- [ ] Debug được `command not found`, sai path, sai quoting hoặc pipeline sai stage.

---

# Tài liệu tham khảo

Các tài liệu dưới đây được ưu tiên vì là tài liệu chính thức hoặc tài liệu reference được cộng đồng Linux sử dụng rộng rãi.

## GNU Bash

- [GNU Bash Reference Manual](https://www.gnu.org/software/bash/manual/)
- [What is a shell? — GNU Bash](https://www.gnu.org/software/bash/manual/html_node/What-is-a-shell_003f.html)
- [Shell Operation — GNU Bash](https://www.gnu.org/software/bash/manual/html_node/Shell-Operation.html)
- [Pipelines — GNU Bash](https://www.gnu.org/software/bash/manual/html_node/Pipelines.html)
- [Redirections — GNU Bash](https://www.gnu.org/software/bash/manual/html_node/Redirections.html)

Các phần này là nguồn chính cho:

```text
shell
command parsing
expansion
pipeline
redirection
exit status
shell scripting
```

## GNU Coreutils

- [GNU Coreutils Manual](https://www.gnu.org/software/coreutils/manual/coreutils.html)

Các utility được dùng trong topic:

```text
pwd
ls
cp
mv
rm
cat
head
tail
wc
df
du
```

## GNU grep

- [GNU Grep Manual](https://www.gnu.org/software/grep/manual/grep.html)

Dùng làm reference cho:

```text
grep
pattern matching
recursive search
exit status của grep
```

## GNU Findutils

- [GNU Findutils Manual](https://www.gnu.org/software/findutils/manual/)

Dùng làm reference cho:

```text
find
filesystem traversal
find expressions
```

## Linux man-pages / util-linux / procps-ng

- [pipe(7) — Linux manual page](https://man7.org/linux/man-pages/man7/pipe.7.html)
- [ps(1) — Linux manual page](https://man7.org/linux/man-pages/man1/ps.1.html)
- [top(1) — Linux manual page](https://man7.org/linux/man-pages/man1/top.1.html)
- [mount(8) — Linux manual page](https://man7.org/linux/man-pages/man8/mount.8.html)

Các reference này hỗ trợ mental model về:

```text
pipe
process observation
interactive process monitoring
filesystem mount
```

## Cách tra cứu khi làm việc thực tế

Trên chính HOST:

```bash
man bash
help cd
man ls
man grep
man find
man ps
man top
man mount
info coreutils
```

Nguyên tắc ưu tiên nguồn:

```text
official project documentation
        ↓
installed man/info pages
        ↓
kernel/man-pages documentation
        ↓
distribution documentation
        ↓
community discussion để tìm case thực tế
        ↓
luôn đối chiếu lại behavior bằng manual/version đang chạy
```

Community Q&A hữu ích để tìm triệu chứng và edge case, nhưng không nên dùng một câu trả lời cộng đồng làm specification nếu manual chính thức đã mô tả behavior.

---

> **Điều hướng:** [← Root README](README.md) · [Chủ đề 2 — Linux File System →](README-topic-02.md)
