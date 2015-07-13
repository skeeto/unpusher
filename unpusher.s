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
%define PLAYER		(LIGHT_RED|0x01)
%define BARREL		(BG_BLACK|LIGHT_YELLOW|0x03)
%define COMPLETED	(BG_GREEN|LIGHT_YELLOW|0x06)
%define TARGET		(BG_GREEN|BLACK|0x2E)
%define WALL		(BG_YELLOW|DARK_RED|0xB1)

section .text
_start:
	xor ax, ax

;; reset() -- fills map and reset player position
;; Inputs:
;; al : tile type to fill map
reset:
	mov word [px], 0
	mov word [py], 0
	mov word [slots], 0xFFFF
	mov cx, 40*25
	mov di, map
	rep stosb

;; vga_initialize() -- sets VGA to 40x25 16-color text mode
vga_initialize:
	xor ax, ax
	int 0x10
	mov ax, 0xB800
	mov es, ax

	mov si, level_01
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
	mov bx, ax
	movzx bp, ah
	movzx ax, al
	imul bp, ax
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
	test ah, 0x80
	jz .single
.multiple:
	shl ax, 1
	mov dl, ah
	shr dl, 5
	add dl, 2
	shl ax, 3
	sub ch, 4
	jmp .decode_tile
.single:
	mov dl, 1
	shl ax, 1
	dec ch
.decode_tile:
	mov dh, ah
	test ah, 0x80
	jz .size_two
	test ah, 0x40
	jz .size_two
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
	movzx ax, ah
	mov [px], ax
	lodsb
	movzx ax, al
	mov [py], ax

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
;; Computer center
	mov ax, 40
	sub al, bl
	shr al, 1
	mov dx, 25
	sub dl, bh
	jz .no_slide_up
	dec dl			; round down (pusher.exe bug)
.no_slide_up:
	shr dl, 1
	add [px], ax		; adjust player x
	add [py], dx		; adjust player y
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
	mov bx, [py]
	imul bx, 40
	add bx, [px]
	add bx, bx
	mov word [es:bx], PLAYER

;; exit() -- exit the program with code 0
exit:
	mov ax, 0x4C00
	int 0x21

;; tmp
sleep:
	push ax
	push cx
	push dx
	mov cx, 1
	mov dx, 0
	mov ax, 0x8600
	int 0x15
	pop ax
	pop cx
	pop dx
	ret

section .data
query:	db 'Number of maze:', 0
win:	db 'Congratulations !!!', 0
tiles:	dw EMPTY, WALL, BARREL, 0, 0, 0, TARGET, COMPLETED
level_01:
	db 0x16, 0x0B, 0xA2, 0xDF, 0x38, 0x32, 0x1F, 0x38, 0x2A, 0x03, 0xE6
	db 0x12, 0xC0, 0xA5, 0xF2, 0x83, 0x02, 0x81, 0x03, 0xE4, 0x12, 0x82
	db 0x25, 0x06, 0xCD, 0x64, 0x22, 0x51, 0xAC, 0x11, 0xA1, 0x0A, 0x05
	db 0xE5, 0x11, 0xB1, 0x14, 0x82, 0x29, 0x82, 0x31, 0xA0, 0xE1, 0x2C
	db 0x18, 0xD1, 0xCF, 0x80, 0x0C, 0x08

section .bss
px:	resw 1
py:	resw 1
slots:	resw 1
map:	resb 80*25
buf:	resb 80*25
