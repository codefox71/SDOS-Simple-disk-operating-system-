BITS 16
ORG 0x7E00

MEMORY_SIZE equ 4096
MEMORY_BASE equ 0xC000
BTFS_START_LBA equ 17
BTFS_BUFFER equ 0xA000
BTFS_TREE equ BTFS_BUFFER + 32
BTFS_DATA_BUFFER equ 0xB200

start:
    cld
    mov word [0x200], ascii_output_interrupt
    mov word [0x202], 0
    mov word [0x204], ascii_input_interrupt
    mov word [0x206], 0
    mov word [0x208], ascii_exit_interrupt
    mov word [0x20A], 0
    mov word [0x20C], kernel_command_interrupt
    mov word [0x20E], 0
    mov si, boot_msg
    call print_string
    call initialize_memory
    call initialize_btfs

.prompt_loop:
    mov si, prompt_msg
    call print_string

    xor cx, cx
    mov di, input_buffer

.read_key:
    mov ah, 0x00
    int 0x16

    cmp al, 0x0D
    je .enter
    cmp al, 0x08
    je .backspace
    cmp al, 0x7F
    je .backspace
    cmp al, 0x1B
    je .quit

    cmp cx, 63
    jae .read_key

    stosb
    inc cx

    mov ah, 0x0E
    mov bl, 0x07
    int 0x10
    jmp .read_key

.backspace:
    cmp cx, 0
    je .read_key
    dec cx
    dec di

    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .read_key

.enter:
    mov al, 0
    stosb

    mov si, newline
    call print_string

    mov si, input_buffer
    call process_command

    mov si, newline
    call print_string
    jmp .prompt_loop

.quit:
    mov si, goodbye_msg
    call print_string
    cli
    hlt

initialize_memory:
    mov word [next_free_addr], 0
    mov cx, MEMORY_SIZE
    mov di, MEMORY_BASE
.init_loop:
    mov byte [di], 0
    inc di
    dec cx
    jnz .init_loop
    ret

ascii_output_interrupt:
    push ax
    push bx
    push cx
    push dx
    push si
    cmp ah, 1
    je .string_loop
    call output_ascii_character
    jmp .done
.string_loop:
    lodsb
    test al, al
    jz .done
    call output_ascii_character
    jmp .string_loop
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret

output_ascii_character:
    cmp al, 0x20
    jb .control
    cmp al, 0x7E
    ja .skip
    jmp .emit
.control:
    cmp al, 0x08
    je .emit
    cmp al, 0x09
    je .emit
    cmp al, 0x0A
    je .emit
    cmp al, 0x0D
    jne .skip
.emit:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov ah, 0x0E
    mov bl, 0x07
    int 0x10
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.skip:
    ret

ascii_input_interrupt:
    push bx
    push cx
    push dx
    push si
    push di
.read_key:
    xor ah, ah
    int 0x16
    test al, al
    jz .read_key
    cmp al, 0x7F
    jne .save_character
    mov al, 0x08
.save_character:
    mov [input_char], al
    cmp al, 0x0D
    je .echo_enter
    cmp al, 0x08
    je .echo_backspace
    call output_ascii_character
    jmp .return_character
.echo_enter:
    call output_ascii_character
    mov al, 0x0A
    call output_ascii_character
    jmp .return_character
.echo_backspace:
    call output_ascii_character
    mov al, ' '
    call output_ascii_character
    mov al, 0x08
    call output_ascii_character
.return_character:
    mov al, [input_char]
    xor ah, ah
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    iret

ascii_exit_interrupt:
    mov [last_exit_code], al
    push bp
    mov bp, sp
    mov word [ss:bp + 2], program_abort
    pop bp
    iret

program_abort:
    ret

kernel_command_interrupt:
    mov [kernel_command_id], ah
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov byte [kernel_call_mode], 1
    call process_command
    mov byte [kernel_call_mode], 0
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret

skip_spaces:
    cmp byte [si], 0
    je .done
    cmp byte [si], ' '
    je .next
    cmp byte [si], 9
    je .next
    cmp byte [si], 13
    je .next
    cmp byte [si], 10
    je .next
    jmp .done
.next:
    inc si
    jmp skip_spaces
.done:
    ret

read_token_lower:
    push di
    xor cx, cx
.token_loop:
    cmp byte [si], 0
    je .finish
    cmp byte [si], ' '
    je .finish
    cmp byte [si], 9
    je .finish
    cmp byte [si], 13
    je .finish
    cmp byte [si], 10
    je .finish
    mov al, [si]
    cmp al, 'A'
    jb .store
    cmp al, 'Z'
    ja .store
    add al, 32
.store:
    mov [di], al
    inc di
    inc si
    inc cx
    jmp .token_loop
.finish:
    mov byte [di], 0
    pop di
    ret

write_dec:
    push ax
    push bx
    push cx
    push dx
    mov ax, dx
    mov bx, 10
    xor cx, cx
    mov si, temp_num_buf + 15
    mov byte [si], 0
.loop:
    xor dx, dx
    div bx
    add dl, '0'
    dec si
    mov [si], dl
    inc cx
    test ax, ax
    jnz .loop
    mov di, si
    ; print string from di
.print_loop:
    mov al, [di]
    test al, al
    jz .done
    mov ah, 0x0E
    mov bl, 0x07
    int 0x10
    inc di
    jmp .print_loop
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

process_command:
    push si
    mov si, input_buffer
    call skip_spaces
    cmp byte [si], 0
    je .done

    mov di, command_name
    call read_token_lower
    mov si, command_name

    cmp byte [kernel_call_mode], 0
    jne .kernel_command

    mov di, cmd_help
    call strcmp_ci
    cmp ax, 0
    je .cmd_help
    mov di, cmd_help_long
    call strcmp_ci
    cmp ax, 0
    je .cmd_help
    mov di, cmd_help_short
    call strcmp_ci
    cmp ax, 0
    je .cmd_help

    mov di, cmd_mem
    call strcmp_ci
    cmp ax, 0
    je .cmd_mem
    mov di, cmd_status
    call strcmp_ci
    cmp ax, 0
    je .cmd_status

    mov di, cmd_dir
    call strcmp_ci
    cmp ax, 0
    je .cmd_dir

    mov di, cmd_run
    call strcmp_ci
    cmp ax, 0
    je .cmd_run

    mov di, cmd_load
    call strcmp_ci
    cmp ax, 0
    je .cmd_load

    call run_bin_command
    jc .unknown_command
    jmp .done
.unknown_command:
    mov si, unknown_msg
    call print_string
    jmp .done
