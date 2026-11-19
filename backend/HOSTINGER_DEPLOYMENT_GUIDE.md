# Digital Share — Hostinger VPS Production Deployment Guide (.NET 8 + MySQL)

**Platform:** Hostinger VPS (Ubuntu 22.04 LTS or 24.04 LTS)  
**Stack:** .NET 8 ASP.NET Core Web API, MySQL 8.0 / MariaDB, Nginx Reverse Proxy, Systemd, Let's Encrypt SSL  
**Branding:** Powered by Medindia4u.com  

---

## 1. Prerequisites & Server Preparation

### 1.1 Connect to Hostinger VPS
```bash
ssh root@YOUR_SERVER_IP
```

### 1.2 Update System Packages
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git ufw unzip jq
```

### 1.3 Install .NET 8 ASP.NET Core Runtime
```bash
# Add Microsoft package repository for Ubuntu
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# Install ASP.NET Core 8.0 Runtime
sudo apt update
sudo apt install -y aspnetcore-runtime-8.0

# Verify installation
dotnet --info
```

---

## 2. MySQL Database Setup & Hardening

### 2.1 Verify MySQL Service
```bash
sudo systemctl status mysql
```
If MySQL is not installed:
```bash
sudo apt install -y mysql-server
sudo systemctl enable --now mysql
```

### 2.2 Secure MySQL Installation
```bash
sudo mysql_secure_installation
```
*(Answer Y to validate password plugin if desired, set root password, remove anonymous users, disallow root login remotely, remove test database, and reload privilege tables).*

### 2.3 Create Digital Share Database and Dedicated User
Open the MySQL prompt:
```bash
sudo mysql -u root -p
```
Run the following SQL commands:
```sql
-- 1. Create database with utf8mb4 charset and unicode collation
CREATE DATABASE IF NOT EXISTS digitalshare 
    CHARACTER SET utf8mb4 
    COLLATE utf8mb4_unicode_ci;

-- 2. Create dedicated application user locked to local loopback (127.0.0.1 and localhost)
-- Replace 'STRONG_PASSWORD_HERE_32_CHARS' with your secure production password
CREATE USER IF NOT EXISTS 'digitalshare_user'@'127.0.0.1' IDENTIFIED BY 'STRONG_PASSWORD_HERE_32_CHARS';
CREATE USER IF NOT EXISTS 'digitalshare_user'@'localhost' IDENTIFIED BY 'STRONG_PASSWORD_HERE_32_CHARS';

-- 3. Grant minimum required application privileges
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, REFERENCES, LOCK TABLES, EXECUTE 
    ON digitalshare.* TO 'digitalshare_user'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, REFERENCES, LOCK TABLES, EXECUTE 
    ON digitalshare.* TO 'digitalshare_user'@'localhost';

-- 4. Apply changes
FLUSH PRIVILEGES;

-- 5. Verify character set and database
SELECT schema_name, default_character_set_name, default_collation_name 
FROM information_schema.schemata WHERE schema_name = 'digitalshare';

