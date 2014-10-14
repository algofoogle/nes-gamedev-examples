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


.macro basic_init
	; Disable interrupts:
	sei
	; Disable 'decimal' mode (because the NES CPU doesn't support it):
	cld
	; Basic init:
	ldx #0
	stx PPU_CTRL		; General init state; NMIs (bit 7) disabled.
	stx PPU_MASK		; Disable rendering, i.e. turn off background & sprites.
	stx APU_DMC_CTRL	; Disable DMC IRQ.

	; Set stack pointer:
	dex 				; X = $FF
	txs					; Stack pointer = $FF
.endmacro


.macro clear_wram
	; Clear WRAM, including zeropage; probably not strictly necessary
	; (and creates a false sense of security) but it DOES ensure a clean
	; state at power-on and reset.
	; WRAM ("Work RAM") is the only general-purpose RAM in the NES.
	; It is 2KiB mapped to $0000-$07FF.
	ldx #0
	txa
:	sta $0000, X 		; This line, in the loop, will clear zeropage.
	sta $0100, X
	sta $0200, X
	sta $0300, X
	sta $0400, X
	sta $0500, X
	sta $0600, X
	sta $0700, X
	inx
	bne :-
.endmacro


.macro ack_interrupts
	; Clear lingering interrupts since before reset:
	bit PPU_STATUS		; Ack VBLANK NMI (if one was left over after reset); bit 7.
	bit APU_CHAN_CTRL	; Ack DMC IRQ; bit 7
.endmacro


.macro init_apu
	; Init APU:
	lda #$40
	sta APU_FRAME		; Disable APU Frame IRQ
	lda #$0F
	sta APU_CHAN_CTRL	; Disable DMC, enable/init other channels.
.endmacro


.macro ppu_wakeup
	; PPU warm-up: Wait 1 full frame for the PPU to become stable, by watching VBLANK.
	; NOTE: There are 2 different ways to wait for VBLANK. This is one, recommended
	; during early startup init. The other is by the NMI being triggered.
	; For more information, see: http://wiki.nesdev.com/w/index.php/NMI#Caveats
:	bit PPU_STATUS		; P.V (overflow) <- bit 6 (S0 hit); P.N (negative) <- bit 7 (VBLANK).
	bpl	:-				; Keep checking until bit 7 (VBLANK) is asserted.
	; First PPU frame has reached VBLANK.

	; NOTE: "bit PPU_STATUS" reads the bit, but actually clears it in the process too,
	; so we can loop on checking it a second time:

	; Wait for second VBLANK:
:	bit PPU_STATUS
	bpl :-
	; VLBANK asserted: PPU is now fully stabilised.
.endmacro


.macro load_palettes pdata
	; $3F00-$3F1F in the PPU address space is where palette data is kept,
	; organised as 2 sets (background & sprite sets) of 4 palettes, each
	; being 4 bytes long (but only the upper 3 bytes of each being used).
	; That is 2(sets) x 4(palettes) x 3(colours). $3F00 itself is the
	; "backdrop" colour, or the universal background colour.
	ppu_addr $3F00	; Tell the PPU we want to access address $3F00 in its address space.
	ldx #0
:	lda pdata,x
	sta PPU_DATA
	inx
	cpx #32		; P.C gets set if X>=M (i.e. X>=32).
	bcc :-		; Loop if P.C is clear.
	; NOTE: Trying to load the palette outside of VBLANK may lead to the colours being
	; rendered as pixels on the screen. See:
	; http://wiki.nesdev.com/w/index.php/Palette#The_background_palette_hack
.endmacro


.macro clear_vram first_table, num_tables
	; Clear the nametables.
	; The physical VRAM (Video RAM) of the NES is only 2KiB, allowing for two nametables.
	; Each nametable is 1024 bytes of memory, arranged as 32 columns by 30 rows of
	; tile references, for a total of 960 ($3C0) bytes. The remaining 64 bytes are
	; for the attribute table of that nametable.
	; Nametable 0 starts at PPU address $2000, while nametable 1 starts at $2400,
	; nametable 3 at $2800, and nametable 4 at $2c00.
	; For more information, see: http://wiki.nesdev.com/w/index.php/Nametable
	; Because of mirroring, however, in this case implied by the INES header to
	; be "horizontal mirroring", $2000-$23FF is mapped to the same memory
	; as $2400-$27FF, meaning that the next UNIQUE nametable starts at $2800.
	; In order to keep things simple when we clear the video RAM, we just blank out
	; the entire $2000-$2FFF range, which means we're wasting some CPU time, but
	; it isn't noticeable to the user, and saves overcomplicating the code below.
	; NOTE: In order to keep this loop tight (knowing we can only easily count 256 iterations
	; in a single loop), we just have one loop and do multiple writes in it.
	ppu_addr $2000+($400*first_table)
	ldx #0
	txa
	; Write 0 into the PPU Nametable RAM, 16 times, per each of 256 iterations:
:	Repeat 4*num_tables, sta PPU_DATA
	inx
	bne :-
.endmacro


.macro enable_vblank_nmi
	; Activate VBLANK NMIs.
	lda #VBLANK_NMI
	sta PPU_CTRL
.endmacro


.macro fill_attribute_table tnum
	; Clear attribute table, for a given nametable:
	; One palette (out of the 4 background palettes available) may be assigned
	; per 2x2 group of tiles. The actual layout of the attribute table is a bit
	; funny. See here for more info: http://wiki.nesdev.com/w/index.php/PPU_attribute_tables
	; Attribute table for Nametable 0, first:
	ppu_addr ($23c0+($400*tnum))
	ldx #64
:	sta PPU_DATA
	dex
	bne :-
.endmacro


.macro trigger_ppu_dma
	; Trigger DMA to copy from local OAM_RAM ($0200-$02FF) to PPU OAM RAM.
	; For more info on DMA, see: http://wiki.nesdev.com/w/index.php/PPU_OAM#DMA
	lda #0
	sta PPU_OAM_ADDR	; Specify the target starts at $00 in the PPU's OAM RAM.
	lda #>OAM_RAM		; Get upper byte (i.e. page) of source RAM for DMA operation.
	sta OAM_DMA			; Trigger the DMA.
	; DMA will halt the CPU while it copies 256 bytes from $0200-$02FF
	; into $00-$FF of the PPU's OAM RAM.
.endmacro


.macro init_sprites
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
.endmacro