.kernel_command:
    mov al, [kernel_command_id]
    cmp al, 0
    je .cmd_pwd
    cmp al, 1
    je .cmd_chdir
    cmp al, 2
    je .cmd_ls
    cmp al, 3
    je .cmd_cat
    cmp al, 4
    je .cmd_echo
    cmp al, 5
    je .cmd_clear
    cmp al, 6
    je .cmd_touch
    cmp al, 7
    je .cmd_rmf
    cmp al, 8
    je .cmd_cpy
    cmp al, 9
    je .cmd_move
    cmp al, 10
    je .cmd_makedir
    cmp al, 11
    je .cmd_remdir
    jmp .unknown_command

.cmd_dir:
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    call parse_uint_arg
    jc .usage_dir
    mov bp, ax
    call skip_spaces
    call parse_uint_arg
    jc .usage_dir
    mov dx, ax
    call require_no_more_args
    jne .usage_dir
    call validate_range
    jc .range_error
    call dump_range
    jmp .done
.usage_dir:
    mov si, usage_dir
    call print_string
    jmp .done

.cmd_load:
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    mov di, path_buffer
    call read_token
    mov [path_length], cx
    call skip_spaces
    cmp byte [btfs_valid], 1
    jne .btfs_error
    mov di, hex_arg
    call read_token_lower
    test cx, cx
    jz .usage_load
    mov [hex_length], cx
    call require_no_more_args
    cmp byte [si], 0
    je .file_write
.raw_load:
    mov si, path_buffer
    mov di, hex_arg
    mov cx, [path_length]
    rep movsb
    mov byte [di], 0
    mov cx, [path_length]
    mov [hex_length], cx
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    call skip_command_token
    call parse_uint_arg
    jc .usage_load
    mov bp, ax
    call skip_spaces
    call parse_uint_arg
    jc .usage_load
    mov dx, ax
    call require_no_more_args
    jne .usage_load
    call validate_range
    jc .range_error
    call store_hex_range
    jc .bad_hex
    mov ax, dx
    inc ax
    cmp ax, [next_free_addr]
    jbe .raw_load_reserved
    mov [next_free_addr], ax
.raw_load_reserved:
    mov dx, [loaded_count]
    mov si, loaded_msg
    call print_string
    call write_dec
    mov si, bytes_msg
    call print_string
    jmp .done
.file_write:
    call write_file_from_hex
    jc .file_error
    mov si, file_written_msg
    call print_string
    mov dx, [write_size]
    call write_dec
    mov si, file_bytes_msg
    call print_string
    jmp .done
.usage_load:
    mov si, usage_load
    call print_string
    jmp .done
.bad_hex:
    mov si, bad_hex_msg
    call print_string
    jmp .done
.file_error:
    mov si, file_error_msg
    call print_string
    jmp .done
.btfs_error:
    mov si, btfs_error_msg
    call print_string
    jmp .done

.cmd_rmf:
    cmp byte [btfs_valid], 1
    jne .btfs_error
    call parse_one_path
    jc .usage_rmf
    call resolve_path
    jc .file_error
    call get_node_record
    cmp byte [di + 4], 2
    jne .file_error
    call free_file_chain
    jc .file_error
    call get_node_record
    mov word [di], 0xFFFF
    call write_tree
    jc .file_error
    mov si, removed_msg
    call print_string
    jmp .done
.usage_rmf:
    mov si, usage_rmf
    call print_string
    jmp .done

.cmd_cpy:
    cmp byte [btfs_valid], 1
    jne .btfs_error
    call parse_two_paths
    jc .usage_cpy
    mov si, path_buffer
    call resolve_path
    jc .file_error
    call get_node_record
    cmp byte [di + 4], 2
    jne .file_error
    call load_file_to_memory
    jc .file_error
    mov ax, [file_start]
    add ax, MEMORY_BASE
    mov [write_source], ax
    mov ax, [file_size]
    mov [write_size], ax
    mov si, path2_buffer
    mov di, path_buffer
    call copy_zstring
    call write_file_from_memory
    jc .file_error
    mov si, copied_msg
    call print_string
    jmp .done
.usage_cpy:
    mov si, usage_cpy
    call print_string
    jmp .done

.cmd_move:
    cmp byte [btfs_valid], 1
    jne .btfs_error
    call parse_two_paths
    jc .usage_move
    mov si, path_buffer
    call resolve_path
    jc .file_error
    mov ax, [resolve_node]
    mov [source_node], ax
    mov si, path2_buffer
    mov di, path_buffer
    call copy_zstring
    call resolve_parent
    jc .file_error
    mov ax, [resolve_node]
    mov [destination_parent], ax
    call find_child
    jnc .file_error
    mov ax, [source_node]
    mov [resolve_node], ax
    call get_node_record
    mov ax, [destination_parent]
    mov [di + 2], ax
    mov al, [component_length]
    mov [di + 5], al
    push di
    add di, 6
    mov si, name_buffer
    mov cx, 40
    xor al, al
    rep stosb
    pop di
    push di
    add di, 6
    mov si, name_buffer
    mov cl, [component_length]
    xor ch, ch
    rep movsb
    pop di
    call write_tree
    jc .file_error
    mov si, moved_msg
    call print_string
    jmp .done
.usage_move:
    mov si, usage_move
    call print_string
    jmp .done

.cmd_makedir:
    cmp byte [btfs_valid], 1
    jne .btfs_error
    call parse_one_path
    jc .usage_makedir
    call create_directory_from_path
    jc .file_error
    mov si, directory_created_msg
    call print_string
    jmp .done
.usage_makedir:
    mov si, usage_makedir
    call print_string
    jmp .done

.cmd_remdir:
    cmp byte [btfs_valid], 1
    jne .btfs_error
    call parse_one_path
    jc .usage_remdir
    call resolve_path
    jc .file_error
    call get_node_record
    cmp byte [di + 4], 1
    jne .file_error
    mov ax, [resolve_node]
    mov [source_node], ax
    call directory_is_empty
    jc .file_error
    mov ax, [source_node]
    mov [resolve_node], ax
    call get_node_record
    mov word [di], 0xFFFF
    call write_tree
    jc .file_error
    mov si, directory_removed_msg
    call print_string
    jmp .done
.usage_remdir:
    mov si, usage_remdir
    call print_string
    jmp .done

.cmd_run:
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    call skip_spaces
    cmp byte [si], '-'
    je .cmd_run_files
    call parse_uint_arg
    jc .usage_run
    mov bp, ax
    call skip_spaces
    call parse_uint_arg
    jc .usage_run
    mov dx, ax
    call require_no_more_args
    jne .usage_run
    call validate_range
    jc .range_error
    mov [run_start], bp
    mov [run_end], dx
    call execute_payload
    jmp .done
