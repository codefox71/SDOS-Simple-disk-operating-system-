; Target: Linux x86_64 (NASM syntax)
; Standalone executable: provides _start entry point and pure Linux syscall / built-in implementations
; of memory shims, string formatting, parsing, and I/O (no external libc / ld unresolved references).

default rel

global _start
global list_memory_free
global read_value_from_memory
global start_excute_at
global write_value_to_memory
global memory_allocate
global usb_port_init
global _to_int
global Kernel
global kernel_init
global kernel_validate_range
global kernel_read_memory
global kernel_write_memory
global kernel_dir
global kernel_load
global kernel_run
global kernel_mem
global kernel_execute
global command
global main

section .data
    default_memory_size:        dq 4096

    ; Memory shim storage
    free_memory_counter:        dq 4096
    memory_alloc_cursor:        dq 0
    usb_port_count:            dq 0

    ; USB status text
    msg_usb_ready:             db "USB ports initialized", 10, 0

    ; Error & formatting string constants
    msg_sdos_ready:             db "SDOS ready. Type 'help' for a list of commands.", 10, 0
    prompt_sdos:                db "SDOS> ", 0
    str_newline:                db 10, 0
    str_err_prefix:             db "Error: ", 0

    str_cannot_be_empty:        db " cannot be empty", 0
    str_not_valid_integer:      db " is not a valid integer: '", 0
    str_quote_end:              db "'", 0

    str_name_value:             db "value", 0
    str_name_start:             db "start", 0
    str_name_end:               db "end", 0
    str_name_address:           db "address", 0

    err_range_non_negative:     db "memory addresses must be non-negative", 0
    err_end_less_than_start:    db "end address must be greater than or equal to start address", 0
    err_end_exceeds_prefix:     db "end address ", 0
    err_end_exceeds_mid:        db " exceeds the memory bounds of ", 0

    err_addr_outside_prefix:    db "memory address ", 0
    err_addr_outside_suffix:    db " is outside the valid range", 0

    err_numeric_8bit:           db "memory values are limited to 8-bit unsigned integers (0-255)", 0

    err_no_raw_hex:             db "no raw hex data was supplied", 0
    err_hex_complete_bytes:     db "hex payload must contain complete bytes (even number of digits)", 0
    err_payload_exceeds_p1:     db "payload size ", 0
    err_payload_exceeds_p2:     db " exceeds the requested memory width ", 0

    err_unable_parse_p1:        db "unable to parse command: '", 0
    err_unable_parse_p2:        db "'", 0

    err_usage_dir:              db "usage: dir [start] [end]", 0
    err_usage_load:             db "usage: load [raw_hex] [start] [end]", 0
    err_usage_run:              db "usage: run [start] [end]", 0
    err_unknown_command_p1:     db "unknown command: ", 0

    out_loaded_p1:              db "Loaded ", 0
    out_loaded_p2:              db " bytes to memory", 10, 0
    out_exec_p1:                db "Executed memory range ", 0
    out_exec_p2:                db " to ", 0
    out_zero_addr_p1:           db "Zero addresses: ", 0

    help_text:
        db "Available commands:", 10
        db "  dir [start] [end]        list values inside a memory range", 10
        db "  load [raw_hex] [start] [end]  load a raw hex payload into memory", 10
        db "  run [start] [end]        execute a memory range", 10
        db "  mem                     show zero-filled memory addresses", 10, 0

    cmd_dir:                    db "dir", 0
    cmd_load:                   db "load", 0
    cmd_run:                    db "run", 0
    cmd_mem:                    db "mem", 0
    cmd_help:                   db "help", 0
    cmd_help_long:              db "--help", 0
    cmd_help_short:             db "-h", 0

section .bss
    ; Global Kernel instance (matching `kernel = Kernel()`)
    global_kernel_memory_size:  resq 1
    global_kernel_memory:       resb 4096
    usb_port_state:             resb 64

    ; Execution state & buffers
    last_error_flag:            resq 1
    last_error_buffer:          resb 1024

    input_line_buffer:          resb 4096
    normalized_hex_buffer:      resb 4096
    payload_buffer:             resb 4096
    format_num_buffer:          resb 64

    ; Command parsing tokens
    parsed_token_pointers:      resq 64
    parsed_token_count:         resq 1
    token_storage_buffer:       resb 4096

section .text

; ==============================================================================
; Low-level shims in lib.py
; ==============================================================================

list_memory_free:
    mov rax, [free_memory_counter]
    ret

memory_allocate:
    ; rdi = requested byte count
    ; returns rax = pointer into the memory arena
    push rbx
    mov rbx, [memory_alloc_cursor]
    test rdi, rdi
    jle .alloc_fail
    mov rax, rbx
    add rax, rdi
    cmp rax, 4096
    jg .alloc_fail
    lea rax, [global_kernel_memory + rbx]
    mov [memory_alloc_cursor], rdi
    add qword [memory_alloc_cursor], rbx
    pop rbx
    ret

