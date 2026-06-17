# Assembly RISC-V

## 1. Peta Konsep & Teori Dasar

Untuk membangun sistem tanpa bantuan sistem operasi, Anda wajib memahami tiga pilar utama arsitektur komputer. Pilar pertama adalah lingkungan *bare-metal*, yakni kondisi di mana kode program dieksekusi langsung oleh *core* CPU tanpa adanya lapisan abstraksi seperti Linux atau Windows. Konsekuensi dari lingkungan ini adalah ketiadaan manajemen memori virtual, skeduler *thread*, *file system*, maupun pustaka standar C. Sebagai pemrogram, Anda memegang tanggung jawab penuh untuk mengonfigurasi memori, menangani interupsi, dan mengontrol periferal secara manual melalui instruksi mesin.

Pilar kedua adalah *Memory-Mapped I/O* (MMIO). Ini adalah metode pemetaan register kendali periferal eksternal, seperti pengontrol serial UART, ke dalam ruang alamat memori yang sama dengan RAM utama. Dengan MMIO, CPU tidak membutuhkan instruksi khusus untuk mengakses periferal. Anda cukup mengirim data ke luar sistem menggunakan instruksi operasi memori standar, seperti *Store Byte*, ke alamat spesifik yang telah ditentukan oleh perancang perangkat keras.

Pilar ketiga berpusat pada spesifikasi mesin virtual QEMU, khususnya profil papan induk virtual bernama `virt`. Profil ini memiliki peta memori tetap yang menjadi acuan mutlak proyek ini. Dua alamat krusial yang perlu Anda ingat adalah alamat awal RAM di `0x80000000`, yang menjadi titik fisik pertama bagi CPU RISC-V untuk mencari dan mengeksekusi instruksi setelah siklus *reset* selesai, serta alamat register UART di `0x10000000`. Alamat UART ini adalah basis fisik untuk pengontrol serial standar, di mana karakter yang ditulis ke alamat tersebut akan diteruskan oleh QEMU secara langsung ke terminal *host* Anda.

## 2. Persiapan Perangkat Lunak

```bash
# Memperbarui indeks paket repositori
sudo apt update

# Memasang compiler GCC spesifik RISC-V (bare-metal/elf) dan emulator QEMU
sudo apt install gcc-riscv64-unknown-elf qemu-system-misc
```

Proses kompilasi proyek ini membutuhkan *toolchain* khusus untuk melakukan kompilasi silang (*cross-compilation*), mengingat arsitektur komputer kerja Anda kemungkinan besar berbeda dengan arsitektur target RISC-V. Anda dapat menginstal *compiler* GCC spesifik RISC-V dan emulator QEMU pada distribusi Linux berbasis Debian atau Ubuntu menggunakan perintah di atas. Setelah instalasi selesai, pastikan perangkat lunak telah terpasang dengan benar dengan memeriksa versinya melalui perintah `riscv64-unknown-elf-gcc --version` dan `qemu-system-riscv64 --version` di terminal Anda.

## 3. Siklus Hidup Berkas (Pipeline Produksi)

Proyek ini melibatkan rantai transformasi berkas yang linier, di mana data mengalir dari kode teks yang dipahami manusia menjadi sekumpulan bit murni yang dieksekusi oleh CPU. Alur ini dimulai dari berkas `hello.s` yang berisi kode sumber instruksi bahasa *assembly* tingkat rendah murni. Selanjutnya, terdapat berkas konfigurasi `linker.ld` yang bertindak sebagai cetak biru untuk mengatur pemetaan sektor kode ke alamat memori fisik RAM.

Proses kompilasi kemudian akan menghasilkan berkas objek `hello.o`, yakni hasil translasi dari *assembly* ke kode mesin yang alamat memorinya masih bersifat relatif. Berkas objek ini lalu ditautkan menjadi `hello.elf`, sebuah berkas biner terstruktur yang sudah terikat dengan alamat memori pasti beserta metadata untuk keperluan *debugging*. Terakhir, berkas tersebut dikupas menjadi `hello.bin`, sebuah biner mentah murni tanpa *header* ELF yang berisi 100% instruksi CPU yang siap pakai.

## 4. Implementasi Langkah Demi Langkah

### 1. Menulis Kode Assembly (`hello.s`)

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
    .asciz "Hello World!\n" # String teks otomatis diakhiri byte 0x00 (NULL)