.cmd_run_files:
    cmp byte [btfs_valid], 1
    jne .btfs_error
    mov ax, [next_free_addr]
    mov [run_start], ax
    mov word [expected_file_index], 1
.run_file_loop:
    call skip_spaces
    cmp byte [si], 0
    je .run_files_done
    cmp byte [si], '-'
    jne .usage_run
    inc si
    cmp byte [si], 'f'
    jne .usage_run
    inc si
    call parse_uint_arg
    jc .usage_run
    cmp ax, [expected_file_index]
    jne .usage_run
    inc word [expected_file_index]
    call skip_spaces
    mov di, path_buffer
    call read_token
    test cx, cx
    jz .usage_run
    call resolve_path
    jc .file_error
    call load_file_to_memory
    jc .file_error
    jmp .run_file_loop
.run_files_done:
    cmp word [expected_file_index], 1
    je .usage_run
    mov ax, [next_free_addr]
    cmp ax, [run_start]
    je .file_error
    dec ax
    mov [run_end], ax
    call execute_payload
    jmp .done
.usage_run:
    mov si, usage_run
    call print_string
    jmp .done
.range_error:
    mov si, range_error_msg
    call print_string
    jmp .done

.cmd_chdir:
    cmp byte [btfs_valid], 1
    jne .btfs_error
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    mov di, path_buffer
    call read_token
    test cx, cx
    jz .usage_chdir
    call require_no_more_args
    jne .usage_chdir
    call resolve_path
    jc .file_error
    call get_node_record
    cmp byte [di + 4], 1
    jne .not_directory
    mov ax, [resolve_node]
    mov [cwd_node], ax
    mov si, chdir_msg
    call print_string
    jmp .done
.usage_chdir:
    mov si, usage_chdir
    call print_string
    jmp .done
.not_directory:
    mov si, not_directory_msg
    call print_string
    jmp .done

.cmd_ls:
    cmp byte [btfs_valid], 1
    jne .btfs_error
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    call require_no_more_args
    jne .usage_ls
    mov bx, BTFS_TREE
    mov cx, 64
.ls_loop:
    cmp word [bx], 0xFFFF
    je .ls_next
    mov ax, [bx + 2]
    cmp ax, [cwd_node]
    jne .ls_next
    push bx
    push cx
    mov si, bx
    add si, 6
    mov cl, [bx + 5]
    xor ch, ch
    mov di, name_buffer
    rep movsb
    mov byte [di], 0
    mov si, name_buffer
    call print_string
    mov si, newline
    call print_string
    pop cx
    pop bx
.ls_next:
    add bx, 64
    loop .ls_loop
    jmp .done
.usage_ls:
    mov si, usage_ls
    call print_string
    jmp .done

.cmd_mem:
    mov cx, MEMORY_SIZE
    xor ax, ax
    mov di, MEMORY_BASE
.mem_count:
    cmp byte [di], 0
    je .inc_zero
    jmp .next_byte
.inc_zero:
    inc ax
.next_byte:
    inc di
    dec cx
    jnz .mem_count
    mov dx, ax
    mov si, zero_count_msg
    call print_string
    mov ax, dx
    call write_dec
    mov si, newline
    call print_string
    jmp .done
.cmd_status:
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    call require_no_more_args
    jne .usage_status
    mov si, last_status_msg
    call print_string
    xor dx, dx
    mov dl, [last_exit_code]
    call write_dec
    mov si, newline
    call print_string
    jmp .done
.usage_status:
    mov si, usage_status
    call print_string
    jmp .done

.cmd_pwd:
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    call require_no_more_args
    jne .usage_pwd
    call print_working_directory
    jmp .done
.usage_pwd:
    mov si, usage_pwd
    call print_string
    jmp .done

.cmd_echo:
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    call print_string
    jmp .done

.cmd_clear:
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    call require_no_more_args
    jne .usage_clear
    mov ah, 0x06
    mov al, 0
    mov bh, 0x07
    xor cx, cx
    mov dx, 0x184F
    int 0x10
    mov ah, 0x02
    xor bx, bx
    xor dx, dx
    int 0x10
    jmp .done
.usage_clear:
    mov si, usage_clear
    call print_string
    jmp .done

.cmd_touch:
    cmp byte [btfs_valid], 1
    jne .btfs_error
    call parse_one_path
    jc .usage_touch
    mov word [write_size], 0
    mov word [write_source], 0
    call write_file_from_memory
    jc .file_error
    mov si, touched_msg
    call print_string
    jmp .done
.usage_touch:
    mov si, usage_touch
    call print_string
    jmp .done

.cmd_cat:
    cmp byte [btfs_valid], 1
    jne .btfs_error
    call parse_one_path
    jc .usage_cat
    call resolve_path
    jc .file_error
    call get_node_record
    cmp byte [di + 4], 2
    jne .file_error
    call load_file_to_memory
    jc .file_error
    mov ax, [file_start]
    mov [cat_cursor], ax
    mov ax, [file_size]
    mov [cat_remaining], ax
.cat_loop:
    cmp word [cat_remaining], 0
    je .cat_done
    mov bx, MEMORY_BASE
    add bx, [cat_cursor]
    mov al, [bx]
    cmp al, 0x20
    jb .cat_control
    cmp al, 0x7E
    jbe .cat_emit
    jmp .cat_dot
.cat_control:
    cmp al, 0x09
    je .cat_emit
    cmp al, 0x0A
    je .cat_emit
    cmp al, 0x0D
    je .cat_emit
.cat_dot:
    mov al, '.'
.cat_emit:
    call output_ascii_character
    inc word [cat_cursor]
    dec word [cat_remaining]
    jmp .cat_loop
.cat_done:
    mov al, 0x0A
    call output_ascii_character
    jmp .done
.usage_cat:
    mov si, usage_cat
    call print_string
    jmp .done

.cmd_help:
    mov si, help_text
    call print_string

.done:
    pop si
    ret

strcmp_ci:
    push si
    push di
.loop:
    mov al, [si]
    mov bl, [di]
    cmp al, 0
    je .done_same
    cmp bl, 0
    je .done_diff
    cmp al, 'A'
    jb .check_b
    cmp al, 'Z'
    ja .check_b
    add al, 32
.check_b:
    cmp bl, 'A'
    jb .cmp_char
    cmp bl, 'Z'
    ja .cmp_char
    add bl, 32
.cmp_char:
    cmp al, bl
    jne .done_diff
    inc si
    inc di
    jmp .loop
.done_same:
    xor ax, ax
    jmp .finish
.done_diff:
    mov ax, 1
