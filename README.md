# 🚀 Auto Installer Pterodactyl — AstraCodeX

<div align="center">

![Version](https://img.shields.io/badge/version-2.0-blue?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-orange?style=for-the-badge)
![License](https://img.shields.io/badge/license-Custom%20License-red?style=for-the-badge)
![Made By](https://img.shields.io/badge/made%20by-AstraCodeX-purple?style=for-the-badge)

**Auto Installer Pterodactyl Panel, Wings, Node, dan Theme**
*Cepat • Mudah • Otomatis*

</div>

---

## ⚡ One-Line Install

Salin dan jalankan perintah ini di VPS Anda (fresh install, **root**):

```bash
bash <(curl -s https://raw.githubusercontent.com/Astra-Devl/installer/main/install.sh)
```

> ⚠️ **Catatan:** Ganti `USERNAME/REPO` dengan username dan nama repository Anda yang sebenarnya.

Atau download manual:

```bash
wget https://raw.githubusercontent.com/Astra-Devl/installer/main/install.sh
chmod +x install.sh
sudo bash install.sh
```

---

## 📖 Tentang Script

**AstraCodeX Auto Installer** adalah script Bash yang dibuat untuk mempermudah proses instalasi **Pterodactyl Panel** beserta komponen pendukungnya seperti **Wings**, **Node**, dan berbagai **Theme** populer secara **otomatis**.

Script ini dirancang untuk pengguna yang ingin menghemat waktu dan menghindari instalasi manual yang rumit.

---

## ✨ Fitur Utama

| No | Fitur | Deskripsi |
|----|-------|-----------|
| 1 | 🎨 **Install Theme** | Stellar, Billing, Enigma, Claymorphism, Elysium, Nebula, Blueprint |
| 2 | 🗑️ **Uninstall Theme** | Rollback tema ke default panel |
| 3 | ⚙️ **Configure Wings** | Setup Wings otomatis via token |
| 4 | 📍 **Create Node** | Buat lokasi & node baru di panel |
| 5 | 📦 **Install Panel** | Install Panel + Wings + Node otomatis |
| 6 | 🧹 **Uninstall Panel** | Hapus panel & wings bersih |
| 7 | 🔒 **Install Protect** | Proteksi panel dari modifikasi ilegal |
| 8 | ♻️ **Restore Protect** | Kembalikan panel ke kondisi sebelum proteksi |
| 9 | 🔑 **Hack Back Panel** | Tambah akun admin darurat |
| 10 | 🔐 **Ubah Password VPS** | Ganti password root VPS dengan cepat |

---

## 🖥️ Persyaratan Sistem

| Komponen | Minimum |
|----------|---------|
| **OS** | Ubuntu 20.04 / 22.04 / 24.04 atau Debian 11 / 12 |
| **RAM** | 1 GB (2 GB direkomendasikan) |
| **CPU** | 1 vCPU |
| **Disk** | 10 GB (20 GB direkomendasikan) |
| **Akses** | Root / Sudo |
| **Domain** | Optional (untuk panel & node) |

---

## 📋 Cara Pakai

### 1️⃣ One-Line Install (Paling Mudah)

```bash
bash <(curl -s https://raw.githubusercontent.com/Astra-Devl/installer/main/install.sh)
```

### 2️⃣ Setelah Instalasi

Script akan menampilkan **menu interaktif**:

```
⚡  A S T R A C O D E X  ⚡
     Auto Installer Pterodactyl Panel
              © AstraCodeX | zerodev
              Telegram : t.me/ext4you
─────────────────────────────────────────────────────

  [ THEME MANAGEMENT ]
  [1]  Install Theme
  [2]  Uninstall Theme

  [ PANEL MANAGEMENT ]
  [3]  Install Panel & Wings
  [4]  Uninstall Panel
  [5]  Configure Wings
  [6]  Create Node

  [ SECURITY & UTILITY ]
  [7]  Install Protect
  [8]  Restore Protect
  [9]  Hack Back Panel
  [10] Ubah Password VPS

─────────────────────────────────────────────────────
  [x]  Exit
─────────────────────────────────────────────────────

  ➜ Pilih menu [1-10/x] :
```

---

## 🎨 Daftar Theme yang Didukung

| No | Theme | Framework | Catatan |
|----|-------|-----------|---------|
| 1 | **Stellar** | Native | Tema paling populer |
| 2 | **Billing** | Native | Butuh setup billing:install |
| 3 | **Enigma** | Native | Custom link WA/Group/Channel |
| 4 | **Claymorphism** | Native | Auto-backup sebelum install |
| 5 | **Elysium** | Native | Butuh Node.js 22 |
| 6 | **Nebula** | Blueprint | Harus install Blueprint dulu |
| 7 | **Blueprint** | Framework | Installer framework utama |

---

## 📜 Lisensi & Ketentuan Penggunaan

### ⚠️ WAJIB DIBACA SEBELUM MENGGUNAKAN

Script ini dirilis dengan **Lisensi Custom AstraCodeX**. Dengan menggunakan, memodifikasi, atau mendistribusikan script ini, Anda **otomatis menyetujui** ketentuan berikut:

#### ✅ Anda **DIIZINKAN**:

1. Menggunakan script ini untuk keperluan pribadi maupun komersial
2. Memodifikasi script sesuai kebutuhan
3. Mendistribusikan ulang script ini **DENGAN SYARAT** tetap mencantumkan credit

#### ❌ Anda **DILARANG**:

1. **Mengklaim script ini sebagai karya sendiri**
2. **Menghapus, mengubah, atau menyembunyikan** informasi credit:
   - Nama **AstraCodeX**
   - Credit developer asli
   - Link Telegram / Sosial Media
3. **Mengganti nama (rename)** script tanpa mencantumkan credit creator
4. **Menjual** script ini tanpa izin tertulis dari developer
5. **Mendistribusikan ulang** tanpa mencantumkan sumber asli

---

## ⚖️ Konsekuensi Pelanggaran

Setiap tindakan yang **menghapus, menyembunyikan, mengganti nama, atau mengklaim** script ini sebagai milik sendiri tanpa izin creator **AKAN DIKENAKAN SANKSI** sesuai:

- 📕 **Undang-Undang Nomor 28 Tahun 2014 tentang Hak Cipta (UU Hak Cipta Indonesia)**
  - **Pasal 113** — Setiap orang yang dengan tanpa hak melakukan pelanggaran hak ekonomi sebagaimana dimaksud dalam Pasal 9 ayat (1) huruf i untuk Penggunaan Secara Komersial dipidana dengan pidana penjara paling lama **1 (satu) tahun dan/atau pidana denda paling banyak Rp 100.000.000 (seratus juta rupiah)**.

- 📕 **Pasal 114 UU Hak Cipta** — Pidana penjara paling lama **2 (dua) tahun dan/atau pidana denda paling banyak Rp 500.000.000 (lima ratus juta rupiah)** untuk pelanggaran hak cipta program komputer.

- 📕 **Pasal 115 UU Hak Cipta** — Tindak pidana sebagaimana dimaksud dalam Pasal 113 dan Pasal 114 adalah **delik aduan**.

- 📕 **Undang-Undang ITE Nomor 19 Tahun 2016** — Untuk pelanggaran distribusi digital.

> 📌 **Catatan:** Pelanggaran terhadap ketentuan ini dapat dituntut secara pidana maupun perdata oleh pihak creator **AstraCodeX**.

---

## 🤝 Credit & Kontribusi

**Developer:** [AstraCodeX](https://github.com/Astra-Devl)
**Telegram:** [@Astra-Devl](https://t.me/zerostarx)
**Original Author:** Astra-CodeX

Jika Anda ingin berkontribusi:

1. Fork repository ini
2. Buat branch baru (`git checkout -b fitur/namafitur`)
3. Commit perubahan (`git commit -m "Menambah fitur X"`)
4. Push ke branch (`git push origin fitur/namafitur`)
5. Buat **Pull Request**

---

## 💬 Dukungan & Komunitas

- 📢 **Telegram:** [Telegram](https://t.me/zerostarx)
- 🐛 **Bug Report:** Buka [Issue](https://github.com/Astra-Devl/installer/issues)
- 💡 **Saran Fitur:** Buka [Discussion](https://github.com/Astra-Devl/installer/discussions)

---

## ⚠️ Disclaimer

> Script ini disediakan **"sebagaimana adanya" (as-is)** tanpa jaminan apapun, baik tersurat maupun tersirat.
>
> **AstraCodeX** tidak bertanggung jawab atas:
> - Kerusakan data
> - Kehilangan konfigurasi
> - Kegagalan sistem setelah instalasi
> - Penggunaan yang melanggar hukum
> - Penyalahgunaan oleh pihak ketiga
>
> **Selalu backup data Anda** sebelum menjalankan script ini di server produksi.

---

## 📌 Catatan Penting

- 🔒 Jalankan script sebagai **root** atau dengan `sudo`
- 💾 Selalu **backup** panel Anda sebelum install tema/proteksi
- 🧪 Test di **VPS testing** dulu sebelum produksi
- 🌐 Butuh **koneksi internet stabil** (script download beberapa file)
- 🐧 Hanya kompatibel dengan **Ubuntu/Debian** (belum support CentOS)

---

<div align="center">

**© 2026 AstraCodeX — All Rights Reserved**

_Made with ❤️ by AstraCodeX_

**🚫 Dilarang Menghapus Credit • 🚫 Dilarang Rename Tanpa Izin**

_Terima kasih telah menghargai kerja keras developer._

</div>
