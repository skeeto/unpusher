bits 16
org 0x100
	mov ah, 0
	mov al, 0
	int 0x10
	mov ah, 0x1d
	mov bx, 1
	int 0x1f
