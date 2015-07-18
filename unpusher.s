bits 16
org 0x100

%define BLACK		(0x00 << 8)
%define DARK_BLUE	(0x01 << 8)
%define DARK_GREEN	(0x02 << 8)
%define DARK_CYAN	(0x03 << 8)
%define DARK_RED	(0x04 << 8)
%define DARK_MAGENTA	(0x05 << 8)
%define DARK_YELLOW	(0x06 << 8)
%define LIGHT_GRAY	(0x07 << 8)
%define DARK_GRAY	(0x08 << 8)
%define LIGHT_BLUE	(0x09 << 8)
%define LIGHT_GREEN	(0x0A << 8)
%define LIGHT_CYAN	(0x0B << 8)
%define LIGHT_RED	(0x0C << 8)
%define LIGHT_MAGENTA	(0x0D << 8)
%define LIGHT_YELLOW	(0x0E << 8)
%define WHITE		(0x0F << 8)

%define BG_BLACK	(0x00 << 12)
%define BG_BLUE		(0x01 << 12)
%define BG_GREEN	(0x02 << 12)
%define BG_CYAN		(0x03 << 12)
%define BG_RED		(0x04 << 12)
%define BG_MAGENTA	(0x05 << 12)
%define BG_YELLOW	(0x06 << 12)
%define BG_GRAY		(0x07 << 12)

%define EMPTY		(BG_BLACK|BLACK)
%define PLAYER_EMPTY	(LIGHT_RED|0x01)
%define PLAYER_TARGET	(BG_GREEN|DARK_RED|0x01)
%define BARREL		(BG_BLACK|LIGHT_YELLOW|0x03)
%define COMPLETED	(BG_GREEN|LIGHT_YELLOW|0x06)
%define TARGET		(BG_GREEN|BLACK|0x2E)
%define WALL		(BG_YELLOW|DARK_RED|0xB1)

%define VK_LEFT		0x4b00
%define VK_RIGHT	0x4d00
%define VK_UP		0x4800
%define VK_DOWN		0x5000
%define VK_SPACE	0x3920
%define VK_ESC		0x011b

section .text
_start:

;; vga_initialize() -- sets VGA to 40x25 16-color text mode
vga_initialize:
	xor ax, ax
	int 0x10
	mov ax, 0xB800
	mov es, ax

;; reset() -- fills map and reset player position
reset:
	mov al, 0
	mov byte [px], 0
	mov byte [py], 26
	mov word [slots], 0xFFFF
	mov cx, 40*25
	mov di, map
	push es
	push ds
	pop es
	rep stosb
	pop es
	call draw

;; select_level() -- interface for selecting the level
;; Outputs:
;; si : pointer to compressed level data
select_level:
	mov si, query
	mov di, 12*80+10*2
	mov ax, BG_BLUE|LIGHT_YELLOW
.write:	lodsb
	stosw
	cmp al, 0
	jnz .write
	mov si, di		; save end-of-string location
	mov bx,	[mazeid]	; load selection
	mov cx, 10		; constant
.num:	mov di, si
	mov ax, bx
	xor dx, dx
	div cx
	add ax, BG_BLUE|LIGHT_YELLOW|'0'
	cmp al, '0'
	jne .non_blank
	mov al, 0
.non_blank:
	stosw
	add dx, BG_BLUE|LIGHT_YELLOW|'0'
	mov ax, dx
	stosw
	call getkey
	cmp ax, VK_LEFT
	je .left
	cmp ax, VK_RIGHT
	je .right
	cmp ax, VK_SPACE
	je .finish
	jmp .num
.left:
	cmp bx, 1		; lower bound
	je .num
	dec bx
	jmp .num
.right:
	cmp bx, nlevels		; upper bound
	je .num
	inc bx
	jmp .num
.finish:
	mov [mazeid], bx	; save selection
	dec bx			; 0-index
	add bx, bx		; word-size
	mov si, [levels+bx]

;; decode() -- decodes level at si into buf
;; Inputs:
;; si : pointer to input
;; Outputs:
;; bh : map height
;; bl : map width
;; Working state:
;; ax : the next two bytes of input
;; bp : total number of tiles
;; di : number of tiles written
;; ch : number of input bits in ax
;; dl : number of output tiles
;; dh : tile code
decode:
	lodsw
	mov bx, ax		; long term storage
	movzx bp, ah
	movzx ax, al
	imul bp, ax		; compute total number of tiles
	xor di, di
	mov ch, 0