.finish:
    pop di
    pop si
    ret

require_no_more_args:
    call skip_spaces
    cmp byte [si], 0
    ret

validate_range:
    cmp bp, dx
    ja .invalid
    cmp dx, MEMORY_SIZE
    jae .invalid
    clc
    ret
.invalid:
    stc
    ret

initialize_btfs:
    mov byte [btfs_valid], 0
    mov ax, BTFS_START_LBA
    mov bx, BTFS_BUFFER
    mov cx, 9
    call read_disk_sectors
    jc .invalid
    cmp byte [BTFS_BUFFER], 'B'
    jne .invalid
    cmp byte [BTFS_BUFFER + 1], 'T'
    jne .invalid
    cmp byte [BTFS_BUFFER + 2], 'F'
    jne .invalid
    cmp byte [BTFS_BUFFER + 3], 'S'
    jne .invalid
    cmp word [BTFS_BUFFER + 4], 1
    jne .invalid
    cmp word [BTFS_BUFFER + 8], 256
    jne .invalid
    cmp word [BTFS_BUFFER + 10], 64
    jne .invalid
    cmp word [BTFS_BUFFER + 12], 256
    jne .invalid
    cmp word [BTFS_BUFFER + 14], 64
    jne .invalid
    mov byte [btfs_valid], 1
    call build_data_bitmap
    jc .invalid
    ret
.invalid:
    mov byte [btfs_valid], 0
    mov si, btfs_error_msg
    call print_string
    ret

read_disk_sectors:
    mov byte [disk_operation], 2
    jmp disk_transfer

write_disk_sectors:
    mov byte [disk_operation], 3

disk_transfer:
    ; AX=LBA, BX=buffer offset, CX=sector count.
    push ax
    push bx
    push cx
    push dx
    push es
    mov [disk_lba], ax
    mov [disk_buffer], bx
    mov [disk_count], cx
.sector_loop:
    cmp word [disk_count], 0
    je .success
    mov ax, [disk_lba]
    xor dx, dx
    mov bx, 18
    div bx
    inc dl
    mov [disk_sector], dl
    xor dx, dx
    mov bx, 2
    div bx
    mov ch, al
    mov dh, dl
    mov cl, [disk_sector]
    mov dl, 0
    mov bx, [disk_buffer]
    xor ax, ax
    mov es, ax
    mov ah, [disk_operation]
    mov al, 1
    int 0x13
    jc .failed
.sector_ok:
    inc word [disk_lba]
    add word [disk_buffer], 512
    dec word [disk_count]
    jmp .sector_loop
.success:
    clc
    jmp .done
.failed:
    stc
.done:
    pop es
    pop dx
    pop cx
    pop bx
    pop ax
    ret

read_block_link:
    mov ax, [current_block]
    cmp ax, 256
    jae .failed
    mov dx, ax
    and dx, 1
    shl dx, 8
    add dx, 32
    mov [block_offset], dx
    shr ax, 1
    add ax, BTFS_START_LBA + 8
    mov bx, BTFS_DATA_BUFFER
    mov cx, 1
    call read_disk_sectors
    jc .failed
    mov bx, [block_offset]
    mov ax, [BTFS_DATA_BUFFER + bx]
    clc
    ret
.failed:
    stc
    ret

build_data_bitmap:
    push ax
    push bx
    push cx
    push di
    mov di, data_bitmap
    xor ax, ax
    mov cx, 32
    rep stosb
    mov word [bitmap_node], 0
.node_loop:
    cmp word [bitmap_node], 64
    jae .done
    mov bx, [bitmap_node]
    shl bx, 6
    add bx, BTFS_TREE
    cmp word [bx], 0xFFFF
    je .next_node
    cmp byte [bx + 4], 2
    jne .next_node
    mov ax, [bx + 46]
    mov [current_block], ax
    mov ax, [bx + 48]
    mov [blocks_remaining], ax
.chain_loop:
    cmp word [blocks_remaining], 0
    je .next_node
    mov ax, [current_block]
    cmp ax, 256
    jae .failed
    bts word [data_bitmap], ax
    call read_block_link
    jc .failed
    mov [current_block], ax
    dec word [blocks_remaining]
    jmp .chain_loop
.next_node:
    inc word [bitmap_node]
    jmp .node_loop
.done:
    clc
    jmp .return
.failed:
    stc
.return:
    pop di
    pop cx
    pop bx
    pop ax
    ret

allocate_data_block:
    xor ax, ax
.scan:
    cmp ax, 256
    jae .full
    bt word [data_bitmap], ax
    jc .next
    bts word [data_bitmap], ax
    mov [allocated_block], ax
    clc
    ret
.next:
    inc ax
    jmp .scan
.full:
    stc
    ret

free_file_chain:
    call get_node_record
    mov ax, [di + 46]
    mov [current_block], ax
    mov ax, [di + 48]
    mov [blocks_remaining], ax
.free_loop:
    cmp word [blocks_remaining], 0
    je .done
    call read_block_link
    jc .failed
    mov [next_block], ax
    mov ax, [current_block]
    btr word [data_bitmap], ax
    mov ax, [next_block]
    mov [current_block], ax
    dec word [blocks_remaining]
    jmp .free_loop
.done:
    clc
    ret
.failed:
    stc
    ret

write_tree:
    push ax
    push bx
    push cx
    push si
    push di
    mov ax, BTFS_START_LBA
    mov bx, BTFS_BUFFER
    mov cx, 8
    call write_disk_sectors
    jc .failed
    mov ax, BTFS_START_LBA + 8
    mov bx, BTFS_DATA_BUFFER
    mov cx, 1
    call read_disk_sectors
    jc .failed
    mov si, BTFS_BUFFER + 4096
    mov di, BTFS_DATA_BUFFER
    mov cx, 32
    rep movsb
    mov ax, BTFS_START_LBA + 8
    mov bx, BTFS_DATA_BUFFER
    mov cx, 1
    call write_disk_sectors
    jc .failed
    clc
    jmp .return
.failed:
    stc
.return:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

read_token:
    push di
    xor cx, cx
.loop:
    cmp byte [si], 0
    je .finish
    cmp byte [si], ' '
    je .finish
    cmp byte [si], 9
    je .finish
    cmp byte [si], 13
    je .finish
    cmp byte [si], 10
    je .finish
    mov al, [si]
    mov [di], al
    inc si
    inc di
    inc cx
    jmp .loop
.finish:
    mov byte [di], 0
    pop di
    ret

parse_one_path:
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    mov di, path_buffer
    call read_token
    test cx, cx
    jz .invalid
    call require_no_more_args
    jne .invalid
    clc
    ret
