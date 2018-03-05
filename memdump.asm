;******************************************************************************
; MemDump is an 8088 program to show contents of memory in hexadecimal.
; Copyright (C) 2018 s0s
; 
; This program is free software; you can redistribute it and/or
; modify it under the terms of the GNU General Public License
; as published by the Free Software Foundation; either version 2
; of the License, or (at your option) any later version.
; 
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
; 
; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

;    ************************************************************************
;      * Created:    July 4, 2017                                         *
;      * Author:     s0s, a.k.a. TerraformerX                             *
;      *                                                                  *
;      * Modified:   March 4, 2018                                        *
;      * Changes:    Fixed an omission in the BtoATable                   *
;      *                                                                  *
;      * Purpose:    To make utilities to print a screen and dump memory  *
;      *                                                                  *
;      * Functional: - stack                                              *
;      *             - I/O (8255 PPI)                                     *
;      *             - interrupts (8259 PIC)                              *
;      *             - the improved LCDinit subroutine                    *
;      *             - GetStrLen                                          *
;      *             - PrintStr                                           *
;      *             - ByteToHex                                          *
;      *                                                                  *
;    ************************************************************************
;
;...............................................................................
USE16
CPU 8086

; Beginning of constant definitions
section		.data

; ROM constants
_1KB		equ	1024
_32KB		equ	32*_1KB
_128KB		equ	128*_1KB
ROM_SIZE	equ	_128KB		; Set size of ROM here

; Interrupt constants
IVT_SEGMENT	equ	0x0000		; Segment containing IVT addresses
INT_SR_SEGMENT	equ	0x10000-(ROM_SIZE/16)-0x10; Segment of ISRs
INT_20		equ	0x20		; Interrupt type 20h; really type 32
INT_20_OFFSET	equ	0x1100		; Offset of ISR 20h
INT_80		equ	0x80		; Interrupt type 80h; really type 128
INT_80_OFFSET	equ	0x3100		; Offset of ISR 80h

; 8259 PIC initialization commands
INT_ICW1	equ	00011111b	; Lvl trig,4 addr bytes,sngl,expect ICW4
INT_ICW2	equ	00100000b	; Interrupts start at 32
INT_ICW4	equ	00000011b	; Non-buffered mode (pin16=NC),AEOI,8088
INT_OCW1	equ	11111110b	; Mask all interrupts except first one

; 8259 PIC command ports
INT_ICW1_PORT	equ	0xBE		; IO port 190
INT_ICW2_PORT	equ	0xBF		; IO port 191
INT_ICW4_PORT	equ	0xBF		; IO port 191
INT_OCW1_PORT	equ	0xBF		; IO port 191 

; IO ports
IO_PORT0	equ	0x00		; 8255 "A" PPI port 0
IO_PORT1	equ	0x01		; 8255 "A" PPI port 1
IO_PORT2	equ	0x02		; 8255 "A" PPI port 2
_8255A_CMD_PORT	equ	0x03		; 8255 "A" PPI port 3

; Memory locations
DATA_SEG	equ	0x0400		; Segment where program data is stored
TXT_BUFF	equ	0x0000		; Offset of text buffer (LCD text), 8KB
TXT_BUF_POS	equ	0x2000		; Position in text buffer, 2 bytes
LCD_CHAR_POS	equ	0x2002		; LCD addr of last char printed, 1 byte
MISC_DATA	equ	0x2003		; Byte for misc data storage
DISP_POS	equ	0x2004		; Pos in txt buff of top LCD line
;...............................................................................
; Subroutines
; ***********
; Delay
; PrintChar
; PrintStr
; InitLCD
; GetStrLen

; Beginning of program code
org		0x100

