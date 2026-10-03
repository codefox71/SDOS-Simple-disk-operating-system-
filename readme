this os is a simple redition of a simple disk os or Sdos the example is in python but would
be idealy writen in x86_64 assambly

it has the following commands that are built in 
```sh
dir [point in memory to start], [point in memory to end dir]
```

```sh
load [raw hex to load to memory], [point in memory to start], [point in memory to end store] 
```

:: please note that if the program is more bytes that can fit in the selected width it will error. In the NASM shell, `load [path] [raw_hex]` creates or replaces a BTfs file.

```sh
run [point in memory to start execute], [point in memory to end execute]
```

:: the NASM boot shell executes the bytes at start as 16-bit x86 real-mode instructions. Code must return with RET or fall through end, and must preserve SS:SP. The end value validates the memory range but is not a sandbox; jumps can leave it.

```sh
mem
```
 ::lists how many addresses are zeros in memory

The Python kernel models run through the execution shim; the bootable NASM image runs the instructions on the emulated CPU.

The bootable NASM image provides an ASCII output interrupt: put a printable character (0x20-0x7E) in AL and execute `INT 80h`. Non-printable values are ignored.

Programs control their own terminal output. `run`, `run -fN`, and `/bin` invocation do not print a banner or register dump. `INT 80h` uses `AH=0` to print the character in `AL`, or `AH=1` to print a NUL-terminated string at `DS:SI`. Printable ASCII and the control characters backspace, tab, line feed, and carriage return are sent to the terminal.

`INT 81h` waits for one keyboard character, echoes it, and returns it in `AL` (`AH` is zero). `INT 82h` exits the current program immediately; put the exit status in `AL`. A normal `RET` also returns, using the low byte of `AX` as the status. Use the shell's `status` command to display the most recent program status.

Read and echo one input character, then print its next ASCII character:

```text
load CD810401CD80C3 0 6
run 0 6
```

Print a NUL-terminated string stored after the program code:

```text
load BE08C0B401CD80C348656C6C6F00 0 13
run 0 13
```

Exit without a `RET` and report status 42 afterward:

```text
load B02ACD82 20 23
run 20 23
status
```

Example: load and run this 16-bit program to print `***` by looping three times:

```text
load B90300B82A00CD80E2FCC3 0 10
run 0 10
```

The bytes are `mov cx,3; mov ax,42; int 80h; loop; ret`. INT 80h preserves CX and AX so the program can loop and return normally.

Example: count up and print `123` using only `ADD` for arithmetic. The loop counter starts at `0xFFFD` and wraps to zero after three additions:

```text
load B9FDFFB0300401CD8083C10175F7C3 0 14
run 0 14
```

The bytes are `mov cx,0xFFFD; mov al,'0'; add al,1; int 80h; add cx,1; jnz loop; ret`.

## C subset compiler

`src/c2hex.py` compiles a small C subset into `load` and `run` commands. It supports one `int main()` function, local `int` variables, `+` and `-`, assignments, `while`, `putchar`, and `return`:

```sh
python3 src/c2hex.py examples/count.c
```

Paste each generated `load` line into SDOS, then paste the final `run` line. The compiler emits 16-bit real-mode code for this monitor; it is not a general-purpose C compiler and does not support headers, pointers, arrays, or arbitrary function calls.

Pass `-S` (or `--asm`) to print the generated program as a NASM-compatible assembly listing with byte offsets and branch labels:

```sh
python3 src/c2hex.py -S examples/count.c
```

## BTfs

BTfs is embedded in `build/sdos.img` at LBA 17. It has a 64-record tree zone and a 256-block data zone. Tree records identify a node's parent, type, name, and file data-block chain; the volume header contains the shared superblock ID. Each data block is 256 bytes, with 254 payload bytes and a 2-byte next-block link. This gives 63 non-root tree nodes and up to 65,024 bytes of file data.

The NASM/QEMU shell supports `pwd`, `cd`, `ls`, `cat`, `echo`, `clear`, `touch`, `load [path] [raw_hex]`, `rm`, `cp`, `mv`, `mkdir`, and `rmdir`, as well as the original `chdir`, `RMF`, `cpy`, `move`, `makedir`, and `remdir` names. `cat` displays printable text and substitutes `.` for non-text bytes. `touch` creates an empty file. `rmdir` only removes empty folders. File operations write the floppy image immediately. `load [path] [raw_hex]` creates or replaces a file; numeric `load [raw_hex] [start] [end]` still writes directly to memory. The prompt accepts at most 63 characters per command, so inline hex writes are limited by the path length; use host `.hex` files for larger programs. `cp`/`cpy` and `run -f1 ...` load through 4096-byte RAM, and dependencies are concatenated in order without linking.

For example, `pwd` prints the current path, `cd /test/` changes folders, `touch note.txt` creates an empty file, `load note.txt 48656C6C6F0A` writes `Hello` plus a newline, and `cat note.txt` displays it. `echo hello` prints text, and `clear` clears the terminal.

All executable files belong under `/bin`. An extensionless command is looked up there; for example, typing `hello` runs `/bin/hello`. A filename with an extension can also be invoked as `hello.hex`. Programs receive no command-line arguments.

Seed the volume from a host directory by placing files under `btfs_root/`, then build and boot the image:

```sh
python3 src/btfs_pack.py btfs_root build/btfs.img
./build_image.sh
./run_qemu.sh
```

The included `btfs_root/bin/hello.hex` prints `*` when run. In QEMU, try `hello.hex` from any folder, or `run -f1 /bin/hello.hex`. Host `.hex` files are decoded from whitespace-separated hexadecimal text; other files are stored as raw bytes. Paths may be absolute from `/` or relative to the current folder; `cd /bin/` changes the working tree node.

The host packer merges `btfs_root/` into `build/btfs.img`; rebuilding first extracts the current volume from the floppy so changes made in QEMU are preserved. Numeric `load [raw_hex] [start] [end]` and `run [start] [end]` remain available.
