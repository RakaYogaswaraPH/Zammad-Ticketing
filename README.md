# Zammad IT Helpdesk - Custom Build (Diskominfo Kabupaten Bandung)

Repository ini berisi seluruh penyesuaian (kustomisasi) untuk sistem IT Helpdesk Zammad Diskominfo Kabupaten Bandung:

- **Theme & Branding Diskominfo**: Login page, dashboard layout, custom styles.
- **SLA Tracker & Live Reports**: Pelacakan waktu tanggap, durasi pengerjaan live, dan laporan tren durasi SLA.
- **Agent Rating System**: Penilaian bintang dan ulasan komentar pelanggan per petugas via Telegram dan Web.
- **Real-time Dashboard Metrics**: Card simetris 2x2 yang terhubung live dengan database tiket.
- **Security & Optimization**: Proteksi SQLi URL middleware, debouncing, dan caching.

---

## 📖 Panduan Migrasi ke Server Ubuntu

Untuk panduan lengkap langkah-demi-langkah migrasi ke server Diskominfo:
👉 **[Baca PANDUAN_MIGRASI_DISKOMINFO.md](./PANDUAN_MIGRASI_DISKOMINFO.md)**

---

## 🚀 Quick Setup untuk Development / Production

1. Clone official Zammad Docker Compose di folder sebelah:
   ```bash
   cd ~/Zammad
   git clone https://github.com/zammad/zammad-docker-compose.git zammad
   ```
2. Salin file `docker-compose.override.yml`:
   ```bash
   cp ~/Zammad/Zammad-Custom/docker-compose.override.yml ~/Zammad/zammad/docker-compose.override.yml
   ```
3. Jalankan container:
   ```bash
   cd ~/Zammad/zammad
   docker compose up -d
   ```

