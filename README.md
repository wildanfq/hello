# Panduan Lengkap: Pemrograman Bare-Metal pada CPU RISC-V Menggunakan Assembly dan Emulator QEMU

---

## I. Peta Konsep & Teori Dasar

Untuk membangun sistem tanpa bantuan OS, Anda wajib memahami tiga pilar arsitektur komputer berikut:

### 1. Lingkungan Bare-Metal

*Bare-metal* adalah kondisi di mana kode program dieksekusi langsung oleh *core* CPU tanpa adanya lapisan abstraksi seperti Sistem Operasi (Linux, Windows, atau RTOS).

* **Konsekuensi:** Tidak ada manajemen memori virtual (MMU aktif), tidak ada skeduler *thread*, tidak ada *file system*, dan tidak ada pustaka standar C (`stdio.h`, `malloc`, dll.).
* **Tanggung Jawab:** Anda selaku programmer wajib mengonfigurasi memori, menangani interupsi, dan mengontrol periferal secara manual melalui instruksi mesin.

### 2. Memory-Mapped I/O (MMIO)

MMIO adalah metode di mana register kendali periferal eksternal (seperti pengontrol serial UART) dipetakan ke dalam ruang alamat memori yang sama dengan RAM utama.

* CPU tidak membutuhkan instruksi khusus untuk mengakses periferal.
* Mengirim data ke luar sistem cukup dilakukan dengan menggunakan instruksi operasi memori standar (seperti `sb` atau *Store Byte*) ke alamat spesifik yang telah ditentukan oleh perancang perangkat keras.

### 3. Spesifikasi Mesin Virtual QEMU (`virt`)

Emulator QEMU menyediakan profil papan induk (*motherboard*) virtual bernama `virt`. Profil ini memiliki peta memori (*memory map*) tetap yang menjadi acuan mutlak proyek ini:

* **Alamat Awal RAM (`0x80000000`):** Titik fisik pertama di mana CPU RISC-V akan mencari dan mengeksekusi instruksi setelah siklus *reset* selesai.
* **Alamat Register UART (`0x10000000`):** Alamat fisik basis untuk pengontrol serial standar NS16550A. Karakter yang ditulis ke alamat ini akan diteruskan oleh QEMU ke terminal *host* Anda.

---

## II. Persiapan Perangkat Lunak

Proses kompilasi membutuhkan *toolchain* khusus untuk melakukan kompilasi silang (*cross-compilation*), karena arsitektur komputer kerja Anda (biasanya x86_64) berbeda dengan arsitektur target (RISC-V).

Jalankan perintah berikut pada distribusi Linux berbasis Debian/Ubuntu:

```bash
# Memperbarui indeks paket repositori
sudo apt update

# Memasang compiler GCC spesifik RISC-V (bare-metal/elf) dan emulator QEMU
sudo apt install gcc-riscv64-unknown-elf qemu-system-misc

```

> **Catatan Verifikasi:** Anda dapat memastikan perangkat lunak terpasang dengan memeriksa versinya menggunakan perintah `riscv64-unknown-elf-gcc --version` dan `qemu-system-riscv64 --version`.

---

## III. Siklus Hidup Berkas (Pipeline Produksi)

Proyek ini melibatkan rantai transformasi berkas yang linier. Data mengalir dari kode teks yang dipahami manusia hingga menjadi bit murni yang dipahami oleh gerbang logika CPU.

| Nama Berkas | Jenis Berkas | Ekstensi | Peran & Karakteristik dalam Proyek |
| --- | --- | --- | --- |
| **`hello.s`** | *Source Code* | `.s` | Berisi instruksi bahasa assembly manusia tingkat rendah murni. |
| **`linker.ld`** | *Configuration* | `.ld` | Cetak biru yang mengatur pemetaan sektor kode ke alamat memori fisik RAM. |
| **`hello.o`** | *Object File* | `.o` | Hasil translasi dari assembly ke kode mesin. Alamat memori internal masih bersifat relatif (mengambang). |
| **`hello.elf`** | *Executable* | `.elf` | Berkas biner terstruktur (Executable and Linkable Format) yang sudah terikat alamat memori pasti, lengkap dengan metadata untuk proses *debugging*. |
| **`hello.bin`** | *Raw Binary* | `.bin` | Hasil kupasan akhir. Semua header ELF dibuang, menyisakan 100% instruksi CPU murni siap pakai. |

---

## IV. Implementasi Langkah Demi Langkah

### 1. Menulis Kode Assembly (`hello.s`)

