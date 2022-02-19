datasize 256
codesize 8192
confsize 9
cfgbase 0x8000
eebase 0xf000
erasesize 32
groupsize 32
blockwrite false
magic {0x3fff 0x319f 0x3e00 0x2600}
recover {
    addr {
        set movlp [expr {0x3180 | $addr >> 8}]
	set call [expr {0x2000 | $addr & 0x7ff}]
        return [list $movlp $call 0x3180 0x2820]
    }
}