section		.text
start:		
		; Initialize the stack
		mov	sp,0xFFFF	; SP=64K, 384K in memory, 64K above SS
		mov	bx, 0		; Initialize BX to 0
		mov	ax,0x5000 	; Initialize SS to be at 320KB, 64KB
		mov	ss,ax		;   below the end of RAM
	
		mov	ax, cs		; Make DS = CS
		mov	ds, ax
	
		; This sets up the 8255 programmable-peripheral interface
		mov	al, 0x90	; Set 8255 to Mode 0 (basic I/O)
		out	_8255A_CMD_PORT, al	; Port 0 input, ports 1 & 2 output 
	
		; This sets up the interrupt vector table
		mov	dx, IVT_SEGMENT	; Segment of interrupt vector table
		mov	es, dx 		; Put it into ES 
	
		; Install int 20
		mov	bx, 4*INT_20	; Offset of interrupt vector table
		mov	dx, INT_20_OFFSET;Load DX with offset of ISR section 
		mov	word [es:bx], dx; Install ISR offset into IVT entry 20h 
		mov	dx, INT_SR_SEGMENT;Value of int subroutine segment
		mov	word [es:bx+2], dx;Install ISR segment in IVT entry 20h

		; Install int 80
		mov	bx, 4*INT_80	; Offset of interrupt vector table
		mov	dx, INT_80_OFFSET;Load DX with offset of ISR section 
		mov	word [es:bx], dx; Install ISR offset into IVT entry 20h 
		mov	dx, INT_SR_SEGMENT;Value of int subroutine segment
		mov	word [es:bx+2], dx;Install ISR segment in IVT entry 20h

		; Initialize data memory
		mov	cx, 0x1003	; Number of words to zero fill
		xor	ax, ax		; Clear AX
		mov	di, TXT_BUFF	; Offset to fill from
		mov	dx, DATA_SEG	; Segment of data memory
		mov	es, dx
		rep	stosw
	
		; Initialize the 8259 PIC
		mov	al, INT_ICW1
		out	INT_ICW1_PORT, al
		mov	al, INT_ICW2
		out	INT_ICW2_PORT, al
		mov	al, INT_ICW4
		out	INT_ICW4_PORT, al
		mov	al, INT_OCW1
		out	INT_OCW1_PORT, al 
		
		call	InitLCD		; Initialize the 20x4 LCD display
		sti			; Enable interrupts 
		; End of system initialization

		mov	si, 0x0100	; Offset to start dumping memory
		mov	cx, 0xDFF0	; Segment to dump
		call	MemDump
		jmp	$


	
; Beginning of subroutines
	
Delay:		dec	bx		; Decrement it by 1 each time.  
		cmp	bx, 0x0000	; See if the loop is done
		jnz	Delay		; If not, iterate again
		ret 

; E = 100b, RS = 010b, RW = 001b
PrintChar:	
		push	ax		; Save the ASCII character
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		pop	ax		; Get the ASCII character back
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x001F 
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x001F 
		call	Delay
		ret 

hexLookup:	db	'0123456789ABCDEF'
ByteToHex:
; ACCEPTS
;   AL = byte
; ASSUMES
;   DS is where hexLookup is.
; CORRUPTS
;   BX, CL
; RETURNS
;   AH = low character
;   AL = high character
;     This reverse order is usually more useful during output
	mov  bx, hexLookup
	mov  ah, al
	and  al, 0x0F
	xlat
	xchg ah, al
	mov  cl, 4
	shr  al, cl
	xlat
	ret

memdumptitle:	db	': memdump v1    ', 0x00
MemDump:
; ACCEPTS
;   CX=segment to dump, SI=starting location
; ASSUMES
;   DS is where hexLookup is.
; CORRUPTS
;   AX, BX, CX, DX, DS, ES
; RETURNS
;   AH = low character
;   AL = high character
;     This reverse order is usually more useful during output 
; Registers that CAN'T save stuff in:
;   AX

		; Clear the screen
		mov	al, 0		; Clear IO_PORT2
		out	IO_PORT2, al
		mov	al, 1		; Command to clear the display
		out	IO_PORT1, al 
		mov	al, 4		; Make E high
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay 
		mov	al, 0		; Make E low
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay 
		mov	al, 2		; Make RS high
		out	IO_PORT2, al 
		mov	bx, 0x00FF
		call	Delay 