```

Kode *assembly* di atas bertanggung jawab untuk menginisialisasi penunjuk alamat, membaca karakter satu per satu, dan mengirimkannya ke *port* serial. Dalam arsitektur RISC-V, kita menggunakan register sementara seperti `t0`, `t1`, dan `t2` sesuai standar *Application Binary Interface* (ABI). Proses dimulai dengan memuat alamat UART ke dalam `t0` dan alamat string ke dalam `t1`. Di dalam perulangan `print_loop`, instruksi `lb` mengambil satu *byte* karakter dari alamat memori, sedangkan instruksi `beqz` bertugas sebagai detektor akhir string yang akan menghentikan proses jika mendeteksi nilai *null* (`0x00`). Jika karakter bukan *null*, instruksi inti MMIO yaitu `sb` akan mengeksekusinya dengan menuliskan data tersebut langsung ke alamat memori UART, yang kemudian ditangkap oleh QEMU menjadi *output* teks. Program ini kemudian diakhiri dengan instruksi `j end` yang mengunci *Program Counter* pada satu titik konstan, sebuah jebakan mematikan yang mencegah CPU membaca area memori acak selanjutnya yang bisa memicu *kernel panic*.

### 2. Membuat Skrip Tata Letak Memori (`linker.ld`)

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

Tanpa keberadaan sistem operasi, *compiler* tidak mengetahui di mana posisi RAM fisik berada. Oleh karena itu, skrip penaut atau *linker script* di atas berfungsi sebagai penunjuk arah bagi *compiler* dalam menyusun struktur biner. Skrip ini menggunakan tanda titik sebagai *Location Counter* yang ditetapkan pada alamat dasar `0x80000000`. Seluruh penempatan seksi seperti blok instruksi `.text` dan blok data statis `.rodata` dari semua berkas objek akan disusun secara berurutan dan dihitung secara inkremental dimulai dari alamat dasar fisik RAM QEMU tersebut.

### 3. Proses Kompilasi dan Ekstraksi Biner

```bash
# Langkah A: Mengompilasi dan menautkan alamat memori secara langsung menjadi berkas ELF
riscv64-unknown-elf-gcc -nostdlib -nostartfiles -T linker.ld -o hello.elf hello.s

# Langkah B: Mengekstraksi kode mesin murni dari format ELF menjadi biner mentah
riscv64-unknown-elf-objcopy -O binary hello.elf hello.bin
```

Untuk menghasilkan berkas biner akhir, Anda perlu menjalankan proses kompilasi dan ekstraksi di atas secara berurutan. Pada tahap kompilasi, *flag* `-nostdlib` dan `-nostartfiles` digunakan untuk menginstruksikan *compiler* agar mengabaikan pustaka standar C dan berkas inisialisasi internal GCC, karena kita mendefinisikan prosedur *boot* kita sendiri secara manual. Kita juga menggunakan *flag* `-T` untuk memaksa proses tautan mematuhi aturan tata letak memori di dalam berkas `linker.ld`. Setelah berkas ELF terbentuk, perintah `objcopy` dengan parameter `-O binary` digunakan untuk membuang seluruh metadata dan tabel simbol, sehingga menghasilkan struktur biner polos murni yang ukurannya sama persis dengan data aslinya.

### 4. Mengeksekusi Berkas Biner Pada Perangkat Keras Virtual

```bash
qemu-system-riscv64 -machine virt -bios hello.bin -nographic
```

Setelah berkas biner mentah siap, Anda dapat mengeksekusinya di dalam komponen sistem emulator QEMU. Parameter `-machine virt` pada perintah di atas memilih profil mesin virtual yang menyediakan alamat RAM pada basis yang tepat, sedangkan parameter `-bios` memerintahkan QEMU untuk menyalin isi dari berkas `hello.bin` secara langsung ke alamat awal memori RAM tersebut sebelum melepas pin *reset* CPU. Penggunaan parameter `-nographic` sangat penting karena ia akan menolak pembukaan jendela grafis eksternal dan langsung menghubungkan interkoneksi MMIO UART ke aliran terminal tempat Anda bekerja.

## 5. Alur Kronologis Eksekusi Sistem (Runtime Flow)

Berikut adalah urutan kejadian logis di dalam sistem secara bertahap saat program dieksekusi:

1. **Power-On / Reset:** Siklus awal saat sistem perangkat keras virtual dinyalakan.
2. **Pemuatan Biner:** QEMU menyalin berkas `hello.bin` secara utuh ke dalam memori RAM pada alamat `0x80000000`.
3. **Booting CPU:** *Core* CPU RISC-V aktif dan langsung melompat ke alamat awal `0x80000000` untuk mengeksekusi instruksi pertama.
4. **Inisialisasi (`_start`):** Register `t0` diisi dengan alamat dasar antarmuka UART (`0x10000000`).
5. **Membaca Karakter (`print_loop`):** CPU membaca 1 *byte* karakter dari alamat teks yang ditunjuk oleh register `t1`.
6. **Pengecekan Kondisi (Percabangan):**
* **Jika *byte* = `0x00` (Selesai):** Program melompat ke label `end` dan mengunci diri dalam *infinite loop* (perulangan tanpa batas) untuk mencegah *error*.
* **Jika *byte* ≠ `0x00` (Lanjut):** Karakter dikirim ke `t0` (MMIO UART) untuk dicetak, penunjuk alamat `t1` digeser 1 *byte* ke depan, lalu eksekusi kembali memutar ke langkah 5.

## Cara Menghentikan Simulasi

Program *bare-metal* ini sengaja dirancang untuk berakhir dengan instruksi perangkap tanpa batas demi menjaga stabilitas sistem, sehingga terminal Anda akan terkunci sepenuhnya di dalam emulasi mesin. Untuk mematikan QEMU dan mengembalikan kontrol penuh ke *shell* Linux asli Anda, Anda hanya perlu menekan tombol `Ctrl` dan `A` secara bersamaan pada *keyboard*, melepaskannya, lalu segera menekan tombol huruf `X`. Terminal akan menampilkan pesan pengakhiran dari QEMU dan Anda bisa kembali bekerja secara normal.
