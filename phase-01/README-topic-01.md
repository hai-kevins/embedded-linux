# Chủ đề 1 — Basic Linux Command Line

> **Phạm vi:** Linux command-line fundamentals — nền tảng lý thuyết cho Embedded Linux.
>
> Chương này chỉ trình bày **lý thuyết**. Không có lab, bài tập hoặc hướng dẫn thao tác thực hành.
>
> Chương này tập trung vào bản chất của môi trường command line trong Linux: terminal là gì, TTY/PTY là gì, shell là gì, shell phân tích và thực thi command như thế nào, command được tìm ra bằng cơ chế nào, process và environment liên hệ với command line ra sao, dữ liệu đi qua `stdin/stdout/stderr` như thế nào, redirection và pipeline thực sự làm gì, và các utility cơ bản như `grep`, `find`, `ps`, `top`, `mount`, `df`, `du` đang quan sát hệ thống ở lớp abstraction nào.
>
> Mục tiêu của chương **không phải học thuộc command syntax**. Mục tiêu là hình thành mental model đúng:
>
> `terminal → shell parser → expansion → command lookup → process/builtin → file descriptors → kernel/resources`
>
> Mental model này sẽ xuất hiện lại trong File System, File I/O, Process, Signal, IPC, Socket, Build System, RootFS, BusyBox, Device Driver, board bring-up và debugging.
>
> **Giới hạn chủ đề:** chương này chỉ đi sâu đến mức cần thiết để hiểu command-line environment. Các nội dung như inode/filesystem internals, `open/read/write`, `fork/exec` API chi tiết, signal programming, process scheduling, IPC implementation và socket programming sẽ được tách sang các topic tương ứng.
>
> **Cấu trúc tài liệu:** các mục `##` là khối kiến thức lớn; các concept chi tiết được đặt ở `###`/`####` để giữ mục lục gọn nhưng không giảm chiều sâu nội dung.
>
> **Điều hướng:** [← Root README](../README.md) · [Chủ đề 2 — Linux File System →](README-topic-02.md)

---

## Mục lục

