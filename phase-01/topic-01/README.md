# Topic 01 — Bài tập thực hành Basic Linux CMD

> **Mức độ:** Fresher Embedded Linux  
> **Phạm vi:** Terminal, lệnh Linux cơ bản, pipeline, redirection và Bash script cơ bản.  
> **Mục tiêu:** Sau khi hoàn thành, người học có thể thao tác hoàn toàn bằng terminal, xử lý đầu ra bằng pipeline và tự động hóa một số tác vụ đơn giản bằng Bash.

---

## Mục lục

- [Bài 1 — Tạo và quản lý cây thư mục bằng terminal](#bài-1--tạo-và-quản-lý-cây-thư-mục-bằng-terminal)
- [Bài 2 — Tìm kiếm file trong project](#bài-2--tìm-kiếm-file-trong-project)
- [Bài 3 — Đọc và lọc file log](#bài-3--đọc-và-lọc-file-log)
- [Bài 4 — Pipeline cơ bản](#bài-4--pipeline-cơ-bản)
- [Bài 5 — Pipeline xử lý log](#bài-5--pipeline-xử-lý-log)
- [Bài 6 — Phân tích process bằng pipeline](#bài-6--phân-tích-process-bằng-pipeline)
- [Bài 7 — Phân tích dung lượng filesystem](#bài-7--phân-tích-dung-lượng-filesystem)
- [Bài 8 — Redirection: stdout và stderr](#bài-8--redirection-stdout-và-stderr)
- [Bash Script 1 — system_info.sh](#bash-script-1--system_infosh)
- [Bash Script 2 — check_file.sh](#bash-script-2--check_filesh)
- [Bash Script 3 — log_report.sh](#bash-script-3--log_reportsh)
- [Tổng kết kiến thức cần đạt](#tổng-kết-kiến-thức-cần-đạt)

---

# Bài 1 — Tạo và quản lý cây thư mục bằng terminal

## Mục tiêu

Làm quen với:

```text
pwd
ls
cd
mkdir
touch
cp
mv
rm
```

và phân biệt đường dẫn tuyệt đối với đường dẫn tương đối.

## Đề bài

Không dùng File Manager. Tạo cấu trúc:

```text
embedded_app/
├── src/
│   ├── main.c
│   └── uart.c
├── include/
│   └── uart.h
├── config/
│   └── app.conf
├── logs/
│   └── system.log
└── build/
```

Sau đó:

1. Tạo `src/gpio.c` và `include/gpio.h`.
2. Sao chép `config/app.conf` thành `config/app.conf.backup`.
3. Đổi tên `logs/system.log` thành `logs/system_old.log`.
4. Di chuyển `config/app.conf.backup` vào `build/`.
5. Xóa `src/gpio.c` và `include/gpio.h`.
6. Hiển thị lại toàn bộ cây thư mục bằng terminal.

## Lời giải

```bash
mkdir -p embedded_app/{src,include,config,logs,build}
cd embedded_app

touch src/main.c
touch src/uart.c
touch include/uart.h
touch config/app.conf
touch logs/system.log

touch src/gpio.c
touch include/gpio.h

cp config/app.conf config/app.conf.backup
mv logs/system.log logs/system_old.log
mv config/app.conf.backup build/
rm src/gpio.c include/gpio.h

find .
```

Có thể dùng thêm:

```bash
ls -R
```

## Giải thích

```text
mkdir -p   tạo thư mục, kể cả thư mục cha nếu cần
touch      tạo file rỗng nếu file chưa tồn tại
cp         sao chép
mv         di chuyển hoặc đổi tên
rm         xóa file
find .     duyệt cây thư mục từ vị trí hiện tại
```

## Kết quả mong đợi

```text
embedded_app/
├── build/
│   └── app.conf.backup
├── config/
│   └── app.conf
├── include/
│   └── uart.h
├── logs/
│   └── system_old.log
└── src/
    ├── main.c
    └── uart.c
```

---

# Bài 2 — Tìm kiếm file trong project

## Mục tiêu

Làm quen với `find` và các điều kiện tìm kiếm cơ bản.

## Đề bài

Trong `embedded_app`, tạo thêm:

```text
src/spi.c
src/i2c.c
include/spi.h
include/i2c.h
logs/uart.log
logs/error.log
README.txt
```

Yêu cầu:

1. Tìm tất cả file `.c`.
2. Tìm tất cả file `.h`.
3. Tìm file có tên chứa `uart`.
4. Tìm tất cả file `.log`.
5. Tìm tất cả thư mục.
6. Tìm các file được thay đổi trong vòng 1 ngày gần đây.

## Lời giải

```bash
touch src/spi.c src/i2c.c
touch include/spi.h include/i2c.h
touch logs/uart.log logs/error.log
touch README.txt
```

Tìm file `.c`:

```bash
find . -type f -name "*.c"
```

Tìm file `.h`:

```bash
find . -type f -name "*.h"
```

Tìm tên chứa `uart`:

```bash
find . -type f -name "*uart*"
```

Tìm file `.log`:

```bash
find . -type f -name "*.log"
```

Tìm thư mục:

```bash
find . -type d
```

Tìm file vừa thay đổi gần đây:

```bash
find . -type f -mtime -1
```

## Giải thích

```text
.           bắt đầu từ thư mục hiện tại
-type f     chỉ file thường
-type d     chỉ thư mục
-name       lọc theo tên
"*.c"       tên kết thúc bằng .c
"*uart*"    tên chứa uart
-mtime -1   được sửa trong khoảng gần 1 ngày
```

---

# Bài 3 — Đọc và lọc file log

## Mục tiêu

Làm quen với `cat`, `grep`, `head`, `tail`, `wc`.

## Đề bài

Tạo `logs/system.log` có nội dung:

```text
INFO system started
INFO UART initialized
WARN temperature high
ERROR sensor timeout
INFO reconnecting
ERROR network disconnected
WARN voltage low
INFO system running
ERROR UART framing error
INFO retry UART
```

Yêu cầu:

1. Hiển thị toàn bộ log.
2. Chỉ lấy dòng `ERROR`.
3. Chỉ lấy dòng `WARN`.
4. Tìm tất cả dòng chứa `UART`.
5. Tìm `uart` không phân biệt hoa thường.
6. Đếm số dòng `ERROR`.
7. Hiển thị 3 dòng đầu.
8. Hiển thị 3 dòng cuối.

## Lời giải

Tạo dữ liệu:

```bash
cat > logs/system.log <<'LOG'
INFO system started
INFO UART initialized
WARN temperature high
ERROR sensor timeout
INFO reconnecting
ERROR network disconnected
WARN voltage low
INFO system running
ERROR UART framing error
INFO retry UART
LOG
```

Hiển thị toàn bộ:

```bash
cat logs/system.log
```

Chỉ lỗi:

```bash
grep "ERROR" logs/system.log
```

Chỉ cảnh báo:

```bash
grep "WARN" logs/system.log
```

Tìm `UART`:

```bash
grep "UART" logs/system.log
```

Không phân biệt hoa thường:

```bash
grep -i "uart" logs/system.log
```

Đếm lỗi:

```bash
grep "ERROR" logs/system.log | wc -l
```

Ba dòng đầu:

```bash
head -n 3 logs/system.log
```

Ba dòng cuối:

```bash
tail -n 3 logs/system.log
```

## Mô hình tư duy

```text
system.log
    |
   grep
    |
dữ liệu đã lọc
    |
   wc
    |
    v
số lượng
```

---

# Bài 4 — Pipeline cơ bản

## Mục tiêu

Hiểu nguyên lý:

```text
stdout của lệnh trước
        |
        v
stdin của lệnh sau
```

## Đề bài

Dùng `/etc/passwd` làm dữ liệu.

Yêu cầu:

1. Hiển thị các dòng chứa `/bin/bash`.
2. Chỉ lấy tên user.
3. Sắp xếp tên user.
4. Đếm số user dùng `/bin/bash`.

## Lời giải

Lọc dòng:

```bash
grep "/bin/bash" /etc/passwd
```

Chỉ lấy username:

```bash
grep "/bin/bash" /etc/passwd | cut -d: -f1
```

Sắp xếp:

```bash
grep "/bin/bash" /etc/passwd | cut -d: -f1 | sort
```

Đếm:

```bash
grep "/bin/bash" /etc/passwd | cut -d: -f1 | wc -l
```

## Giải thích

Cấu trúc `/etc/passwd` có dạng:

```text
username:x:uid:gid:info:home:shell
```

Vì username là trường đầu tiên và dấu phân cách là `:`, nên:

```bash
cut -d: -f1
```

có nghĩa là lấy trường số 1 với dấu phân cách `:`.

---

# Bài 5 — Pipeline xử lý log

## Mục tiêu

Kết hợp `grep`, `awk`, `sort`, `uniq`, `head`, `tail`, `wc` và redirection.

## Đề bài

Tạo `logs/device.log`:

```text
INFO UART initialized
ERROR SENSOR timeout
WARN CPU temperature
ERROR NETWORK disconnected
ERROR SENSOR timeout
INFO NETWORK connected
WARN BATTERY low
ERROR UART framing
ERROR SENSOR invalid_data
ERROR NETWORK timeout
```

Yêu cầu:

1. Đếm tổng số lỗi.
2. Liệt kê module phát sinh lỗi.
3. Tìm module có nhiều lỗi nhất.
4. Lấy 3 lỗi cuối.
5. Lưu toàn bộ lỗi vào `logs/error_report.txt`.

## Lời giải

```bash
cat > logs/device.log <<'LOG'
INFO UART initialized
ERROR SENSOR timeout
WARN CPU temperature
ERROR NETWORK disconnected
ERROR SENSOR timeout
INFO NETWORK connected
WARN BATTERY low
ERROR UART framing
ERROR SENSOR invalid_data
ERROR NETWORK timeout
LOG
```

Đếm lỗi:

```bash
grep "^ERROR" logs/device.log | wc -l
```

Lấy tên module:

```bash
grep "^ERROR" logs/device.log | awk '{print $2}'
```

Module lỗi nhiều nhất:

```bash
grep "^ERROR" logs/device.log |
awk '{print $2}' |
sort |
uniq -c |
sort -nr |
head -n 1
```

Ba lỗi cuối:

```bash
grep "^ERROR" logs/device.log | tail -n 3
```

Lưu report:

```bash
grep "^ERROR" logs/device.log > logs/error_report.txt
```

## Giải thích pipeline dài

```text
ERROR lines
    |
    v
module name
    |
   sort
    |
nhóm các tên giống nhau
    |
 uniq -c
    |
đếm số lần
    |
sort -nr
    |
lớn nhất trước
    |
 head -n 1
```

---

# Bài 6 — Phân tích process bằng pipeline

## Mục tiêu

Làm quen mức cơ bản với `ps`, `grep`, `sort`, `head`.

> Bài này chỉ dùng process output như dữ liệu. Process internals sẽ học ở topic riêng.

## Đề bài

1. Hiển thị danh sách process.
2. Xem các cột PID, CPU, Memory và Command.
3. Sắp xếp process theo CPU giảm dần.
4. Lấy 5 process sử dụng CPU nhiều nhất.
5. Tìm process có tên chứa `bash`.

## Lời giải

Danh sách process:

```bash
ps aux
```

Top process theo CPU:

```bash
ps -eo pid,%cpu,%mem,comm --sort=-%cpu | head -n 6
```

Dùng `6` vì dòng đầu là header, sau đó còn 5 process.

Tìm `bash`:

```bash
ps aux | grep "[b]ash"
```

## Vì sao dùng `[b]ash`?

Nếu dùng:

```bash
ps aux | grep bash
```

thì chính process `grep bash` có thể xuất hiện trong kết quả.

Pattern:

```text
[b]ash
```

vẫn match chữ `bash`, nhưng command line của `grep` chứa chuỗi `[b]ash`, không phải chuỗi `bash` liên tục theo cách tìm kiếm đó.

---

# Bài 7 — Phân tích dung lượng filesystem

## Mục tiêu

Phân biệt `df` và `du`.

## Đề bài

1. Hiển thị dung lượng filesystem.
2. Hiển thị theo đơn vị dễ đọc.
3. Tìm các thư mục/file chiếm nhiều dung lượng trong `/var`.
4. Hiển thị 5 mục lớn nhất.
5. Giải thích sự khác nhau giữa `df` và `du`.

## Lời giải

Xem filesystem:

```bash
df -h
```

Tìm các mục lớn trong `/var`:

```bash
du -sh /var/* 2>/dev/null | sort -hr | head -n 5
```

## `df` và `du`

`df` trả lời:

```text
Filesystem còn bao nhiêu dung lượng?
```

Mô hình:

```text
df -> mức filesystem
```

`du` trả lời:

```text
File hoặc thư mục này chiếm bao nhiêu dung lượng?
```

Mô hình:

```text
du -> mức cây file/thư mục
```

## Vì sao có `2>/dev/null`?

Một số thư mục có thể không cho user hiện tại đọc.

```bash
2>/dev/null
```

chuyển `stderr` sang `/dev/null` để output chính dễ quan sát hơn.

---

# Bài 8 — Redirection: stdout và stderr

## Mục tiêu

Hiểu:

```text
stdin
stdout
stderr

>
>>
2>
2>>
```

## Đề bài

1. Chạy một lệnh vừa tạo output bình thường vừa tạo lỗi.
2. Lưu stdout vào `result.log`.
3. Lưu stderr vào `error.log`.
4. Chạy thêm một lệnh và nối output vào cuối file.
5. Giải thích sự khác nhau giữa `>` và `>>`.

## Lời giải

Lệnh có cả output và error:

```bash
ls /etc /directory_khong_ton_tai
```

Chỉ redirect stdout:

```bash
ls /etc /directory_khong_ton_tai > result.log
```

Chỉ redirect stderr:

```bash
ls /etc /directory_khong_ton_tai 2> error.log
```

Redirect riêng cả hai:

```bash
ls /etc /directory_khong_ton_tai > result.log 2> error.log
```

Append stdout:

```bash
ls /usr >> result.log
```

Append stderr:

```bash
ls /abc 2>> error.log
```

## Phân biệt `>` và `>>`

```text
>
  ghi mới
  nội dung cũ bị thay thế

>>
  nối thêm vào cuối file
```

## File descriptor chuẩn

```text
0 = stdin
1 = stdout
2 = stderr
```

Do đó:

```bash
2> error.log
```

có nghĩa là chuyển file descriptor số 2 sang `error.log`.

---

# Bash Script 1 — `system_info.sh`

## Mục tiêu

Viết script tạo báo cáo hệ thống cơ bản.

## Đề bài

Viết `system_info.sh` hiển thị:

```text
Hostname
Current user
Current time
Kernel version
Uptime
Memory
Filesystem usage
Top CPU processes
```

## Lời giải

```bash
#!/usr/bin/env bash

echo "======================================"
echo "       SYSTEM INFORMATION REPORT"
echo "======================================"

echo
echo "[HOSTNAME]"
hostname

echo
echo "[USER]"
whoami

echo
echo "[DATE]"
date

echo
echo "[KERNEL]"
uname -r

echo
echo "[UPTIME]"
uptime

echo
echo "[MEMORY]"
free -h

echo
echo "[FILESYSTEM]"
df -h

echo
echo "[TOP CPU PROCESSES]"
ps -eo pid,%cpu,%mem,comm --sort=-%cpu | head -n 6
```

## Phiên bản lưu report vào file

```bash
#!/usr/bin/env bash

REPORT="system_report.txt"

{
    echo "======================================"
    echo "       SYSTEM INFORMATION REPORT"
    echo "======================================"

    echo
    echo "[HOSTNAME]"
    hostname

    echo
    echo "[USER]"
    whoami

    echo
    echo "[DATE]"
    date

    echo
    echo "[KERNEL]"
    uname -r

    echo
    echo "[UPTIME]"
    uptime

    echo
    echo "[MEMORY]"
    free -h

    echo
    echo "[FILESYSTEM]"
    df -h

    echo
    echo "[TOP CPU PROCESSES]"
    ps -eo pid,%cpu,%mem,comm --sort=-%cpu | head -n 6
} > "$REPORT"

echo "Report created: $REPORT"
```

## Kiến thức chính

```text
#!/usr/bin/env bash
  chọn Bash để chạy script

VARIABLE="value"
  khai báo biến

"$VARIABLE"
  lấy giá trị biến và quote an toàn

{ ...; } > file
  redirect output của cả một nhóm lệnh
```

---

# Bash Script 2 — `check_file.sh`

## Mục tiêu

Học argument, `if`, test và exit status.

## Đề bài

Script chạy theo dạng:

```bash
./check_file.sh <path>
```

Kiểm tra:

```text
đường dẫn có tồn tại không?
regular file hay directory?
có thể đọc không?
có thể ghi không?
có thể thực thi không?
```

Nếu thiếu argument, script phải trả exit status khác `0`.

## Lời giải

```bash
#!/usr/bin/env bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path>"
    exit 1
fi

PATH_TO_CHECK="$1"

if [ ! -e "$PATH_TO_CHECK" ]; then
    echo "ERROR: Path does not exist: $PATH_TO_CHECK"
    exit 2
fi

echo "Path: $PATH_TO_CHECK"

if [ -f "$PATH_TO_CHECK" ]; then
    echo "Type: regular file"
elif [ -d "$PATH_TO_CHECK" ]; then
    echo "Type: directory"
else
    echo "Type: other"
fi

if [ -r "$PATH_TO_CHECK" ]; then
    echo "Readable: yes"
else
    echo "Readable: no"
fi

if [ -w "$PATH_TO_CHECK" ]; then
    echo "Writable: yes"
else
    echo "Writable: no"
fi

if [ -x "$PATH_TO_CHECK" ]; then
    echo "Executable: yes"
else
    echo "Executable: no"
fi

exit 0
```

## Giải thích

Các biến đặc biệt:

```text
$#   số argument
$0   tên script
$1   argument thứ nhất
```

Các test:

```text
-e   tồn tại
-f   regular file
-d   directory
-r   readable
-w   writable
-x   executable/searchable
```

Luôn ưu tiên quote biến đường dẫn:

```bash
[ -f "$PATH_TO_CHECK" ]
```

thay vì:

```bash
[ -f $PATH_TO_CHECK ]
```

vì đường dẫn có thể chứa dấu cách hoặc ký tự đặc biệt.

### Exit status dùng trong bài

```text
0   thành công
1   sai cách gọi script
2   đường dẫn không tồn tại
```

---

# Bash Script 3 — `log_report.sh`

## Mục tiêu

Kết hợp argument, kiểm tra đầu vào, pipeline, biến và command substitution.

## Đề bài

Script chạy:

```bash
./log_report.sh system.log
```

và hiển thị:

```text
Log file      :
Total lines   :
INFO count    :
WARN count    :
ERROR count   :
Last ERROR    :
```

Nếu file không tồn tại, trả exit status khác `0`.

## Lời giải

```bash
#!/usr/bin/env bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <log_file>"
    exit 1
fi

LOG_FILE="$1"

if [ ! -f "$LOG_FILE" ]; then
    echo "ERROR: File not found: $LOG_FILE"
    exit 2
fi

TOTAL_LINES=$(wc -l < "$LOG_FILE")
INFO_COUNT=$(grep -c "^INFO" "$LOG_FILE")
WARN_COUNT=$(grep -c "^WARN" "$LOG_FILE")
ERROR_COUNT=$(grep -c "^ERROR" "$LOG_FILE")
LAST_ERROR=$(grep "^ERROR" "$LOG_FILE" | tail -n 1)

echo "======================================"
echo "             LOG REPORT"
echo "======================================"

echo "Log file    : $LOG_FILE"
echo "Total lines : $TOTAL_LINES"
echo "INFO count  : $INFO_COUNT"
echo "WARN count  : $WARN_COUNT"
echo "ERROR count : $ERROR_COUNT"

if [ -n "$LAST_ERROR" ]; then
    echo "Last ERROR  : $LAST_ERROR"
else
    echo "Last ERROR  : none"
fi

exit 0
```

## Giải thích

Command substitution:

```bash
TOTAL_LINES=$(wc -l < "$LOG_FILE")
```

Bash chạy phần bên trong `$()` rồi gán output cho biến.

`grep -c`:

```bash
grep -c "^ERROR" file
```

đếm số dòng phù hợp.

Dấu `^` nghĩa là bắt đầu dòng, nên:

```text
^ERROR
```

chỉ khớp dòng bắt đầu bằng `ERROR`.

Kiểm tra chuỗi không rỗng:

```bash
[ -n "$LAST_ERROR" ]
```

---

# Tổng kết kiến thức cần đạt

Sau 8 bài và 3 Bash script, một Fresher Embedded Linux nên giải thích được các phần sau.

## 1. Terminal cơ bản

```text
pwd
cd
ls
mkdir
touch
cp
mv
rm
find
```

## 2. Đường dẫn

Phân biệt:

```text
absolute path
relative path
```

Ví dụ:

```text
/home/user/project/src/main.c
```

là đường dẫn tuyệt đối.

```text
src/main.c
```

là đường dẫn tương đối nếu đang đứng ở thư mục gốc của project.

## 3. Pipeline

Hiểu:

```text
command A
   |
   v
stdout
   |
   v
stdin
   |
   v
command B
```

Ví dụ:

```bash
grep "ERROR" system.log | wc -l
```

## 4. Redirection

Hiểu:

```text
>
>>
2>
2>>
```

và:

```text
stdin  = fd 0
stdout = fd 1
stderr = fd 2
```

## 5. Xử lý text cơ bản

Biết dùng ở mức cơ bản:

```text
grep
cut
awk
sort
uniq
head
tail
wc
```

Không yêu cầu thành thạo `awk` nâng cao ở Topic 01.

## 6. Bash cơ bản

Biết:

```text
shebang
variable
argument
if
test
command substitution
exit status
```

## 7. Exit status

```text
command/script
      |
      v
exit status
      |
      +--> 0      thành công
      |
      +--> != 0   lỗi hoặc điều kiện đặc biệt
```

Kiểm tra exit status gần nhất:

```bash
echo $?
```

## 8. Chuẩn Fresher nên đạt

Bạn nên tự xử lý được một tác vụ dạng:

```text
1. nhận đầu vào
2. kiểm tra đầu vào
3. gọi Linux command
4. nối pipeline
5. lọc output
6. lưu report
7. trả exit status hợp lý
```

Mô hình cuối Topic 01:

```text
Linux utilities
      |
      v
   stdout
      |
      v
   pipeline
      |
      v
lọc / biến đổi
      |
      v
 Bash script
      |
      v
report / exit status
```