Buat berkas bernama `hello.s`. Kode ini bertanggung jawab menginisialisasi penunjuk alamat, membaca karakter satu per satu, dan mengirimkannya ke port serial.

```assembly
.equ UART_BASE, 0x10000000      # Mendefinisikan konstanta alamat UART

.section .text                  # Menandai blok memori sebagai kode instruksi
.global _start                  # Mengekspos label _start agar terlihat oleh linker

_start:
    li t0, UART_BASE            # Load Immediate: t0 = 0x10000000
    la t1, hello_msg            # Load Address: t1 = alamat memori string 'hello_msg'

print_loop:
    lb t2, 0(t1)                # Load Byte: t2 = nilai byte di alamat yang ditunjuk t1
    beqz t2, end                # Branch if Equal to Zero: Jika t2 == 0 (NULL), lompat ke 'end'
    sb t2, 0(t0)                # Store Byte: Kirim isi t2 ke alamat memori di dalam t0 (UART)
    addi t1, t1, 1              # Add Immediate: Geser penunjuk alamat t1 sebesar 1 byte ke depan
    j print_loop                # Jump: Kembali ke awal perulangan untuk karakter berikutnya

end:
    j end                       # Infinite Loop: Jebakan mematikan agar CPU tidak lepas kendali

.section .rodata                # Menandai blok memori sebagai data Read-Only
hello_msg:
    .asciz "Hello World, Bare Metal RISC-V!\n" # String teks otomatis diakhiri byte 0x00 (NULL)

```

#### Analisis Struktur & Mekanisme Kode:

* **`t0, t1, t2`:** Merupakan register sementara (*temporary registers*) pada arsitektur RISC-V berdasarkan standar ABI (*Application Binary Interface*).
* **`lb t2, 0(t1)`:** Menggunakan metode *offset addressing*. Mengambil data berukuran 1 byte dari alamat `t1 + 0`.
* **`sb t2, 0(t0)`:** Proses inti MMIO. Menuliskan data di `t2` langsung ke alamat `0x10000000`. Sinyal bus data akan ditangkap oleh periferal UART QEMU dan dikonversi menjadi output teks.
* **`beqz t2, end`:** Berfungsi sebagai detektor akhir string. Karena direktif `.asciz` otomatis menyisipkan byte `0x00` di akhir teks, instruksi ini mendeteksi nilai tersebut untuk menghentikan loop.
* **`end: j end`:** Mengunci *Program Counter* (PC) CPU pada satu titik konstan. Tanpa instruksi ini, CPU akan terus membaca area memori selanjutnya yang berisi data acak (*garbage data*), memicu *kernel panic* level perangkat keras (*illegal instruction exception*).

---

### 2. Membuat Skrip Tata Letak Memori (`linker.ld`)

Tanpa OS, compiler tidak tahu di mana posisi RAM fisik berada. Skrip penaut (*linker script*) ini berfungsi sebagai penunjuk arah bagi compiler untuk menyusun struktur biner.

Buat berkas bernama `linker.ld`:

```ld
OUTPUT_ARCH( "riscv" )          /* Menetapkan arsitektur target: RISC-V */
ENTRY( _start )                 /* Menetapkan titik eksekusi pertama di label _start */

SECTIONS
{
    /* Menetapkan nilai Location Counter awal ke alamat RAM fisik QEMU 'virt' */
    . = 0x80000000; 

    /* Menyusun bagian kode instruksi (.text) di bagian paling awal RAM */
    .text : {
        *(.text)                /* Gabungkan semua seksi .text dari semua berkas objek */
    }

    /* Menyusun data statis read-only (seperti string teks) tepat setelah .text */
    .rodata : {
        *(.rodata)              /* Gabungkan semua seksi .rodata */
    }

    /* Alokasi ruang untuk data terinisialisasi dan tidak terinisialisasi */
    .data : { *(.data) }
    .bss  : { *(.bss)  }
}

```

#### Analisis Parameter Linker:

* **`. = 0x80000000;`:** Tanda titik (`.`) disebut sebagai *Location Counter*. Seluruh penempatan seksi di bawah baris ini akan dihitung secara inkremental dimulai dari alamat dasar tersebut.
* **`*(.text)`:** Karakter wildcard `*` berarti instruksi linker ini berlaku untuk semua berkas objek (`.o`) yang terlibat dalam proses pencatatan tautan memori.

---

### 3. Proses Kompilasi dan Ekstraksi Biner

Jalankan rangkaian perintah berikut pada terminal Anda secara berurutan:

