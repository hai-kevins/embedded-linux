# Chủ đề 1 — Basic Linux Command Line

> **Phạm vi:** Linux command-line fundamentals — lý thuyết nền tảng cho Embedded Linux.
>
> Chương này tập trung vào **bản chất của môi trường command line trong Linux**: terminal là gì, shell là gì, shell phân tích và thực thi command như thế nào, executable được tìm ra bằng cơ chế nào, dữ liệu đi qua `stdin/stdout/stderr` ra sao, pipeline và redirection thực sự làm gì ở mức process/file descriptor, và vì sao các utility nhỏ có thể ghép lại thành một hệ thống xử lý mạnh.
>
> Mục tiêu của chương không phải học thuộc lệnh. Mục tiêu là hình thành **mental model đúng về command execution trong Linux**, vì các khái niệm này sẽ lặp lại ở system programming, process, IPC, device file, driver, logging, build system và debugging.

> **Điều hướng:** [← Root README](README.md) · [Chủ đề 2 — Linux File System →](README-topic-02.md)

---

## Mục lục

- [1. Command line trong Linux thực chất là gì?](#1-command-line-trong-linux-thực-chất-là-gì)
- [2. Terminal, TTY, pseudo-terminal và shell](#2-terminal-tty-pseudo-terminal-và-shell)
- [3. Shell là một command language interpreter](#3-shell-là-một-command-language-interpreter)
- [4. Cấu trúc của một command line](#4-cấu-trúc-của-một-command-line)
- [5. Quá trình shell xử lý một command](#5-quá-trình-shell-xử-lý-một-command)
- [6. Shell builtin, function và external executable](#6-shell-builtin-function-và-external-executable)
- [7. PATH và cơ chế command lookup](#7-path-và-cơ-chế-command-lookup)
- [8. Current working directory và path resolution](#8-current-working-directory-và-path-resolution)
- [9. Environment và shell variables](#9-environment-và-shell-variables)
- [10. Process model phía sau command line](#10-process-model-phía-sau-command-line)
- [11. Standard file descriptors](#11-standard-file-descriptors)
- [12. Redirection thực chất là gì?](#12-redirection-thực-chất-là-gì)
- [13. Pipeline và Unix process composition](#13-pipeline-và-unix-process-composition)
- [14. Quoting, expansion và globbing](#14-quoting-expansion-và-globbing)
- [15. Exit status và control flow](#15-exit-status-và-control-flow)
- [16. Các utility cơ bản dưới góc nhìn abstraction](#16-các-utility-cơ-bản-dưới-góc-nhìn-abstraction)
- [17. Command line như một data-flow system](#17-command-line-như-một-data-flow-system)
- [18. Error model và tư duy debug](#18-error-model-và-tư-duy-debug)
- [19. Liên hệ với Embedded Linux](#19-liên-hệ-với-embedded-linux)
- [20. Mô hình tư duy tổng hợp](#20-mô-hình-tư-duy-tổng-hợp)
- [21. Các nguyên tắc cốt lõi](#21-các-nguyên-tắc-cốt-lõi)
- [Tài liệu tham khảo](#tài-liệu-tham-khảo)

---

# 1. Command line trong Linux thực chất là gì?

Command line không phải chỉ là một nơi để "gõ lệnh".

Về bản chất, nó là một **môi trường tương tác giữa người dùng và hệ điều hành thông qua một command interpreter**.

Có thể nhìn theo chuỗi abstraction:

```text
User
  ↓
Terminal interface
  ↓
Shell
  ↓
Process creation / builtin execution
  ↓
Kernel
  ↓
Filesystem / device / network / process / memory
```

Ở mức cao, người dùng nhìn thấy:

```text
$ ls -l /etc
```

Nhưng bên dưới, nhiều lớp đang tham gia:

```text
keyboard input
   ↓
terminal / pseudo-terminal
   ↓
shell parser
   ↓
command lookup
   ↓
argument vector creation
   ↓
process execution
   ↓
system calls
   ↓
kernel
   ↓
filesystem objects
   ↓
formatted output
```

Do đó, command line là một **frontend cho process execution và resource interaction**.

Đây là lý do command line rất quan trọng trong Embedded Linux.

Một hệ thống nhúng thường không có:

```text
desktop GUI
window manager
full graphical environment
```

nhưng gần như luôn cần một hoặc nhiều trong số:

```text
serial console
SSH
shell
system log
startup script
service command
debug utility
```

Vì vậy command line không phải công cụ phụ.

Trong Embedded Linux, nó là một trong các giao diện quản trị và debug chính.

---

# 2. Terminal, TTY, pseudo-terminal và shell

Ba khái niệm thường bị gộp lại thành "terminal":

```text
terminal
shell
command
```

Nhưng chúng thuộc các lớp khác nhau.

---

## 2.1 Terminal

Trong lịch sử UNIX, terminal từng là thiết bị vật lý:

```text
keyboard
+
display/printer
+
serial line
```

kết nối tới hệ thống.

Ngày nay, trên desktop Linux, người dùng thường sử dụng **terminal emulator** như:

```text
GNOME Terminal
Konsole
xterm
Alacritty
kitty
```

Terminal emulator cung cấp:

```text
text display
keyboard input
terminal control sequences
window/tab management
pseudo-terminal endpoint
```

Terminal không hiểu bản chất của:

```bash
grep -n error app.log
```

Nó chủ yếu truyền byte input/output giữa người dùng và process phía sau.

---

# 2.2 TTY

`TTY` xuất phát từ "teletypewriter".

Trong Linux, TTY trở thành một abstraction của kernel cho terminal-style I/O.

Mental model:

```text
process
  ↕
TTY subsystem
  ↕
terminal device / serial line / pseudo-terminal
```

TTY layer có thể tham gia các cơ chế như:

```text
line discipline
echo
canonical input
special control characters
terminal settings
```

Ví dụ:

```text
Ctrl+C
Ctrl+D
Backspace behavior
local echo
```

không đơn giản chỉ là "ký tự bình thường".

Chúng có thể được terminal/TTY stack xử lý theo cấu hình hiện tại.

---

# 2.3 Pseudo-terminal

Khi chạy terminal emulator trên desktop, không nhất thiết có hardware terminal thật.

Thay vào đó Linux dùng pseudo-terminal:

```text
PTY master
    ↕
PTY slave
```

Mô hình:

```text
Terminal Emulator
      |
      | PTY master
      v
+------------------+
| Kernel PTY layer |
+------------------+
      ^
      | PTY slave
      |
    Shell
```

Shell thường thấy phía slave như một terminal bình thường.

Terminal emulator điều khiển phía master.

Cơ chế này tạo ảo giác rằng:

```text
shell <-> terminal
```

đang nói chuyện qua terminal vật lý.

---

# 2.4 Serial console trong Embedded Linux

Trong Embedded Linux, terminal abstraction trở nên dễ nhìn hơn.

Ví dụ:

```text
Laptop
  |
USB-UART
  |
SoC UART
  |
/dev/ttySx
  |
kernel console / getty / shell
```

Vì vậy kiến thức command line liên kết trực tiếp với:

```text
UART console
boot log
login shell
debug shell
```

trên board nhúng.

---

# 3. Shell là một command language interpreter

GNU Bash định nghĩa shell như một **command language interpreter**.

Điều này quan trọng vì shell không phải đơn giản là "program chạy program khác".

Shell có cả:

```text
syntax
grammar
variables
expansion
redirection
pipeline
conditional
loop
function
job control
environment handling
```

Do đó shell gần với một **ngôn ngữ lập trình nhỏ chuyên điều phối process và data flow**.

---

# 3.1 Interactive shell

Interactive shell nhận command từ người dùng.

Ví dụ mental model:

```text
prompt
  ↓
user input
  ↓
parse
  ↓
execute
  ↓
wait/result
  ↓
new prompt
```

Prompt như:

```text
$
#
```

không phải kernel prompt.

Nó được shell hiển thị.

---

# 3.2 Non-interactive shell

Shell cũng có thể đọc command từ:

```text
script file
standard input
-c argument
```

Ví dụ architecture:

```text
script.sh
   ↓
bash parser
   ↓
same execution machinery
```

Điểm quan trọng:

> Shell script và interactive command line dùng cùng một nền tảng syntax/execution model.

Khác biệt chính nằm ở:

```text
input source
interactive features
startup behavior
job control
```

---

# 3.3 Login shell và non-login shell

Một shell có thể được khởi tạo ở các mode khác nhau.

Điều này ảnh hưởng đến:

```text
startup files
environment initialization
PATH
aliases
shell options
```

Ví dụ trong Bash, các startup file khác nhau có thể được đọc tùy:

```text
login shell?
interactive?
non-interactive?
```

Đây là lý do đôi khi:

```text
command chạy được trong terminal
```

nhưng:

```text
không chạy trong script/service
```

do environment khác nhau.

---

# 4. Cấu trúc của một command line

Một simple command thường được người dùng nhìn như:

```text
command option argument
```

Ví dụ:

```bash
grep -n "error" app.log
```

Có thể tách:

```text
command  = grep
option   = -n
pattern  = error
operand  = app.log
```

Nhưng shell nhìn command line rộng hơn.

Nó còn phải xử lý:

```text
quotes
operators
redirection
pipeline
variables
wildcards
command substitution
```

Ví dụ:

```bash
grep -i "$pattern" *.log > result.txt
```

Không phải toàn bộ chuỗi trên được truyền nguyên xi cho `grep`.

Shell xử lý nhiều thành phần trước.

---

# 4.1 Word

Shell parser chia input thành các word/token theo grammar.

Ví dụ:

```bash
echo hello world
```

có thể tạo conceptual words:

```text
echo
hello
world
```

Sau expansion, số lượng argument có thể thay đổi.

---

# 4.2 Operator

Một số ký tự có nghĩa đặc biệt với shell:

```text
|
||
&&
;
&
>
>>
<
<<
()
{}
```

Chúng không đơn giản là argument bình thường.

Ví dụ:

```bash
cmd1 | cmd2
```

`|` được shell hiểu như pipeline operator.

---

# 4.3 Argument vector

External program trong UNIX-like system thường nhận command arguments dưới dạng:

```text
argv[0]
argv[1]
argv[2]
...
```

Ví dụ conceptual mapping:

```bash
grep -n error file.log
```

có thể trở thành:

```text
argv[0] = "grep"
argv[1] = "-n"
argv[2] = "error"
argv[3] = "file.log"
```

Điểm quan trọng:

> Program không nhận "command line string" theo đúng cách người dùng nhìn thấy nó.

Shell đã parse và tạo argument structure.

---

# 5. Quá trình shell xử lý một command

GNU Bash mô tả shell operation như một chuỗi bước logic.

Có thể đơn giản hóa:

```text
1. Read input
2. Parse tokens / operators
3. Build command structure
4. Perform expansions
5. Apply redirections
6. Resolve command
7. Execute
8. Wait / collect status
```

Đây là mental model cốt lõi.

---

# 5.1 Read input

Input có thể đến từ:

```text
terminal
script
pipe
-c string
```

Shell nhận một chuỗi byte/text.

---

# 5.2 Lexical analysis và parsing

Shell phải xác định:

```text
word nào là command
word nào là argument
operator nào là pipeline
operator nào là redirect
quote nào giữ literal meaning
```

Ví dụ:

```bash
echo "a | b"
```

`|` nằm trong quote nên không được parse như pipeline operator.

Trong khi:

```bash
echo a | b
```

là cấu trúc pipeline.

---

# 5.3 Expansion

Sau parsing, shell có thể thực hiện nhiều loại expansion:

```text
parameter expansion
command substitution
arithmetic expansion
pathname expansion
word splitting
tilde expansion
```

Không phải mọi expansion đều xảy ra trong mọi context.

Ordering và quoting có ảnh hưởng rất lớn.

---

# 5.4 Redirection setup

Shell thiết lập file descriptor trước khi external command chạy.

Ví dụ:

```bash
cmd > out.txt
```

shell phải:

```text
open/create out.txt
redirect stdout
then execute cmd
```

Program `cmd` không nhất thiết biết rằng output của nó đang đi vào file.

Từ góc nhìn program:

```text
write(fd=1, ...)
```

vẫn chỉ là ghi stdout.

---

# 5.5 Command resolution

Shell xác định `cmd` là:

```text
reserved word?
alias?
function?
builtin?
external command?
```

Nếu external command, shell tìm executable.

---

# 5.6 Execution

Nếu là builtin:

```text
shell có thể thực thi nội bộ
```

Nếu là external command:

```text
shell tạo execution context/process
      ↓
program image được load
      ↓
program chạy
```

Ở Linux, chi tiết low-level thường liên quan tới:

```text
fork/clone-like process creation
execve()
wait()
```

tùy implementation và optimization.

---

# 5.7 Exit status

Khi command hoàn tất, shell thu kết quả:

```text
0
non-zero
signal termination
pipeline status
```

và dùng nó cho:

```text
$?
if
&&
||
set -e behavior
script control flow
```

---

# 6. Shell builtin, function và external executable

Không phải mọi command đều là executable file.

---

# 6.1 Builtin

Builtin nằm trong chính shell process.

Ví dụ phổ biến:

```text
cd
export
unset
read
alias
jobs
fg
bg
```

Vì sao cần builtin?

Xét `cd`.

Current working directory là state của process.

Nếu shell làm:

```text
shell
  |
  +--> child
         |
         +--> chdir("/tmp")
         |
         +--> exit
```

thì shell cha không đổi directory.

Do đó `cd` phải thay đổi state của shell process hiện tại.

Đây là lý do bản chất, không phải chỉ là quyết định implementation tùy ý.

---

# 6.2 Shell function

Shell function là block command do người dùng định nghĩa.

Nó tồn tại trong execution environment của shell.

Ví dụ conceptual:

```text
function name
   ↓
shell symbol table
   ↓
execute function body
```

Function khác external binary ở chỗ:

```text
không cần ELF executable riêng
không cần PATH lookup theo cách thông thường
```

---

# 6.3 Alias

Alias là một cơ chế textual/substitution ở shell level.

Nó không phải executable.

Ví dụ concept:

```text
alias ll='ls -l'
```

Khi shell parse input tương ứng, alias có thể được expand theo rule của shell.

Không nên nhầm:

```text
alias
```

với:

```text
symlink
```

Alias tồn tại ở shell syntax layer.

Symlink tồn tại ở filesystem layer.

---

# 6.4 External executable

External command là program nằm trong filesystem.

Ví dụ:

```text
/usr/bin/grep
/usr/bin/find
/usr/bin/ps
```

Executable có thể là:

```text
ELF binary
script có shebang
interpreter-driven executable
```

Shell phải resolve đường dẫn và yêu cầu kernel thực thi.

---

# 7. PATH và cơ chế command lookup

Khi nhập:

```text
grep
```

shell không mặc định search toàn filesystem.

Nó sử dụng command resolution rules.

Đối với external executable, biến `PATH` rất quan trọng.

---

# 7.1 PATH là gì?

`PATH` là danh sách directory.

Ví dụ:

```text
/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

Mental model:

```text
command name = grep
      |
      v
iterate PATH entries
      |
      +--> /usr/local/sbin/grep
      +--> /usr/local/bin/grep
      +--> /usr/sbin/grep
      +--> /usr/bin/grep  <-- found
```

Search theo thứ tự.

Directory đứng trước có priority cao hơn.

---

# 7.2 PATH không phải registry

PATH không lưu danh sách command.

Nó chỉ lưu:

```text
directory search order
```

Shell vẫn phải kiểm tra filesystem.

---

# 7.3 Vì sao current directory thường không nằm trong PATH?

Nếu `.` tự động có trong PATH và đứng trước system directory:

```text
attacker tạo ./ls
```

người dùng nhập:

```text
ls
```

có thể vô tình chạy binary độc hại trong current directory.

Do đó việc explicit:

```text
./program
```

làm rõ rằng người dùng muốn executable tại path tương đối đó.

---

# 7.4 Command hashing

Một số shell như Bash có thể cache vị trí executable đã resolve để tránh search PATH liên tục.

Do đó mental model đầy đủ hơn:

```text
command
   |
   +--> shell cache/hash?
   |
   +--> PATH search
```

Điều này giải thích một số edge case khi executable được di chuyển hoặc PATH thay đổi.

---

# 8. Current working directory và path resolution

Mỗi process trong Linux có một current working directory.

Đây là state của process.

Shell cũng vậy.

---

# 8.1 Absolute path

Absolute path bắt đầu từ `/`.

```text
/etc/passwd
/usr/bin/bash
/home/user/project
```

Resolution bắt đầu từ root.

```text
/
 ↓
etc
 ↓
passwd
```

---

# 8.2 Relative path

Relative path được resolve từ current working directory.

Ví dụ:

```text
cwd = /home/user
path = project/main.c
```

Result conceptual:

```text
/home/user/project/main.c
```

---

# 8.3 `.` và `..`

```text
.   current directory
..  parent directory
```

Đây là directory entries/semantic path components đặc biệt.

---

# 8.4 Working directory là process state

Điểm quan trọng:

```text
shell A có cwd riêng
shell B có cwd riêng
service có cwd riêng
process con thừa hưởng cwd ban đầu từ parent
```

Do đó một path tương đối có thể đúng trong terminal này nhưng sai trong service khác.

Đây là một nguyên nhân phổ biến của:

```text
works manually
fails in service
```

---

# 9. Environment và shell variables

Shell duy trì nhiều loại state.

Hai khái niệm thường bị nhầm:

```text
shell variable
environment variable
```

---

# 9.1 Shell variable

Shell variable tồn tại trong shell.

Ví dụ conceptual:

```text
name=value
```

Nó không tự động được truyền cho child process.

---

# 9.2 Environment variable

Environment là tập key/value được truyền vào process khi process được tạo/executed.

Ví dụ:

```text
PATH
HOME
LANG
USER
TERM
```

Một external program có thể đọc environment.

Mental model:

```text
shell state
   |
   +--> shell variables
   |
   +--> exported variables
           |
           v
      child environment
```

---

# 9.3 `export`

`export` đánh dấu variable để nó được đưa vào environment của child process.

Concept:

```text
VAR=value
  |
shell variable

export VAR
  |
  v
future child processes inherit VAR
```

Child có thể thay đổi environment của chính nó nhưng không trực tiếp thay environment của parent.

---

# 9.4 Environment inheritance

Process creation theo mô hình UNIX thường mang tính inheritance.

Child ban đầu thừa hưởng nhiều context:

```text
environment
open file descriptors
current working directory
resource limits
credentials
signal disposition aspects
```

Sau `exec`, process image thay đổi nhưng nhiều process attributes vẫn tiếp tục tồn tại theo rule cụ thể.

Đây là bridge quan trọng giữa shell và system programming.

---

# 10. Process model phía sau command line

Command line nhìn đơn giản nhưng gần như luôn liên quan process.

---

# 10.1 Shell bản thân là một process

Khi terminal mở shell:

```text
terminal emulator
      |
      v
shell process
```

Shell có:

```text
PID
PPID
cwd
environment
file descriptors
signal state
```

---

# 10.2 External command thường chạy trong process context riêng

Conceptual flow:

```text
shell
  |
  +--> create child execution context
           |
           +--> setup redirection
           +--> setup pipe
           +--> exec program
           |
           v
        external process
```

Shell có thể:

```text
wait
or
continue asynchronously
```

tùy command syntax.

---

# 10.3 Foreground process

Foreground job gắn với terminal interaction.

Thường:

```text
shell launches command
      ↓
terminal foreground process group changes
      ↓
command interacts with TTY
      ↓
command exits/stops
      ↓
shell regains foreground
```

Đây là nền tảng cho job control.

---

# 10.4 Background process

Khi command được chạy background:

```text
command &
```

shell không chờ completion theo cách foreground bình thường.

Điều này tạo thêm khái niệm:

```text
job
process group
terminal ownership
signal handling
```

Chi tiết process/job control sẽ được học ở topic process.

---

# 11. Standard file descriptors

Đây là một trong những abstraction quan trọng nhất của Linux.

Một process command-line thông thường khởi đầu với:

```text
fd 0 -> stdin
fd 1 -> stdout
fd 2 -> stderr
```

---

# 11.1 File descriptor là gì?

File descriptor là một số nguyên nhỏ dùng như handle để process tham chiếu tới một open file description/kernel I/O object.

Mental model đơn giản:

```text
Process
+------------------+
| fd 0             |----> input endpoint
| fd 1             |----> output endpoint
| fd 2             |----> error endpoint
| fd 3             |----> another file/socket/pipe...
+------------------+
```

Program dùng:

```text
read()
write()
```

trên file descriptor.

---

# 11.2 stdin

`stdin` là input stream mặc định.

Thông thường trong interactive shell:

```text
fd 0
 |
 v
terminal
```

Nhưng shell có thể thay nó bằng:

```text
file
pipe
here-document
socket-like endpoint
```

---

# 11.3 stdout

`stdout` là output stream mặc định cho result bình thường.

Thông thường:

```text
fd 1
 |
 v
terminal
```

Nhưng có thể redirect tới:

```text
file
pipe
device
```

---

# 11.4 stderr

`stderr` dành cho diagnostic/error output.

Việc tách:

```text
stdout
stderr
```

cho phép program vừa:

```text
tạo machine-consumable data
```

vừa:

```text
ghi diagnostic cho human
```

mà không trộn hai luồng.

Đây là một design cực kỳ quan trọng.

---

# 11.5 Tại sao chỉ là file descriptor?

UNIX cố gắng chuẩn hóa I/O qua abstraction chung.

Một process có thể write tới:

```text
regular file
terminal
pipe
socket
device
```

mà API cơ bản vẫn có thể là:

```text
write(fd, buffer, size)
```

Đây là nền tảng của câu nói thường gặp:

> "Everything is a file"

Câu này hữu ích như mental model nhưng không hoàn toàn chính xác theo nghĩa tuyệt đối.

Tốt hơn nên hiểu:

> Linux/UNIX cố gắng cung cấp nhiều resource thông qua **file-descriptor-oriented interfaces**.

---

# 12. Redirection thực chất là gì?

Redirection là việc shell thay đổi mapping file descriptor của command trước khi execution.

---

# 12.1 `>` không phải feature của program

Ví dụ:

```text
program > output.txt
```

Program thường không parse `>`.

Shell parse nó.

Mental model:

```text
shell
 |
 +--> open("output.txt")
 |
 +--> make fd 1 point to file
 |
 +--> execute program
```

Program vẫn nghĩ:

```text
stdout = fd 1
```

nhưng endpoint đã khác.

---

# 12.2 Conceptual descriptor table

Trước redirect:

```text
fd 0 -> terminal input
fd 1 -> terminal output
fd 2 -> terminal output
```

Sau:

```text
cmd > out.txt
```

có thể trở thành:

```text
fd 0 -> terminal input
fd 1 -> out.txt
fd 2 -> terminal output
```

---

# 12.3 Append

`>>` khác `>` ở file opening semantics.

Concept:

```text
>   open for output, truncate/replace current content
>>  open for output in append mode
```

Điểm chính nằm ở:

```text
how shell opens target
```

không nằm ở program.

---

# 12.4 Redirect stderr

```text
2> error.log
```

`2` là file descriptor number.

Shell thiết lập:

```text
fd 2 -> error.log
```

stdout không đổi.

---

# 12.5 Descriptor duplication

Cú pháp:

```text
2>&1
```

không đơn giản là "đưa stderr vào stdout" dưới dạng text.

Nó có nghĩa conceptually:

```text
make fd 2 refer to same destination as fd 1
```

Ordering quan trọng.

Ví dụ:

```text
cmd > out 2>&1
```

logic:

```text
1. fd1 -> out
2. fd2 -> current fd1 target
```

Sau đó:

```text
fd1 -> out
fd2 -> out
```

Nhưng:

```text
cmd 2>&1 > out
```

ordering khác.

Concept:

```text
1. fd2 -> current fd1 target (terminal)
2. fd1 -> out
```

Result:

```text
fd1 -> out
fd2 -> terminal
```

Đây là ví dụ điển hình cho việc hiểu semantics thay vì học syntax máy móc.

---

# 13. Pipeline và Unix process composition

Pipeline là một trong những đặc trưng mạnh nhất của UNIX shell.

Cú pháp:

```text
producer | consumer
```

Mental model:

```text
process A stdout
       |
       v
    kernel pipe
       |
       v
process B stdin
```

---

# 13.1 Pipe là kernel object

Pipe không phải file text tạm.

Nó là IPC mechanism trong kernel.

Có hai đầu:

```text
read end
write end
```

Shell tạo pipe và map file descriptor:

```text
A fd1 -> pipe write end
B fd0 -> pipe read end
```

---

# 13.2 Processes có thể chạy đồng thời

Pipeline không nhất thiết:

```text
A chạy xong
↓
B bắt đầu
```

Thông thường các process trong pipeline có thể tồn tại đồng thời.

Data chảy dần:

```text
A produces bytes
      ↓
pipe buffer
      ↓
B consumes bytes
```

Đây là streaming model.

---

# 13.3 Backpressure

Pipe có buffer hữu hạn.

Nếu consumer chậm:

```text
B đọc chậm
   ↓
pipe buffer đầy
   ↓
A write có thể block
```

Nếu producer chậm:

```text
B read
   ↓
không có data
   ↓
B có thể block
```

Vì vậy pipeline tự nhiên có flow control thông qua blocking I/O.

---

# 13.4 EOF trong pipeline

Consumer biết input kết thúc khi:

```text
all write ends of pipe are closed
```

Sau đó `read()` có thể trả EOF.

Điều này liên quan trực tiếp tới process lifetime và descriptor inheritance.

---

# 13.5 Pipeline composition

Unix philosophy khuyến khích utility làm một nhiệm vụ tương đối tập trung.

Ví dụ abstraction:

```text
source
  ↓
filter
  ↓
transform
  ↓
aggregate
  ↓
sink
```

Pipeline biến các utility độc lập thành một processing graph.

---

# 13.6 stderr không tự đi qua pipe

Với:

```text
A | B
```

thông thường:

```text
A stdout -> pipe -> B stdin
A stderr -> original stderr destination
```

Điều này giúp diagnostic không làm hỏng data stream.

---

# 14. Quoting, expansion và globbing

Shell syntax mạnh nhưng cũng dễ gây lỗi vì input người dùng trải qua nhiều stage trước khi program nhận argument.

---

# 14.1 Parameter expansion

Ví dụ concept:

```text
$HOME
```

shell thay bằng value.

Program không thấy literal `$HOME` trừ khi quoting ngăn expansion.

---

# 14.2 Command substitution

Concept:

```text
$(command)
```

shell:

```text
execute inner command
       ↓
capture stdout
       ↓
substitute result
```

Do đó command substitution tạo dependency:

```text
inner process output
        ↓
outer command argument
```

---

# 14.3 Pathname expansion / globbing

Pattern:

```text
*.c
```

thường được shell expand dựa trên directory entries.

Ví dụ:

```text
main.c
gpio.c
uart.c
```

pattern có thể thành:

```text
gpio.c main.c uart.c
```

trước khi program chạy.

Program nhận danh sách filename đã expand.

---

# 14.4 Single quotes

Single quote ngăn hầu hết shell interpretation bên trong.

Concept:

```text
'$HOME'
```

được giữ literal.

---

# 14.5 Double quotes

Double quote giữ word grouping nhưng vẫn cho phép một số expansion như parameter expansion và command substitution.

Concept:

```text
"$HOME"
```

giữ result thành một shell word logic thay vì để word splitting/globbing làm thay đổi structure ngoài ý muốn.

---

# 14.6 Word splitting

Unquoted expansion có thể tạo nhiều word.

Ví dụ conceptual:

```text
VAR="a b"
```

unquoted:

```text
$VAR
```

có thể trở thành:

```text
"a"
"b"
```

Trong khi quoted:

```text
"$VAR"
```

giữ:

```text
"a b"
```

như một argument logic.

---

# 14.7 Expansion ordering

Shell expansion không phải một operation duy nhất.

Nó là nhiều stage có thứ tự.

Ở mức nền tảng nên nhớ:

```text
syntax parsing
   ↓
expansions
   ↓
word structure may change
   ↓
redirection
   ↓
execution
```

Khi command "trông đúng" nhưng argument sai, nguyên nhân rất thường nằm ở expansion/quoting.

---

# 15. Exit status và control flow

UNIX process không chỉ tạo text output.

Nó còn trả **status**.

---

# 15.1 Exit status

Thông thường:

```text
0        success
non-zero non-success / condition / error
```

Nhưng semantic cụ thể tùy program.

Ví dụ một utility có thể dùng nhiều non-zero code cho nhiều trạng thái khác nhau.

Không nên mặc định mọi non-zero đều có cùng nghĩa.

---

# 15.2 Shell nhận status

Shell lưu status của command gần nhất.

Concept:

```text
process terminates
     ↓
kernel records termination state
     ↓
parent shell collects status
     ↓
shell control flow
```

---

# 15.3 `&&`

```text
A && B
```

nghĩa:

```text
run A
  ↓
A success?
  |
 yes -> run B
 no  -> do not run B
```

---

# 15.4 `||`

```text
A || B
```

nghĩa:

```text
run A
  ↓
A success?
  |
 yes -> skip B
 no  -> run B
```

---

# 15.5 `;`

```text
A ; B
```

không dùng success của A làm điều kiện.

---

# 15.6 Exit status là machine interface

Điểm quan trọng:

```text
stdout = data for humans/programs
stderr = diagnostics
exit status = control result
```

Automation tốt nên không cố parse text nếu program đã cung cấp exit status rõ ràng.

---

# 16. Các utility cơ bản dưới góc nhìn abstraction

Các command cơ bản nên được hiểu theo **abstraction mà chúng tác động**, không phải chỉ học syntax.

---

# 16.1 Navigation utilities

Các utility như:

```text
pwd
cd
ls
```

liên quan tới:

```text
current working directory
directory entries
path resolution
```

Mental model:

```text
process context
   |
   +--> cwd
   |
   +--> pathname
           |
           v
      filesystem lookup
```

---

# 16.2 File manipulation utilities

Các utility:

```text
cp
mv
rm
mkdir
touch
```

thay đổi filesystem namespace hoặc file metadata/content.

Không nên nhìn chúng chỉ là "lệnh copy/xóa".

Ví dụ:

```text
cp
```

liên quan:

```text
open source
read data
create/open destination
write data
metadata handling
```

`mv` có thể là:

```text
rename within filesystem
```

hoặc trong một số trường hợp cần logic tương đương:

```text
copy + remove
```

khi di chuyển qua filesystem boundary.

---

# 16.3 Text-processing utilities

Các utility:

```text
cat
head
tail
wc
grep
```

thường phù hợp với stream model.

Mental model:

```text
input bytes/text
      ↓
processing
      ↓
output bytes/text
```

Do đó chúng ghép pipeline rất tự nhiên.

---

# 16.4 Filesystem search

`find` làm việc trên filesystem tree.

Mental model:

```text
starting path
    ↓
tree traversal
    ↓
evaluate predicates
    ↓
selected entries
```

Khác `grep`:

```text
grep -> content matching
find -> filesystem entry selection
```

---

# 16.5 Process observation

Utilities như:

```text
ps
top
```

trình bày process state từ kernel/proc-based interfaces theo cách khác nhau.

```text
ps  -> snapshot
top -> periodically refreshed interactive view
```

Cả hai đều là userspace observer của process information.

---

# 16.6 Storage observation

`df` và `du` nhìn storage từ hai abstraction khác nhau.

```text
df
 |
 +--> filesystem allocation/accounting perspective

du
 |
 +--> directory/file tree traversal perspective
```

Vì thế số liệu có thể khác.

Đây không nhất thiết là bug.

---

# 16.7 Mount observation

`mount`/`findmnt` liên quan tới mapping:

```text
filesystem
   ↓
mount point
   ↓
visible namespace path
```

Mount không "copy filesystem vào directory".

Nó gắn một filesystem tree vào namespace tại một vị trí.

---

# 17. Command line như một data-flow system

Một command line phức tạp có thể được xem như graph.

Ví dụ abstract:

```text
source | filter | transform > sink
```

Tương đương mental model:

```text
+--------+     +--------+     +-----------+
| source | --> | filter | --> | transform |
+--------+     +--------+     +-----+-----+
                                      |
                                      v
                                    sink
```

Shell chịu trách nhiệm:

```text
parse syntax
create processes
create pipes
duplicate descriptors
open files
connect endpoints
wait/collect status
```

Utilities chịu trách nhiệm:

```text
consume input
perform transformation
produce output
return status
```

Sự tách trách nhiệm này là nền tảng của UNIX composability.

---

# 17.1 Data plane và control plane

Có thể nhìn command line theo hai lớp.

## Data plane

```text
stdin
stdout
stderr
pipe byte streams
file content
```

## Control plane

```text
process creation
exit status
signals
job control
conditional execution
```

Mental model:

```text
        control
shell ----------------> processes
  |                        |
  |                        |
  +------ data wiring -----+
           pipes/fds
```

Đây là một cách nhìn rất hữu ích khi học system programming sau này.

---

# 18. Error model và tư duy debug

Command-line error nên được phân loại theo layer.

---

# 18.1 Resolution error

Ví dụ symptom:

```text
command not found
```

Causal chain:

```text
token parsed as command
       ↓
builtin/function/alias lookup
       ↓
PATH lookup
       ↓
executable not found
```

Root cause có thể là:

```text
PATH sai
package chưa cài
command name sai
environment khác
```

---

# 18.2 Path resolution error

Symptom:

```text
No such file or directory
```

Có thể xuất phát từ:

```text
cwd sai
relative path sai
target không tồn tại
symlink target thiếu
interpreter path thiếu
dynamic loader thiếu
```

Do đó error text không luôn chỉ ra chính xác layer cuối cùng.

---

# 18.3 Permission error

Symptom:

```text
Permission denied
```

Possible causes:

```text
execute bit
directory search permission
filesystem mount option
credentials
MAC policy
interpreter/resource permission
```

Permission sẽ được đào sâu trong Topic 2.

---

# 18.4 Expansion error

Command nhìn "đúng" nhưng program nhận argument sai.

Causal chain:

```text
variable
  ↓
expansion
  ↓
word splitting
  ↓
globbing
  ↓
argument vector khác mong muốn
```

Đây là lý do quoting là semantic, không phải style.

---

# 18.5 Redirection error

Có thể xảy ra khi:

```text
target directory không tồn tại
permission không đủ
filesystem read-only
descriptor ordering sai
```

Điểm quan trọng:

> Redirection failure có thể xảy ra trước khi external program thực sự chạy.

---

# 18.6 Pipeline error

Pipeline nhiều stage tạo nhiều failure point.

Mental model debug:

```text
source output correct?
      ↓
pipe wiring correct?
      ↓
filter receives expected bytes?
      ↓
format compatible?
      ↓
consumer status?
```

Không nên nhìn toàn pipeline như một black box.

---

# 19. Liên hệ với Embedded Linux

Topic này có vẻ "Linux cơ bản", nhưng gần như mọi phần đều xuất hiện lại trong Embedded Linux.

---

# 19.1 Serial console

Embedded board:

```text
UART
 ↓
TTY driver
 ↓
console/getty
 ↓
shell
```

Kiến thức terminal/TTY giúp hiểu:

```text
boot console
login prompt
serial shell
Ctrl+C
line settings
```

---

# 19.2 Init scripts và services

Startup sequence thường chạy:

```text
shell scripts
service commands
applications
```

Nếu không hiểu:

```text
PATH
cwd
environment
exit status
redirection
```

rất dễ gặp:

```text
works manually
fails at boot
```

---

# 19.3 Logging

Embedded application thường có:

```text
stdout
stderr
syslog/journal
file logs
serial logs
```

Việc tách stdout/stderr giúp thiết kế application và debug tốt hơn.

---

# 19.4 Build systems

Makefile và build scripts dựa rất nhiều vào shell semantics.

Ví dụ concept:

```text
compiler command
   ↓
exit status
   ↓
make decision
```

Pipeline/redirection/environment cũng xuất hiện thường xuyên.

---

# 19.5 Device access

Sau này userspace tương tác driver qua:

```text
/dev/*
/sys/*
/proc/*
```

và rất nhiều interaction vẫn dựa trên:

```text
file descriptor
read/write
path resolution
permissions
```

Topic 1 là nền cho abstraction này.

---

# 19.6 Remote administration

Embedded target thường được quản trị qua:

```text
serial
SSH
network shell
```

Command line là interface vận hành thực tế, không phải kiến thức phụ.

---

# 20. Mô hình tư duy tổng hợp

Có thể tổng hợp toàn bộ topic bằng sơ đồ:

```text
                    USER
                      |
                      v
              Terminal / PTY
                      |
                      v
                   Shell
                      |
        +-------------+-------------+
        |             |             |
        v             v             v
      Parse        Expansion     Redirection
        |             |             |
        +-------------+-------------+
                      |
                      v
              Command resolution
                      |
          +-----------+-----------+
          |                       |
          v                       v
       Builtin                External
                                  |
                                  v
                               Process
                                  |
                 +----------------+----------------+
                 |                |                |
                 v                v                v
              stdin            stdout           stderr
               fd0              fd1              fd2
                 |                |                |
                 +--------+-------+--------+-------+
                          |                |
                          v                v
                       files            pipes
                       TTY              devices
                       sockets          logs
```

Ở góc nhìn kernel/process:

```text
Shell
  |
  +--> process lifecycle
  +--> file descriptor table
  +--> environment
  +--> current working directory
  +--> signals
  +--> pipes
  +--> terminal association
```

Ở góc nhìn shell language:

```text
command
  ↓
syntax
  ↓
expansion
  ↓
descriptor wiring
  ↓
execution
  ↓
exit status
```

Ở góc nhìn Unix philosophy:

```text
small programs
     ↓
standard streams
     ↓
composition
     ↓
pipeline
     ↓
larger behavior
```

Ba mental model này bổ sung cho nhau.

---

# 21. Các nguyên tắc cốt lõi

1. **Terminal và shell là hai lớp khác nhau.** Terminal vận chuyển/hiển thị I/O; shell là command interpreter.

2. **Shell bản thân là một process có state.** Nó có PID, environment, file descriptors và current working directory.

3. **Một command line được shell parse trước khi program chạy.** Program thường không nhận nguyên chuỗi người dùng đã nhập.

4. **Expansion có thể thay đổi argument vector.** Quoting vì vậy là semantic của command, không phải vấn đề format.

5. **Builtin tồn tại vì một số operation phải thay đổi state của shell hiện tại.**

6. **PATH là ordered search path cho executable.** Nó không phải database của command.

7. **Relative path phụ thuộc current working directory của process.**

8. **Environment được truyền từ parent sang child theo process execution model.**

9. **File descriptor là abstraction trung tâm của Linux I/O.**

10. **stdin/stdout/stderr chỉ là conventional file descriptor mappings: 0, 1 và 2.**

11. **Redirection là việc thay đổi descriptor mapping trước khi command chạy.**

12. **Pipeline dùng kernel pipe để nối stdout của process trước với stdin của process sau.**

13. **Pipeline hỗ trợ streaming và backpressure, không chỉ là nối text sau khi command đầu hoàn tất.**

14. **stderr được tách khỏi stdout để data stream và diagnostic stream có thể xử lý độc lập.**

15. **Exit status là interface điều khiển cho automation.**

16. **Command-line utilities mạnh vì chúng có thể compose qua standard streams.**

17. **Error phải được phân tích theo layer: parsing → expansion → resolution → path → permission → redirection → process → program logic.**

18. **Các abstraction của Topic 1 sẽ xuất hiện lại trong process, IPC, shell scripting, build system, device file và driver interaction.**

19. **Embedded Linux phụ thuộc command line nhiều hơn desktop Linux vì serial console, SSH và shell thường là giao diện quản trị chính.**

20. **Mục tiêu đúng không phải nhớ nhiều command, mà là hiểu command execution model.**

---

# Tài liệu tham khảo

Các nguồn dưới đây được ưu tiên vì là tài liệu chính thức hoặc reference kỹ thuật được cộng đồng Linux sử dụng rộng rãi.

## GNU Bash

- [GNU Bash Reference Manual](https://www.gnu.org/software/bash/manual/)
- [What is a shell?](https://www.gnu.org/software/bash/manual/html_node/What-is-a-shell_003f.html)
- [Shell Operation](https://www.gnu.org/software/bash/manual/html_node/Shell-Operation.html)
- [Shell Expansions](https://www.gnu.org/software/bash/manual/html_node/Shell-Expansions.html)
- [Redirections](https://www.gnu.org/software/bash/manual/html_node/Redirections.html)
- [Pipelines](https://www.gnu.org/software/bash/manual/html_node/Pipelines.html)
- [Bourne Shell Builtins](https://www.gnu.org/software/bash/manual/html_node/Bourne-Shell-Builtins.html)

Các phần này là nguồn chính cho:

```text
shell model
parsing
expansion
builtin
pipeline
redirection
exit status
```

---

## GNU Coreutils

- [GNU Coreutils Manual](https://www.gnu.org/software/coreutils/manual/coreutils.html)

Dùng làm reference cho nhóm utility:

```text
pwd
ls
cp
mv
rm
mkdir
cat
head
tail
wc
df
du
```

---

## GNU grep

- [GNU Grep Manual](https://www.gnu.org/software/grep/manual/grep.html)

Dùng cho:

```text
text pattern matching
stream filtering
grep exit semantics
```

---

## GNU Findutils

- [GNU Findutils Manual](https://www.gnu.org/software/findutils/manual/)

Dùng cho:

```text
filesystem traversal
find expressions
file selection
```

---

## Linux man-pages

- [pipe(7)](https://man7.org/linux/man-pages/man7/pipe.7.html)
- [execve(2)](https://man7.org/linux/man-pages/man2/execve.2.html)
- [fork(2)](https://man7.org/linux/man-pages/man2/fork.2.html)
- [dup2(2)](https://man7.org/linux/man-pages/man2/dup2.2.html)
- [open(2)](https://man7.org/linux/man-pages/man2/open.2.html)
- [read(2)](https://man7.org/linux/man-pages/man2/read.2.html)
- [write(2)](https://man7.org/linux/man-pages/man2/write.2.html)
- [chdir(2)](https://man7.org/linux/man-pages/man2/chdir.2.html)
- [environ(7)](https://man7.org/linux/man-pages/man7/environ.7.html)
- [pty(7)](https://man7.org/linux/man-pages/man7/pty.7.html)
- [tty(4)](https://man7.org/linux/man-pages/man4/tty.4.html)

Các manual page này hỗ trợ phần bản chất phía dưới shell:

```text
process execution
file descriptor
pipe
environment
working directory
TTY / PTY
```

---

## procps-ng / util-linux

- [ps(1)](https://man7.org/linux/man-pages/man1/ps.1.html)
- [top(1)](https://man7.org/linux/man-pages/man1/top.1.html)
- [mount(8)](https://man7.org/linux/man-pages/man8/mount.8.html)

---

## POSIX

- [The Open Group Base Specifications](https://pubs.opengroup.org/onlinepubs/9699919799/)

POSIX hữu ích để phân biệt:

```text
portable shell behavior
standard utility behavior
GNU-specific extensions
```

Khi behavior của Bash/GNU utility vượt POSIX, nên xem đó là implementation-specific hoặc GNU extension thay vì mặc định coi là universal UNIX behavior.

---

## Nguyên tắc sử dụng nguồn

Thứ tự ưu tiên:

```text
official specification / project manual
              ↓
Linux man-pages
              ↓
distribution documentation
              ↓
implementation source/documentation
              ↓
community discussion
```

Community source hữu ích cho:

```text
edge case
real-world failure
debug symptom
implementation experience
```

nhưng không nên thay thế specification/manual khi xác định behavior chính thức.

---

> **Điều hướng:** [← Root README](README.md) · [Chủ đề 2 — Linux File System →](README-topic-02.md)
