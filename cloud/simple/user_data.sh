#!/bin/bash
# EC2 初回起動時の設定: Java（Amazon Corretto 21）と Nginx（80 番 → アプリの 8080 番へ転送）
set -euxo pipefail
dnf install -y java-21-amazon-corretto-headless nginx postgresql16
cat > /etc/nginx/conf.d/app.conf <<'CONF'
server {
    listen 80 default_server;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }
}
CONF
systemctl enable --now nginx
useradd --system --home /opt/app --shell /sbin/nologin app || true
mkdir -p /opt/app && chown app:app /opt/app
cat > /etc/systemd/system/app.service <<'UNIT'
[Unit]
Description=sample-app (Spring Boot)
After=network-online.target

[Service]
User=app
WorkingDirectory=/opt/app
EnvironmentFile=-/opt/app/app.env
ExecStart=/usr/bin/java -jar /opt/app/app.jar
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
