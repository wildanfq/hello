# **Program Bare Metal di CPU RISC-V dengan Assembly Tanpa Sistem Operasi Menggunakan Emulator QEMU**

---

## **I. Peta Konsep & Teori Dasar**

Sebelum masuk ke teknis, kita harus memahami tiga pilar utama yang membuat program ini dapat berjalan langsung di atas perangkat keras:

* **Bare Metal:** Kondisi di mana program dieksekusi langsung oleh CPU tanpa adanya lapisan sistem operasi (seperti Linux atau Windows). Tidak ada manajemen memori otomatis, tidak ada file sistem, dan tidak ada *standard library* (seperti `printf`).
* **Memory-Mapped I/O (MMIO):** Metode komunikasi di mana perangkat keras eksternal (dalam kasus ini, port serial UART) dipetakan ke dalam alamat memori yang sama dengan RAM. Menulis data ke alamat tersebut berarti mengirimkan data langsung ke fisik perangkat.
* **QEMU (Mesin `virt`):** Emulator yang kita gunakan dikonfigurasi untuk meniru sebuah papan induk (*motherboard*) virtual berspesifikasi tetap:
* Alamat Awal RAM: `0x80000000` (Titik pertama CPU mencari instruksi).
* Alamat Register UART: `0x10000000` (Pintu keluar karakter ke layar terminal).

---

## **II. Persiapan Perangkat Lunak**

Gunakan manajer paket distribusi Linux Anda untuk memasang *toolchain* compiler khusus RISC-V (Arsitektur target) dan emulator QEMU (Sistem target).

```bash
sudo apt update
sudo apt install gcc-riscv64-unknown-elf qemu-system-misc

```

---

## **III. Siklus Hidup Berkas (Pipeline Produksi)**

Proyek ini terdiri dari 5 berkas utama yang saling berkaitan dalam sebuah alur kerja linier:

| Nama Berkas | Jenis Berkas | Peran dalam Proyek |
| --- | --- | --- |
| **`hello.s`** | Kode Sumber (*Source*) | Berisi instruksi bahasa assembly manusia tingkat rendah. |
| **`linker.ld`** | Skrip Penaut (*Linker*) | Berisi aturan penempatan sektor kode pada alamat RAM fisik. |
| **`hello.o`** | Berkas Objek (*Object*) | Hasil rakitan mesin murni, namun posisi alamatnya masih mengambang. |
| **`hello.elf`** | Format Eksekusi (*Executable*) | Berkas biner yang sudah terikat alamat memori, lengkap dengan metadata *debug*. |
| **`hello.bin`** | Biner Mentah (*Raw Binary*) | Hasil kupasan total dari berkas ELF. Hanya berisi instruksi CPU 100% murni. |

---

## **IV. Implementasi Langkah Demi Langkah**

### **1. Menulis Kode Assembly (`hello.s`)**

Buat sebuah berkas bernama `hello.s` dan masukkan kode biner bersih berikut:

```assembly
.equ UART_BASE, 0x10000000

.section .text
.global _start

_start:
    li t0, UART_BASE
    la t1, hello_msg

print_loop:
    lb t2, 0(t1)
    beqz t2, end
    sb t2, 0(t0)
    addi t1, t1, 1
    j print_loop

end:
    j end

.section .rodata
hello_msg:
    .asciz "Hello World, Bare Metal RISC-V!\n"

```

---

### **Analisis Struktur & Penjelasan Kode `hello.s**`

* **`.equ UART_BASE, 0x10000000`**
Membuat konstanta bernama `UART_BASE` yang merujuk pada alamat fisik pengontrol serial QEMU.
* **`.section .text` dan `.global _start**`
Pernyataan kepada compiler bahwa bagian di bawah ini adalah instruksi eksekusi utama, dengan `_start` sebagai titik masuk (*entry point*) pertama.
* **`li t0, UART_BASE`**
*Load Immediate*. Memasukkan nilai konstan `0x10000000` ke dalam register sementara `t0`.
* **`la t1, hello_msg`**
*Load Address*. Mencari tahu di alamat RAM berapa string teks "Hello World" berada, lalu menyimpannya di register `t1`.
* **`lb t2, 0(t1)`**
*Load Byte*. Mengambil 1 karakter (1 byte) dari posisi memori yang saat ini ditunjuk oleh register `t1`, lalu menyimpannya di register `t2`.
* **`beqz t2, end`**
*Branch if Equal to Zero*. Memeriksa isi register `t2`. Jika berisi angka `0` (karakter NULL yang menandakan teks habis), program akan melompat keluar ke label `end`.
* **`sb t2, 0(t0)`**
*Store Byte*. Melemparkan 1 karakter yang ada di register `t2` langsung ke alamat memori yang dipegang oleh `t0` (`0x10000000`). Pada detik ini, perangkat keras UART menangkap data dan mencetaknya ke layar terminal.
* **`addi t1, t1, 1`**
*Add Immediate*. Menambahkan angka 1 pada nilai register `t1` agar posisinya bergeser ke karakter urutan berikutnya dalam string.
* **`j print_loop`**
*Jump*. Memaksa CPU melompat kembali ke atas untuk memproses karakter berikutnya.
* **`end: j end`**
*Infinite Loop*. Menjebak CPU dalam perulangan tanpa akhir di tempat yang sama. Ini wajib dilakukan pada sistem *bare metal* agar CPU tidak mengeksekusi sisa memori kosong yang tidak valid setelah program selesai.