; Save the dump segment in DX
		mov	dx, cx

		; Convert the first byte of the segment to hex
		mov	al, dh		; Put the byte to parse in AL
		mov	bx, cs		; Put segment of hexLookup in BX
		mov	ds, bx		; And then DS
		mov	bx, hexLookup	; Address of hexLookup in BX
		mov	ah, al
		and	al, 0x0F
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat 
		call	PrintChar	; Print high nibble
		xchg	ah, al
		call	PrintChar	; Print low nibble

		; Convert the second byte to hex
		mov	al, dl		; Put the byte to parse in AL
		mov	bx, hexLookup	; Address of hexLookup in BX
		mov	ah, al
		and	al, 0x0F
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat 
		call	PrintChar	; Print high nibble
		xchg	ah, al
		call	PrintChar	; Print low nibble 

		; Print the title string
		mov	es, si		; Save SI offset in ES
		mov	si, memdumptitle
		call	PrintStr

; Preparations for line 2
		; Set DDRAM address to 40h
		mov	al, 0xC0	; Set LCD DDRAM address to 40h
		out	IO_PORT1, al 
		mov	al, 4		; Make E high
		out	IO_PORT2, al
		mov	bx, 0x001F
		call	Delay 
		xor	al, al		; Make E low
		out	IO_PORT2, al
		mov	bx, 0x001F
		call	Delay
		mov	al, 2		; Make RS high
		out	IO_PORT2, al 

		mov	si, es		; Put the start location back in SI
		mov	es, dx		; Save dump segment in ES 
		mov	dx, si

		; Convert the first byte of the segment to hex
		mov	al, dh		; Put the byte to parse in AL
		mov	bx, cs		; Put segment of hexLookup in BX
		mov	ds, bx		; And then DS
		mov	bx, hexLookup	; Address of hexLookup in BX
		mov	ah, al
		and	al, 0x0F
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat 
		call	PrintChar	; Print high nibble
		xchg	ah, al
		call	PrintChar	; Print low nibble

		; Convert the second byte to hex
		mov	al, dl		; Put the byte to parse in AL
		mov	bx, hexLookup	; Address of hexLookup in BX
		mov	ah, al
		and	al, 0x0F
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat 
		call	PrintChar	; Print high byte
		xchg	ah, al
		call	PrintChar	; Print low nibble 

		mov	dl, 4		; Times to iterate per line 

; Now dump memory for this line
MemDumpL2:	
		mov	bx, es		; Segment to dump
		mov	ds, bx		; Move it into DS for lodsw 
		lodsw

		mov	dh, ah		; Store the second byte in DH for now
	
		; Hex lookup
		mov	ah, al
		and	al, 0x0F
		mov	bx, cs		; Segment hexLookup is in
		mov	ds, bx		; Now DS is set to hexLookup for xlat
		mov	bx, hexLookup	; Now hexLookup's address is in BX for xlat 
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat

		; Print the high hex nibble
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		nop			; Delay
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop

		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		nop			; Delay
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop


		; Now print the low hex nibble
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		xchg	ah, al
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		nop			; Delay
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop

		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		nop			; Delay
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop


		mov	al, dh		; Put the second byte into AL now

		; Hex lookup
		mov	ah, al
		and	al, 0x0F
		mov	bx, cs		; Segment hexLookup is in
		mov	ds, bx		; Now DS is set to hexLookup for xlat
		mov	bx, hexLookup	; Now hexLookup's address is in BX for xlat 
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat

		; Print the high hex nibble
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		nop			; Delay
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop

		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		nop			; Delay
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop


		; Now print the low hex nibble
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		xchg	ah, al
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		nop			; Delay
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop

		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		nop			; Delay
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop

		dec	dl
		cmp	dl, 0		; Is this line done yet?
		jnz	MemDumpL2