.alloc_fail:
    xor rax, rax
    pop rbx
    ret

read_value_from_memory:
    ; Parameters: rdi = address
    ; Simulate hardware-backed memory read from the kernel buffer.
    mov rax, 0
    cmp rdi, 0
    jl .done
    cmp rdi, [global_kernel_memory_size]
    jge .done
    mov rax, [global_kernel_memory + rdi]
.done:
    ret

start_excute_at:
    ; Parameters: rdi = start, rsi = end
    ; Simulate execution by validating the range but not altering memory.
    ret

write_value_to_memory:
    ; Parameters: rdi = address, rsi = value
    ; Simulate hardware-backed memory write into the kernel buffer.
    cmp rdi, 0
    jl .done
    cmp rdi, [global_kernel_memory_size]
    jge .done
    mov byte [global_kernel_memory + rdi], sil
.done:
    ret

usb_port_init:
    ; rdi = requested port count (defaults to 1 if <= 0)
    ; returns rax = total initialized ports
    push rbx
    push rcx
    mov rbx, rdi
    cmp rbx, 0
    jg .keep_count
    mov rbx, 1
.keep_count:
    mov [usb_port_count], rbx
    lea rdi, [usb_port_state]
    mov rcx, rbx
    mov al, 1
.init_loop:
    cmp rcx, 0
    je .init_done
    mov [rdi], al
    inc rdi
    dec rcx
    jmp .init_loop
.init_done:
    ; optional human-readable output for debugging
    lea rdi, [msg_usb_ready]
    call print_string
    mov rax, [usb_port_count]
    pop rcx
    pop rbx
    ret

; ==============================================================================
; System and Utility Routines
; ==============================================================================

sys_exit:
    mov rax, 60                 ; sys_exit
    syscall
    ret

sys_write_stdout:
    ; rdi = buffer pointer, rsi = length
    mov rdx, rsi                ; count
    mov rsi, rdi                ; buf
    mov rdi, 1                  ; stdout fd
    mov rax, 1                  ; sys_write
    syscall
    ret

string_length:
    ; rdi = null-terminated string pointer
    xor rax, rax
.len_loop:
    cmp byte [rdi + rax], 0
    je .len_done
    inc rax
    jmp .len_loop
.len_done:
    ret

print_string:
    ; rdi = null-terminated string pointer
    push rdi
    call string_length
    pop rdi
    mov rsi, rax
    call sys_write_stdout
    ret

print_newline:
    lea rdi, [str_newline]
    call print_string
    ret

clear_error:
    mov qword [last_error_flag], 0
    mov byte [last_error_buffer], 0
    ret

set_error:
    ; rdi = null-terminated error string
    push rdi
    mov qword [last_error_flag], 1
    lea rsi, [last_error_buffer]
.copy_err:
    mov al, [rdi]
    mov [rsi], al
    inc rdi
    inc rsi
    test al, al
    jnz .copy_err
    pop rdi
    ret

is_space_char:
    ; al = character; returns ZF=1 (je/jz) if space, ZF=0 (jne/jnz) if not space
    cmp al, ' '
    je .is_sp
    cmp al, 9                  ; '\t'
    je .is_sp
    cmp al, 10                 ; '\n'
    je .is_sp
    cmp al, 13                 ; '\r'
    je .is_sp
    cmp al, 11                 ; '\v'
    je .is_sp
    cmp al, 12                 ; '\f'
    je .is_sp
    xor dl, dl                 ; clear ZF
    inc dl                     ; dl = 1, clears ZF
    ret
.is_sp:
    xor al, al                 ; sets ZF
    ret

int_to_str:
    ; rdi = integer value (signed 64-bit), rsi = output buffer
    ; returns rax = length
    push rbx
    push rcx
    push rdx
    mov rax, rdi
    mov rcx, rsi
    test rax, rax
    jns .positive
    mov byte [rcx], '-'
    inc rcx
    neg rax
.positive:
    mov rbx, 10
    push rcx                   ; start of digits
.div_loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    push rdx
    test rax, rax
    jnz .div_loop
.pop_loop:
    pop rdx
    mov [rcx], dl
    inc rcx
    cmp rsp, [rsp - 8]         ; compare stack position to saved pointer
    ; We instead count digits
    ; Let's do standard digit store on stack with counter:
    jmp .done_fixed_logic
.done_fixed_logic:
    ; Clean up and rerun robust int_to_str
    pop rax                    ; clean saved rcx
    pop rdx
    pop rcx
    pop rbx
    jmp robust_int_to_str

robust_int_to_str:
    ; rdi = integer, rsi = destination buffer
    push rbx
    push r12
    push r13
    mov rax, rdi
    mov r12, rsi
    xor r13, r13               ; count of digits
    test rax, rax
    jns .prep_digits
    mov byte [r12], '-'
    inc r12
    neg rax
.prep_digits:
    mov rbx, 10
