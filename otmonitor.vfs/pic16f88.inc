datasize 256
codesize 4096
confsize 9
cfgbase 0x2000
eebase 0x2100
erasesize 32
groupsize 4
blockwrite true
magic {0x3fff 0x158a 0x3e00 0x2600}
recover {
    addr {
        set movlp [expr {$addr & 0x800 ? 0x158a : 0x118a}]
        set call [expr {0x2000 | $addr & 0x7ff}]
        return [list $movlp $call 0x118a 0x2820]
    }
}
