#!/usr/bin/env bash
# ==============================================================================
# Script tự động cấu hình và triển khai Spring Boot Systemd Service (Bài 3)
# ==============================================================================

set -euo pipefail

echo "=========================================================="
echo " [1/5] Khởi tạo MySQL Database & User"
echo "=========================================================="
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS springboot_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'spring-admin'@'localhost' IDENTIFIED BY 'SpringSecure@123';
CREATE USER IF NOT EXISTS 'spring-admin'@'%' IDENTIFIED BY 'SpringSecure@123';
GRANT ALL PRIVILEGES ON springboot_db.* TO 'spring-admin'@'localhost';
GRANT ALL PRIVILEGES ON springboot_db.* TO 'spring-admin'@'%';
FLUSH PRIVILEGES;
EOF
echo "=> Đã tạo database springboot_db và user spring-admin thành công."

echo "=========================================================="
echo " [2/5] Tạo User hệ thống spring-runner (Non-root, No login)"
echo "=========================================================="
if ! id -u spring-runner >/dev/null 2>&1; then
    sudo useradd -r -s /bin/false -d /opt/spring-app -m spring-runner
    echo "=> Đã tạo user spring-runner."
else
    echo "=> User spring-runner đã tồn tại."
fi

echo "=========================================================="
echo " [3/5] Cấp quyền thư mục /opt/spring-app"
echo "=========================================================="
sudo mkdir -p /opt/spring-app
if [ -f "./app.jar" ]; then
    sudo cp ./app.jar /opt/spring-app/
    echo "=> Đã copy app.jar vào /opt/spring-app/"
fi
sudo chown -R spring-runner:spring-runner /opt/spring-app
sudo chmod 750 /opt/spring-app

echo "=========================================================="
echo " [4/5] Cài đặt tệp cấu hình Systemd Service"
echo "=========================================================="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo cp "${SCRIPT_DIR}/spring-app.service" /etc/systemd/system/spring-app.service
sudo chmod 644 /etc/systemd/system/spring-app.service

sudo systemctl daemon-reload
sudo systemctl enable spring-app.service
sudo systemctl restart spring-app.service

echo "=========================================================="
echo " [5/5] Kiểm tra kết quả triển khai"
echo "=========================================================="
echo "Trạng thái dịch vụ:"
sudo systemctl status spring-app.service --no-pager || true

echo ""
echo "Kiểm tra cổng 8082:"
ss -tlnp | grep 8082 || echo "Đang đợi ứng dụng khởi động hoàn tất trên cổng 8082..."