; Preparations for line 3

		; Set the cursor to beginning of line 3
		mov	al, 0x94	; Set LCD DDRAM address to 14h
		out	IO_PORT1, al 
		mov	al, 4		; Make E high
		out	IO_PORT2, al
		mov	bx, 0x001F
		call	Delay 
		xor	al, al		; Make E low
		out	IO_PORT2, al
		mov	bx, 0x001F
		call	Delay
		mov	al, 2		; Make RS high
		out	IO_PORT2, al 

		mov	dx, si		; Put the offset into DX to print

		; Convert the first byte of the offset to hex
		mov	al, dh		; Put the byte to parse in AL
		mov	bx, cs		; Put segment of hexLookup in BX
		mov	ds, bx		; And then DS
		mov	bx, hexLookup	; Address of hexLookup in BX
		mov	ah, al
		and	al, 0x0F
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat 
		call	PrintChar	; Print high nibble
		xchg	ah, al
		call	PrintChar	; Print low nibble

		; Convert the second byte to hex
		mov	al, dl		; Put the byte to parse in AL
		mov	bx, hexLookup	; Address of hexLookup in BX
		mov	ah, al
		and	al, 0x0F
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat 
		call	PrintChar	; Print high byte
		xchg	ah, al
		call	PrintChar	; Print low nibble 

		mov	dl, 8		; Times to iterate per line 

; Now dump memory for this line
MemDumpL3:	
		mov	bx, es		; Segment to dump
		mov	ds, bx		; Move it into DS for lodsw 
		lodsb
	
		; Hex lookup
		mov	ah, al
		and	al, 0x0F
		mov	bx, cs		; Segment hexLookup is in
		mov	ds, bx		; Now DS is set to hexLookup for xlat
		mov	bx, hexLookup	; Now hexLookup's address is in BX for xlat 
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat

		; Print the high hex nibble
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x0008
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x0008
		call	Delay

		; Now print the low hex nibble
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		xchg	ah, al
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x0008
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x0008
		call	Delay

		dec	dl
		cmp	dl, 0		; Is this line done yet?
		jnz	MemDumpL3

; Preparations for line 4

		; Set the cursor to beginning of line 4
		mov	al, 0xD4	; Set LCD DDRAM address to 54h
		out	IO_PORT1, al 
		mov	al, 4		; Make E high
		out	IO_PORT2, al
		mov	bx, 0x001F
		call	Delay 
		xor	al, al		; Make E low
		out	IO_PORT2, al
		mov	bx, 0x001F
		call	Delay
		mov	al, 2		; Make RS high
		out	IO_PORT2, al 

		mov	dx, si		; Put the offset into DX to print

		; Convert the first byte of the offset to hex
		mov	al, dh		; Put the byte to parse in AL
		mov	bx, cs		; Put segment of hexLookup in BX
		mov	ds, bx		; And then DS
		mov	bx, hexLookup	; Address of hexLookup in BX
		mov	ah, al
		and	al, 0x0F
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat 
		call	PrintChar	; Print high nibble
		xchg	ah, al
		call	PrintChar	; Print low nibble

		; Convert the second byte to hex
		mov	al, dl		; Put the byte to parse in AL
		mov	bx, hexLookup	; Address of hexLookup in BX
		mov	ah, al
		and	al, 0x0F
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat 
		call	PrintChar	; Print high byte
		xchg	ah, al
		call	PrintChar	; Print low nibble 

		mov	dl, 8		; Times to iterate per line 

; Now dump memory for this line
MemDumpL4:
		mov	bx, es		; Segment to dump
		mov	ds, bx		; Move it into DS for lodsw
		lodsb
	
		; Hex lookup
		mov	ah, al
		and	al, 0x0F
		mov	bx, cs		; Segment hexLookup is in
		mov	ds, bx		; Now DS is set to hexLookup for xlat
		mov	bx, hexLookup	; Now hexLookup's address is in BX for xlat 
		xlat
		xchg	ah, al
		mov	cl, 4
		shr	al, cl
		xlat

		; Print the high hex nibble
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x0008
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x0008
		call	Delay

		; Now print the low hex nibble
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		xchg	ah, al
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x0008
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x0008
		call	Delay

		dec	dl
		cmp	dl, 0		; Is this line done yet?
		jnz	MemDumpL4
		
		ret