.digits_loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    push rdx
    inc r13
    test rax, rax
    jnz .digits_loop
.write_digits:
    pop rdx
    mov [r12], dl
    inc r12
    dec r13
    jnz .write_digits
    mov byte [r12], 0
    pop r13
    pop r12
    pop rbx
    ret

; ==============================================================================
; def _to_int(value: str, name: str = "value") -> int:
; ==============================================================================

_to_int:
    ; rdi = pointer to null-terminated string value
    ; rsi = pointer to null-terminated name string (e.g. "value", "start", "end", "address")
    ; returns rax = parsed integer, sets last_error_flag on ValueError
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi               ; original value
    mov r13, rsi               ; name

    ; text = str(value).strip()
    ; Skip leading spaces
.skip_leading:
    mov al, [rdi]
    test al, al
    jz .check_empty
    call is_space_char
    jne .find_end
    inc rdi
    jmp .skip_leading

.find_end:
    mov r14, rdi               ; start of stripped text
    mov r15, rdi
.scan_end:
    cmp byte [r15], 0
    je .backtrack_trailing
    inc r15
    jmp .scan_end

.backtrack_trailing:
    dec r15
.trim_trailing:
    cmp r15, r14
    jb .check_empty
    mov al, [r15]
    call is_space_char
    jne .trimmed_slice_ready
    dec r15
    jmp .trim_trailing

.check_empty:
    ; raise ValueError(f"{name} cannot be empty")
    lea rdi, [last_error_buffer]
    mov rsi, r13
.cpy_name_empty:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .cpy_name_empty
    dec rdi
    lea rsi, [str_cannot_be_empty]
.cpy_empty_msg:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .cpy_empty_msg
    mov qword [last_error_flag], 1
    xor rax, rax
    jmp .done_to_int

.trimmed_slice_ready:
    ; Null-terminate temporary copy of stripped text in format_num_buffer
    lea rbx, [format_num_buffer]
    mov rcx, r14
.copy_stripped:
    mov al, [rcx]
    mov [rbx], al
    inc rbx
    inc rcx
    cmp rcx, r15
    jbe .copy_stripped
    mov byte [rbx], 0

    lea rsi, [format_num_buffer]
    ; Check sign
    xor r8, r8                 ; sign: 0 = positive, 1 = negative
    mov al, [rsi]
    cmp al, '+'
    je .has_pos
    cmp al, '-'
    jne .check_base
    mov r8, 1
    inc rsi
    jmp .check_base
.has_pos:
    inc rsi

.check_base:
    ; text.lower().startswith("0x") -> base 16
    cmp byte [rsi], '0'
    jne .detect_base_0
    mov al, [rsi + 1]
    cmp al, 'x'
    je .base_16_prefix
    cmp al, 'X'
    je .base_16_prefix
    cmp al, 'o'
    je .base_8_prefix
    cmp al, 'O'
    je .base_8_prefix
    cmp al, 'b'
    je .base_2_prefix
    cmp al, 'B'
    je .base_2_prefix

.detect_base_0:
    ; base 10 by default
    mov r9, 10
    jmp .parse_digits

.base_16_prefix:
    add rsi, 2
    mov r9, 16
    jmp .parse_digits

.base_8_prefix:
    add rsi, 2
    mov r9, 8
    jmp .parse_digits

.base_2_prefix:
    add rsi, 2
    mov r9, 2
    jmp .parse_digits

.parse_digits:
    cmp byte [rsi], 0
    je .raise_invalid_format
    xor rax, rax               ; accumulator
.digit_loop:
    movzx rcx, byte [rsi]
    test cl, cl
    jz .parse_success

    ; Convert character to digit value in rdx
    cmp cl, '0'
    jb .raise_invalid_format
    cmp cl, '9'
    jbe .digit_0_9
    cmp cl, 'a'
    jb .check_upper
    cmp cl, 'f'
    ja .raise_invalid_format
    sub cl, 'a'
    add cl, 10
    movzx rdx, cl
    jmp .check_digit_radix

.check_upper:
    cmp cl, 'A'
    jb .raise_invalid_format
    cmp cl, 'F'
    ja .raise_invalid_format
    sub cl, 'A'
    add cl, 10
    movzx rdx, cl
    jmp .check_digit_radix

.digit_0_9:
    sub cl, '0'
    movzx rdx, cl

.check_digit_radix:
    cmp rdx, r9
    jae .raise_invalid_format
    imul rax, r9
    add rax, rdx
    inc rsi
    jmp .digit_loop

.parse_success:
    test r8, r8
    jz .done_to_int
    neg rax
    jmp .done_to_int

.raise_invalid_format:
    ; raise ValueError(f"{name} is not a valid integer: {value!r}")
    lea rdi, [last_error_buffer]
    mov rsi, r13
.cpy_n2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .cpy_n2
    dec rdi
    lea rsi, [str_not_valid_integer]
