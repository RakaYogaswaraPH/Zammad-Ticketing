# 🚀 Panduan Migrasi Zammad Helpdesk ke Server Diskominfo Kabupaten Bandung

Dokumen ini adalah panduan langkah-demi-langkah resmi untuk memindahkan seluruh sistem **Zammad IT Helpdesk (Custom Build)** dari mesin lokal/development ke **Server Ubuntu Diskominfo**.

Repository Kode Kustom: **[https://github.com/RakaYogaswaraPH/Zammad-Ticketing](https://github.com/RakaYogaswaraPH/Zammad-Ticketing)**

---

## 📌 Gambaran Umum Alur Migrasi

```
[LAPTOP / MESIN LOKAL]
   ├── 1. Backup Database PostgreSQL   ──> zammad_production.dump
   ├── 2. Backup Lampiran File/Storage ──> zammad_storage.tar.gz
   ├── 3. Backup Config Nginx Kustom   ──> nginx_custom.conf
   └── 4. Kode Kustom                  ──> Sudah di GitHub (Zammad-Ticketing)
            │
            │ (Transfer via SCP / Git Clone)
            ▼
[SERVER UBUNTU DISKOMINFO]
   ├── 1. Install Docker & Docker Compose
   ├── 2. Set Kernel Parameter (vm.max_map_count untuk Elasticsearch)
   ├── 3. Clone repo official Zammad & repo Zammad-Ticketing
   ├── 4. Pasang docker-compose.override.yml
   ├── 5. Restore Database & Storage Lampiran
   ├── 6. Jalankan Stack (docker compose up -d)
   ├── 7. Rebuild Index Elasticsearch & Pasang Nginx Config
   └── 8. Pengujian & Verifikasi
```

---

## 💻 TAHAP 1: Backup Data dari Laptop (Mesin Lokal)

Buka terminal di laptop kamu, lalu jalankan perintah berikut untuk mengekstrak data yang dibutuhkan:

### 1.1 Backup Database PostgreSQL (Tiket, Akun, Riwayat, Rating, SLA)
```bash
docker exec zammad-zammad-postgresql-1 pg_dump -U zammad -Fc zammad_production > ~/zammad_production.dump
```

### 1.2 Backup File Lampiran Tiket (Storage)
```bash
docker run --rm \
  -v zammad_zammad-storage:/source \
  -v ~/:/backup \
  alpine tar czf /backup/zammad_storage.tar.gz -C /source .
```

### 1.3 Backup Konfigurasi Nginx Kustom
```bash
docker exec zammad-zammad-nginx-1 cat /etc/nginx/sites-available/default > ~/nginx_custom.conf
```

> **Hasil di laptop (`~/`):**
> 1. `~/zammad_production.dump` (~40-50 MB)
> 2. `~/zammad_storage.tar.gz`
> 3. `~/nginx_custom.conf`

---

## 🖥️ TAHAP 2: Setup Awal Server Ubuntu Diskominfo

SSH masuk ke server Ubuntu:
```bash
ssh username@IP_SERVER_DISKOMINFO
```

### 2.1 Update Sistem Operasi & Pasang Paket Dasar
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg lsb-release git rsync ufw
```

### 2.2 Konfigurasi Kernel untuk Elasticsearch (Wajib)
Elasticsearch membutuhkan batas memory map yang lebih tinggi agar tidak crash saat startup:
```bash
# Set langsung
sudo sysctl -w vm.max_map_count=262144

# Permanenkan agar tidak hilang saat server reboot
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 2.3 Install Docker Engine & Docker Compose Plugin
```bash
# 1. Tambahkan GPG key resmi Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 2. Tambahkan repository Docker ke APT
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 3. Install Docker packages
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 4. Beri izin user menjalankan docker tanpa sudo
sudo usermod -aG docker $USER
newgrp docker

# 5. Aktifkan auto-start Docker saat booting
sudo systemctl enable docker
sudo systemctl enable containerd

# 6. Tes instalasi
docker --version
docker compose version
```

---

## 📂 TAHAP 3: Setup Folder & Clone Repository di Server

Di server Ubuntu Diskominfo:

```bash
# 1. Buat folder induk Zammad
mkdir -p ~/Zammad && cd ~/Zammad

# 2. Clone repository kode kustom (Zammad-Ticketing)
git clone https://github.com/RakaYogaswaraPH/Zammad-Ticketing.git Zammad-Custom

# 3. Clone repository official Zammad Docker Compose
git clone https://github.com/zammad/zammad-docker-compose.git zammad

# 4. Salin file docker-compose.override.yml dari Zammad-Custom ke folder zammad
cp ~/Zammad/Zammad-Custom/docker-compose.override.yml ~/Zammad/zammad/docker-compose.override.yml
```

> **Verifikasi isi file `~/Zammad/zammad/docker-compose.override.yml`:**
> Pastikan isinya seperti berikut (path `${HOME}` akan otomatis menunjuk ke home user di server):
> ```yaml
> x-custom-code: &custom-code
>   volumes:
>     - ${HOME}/Zammad/Zammad-Custom/app:/opt/zammad/app:z
>     - ${HOME}/Zammad/Zammad-Custom/lib:/opt/zammad/lib:z
>     - ${HOME}/Zammad/Zammad-Custom/i18n:/opt/zammad/i18n:z
>     - ${HOME}/Zammad/Zammad-Custom/config/routes/sla_reports.rb:/opt/zammad/config/routes/sla_reports.rb:z
>     - ${HOME}/Zammad/Zammad-Custom/config/routes/ticket_open_count.rb:/opt/zammad/config/routes/ticket_open_count.rb:z
> 
> services:
>   zammad-railsserver:
>     <<: *custom-code
>   zammad-scheduler:
>     <<: *custom-code
>   zammad-websocket:
>     <<: *custom-code
> ```

---

## 🚚 TAHAP 4: Kirim File Backup ke Server Diskominfo

Buka terminal **di laptop kamu**, jalankan SCP untuk mengirim 3 file backup:

```bash
# Ganti username dan IP_SERVER_DISKOMINFO dengan data server kamu
scp ~/zammad_production.dump username@IP_SERVER_DISKOMINFO:/home/username/
scp ~/zammad_storage.tar.gz username@IP_SERVER_DISKOMINFO:/home/username/
scp ~/nginx_custom.conf username@IP_SERVER_DISKOMINFO:/home/username/
```

---

## 🗄️ TAHAP 5: Restore Database & File Storage di Server

Kembali ke terminal **server Diskominfo**:

### 5.1 Jalankan Container PostgreSQL Terlebih Dahulu
```bash
cd ~/Zammad/zammad

# Nyalakan hanya container database PostgreSQL
docker compose up -d zammad-postgresql

# Tunggu beberapa detik sampai statusnya "healthy"
docker compose ps
```

### 5.2 Restore Database
```bash
# Pastikan database zammad_production ada
docker exec zammad-zammad-postgresql-1 psql -U postgres -c "CREATE DATABASE zammad_production OWNER zammad;" 2>/dev/null || true

# Restore data dari file dump
docker exec -i zammad-zammad-postgresql-1 pg_restore -U zammad -d zammad_production < ~/zammad_production.dump

# Verifikasi bahwa data tiket dan akun berhasil masuk
docker exec zammad-zammad-postgresql-1 psql -U zammad -d zammad_production -c "SELECT count(*) as total_tiket FROM tickets;"
```

### 5.3 Restore File Storage Lampiran
```bash
docker run --rm \
  -v zammad_zammad-storage:/target \
  -v /home/$USER:/backup \
  alpine tar xzf /backup/zammad_storage.tar.gz -C /target
```

---

## 🚀 TAHAP 6: Jalankan Seluruh Stack Zammad

Di server Diskominfo:

```bash
cd ~/Zammad/zammad

# 1. Download (pull) seluruh container images
docker compose pull

# 2. Jalankan semua service di background
docker compose up -d

# 3. Pantau log inisialisasi awal (tunggu ~3-5 menit)
docker compose logs -f zammad-railsserver
# Tekan Ctrl + C untuk keluar dari tampilan log
```

Cek status seluruh container:
```bash
docker compose ps
```
Pastikan service utama statusnya **healthy**:
- `zammad-railsserver` (healthy)
- `zammad-postgresql` (healthy)
- `zammad-redis` (healthy)
- `zammad-elasticsearch` (healthy)
- `zammad-memcached` (healthy)
- `zammad-nginx` (Up, listening port 8080)

---

## 🔧 TAHAP 7: Konfigurasi Post-Deploy (Sangat Penting)

### 7.1 Pasang Konfigurasi Nginx Kustom (Performa + Proteksi SQLi)
```bash
docker cp ~/nginx_custom.conf zammad-zammad-nginx-1:/etc/nginx/sites-available/default
docker exec zammad-zammad-nginx-1 nginx -s reload
```

### 7.2 Rebuild Search Index Elasticsearch
Karena database baru saja di-restore dari server lain, Elasticsearch index harus di-sinkronkan ulang agar fitur search & overviews normal:
```bash
docker exec -t zammad-zammad-railsserver-1 bundle exec rake zammad:searchindex:rebuild
```
*(Tunggu sampai proses selesai 100%)*

### 7.3 Buka Firewall Port (Jika UFW Aktif)
```bash
sudo ufw allow 8080/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw status
```

---

## 🌐 TAHAP 8: Konfigurasi Domain & Admin UI

1. Buka browser: `http://IP_SERVER_DISKOMINFO:8080`
2. Login menggunakan akun Administrator yang biasa kamu pakai.
3. Masuk ke **Menu Pengaturan Admin**:
   - Pergi ke **Settings** → **System** → **Fully Qualified Domain Name (FQDN)**:
     Isi dengan domain server Diskominfo (misal: `helpdesk.bandungkab.go.id` atau IP server).
   - Atur **HTTP Type**: pilih `https` jika menggunakan SSL/domain, atau `http` jika masih IP langsung.
4. Periksa **Channels** → **Telegram**:
   - Pastikan webhook Telegram mengarah ke domain/alamat baru agar bot rating & notifikasi tetap responsif.

---

## 🔒 TAHAP 9 (Opsional): Pasang Domain & SSL Nginx Host

Jika ingin diakses lewat domain resmi (port 80 / 443 HTTPS):

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

Buat reverse proxy file `/etc/nginx/sites-available/zammad`:
```nginx
server {
    listen 80;
    server_name helpdesk.bandungkab.go.id; # Ganti dengan domain Anda

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 50M;
    }
}
```

Aktifkan config dan dapatkan SSL gratis:
```bash
sudo ln -s /etc/nginx/sites-available/zammad /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d helpdesk.bandungkab.go.id
```

---

## ✅ TAHAP 10: Checklist Pengujian Akhir

Lakukan tes berikut untuk memastikan semua berjalan sempurna:

- [ ] **Akses Web**: Halaman login Diskominfo terbuka dengan lancar.
- [ ] **Autentikasi**: Login Admin dan Agent berhasil.
- [ ] **Dashboard**: Tampil 4 card simetris (2x2) tanpa animasi hover yang resize.
- [ ] **Card SLA**: Durasi tercepat & terlama tampil akurat.
- [ ] **Real-time Ticket**: Card "Tiket Dalam Proses" menampilkan data live.
- [ ] **Halaman SLA**: Laporan SLA dan tren durasi dapat dibuka.
- [ ] **Rating Agen**: Berfungsi dengan komentar dan bintang di tiket zoom.
- [ ] **Keamanan**: Test URL injection dengan `curl -I "http://localhost:8080/api/v1/users?query=1'OR'1'='1"` menghasilkan HTTP **403 Forbidden**.

---

## 🛠️ Perintah Berguna untuk Maintenance di Server

```bash
# Masuk ke folder zammad
cd ~/Zammad/zammad

# Cek status container
docker compose ps

# Lihat logs container tertentu
docker compose logs -f zammad-railsserver
docker compose logs -f zammad-nginx

# Restart service zammad
docker compose restart zammad-railsserver

# Stop seluruh sistem
docker compose down

# Start kembali seluruh sistem
docker compose up -d

# Tarik update kode kustom terbaru dari GitHub
cd ~/Zammad/Zammad-Custom
git pull origin main
docker compose -f ~/Zammad/zammad/docker-compose.yml -f ~/Zammad/zammad/docker-compose.override.yml restart zammad-railsserver
```