.invalid:
    stc
    ret

parse_two_paths:
    mov si, input_buffer
    call skip_spaces
    call skip_command_token
    mov di, path_buffer
    call read_token
    test cx, cx
    jz .invalid
    call skip_spaces
    mov di, path2_buffer
    call read_token
    test cx, cx
    jz .invalid
    call require_no_more_args
    jne .invalid
    clc
    ret
.invalid:
    stc
    ret

copy_zstring:
.loop:
    lodsb
    stosb
    test al, al
    jnz .loop
    ret

resolve_path:
    push si
    mov si, path_buffer
    mov ax, [cwd_node]
    cmp byte [si], '/'
    jne .set_start
    xor ax, ax
.set_start:
    mov [resolve_node], ax
.next_component:
    cmp byte [si], '/'
    jne .copy_component
    inc si
    jmp .next_component
.copy_component:
    mov di, component_buffer
    xor cx, cx
.component_loop:
    mov al, [si]
    cmp al, 0
    je .component_done
    cmp al, '/'
    je .component_done
    cmp cx, 40
    jae .failed
    mov [di], al
    inc di
    inc si
    inc cx
    jmp .component_loop
.component_done:
    mov byte [di], 0
    mov [component_length], cl
    test cl, cl
    jz .resolved
    cmp cl, 1
    jne .check_parent
    cmp byte [component_buffer], '.'
    je .next_component
.check_parent:
    cmp cl, 2
    jne .find_component
    cmp byte [component_buffer], '.'
    jne .find_component
    cmp byte [component_buffer + 1], '.'
    jne .find_component
    call get_node_record
    mov ax, [di + 2]
    cmp ax, 0xFFFF
    je .next_component
    mov [resolve_node], ax
    jmp .next_component
.find_component:
    call find_child
    jc .failed
    jmp .next_component
.resolved:
    pop si
    clc
    ret
.failed:
    pop si
    stc
    ret

get_node_record:
    mov di, BTFS_TREE
    mov ax, [resolve_node]
    shl ax, 6
    add di, ax
    ret

find_child:
    call get_node_record
    cmp byte [di + 4], 1
    jne .not_found
    push si
    mov bx, BTFS_TREE
    mov cx, 64
.scan:
    cmp word [bx], 0xFFFF
    je .next
    mov ax, [resolve_node]
    cmp [bx + 2], ax
    jne .next
    mov al, [bx + 5]
    cmp al, [component_length]
    jne .next
    push bx
    push cx
    push si
    push di
    mov si, component_buffer
    mov di, bx
    add di, 6
    mov cl, [component_length]
    xor ch, ch
    repe cmpsb
    pop di
    pop si
    pop cx
    pop bx
    jne .next
    mov ax, [bx]
    mov [resolve_node], ax
    pop si
    clc
    ret
.next:
    add bx, 64
    loop .scan
    pop si
.not_found:
    stc
    ret

write_file_from_hex:
    mov cx, [hex_length]
    test cx, cx
    jz .invalid
    test cl, 1
    jnz .invalid
    shr cx, 1
    cmp cx, 254
    ja .invalid
    mov [write_size], cx
    mov si, hex_arg
    mov di, file_payload
.decode_loop:
    cmp word [write_size], 0
    je .decoded
    call parse_hex_nibble
    jc .invalid
    shl al, 4
    mov ah, al
    call parse_hex_nibble
    jc .invalid
    or ah, al
    mov [di], ah
    inc di
    dec word [write_size]
    jmp .decode_loop
.decoded:
    mov ax, [hex_length]
    shr ax, 1
    mov [write_size], ax
    mov word [write_source], file_payload
    call write_file_from_memory
    ret
.invalid:
    stc
    ret

write_file_from_memory:
    cmp word [write_size], 65024
    ja .failed
    call resolve_parent
    jc .failed
    mov ax, [resolve_node]
    mov [file_parent_id], ax
    call find_child
    jc .new_node
    call get_node_record
    cmp byte [di + 4], 2
    jne .failed
    mov ax, [resolve_node]
    mov [file_node_id], ax
    call free_file_chain
    jc .failed
    jmp .allocate_blocks
.new_node:
    call allocate_node_id
    jc .failed
    mov [file_node_id], ax
.allocate_blocks:
    mov ax, [write_size]
    test ax, ax
    jz .zero_blocks
    add ax, 253
    xor dx, dx
    mov bx, 254
    div bx
    jmp .save_block_count
.zero_blocks:
    xor ax, ax
.save_block_count:
    mov [write_blocks], ax
    mov word [write_index], 0
.allocate_loop:
    mov ax, [write_index]
    cmp ax, [write_blocks]
    jae .write_begin
    call allocate_data_block
    jc .failed
    mov bx, [write_index]
    shl bx, 1
    mov [block_list + bx], ax
    inc word [write_index]
    jmp .allocate_loop
.write_begin:
    mov word [write_index], 0
    mov ax, [write_size]
    mov [write_remaining], ax
    mov ax, [write_source]
    mov [write_source_cursor], ax
.write_loop:
    mov ax, [write_index]
    cmp ax, [write_blocks]
    jae .update_record
    mov bx, ax
    shl bx, 1
    mov ax, [block_list + bx]
    mov [current_block], ax
    mov dx, ax
    and dx, 1
    shl dx, 8
    add dx, 32
    mov [block_offset], dx
    shr ax, 1
    add ax, BTFS_START_LBA + 8
    mov [write_lba], ax
    mov bx, BTFS_DATA_BUFFER
    mov cx, 1
    cmp word [block_offset], 288
    jne .read_block
    mov cx, 2
.read_block:
    mov ax, [write_lba]
    call read_disk_sectors
    jc .failed
    mov ax, [write_index]
    inc ax
    cmp ax, [write_blocks]
    jae .last_data_block
    shl ax, 1
    mov bx, ax
    mov bx, [block_list + bx]
    jmp .store_next_block
.last_data_block:
    mov bx, 0xFFFF
.store_next_block:
    mov di, [block_offset]
    mov [BTFS_DATA_BUFFER + di], bx
    mov ax, [write_remaining]
    cmp ax, 254
    jbe .count_ready
    mov ax, 254
.count_ready:
    mov [copy_count], ax
    mov si, [write_source_cursor]
    mov di, BTFS_DATA_BUFFER
    add di, [block_offset]
    add di, 2
    mov cx, [copy_count]
    rep movsb
    mov [write_source_cursor], si
    mov ax, [write_remaining]
    sub ax, [copy_count]
    mov [write_remaining], ax
    mov ax, [write_lba]
    mov bx, BTFS_DATA_BUFFER
    mov cx, 1
    cmp word [block_offset], 288
    jne .write_block
    mov cx, 2