---

### **2. Membuat Skrip Tata Letak Memori (`linker.ld`)**

Buat sebuah berkas bernama `linker.ld` dan masukkan kode konfigurasi berikut:

```ld
OUTPUT_ARCH( "riscv" )
ENTRY( _start )

SECTIONS
{
    . = 0x80000000;

    .text : {
        *(.text)
    }

    .rodata : {
        *(.rodata)
    }

    .data : { *(.data) }
    .bss : { *(.bss) }
}

```

---

### **Analisis Struktur & Penjelasan Kode `linker.ld**`

* **`OUTPUT_ARCH( "riscv" )`**
Menegaskan kepada sistem penaut (*linker*) bahwa arsitektur target pemetaan memori ini adalah untuk mesin RISC-V.
* **`ENTRY( _start )`**
Menetapkan bahwa label `_start` di dalam berkas assembly adalah instruksi pertama yang harus diletakkan di baris terdepan tata letak memori.
* **`. = 0x80000000;`**
Menetapkan *Location Counter* (titik awal penulisan). Angka `0x80000000` adalah standar mutlak dari QEMU tipe `virt` sebagai alamat memori RAM pertama yang akan dibaca saat komputer virtual dihidupkan.
* **`*(.text)` dan `*(.rodata)**`
Menginstruksikan linker untuk mengumpulkan semua bagian kode eksekusi (`.text`) dan semua data teks konstan (`.rodata`) dari berkas objek, lalu menjahitnya secara berurutan tepat dimulai dari titik alamat RAM di atas.

---

### **3. Proses Kompilasi dan Ekstraksi Biner**

Eksekusi rangkaian perintah berikut secara berurutan pada terminal Anda untuk memproses kode sumber menjadi bentuk biner final:

```bash
# 1. Mengompilasi assembly dan menautkan alamat memori (Menghasilkan berkas ELF)
riscv64-unknown-elf-gcc -nostdlib -nostartfiles -T linker.ld -o hello.elf hello.s

# 2. Mengupas metadata ELF untuk menghasilkan biner murni (Menghasilkan berkas BIN)
riscv64-unknown-elf-objcopy -O binary hello.elf hello.bin

```

**Penjelasan Bendera (*Flags*) Kompilasi:**

* `-nostdlib`: Melarang compiler menyertakan pustaka standar C bawaan sistem operasi.
* `-nostartfiles`: Melarang compiler memasukkan kode inisialisasi internal (seperti fungsi bawaan sebelum `main`).
* `-T linker.ld`: Memaksa compiler mematuhi denah peta memori yang diatur di berkas `linker.ld`.
* `-O binary`: Instruksi penjelas bagi `objcopy` untuk membuang semua struktur pembungkus berkas dan menyisakan data biner murni.

---

### **4. Mengeksekusi Berkas Biner Pada Perangkat Keras Virtual**

Jalankan perintah di bawah ini untuk menyalakan emulator QEMU dengan menyuapkan biner murni Anda langsung ke dalam komponen internal sistem:

```bash
qemu-system-riscv64 -machine virt -bios hello.bin -nographic

```

**Penjelasan Parameter QEMU:**

* `-machine virt`: Memilih arsitektur papan induk virtual tipe `virt` (yang memiliki konfigurasi RAM di `0x80000000` dan UART di `0x10000000`).
* `-bios hello.bin`: Memperlakukan berkas `hello.bin` sebagai *Firmware/BIOS* utama sistem. QEMU akan menyalin isi berkas ini langsung ke alamat memori `0x80000000` sejak komputer pertama kali dinyalakan.
* `-nographic`: Mematikan simulasi layar monitor grafis dan mengalihkan seluruh komunikasi jalur serial UART langsung ke jendela terminal aktif Anda.

---

## **V. Alur Kronologis Eksekusi Sistem (Runtime Flow)**

Saat Anda menekan tombol `Enter` pada perintah QEMU, berikut adalah urutan kejadian logis di dalam sistem:

```text
[Power On] 
   ↓
QEMU memuat 'hello.bin' tepat ke alamat RAM 0x80000000
   ↓
CPU RISC-V aktif dan melompat ke alamat awal 0x80000000 (Label _start)
   ↓
Register t0 mencatat alamat UART (0x10000000)
   ↓
Looping dimulai: Karakter pertama dipindahkan ke register t2
   ↓
Karakter di t2 dikirim langsung ke memori UART -> Karakter muncul di terminal
   ↓
Alamat teks bergeser ke kanan (+1 byte)
   ↓
Apakah karakter berikutnya bernilai 0 (NULL)? 
   ├─► [Tidak] -> Ulangi proses Looping
   └─► [Ya]    -> Keluar dari loop dan masuk ke perangkap 'Infinite Loop'

```

---

## **VI. Cara Menghentikan Simulasi**

Karena program *bare metal* ini diakhiri dengan instruksi perangkap tanpa batas (`j end`) untuk menstabilkan kondisi CPU, terminal Anda akan terkunci di dalam emulator.

Untuk keluar dan mematikan emulator QEMU:

1. Tekan kombinasi tombol **`Ctrl + A`** secara bersamaan.
2. Lepaskan kedua tombol tersebut.
3. Tekan tombol huruf **`X`** pada keyboard Anda.
