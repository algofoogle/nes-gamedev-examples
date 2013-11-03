# ex01-c-example

This is the source code for an example NES ROM, written in C, that demonstrates
a simple program that can be compiled using cc65.

The *original* source was taken from:

*	[NES Game Programming Part 1](http://www.dreamincode.net/forums/topic/152401-nes-game-programming-part-1/),
	by [WolfCoder](http://www.dreamincode.net/forums/user/4811-wolfcoder/).

To compile this example to a `.nes` file (which can be run in, say,
[FCEUX](http://www.fceux.com/web/download.html)):

    cl65 -t nes hello-nes.c -o hello.nes

This tells the [`cl65` compile-and-link utility](http://www.cc65.org/doc/cl65-2.html)
to use the `nes` target and compile `hello-nes.c` to a NES image called `hello.nes`,
which is a binary with an [INES cartridge header](http://wiki.nesdev.com/w/index.php/INES).