PrintStr:
; ACCEPTS
;   DS=segment the string is in, SI=address of string
; CORRUPTS
;   AX, BX, CX, DS, SI
; RETURNS
;   nothing 
PrintStrLoop:	lodsw
		cmp	al, 0		; See if text exists here
		jz	PrntStrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
;PrintStr just to make it easier to search here
		; Second character, if applicable
		mov	ax, cx
		xchg	ah, al
		cmp	al, 0		; See if text exists here
		jz	PrntStrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

		; Third character, if applicable
		lodsw			; Why not do it again to save cycles?
		cmp	al, 0		; See if text exists here
		jz	PrntStrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

		; Fourth character, if applicable
		mov	ax, cx
		xchg	ah, al
		cmp	al, 0		; See if text exists here
		jz	PrntStrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay 
		jmp	PrintStrLoop
PrntStrExit:	ret 

PrintScreen:
; ACCEPTS
;   nothing
; CORRUPTS
;   AX, BX, CX, DS, SI
; RETURNS
;   nothing 
		mov	bx, DATA_SEG	; Segment text buffer is in
		mov	ds, bx
		mov	si, DISP_POS	; Put display position into SI

		mov	al, 1		; Command to clear the display
		out	IO_PORT1, al 
		mov	al, 4		; Make E high
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay 
		xor	al, al		; Make E low
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay
		mov	al, 2		; Make RS high
		out	IO_PORT2, al

		mov	dl, 5		; Iterate this many times
		
PrintL1Loop:
		lodsw
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
;PrintScr just to make it easier to search here
		; Second character, if applicable
		mov	ax, cx
		xchg	ah, al
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

		; Third character, if applicable
		lodsw			; Why not do it again to save cycles?
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

		; Fourth character, if applicable
		mov	ax, cx
		xchg	ah, al
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay 
		
		dec	dl
		cmp	dl, 0		; Is this line done?
		jnz	PrintL1Loop	; If not, iterate again

; Preparations for the second line
		mov	ax, si
		add	ax, 20		; Increment SI by 20 for next line
		mov	si, ax

		mov	al, 0xC0	; Set LCD DDRAM address to 40h
		out	IO_PORT1, al 
		mov	al, 4		; Make E high
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay 
		xor	al, al		; Make E low
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay
		mov	al, 2		; Make RS high
		out	IO_PORT2, al

		mov	dl, 5		; Iterate this many times
	
; Loop to print the second line
PrintL2Loop:	lodsw
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

;Line 2 just to make it easier to search here

		; Second character, if applicable
		mov	ax, cx
		xchg	ah, al
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

		; Third character, if applicable
		lodsw			; Why not do it again to save cycles?
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

		; Fourth character, if applicable
		mov	ax, cx
		xchg	ah, al
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay 
		
		dec	dl
		cmp	dl, 0		; Is this line done?
		jnz	PrintL2Loop	; If not, iterate again

; Preparations for the third line
		mov	ax, si
		add	ax, 20		; Increment SI by 20 for next line
		mov	si, ax 
		mov	al, 0xD4	; Set LCD DDRAM address to 14h
		out	IO_PORT1, al 
		mov	al, 4		; Make E high
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay 
		xor	al, al		; Make E low
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay
		mov	al, 2		; Make RS high
		out	IO_PORT2, al 
		mov	dl, 5		; Iterate this many times
	
; Loop to print the third line
PrintL3Loop:	lodsw
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

