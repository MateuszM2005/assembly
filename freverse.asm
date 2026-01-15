global _start

SYS_EXIT equ 60
SYS_STAT equ 4
SYS_OPEN equ 2
SYS_MMAP equ 9
SYS_CLOSE equ 3
SYS_MUNMAP equ 11
SYS_MSYNC equ 26


; Reverse the file named in the first argument.

_start:


; Get the filesize with SYS_STAT, utilizing redzone.
; Stat struct size: 140 bytes; redzone 128 bytes; [rsp; rsp + 16) not needed.
; After check if size > 2 => else: exit programme.

.get_length:
        cmp qword [rsp], 2	; check for valid arguments
        jne .error1

        mov eax, SYS_STAT       ; SYS CODE: 32 bit
        mov rdi, [rsp + 16]     ; FILENAME pointer: 64 bit
        lea rsi, [rsp - 128]    ; ADRESS to put struct: 64 bit
        syscall
        test eax, eax           ; error check
        js .error1

        mov eax, dword [rsp - 104]
        and ax, 0xF000
        cmp ax, 0x8000
        jne .error1		; check for file type

        mov r15, [rsp-80]       ; load the file length: 64 bit
        cmp r15, 1
        jle .exit		; ignore case where nothing needs to be done


; Get file descriptor for future use.

.open_file:
        mov eax, SYS_OPEN       ; SYS CODE: 32 bit
                                ; FILENAME pointer: 64 bit, already set
        mov esi, 2              ; FLAGS: 32 bit
                                ; MODE is ignored
        syscall
        test eax, eax           ; error check
        js .error1

        mov esp, eax            ; move the FD: 32 bit


.mmap:
        mov eax, SYS_MMAP       ; SYS CODE: 32 bit
        xor edi, edi            ; ADRRESS: set to nullptr
        mov rsi, r15            ; LENGTH of mapped area: 64 bit
        mov edx, 3              ; PROT read + write: 32 bit
        mov r10, 0x8001         ; FLAGS - map shared, preload pages
        mov r8, rsp             ; FD
        mov r9, 0               ; OFFSET = 0
        syscall

        test rax, rax           ; error check
        js .error0

        mov rdi, rax            ; move the adress: 64 bit
	
	; AFTER THE FIRST PART:
        ; ADRESS: rdi, rax
        ; LENGTH: r15, rsi
        ; FD: rsp (no using stack)


; Reversing the mapped file:
; Use rbx, rcx as data stroage to perform bswap.
; Use rax, rdx as pointers to "opposite" parts of file.
; Iterate with bswap on each pair for performance.
; Modifies only rax, rbx, rcx, rdx.

.reverse_big:
        lea rdx, [rax + r15 - 8]; Load the end of the file into rdx
.big_loop:
        mov rbx, rdx;           ; Compare for end of loop case
        sub rbx, rax;           ; This only occurs rax + 8 < rdx
        sub rbx, 8
        js .reverse_small       ; Jumps to fill the middle

        prefetcht0 [rax + 64]   ; Some optimization
        prefetcht0 [rdx - 64]	; Prefetching might help with pipelining
				; although it is still suboptimal

        mov rbx, qword [rax]    ; Swap memory adresses + bswap
        mov rcx, qword [rdx]
        bswap rbx
        bswap rcx
        mov qword [rdx], rbx
        mov qword [rax], rcx

        add rax, 8              ; Change values
        sub rdx, 8
        jmp .big_loop


; Reverse the middle of the file of length <= 15 bytes.
; This iterates byte by byte (as optimization is not needed for such small data).
; Modifies only rax, rbx, rcx, rdx.

.reverse_small:
        add rdx, 8              ; Get end adress into rdx and start into rax
        dec rax                 ; Both moved by one bit for space optimization

.small_loop:
        inc rax                 ; Loop end condition: rax >= rdx
        dec rdx
        cmp rax, rdx
        jge .unmap

        mov bl, byte [rax]      ; Swap bytes
        mov cl, byte [rdx]
        mov byte [rdx], bl
        mov byte [rax], cl

        jmp .small_loop


; Unmap -> Close File -> End
; Error logic: 
; Error 0: when file needs to be closed.
; Error 1: when file is not open.

.unmap:
        mov eax, SYS_MUNMAP     ; SYS CODE: 32 bit
                                ; ADRESS: 64 bit, already set
                                ; LENGTH: 64 bit, already set
        syscall

        mov ebx, 0
        test eax, eax           ; error check
        jns .closes

.error0:
        mov ebx, 1

.close:
        mov eax, SYS_CLOSE      ; SYS CODE: 32 bit
        mov edi, esp            ; FD: 32 bit
        syscall

        test eax, eax           ; error check
        jns .exit
.error1:
        mov ebx, 1

.exit:
        mov edi, ebx
        mov eax, SYS_EXIT       ; SYS CODE
        syscall
