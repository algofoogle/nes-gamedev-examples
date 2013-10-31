This is an example NES ROM, the source of which is taken from:

http://www.dreamincode.net/forums/topic/152401-nes-game-programming-part-1/

To compile to a `.nes` file (which can be run in, say,
[FCEUX](http://www.fceux.com/web/download.html)):

    cl65 -t nes hello-nes.c -o hello.nes

This tells `cl65` (the compiler & linker?) to use the `nes` target and compile
`hello-nes.c` to a NES image called `hello.nes`, which is a binary with an
[INES cartridge header](http://wiki.nesdev.com/w/index.php/INES).

