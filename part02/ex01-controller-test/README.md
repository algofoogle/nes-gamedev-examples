# ex02-asm-example

This is a simple example NES program, written by [Anton Maurovic](http://anton.maurovic.com),
in 6502 assembly language.

It writes a message to the screen with a basic "typewriter" sound effect per each
character, then changes part of the message to an orange colour, before scrolling it
off the screen and repeating the process.


## Features

Primarily this demonstrates:

1.	How to structure a 6502 assembly language program for cc65, such that it targets
	the NES architecture, and in particular the `.nes`
	([INES](http://wiki.nesdev.com/w/index.php/INES)) file format.

2.	Initialising and validating hardware in the NES, especially the PPU (Picture Processing Unit)
	for video, and the APU (Audio Processing Unit).

3.	Writing to a nametable of the PPU, i.e. creating a "background image" using the "tile" layout
	-- in this case writing characters of a message to the screen.

4.	Generating simple one-shot sound effects with the APU -- in this case a white noise
	effect with an envelope.

5.	The basics of scrolling.


## Compiling

1.	Assemble `test.s` to an object file, `test.o`, using the
	[`ca65` assembler utility](http://www.cc65.org/doc/ca65.html):

		ca65 test.s -o test.o

2.	You can then link the object file to a usable file, `test.nes`, using the
	[`ld65` linker utility](http://www.cc65.org/doc/ld65.html):

		ld65 test.o -C nesfile.ini -o test.nes

	Note that this uses `nesfile.ini` as configuration to tell the linker the binary
	layout of the target file, such that it matches the
	[INES specifications](http://wiki.nesdev.com/w/index.php/INES).

	Note also that the intermediate file `test.o` can now be deleted, if you prefer.

3.	You now have `test.nes` which can be run with an emulator... say,
	[FCEUX](http://www.fceux.com/web/download.html).


## Files

The following files make up this program:

*	`test.s` -- The main 6502 assembly language source code, specifically in cc65's `ca65` format.

*	`nesdefs.inc` -- An assembly language "include file" that defines certain constants
	(e.g. key memory locations such as NES hardware registers)
	and macros that are likely to be used by all NES programs.

*	`anton.chr` -- Raw binary data for a single
	["pattern table"](http://wiki.nesdev.com/w/index.php/PPU_pattern_tables) (4096 bytes) of 256 "tiles", that
	are used to generate pixel images on the NES. In this case, this is a character set
	that I drew and encoded in the format required for the
	[NES "Character ROM"](http://wiki.nesdev.com/w/index.php/CHR_ROM_vs._CHR_RAM). This file gets
	"included" into `test.s`, but as a raw binary blob instead of source code.

*	`nesfile.ini` -- The definition of the memory segments in this project, as they are fleshed out
	in the source code, and as they are to be laid out in the target `test.nes` file.


## Extra debugging information

Note that, if you want, you can get extra information about the compiling and linking
stages, as follows:

*	If you append `-l` to the `ca65` command-line, then upon successful assembly it
	will generate an extra `test.lst` "listing" file that shows what machine code was generated
	for each line of source code. For example:

		ca65 test.s -o test.o -l

	...will give a `test.lst` file that looks something like:

		000004r 1               ; MAIN PROGRAM START: The 'reset' address.
		000004r 1               .proc reset
		000004r 1               
		000004r 1               	; Disable interrupts:
		000004r 1  78           	sei
		000005r 1               
		000005r 1               	; Basic init:
		000005r 1  A2 00        	ldx #0
		000007r 1  8E 00 20     	stx PPU_CTRL		; General init state; NMIs (bit 7) disabled.
		00000Ar 1  8E 01 20     	stx PPU_MASK		; Disable rendering, i.e. turn off background & sprites.
		00000Dr 1  8E 10 40     	stx APU_DMC_CTRL	; Disable DMC IRQ.
		000010r 1               
		000010r 1               	; Set stack pointer:
		000010r 1  A6 FF        	ldx $FF
		000012r 1  9A           	txs					; Stack pointer = $FF
		000013r 1               
		...

*	If you append `-m XXX` to the `ld65` command-line, then it will generate a memory
	map file called `XXX` that describes the starting address and number of bytes used
	for each segment. For example:

		ld65 test.o -C nesfile.ini -o test.nes -m map.txt

	...will generate a `map.txt` file that contains, amongst other things:

		Segment list:
		-------------
		Name                  Start   End     Size
		--------------------------------------------
		INESHDR               000000  000005  000006
		PATTERN0              000000  000FFF  001000
		ZEROPAGE              000010  000012  000003
		PATTERN1              001000  001FFF  001000
		CODE                  00C000  00C194  000195
		RODATA                00C200  00C29D  00009E
		VECTORS               00FFFA  00FFFF  000006

	Note that because of the architecture of the NES, some of these
	(namely `PATTERN0` and `PATTERN1`) will appear to overlap with others, due to the
	separate address buses (and hence separate memory spaces that are coincident).