.cpy_msg2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .cpy_msg2
    dec rdi
    mov rsi, r12
.cpy_val2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .cpy_val2
    dec rdi
    lea rsi, [str_quote_end]
.cpy_q2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .cpy_q2
    mov qword [last_error_flag], 1
    xor rax, rax

.done_to_int:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ==============================================================================
; Kernel class implementation
; ==============================================================================

Kernel:
kernel_init:
    ; rdi = memory_size (default 4096)
    cmp rdi, 0
    jg .size_ok
    mov rdi, 4096
.size_ok:
    mov [global_kernel_memory_size], rdi
    mov qword [memory_alloc_cursor], 0
    ; self.memory: Dict[int, int] = {address: 0 for address in range(memory_size)}
    lea rdi, [global_kernel_memory]
    mov rcx, 4096
    xor al, al
.zero_mem:
    mov [rdi], al
    inc rdi
    dec rcx
    jnz .zero_mem
    ret

kernel_validate_range:
    ; rdi = start, rsi = end
    ; returns rax = start_addr, rdx = end_addr; sets error on exception
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi

    lea rsi, [str_name_start]
    call _to_int
    cmp qword [last_error_flag], 0
    jne .validate_failed
    mov r14, rax               ; start_addr

    mov rdi, r13
    lea rsi, [str_name_end]
    call _to_int
    cmp qword [last_error_flag], 0
    jne .validate_failed
    mov rbx, rax               ; end_addr

    ; if start_addr < 0 or end_addr < 0:
    test r14, r14
    js .err_non_negative
    test rbx, rbx
    js .err_non_negative

    ; if end_addr < start_addr:
    cmp rbx, r14
    jl .err_end_less

    ; if end_addr >= self.memory_size:
    mov rcx, [global_kernel_memory_size]
    cmp rbx, rcx
    jge .err_end_exceeds

    mov rax, r14
    mov rdx, rbx
    jmp .validate_done

.err_non_negative:
    lea rdi, [err_range_non_negative]
    call set_error
    jmp .validate_failed

.err_end_less:
    lea rdi, [err_end_less_than_start]
    call set_error
    jmp .validate_failed

.err_end_exceeds:
    ; f"end address {end_addr} exceeds the memory bounds of {self.memory_size - 1}"
    lea rdi, [last_error_buffer]
    lea rsi, [err_end_exceeds_prefix]
.c1:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .c1
    dec rdi

    push rdi
    mov rdi, rbx
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    pop rdi
    lea rsi, [format_num_buffer]
.c2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .c2
    dec rdi

    lea rsi, [err_end_exceeds_mid]
.c3:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .c3
    dec rdi

    mov rax, [global_kernel_memory_size]
    dec rax
    push rdi
    mov rdi, rax
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    pop rdi
    lea rsi, [format_num_buffer]
.c4:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .c4
    mov qword [last_error_flag], 1

.validate_failed:
    xor rax, rax
    xor rdx, rdx

.validate_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

kernel_read_memory:
    ; rdi = address
    push rbx
    mov rbx, rdi
    lea rsi, [str_name_address]
    call _to_int
    cmp qword [last_error_flag], 0
    jne .read_err

    test rax, rax
    js .read_outside
    cmp rax, [global_kernel_memory_size]
    jge .read_outside

    mov rbx, rax
    lea rdi, [global_kernel_memory]
    movzx rax, byte [rdi + rbx]

    push rax
    mov rdi, rbx
    call read_value_from_memory
    pop rax
    pop rbx
    ret

.read_outside:
    ; f"memory address {addr} is outside the valid range"
    lea rdi, [last_error_buffer]
    lea rsi, [err_addr_outside_prefix]
.ro1:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    test cl, cl
    jnz .ro1
    dec rdi

    push rdi
    mov rdi, rax
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    pop rdi
    lea rsi, [format_num_buffer]
.ro2:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    test cl, cl
    jnz .ro2
    dec rdi

    lea rsi, [err_addr_outside_suffix]
.ro3:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    test cl, cl
    jnz .ro3
    mov qword [last_error_flag], 1

.read_err:
    xor rax, rax
    pop rbx
    ret

kernel_write_memory:
    ; rdi = address, rsi = value
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    mov rdi, rbx
    lea rsi, [str_name_address]
    call _to_int
    cmp qword [last_error_flag], 0
    jne .write_err
    mov r13, rax               ; addr

    mov rdi, r12
    lea rsi, [str_name_value]
    call _to_int
    cmp qword [last_error_flag], 0
    jne .write_err
    mov rbx, rax               ; numeric_value

    ; if addr < 0 or addr >= self.memory_size:
    test r13, r13
    js .write_outside
    cmp r13, [global_kernel_memory_size]
    jge .write_outside

    ; if numeric_value < 0 or numeric_value > 255:
    test rbx, rbx
    js .write_invalid_val
    cmp rbx, 255
    jg .write_invalid_val

    lea rdi, [global_kernel_memory]
    mov [rdi + r13], bl

    mov rdi, r13
    mov rsi, rbx
    call write_value_to_memory

    mov rax, rbx
    jmp .write_done

