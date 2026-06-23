
# Assembly RISC-V

## 1. Peta Konsep dan Dasar Teori

Sebelum menulis program RISC-V tanpa sistem operasi, terdapat tiga konsep utama yang harus dipahami, yaitu lingkungan *bare-metal*, *Memory-Mapped I/O* (MMIO), dan peta memori mesin virtual QEMU.

Lingkungan *bare-metal* adalah kondisi ketika program berjalan langsung di atas CPU tanpa lapisan sistem operasi seperti Linux atau Windows. Pada kondisi ini tidak tersedia manajemen memori virtual, *scheduler*, *file system*, maupun pustaka standar. Seluruh proses inisialisasi sistem, pengelolaan memori, penanganan interupsi, dan akses perangkat keras menjadi tanggung jawab program yang dibuat.

Konsep kedua adalah *Memory-Mapped I/O* (MMIO). Pada metode ini, register perangkat keras dipetakan ke ruang alamat memori yang sama dengan RAM. Akibatnya, CPU dapat berkomunikasi dengan perangkat eksternal menggunakan instruksi memori biasa seperti *load* dan *store*. Dalam proyek ini, UART digunakan sebagai media keluaran (*output*) dengan alamat dasar `0x10000000`.

Konsep ketiga adalah peta memori mesin virtual QEMU dengan tipe mesin `virt`. Pada konfigurasi ini, RAM dimulai dari alamat `0x80000000`, sedangkan UART berada pada alamat `0x10000000`. Setelah proses *reset*, CPU RISC-V akan mulai mengeksekusi instruksi dari alamat awal RAM tersebut. Ketika data ditulis ke alamat UART, QEMU akan meneruskannya langsung ke terminal host.

## 2. Persiapan Perangkat Lunak

Instal *toolchain* RISC-V dan emulator QEMU menggunakan perintah berikut:

```bash
sudo apt update
sudo apt install gcc-riscv64-unknown-elf qemu-system-misc
```

Kompiler RISC-V digunakan untuk melakukan *cross-compilation*, yaitu proses kompilasi dari komputer host menuju arsitektur target RISC-V. Sementara itu, QEMU digunakan untuk menjalankan dan menguji program tanpa memerlukan perangkat keras fisik.

Setelah instalasi selesai, pastikan seluruh perangkat lunak telah terpasang dengan benar menggunakan perintah berikut:

```bash
riscv64-unknown-elf-gcc --version
qemu-system-riscv64 --version
```

Jika kedua perintah menampilkan informasi versi, maka lingkungan pengembangan telah siap digunakan.

## 3. Siklus Hidup Berkas

Proses pembangunan program berlangsung melalui beberapa tahap transformasi berkas hingga menghasilkan kode mesin yang dapat dieksekusi CPU.

Berkas `hello.s` berisi kode sumber Assembly RISC-V yang ditulis oleh programmer. Berkas ini kemudian diproses bersama `linker.ld`, yaitu skrip yang menentukan tata letak memori dan alamat penempatan setiap bagian program.

Hasil proses kompilasi menghasilkan berkas objek `hello.o`, yaitu kode mesin yang masih menggunakan alamat relatif. Berkas objek tersebut kemudian ditautkan (*linked*) menjadi `hello.elf`, yaitu berkas biner lengkap yang telah memiliki alamat memori final beserta metadata tambahan untuk proses debugging.

Tahap terakhir adalah ekstraksi ELF menjadi `hello.bin`. Berkas ini merupakan biner mentah (*raw binary*) yang hanya berisi instruksi mesin tanpa header atau metadata tambahan sehingga siap dimuat langsung ke memori oleh QEMU.

## 4. Implementasi

### 4.1 Menulis Program Assembly (`hello.s`)

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
    .asciz "Hello World!\n"
