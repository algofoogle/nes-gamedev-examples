; This example makes use of nesfile.ini (i.e. a configuration file for ld65).

; Build this by running ./bb, which basically does this:
;	# Assemble:
;	ca65 test.s -o output/test.o -l
; 	# Link, to create test.nes:
;	ld65 output/test.o -m output/map.txt -o output/test.nes -C nesfile.ini
; ...and then runs it with FCEUX.

; =====	Includes ===============================================================

.include "nes.inc"		; This is found in cc65's "asminc" dir.
.include "nesdefs.inc"	; This may be better than "nes.inc".
.include "helpers.inc"	; Various helper macros for init, etc, used by Anton's examples.

; =====	Local macros ===========================================================

; (None)


; =====	iNES header ============================================================

.segment "INESHDR"
	.byt "NES",$1A
	.byt 1 				; 1 x 16kB PRG block.
	.byt 1 				; 1 x 8kB CHR block.
	; Rest of iNES header defaults to 0, indicating mapper 0, standard RAM size, etc.

; =====	Interrupt vectors ======================================================

.segment "VECTORS"
	.addr nmi_isr, reset, irq_isr

; =====	RAM reservations =======================================================

.include "ram.inc"		; Reservations in Zero-page RAM, and General (BSS) WRAM.


; =====	Program data (read-only) ===============================================

.include "rodata.inc"	; "RODATA" segment; data found in the ROM.


; =====	Main code ==============================================================

.segment "CODE"


; MAIN PROGRAM START: The 'reset' address.
.proc reset

	basic_init
	clear_wram
	ack_interrupts
	init_apu
	ppu_wakeup

	; We're in VBLANK for a short while, so do video prep now...

	load_palettes palette_data

	; Clear all 4 nametables (i.e. start at nametable 0, and clear 4 nametables):
	clear_vram 0, 4

	; Fill attribute tables, for nametable 0, with palette %01
	; (for all 4 palettes, hence %01010101 or $55):
	lda #$55			; Select palette %01 (2nd palette) throughout.
	fill_attribute_table 0
	fill_attribute_table 2
	; These two are done because 0 and 2 are stacked vertically,
	; due to the INES header selecting horizontal mirroring in this case.

	enable_vblank_nmi

	; Now wait until nmi_counter increments, to indicate the next VBLANK.
	wait_for_nmi
	; By this point, we're in the 3rd VBLANK.

	init_sprites
	trigger_ppu_dma

	; Set X & Y scrolling positions (which have ranges of 0-255 and 0-239 respectively):
	ppu_scroll 0, 0

	; Configure PPU parameters/behaviour/table selection:
	lda #VBLANK_NMI|BG_0|SPR_0|NT_0|VRAM_RIGHT
	sta PPU_CTRL

	; Turn the screen on, by activating background and sprites:
	lda #BG_ON|SPR_ON
	sta PPU_MASK

	; Wait until the screen refreshes.
	wait_for_nmi
	; OK, at this point we know the screen is visible, ready, and waiting.

	; ------ Configure noise channel ------

	; Set noise type and period:
	; 0-------	Pseudo-random noise (instead of random regular waveform).
	; ----1000	Mid-range period/frequency.
	lda #%00001000
	sta APU_NOISE_FREQ	; Noise mode & period (frequency).

	; Set volume control:
	; --0-----	Use silencing timer (makes it one-shot).
	; ---0----	Use volume envelope (fade).
	; ----0000	Envelope length (shortest).
	lda #%00000000		; Very short fade, one-shot.
	sta APU_NOISE_VOL	; Noise channel volume control.

	; Set length counter:
	; 11111---	Maximum timer (though other values seem to have no effect?)
	lda #%11111000
	sta APU_NOISE_TIMER	; Length counter load.

	; Channel control:
	; ----1---	Enable noise channel.
	lda #%00001000
	sta APU_CHAN_CTRL	; Channel control.


message_loop:
	; Wait 1s (60 frames at 60Hz):
	nmi_delay 60

	; Make a debug click by firing the noise channel one-shot
	; (by loading the length counter from a value selected from
	; a look-up table, specified here by the upper 5 bits).
	; The table is described here:
	; http://wiki.nesdev.com/w/index.php/APU_Length_Counter#Table_structure
	; ...and in this case you can see that $03 is the shortest (2).
	lda #%00011000		; 
	sta APU_NOISE_TIMER

	; Clear lines 2-6 of the nametable (i.e. skip first 32*2 tiles, clear next 32*4 tiles):
	ppu_addr $2000+(32*2)
	lda #0
	ldx #(32*4/4)		; NOTE: 4 x "STA" instructions make this loop faster.