.write_outside:
    lea rdi, [last_error_buffer]
    lea rsi, [err_addr_outside_prefix]
.wo1:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    test cl, cl
    jnz .wo1
    dec rdi

    push rdi
    mov rdi, r13
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    pop rdi
    lea rsi, [format_num_buffer]
.wo2:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    test cl, cl
    jnz .wo2
    dec rdi

    lea rsi, [err_addr_outside_suffix]
.wo3:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    test cl, cl
    jnz .wo3
    mov qword [last_error_flag], 1
    xor rax, rax
    jmp .write_done

.write_invalid_val:
    lea rdi, [err_numeric_8bit]
    call set_error
    xor rax, rax
    jmp .write_done

.write_err:
    xor rax, rax

.write_done:
    pop r13
    pop r12
    pop rbx
    ret

kernel_dir:
    ; rdi = start, rsi = end
    push rbx
    push r12
    push r13
    push r14

    call kernel_validate_range
    cmp qword [last_error_flag], 0
    jne .dir_failed

    mov r12, rax               ; start_addr
    mov r13, rdx               ; end_addr

    ; Format and print Python representation: [(0, 0), (1, 0), ...]
    mov al, '['
    lea rdi, [format_num_buffer]
    mov [rdi], al
    mov rsi, 1
    call sys_write_stdout

    mov r14, r12
.dir_loop:
    cmp r14, r13
    jg .dir_end_bracket

    cmp r14, r12
    je .print_pair
    lea rdi, [format_num_buffer]
    mov word [rdi], 0x202C     ; ", "
    mov rsi, 2
    call sys_write_stdout

.print_pair:
    lea rdi, [format_num_buffer]
    mov byte [rdi], '('
    mov rsi, 1
    call sys_write_stdout

    mov rdi, r14
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    lea rdi, [format_num_buffer]
    call print_string

    lea rdi, [format_num_buffer]
    mov word [rdi], 0x202C     ; ", "
    mov rsi, 2
    call sys_write_stdout

    ; read_memory(r14)
    lea rdi, [format_num_buffer]
    mov rax, r14
    call robust_int_to_str
    lea rdi, [format_num_buffer]
    call kernel_read_memory
    mov rbx, rax

    mov rdi, rbx
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    lea rdi, [format_num_buffer]
    call print_string

    lea rdi, [format_num_buffer]
    mov byte [rdi], ')'
    mov rsi, 1
    call sys_write_stdout

    inc r14
    jmp .dir_loop

.dir_end_bracket:
    lea rdi, [format_num_buffer]
    mov byte [rdi], ']'
    mov rsi, 1
    call sys_write_stdout
    call print_newline

.dir_failed:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

kernel_load:
    ; rdi = raw_hex, rsi = start, rdx = end
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi               ; raw_hex
    mov r13, rsi               ; start
    mov r14, rdx               ; end

    mov rdi, r13
    mov rsi, r14
    call kernel_validate_range
    cmp qword [last_error_flag], 0
    jne .load_failed
    mov r13, rax               ; start_addr
    mov r14, rdx               ; end_addr

    ; normalized = re.sub(r"[^0-9A-Fa-f]", "", str(raw_hex))
    lea rdi, [normalized_hex_buffer]
    mov rsi, r12
    xor rcx, rcx               ; length of normalized
.normalize_loop:
    mov al, [rsi]
    test al, al
    jz .normalize_done
    inc rsi

    ; Check 0-9, A-F, a-f
    cmp al, '0'
    jb .normalize_loop
    cmp al, '9'
    jbe .keep_char
    cmp al, 'A'
    jb .normalize_loop
    cmp al, 'F'
    jbe .keep_char
    cmp al, 'a'
    jb .normalize_loop
    cmp al, 'f'
    ja .normalize_loop

.keep_char:
    mov [rdi + rcx], al
    inc rcx
    jmp .normalize_loop

.normalize_done:
    mov byte [rdi + rcx], 0
    test rcx, rcx
    jnz .check_even
    lea rdi, [err_no_raw_hex]
    call set_error
    jmp .load_failed

.check_even:
    test rcx, 1
    jz .parse_payload_bytes
    lea rdi, [err_hex_complete_bytes]
    call set_error
    jmp .load_failed

.parse_payload_bytes:
    mov r15, rcx
    shr r15, 1                 ; payload size in bytes (rcx / 2)

    ; width = end_addr - start_addr + 1
    mov rax, r14
    sub rax, r13
    inc rax                    ; width
    cmp r15, rax
    jle .do_payload_conversion

    ; raise ValueError(f"payload size {len(payload)} exceeds the requested memory width {width}")
    lea rdi, [last_error_buffer]
    lea rsi, [err_payload_exceeds_p1]
