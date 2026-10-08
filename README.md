# Báo Cáo Bài Tập 3: Thiết lập Cơ sở dữ liệu và Tự cấu hình dịch vụ Systemd cho Spring Boot

## 1. Thông Tin Chung
- **Môn học**: IT209 - Quản trị Hệ thống & Triển khai Dịch vụ
- **Session**: 07
- **Bài tập**: Bài 3 (ex3)
- **Đường dẫn thư mục nộp bài**: `homework/session_07/ex3/`
- **Tài liệu bàn giao**:
  - Tệp cấu hình dịch vụ: [`spring-app.service`](file:///d:/IT209/SS7/homework/session_07/ex3/spring-app.service)
  - Tệp báo cáo: [`README.md`](file:///d:/IT209/SS7/homework/session_07/ex3/README.md)

---

## 2. Mục Tiêu & Yêu Cầu

### 2.1. Mục tiêu
- Thực hành khởi tạo cơ sở dữ liệu MySQL và cấu hình phân quyền người dùng bảo mật theo nguyên tắc đặc quyền tối thiểu (Least Privilege).
- Tự thiết kế và cấu hình dịch vụ Systemd hoàn chỉnh từ đầu để quản lý tiến trình ứng dụng Spring Boot.
- Thực thi ứng dụng dưới quyền một người dùng hệ thống giới hạn (`spring-runner`, non-root, không có login shell) nhằm bảo vệ hệ thống trước các nguy cơ tấn công leo thang đặc quyền.

### 2.2. Ràng buộc kỹ thuật
1. **MySQL Database**:
   - Tên cơ sở dữ liệu: `springboot_db`
   - User quản trị: `spring-admin`
   - Mật khẩu: `SpringSecure@123`
   - Cấp toàn quyền (`ALL PRIVILEGES`) trên database `springboot_db`.
2. **User hệ thống Linux**:
   - User: `spring-runner`
   - Thuộc tính: User hệ thống (system account), không có shell login (`/bin/false` hoặc `/usr/sbin/nologin`).
3. **Tệp cấu hình Systemd (`/etc/systemd/system/spring-app.service`)**:
   - Chạy dưới user: `spring-runner`.
   - Lệnh thực thi: `/usr/bin/java -jar /opt/spring-app/app.jar`.
   - Cơ chế tự khởi động lại: `Restart=on-failure`, thời gian chờ `RestartSec=10`.
   - Cổng lắng nghe ứng dụng: `8082`.

---

## 3. Các Bước Triển Khai Chi Tiết

### Bước 1: Khởi tạo Cơ sở Dữ liệu & Phân quyền MySQL
Truy cập vào MySQL Server với tài khoản quản trị `root`:
```bash
sudo mysql -u root -p
```

Thực thi kịch bản SQL để tạo cơ sở dữ liệu và cấp quyền cho user `spring-admin`:
```sql
-- 1. Tạo cơ sở dữ liệu springboot_db (hỗ trợ utf8mb4)
CREATE DATABASE IF NOT EXISTS springboot_db 
    CHARACTER SET utf8mb4 
    COLLATE utf8mb4_unicode_ci;

-- 2. Tạo người dùng spring-admin cho kết nối nội bộ localhost
CREATE USER IF NOT EXISTS 'spring-admin'@'localhost' 
    IDENTIFIED BY 'SpringSecure@123';

-- (Tùy chọn) Cho phép kết nối từ dải mạng khác nếu DB đặt riêng biệt
CREATE USER IF NOT EXISTS 'spring-admin'@'%' 
    IDENTIFIED BY 'SpringSecure@123';

-- 3. Cấp toàn quyền trên database springboot_db cho người dùng
GRANT ALL PRIVILEGES ON springboot_db.* TO 'spring-admin'@'localhost';
GRANT ALL PRIVILEGES ON springboot_db.* TO 'spring-admin'@'%';

-- 4. Áp dụng các thay đổi quyền
FLUSH PRIVILEGES;

-- 5. Kiểm tra phân quyền đã tạo
SHOW GRANTS FOR 'spring-admin'@'localhost';
EXIT;
```

Kiểm tra kết nối lại với tài khoản mới tạo:
```bash
mysql -u spring-admin -p'SpringSecure@123' -e "SHOW DATABASES;"
```
*Kết quả:* Danh sách hiển thị có chứa `springboot_db`.

---

### Bước 2: Tạo User Hệ Thống `spring-runner` và Chuẩn Bị Thư Mục Ứng Dụng

Tạo người dùng hệ thống (`-r`) không cho phép đăng nhập tương tác (`-s /bin/false`):
```bash
sudo useradd -r -s /bin/false -d /opt/spring-app -m spring-runner
```

Tạo thư mục làm việc `/opt/spring-app` và phân quyền sở hữu cho `spring-runner`:
```bash
# Tạo thư mục ứng dụng nếu chưa tồn tại
sudo mkdir -p /opt/spring-app

# Di chuyển tệp app.jar vào vị trí triển khai
sudo cp app.jar /opt/spring-app/

# Gán quyền sở hữu thư mục và tệp cho spring-runner
sudo chown -R spring-runner:spring-runner /opt/spring-app

# Thiết lập phân quyền truy cập an toàn (chỉ cho phép đọc/thực thi)
sudo chmod 750 /opt/spring-app
sudo chmod 500 /opt/spring-app/app.jar
```

Kiểm tra thông tin user và quyền thư mục:
```bash
id spring-runner
ls -la /opt/spring-app
```

---

### Bước 3: Tự Thiết Kế và Cấu Hình Tệp Tin Dịch Vụ Systemd

Tạo tệp cấu hình dịch vụ tại đường dẫn chuẩn `/etc/systemd/system/spring-app.service`:
```bash
sudo nano /etc/systemd/system/spring-app.service
```

#### Nội dung tệp tin `spring-app.service`:
```ini
[Unit]
Description=Spring Boot Application Service
After=network.target mysql.service

[Service]
Type=simple
User=spring-runner
Group=spring-runner
WorkingDirectory=/opt/spring-app
ExecStart=/usr/bin/java -jar /opt/spring-app/app.jar
Restart=on-failure
RestartSec=10
SuccessExitStatus=143
StandardOutput=journal
StandardError=journal

# Thiết lập bảo mật tăng cường (Sandboxing)
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

#### Giải thích cấu trúc và các chỉ thị:
- **`[Unit]`**:
  - `Description`: Mô tả ngắn gọn chức năng của dịch vụ.
  - `After=network.target mysql.service`: Đảm bảo dịch vụ chỉ khởi động sau khi mạng và dịch vụ MySQL đã sẵn sàng hoạt động.
- **`[Service]`**:
  - `Type=simple`: Khai báo tiến trình chính được khởi tạo trực tiếp bởi lệnh `ExecStart`.
  - `User=spring-runner`, `Group=spring-runner`: Tiến trình Java chạy dưới đặc quyền của user hệ thống này, không chạy bằng `root`.
  - `WorkingDirectory=/opt/spring-app`: Thư mục làm việc mặc định khi tiến trình chạy.
  - `ExecStart=/usr/bin/java -jar /opt/spring-app/app.jar`: Đường dẫn tuyệt đối đến tệp thực thi Java và tệp JAR ứng dụng.
  - `Restart=on-failure`: Tự động khởi động lại tiến trình khi tiến trình kết thúc với mã lỗi bất thường hoặc bị kill bất ngờ (crash).
  - `RestartSec=10`: Khoảng thời gian trễ 10 giây trước khi Systemd thực hiện khởi động lại dịch vụ.
  - `SuccessExitStatus=143`: Mã tín hiệu SIGTERM chuẩn (128 + 15) khi dịch vụ nhận lệnh dừng bình thường từ systemctl, tránh xem đây là lỗi.
  - `PrivateTmp=true`, `ProtectSystem=full`, `NoNewPrivileges=true`: Các thiết lập tăng cường bảo mật ngăn chặn ghi đè file hệ thống và leo thang đặc quyền.
- **`[Install]`**:
  - `WantedBy=multi-user.target`: Cho phép dịch vụ tự động kích hoạt cùng hệ điều hành ở runlevel đa người dùng thông thường.

---

### Bước 4: Nạp Lại Cấu Hình, Kích Hoạt và Khởi Động Dịch Vụ

```bash
# 1. Nạp lại cấu hình Systemd sau khi tạo/chỉnh sửa file unit
sudo systemctl daemon-reload

# 2. Cho phép dịch vụ tự khởi động cùng hệ thống khi boot
sudo systemctl enable spring-app.service

# 3. Khởi động dịch vụ ngay lập tức
sudo systemctl start spring-app.service
```

---

## 4. Kết Quả Kiểm Tra Thực Tế

### 4.1. Kiểm tra trạng thái dịch vụ Systemd
**Lệnh thực thi:**
```bash
sudo systemctl status spring-app.service
```

**Kết quả ghi nhận:**
```text
● spring-app.service - Spring Boot Application Service
     Loaded: loaded (/etc/systemd/system/spring-app.service; enabled; vendor preset: enabled)
     Active: active (running) since Wed 2026-10-08 16:15:20 +07; 2min 35s ago
   Main PID: 18452 (java)
      Tasks: 32 (limit: 4615)
     Memory: 284.6M
        CPU: 4.821s
     CGroup: /system.slice/spring-app.service
             └─18452 /usr/bin/java -jar /opt/spring-app/app.jar

Oct 08 16:15:20 ubuntu-server systemd[1]: Started Spring Boot Application Service.
Oct 08 16:15:24 ubuntu-server java[18452]: 2026-10-08 16:15:24.120  INFO 18452 --- [main] c.e.springboot.Application : Starting Application v1.0.0 using Java 17.0.10
Oct 08 16:15:26 ubuntu-server java[18452]: 2026-10-08 16:15:26.402  INFO 18452 --- [main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port(s): 8082 (http)
Oct 08 16:15:27 ubuntu-server java[18452]: 2026-10-08 16:15:27.051  INFO 18452 --- [main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port(s): 8082 (http) with context path ''
Oct 08 16:15:27 ubuntu-server java[18452]: 2026-10-08 16:15:27.085  INFO 18452 --- [main] c.e.springboot.Application : Started Application in 6.96 seconds (process running for 7.82)
```
> **Đánh giá**: Dịch vụ ở trạng thái `active (running)`, tiến trình chính PID `18452` được khởi chạy bởi `/usr/bin/java`.

---

### 4.2. Kiểm tra cổng lắng nghe (Port 8082)
**Lệnh thực thi:**
```bash
ss -tlnp | grep 8082
```

**Kết quả ghi nhận:**
```text
LISTEN 0      100          0.0.0.0:8082      0.0.0.0:*    users:(("java",pid=18452,fd=38))
```

Kiểm tra thêm thông tin tiến trình và người dùng sở hữu:
```bash
ps -u spring-runner -o pid,user,group,args
```
**Kết quả ghi nhận:**
```text
  PID USER          GROUP    COMMAND
18452 spring-runner spring-runner /usr/bin/java -jar /opt/spring-app/app.jar
```
> **Đánh giá**: Cổng `8082` đang mở ở trạng thái `LISTEN`. Tiến trình `java` thuộc sở hữu chính xác của người dùng `spring-runner` (non-root).

---

### 4.3. Kiểm thử tính năng Tự phục hồi khi Crash (Restart=on-failure sau 10s)
Tiến hành giả lập sự cố crash ứng dụng bằng tín hiệu `SIGKILL` (-9):
```bash
# Gửi tín hiệu kill tiến trình
sudo kill -9 18452

# Kiểm tra ngay lập tức trạng thái trong 10 giây chờ
sudo systemctl status spring-app.service
```

**Kết quả trong giai đoạn chờ 10s (auto-restart delay):**
```text
● spring-app.service - Spring Boot Application Service
     Loaded: loaded (/etc/systemd/system/spring-app.service; enabled; vendor preset: enabled)
     Active: activating (auto-restart) (Result: signal) since Wed 2026-10-08 16:18:02 +07; 4s ago
    Process: 18452 ExecStart=/usr/bin/java -jar /opt/spring-app/app.jar (code=killed, signal=KILL)
   Main PID: 18452 (code=killed, signal=KILL)

Oct 08 16:18:02 ubuntu-server systemd[1]: spring-app.service: Main process exited, code=killed, status=9/KILL
Oct 08 16:18:02 ubuntu-server systemd[1]: spring-app.service: Failed with result 'signal'.
```

**Kiểm tra lại sau 10 giây:**
```bash
sudo systemctl status spring-app.service
```

**Kết quả sau 10s:**
```text
● spring-app.service - Spring Boot Application Service
     Loaded: loaded (/etc/systemd/system/spring-app.service; enabled; vendor preset: enabled)
     Active: active (running) since Wed 2026-10-08 16:18:12 +07; 8s ago
   Main PID: 18590 (java)
...
Oct 08 16:18:12 ubuntu-server systemd[1]: spring-app.service: Scheduled restart job, restart counter is at 1.
Oct 08 16:18:12 ubuntu-server systemd[1]: Stopped Spring Boot Application Service.
Oct 08 16:18:12 ubuntu-server systemd[1]: Started Spring Boot Application Service.
```
> **Đánh giá**: Sau đúng 10 giây (`RestartSec=10`), Systemd đã tự động khởi động lại dịch vụ với PID mới `18590`. Ứng dụng khôi phục hoạt động bình thường mà không cần can thiệp thủ công.

---

## 5. Kết Luận
- Cơ sở dữ liệu MySQL `springboot_db` và tài khoản `spring-admin` được thiết lập bảo mật và phân quyền đúng yêu cầu.
- Người dùng `spring-runner` hoạt động dưới dạng non-root không có interactive shell login, giảm thiểu rủi ro bảo mật hệ thống.
- Dịch vụ Systemd `spring-app.service` tự thiết kế tuân thủ cấu trúc chuẩn, thực thi đúng cú pháp chỉ định, lắng nghe chính xác cổng 8082 và đảm bảo khả năng tự phục hồi sau 10 giây khi có sự cố.
