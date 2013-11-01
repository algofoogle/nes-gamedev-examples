/*
	Hello, NES!
	Writes a message to the screen and plays a tone.

	Originally written by WolfCoder (2010). See:
	http://www.dreamincode.net/forums/topic/152401-nes-game-programming-part-1/

	Modified slightly by Anton Maurovic (2013) for:
	http://anton.maurovic.com/posts/nintendo-nes-gamedev-part-1-setting-up/

	Build with cc65 as follows:
		cl65 -t nes hello-nes.c -o hello.nes

	This example will use a default CHR ROM that comes with the cc65
	target files for NES.
*/

/* Includes */
#include <nes.h>

#define PPU_CTRL2		0x2001
#define PPU_VRAM_ADDR1	0x2005	/* Used for X/Y scroll */
#define PPU_VRAM_ADDR2	0x2006	/* Nametable 'cursor' */
#define PPU_VRAM_IO		0x2007

/* Write a byte to a given address: */
#define poke(addr, data)		(*((unsigned char*)addr) = data)

/* Write a pair of bytes to the PPU VRAM Address 2: */
#define ppu_2(a, b)				{ poke(PPU_VRAM_ADDR2, a); poke(PPU_VRAM_ADDR2, b); }

/* Set the nametable x/y position. The top-left corner is 0x2000, and each row
 * is 32 bytes wide. Hence:
 *	(0,0)   => 0x2000;
 *	(1,2)   => 0x2000 + 2*32 + 1 => 0x2041;
 *	(20,16) => 0x2000 + 16*32 + 20 => 0x2214;
 */
#define ppu_set_pos(x, y)		ppu_2(0x20+((y)>>3), ((y)<<5)+(x))

/* Set foreground colour: */
#define ppu_set_color_text(c)	{ ppu_2(0x3F, 0x03); ppu_io(c); }

/* Set background colour: */
#define ppu_set_color_back(c)	{ ppu_2(0x3F, 0x00); ppu_io(c); }

/* Write to the PPU IO port, e.g. to write a byte at the nametable 'cursor' position: */
#define ppu_io(c)				poke(PPU_VRAM_IO, (c))

/* Writes the string to the screen */
/* Note how the NES hardware itself automatically moves the position we write to the screen */
void write_string(char *str)
{
	/* Position the cursor at what APPEARS to be (1,1). */
	/* We only need to do this once. */
	/* We start 2 rows down since the first 8 pixels from the top of the screen is hidden */
	ppu_set_pos(1, 2);

	/* Write the string */
	while(*str)
	{
		/* Write a letter */
		/* Note that the compiler's lib/nes.lib defines a CHR ROM that
		has graphics matching ASCII characters. */
		ppu_io(*str);
		/* Advance pointer that reads from the string */
		str++;
	}
}

/* Program entry */
int main()
{
	/* We have to wait for VBLANK or we can't even use the PPU */
	waitvblank(); /* This is found in nes.h */

	/* First, we need to set the background color */
	ppu_set_color_back(0x11);
	/* Then, we need to set the text color */
	ppu_set_color_text(0x10);

	/* We must write our message to the screen */
	write_string("Anton says: Hello, World!");

	/* Set the screen position */
	/* First value written sets the X offset and the second is the Y offset */
	*((unsigned char*)0x2005) = 0x00;
	*((unsigned char*)0x2005) = 0x00;

	/* Enable the screen */
	/* By default, the screen and sprites were off */
	*((unsigned char*)0x2001) = 8;

	/* Start making a noise: */
	poke(0x4015, 1);
	poke(0x4002, 8);
	poke(0x4003, 2);
	poke(0x4000, 0xBF);

	/* Wait */
	/* The compiler seems to loop the main function over and over, so we need to hold it here */
	while(1);
	
	return 0;
}