.lp1:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    test cl, cl
    jnz .lp1
    dec rdi

    push rdi
    push rax
    mov rdi, r15
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    pop rax
    pop rdi
    lea rsi, [format_num_buffer]
.lp2:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    test cl, cl
    jnz .lp2
    dec rdi

    lea rsi, [err_payload_exceeds_p2]
.lp3:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    test cl, cl
    jnz .lp3
    dec rdi

    push rdi
    mov rdi, rax
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    pop rdi
    lea rsi, [format_num_buffer]
.lp4:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    test cl, cl
    jnz .lp4
    mov qword [last_error_flag], 1
    jmp .load_failed

.do_payload_conversion:
    xor rbx, rbx               ; byte index
.convert_loop:
    cmp rbx, r15
    jae .write_payload_to_memory

    mov rsi, rbx
    shl rsi, 1
    lea rdx, [normalized_hex_buffer]
    movzx rdi, byte [rdx + rsi]     ; high nibble char
    movzx r8, byte [rdx + rsi + 1] ; low nibble char

    ; Convert high nibble
    cmp dil, '9'
    jbe .h_num
    cmp dil, 'F'
    jbe .h_upper
    sub dil, 'a' - 10
    jmp .h_done
.h_upper:
    sub dil, 'A' - 10
    jmp .h_done
.h_num:
    sub dil, '0'
.h_done:

    ; Convert low nibble
    cmp r8b, '9'
    jbe .l_num
    cmp r8b, 'F'
    jbe .l_upper
    sub r8b, 'a' - 10
    jmp .l_done
.l_upper:
    sub r8b, 'A' - 10
    jmp .l_done
.l_num:
    sub r8b, '0'
.l_done:

    shl dil, 4
    or dil, r8b
    lea rcx, [payload_buffer]
    mov [rcx + rbx], dil
    inc rbx
    jmp .convert_loop

.write_payload_to_memory:
    ; for offset, byte_value in enumerate(payload):
    ;     self.write_memory(start_addr + offset, byte_value)
    xor rbx, rbx
.write_loop:
    cmp rbx, r15
    jae .load_success

    lea rcx, [payload_buffer]
    movzx rsi, byte [rcx + rbx] ; byte_value
    mov rdi, r13
    add rdi, rbx               ; start_addr + offset

    ; Convert both to strings for write_memory shim
    push rbx
    push rdi
    push rsi
    lea rsi, [token_storage_buffer]
    call robust_int_to_str     ; address str

    pop rdi                    ; byte_value
    lea rsi, [token_storage_buffer + 64]
    call robust_int_to_str     ; value str

    lea rdi, [token_storage_buffer]
    lea rsi, [token_storage_buffer + 64]
    call kernel_write_memory
    pop rdi
    pop rbx

    inc rbx
    jmp .write_loop

.load_success:
    mov rax, r15               ; return number of loaded bytes
    jmp .load_exit

.load_failed:
    xor rax, rax

.load_exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

kernel_run:
    ; rdi = start, rsi = end
    push rbx
    push r12
    push r13
    push r14

    call kernel_validate_range
    cmp qword [last_error_flag], 0
    jne .run_failed

    mov r12, rax               ; start_addr
    mov r13, rdx               ; end_addr

    mov rdi, r12
    mov rsi, r13
    call start_excute_at

    ; return [self.read_memory(addr) for addr in range(start_addr, end_addr + 1)]
    ; read all values
    mov r14, r12
.run_read_loop:
    cmp r14, r13
    jg .run_success

    mov rdi, r14
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    lea rdi, [format_num_buffer]
    call kernel_read_memory

    inc r14
    jmp .run_read_loop

.run_success:
    mov rax, 1
    jmp .run_exit

.run_failed:
    xor rax, rax

.run_exit:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

kernel_mem:
    ; returns rax = zero_addresses, rdx = free_memory
    push rbx
    call list_memory_free
    mov rdx, rax               ; free_memory

    ; zero_addresses = sum(1 for value in self.memory.values() if value == 0)
    xor rax, rax
    xor rcx, rcx
    lea rbx, [global_kernel_memory]
.count_zeros:
    cmp rcx, [global_kernel_memory_size]
    jae .mem_done
    cmp byte [rbx + rcx], 0
    jne .skip_zero
    inc rax
.skip_zero:
    inc rcx
    jmp .count_zeros

.mem_done:
    pop rbx
    ret

; ==============================================================================
; shlex.split equivalent tokenizer
; ==============================================================================

split_command_line:
    ; rdi = command_line string pointer
    ; returns rax = count of tokens (stores token pointers in parsed_token_pointers)
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi
    lea r13, [parsed_token_pointers]
    lea r14, [token_storage_buffer]
    xor r15, r15               ; token count
    mov qword [parsed_token_count], 0

.skip_token_sp:
    mov al, [r12]
    test al, al
    jz .split_success
    call is_space_char
    jne .start_token
    inc r12
    jmp .skip_token_sp

