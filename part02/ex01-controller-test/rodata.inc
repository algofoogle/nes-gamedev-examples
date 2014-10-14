; =====	Program data (read-only) ===============================================

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