.write_block:
    call write_disk_sectors
    jc .failed
    inc word [write_index]
    jmp .write_loop
.update_record:
    mov ax, [file_node_id]
    mov [resolve_node], ax
    call get_node_record
    mov ax, [file_node_id]
    mov [di], ax
    mov ax, [file_parent_id]
    mov [di + 2], ax
    mov byte [di + 4], 2
    mov al, [component_length]
    mov [di + 5], al
    push di
    add di, 6
    mov cx, 40
    xor al, al
    rep stosb
    pop di
    push di
    add di, 6
    mov si, name_buffer
    mov cl, [component_length]
    xor ch, ch
    rep movsb
    pop di
    mov ax, [write_blocks]
    mov [di + 48], ax
    mov ax, [write_size]
    mov [di + 50], ax
    mov word [di + 52], 0
    cmp word [write_blocks], 0
    je .empty_file
    mov ax, [block_list]
    mov [di + 46], ax
    jmp .flush_record
.empty_file:
    mov word [di + 46], 0xFFFF
.flush_record:
    call write_tree
    ret
.failed:
    stc
    ret

resolve_parent:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov word [last_slash], 0
    mov si, path_buffer
.scan_path:
    mov al, [si]
    test al, al
    jz .path_end
    cmp al, '/'
    jne .path_next
    mov [last_slash], si
.path_next:
    inc si
    jmp .scan_path
.path_end:
    mov si, path_buffer
    mov di, [last_slash]
    test di, di
    jz .copy_name
    lea si, [di + 1]
.copy_name:
    mov di, name_buffer
    xor cx, cx
.name_loop:
    mov al, [si]
    test al, al
    jz .name_done
    cmp cx, 40
    jae .invalid
    mov [di], al
    inc si
    inc di
    inc cx
    jmp .name_loop
.name_done:
    test cx, cx
    jz .invalid
    mov byte [di], 0
    mov [component_length], cl
    mov [leaf_length], cl
    mov si, name_buffer
    mov di, component_buffer
    rep movsb
    mov byte [di], 0
    mov di, [last_slash]
    test di, di
    jz .use_cwd
    cmp di, path_buffer
    jne .terminate_parent
    mov byte [path_buffer + 1], 0
    jmp .resolve_parent_path
.terminate_parent:
    mov byte [di], 0
.resolve_parent_path:
    mov si, path_buffer
    call resolve_path
    jc .invalid
    jmp .check_directory
.use_cwd:
    mov ax, [cwd_node]
    mov [resolve_node], ax
.check_directory:
    call get_node_record
    cmp byte [di + 4], 1
    jne .invalid
    mov al, [leaf_length]
    mov [component_length], al
    mov si, name_buffer
    mov di, component_buffer
    mov cl, [leaf_length]
    xor ch, ch
    rep movsb
    mov byte [di], 0
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret
.invalid:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret

allocate_node_id:
    mov bx, BTFS_TREE
    xor ax, ax
    mov cx, 64
.scan:
    cmp word [bx], 0xFFFF
    je .found
    inc ax
    add bx, 64
    loop .scan
    stc
    ret
.found:
    clc
    ret

create_directory_from_path:
    call resolve_parent
    jc .failed
    mov [destination_parent], ax
    mov ax, [resolve_node]
    mov [destination_parent], ax
    call find_child
    jnc .failed
    call allocate_node_id
    jc .failed
    mov [resolve_node], ax
    call get_node_record
    mov ax, [resolve_node]
    mov [di], ax
    mov ax, [destination_parent]
    mov [di + 2], ax
    mov byte [di + 4], 1
    mov al, [component_length]
    mov [di + 5], al
    push di
    add di, 6
    mov cx, 40
    xor al, al
    rep stosb
    pop di
    push di
    add di, 6
    mov si, name_buffer
    mov cl, [component_length]
    xor ch, ch
    rep movsb
    pop di
    mov word [di + 46], 0xFFFF
    mov word [di + 48], 0
    mov dword [di + 50], 0
    call write_tree
    ret
.failed:
    stc
    ret

directory_is_empty:
    mov bx, BTFS_TREE
    mov cx, 64
.scan:
    cmp word [bx], 0xFFFF
    je .next
    mov ax, [bx + 2]
    cmp ax, [source_node]
    je .not_empty
.next:
    add bx, 64
    loop .scan
    clc
    ret
.not_empty:
    stc
    ret

run_bin_command:
    mov ax, [next_free_addr]
    mov [bin_saved_free], ax
    mov byte [path_buffer], '/'
    mov byte [path_buffer + 1], 'b'
    mov byte [path_buffer + 2], 'i'
    mov byte [path_buffer + 3], 'n'
    mov byte [path_buffer + 4], '/'
    mov si, command_name
    mov di, path_buffer + 5
    call copy_zstring
    call resolve_path
    jnc .found
    mov si, command_name
    mov di, path_buffer + 5
    call copy_zstring
    dec di
    mov byte [di], '.'
    mov byte [di + 1], 'h'
    mov byte [di + 2], 'e'
    mov byte [di + 3], 'x'
    mov byte [di + 4], 0
    call resolve_path
    jc .not_found
.found:
    call load_file_to_memory
    jc .not_found
    cmp word [file_size], 0
    je .not_found
    mov ax, [file_start]
    mov [run_start], ax
    add ax, [file_size]
    dec ax
    mov [run_end], ax
    call execute_payload
    mov ax, [bin_saved_free]
    mov [next_free_addr], ax
    clc
    ret
.not_found:
    stc
    ret

print_counted:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
.loop:
    test cx, cx
    jz .done
    lodsb
    call output_ascii_character
    dec cx
    jmp .loop
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_working_directory:
    mov word [pwd_count], 0
    mov ax, [cwd_node]
.collect:
    test ax, ax
    jz .print_path
    mov bx, [pwd_count]
    shl bx, 1
    mov [pwd_nodes + bx], ax
    inc word [pwd_count]
    mov [resolve_node], ax
    call get_node_record
    mov ax, [di + 2]
    jmp .collect
.print_path:
    mov al, '/'
    call output_ascii_character
    mov ax, [pwd_count]
    mov [pwd_index], ax
.component:
    cmp word [pwd_index], 0
    je .done
    dec word [pwd_index]
    mov bx, [pwd_index]
    shl bx, 1
    mov ax, [pwd_nodes + bx]
    mov [resolve_node], ax
    call get_node_record
    mov si, di
    add si, 6
    xor cx, cx
    mov cl, [di + 5]
    call print_counted
    cmp word [pwd_index], 0
    je .component
    mov al, '/'
    call output_ascii_character
    jmp .component