:	Repeat 4, sta PPU_DATA
	dex
	bne :-

	; Now fix the palettes for the above 4 lines (2-6) that we just cleared:
	; NOTE: There are 4 actual rows to a metarow. 1 metarow is 8 bytes across.
	; Hence, setting the palettes for rows 2-6 requires that we rewrite both
	; metarows 0 and 1 (which covers actual rows 0-3, and 4-7, respectively).
	ppu_addr $23c0 		; Select 1st metarow (rows 0-3; we'll then do 4-7).
	ldx #(16/4)			; Fill two metarows (8 bytes each), which covers 8 actual rows.
	lda #%01010101		; Both the upper rows (bits 0-3) and the lower rows (bits 4-7) get pallete 1 (%01 x 4).
:	Repeat 4, sta PPU_DATA
	dex
	bne :-

	; Point screen offset counter back to start of line 2:
	lda #(32*2)
	sta screen_offset

	; Point back to start of source message:
	lda #0
	sta msg_ptr

	; Fix scroll position:
	; NOTE: We have to do this after writing to VRAM, because scroll position seems
	; to automatically track the VRAM target address. For a possible explanation of this, see:
	; http://wiki.nesdev.com/w/index.php/The_skinny_on_NES_scrolling
	ppu_scroll 0, 0

	; Wait 1s:
	nmi_delay 60

char_loop:
	; Fix message screen offset pointer:
	lda #$20			; Hi-byte of $2000
	sta PPU_ADDR
	lda screen_offset	; Get current screen offset.
	inc screen_offset	; Increment screen offset variable, for next time.
	sta PPU_ADDR

	; Fix scroll position:
	ppu_scroll 0, 0

	; Write next character of message:
	ldx msg_ptr			; Get message offset.
	inc msg_ptr			; Increment message offset source.
	lda hello_msg,x		; Get message character.
	beq message_done	; A=0 => End of message.
	sta PPU_DATA		; Write the character.

	cmp #$20
	beq skip_click		; Don't make a click for space characters.

	; Activate short one-shot noise effect here, by loading length counter:
	lda #%00111000		; Length ID 7 is "6" (?) steps => 6/240 => 25ms??
	sta APU_NOISE_TIMER

skip_click:
	; Wait for 50ms (3 frames at 60Hz):
	nmi_delay 3
	jmp char_loop		; Go process the next character.

message_done:
	; Message is done; wait half a second.
	nmi_delay 30
	; Change the text colour of the 5th and 6th rows.
	lda #$23			; Attribute table starts at $23C0.
	sta PPU_ADDR
	lda #$C8			; Select 2nd metarow (rows 4, 5, 6, and 7).
	sta PPU_ADDR
	ldx #8				; Fill just one metarow.
	lda #%01011111		; Lower 2 rows (bits 4-7) get palette 1 (%01 x 2), upper 2 get palette 3 (%11 x 2).
:	sta PPU_DATA
	dex
	bne :-

	; Fix scroll position:
	ppu_scroll 0, 0

	; Wait 1 sec:
	nmi_delay 60

	; Scroll off screen:
	ldx #0
scroll_loop:
	cpx #((7*8)<<1)		; Scroll by 56 scanlines (7 lines), using lower bit to halve the speed.
	beq repeat_message_loop	; Reached our target scroll limit.
	wait_for_nmi
	lda #0
	sta PPU_SCROLL		; X scroll is still 0.
	txa
	lsr a				; Discard lower bit.
	sta PPU_SCROLL		; Y scroll is upper 6 bits of X register.
	inx					; Increment scroll counter.
	jmp scroll_loop

repeat_message_loop:
	jmp message_loop

.endproc


; NMI ISR.
; Use of .proc means labels are specific to this scope.
.proc nmi_isr
	dec nmi_counter
	rti
.endproc


; IRQ/BRK ISR:
.proc irq_isr
	; Handle IRQ/BRK here.
	rti
.endproc





; =====	CHR-ROM Pattern Tables =================================================

; ----- Pattern Table 0 --------------------------------------------------------

.segment "PATTERN0"

	.incbin "anton2.chr"

.segment "PATTERN1"

	.repeat $100
		.byt %11111111
		.byt %10111011
		.byt %11010111
		.byt %11101111
		.byt %11010111
		.byt %10111011
		.byt %11111111
		.byt %11111111
		Repeat 8, .byt $FF
	.endrepeat