EXIT;
```

### 2.4 Test MySQL User Connectivity
```bash
mysql -u digitalshare_user -p -h 127.0.0.1 digitalshare
# Enter STRONG_PASSWORD_HERE_32_CHARS
# If successful, type EXIT;
```

---

## 3. Database Schema Migration

You have two simple options to initialize the MySQL schema:

### Option A: Direct SQL Migration (Recommended for instant setup)
Upload `mysql-database-migration.sql` to your VPS (or run on server):
```bash
mysql -u digitalshare_user -p -h 127.0.0.1 digitalshare < mysql-database-migration.sql
```
*Verify that tables were created:*
```bash
mysql -u digitalshare_user -p -h 127.0.0.1 digitalshare -e "SHOW TABLES;"
```

### Option B: Automatic Startup Migration
The Digital Share API automatically executes `dbContext.Database.Migrate()` on application startup. When the API starts with valid MySQL credentials, it initializes and checks the schema automatically.

---

## 4. Application Deployment

### 4.1 Create Application Directory
```bash
sudo mkdir -p /var/www/digitalshare/api
sudo mkdir -p /var/www/digitalshare/uploads/profile-photos
sudo mkdir -p /var/www/digitalshare/uploads/temp-scans
sudo chown -R www-data:www-data /var/www/digitalshare
sudo chmod -R 755 /var/www/digitalshare
```

### 4.2 Upload Published Files
From your development machine, upload the `./publish` directory contents to the server:
```bash
scp -r backend/publish/* root@YOUR_SERVER_IP:/var/www/digitalshare/api/
```
Or via rsync:
```bash
rsync -avz --delete backend/publish/ root@YOUR_SERVER_IP:/var/www/digitalshare/api/
```

### 4.3 Configure Production Environment Variables (.env)
Create the secure production environment configuration on the VPS:
```bash
sudo nano /var/www/digitalshare/api/.env
```
Paste and fill in your actual production values:
```bash
# ASP.NET Core Environment
ASPNETCORE_ENVIRONMENT=Production
PORT=5000

# Hostinger Local MySQL Connection String
ConnectionStrings__DefaultConnection=Server=127.0.0.1;Port=3306;Database=digitalshare;User=digitalshare_user;Password=STRONG_PASSWORD_HERE_32_CHARS;CharSet=utf8mb4;

# High-Entropy JWT Secret Key (Minimum 32 characters / 256-bit)
Jwt__Issuer=DigitalShare.Api
Jwt__Audience=DigitalShare.MobileApp
Jwt__SecretKey=REPLACE_WITH_YOUR_UNIQUE_64_CHAR_SECRET_KEY_FOR_PRODUCTION!
Jwt__ExpiryMinutes=60
Jwt__RefreshTokenExpiryDays=30

# File Storage Configuration (Local or Cloudflare R2)
Storage__Provider=Local
Storage__Local__Directory=uploads/temp-scans
Storage__Local__MaxFileSizeMb=20

# Google Gemini API Key (Kept strictly on backend)
Gemini__ApiKey=YOUR_PRODUCTION_GEMINI_API_KEY
Gemini__ModelId=gemini-3.8-flash
Gemini__FallbackModelId=gemini-3.5-flash-lite
Gemini__Enabled=true
```

Set strict file permissions so only `www-data` can read secrets:
```bash
sudo chown -R www-data:www-data /var/www/digitalshare
sudo chmod 600 /var/www/digitalshare/api/.env
```

---

## 5. Systemd Service Configuration

### 5.1 Create Systemd Service File
```bash
sudo nano /etc/systemd/system/digitalshare.service
```
Insert the following configuration:
```ini
[Unit]
Description=Digital Share .NET 8 Web API
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=notify
WorkingDirectory=/var/www/digitalshare/api
ExecStart=/usr/bin/dotnet /var/www/digitalshare/api/DigitalShare.Api.dll
Restart=always
RestartSec=5
KillSignal=SIGINT
SyslogIdentifier=digitalshare-api
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false
EnvironmentFile=/var/www/digitalshare/api/.env

[Install]
WantedBy=multi-user.target
```

### 5.2 Enable and Start the Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable digitalshare.service
sudo systemctl start digitalshare.service
```

### 5.3 Check Service Status and Logs
```bash
sudo systemctl status digitalshare.service
sudo journalctl -u digitalshare.service -n 50 --no-pager
```
*Verify you see:*
`[MySQL Connection Diagnostic] Success=True, Scheme='mysql-key-value', Host='127.0.0.1', Port=3306, Database='digitalshare'`  
`Application started. Press Ctrl+C to shut down.`

---

## 6. Nginx Reverse Proxy & SSL Configuration

### 6.1 Install Nginx
```bash
sudo apt install -y nginx
sudo systemctl enable --now nginx
```

### 6.2 Configure Nginx Site
```bash
sudo nano /etc/nginx/sites-available/digitalshare.conf
```
Paste the following reverse-proxy configuration (replace `api.yourdomain.com` with your subdomain):
```nginx
server {
    listen 80;
    server_name api.yourdomain.com; # Replace with your subdomain

    # Max upload size for card images and profile photos
    client_max_body_size 25M;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection keep-alive;
        proxy_set_header   Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_set_header   X-Forwarded-Host $host;

        proxy_connect_timeout 60s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
    }

    # Static uploads caching
    location /uploads/ {
        alias /var/www/digitalshare/uploads/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
}
```

### 6.3 Enable Nginx Site
```bash
sudo ln -s /etc/nginx/sites-available/digitalshare.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## 7. SSL Certificate Installation (Let's Encrypt / Certbot)

### 7.1 Install Certbot
```bash
sudo apt install -y certbot python3-certbot-nginx
```

### 7.2 Obtain and Install Free SSL Certificate
Ensure your DNS A-record points `api.yourdomain.com` to your Hostinger VPS IP, then run:
```bash
sudo certbot --nginx -d api.yourdomain.com
```
Certbot will automatically configure HTTPS redirect and update the Nginx configuration.

### 7.3 Verify Auto-Renewal
```bash
sudo certbot renew --dry-run
```

---

## 8. Firewall & Security Hardening (UFW)

Keep MySQL and backend internal ports strictly isolated from the internet:
```bash
# Allow SSH
sudo ufw allow OpenSSH

# Allow HTTP and HTTPS
sudo ufw allow 'Nginx Full'

# Ensure MySQL port 3306 is NOT open to the public
sudo ufw deny 3306

# Enable firewall
sudo ufw enable
sudo ufw status verbose
```

---

## 9. Automated MySQL Daily Backups

Create a daily backup script:
```bash
sudo mkdir -p /var/backups/digitalshare-mysql
sudo nano /usr/local/bin/backup-digitalshare.sh
```
Add:
```bash
#!/bin/bash
BACKUP_DIR="/var/backups/digitalshare-mysql"
DATE=$(date +"%Y%m%d_%H%M%S")
FILENAME="$BACKUP_DIR/digitalshare_backup_$DATE.sql.gz"

# Run dump and compress
mysqldump -u digitalshare_user -p'STRONG_PASSWORD_HERE_32_CHARS' -h 127.0.0.1 digitalshare | gzip > "$FILENAME"
chmod 600 "$FILENAME"

# Delete backups older than 14 days
find "$BACKUP_DIR" -type f -name "*.sql.gz" -mtime +14 -delete

echo "[$(date)] Backup completed: $FILENAME" >> "$BACKUP_DIR/backup.log"
```
Make executable and test:
```bash
sudo chmod +x /usr/local/bin/backup-digitalshare.sh
sudo /usr/local/bin/backup-digitalshare.sh
ls -lh /var/backups/digitalshare-mysql
```
Schedule in cron (`sudo crontab -e`):
```cron
0 2 * * * /usr/local/bin/backup-digitalshare.sh
```

---

## 10. Smoke Testing & Verification Checklist

Once deployed, verify the API endpoints:

1. **Liveness Probe:**
   ```bash
   curl -I https://api.yourdomain.com/health
   # Expected: HTTP/1.1 200 OK
   ```

2. **Database Readiness Probe (Verifies MySQL connection and migrations):**
   ```bash
   curl https://api.yourdomain.com/health/ready
   # Expected: {"status":"Healthy","database":"Connected","schema":"Synchronized"}
   ```

3. **User Registration / Login:**
   ```bash
   curl -X POST https://api.yourdomain.com/api/auth/register \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com","password":"Password123!","fullName":"Test User"}'
   ```

4. **Flutter Mobile App Connection:**
   Update your mobile app `baseUrl` in `mobile/lib/config/api_config.dart` or `.env` to:
   `https://api.yourdomain.com`
   The Flutter app will connect seamlessly without any code changes!