.done:
    mov al, 13
    call output_ascii_character
    mov al, 10
    call output_ascii_character
    ret

load_file_to_memory:
    push si
    call get_node_record
    cmp byte [di + 4], 2
    jne .failed
    cmp word [di + 52], 0
    jne .failed
    mov ax, [di + 50]
    mov [file_size], ax
    mov ax, [next_free_addr]
    mov [file_start], ax
    mov [load_cursor], ax
    add ax, [file_size]
    jc .failed
    cmp ax, MEMORY_SIZE
    ja .failed
    mov ax, [file_size]
    mov [file_remaining], ax
    mov ax, [di + 46]
    mov [current_block], ax
    mov ax, [di + 48]
    mov [blocks_remaining], ax
.block_loop:
    cmp word [file_remaining], 0
    je .loaded
    cmp word [blocks_remaining], 0
    je .failed
    mov ax, [current_block]
    cmp ax, 256
    jae .failed
    mov dx, ax
    and dx, 1
    shl dx, 8
    add dx, 32
    mov [block_offset], dx
    shr ax, 1
    add ax, BTFS_START_LBA + 8
    mov bx, BTFS_DATA_BUFFER
    mov cx, 1
    call read_disk_sectors
    jc .failed
    cmp word [block_offset], 288
    jne .sector_ready
    mov ax, [disk_lba]
    inc ax
    mov bx, BTFS_DATA_BUFFER + 512
    mov cx, 1
    call read_disk_sectors
    jc .failed
.sector_ready:
    mov bx, [block_offset]
    mov ax, [BTFS_DATA_BUFFER + bx]
    mov [next_block], ax
    mov si, BTFS_DATA_BUFFER
    add si, [block_offset]
    add si, 2
    mov di, MEMORY_BASE
    add di, [load_cursor]
    mov ax, [file_remaining]
    cmp ax, 254
    jbe .copy_count_ready
    mov ax, 254
.copy_count_ready:
    mov [copy_count], ax
    mov cx, ax
    rep movsb
    mov ax, [load_cursor]
    add ax, [copy_count]
    mov [load_cursor], ax
    mov ax, [file_remaining]
    sub ax, [copy_count]
    mov [file_remaining], ax
    mov ax, [next_block]
    mov [current_block], ax
    dec word [blocks_remaining]
    jmp .block_loop
.loaded:
    mov ax, [load_cursor]
    mov [next_free_addr], ax
    pop si
    clc
    ret
.failed:
    pop si
    stc
    ret

execute_payload:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es

    ; Use a temporary RET after the selected range for code that falls through.
    mov bx, MEMORY_BASE
    add bx, [run_end]
    inc bx
    mov al, [bx]
    mov [run_saved_byte], al
    mov byte [bx], 0xC3

    mov bx, MEMORY_BASE
    add bx, [run_start]
    call bx
    cld
    mov [cs:run_result], ax
    mov [cs:last_exit_code], al

    pop es
    pop ds
    mov bx, MEMORY_BASE
    add bx, [run_end]
    inc bx
    mov al, [run_saved_byte]
    mov [bx], al

    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

skip_command_token:
    call skip_spaces
    ; advance past current token
    cmp byte [si], 0
    je .done
.token_loop:
    cmp byte [si], 0
    je .done
    cmp byte [si], ' '
    je .done
    cmp byte [si], 9
    je .done
    cmp byte [si], 13
    je .done
    cmp byte [si], 10
    je .done
    inc si
    jmp .token_loop
.done:
    call skip_spaces
    ret

parse_uint_arg:
    push bx
    push cx
    push dx
    push di

    call skip_spaces
    xor ax, ax
    mov bx, 10
    xor cx, cx

    cmp byte [si], 0
    je .invalid
    cmp byte [si], '0'
    jne .scan
    inc si
    cmp byte [si], 'x'
    je .hex_mode
    cmp byte [si], 'X'
    je .hex_mode
    dec si
    jmp .scan

.hex_mode:
    inc si
    mov bx, 16

.scan:
    cmp byte [si], 0
    je .finish
    cmp byte [si], ' '
    je .finish
    cmp byte [si], 9
    je .finish
    cmp byte [si], 13
    je .finish
    cmp byte [si], 10
    je .finish

    mov dl, [si]
    cmp dl, '0'
    jb .invalid
    cmp dl, '9'
    jbe .digit_ok
    cmp dl, 'A'
    jb .invalid
    cmp dl, 'F'
    jbe .hex_digit
    cmp dl, 'a'
    jb .invalid
    cmp dl, 'f'
    ja .invalid
    sub dl, 'a'
    add dl, 10
    jmp .digit_add

.hex_digit:
    sub dl, 'A'
    add dl, 10
    jmp .digit_add

.digit_ok:
    sub dl, '0'

.digit_add:
    xor dh, dh
    cmp dx, bx
    jae .invalid
    mov di, dx
    mul bx
    or dx, dx
    jnz .invalid
    add ax, di
    jc .invalid
    inc cx
    inc si
    jmp .scan

.finish:
    test cx, cx
    jz .invalid
    clc
    jmp .return
.invalid:
    xor ax, ax
    stc
.return:
    pop di
    pop dx
    pop cx
    pop bx
    ret

store_hex_range:
    ; BP = start, DX = end, hex_arg contains one raw-hex token.
    mov cx, [hex_length]
    test cx, cx
    jz .invalid
    test cx, 1
    jnz .invalid
    shr cx, 1
    mov ax, dx
    sub ax, bp
    inc ax
    cmp cx, ax
    ja .invalid
    mov [loaded_count], cx
    push si
    mov si, hex_arg
    mov cx, [hex_length]
.validate_hex:
    call parse_hex_nibble
    jc .invalid_pop
    loop .validate_hex
    pop si
    mov si, hex_arg
    mov di, bp
    mov cx, [loaded_count]
.byte_loop:
    test cx, cx
    jz .success
    call parse_hex_nibble
    jc .invalid
    shl al, 4
    mov ah, al
    call parse_hex_nibble
    jc .invalid
    or ah, al
    mov bx, MEMORY_BASE
    add bx, di
    mov [bx], ah
    inc di
    dec cx
    jmp .byte_loop
.success:
    clc
    ret
.invalid_pop:
    pop si
.invalid:
    stc
    ret

parse_hex_nibble:
    mov al, [si]
    inc si
    cmp al, '0'
    jb .invalid
    cmp al, '9'
    jbe .decimal
    cmp al, 'a'
    jb .upper
    cmp al, 'f'
    ja .invalid
    sub al, 'a' - 10
    clc
    ret