```

Program dimulai pada label `_start`. Register `t0` digunakan untuk menyimpan alamat UART, sedangkan register `t1` menyimpan alamat string yang akan dicetak.

Pada bagian `print_loop`, instruksi `lb` membaca satu byte karakter dari memori. Nilai tersebut kemudian diperiksa menggunakan `beqz`. Jika karakter yang dibaca bernilai `0x00` (*null terminator*), program akan keluar dari proses pencetakan dan masuk ke label `end`.

Apabila karakter yang dibaca bukan `0x00`, instruksi `sb` akan menuliskannya ke alamat UART. Karena UART menggunakan MMIO, penulisan tersebut langsung diterjemahkan oleh QEMU sebagai keluaran ke terminal. Register `t1` kemudian digeser satu byte ke depan menggunakan `addi` dan proses diulang hingga seluruh karakter selesai dikirim.

Setelah semua karakter dicetak, program masuk ke *infinite loop* pada label `end` untuk mencegah CPU mengeksekusi area memori yang tidak valid.

### 4.2 Membuat Linker Script (`linker.ld`)

```ld
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
    . = 0x80000000;

    .text : {
        *(.text)
    }

    .rodata : {
        *(.rodata)
    }

    .data : {
        *(.data)
    }

    .bss : {
        *(.bss)
    }
}
```

Pada sistem *bare-metal*, tidak ada sistem operasi yang mengatur lokasi penempatan program di memori. Oleh karena itu, *linker script* digunakan untuk menentukan alamat fisik setiap bagian program.

Alamat awal ditetapkan pada `0x80000000`, yaitu alamat dasar RAM pada mesin virtual QEMU `virt`. Bagian `.text` ditempatkan terlebih dahulu karena berisi instruksi program. Setelah itu ditempatkan bagian `.rodata`, `.data`, dan `.bss` secara berurutan.

Dengan konfigurasi ini, CPU akan menemukan instruksi pertama tepat pada alamat yang sesuai saat proses boot berlangsung.

### 4.3 Kompilasi dan Pembuatan Biner

Kompilasi program dilakukan menggunakan perintah berikut:

```bash
riscv64-unknown-elf-gcc \
    -nostdlib \
    -nostartfiles \
    -T linker.ld \
    -o hello.elf \
    hello.s
```

Opsi `-nostdlib` digunakan untuk menonaktifkan pustaka standar C, sedangkan `-nostartfiles` menonaktifkan kode inisialisasi bawaan GCC. Hal ini diperlukan karena seluruh proses boot dibuat secara manual.

Opsi `-T linker.ld` memerintahkan *linker* untuk menggunakan tata letak memori yang telah ditentukan pada berkas `linker.ld`.

Setelah berkas ELF berhasil dibuat, ekstrak menjadi biner mentah menggunakan perintah berikut:

```bash
riscv64-unknown-elf-objcopy \
    -O binary \
    hello.elf \
    hello.bin
```

Perintah ini menghapus seluruh metadata ELF dan hanya menyisakan instruksi mesin yang diperlukan CPU.

### 4.4 Menjalankan Program di QEMU

Jalankan program menggunakan perintah berikut:

```bash
qemu-system-riscv64 \
    -machine virt \
    -bios hello.bin \
    -nographic
```

Opsi `-machine virt` memilih papan induk virtual RISC-V standar yang disediakan QEMU. Opsi `-bios hello.bin` memuat berkas biner ke memori dan menjadikannya titik awal eksekusi CPU. Sementara itu, opsi `-nographic` menghubungkan UART langsung ke terminal sehingga keluaran program dapat dilihat tanpa jendela grafis.

Jika berhasil, terminal akan menampilkan:

```text
Hello World!
```

## 5. Alur Eksekusi Program

Saat program dijalankan, urutan proses yang terjadi adalah sebagai berikut.

Pertama, QEMU melakukan inisialisasi mesin virtual dan memuat `hello.bin` ke RAM pada alamat `0x80000000`. Setelah proses reset selesai, CPU RISC-V mulai mengeksekusi instruksi pertama pada alamat tersebut.

Program kemudian mengisi register `t0` dengan alamat UART dan register `t1` dengan alamat string `Hello World!`. CPU membaca karakter satu per satu dari memori menggunakan instruksi `lb`.

Setiap karakter yang dibaca akan dikirim ke UART menggunakan instruksi `sb`. QEMU menerima data tersebut dan menampilkannya ke terminal. Setelah karakter terakhir dibaca, CPU menemukan nilai `0x00` sebagai penanda akhir string dan keluar dari proses pencetakan.

Program kemudian masuk ke *infinite loop* pada label `end`, menjaga CPU tetap berada dalam kondisi aman tanpa mengeksekusi memori yang tidak valid.