;Line 2 just to make it easier to search here

		; Second character, if applicable
		mov	ax, cx
		xchg	ah, al
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

		; Third character, if applicable
		lodsw			; Why not do it again to save cycles?
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

		; Fourth character, if applicable
		mov	ax, cx
		xchg	ah, al
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay 
		
		dec	dl
		cmp	dl, 0		; Is this line done?
		jnz	PrintL3Loop	; If not, iterate again

; Preparations for the fourth line
		mov	ax, si
		add	ax, 20		; Increment SI by 20 for next line
		mov	si, ax

		mov	al, 0xD4	; Set LCD DDRAM address to 54h
		out	IO_PORT1, al 
		mov	al, 4		; Make E high
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay 
		xor	al, al		; Make E low
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay
		mov	al, 2		; Make RS high
		out	IO_PORT2, al

		mov	dl, 5		; Iterate this many times
	
; Loop to print the fourth line
PrintL4Loop:	lodsw
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

;Line 2 just to make it easier to search here

		; Second character, if applicable
		mov	ax, cx
		xchg	ah, al
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

		; Third character, if applicable
		lodsw			; Why not do it again to save cycles?
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay

		; Fourth character, if applicable
		mov	ax, cx
		xchg	ah, al
		cmp	al, 0		; See if text exists here
		jz	PrntScrExit	; If not then exit
		mov	cx, ax		; Save AX in CX
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	ax, cx		; Put CX back in AX
		out	IO_PORT1,al	; Send the character to the display
		mov	al,0x06		; Make E and RS high
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay
		mov	al,0x02		; Make RS high, E low
		out	IO_PORT2,al
		mov	bx, 0x000F
		call	Delay 
		
		dec	dl
		cmp	dl, 0		; Is this line done?
		jnz	PrintL4Loop	; If not, iterate again

PrntScrExit:	ret 



initSequence:	db	0x38, 0x0C, 0x01, 0x06, 0x14, 0x02, 0x80 
; E = 100b, RS = 010b, RW = 001b
InitLCD:
; ACCEPTS
;   nothing
; CORRUPTS
;   SI, CX, AX
; RETURNS
;   nothing 
		mov	bx, 0x01FF		; Set the countdown timer.
InitDel:	dec	bx			; Decrement it by 1 each time.  
		cmp	bx, 0x0000		; See if the loop is done
		jnz	InitDel			; If the counter hasn't counted

		; Start initialization of the LCD
		mov	si, initSequence 	; assuming DS == CS / tiny
		mov	cx, 7			; Number of iterations (strlen)
		cld
initLCDLoop:
		lodsb
		out	IO_PORT1, al

		mov	al, 4
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay

		xor	al, al
		out	IO_PORT2, al
		mov	bx, 0x002F
		call	Delay

		loop	initLCDLoop
		ret 



PrintByteAsDec:
; ACCEPTS
;   AL=byte to convert & print
; CORRUPTS
;   AX, BX, DS, SI
; RETURNS
;   nothing 
		mov	bx, cs
		mov	ds, bx
		shl	ax, 1
		shl	ax, 1
		add	ax, BtoATable
		mov	si, ax

		lodsw
		call	PrintChar
		mov	bx, 0x001F
		call	Delay
		
		xchg	ah, al
		cmp	al, 0
		jz	pbadExit
		call	PrintChar
		mov	bx, 0x001F
		call	Delay
		
		lodsb
		cmp	al, 0
		jz	pbadExit
		call	PrintChar
		mov	bx, 0x001F
		call	Delay
pbadExit:	ret 

GetStrLen:
; ACCEPTS
;   AX=address of string, BX=segment containing the string
; CORRUPTS
;   AX, CX, DI, ES
; RETURNS
;   AL=binary length of string
		mov	es, bx
		mov	di, ax		; Move string address into di
		mov	cx, 0xFFFF	; Initialize CX
		sub	ax, ax		; Initialize AX
		cld
		repne	scasb
		not	cx
		dec	cx		; Get the length of the string
		mov	al, cl
		ret 

