; Test helper only: run PUTR with DOS handles 1 and 2 sharing PUTR.OUT.
; DOSBox's shell redirects stdout but leaves DOS stderr on the console.
bits 16
org 100h
start:
    mov sp, stack_top
    mov bx, (stack_top - $$ + 100h + 15) / 16
    mov ah, 4Ah
    int 21h
    jc failed
    mov dx, output_name
    xor cx, cx
    mov ah, 3Ch
    int 21h
    jc failed
    mov bx, ax
    mov cx, 1
    mov ah, 46h
    int 21h
    jc failed
    mov cx, 2
    mov ah, 46h
    int 21h
    jc failed
    mov ah, 3Eh
    int 21h
    mov ax, cs
    mov [parameters + 4], ax
    mov [parameters + 8], ax
    mov [parameters + 12], ax
    mov dx, program_name
    mov bx, parameters
    mov ax, 4B00h
    int 21h
    jc failed
    mov ah, 4Dh
    int 21h
    mov ah, 4Ch
    int 21h
failed:
    mov ax, 4CFFh
    int 21h
program_name db 'PUTR.COM', 0
output_name db 'PUTR.OUT', 0
command_tail db 0, 13
parameters dw 0, command_tail, 0, 5Ch, 0, 6Ch, 0
times 512 db 0
stack_top:
