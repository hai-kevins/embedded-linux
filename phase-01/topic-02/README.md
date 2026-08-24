# Topic 02 — Bài tập thực hành Linux File System

> **Mức độ:** Fresher Embedded Linux  
> **Phạm vi:** `ls -l`, `stat`, `file`, permission, ownership, `chmod`, `chown`, `umask`, `mount`, `umount`, `findmnt`, `df`, `du`.  
> **Mục tiêu:** Sau khi hoàn thành, người học có thể quan sát metadata của file, hiểu permission/ownership, hiểu `umask`, và hình dung đúng bản chất của mount point trong Linux.
>
> **Lưu ý an toàn:** Các bài mount sử dụng `tmpfs` trong thư mục lab. Không thao tác với partition, `mkfs`, ổ đĩa thật hoặc thiết bị lưu trữ quan trọng.

---

## Mục lục

- [Bài 1 — Phân biệt các loại file bằng `ls -l`, `stat`, `file`](#bài-1--phân-biệt-các-loại-file-bằng-ls--l-stat-file)
- [Bài 2 — So sánh `ls -l`, `stat` và `file`](#bài-2--so-sánh-ls--l-stat-và-file)
- [Bài 3 — Thực hành `chmod` với file](#bài-3--thực-hành-chmod-với-file)
- [Bài 4 — Permission của directory khác file như thế nào?](#bài-4--permission-của-directory-khác-file-như-thế-nào)
- [Bài 5 — Ownership với `chown`](#bài-5--ownership-với-chown)
- [Bài 6 — Hiểu `umask`](#bài-6--hiểu-umask)
- [Bài 7 — Mount một `tmpfs`](#bài-7--mount-một-tmpfs)
- [Bài 8 — Mount point che nội dung bên dưới như thế nào?](#bài-8--mount-point-che-nội-dung-bên-dưới-như-thế-nào)
- [Mini Challenge — `filesystem_report.sh`](#mini-challenge--filesystem_reportsh)
- [Tổng kết kiến thức cần đạt](#tổng-kết-kiến-thức-cần-đạt)

---

# Bài 1 — Phân biệt các loại file bằng `ls -l`, `stat`, `file`

## Mục tiêu

Hiểu ba công cụ:

```text
ls -l
stat
file
```

và phân biệt:

```text
regular file
directory
symbolic link
```

## Đề bài

Trong `~/topic02_lab`, tạo:

```text
file_types/
├── regular.txt
├── directory/
└── link.txt -> regular.txt
```

Sau đó dùng `ls -l`, `stat`, `file` để trả lời:

1. `regular.txt` là loại gì?
2. `directory/` là loại gì?
3. `link.txt` là loại gì?
4. Permission của từng đối tượng là gì?
5. Owner và group là ai?
6. Inode của từng đối tượng là bao nhiêu?
7. Kích thước của từng đối tượng là bao nhiêu?
8. `stat link.txt` và `stat -L link.txt` khác nhau ở đâu?

## Lời giải

```bash
mkdir -p file_types/directory
touch file_types/regular.txt
ln -s regular.txt file_types/link.txt
```

Kiểm tra:

```bash
ls -l file_types
```

Dùng `file`:

```bash
file file_types/regular.txt
file file_types/directory
file file_types/link.txt
```

Dùng `stat`:

```bash
stat file_types/regular.txt
stat file_types/directory
stat file_types/link.txt
```

Theo symbolic link tới target:

```bash
stat -L file_types/link.txt
```

### Giải thích

Ký tự đầu của `ls -l`:

```text
-
  regular file

d
  directory

l
  symbolic link
```

Mental model:

```text
pathname
   |
   v
directory entry
   |
   v
inode / metadata
   |
   +--> file type
   +--> permission
   +--> owner
   +--> group
   +--> size
   +--> timestamps
```

Phân biệt:

```text
ls -l
  → tổng quan metadata

stat
  → metadata chi tiết

file
  → nhận diện loại/nội dung của đối tượng
```

---

# Bài 2 — So sánh `ls -l`, `stat` và `file`

## Mục tiêu

Hiểu mỗi công cụ trả lời một câu hỏi khác nhau.

## Đề bài

Tạo:

```text
inspect/
└── hello.txt
```

với nội dung:

```text
Hello Embedded Linux
```

Sau đó điền bảng:

| Thông tin | `ls -l` | `stat` | `file` |
|---|---:|---:|---:|
| Loại file | ? | ? | ? |
| Permission | ? | ? | ? |
| Owner | ? | ? | ? |
| Group | ? | ? | ? |
| Size | ? | ? | ? |
| Inode | ? | ? | ? |
| Nhận diện nội dung | ? | ? | ? |

## Lời giải

```bash
mkdir -p inspect
echo "Hello Embedded Linux" > inspect/hello.txt
```

Kiểm tra:

```bash
ls -l inspect/hello.txt
stat inspect/hello.txt
file inspect/hello.txt
```

Muốn xem inode bằng `ls`:

```bash
ls -li inspect/hello.txt
```

### Đáp án

| Thông tin | `ls -l` | `stat` | `file` |
|---|---:|---:|---:|
| Loại file | Có | Có | Có |
| Permission | Có | Có | Không phải mục tiêu chính |
| Owner | Có | Có | Không |
| Group | Có | Có | Không |
| Size | Có | Có | Không phải mục tiêu chính |
| Inode | Không ở `ls -l` thường | Có | Không |
| Nhận diện nội dung | Không | Không | Có |

Kết luận:

```text
ls -l
  → nhìn nhanh

stat
  → metadata đầy đủ

file
  → nhận diện loại/nội dung
```

---

# Bài 3 — Thực hành `chmod` với file

## Mục tiêu

Hiểu `owner`, `group`, `other` và `r/w/x` ở cả numeric mode và symbolic mode.

## Đề bài

Tạo `permissions/script.sh`:

```bash
#!/usr/bin/env bash
echo "Hello"
```

Lần lượt đặt permission:

```text
rw-r--r--
rwxr-xr-x
rw-------
r--r--r--
```

Yêu cầu:

1. Dùng numeric mode.
2. Dùng symbolic mode.
3. Giải thích `644`, `755`, `600`, `444`.
4. Kiểm tra sau mỗi lần bằng `ls -l`.

## Lời giải

```bash
mkdir -p permissions

cat > permissions/script.sh <<'EOF'
#!/usr/bin/env bash
echo "Hello"
EOF
```

Đặt `644`:

```bash
chmod 644 permissions/script.sh
ls -l permissions/script.sh
```

Đặt `755`:

```bash
chmod 755 permissions/script.sh
```

Đặt `600`:

```bash
chmod 600 permissions/script.sh
```

Đặt `444`:

```bash
chmod 444 permissions/script.sh
```

### Numeric permission

```text
r = 4
w = 2
x = 1
```

Ví dụ:

```text
7 = rwx
6 = rw-
5 = r-x
4 = r--
0 = ---
```

Do đó:

```text
755
owner = rwx
group = r-x
other = r-x
```

### Symbolic mode

```bash
chmod 644 permissions/script.sh
chmod u+x permissions/script.sh
chmod u-w permissions/script.sh
chmod g+r permissions/script.sh
chmod o-rwx permissions/script.sh
```

Ký hiệu:

```text
u = owner
g = group
o = other
a = all

+ = thêm
- = bỏ
= = đặt chính xác
```

Ví dụ:

```bash
chmod u=rw,g=r,o= permissions/script.sh
```

---

# Bài 4 — Permission của directory khác file như thế nào?

## Mục tiêu

Hiểu `r/w/x` trên directory không có ý nghĩa hoàn toàn giống regular file.

## Đề bài

Tạo:

```text
dir_permissions/
└── data.txt
```

Sau đó nghiên cứu các permission:

```text
700
400
100
```

và trả lời:

1. `r` trên directory làm gì?
2. `w` trên directory làm gì?
3. `x` trên directory làm gì?
4. Tại sao có `r` nhưng thiếu `x` vẫn khó truy cập file bên trong?
5. Tại sao quyền xóa file liên quan nhiều tới directory chứa file?

## Lời giải

```bash
mkdir -p dir_permissions
echo "hello" > dir_permissions/data.txt
```

Trường hợp đầy đủ:

```bash
chmod 700 dir_permissions
```

Chỉ có read:

```bash
chmod 400 dir_permissions
ls dir_permissions
```

Khôi phục:

```bash
chmod 700 dir_permissions
```

Chỉ có execute:

```bash
chmod 100 dir_permissions
```

Nếu biết chính xác pathname và file bên trong cho phép, `x` cho phép traverse/search, nhưng thiếu `r` nên không thể liệt kê directory bình thường.

Khôi phục:

```bash
chmod 755 dir_permissions
```

### Ý nghĩa cốt lõi

```text
r trên directory
  → đọc danh sách entry

w trên directory
  → thay đổi entry: create/remove/rename
    thường còn cần x để thao tác pathname hữu ích

x trên directory
  → traverse/search directory
```

Đừng nhầm:

```text
x trên regular file
  → execute

x trên directory
  → traverse/search
```

---

# Bài 5 — Ownership với `chown`

## Mục tiêu

Hiểu `owner`, `group` và cách chúng liên hệ với permission.

## Đề bài

Tạo:

```text
ownership/owner_lab.txt
```

Yêu cầu:

1. Xem owner/group bằng `ls -l`.
2. Xem UID/GID bằng `stat`.
3. Dùng `chown` để thay đổi owner/group trong môi trường phù hợp.
4. Dùng `chgrp` để thay đổi group.
5. Giải thích owner/group liên hệ với permission bits thế nào.

## Lời giải

```bash
mkdir -p ownership
touch ownership/owner_lab.txt
```

Xem owner/group:

```bash
ls -l ownership/owner_lab.txt
```

Xem chi tiết:

```bash
stat ownership/owner_lab.txt
```

Dạng ngắn:

```bash
stat -c 'owner=%U uid=%u group=%G gid=%g mode=%A' ownership/owner_lab.txt
```

Xem group hiện tại:

```bash
groups
```

Đổi group sang một group mà user hiện tại là thành viên:

```bash
chgrp <group_name> ownership/owner_lab.txt
```

Cú pháp `chown`:

```text
chown owner file
chown owner:group file
chown :group file
```

Ví dụ đổi owner thường cần quyền quản trị:

```bash
sudo chown root:root ownership/owner_lab.txt
```

Trả lại:

```bash
sudo chown "$USER":"$(id -gn)" ownership/owner_lab.txt
```

Mental model:

```text
Process muốn truy cập file
          |
          v
Kernel xem credentials
          |
          v
Có phải owner?
   | yes
   v
dùng owner permission bits

nếu không:
có group phù hợp?
   | yes
   v
dùng group permission bits

nếu không:
   |
   v
dùng other permission bits
```

---

# Bài 6 — Hiểu `umask`

## Mục tiêu

Hiểu vì sao file/directory mới tạo không luôn có permission giống nhau.

## Đề bài

Lần lượt thử:

```text
umask 022
umask 027
umask 077
```

Với mỗi giá trị:

1. Tạo một file.
2. Tạo một directory.
3. Kiểm tra permission.
4. So sánh kết quả.

## Lời giải

```bash
mkdir -p umask_lab
cd umask_lab

OLD_UMASK=$(umask)
```

### `umask 022`

```bash
umask 022
touch file_022
mkdir dir_022
stat -c '%a %n' file_022 dir_022
```

Thường:

```text
644 file_022
755 dir_022
```

### `umask 027`

```bash
umask 027
touch file_027
mkdir dir_027
stat -c '%a %n' file_027 dir_027
```

Thường:

```text
640 file_027
750 dir_027
```

### `umask 077`

```bash
umask 077
touch file_077
mkdir dir_077
stat -c '%a %n' file_077 dir_077
```

Thường:

```text
600 file_077
700 dir_077
```

### Mental model

```text
file thường request:
666

directory thường request:
777

        |
        v

umask loại bỏ permission bits

        |
        v

permission cuối
```

Không nên coi `umask` chỉ là phép trừ số học.

Khôi phục:

```bash
umask "$OLD_UMASK"
cd ~/topic02_lab
```

---

# Bài 7 — Mount một `tmpfs`

## Mục tiêu

Hiểu `filesystem`, `mount point`, `mount`, `findmnt`, `df`, `umount` mà không dùng partition thật.

## Đề bài

Tạo:

```text
~/topic02_lab/tmpfs_mount
```

Sau đó:

1. Mount `tmpfs` 16 MiB.
2. Xác định filesystem type.
3. Xác định mount point.
4. Xem dung lượng.
5. Tạo file trong `tmpfs`.
6. Unmount.
7. Quan sát file sau unmount.

## Lời giải

Tạo mount point:

```bash
mkdir -p ~/topic02_lab/tmpfs_mount
```

Mount:

```bash
sudo mount -t tmpfs -o size=16M tmpfs ~/topic02_lab/tmpfs_mount
```

Kiểm tra:

```bash
findmnt ~/topic02_lab/tmpfs_mount
```

Xem dung lượng:

```bash
df -h ~/topic02_lab/tmpfs_mount
```

Tạo file:

```bash
echo "This file lives in tmpfs" > ~/topic02_lab/tmpfs_mount/data.txt
```

Kiểm tra:

```bash
ls -l ~/topic02_lab/tmpfs_mount
```

Unmount:

```bash
sudo umount ~/topic02_lab/tmpfs_mount
```

Kiểm tra lại:

```bash
ls -la ~/topic02_lab/tmpfs_mount
```

`data.txt` không còn xuất hiện.

Mental model:

```text
tmpfs filesystem
      |
      v
mount point
      |
      v
~/topic02_lab/tmpfs_mount
```

Sai:

```text
mount = copy filesystem vào directory
```

Đúng:

```text
mount
=
gắn filesystem vào một vị trí trong filesystem namespace
```

---

# Bài 8 — Mount point che nội dung bên dưới như thế nào?

## Mục tiêu

Hiểu mount có thể che nội dung directory đang tồn tại mà không xóa nội dung cũ.

## Đề bài

Tạo:

```text
mount_cover/
└── original.txt
```

Sau đó:

1. Kiểm tra `original.txt`.
2. Mount `tmpfs` vào `mount_cover/`.
3. Kiểm tra lại.
4. Tạo `inside_tmpfs.txt`.
5. Unmount.
6. Quan sát lại.

## Lời giải

```bash
mkdir -p ~/topic02_lab/mount_cover
echo "original file" > ~/topic02_lab/mount_cover/original.txt
ls -l ~/topic02_lab/mount_cover
```

Mount:

```bash
sudo mount -t tmpfs -o size=16M tmpfs ~/topic02_lab/mount_cover
```

Kiểm tra:

```bash
ls -la ~/topic02_lab/mount_cover
```

`original.txt` không còn nhìn thấy qua mount point.

Tạo file mới trên `tmpfs`:

```bash
echo "tmpfs file" > ~/topic02_lab/mount_cover/inside_tmpfs.txt
```

Kiểm tra:

```bash
ls -l ~/topic02_lab/mount_cover
```

Unmount:

```bash
sudo umount ~/topic02_lab/mount_cover
```

Kiểm tra:

```bash
ls -l ~/topic02_lab/mount_cover
```

`original.txt` xuất hiện trở lại.

### Hình dung

Trước mount:

```text
mount_cover/
└── original.txt
```

Sau mount:

```text
pathname mount_cover/
        |
        v
+----------------------+
|       tmpfs          |
| inside_tmpfs.txt     |
+----------------------+

original.txt vẫn ở filesystem phía dưới,
nhưng bị mount che khỏi view hiện tại.
```

Sau unmount:

```text
mount_cover/
└── original.txt
```

Điểm quan trọng:

```text
mount không xóa nội dung cũ
mount chỉ thay view tại mount point
```

---

# Mini Challenge — `filesystem_report.sh`

## Mục tiêu

Kết hợp Topic 01 và Topic 02:

```text
Bash
argument
if
stat
file
findmnt
permission
ownership
filesystem
mount point
```

## Đề bài

Viết:

```text
filesystem_report.sh
```

chạy:

```bash
./filesystem_report.sh <path>
```

Script cần in:

```text
Path
Object type
Owner
UID
Group
GID
Permission symbolic
Permission numeric
Size
Inode
Hard-link count
Filesystem type
Mount point
```

Yêu cầu:

1. Thiếu argument → exit status khác `0`.
2. Path không tồn tại → báo lỗi.
3. Quote biến đúng.
4. Dùng `stat`.
5. Dùng `file`.
6. Dùng `findmnt`.
7. Trả `0` khi thành công.

## Lời giải

```bash
cat > ~/topic02_lab/filesystem_report.sh <<'EOF'
#!/usr/bin/env bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path>" >&2
    exit 1
fi

TARGET="$1"

if [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    echo "ERROR: Path does not exist: $TARGET" >&2
    exit 2
fi

OBJECT_TYPE=$(file -b "$TARGET")

OWNER=$(stat -c '%U' "$TARGET")
UID_VALUE=$(stat -c '%u' "$TARGET")

GROUP=$(stat -c '%G' "$TARGET")
GID_VALUE=$(stat -c '%g' "$TARGET")

PERM_SYMBOLIC=$(stat -c '%A' "$TARGET")
PERM_NUMERIC=$(stat -c '%a' "$TARGET")

SIZE=$(stat -c '%s' "$TARGET")
INODE=$(stat -c '%i' "$TARGET")
LINKS=$(stat -c '%h' "$TARGET")

FILESYSTEM_TYPE=$(findmnt -T "$TARGET" -n -o FSTYPE)
MOUNT_POINT=$(findmnt -T "$TARGET" -n -o TARGET)

echo "======================================"
echo "        FILESYSTEM OBJECT REPORT"
echo "======================================"

echo "Path                : $TARGET"
echo "Object type         : $OBJECT_TYPE"
echo "Owner               : $OWNER"
echo "UID                 : $UID_VALUE"
echo "Group               : $GROUP"
echo "GID                 : $GID_VALUE"
echo "Permission symbolic : $PERM_SYMBOLIC"
echo "Permission numeric  : $PERM_NUMERIC"
echo "Size                : $SIZE bytes"
echo "Inode               : $INODE"
echo "Hard-link count     : $LINKS"
echo "Filesystem type     : $FILESYSTEM_TYPE"
echo "Mount point         : $MOUNT_POINT"

exit 0
EOF
```

Cho phép thực thi:

```bash
chmod +x ~/topic02_lab/filesystem_report.sh
```

Chạy:

```bash
~/topic02_lab/filesystem_report.sh     ~/topic02_lab/file_types/regular.txt
```

### Giải thích các format của `stat`

```text
%U  owner name
%u  UID

%G  group name
%g  GID

%A  symbolic permission
%a  numeric permission

%s  size
%i  inode
%h  hard-link count
```

### `findmnt -T`

```bash
findmnt -T "$TARGET"
```

tìm filesystem chứa pathname đó.

```text
-n
  bỏ header

-o FSTYPE
  lấy filesystem type

-o TARGET
  lấy mount point
```

Mental model:

```text
path
 |
 v
filesystem object
 |
 +--> type
 +--> inode
 +--> ownership
 +--> permission
 +--> size
 |
 v
filesystem
 |
 v
mount point
```

---

# Tổng kết kiến thức cần đạt

Sau 8 bài và Mini Challenge, một Fresher Embedded Linux nên giải thích được các phần sau.

## 1. Quan sát file và metadata

Biết dùng:

```text
ls -l
stat
file
```

và hiểu:

```text
ls -l
  → xem nhanh loại file, permission, owner, group, size

stat
  → xem metadata chi tiết

file
  → nhận diện loại hoặc nội dung của đối tượng
```

## 2. Loại file và inode

Phân biệt được:

```text
regular file
directory
symbolic link
```

và hiểu mô hình:

```text
pathname
   |
   v
directory entry
   |
   v
inode
   |
   +--> type
   +--> permission
   +--> owner / group
   +--> size
   +--> timestamps
```

Tên file không phải là inode.

## 3. Permission

Hiểu ba nhóm:

```text
owner
group
other
```

và ba quyền:

```text
r
w
x
```

Đọc được các mode cơ bản:

```text
644
755
600
700
750
640
```

Ví dụ:

```text
755

owner  = rwx
group  = r-x
other  = r-x
```

Đồng thời phân biệt được ý nghĩa của `r/w/x` trên regular file và directory.

## 4. Ownership

Hiểu:

```text
owner
group
```

là metadata của filesystem object.

Biết dùng ở mức cơ bản:

```text
chown
chgrp
```

và phân biệt:

```text
chmod
  → thay permission

chown
  → thay owner/group
```

## 5. `umask`

Hiểu mô hình:

```text
permission được yêu cầu khi tạo object
            |
            v
umask loại bỏ một số permission bits
            |
            v
permission cuối
```

Biết giải thích các trường hợp cơ bản:

```text
umask 022
umask 027
umask 077
```

và hiểu vì sao file mới và directory mới thường có permission khác nhau.

## 6. Mount và unmount

Hiểu:

```text
mount
  → gắn filesystem vào một mount point

umount
  → tách filesystem khỏi mount point
```

Không nhầm:

```text
mount
!=
copy dữ liệu vào directory
```

Hiểu rằng khi một filesystem được mount lên directory:

```text
nội dung cũ phía dưới không bị xóa
```

mà chỉ bị che khỏi view tại mount point cho tới khi `umount`.

## 7. Quan sát filesystem

Biết dùng ở mức cơ bản:

```text
findmnt
df
du
```

và phân biệt:

```text
findmnt
  → xem filesystem đang được mount ở đâu

df
  → xem dung lượng ở mức filesystem

du
  → xem dung lượng của file hoặc cây directory
```

## 8. Chuẩn Fresher nên đạt

Bạn nên tự xử lý được một tác vụ dạng:

```text
1. nhận một pathname
2. xác định loại filesystem object
3. đọc metadata
4. đọc owner/group
5. đọc và thay đổi permission
6. giải thích ảnh hưởng của umask
7. xác định filesystem và mount point
8. tạo báo cáo bằng Bash script
```

Mô hình cuối Topic 02:

```text
pathname
   |
   v
directory entry
   |
   v
inode
   |
   +--> type
   +--> owner / group
   +--> permission
   +--> size
   +--> timestamps
   |
   v
filesystem
   |
   v
mount point
   |
   v
Linux filesystem namespace
```

Nếu có thể tự làm lại 8 bài và viết `filesystem_report.sh` mà không chép nguyên lời giải, đồng thời giải thích được từng thông tin mà `ls -l`, `stat`, `file`, `chmod`, `chown`, `umask`, `findmnt`, `df` và `du` cho biết, thì Topic 02 đã đạt mức Fresher Embedded Linux hợp lý.