```bash
# Langkah A: Mengompilasi dan menautkan alamat memori secara langsung menjadi berkas ELF
riscv64-unknown-elf-gcc -nostdlib -nostartfiles -T linker.ld -o hello.elf hello.s

# Langkah B: Mengekstraksi kode mesin murni dari format ELF menjadi biner mentah
riscv64-unknown-elf-objcopy -O binary hello.elf hello.bin

```

#### Penjelasan Bendera (Flags) Kompilasi:

* **`-nostdlib`:** Menginstruksikan compiler untuk benar-benar mengabaikan pustaka standar C. Menghindari eror akibat tidak ditemukannya fungsi sistem seperti `crts0`.
* **`-nostartfiles`:** Melarang penyertaan berkas inisialisasi standar internal GCC. Kita mendefinisikan prosedur *boot* kita sendiri melalui label `_start`.
* **`-T linker.ld`:** Memaksa proses tautan untuk patuh secara mutlak pada aturan tata letak memori yang sudah kita rancang di dalam berkas `linker.ld`.
* **`-O binary`:** Parameter output untuk `objcopy` yang memerintahkan sistem membuang seluruh tabel simbol, informasi arsitektur, dan metadata *debugging* dari berkas ELF, menghasilkan struktur biner polos seukuran data aslinya.

---

### 4. Mengeksekusi Berkas Biner Pada Perangkat Keras Virtual

Gunakan perintah berikut untuk menyuapkan biner hasil kompilasi langsung ke dalam komponen sistem emulator QEMU:

```bash
qemu-system-riscv64 -machine virt -bios hello.bin -nographic

```

#### Penjelasan Parameter QEMU:

* **`-machine virt`:** Memilih profil mesin virtual terarah yang menyediakan alamat RAM pada basis `0x80000000`.
* **`-bios hello.bin`:** Memasukkan berkas biner kita untuk bertindak langsung sebagai *Firmware/BIOS*. QEMU secara otomatis menyalin isi dari berkas `hello.bin` langsung tepat ke alamat awal memori RAM (`0x80000000`) sebelum melepas pin *reset* CPU.
* **`-nographic`:** Menolak pembukaan jendela GUI eksternal dan memaksa QEMU menghubungkan interkoneksi MMIO UART (`0x10000000`) langsung ke aliran input/output terminal tempat Anda menjalankan perintah tersebut.

---

## V. Alur Kronologis Eksekusi Sistem (Runtime Flow)

Berikut adalah visualisasi urutan kejadian logis di dalam sistem secara bertahap saat tombol eksekusi ditekan:

```text
+------------------------------------------------------------+
|                    Siklus Power-On / Reset                 |
+------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------+
| QEMU memuat 'hello.bin' secara utuh ke RAM @ 0x80000000    |
+------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------+
| Core CPU RISC-V aktif -> Lompat ke target awal: 0x80000000 |
+------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------+
| Eksekusi '_start': Register t0 diisi 0x10000000 (UART)     |
+------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------+
| Eksekusi 'print_loop': Baca 1 byte dari alamat teks (t1)   |
+------------------------------------------------------------+
                              |
                              v
                    /                   \
                   /                     \
                  v                       v
        [Apakah Byte == 0x00?]   [Apakah Byte != 0x00?]
                  |                       |
                  | YA                    | TIDAK
                  v                       v
+-------------------------+     +-------------------------+
| Lompat ke label 'end'   |     | Kirim byte ke t0 (MMIO) |
| (Masuk Infinite Loop)   |     +-------------------------+
+-------------------------+               |
                                          v
                                +-------------------------+
                                | Alamat t1 ditambah 1    |
                                +-------------------------+
                                          |
                                          v
                                +-------------------------+
                                | Lompat ke 'print_loop'  |
                                +-------------------------+

```

---

## VI. Cara Menghentikan Simulasi

Karena program *bare-metal* ini diakhiri dengan instruksi perangkap tanpa batas (`j end`) untuk menjaga stabilitas sirkuit elektrik CPU, terminal Anda akan terkunci sepenuhnya di dalam emulasi mesin.

Untuk mematikan QEMU dan kembali ke terminal Linux asli Anda, gunakan kombinasi tombol pintas (*shortcut*) berikut:

1. Tekan tombol **`Ctrl + A`** secara bersamaan di keyboard.
2. Lepaskan kedua tombol tersebut.
3. Segera tekan tombol huruf **`X`** pada keyboard Anda.

Terminal akan menampilkan pesan `QEMU: Terminated` dan mengembalikan kontrol kendali penuh ke *shell* Linux Anda.
