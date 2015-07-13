NASM  = nasm
DOSVM = dosbox

unpusher.com : unpusher.s
	$(NASM) -fbin -o $@ $<

run : unpusher.com
	$(DOSVM) $<
