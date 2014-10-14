; =====	Zero-page RAM ==========================================================

.segment "ZEROPAGE"

nmi_counter:	.res 1	; Counts DOWN for each NMI.
msg_ptr:		.res 1	; Points to the next character to fetch from a message.
screen_offset:	.res 1	; Points to the next screen offset to write.

; =====	General RAM ============================================================

.segment "BSS"
; Put labels with .res statements here.