.step:
	cmp ch, 8
	jg .skip_read
	lodsb
	mov cl, 8
	sub cl, ch
	shl ax, cl
	add ch, 8
.skip_read:
	shl ax, 1
	jc .multiple
.single:
	mov dl, 1
	dec ch
	jmp .decode_tile
.multiple:
	mov dl, ah
	shr dl, 5
	add dl, 2
	shl ax, 3
	sub ch, 4
	jmp .decode_tile
.decode_tile:
	mov dh, ah
	cmp ah, 0xC0
	jb .size_two
.size_three:
	shr dh, 5
	shl ax, 3
	sub ch, 3
	jmp .write
.size_two:
	shr dh, 6
	shl ax, 2
	sub ch, 2
.write:
	cmp ch, 8
	jge .write_loop		; >= 1 byte of data left, don't shift
	mov cl, 8
	sub cl, ch
	shr ax, cl		; shift ah bits all the way to the right
.write_loop:
	mov [buf+di], dh
	inc di
	dec dl
	jnz .write_loop
	cmp di, bp
	jl .step
.player_pos:
	cmp ch, 8
	jge .x_was_buffered
	lodsb
	mov ah, al
	mov ch, 8
.x_was_buffered:
	mov cl, ch
	sub cl, 8
	shl ax, cl
	mov [px], ah
	lodsb
	mov [py], al

;; buf_to_map() -- copy decoded buffer to map
;; Inputs:
;; bl : buffer width
;; bh : buffer height
;; Working state:
;; ax : offset to center map
;; di : pointer into map
;; si : pointer to buf
;; cx : x counter
;; bp : y counter
;; dx : y stop
buf_to_map:
	push es
	push ds
	pop es
;; Compute center
	mov ax, 40
	sub al, bl
	shr al, 1		; (40 - width) / 2
	mov dx, 25
	sub dl, bh
	jz .no_slide_up
	dec dl			; round down (pusher.exe bug)
.no_slide_up:
	shr dl, 1		; (25 - height - 1) / 2
	add [px], al		; adjust player x
	add [py], dl		; adjust player y
	imul dx, 40
	add ax, dx		; destination offset
	xor bp, bp
	mov si, buf
	movzx dx, bh		; 16-bit height
	imul dx, 40
.loop:
	lea di, [map+bp]
	add di, ax
	movzx cx, bl
	rep movsb
	add bp, 40
	cmp bp, dx
	jl .loop
	pop es

play:
	call draw
	call getkey
	cmp ax, VK_SPACE
	je reset
	cmp ax, VK_LEFT
	je reset
	cmp ax, VK_RIGHT
	je reset
	cmp ax, VK_UP
	je reset
	cmp ax, VK_DOWN
	je reset
	jmp play

;; getkey() -- wait for keystroke and return it
;; Outputs:
;; ax : ASCII + scan code for input key
getkey:
	mov ah, 0
	int 0x16
	cmp ax, VK_ESC
	je exit
	ret

;; draw() -- full redraw of map onto vga display
draw:
	mov si, map
	xor di, di
	mov cx, 40*25
.step:	lodsb
	add al, al
	movzx bx, al
	mov ax, [tiles+bx]
	stosw
	loop .step
	mov bl, [py]
	imul bx, 40
	mov al, [px]
	add bx, ax
	movzx ax, al
	add bx, bx
	mov ax, [es:bx]
	cmp ax, EMPTY
	je .empty
	mov word [es:bx], PLAYER_TARGET
	ret
.empty	:mov word [es:bx], PLAYER_EMPTY
	ret

;; exit() -- exit the program with code 0
exit:
	mov ax, 0x0003
	int 0x10
	mov ax, 0x4C00
	int 0x21

section .data
mazeid:	dw 1
query:	db 'Number of maze:', 0
win:	db 'Congratulations !!!', 0
tiles:	dw EMPTY, WALL, BARREL, 0, 0, 0, TARGET, COMPLETED
%include "original60.s"

section .bss
px:	resb 1
py:	resb 1
slots:	resw 1
map:	resb 80*25
buf:	resb 80*25