- [1. Nền tảng Command Line và CLI](#1-nền-tảng-command-line-và-cli)
- [2. Terminal, TTY, PTY và Shell](#2-terminal-tty-pty-và-shell)
- [3. Shell Language và Command Execution](#3-shell-language-và-command-execution)
- [4. Quoting, Expansion và Globbing](#4-quoting-expansion-và-globbing)
- [5. Command Resolution và Execution Context](#5-command-resolution-và-execution-context)
- [6. Variables, Environment và `argv`](#6-variables-environment-và-argv)
- [7. Process Model phía sau Command Line](#7-process-model-phía-sau-command-line)
- [8. Standard Streams và Redirection](#8-standard-streams-và-redirection)
- [9. Pipe và Pipeline](#9-pipe-và-pipeline)
- [10. Exit Status và Shell Control Flow](#10-exit-status-và-shell-control-flow)
- [11. Foreground, Background và Job Control](#11-foreground-background-và-job-control)
- [12. Các Utility cơ bản theo Abstraction](#12-các-utility-cơ-bản-theo-abstraction)
- [13. Search và Filtering: `grep`, `find`](#13-search-và-filtering-grep-find)
- [14. Process Observation: `ps`, `top`](#14-process-observation-ps-top)
- [15. Filesystem/Storage Observation: `mount`, `df`, `du`](#15-filesystemstorage-observation-mount-df-du)
- [16. Command Line như một Data-flow System](#16-command-line-như-một-data-flow-system)
- [17. Error Model và Debugging](#17-error-model-và-debugging)
- [18. Liên hệ với Embedded Linux](#18-liên-hệ-với-embedded-linux)
- [19. Tổng kết và Mental Model](#19-tổng-kết-và-mental-model)
- [20. Tài liệu tham khảo](#20-tài-liệu-tham-khảo)

---

## 1. Nền tảng Command Line và CLI

### 1.1 Command line trong Linux thực chất là gì?


Command line thường được nhìn thấy dưới dạng:

```text
$ command argument option ...
```

Nhưng giao diện này chỉ là lớp ngoài cùng.

Một command-line session điển hình có nhiều lớp:

```text
User
  |
  v
Terminal / terminal emulator
  |
  v
TTY / PTY interface
  |
  v
Shell
  |
  +--> parse command language
  +--> perform expansions
  +--> configure redirections/pipes
  +--> execute builtin/function
  |       or
  +--> locate executable and start program
          |
          v
       Process
          |
          v
       Kernel
          |
          +--> filesystems
          +--> devices
          +--> processes
          +--> memory
          +--> network
```

Do đó, command line không phải bản thân kernel, cũng không phải chỉ là “một chương trình để gõ lệnh”.

Nó là **một môi trường tương tác và một command language** dùng để:

```text
describe operations
compose programs
connect data streams
control process execution
inspect operating-system state
```

Một câu lệnh nhìn đơn giản như:

```text
grep error system.log
```

có thể liên quan tới:

```text
terminal input
    ↓
shell lexical/parser rules
    ↓
word expansion
    ↓
command search
    ↓
process execution
    ↓
filesystem access
    ↓
read bytes
    ↓
pattern matching
    ↓
write stdout
    ↓
terminal output
```

Điểm cốt lõi:

> **Shell không “làm tất cả công việc”. Shell tổ chức việc thực thi; utility và kernel thực hiện phần lớn operation phía dưới.**

---

### 1.2 CLI và GUI khác nhau ở lớp nào?


CLI và GUI không phải hai hệ điều hành khác nhau.

Chúng thường là hai kiểu frontend khác nhau tới cùng các resource/system service phía dưới.

Mental model:

```text
                User
                 |
        +--------+--------+
        |                 |
        v                 v
       GUI               CLI
        |                 |
 window/app            terminal
        |                 |
 toolkit/API            shell
        |                 |
        +--------+--------+
                 |
              system APIs
                 |
               kernel
```

#### 1.2.1 GUI ưu tiên trực quan

GUI thường biểu diễn resource bằng:

```text
window
button
menu
icon
dialog
drag-and-drop
```

Ưu điểm:

```text
discoverability cao
feedback trực quan
phù hợp tác vụ tương tác
```

Nhưng GUI có thể:

```text
che abstraction phía dưới
khó tự động hóa chuỗi thao tác dài
khó dùng khi target không có display stack
```

#### 1.2.2 CLI ưu tiên biểu đạt bằng text và composition

CLI thường biểu diễn operation bằng:

```text
command
arguments
options
streams
exit status
```

Điểm mạnh không nằm ở việc “gõ nhanh hơn GUI”, mà ở tính **composable**:

```text
producer
  |
  v
filter
  |
  v
transform
  |
  v
consumer
```

Text command còn dễ:

```text
ghi lại
review
version-control
remote execution
automation
reproduction
```

#### 1.2.3 Trong Embedded Linux

Một board embedded có thể không có:

```text
GPU desktop stack
display
window manager
full desktop environment
```

nhưng vẫn có:

```text
UART console
SSH
shell
kernel log
BusyBox utilities
system service interface
```

Do đó command line trong Embedded Linux thường không phải “giao diện phụ”.

Nó có thể là **giao diện quản trị và debug chính**.

---

## 2. Terminal, TTY, PTY và Shell

### 2.1 Terminal, TTY, PTY và shell


Bốn khái niệm này liên quan nhưng không đồng nghĩa.

```text
terminal       ≠ shell
TTY            ≠ shell
PTY            ≠ shell
terminal app   ≠ command interpreter
```

---

#### 2.1.1 Terminal

Trong lịch sử UNIX, terminal có thể là thiết bị vật lý:

```text
keyboard
   +
display/printer
   +
serial communication
```

Ngày nay desktop Linux thường dùng terminal emulator.

Terminal emulator chịu trách nhiệm các việc kiểu:

```text
nhận keyboard input
render text output
interpret terminal control sequences
manage window/tab
connect to a PTY
```

Nó không cần hiểu semantics của:

```text
grep
find
mount
ps
```

Nó chủ yếu vận chuyển và hiển thị byte/character stream.

---

#### 2.1.2 TTY

`TTY` có nguồn gốc từ teletypewriter.

Trong Linux, TTY là một kernel abstraction dành cho terminal-style I/O.

Mental model:

```text
process
   ↕
TTY subsystem
   ↕
terminal endpoint
```

TTY layer có thể tham gia:

```text
canonical input
line discipline
echo
special control characters
terminal attributes
foreground process-group behavior
```

Vì vậy ký tự như:

```text
Ctrl+C
Ctrl+Z
Backspace
Enter
```

không nhất thiết chỉ là byte được giao nguyên trạng cho application.

Behavior phụ thuộc TTY configuration và line discipline.

---

#### 2.1.3 Controlling terminal

Một session/process group có thể liên hệ với một **controlling terminal**.

Concept này quan trọng cho:

```text
interactive shell
foreground process group
job control
terminal-generated signals
```

Linux cung cấp `/dev/tty` như một character device đại diện controlling terminal của process nếu process có controlling terminal.

Mental model đơn giản:

```text
terminal
   |
   +---- session
          |
          +---- shell
          |
          +---- foreground job
          |
          +---- background jobs
```

Topic Process/Signal sẽ đào sâu.

---

#### 2.1.4 PTY — pseudoterminal

Desktop terminal emulator và SSH thường không cần một terminal vật lý.

Linux cung cấp pseudoterminal pair:

```text
PTY master  <------>  PTY slave
```

Slave side trông với process gần giống classical terminal.

Mental model:

```text
+-------------------+
| Terminal Emulator |
+-------------------+
          |
      PTY master
          |
    kernel PTY layer
          |
      PTY slave
          |
+-------------------+
|       Shell       |
+-------------------+
```

Dữ liệu:

```text
keyboard
  ↓
terminal emulator
  ↓
PTY master
  ↓
PTY slave
  ↓
shell/program
```

Và output đi chiều ngược lại.

Linux UNIX 98 PTY thường liên quan:

```text
/dev/ptmx
/dev/pts/<n>
devpts filesystem
```

---

#### 2.1.5 SSH và PTY

Một interactive SSH session thường có thể yêu cầu PTY phía remote.

Conceptually:

```text
local terminal
      |
      v
SSH client
      |
   network
      |
      v
SSH server
      |
 remote PTY
      |
 remote shell
```

Vì thế interactive behavior như:

```text
prompt
Ctrl+C
terminal dimensions
line editing
```

có thể hoạt động gần giống local terminal.

---

#### 2.1.6 Serial console trong Embedded Linux

Với embedded target, chain có thể gần hardware hơn:

```text
Laptop terminal program
        |
     USB-UART
        |
   board UART pins
        |
   SoC UART driver
        |
      TTY layer
        |
   login/getty/shell
```

Ở đây:

```text
UART
```

là hardware communication peripheral,

còn:

```text
shell
```

là command interpreter.

Không nên gộp hai lớp này.

---

## 3. Shell Language và Command Execution

### 3.1 Shell là một command-language interpreter


POSIX mô tả shell command language như một ngôn ngữ có:

```text
words
operators
redirections
pipelines
lists
compound commands
variables
expansions
functions
control structures
```

Một shell không chỉ là launcher.

Nó vừa là:

```text
parser
language runtime
execution coordinator
environment manager
redirection/pipeline configurator
```

Các shell phổ biến:

```text
sh-style shell
Bash
dash
ash
zsh
ksh
```

Trong Embedded Linux, BusyBox `ash` rất phổ biến.

#### 3.1.1 POSIX shell và Bash không hoàn toàn giống nhau

Bash hỗ trợ nhiều extension ngoài POSIX.

Ví dụ:

```text
arrays
[[ ... ]]
process substitution
brace expansion
Bash-specific options
```

Do đó phải tách:

```text
POSIX shell semantics
          vs
Bash-specific semantics
```

Nếu script cần portable giữa:

```text
dash
ash
bash
```

không nên mặc định mọi Bash feature đều có.

#### 3.1.2 Interactive shell và non-interactive shell

Interactive shell:

```text
đọc command từ terminal/user
hiển thị prompt
job control thường bật
interactive error behavior
```

Non-interactive shell thường:

```text
đọc shell script
hoặc command string
```

Startup behavior và error semantics có thể khác.

#### 3.1.3 Login shell

Login shell là shell được khởi tạo như một login session theo shell-specific convention.

Nó có thể đọc startup file khác interactive non-login shell.

Vì vậy câu hỏi:

> “Vì sao biến môi trường có ở terminal này nhưng không có ở service/script kia?”

thường liên quan tới:

```text
shell startup mode
inheritance
environment initialization
```

chứ không chỉ “Linux mất biến”.

---

### 3.2 Cấu trúc của một command line


Một simple command có thể nhìn như:

```text
variable assignments
      +
command name
      +
arguments
      +
redirections
```

Ví dụ conceptual:

```text
LANG=C grep -n error input.txt > result.txt
```

có các thành phần:

```text
LANG=C
  shell assignment for command environment

grep
  command name

-n
  argument interpreted by grep as option

error
  argument interpreted by grep as pattern

input.txt
  argument interpreted by grep as pathname

> result.txt
  redirection interpreted by shell
```

Điểm cực kỳ quan trọng:

> **Shell và command không cùng chịu trách nhiệm parse mọi thứ.**

Shell xử lý:

```text
grammar
quotes
expansions
redirections
pipes
control operators
```

Program nhận:

```text
argv[]
environment
already-configured file descriptors
```

Program như `grep` tự hiểu:

```text
-n
--color
pattern syntax
file operands
```

Shell không biết `-n` có nghĩa là line number.

---

### 3.3 Shell xử lý một command theo những giai đoạn nào?


GNU Bash mô tả simple-command expansion và execution theo các bước xác định.

Ở mức mental model có thể tóm tắt:

```text
raw command text
      ↓
lexing / parsing
      ↓
identify words, operators, assignments, redirections
      ↓
shell expansions
      ↓
word splitting / filename expansion where applicable
      ↓
quote removal
      ↓
command lookup
      ↓
redirection setup
      ↓
builtin/function execution
        or
external program execution
      ↓
wait / collect status as required
      ↓
exit status
```

Cần lưu ý đây là sơ đồ học tập; exact ordering có nhiều chi tiết theo POSIX/Bash.

#### 3.3.1 Một state machine cho command lifecycle

```mermaid
stateDiagram-v2
    [*] --> ReadCommand
    ReadCommand --> Parse
    Parse --> SyntaxError: invalid shell grammar
    SyntaxError --> ReadCommand: interactive shell continues

    Parse --> Expand: valid command
    Expand --> ExpansionError: expansion failure
    ExpansionError --> ReadCommand

    Expand --> Lookup
    Lookup --> NotFound: command search fails
    NotFound --> Status127

    Lookup --> SetupRedirection: command resolved
    SetupRedirection --> RedirectionError: open/dup/setup fails
    RedirectionError --> NonZeroStatus

    SetupRedirection --> ExecuteBuiltin: builtin/function
    SetupRedirection --> ExecuteProgram: external command

    ExecuteBuiltin --> CollectStatus
    ExecuteProgram --> CollectStatus

    CollectStatus --> ReadCommand: interactive session
```

State diagram trên nhấn mạnh:

```text
parse failure
lookup failure
redirection failure
program failure
```

là các lớp lỗi khác nhau.

---

## 4. Quoting, Expansion và Globbing

### 4.1 Quoting: khi nào ký tự được hiểu theo nghĩa literal?


Shell có nhiều ký tự mang syntax đặc biệt:

```text
space
tab
newline
|
&
;
<
>
(
)
$
`
\
'
"
*
?
[
...
```

Quoting kiểm soát khi nào shell được phép hiểu các ký tự này như syntax.

---

#### 4.1.1 Backslash

Backslash thường preserve literal value của ký tự kế tiếp, với các rule cụ thể theo shell/context.

Concept:

```text
\*
```

khác:

```text
*
```

Vế đầu có thể truyền literal `*`.

Vế sau có thể tham gia filename expansion.

---

#### 4.1.2 Single quotes

Trong POSIX-style shell, single quotes preserve literal value của các ký tự bên trong, trừ việc không thể chứa single quote literal theo cách đơn giản bên trong chính single-quoted string.

Mental model:

```text
'...'
   ↓
strong quoting
```

Ví dụ concept:

```text
'$HOME'
```

không parameter-expand `$HOME`.

---

#### 4.1.3 Double quotes

Double quote yếu hơn single quote.

Một số expansion vẫn hoạt động:

```text
parameter expansion
command substitution
arithmetic expansion
```

nhưng word splitting và filename expansion bị ảnh hưởng mạnh/không xảy ra theo cách thông thường trên kết quả quoted.

Mental model:

```text
"$variable"
```

thường giúp preserve một argument ngay cả khi value chứa whitespace.

---

#### 4.1.4 Quote removal

Quote character dùng để điều khiển shell parser/expansion không nhất thiết trở thành character truyền vào `argv`.

Ví dụ conceptual:

```text
"hello world"
```

được shell biến thành **một argument** chứa:

```text
hello world
```

không chứa hai ký tự `"`.

---

#### 4.1.5 Quoting không phải “format text”

Quoting ảnh hưởng semantics:

```text
argument boundaries
expansion
globbing
word splitting
redirection operands
pattern handling
```

Đây là lý do quoting bug có thể trở thành:

```text
wrong pathname
wrong number of argv elements
unexpected wildcard expansion
security bug trong script
```

---

### 4.2 Shell expansion và vì sao “text nhập vào” có thể khác `argv`


Một command line không được chuyển nguyên xi thành `argv`.

Shell có nhiều expansion phase.

Bash có các expansion như:

```text
brace expansion
tilde expansion
parameter/variable expansion
command substitution
arithmetic expansion
word splitting
filename expansion
quote removal
```

Không phải tất cả đều là POSIX feature; brace expansion là Bash feature.

#### 4.2.1 Parameter expansion

Concept:

```text
$HOME
${USER}
```

Shell thay reference bằng value trước khi program chạy.

Program không nhận literal `$HOME` nếu expansion xảy ra.

#### 4.2.2 Command substitution

Concept:

```text
$(command)
```

Shell chạy command substitution và dùng output làm một phần của word theo quoting/expansion rules.

Điều này tạo data dependency:

```text
inner command
   ↓
stdout capture
   ↓
outer command argument construction
```

#### 4.2.3 Arithmetic expansion

Bash/POSIX shell có arithmetic expansion:

```text
$(( expression ))
```

Shell tính arithmetic expression rồi tạo text result.

#### 4.2.4 Word splitting

Kết quả expansion không được quote có thể bị split theo `IFS` rules.

Đây là nguồn bug nổi tiếng:

```text
variable contains whitespace
       ↓
unquoted expansion
       ↓
one logical value becomes multiple argv elements
```

#### 4.2.5 Filename expansion

Sau một số expansion, pattern characters có thể được shell dùng để match pathname entries.

Khi đó external program nhận **danh sách filename đã expand**, không nhận wildcard gốc.

#### 4.2.6 Mental model

```text
typed shell text

mycmd "$A" *.log

        ↓ shell

argv[0] = "mycmd"
argv[1] = value of A as one argument
argv[2] = "a.log"
argv[3] = "b.log"
...
```

Program có thể không biết user từng viết `*.log`.

---

### 4.3 Globbing không phải regular expression


Hai khái niệm thường bị nhầm:

```text
shell glob
regex
```

Chúng có syntax và engine khác nhau.

#### 4.3.1 Shell glob

Common shell filename patterns:

```text
*
?
[abc]
[a-z]
```

Mục tiêu chính:

```text
match pathnames / filenames
```

Ví dụ mental model:

```text
*.c
  |
  | shell filename expansion
  v
main.c util.c driver.c
```

#### 4.3.2 Regular expression

Regex được utility/library như `grep` hiểu.

Ví dụ regex concept:

```text
^error
[0-9]+
foo.*bar
```

Shell không tự hiểu regex semantics này khi nó chỉ đang parse argument.

#### 4.3.3 Vì sao quote pattern của `grep` thường quan trọng?

Pattern:

```text
*.c
```

nếu không quote có thể bị shell glob-expand trước.

`grep` có thể không bao giờ nhận đúng pattern intended.

Mental model:

```text
shell syntax layer
      ↓
argv
      ↓
grep regex layer
```

Hai parser khác nhau.

---

## 5. Command Resolution và Execution Context

### 5.1 Shell builtin, shell function và external executable


Khi thấy:

```text
command arg...
```

không thể mặc định nó luôn tạo một executable process mới.

Command có thể là:

```text
reserved word
alias
shell function
builtin
external executable
```

Exact lookup order phụ thuộc shell/spec.

---

#### 5.1.1 Builtin

Builtin chạy bên trong shell implementation.

Ví dụ shell cần builtin cho những operation phải ảnh hưởng chính shell:

```text
cd
export
unset
read
jobs
wait
```

Nếu `cd` chỉ là child process độc lập:

```text
shell cwd = /home
      |
      +--> child executes cd /tmp
                |
                v
          child cwd = /tmp
                |
              exits
      |
shell cwd vẫn = /home
```

Vì vậy `cd` cần thay current directory của shell process.

---

#### 5.1.2 External executable

External command thường là executable file được shell tìm và execute.

Ví dụ common GNU/Linux utilities:

```text
/bin/ls
/usr/bin/grep
/usr/bin/find
/usr/bin/ps
```

Location phụ thuộc distro/system.

Không nên hard-code mental model rằng mọi command nằm `/bin`.

---

#### 5.1.3 Shell function

Function là shell-language construct được định nghĩa trong shell environment.

Function có thể:

```text
nhận positional parameters
dùng shell variables
gọi command khác
return shell status
```

Nó không nhất thiết tương ứng executable file.

---

#### 5.1.4 Alias

Alias là text-level shell convenience mechanism.

Alias expansion xảy ra ở shell parsing context, không phải kernel command lookup.

Do đó:

```text
alias
function
builtin
executable
```

là bốn abstraction khác nhau.

---

### 5.2 `PATH` và command search


Khi command name không chứa `/`, shell có thể search `PATH`.

Ví dụ:

```text
PATH=/usr/local/bin:/usr/bin:/bin
```

Mental model:

```text
command = grep
   |
   v
search PATH entries in order
   |
   +--> /usr/local/bin/grep ?
   |
   +--> /usr/bin/grep ?
   |
   +--> /bin/grep ?
   |
   v
resolved executable
```

Exact search semantics còn có:

```text
functions
builtins
hash cache
POSIX special builtins
shell-specific rules
```

#### 5.2.1 Có slash → khác search mode

Command:

```text
./app
```

chứa `/`.

Shell không cần search `PATH` theo cùng cách.

Nó dùng pathname được chỉ định.

#### 5.2.2 Vì sao current directory thường không tự nằm trong `PATH`?

Nếu `.` không ở `PATH`, gõ:

```text
app
```

không đồng nghĩa:

```text
./app
```

Điều này giúp tránh vô tình execute file trong arbitrary current directory khi user intended system command.

#### 5.2.3 Empty PATH entry

Trong một số shell/POSIX semantics, empty field có thể biểu diễn current directory; đây là cấu hình dễ gây confusion/security risk.

Mental model tốt:

```text
PATH defines command-search namespace
not filesystem visibility
```

Một file tồn tại nhưng không nằm trên search path vẫn có thể execute bằng explicit pathname nếu permissions/format cho phép.

#### 5.2.4 Command cache

Shell có thể cache vị trí command để tránh search `PATH` lặp lại.

Bash có command hashing.

Vì vậy khi executable thay đổi location hoặc `PATH` thay đổi, shell-specific cache behavior có thể ảnh hưởng.

---

### 5.3 Current working directory và pathname context


Mỗi process có current working directory (cwd).

Shell cũng là process, nên shell có cwd.

Mental model:

```text
shell process
    |
    +--> cwd = /home/hai/project
```

Relative pathname được resolve từ context này.

Ví dụ:

```text
src/main.c
```

conceptually bắt đầu từ:

```text
/home/hai/project
```

#### 5.3.1 `pwd`

`pwd` biểu diễn current working directory của shell context.

Nó không “hỏi terminal đang ở folder nào”.

Terminal window không có cwd theo nghĩa process filesystem state giống shell; process bên trong terminal có cwd.

#### 5.3.2 `cd`

`cd` thay cwd của shell.

Đây là process state.

Cwd được child process kế thừa khi shell tạo child.

#### 5.3.3 Logical và physical path

Shell có thể maintain logical cwd có symlink components, trong khi kernel filesystem traversal có physical object semantics.

Bash `pwd` có logical/physical modes.

Topic File System sẽ đào sâu pathname, symlink và inode.

---

## 6. Variables, Environment và `argv`

### 6.1 Shell variable và environment variable


Hai khái niệm này thường bị dùng thay nhau nhưng không giống nhau.

#### 6.1.1 Shell variable

Shell có internal variable namespace:

```text
NAME=value
```

Variable có thể chỉ tồn tại trong shell.

#### 6.1.2 Environment variable

Environment là array các chuỗi dạng:

```text
name=value
```

được cung cấp cho program khi program image mới được execute.

Linux `environ(7)` mô tả environment như một array pointer kết thúc bởi NULL.

Mental model:

```text
shell variables
      |
      | export selected variables
      v
environment for child
      |
      v
exec new program
```

#### 6.1.3 `export`

`export` đánh dấu shell variable để shell đưa nó vào environment của command sau.

Concept:

```text
VAR=value       shell variable

export VAR      mark for environment inheritance
```

Không phải mọi shell variable tự động thành environment variable.

#### 6.1.4 Environment inheritance

Khi process được tạo, child thường inherit environment copy từ parent.

Khi new program được `execve()`:

```text
argv[]
envp[] / environ
```

được cung cấp cho program mới.

#### 6.1.5 Child không thể “export ngược” trực tiếp vào parent

Mental model:

```text
parent shell env
      |
      +--> child gets copy
             |
             +--> child modifies own environment
             |
             v
            exit

parent environment unchanged
```

Điều này giải thích vì sao script chạy như child không thể đơn giản thay permanent environment của parent shell.

`source`/`.` khác vì shell đọc commands vào current shell environment.

#### 6.1.6 Environment có thể chứa configuration quan trọng

Ví dụ:

```text
PATH
HOME
LANG
LC_*
TERM
PWD
SHELL
```

Nhưng semantics exact của từng variable phụ thuộc shell/library/program.

Không nên suy luận chỉ từ tên.

---

### 6.2 `argv`, environment và process image


Một C program thường nhìn command-line arguments qua:

```c
int main(int argc, char *argv[])
```

Mental model:

```text
shell words after expansion
      ↓
argument vector
      ↓
argv[0]
argv[1]
argv[2]
...
NULL
```

#### 6.2.1 `argv[0]`

Convention thường là command/program name.

Nhưng kernel/API không nên được hiểu là luôn xác minh `argv[0]` chính xác bằng executable pathname.

#### 6.2.2 Argument boundaries là cấu trúc

Program nhận array strings.

Nó không nhận nguyên command line như một single raw line rồi tự split theo shell syntax.

Do đó:

```text
"hello world"
```

sau shell parsing có thể thành một `argv` element.

#### 6.2.3 Environment là channel khác arguments

Arguments:

```text
explicit per invocation
```

Environment:

```text
ambient process configuration inherited/provided
```

Ví dụ conceptual:

```text
LANG=C sort file
```

`LANG=C` có thể được shell đưa vào environment của `sort`, trong khi `file` là argument.

Hai channel khác nhau.

---

## 7. Process Model phía sau Command Line

### 7.1 Process model phía sau command line


External command cuối cùng phải trở thành running program context.

Trên Unix/Linux, mental model phổ biến:

```text
shell
  |
 fork/create child-like execution context
  |
  +--> child sets up pipes/redirections
  |
  +--> execve(new program)
  |
  v
program runs
```

Cần hai nuance.

#### 7.1.1 `fork()` + `exec()` là mental model, không phải mọi command đều bắt buộc đúng chuỗi đó

Shell có thể:

```text
execute builtin without fork
optimize final command with exec
use different process-creation mechanisms internally
```

Nhưng `fork` + `exec` vẫn là model rất hữu ích để hiểu Unix process semantics.

#### 7.1.2 `execve()` không tạo “process thứ hai”

`execve()` thay program image của calling process.

Theo Linux man-pages:

```text
old program image
     |
     | execve()
     v
new program image
```

PID có thể giữ nguyên vì vẫn là cùng process identity ở nhiều khía cạnh, nhưng code/data/stack được thay theo executable mới.

#### 7.1.3 Shell chờ foreground command

Với simple foreground external command, shell thường:

```text
start child/program
      ↓
wait
      ↓
receive termination/status
      ↓
display next prompt
```

Đây là lý do prompt chưa trở lại khi foreground command vẫn chạy.

---

#### 7.1.4 Command lifecycle dưới dạng UML-style sequence

```mermaid
sequenceDiagram
    participant U as User
    participant T as Terminal/PTY
    participant S as Shell
    participant K as Kernel
    participant P as Program

    U->>T: command text
    T->>S: input bytes
    S->>S: parse + expand + lookup
    S->>K: create execution context
    S->>K: configure FDs / redirections
    S->>K: exec program
    K->>P: start new program image
    P->>K: syscalls / resource access
    P->>T: stdout/stderr through FDs
    P->>K: exit(status)
    K->>S: wait status
    S->>T: prompt/output
```

Sơ đồ giản lược để thể hiện responsibility.

---

## 8. Standard Streams và Redirection

### 8.1 Standard input, standard output và standard error


POSIX program model thường bắt đầu với ba standard streams/file descriptors:

```text
FD 0 -> stdin
FD 1 -> stdout
FD 2 -> stderr
```

Mental model:

```text
          +----------------------+
FD 0 ---->|                      |
          |       process        |----> FD 1
          |                      |----> FD 2
          +----------------------+
```

#### 8.1.1 Default trong interactive terminal

Thông thường:

```text
stdin  -> terminal/PTY
stdout -> terminal/PTY
stderr -> terminal/PTY
```

Vì cả stdout và stderr cùng hiện trên terminal nên người mới dễ tưởng chúng là một stream.

Không phải.

Chúng là file descriptors riêng.

#### 8.1.2 Vì sao tách stdout và stderr?

Một program có hai loại output conceptually:

```text
normal result
diagnostic/error
```

Tách channel cho phép:

```text
pipeline chỉ data result
error vẫn xuất hiện terminal

hoặc

capture result riêng
capture diagnostics riêng
```

Đây là nền của automation đáng tin cậy.

#### 8.1.3 Stream không đồng nghĩa terminal

FD có thể trỏ tới:

```text
terminal
regular file
pipe
socket
device
/dev/null
```

Do đó utility tốt thường không cần biết “output đang đi đâu”; nó chỉ write vào stdout/stderr.

---

### 8.2 Redirection thực chất là thay đổi file-descriptor wiring


Shell syntax:

```text
>
<
>>
2>
2>&1
...
```

không phải instruction mà external program tự parse.

Shell xử lý redirection trước/khi setup execution context.

Mental model:

```text
Without redirection

process FD 1
    |
    v
terminal


With stdout redirection

process FD 1
    |
    v
file
```

#### 8.2.1 Output redirection

Concept:

```text
command > output
```

Shell conceptually:

```text
open/create output target
      ↓
associate target FD with child's FD 1
      ↓
execute command
```

Program vẫn chỉ:

```text
write(1, ...)
```

Program có thể không biết stdout là file.

#### 8.2.2 Input redirection

Concept:

```text
command < input
```

Shell làm FD 0 đọc từ file/endpoint thay vì terminal.

#### 8.2.3 Append

Concept:

```text
>>
```

Shell open output với append semantics thay vì truncating semantics.

#### 8.2.4 Redirect stderr

Concept:

```text
2> error.log
```

thay FD 2 target.

#### 8.2.5 Duplicate descriptor

Concept:

```text
2>&1
```

không có nghĩa:

```text
"send stderr to filename called &1"
```

Nó duplicate/associate FD 2 với target hiện tại của FD 1 theo shell redirection semantics.

---

### 8.3 Thứ tự redirection và vì sao thứ tự toán tử quan trọng


Redirections được xử lý theo thứ tự.

Hai command forms:

```text
command >out 2>&1
```

và:

```text
command 2>&1 >out
```

không tương đương.

#### 8.3.1 Trường hợp A

```text
>out
```

trước:

```text
FD1 -> out
FD2 -> terminal
```

sau:

```text
2>&1
```

FD2 duplicate current FD1:

```text
FD1 -> out
FD2 -> out
```

#### 8.3.2 Trường hợp B

Bắt đầu:

```text
FD1 -> terminal
FD2 -> terminal
```

`2>&1`:

```text
FD2 -> current FD1 -> terminal
```

sau đó `>out`:

```text
FD1 -> out
FD2 -> terminal
```

ASCII:

```text
A: >out 2>&1

stdout ----+
           +----> out
stderr ----+


B: 2>&1 >out

stdout ---------> out
stderr ---------> terminal
```

Bài học:

> **Redirection là thao tác trên descriptor graph; thứ tự thay đổi graph.**

---

## 9. Pipe và Pipeline

### 9.1 Pipe: kênh byte-stream do kernel quản lý


Pipe là IPC primitive.

Ở mức concept:

```text
writer process
      |
      | bytes
      v
 +-----------+
 | kernel    |
 | pipe      |
 | buffer    |
 +-----------+
      |
      | bytes
      v
reader process
```

Pipe có read end và write end.

#### 9.1.1 Pipe không phải temporary regular file

Data thường nằm trong kernel-managed pipe buffering, không phải shell tạo một file trung gian rồi ghi toàn bộ output.

#### 9.1.2 Pipe là byte stream

Pipe không tự biết:

```text
line
JSON object
record
CSV row
log event
```

Đó là convention/protocol giữa producer và consumer.

#### 9.1.3 EOF

Reader thấy EOF khi không còn writer giữ write end và buffered data đã đọc hết.

Đây là lý do việc đóng unused pipe descriptors quan trọng trong process implementation.

#### 9.1.4 Broken pipe và SIGPIPE

Nếu process write vào pipe nhưng không còn reader, write có thể thất bại với `EPIPE` và process có thể nhận `SIGPIPE` theo normal Unix semantics.

Điều này giải thích tại sao producer trong pipeline đôi khi kết thúc sớm khi downstream command không cần thêm input.

---

### 9.2 Pipeline: process composition thay vì “chuyển text bằng shell”


Shell pipeline syntax:

```text
producer | consumer
```

POSIX semantics cốt lõi:

```text
stdout của command bên trái
        ↓
pipe
        ↓
stdin của command bên phải
```

Mental model:

```text
+----------+       kernel pipe       +----------+
| producer | FD1 ==================> | consumer |
+----------+                          +----------+
                                      FD0
```

Shell không cần đọc từng dòng rồi truyền lại.

Nó chủ yếu:

```text
create pipe
wire descriptors
start commands
wait according to shell semantics
```

#### 9.2.1 Pipeline nhiều stage

```text
A | B | C
```

conceptually:

```text
A stdout
   |
 pipe1
   |
B stdin
B stdout
   |
 pipe2
   |
C stdin
```

Mỗi stage có thể chạy concurrently.

#### 9.2.2 Pipeline là composition interface

Utility nhỏ có thể chuyên một việc:

```text
produce
filter
transform
aggregate
format
```

và được nối bằng stream.

Đây là Unix composability.

#### 9.2.3 stderr mặc định không đi vào `|`

Normal pipeline nối:

```text
left FD1 -> pipe
```

FD2 vẫn theo target riêng, thường terminal.

Bash có syntax extension để pipe stdout+stderr, nhưng phải phân biệt với POSIX `|`.

#### 9.2.4 Pipeline exit status

POSIX/Bash normal behavior khi `pipefail` không bật thường lấy status từ rightmost command.

Bash `pipefail` thay rule để pipeline phản ánh failure của command phù hợp trong pipeline.

Vì vậy:

```text
data flow success
```

và:

```text
pipeline status rule
```

là hai concept riêng.

---

## 10. Exit Status và Shell Control Flow

### 10.1 Exit status và contract giữa các command


Một command hoàn thành với exit status.

Convention phổ biến:

```text
0     success
nonzero  failure / false / special condition
```

Nhưng ý nghĩa cụ thể của nonzero status thuộc utility.

Không nên hiểu:

```text
1 luôn nghĩa "generic fatal error"
```

#### 10.1.1 Status 126 và 127

POSIX shell semantics:

```text
127
command not found

126
command name found but not executable utility
```

Đây là diagnostic clue quan trọng.

#### 10.1.2 Signal termination

Shell biểu diễn command bị signal terminate bằng status > 128 theo POSIX rule, với exact mapping có implementation-defined aspects.

Bash thường dùng convention:

```text
128 + signal_number
```

nhưng khi nói portable semantics nên không khẳng định mapping này cho mọi shell như một định luật POSIX universal.

#### 10.1.3 `$?`

Trong shell, special parameter `$?` phản ánh status của pipeline/command gần nhất theo shell rules.

Nó là transient state.

Một command khác chạy sau đó có thể overwrite value.

#### 10.1.4 Exit status là machine-readable control channel

stdout có thể là:

```text
human/data output
```

stderr:

```text
diagnostic
```

exit status:

```text
small control result
```

Ba channel khác nhau.

Mental model:

```text
process result
   |
   +--> stdout   data
   +--> stderr   diagnostic
   +--> status   success/control outcome
```

---

### 10.2 Command lists, `&&`, `||`, `;` và control flow


Shell command language dùng exit status để xây control flow.

#### 10.2.1 `;`

Concept:

```text
A ; B
```

B được xét/chạy sau A bất kể A success hay failure, trừ các shell termination/event conditions khác.

#### 10.2.2 `&&`

```text
A && B
```

B chạy khi A có success status theo shell condition semantics.

Mental model:

```text
A
 |
 +-- success --> B
 |
 +-- failure --> stop this AND-list path
```

#### 10.2.3 `||`

```text
A || B
```

B chạy khi A thất bại theo status semantics.

```text
A
 |
 +-- success --> stop this OR-list path
 |
 +-- failure --> B
```

#### 10.2.4 `&&` và `||` không truyền data

Chúng truyền **control decision** dựa trên exit status.

Khác với:

```text
|
```

là stream/data connection.

Tách:

```text
|      data flow
&&     conditional control flow on success
||     conditional control flow on failure
```

---

## 11. Foreground, Background và Job Control

### 11.1 Foreground, background, session và job-control ở mức nền tảng


Interactive shell thường có khái niệm job control.

#### 11.1.1 Foreground job

Foreground process group là group được terminal cho phép tương tác terminal input theo normal job-control semantics.

TTY-generated signals như `SIGINT` thường nhắm foreground process group.

Mental model:

```text
controlling terminal
        |
        v
foreground process group
        |
     command(s)
```

#### 11.1.2 Background job

Shell syntax:

```text
command &
```

cho asynchronous/background execution.

Background process vẫn có:

```text
stdin/stdout/stderr descriptors
environment
cwd
```

nhưng terminal access/job-control behavior có thể khác.

#### 11.1.3 Shell không đồng nghĩa process group

Một pipeline có thể gồm nhiều processes trong một process group để shell quản lý như một job.

Chi tiết process group/session/signal sẽ học ở Process và Signal topics.

Ở Topic 1 chỉ cần mental model:

```text
terminal
   |
session
   |
shell
   |
jobs
   +--> foreground process group
   +--> background process groups
```

---

## 12. Các Utility cơ bản theo Abstraction

### 12.1 Các utility cơ bản dưới góc nhìn abstraction


Roadmap yêu cầu “các lệnh cơ bản”, nhưng mục tiêu không phải tạo dictionary command.

Nên phân loại theo resource/abstraction.

#### 12.1.1 Navigation / naming context

```text
pwd
cd
ls
```

Mental model:

```text
pwd -> process current-working-directory view
cd  -> change shell cwd
ls  -> inspect directory entries / metadata view
```

Chi tiết filesystem sang Topic 2.

#### 12.1.2 File/directory manipulation

```text
mkdir
cp
mv
rm
ln
touch
```

Ở mức Topic 1:

```text
mkdir -> create directory namespace object
cp    -> copy content/metadata according to options
mv    -> rename/move, possibly copy+remove across filesystems
rm    -> unlink/remove names/trees according to options
ln    -> create links
touch -> update timestamps or create empty file depending state
```

Exact inode/link semantics ở Topic 2.

#### 12.1.3 Text/stream utilities

```text
cat
head
tail
wc
sort
uniq
cut
tr
printf
```

Có thể nhìn như các transform:

```text
cat
stream concatenation/pass-through

head/tail
stream selection

wc
aggregation/count

sort
ordering transform

uniq
adjacent duplicate processing

cut
field/column selection

tr
character translation/deletion

printf
formatted stream producer
```

#### 12.1.4 Search/filter

```text
grep
find
```

Hai command đều “tìm” nhưng ở abstraction khác:

```text
grep
search/filter contents or input lines

find
traverse filesystem hierarchy and evaluate file predicates/actions
```

#### 12.1.5 Process observation

```text
ps
top
```

```text
ps
snapshot-style process information

top
repeated/dynamic system and process display
```

#### 12.1.6 Storage/filesystem observation

```text
mount
df
du
```

```text
mount -> attachment/mount topology and operations
df    -> filesystem capacity/accounting
du    -> usage attributed to file hierarchy
```

---

## 13. Search và Filtering: `grep`, `find`

### 13.1 `grep`: stream filtering bằng pattern matching


GNU `grep` tìm lines match pattern.

Mental model:

```text
input stream/files
      |
      v
line-oriented scanning
      |
      v
pattern matcher
      |
  +---+---+
  |       |
match   no match
  |
selected output/status
```

#### 13.1.1 `grep` là consumer/filter

`grep` có thể nhận input từ:

```text
file operands
stdin
pipeline
```

Vì vậy nó rất phù hợp Unix pipeline model.

#### 13.1.2 Pattern và regex dialect

GNU `grep` có các matcher mode như:

```text
BRE  Basic Regular Expressions
ERE  Extended Regular Expressions
fixed strings
PCRE2-based mode khi hỗ trợ
```

Không nên nói:

```text
grep pattern = shell wildcard
```

Hai language khác nhau.

#### 13.1.3 Line-oriented semantics

Common `grep` behavior xử lý input theo lines.

Pattern success thường quyết định line nào được selected.

Options có thể thay:

```text
invert selection
print line number
count
show context
recursive traversal
binary handling
```

nhưng abstraction cốt lõi vẫn là:

```text
select information from stream based on pattern
```

#### 13.1.4 `grep` exit status có semantic value

GNU/POSIX `grep` thường dùng:

```text
0 -> selected line found
1 -> no selected line
>1 -> error
```

Đây là ví dụ tốt chứng minh:

```text
nonzero
```

không luôn có nghĩa “program crashed”.

`1` có thể là legitimate query result.

---

### 13.2 `find`: traversal của filesystem hierarchy


GNU `find` bắt đầu từ một hoặc nhiều starting points và traverse directory hierarchy.

Mental model:

```text
start path(s)
      |
      v
filesystem traversal
      |
      v
for each encountered entry
      |
      v
evaluate expression
      |
  +---+------------------+
  |                      |
tests/predicates       actions
```

#### 13.2.1 `find` expression là một language nhỏ

Expression có thể gồm:

```text
tests
actions
operators
options
```

Tests có thể liên quan:

```text
name
type
size
time
ownership
permissions
path
```

Actions có thể:

```text
print
execute command
delete
```

Tại Topic 1 chỉ cần hiểu abstraction, không đi vào destructive operations.

#### 13.2.2 `find` khác shell glob

Shell glob:

```text
expands pathnames trước command invocation
```

`find`:

```text
program tự traverse hierarchy sau khi chạy
```

Sơ đồ:

```text
Shell glob

shell
  |
  +--> read directory
  +--> expand *.c
  |
  v
program gets list


find

shell starts find
       |
       v
find itself traverses filesystem tree
```

#### 13.2.3 Quote và ownership của pattern

Pattern passed cho `find -name` cần được shell truyền đúng.

Nếu shell expand wildcard trước, `find` có thể nhận argument khác intended.

Đây là ví dụ điển hình của two-language problem:

```text
shell pattern syntax layer
       +
find expression/pattern layer
```

---

## 14. Process Observation: `ps`, `top`

### 14.1 `ps`: snapshot của process state


`ps` thuộc procps-ng ecosystem trên Linux.

Mental model:

```text
kernel process state
       |
   /proc + system interfaces
       |
       v
      ps
       |
       v
formatted snapshot
```

`ps` không “theo dõi liên tục” theo mặc định.

Nó tạo một view tại thời điểm command thu thập information.

#### 14.1.1 Process identity và attributes

Fields thường gặp:

```text
PID
PPID
TTY
state
CPU time
command
user
memory-related metrics
```

Exact output phụ thuộc options/personality.

#### 14.1.2 `ps` có nhiều option syntax tradition

Linux `ps` hỗ trợ:

```text
UNIX options with -
BSD options without -
GNU long options with --
```

Mix option style có thể thay default selection/display.

Đây là lý do `ps` syntax trông phức tạp hơn nhiều GNU utility khác.

#### 14.1.3 Snapshot không phải ground truth tuyệt đối bất biến

Process table thay đổi trong lúc `ps` đọc.

Process có thể:

```text
start
exit
change state
```

trong quá trình snapshot.

Output nên hiểu là **observation của dynamic system**.

---

### 14.2 `top`: dynamic view của process/system activity


`top` cũng thuộc procps-ng.

Khác `ps`, `top` cập nhật display theo interval.

Mental model:

```text
sample system/process counters
       ↓
wait interval
       ↓
sample again
       ↓
derive rates/percentages
       ↓
refresh display
       ↓
repeat
```

#### 14.2.1 CPU percentage là measurement theo interval

CPU usage không phải một field tĩnh “lưu trong process”.

Nó thường được suy ra từ thay đổi counters theo thời gian.

Concept:

```text
counter at t1
counter at t2
      |
      v
delta / elapsed interval
      |
      v
CPU usage estimate/display
```

#### 14.2.2 Load average không phải CPU percentage

Linux load average liên quan runnable/uninterruptible task load semantics, không đơn giản là:

```text
CPU utilization %
```

Do đó:

```text
load = 4
```

không trực tiếp nghĩa:

```text
CPU = 400%
```

Context số CPU và task states quan trọng.

#### 14.2.3 Memory fields cần hiểu theo Linux memory model

Các metric như:

```text
VIRT
RES
SHR
```

không nên cộng/trừ naively để suy ra “RAM thật của process” trong mọi trường hợp.

Shared mappings, page cache, virtual mappings làm memory accounting phức tạp.

Topic Process/Memory sẽ đi sâu.

---

## 15. Filesystem/Storage Observation: `mount`, `df`, `du`

### 15.1 `mount`: quan sát và thay đổi filesystem attachment


`mount` nằm trong util-linux trên GNU/Linux phổ biến.

Command này liên quan cơ chế mount của kernel.

Ở Topic 1 chỉ cần mental model:

```text
filesystem instance
        |
        | attach
        v
mount point in namespace
```

Ví dụ topology:

```text
/
├── home
├── proc   <-- procfs mounted here
├── sys    <-- sysfs mounted here
└── mnt
    └── data <-- another filesystem may mount here
```

#### 15.1.1 Mount không đồng nghĩa disk

Filesystem có thể là:

```text
ext4
tmpfs
procfs
sysfs
NFS
SquashFS
...
```

Một số không có block device phía dưới.

#### 15.1.2 `mount` output không phải interface tốt nhất để programmatically parse

Modern util-linux có `findmnt` để query mount topology rõ ràng hơn.

`/proc/self/mountinfo` là kernel-exposed detailed mount information.

Topic File System sẽ đào sâu.

#### 15.1.3 Embedded Linux relevance

Boot sequence cuối cùng cần root filesystem được mount.

Các pseudo-filesystem:

```text
/proc
/sys
/dev
```

cũng là phần quan trọng của running userspace.

---

### 15.2 `df`: filesystem-wide space accounting


GNU `df` báo:

```text
filesystem space used
filesystem space available
total size
mount point
```

Mental model:

```text
selected pathname
      |
      v
filesystem containing pathname
      |
      v
filesystem accounting/statistics
      |
      v
df report
```

#### 15.2.1 `df` không walk toàn bộ file tree

Nó không cần cộng size từng file như `du`.

Nó query filesystem statistics.

Do đó `df` trả lời:

> **Filesystem này đang có capacity/usage accounting như thế nào?**

#### 15.2.2 Mounted filesystem context

Nếu không có operand, GNU `df` thường report mounted filesystems theo utility rules.

Pseudo/duplicate filesystems có filtering rules riêng.

#### 15.2.3 “Available” không luôn bằng `total - used` theo trực giác user

Filesystem có thể có:

```text
reserved blocks
metadata accounting
filesystem-specific policies
```

Do đó exact fields cần hiểu theo filesystem/utility semantics.

---

### 15.3 `du`: file-tree disk-usage accounting


GNU `du` ước lượng file space usage cho file/directory operands.

Mental model:

```text
starting path
     |
     v
walk reachable entries
     |
     v
read allocation-related metadata
     |
     v
aggregate usage
```

Nó trả lời:

> **Những file reachable từ path này đang được quy bao nhiêu storage usage?**

#### 15.3.1 `du` không giống logical file-size sum

Sparse file là ví dụ:

```text
logical size large
allocated blocks small
```

`du` default thường quan tâm allocated space hơn apparent/logical size.

#### 15.3.2 Hard links

Nếu cùng inode xuất hiện qua nhiều hard links, utility có rules để tránh double counting trong common modes.

#### 15.3.3 Mount boundaries

`du` có thể cross filesystem boundaries hoặc bị giới hạn bởi option.

Do đó tree view có thể không trùng filesystem capacity view.

---

### 15.4 `df` và `du` khác nhau về câu hỏi đang trả lời


Đây là distinction cần nhớ từ đầu.

```text
df
 |
 +--> filesystem accounting

du
 |
 +--> pathname tree accounting
```

ASCII:

```text
                    Filesystem
                 /             \
                /               \
               v                 v
       allocation tables       namespace
              |                   |
              v                   v
             df                  du
```

#### 15.4.1 Open-but-unlinked file

Một case kinh điển:

```text
process opens log
      ↓
directory entry is removed
      ↓
process still holds open reference
      ↓
blocks still allocated
```

Kết quả:

```text
du may no longer reach old pathname
df still sees allocated filesystem space
```

Đây là một ví dụ cho:

```text
namespace
!=
storage allocation state
```

Topic File System/File I/O sẽ giải thích kỹ hơn.

#### 15.4.2 Filesystem metadata

`df` accounting có thể bao gồm allocations không được `du` quy trực tiếp cho visible files theo cách user mong đợi.

Do đó chênh lệch không tự động là bug.

---

## 16. Command Line như một Data-flow System

### 16.1 Command line như một data-flow system


Sau khi hiểu:

```text
stdin
stdout
stderr
pipe
redirection
exit status
```

có thể nhìn shell command line như một data-flow/control-flow environment.

#### 16.1.1 Data plane

```text
producer stdout
      |
     pipe
      |
filter stdin
      |
filter stdout
      |
     pipe
      |
consumer stdin
```

#### 16.1.2 Diagnostic plane

Mỗi process có thể giữ:

```text
stderr
  |
  v
terminal / log
```

tách khỏi normal data pipeline.

#### 16.1.3 Control plane

```text
exit status
    |
    +--> &&
    +--> ||
    +--> if
    +--> shell logic
```

Ba lớp:

```text
DATA
stdout/stdin/pipe

DIAGNOSTIC
stderr

CONTROL
exit status
```

Đây là một mental model rất mạnh cho automation.

---

#### 16.1.4 Pipeline architecture

```mermaid
flowchart LR
    A[Producer Process] -->|stdout / FD 1| P1[(Kernel Pipe)]
    P1 -->|stdin / FD 0| B[Filter Process]
    B -->|stdout / FD 1| P2[(Kernel Pipe)]
    P2 -->|stdin / FD 0| C[Consumer Process]

    A -. stderr / FD 2 .-> T[Terminal or Log]
    B -. stderr / FD 2 .-> T
    C -. stderr / FD 2 .-> T
```

Mermaid này chỉ mô tả stream wiring, không hàm ý shell copy data từng byte.

---

## 17. Error Model và Debugging

### 17.1 Error model và tư duy debug command line


Khi command fail, đừng bắt đầu bằng việc đoán command syntax.

Phân loại layer trước.

Mental model:

```text
1. terminal/input problem?
        ↓
2. shell parse/quote problem?
        ↓
3. expansion problem?
        ↓
4. command lookup problem?
        ↓
5. permission/executable-format problem?
        ↓
6. redirection/pipe problem?
        ↓
7. program argument/option problem?
        ↓
8. underlying resource/system problem?
```

---

#### 17.1.1 “command not found”

Likely layer:

```text
shell command lookup
```

Possible causes:

```text
PATH does not contain location
executable absent
typo
shell cache/stale path
command belongs to missing package
```

POSIX shell status typically:

```text
127
```

---

#### 17.1.2 “Permission denied” before program starts

Could be:

```text
execute bit missing
directory search permission missing
filesystem mounted noexec
security policy
interpreter unavailable in script context
```

Do not assume:

```text
chmod 777
```

is the correct answer.

Need identify which layer denied operation.

---

#### 17.1.3 “No such file or directory” dù executable trông tồn tại

Possible deeper causes include:

```text
pathname component missing
symlink target missing
ELF interpreter/dynamic loader missing
script shebang interpreter missing
architecture/format problems can produce different errors
```

Therefore shell-visible error message may come from deeper executable loading path.

---

#### 17.1.4 Unexpected argument count

Likely:

```text
quoting
word splitting
globbing
```

Mental model:

```text
typed word
   ↓
expansion
   ↓
argv elements
```

Debugging nên nghĩ ở `argv`, không chỉ nhìn text.

---

#### 17.1.5 Pipeline hides upstream failure

Default pipeline status may come from final stage.

Thus:

```text
A fails
B receives empty input but exits success
```

pipeline can look successful depending shell/options.

This is why `pipefail` exists in shells like Bash.

---

#### 17.1.6 Output “missing”

Check descriptor routing:

```text
stdout redirected?
stderr redirected?
pipeline consumes output?
program buffers output differently on TTY vs pipe/file?
```

C stdio programs may use different buffering mode depending destination, so absence/delay of visible output không nhất thiết means program never produced data.

---

#### 17.1.7 Environment-dependent behavior

Same executable can behave differently because:

```text
PATH
LANG/locale
HOME
TERM
working directory
umask
environment variables
stdin type
TTY vs pipe
```

Therefore reproducibility requires understanding execution context.

---

## 18. Liên hệ với Embedded Linux

### 18.1 Vì sao command line đặc biệt quan trọng trong Embedded Linux?


Embedded Linux thường giảm bớt UI stack nhưng giữ low-level text interfaces.

#### 18.1.1 Early bring-up

Khi board chưa có:

```text
display
network
GUI
application stack
```

UART console có thể vẫn cung cấp:

```text
bootloader console
kernel logs
init messages
shell
```

Command-line literacy lúc này là foundational.

#### 18.1.2 BusyBox

Minimal rootfs thường dùng BusyBox để cung cấp nhiều applets:

```text
sh
ls
cat
mount
ps
grep
find
...
```

Các applet có option set có thể nhỏ hơn GNU full utilities.

Do đó cần hiểu **abstraction/semantics**, không phụ thuộc một option cụ thể.

#### 18.1.3 RootFS debugging

Các symptom:

```text
cannot mount root fs
init not found
service fails
device node missing
library missing
permission denied
```

được điều tra qua:

```text
shell
filesystem utilities
/proc
/sys
/dev
logs
```

#### 18.1.4 Driver interaction

Sau này driver có thể expose:

```text
/dev/...
/sys/...
/proc/...
```

Command line trở thành observation/control surface.

Mental model:

```text
shell utility
      ↓
filesystem/device interface
      ↓
kernel subsystem
      ↓
driver
      ↓
hardware
```

#### 18.1.5 Remote management

Embedded target thường được access qua:

```text
serial
SSH
network service
```

CLI dễ truyền qua low-bandwidth text channels và dễ automate.

#### 18.1.6 Build systems

Cross-compilation, kernel, Buildroot và Yocto đều phụ thuộc command-line environment:

```text
make
compiler
shell scripts
environment variables
filesystem tools
```

Nếu shell semantics yếu, build/debug problem dễ bị hiểu sai.

#### 18.1.7 Production/debug separation

Production product có thể không expose interactive shell cho end-user vì security.

Nhưng engineer vẫn cần command-line knowledge để:

```text
development
factory
service mode
debug image
recovery
CI/build
diagnostics
```

---

## 19. Tổng kết và Mental Model

### 19.1 Mô hình tư duy tổng hợp


Một command-line interaction có thể nhìn từ trên xuống:

```text
+----------------------------------------------------+
|                     USER                           |
+----------------------------------------------------+
                         |
                         v
+----------------------------------------------------+
|          TERMINAL / SERIAL / SSH FRONTEND          |
+----------------------------------------------------+
                         |
                         v
+----------------------------------------------------+
|                    TTY / PTY                       |
| input discipline, terminal semantics, job control  |
+----------------------------------------------------+
                         |
                         v
+----------------------------------------------------+
|                      SHELL                         |
|                                                    |
| parse                                               |
|   ↓                                                 |
| quote / expand                                      |
|   ↓                                                 |
| command lookup                                      |
|   ↓                                                 |
| configure FD graph                                  |
|   ↓                                                 |
| builtin/function OR external process                |
+----------------------------------------------------+
             |                          |
             |                          |
             v                          v
      shell state                 process image
      cd/export/...               argv + environment
                                        |
                                        v
+----------------------------------------------------+
|               FILE DESCRIPTOR GRAPH                |
|                                                    |
| FD0 stdin   FD1 stdout   FD2 stderr                 |
|     \          |             /                      |
|      \      pipes/files/TTY/devices                 |
+----------------------------------------------------+
                         |
                         v
+----------------------------------------------------+
|                      KERNEL                        |
| process | filesystem | device | memory | network    |
+----------------------------------------------------+
```

Một mental model khác nhấn mạnh shell transformations:

```text
Command Text
    |
    v
Parse
    |
    v
Expansion
    |
    v
Words / argv candidates
    |
    v
Lookup
    |
    +--> builtin/function
    |
    +--> external executable
             |
             v
         Process
             |
      +------+------+
      |             |
    stdin         stdout
      |             |
      +--- pipe -----+
             |
           next process
```

Và mental model cuối cho các utility roadmap:

```text
                            Linux System
                                |
        +-----------------------+------------------------+
        |                       |                        |
        v                       v                        v
   Filesystem tree          Processes              Mounted FS
        |                       |                        |
        |                       |                        |
   +----+----+             +----+----+             +-----+-----+
   |         |             |         |             |           |
 grep?     find           ps        top          df           mount
   |         |             |         |             |
content   namespace     snapshot   dynamic      capacity
filter    traversal      view       view        accounting

                         file tree
                            |
                            v
                           du
                            |
                     attributed usage
```

Lưu ý:

```text
grep
```

không phải filesystem traversal utility về bản chất;

nó là stream/content matcher.

`find` mới là hierarchy traversal utility.

---

### 19.2 Các nguyên tắc cốt lõi


1. Command line là một execution/composition environment, không chỉ là nơi nhập text.

2. Terminal và shell là hai lớp khác nhau: terminal xử lý terminal I/O/display; shell hiểu command language.

3. TTY là kernel terminal abstraction; PTY là virtual master/slave terminal pair.

4. Interactive terminal emulator thường giao tiếp với shell qua PTY chứ không phải terminal hardware thật.

5. Serial console trong Embedded Linux làm terminal abstraction dễ quan sát hơn vì có hardware UART ở phía dưới.

6. Shell vừa là parser vừa là execution coordinator.

7. POSIX shell semantics và Bash extensions phải được phân biệt khi nói về portability.

8. Shell grammar được xử lý trước khi external program nhận arguments.

9. Program không nhận raw shell command line; nó nhận argument vector sau shell parsing/expansion.

10. Quote characters chủ yếu điều khiển shell interpretation; chúng thường không trở thành ký tự trong final argument.

11. Unquoted expansion có thể tạo nhiều argv elements qua word splitting và filename expansion.

12. Shell globbing và regular expression là hai pattern language khác nhau.

13. Builtin, shell function và external executable là ba loại execution entity khác nhau.

14. Một số operation như `cd` phải ảnh hưởng current shell state nên không thể được hiểu đơn giản như child executable bình thường.

15. `PATH` là command-search path, không phải filesystem search engine chung.

16. Command chứa `/` được xử lý bằng explicit pathname thay vì normal PATH search.

17. Current working directory là state của process; relative pathname được resolve trong context đó.

18. Shell variable không tự động là environment variable.

19. `export` làm selected shell variables được đưa vào environment của future executed commands.

20. Child process nhận environment từ parent context nhưng không thể trực tiếp sửa environment của parent theo normal process isolation.

21. `execve()` thay program image của calling process; nó không có nghĩa “tạo PID mới”.

22. `fork + exec` là mental model rất hữu ích cho shell external-command execution nhưng không phải mọi shell command bắt buộc tạo child theo đúng một implementation path.

23. FD 0, 1, 2 lần lượt là stdin, stdout và stderr theo standard convention.

24. stdin/stdout/stderr là descriptor interfaces, không đồng nghĩa terminal.

25. Redirection được shell setup bằng cách thay descriptor targets trước/khi command chạy.

26. Thứ tự redirection quan trọng vì descriptor duplication tham chiếu target hiện tại tại thời điểm operation xảy ra.

27. Pipe là kernel-managed byte stream, không phải temporary regular file.

28. Pipeline nối stdout của stage trước với stdin stage sau; shell không cần copy từng line.

29. stderr không tự đi qua normal `|`.

30. Exit status là control result, tách khỏi stdout và stderr.

31. Zero thường biểu diễn success; nonzero semantics phải đọc theo utility.

32. POSIX dùng 127 cho command not found và 126 cho command found nhưng không executable utility.

33. `&&`/`||` dùng exit status để tạo control flow; `|` dùng data stream để tạo data flow.

34. `grep` là content/stream filter dựa trên pattern; `find` là filesystem hierarchy traversal engine.

35. `grep` regex không phải shell glob.

36. `ps` là snapshot view của process state; `top` là repeated/dynamic sampling view.

37. `mount` nói về filesystem attachment vào namespace, không chỉ “ổ đĩa”.

38. `df` query filesystem-wide capacity/accounting; `du` aggregate usage từ pathname tree.

39. `df` và `du` khác nhau không có nghĩa một trong hai sai; chúng đo hai abstraction khác nhau.

40. Command-line debugging nên xác định layer: terminal → shell parsing → expansion → lookup → redirection → program arguments → resource/kernel.

41. “Permission denied”, “command not found”, “no such file” có thể đến từ các lớp khác nhau và không nên chữa bằng một công thức duy nhất.

42. Environment, cwd, locale, terminal type và descriptor routing đều là execution context.

43. Command line rất quan trọng trong Embedded Linux vì serial console, SSH, BusyBox, boot diagnostics và driver interfaces đều dựa mạnh vào text/system interfaces.

44. Học command line đúng nghĩa là hiểu chuỗi:

```text
terminal
   ↓
shell
   ↓
parse / expand
   ↓
lookup
   ↓
process or builtin
   ↓
file descriptors
   ↓
kernel resources
```

---

## 20. Tài liệu tham khảo


Nguồn của chapter được ưu tiên theo thứ tự:

```text
POSIX / standards
        ↓
upstream GNU documentation
        ↓
Linux kernel / Linux man-pages
        ↓
upstream utility project documentation
        ↓
recognized Embedded Linux training material
        ↓
reputable community documentation for edge cases
```

Các nguồn cộng đồng chỉ nên dùng để:

```text
quan sát case thực tế
tìm symptom
tìm keyword
đối chiếu behavior distribution-specific
```

Không dùng community answer thay specification/manual khi xác định semantics nền tảng.

---

### POSIX / The Open Group

#### Shell Command Language — POSIX

- https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html

Nguồn chuẩn cho:

```text
shell grammar
token/word/operator
quoting
parameter expansion
command substitution
redirection
pipeline
lists
command search
environment
exit status
```

Các điểm được dùng đặc biệt trong chapter:

```text
pipeline wiring
exit status 126/127
command search
redirection order/context
shell-language semantics
```

#### POSIX standard utilities

- https://pubs.opengroup.org/onlinepubs/9799919799/idx/utilities.html

Dùng để phân biệt:

```text
portable utility behavior
vs
GNU/Linux extension
```

---

### GNU Bash

#### GNU Bash Reference Manual

- https://www.gnu.org/software/bash/manual/

Nguồn chính cho Bash-specific shell semantics:

```text
shell syntax
shell operation
quoting
shell expansions
redirections
pipelines
command search/execution
environment
exit status
job control
builtins
```

Các section đặc biệt liên quan:

```text
3.1 Shell Syntax
3.2 Shell Commands
3.5 Shell Expansions
3.6 Redirections
3.7 Executing Commands
4   Shell Builtin Commands
7   Job Control
```

Lưu ý:

```text
Bash manual
!=
POSIX portability guarantee
```

Bash có extensions ngoài POSIX.

---

### Linux man-pages

Linux man-pages project là reference chính cho Linux kernel / libc userspace interface.

#### `pty(7)`

- https://man7.org/linux/man-pages/man7/pty.7.html

Nguồn cho:

```text
pseudoterminal master/slave
terminal emulator
SSH/network login PTY
UNIX 98 PTY
```

#### `pts(4)`

- https://man7.org/linux/man-pages/man4/pts.4.html

Nguồn cho:

```text
/dev/ptmx
/dev/pts/*
devpts
PTY allocation model
```

#### `tty(4)`

- https://man7.org/linux/man-pages/man4/tty.4.html

Nguồn cho:

```text
controlling terminal
/dev/tty
TTY relationship with process/session
```

#### `termios(3)`

- https://man7.org/linux/man-pages/man3/termios.3.html

Nguồn bổ sung cho:

```text
canonical mode
echo
terminal special characters
terminal attributes
```

#### `environ(7)`

- https://man7.org/linux/man-pages/man7/environ.7.html

Nguồn chính cho:

```text
environment array
name=value
inheritance
environment passed during program execution
```

#### `execve(2)`

- https://man7.org/linux/man-pages/man2/execve.2.html

Nguồn cho:

```text
program execution
argv
envp
process image replacement
ELF/script interpreter context
```

#### `fork(2)`

- https://man7.org/linux/man-pages/man2/fork.2.html

Nguồn nền cho Unix parent/child process mental model.

#### `pipe(2)` và `pipe(7)`

- https://man7.org/linux/man-pages/man2/pipe.2.html
- https://man7.org/linux/man-pages/man7/pipe.7.html

Nguồn cho:

```text
pipe read/write ends
kernel pipe behavior
EOF
EPIPE/SIGPIPE
pipe capacity semantics
```

#### `dup(2)`

- https://man7.org/linux/man-pages/man2/dup.2.html

Nguồn để hiểu descriptor duplication phía dưới shell redirection.

---

### GNU Coreutils

#### GNU Coreutils Manual

- https://www.gnu.org/software/coreutils/manual/

Nguồn upstream cho các utility:

```text
pwd
ls
cat
head
tail
wc
sort
uniq
cut
tr
mkdir
cp
mv
rm
ln
touch
df
du
```

Các phần chapter dùng nhiều:

```text
Directory listing
Basic operations
Text operations
File space usage
```

#### `df`

GNU Coreutils mô tả `df` là utility report amount of space used/available trên filesystems.

Mental model được giữ trong chapter:

```text
df -> filesystem-wide accounting
```

#### `du`

GNU Coreutils mô tả `du` là utility estimate file space usage.

Mental model:

```text
du -> selected file/tree usage
```

---

### GNU Grep

#### GNU Grep Manual

- https://www.gnu.org/software/grep/manual/

Nguồn cho:

```text
grep matching model
BRE / ERE
fixed strings
selected lines
recursive behavior
exit status
```

Đặc biệt:

```text
0  selected line found
1  no selected line
2  error
```

theo normal GNU grep semantics, với options có thể ảnh hưởng behavior.

---

### GNU Findutils

#### GNU Findutils Manual

- https://www.gnu.org/software/findutils/manual/

Nguồn cho:

```text
find
locate
xargs
filesystem hierarchy traversal
find expressions
tests/actions/operators
```

Chapter chỉ dùng `find` ở mức abstraction.

Các destructive action không thuộc phạm vi Topic 1.

---

### procps-ng

#### procps-ng upstream

- https://gitlab.com/procps-ng/procps

Project upstream cho:

```text
ps
top
free
vmstat
...
```

#### `ps(1)`

- https://man7.org/linux/man-pages/man1/ps.1.html

Nguồn cho:

```text
process selection
output formats
UNIX/BSD/GNU option styles
snapshot process reporting
```

#### `top(1)`

- https://man7.org/linux/man-pages/man1/top.1.html

Nguồn cho:

```text
dynamic process/system display
CPU/memory fields
sampling/refresh behavior
interactive process monitoring
```

---

### util-linux

#### util-linux upstream

- https://github.com/util-linux/util-linux

Project upstream chứa nhiều Linux system utilities.

#### `mount(8)`

- https://man7.org/linux/man-pages/man8/mount.8.html

Nguồn cho:

```text
mount utility
filesystem attachment
mount options
mount table behavior
```

#### `findmnt(8)`

- https://man7.org/linux/man-pages/man8/findmnt.8.html

Nguồn cho:

```text
query mount topology
/proc/self/mountinfo based views
filesystem/mount relationships
```

---

### Linux kernel documentation

#### The TTY subsystem

- https://docs.kernel.org/driver-api/tty/

Nguồn kernel-level bổ sung cho:

```text
TTY driver model
line discipline
terminal driver architecture
```

Topic 1 chỉ dùng mental model, không đi vào driver API.

#### Filesystems / proc interfaces

- https://docs.kernel.org/filesystems/proc.html

Bổ sung cho cách tools/process observation liên hệ với kernel-exported `/proc` information.

---

### Bootlin Embedded Linux training

#### Embedded Linux System Development

- https://bootlin.com/training/embedded-linux/
- https://bootlin.com/doc/training/embedded-linux/

Bootlin được dùng để đối chiếu **scope Embedded Linux thực tế**:

```text
Linux host command line
serial console
cross-development environment
root filesystem
BusyBox
system integration
```

Điểm quan trọng:

> Command-line knowledge là nền để đi tiếp vào toolchain, bootloader, kernel, rootfs và embedded target debugging; nó không phải một chủ đề tách biệt khỏi Embedded Linux.

---

### BusyBox

#### BusyBox official documentation

- https://busybox.net/
- https://busybox.net/downloads/BusyBox.html

Nguồn cho context Embedded Linux:

```text
single multi-call binary
shell/applications in minimal rootfs
ash shell
core utility applets
```

Khi chuyển từ Ubuntu HOST sang embedded rootfs, cần nhớ:

```text
GNU utility
vs
BusyBox applet
```

có thể khác option set nhưng cùng phục vụ nhiều abstraction tương tự.

---

### Reputable community references

Community documentation chỉ được xem là **nguồn bổ sung**, không phải authority cao hơn POSIX/upstream docs.

#### ArchWiki

- https://wiki.archlinux.org/

Có giá trị cho:

```text
real Linux system behavior
shell environment
terminal/console context
system troubleshooting
distribution integration
```

#### Unix & Linux Stack Exchange

- https://unix.stackexchange.com/

Có giá trị khi nghiên cứu:

```text
edge cases
shell quoting surprises
TTY/PTY behavior
pipeline/redirection debugging
filesystem/process symptom analysis
```

Một answer cộng đồng chỉ nên được dùng sau khi:

```text
xác định exact behavior
      ↓
đối chiếu POSIX/manual/upstream source
      ↓
kiểm tra version/system context
```

---

### Nguyên tắc kiểm chứng khi đọc tài liệu command line

Nếu gặp hai nguồn nói khác nhau, kiểm tra theo thứ tự:

```text
1. Behavior đó là POSIX hay GNU/Bash/Linux-specific?
2. Shell nào?
3. Utility implementation nào?
4. Version nào?
5. Interactive hay non-interactive?
6. TTY hay pipe/file?
7. Environment/cwd khác nhau không?
8. Source upstream nói gì?
```

Không nên lấy một command example hoạt động trên Ubuntu Bash rồi kết luận:

```text
mọi POSIX shell
mọi BusyBox system
mọi Linux distribution
```

đều có behavior giống hệt.

---

> **Điều hướng:** [← Root README](../README.md) · [Chủ đề 2 — Linux File System →](README-topic-02.md)
