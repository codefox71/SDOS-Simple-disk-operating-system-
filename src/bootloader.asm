BITS 16
ORG 0x7C00

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld

    mov si, loading_msg
    call print_string

    ; Read the kernel from the disk starting at sector 2 into memory at 0x7E00.
    ; Load the 8 KiB OS stage from sectors 2 through 17.
    mov ah, 0x02
    mov al, 16
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, 0
    mov bx, 0x7E00
    int 0x13
    jc disk_error

    jmp 0x7E00

print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_string
.done:
    ret

disk_error:
    mov si, error_msg
    call print_string
    cli
    hlt
    jmp $

loading_msg db "Loading SDOS...", 13, 10, 0
error_msg   db "Disk read error", 13, 10, 0

TIMES 510 - ($ - $$) db 0
DW 0xAA55