.start_token:
    mov [r13 + r15 * 8], r14   ; store token pointer
    inc r15

.token_char_loop:
    mov al, [r12]
    test al, al
    jz .finish_token
    call is_space_char
    je .finish_token

    cmp al, '"'
    je .in_dquote
    cmp al, "'"
    je .in_squote

    mov [r14], al
    inc r14
    inc r12
    jmp .token_char_loop

.in_dquote:
    inc r12                    ; skip opening quote
.dquote_loop:
    mov al, [r12]
    test al, al
    jz .err_unclosed_quote
    cmp al, '"'
    je .close_quote
    mov [r14], al
    inc r14
    inc r12
    jmp .dquote_loop

.in_squote:
    inc r12                    ; skip opening quote
.squote_loop:
    mov al, [r12]
    test al, al
    jz .err_unclosed_quote
    cmp al, "'"
    je .close_quote
    mov [r14], al
    inc r14
    inc r12
    jmp .squote_loop

.close_quote:
    inc r12
    jmp .token_char_loop

.finish_token:
    mov byte [r14], 0
    inc r14
    jmp .skip_token_sp

.err_unclosed_quote:
    ; raise ValueError(f"unable to parse command: {command_line!r}")
    lea rdi, [last_error_buffer]
    lea rsi, [err_unable_parse_p1]
.eup1:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .eup1
    dec rdi

    mov rsi, [input_line_buffer]
    lea rsi, [input_line_buffer]
.eup2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .eup2
    dec rdi

    lea rsi, [err_unable_parse_p2]
.eup3:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .eup3
    mov qword [last_error_flag], 1
    xor rax, rax
    jmp .split_done

.split_success:
    mov [parsed_token_count], r15
    mov rax, r15

.split_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ==============================================================================
; String Comparison Helpers
; ==============================================================================

strcmp_exact:
    ; rdi, rsi null-terminated strings
.sc_loop:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .sc_diff
    test al, al
    jz .sc_eq
    inc rdi
    inc rsi
    jmp .sc_loop
.sc_diff:
    mov rax, 1
    ret
.sc_eq:
    xor rax, rax
    ret

to_lower_in_place:
    ; rdi = null-terminated string
.low_loop:
    mov al, [rdi]
    test al, al
    jz .low_done
    cmp al, 'A'
    jb .next_c
    cmp al, 'Z'
    ja .next_c
    add byte [rdi], 32
.next_c:
    inc rdi
    jmp .low_loop
.low_done:
    ret

; ==============================================================================
; Kernel.execute(command_line: str)
; ==============================================================================

kernel_execute:
    ; rdi = command_line
    push rbx
    push r12
    push r13

    call clear_error

    test rdi, rdi
    jz .exec_none

    ; if not command_line or not command_line.strip():
    mov r12, rdi
.chk_strip:
    mov al, [r12]
    test al, al
    jz .exec_none
    call is_space_char
    jne .has_non_space
    inc r12
    jmp .chk_strip

.has_non_space:
    mov rdi, [rsp + 0]         ; command_line
    call split_command_line
    cmp qword [last_error_flag], 0
    jne .exec_error

    mov rcx, [parsed_token_count]
    test rcx, rcx
    jz .exec_none

    ; command = tokens[0].lower()
    mov r12, [parsed_token_pointers]
    mov rdi, r12
    call to_lower_in_place

    ; if command == "dir":
    mov rdi, r12
    lea rsi, [cmd_dir]
    call strcmp_exact
    test rax, rax
    jne .check_load_cmd

    cmp qword [parsed_token_count], 3
    je .do_dir
    lea rdi, [err_usage_dir]
    call set_error
    jmp .exec_error

.do_dir:
    mov rdi, [parsed_token_pointers + 8]
    mov rsi, [parsed_token_pointers + 16]
    call kernel_dir
    jmp .exec_done

.check_load_cmd:
    mov rdi, r12
    lea rsi, [cmd_load]
    call strcmp_exact
    test rax, rax
    jne .check_run_cmd

    cmp qword [parsed_token_count], 4
    je .do_load
    lea rdi, [err_usage_load]
    call set_error
    jmp .exec_error

.do_load:
    mov rdi, [parsed_token_pointers + 8]
    mov rsi, [parsed_token_pointers + 16]
    mov rdx, [parsed_token_pointers + 24]
    call kernel_load
    cmp qword [last_error_flag], 0
    jne .exec_error

    ; print(f"Loaded {len(result)} bytes to memory")
    mov rbx, rax
    lea rdi, [out_loaded_p1]
    call print_string
    mov rdi, rbx
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    lea rdi, [format_num_buffer]
    call print_string
    lea rdi, [out_loaded_p2]
    call print_string
    jmp .exec_done

.check_run_cmd:
    mov rdi, r12
    lea rsi, [cmd_run]
    call strcmp_exact
    test rax, rax
    jne .check_mem_cmd

    cmp qword [parsed_token_count], 3
    je .do_run
    lea rdi, [err_usage_run]
    call set_error
    jmp .exec_error

