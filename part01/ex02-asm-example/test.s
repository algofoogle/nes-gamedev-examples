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

; =====	Local macros ===========================================================

; This waits for a change in the value of the NMI counter.
; It destroys the A register.
.macro wait_for_nmi
	lda nmi_counter
:	cmp nmi_counter
	beq	:-				; Loop, so long as nmi_counter hasn't changed its value.
.endmacro

; This waits for a given no. of NMIs to pass. It destroys the A register.
; Note that it relies on an NMI counter that decrements, rather than increments.
.macro nmi_delay frames
	lda #frames
	sta nmi_counter		; Store the desired frame count.
:	lda nmi_counter		; In a loop, keep checking the frame count.
	bne :-				; Loop until it's decremented to 0.
.endmacro



; =====	iNES header ============================================================

.segment "INESHDR"
	.byt "NES",$1A
	.byt 1
	.byt 1

; =====	Interrupt vectors ======================================================

.segment "VECTORS"
	.addr nmi_isr, reset, irq_isr

; =====	Zero-page RAM ==========================================================

.segment "ZEROPAGE"

nmi_counter:	.res 1	; Counts DOWN for each NMI.
msg_ptr:		.res 1	; Points to the next character to fetch from a message.
screen_offset:	.res 1	; Points to the next screen offset to write.

; =====	General RAM ============================================================

.segment "BSS"
; Put labels with .res statements here.

; =====	Music ==================================================================

.segment "RODATA"

palette_data:
; Colours available in the NES palette are:
; http://bobrost.com/nes/files/NES_Palette.png
.repeat 2
	pal $09,	$16, $2A, $12	; $09 (dark plant green), $16 (red), $2A (green), $12 (blue).
	pal 		$16, $28, $3A	; $16 (red), $28 (yellow), $3A (very light green).
	pal 		$00, $10, $20	; Grey; light grey; white.
	pal 		$25, $37, $27	; Pink; light yellow; orange.
.endrepeat

hello_msg:
        ; 01234567890123456789012345678901
	.byt "  Hello, World!                 "
	.byt "  This is a test by             "
	.byt "  anton@maurovic.com            "
	.byt "  - http://anton.maurovic.com", 0

; =====	Main code ==============================================================

.segment "CODE"


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


; MAIN PROGRAM START: The 'reset' address.
.proc reset

	; Disable interrupts:
	sei

	; Basic init:
	ldx #0
	stx PPU_CTRL		; General init state; NMIs (bit 7) disabled.
	stx PPU_MASK		; Disable rendering, i.e. turn off background & sprites.
	stx APU_DMC_CTRL	; Disable DMC IRQ.

	; Set stack pointer:
	ldx $FF
	txs					; Stack pointer = $FF

	; Clear lingering interrupts since before reset:
	bit PPU_STATUS		; Ack VBLANK NMI (if one was left over after reset); bit 7.
	bit APU_CHAN_CTRL	; Ack DMC IRQ; bit 7

	; Init APU:
	lda #$40
	sta APU_FRAME		; Disable APU Frame IRQ
	lda #$0F
	sta APU_CHAN_CTRL	; Disable DMC, enable/init other channels.

	; PPU warm-up: Wait 1 full frame for the PPU to become stable, by watching VBLANK.
	; NOTE: There are 2 different ways to wait for VBLANK. This is one, recommended
	; during early startup init. The other is by the NMI being triggered.
	; For more information, see: http://wiki.nesdev.com/w/index.php/NMI#Caveats
:	bit PPU_STATUS		; P.V (overflow) <- bit 6 (S0 hit); P.N (negative) <- bit 7 (VBLANK).
	bpl	:-				; Keep checking until bit 7 (VBLANK) is asserted.
	; First PPU frame has reached VBLANK.

	; Clear zeropage:
	ldx #0
	txa
:	sta $00,x
	inx
	bne :-

	; Disable 'decimal' mode.
	cld

	; Move all sprites below line 240, so they're hidden.
	; Here, we PREPARE this by loading $0200-$02FF with data that we will transfer,
	; via DMA, to the NES OAM (Object Attribute Memory) in the PPU. The DMA will take
	; place after we know the PPU is ready (i.e. after 2nd VBLANK).
	; NOTE: OAM RAM contains 64 sprite definitions, each described by 4 bytes:
	;	byte 0: Y position of the top of the sprite.
	;	byte 1: Tile number.
	;	byte 2: Attributes (inc. palette, priority, and flip).
	;	byte 3: X position of the left of the sprite.
	ldx #0
	lda #$FF
:	sta OAM_RAM,x	; Each 4th byte in OAM (e.g. $00, $04, $08, etc.) is the Y position.
	Repeat 4, inx
	bne :-
	; NOTE our DMA isn't triggered until a bit later on.

	; Wait for second VBLANK:
:	bit PPU_STATUS
	bpl :-
	; VLBANK asserted: PPU is now fully stabilised.

	; --- We're still in VBLANK for a short while, so do video prep now ---

	; Load the main palette.
	; $3F00-$3F1F in the PPU address space is where palette data is kept,
	; organised as 2 sets (background & sprite sets) of 4 palettes, each
	; being 4 bytes long (but only the upper 3 bytes of each being used).
	; That is 2(sets) x 4(palettes) x 3(colours). $3F00 itself is the
	; "backdrop" colour, or the universal background colour.
	ppu_addr $3F00	; Tell the PPU we want to access address $3F00 in its address space.
	ldx #0
:	lda palette_data,x
	sta PPU_DATA
	inx
	cpx #32		; P.C gets set if X>=M (i.e. X>=32).
	bcc :-		; Loop if P.C is clear.
	; NOTE: Trying to load the palette outside of VBLANK may lead to the colours being
	; rendered as pixels on the screen. See:
	; http://wiki.nesdev.com/w/index.php/Palette#The_background_palette_hack

	; Clear the first nametable.
	; Each nametable is 1024 bytes of memory, arranged as 32 columns by 30 rows of
	; tile references, for a total of 960 ($3C0) bytes. The remaining 64 bytes are
	; for the attribute table of that nametable.
	; Nametable 0 starts at PPU address $2000.
	; For more information, see: http://wiki.nesdev.com/w/index.php/Nametable
	; NOTE: In order to keep this loop tight (knowing we can only count up to
	; 255 in a single loop, rather than 960), we just have one loop and do
	; multiple writes in it.
	ppu_addr $2000
	lda #0
	ldx #32*30/4	; Only need to repeat a quarter of the time, since the loop writes 4 times.
:	Repeat 4, sta PPU_DATA
	dex
	bne :-

	; Clear attribute table.
	; One palette (out of the 4 background palettes available) may be assigned
	; per 2x2 group of tiles. The actual layout of the attribute table is a bit
	; funny. See here for more info: http://wiki.nesdev.com/w/index.php/PPU_attribute_tables
	ldx #64
	lda #$55			; Select palette 1 (2nd palette) throughout.
:	sta PPU_DATA
	dex
	bne :-

	; Activate VBLANK NMIs.
	lda #VBLANK_NMI
	sta PPU_CTRL

	; Now wait until nmi_counter increments, to indicate the next VBLANK.
	wait_for_nmi
	; By this point, we're in the 3rd VBLANK.

	; Trigger DMA to copy from local OAM_RAM ($0200-$02FF) to PPU OAM RAM.
	; For more info on DMA, see: http://wiki.nesdev.com/w/index.php/PPU_OAM#DMA
	lda #0
	sta PPU_OAM_ADDR	; Specify the target starts at $00 in the PPU's OAM RAM.
	lda #>OAM_RAM		; Get upper byte (i.e. page) of source RAM for DMA operation.
	sta OAM_DMA			; Trigger the DMA.
	; DMA will halt the CPU while it copies 256 bytes from $0200-$02FF
	; into $00-$FF of the PPU's OAM RAM.

	; Set X & Y scrolling positions (0-255 and 0-239 respectively):
	lda #0
	sta PPU_SCROLL		; Write X position first.
	sta PPU_SCROLL		; Then write Y position.

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

	; Clear the first 8 lines of the nametable:
	ppu_addr $2000
	lda #0
	ldx #(32*8/4)
:	Repeat 4, sta PPU_DATA
	dex
	bne :-

	; Now fix the palettes for those 8 lines:
	lda #$23
	sta PPU_ADDR
	lda #$C0			; Select 1st metarow (rows 0-3; we'll then do 4-7).
	sta PPU_ADDR
	ldx #16				; Fill two metarows (8 bytes each)
	lda #$55			; Lower 2 rows (bits 4-7) get palette 1, upper 2 get palette 3.
:	sta PPU_DATA
	dex
	bne :-

	; Point screen offset counter back to start of line 2:
	lda #(32*2)
	sta screen_offset

	; Point back to start of source message:
	lda #0
	sta msg_ptr

	; Fix scroll position:
	lda #0
	sta PPU_SCROLL		; Write X position first.
	sta PPU_SCROLL		; Then write Y position.

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
	lda #0
	sta PPU_SCROLL		; Write X position first.
	sta PPU_SCROLL		; Then write Y position.

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
	lda #$5F			; Lower 2 rows (bits 4-7) get palette 1, upper 2 get palette 3.
:	sta PPU_DATA
	dex
	bne :-

	; Fix scroll position:
	lda #0
	sta PPU_SCROLL		; Write X position first.
	sta PPU_SCROLL		; Then write Y position.

	; Wait 1 sec:
	nmi_delay 60

	; Scroll off screen:
	ldx #0
scroll_loop:
	cpx #((6*8)<<1)		; Scroll by 56 scanlines (7 lines), using lower bit to halve the speed.
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



; =====	CHR-ROM Pattern Tables =================================================

; ----- Pattern Table 0 --------------------------------------------------------

.segment "PATTERN0"

	.incbin "anton.chr"

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