.upper:
    cmp al, 'A'
    jb .invalid
    cmp al, 'F'
    ja .invalid
    sub al, 'A' - 10
    clc
    ret
.decimal:
    sub al, '0'
    clc
    ret
.invalid:
    stc
    ret

dump_range:
    ; bp = start, dx = end
    mov ax, bp
    mov [current_addr], ax
    mov [range_end], dx
.loop:
    mov si, range_header
    call print_string
    mov dx, [current_addr]
    call write_dec
    mov si, colon_space
    call print_string
    mov bx, MEMORY_BASE
    add bx, [current_addr]
    mov dl, [bx]
    mov dh, 0
    call write_dec
    mov si, newline
    call print_string
    mov ax, [current_addr]
    cmp ax, [range_end]
    jae .done
    inc ax
    mov [current_addr], ax
    jmp .loop
.done:
    ret

print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    mov bl, 0x07
    int 0x10
    jmp print_string
.done:
    ret

boot_msg     db "SDOS booted successfully!", 13, 10, 0
prompt_msg   db "SDOS> ", 0
newline      db 13, 10, 0
goodbye_msg  db "Shutting down...", 13, 10, 0
help_text    db "pwd cd ls cat echo clear touch load rm cp mv mkdir rmdir run status help", 13, 10, 0
unknown_msg  db "Unknown command", 13, 10, 0
loaded_msg   db "Loaded ", 0
file_loaded_msg db "Loaded ", 0
file_address_msg db " bytes at address ", 0
file_written_msg db "Wrote ", 0
file_bytes_msg db " bytes to file", 13, 10, 0
removed_msg  db "File removed", 13, 10, 0
copied_msg   db "File copied", 13, 10, 0
moved_msg    db "Node moved", 13, 10, 0
directory_created_msg db "Directory created", 13, 10, 0
directory_removed_msg db "Directory removed", 13, 10, 0
running_msg  db "Executing 16-bit real-mode code...", 13, 10, 0
returned_msg db "Returned AX: ", 0
last_status_msg db "Last program status: ", 0
btfs_error_msg db "BTfs volume unavailable", 13, 10, 0
file_error_msg db "BTfs path or file load error", 13, 10, 0
chdir_msg    db "Directory changed", 13, 10, 0
not_directory_msg db "BTfs node is not a directory", 13, 10, 0
zero_count_msg db "Zero addresses: ", 0
range_header db "Address ", 0
colon_space  db ": ", 0
cmd_dir      db "dir", 0
cmd_load     db "load", 0
cmd_run      db "run", 0
cmd_chdir    db "chdir", 0
cmd_ls       db "ls", 0
cmd_rmf      db "rmf", 0
cmd_cpy      db "cpy", 0
cmd_move     db "move", 0
cmd_makedir  db "makedir", 0
cmd_remdir   db "remdir", 0
cmd_mem      db "mem", 0
cmd_status   db "status", 0
cmd_pwd      db "pwd", 0
cmd_cd       db "cd", 0
cmd_echo     db "echo", 0
cmd_clear    db "clear", 0
cmd_cat      db "cat", 0
cmd_touch    db "touch", 0
cmd_rm       db "rm", 0
cmd_cp       db "cp", 0
cmd_mv       db "mv", 0
cmd_mkdir    db "mkdir", 0
cmd_rmdir    db "rmdir", 0
cmd_help     db "help", 0
cmd_help_long db "--help", 0
cmd_help_short db "-h", 0
command_name times 16 db 0
hex_arg      times 64 db 0
temp_num_buf times 16 db 0
input_buffer times 64 db 0
path_buffer  times 64 db 0
path2_buffer times 64 db 0
component_buffer times 41 db 0
name_buffer  times 42 db 0
file_payload times 254 db 0
block_list   times 256 dw 0
hex_length   dw 0
path_length  dw 0
loaded_count dw 0
range_end    dw 0
current_addr dw 0
run_end      dw 0
run_start    dw 0
run_result   dw 0
run_saved_byte db 0
last_exit_code db 0
input_char   db 0
kernel_command_id db 0
kernel_call_mode db 0
bin_saved_free dw 0
btfs_valid   db 0
disk_sector  db 0
disk_count   dw 0
disk_operation db 2
last_slash   dw 0
leaf_length  db 0
bitmap_node  dw 0
allocated_block dw 0
source_node  dw 0
destination_parent dw 0
write_source dw 0
write_source_cursor dw 0
write_size   dw 0
write_blocks dw 0
write_index  dw 0
write_remaining dw 0
file_node_id dw 0
file_parent_id dw 0
write_lba    dw 0
data_bitmap  times 32 db 0
cat_cursor   dw 0
cat_remaining dw 0
pwd_count    dw 0
pwd_index    dw 0
pwd_nodes    times 64 dw 0
disk_lba     dw 0
disk_buffer  dw 0
cwd_node     dw 0
resolve_node dw 0
component_length db 0
next_free_addr dw 0
expected_file_index dw 0
file_size    dw 0
file_start   dw 0
load_cursor  dw 0
file_remaining dw 0
current_block dw 0
blocks_remaining dw 0
block_offset dw 0
next_block   dw 0
copy_count   dw 0
usage_dir    db "Usage: dir [start] [end]", 13, 10, 0
usage_load   db "Usage: load [filename] or load [raw_hex] [start] [end]", 13, 10, 0
usage_run    db "Usage: run [start] [end] or run -f1 [file] -f2 [file]...", 13, 10, 0
usage_chdir  db "Usage: chdir [path]", 13, 10, 0
usage_ls     db "Usage: ls", 13, 10, 0
usage_status db "Usage: status", 13, 10, 0
usage_pwd    db "Usage: pwd", 13, 10, 0
usage_clear  db "Usage: clear", 13, 10, 0
usage_touch  db "Usage: touch [path]", 13, 10, 0
usage_cat    db "Usage: cat [file]", 13, 10, 0
touched_msg  db "File created", 13, 10, 0
usage_rmf    db "Usage: RMF [file]", 13, 10, 0
usage_cpy    db "Usage: cpy [source] [destination]", 13, 10, 0
usage_move   db "Usage: move [source] [destination]", 13, 10, 0
usage_makedir db "Usage: makedir [path]", 13, 10, 0
usage_remdir db "Usage: remdir [path]", 13, 10, 0
range_error_msg db "Error: invalid memory range (0-4095; end >= start)", 13, 10, 0
bad_hex_msg  db "Error: invalid hex or payload exceeds range", 13, 10, 0
bytes_msg    db " bytes to memory", 13, 10, 0

TIMES 8192 - ($ - $$) db 0