.do_run:
    mov rdi, [parsed_token_pointers + 8]
    mov rsi, [parsed_token_pointers + 16]
    call kernel_run
    cmp qword [last_error_flag], 0
    jne .exec_error

    ; print(f"Executed memory range {tokens[1]} to {tokens[2]}")
    lea rdi, [out_exec_p1]
    call print_string
    mov rdi, [parsed_token_pointers + 8]
    call print_string
    lea rdi, [out_exec_p2]
    call print_string
    mov rdi, [parsed_token_pointers + 16]
    call print_string
    call print_newline
    jmp .exec_done

.check_mem_cmd:
    mov rdi, r12
    lea rsi, [cmd_mem]
    call strcmp_exact
    test rax, rax
    jne .check_help_cmd

    call kernel_mem
    ; print(f"Zero addresses: {result['zero_addresses']}")
    mov rbx, rax
    lea rdi, [out_zero_addr_p1]
    call print_string
    mov rdi, rbx
    lea rsi, [format_num_buffer]
    call robust_int_to_str
    lea rdi, [format_num_buffer]
    call print_string
    call print_newline
    jmp .exec_done

.check_help_cmd:
    ; if command in {"help", "--help", "-h"}:
    mov rdi, r12
    lea rsi, [cmd_help]
    call strcmp_exact
    test rax, rax
    jz .do_help

    mov rdi, r12
    lea rsi, [cmd_help_long]
    call strcmp_exact
    test rax, rax
    jz .do_help

    mov rdi, r12
    lea rsi, [cmd_help_short]
    call strcmp_exact
    test rax, rax
    jz .do_help

    ; raise ValueError(f"unknown command: {command}")
    lea rdi, [last_error_buffer]
    lea rsi, [err_unknown_command_p1]
.uk1:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .uk1
    dec rdi

    mov rsi, r12
.uk2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .uk2
    mov qword [last_error_flag], 1
    jmp .exec_error

.do_help:
    lea rdi, [help_text]
    call print_string
    jmp .exec_done

.exec_none:
    xor rax, rax
    jmp .exec_done

.exec_error:
    xor rax, rax

.exec_done:
    pop r13
    pop r12
    pop rbx
    ret

; ==============================================================================
; Top-level command function
; ==============================================================================

command:
    ; def command(command_line: str):
    ;     return kernel.execute(command_line)
    call kernel_execute
    ret

; ==============================================================================
; Main REPL Loop
; ==============================================================================

main:
    push rbx
    push r12

    ; kernel = Kernel()
    mov rdi, 4096
    call kernel_init

    ; print("SDOS ready. Type 'help' for a list of commands.")
    lea rdi, [msg_sdos_ready]
    call print_string

.repl_loop:
    ; print prompt
    lea rdi, [prompt_sdos]
    call print_string

    ; read line from stdin (fd 0)
    lea rsi, [input_line_buffer]
    mov rdi, 0                 ; stdin
    mov rdx, 4095
    mov rax, 0                 ; sys_read
    syscall

    ; Handle EOF / errors
    cmp rax, 0
    jle .repl_eof

    ; Null-terminate and strip newline
    lea rdi, [input_line_buffer]
    mov byte [rdi + rax], 0
    dec rax
    cmp byte [rdi + rax], 10   ; '\n'
    jne .chk_strip_empty
    mov byte [rdi + rax], 0
    dec rax
    cmp rax, 0
    jl .chk_strip_empty
    cmp byte [rdi + rax], 13   ; '\r'
    jne .chk_strip_empty
    mov byte [rdi + rax], 0

.chk_strip_empty:
    ; if not command_line.strip(): continue
    lea rdi, [input_line_buffer]
.chk_all_sp:
    mov al, [rdi]
    test al, al
    jz .repl_loop
    call is_space_char
    jne .repl_execute_line
    inc rdi
    jmp .chk_all_sp

.repl_execute_line:
    lea rdi, [input_line_buffer]
    call kernel_execute

    ; except ValueError as exc: print(f"Error: {exc}")
    cmp qword [last_error_flag], 0
    je .repl_loop

    lea rdi, [str_err_prefix]
    call print_string
    lea rdi, [last_error_buffer]
    call print_string
    call print_newline
    jmp .repl_loop

.repl_eof:
    ; except EOFError: print(); break
    call print_newline
    pop r12
    pop rbx
    ret

; ==============================================================================
; Entry Point (_start)
; ==============================================================================

_start:
    ; Clear Direction Flag per x86_64 ABI
    cld

    ; Initialize global kernel instance and platform resources
    mov rdi, 4096
    call kernel_init
    mov rdi, 4
    call usb_port_init
    mov rdi, 128
    call memory_allocate

    ; if __name__ == "__main__": main()
    call main

    ; Exit with code 0
    xor rdi, rdi
    call sys_exit