; String declarations
msg:		db	'This is a test string', 0x00
BtoATable	db	'0', 0x00, 0x00, 0x00, '1', 0x00, 0x00, 0x00, '2', 0x00, 0x00, 0x00, '3', 0x00, 0x00, 0x00, '4', 0x00, 0x00, 0x00, '5', 0x00, 0x00, 0x00, '6', 0x00, 0x00, 0x00, '7', 0x00, 0x00, 0x00, '8', 0x00, 0x00, 0x00, '9', 0x00, 0x00, 0x00, '10', 0x00, 0x00, '11', 0x00, 0x00, '12', 0x00, 0x00, '13', 0x00, 0x00, '14', 0x00, 0x00, '15', 0x00, 0x00, '16', 0x00, 0x00, '17', 0x00, 0x00, '18', 0x00, 0x00, '19', 0x00, 0x00, '20', 0x00, 0x00, '21', 0x00, 0x00, '22', 0x00, 0x00, '23', 0x00, 0x00, '24', 0x00, 0x00, '25', 0x00, 0x00, '26', 0x00, 0x00, '27', 0x00, 0x00, '28', 0x00, 0x00, '29', 0x00, 0x00, '30', 0x00, 0x00, '31', 0x00, 0x00, '32', 0x00, 0x00, '33', 0x00, 0x00, '34', 0x00, 0x00, '35', 0x00, 0x00, '36', 0x00, 0x00, '37', 0x00, 0x00, '38', 0x00, 0x00, '39', 0x00, 0x00, '40', 0x00, 0x00, '41', 0x00, 0x00, '42', 0x00, 0x00, '43', 0x00, 0x00, '44', 0x00, 0x00, '45', 0x00, 0x00, '46', 0x00, 0x00, '47', 0x00, 0x00, '48', 0x00, 0x00, '49', 0x00, 0x00, '50', 0x00, 0x00, '51', 0x00, 0x00, '52', 0x00, 0x00, '53', 0x00, 0x00, '54', 0x00, 0x00, '55', 0x00, 0x00, '56', 0x00, 0x00, '57', 0x00, 0x00, '58', 0x00, 0x00, '59', 0x00, 0x00, '60', 0x00, 0x00, '61', 0x00, 0x00, '62', 0x00, 0x00, '63', 0x00, 0x00, '64', 0x00, 0x00, '65', 0x00, 0x00, '66', 0x00, 0x00, '67', 0x00, 0x00, '68', 0x00, 0x00, '69', 0x00, 0x00, '70', 0x00, 0x00, '71', 0x00, 0x00, '72', 0x00, 0x00, '73', 0x00, 0x00, '74', 0x00, 0x00, '75', 0x00, 0x00, '76', 0x00, 0x00, '77', 0x00, 0x00, '78', 0x00, 0x00, '79', 0x00, 0x00, '80', 0x00, 0x00, '81', 0x00, 0x00, '82', 0x00, 0x00, '83', 0x00, 0x00, '84', 0x00, 0x00, '85', 0x00, 0x00, '86', 0x00, 0x00, '87', 0x00, 0x00, '88', 0x00, 0x00, '89', 0x00, 0x00, '90', 0x00, 0x00, '91', 0x00, 0x00, '92', 0x00, 0x00, '93', 0x00, 0x00, '94', 0x00, 0x00, '95', 0x00, 0x00, '96', 0x00, 0x00, '97', 0x00, 0x00, '98', 0x00, 0x00, '99', 0x00, 0x00, '100', 0x00, '101', 0x00, '102', 0x00, '103', 0x00, '104', 0x00, '105', 0x00, '106', 0x00, '107', 0x00, '108', 0x00, '109', 0x00, '110', 0x00, '111', 0x00, '112', 0x00, '113', 0x00, '114', 0x00, '115', 0x00, '116', 0x00, '117', 0x00, '118', 0x00, '119', 0x00, '120', 0x00, '121', 0x00, '122', 0x00, '123', 0x00, '124', 0x00, '125', 0x00, '126', 0x00, '127', 0x00, '128', 0x00, '129', 0x00, '130', 0x00, '131', 0x00, '132', 0x00, '133', 0x00, '134', 0x00, '135', 0x00, '136', 0x00, '137', 0x00, '138', 0x00, '139', 0x00, '140', 0x00, '141', 0x00, '142', 0x00, '143', 0x00, '144', 0x00, '145', 0x00, '146', 0x00, '147', 0x00, '148', 0x00, '149', 0x00, '150', 0x00, '151', 0x00, '152', 0x00, '153', 0x00, '154', 0x00, '155', 0x00, '156', 0x00, '157', 0x00, '158', 0x00, '159', 0x00, '160', 0x00, '161', 0x00, '162', 0x00, '163', 0x00, '164', 0x00, '165', 0x00, '166', 0x00, '167', 0x00, '168', 0x00, '169', 0x00, '170', 0x00, '171', 0x00, '172', 0x00, '173', 0x00, '174', 0x00, '175', 0x00, '176', 0x00, '177', 0x00, '178', 0x00, '179', 0x00, '180', 0x00, '181', 0x00, '182', 0x00, '183', 0x00, '184', 0x00, '185', 0x00, '186', 0x00, '187', 0x00, '188', 0x00, '189', 0x00, '190', 0x00, '191', 0x00, '192', 0x00, '193', 0x00, '194', 0x00, '195', 0x00, '196', 0x00, '197', 0x00, '198', 0x00, '199', 0x00, '200', 0x00, '201', 0x00, '202', 0x00, '203', 0x00, '204', 0x00, '205', 0x00, '206', 0x00, '207', 0x00, '208', 0x00, '209', 0x00, '210', 0x00, '211', 0x00, '212', 0x00, '213', 0x00, '214', 0x00, '215', 0x00, '216', 0x00, '217', 0x00, '218', 0x00, '219', 0x00, '220', 0x00, '221', 0x00, '222', 0x00, '223', 0x00, '224', 0x00, '225', 0x00, '226', 0x00, '227', 0x00, '228', 0x00, '229', 0x00, '230', 0x00, '231', 0x00, '232', 0x00, '233', 0x00, '234', 0x00, '235', 0x00, '236', 0x00, '237', 0x00, '238', 0x00, '239', 0x00, '240', 0x00, '241', 0x00, '242', 0x00, '243', 0x00, '244', 0x00, '245', 0x00, '246', 0x00, '247', 0x00, '248', 0x00, '249', 0x00, '250', 0x00, '251', 0x00, '252', 0x00, '253', 0x00, '254', 0x00, '255', 0x00

		times	((ROM_SIZE-0x1F000) - ($-$$)) db 0 

;***************************************
; Beginning of the interrupt subroutines
;*************************************** 

;*************************************** 
; Interrupt 20h subroutine 
; DFF0:1100
; Keeping the same code segment as the program
; Address 900KB, 124KB below the end of memory 
section		.isr20Section start=(ROM_SIZE-0x1F000+0x100) align=16 
INT_20_SR:	
		cli
		mov	al, 0xDB
		out	IO_PORT2, al
		sti
		iret

;*************************************** 
; Interrupt 80h subroutine 
; DFF0:3140
; Keeping the same code segment as the program
; Address 908KB, 116KB below the end of memory 
section		.isr80Section start=(ROM_SIZE-0x1CFC0+0x100) align=16 
INT_80_SR:	
		cli
		mov	al, 0x6A
		out	IO_PORT2, al
		sti
		iret

; The memory address where the 8088 gets the first instruction
; FFFF:0000
; Reset_vector:	
section		.resetVector	start=(ROM_SIZE+0x100-16) align=16 
		cli			; Disable interrupts during system init 
		db	0xEA			; far jump
		dw	start			; Sets the offset IP value
		dw	0x10000-(ROM_SIZE/16)-0x10; Target CS value
		align	16, db 0
